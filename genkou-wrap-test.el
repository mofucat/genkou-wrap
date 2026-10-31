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
