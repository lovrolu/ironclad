;;;; -*- mode: lisp; indent-tabs-mode: nil -*-
;;;; rsa.lisp -- implementation of the RSA public key algorithm

(in-package :crypto)


;;; class definitions

(defclass rsa-key ()
  ((n :initarg :n :reader rsa-key-modulus :type integer)))

(defclass rsa-public-key (rsa-key)
  ((e :initarg :e :reader rsa-key-exponent :type integer)))

(defclass rsa-private-key (rsa-key)
  ((d :initarg :d :reader rsa-key-exponent :type integer)))


;;; function definitions

(defmethod make-public-key ((kind (eql :rsa))
                            &key e n &allow-other-keys)
  (unless e
    (error 'missing-key-parameter
           :kind 'rsa
           :parameter 'e
           :description "public exponent"))
  (unless n
    (error 'missing-key-parameter
           :kind 'rsa
           :parameter 'n
           :description "modulus"))
  (make-instance 'rsa-public-key :e e :n n))

(defmethod destructure-public-key ((public-key rsa-public-key))
  (list :e (rsa-key-exponent public-key)
        :n (rsa-key-modulus public-key)))

(defmethod make-private-key ((kind (eql :rsa))
                             &key d n &allow-other-keys)
  (unless d
    (error 'missing-key-parameter
           :kind 'rsa
           :parameter 'd
           :description "private exponent"))
  (unless n
    (error 'missing-key-parameter
           :kind 'rsa
           :parameter 'n
           :description "modulus"))
  (make-instance 'rsa-private-key :d d :n n))

(defmethod destructure-private-key ((private-key rsa-private-key))
  (list :d (rsa-key-exponent private-key)
        :n (rsa-key-modulus private-key)))

(defmethod generate-key-pair ((kind (eql :rsa)) &key num-bits &allow-other-keys)
  (unless num-bits
    (error 'missing-key-parameter
           :kind 'rsa
           :parameter 'num-bits
           :description "modulus size"))
  (let ((l (floor num-bits 2)))
    (multiple-value-bind (p q n)
        (loop for a = (generate-prime (- num-bits l))
              for b = (generate-prime l)
              for c = (* a b)
              until (and (/= a b) (= num-bits (integer-length c)))
              finally (return (values a b c)))
      (let* ((phi (* (1- p) (1- q)))
             (e (loop for e = (+ 2 (strong-random (- phi 2)))
                      until (= 1 (gcd e phi))
                      finally (return e)))
             (d (modular-inverse-with-blinding e phi)))
        (values (make-private-key :rsa :d d :n n)
                (make-public-key :rsa :e e :n n))))))

(defun rsa-core (msg exponent modulus)
  (assert (< msg modulus))
  (expt-mod msg exponent modulus))

(defmethod make-message ((kind (eql :rsa)) &key m n-bits &allow-other-keys)
  (unless m
    (error 'missing-message-parameter
           :kind 'rsa
           :parameter 'm
           :description "ciphertext"))
  (unless n-bits
    (error 'missing-message-parameter
           :kind 'rsa
           :parameter 'n-bits
           :description "modulus size"))
  (integer-to-octets m :n-bits n-bits))

(defmethod destructure-message ((kind (eql :rsa)) message)
  (list :m (octets-to-integer message) :n-bits (* 8 (length message))))

(defmethod encrypt-message ((key rsa-public-key) msg &key (start 0) end oaep &allow-other-keys)
  (let ((nbits (integer-length (rsa-key-modulus key)))
        (m (subseq msg start end)))
    (when oaep
      (setf m (oaep-encode :sha1 m (/ nbits 8))))
    (setf m (octets-to-integer m))
    (make-message :rsa
                  :m (rsa-core m (rsa-key-exponent key) (rsa-key-modulus key))
                  :n-bits nbits)))

(defmethod decrypt-message ((key rsa-private-key) msg &key (start 0) end oaep &allow-other-keys)
  (let* ((nbits (integer-length (rsa-key-modulus key)))
         (message-elements (destructure-message :rsa (subseq msg start end)))
         (m (getf message-elements :m)))
    (if oaep
        (oaep-decode :sha1 (integer-to-octets
                            (rsa-core m (rsa-key-exponent key) (rsa-key-modulus key))
                            :n-bits nbits))
        (integer-to-octets
         (rsa-core m (rsa-key-exponent key) (rsa-key-modulus key))))))

(defmethod make-signature ((kind (eql :rsa)) &key s n-bits &allow-other-keys)
  (unless s
    (error 'missing-signature-parameter
           :kind 'rsa
           :parameter 's
           :description "signature"))
  (unless n-bits
    (error 'missing-signature-parameter
           :kind 'rsa
           :parameter 'n-bits
           :description "modulus size"))
  (integer-to-octets s :n-bits n-bits))

(defmethod destructure-signature ((kind (eql :rsa)) signature)
  (list :s (octets-to-integer signature) :n-bits (* 8 (length signature))))

(defmethod sign-message ((key rsa-private-key) msg &key (start 0) end pss &allow-other-keys)
  (let ((nbits (integer-length (rsa-key-modulus key)))
        (m (subseq msg start end)))
    (when pss
      (setf m (pss-encode :sha1 m (/ nbits 8))))
    (setf m (octets-to-integer m))
    (make-signature :rsa
                    :s (rsa-core m (rsa-key-exponent key) (rsa-key-modulus key))
                    :n-bits nbits)))

(defmethod verify-signature ((key rsa-public-key) msg signature &key (start 0) end pss &allow-other-keys)
  (let ((nbits (integer-length (rsa-key-modulus key))))
    (unless (= (* 8 (length signature)) nbits)
      (error 'invalid-signature-length :kind 'rsa))
    (let* ((signature-elements (destructure-signature :rsa signature))
           (s (getf signature-elements :s)))
      (if pss
          (let ((sig (integer-to-octets (rsa-core s
                                                  (rsa-key-exponent key)
                                                  (rsa-key-modulus key))
                                        :n-bits nbits)))
            (pss-verify :sha1 (subseq msg start end) sig))
          (let ((sig (integer-to-octets (rsa-core s
                                                  (rsa-key-exponent key)
                                                  (rsa-key-modulus key)))))
            (equalp sig (subseq msg start end)))))))
