;;; gitsum.el --- basic darcsum feelalike for Git
;; Copyright (C) 2008  Christian Neukirchen <purl.org/net/chneukirchen>
;; Licensed under the same terms as Emacs.

;; Repository: http://github.com/chneukirchen/gitsum
;;              git://github.com/chneukirchen/gitsum.git
;; Patches to: chneukirchen@gmail.com

;; Version: 0.2
;; 04feb2008  +chris+

(eval-when-compile (require 'cl))

;; git.el for `git-get-top-dir'
(require 'git)

(defcustom gitsum-reuse-buffer t
  "Whether `gitsum' should try to reuse an existing buffer
if there is already one that displays the same directory."
  :group 'git
  :type 'boolean)

(defcustom gitsum-use-elscreen nil
  "Whether `gitsum' use el-screen."
  :group 'git
  :type 'boolean)

(easy-mmode-defmap gitsum-diff-mode-shared-map
  '(("A" . gitsum-amend)
    ("c" . gitsum-commit)
    ("g" . gitsum-refresh)
    ("k" . gitsum-kill-dwim)
    ("P" . gitsum-push)
    ("R" . gitsum-revert)
    ("s" . gitsum-switch-to-git-status)
    ("q" . gitsum-kill-buffer)
    ("u" . gitsum-undo))
  "Basic keymap for `gitsum-diff-mode', bound to various prefix keys.")

(define-derived-mode gitsum-diff-mode diff-mode "gitsum"
  "Git summary mode is for preparing patches to a Git repository.
This mode is meant to be activated by `M-x gitsum' or pressing `s' in git-status.
\\{gitsum-diff-mode-shared-map}
\\{gitsum-diff-mode-map}"
  ;; magic...
  (lexical-let ((ro-bind (cons 'buffer-read-only gitsum-diff-mode-shared-map)))
    (add-to-list 'minor-mode-overriding-map-alist ro-bind))
  (setq buffer-read-only t))

(define-key gitsum-diff-mode-map (kbd "C-c C-c") 'gitsum-commit)
(define-key gitsum-diff-mode-map (kbd "C-/") 'gitsum-undo)
(define-key gitsum-diff-mode-map (kbd "C-_") 'gitsum-undo)

;; When git.el is loaded, hack into keymap.
(when (boundp 'git-status-mode-map)
  (define-key git-status-mode-map "s" 'gitsum-switch-from-git-status))

;; Undo doesn't work in read-only buffers else.
(defun gitsum-undo ()
  "Undo some previous changes.

Repeat this command to undo more changes.
A numeric argument serves as a repeat count."
  (interactive)
  (let ((inhibit-read-only t))
    (undo)))

(defun gitsum-git-command (command)
  (let ((dir (git-get-top-dir default-directory)))
    (concat "cd " dir "; " command)))

(defun gitsum-refresh (&optional arguments)
  "Regenerate the patch based on the current state of the index."
  (interactive)
  (let ((inhibit-read-only t))
    (erase-buffer)
    (insert "# Directory:  " (git-get-top-dir default-directory) "\n")
    (insert "# Use n and p to navigate and k to kill a hunk.  u is undo, g will refresh.\n")
    (insert "# Edit the patch as you please and press 'c' to commit.\n\n")
    (let ((diff (shell-command-to-string (concat "git diff " arguments))))
      (if (zerop (length diff))
          (insert "## No changes. ##")
        (insert diff)
        (goto-char (point-min))
        (delete-matching-lines "^index \\|^diff --git ")))
    (set-buffer-modified-p nil)
    (goto-char (point-min))
    (forward-line 4)))

(defun gitsum-kill-dwim ()
  "Kill the current hunk or file depending on point."
  (interactive)
  (let ((inhibit-read-only t))
    (if (looking-at "^---\\|^\\+\\+\\+")
        (diff-file-kill)
      (diff-hunk-kill)
      (save-excursion
        (when (or (looking-at "^--- ")
                  (eobp))
          (let ((here (point)))
            (forward-line -2)
            (when (looking-at "^--- ")
              (delete-region here (point)))))))))

(defun gitsum-commit (&optional type)
  "Commit the patch as-is, asking for a commit message."
  (interactive)
  (let ((buffer (get-buffer-create "*gitsum-commit*"))
        (dir (git-get-top-dir default-directory))
        (amend (and type (eq type 'amend))))
    (unless amend
      (shell-command-on-region (point-min) (point-max) (gitsum-git-command "git apply --check --cached"))
      (shell-command-on-region (point-min) (point-max) (gitsum-git-command "(cat; git diff --cached) | git apply --stat") buffer))
    (with-current-buffer buffer
      (when amend
        (make-local-variable 'gitsum-commit-amend-p)
        (setq gitsum-commit-amend-p amend))
      (setq default-directory dir)
      (goto-char (point-min))
      (insert "\n")
      (while (re-search-forward "^" nil t)
        (replace-match "# " nil nil))
      (forward-line 0)
      (forward-char -1)
      (delete-region (point) (point-max))
      (goto-char (point-min)))
    (log-edit 'gitsum-do-commit nil nil buffer)))

(defun gitsum-amend ()
  "Amend the last commit."
  (interactive)
  (let ((last (substring (shell-command-to-string
                          (gitsum-git-command "git log -1 --pretty=oneline --abbrev-commit"))
                         0 -1)))
    (if (y-or-n-p (concat "Amend to " last ", or update comment?"))
        (progn (shell-command-on-region (point-min) (point-max) (gitsum-git-command "git apply --cached"))
               (shell-command (gitsum-git-command "git commit --amend -C HEAD")))
      (gitsum-commit 'amend))
    (gitsum-refresh)))

(defun gitsum-push ()
  "Push the current repository."
  (interactive)
  (let ((args (read-string "Shell command: " "git push ")))
    (let ((buffer (get-buffer-create " *gitsum-push*")))
      (switch-to-buffer buffer)
      (insert "Running " args "...\n\n")
      (start-process-shell-command "gitsum-push" buffer args))))

(defun gitsum-revert ()
  "Revert the active patches in the working directory."
  (interactive)
  (let ((count (count-matches "^@@" (point-min) (point-max))))
    (if (not (yes-or-no-p
              (format "Are you sure you want to revert these %d hunk(s)? "
                      count)))
        (message "Revert canceled.")
      (shell-command-on-region (point-min) (point-max) (gitsum-git-command "git apply --reverse"))
      (gitsum-refresh))))

(defun gitsum-do-commit ()
  "Perform the actual commit using the current buffer as log message."
  (interactive)
  (with-current-buffer log-edit-parent-buffer
    (shell-command-on-region (point-min) (point-max)
                             (gitsum-git-command "git apply --cached")))
  (let ((commit-command
         (if (and (boundp 'gitsum-commit-amend-p) gitsum-commit-amend-p)
             (progn (setq gitsum-commit-amend-p nil)
                    "git commit -F- --cleanup=strip --amend")
           "git commit -F- --cleanup=strip")))
    (shell-command-on-region (point-min) (point-max)
                             (gitsum-git-command commit-command))) 
  (with-current-buffer log-edit-parent-buffer
    (if gitsum-reuse-buffer
        (gitsum-refresh)
      (kill-buffer)
      (if gitsum-use-elscreen
          (elscreen-kill)))))

(defun gitsum-kill-buffer ()
  "Kill the current buffer if it has no manual changes."
  (interactive)
  (if (buffer-modified-p)
      (message "Patch was modified, use C-x k to kill.")
    (kill-buffer nil)))

(defun gitsum-switch-to-git-status ()
  "Switch to git-status."
  (interactive)
  (git-status (git-get-top-dir default-directory)))

(defun gitsum-switch-from-git-status ()
  "Switch to gitsum, resticting diff to marked files if any."
  (interactive)
  (let ((marked (git-get-filenames
                 (ewoc-collect git-status
                               (lambda (info) (git-fileinfo->marked info))))))
    (gitsum)
    (when marked
      (gitsum-refresh (mapconcat 'identity marked " ")))))

(defun gitsum-find-buffer (dir)
  "Find the gitsum buffer handling a specified directory."
  (let ((list (buffer-list))
        (fulldir (expand-file-name dir))
        found)
    (while (and list (not found))
      (let ((buffer (car list)))
        (with-current-buffer buffer
          (when (and list-buffers-directory
                     (string-equal fulldir
                                   (expand-file-name list-buffers-directory))
                     (eq major-mode 'gitsum-diff-mode))
            (setq found buffer))))
      (setq list (cdr list)))
    found))

(defun gitsum ()
  "Entry point into gitsum-diff-mode."
  (interactive)
  (let* ((dir (git-get-top-dir default-directory))
         (buffer (or (and gitsum-reuse-buffer (gitsum-find-buffer dir))
                     (generate-new-buffer "*gitsum*"))))
    (if gitsum-use-elscreen
        (elscreen-create))
    (switch-to-buffer buffer)
    (gitsum-diff-mode)
    (set (make-local-variable 'list-buffers-directory) dir)
    (gitsum-refresh)))

;; viper compatible
(eval-after-load "viper"
  '(add-to-list 'viper-emacs-state-mode-list 'gitsum-diff-mode))

(provide 'gitsum)
