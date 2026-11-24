;;; ============================================================
;;; launcher_opt.lsp - CAD 런처 옵션 파일 읽기 헬퍼 (AutoCAD LT 2024+)
;;; 옵션 파일 : %TEMP%\cad_launcher_opt.txt  (key=value, 첫 줄 _CMD=명령ID)
;;;
;;; (LO:take "ID")       ; 런처에서 ID 명령으로 실행된 경우 옵션 로드 후 파일 삭제 → T
;;;                      ; 직접 입력해서 실행한 경우 nil (→ 기존 프롬프트 방식 사용)
;;; (LO:get  "key" 기본) ; 문자열
;;; (LO:num  "key" 기본) ; 실수
;;; (LO:int  "key" 기본) ; 정수
;;; (LO:bool "key" 기본) ; "1" → T
;;; LO_SHOW              ; 현재 옵션 파일 내용 확인 (디버그용)
;;; ============================================================

(defun LO:path () (strcat (getenv "TEMP") "\\cad_launcher_opt.txt"))

(defun LO:load (/ f line pos lst)
  (setq *LO-OPTS* nil)
  (if (and (findfile (LO:path)) (setq f (open (LO:path) "r")))
    (progn
      (while (setq line (read-line f))
        (if (setq pos (vl-string-search "=" line))
          (setq lst (cons (cons (strcase (vl-string-trim " \t" (substr line 1 pos)))
                                (vl-string-trim " \t" (substr line (+ pos 2))))
                          lst))))
      (close f)
      (setq *LO-OPTS* (reverse lst))))
  *LO-OPTS*)

(defun LO:get (key def / a)
  (if (setq a (assoc (strcase key) *LO-OPTS*)) (cdr a) def))

(defun LO:num (key def / v)
  (setq v (LO:get key nil))
  (if (and v (distof v)) (distof v) def))

(defun LO:int (key def) (fix (LO:num key def)))

(defun LO:bool (key def / v)
  (setq v (LO:get key nil))
  (if v (= v "1") def))

(defun LO:take (id)
  (LO:load)
  (if (and *LO-OPTS* (= (strcase (LO:get "_CMD" "")) (strcase id)))
    (progn (vl-file-delete (LO:path)) T)
    (progn (setq *LO-OPTS* nil) nil)))

(defun c:LO_SHOW (/ lst)
  (if (setq lst (LO:load))
    (foreach a lst (princ (strcat "\n  " (car a) " = " (cdr a))))
    (princ "\n옵션 파일 없음"))
  (princ))

(princ)
