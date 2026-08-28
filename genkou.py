#!/usr/bin/env python3
"""
genkou.py — 20×20 原稿用紙ジェネレータ（PDF直接出力版）

reportlab のみで完結するため、LibreOffice などの外部アプリ不要。
標準入力からテキストを受け取り、A4縦・横書き・20×20マスの原稿用紙PDFを生成する。

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
COLS = 20
ROWS = 20

CELL_W = 9.3 * mm
CELL_H = 9.75 * mm
GAP = 3.4 * mm

MARGIN_TOP = 15 * mm
MARGIN_LEFT = 12 * mm
MARGIN_RIGHT = 12 * mm
MARGIN_BOTTOM = 8 * mm
FOOTER_Y = 4 * mm  # 用紙下端からページ番号までの距離

OUTER_COLOR = (0xA6 / 255, 0xA6 / 255, 0xA6 / 255)
INNER_COLOR = (0xD9 / 255, 0xD9 / 255, 0xD9 / 255)
OUTER_WIDTH = 0.6
INNER_WIDTH = 0.25

FONT_NAME = "IPAGothic"  # 埋め込みフォント（同ディレクトリの ipag.ttf を使用）
FONT_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "ipag.ttf")
FONT_SIZE = 12.5
SMALL_FONT_SIZE = 8.5  # 禁則処理でマスに同居させる文字（句読点など）のサイズ

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
            f"        genkou.py と同じフォルダに ipag.ttf を置いてください。\n"
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


def draw_manuscript(c: canvas.Canvas, grid, page_width, page_height):
    grid_left = MARGIN_LEFT
    grid_top = page_height - MARGIN_TOP  # PDF座標系は左下原点なので上端をここで計算

    for row_idx in range(ROWS):
        row_top = grid_top - row_idx * (CELL_H + GAP)
        row_bottom = row_top - CELL_H

        is_first_row = row_idx == 0
        is_last_row = row_idx == ROWS - 1

        # --- そのマス行の罫線 ---
        for col_idx in range(COLS):
            cell_left = grid_left + col_idx * CELL_W
            cell_right = cell_left + CELL_W
            is_first_col = col_idx == 0
            is_last_col = col_idx == COLS - 1

            # 上辺
            c.setStrokeColorRGB(*(OUTER_COLOR if is_first_row else INNER_COLOR))
            c.setLineWidth(OUTER_WIDTH if is_first_row else INNER_WIDTH)
            c.line(cell_left, row_top, cell_right, row_top)

            # 下辺
            c.setStrokeColorRGB(*(OUTER_COLOR if is_last_row else INNER_COLOR))
            c.setLineWidth(OUTER_WIDTH if is_last_row else INNER_WIDTH)
            c.line(cell_left, row_bottom, cell_right, row_bottom)

            # 左辺
            c.setStrokeColorRGB(*(OUTER_COLOR if is_first_col else INNER_COLOR))
            c.setLineWidth(OUTER_WIDTH if is_first_col else INNER_WIDTH)
            c.line(cell_left, row_bottom, cell_left, row_top)

            # 右辺
            c.setStrokeColorRGB(*(OUTER_COLOR if is_last_col else INNER_COLOR))
            c.setLineWidth(OUTER_WIDTH if is_last_col else INNER_WIDTH)
            c.line(cell_right, row_bottom, cell_right, row_top)

            # 文字（禁則処理で2文字が同居する場合がある）
            cell_content = grid[row_idx][col_idx]
            if cell_content.strip():
                c.setFillColorRGB(0, 0, 0)
                if len(cell_content) >= 2:
                    # 主文字 + 禁則文字（句読点など）が同居するマス
                    main_char, small_char = cell_content[0], cell_content[1]
                    c.setFont(FONT_NAME, FONT_SIZE)
                    mx = cell_left + CELL_W * 0.38
                    my = row_bottom + CELL_H / 2 - FONT_SIZE * 0.35
                    c.drawCentredString(mx, my, main_char)

                    c.setFont(FONT_NAME, SMALL_FONT_SIZE)
                    sx = cell_right - CELL_W * 0.20
                    sy = row_bottom + CELL_H * 0.16
                    c.drawCentredString(sx, sy, small_char)
                else:
                    c.setFont(FONT_NAME, FONT_SIZE)
                    cx = cell_left + CELL_W / 2
                    cy = row_bottom + CELL_H / 2 - FONT_SIZE * 0.35
                    c.drawCentredString(cx, cy, cell_content)

        # --- 行間の隙間部分：外枠の左右だけ継続させる ---
        if not is_last_row:
            gap_top = row_bottom
            gap_bottom = gap_top - GAP
            c.setStrokeColorRGB(*OUTER_COLOR)
            c.setLineWidth(OUTER_WIDTH)
            c.line(grid_left, gap_top, grid_left, gap_bottom)
            c.line(grid_left + COLS * CELL_W, gap_top, grid_left + COLS * CELL_W, gap_bottom)


def draw_footer(c: canvas.Canvas, page_num, page_width):
    c.setFont(FONT_NAME, 9)
    c.setFillColorRGB(0.5, 0.5, 0.5)
    c.drawCentredString(page_width / 2, FOOTER_Y, str(page_num))


def generate_pdf(text: str, output_path: str):
    register_font()

    page_width, page_height = A4  # portrait, points単位(reportlabはptだがmm使用のため変換済み変数を使う)
    c = canvas.Canvas(output_path, pagesize=A4)

    rows = text_to_rows(text)
    pages = paginate_rows(rows)

    for page_idx, grid in enumerate(pages, start=1):
        draw_manuscript(c, grid, page_width, page_height)
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
