;;; genkou-wrap.el --- 原稿用紙PDF作成ユーティリティ -*- lexical-binding: t; -*-

;; Author: (mofu)
;; Version: 0.2.0
;; Package-Requires: ((emacs "27.1"))
;; Keywords: japanese, wp, tools

;;; Commentary:
;;
;; genkou.py（20×20 原稿用紙PDFジェネレータ）用の Emacs 連携パッケージ。
;;
;; - 20字ごとに禁則処理つきで改行するコマンド（任意。見た目上の整形用）
;; - genkou-wrap-mode 内で
;;     C-c C-c   : バッファの内容から原稿用紙PDFを生成
;;     C-u C-c C-c : PDFのファイル名・保存先を指定して生成
;;     C-c C-v   : 生成したPDFを開く（ビューアは genkou-wrap-pdf-viewer で変更可）
;;     C-c C-f   : バッファ全体を20字ごとに改行（禁則処理つき）
;;     C-c C-r   : C-c C-f による改行を取り除いて元に戻す
;; - PDFは genkou-wrap-output-directory（既定: ~/.emacs.d/genkou-wrap/）に
;;   出力する。同名のPDFが既にあるときは「上書き／別名で保存／中止」を選べる。
;; - 初回の C-c C-c 実行時に、専用の Python 仮想環境を自動作成し、
;;   reportlab をインストールする（straight のインストール処理自体には
;;   一切手を加えない。仮想環境の作成は "初回利用時" に遅延実行される）。
;;
;; leaf + straight での設定例:
;;
;;   (leaf genkou-wrap
;;     :straight (genkou-wrap
;;                :type git
;;                :host github
;;                :repo "yourname/genkou-wrap"
;;                :files ("genkou-wrap.el" "genkou.py" "*.ttf"
;;                        "requirements.txt" "IPA_Font_License.txt"))
;;     :commands (genkou-wrap-mode genkou-wrap-buffer genkou-wrap-region
;;                genkou-unwrap-buffer genkou-unwrap-region)
;;     :custom (genkou-cols . 20))
;;
;; 使い方:
;;   M-x genkou-wrap-mode  でマイナーモードを有効化した上で
;;   C-c C-c  … PDF生成（C-u を付けると保存先を指定）
;;   C-c C-v  … PDFを開く
;;   C-c C-f  … 20字ごとに改行
;;   C-c C-r  … 改行を元に戻す

;;; Code:

(require 'cl-lib)
(require 'subr-x)

(defgroup genkou-wrap nil
  "原稿用紙ドラフト整形・PDF生成ユーティリティ。"
  :group 'text)

(defcustom genkou-cols 20
  "1行の文字数。genkou.py の COLS と合わせること。"
  :type 'integer
  :group 'genkou-wrap)

(defcustom genkou-wrap-venv-directory
  (expand-file-name "genkou-wrap/venv" user-emacs-directory)
  "genkou.py 実行用の Python 仮想環境を置くディレクトリ。
straight のビルドディレクトリとは独立させ、パッケージ更新の影響を受けないようにする。"
  :type 'directory
  :group 'genkou-wrap)

(defcustom genkou-wrap-output-directory
  (expand-file-name "genkou-wrap" user-emacs-directory)
  "生成したPDFを出力するディレクトリ。
存在しなければ自動で作成する。ファイル名は、バッファがファイルを訪問していれば
そのファイル名の拡張子を .pdf にしたもの、そうでなければバッファ名になる。"
  :type 'directory
  :group 'genkou-wrap)

(defcustom genkou-wrap-python-command "python3"
  "仮想環境を作成するときに使う Python のコマンド名（またはフルパス）。"
  :type 'string
  :group 'genkou-wrap)

(defcustom genkou-wrap-pdf-viewer (if (eq system-type 'darwin) "Skim" nil)
  "`genkou-wrap-preview' (C-c C-v) でPDFを開くときに使うビューア。
- nil      : OS標準のアプリで開く（macOS: open、Windows: 関連付け、その他: xdg-open）
- 文字列   : macOS ではアプリ名（`open -a' に渡す）、それ以外では実行するコマンド名
- 関数     : PDFのパスを引数にその関数を呼ぶ（例: `find-file-other-window'）"
  :type '(choice (const :tag "OS標準のアプリ" nil)
                 (string :tag "アプリ名（macOS）／コマンド名")
                 (function :tag "関数"))
  :group 'genkou-wrap)

;; --- 禁則文字 ---

(defconst genkou--line-start-forbidden
  (append
   "、。，．・"
   "」』）】〕〉》〙〗〟"
   "ヽヾゝゞ々〻ー"
   "?!？！"
   "ぁぃぅぇぉっゃゅょゎ"
   "ァィゥェォッャュョヮ"
   nil)
  "行頭に来てはいけない文字（行頭禁則）。")

(defconst genkou--line-end-forbidden
  (append
   "「『（【〔〈《〘〖〝"
   nil)
  "行末に来てはいけない文字（行末禁則）。")

(defconst genkou--max-hang 3
  "行末のマスにぶら下げられる行頭禁則文字の最大数（例: 「。』」」の3文字）。
genkou.py の MAX_HANG と合わせること。")

(defun genkou--wrap-paragraph (str cols)
  "STR（改行を含まない1段落分の文字列）を、禁則処理を適用しながら
COLS 文字幅の行のリストに分割して返す。

行頭禁則の文字は前の行の末尾にぶら下げる。「。」」のように禁則文字が
続く場合は `genkou--max-hang' 文字までまとめてぶら下げる。
三点リーダー（……）やダッシュ（――）は、行をまたいで分かれてもよい。"
  (let ((n (length str))
        (idx 0)
        (rows '()))
    (while (< idx n)
      (let ((row-start idx))
        (cl-block fill-row
          (while (< (- idx row-start) cols)
            (when (>= idx n)
              (cl-return-from fill-row))
            (let ((ch (aref str idx)))
              (when (and (= (- idx row-start) (1- cols))
                         (memq ch genkou--line-end-forbidden))
                (cl-return-from fill-row))
              (setq idx (1+ idx)))))
        (let ((row-end idx)
              (hung 0))
          (while (and (< idx n)
                      (< hung genkou--max-hang)
                      (memq (aref str idx) genkou--line-start-forbidden))
            (setq idx (1+ idx)
                  row-end idx
                  hung (1+ hung)))
          (push (substring str row-start row-end) rows))))
    (nreverse rows)))

(defun genkou--wrap-text (text)
  "TEXT 全体を、既存の改行を段落区切りとして尊重しつつ、
各段落内を genkou--wrap-paragraph で再改行した文字列を返す。"
  (let* ((paragraphs (split-string text "\n" nil)))
    (mapconcat
     (lambda (para)
       (if (string-empty-p para)
           ""
         (mapconcat #'identity (genkou--wrap-paragraph para genkou-cols) "\n")))
     paragraphs
     "\n")))

;;;###autoload
(defun genkou-wrap-region (start end)
  "リージョン内のテキストを、禁則処理つきで genkou-cols 文字ごとに改行する。
（見た目上のプレビュー用。実際のPDF生成では必須ではない — genkou.py 側で
 未整形のテキストからも同じ結果が得られるため。）"
  (interactive "r")
  (let* ((text (buffer-substring-no-properties start end))
         (wrapped (genkou--wrap-text text)))
    (delete-region start end)
    (goto-char start)
    (insert wrapped)))

;;;###autoload
(defun genkou-wrap-buffer ()
  "バッファ全体を、禁則処理つきで genkou-cols 文字ごとに改行する。"
  (interactive)
  (genkou-wrap-region (point-min) (point-max)))

;;;###autoload
(defun genkou-unwrap-region (start end)
  "リージョン内の genkou-wrap-region による改行を取り除き、
段落区切り（空行）だけを残した状態に戻す。"
  (interactive "r")
  (let* ((text (buffer-substring-no-properties start end))
         (paragraphs (split-string text "\n\n+" nil))
         (unwrapped (mapconcat
                     (lambda (para)
                       (replace-regexp-in-string "\n" "" para))
                     paragraphs
                     "\n\n")))
    (delete-region start end)
    (goto-char start)
    (insert unwrapped)))

;;;###autoload
(defun genkou-unwrap-buffer ()
  "バッファ全体を対象に genkou-unwrap-region を実行する。"
  (interactive)
  (genkou-unwrap-region (point-min) (point-max)))

;; --- PDF生成・プレビュー ---

(defvar genkou-wrap--this-file
  (or load-file-name buffer-file-name)
  "このファイル自身のパス。genkou.py 等の同梱ファイルを探す基準に使う。")

(defun genkou-wrap--script-directory ()
  "genkou-wrap.el と同じディレクトリ（genkou.py 等が置かれている場所）を返す。"
  (file-name-directory genkou-wrap--this-file))

(defun genkou-wrap--venv-python ()
  "仮想環境内の python 実行ファイルのパスを返す。"
  (expand-file-name
   (if (eq system-type 'windows-nt) "Scripts/python.exe" "bin/python3")
   genkou-wrap-venv-directory))

(defvar-local genkou-wrap--last-pdf nil
  "このバッファから直近に生成したPDFのパス。
一度決まった出力先は、このバッファでは以後も使い続け、再生成のたびに上書きする。")

(defun genkou-wrap--ensure-venv ()
  "仮想環境が無ければ作成し、依存パッケージをインストールする。
初回のみ数秒〜十数秒かかる。straight のインストール処理そのものには関与しない
（このパッケージを使い始めた最初の C-c C-c で遅延実行される）。"
  (unless (file-executable-p (genkou-wrap--venv-python))
    (message "genkou-wrap: 初回セットアップ中（仮想環境を作成しています）...")
    (make-directory (file-name-directory
                      (directory-file-name genkou-wrap-venv-directory))
                     t)
    (let ((buf (get-buffer-create "*genkou-wrap-setup*"))
          (requirements (expand-file-name "requirements.txt"
                                           (genkou-wrap--script-directory))))
      (unless (zerop (call-process genkou-wrap-python-command nil buf t
                                    "-m" "venv" genkou-wrap-venv-directory))
        (pop-to-buffer buf)
        (error "genkou-wrap: 仮想環境の作成に失敗しました"))
      (unless (zerop (call-process (genkou-wrap--venv-python) nil buf t
                                    "-m" "pip" "install" "-r" requirements))
        (pop-to-buffer buf)
        (error "genkou-wrap: 依存パッケージのインストールに失敗しました")))
    (message "genkou-wrap: セットアップが完了しました。")))

;; --- 出力先の決定 ---

(defun genkou-wrap--default-basename ()
  "出力PDFの既定のファイル名（拡張子なし）を返す。
ファイルを訪問していればそのファイル名、そうでなければバッファ名。
ファイル名に使えない文字は `_' に置き換える。"
  (let* ((raw (if buffer-file-name
                  (file-name-base buffer-file-name)
                (buffer-name)))
         (clean (string-trim
                 (replace-regexp-in-string "[/\\\\:*?\"<>|]" "_" raw)
                 "[_ ]+" "[_ ]+")))
    (if (string-empty-p clean) "genkou-draft" clean)))

(defun genkou-wrap--default-pdf-path ()
  "既定の出力先（`genkou-wrap-output-directory' の下）のフルパスを返す。"
  (expand-file-name (concat (genkou-wrap--default-basename) ".pdf")
                    (file-name-as-directory
                     (expand-file-name genkou-wrap-output-directory))))

(defun genkou-wrap--unique-path (path)
  "PATH が既に存在するとき、末尾に -1, -2, ... を付けた未使用のパスを返す。
存在しなければ PATH をそのまま返す。"
  (if (not (file-exists-p path))
      path
    (let ((base (file-name-sans-extension path))
          (ext (or (file-name-extension path t) ""))
          (n 1))
      (while (file-exists-p (format "%s-%d%s" base n ext))
        (setq n (1+ n)))
      (format "%s-%d%s" base n ext))))

(defun genkou-wrap--read-pdf-path (initial)
  "PDFの保存先をミニバッファで尋ねて、フルパスを返す。
INITIAL は初期値（フルパス）。既にあるファイルを指定したときは上書きの確認を、
存在しないフォルダを指定したときは作成の確認を求める。"
  (let (result)
    (while (not result)
      (let* ((input (expand-file-name
                     (read-file-name "PDFの保存先: "
                                     (file-name-directory initial) nil nil
                                     (file-name-nondirectory initial))))
             (input (if (directory-name-p input)
                        (expand-file-name (file-name-nondirectory initial) input)
                      input))
             (input (if (file-name-extension input) input (concat input ".pdf")))
             (dir (file-name-directory input)))
        (cond
         ((not (file-directory-p dir))
          (when (y-or-n-p (format "%s がありません。作成しますか? "
                                  (abbreviate-file-name dir)))
            (setq result input)))
         ((not (file-exists-p input))
          (setq result input))
         ((y-or-n-p (format "%s は既にあります。上書きしますか? "
                            (abbreviate-file-name input)))
          (setq result input)))))
    result))

(defun genkou-wrap--resolve-pdf-path (force-ask)
  "このバッファのPDFの出力先を決めて返す。
- FORCE-ASK が nil で、このバッファで出力先が決まっていれば、それを使う（上書き）。
- 決まっていなければ既定の出力先を使う。同名のPDFが既にあるときは、
  「上書き／別名で保存／中止」を選ばせる。
- FORCE-ASK が非 nil なら、常にファイル名を尋ねる。"
  (let ((default (genkou-wrap--default-pdf-path)))
    (cond
     (force-ask
      (genkou-wrap--read-pdf-path
       (genkou-wrap--unique-path (or genkou-wrap--last-pdf default))))
     (genkou-wrap--last-pdf
      genkou-wrap--last-pdf)
     ((not (file-exists-p default))
      default)
     (t
      (pcase (car (read-multiple-choice
                   (format "%s は既にあります: "
                           (abbreviate-file-name default))
                   '((?o "上書き")
                     (?r "別名で保存")
                     (?q "中止"))))
        (?o default)
        (?r (genkou-wrap--read-pdf-path (genkou-wrap--unique-path default)))
        (_ (user-error "genkou-wrap: 中止しました")))))))

;;;###autoload
(defun genkou-wrap-compile (&optional ask-name)
  "現在のバッファの内容から原稿用紙PDFを生成する。
テキストの整形（20字ごとの改行・禁則処理）は genkou.py 側がまとめて行うため、
事前に genkou-wrap-buffer で改行しておく必要はない。

PDFは `genkou-wrap-output-directory' に出力する。同名のPDFが既にあるときは
上書きするか別名で保存するかを尋ねる。一度決まった出力先は、このバッファでは
以後も使い続ける（再生成は上書き）。
前置引数（\\[universal-argument]）を付けると、ファイル名・保存先を指定できる。"
  (interactive "P")
  (let* ((script (expand-file-name "genkou.py" (genkou-wrap--script-directory)))
         (pdf (genkou-wrap--resolve-pdf-path ask-name))
         (buf (get-buffer-create "*genkou-wrap*")))
    (unless (file-exists-p script)
      (error "genkou-wrap: genkou.py が見つかりません: %s" script))
    (genkou-wrap--ensure-venv)
    (make-directory (file-name-directory pdf) t)
    (with-current-buffer buf
      (erase-buffer))
    (let ((exit-code
           (call-process-region (point-min) (point-max)
                                 (genkou-wrap--venv-python)
                                 nil buf nil
                                 script "-o" pdf)))
      (if (zerop exit-code)
          (progn
            (setq genkou-wrap--last-pdf pdf)
            (message "genkou-wrap: PDFを生成しました -> %s" pdf))
        (pop-to-buffer buf)
        (error "genkou-wrap: PDF生成に失敗しました（詳細は *genkou-wrap* バッファを確認）")))))

(declare-function w32-shell-execute "w32fns")

(defun genkou-wrap--open-pdf (pdf)
  "PDF を `genkou-wrap-pdf-viewer' の設定に従って開く。"
  (let ((viewer genkou-wrap-pdf-viewer))
    (cond
     ((functionp viewer)
      (funcall viewer pdf))
     ((stringp viewer)
      (if (eq system-type 'darwin)
          (call-process "open" nil 0 nil "-a" viewer pdf)
        (call-process viewer nil 0 nil pdf)))
     ((eq system-type 'darwin)
      (call-process "open" nil 0 nil pdf))
     ((eq system-type 'windows-nt)
      (w32-shell-execute "open" pdf))
     (t
      (call-process "xdg-open" nil 0 nil pdf)))
    (message "genkou-wrap: 開きました -> %s" pdf)))

;;;###autoload
(defun genkou-wrap-preview ()
  "直近に生成したPDFを `genkou-wrap-pdf-viewer' で開く。
まだ生成していなければ、先に genkou-wrap-compile を実行する。"
  (interactive)
  (unless (and genkou-wrap--last-pdf (file-exists-p genkou-wrap--last-pdf))
    (genkou-wrap-compile))
  (genkou-wrap--open-pdf genkou-wrap--last-pdf))

;;;###autoload
(defvar genkou-wrap-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-c") #'genkou-wrap-compile)
    (define-key map (kbd "C-c C-v") #'genkou-wrap-preview)
    (define-key map (kbd "C-c C-f") #'genkou-wrap-buffer)
    (define-key map (kbd "C-c C-r") #'genkou-unwrap-buffer)
    map)
  "genkou-wrap-mode 用のキーマップ。")

;;;###autoload
(define-minor-mode genkou-wrap-mode
  "原稿用紙PDF作成用のマイナーモード。

\\{genkou-wrap-mode-map}"
  :lighter " 原稿"
  :keymap genkou-wrap-mode-map)

(provide 'genkou-wrap)
;;; genkou-wrap.el ends here
