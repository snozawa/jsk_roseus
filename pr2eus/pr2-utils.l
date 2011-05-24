;;
;;
;;
(require :pr2 "package://pr2eus/pr2.l")

(defmethod pr2-robot
  (:select-target-arm
   (c)
   (let ((v (send self :inverse-transform-vector (send c :worldpos))))
     (if (> (elt v 1) 0) :larm :rarm)))
  (:inverse-kinematics
   (target-coords &rest args &key (link-list) (move-arm)
                  (use-torso t) (move-target)
                  (use-base nil) (start-coords (send self :copy-worldcoords))
                  &allow-other-keys)
   (let (weight union-link-list torso-id base-weight diff-pos-rot)
     ;;
     ;; move-arm     x o x x o o x o ;; only in this function
     ;; link-list    x x o x o x o o ;; defined in upper class
     ;; move-target  x x x o x o o o ;; defined in upper class
     ;;              1 3 x x x 4 2 x
     ;;
     ;; 1:set move-arm from target-coords, set move-target from move-arm
     ;; 2;do nothing, since move-arm is used to set link-list and move-target
     ;; 3;set move-coords and link-list from move-arm
     ;; 4;set link-list from move-arm and move-target
     (unless move-arm
       (setq move-arm (send self :select-target-arm target-coords)))
     (unless move-target
       (setq move-target (send self move-arm :end-coords)))
     (unless link-list
       (setq link-list (send self :link-list (send move-target :parent)
                             (unless use-torso (car (send self move-arm))))))

     ;; use torso
     (setq weight (instantiate float-vector (send self :calc-target-joint-dimension link-list))
           union-link-list (send self :calc-union-link-list link-list)
           torso-id (position torso_lift_joint (send-all union-link-list :joint)))
     (fill weight 1)
     (when (and use-torso torso-id)
       (if (not (numberp use-torso)) (setq use-torso 0.005))
       (if torso-id (setf (elt weight torso-id) use-torso)))

     ;; use base
     (cond
      (use-base
       (setq diff-pos-rot
             (concatenate float-vector
                          (send start-coords :difference-position self)
                          (send start-coords :difference-rotation self)))
       (send self :move-to start-coords :world)
       (with-append-root-joint
        (ll self link-list
            :joint-class omniwheel-joint
            :joint-args
            (list :min #f(-30 -30 -30)
                  :max #f( 30  30  30)))
        (send (caar ll) :joint :joint-angle
              (float-vector (elt diff-pos-rot 0)
                            (elt diff-pos-rot 1)
                            (rad2deg (elt diff-pos-rot 5))))
        (if (eq use-base t) (setq use-base 0.1))
        (send-super* :inverse-kinematics target-coords
                     :rthre (deg2rad 5)
                     :thre 10
                     :stop 300
                     :weight (concatenate float-vector (float-vector use-base use-base use-base) weight)
                     :link-list (car ll) ;; link-list
                     :move-target move-target
                    args)))
      (t
       (send-super* :inverse-kinematics target-coords
                    :rthre (deg2rad 5)
                    :thre 10
                    :stop 300
                    :weight weight
                    :link-list link-list
                    :move-target move-target
                    args))
       )))
  (:limb
   (limb method &rest args)
   (case method
     (:gripper
      (send* self :gripper limb args))
     (t
      (send-super* :limb limb method args))))
  (:gripper
   (limb &rest args)
   (cond
    ((memq :joint-angle args)
     (if (null (cdr args))
         (case limb
           (:larm
            (* (send self :l_gripper_l_finger_joint :joint-angle) 2))
           (:rarm
            (* (send self :r_gripper_l_finger_joint :joint-angle) 2)))
       (let ((a/2 (/ (cadr args) 2)))
         (case limb
           (:larm
            (send self :l_gripper_l_finger_joint :joint-angle a/2)
            (send self :l_gripper_r_finger_joint :joint-angle a/2)
            (send self :l_gripper_l_finger_tip_joint :joint-angle a/2)
            (send self :l_gripper_r_finger_tip_joint :joint-angle a/2))
           (:rarm
            (send self :r_gripper_l_finger_joint :joint-angle a/2)
            (send self :r_gripper_r_finger_joint :joint-angle a/2)
            (send self :r_gripper_l_finger_tip_joint :joint-angle a/2)
            (send self :r_gripper_r_finger_tip_joint :joint-angle a/2)))
         (* a/2 2))))))
  )


