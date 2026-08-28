;;; genkou-wrap.el --- 原稿用紙PDF作成ユーティリティ -*- lexical-binding: t; -*-

;; Author: (your name)
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1"))
;; Keywords: japanese, wp, tools

;;; Commentary:
;;
;; genkou.py（20×20 原稿用紙PDFジェネレータ）用の Emacs 連携パッケージ。
;;
;; - 20字ごとに禁則処理つきで改行するコマンド（任意。見た目上の整形用）
;; - genkou-wrap-mode 内で
;;     C-c C-c : バッファの内容から原稿用紙PDFを生成
;;     C-c C-v : 生成したPDFを Skim.app（macOS）でプレビュー
;;     C-c C-f : バッファ全体を20字ごとに改行（禁則処理つき）
;;     C-c C-r : C-c C-f による改行を取り除いて元に戻す
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
;;                :files ("genkou-wrap.el" "genkou.py" "ipag.ttf"
;;                        "requirements.txt" "IPA_Font_License.txt"))
;;     :commands (genkou-wrap-mode genkou-wrap-buffer genkou-wrap-region)
;;     :custom (genkou-cols . 20))
;;
;; 使い方:
;;   M-x genkou-wrap-mode  でマイナーモードを有効化した上で
;;   C-c C-c  … PDF生成
;;   C-c C-v  … Skimでプレビュー
;;   C-c C-f  … 20字ごとに改行
;;   C-c C-r  … 改行を元に戻す

;;; Code:

(require 'cl-lib)

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

(defcustom genkou-wrap-pdf-viewer "Skim"
  "PDFプレビューに使う macOS アプリケーション名（`open -a` に渡す）。"
  :type 'string
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

(defun genkou--wrap-paragraph (str cols)
  "STR（改行を含まない1段落分の文字列）を、禁則処理を適用しながら
COLS 文字幅の行のリストに分割して返す。"
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
        (let ((row-end idx))
          (when (and (< idx n)
                     (memq (aref str idx) genkou--line-start-forbidden))
            (setq row-end (1+ idx))
            (setq idx (1+ idx)))
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
  "このバッファから直近に生成したPDFのパス。")

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
      (unless (zerop (call-process "python3" nil buf t
                                    "-m" "venv" genkou-wrap-venv-directory))
        (pop-to-buffer buf)
        (error "genkou-wrap: 仮想環境の作成に失敗しました"))
      (unless (zerop (call-process (genkou-wrap--venv-python) nil buf t
                                    "-m" "pip" "install" "-r" requirements))
        (pop-to-buffer buf)
        (error "genkou-wrap: 依存パッケージのインストールに失敗しました")))
    (message "genkou-wrap: セットアップが完了しました。")))

(defun genkou-wrap--pdf-path ()
  "生成するPDFの出力先パスを決める。
バッファがファイルを訪問していれば同名の .pdf、そうでなければ一時ファイル。"
  (if buffer-file-name
      (concat (file-name-sans-extension buffer-file-name) ".pdf")
    (expand-file-name "genkou-draft.pdf" temporary-file-directory)))

;;;###autoload
(defun genkou-wrap-compile ()
  "現在のバッファの内容から原稿用紙PDFを生成する。
テキストの整形（20字ごとの改行・禁則処理）は genkou.py 側がまとめて行うため、
事前に genkou-wrap-buffer で改行しておく必要はない。"
  (interactive)
  (genkou-wrap--ensure-venv)
  (let* ((script (expand-file-name "genkou.py" (genkou-wrap--script-directory)))
         (pdf (genkou-wrap--pdf-path))
         (python (genkou-wrap--venv-python))
         (buf (get-buffer-create "*genkou-wrap*")))
    (unless (file-exists-p script)
      (error "genkou-wrap: genkou.py が見つかりません: %s" script))
    (with-current-buffer buf
      (erase-buffer))
    (let ((exit-code
           (call-process-region (point-min) (point-max) python
                                 nil buf nil
                                 script "-o" pdf)))
      (if (zerop exit-code)
          (progn
            (setq genkou-wrap--last-pdf pdf)
            (message "genkou-wrap: PDFを生成しました -> %s" pdf))
        (pop-to-buffer buf)
        (error "genkou-wrap: PDF生成に失敗しました（詳細は *genkou-wrap* バッファを確認）")))))

;;;###autoload
(defun genkou-wrap-preview ()
  "直近に生成したPDFを genkou-wrap-pdf-viewer（既定: Skim）で開く。
まだ生成していなければ、先に genkou-wrap-compile を実行する。"
  (interactive)
  (unless (and genkou-wrap--last-pdf (file-exists-p genkou-wrap--last-pdf))
    (genkou-wrap-compile))
  (cond
   ((eq system-type 'darwin)
    (call-process "open" nil 0 nil "-a" genkou-wrap-pdf-viewer genkou-wrap--last-pdf)
    (message "genkou-wrap: %s で開きました" genkou-wrap-pdf-viewer))
   (t
    (error "genkou-wrap-preview は現在 macOS のみ対応しています（%s で開いてください: %s）"
           genkou-wrap-pdf-viewer genkou-wrap--last-pdf))))

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
