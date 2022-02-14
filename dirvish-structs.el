;;; dirvish-structs.el --- Dirvish data structures -*- lexical-binding: t -*-

;; This file is NOT part of GNU Emacs.

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; This library contains data structures for Dirvish.

;;; Code:

(declare-function dirvish--add-advices "dirvish-advices")
(declare-function dirvish--remove-advices "dirvish-advices")
(require 'dirvish-options)
(require 'ansi-color)
(require 'cl-lib)

(defun dirvish-curr (&optional frame)
  "Get current dirvish instance in FRAME.

FRAME defaults to current frame."
  (if dirvish--curr-name
      (gethash dirvish--curr-name (dirvish-hash))
    (frame-parameter frame 'dirvish--curr)))

(defun dirvish-drop (&optional frame)
  "Drop current dirvish instance in FRAME.

FRAME defaults to current frame."
  (set-frame-parameter frame 'dirvish--curr nil))

(defun dirvish-reclaim (&optional _window)
  "Reclaim current dirvish."
  (unless (active-minibuffer-window)
    (if dirvish--curr-name
        (or dirvish-override-dired-mode (dirvish--add-advices))
      (or dirvish-override-dired-mode (dirvish--remove-advices)))
    (set-frame-parameter nil 'dirvish--curr (gethash dirvish--curr-name (dirvish-hash)))))

;;;###autoload
(cl-defmacro dirvish-define-attribute (name arglist &key bodyform lineform)
  "Define dirvish attribute NAME.

An attribute contains two rendering functions that being called
on `post-command-hook': `dirvish--render-NAME-body/line'.  The
former one takes no argument and runs BODYFORM once.  The latter
one takes ARGLIST and runs LINEFORM for every line where ARGLIST
can have element of `beg' (filename beginning position),
`end' (filename end position), or `hl-face' (indicate current
line when present)."
  (declare (indent defun))
  (let* ((attr-name (intern (format "dirvish-%s" name)))
         (body-func-name (intern (format "dirvish--render-%s-body" name)))
         (line-func-name (intern (format "dirvish--render-%s-line" name)))
         (line-arglist '(beg end hl-face))
         (ignore-list (cl-set-difference line-arglist arglist)))
    `(progn
       (defun ,body-func-name ()
         (remove-overlays (point-min) (point-max) ',attr-name t)
         ,bodyform)
       (defun ,line-func-name ,line-arglist
         (ignore ,@ignore-list)
         ,lineform))))

(defmacro dirvish--get-buffer (type &rest body)
  "Return dirvish buffer with TYPE.
If BODY is non-nil, create the buffer and execute BODY in it."
  (declare (indent 1))
  `(progn
     (let* ((id (frame-parameter nil 'window-id))
            (h-name (format " *Dirvish %s-%s*" ,type id))
            (buf (get-buffer-create h-name)))
       (with-current-buffer buf ,@body buf))))

(defun dirvish-update-ansicolor-h (_win pos)
  "Update dirvish ansicolor in preview window from POS."
  (with-current-buffer (current-buffer)
    (ansi-color-apply-on-region
     pos (progn (goto-char pos) (forward-line (frame-height)) (point)))))

(defun dirvish-init-frame (&optional frame)
  "Initialize the dirvishs system in FRAME.
By default, this uses the current frame."
  (unless (frame-parameter frame 'dirvish--hash)
    (with-selected-frame (or frame (selected-frame))
      (set-frame-parameter frame 'dirvish--transient '())
      (set-frame-parameter frame 'dirvish--hash (make-hash-table :test 'equal))
      (dirvish--get-buffer 'preview
        (setq-local mode-line-format nil)
        (add-hook 'window-scroll-functions #'dirvish-update-ansicolor-h nil :local))
      (dirvish--get-buffer 'header
        (setq-local header-line-format nil)
        (setq-local window-size-fixed 'height)
        (setq-local face-font-rescale-alist nil)
        (setq-local mode-line-format (and dirvish-header-line-format
                                          '((:eval (dirvish-format-header-line)))))
        (set (make-local-variable 'face-remapping-alist)
             `((mode-line-inactive :inherit (mode-line-active) :height ,dirvish-header-line-height))))
      (dirvish--get-buffer 'footer
        (setq-local header-line-format nil)
        (setq-local window-size-fixed 'height)
        (setq-local face-font-rescale-alist nil)
        (setq-local mode-line-format '((:eval (dirvish-format-mode-line))))
        (set (make-local-variable 'face-remapping-alist)
             '((mode-line-inactive mode-line-active)))))))

(defun dirvish-hash (&optional frame)
  "Return a hash containing all dirvish instance in FRAME.

The keys are the dirvish's names automatically generated by
`cl-gensym'.  The values are dirvish structs created by
`make-dirvish'.

FRAME defaults to the currently selected frame."
  ;; XXX: This must return a non-nil value to avoid breaking frames initialized
  ;; with after-make-frame-functions bound to nil.
  (or (frame-parameter frame 'dirvish--hash)
      (make-hash-table)))

(defun dirvish-get-all (slot &optional all-frame)
  "Gather slot value SLOT of all Dirvish in `dirvish-hash' as a flattened list.
If optional ALL-FRAME is non-nil, collect SLOT for all frames."
  (let* ((dv-slot (intern (format "dv-%s" slot)))
         (all-vals (if all-frame
                       (mapcar (lambda (fr)
                                 (with-selected-frame fr
                                   (mapcar dv-slot (hash-table-values (dirvish-hash)))))
                               (frame-list))
                     (mapcar dv-slot (hash-table-values (dirvish-hash))))))
    (delete-dups (flatten-tree all-vals))))

(cl-defstruct
    (dirvish
     (:conc-name dv-)
     (:constructor
      make-dirvish
      (&key
       (depth dirvish-depth)
       (root-window-func #'frame-selected-window)
       (transient nil)
       &aux
       (fullscreen-depth (if (>= depth 0) depth dirvish-depth))
       (read-only-depth (if (>= depth 0) depth dirvish-depth)))))
  "Define dirvish data type."
  (name
   (cl-gensym)
   :documentation "is a symbol that is unique for every instance.")
  (depth
   dirvish-depth
   :documentation "TODO.")
  (fullscreen-depth
   dirvish-depth
   :documentation "TODO.")
  (read-only-depth
   dirvish-depth
   :read-only t :documentation "TODO.")
  (transient
   nil
   :documentation "TODO.")
  (parent-buffers
   ()
   :documentation "holds all parent buffers in this instance.")
  (parent-windows
   ()
   :documentation "holds all parent windows in this instance.")
  (preview-window
   nil
   :documentation "is the window to display preview buffer.")
  (preview-buffers
   ()
   :documentation "holds all file preview buffers in this instance.")
  (window-conf
   (current-window-configuration)
   :documentation "is the window configuration given by `current-window-configuration'.")
  (root-window-func
   #'frame-selected-window
   :documentation "is the main dirvish window.")
  (root-window
   nil
   :documentation "is the main dirvish window.")
  (root-dir-buf-alist
   ()
   :documentation "TODO.")
  (attributes-alist
   ()
   :documentation "TODO.")
  (index-path
   ""
   :documentation "is the file path under cursor in ROOT-WINDOW.")
  (preview-dispatchers
   dirvish-preview-dispatchers
   :documentation "Preview dispatchers used for preview in this instance.")
  (ls-switches
   dired-listing-switches
   :documentation "is the list switches passed to `ls' command.")
  (sort-criteria
   (cons "default" "")
   :documentation "is the addtional sorting flag added to `dired-list-switches'."))

(defmacro dirvish-new (&rest args)
  "Create a new dirvish struct and put it into `dirvish-hash'.

ARGS is a list of keyword arguments followed by an optional BODY.
The keyword arguments set the fields of the dirvish struct.
If BODY is given, it is executed to set the window configuration
for the dirvish.

Save point, and current buffer before executing BODY, and then
restore them after."
  (declare (indent defun))
  (let ((keywords))
    (while (keywordp (car args))
      (dotimes (_ 2) (push (pop args) keywords)))
    (setq keywords (reverse keywords))
    `(let ((dv (make-dirvish ,@keywords)))
       (dirvish-init-frame)
       (puthash (dv-name dv) dv (dirvish-hash))
       ,(when args `(save-excursion ,@args)) ; Body form given
       dv)))

(defmacro dirvish-kill (dv &rest body)
  "Kill a dirvish instance DV and remove it from `dirvish-hash'.

DV defaults to current dirvish instance if not given.  If BODY is
given, it is executed to unset the window configuration brought
by this instance."
  (declare (indent defun))
  `(progn
     (let ((conf (dv-window-conf ,dv)))
       (when (and (not (dirvish-dired-p ,dv)) (window-configuration-p conf))
         (set-window-configuration conf)))
     (let ((tran-list (frame-parameter nil 'dirvish--transient)))
       (set-frame-parameter nil 'dirvish--transient (remove dv tran-list)))
     (cl-labels ((kill-when-live (b) (and (buffer-live-p b) (kill-buffer b))))
       (mapc #'kill-when-live (dv-parent-buffers ,dv))
       (mapc #'kill-when-live (dv-preview-buffers ,dv)))
     (remhash (dv-name ,dv) (dirvish-hash))
     ,@body))

(defun dirvish--start-transient (old-dv new-dv)
  "Mark OLD-DV and NEW-DV as a parent/child transient Dirvish."
  (setf (dv-transient new-dv) old-dv)
  (let ((tran-list (frame-parameter nil 'dirvish--transient)))
    (set-frame-parameter nil 'dirvish--transient (push old-dv tran-list)))
  (dirvish-activate new-dv))

(defun dirvish--end-transient (tran)
  "End transient of Dirvish instance or name TRAN."
  (cl-loop
   with hash = (dirvish-hash)
   with tran-dv = (if (dirvish-p tran) tran (gethash tran hash))
   for dv-name in (mapcar #'dv-name (hash-table-values hash))
   for dv = (gethash dv-name hash)
   for dv-tran = (dv-transient dv) do
   (when (or (eq dv-tran tran) (eq dv-tran tran-dv))
     (dirvish-kill dv))
   finally (dirvish-deactivate tran-dv)))

(defun dirvish--create-root-window (dv)
  "Create root window of DV."
  (let ((depth (dv-depth dv))
        (r-win (funcall (dv-root-window-func dv))))
    (when (and (>= depth 0) (window-parameter r-win 'window-side))
      (setq r-win (next-window)))
    (setf (dv-root-window dv) r-win)
    r-win))

(defun dirvish--refresh-slots (dv)
  "Update dynamic slot values of DV."
  (let* ((attrs (remove nil (append '(hl-line zoom symlink-target) dirvish-attributes)))
         (attrs-alist
          (cl-loop for attr in attrs
                   for body-renderer = (intern (format "dirvish--render-%s-body" attr))
                   for line-renderer = (intern (format "dirvish--render-%s-line" attr))
                   collect (cons body-renderer line-renderer)))
         (preview-dps
          (cl-loop for dp-name in (append '(disable) dirvish-preview-dispatchers '(default))
                   for dp-func-name = (intern (format "dirvish-preview-%s-dispatcher" dp-name))
                   collect dp-func-name)))
    (setf (dv-attributes-alist dv) attrs-alist)
    (setf (dv-preview-dispatchers dv) preview-dps)
    (cond ((seq-intersection attrs dirvish-enlarge-attributes)
           (unless (dirvish-dired-p dv) (setf (dv-depth dv) 0))
           (setf (dv-fullscreen-depth dv) 0))
          (t
           (unless (dirvish-dired-p dv) (setf (dv-depth dv) (dv-read-only-depth dv)))
           (setf (dv-fullscreen-depth dv) (dv-read-only-depth dv))))))

(defun dirvish-activate (dv)
  "Activate dirvish instance DV."
  (setq tab-bar-new-tab-choice "*scratch*")
  (when-let (old-dv (dirvish-curr))
    (cond ((dv-transient dv) nil)
          ((and (not (dirvish-dired-p old-dv))
                (not (dirvish-dired-p dv)))
           (dirvish-deactivate dv)
           (user-error "Dirvish: using current session"))
          ((memq (selected-window) (dv-parent-windows old-dv))
           (dirvish-deactivate old-dv))))
  (dirvish--refresh-slots dv)
  (dirvish--create-root-window dv)
  (set-frame-parameter nil 'dirvish--curr dv)
  (run-hooks 'dirvish-activation-hook)
  dv)

(defun dirvish-deactivate (dv)
  "Deactivate dirvish instance DV."
  (dirvish-kill dv
    (unless (dirvish-get-all 'name t)
      (setq other-window-scroll-buffer nil)
      (setq tab-bar-new-tab-choice dirvish-saved-new-tab-choice)
      (dolist (tm dirvish-repeat-timers) (cancel-timer (symbol-value tm))))
    (dirvish-reclaim))
  (and dirvish-debug-p (message "leftover: %s" (dirvish-get-all 'name t))))

(defun dirvish-dired-p (&optional dv)
  "Return t if DV is a `dirvish-dired' instance.
DV defaults to the current dirvish instance if not provided."
  (when-let ((dv (or dv (dirvish-curr)))) (eq (dv-depth dv) -1)))

(defun dirvish-live-p (&optional dv)
  "Return t if selected window is occupied by Dirvish DV.
DV defaults to the current dirvish instance if not provided."
  (when-let ((dv (or dv (dirvish-curr)))) (memq (selected-window) (dv-parent-windows dv))))

(provide 'dirvish-structs)
;;; dirvish-structs.el ends here
