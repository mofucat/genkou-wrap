;;; genkou-wrap-test.el --- Tests for genkou-wrap -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; 実行:
;;   emacs -Q --batch -L . -l genkou-wrap-test.el -f ert-run-tests-batch-and-exit
;;
;; genkou--wrap-cases は test_genkou.py (pytest) の WRAP_CASES と同じ内容。
;; Python 版と Elisp 版で禁則処理の結果が食い違わないように、両方に同じ
;; ケースを通している。片方を直したら、もう片方とテストの両方を揃えること。

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'genkou-wrap)

(defun genkou-test--a (n) "「あ」を N 個並べた文字列。" (make-string n ?あ))

(defconst genkou-test--wrap-cases
  `(("ちょうど20字"
     ,(genkou-test--a 20)
     (,(genkou-test--a 20)))
    ("21字は2行になる"
     ,(genkou-test--a 21)
     (,(genkou-test--a 20) "あ"))
    ("句点が行頭に来るなら前の行へ"
     ,(concat (genkou-test--a 20) "。い")
     (,(concat (genkou-test--a 20) "。") "い"))
    ("。」は2つとも前の行へ"
     ,(concat (genkou-test--a 20) "。」い")
     (,(concat (genkou-test--a 20) "。」") "い"))
    ("。』」は3つとも前の行へ"
     ,(concat (genkou-test--a 20) "。』」い")
     (,(concat (genkou-test--a 20) "。』」") "い"))
    ("ぶら下げは3文字まで"
     ,(concat (genkou-test--a 20) "。」」」い")
     (,(concat (genkou-test--a 20) "。」」") "」い"))
    ("開き括弧は行末に来ない"
     ,(concat (genkou-test--a 19) "「い")
     (,(genkou-test--a 19) "「い"))
    ("……は行をまたいでよい"
     ,(concat (genkou-test--a 19) "……い")
     (,(concat (genkou-test--a 19) "…") "…い"))
    ("――は行をまたいでよい"
     ,(concat (genkou-test--a 19) "――い")
     (,(concat (genkou-test--a 19) "―") "―い")))
  "(名前 入力 期待する行のリスト) のリスト。")

(ert-deftest genkou-wrap-paragraph-cases ()
  (dolist (c genkou-test--wrap-cases)
    (pcase-let ((`(,name ,input ,expected) c))
      (ert-info (name)
        (should (equal (genkou--wrap-paragraph input 20) expected))))))

(ert-deftest genkou-wrap-text-keeps-blank-lines ()
  (let ((genkou-cols 20))
    (should (equal (genkou--wrap-text "あ\n\nい") "あ\n\nい"))))

(ert-deftest genkou-wrap-closing-bracket-never-starts-a-row ()
  (dolist (row (genkou--wrap-paragraph (concat (genkou-test--a 20) "。」い") 20))
    (should-not (string-prefix-p "」" row))))

(ert-deftest genkou-max-hang-matches-python-side ()
  (should (= genkou--max-hang 3)))

;; --- wrap / unwrap（整形前の状態に戻る） ---

(defconst genkou-test--mixed-text
  (concat (genkou-test--a 45) "。」\n"          ; 長い段落（折り返される）
          "単独の改行で区切った短い段落\n"       ; 単独の改行
          "\n"                                  ; 空行
          (genkou-test--a 21))                  ; 空行の後の段落（折り返される）
  "空行区切りと単独の改行区切りが混在した原稿。")

(defmacro genkou-test--with-text (text &rest body)
  "TEXT を入れた一時バッファで BODY を実行する。"
  (declare (indent 1))
  `(with-temp-buffer
     (let ((genkou-cols 20))
       (insert ,text)
       ,@body)))

(ert-deftest genkou-unwrap-restores-original-exactly ()
  "wrap → unwrap で、整形前と完全に同じ文字列に戻る（単独の改行の段落もつながらない）。"
  (genkou-test--with-text genkou-test--mixed-text
    (genkou-wrap-buffer)
    (should-not (equal (buffer-string) genkou-test--mixed-text))
    (genkou-unwrap-buffer)
    (should (equal (buffer-substring-no-properties (point-min) (point-max))
                   genkou-test--mixed-text))))

(ert-deftest genkou-wrap-twice-then-unwrap-restores-original ()
  "wrap を重ねても改行が二重に残らず、unwrap 一回で元に戻る。"
  (genkou-test--with-text genkou-test--mixed-text
    (genkou-wrap-buffer)
    (let ((once (buffer-substring-no-properties (point-min) (point-max))))
      (genkou-wrap-buffer)
      (should (equal (buffer-substring-no-properties (point-min) (point-max)) once)))
    (genkou-unwrap-buffer)
    (should (equal (buffer-substring-no-properties (point-min) (point-max))
                   genkou-test--mixed-text))))

(ert-deftest genkou-unwrap-keeps-edits-made-after-wrap ()
  "wrap した後に書き足した文字は、unwrap しても残る。"
  (genkou-test--with-text (genkou-test--a 30)
    (genkou-wrap-buffer)
    (goto-char (point-max))
    (insert "ＸＹ")
    (genkou-unwrap-buffer)
    (should (equal (buffer-substring-no-properties (point-min) (point-max))
                   (concat (genkou-test--a 30) "ＸＹ")))))

(ert-deftest genkou-unwrap-without-wrap-does-nothing ()
  "wrap していないバッファでは何も壊さず、user-error になる。"
  (genkou-test--with-text genkou-test--mixed-text
    (should-error (genkou-unwrap-buffer) :type 'user-error)
    (should (equal (buffer-substring-no-properties (point-min) (point-max))
                   genkou-test--mixed-text))))

(ert-deftest genkou-wrap-marks-only-inserted-newlines ()
  "印が付くのは wrap が入れた改行だけで、元からあった改行には付かない。"
  (let* ((genkou-cols 20)
         (text (genkou--wrap-text (concat (genkou-test--a 25) "\n" (genkou-test--a 3))))
         (first-nl (string-match "\n" text))
         (second-nl (string-match "\n" text (1+ first-nl))))
    (should (get-text-property first-nl 'genkou-wrap-newline text))      ; wrap が入れた改行
    (should-not (get-text-property second-nl 'genkou-wrap-newline text)))) ; 元からの改行

(ert-deftest genkou-typing-after-wrapped-newline-does-not-inherit-mark ()
  "wrap が入れた改行の直後に入力した文字へ、印が引き継がれない（unwrap で消えない）。"
  (genkou-test--with-text (genkou-test--a 25)
    (genkou-wrap-buffer)
    (goto-char (1+ (string-match "\n" (buffer-string))))   ; 改行の直後（文字位置はバッファ位置-1）
    (insert-and-inherit "Ｚ")
    (should-not (get-text-property (1- (point)) 'genkou-wrap-newline))
    (genkou-unwrap-buffer)
    (should (string-match-p "Ｚ" (buffer-string)))))

;; --- 出力先の決定 ---

(defmacro genkou-test--with-output-dir (&rest body)
  "一時ディレクトリを出力先にして BODY を実行する。"
  (declare (indent 0))
  `(let* ((dir (make-temp-file "genkou-test" t))
          (genkou-wrap-output-directory dir))
     (unwind-protect (progn ,@body)
       (delete-directory dir t))))

(ert-deftest genkou-default-basename ()
  (with-temp-buffer
    (setq buffer-file-name "/tmp/x/原稿.v2.txt")
    (should (equal (genkou-wrap--default-basename) "原稿.v2")))
  (with-temp-buffer
    (rename-buffer "*genkou-test-draft*" t)
    (should (equal (genkou-wrap--default-basename) "genkou-test-draft")))
  (with-temp-buffer
    (rename-buffer "a/b:c" t)
    (should (equal (genkou-wrap--default-basename) "a_b_c"))))

(ert-deftest genkou-unique-path ()
  (genkou-test--with-output-dir
    (let ((p (expand-file-name "a.pdf" dir)))
      (should (equal (genkou-wrap--unique-path p) p))
      (write-region "" nil p)
      (should (equal (genkou-wrap--unique-path p)
                     (expand-file-name "a-1.pdf" dir)))
      (write-region "" nil (expand-file-name "a-1.pdf" dir))
      (should (equal (genkou-wrap--unique-path p)
                     (expand-file-name "a-2.pdf" dir))))))

(ert-deftest genkou-resolve-uses-default-when-no-conflict ()
  (genkou-test--with-output-dir
    (with-temp-buffer
      (rename-buffer "doc" t)
      (should (equal (genkou-wrap--resolve-pdf-path nil)
                     (expand-file-name "doc.pdf" dir))))))

(ert-deftest genkou-resolve-conflict-overwrite ()
  (genkou-test--with-output-dir
    (with-temp-buffer
      (rename-buffer "doc" t)
      (write-region "" nil (expand-file-name "doc.pdf" dir))
      (cl-letf (((symbol-function 'read-multiple-choice)
                 (lambda (&rest _) '(?o "上書き"))))
        (should (equal (genkou-wrap--resolve-pdf-path nil)
                       (expand-file-name "doc.pdf" dir)))))))

(ert-deftest genkou-resolve-conflict-rename ()
  (genkou-test--with-output-dir
    (with-temp-buffer
      (rename-buffer "doc" t)
      (write-region "" nil (expand-file-name "doc.pdf" dir))
      (let (initial)
        (cl-letf (((symbol-function 'read-multiple-choice)
                   (lambda (&rest _) '(?r "別名で保存")))
                  ;; 初期値（doc-1.pdf）をそのまま受け入れる
                  ((symbol-function 'read-file-name)
                   (lambda (_prompt d _default _must initial-name &rest _)
                     (setq initial initial-name)
                     (expand-file-name initial-name d))))
          (should (equal (genkou-wrap--resolve-pdf-path nil)
                         (expand-file-name "doc-1.pdf" dir)))
          (should (equal initial "doc-1.pdf")))))))

(ert-deftest genkou-resolve-conflict-cancel ()
  (genkou-test--with-output-dir
    (with-temp-buffer
      (rename-buffer "doc" t)
      (write-region "" nil (expand-file-name "doc.pdf" dir))
      (cl-letf (((symbol-function 'read-multiple-choice)
                 (lambda (&rest _) '(?q "中止"))))
        (should-error (genkou-wrap--resolve-pdf-path nil) :type 'user-error)))))

(ert-deftest genkou-resolve-reuses-last-pdf-without-asking ()
  (genkou-test--with-output-dir
    (with-temp-buffer
      (rename-buffer "doc" t)
      (let ((last (expand-file-name "doc.pdf" dir)))
        (write-region "" nil last)
        (setq genkou-wrap--last-pdf last)
        (cl-letf (((symbol-function 'read-multiple-choice)
                   (lambda (&rest _) (error "尋ねてはいけない"))))
          (should (equal (genkou-wrap--resolve-pdf-path nil) last)))))))

(ert-deftest genkou-resolve-force-ask-prompts-for-name ()
  (genkou-test--with-output-dir
    (with-temp-buffer
      (rename-buffer "doc" t)
      (let ((chosen (expand-file-name "memo.pdf" dir)))
        (cl-letf (((symbol-function 'read-file-name)
                   (lambda (&rest _) chosen)))
          (should (equal (genkou-wrap--resolve-pdf-path t) chosen)))))))

;; --- ビューア ---

(ert-deftest genkou-open-pdf-with-function ()
  (let* (got
         (genkou-wrap-pdf-viewer (lambda (p) (setq got p))))
    (genkou-wrap--open-pdf "/tmp/a.pdf")
    (should (equal got "/tmp/a.pdf"))))

(ert-deftest genkou-open-pdf-macos-app-name ()
  (let ((system-type 'darwin)
        (genkou-wrap-pdf-viewer "Skim")
        calls)
    (cl-letf (((symbol-function 'call-process)
               (lambda (&rest args) (push args calls) 0)))
      (genkou-wrap--open-pdf "/tmp/a.pdf"))
    (should (equal (car calls)
                   '("open" nil 0 nil "-a" "Skim" "/tmp/a.pdf")))))

(ert-deftest genkou-open-pdf-command-on-other-os ()
  (let ((system-type 'gnu/linux)
        (genkou-wrap-pdf-viewer "evince")
        calls)
    (cl-letf (((symbol-function 'call-process)
               (lambda (&rest args) (push args calls) 0)))
      (genkou-wrap--open-pdf "/tmp/a.pdf"))
    (should (equal (car calls) '("evince" nil 0 nil "/tmp/a.pdf")))))

(ert-deftest genkou-open-pdf-system-default ()
  (let ((genkou-wrap-pdf-viewer nil)
        calls)
    (cl-letf (((symbol-function 'call-process)
               (lambda (&rest args) (push args calls) 0)))
      (let ((system-type 'darwin))
        (genkou-wrap--open-pdf "/tmp/a.pdf"))
      (let ((system-type 'gnu/linux))
        (genkou-wrap--open-pdf "/tmp/a.pdf")))
    (should (equal (nth 1 calls) '("open" nil 0 nil "/tmp/a.pdf")))
    (should (equal (nth 0 calls) '("xdg-open" nil 0 nil "/tmp/a.pdf")))))

;; --- キーマップ ---

(ert-deftest genkou-keymap ()
  (should (eq (lookup-key genkou-wrap-mode-map (kbd "C-c C-c")) #'genkou-wrap-compile))
  (should (eq (lookup-key genkou-wrap-mode-map (kbd "C-c C-v")) #'genkou-wrap-preview))
  ;; 保存コマンド (C-c C-s) は廃止した
  (should-not (lookup-key genkou-wrap-mode-map (kbd "C-c C-s"))))

(provide 'genkou-wrap-test)
;;; genkou-wrap-test.el ends here
