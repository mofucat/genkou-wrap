"""genkou.py のテスト。

実行:
    pip install pytest
    pytest

WRAP_CASES は genkou-wrap-test.el (ERT) の genkou-test--wrap-cases と同じ内容。
Python 版と Elisp 版で禁則処理の結果が食い違わないように、両方に同じケースを通している。
片方を直したら、もう片方とテストの両方を揃えること。
"""
import re

import pytest

import genkou

FW = genkou.FULL_WIDTH_SPACE


def wrapped(text, cols=20):
    """text_to_rows の結果を、各行の末尾の空白パディングを除いた文字列のリストにする。"""
    return ["".join(row).rstrip(FW) for row in genkou.text_to_rows(text, cols)]


# (名前, 入力, 期待する行のリスト)
WRAP_CASES = [
    ("ちょうど20字", "あ" * 20, ["あ" * 20]),
    ("21字は2行になる", "あ" * 21, ["あ" * 20, "あ"]),
    # 行頭禁則: 禁則文字は前の行の最後のマスにぶら下げる
    ("句点が行頭に来るなら前の行へ", "あ" * 20 + "。い", ["あ" * 20 + "。", "い"]),
    ("。」は2つとも前の行へ", "あ" * 20 + "。」い", ["あ" * 20 + "。」", "い"]),
    ("。』」は3つとも前の行へ", "あ" * 20 + "。』」い", ["あ" * 20 + "。』」", "い"]),
    # 既知の限界: ぶら下げは3文字まで。4文字目以降は次の行の先頭に来る
    ("ぶら下げは3文字まで", "あ" * 20 + "。」」」い", ["あ" * 20 + "。」」", "」い"]),
    # 行末禁則: 開き括弧は行末に置かず、次の行へ送る
    ("開き括弧は行末に来ない", "あ" * 19 + "「い", ["あ" * 19, "「い"]),
    # 三点リーダー・ダッシュは行をまたいで分かれてよい（意図した仕様）
    ("……は行をまたいでよい", "あ" * 19 + "……い", ["あ" * 19 + "…", "…い"]),
    ("――は行をまたいでよい", "あ" * 19 + "――い", ["あ" * 19 + "―", "―い"]),
    # 段落
    ("空行は1行の空白行になる", "あ\n\nい", ["あ", "", "い"]),
]


@pytest.mark.parametrize("name,text,expected", WRAP_CASES, ids=[c[0] for c in WRAP_CASES])
def test_wrap_cases(name, text, expected):
    assert wrapped(text) == expected


def test_crlf_is_treated_as_paragraph_break():
    assert wrapped("あ\r\nい") == ["あ", "い"]


def test_every_row_has_exactly_cols_cells():
    for text in ("あ" * 45, "あ" * 20 + "。」い", "あ" * 19 + "「い", "あ\n\nい"):
        for row in genkou.text_to_rows(text):
            assert len(row) == genkou.COLS


def test_hung_characters_share_the_last_cell():
    rows = genkou.text_to_rows("あ" * 19 + "い。」う")
    assert rows[0][-1] == "い。」"
    assert rows[1][0] == "う"


def test_closing_bracket_never_starts_a_row_when_it_can_hang():
    # 「。」」が次の行の先頭に来てはいけない（今回の修正の中心）
    for row in genkou.text_to_rows("あ" * 20 + "。」い"):
        assert row[0] != "」"


def test_max_hang_matches_elisp_side():
    # genkou-wrap.el の genkou--max-hang と同じ値であること
    assert genkou.MAX_HANG == 3


# --- ページ分割 ---

@pytest.mark.parametrize("n_chars,n_pages", [(1, 1), (400, 1), (401, 2), (800, 2), (801, 3)])
def test_pagination(n_chars, n_pages):
    pages = genkou.paginate_rows(genkou.text_to_rows("あ" * n_chars))
    assert len(pages) == n_pages
    assert all(len(page) == genkou.ROWS for page in pages)


# --- PDF出力（スモークテスト） ---

def count_pdf_pages(data: bytes) -> int:
    return len(re.findall(rb"/Type\s*/Page(?![s\w])", data))


def test_generate_pdf_writes_a_valid_pdf(tmp_path):
    out = tmp_path / "out.pdf"
    genkou.generate_pdf("テスト原稿です。", str(out))
    data = out.read_bytes()
    assert data.startswith(b"%PDF")
    assert count_pdf_pages(data) == 1


def test_generate_pdf_page_count_follows_text_length(tmp_path):
    out = tmp_path / "out.pdf"
    genkou.generate_pdf("あ" * 401, str(out))
    assert count_pdf_pages(out.read_bytes()) == 2


def test_generate_pdf_handles_hung_characters(tmp_path):
    # 複数のぶら下げ文字を含んでも、描画で例外にならない
    out = tmp_path / "out.pdf"
    genkou.generate_pdf("あ" * 19 + "い。』」う", str(out))
    assert out.read_bytes().startswith(b"%PDF")
