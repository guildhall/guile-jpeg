;; guile-jpeg
;; Copyright (C) 2014 Andy Wingo <wingo at pobox dot com>

;; This library is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3 of the License, or (at
;; your option) any later version.
;;
;; This library is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this library; if not, see <http://www.gnu.org/licenses/>.

;;; Commentary:
;;
;; A parser for JPEG.
;;
;;; Code:

(define-module (jpeg)
  #:use-module (ice-9 match)
  #:use-module ((srfi srfi-1) #:select (filter-map))
  #:use-module (rnrs bytevectors)
  #:use-module (jpeg exif)
  #:use-module (jpeg array)
  #:use-module (jpeg bit-ports)
  #:use-module (jpeg dct)
  #:use-module (jpeg huffman)
  #:use-module (jpeg jfif)
  #:use-module (jpeg pixbufs)
  #:export (jpeg-dimensions
            jpeg-dimensions-and-exif
            jpeg->rgb
            rgb->jpeg)
  #:re-export (read-jpeg write-jpeg))


(define (jpeg-dimensions jpeg)
  (let* ((jpeg (if (jpeg? jpeg)
                   jpeg
                   (read-jpeg jpeg #:with-body? #f #:with-misc-sections? #f)))
         (frame (jpeg-frame jpeg)))
    (values (frame-x frame)
            (frame-y frame))))

(define (find-exif misc-segments)
  (define (bv-prefix? prefix bv)
    (and (>= (bytevector-length bv) (bytevector-length prefix))
         (let lp ((n 0))
           (or (= n (bytevector-length prefix))
               (and (eqv? (bytevector-u8-ref prefix n)
                          (bytevector-u8-ref bv n))
                    (lp (1+ n)))))))
  (define (bv-suffix bv start)
    (let* ((len (- (bytevector-length bv) start))
           (out (make-bytevector len)))
      (bytevector-copy! bv start out 0 len)
      out))
  (filter-map (lambda (misc)
                (and (= (misc-marker misc) #xffe1) ; APP1
                     (bv-prefix? #vu8(69 120 105 102 0 0) (misc-bytes misc))
                     (parse-exif (bv-suffix (misc-bytes misc) 6))))
              misc-segments))

(define (jpeg-dimensions-and-exif jpeg)
  (let* ((jpeg (if (jpeg? jpeg)
                   jpeg
                   (read-jpeg jpeg #:with-body? #f)))
         (frame (jpeg-frame jpeg)))
    (values (frame-x frame)
            (frame-y frame)
            (match (find-exif (jpeg-misc-segments jpeg))
              (((main thumbnail)) main)
              (((main)) main)
              (_ '())))))

(define* (jpeg->rgb in #:key
                    (argb? #f)
                    (stride-for-width
                     (lambda (width) (* width (if argb? 4 3)))))
  (let ((jpeg (if (jpeg? in) in (read-jpeg in))))
    (yuv->rgb (jpeg->planar-image jpeg)
              #:argb? argb?
              #:stride (stride-for-width (frame-x (jpeg-frame jpeg))))))

(define rgb->jpeg
  (case-lambda*
   ((rgb #:key (samp-x 2) (samp-y 2) (quality 85))
    (planar-image->jpeg (rgb->yuv rgb #:samp-x samp-x #:samp-y samp-y)
                        #:quality quality))
   ((buffer width height #:key (stride (* width 3))
            (samp-x 2) (samp-y 2) (quality 85) (argb? #f))
    (rgb->jpeg (make-interleaved-image width height (if argb? 4 3) stride
                                       buffer)
               #:samp-x samp-x #:samp-y samp-y #:quality quality))))
