;;; @launcher
;;; 리습: SUM
;;; 분류: 단순기능
;;; 설명: 선택한 문자의 숫자·연장(m) 합계
;;; 기능: 문자 숫자 합계 | SUM | 선택한 문자(123.45, 2.9m, 63mm-4M)의 연장을 합산
;;; @end
;;; ============================================================
;;; SUM.LSP
;;; 선택한 텍스트(TEXT, MTEXT)의 값을 합산하는 통합 명령
;;;
;;; 아래 형태를 모두 지원합니다 :
;;;   1) 순수 숫자         예) 123.45, 2.9
;;;   2) 관경-연장 형태     예) 63mm-4M, 100mm-12.5m  (관경은 무시, 연장만 사용)
;;;   3) 단독 단위 형태     예) 2.9m
;;;
;;; 처리 기준 :
;;;   - "-" 가 있으면 뒤쪽 부분만 사용 (관경 제외)
;;;   - "-" 가 없으면 텍스트 전체를 사용
;;;   - 그 안에서 앞쪽 숫자(0-9, .) 와 뒤쪽 단위 문자를 분리
;;;   - 단위가 없거나(빈 문자열) "m"/"M" 이면 -> 합산 대상
;;;   - 단위가 그 외(EA, 개, A 등)면          -> 제외(단위불일치) 목록
;;;   - 숫자 자체가 없거나 인식 불가하면       -> 오류 목록
;;;
;;; 사용법 : 명령행에 SUM 입력 -> 텍스트 객체들 선택 -> Enter
;;; ============================================================

(defun c:SUM (/ ss i ent edata str clean dashPos rest numPart unitPart
              ch j len total validCount errList skipList e msg val)

  (setq ss (ssget '((0 . "TEXT,MTEXT"))))

  (if (not ss)
    (progn
      (princ "\n[SUM] 선택된 텍스트 객체가 없습니다.")
      (princ)
    )
    (progn
      (setq total      0.0
            validCount 0
            errList    '()   ; 형식/숫자 오류
            skipList   '()   ; 형식은 맞지만 단위가 m 이 아닌 텍스트
            i          0
      )

      (while (< i (sslength ss))
        (setq ent   (ssname ss i)
              edata (entget ent)
              str   (cdr (assoc 1 edata))
        )

        ;; MTEXT 서식 코드 제거 + 공백 제거
        (setq clean (mtext-clean str))
        (setq clean (vl-string-trim " " clean))

        ;; "-" 가 있으면 뒤쪽 문자열, 없으면 전체 문자열을 대상으로 파싱
        ;; 예) "63mm-4M" -> "4M" / "2.9m" -> "2.9m" / "123.45" -> "123.45"
        (setq dashPos (vl-string-search "-" clean))
        (if dashPos
          (setq rest (substr clean (+ dashPos 2)))
          (setq rest clean)
        )

        ;; 앞에서부터 숫자(0-9, .)만 모아 numPart, 나머지는 unitPart
        (setq numPart ""
              unitPart ""
              j 1
              len (strlen rest)
        )
        (while (<= j len)
          (setq ch (substr rest j 1))
          (if (or (and (>= (ascii ch) 48) (<= (ascii ch) 57)) (= ch "."))
            (setq numPart (strcat numPart ch))
            (setq unitPart (strcat unitPart ch))
          )
          (setq j (1+ j))
        )
        (setq unitPart (vl-string-trim " " unitPart))

        (cond
          ;; 숫자 부분이 비어있으면 형식오류
          ((= numPart "")
           (setq errList (cons (list (cdr (assoc 5 edata)) str "형식오류(숫자 없음)") errList))
          )
          ;; 단위가 없거나(순수 숫자) "m"/"M" 이면 -> 합산 대상
          ((or (= unitPart "") (= (strcase unitPart) "M"))
           (setq val (vl-catch-all-apply 'distof (list numPart 2)))
           (if (and val (not (vl-catch-all-error-p val)) (numberp val))
             (progn
               (setq total      (+ total val)
                     validCount (1+ validCount)
               )
             )
             (setq errList (cons (list (cdr (assoc 5 edata)) str "숫자 인식 불가") errList))
           )
          )
          ;; 그 외 단위 -> 제외(단위불일치) 목록
          (T
           (setq skipList (cons (list (cdr (assoc 5 edata)) str unitPart) skipList))
          )
        )

        (setq i (1+ i))
      )

      (setq errList  (reverse errList))
      (setq skipList (reverse skipList))

      ;; ---------------- 결과 출력 ----------------
      (setq msg
        (strcat
          "■ SUM 결과\n"
          "----------------------------------\n"
          "선택한 텍스트 개수   : " (itoa (sslength ss)) "\n"
          "합산된 텍스트 개수   : " (itoa validCount) "\n"
          "합계                : " (rtos total 2 2) " m\n"
        )
      )

      (if skipList
        (progn
          (setq msg
            (strcat msg
              "----------------------------------\n"
              "※ 단위가 m 이 아니어서 제외된 텍스트 : " (itoa (length skipList)) "건\n"
            )
          )
          (foreach e skipList
            (setq msg
              (strcat msg
                "  - \"" (cadr e) "\"  (단위: " (caddr e) ")  (Handle: " (car e) ")\n"
              )
            )
          )
        )
      )

      (if errList
        (progn
          (setq msg
            (strcat msg
              "----------------------------------\n"
              "※ 형식/숫자 오류로 제외된 텍스트 : " (itoa (length errList)) "건\n"
            )
          )
          (foreach e errList
            (setq msg
              (strcat msg
                "  - \"" (cadr e) "\"  (" (caddr e) ")  (Handle: " (car e) ")\n"
              )
            )
          )
        )
      )

      (if (and (not skipList) (not errList))
        (setq msg (strcat msg "모든 텍스트가 정상적으로 인식되어 합산되었습니다.\n"))
      )

      ;; 명령행 출력
      (princ (strcat "\n" msg))

      ;; 팝업 요약
      (alert msg)

      (princ)
    )
  )
  (princ)
)

;; --------------------------------------------------------------
;; MTEXT 서식 코드 제거 함수
;; --------------------------------------------------------------
(defun mtext-clean (s / )
  (if (not s)
    ""
    (progn
      (setq s (vl-string-subst " " "\\P" s))
      (setq s (vl-string-subst "" "{" s))
      (setq s (vl-string-subst "" "}" s))
      s
    )
  )
)

(princ "\nSUM 명령이 로드되었습니다. (SUM + SUM2 통합) 사용하려면 명령행에 SUM 을 입력하세요.")
(princ)
