(setq lisp::*error-handler* #'(lambda (&rest args) (print args *error-output*)(exit 1)))
(make-package "ROS")
(defvar *roslib-dir* (read-line (piped-fork "rospack find roslib")))
(defvar *gendeps-bin*
  (cond ((probe-file (format nil "~A/scripts/gendeps" *roslib-dir*))
	 (format nil "~A/scripts/gendeps" *roslib-dir*))
	((probe-file (format nil "~A/bin/gendeps" *roslib-dir*))
	 (format nil "~A/bin/gendeps" *roslib-dir*))
	((probe-file (format nil "~A/../../lib/roslib/gendeps" (unix::getenv "ROS_ROOT")))
         (format nil "~A/../../lib/roslib/gendeps" (unix::getenv "ROS_ROOT")))
	(t
	 nil)))

(defun generate-msg-datatype-name-list (strm)
  (let (msgs consts line pos type var init-elem vec-size)
    (while (not (eq :eof (setq line (read-line strm nil :eof))))
      ;; remove comments
      (if (string= line "---" :start1 0 :end1 3) (return))
      (setq pos (position #\# line))
      (if pos (setq line (subseq line 0 pos)))
      ;; replcae tab to whitespace
      (setq line (nsubstitute #\space #\tab line))
      ;; remove whitespaces
      (setq line (string-trim " " line))

      ;;(setq pos (count #\space line))
      ;;(setq line (remove-duplicates  line :test #'(lambda (a b) (if (eq a #\space) (equal a b) nil))))
      ;;
      (when (> (length line) 0)
	;; split line into type and var
	(setq pos (position #\space line))
	(setq type (subseq line 0 pos))
	(setq var (concatenate string "_" (string-left-trim '(#\space #\tab) (subseq line (1+ pos)))))
	;; format type
	(if (string= "header" (string-downcase type))
	    (setq type (concatenate string "std_msgs::" type)))
	(if (setq pos (position #\/ type))
	    (setq type (format nil "~A::~A" (subseq type 0 pos) (subseq type (1+ pos)))))
	;; when variable is list
	(if (setq pos (position #\[ type))
	    (setq vec-size
		  (if (= (1+ pos) (position #\] type)) 0
		    (read-from-string (subseq type (1+ pos))))
		  type (subseq type 0 pos))
	  (setq vec-size nil))
	;; constants
	(if (setq pos (position #\= var))
	    (progn
              (setq init-elem (string-trim " " (subseq var (1+ pos))))
              (setq var (string-trim " " (subseq var 0 pos)))
              (push (list type var init-elem vec-size) consts))
	  (push (list type var vec-size) msgs))))
    (list (setq msgs (nreverse msgs)) (setq consts (nreverse consts)))))

(defun ros::ros-home-dir ()
  (let ((ros-home (unix::getenv "ROS_HOME")))
    (unless ros-home (setq ros-home (format nil "~A/.ros" (unix::getenv "HOME"))))
    (unless (probe-file (format nil "~A/roseus" ros-home))
      (unix::system (format nil "mkdir ~A/roseus" ros-home)))
    ros-home))
(defun generate-msg-output-file-name (fname pkg name dir)
  (let (l oname)
    (setq l (read-line (piped-fork (format nil "rospack find ~A" pkg)) nil))
    (unless l
      (warning-message 1 ";; ERROR could not find ~A package~%" pkg)(exit 1))
    (setq oname (format nil "~A/roseus/~A/~A/" (ros::ros-home-dir) pkg dir))
    (unless (lisp::directory-p oname)
      (warning-message 6 ";; mkdir ~A~%" oname)
      (unix::system (format nil "mkdir -p ~A" oname)))
    (setq oname (concatenate string oname (format nil "~A.l" name)))))

;;
;;
;;

(defun generate-variable-type (type)
  (cond ((or (string= type "byte") (string= type "char")
	     (string= type "int8") (string= type "uint8"))
	 :int8)
	((or (string= type "int16") (string= type "uint16"))
	 :int16)
	((or (string= type "int32") (string= type "uint32"))
	 :int32)
	((or (string= type "int64") (string= type "uint64"))
	 :int64)
	((string= type "float32")
	 :float32)
	((string= type "float64")
	 :float64)
	((string= type "string")
	 :string)
        ((string= type "bool") ;; bool is used as byte
         :boolean)
	((or (string= type "time") (string= type "duration"))
	 :time)
	(t
	 :rostype)))

;;
;;
;;
(defun generate-donotedit-message (strm from)
  (format strm ";;~%")
  (format strm ";; DO NOT EDIT THIS FILE~%")
  (format strm ";;~%")
  (format strm ";; Auto-generated from ~A~%" from)
  (format strm ";;  at ~A" (unix:asctime (unix:localtime)))
  (format strm ";;  using ~A~%" (lisp-implementation-version))
  (format strm ";;~%")
  (format strm "~%"))

(defun generate-msg-headers (strm pkg name)
  (let ((upcase-pkg (string-upcase pkg))
	(upcase-name (string-upcase name)))
    (format strm ";;~%")
    (generate-donotedit-message strm (format nil "~A/~A.msg" pkg name))
    (format strm "(when (boundp '~A::~A)~%" pkg name)
    (format strm "  (if (not (find-package \"~A\"))~%" upcase-pkg)
    (format strm "    (make-package \"~A\"))~%" upcase-pkg)
    (format strm "  (shadow '~A (find-package \"~A\")))~%" name upcase-pkg)
    (format strm "(unless (find-package \"~A::~A\")~%" upcase-pkg upcase-name)
    (format strm "  (make-package \"~A::~a\"))~%" upcase-pkg upcase-name)
    (format strm "~%")
    (format strm "(in-package \"ROS\")~%")
    (format strm "~%")
    ))

(defun generate-msg-loaders (strm msgs name)
  (let ()
    (format strm ";;~%")
    (dolist (msg msgs)
      (when (substringp "::" (car msg))
        (let ((pkg (subseq (car msg) 0 (position #\: (car msg))))
              (file (subseq (car msg) (+ (position #\: (car msg)) 2))))
          (format strm "(if (not (find-package \"~A\"))~%" (string-upcase pkg))
          (format strm "  (ros::roseus-add-msgs \"~A\"))~%" pkg))))
    (format strm "~%")
    ))

(defun make-const-string (str)
  ;; replace " -> \"
  (let ((strm (make-string-output-stream (+ 2 (length str)))))
    (format strm "~C" #\")
    (dotimes (i (length str))
      (let ((c (elt str i)))
	(if (= c #\") (format strm "~C" #\\))
	(format strm "~C" c)))
    (format strm "~C" #\")
    (get-output-stream-string strm)))
(defun generate-msg-defconstants (strm pkg name consts)
  (let (accessor)
    (dolist (const consts)
      (setq accessor (subseq (cadr const) 1))
      (format strm "(shadow '*~A* (find-package \"~A::~A\"))~%" accessor (string-upcase pkg) (string-upcase name))
      (format strm "(defconstant ~A::~A::*~A* ~A)~%" pkg name accessor
	      (if (string= (car const) "string")
		  (make-const-string (caddr const))
		(caddr const))))
    (format strm "~%")
    ))

(defun generate-msg-defclass (strm pkg name msgs)
  (let ()
    (format strm "(defclass ~A::~A~%" pkg name)
    (format strm "  :super ros::object~%")
    (format strm "  :slots (")
    (dolist (msg msgs) (format strm "~A " (cadr msg)))
    (format strm "))~%")
    (format strm "~%")
    ))

(defun generate-msg-init (strm pkg name msgs)
  (let (type accessor var var-type init-elem vec-size)
    (format strm "  (:init~%")
    (format strm "   (&key~%")
    (dolist (msg msgs)
      (setq type (elt msg 0) var (elt msg 1)
	    vec-size (elt msg 2))
      (setq accessor (subseq var 1))
      (setq var-type (generate-variable-type type))
      (setq init-elem
	    (case var-type
		  ((:int8 :int16 :int32 :int64) 0)
		  ((:float32 :float64) 0.0)
		  (:string "\"\"")
                  (:boolean "nil")
		  (:time "(instance ros::time :init)")
		  (:rostype (format nil "(instance ~A :init)"
				    (if (substringp "::" type)
					type
				      (concatenate string pkg "::" type))))
		  (t (error "undefined type ~A~%" msg))))
      (cond
       ((and vec-size (eq var-type :int8))
	(format strm "    ((:~A _~A) (make-array ~A :initial-element ~A :element-type :char))~%" accessor var vec-size init-elem))
       ((and vec-size (eq var-type :boolean))
	(format strm "    ((:~A _~A) (make-array ~A :initial-element ~A :element-type :object))~%" accessor var vec-size init-elem))
       ((and vec-size (memq var-type '(:int16 :int32 :int64)))
	(format strm "    ((:~A _~A) (make-array ~A :initial-element ~A :element-type :integer))~%" accessor var vec-size init-elem))
       ((and vec-size (memq var-type '(:float32 :float64)))
	(format strm "    ((:~A _~A) (make-array ~A :initial-element ~A :element-type :float))~%" accessor var vec-size init-elem))
       (vec-size
	(format strm "    ((:~A _~A) (let (r) (dotimes (i ~A) (push ~A r)) r))~%" accessor var vec-size init-elem))
       (t
	(format strm "    ((:~A _~A) ~A)~%" accessor var init-elem))))
    (format strm "    )~%")
    (format strm "   (send-super :init)~%")
    (dolist (msg msgs)
      (setq type (elt msg 0) var (elt msg 1)
	    vec-size (elt msg 2))
      (let ((s1 "") (s2 ""))
	(unless vec-size
	  (case
	   (generate-variable-type type)
	   ((:int8 :int16 :int32 :int64) (setq s1 "(round " s2 ")"))
	   ((:float32 :float64) (setq s1 "(float " s2 ")"))
	   (:string (setq s1 "(string " s2 ")"))))
	(format strm "   (setq ~A ~A_~A~A)~%" var s1 var s2)))
    (format strm "   self)~%")))

(defun generate-msg-accessors (strm pkg name msgs)
  (let (var accessor)
    (dolist (msg msgs)
      (setq var (cadr msg))
      (setq accessor (subseq var 1))
      (format strm "  (:~A~%" accessor)
      (if (eq (generate-variable-type (car msg)) :rostype)
	  (progn
	    (format strm "   (&rest _~A)~%" var)
	    (format strm "   (if (keywordp (car _~A))~%" var)
	    (format strm "       (send* ~A _~A)~%" var var)
	    (format strm "     (progn~%")
	    (format strm "       (if _~A (setq ~A (car _~A)))~%" var var var)
	    (format strm "       ~A)))~%" var))
	(progn
	  (format strm "   (&optional _~A)~%" var)
	  (format strm "   (if _~A (setq ~A _~A)) ~A)~%" var var var var))))
    ))

(defun generate-msg-serialization-length (strm pkg name msgs)
  (let (type var vec-size gen-type)
    (format strm "  (:serialization-length~%")
    (format strm "   ()~%")
    (format strm "   (+~%")
    (unless msgs ;; empty message
      (format strm "    0~%"))
    (dolist (msg msgs)
      (setq type (elt msg 0) var (elt msg 1)
	    vec-size (elt msg 2)
            gen-type (generate-variable-type type))
      (cond
       (vec-size (format strm "    ;; ~A[~A] ~A~%" type (if (zerop vec-size) "" vec-size) var))
       (t        (format strm "    ;; ~A ~A~%" type var)))
      (format strm "    ")
      (if (and vec-size (and (not (eq gen-type :rostype))
                             (not (eq gen-type :string))))
          (format strm "(* "))
      (case
       gen-type
       ((:int8 :boolean) (format strm "1"))
       (:int16 (format strm "2"))
       ((:int32 :float32) (format strm "4"))
       ((:int64 :float64) (format strm "8"))
       (:time (format strm "8"))
       (:rostype
        (if vec-size
            (format strm "(apply #'+ (send-all ~A :serialization-length))" var)
          (format strm "(send ~A :serialization-length)" var)))
       (:string
        (if vec-size
            (format strm "(apply #'+ (mapcar #'(lambda (x) (+ 4 (length x))) ~A))" var)
          (format strm "4 (length ~A)" var)))
       (t (error "undefined type ~A~%" msg)))
      (cond
       ((and vec-size (eq gen-type :rostype) (zerop vec-size))
        (format strm " 4"))
       ((and vec-size (eq gen-type :string) (zerop vec-size))
        (format strm " 4"))
       ((and vec-size (and (not (eq gen-type :rostype))
                           (not (eq gen-type :string)))
             (zerop vec-size))
        (format strm " (length ~A)) 4" var))
       ((and vec-size (and (not (eq gen-type :rostype))
                           (not (eq gen-type :string))))
        (format strm " ~A)" vec-size)))
      (format strm "~%")
      )
    (format strm "    ))~%")
    ))

(defun generate-msg-serialize (strm pkg name msgs)
  (let (type var-type var vec-size)
    (format strm "  (:serialize~%")
    (format strm "   (&optional strm)~%")
    (format strm "   (let ((s (if strm strm~%")
    (format strm "              (make-string-output-stream (send self :serialization-length)))))~%")
    (dolist (msg msgs)
      (setq type (elt msg 0) var (elt msg 1)
	    vec-size (elt msg 2) var-type (generate-variable-type type))
      (cond
       ((and vec-size (zerop vec-size) (memq var-type '(:time :string :rostype)))
	(format strm "     ;; ~A[] ~A~%" type var)
	(format strm "     (write-long (length ~A) s)~%" var)
        (format strm "     (dolist (elem ~A)~%  " var)
        (setq var "elem"))
       ((and vec-size (zerop vec-size))
	(format strm "     ;; ~A[] ~A~%" type var)
	(format strm "     (write-long (length ~A) s)~%" var)
        (cond
         ((eq var-type :int8) );; do nothing
         (t
          (format strm "     (dotimes (i (length ~A))~%  " var)
          (setq var (format nil "(elt ~A i)" var)))))
       (vec-size
	(format strm "     ;; ~A[~A] ~A~%" type vec-size var)
        (cond
         ((eq var-type :int8) );; do nothing
         (t
          (format strm "     (dotimes (i ~A)~%  " vec-size)
          (setq var (format nil "(elt ~A i)" var)))))
       (t
        (format strm "     ;; ~A ~A~%" type var)))
      (case
       var-type
       (:int8
        (if vec-size
            (format strm "     (princ ~A s)~%" var)
          (format strm "     (write-byte ~A s)~%" var)))
       (:int16
	(format strm "     (write-word ~A s)~%" var))
       (:int32
	(format strm "     (write-long ~A s)~%" var))
       (:int64

	(format strm "#+(or :alpha :irix6 :x86_64)~%")
	(format strm "     (progn (sys::poke ~A (send s :buffer) (send s :count) :long) (incf (stream-count s) 8))~%" var)
	(format strm "#-(or :alpha :irix6 :x86_64)~%")
	(format strm "     (cond ((and (class ~A) (= (length (~A . bv)) 2)) ;; bignum~%" var var)
	(format strm "            (write-long (ash (elt (~A . bv) 0) 0) s)~%" var)
	(format strm "            (write-long (ash (elt (~A . bv) 1) -1) s))~%" var)
	(format strm "           ((and (class ~A) (= (length (~A . bv)) 1)) ;; big1~%" var var)
	(format strm "            (write-long (elt (~A . bv) 0) s)~%" var)
        (format strm "            (write-long (if (>= ~A 0) 0 #xffffffff) s))~%" var)
	(format strm "           (t                                         ;; integer~%")
        (format strm "            (write-long ~A s)(write-long (if (>= ~A 0) 0 #xffffffff) s)))~%" var var)
        )
       (:float32
	(format strm "     (sys::poke ~A (send s :buffer) (send s :count) :float) (incf (stream-count s) 4)~%" var))
       (:float64
	(format strm "     (sys::poke ~A (send s :buffer) (send s :count) :double) (incf (stream-count s) 8)~%" var))
       (:string
	(format strm "     (write-long (length ~A) s) (princ ~A s)~%" var var))
       (:boolean
        (format strm "     (if ~A (write-byte -1 s) (write-byte 0 s))~%" var))
       (:time
	(format strm "     (write-long (send ~A :sec) s) (write-long (send ~A :nsec) s)~%" var var))
       (:rostype
	(format strm "     (send ~A :serialize s)~%" var))
       (t (error "undefined type ~A~%" msg)))
      (if (and vec-size (not (eq var-type :int8))) (format strm "       )~%"))
      )
    (format strm "     ;;~%")
    (format strm "     (if (null strm) (get-output-stream-string s))))~%")))

(defun generate-msg-deserialize (strm pkg name msgs)
  (let (type var vec-size set var-type)
    (format strm "  (:deserialize~%")
    (format strm "   (buf &optional (ptr- 0))~%")
    (dolist (msg msgs)
      (setq type (elt msg 0) var (elt msg 1)
	    vec-size (elt msg 2) var-type (generate-variable-type type))
      (cond
       ((and vec-size (zerop vec-size))
	(format strm "   ;; ~A[] ~A~%" type var)
	(format strm "   (let (n)~%")
	(format strm "     (setq n (sys::peek buf ptr- :integer)) (incf ptr- 4)~%")
	(case
	 var-type
         (:int8
	  (format strm "     (setq ~A (make-array n :element-type :char))~%" var))
	 (:boolean
	  (format strm "     (setq ~A (make-array n :element-type :object))~%" var))
	 ((:int16 :int32 :int64)
	  (format strm "     (setq ~A (instantiate integer-vector n))~%" var))
	 ((:float32 :float64)
	  (format strm "     (setq ~A (instantiate float-vector n))~%" var))
         (:string
           (format strm "     (setq ~A (make-list n))~%" var))
	 (:rostype
	  (format strm "     (setq ~A (let (r) (dotimes (i n) (push (instance ~A :init) r)) r))~%" var (if (substringp "::" type) type (concatenate string pkg "::" type)))))
        (case
         var-type
         (:rostype
          (format strm "     (dolist (elem- ~A)~%" var)
          (format strm "       ")
          (setq set "setf" var "elem-"))
         (:int8 (format strm "     " var)) ;; do nothing
         (t
          (format strm "     (dotimes (i n)~%" var)
          (format strm "       ")
          (setq set "setf" var (format nil "(elt ~A i)" var))))
        )
       (vec-size
	(format strm "   ;; ~A[~A] ~A~%" type vec-size var)
        (case
         var-type
         (:rostype
          (format strm "     (dolist (elem- ~A)~%" var)
          (format strm "       ")
          (setq set "setf" var "elem-"))
         (:int8 (format strm "     " var)) ;; do nothing
         (t
          (format strm "   (dotimes (i (length ~A))~%" var)
          (format strm "     ")
          (setq set "setf" var (format nil "(elt ~A i)" var)))))
       (t
        (format strm "   ;; ~A ~A~%" type var)
        (format strm "   ")
	(setq set "setq")))

      (case
       var-type
       (:int8
        (if vec-size
            (format strm "(replace ~A buf :start2 ptr-) (incf ptr- (length ~A))~%" var var)
          (format strm "(~A ~A (sys::peek buf ptr- :char)) (incf ptr- 1)~%" set var)))
       (:int16
	(format strm "(~A ~A (sys::peek buf ptr- :short)) (incf ptr- 2)~%" set var))
       (:int32
	(format strm "(~A ~A (sys::peek buf ptr- :integer)) (incf ptr- 4)~%" set var))
       (:int64
	(format strm "~%#+(or :alpha :irix6 :x86_64)~%")
	(format strm "   (~A ~A (prog1 (sys::peek buf ptr- :long) (incf ptr- 8)))~%" set var)
	(format strm "#-(or :alpha :irix6 :x86_64)~%")
	(format strm "   (~A ~A (let ((b0 (prog1 (sys::peek buf ptr- :integer) (incf ptr- 4)))~%" set var)
	(format strm "                (b1 (prog1 (sys::peek buf ptr- :integer) (incf ptr- 4))))~%")
	(format strm "            (cond ((= b1 -1) b0)~%")
	(format strm "                   ((and (= b1  0)~%")
	(format strm "                         (<= lisp::most-negative-fixnum b0 lisp::most-positive-fixnum))~%")
	(format strm "                    b0)~%")
	(format strm "                  ((= b1  0) (make-instance bignum :size 1 :bv (integer-vector b0)))~%")
	(format strm "                  (t (make-instance bignum :size 2 :bv (integer-vector b0 (ash b1 1)))))))~%"))
       (:float32
	(format strm "(~A ~A (sys::peek buf ptr- :float)) (incf ptr- 4)~%" set var))
       (:float64
	(format strm "(~A ~A (sys::peek buf ptr- :double)) (incf ptr- 8)~%" set var))
       (:string
	(format strm "(let (n) (setq n (sys::peek buf ptr- :integer)) (incf ptr- 4) (~A ~A (subseq buf ptr- (+ ptr- n))) (incf ptr- n))~%" set var))
       (:boolean
	(format strm "(~A ~A (not (= 0 (sys::peek buf ptr- :char)))) (incf ptr- 1)~%" set var))
       (:time
	(format strm "(send ~A :sec (sys::peek buf ptr- :integer)) (incf ptr- 4)  (send ~A :nsec (sys::peek buf ptr- :integer)) (incf ptr- 4)~%" var var))
       (:rostype
        (format strm "(send ~A :deserialize buf ptr-) (incf ptr- (send ~A :serialization-length))~%" var var))
       (t (error "undefined type ~A~%" msg)))
      (cond
       ((and vec-size (eq var-type :int8) (zerop vec-size))
        (format strm "     )~%"))
       ((and vec-size (eq var-type :int8))
        ) ;; do nothing
       ((and vec-size (zerop vec-size))
	(format strm "       ))~%"))
       (vec-size
	(format strm "     )~%")))
      )
    (format strm "   ;;~%")
    (format strm "   self)~%")))

(setq *md5table* nil)
(defun get-md5sum (pkg name fname)
  (let ((key fname) val)
    (setq val (cdr (assoc key *md5table* :test #'string=)))
    (when (null val)
      (setq val (read-line (piped-fork (format nil "~A md5 ~A/~A" (if (string= (pathname-type fname) "msg") "rosmsg" "rossrv") pkg name)) nil nil))) ;;use rosmsg or rossrv instead of gendeps https://github.com/ros/ros/issues/18
    (when (not val)
      (setq val (read-line (piped-fork (format nil "~A --md5 ~A" *gendeps-bin* fname)) nil nil))) ;;workaround for packages installed from source
    (when (null val) ;; some groovy/rosbuild environemnt needs this line?
      (setq val (read-line (piped-fork (format nil "PYTHONPATH=`rospack find ~A`/build/devel/lib/python2.7/dist-packages:$PYTHONPATH ~A md5 ~A/~A" pkg (if (string= (pathname-type fname) "msg") "rosmsg" "rossrv") pkg name)) nil nil)))
    (when (null val)
      (warning-message 1 "[ERROR] Could not get md5sum for ~A ~A ~A~%" pkg name fname)
      (exit -1))
    (push (cons key val) *md5table*)
    val))
(defun generate-msg-md5sum (strm pkg name fname)
  (let ()
    (format strm "(setf (get ~A::~A :md5sum-) \"~A\")~%" pkg name (get-md5sum pkg name fname))))

(defun generate-msg-datatype (strm pkg name)
  (let ()
    (format strm "(setf (get ~A::~A :datatype-) \"~A/~A\")~%" pkg name pkg name)))

(defun escape-double-quote (str)
  (let ((str2 ""))
    (dotimes (i (length str))
      (case (elt str i)
            (#\" (setq str2 (concatenate string str2 "\\\"")))
            (t   (setq str2 (format nil "~A~C" str2 (elt str i))))))
    str2))

(defun generate-msg-definition (strm pkg name fname)
  (let (p def)
    (format strm "(setf (get ~A::~A :definition-)~%      \"" pkg name)
    (setq p (piped-fork (format nil "~A --cat ~A" *gendeps-bin* fname)))
    (while (setq def (read-line p nil nil))
      (format strm "~A~%" (escape-double-quote def)))
    (format strm "\")~%")
    (format strm "~%")))

(defun generate-srv-type (strm pkg name req-msgs res-msgs)
  (let ()
    (format strm "(setf (get ~A::~A :request) ~A::~A)~%" pkg name pkg req-msgs)
    (format strm "(setf (get ~A::~A :response) ~A::~A)~%" pkg name pkg res-msgs)
    (format strm "~%")
    (format strm "(defmethod ~A::~A~%" pkg req-msgs)
    (format strm "  (:response () (instance ~A::~A :init)))~%" pkg res-msgs)
    (format strm "~%")))


(defun generate-provide (strm pkg name fname)
  (let ()
    (format strm "~%~%")
    (format strm "(provide :~A/~A \"~A\")~%"
	    pkg name (get-md5sum pkg name fname))))

;;;
;;;
;;;

(defun genfile-header (fname)
  (let (pkg name)
    (setq pkg (car (last (butlast (pathname-directory fname)))))
    (setq name (pathname-name fname))
    (warning-message 6 ";; generate message for ~A/~A~%" pkg name)
    (warning-message 6 ";; parsing ~A~%" fname)
    (unless (probe-file fname)
      (warning-message 1 ";; ERROR message file ~A not found~%" fname)(exit 1))
    (list pkg name)))

(defun genfile-body (pkg name msgs strm)
  (let ()
    ;;
    ;; defclass
    (generate-msg-defclass strm pkg name msgs)
    ;; defmethod
    (format strm "(defmethod ~A::~A~%" pkg name)
    ;; :init
    (generate-msg-init strm pkg name msgs)
    ;; :accessors
    (generate-msg-accessors strm pkg name msgs)
    ;; serialization-length
    (generate-msg-serialization-length strm pkg name msgs)
    ;; serialize
    (generate-msg-serialize strm pkg name msgs)
    ;; deserialize
    (generate-msg-deserialize strm pkg name msgs)
    (format strm "  )~%~%")
    ;;
    ))

;;;
;;;
;;;

(defun check-srv-file (pkg name)
  (read-line (piped-fork (format nil "rossrv show ~A/~A" pkg name)) nil))
(defun check-msg-file (pkg name)
  (read-line (piped-fork (format nil "rosmsg show ~A/~A" pkg name)) nil))

(defun genmsg-eus (fname)
  (let (msgs consts def pkg name oname)
    (multiple-value-setq (pkg name) (genfile-header fname))
    ;;; https://github.com/willowgarage/catkin/issues/122
    (unless (or (check-msg-file pkg name)
		(string= (format nil "~A/roseus/~A/action_msg/~A.msg" (ros::ros-home-dir) pkg name) fname))
      (warning-message 1 ";; error occured when parsing ~A/msg/~A~%" pkg name)
      (return-from genmsg-eus nil))
    (with-open-file
     (strm fname :direction :input)
     (multiple-value-setq (msgs consts) (generate-msg-datatype-name-list strm)))
    (setq oname (generate-msg-output-file-name fname pkg name "msg"))
    (warning-message 6 ";; writing to ~A~%" oname)

    (with-open-file
     (strm oname :direction :output)
     (generate-msg-headers strm pkg name)
     ;;
     (generate-msg-loaders strm msgs name)
     ;; defconstants
     (generate-msg-defconstants strm pkg name consts)
     ;;
     (genfile-body pkg name msgs strm)
     ;; md5sum/type/definition
     (generate-msg-md5sum strm pkg name fname)
     (generate-msg-datatype strm pkg name)
     (generate-msg-definition strm pkg name fname)

     (generate-provide strm pkg name fname)
     (format strm "~%~%")
     )))

(defun genfile-srvs (pkg name strm)
  (let ()
    (format strm "(defclass ~A::~A~%" pkg name)
    (format strm "  :super ros::object~%")
    (format strm "  :slots ())~%~%")
#|
    (format strm "(defmethod ~A::~A~%" pkg name)
    (format strm "  (:init ()~%")
    (format strm "   (setq request (instance ~A::~ARequest :init)~%" pkg name)
    (format strm "         response (instance ~A::~AResponse :init)))~%" pkg name)
    (format strm "  (:request  (&rest args) (if args (send* request args) request))~%")
    (format strm "  (:response (&rest args) (if args (send* response args) response))~%")
    (format strm ")~%~%")
|#
    ))

(defun gensrv-eus (fname)
  (let (req-msgs res-msgs consts1 consts2 doc pkg name req-name res-name oname)
    (multiple-value-setq (pkg name) (genfile-header fname))
    (setq req-name (format nil "~ARequest"  name)
          res-name (format nil "~AResponse" name))
    (unless (check-srv-file pkg name)
      (warning-message 1 ";; error occured when parsing ~A/srv/~A~%" pkg name)
      (return-from gensrv-eus nil))
    (with-open-file
     (strm fname :direction :input)
     (multiple-value-setq (req-msgs consts1) (generate-msg-datatype-name-list strm))
     (multiple-value-setq (res-msgs consts2) (generate-msg-datatype-name-list strm)))

    (setq oname (generate-msg-output-file-name fname pkg name "srv"))
    (warning-message 6 ";; writing to ~A~%" oname)

    (with-open-file
     (strm oname :direction :output)
     (generate-msg-headers strm pkg name)
     ;; defconstants
     (generate-msg-defconstants strm pkg name (append consts1 consts2))
     ;;
     (genfile-body pkg req-name req-msgs strm)
     (genfile-body pkg res-name res-msgs strm)
     ;; md5sum/type/definition
     (genfile-srvs pkg name strm)
     (generate-msg-md5sum strm pkg name fname)
     (generate-msg-datatype strm pkg name)
     (generate-srv-type strm pkg name req-name res-name)
     (generate-msg-md5sum strm pkg req-name fname)
     (generate-msg-datatype   strm pkg req-name)
     (generate-msg-definition strm pkg req-name fname)
     (generate-msg-md5sum strm pkg res-name fname)
     (generate-msg-datatype   strm pkg res-name)
     (generate-msg-definition strm pkg res-name fname)

     (generate-provide strm pkg name fname)
     (format strm "~%~%")
     )))


(defun genmanifest-eus (pkg &optional (target-file "manifest.l"))
  (let (depend-pkgs strm l
	(dir (format nil "~A/roseus/~A" (ros::ros-home-dir) pkg)))
    (setq strm (piped-fork (format nil "rospack depends -q ~A" pkg)))
    (while (setq l (read-line strm nil))
      (push l depend-pkgs))
    (close strm)
    (push pkg depend-pkgs)
    (setq depend-pkgs (nreverse depend-pkgs))
    (unless depend-pkgs (return-from genmanifest-eus nil))
    (unless (lisp::directory-p dir)
      (warning-message 6 ";; mkdir ~A~%" dir)
      (unix::system (format nil "mkdir -p ~A" dir)))
    (setq target-file (format nil "~A/~A" dir target-file))
    (with-open-file
     (f target-file :direction :output)
     (warning-message 6 ";; writing to ~A~%" target-file)
     (generate-donotedit-message f pkg)
     (dolist (pkg depend-pkgs)
       (pprint `(ros::load-ros-package ,pkg) f)))
    ))



