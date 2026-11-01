# genkou-wrap — 20×20 原稿用紙PDFジェネレータ + Emacs連携

標準入力から受け取ったテキストを、A4縦・横書き・20×20マスの原稿用紙PDFに変換します。
Emacsから `C-c C-c` でPDF生成、`C-c C-v` で好みのPDFビューア（macOSの既定は Skim.app）で開くところまで行える連携パッケージ(`genkou-wrap.el`)も同梱しています。

- **reportlab のみで完結**：LibreOffice など外部アプリのインストール不要
- **400字を超える原稿は自動で複数ページに分割**
- **改行を段落区切りとして認識**（行末まで空白で埋めて次の行へ）
- **日本語の禁則処理に対応**（句読点や閉じ括弧が行頭に来ない、開き括弧が行末に来ない。`。」` のように続く場合もまとめて前の行の末尾へ）
- **フォント埋め込み済み**（IPA明朝同梱。環境を選ばず文字化けしません）
- **Emacs (straight.el + leaf) 連携**：`C-c C-c` でPDF生成（既定の出力先は `~/.emacs.d/genkou-wrap/`。同名のPDFがあれば上書き/別名保存を選択）、`C-c C-v` で好みのビューアで開く、`C-c C-f` / `C-c C-r` でバッファ上の20字折り返しのオン・オフ

## 同梱ファイル

| ファイル | 内容 |
|---|---|
| `genkou-wrap.el` | Emacs連携パッケージ本体 |
| `genkou.py` | PDF生成スクリプト本体 |
| `ipam.ttf` | 埋め込み用フォント（IPA明朝） |
| `IPA_Font_License.txt` | フォントのライセンス条項 |
| `requirements.txt` | 必要なPythonパッケージ一覧 |
| `test_genkou.py` | `genkou.py` のテスト（pytest） |
| `genkou-wrap-test.el` | `genkou-wrap.el` のテスト（ERT） |
| `LICENSE` | このプログラム本体のライセンス（MIT） |
| `README.md` | このファイル |

## Emacsでの使い方（straight.el + leaf）

### インストール

`init.el` に次の設定を追加します：

```elisp
(leaf genkou-wrap
  :straight (genkou-wrap
             :type git
             :host github
             :repo "mofucat/genkou-wrap"
             :files ("genkou-wrap.el" "genkou.py" "*.ttf"
                     "requirements.txt" "IPA_Font_License.txt"))
  :commands (genkou-wrap-mode genkou-wrap-buffer genkou-wrap-region
             genkou-unwrap-buffer genkou-unwrap-region)
  :custom (genkou-cols . 20))
```

フォントファイルはレシピの `:files` に含まれていないと straight のビルドディレクトリにリンクされず、PDF生成に失敗します。`"*.ttf"` と書いておけば、フォントを差し替えても設定を直す必要がありません。フォントを変更したときは、新しい `.ttf` を `git add` してpushした上で `M-x straight-pull-package` → `M-x straight-rebuild-package` を実行してください。

### 使う

原稿を書いているバッファで：

```
M-x genkou-wrap-mode
```

- **`C-c C-c`** — バッファの内容から原稿用紙PDFを生成します。PDFは `genkou-wrap-output-directory`（既定: `~/.emacs.d/genkou-wrap/`）に、訪問しているファイルと同名の `.pdf`（ファイルを訪問していなければバッファ名）として出力されます。出力先のフォルダは自動で作られます。
  - 同名のPDFが既にあるときは、**上書き / 別名で保存 / 中止** を選べます。「別名で保存」を選ぶと `名前-1.pdf` を初期値にファイル名を尋ねます（別のフォルダも指定できます）。
  - 同じバッファでは、一度決まった出力先を以後も使い続け、再生成のたびに上書きします（毎回は尋ねません）。
  - `C-u C-c C-c` のように前置引数を付けると、ファイル名と保存先を明示的に指定できます。
- **`C-c C-v`** — 直近に生成したPDFを開きます。まだ生成していなければ自動で先に `C-c C-c` 相当の処理を行います。開くアプリは `genkou-wrap-pdf-viewer` で変更できます（macOSの既定は Skim.app）。
- **`C-c C-f`** — バッファ全体を20字ごとに改行します（禁則処理つき）。原稿用紙のマス割りを editor 上でも確認したいときに使います。原稿に元からある改行（空行でも単独の改行でも）はそのまま保持され、`C-c C-f` が新しく入れた改行にだけ印が付きます。何度実行しても改行が二重になることはありません。折り返しは半角英数字も1文字として数えるため、半角を含む行はエディタ上で短く見えます（詳しくは「仕様」の「文字数の数え方」）。
- **`C-c C-r`** — `C-c C-f` で入れた改行（印の付いた改行）だけを取り除き、`C-c C-f` を実行する前の状態に戻します。元からあった改行は、空行でも単独の改行でもそのまま残ります。`C-c C-f` の後に書き足した文字も残ります。印はEmacsのバッファ内だけの情報なので、整形したテキストをファイルに保存して開き直すと失われ、`C-c C-r` では戻せなくなります（`C-c C-f` の直後なら、通常の undo でも戻せます）。

**改行を気にせず自由に書いて構いません。** 禁則処理・20字ごとの折り返し・ページ分割はすべて `genkou.py` 側が担当します。

（`C-c C-f`（`M-x genkou-wrap-buffer`）で見た目上だけ20字ごとに禁則処理つきで改行することも可能ですが、PDF生成には必須ではありません。`C-c C-r`（`M-x genkou-unwrap-buffer`）で整形前の状態に戻せます。）

### 初回セットアップについて

`C-c C-c` を初めて実行したとき、専用のPython仮想環境を自動的に作成し、`reportlab` をインストールします（数秒〜十数秒）。この仮想環境は `~/.emacs.d/genkou-wrap/venv` に作られ、`straight` のパッケージ更新(`straight-pull-package` 等)の影響を受けない独立した場所に置かれます。2回目以降は再作成されません。

セットアップの様子は `*genkou-wrap-setup*` バッファで確認できます。失敗した場合もこのバッファにエラー内容が出力されます。

### 設定

`M-x customize-group RET genkou-wrap` または `setq` / leaf の `:custom` で変更できます。

| 変数 | 既定値 | 内容 |
|---|---|---|
| `genkou-wrap-output-directory` | `~/.emacs.d/genkou-wrap/` | PDFの出力先 |
| `genkou-wrap-venv-directory` | `~/.emacs.d/genkou-wrap/venv` | Python仮想環境の場所 |
| `genkou-wrap-python-command` | `"python3"` | 仮想環境の作成に使うPython（pyenv や Homebrew のPythonを使うときはここを変更） |
| `genkou-wrap-pdf-viewer` | macOS: `"Skim"` / その他: `nil` | `C-c C-v` で使うビューア（下記） |
| `genkou-cols` | `20` | 1行の文字数（`genkou.py` の `COLS` と合わせる） |

`genkou-wrap-pdf-viewer` の値：

- `nil` — OS標準のアプリで開く（macOS: `open`、Windows: 関連付け、その他: `xdg-open`）
- 文字列 — macOS ではアプリ名（`open -a` に渡す）、それ以外では実行するコマンド名
- 関数 — PDFのパスを引数にその関数を呼ぶ。たとえば pdf-tools で開くなら `(setq genkou-wrap-pdf-viewer #'find-file-other-window)`

## コマンドラインでの使い方（Emacsを使わない場合）

滅多に使わないツールとして、必要なときだけ仮想環境を用意して、終わったら消す運用です。

### 1. 使う直前：仮想環境を作って有効化し、依存パッケージを入れる

```bash
cd /path/to/this/folder
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

### 2. 実行する

```bash
echo "テスト原稿です。" | python3 genkou.py
cat draft.txt | python3 genkou.py -o output.pdf
```

### 3. 使い終わったら：仮想環境を無効化して削除する

```bash
deactivate
rm -rf .venv
```

## 仕様

- 用紙: A4 縦向き（210mm × 297mm）
- 文字方向: 横書き
- マス目: 20列 × 20行（400字詰め）、1マス 22pt × 22pt（約7.8mm角）
- 文字数の数え方: 半角の英数字や記号も、全角の文字と同じく**1文字＝1マス**として数えます。PDFでも半角文字は1マスに1文字ずつ入りますが、エディタ上では半角が全角の約半分の幅で表示されるため、半角を含む行は20文字ちょうどでも短く見えます（`C-c C-f` の折り返しも同じ数え方です）。
- 罫線: 25%グレー、太さ0.25pt（外枠・内側とも同じ）
- 行間: 各行の間に11ptの隙間
- 本文: IPA明朝 12pt
- 行番号: 5行ごと（5・10・15・20）に罫線の左側へ表示
- キャプション: 罫線の右下に「20W × 20L = 400」を表示
- フッター: 2ページ以上のとき中央にページ番号（1ページのみのときは表示しない）
- 禁則処理:
  - 行頭禁則（句読点・閉じ括弧・小さい仮名などは行頭に来ない → 前の行の最後のマスに小さく同居）。`。」` のように禁則文字が続く場合は、最大3文字までまとめて同居させます。2文字目以降は罫線の外（欄外）に並びます。原稿用紙で行頭に来てしまう句読点・閉じ括弧を、前の行の末尾（欄外）に書く作法に合わせています。禁則文字が4文字以上続く場合、4文字目以降は次の行の先頭になります。
  - 行末禁則（開き括弧は行末に来ない → 早めに行を区切り次の行へ送る）
  - 三点リーダー（`……`）とダッシュ（`――`）は、行をまたいで分かれることがあります。行末にだけ空白ができるより読みやすいための仕様です。
  - 句点の有無には手を加えません。かぎ括弧の中の文末に句点を打つか（`「…です。」`）は流儀が分かれるため（文部省の句読法案は打つとし、新聞などでは省くことが多い）、入力どおりに配置します。

## テスト

```bash
pip install pytest
pytest                                                                 # genkou.py
emacs -Q --batch -L . -l genkou-wrap-test.el -f ert-run-tests-batch-and-exit   # genkou-wrap.el
```

禁則処理は Python 版（`genkou.py`）と Elisp 版（`genkou-wrap.el`）の両方にあるため、同じ入力と期待値を両方のテストに通して、実装が食い違わないようにしています。禁則処理を変えるときは、両方の実装とテストを揃えてください。

## 制作について

仕様と設計はmofuが、実装の大部分は Claude（Anthropic）の支援によるものです。

## ライセンス

このプログラム本体（`genkou.py`、`genkou-wrap.el` など）は [MIT License](LICENSE) で公開しています。同梱のフォントだけは別のライセンスです（次項）。

## フォントのライセンスについて

同梱の `ipam.ttf`（IPA明朝）は「IPAフォントライセンスv1.0」の下で配布されています。複製・改変・再頒布が許可されたオープンなフォントです。詳細は `IPA_Font_License.txt` を参照してください。

## トラブルシューティング

**`[error] フォントファイルが見つかりません` と表示される**
→ `ipam.ttf` が `genkou.py` と同じフォルダにあるか確認してください。

**`pip install` で `PermissionError: [Errno 1] Operation not permitted` が出る（macOS）**
→ Desktop・Documents・Downloads フォルダで作業していると、ターミナルアプリにmacOSのプライバシー保護がかかっている場合があります。「システム設定 → プライバシーとセキュリティ → フルディスクアクセス」で使用中のターミナルアプリを許可してから、ターミナルを再起動してください。

**Emacsで `genkou-wrap: 仮想環境の作成に失敗しました` と出る**
→ `*genkou-wrap-setup*` バッファを確認してください。`python3` コマンドが見つからない、あるいはネットワーク環境でpipがreportlabを取得できない、といった原因が考えられます。

## カスタマイズしたい場合

`genkou.py` 冒頭のパラメータ（マス目サイズ・余白・色・フォントなど）、または `genkou-wrap.el` の `defcustom`（`genkou-cols`、`genkou-wrap-output-directory`、`genkou-wrap-venv-directory`、`genkou-wrap-python-command`、`genkou-wrap-pdf-viewer`。上の「設定」を参照）を編集してください。

