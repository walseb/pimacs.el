;;; pimacs-hashline-diff.el --- Diffs for hashline edits -*- lexical-binding: t; -*-

;;; Commentary:

;; Hashline's edit result contains anchors rather than a patch.  Save the file
;; just before such an edit runs and compare it with the resulting file.  The
;; snapshot is kept in memory and fed to `diff' on standard input, avoiding an
;; extra temporary-file write.  Ordinary edit tools, which return :patch, are
;; left unchanged.

;;; Code:

(require 'seq)
(require 'pimacs-utils)
(defvar pimacs-hashline-diff--snapshots (make-hash-table :test #'eq)
  "Pre-edit contents and paths, indexed by the exact arguments object.")

(defun pimacs-hashline-diff--hashline-p (args)
  "Return non-nil when ARGS describe a hashline edit."
  (let ((edits (plist-get args :edits)))
    (and edits
         (seq-some
          (lambda (edit)
            (let ((anchor (or (plist-get edit :pos)
                              (plist-get edit :end))))
              (or (member (plist-get edit :op)
                          '("replace" "append" "prepend" "replace_text"))
                  (and (stringp anchor)
                       (string-match-p "\\`[0-9]+#[[:alnum:]]+" anchor)))))
          edits))))

(defun pimacs-hashline-diff--file (args)
  "Return the absolute file named by ARGS."
  (when-let ((path (plist-get args :path)))
    (expand-file-name path (pimacs--project-root))))

(defun pimacs-hashline-diff--capture (args)
  "Capture the file before the hashline edit described by ARGS."
  (when-let* (((pimacs-hashline-diff--hashline-p args))
              (file (pimacs-hashline-diff--file args))
              ((file-readable-p file)))
    (with-temp-buffer
      (insert-file-contents-literally file)
      (puthash args (cons (buffer-string) file)
               pimacs-hashline-diff--snapshots))))

(defun pimacs-hashline-diff--make (old file)
  "Return a unified diff between OLD contents and FILE, or nil."
  (when (and old (file-readable-p file) (executable-find "diff"))
    (with-temp-buffer
      (insert old)
      (let ((status (call-process-region
                     (point-min) (point-max) "diff" t t nil
                     "-u" "--label" file "--label" file "-" file)))
        (cond
         ((eq status 1) (buffer-string))
         ((eq status 0) nil)
         ;; Do not replace a successful edit result with a diff diagnostic.
         (t nil))))))

(defun pimacs-hashline-diff--format-tool-args (fn tool-name args)
  "Capture edit input before calling FN for TOOL-NAME and ARGS."
  (when (equal tool-name "edit")
    ;; This advice runs before `pimacs--format-tool-args' creates its temporary
    ;; buffer, so project-relative paths are resolved in the chat buffer.
    (pimacs-hashline-diff--capture args))
  (funcall fn tool-name args))

(defun pimacs-hashline-diff--insert-edit-result (fn content details args)
  "Supply a synthesized patch to the standard edit result function FN."
  (let* ((snapshot (gethash args pimacs-hashline-diff--snapshots))
         (patch (or (plist-get details :patch)
                    (and snapshot
                         (pimacs-hashline-diff--make
                          (car snapshot) (cdr snapshot))))))
    (remhash args pimacs-hashline-diff--snapshots)
    (funcall fn content
             (if patch
                 (plist-put (copy-sequence details) :patch patch)
               details)
             args)))

(defun pimacs-hashline-diff--install ()
  "Install hashline diff handling independently of customizable inserter maps."
  (unless (advice-member-p #'pimacs-hashline-diff--format-tool-args
                           'pimacs--format-tool-args)
    (advice-add 'pimacs--format-tool-args :around
                #'pimacs-hashline-diff--format-tool-args))
  (unless (advice-member-p #'pimacs-hashline-diff--insert-edit-result
                           'pimacs--insert-edit-result)
    (advice-add 'pimacs--insert-edit-result :around
                #'pimacs-hashline-diff--insert-edit-result)))

(with-eval-after-load 'pimacs
  (pimacs-hashline-diff--install))

(provide 'pimacs-hashline-diff)
;;; pimacs-hashline-diff.el ends here
