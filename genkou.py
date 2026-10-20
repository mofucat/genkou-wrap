#!/usr/bin/env python3
"""
genkou.py — 20×20 原稿用紙ジェネレータ（PDF直接出力版）

reportlab のみで完結するため、LibreOffice などの外部アプリ不要。
標準入力からテキストを受け取り、A4縦・横書き・20×20マスの原稿用紙PDFを生成する。
書式は test.pdf（行番号・「20W × 20L = 400」のキャプション付き）に合わせている。

使い方:
    echo "テスト原稿です。" | python3 genkou.py
    cat draft.txt | python3 genkou.py -o output.pdf

セットアップ（初回のみ）:
    pip install reportlab
"""

import sys
import os
import argparse

from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.pdfgen import canvas
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont

# --- パラメータ ---
# 寸法はすべて pt（1pt = 1/72 inch）。test.pdf（A4・20×20マス）の実測値に合わせている。
COLS = 20
ROWS = 20

CELL_W = 22.0  # マスの幅
CELL_H = 22.0  # マスの高さ
GAP = 11.0     # 行と行の間の隙間

GRID_LEFT = 77.0  # 用紙左端から罫線左端まで
GRID_TOP = 96.0   # 用紙上端から罫線上端まで
FOOTER_Y = 4 * mm  # 用紙下端からページ番号までの距離

LINE_GRAY = 0.25   # 罫線・ラベルの色（グレースケール。0=黒, 1=白）
LINE_WIDTH = 0.25  # 罫線の太さ（外枠・内側とも同じ）

# 本文フォント（同ディレクトリの ipam.ttf = IPA明朝 を埋め込む）
FONT_NAME = "IPAMincho"
FONT_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "ipam.ttf")
FONT_SIZE = 12.0
SMALL_FONT_SIZE = 8.0  # 禁則処理でマスに同居させる文字（句読点など）のサイズ
TEXT_BASELINE = 16.0   # 本文のベースライン位置（マス上端から下向きに測った距離）
TEXT_X_SHIFT = 0.64    # 本文を罫線に対して右へずらす量（test.pdf の実測値）

# ラベル用フォント（行番号・「20W × 20L = 400」・ページ番号）。
# PDF標準フォントなので埋め込み不要。
LABEL_FONT = "Times-Italic"
LABEL_FONT_SIZE = 9
LABEL_ROW_INTERVAL = 5       # 何行ごとに行番号を振るか
LABEL_ROW_RIGHT_GAP = 3.0    # 行番号の右端と罫線左端の間隔
LABEL_ROW_BASELINE = 13.637  # 行番号のベースライン位置（マス上端から下向きに測った距離）
LABEL_CAPTION_BASELINE = 10.137  # キャプションのベースライン位置（罫線下端から下向きに測った距離）

FULL_WIDTH_SPACE = "　"

# --- 禁則文字（きんそくもじ） ---
# 行頭禁則：行の先頭に来てはいけない文字（句読点・閉じ括弧・小さい仮名など）
LINE_START_FORBIDDEN = set(
    "、。，．・"
    "」』）】〕〉》」』〙〗〟"
    "ヽヾゝゞ々〻ー"
    "?!？！"
    "ぁぃぅぇぉっゃゅょゎ"
    "ァィゥェォッャュョヮ"
)

# 行末禁則：行の末尾に来てはいけない文字（開き括弧など）
LINE_END_FORBIDDEN = set(
    "「『（【〔〈《「『〘〖〝"
)


def register_font():
    if not os.path.exists(FONT_FILE):
        sys.stderr.write(
            f"[error] フォントファイルが見つかりません: {FONT_FILE}\n"
            f"        genkou.py と同じフォルダに ipam.ttf を置いてください。\n"
        )
        sys.exit(1)
    pdfmetrics.registerFont(TTFont(FONT_NAME, FONT_FILE))


def _wrap_paragraph(chars, cols):
    """
    1段落分の文字列(リスト)を、禁則処理を適用しながら cols 文字幅の行に分割する。

    - 行頭禁則: 次の行の先頭になるはずの文字が禁則文字なら、前の行の最後のマスに
      同居させる（そのマスは「主文字＋小さい禁則文字」の2文字を保持する）。
    - 行末禁則: 行の最後のマスに来るはずの文字が開き括弧などの禁則文字なら、
      その行を1文字分空けて早めに区切り、その文字は次の行の先頭に送る。

    戻り値: 行のリスト。各行は cols 個のセル。各セルは 1文字の文字列、または
    （行頭禁則で同居した場合）2文字の文字列。
    """
    rows = []
    idx = 0
    n = len(chars)

    while idx < n:
        row = []
        while len(row) < cols and idx < n:
            ch = chars[idx]
            # 行末禁則チェック：このマスが行の最後のマスで、かつ禁則文字なら
            # ここで行を打ち切り、この文字は次の行の先頭に送る
            if len(row) == cols - 1 and ch in LINE_END_FORBIDDEN:
                break
            row.append(ch)
            idx += 1

        # 行頭禁則チェック：次に来る文字が禁則文字なら、今の行の最後のマスに同居させる
        if row and idx < n and chars[idx] in LINE_START_FORBIDDEN:
            row[-1] = row[-1] + chars[idx]
            idx += 1

        # 空きマスを埋める
        while len(row) < cols:
            row.append(FULL_WIDTH_SPACE)

        rows.append(row)

    return rows


def text_to_rows(text: str, cols: int = COLS):
    """
    テキストを COLS 文字幅の行のリストに変換する。
    改行(\\n)は段落区切りとして扱い、その時点で行を空白パディングして
    次の行へ送る（原稿用紙の慣習に合わせる）。禁則処理も適用する。
    """
    paragraphs = text.splitlines()  # \n, \r\n を吸収し、末尾の改行は行として残らない
    if not paragraphs:
        paragraphs = [""]

    rows = []
    for para in paragraphs:
        para_rows = _wrap_paragraph(list(para), cols)
        if not para_rows:
            # 空段落（連続改行）でも1行分の空白行を残す
            para_rows = [[FULL_WIDTH_SPACE] * cols]
        rows.extend(para_rows)

    return rows


def paginate_rows(rows, rows_per_page: int = ROWS):
    """行のリストを rows_per_page 行ごとのページに分割。最終ページは空行でパディング。"""
    if not rows:
        rows = [[FULL_WIDTH_SPACE] * COLS]

    pages = []
    for i in range(0, len(rows), rows_per_page):
        page_rows = rows[i:i + rows_per_page]
        if len(page_rows) < rows_per_page:
            page_rows = page_rows + [[FULL_WIDTH_SPACE] * COLS] * (rows_per_page - len(page_rows))
        pages.append(page_rows)
    return pages


def draw_grid(c: canvas.Canvas, page_height):
    """罫線を描く。外枠（rect）＋行ごとの上下の横線＋マス内の縦線。"""
    left = GRID_LEFT
    right = left + COLS * CELL_W
    top = page_height - GRID_TOP
    bottom = top - (ROWS * CELL_H + (ROWS - 1) * GAP)

    c.setStrokeGray(LINE_GRAY)
    c.setLineWidth(LINE_WIDTH)

    # 外枠（行間の隙間も含めて、左右の辺は上端から下端まで連続する）
    c.rect(left, bottom, right - left, top - bottom, stroke=1, fill=0)

    for row_idx in range(ROWS):
        row_top = top - row_idx * (CELL_H + GAP)
        row_bottom = row_top - CELL_H

        # 各マス行の上辺・下辺（最初の上辺と最後の下辺は外枠が兼ねる）
        if row_idx > 0:
            c.line(left, row_top, right, row_top)
        if row_idx < ROWS - 1:
            c.line(left, row_bottom, right, row_bottom)

        # マス内の縦線（左右の端は外枠が兼ねる）
        for col_idx in range(1, COLS):
            x = left + col_idx * CELL_W
            c.line(x, row_bottom, x, row_top)


def draw_characters(c: canvas.Canvas, grid, page_height):
    """マスに文字を描く。"""
    c.setFillGray(0)
    for row_idx in range(ROWS):
        row_top = page_height - GRID_TOP - row_idx * (CELL_H + GAP)
        row_bottom = row_top - CELL_H
        baseline = row_top - TEXT_BASELINE

        for col_idx in range(COLS):
            cell_content = grid[row_idx][col_idx]
            if not cell_content.strip():
                continue

            cell_left = GRID_LEFT + col_idx * CELL_W + TEXT_X_SHIFT
            cell_right = cell_left + CELL_W

            if len(cell_content) >= 2:
                # 主文字 + 禁則文字（句読点など）が同居するマス
                main_char, small_char = cell_content[0], cell_content[1]
                c.setFont(FONT_NAME, FONT_SIZE)
                c.drawCentredString(cell_left + CELL_W * 0.38, baseline, main_char)

                c.setFont(FONT_NAME, SMALL_FONT_SIZE)
                c.drawCentredString(cell_right - CELL_W * 0.20,
                                    row_bottom + CELL_H * 0.16, small_char)
            else:
                c.setFont(FONT_NAME, FONT_SIZE)
                c.drawCentredString(cell_left + CELL_W / 2, baseline, cell_content)


def draw_labels(c: canvas.Canvas, page_height):
    """行番号（5行ごと）と、罫線の右下のキャプション（例: 20W × 20L = 400）を描く。"""
    c.setFillGray(LINE_GRAY)
    c.setFont(LABEL_FONT, LABEL_FONT_SIZE)

    for row_idx in range(ROWS):
        row_no = row_idx + 1
        if row_no % LABEL_ROW_INTERVAL:
            continue
        row_top = page_height - GRID_TOP - row_idx * (CELL_H + GAP)
        c.drawRightString(GRID_LEFT - LABEL_ROW_RIGHT_GAP,
                          row_top - LABEL_ROW_BASELINE, str(row_no))

    grid_bottom = page_height - GRID_TOP - (ROWS * CELL_H + (ROWS - 1) * GAP)
    caption = f"{COLS}W \u00d7 {ROWS}L = {COLS * ROWS}"
    c.drawRightString(GRID_LEFT + COLS * CELL_W,
                      grid_bottom - LABEL_CAPTION_BASELINE, caption)


def draw_footer(c: canvas.Canvas, page_num, page_width):
    c.setFont(LABEL_FONT, LABEL_FONT_SIZE)
    c.setFillGray(LINE_GRAY)
    c.drawCentredString(page_width / 2, FOOTER_Y, str(page_num))


def generate_pdf(text: str, output_path: str):
    register_font()

    page_width, page_height = A4  # portrait, points単位(reportlabはptだがmm使用のため変換済み変数を使う)
    c = canvas.Canvas(output_path, pagesize=A4)

    rows = text_to_rows(text)
    pages = paginate_rows(rows)

    for page_idx, grid in enumerate(pages, start=1):
        draw_grid(c, page_height)
        draw_characters(c, grid, page_height)
        draw_labels(c, page_height)
        if len(pages) > 1:  # 1ページのみの場合はページ番号を付けない（test.pdf に合わせる）
            draw_footer(c, page_idx, page_width)
        c.showPage()

    c.save()
    sys.stderr.write(f"[done] {output_path} を生成しました ({len(pages)}ページ, 入力{len(text)}文字)\n")


def read_stdin() -> str:
    return sys.stdin.read()


def main():
    parser = argparse.ArgumentParser(description="20×20 原稿用紙PDFジェネレータ")
    parser.add_argument("-o", "--output", default="manuscript.pdf", help="出力PDFファイル名")
    args = parser.parse_args()

    text = read_stdin()
    generate_pdf(text, args.output)


if __name__ == "__main__":
    main()
