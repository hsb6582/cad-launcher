;;; @launcher
;;; 리습: GLC
;;; 분류: 단순기능
;;; 설명: 선 길이로 지반고·관상부레벨 문자 자동 계산
;;; 기능: 지반고·관상부레벨 계산 | GLC | 선 길이/5 + 숫자A → 지반고, 지반고 - 심도 → 관상부레벨
;;; @end
;;; ======================================================================
;;; gl_level_calc.lsp
;;; 기능 : 선(또는 폴리선) 길이를 이용해 "지반고"와 "관상부레벨" 텍스트 값을
;;;        자동으로 계산하여 갱신한다.
;;;
;;; 사용법 : 명령행에 GLC 입력 후 다음 순서로 선택
;;;   1) 선 또는 폴리선 선택   (선A)
;;;   2) 텍스트 선택           (숫자A)   *지반고 계산에 사용됨
;;;   3) 텍스트 선택           (심도)
;;;   4) 텍스트 선택           (관상부레벨)
;;;   5) 텍스트 선택           (지반고)
;;;
;;; 계산식
;;;   지반고(신규)      = 선A 길이 / 5 + 숫자A       -> 소수 둘째자리(**.** )로 반영
;;;   관상부레벨(신규)  = 지반고(신규) - 심도        -> 소수 둘째자리(**.** )로 반영
;;;
;;; 주의사항
;;;   - AutoCAD LT 2024 이상 호환 (문자 읽기/쓰기는 ActiveX 대신 entget/entmod 사용)
;;;   - 심도 텍스트에 "1.50m" 처럼 단위기호가 붙어 있어도 숫자만 추출합니다.
;;;   - TEXT, MTEXT 모두 지원합니다.
;;; ======================================================================

(vl-load-com)

;; ----------------------------------------------------------------------
;; 텍스트 내용 읽기 (TEXT/MTEXT 공통)
;; ----------------------------------------------------------------------
(defun gl:get-text-value (ent)
  (cdr (assoc 1 (entget ent)))
)

;; ----------------------------------------------------------------------
;; 텍스트 내용 쓰기 (TEXT/MTEXT 공통)
;; ----------------------------------------------------------------------
(defun gl:set-text-value (ent val / ed)
  (setq ed (entget ent))
  (entmod (subst (cons 1 val) (assoc 1 ed) ed))
  (entupd ent)
)

;; ----------------------------------------------------------------------
;; 문자열에서 숫자(부호, 소수점 포함)만 추출하여 실수로 반환
;; 예) "심도 1.50 m" -> 1.50
;; ----------------------------------------------------------------------
(defun gl:extract-number (str / i ch result)
  (setq result "")
  (setq i 1)
  (while (<= i (strlen str))
    (setq ch (substr str i 1))
    (if (or (and (>= (ascii ch) 48) (<= (ascii ch) 57))
            (= ch ".")
            (= ch "-"))
      (setq result (strcat result ch))
    )
    (setq i (1+ i))
  )
  (if (= result "")
    0.0
    (atof result)
  )
)

;; ----------------------------------------------------------------------
;; 선/폴리선의 전체 길이 (Line, LWPolyline, Polyline, Arc 등 공통 지원)
;; ----------------------------------------------------------------------
(defun gl:get-curve-length (ent)
  (vlax-curve-getDistAtParam ent (vlax-curve-getEndParam ent))
)

;; ----------------------------------------------------------------------
;; 실수를 "**.**" (소수 둘째자리) 문자열로 변환
;; ----------------------------------------------------------------------
(defun gl:fmt2 (num)
  (rtos num 2 2)
)

;; ----------------------------------------------------------------------
;; 메인 명령
;; ----------------------------------------------------------------------
(defun c:GLC (/ lineEnt numAEnt depthEnt crownEnt groundEnt
                   lineLen depthVal groundVal crownVal
                   groundStr crownStr numAVal)

  (princ "\n=== 지반고 / 관상부레벨 자동계산 ===")

  ;; 1) 선 또는 폴리선 선택 (선A)
  (setq lineEnt (car (entsel "\n선 또는 폴리선을 선택하세요 (선A): ")))
  (if (not lineEnt)
    (progn (princ "\n선택이 취소되었습니다.") (exit))
  )

  ;; 2) 숫자A 텍스트 선택 (지반고 계산에 사용)
  (setq numAEnt (car (entsel "\n숫자A 텍스트를 선택하세요: ")))

  ;; 3) 심도 텍스트 선택
  (setq depthEnt (car (entsel "\n심도 텍스트를 선택하세요: ")))

  ;; 4) 관상부레벨 텍스트 선택
  (setq crownEnt (car (entsel "\n관상부레벨 텍스트를 선택하세요: ")))

  ;; 5) 지반고 텍스트 선택
  (setq groundEnt (car (entsel "\n지반고 텍스트를 선택하세요: ")))

  (if (and lineEnt numAEnt depthEnt crownEnt groundEnt)
    (progn
      ;; 선A 길이
      (setq lineLen (gl:get-curve-length lineEnt))

      ;; 숫자A 값
      (setq numAVal (gl:extract-number (gl:get-text-value numAEnt)))

      ;; 심도 값
      (setq depthVal (gl:extract-number (gl:get-text-value depthEnt)))

      ;; 지반고(신규) = 선A/5 + 숫자A
      (setq groundVal (+ (/ lineLen 5.0) numAVal))
      (setq groundStr (gl:fmt2 groundVal))
      (gl:set-text-value groundEnt groundStr)

      ;; 관상부레벨(신규) = 지반고(신규) - 심도
      (setq crownVal (- groundVal depthVal))
      (setq crownStr (gl:fmt2 crownVal))
      (gl:set-text-value crownEnt crownStr)

      ;; 결과 출력
      (princ (strcat "\n선A 길이         : " (rtos lineLen 2 3)))
      (princ (strcat "\n숫자A 값         : " (rtos numAVal 2 2)))
      (princ (strcat "\n심도             : " (rtos depthVal 2 2)))
      (princ (strcat "\n계산된 지반고     : " groundStr))
      (princ (strcat "\n계산된 관상부레벨 : " crownStr))
    )
    (princ "\n필요한 객체가 모두 선택되지 않아 계산을 중단합니다.")
  )
  (princ)
)

(princ "\nGLC 명령이 로드되었습니다. 실행하려면 GLC 를 입력하세요.")
(princ)
