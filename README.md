# genkou-wrap — 20×20 原稿用紙PDFジェネレータ + Emacs連携

標準入力から受け取ったテキストを、A4縦・横書き・20×20マスの原稿用紙PDFに変換します。
Emacsから `C-c C-c` でPDF生成、`C-c C-v` でSkim.appプレビューまで行える連携パッケージ(`genkou-wrap.el`)も同梱しています。

- **reportlab のみで完結**：LibreOffice など外部アプリのインストール不要
- **400字を超える原稿は自動で複数ページに分割**
- **改行を段落区切りとして認識**（行末まで空白で埋めて次の行へ）
- **日本語の禁則処理に対応**（句読点や閉じ括弧が行頭に来ない、開き括弧が行末に来ない）
- **フォント埋め込み済み**（IPA明朝同梱。環境を選ばず文字化けしません）
- **Emacs (straight.el + leaf) 連携**：`C-c C-c` でPDF生成、`C-c C-v` でSkimプレビュー、`C-c C-f` / `C-c C-r` でバッファ上の20字折り返しのオン・オフ

## 同梱ファイル

| ファイル | 内容 |
|---|---|
| `genkou-wrap.el` | Emacs連携パッケージ本体 |
| `genkou.py` | PDF生成スクリプト本体 |
| `ipam.ttf` | 埋め込み用フォント（IPA明朝） |
| `IPA_Font_License.txt` | フォントのライセンス条項 |
| `requirements.txt` | 必要なPythonパッケージ一覧 |
| `README.md` | このファイル |

## Emacsでの使い方（straight.el + leaf）

### インストール

このリポジトリをGitHubにpushした上で：

```elisp
(leaf genkou-wrap
  :straight (genkou-wrap
             :type git
             :host github
             :repo "yourname/genkou-wrap"
             :files ("genkou-wrap.el" "genkou.py" "ipam.ttf"
                     "requirements.txt" "IPA_Font_License.txt"))
  :commands (genkou-wrap-mode genkou-wrap-buffer genkou-wrap-region
             genkou-unwrap-buffer genkou-unwrap-region)
  :custom (genkou-cols . 20))
```

プライベートリポジトリの場合、SSH鍵でのGitHub認証があらかじめ必要です。

### 使う

原稿を書いているバッファで：

```
M-x genkou-wrap-mode
```

- **`C-c C-c`** — バッファの内容から原稿用紙PDFを生成します。バッファがファイルを訪問していれば、同じ場所に同名の `.pdf` として保存されます。
- **`C-c C-v`** — 直近に生成したPDFを Skim.app（macOS）で開きます。まだ生成していなければ自動で先に `C-c C-c` 相当の処理を行います。
- **`C-c C-f`** — バッファ全体を20字ごとに改行します（禁則処理つき）。原稿用紙のマス割りを editor 上でも確認したいときに使います。段落区切り（空行）はそのまま保持されます。
- **`C-c C-r`** — `C-c C-f` で挿入された改行を取り除き、元の段落だけの状態に戻します。空行による段落区切りは残ります。

**改行を気にせず自由に書いて構いません。** 禁則処理・20字ごとの折り返し・ページ分割はすべて `genkou.py` 側が担当します。

（`C-c C-f`（`M-x genkou-wrap-buffer`）で見た目上だけ20字ごとに禁則処理つきで改行することも可能ですが、PDF生成には必須ではありません。`C-c C-r`（`M-x genkou-unwrap-buffer`）で元に戻せます。）

### 初回セットアップについて

`C-c C-c` を初めて実行したとき、専用のPython仮想環境を自動的に作成し、`reportlab` をインストールします（数秒〜十数秒）。この仮想環境は `~/.emacs.d/genkou-wrap/venv` に作られ、`straight` のパッケージ更新(`straight-pull-package` 等)の影響を受けない独立した場所に置かれます。2回目以降は再作成されません。

セットアップの様子は `*genkou-wrap-setup*` バッファで確認できます。失敗した場合もこのバッファにエラー内容が出力されます。

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
- 罫線: 25%グレー、太さ0.25pt（外枠・内側とも同じ）
- 行間: 各行の間に11ptの隙間
- 本文: IPA明朝 12pt
- 行番号: 5行ごと（5・10・15・20）に罫線の左側へ表示
- キャプション: 罫線の右下に「20W × 20L = 400」を表示
- フッター: 2ページ以上のとき中央にページ番号（1ページのみのときは表示しない）
- 禁則処理:
  - 行頭禁則（句読点・閉じ括弧・小さい仮名などは行頭に来ない → 前の行の最後のマスに小さく同居）
  - 行末禁則（開き括弧は行末に来ない → 早めに行を区切り次の行へ送る）

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

`genkou.py` 冒頭のパラメータ（マス目サイズ・余白・色・フォントなど）、または `genkou-wrap.el` の `defcustom`（`genkou-cols`、`genkou-wrap-venv-directory`、`genkou-wrap-pdf-viewer` など）を編集してください。

