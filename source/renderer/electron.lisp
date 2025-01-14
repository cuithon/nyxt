;;;; SPDX-FileCopyrightText: Atlas Engineer LLC
;;;; SPDX-License-Identifier: BSD-3-Clause

(nyxt:define-package :nyxt/renderer/electron
  (:documentation "Electron renderer."))
(in-package :nyxt/renderer/electron)

(push :nyxt-electron *features*)

(define-class electron-renderer (renderer)
  ((name "Electron"))
  (:export-class-name-p t)
  (:export-accessor-names-p t)
  (:metaclass user-class)
  (:documentation "Electron renderer class."))

(defmethod install ((renderer electron-renderer))
  (flet ((set-superclasses (renderer-class-sym+superclasses)
           (closer-mop:ensure-finalized
            (closer-mop:ensure-class (first renderer-class-sym+superclasses)
                                     :direct-superclasses (rest renderer-class-sym+superclasses)
                                     :metaclass 'interface-class))))
    (mapc #'set-superclasses '((renderer-browser electron-browser)
                               (renderer-scheme electron-scheme)
                               (renderer-window electron-window)
                               (renderer-buffer electron-buffer)))))

(defmethod uninstall ((renderer electron-renderer))
  (flet ((remove-superclasses (renderer-class-sym)
           (closer-mop:ensure-finalized
            (closer-mop:ensure-class renderer-class-sym
                                     :direct-superclasses '()
                                     :metaclass 'interface-class))))
    (mapc #'remove-superclasses '(renderer-browser
                                  renderer-scheme
                                  renderer-window
                                  renderer-buffer))))

(setf nyxt::*renderer* (make-instance 'electron-renderer))

(define-class electron-scheme (electron:protocol)
  ()
  (:export-class-name-p t)
  (:export-accessor-names-p t)
  (:metaclass user-class)
  (:documentation "Electron scheme class."))

(defmethod initialize-instance :after ((scheme electron-scheme) &key)
  ;; Set the scheme name from child (`scheme') to parent class
  ;; (`electron-scheme').
  (setf (slot-value scheme 'electron:scheme-name)
        (name scheme)))

(defmethod ffi-register-custom-scheme ((scheme electron-scheme))
  (electron:handle-callback scheme (callback scheme)))

(define-class electron-browser (electron:interface)
  ()
  (:export-class-name-p t)
  (:export-accessor-names-p t)
  (:metaclass user-class)
  (:documentation "Electron browser class."))

(defmethod ffi-initialize ((browser electron-browser) urls startup-timestamp)
  (declare (ignore urls startup-timestamp))
  (log:debug "Initializing Electron Interface")
  (setf electron:*interface* (make-instance 'electron:interface))
  ;; Schemes' privileges (security settings) need to be set before launch.
  (setf (electron:protocols electron:*interface*)
        (list (make-instance 'electron:protocol
                             :scheme-name "nyxt"
                             :privileges "{}")
             (make-instance 'electron:protocol
                             :scheme-name "nyxt-resource"
                             :privileges "{secure:true}")
              (make-instance 'electron:protocol
                             :scheme-name "lisp"
                             :privileges "{supportFetchAPI:true,corsEnabled:true}")
              (make-instance 'electron:protocol
                             :scheme-name "view-source"
                             :privileges "{}")
              (make-instance 'electron:protocol
                             :scheme-name "editor"
                             :privileges "{}")
              (make-instance 'electron:protocol
                             :scheme-name "gopher"
                             :privileges "{}")
              (make-instance 'electron:protocol
                             :scheme-name "gemini"
                             :privileges "{}")))
  (electron:launch electron:*interface*)
  (maphash (lambda (scheme-name callbacks)
             (ffi-register-custom-scheme (make-instance 'scheme
                                                        :name scheme-name
                                                        :callback (first callbacks)
                                                        :error-callback (second callbacks))))
           nyxt::*schemes*)
  (call-next-method))

(defmethod ffi-kill-browser ((browser electron-browser))
  (declare (ignore browser))
  (electron:terminate))

;; Find analog of
;; https://webkitgtk.org/reference/webkit2gtk/stable/func.uri_for_display.html
;; (defmethod ffi-display-url ((browser electron-browser) text))

(define-class electron-buffer (electron:browser-view)
  ()
  (:export-class-name-p t)
  (:export-accessor-names-p t)
  (:metaclass user-class)
  (:documentation "Electron buffer class."))

(defmethod initialize-instance :after ((buffer electron-buffer) &key extra-modes no-hook-p)
  (finalize-buffer buffer :extra-modes extra-modes :no-hook-p no-hook-p))

;; TODO Needed for resurrect-buffer.
;; (defmethod ffi-buffer-make ((buffer electron-buffer))
;;   (make-instance 'electron-buffer))

(defmethod ffi-buffer-delete ((buffer electron-buffer))
  (electron:kill buffer))

(defmethod ffi-buffer-url ((buffer electron-buffer))
  (quri:uri (electron:get-url buffer)))

(defmethod ffi-buffer-title ((buffer electron-buffer))
  (electron:get-title buffer))

(defmethod ffi-buffer-load ((buffer electron-buffer) url)
  ;; Primitive way to introduce the auto-rules logic.
  (apply-auto-rules url buffer)
  ;; Hack until on-signal-* methods are handled.
  (setf (slot-value buffer 'url) url)
  ;; Taken from the GTK port, although it shows bad design:
  ;; Mark buffer as :loading right away so functions like `window-set-buffer'
  ;; don't try to reload if they are called before the "load-changed" signal
  ;; is emitted.
  (when (web-buffer-p buffer) (setf (nyxt::status buffer) :loading))
  (electron:load-url buffer url)
  ;; Hack until on-signal-* methods are handled.
  (electron:on-event (electron:web-contents buffer) "did-finish-load"
                     (lambda (_) (declare (ignore _)) (setf (nyxt::status buffer) :finished))))

(defmethod ffi-buffer-evaluate-javascript ((buffer electron-buffer) javascript
                                           &optional world-name)
  ;; TODO world-name is used in user-script mode.
  (declare (ignore world-name))
  (electron:execute-javascript (electron:web-contents buffer) javascript))

(defmethod ffi-buffer-evaluate-javascript-async ((buffer electron-buffer) javascript
                                                 &optional world-name)
  (declare (ignore world-name))
  ;; Temporary fallback.
  (ffi-buffer-evaluate-javascript buffer javascript))

(defmethod ffi-inspector-show ((buffer electron-buffer))
  (electron:open-dev-tools buffer))

(defmethod ffi-focused-p ((buffer electron-buffer))
  (electron:is-focused buffer))

;; Not used anywhere, deprecate?
;; (defmethod ffi-buffer-load-html ((buffer electron-buffer) html-content url))

;; ffi-buffer-load-alternate-html handles bogus URLs (https://bogusfoo.com/).
;; (defmethod ffi-buffer-load-alternate-html ((buffer electron-buffer) html-content content-url url))

;; TODO Specialize as not to use the general JS solution from foreign-interface.
;; (defmethod ffi-buffer-copy ((buffer electron-buffer) &optional (text nil text-provided-p)))
;; (defmethod ffi-buffer-paste ((buffer electron-buffer) &optional (text nil text-provided-p)))
;; (defmethod ffi-buffer-cut ((buffer electron-buffer)))
;; (defmethod ffi-buffer-select-all ((buffer electron-buffer)))

;; TODO
;; (defmethod ffi-buffer-undo ((buffer electron-buffer)))
;; (defmethod ffi-buffer-redo ((buffer electron-buffer)))

;; TODO
;; (defmethod ffi-buffer-cookie-policy ((buffer electron-buffer)))

(defmethod ffi-height ((buffer electron-buffer))
  (electron:get-bounds buffer 'height))

(defmethod (setf ffi-height) (height (buffer electron-buffer))
  (electron:set-bounds buffer
                       (electron:get-bounds buffer 'x)
                       (electron:get-bounds buffer 'y)
                       (electron:get-bounds buffer 'width)
                       height))

(defmethod ffi-focus-prompt-buffer ((prompt-buffer prompt-buffer))
  (electron:focus prompt-buffer)
  prompt-buffer)

(defmethod (setf ffi-height) ((height integer) (prompt-buffer prompt-buffer))
  (with-slots (window) prompt-buffer
    (case height
      (0
       (ffi-buffer-delete prompt-buffer)
       (electron:focus (nyxt::active-buffer window)))
      (t
       (electron:on window "resize"
         (format nil "~a.setBounds({x:      0,
                                    y:      ~a.getBounds().height -
                                            (~a +
                                             ~a.getBounds().height +
                                             ~a.getBounds().height),
                                    width:  ~a.getBounds().width,
                                    height: ~a})"
                 (electron:remote-symbol prompt-buffer)
                 (electron:remote-symbol window)
                 height
                 (electron:remote-symbol (status-buffer window))
                 (electron:remote-symbol (message-buffer window))
                 (electron:remote-symbol window)
                 height))
       (add-buffer window
                   prompt-buffer
                   :x 0
                   :y (- (electron:get-bounds window 'height)
                         (+ height
                            (height (status-buffer window))
                            (height (message-buffer window))))
                   :width (electron:get-bounds window 'width)
                   :height height
                   :horizontal-p t
                   :width-p t)
       (electron:load-url prompt-buffer "about:blank")
       (electron:set-top-browser-view window prompt-buffer)
       (ffi-focus-prompt-buffer prompt-buffer)))))

(defmethod ffi-width ((buffer electron-buffer))
  (electron:get-bounds buffer 'width))

(defmethod (setf ffi-width) (width (buffer electron-buffer))
  (electron:set-bounds buffer
                       (electron:get-bounds buffer 'x)
                       (electron:get-bounds buffer 'y)
                       width
                       (electron:get-bounds buffer 'height)))

(defmethod ffi-buffer-sound-enabled-p ((buffer electron-buffer))
  (not (electron:muted-p (electron:web-contents buffer))))
(defmethod (setf ffi-buffer-sound-enabled-p) ((buffer electron-buffer) value)
  (electron:set-audio-muted (electron:web-contents buffer) (not value)))

;; TODO Support download-mode.
;; (defmethod ffi-buffer-download ((buffer electron-buffer) url))

;; TODO Support proxy-mode.
;; (defmethod ffi-buffer-proxy ((buffer electron-buffer)))
;; (defmethod (setf ffi-buffer-proxy) (value (buffer electron-buffer)))

;; TODO Support user-script mode.
;; (defmethod ffi-buffer-add-user-style ((buffer electron-buffer) style))
;; (defmethod ffi-buffer-remove-user-style ((buffer electron-buffer) style))
;; (defmethod ffi-buffer-add-user-script ((buffer electron-buffer) script))
;; (defmethod ffi-buffer-remove-user-script ((buffer electron-buffer) script))

;; TODO Support no-image mode.
;; (defmethod ffi-buffer-auto-load-image-enabled-p ((buffer electron-buffer)))
;; (defmethod (setf ffi-buffer-auto-load-image-enabled-p) ((buffer electron-buffer)))

;; TODO Support reduce-tracking mode.
;; See https://stackoverflow.com/a/35672988
;; See https://www.electronjs.org/docs/latest/api/web-contents#contentsloadurlurl-options
;; (defmethod ffi-buffer-user-agent ((buffer electron-buffer)))
;; (defmethod (setf ffi-buffer-user-agent) (value (buffer electron-buffer)))
;; (defmethod ffi-tracking-prevention ((buffer electron-buffer)))
;; (defmethod (setf ffi-tracking-prevention) (value (buffer electron-buffer)))
;; See https://www.electronjs.org/docs/latest/api/session#sessetuseragentuseragent-acceptlanguages.
;; (defmethod ffi-preferred-languages ((buffer electron-buffer)))

(define-class electron-window (electron:browser-window)
  ()
  (:export-class-name-p t)
  (:export-accessor-names-p t)
  (:metaclass user-class)
  (:documentation "Electron window class."))

(defmethod initialize-instance :after ((window electron-window) &key)
  (let ((message-buffer (message-buffer window))
        (status-buffer (status-buffer window)))
    (setf (slot-value window 'nyxt::active-buffer) (make-instance 'input-buffer))
    (electron:on window "resize"
      (format nil "~a.setBounds({x:      0,
                                 y:      ~a.getBounds().height - ~a,
                                 width:  ~a.getBounds().width,
                                 height: ~a})"
              (electron:remote-symbol message-buffer)
              (electron:remote-symbol window)
              (height message-buffer)
              (electron:remote-symbol window)
              (height message-buffer)))
    (add-buffer window
                message-buffer
                :x 0
                :y (- (electron:get-bounds window 'height)
                      (height message-buffer))
                :width (electron:get-bounds window 'width)
                :height (height message-buffer)
                :horizontal-p t
                :width-p t)
    (electron:load-url message-buffer "about:blank")
    (electron:on window "resize"
      (format nil "~a.setBounds({x:      0,
                                 y:      ~a.getBounds().height - (~a + ~a),
                                 width:  ~a.getBounds().width,
                                 height: ~a})"
              (electron:remote-symbol status-buffer)
              (electron:remote-symbol window)
              (height status-buffer)
              (height message-buffer)
              (electron:remote-symbol window)
              (height status-buffer)))
    (add-buffer window
                status-buffer
                :x 0
                :y (- (electron:get-bounds window 'height)
                      (+ (height status-buffer)
                         (height message-buffer)))
                :width (electron:get-bounds window 'width)
                :height (height status-buffer)
                :horizontal-p t
                :width-p t)
    (electron:load-url status-buffer "about:blank")
    ;; KLUDGE Without it, the window won't intercept input events.
    (electron:load-url window "about:blank")
    ;; Each window listens to input events.  Another approach would be to listen
    ;; the each buffer.
    (electron:register-before-input-event window
                                          (lambda (win event)
                                            (on-signal-key-press-event win event)))))

(defmethod add-buffer ((window electron-window) (buffer electron-buffer)
                       &key (x 0) (y 0) (width 1000) (height 1000)
                         (width-p nil) (height-p nil) (horizontal-p nil) (vertical-p nil))
  (electron:add-browser-view window buffer)
  (electron:set-auto-resize buffer width-p height-p horizontal-p vertical-p)
  (electron:set-bounds buffer x y width height)
  buffer)

(defmethod ffi-window-delete ((window electron-window))
  (electron:kill window))

(defmethod ffi-window-title ((window electron-window))
  (electron:get-title window))
(defmethod (setf ffi-window-title) (title (window electron-window))
  (electron:set-title window title))

(defmethod ffi-window-set-buffer ((window electron-window)
                                  (buffer electron-buffer)
                                  &key (focus t))
  ;; In GTK, when the prompt buffer is up and a new main buffer is created, the
  ;; prompt buffer remains open.  As per below, the prompt buffer would be
  ;; closed.
  (add-buffer window
              buffer
              :x 0
              :y 0
              :width (electron:get-bounds window 'width)
              :height (- (electron:get-bounds window 'height)
                         (+ (height (status-buffer window))
                            (height (message-buffer window))))
              :width-p t
              :height-p t
              :horizontal-p t
              :vertical-p nil)
  (electron:set-top-browser-view window buffer)
  (when focus (electron:focus buffer))
  buffer)

;; Setting the html for panel and internal pages should use the same logic.
;; See issue #3239.
;; (defmethod ffi-window-add-panel-buffer ((window electron-window)
;;                                         (panel-buffer panel-buffer)
;;                                         side)
;;   (match side
;;     (:left (push panel-buffer (panel-buffers-left window)))
;;     (:right (push panel-buffer (panel-buffers-right window)))))

;; (defmethod ffi-window-delete-panel-buffer ((window electron-window)
;;                                            (panel-buffer panel-buffer))
;;   (delete panel-buffer (panel-buffers window)))

(defmethod ffi-height ((window electron-window))
  (electron:get-bounds window 'height))

(defmethod ffi-width ((window electron-window))
  (electron:get-bounds window 'width))

(defmethod ffi-window-fullscreen ((window electron-window))
  (electron:fullscreen window))

(defmethod ffi-window-unfullscreen ((window electron-window))
  (electron:unfullscreen window))

(defmethod ffi-window-maximize ((window electron-window))
  (electron:maximize window))

(defmethod ffi-window-unmaximize ((window electron-window))
  (electron:unmaximize window))

;; Input handling

(defun translate-modifiers (event)
  "Return list of modifiers fit for `keymaps:make-key'."
  (let ((modifiers (list)))
    (when (cdr (assoc :shift event))
      (push "shift" modifiers))
    (when (cdr (assoc :control event))
      (push "control" modifiers))
    (when (cdr (assoc :alt event))
      (push "meta" modifiers))
    (when (cdr (assoc :meta event))
      (push "super" modifiers))
    modifiers))

(defun translate-key-string (key-string)
  "Return string representation of a keyval.
Return nil when key must be discarded, e.g. for modifiers."
  (match key-string
    ((or "Alt" "Shift" "Control" "Meta") nil)
    ;; Compatibility layer between GDK keycode names and those of Browsers.
    ;; https://gitlab.gnome.org/GNOME/gtk/-/blob/main/gdk/gdkkeysyms.h
    ;; https://developer.mozilla.org/en-US/docs/Web/API/UI_Events/Keyboard_event_key_values
    ("-" "hyphen")
    (" " "space")
    ("Enter" "return")
    ("Escape" "escape")
    ("Tab" "tab")
    ("Backspace" "backspace")
    ("ArrowUp" "up")
    ("ArrowDown" "down")
    ("ArrowRight" "right")
    ("ArrowLeft" "left")
    ("PageUp" "pageup")
    ("PageDown" "pagedown")
    ("Home" "home")
    ("End" "end")
    ("F1" "f1")
    ("F2" "f2")
    ("F3" "f3")
    ("F4" "f4")
    ("F5" "f5")
    ("F6" "f6")
    ("F7" "f7")
    ("F8" "f8")
    ("F9" "f9")
    ("F10" "f10")
    ("F11" "f11")
    ("F12" "f12")
    (_ key-string)))

(defmethod on-signal-key-press-event ((sender electron-window) event)
  (let ((key-string (translate-key-string (rest (assoc :key event))))
        (buffer (or (current-prompt-buffer) (nyxt::active-buffer sender))))
    (flet ((key () (keymaps:make-key :value key-string
                                     :modifiers (translate-modifiers event)
                                     :status :pressed)))
      (when key-string
        (alex:appendf (key-stack sender)
                      (list (key)))
        (run-thread "on-signal-key-press" (on-signal-key-press buffer (key)))
        (dispatch-input-event event buffer sender)))))

(defmethod on-signal-key-release-event ((sender electron-window) event)
  (declare (ignore sender event)))

;; TODO on-signal-* methods
