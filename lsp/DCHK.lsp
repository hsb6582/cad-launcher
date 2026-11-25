;;; @launcher
;;; 리습: DCHK
;;; 분류: 도면 검수 (개발 중)
;;; 설명: [개발 중] 자재내역·종단·평면·횡단 자재/수량을 도엽별로 대조
;;; 기능: [개발 중] 설계도면 종합 검수 | DCHK | 도곽마다 자재내역·종단·평면·횡단 수량 대조, 불일치 표시 + CSV
;;; 기능: [개발 중] 검수 표시 지우기 | DCHKDEL | DCHK 가 그린 검수 표시(0검수 레이어) 삭제
;;; @end
;;; ============================================================
;;; DCHK.lsp  -  설계도면 종합 검수
;;;   자재내역 / 종단면도 / 평면도 / 횡단면도의 자재·수량을 도엽별로 대조
;;; AutoCAD LT 2026 호환 (ActiveX 미사용, entget/ssget 기반)
;;;
;;; 명령어:
;;;   DCHK     - 전체 도곽을 검수. 불일치 위치에 표시를 그리고 CSV로 저장
;;;   DCHKDEL  - DCHK가 그린 검수 표시(불일치·확인·이상없음 이력, 모두 "0검수" 레이어)를 삭제
;;;              (이전 버전의 "0검수이력" 레이어 표시도 함께 삭제)
;;;
;;; 대조 규칙 (도엽 1장 = FORM 도곽 1개):
;;;   직관        자재내역 = 종단 관로 라벨 길이 "(140.0M)" = 종단 누적거리(끝-시작)
;;;               평면도 신설관 폴리선 길이는 참고(반올림 오차 허용, "확인" 등급)
;;;   연결관      자재내역 = 종단 상단 라벨 "연결관L=1.5m" 합
;;;   ELBOW       자재내역 = 종단 상단 라벨 "ELBOW90%%Dx2EA" 합 = Fitting's 행 "200A-90%%Dx2" 합
;;;   TEE/S.TEE   자재내역 = Fitting's 행 개수 (상단 라벨 개수는 참고값으로만 기록)
;;;   CAP/VALVE   자재내역 = 종단 상단 라벨 개수
;;   RED         자재내역 = 종단 상단 라벨 "RED 110mmx63mm" 개수
;;   63mm 소구경 S.TEE/TEE(x63)는 Fitting 행에 없으므로 종단 상단 라벨 개수와 대조
;;   63mm 인입관 자재내역 = 종단 "63mm-4M" 합 = 평면 "LP 63mm PE(4m)" 합
;;   63mm 엘보    자재내역 = 평면 63el 블록 개수
;;   63mm 캡 수  자재내역 = S.TEE + TEE(x63) + RED(x63) 수량 합 (표 내부 점검, "확인" 등급)
;;   한 도엽에 종단 그래프가 여러 개면("공사시점" 문자 여러 개) 구간별 관경으로 따로 계산
;;;   LINE MARK   자재내역 = 평면도 라인마크 블록 개수
;;;   TEST BOX    자재내역 = 평면도 T.B 블록 개수
;;;   표지판      자재내역 = 평면도 표지판 블록 + "표" 문자 개수 ("확인" 등급)
;;;   횡단면도    관종·관경 표기가 종단/평면 관로명과 같은지,
;;;               심도 값이 종단 EXCAVATION HEIGHT 행에 있는 값인지
;;;
;;; 평면도 제외 규칙 (대조에서 빼고 CSV "평면 제외" 행에 기록):
;;;   - 히든 선종류(HIDDEN)로 그려진 신설관 = 옆 도엽으로 이어지는 선
;;;   - 63mm 신설관: 히든 관에서 분기했거나, 신설관과 이어지지 않았거나(끝점 접촉)
;;;     인근에 신설관이 없으면 제외. 그 선 주변의 캡/라인마크/인입관 문구도 같이 제외
;;; 종단 표 점검 (측점 열 단위, 누적거리(ADDITIONAL DISTANCE) 행 기준):
;;;   거리        DISTANCE 행 값 = 이전 측점과의 누적거리 차이 (구간 첫 측점은 0)
;;;   레벨        NATURAL GROUND ELEVATION(지반고) - TOP OF PIPE ELEVATION(관상고) = EXCAVATION HEIGHT(심도)
;;;   측점번호    NO.n = n x 간격, +x.x = 누적거리 - 직전 NO 위치, 간격마다 NO.n 측점이 있는지
;;; 63mm 엘보·연결관 (종단에 표기되지 않음) - 평면도의 DETAIL "A/B/C" 표기와 디테일 도면으로 검수:
;;;   디테일 도면에서 63mm 배관의 EL90 개수와 연결관(수직 0.5M 구간) 길이를 읽고,
;;;   자재내역 수량이 "디테일을 N개소에 적용한 합"으로 설명되는지 확인.
;;;   디테일과 유사한 조건의 분기는 같은 디테일로 갈음하므로 적용 횟수를 바꿔 가며 맞는 조합을 찾고
;;;   (평면에 표기된 디테일은 최소 1회, 총 적용 횟수는 63mm 분기 수 이하),
;;;   디테일 밖 평면 63el 블록은 엘보 추가분(0 ~ 블록 수)으로 허용
;;; 판정: 불일치(빨강) / 확인(노랑) / OK / -(대조 대상 없음)
;;; 이상 없는 항목은 자재내역 우측(확인 문구와 같은 자리)에 초록 글씨로
;;;   "[이상없음] 항목: 자재 N = 라벨 N = 평면 N" 처럼 무엇과 무엇을 비교했는지 남김
;;;   (맨 위에 날짜·시간 요약). "0검수" 레이어(불일치 표시와 같은 레이어). DCHKDEL로 함께 삭제
;;; 63mm 이음관·엘보는 종단면도에 표기되지 않으므로 평면도로 검수:
;;;   63mm 신설관 끝점이 큰 관 중간에 닿음 -> TEE/S.TEE (큰관 x 63), 큰 관 끝에 닿음 -> RED (처음 1개),
;;;   같은 끝에 63mm 선이 더 있으면 TEE, 다른 63mm 선 중간에 닿음 -> TEE 63x63
;;;   63mm 엘보 = LPPE63A라인마크 63el 블록 개수 (신설관 63mm 선의 90° 꺾임 개수도 참고)
;;; 결과: 도면 폴더\DCHK\검수결과.csv
;;; 합산 산식은 모두 도면 왼쪽 -> 오른쪽 순서로 기록
;;; ============================================================

;; vl-remove-if 등 일부 함수용 (entget 기반이라 ActiveX 객체는 쓰지 않음)
(vl-load-com)

;; ---------- 설정 (프로젝트마다 레이어명이 다르면 여기만 수정) ----------
(setq *dchk-form-block*   "FORM")            ; 도곽 블록 이름
(setq *dchk-form-layer*   "FORM_")           ; 도곽 블록이 없을 때 쓰는 테두리 레이어
(setq *dchk-form-w*       396.9)             ; 도곽 가로 (블록 축척 1 기준)
(setq *dchk-form-h*       273.98)            ; 도곽 세로
(setq *dchk-lay-prof*     "Q-종단TEXT")      ; 종단 상단 라벨 (ELBOW/TEE/CAP/VALVE/연결관/관로 라벨)
(setq *dchk-lay-fit*      "Q-종단엘보방향")  ; 종단 Fitting's 행
(setq *dchk-lay-sta*      "Q-종단측점")      ; 종단 측점 표 숫자 (심도/누적거리 등)
(setq *dchk-lay-cross*    "횡단*")           ; 횡단면도 (문자·블록)
(setq *dchk-lay-pipename* "관로명")          ; 평면도 관로명 문자
(setq *dchk-lay-pipe*     "*신설관*")        ; 평면도 신설관 폴리선
(setq *dchk-lay-linemark* "*라인마크*")      ; 평면도 라인마크 블록 (LPPE63A라인마크 포함)
(setq *dchk-lay-sign*     "표지판(신설)")    ; 평면도 표지판 블록 레이어
(setq *dchk-lay-tb*       "TB(신설)")        ; 평면도 T.B 블록
(setq *dchk-lay-inlet*    "LPPE*관로명")     ; 평면도 63mm 인입관 길이 문자 " LP 63mm PE(4m)"
(setq *dchk-small-dia*    63.0)              ; 이 관경 이하가 들어간 이음관(TEE/S.TEE/RED/엘보)은 소구경 분기로 봄
(setq *dchk-mark-layer*   "0검수")           ; 검수 표시 레이어
(setq *dchk-qty-tol*      0.05)              ; 수량 비교 허용오차
(setq *dchk-plan-tol*     0.5)               ; 평면 폴리선 길이 비교 허용오차(M)
(setq *dchk-depth-tol*    0.005)             ; 심도 비교 허용오차(M)
(setq *dchk-row-dy*       -1.25)             ; 종단 표 행 제목 문자 대비 값 문자의 Y 오프셋
(setq *dchk-row-tol*      2.5)               ; 종단 표 한 행으로 볼 Y 범위(±)
(setq *dchk-note-h*       1.5)               ; 검수 메모 문자 높이
(setq *dchk-lay-detail*   "디테일TEXT")      ; 디테일 도면의 문자 (제목 DETAIL "A", 관경 라벨, EL90, 0.5M 등)
(setq *dchk-lay-detpipe*  "Y-상세도라인")    ; 디테일 도면의 배관 폴리선
(setq *dchk-lay-detplan*  "Y-평면상세도글씨") ; 평면도의 상세도 표기 문자 DETAIL "A"
(setq *dchk-sta-pitch*    20.0)              ; 종단 측점(NO.n) 간격(M)
(setq *dchk-dist-tol*     0.015)             ; 거리/누적거리 비교 허용오차(M)
(setq *dchk-lvl-tol*      0.011)             ; 지반고-관상고=심도 허용오차(M, 값이 소수 2자리 반올림이라 0.01 허용)
(setq *dchk-hist-layer*   "0검수")           ; 이상없음 이력도 같은 레이어 (초록 글씨)
(setq *dchk-hidden-lt*    "*HIDDEN*,*은선*")  ; 이 선종류면 히든 처리된 선으로 봄 (wcmatch 패턴)
(setq *dchk-lay-small*    "LPPE*")           ; 63mm 계열 평면 레이어 (라인마크/CAP/관로명)
(setq *dchk-lay-cap63*    "LPPE*CAP")        ; 평면 63mm 캡 폴리선 레이어
(setq *dchk-conn-tol*     0.2)               ; 신설관끼리 이어졌다고 볼 끝점 간격(도면단위)
(setq *dchk-r-cap*        2.0)               ; 캡이 신설관에서 이 거리 안에 있어야 함
(setq *dchk-r-mark63*     4.0)               ; 63mm 라인마크가 신설관에서 이 거리 안에 있어야 함
(setq *dchk-r-label63*    12.0)              ; 63mm 인입관 문구가 신설관에서 이 거리 안에 있어야 함
(setq *dchk-r-mark*       3.0)               ; 그 외 라인마크: 이 거리 안 가장 가까운 선이 제외된 선이면 제외

;; ---------- 실행 중 쓰는 전역 ----------
(setq *dchk-frames* nil)   ; ((ox oy w h) ...)
(setq *dchk-ent* nil)      ; 현재 도곽의 수량 항목 ((key src x val) ...)
(setq *dchk-names* nil)    ; ((key kind spec) ...)
(setq *dchk-rowy* nil)     ; ((key . 자재표 행 Y) ...)
(setq *dchk-rows* nil)     ; CSV 행 누적
(setq *dchk-nbad* 0)
(setq *dchk-nwarn* 0)
(setq *dchk-style* nil)    ; 검수 메모에 쓸 문자 스타일 (도면의 한글 문자에서 가져옴)
(setq *dchk-nokf* 0)       ; 현재 도곽의 OK 항목 수

;; ============================================================
;; 문자열/숫자 유틸
;; ============================================================
(defun dchk-nz (s / n i c out)
  ;; 공백 제거 + 대문자 통일
  (if (/= (type s) 'STR) (setq s ""))
  (setq n (strlen s) i 1 out "")
  (while (<= i n)
    (setq c (substr s i 1))
    (if (and (/= c " ") (/= c "\t"))
      (setq out (strcat out (strcase c)))
    )
    (setq i (1+ i))
  )
  out
)

(defun dchk-digit-p (c / a)
  (setq a (ascii c))
  (and (>= a 48) (<= a 57))
)

(defun dchk-nums (s / n i c cur res dot)
  ;; 문자열 안의 숫자(소수 포함)를 순서대로 실수 리스트로 반환
  ;; 예: "MP200APLP(140.0M)" -> (200.0 140.0), "S.TEE300AX200A" -> (300.0 200.0)
  (setq n (strlen s) i 1 cur "" res nil dot nil)
  (while (<= i n)
    (setq c (substr s i 1))
    (cond
      ((dchk-digit-p c) (setq cur (strcat cur c)))
      ((and (= c ".") (/= cur "") (not dot) (< i n) (dchk-digit-p (substr s (1+ i) 1)))
       (setq cur (strcat cur c) dot T)
      )
      (T
       (if (/= cur "") (setq res (cons (atof cur) res)))
       (setq cur "" dot nil)
      )
    )
    (setq i (1+ i))
  )
  (if (/= cur "") (setq res (cons (atof cur) res)))
  (reverse res)
)

(defun dchk-pure-num (s allow-dot / n i ok c dg)
  ;; 숫자(와 소수점)만으로 된 문자열인지
  (setq n (strlen s) i 1 ok (> n 0) dg nil)
  (while (and ok (<= i n))
    (setq c (substr s i 1))
    (cond
      ((dchk-digit-p c) (setq dg T))
      ((and allow-dot (= c ".")) nil)
      (T (setq ok nil))
    )
    (setq i (1+ i))
  )
  (and ok dg)
)

(defun dchk-has (s sub)
  (if (vl-string-search sub s) T nil)
)

(defun dchk-round (x)
  (fix (+ x 0.5))
)

(defun dchk-fmt (x / s)
  ;; 숫자를 군더더기 없이 문자열로 (140.0 -> "140", 1.50 -> "1.5")
  (cond
    ((null x) "")
    ((< (abs (- x (dchk-round x))) 0.000001) (itoa (dchk-round x)))
    (T
     (setq s (rtos x 2 2))
     (if (vl-string-search "." s)
       (progn
         (while (= (substr s (strlen s) 1) "0")
           (setq s (substr s 1 (1- (strlen s))))
         )
         (if (= (substr s (strlen s) 1) ".")
           (setq s (substr s 1 (1- (strlen s))))
         )
       )
     )
     s
    )
  )
)

(defun dchk-eq (a b)
  (< (abs (- a b)) *dchk-qty-tol*)
)

(defun dchk-sort (lst less / res it out placed r)
  ;; 안정 삽입 정렬 (vl-sort는 같은 값을 지워버릴 수 있어 쓰지 않음)
  (setq res nil)
  (foreach it lst
    (setq out nil placed nil)
    (foreach r res
      (if (and (not placed) (apply less (list it r)))
        (setq out (cons it out) placed T)
      )
      (setq out (cons r out))
    )
    (if (not placed) (setq out (cons it out)))
    (setq res (reverse out))
  )
  res
)

(defun dchk-uniq (lst / res v)
  (setq res nil)
  (foreach v lst
    (if (not (member v res)) (setq res (cons v res)))
  )
  (reverse res)
)

(defun dchk-join (lst sep / s v)
  (setq s "")
  (foreach v lst
    (setq s (if (= s "") v (strcat s sep v)))
  )
  s
)

(defun dchk-subsum (lst target tol)
  ;; lst의 일부(또는 전부)를 더해서 target을 만들 수 있는지
  (cond
    ((< (abs target) tol) T)
    ((null lst) nil)
    ((< target 0.0) nil)
    (T
     (or (dchk-subsum (cdr lst) (- target (car lst)) tol)
         (dchk-subsum (cdr lst) target tol)
     )
    )
  )
)

(defun dchk-csv-esc (s)
  (if (or (vl-string-search "," s) (vl-string-search "\"" s))
    (strcat "\"" s "\"")
    s
  )
)

;; ============================================================
;; 도면 요소 읽기
;; ============================================================
(defun dchk-textpos (ed / j72 j73 pt11 pt10)
  ;; 정렬이 기본(좌하단)이 아니면 실제 위치는 그룹 11
  (setq pt10 (cdr (assoc 10 ed)))
  (if (= (cdr (assoc 0 ed)) "MTEXT")
    pt10
    (progn
      (setq j72 (cdr (assoc 72 ed)) j73 (cdr (assoc 73 ed)) pt11 (cdr (assoc 11 ed)))
      (if (null j72) (setq j72 0))
      (if (null j73) (setq j73 0))
      (if (and pt11 (or (/= j72 0) (/= j73 0))) pt11 pt10)
    )
  )
)

(defun dchk-pl-data (ed / pts d closed plen a b c th i)
  ;; LWPOLYLINE -> (첫점X 첫점Y 길이). 호(bulge) 구간 포함
  (setq pts nil)
  (foreach d ed
    (cond
      ((= (car d) 10) (setq pts (cons (list (cadr d) (caddr d) 0.0) pts)))
      ((and (= (car d) 42) pts)
       (setq pts (cons (list (car (car pts)) (cadr (car pts)) (cdr d)) (cdr pts)))
      )
    )
  )
  (setq pts (reverse pts))
  (if pts
    (progn
      (setq closed (= 1 (logand 1 (if (assoc 70 ed) (cdr (assoc 70 ed)) 0))))
      (setq a (car pts))
      (if closed (setq pts (append pts (list a))))
      (setq plen 0.0 i 0)
      (while (< i (1- (length pts)))
        (setq a (nth i pts) b (nth (1+ i) pts))
        (setq c (distance (list (car a) (cadr a)) (list (car b) (cadr b))))
        (if (and (/= (caddr a) 0.0) (> c 0.0))
          (progn
            (setq th (* 4.0 (atan (abs (caddr a)))))
            (setq plen (+ plen (* (/ c (* 2.0 (sin (/ th 2.0)))) th)))
          )
          (setq plen (+ plen c))
        )
        (setq i (1+ i))
      )
      (list (car (car pts)) (cadr (car pts)) plen
            (mapcar '(lambda (q) (list (car q) (cadr q))) pts))
    )
    nil
  )
)

(defun dchk-pl-bbox (ed / xs ys d)
  (setq xs nil ys nil)
  (foreach d ed
    (if (= (car d) 10)
      (setq xs (cons (cadr d) xs) ys (cons (caddr d) ys))
    )
  )
  (if xs
    (list (apply 'min xs) (apply 'min ys)
          (- (apply 'max xs) (apply 'min xs)) (- (apply 'max ys) (apply 'min ys)))
    nil
  )
)

(defun dchk-block-nums (bname / e ed res s)
  ;; 블록 정의 안의 문자 중 숫자만으로 된 값들 (횡단면도 심도 블록용)
  (setq res nil)
  (setq e (tblobjname "BLOCK" bname))
  (while (and e (setq e (entnext e)))
    (setq ed (entget e))
    (cond
      ((= (cdr (assoc 0 ed)) "ENDBLK") (setq e nil))
      ((member (cdr (assoc 0 ed)) '("TEXT" "MTEXT"))
       (setq s (dchk-nz (cdr (assoc 1 ed))))
       (if (dchk-pure-num s T) (setq res (cons (atof s) res)))
      )
    )
  )
  res
)

;; ---------- 도곽 ----------
(defun dchk-collect-frames (/ ss i ed pt sx sy frames bb res fr fr2 dup)
  (setq frames nil)
  (setq ss (ssget "_X" (list (cons 0 "INSERT") (cons 2 *dchk-form-block*))))
  (if ss
    (progn
      (setq i 0)
      (while (< i (sslength ss))
        (setq ed (entget (ssname ss i)))
        (setq pt (cdr (assoc 10 ed)))
        (setq sx (if (assoc 41 ed) (abs (cdr (assoc 41 ed))) 1.0))
        (setq sy (if (assoc 42 ed) (abs (cdr (assoc 42 ed))) 1.0))
        (setq frames (cons (list (car pt) (cadr pt) (* *dchk-form-w* sx) (* *dchk-form-h* sy)) frames))
        (setq i (1+ i))
      )
    )
  )
  ;; FORM 블록이 없으면 FORM_ 레이어의 큰 사각 폴리선을 도곽으로 사용
  (if (null frames)
    (progn
      (setq ss (ssget "_X" (list (cons 0 "LWPOLYLINE") (cons 8 *dchk-form-layer*))))
      (if ss
        (progn
          (setq i 0)
          (while (< i (sslength ss))
            (setq bb (dchk-pl-bbox (entget (ssname ss i))))
            (if (and bb (> (caddr bb) (* 0.9 *dchk-form-w*)))
              (setq frames (cons bb frames))
            )
            (setq i (1+ i))
          )
        )
      )
    )
  )
  ;; 같은 자리에 중복 삽입된 도곽 제거 (0.5 이내)
  (setq res nil)
  (foreach fr frames
    (setq dup nil)
    (foreach fr2 res
      (if (< (distance (list (car fr) (cadr fr)) (list (car fr2) (cadr fr2))) 0.5)
        (setq dup T)
      )
    )
    (if (not dup) (setq res (cons fr res)))
  )
  ;; 위쪽 행부터, 행 안에서는 왼쪽 -> 오른쪽
  (dchk-sort res
    '(lambda (a b)
       (if (> (abs (- (cadr a) (cadr b))) 100.0)
         (> (cadr a) (cadr b))
         (< (car a) (car b))
       )
     )
  )
)

(defun dchk-find-frame (x y / i res fr)
  (setq i 0 res nil)
  (foreach fr *dchk-frames*
    (if (and (null res)
             (>= x (car fr)) (<= x (+ (car fr) (caddr fr)))
             (>= y (cadr fr)) (<= y (+ (cadr fr) (cadddr fr))))
      (setq res i)
    )
    (setq i (1+ i))
  )
  res
)

;; ---------- 전체 스캔: 도곽 안에 있는 문자/블록/신설관 폴리선만 수집 ----------
;; 반환 항목: (도곽번호 종류 X Y 값 레이어)   종류 "T"=문자 "I"=블록 "P"=폴리선(값=길이)
(defun dchk-scan (/ ss i n ed p fi s items v)
  (setq items nil)
  (setq ss (ssget "_X" '((0 . "TEXT,MTEXT") (410 . "Model"))))
  (if ss
    (progn
      (setq i 0 n (sslength ss))
      (while (< i n)
        (setq ed (entget (ssname ss i)))
        (setq p (dchk-textpos ed))
        (setq fi (dchk-find-frame (car p) (cadr p)))
        (if fi
          (progn
            (setq s (cdr (assoc 1 ed)))
            (if (/= (type s) 'STR) (setq s ""))
            ;; 한글이 깨지지 않도록, 도곽 안 한글 문자의 스타일을 메모용으로 기억
            (if (and (null *dchk-style*) (/= s "") (> (ascii s) 127) (assoc 7 ed))
              (setq *dchk-style* (cdr (assoc 7 ed)))
            )
            (setq items (cons (list fi "T" (car p) (cadr p) s (cdr (assoc 8 ed))) items))
          )
        )
        (setq i (1+ i))
      )
    )
  )
  (setq ss (ssget "_X" '((0 . "INSERT") (410 . "Model"))))
  (if ss
    (progn
      (setq i 0 n (sslength ss))
      (while (< i n)
        (setq ed (entget (ssname ss i)))
        (setq p (cdr (assoc 10 ed)))
        (setq fi (dchk-find-frame (car p) (cadr p)))
        (if fi
          (setq items (cons (list fi "I" (car p) (cadr p) (cdr (assoc 2 ed)) (cdr (assoc 8 ed))) items))
        )
        (setq i (1+ i))
      )
    )
  )
  (setq ss (ssget "_X" (list (cons 0 "LWPOLYLINE") (cons 8 *dchk-lay-pipe*) (cons 410 "Model"))))
  (if ss
    (progn
      (setq i 0 n (sslength ss))
      (while (< i n)
        (setq ed (entget (ssname ss i)))
        (setq v (dchk-pl-data ed))
        (if v
          (progn
            (setq fi (dchk-find-frame (car v) (cadr v)))
            (if fi
              (setq items (cons (list fi "P" (car v) (cadr v) (caddr v) (cdr (assoc 8 ed))
                                      (dchk-hidden-p ed) (cadddr v))
                                items))
            )
          )
        )
        (setq i (1+ i))
      )
    )
  )
  ;; 디테일 도면 배관 폴리선: (도곽 "Y" X Y 길이 레이어 히든여부 점목록)
  (setq ss (ssget "_X" (list (cons 0 "LWPOLYLINE") (cons 8 *dchk-lay-detpipe*) (cons 410 "Model"))))
  (if ss
    (progn
      (setq i 0 n (sslength ss))
      (while (< i n)
        (setq ed (entget (ssname ss i)))
        (setq v (dchk-pl-data ed))
        (if v
          (progn
            (setq fi (dchk-find-frame (car v) (cadr v)))
            (if fi
              (setq items (cons (list fi "Y" (car v) (cadr v) (caddr v) (cdr (assoc 8 ed))
                                      (dchk-hidden-p ed) (cadddr v))
                                items))
            )
          )
        )
        (setq i (1+ i))
      )
    )
  )
  ;; 63mm 캡 폴리선: (도곽 "C" X Y 0 레이어 히든여부 점목록)
  (setq ss (ssget "_X" (list (cons 0 "LWPOLYLINE") (cons 8 *dchk-lay-cap63*) (cons 410 "Model"))))
  (if ss
    (progn
      (setq i 0 n (sslength ss))
      (while (< i n)
        (setq ed (entget (ssname ss i)))
        (setq v (dchk-pl-data ed))
        (if v
          (progn
            (setq fi (dchk-find-frame (car v) (cadr v)))
            (if fi
              (setq items (cons (list fi "C" (car v) (cadr v) 0.0 (cdr (assoc 8 ed))
                                      (dchk-hidden-p ed) (cadddr v))
                                items))
            )
          )
        )
        (setq i (1+ i))
      )
    )
  )
  items
)

;; ============================================================
;; 수량 항목 누적 (도곽 1개 단위)
;; ============================================================
(defun dchk-key (kind sizes / spec key a b)
  ;; 항목 키 "종류|규격" 생성 + 표시용 이름 등록
  (setq spec
    (cond
      ((null sizes) "")
      ((= (length sizes) 1) (itoa (car sizes)))
      (T
       (setq a (max (car sizes) (cadr sizes)) b (min (car sizes) (cadr sizes)))
       (strcat (itoa a) "x" (itoa b))
      )
    )
  )
  (setq key (strcat kind "|" spec))
  (if (not (assoc key *dchk-names*))
    (setq *dchk-names* (cons (list key kind spec) *dchk-names*))
  )
  key
)

(defun dchk-add (key src x val)
  (setq *dchk-ent* (cons (list key src x val) *dchk-ent*))
)

(defun dchk-ints (reals)
  (mapcar 'dchk-round reals)
)

(defun dchk-pair (sz)
  ;; TEE류 규격: 숫자가 하나뿐이면 같은 관경 2개로 봄
  (cond
    ((null sz) nil)
    ((null (cdr sz)) (list (car sz) (car sz)))
    (T (list (car sz) (cadr sz)))
  )
)

(defun dchk-first (sz)
  (if sz (list (car sz)) nil)
)

(defun dchk-mat-key (name spec / n sz an)
  ;; 자재내역 품명/규격 -> 항목 키. 대조 대상이 아니면 nil
  (setq n (dchk-nz name))
  (setq sz (dchk-ints (dchk-nums (dchk-nz spec))))
  (cond
    ((dchk-has n "직관") (dchk-key "직관" (dchk-first sz)))
    ((dchk-has n "연결관") (dchk-key "연결관" (dchk-first sz)))
    ((dchk-has n "인입관") (dchk-key "인입관" (dchk-first sz)))
    ((or (dchk-has n "REDUCER") (= n "RED") (= n "R/D") (= n "R.D")) (dchk-key "RED" (dchk-pair sz)))
    ((dchk-has n "ELBOW")
     (setq an (dchk-ints (dchk-nums n)))
     (dchk-key (strcat "ELBOW" (if an (itoa (car an)) "")) (dchk-first sz))
    )
    ((or (dchk-has n "S.TEE") (dchk-has n "STEE")) (dchk-key "S.TEE" (dchk-pair sz)))
    ((dchk-has n "TEE") (dchk-key "TEE" (dchk-pair sz)))
    ((dchk-has n "CAP") (dchk-key "CAP" (dchk-first sz)))
    ((dchk-has n "VALVE") (dchk-key "VALVE" (dchk-first sz)))
    ((dchk-has n "LINEMARK") (dchk-key "LINE MARK" nil))
    ((dchk-has n "표지판") (dchk-key "표지판" nil))
    ((or (dchk-has n "TESTBOX") (= n "T.B") (= n "T/B")) (dchk-key "TEST BOX" nil))
    (T nil)
  )
)

(defun dchk-vals (key src / res en)
  ;; 해당 키/출처의 (X . 값) 목록을 왼쪽 -> 오른쪽 순서로
  (setq res nil)
  (foreach en *dchk-ent*
    (if (and (= (car en) key) (= (cadr en) src))
      (setq res (cons (cons (caddr en) (cadddr en)) res))
    )
  )
  (dchk-sort res '(lambda (a b) (< (car a) (car b))))
)

(defun dchk-total (lst / s v)
  (setq s 0.0)
  (foreach v lst (setq s (+ s (cdr v))))
  s
)

(defun dchk-formula (lst)
  ;; "2+1+1" 형태 (항이 하나면 "")
  (if (and lst (cdr lst))
    (dchk-join (mapcar '(lambda (v) (dchk-fmt (cdr v))) lst) "+")
    ""
  )
)

(defun dchk-show (lst)
  (if lst (dchk-fmt (dchk-total lst)) "")
)

;; ============================================================
;; 자재내역 표 읽기
;; ============================================================
(defun dchk-find-header (txts / names hc it z c0 hdr nm f2 c ok)
  ;; 표 머리글(번호/품명/규격/단위/수량/비고)이 같은 높이에 모두 있는 곳을 찾음
  ;; 반환: ((x y) x6) 또는 nil
  (setq names '("번호" "품명" "규격" "단위" "수량" "비고"))
  (setq hc nil)
  (foreach it txts
    (if (< (strlen (nth 4 it)) 12)
      (progn
        (setq z (dchk-nz (nth 4 it)))
        (if (member z names)
          (setq hc (cons (list z (nth 2 it) (nth 3 it)) hc))
        )
      )
    )
  )
  (setq hdr nil)
  (foreach c0 hc
    (if (and (null hdr) (= (car c0) "번호"))
      (progn
        (setq ok T f2 nil)
        (foreach nm names
          (setq c nil)
          (foreach it hc
            (if (and (null c) (= (car it) nm) (< (abs (- (caddr it) (caddr c0))) 1.0))
              (setq c it)
            )
          )
          (if c
            (setq f2 (cons (list (cadr c) (caddr c)) f2))
            (setq ok nil)
          )
        )
        (if ok (setq hdr (reverse f2)))
      )
    )
  )
  hdr
)

(defun dchk-read-table (txts hdr / xs hy bd tabt it z numrows pitch nr cells ci x key qv qs)
  ;; 자재표를 읽어 *dchk-ent*에 "M" 항목으로 누적. 반환: (pitch 맨윗행Y)
  (setq xs (mapcar 'car hdr))
  (setq hy (cadr (car hdr)))
  (setq bd (list (+ (nth 0 xs) 2.0)
                 (/ (+ (nth 1 xs) (nth 2 xs)) 2.0)
                 (/ (+ (nth 2 xs) (nth 3 xs)) 2.0)
                 (/ (+ (nth 3 xs) (nth 4 xs)) 2.0)
                 (/ (+ (nth 4 xs) (nth 5 xs)) 2.0)))
  (setq tabt nil numrows nil)
  (foreach it txts
    (if (and (> (nth 3 it) (+ hy 1.0)) (> (nth 2 it) (- (car xs) 3.0)))
      (progn
        (setq tabt (cons it tabt))
        (if (< (abs (- (nth 2 it) (car xs))) 2.0)
          (progn
            (setq z (dchk-nz (nth 4 it)))
            (if (dchk-pure-num z nil)
              (setq numrows (cons (list (nth 3 it) (atoi z)) numrows))
            )
          )
        )
      )
    )
  )
  (setq numrows (dchk-sort numrows '(lambda (a b) (< (car a) (car b)))))
  (setq pitch
    (if (and numrows (cdr numrows))
      (/ (- (car (last numrows)) (car (car numrows))) (float (1- (length numrows))))
      3.93
    )
  )
  (foreach nr numrows
    (setq cells nil)
    (foreach it tabt
      (setq x (nth 2 it))
      (if (and (>= x (car bd)) (< (abs (- (nth 3 it) (car nr))) (* 0.3 pitch)))
        (progn
          (setq ci (length (vl-remove-if-not '(lambda (b) (>= x b)) bd)))
          (if (not (assoc ci cells))
            (setq cells (cons (cons ci (nth 4 it)) cells))
          )
        )
      )
    )
    (if (assoc 1 cells)
      (progn
        (setq key (dchk-mat-key (cdr (assoc 1 cells))
                                (if (assoc 2 cells) (cdr (assoc 2 cells)) "")))
        (if key
          (progn
            (setq qs (if (assoc 4 cells) (dchk-nums (dchk-nz (cdr (assoc 4 cells)))) nil))
            (setq qv (if qs (car qs) 0.0))
            (dchk-add key "M" (float (cadr nr)) qv)
            (if (not (assoc key *dchk-rowy*))
              (setq *dchk-rowy* (cons (cons key (car nr)) *dchk-rowy*))
            )
          )
        )
      )
    )
  )
  (list pitch (if numrows (car (last numrows)) hy))
)

;; ============================================================
;; 도면번호
;; ============================================================
(defun dchk-drawing-no (txts fi / lab it z best bestd d)
  ;; 표제란 "DWG.NO." 오른쪽/아래의 도면번호 문자
  (setq lab nil)
  (foreach it txts
    (if (and (null lab) (= (dchk-nz (nth 4 it)) "DWG.NO."))
      (setq lab it)
    )
  )
  (setq best nil bestd nil)
  (if lab
    (foreach it txts
      (if (and (>= (nth 2 it) (- (nth 2 lab) 3.0)) (<= (nth 2 it) (+ (nth 2 lab) 60.0))
               (>= (nth 3 it) (- (nth 3 lab) 7.0)) (<= (nth 3 it) (+ (nth 3 lab) 2.0)))
        (progn
          (setq z (dchk-nz (nth 4 it)))
          (if (and (/= z "DWG.NO.") (wcmatch z "*#*") (wcmatch z "*-*"))
            (progn
              (setq d (distance (list (nth 2 it) (nth 3 it)) (list (nth 2 lab) (nth 3 lab))))
              (if (or (null bestd) (< d bestd))
                (setq bestd d best z)
              )
            )
          )
        )
      )
    )
  )
  (if best best (strcat "도곽#" (itoa (1+ fi))))
)

;; ============================================================
;; 히든 선 / 기하 / 이력 보조 함수
;; ============================================================
(defun dchk-linetype (ed / lt la)
  ;; 객체 선종류 (ByLayer면 레이어의 선종류)
  (setq lt (cdr (assoc 6 ed)))
  (if (or (null lt) (= (strcase lt) "BYLAYER"))
    (progn
      (setq la (tblsearch "LAYER" (cdr (assoc 8 ed))))
      (setq lt (if la (cdr (assoc 6 la)) "CONTINUOUS"))
    )
  )
  (if lt lt "CONTINUOUS")
)

(defun dchk-hidden-p (ed)
  (if (wcmatch (strcase (dchk-linetype ed)) (strcase *dchk-hidden-lt*)) T nil)
)

(defun dchk-lay-size (lay / n)
  ;; 신설관 레이어명 속 관경 ("신설관 LP 63mm PE" -> 63). 못 읽으면 큰 관으로 취급
  (setq n (dchk-nums (dchk-nz lay)))
  (if n (car n) 9999.0)
)

(defun dchk-dps (p a b / dx dy l2 u)
  ;; 점 p와 선분 a-b 사이 거리
  (setq dx (- (car b) (car a)) dy (- (cadr b) (cadr a)) l2 (+ (* dx dx) (* dy dy)))
  (if (< l2 0.000000001)
    (distance (list (car p) (cadr p)) (list (car a) (cadr a)))
    (progn
      (setq u (/ (+ (* (- (car p) (car a)) dx) (* (- (cadr p) (cadr a)) dy)) l2))
      (setq u (max 0.0 (min 1.0 u)))
      (distance (list (car p) (cadr p))
                (list (+ (car a) (* u dx)) (+ (cadr a) (* u dy))))
    )
  )
)

(defun dchk-dpl (p pts / i m d)
  ;; 점 p와 폴리선(점 목록) 사이 최단 거리
  (setq m 1000000.0 i 0)
  (if (= (length pts) 1)
    (setq m (distance (list (car p) (cadr p)) (list (car (car pts)) (cadr (car pts)))))
    (while (< i (1- (length pts)))
      (setq d (dchk-dps p (nth i pts) (nth (1+ i) pts)))
      (if (< d m) (setq m d))
      (setq i (1+ i))
    )
  )
  m
)

(defun dchk-conn-p (a b / ea eb)
  ;; 폴리선 a, b가 끝점으로 이어져 있는가 (한쪽 끝점이 다른 쪽 선 위에 닿음)
  (setq ea (list (car a) (last a)) eb (list (car b) (last b)))
  (or (<= (min (dchk-dpl (car ea) b) (dchk-dpl (cadr ea) b)) *dchk-conn-tol*)
      (<= (min (dchk-dpl (car eb) a) (dchk-dpl (cadr eb) a)) *dchk-conn-tol*))
)

(defun dchk-mindist (p lst / m d q)
  ;; 점 p와 폴리선 목록(각 항목은 점목록) 중 가장 가까운 선까지 거리
  (setq m 1000000.0)
  (foreach q lst
    (setq d (dchk-dpl p q))
    (if (< d m) (setq m d))
  )
  m
)

(defun dchk-near-ok (p vlist alist r strict / da dv)
  ;; p 가까이의 신설관 판정. vlist = 대조에 쓰는 선, alist = 모든 신설관(제외된 선 포함)
  ;; strict: r 안에 신설관이 없으면 제외. 아니어도 가장 가까운 선이 제외된 선이면 제외
  (setq da (dchk-mindist p alist) dv (dchk-mindist p vlist))
  (cond
    ((null alist) T)
    ((and (> da r) (not strict)) T)
    ((> dv r) nil)
    ((> dv (+ da 0.05)) nil)
    (T T)
  )
)

(defun dchk-ensure-layer (name col)
  (if (not (tblsearch "LAYER" name))
    (entmake (list (cons 0 "LAYER") (cons 100 "AcDbSymbolTableRecord")
                   (cons 100 "AcDbLayerTableRecord") (cons 2 name)
                   (cons 70 0) (cons 62 col) (cons 6 "Continuous")))
  )
)

(defun dchk-stamp (/ cd s)
  ;; CDATE -> "YYYY-MM-DD HH:MM"
  (setq cd (getvar "CDATE"))
  (setq s (if cd (rtos cd 2 6) "00000000.000000"))
  (strcat (substr s 1 4) "-" (substr s 5 2) "-" (substr s 7 2) " "
          (substr s 10 2) ":" (substr s 12 2))
)


;; 이상없음 문구를 자재내역 우측에 초록으로 씀. 표 행이 있으면 그 행 옆, 없으면 표 위쪽에 쌓음
;; 쌓는 자리를 썼으면 T 반환
(defun dchk-ok-text (msg ry qx notex topy pitch slot)
  (if (and ry qx)
    (progn
      (dchk-mk-text-on *dchk-hist-layer* notex (- ry (* 0.5 *dchk-note-h*)) *dchk-note-h* 3 msg)
      nil
    )
    (progn
      (dchk-mk-text-on *dchk-hist-layer* notex (+ topy (* pitch (+ 1.0 slot)) (* -0.5 *dchk-note-h*))
                       *dchk-note-h* 3 msg)
      T
    )
  )
)

;; 63mm 선의 꺾임 개수 (90도: 75~105도, 45도: 40~50도)
(defun dchk-bends (pts / i d n90 n45 p0 p1 p2)
  (setq n90 0 n45 0 i 1)
  (while (< i (1- (length pts)))
    (setq p0 (nth (1- i) pts) p1 (nth i pts) p2 (nth (1+ i) pts))
    (if (and (> (distance p0 p1) 0.01) (> (distance p1 p2) 0.01))
      (progn
        (setq d (- (atan (- (cadr p2) (cadr p1)) (- (car p2) (car p1)))
                   (atan (- (cadr p1) (cadr p0)) (- (car p1) (car p0)))))
        (while (> d pi) (setq d (- d (* 2.0 pi))))
        (while (< d (- pi)) (setq d (+ d (* 2.0 pi))))
        (setq d (* (abs d) (/ 180.0 pi)))
        (cond
          ((and (>= d 75.0) (<= d 105.0)) (setq n90 (1+ n90)))
          ((and (>= d 40.0) (<= d 50.0)) (setq n45 (1+ n45)))
        )
      )
    )
    (setq i (1+ i))
  )
  (list n90 n45)
)

;; 큰관 중간 분기의 항목 키: 자재내역에 S.TEE만 있으면 S.TEE, 아니면 TEE
(defun dchk-tee-key (msz / tk sk)
  (setq tk (dchk-key "TEE" (list msz 63)) sk (dchk-key "S.TEE" (list msz 63)))
  (if (and (null (dchk-vals tk "M")) (dchk-vals sk "M")) sk tk)
)


;; ============================================================
;; 종단 표(거리·레벨·측점번호) 점검
;; ============================================================
;; 왼쪽 제목 열의 행 제목(EXCAVATION / TOP OF PIPE / NATURAL GROUND / ADDITIONAL DISTANCE /
;; DISTANCE / STATION NUMBER)을 읽어 행 코드별 대표 Y를 구함 -> ((코드 . Y) ...)
(defun dchk-prof-rows (txts tx / lines it z res cur prev y code g l)
  (setq lines nil)
  (foreach it txts
    (if (< (abs (- (nth 2 it) tx)) 3.0)
      (progn
        (setq z (dchk-nz (nth 4 it)))
        (if (wcmatch z "EXCAVATION*,HEIGHT(M)*,TOPOFPIPE*,ELEVATION(M)*,NATURAL*,GROUND*,ADDITIONAL*,DISTANCE(M)*,STATION*,NUMBER*")
          (setq lines (cons (cons (nth 3 it) z) lines))
        )
      )
    )
  )
  (setq lines (dchk-sort lines '(lambda (a b) (> (car a) (car b)))))
  (setq res nil cur nil prev nil)
  (foreach l lines
    (setq y (car l) z (cdr l))
    (setq code
      (cond
        ((wcmatch z "ADDITIONAL*") "ADD")
        ((wcmatch z "EXCAVATION*") "DEP")
        ((wcmatch z "TOPOFPIPE*") "TOP")
        ((wcmatch z "NATURAL*") "GL")
        ((wcmatch z "STATION*") "STA")
        ((and (wcmatch z "DISTANCE*") (or (null cur) (/= cur "ADD") (> (- prev y) 4.0))) "DIST")
        (T cur)
      )
    )
    (if code
      (progn
        (setq cur code)
        (setq g (assoc code res))
        (if g
          (setq res (subst (cons code (cons y (cdr g))) g res))
          (setq res (cons (list code y) res))
        )
      )
    )
    (setq prev y)
  )
  (mapcar '(lambda (g) (cons (car g) (/ (apply '+ (cdr g)) (float (length (cdr g)))))) res)
)

;; 측점 표 값 문자를 가장 가까운 행에 배정 -> ((코드 X Y 문자 괄호여부) ...)
;; "(2.700)" 처럼 괄호 친 값은 같은 측점의 깊이 다른 값(횡단 구간 등)이라 괄호를 벗겨 별도 값 묶음으로 둠
(defun dchk-prof-vals (txts rows tx rightx / res it best bd d r s par)
  (setq res nil)
  (foreach it txts
    (if (and (wcmatch (nth 5 it) *dchk-lay-sta*) (> (nth 2 it) (+ tx 5.0)) (< (nth 2 it) rightx))
      (progn
        (setq s (dchk-nz (nth 4 it)) par nil)
        (if (and (> (strlen s) 2) (= (substr s 1 1) "(") (= (substr s (strlen s) 1) ")"))
          (setq s (substr s 2 (- (strlen s) 2)) par T)
        )
        (if (/= s "")
          (progn
            (setq best nil bd 3.0)
            (foreach r rows
              (setq d (abs (- (nth 3 it) (- (cdr r) 1.1))))
              (if (< d bd) (setq bd d best (car r)))
            )
            (if best (setq res (cons (list best (nth 2 it) (nth 3 it) s par) res)))
          )
        )
      )
    )
  )
  res
)

(defun dchk-colval (vals code x par / best bd it d)
  (setq best nil bd 0.8)
  (foreach it vals
    (if (and (= (car it) code) (equal (nth 4 it) par))
      (progn
        (setq d (abs (- (cadr it) x)))
        (if (< d bd) (setq bd d best (nth 3 it)))
      )
    )
  )
  best
)

(defun dchk-prof-check (txts starts rightx / tx it z rows vals cols x s add n i pa pseg seg c prevc
                        dd dexp lg lt ld ssta base xx nn mn mx k m found stray
                        dbad dwarn dpts lbad lwarn lpts sbad swarn spts nd nl ns y0 res nset lg2 par)
  (setq tx nil)
  (foreach it txts
    (if (and (null tx) (> (strlen (nth 4 it)) 8) (< (strlen (nth 4 it)) 16)
             (wcmatch (dchk-nz (nth 4 it)) "ADDITIONAL*"))
      (setq tx (nth 2 it))
    )
  )
  (if (null tx)
    nil
    (progn
      (setq rows (dchk-prof-rows txts tx))
      (setq vals (dchk-prof-vals txts rows tx rightx))
      (setq y0 (cdr (assoc "ADD" rows)))
      ;; 누적거리 행 = 측점 열의 기준: (X 누적거리 구간)
      (setq cols nil)
      (foreach it vals
        (if (and (= (car it) "ADD") (null (nth 4 it)))
          (progn
            (setq n (dchk-nums (nth 3 it)))
            (if (and n (not (assoc (cadr it) cols)))
              (setq cols (cons (list (cadr it) (car n) (dchk-seg-index (cadr it) starts)) cols))
            )
          )
        )
      )
      (setq cols (dchk-sort cols '(lambda (a b) (< (car a) (car b)))))
      (if (null cols)
        nil
        (progn
          (setq dbad nil dwarn nil dpts nil lbad nil lwarn nil lpts nil sbad nil swarn nil spts nil)
          (setq nd 0 nl 0 ns 0 pseg -1 pa nil)
          (foreach c cols
            (setq x (car c) add (cadr c) seg (caddr c))
            (setq y0 (if y0 y0 0.0))
            ;; --- 거리 ---
            (setq nd (1+ nd))
            (setq s (dchk-colval vals "DIST" x nil))
            (setq dexp (if (and pa (= seg pseg)) (- add pa) 0.0))
            ;; 관경이 바뀌며 이어지는 구간의 첫 열: 거리는 0 또는 앞 열과의 차 모두 허용
            (if (and pa (/= seg pseg) (>= add pa) s (dchk-nums s)
                     (<= (abs (- (car (dchk-nums s)) (- add pa))) *dchk-dist-tol*))
              (setq dexp (- add pa)))
            (cond
              ((and pa (= seg pseg) (< dexp (- 0.0 *dchk-dist-tol*)))
               (setq dbad (cons (strcat "누적거리 " (dchk-fmt add) ": 앞 측점보다 작음") dbad)
                     dpts (cons (list x y0) dpts)))
              ((null s)
               (if (and pa (= seg pseg))
                 (setq dwarn (cons (strcat "누적거리 " (dchk-fmt add) ": 거리 값 없음") dwarn)
                       dpts (cons (list x y0) dpts))
               ))
              ((setq n (dchk-nums s))
               (if (> (abs (- (car n) dexp)) *dchk-dist-tol*)
                 (setq dbad (cons (strcat "누적거리 " (dchk-fmt add) ": 거리 " (dchk-fmt (car n))
                                          " / 누적거리 차 " (dchk-fmt dexp)) dbad)
                       dpts (cons (list x y0) dpts))
               ))
            )
            (setq pa add pseg seg)
            ;; --- 레벨 ---
            (setq nl (1+ nl))
            ;; 일반 값 묶음과 괄호 값 묶음(깊이가 다른 같은 측점의 값)을 각각 검사
            (setq lg (dchk-colval vals "GL" x nil))
            (setq nset 0)
            (foreach par (list nil T)
              (setq lt (dchk-colval vals "TOP" x par) ld (dchk-colval vals "DEP" x par))
              (if (and (null par) (null lt) (null ld)) nil
                (if (and (null lt) (null ld)) nil
                  (progn
                    (setq nset (1+ nset))
                    (setq lg2 (if (dchk-colval vals "GL" x par) (dchk-colval vals "GL" x par) lg))
                    (if (and lg2 lt ld (dchk-nums lg2) (dchk-nums lt) (dchk-nums ld))
                      (if (> (abs (- (- (car (dchk-nums lg2)) (car (dchk-nums lt))) (car (dchk-nums ld)))) *dchk-lvl-tol*)
                        (setq lbad (cons (strcat "누적거리 " (dchk-fmt add) ": 지반고 " (dchk-fmt (car (dchk-nums lg2)))
                                                 " - 관상고 " (dchk-fmt (car (dchk-nums lt)))
                                                 " ≠ 심도 " (dchk-fmt (car (dchk-nums ld)))) lbad)
                              lpts (cons (list x y0) lpts))
                      )
                      (setq lwarn (cons (strcat "누적거리 " (dchk-fmt add) ": "
                                                (if lg2 "" "지반고 ") (if lt "" "관상고 ") (if ld "" "심도 ") "값 없음") lwarn)
                            lpts (cons (list x y0) lpts))
                    )
                  )
                )
              )
            )
            (if (= nset 0)
              (setq lwarn (cons (strcat "누적거리 " (dchk-fmt add) ": 관상고·심도 값 없음") lwarn)
                    lpts (cons (list x y0) lpts))
            )
            ;; --- 측점번호 ---
            (setq ns (1+ ns))
            (setq ssta (dchk-colval vals "STA" x nil))
            (cond
              ((null ssta)
               (setq swarn (cons (strcat "누적거리 " (dchk-fmt add) ": 측점번호 없음") swarn)
                     spts (cons (list x y0) spts)))
              ((wcmatch ssta "NO.#*")
               (setq nn (atoi (substr ssta 4)))
               (if (> (abs (- add (* nn *dchk-sta-pitch*))) *dchk-dist-tol*)
                 (setq sbad (cons (strcat "누적거리 " (dchk-fmt add) ": " ssta " (기대 NO." (itoa (fix (+ 0.5 (/ add *dchk-sta-pitch*)))) ")") sbad)
                       spts (cons (list x y0) spts))
               ))
              ((= (substr ssta 1 1) "+")
               (setq xx (atof (substr ssta 2)))
               (setq base (* *dchk-sta-pitch* (fix (/ (+ add 0.005) *dchk-sta-pitch*))))
               (if (> (abs (- xx (- add base))) 0.051)
                 (setq sbad (cons (strcat "누적거리 " (dchk-fmt add) ": " ssta " (기대 +" (dchk-fmt (- add base)) ")") sbad)
                       spts (cons (list x y0) spts))
               ))
              (T
               (setq swarn (cons (strcat "누적거리 " (dchk-fmt add) ": 측점번호 형식 확인 " ssta) swarn)
                     spts (cons (list x y0) spts)))
            )
          )
          ;; 간격마다 NO.n 측점이 있는지 (구간별 최소~최대 누적거리 안)
          (setq i 0)
          (while (< i (if starts (length starts) 1))
            (setq mn nil mx nil)
            (foreach c cols
              (if (= (caddr c) i)
                (progn
                  (if (or (null mn) (< (cadr c) mn)) (setq mn (cadr c)))
                  (if (or (null mx) (> (cadr c) mx)) (setq mx (cadr c)))
                )
              )
            )
            (if mn
              (progn
                (setq k (fix (/ mn *dchk-sta-pitch*)))
                (while (<= (* k *dchk-sta-pitch*) (+ mx 0.005))
                  (setq m (* k *dchk-sta-pitch*))
                  (if (>= m (- mn 0.005))
                    (progn
                      (setq found nil)
                      (foreach c cols
                        (if (and (= (caddr c) i) (< (abs (- (cadr c) m)) *dchk-dist-tol*)) (setq found T))
                      )
                      (if (not found)
                        (setq swarn (cons (strcat "누적거리 " (dchk-fmt m) ": NO." (itoa k) " 측점 없음") swarn)
                              spts (cons (list (car (car cols)) y0) spts))
                      )
                    )
                  )
                  (setq k (1+ k))
                )
              )
            )
            (setq i (1+ i))
          )
          ;; 누적거리 열이 없는 값(어긋난 문자)
          (setq stray nil)
          (foreach it vals
            (if (and (/= (car it) "ADD")
                     (> (apply 'min (mapcar '(lambda (c) (abs (- (car c) (cadr it)))) cols)) 3.0))
              (setq stray (cons it stray))
            )
          )
          (foreach it stray
            (setq z (strcat (cond ((= (car it) "DEP") "심도 ") ((= (car it) "TOP") "관상고 ") ((= (car it) "GL") "지반고 ")
                                ((= (car it) "DIST") "거리 ") (T "측점번호 "))
                          (nth 3 it) ": 누적거리 측점 열 없음"))
            (cond
              ((= (car it) "DIST") (setq dwarn (cons z dwarn) dpts (cons (list (cadr it) (caddr it)) dpts)))
              ((= (car it) "STA") (setq swarn (cons z swarn) spts (cons (list (cadr it) (caddr it)) spts)))
              (T (setq lwarn (cons z lwarn) lpts (cons (list (cadr it) (caddr it)) lpts)))
            )
          )
          (setq res nil)
          (setq res (cons (dchk-prof-pack "종단 거리" dbad dwarn dpts nd
                            (strcat "[이상없음] 종단 거리: 거리 = 누적거리 차이 (측점 " (itoa nd) "개)")) res))
          (setq res (cons (dchk-prof-pack "종단 레벨" lbad lwarn lpts nl
                            (strcat "[이상없음] 종단 레벨: 지반고 - 관상고 = 심도 (측점 " (itoa nl) "개)")) res))
          (setq res (cons (dchk-prof-pack "종단 측점번호" sbad swarn spts ns
                            (strcat "[이상없음] 종단 측점번호: NO.n/+x = 누적거리 (간격 "
                                    (dchk-fmt *dchk-sta-pitch*) "M, 측점 " (itoa ns) "개)")) res))
          (reverse res)
        )
      )
    )
  )
)

;; 점검 결과 정리: (항목 판정 개수 상세 표시점목록 이상없음문구)
(defun dchk-prof-pack (item bad warn pts cnt okmsg / all det n)
  (setq bad (reverse bad) warn (reverse warn))
  (setq all (append bad warn))
  (setq n (length all))
  (setq det
    (if (= n 0)
      (strcat "측점 " (itoa cnt) "개 대조")
      (strcat (dchk-join (vl-remove-if 'null (list (nth 0 all) (nth 1 all) (nth 2 all))) "; ")
              (if (> n 3) (strcat " 외 " (itoa (- n 3)) "건") ""))
    )
  )
  (list item (cond (bad "불일치") (warn "확인") (T "OK")) cnt det pts okmsg)
)


;; ============================================================
;; 디테일 도면 읽기 - 63mm 엘보 / 연결관
;; ============================================================
(defun dchk-near-title (p titles / best bd d tt)
  (setq best nil bd 1.0e9)
  (foreach tt titles
    (setq d (distance (list (car p) (cadr p)) (list (cadr tt) (caddr tt))))
    (if (< d bd) (setq bd d best (car tt)))
  )
  best
)

;; 반환: ((글자 관경 EL90개수 연결관길이) ...)  예: (("B" 63 4 1.0) ("C" 63 5 1.0) ("C" 110 8 2.0))
(defun dchk-detail-calc (txts yls / titles it z p ypl labels junc els vals i q pq lb best bd d ep res key ag sz seg a b j
                          idx chg letter k n pts cs)
  (setq titles nil labels nil junc nil els nil vals nil)
  (foreach it txts
    (if (wcmatch (nth 5 it) *dchk-lay-detail*)
      (progn
        (setq z (dchk-nz (nth 4 it)) p (list (nth 2 it) (nth 3 it)))
        (cond
          ((and (wcmatch z "DETAIL*") (>= (strlen z) 8))
           (setq letter (if (= (substr z (strlen z) 1) "\"") (substr z (1- (strlen z)) 1) (substr z (strlen z) 1)))
           (setq titles (cons (list letter (car p) (cadr p)) titles))
          )
          ((or (dchk-has z "TEE") (dchk-has z "RED"))
           (setq n (dchk-nums z))
           (if (and n (cdr n) (/= (dchk-round (car n)) (dchk-round (cadr n)))) (setq junc (cons p junc)))
          )
          ((dchk-has z "CAP") nil)
          ((and (dchk-has z "MM") (or (dchk-has z "LP") (dchk-has z "관")) (dchk-nums z))
           (setq labels (cons (list (dchk-round (car (dchk-nums z))) p) labels))
          )
          ((dchk-has z "EL90") (setq els (cons p els)))
          ((and (> (strlen z) 1) (= (substr z (strlen z) 1) "M") (dchk-pure-num (substr z 1 (1- (strlen z))) T))
           (setq vals (cons (list (atof z) p) vals))
          )
        )
      )
    )
  )
  (if (null titles)
    nil
    (progn
      ;; 배관 폴리선 (번호 점목록 히든 관경)
      (setq ypl nil i 0)
      (foreach it yls
        (setq ypl (cons (list i (nth 7 it) (nth 6 it) nil) ypl) i (1+ i))
      )
      (setq ypl (reverse ypl))
      ;; 1) 관경 라벨이 폴리선 가까이(8 이내, 가장 가까운 것)에 있으면 그 관경
      (setq q ypl ypl nil)
      (foreach pq q
        (setq bd 8.0)
        (foreach lb labels
          (setq d (dchk-dpl (cadr lb) (cadr pq)))
          (if (<= d bd)
            (setq bd d pq (list (car pq) (cadr pq) (caddr pq) (car lb)))
          )
        )
        (setq ypl (cons pq ypl))
      )
      (setq ypl (reverse ypl))
      ;; 2) 라벨 없는 폴리선은 끝점이 가까운(6 이내) 관경 폴리선의 관경을 이어받음.
      ;;    관경이 다른 이음관(TEE 110x63 등) 근처 끝점은 연결로 보지 않음
      (setq chg T)
      (while chg
        (setq chg nil)
        (foreach pq ypl
          (if (null (nth 3 pq))
            (progn
              (setq best nil bd 1.0e9)
              (foreach q ypl
                (if (and (nth 3 q) (/= (car q) (car pq)))
                  (foreach ep (list (car (cadr pq)) (last (cadr pq)))
                    (if (null (vl-some '(lambda (j) (<= (distance ep j) 12.0)) junc))
                      (progn
                        (setq d (dchk-dpl ep (cadr q)))
                        (if (and (<= d 6.0) (< d bd)) (setq bd d best (nth 3 q)))
                      )
                    )
                  )
                )
              )
              (if best
                (progn
                  (setq ypl (subst (list (car pq) (cadr pq) (caddr pq) best) pq ypl))
                  (setq chg T)
                )
              )
            )
          )
        )
      )
      (setq ag nil)
      (foreach p els
        (setq best nil bd 1.0e9)
        (foreach pq ypl
          (if (and (null (caddr pq)) (nth 3 pq))
            (progn (setq d (dchk-dpl p (cadr pq))) (if (< d bd) (setq bd d best pq)))))
        (if best
          (progn
            (setq key (strcat (dchk-near-title p titles) "|" (itoa (nth 3 best))))
            (setq a (assoc key ag))
            (if a (setq ag (subst (list key (1+ (cadr a)) (caddr a)) a ag))
                  (setq ag (cons (list key 1 0.0) ag))))))
      ;; 3) 폴리선별: 연결관 = 수직 구간 옆(5 이내) "x.xM" 값 (히든 폴리선 제외)
      (foreach pq ypl
        (if (and (null (caddr pq)) (nth 3 pq) (cdr (cadr pq)))
          (progn
            (setq pts (cadr pq) j 0 n 0 cs 0.0)
            (while (< j (1- (length pts)))
              (setq a (nth j pts) b (nth (1+ j) pts))
              (if (and (< (abs (- (car a) (car b))) 0.1) (> (abs (- (cadr a) (cadr b))) 1.0))
                (progn
                  (setq bd 5.0 best nil)
                  (foreach lb vals
                    (setq d (dchk-dps (cadr lb) a b))
                    (if (<= d bd) (setq bd d best lb))
                  )
                  (if best (setq cs (+ cs (car best))))
                )
              )
              (setq j (1+ j))
            )
            (setq n 0)
            (setq key (strcat (dchk-near-title (car pts) titles) "|" (itoa (nth 3 pq))))
            (setq a (assoc key ag))
            (if a
              (setq ag (subst (list key (+ n (cadr a)) (+ cs (caddr a))) a ag))
              (setq ag (cons (list key n cs) ag))
            )
          )
        )
      )
      (setq res nil)
      (foreach a ag
        (setq n (vl-string-position (ascii "|") (car a)))
        (setq res (cons (list (substr (car a) 1 n) (atoi (substr (car a) (+ n 2))) (cadr a) (caddr a)) res))
      )
      (reverse res)
    )
  )
)

;; 적용 횟수 조합 찾기: dets = ((글자 EL수 연결관길이 평면표기여부) ...)
;; 연결관 합 = mcon (mcon이 nil이면 연결관 조건 생략), 총 적용 횟수 <= rem
(defun dchk-det-rec (dets rem cs mcon / d lo n res sub)
  (if (null dets)
    (if (or (null mcon) (<= (abs (- cs mcon)) 0.011)) (list nil) nil)
    (progn
      (setq d (car dets) lo (if (nth 3 d) 1 0) res nil n lo)
      (while (<= n rem)
        (if (or (null mcon) (<= (+ cs (* n (caddr d))) (+ mcon 0.011)))
          (foreach sub (dchk-det-rec (cdr dets) (- rem n) (+ cs (* n (caddr d))) mcon)
            (setq res (cons (cons n sub) res))
          )
        )
        (setq n (1+ n))
      )
      res
    )
  )
)

;; 조합 하나로 엘보 수 합 / 설명 문자열
(defun dchk-det-sum (dets ns / s i)
  (setq s 0.0 i 0)
  (foreach d dets (setq s (+ s (* (nth i ns) (cadr d))) i (1+ i)))
  s
)

(defun dchk-det-text (dets ns idx / i d lst)
  (setq i 0 lst nil)
  (foreach d dets
    (if (> (nth i ns) 0)
      (setq lst (cons (strcat "디테일 " (car d) "(" (dchk-fmt (nth idx d)) (if (= idx 2) "M" "개") ")×" (itoa (nth i ns))) lst))
    )
    (setq i (1+ i))
  )
  (dchk-join (reverse lst) " + ")
)

;; ============================================================
;; 검수 표시 그리기
;; ============================================================
(defun dchk-mk-circle (x y r col)
  (entmake (list (cons 0 "CIRCLE") (cons 8 *dchk-mark-layer*) (cons 62 col)
                 (cons 10 (list x y 0.0)) (cons 40 r)))
)

(defun dchk-mk-text-on (lay x y h col s / d)
  (setq d (list (cons 0 "TEXT") (cons 8 lay) (cons 62 col)
                (cons 10 (list x y 0.0)) (cons 40 h) (cons 1 s)))
  (if *dchk-style* (setq d (append d (list (cons 7 *dchk-style*)))))
  (entmake d)
)

(defun dchk-mk-text (x y h col s)
  (dchk-mk-text-on *dchk-mark-layer* x y h col s)
)

(defun dchk-out (dno item spec m l f d p c verdict note)
  (setq *dchk-rows* (cons (list dno item spec m l f d p c verdict note) *dchk-rows*))
  (cond
    ((= verdict "불일치") (setq *dchk-nbad* (1+ *dchk-nbad*)))
    ((= verdict "확인") (setq *dchk-nwarn* (1+ *dchk-nwarn*)))
    ((= verdict "OK") (setq *dchk-nokf* (1+ *dchk-nokf*)))
  )
)

;; ============================================================
;; 구간(관로) 분리 - 한 도엽에 종단 그래프가 여러 개(① ② ...)일 때
;; ============================================================
(defun dchk-minsz (spec / n)
  ;; 규격 문자열("110x63", "63") 중 가장 작은 관경
  (setq n (dchk-nums spec))
  (if n (apply 'min n) 9999.0)
)

;; 누적거리 행 값의 (X . 값) 목록 (X 오름차순)
(defun dchk-add-xs (txts / ly res it n)
  (setq ly nil res nil)
  (foreach it txts
    (if (and (null ly) (> (strlen (nth 4 it)) 8) (< (strlen (nth 4 it)) 16)
             (wcmatch (dchk-nz (nth 4 it)) "ADDITIONAL*"))
      (setq ly (nth 3 it))
    )
  )
  (if ly
    (foreach it txts
      (if (and (wcmatch (nth 5 it) *dchk-lay-sta*)
               (< (abs (- (nth 3 it) (+ ly *dchk-row-dy*))) *dchk-row-tol*))
        (progn
          (setq n (dchk-nums (nth 4 it)))
          (if n (setq res (cons (cons (nth 2 it) (car n)) res)))
        )
      )
    )
  )
  (dchk-sort res '(lambda (a b) (< (car a) (car b))))
)

;; 누적거리 값 -> X (누적거리 열 사이 선형 보간)
(defun dchk-add-to-x (cols av / res c1 c2 c)
  (setq res nil c1 nil)
  (foreach c2 cols
    (if (and c1 (null res) (> (cdr c2) (+ (cdr c1) 0.005))
             (>= av (- (cdr c1) 0.005)) (<= av (+ (cdr c2) 0.005)))
      (setq res (+ (car c1) (* (/ (- av (cdr c1)) (- (cdr c2) (cdr c1))) (- (car c2) (car c1)))))
    )
    (setq c1 c2)
  )
  res
)

(defun dchk-seg-index (x starts / i res st)
  ;; 공사시점 문자의 X(오름차순) 목록으로 x가 속한 구간 번호(0부터)를 구함
  (setq i 0 res 0)
  (foreach st starts
    (if (and (> i 0) (>= x (- st 2.0))) (setq res i))
    (setq i (1+ i))
  )
  res
)

(defun dchk-nth-size (idx sizes fallback / v)
  (setq v (nth idx sizes))
  (if v v fallback)
)

;; ============================================================
;; 도곽 1개 검수
;; ============================================================
(defun dchk-proc-frame (fi fr its / ox oy w h txts inss pls it z s n x dno hdr tab pitch topy
                           rightx qx pipes hasprof laby-add laby-exc addv depv
                           keys en key nm kind spec m l f d p mv bad warn judged verdict note
                           parts nstack fbad fwarn ry notex col crs cdep profks planks ck ok v
                           msg cx cy lst
                           starts st2 nseg segsz fsz sz szl si i plen pav exp-segs vs av pq pa ae acols bst pl2 prevq psg cum sg a0 xb c hi lo nx
                           mins small xn e63 e63s cap63 cm ckey
                           cls vmain hmain csm vsm hsm pending chg q2 ok2 allp valp havel
                           ex-hid ex-hb ex-nc ex-mark ex-cap ex-label cpl hmk stp k exn
                           jends jm jmi jk jw je jkey mp msz ep bn g gv mvc pv ok-k okm okj pck pt
                           kk exold yls lbl lprs lmat lusd lq vl2 dtxc dtxe dres dets dref dl nbr63 kel kcn mel mcn nblk sols sol okl bestsol bb bs b1 solc
                           ns-i es dtxt detm xl)
  (setq ox (car fr) oy (cadr fr) w (caddr fr) h (cadddr fr))
  (setq txts nil inss nil pls nil yls nil)
  (foreach it its
    (cond
      ((= (cadr it) "T") (setq txts (cons it txts)))
      ((= (cadr it) "I") (setq inss (cons it inss)))
      ((= (cadr it) "P") (setq pls (cons it pls)))
      ((= (cadr it) "Y") (setq yls (cons it yls)))
    )
  )
  (setq *dchk-ent* nil *dchk-names* nil *dchk-rowy* nil)
  (setq dno (dchk-drawing-no txts fi))
  (setq fbad 0 fwarn 0 nstack 0 *dchk-nokf* 0)
  (setq notex (+ ox w 3.0))

  ;; ---- 1) 구간(관로)과 관로 라벨 ----
  ;; "공사시점" 문자가 여러 개면 종단 그래프가 여러 개(①, ② ...)인 도엽 -> 구간별로 관경을 따로 봄
  (setq starts nil)
  (foreach it txts
    (if (and (wcmatch (nth 5 it) *dchk-lay-prof*) (dchk-has (dchk-nz (nth 4 it)) "공사시점"))
      (setq starts (cons (nth 2 it) starts))
    )
  )
  (setq starts (dchk-sort starts '<))
  ;; 누적거리 행이 0.00으로 다시 시작하는 곳(이어지는 다른 종단 구간)도 구간 시작으로 본다.
  ;; (0이 아닌 값으로 작아지면 구간 시작이 아니라 입력 오류로 보고 종단 거리 점검에서 지적)
  ;; 도엽 왼쪽 끝 구간은 "공사시점" 문자가 없을 수 있으므로 맨 앞 구간도 추가
  (setq av nil pa nil)
  (foreach ae (dchk-add-xs txts)
    (if (and pa (< (cdr ae) (- pa 0.005)) (< (cdr ae) 0.005))
      (setq starts (cons (- (car ae) 0.5) starts))
    )
    (if (null av) (setq av (car ae)))
    (setq pa (cdr ae))
  )
  (setq starts (dchk-sort starts '<))
  (if (and av (or (null starts) (> (- (car starts) av) 12.0)))
    (setq starts (cons (- av 0.5) starts))
  )
  (setq st2 nil)
  (foreach s starts
    (if (or (null st2) (> (- s (car st2)) 5.0)) (setq st2 (cons s st2)))
  )
  (setq starts (reverse st2))
  (setq nseg (if starts (length starts) 1))
  ;; 관로 라벨 (size mat len x): "LP 315mm PE", "MP 200A PLP (140.0M)"
  (setq pipes nil hasprof nil)
  (foreach it txts
    (if (wcmatch (nth 5 it) *dchk-lay-prof*)
      (progn
        (setq hasprof T)
        (setq z (dchk-nz (nth 4 it)))
        (if (wcmatch z "MP*,LP*")
          (progn
            (setq n (dchk-nums z))
            (if n
              (setq pipes
                (cons (list (dchk-round (car n))
                            (cond ((dchk-has z "PLP") "PLP") ((dchk-has z "PE") "PE") (T ""))
                            (if (and (dchk-has z "(") (cdr n)) (cadr n) nil)
                            (nth 2 it))
                      pipes))
            )
          )
        )
      )
    )
  )
  (setq pipes (reverse pipes))
  ;; 한 종단 안에서 관경이 바뀌는 지점(라벨 길이 누계로 위치 계산)도 구간 시작으로 본다
  (setq acols (dchk-add-xs txts) bst nil)
  (if (and acols (cdr acols))
    (progn
      (setq pl2 (dchk-sort (vl-remove-if '(lambda (q) (null (caddr q))) pipes)
                           '(lambda (a b) (< (cadddr a) (cadddr b)))))
      (setq prevq nil psg -1 cum 0.0)
      (foreach q pl2
        (setq sg (dchk-seg-index (cadddr q) starts))
        (if (/= sg psg) (setq cum 0.0 prevq nil))
        (if prevq
          (progn
            (setq cum (+ cum (caddr prevq)))
            (if (/= (car q) (car prevq))
              (progn
                (setq a0 nil)
                (foreach c acols
                  (if (= (dchk-seg-index (car c) starts) sg)
                    (if (or (null a0) (< (cdr c) a0)) (setq a0 (cdr c)))
                  )
                )
                (if a0
                  (progn
                    (setq xb (dchk-add-to-x acols (+ a0 cum)))
                    (if xb (setq bst (cons (- xb 0.5) bst)))
                  )
                )
              )
            )
          )
        )
        (setq prevq q psg sg)
      )
    )
  )
  (if bst
    (progn
      (setq starts (dchk-sort (append starts bst) '<))
      (setq st2 nil)
      (foreach s starts
        (if (or (null st2) (> (- s (car st2)) 5.0)) (setq st2 (cons s st2)))
      )
      (setq starts (reverse st2))
      (setq nseg (length starts))
    )
  )
  ;; 구간 관경: 길이가 적힌 라벨 > 신설 PE 라벨 > 그 외 순서로 고름
  ;; (기존관 "MP 200A PLP" 교차 표기는 길이가 없고 PLP라서 뒤로 밀림. 선택이 도면 요소 순서에 좌우되지 않게 함)
  (setq fsz nil)
  (foreach pq pipes
    (if (and (caddr pq) (null fsz)) (setq fsz (car pq)))
  )
  (foreach pq pipes
    (if (and (= (cadr pq) "PE") (null fsz)) (setq fsz (car pq)))
  )
  (if (and (null fsz) pipes) (setq fsz (car (car pipes))))
  (setq segsz nil i 0)
  (while (< i nseg)
    (setq sz nil)
    (foreach pq pipes
      (if (and (null sz) (caddr pq) (= (dchk-seg-index (cadddr pq) starts) i)) (setq sz (car pq)))
    )
    (foreach pq pipes
      (if (and (null sz) (= (cadr pq) "PE") (= (dchk-seg-index (cadddr pq) starts) i)) (setq sz (car pq)))
    )
    (foreach pq pipes
      (if (and (null sz) (= (dchk-seg-index (cadddr pq) starts) i)) (setq sz (car pq)))
    )
    (setq segsz (cons sz segsz) i (1+ i))
  )
  (setq segsz (reverse segsz))

  ;; ---- 2) 자재내역 표 ----
  (setq hdr (dchk-find-header txts))
  (if hdr
    (progn
      (setq tab (dchk-read-table txts hdr))
      (setq pitch (car tab) topy (cadr tab))
      (setq rightx (- (car (car hdr)) 3.0))
      (setq qx (car (nth 4 hdr)))
    )
    (setq pitch 3.93 topy (+ oy (* 0.5 h)) rightx (+ ox w) qx nil)
  )

  ;; ---- 3) 종단 상단 라벨 / Fitting's 행 ----
  (setq pav nil)
  (foreach it txts
    (setq x (nth 2 it))
    (setq si (dchk-seg-index x starts))
    (setq sz (dchk-nth-size si segsz fsz))
    (setq szl (if sz (list sz) nil))
    (cond
      ((wcmatch (nth 5 it) *dchk-lay-prof*)
       (setq z (dchk-nz (nth 4 it)))
       (setq n (dchk-nums z))
       (cond
         ((dchk-has z "ELBOW")
          (if n
            (dchk-add (dchk-key (strcat "ELBOW" (itoa (dchk-round (car n)))) szl)
                      "L" x (if (cdr n) (cadr n) 1.0))
          )
         )
         ((or (dchk-has z "S.TEE") (dchk-has z "STEE"))
          (dchk-add (dchk-key "S.TEE" (dchk-pair (dchk-ints n))) "L" x 1.0)
         )
         ((dchk-has z "TEE")
          (dchk-add (dchk-key "TEE" (dchk-pair (dchk-ints n))) "L" x 1.0)
         )
         ((or (wcmatch z "RED#*") (dchk-has z "REDUCER"))
          (dchk-add (dchk-key "RED" (dchk-pair (dchk-ints n))) "L" x 1.0)
         )
         ((dchk-has z "CAP")
          (dchk-add (dchk-key "CAP" (dchk-first (dchk-ints n))) "L" x 1.0)
         )
         ((dchk-has z "VALVE")
          (dchk-add (dchk-key "VALVE" (dchk-first (dchk-ints n))) "L" x 1.0)
         )
         ((dchk-has z "연결관")
          (if n (dchk-add (dchk-key "연결관" szl) "L" x (car n)))
         )
         ((wcmatch z "#*-#*M")
          ;; 63mm 인입관 길이 "63mm-4M"
          (if (and n (cdr n))
            (dchk-add (dchk-key "인입관" (list (dchk-round (car n)))) "L" x (cadr n))
          )
         )
         ((and n (dchk-has z "(") (dchk-has z "M)") (not (wcmatch z "MP*,LP*")))
          ;; 포장 구분 길이 "A.S.P (88.0M)" - 관로 라벨에 길이가 없을 때 직관 길이로 사용
          (setq pav (cons (cons x (last n)) pav))
         )
       )
      )
      ((wcmatch (nth 5 it) *dchk-lay-fit*)
       (setq z (dchk-nz (nth 4 it)))
       (setq n (dchk-nums z))
       (cond
         ((or (dchk-has z "S.TEE") (dchk-has z "STEE"))
          (dchk-add (dchk-key "S.TEE" (dchk-pair (dchk-ints n))) "F" x 1.0)
         )
         ((dchk-has z "TEE")
          (dchk-add (dchk-key "TEE" (dchk-pair (dchk-ints n))) "F" x 1.0)
         )
         ((and n (cdr n))
          ;; "200A-90%%Dx2" / "315mm-90%%Dx4" -> 관경, 각도, 개수
          (dchk-add (dchk-key (strcat "ELBOW" (itoa (dchk-round (cadr n))))
                              (list (dchk-round (car n))))
                    "F" x (if (cddr n) (caddr n) 1.0))
         )
       )
      )
    )
  )
  ;; 직관 길이: 관로 라벨에 길이가 있으면 그 값, 없으면 그 구간의 포장 구분 길이 합
  (setq exp-segs nil)
  (foreach pq pipes
    (if (caddr pq)
      (progn
        (dchk-add (dchk-key "직관" (list (car pq))) "L" (cadddr pq) (caddr pq))
        (setq exp-segs (cons (dchk-seg-index (cadddr pq) starts) exp-segs))
      )
    )
  )
  (setq i 0)
  (while (< i nseg)
    (if (not (member i exp-segs))
      (progn
        (setq plen nil)
        (foreach av pav
          (if (= (dchk-seg-index (car av) starts) i)
            (setq plen (if plen (+ plen (cdr av)) (cdr av)))
          )
        )
        (setq sz (dchk-nth-size i segsz fsz))
        (if (and plen sz)
          (dchk-add (dchk-key "직관" (list sz)) "L" (if starts (nth i starts) 0.0) plen)
        )
      )
    )
    (setq i (1+ i))
  )

  ;; ---- 4) 종단 측점 표: 누적거리 / 심도 ----
  (setq laby-add nil laby-exc nil)
  (foreach it txts
    (setq s (nth 4 it))
    (if (and (> (strlen s) 8) (< (strlen s) 16))
      (progn
        (setq z (dchk-nz s))
        (if (and (null laby-add) (wcmatch z "ADDITIONAL*")) (setq laby-add (nth 3 it)))
        (if (and (null laby-exc) (wcmatch z "EXCAVATION*")) (setq laby-exc (nth 3 it)))
      )
    )
  )
  (setq addv nil depv nil)
  (foreach it txts
    (if (wcmatch (nth 5 it) *dchk-lay-sta*)
      (progn
        (if (and laby-add (< (abs (- (nth 3 it) (+ laby-add *dchk-row-dy*))) *dchk-row-tol*))
          (progn
            (setq n (dchk-nums (nth 4 it)))
            (if n (setq addv (cons (cons (nth 2 it) (car n)) addv)))
          )
        )
        (if (and laby-exc (< (abs (- (nth 3 it) (+ laby-exc *dchk-row-dy*))) *dchk-row-tol*))
          (progn
            (setq n (dchk-nums (nth 4 it)))
            (if n (setq depv (cons (car n) depv)))
          )
        )
      )
    )
  )
  (setq depv (dchk-sort (dchk-uniq depv) '<))
  ;; 구간별 누적거리 (끝 - 시작)
  (setq i 0)
  (while (< i nseg)
    (setq vs nil)
    (foreach av addv
      (if (= (dchk-seg-index (car av) starts) i) (setq vs (cons (cdr av) vs)))
    )
    (setq sz (dchk-nth-size i segsz fsz))
    (if (and sz vs)
      (progn
        (setq lo (apply 'min vs) hi (apply 'max vs))
        ;; 다음 구간이 이어지는 구간(관경 변경)이면 다음 구간 첫 누적거리까지
        (setq nx nil)
        (foreach av addv
          (if (and (= (dchk-seg-index (car av) starts) (1+ i)) (>= (cdr av) (- hi 0.005))
                   (or (null nx) (< (cdr av) nx)))
            (setq nx (cdr av))
          )
        )
        (if (and nx (<= (- nx hi) (* 1.5 *dchk-sta-pitch*)) (>= (- nx hi) 0.0)) (setq hi nx))
        (if (> hi lo)
          (dchk-add (dchk-key "직관" (list sz)) "D" (if starts (nth i starts) 0.0) (- hi lo))
        )
      )
    )
    (setq i (1+ i))
  )

  ;; ---- 5) 평면도 ----
  ;; 5-0) 신설관 선 분류: 히든 선, 히든 관에서 분기했거나 이어지지 않은 63mm 선은 제외
  (setq vmain nil hmain nil csm nil hsm nil allp nil)
  (setq ex-hid 0 ex-hb 0 ex-nc 0 ex-mark 0 ex-cap 0 ex-label 0)
  (foreach it pls
    (if (and (< (nth 2 it) rightx) (nth 7 it))
      (progn
        (setq allp (cons (nth 7 it) allp))
        (cond
          ((nth 6 it)
           (if (> (dchk-lay-size (nth 5 it)) *dchk-small-dia*)
             (setq hmain (cons it hmain))
             (setq hsm (cons it hsm))
           )
          )
          ((> (dchk-lay-size (nth 5 it)) *dchk-small-dia*) (setq vmain (cons it vmain)))
          (T (setq csm (cons it csm)))
        )
      )
    )
  )
  (setq ex-hid (+ (length hmain) (length hsm)))
  ;; 63mm 선: 대조에 쓰는 선(큰 관 또는 이미 인정된 63mm 선)과 이어지면 인정, 반복
  (setq vsm nil pending csm chg T)
  (while (and chg pending)
    (setq chg nil cls nil)
    (foreach it pending
      (setq ok2 nil)
      (foreach q2 (append vmain vsm)
        (if (and (not ok2) (dchk-conn-p (nth 7 it) (nth 7 q2))) (setq ok2 T))
      )
      (if ok2
        (setq vsm (cons it vsm) chg T)
        (setq cls (cons it cls))
      )
    )
    (setq pending (reverse cls))
  )
  ;; 인정 못 받은 63mm 선: 히든 선과 닿아 있으면 "히든에서 분기", 아니면 "미연결"
  (foreach it pending
    (setq ok2 nil)
    (foreach q2 (append hmain hsm)
      (if (and (not ok2) (dchk-conn-p (nth 7 it) (nth 7 q2))) (setq ok2 T))
    )
    (if ok2 (setq ex-hb (1+ ex-hb)) (setq ex-nc (1+ ex-nc)))
  )
  (setq valp nil)
  (foreach it (append vmain vsm) (setq valp (cons (nth 7 it) valp)))
  (setq havel (if allp T nil))
  ;; 5-1) 63mm 분기점: 인정된 63mm 선의 끝점이 닿은 곳으로 TEE / S.TEE / RED / TEE 63x63을 셈
  (setq jends nil)
  (foreach it vsm
    (foreach ep (list (car (nth 7 it)) (last (nth 7 it)))
      (setq jm nil jmi 0 jk 0)
      (foreach q2 vmain
        (if (and (null jm) (<= (dchk-dpl ep (nth 7 q2)) *dchk-conn-tol*)) (setq jm q2 jmi jk))
        (setq jk (1+ jk))
      )
      (cond
        (jm
         (setq mp (nth 7 jm) msz (dchk-round (dchk-lay-size (nth 5 jm))))
         (cond
           ((<= (distance ep (car mp)) *dchk-conn-tol*) (setq jw "F"))
           ((<= (distance ep (last mp)) *dchk-conn-tol*) (setq jw "L"))
           (T (setq jw nil))
         )
         (if jw
           (progn
             (setq jkey (strcat (itoa jmi) jw))
             (setq je (assoc jkey jends))
             (if je
               (setq jends (subst (list jkey msz (1+ (caddr je)) (car ep)) je jends))
               (setq jends (cons (list jkey msz 1 (car ep)) jends))
             )
           )
           (dchk-add (dchk-tee-key msz) "P" (car ep) 1.0)
         )
        )
        (T
         (setq ok2 nil)
         (foreach q2 vsm
           (if (and (not ok2) (not (equal q2 it))
                    (<= (dchk-dpl ep (nth 7 q2)) *dchk-conn-tol*)
                    (> (distance ep (car (nth 7 q2))) *dchk-conn-tol*)
                    (> (distance ep (last (nth 7 q2))) *dchk-conn-tol*))
             (setq ok2 T)
           )
         )
         (if ok2 (dchk-add (dchk-key "TEE" (list 63 63)) "P" (car ep) 1.0))
        )
      )
    )
  )
  ;; 큰 관 끝에 63mm 선이 k개 닿으면 RED 1 + TEE k-1
  (foreach je jends
    (dchk-add (dchk-key "RED" (list (cadr je) 63)) "P" (cadddr je) 1.0)
    (if (> (caddr je) 1)
      (dchk-add (dchk-tee-key (cadr je)) "P" (cadddr je) (float (1- (caddr je))))
    )
  )
  ;; 5-2) 63mm 선의 꺾임 (엘보 참고)
  (foreach it vsm
    (setq bn (dchk-bends (nth 7 it)))
    (if (> (car bn) 0) (dchk-add (dchk-key "ELBOW90" (list 63)) "G" (nth 2 it) (float (car bn))))
    (if (> (cadr bn) 0) (dchk-add (dchk-key "ELBOW45" (list 63)) "G" (nth 2 it) (float (cadr bn))))
  )
  ;; 선이 하나라도 제외됐거나 63mm 계열이면 주변 표시(라인마크/캡/문구)도 가까운 선 기준으로 거름

  (foreach it inss
    (if (< (nth 2 it) rightx)
      (cond
        ((wcmatch (nth 5 it) *dchk-lay-linemark*)
         (setq stp (wcmatch (nth 5 it) *dchk-lay-small*))
         (if (or (not havel)
                 (dchk-near-ok (list (nth 2 it) (nth 3 it)) valp allp
                               (if stp *dchk-r-mark63* *dchk-r-mark*) stp))
           (progn
             (dchk-add (dchk-key "LINE MARK" nil) "P" (nth 2 it) 1.0)
             ;; 63mm 엘보 라인마크 블록(예: 63el)은 63mm 엘보 수량으로도 센다
             (setq z (dchk-nz (nth 4 it)))
             (if (dchk-has z "63EL")
               (dchk-add (dchk-key (if (dchk-has z "45EL") "ELBOW45" "ELBOW90") (list 63)) "P" (nth 2 it) 1.0)
             )
           )
           (setq ex-mark (1+ ex-mark))
         )
        )
        ((wcmatch (nth 5 it) *dchk-lay-tb*) (dchk-add (dchk-key "TEST BOX" nil) "P" (nth 2 it) 1.0))
        ((wcmatch (nth 5 it) *dchk-lay-sign*) (dchk-add (dchk-key "표지판" nil) "P" (nth 2 it) 1.0))
      )
    )
  )
  ;; 63mm 캡 폴리선 (평면 캡 수): 히든이거나 인정된 신설관 가까이에 없으면 제외
  (setq cpl nil)
  (foreach it its
    (if (and (= (cadr it) "C") (< (nth 2 it) rightx))
      (if (or (nth 6 it) (and havel (not (dchk-near-ok (list (nth 2 it) (nth 3 it)) valp allp *dchk-r-cap* T))))
        (setq ex-cap (1+ ex-cap))
        (progn (dchk-add (dchk-key "CAP" (list 63)) "P" (nth 2 it) 1.0) (setq cpl T))
      )
    )
  )
  ;; 63mm 인입관 문구 <-> 인정된 63mm 선 1:1 짝짓기 (가까운 순).
  ;; 문구가 선에서 조금 떨어져 있어도 짝이 있으면 인정 (히든 선 근처에 놓인 문구가 인정된 선의 것일 수 있음)
  (setq lbl nil lprs nil lmat nil lusd nil)
  (foreach it txts
    (if (and (< (nth 2 it) rightx) (wcmatch (nth 5 it) *dchk-lay-inlet*))
      (setq lbl (cons (list (nth 2 it) (nth 3 it)) lbl))
    )
  )
  (foreach lq lbl
    (foreach vl2 vsm
      (setq d (dchk-dpl lq (nth 7 vl2)))
      (if (<= d 25.0) (setq lprs (cons (list d lq vl2) lprs)))
    )
  )
  (setq lprs (dchk-sort lprs '(lambda (a b) (< (car a) (car b)))))
  (foreach lq lprs
    (if (and (not (member (cadr lq) lmat)) (not (member (caddr lq) lusd)))
      (setq lmat (cons (cadr lq) lmat) lusd (cons (caddr lq) lusd))
    )
  )
  (setq planks nil)
  (foreach it txts
    (if (< (nth 2 it) rightx)
      (progn
        (setq s (nth 4 it))
        (if (and (< (strlen s) 4) (= (dchk-nz s) "표"))
          (dchk-add (dchk-key "표지판" nil) "P" (nth 2 it) 1.0)
        )
        (if (wcmatch (nth 5 it) *dchk-lay-inlet*)
          (progn
            (setq n (dchk-nums (dchk-nz s)))
            (if (and n (cdr n))
              (if (or (not havel)
                      (member (list (nth 2 it) (nth 3 it)) lmat)
                      (dchk-near-ok (list (nth 2 it) (nth 3 it)) valp allp *dchk-r-label63* T))
                (dchk-add (dchk-key "인입관" (list (dchk-round (car n)))) "P" (nth 2 it) (last n))
                (setq ex-label (1+ ex-label))
              )
            )
          )
        )
        (if (wcmatch (nth 5 it) *dchk-lay-pipename*)
          (progn
            (setq z (dchk-nz s))
            (if (dchk-has z "신설관")
              (progn
                (setq n (dchk-nums z))
                (if n
                  (setq planks
                    (cons (strcat (cond ((dchk-has z "PLP") "PLP") ((dchk-has z "PE") "PE") (T ""))
                                  " " (itoa (dchk-round (car n))))
                          planks))
                )
              )
            )
          )
        )
      )
    )
  )
  (setq planks (dchk-uniq planks))
  ;; 평면 직관 길이: 히든이 아닌 큰 관 폴리선만
  (foreach it vmain
    (if (< (nth 2 it) rightx)
      (progn
        (setq n (dchk-nums (dchk-nz (nth 5 it))))
        (if n (dchk-add (dchk-key "직관" (list (dchk-round (car n)))) "P" (nth 2 it) (nth 4 it)))
      )
    )
  )

  ;; ---- 5-3) 디테일 도면: 63mm 엘보 / 연결관 ----
  ;; 평면도 "DETAIL A" 표기(최소 1회 적용)와 디테일 도면의 63mm 엘보·연결관 수를 읽음
  (setq dets nil dref nil)
  (foreach it txts
    (if (and (wcmatch (nth 5 it) *dchk-lay-detplan*) (< (nth 2 it) rightx)
             (wcmatch (dchk-nz (nth 4 it)) "DETAIL*"))
      (setq z (dchk-nz (nth 4 it))
            dref (cons (if (= (substr z (strlen z) 1) "\"") (substr z (1- (strlen z)) 1) (substr z (strlen z) 1)) dref))
    )
  )
  (setq dres (dchk-detail-calc txts yls))
  (foreach dl dres
    (if (and (<= (cadr dl) *dchk-small-dia*) (or (> (caddr dl) 0) (> (cadddr dl) 0.0)))
      (setq dets (cons (list (car dl) (float (caddr dl)) (cadddr dl) (if (member (car dl) dref) T nil)) dets))
    )
  )
  (setq dets (reverse dets))
  (setq nbr63 (length vsm))

  ;; ---- 6) 항목별 판정 ----
  (setq keys nil)
  (foreach en (reverse *dchk-ent*)
    ;; 평면 폴리선만 있는 관경(이웃 도엽 관로 등)은 행을 만들지 않음
    (if (and (not (member (car en) keys))
             (not (and (= (cadr en) "P") (wcmatch (car en) "직관|*"))))
      (setq keys (cons (car en) keys))
    )
  )
  (setq keys (reverse keys))
  ;; 자재내역에 행이 없고 평면에 보이는(히든 아닌) 신설관도 없는 큰 관경의 직관/엘보/연결관은
  ;; 히든으로 그려진 기존관 표기로 보고 검수에서 제외
  (setq kk nil exold nil)
  (foreach key keys
    (setq nm (cdr (assoc key *dchk-names*)))
    (setq kind (car nm) spec (cadr nm))
    (if (and (member kind (list "직관" "ELBOW90" "연결관"))
             spec (null (dchk-vals key "M"))
             (> (dchk-minsz spec) *dchk-small-dia*)
             (null (dchk-vals (dchk-key "직관" (list (dchk-round (car (dchk-nums spec))))) "P")))
      (if (not (member (strcat (dchk-fmt (dchk-minsz spec))) exold))
        (setq exold (cons (strcat (dchk-fmt (dchk-minsz spec))) exold)))
      (setq kk (cons key kk))
    )
  )
  (setq keys (reverse kk))
  (foreach key keys
    (setq nm (cdr (assoc key *dchk-names*)))
    (setq kind (car nm) spec (cadr nm))
    (setq m (dchk-vals key "M") l (dchk-vals key "L") f (dchk-vals key "F")
          d (dchk-vals key "D") p (dchk-vals key "P") g (dchk-vals key "G"))
    (setq mv (dchk-total m))
    (setq bad nil warn nil judged nil parts nil xn nil)
    (setq mins (dchk-minsz spec))
    (setq small (<= mins *dchk-small-dia*))
    (cond
      ((= kind "직관")
       (if l (progn (setq judged T) (if (not (dchk-eq mv (dchk-total l))) (setq bad T))))
       (if d (progn (setq judged T) (if (not (dchk-eq mv (dchk-total d))) (setq bad T))))
       (if p
         (progn
           (setq judged T)
           ;; 히든 선은 이미 빠졌으므로 보이는 선 길이 합과 비교 (선 1개당 허용오차)
           (if (> (abs (- mv (dchk-total p))) (* *dchk-plan-tol* (length p))) (setq warn T))
         )
       )
       (setq parts (list (if l (strcat "라벨 " (dchk-show l)) nil)
                         (if d (strcat "누적거리 " (dchk-show d)) nil)
                         (if p (strcat "평면 " (dchk-join (mapcar '(lambda (v) (dchk-fmt (cdr v))) p) "/")) nil)))
      )
      ((= kind "인입관")
       ;; 63mm 인입관: 종단 "63mm-4M" 합, 평면 "LP 63mm PE(4m)" 합과 대조
       (if l (progn (setq judged T) (if (not (dchk-eq mv (dchk-total l))) (setq bad T))))
       (if p (progn (setq judged T) (if (not (dchk-eq mv (dchk-total p))) (setq bad T))))
       (setq parts (list (if l (strcat "종단 " (dchk-show l)) nil)
                         (if p (strcat "평면 " (dchk-show p)) nil)))
      )
      ((or (= kind "연결관") (= kind "VALVE"))
       (cond
         ;; 63mm 연결관은 종단 라벨이 없음: 디테일 도면 대조(아래 6-4)에서 판정
         ((and (= kind "연결관") small dets) nil)
         ((and (= kind "연결관") small (null l))
          (if (> mv 0.0) (setq warn T judged T xn "대조 근거 없음(63mm 연결관: 종단 라벨·평면 디테일 없음)"))
         )
         (hasprof
          (setq judged T)
          (if (not (dchk-eq mv (dchk-total l))) (setq bad T))
         )
       )
       (setq parts (list (if (and small dets) nil (strcat "라벨 " (dchk-fmt (dchk-total l))))))
      )
      ((= kind "CAP")
       ;; 소구경(63mm) 캡은 종단 근거가 없어 아래 "63mm 캡 수 점검"에서 따로 봄
       (if (and hasprof (not small))
         (progn (setq judged T) (if (not (dchk-eq mv (dchk-total l))) (setq bad T)))
       )
       ;; 63mm 캡: 평면 캡 폴리선 개수와 대조 (히든/미연결로 제외된 것은 빠짐)
       (if (and small p)
         (progn (setq judged T) (if (not (dchk-eq mv (dchk-total p))) (setq bad T)))
       )
       (setq parts (list (if small (strcat "평면 " (dchk-fmt (dchk-total p)))
                                   (strcat "라벨 " (dchk-fmt (dchk-total l))))))
      )
      ((wcmatch kind "ELBOW*")
       (cond
         ((and small dets (= kind "ELBOW90"))
          ;; 63mm 엘보는 디테일 도면 대조(아래 6-4)에서 판정
          (setq parts nil)
         )
         (small
          ;; 소구경 엘보는 종단에 표기되지 않음: 평면 LPPE63A라인마크 63el 블록 수와 대조,
          ;; 63mm 신설관 선의 꺾임 수는 참고(블록이 없으면 이것으로 대조)
          (setq gv (dchk-total g))
          (cond
            (p
             (setq judged T)
             (if (not (dchk-eq mv (dchk-total p))) (setq bad T))
             (if (and vsm (not (dchk-eq (dchk-total p) gv)))
               (setq warn T xn (strcat "63el 블록 " (dchk-fmt (dchk-total p)) " / 선 꺾임 " (dchk-fmt gv))))
            )
            (g
             (setq judged T)
             (if (not (dchk-eq mv gv)) (setq warn T xn "63el 블록 없음 - 선 꺾임 개수로 대조"))
            )
            ((> mv 0.0) (setq warn T xn "대조 근거 없음(평면 63el 블록·선 꺾임 없음)"))
          )
          (setq parts (list (if p (strcat "평면 63el 블록 " (dchk-fmt (dchk-total p))) nil)
                            (if g (strcat "선 꺾임 " (dchk-fmt gv)) nil)))
         )
         (T
          (if hasprof
            (progn
              (setq judged T)
              (if (or (not (dchk-eq mv (dchk-total l))) (not (dchk-eq mv (dchk-total f)))) (setq bad T))
            )
          )
          (setq parts (list (strcat "라벨 " (dchk-fmt (dchk-total l)))
                            (strcat "Fitting " (dchk-fmt (dchk-total f)))))
         )
       )
      )
      ((or (= kind "TEE") (= kind "S.TEE") (= kind "RED"))
       (cond
         ((and small havel)
          ;; 63mm 이음관은 종단에 표기되지 않으므로 평면 63mm 신설관의 분기 위치로 센다
          (setq pv (dchk-total p) mvc mv)
          (if (member kind '("TEE" "S.TEE"))
            (progn
              (setq ok-k (dchk-key (if (= kind "TEE") "S.TEE" "TEE") (dchk-pair (dchk-ints (dchk-nums spec)))))
              (setq mvc (+ mv (dchk-total (dchk-vals ok-k "M"))))
              (setq pv (+ pv (dchk-total (dchk-vals ok-k "P"))))
            )
          )
          (setq judged T)
          (if (not (dchk-eq mvc pv)) (setq bad T))
          (setq parts (list (strcat "평면 분기 " (dchk-fmt pv))
                            (if l (strcat "라벨(참고) " (dchk-fmt (dchk-total l))) nil)))
          (if (not (dchk-eq mvc mv)) (setq xn (strcat "TEE+S.TEE 합 " (dchk-fmt mvc))))
         )
         ((or small (= kind "RED"))
          ;; 소구경 분기/레듀샤는 Fitting 행에 없고 종단 상단 라벨로만 셀 수 있음
          (if hasprof
            (progn
              (setq judged T)
              (cond
                ((dchk-eq mv (dchk-total l)) nil)
                ((and (> mv 0.0) (null l)) (setq warn T xn "대조 근거 없음(종단 상단 라벨 없음)"))
                (T (setq bad T))
              )
            )
          )
          (setq parts (list (strcat "라벨 " (dchk-fmt (dchk-total l)))))
         )
         (T
          (if hasprof
            (progn (setq judged T) (if (not (dchk-eq mv (dchk-total f))) (setq bad T)))
          )
          (setq parts (list (strcat "Fitting " (dchk-fmt (dchk-total f)))
                            (strcat "라벨(참고) " (dchk-fmt (dchk-total l)))))
         )
       )
      )
      ((or (= kind "LINE MARK") (= kind "TEST BOX"))
       (setq judged T)
       (if (not (dchk-eq mv (dchk-total p))) (setq bad T))
       (setq parts (list (strcat "평면 " (dchk-fmt (dchk-total p)))))
      )
      ((= kind "표지판")
       (setq judged T)
       (if (not (dchk-eq mv (dchk-total p))) (setq warn T))
       (setq parts (list (strcat "평면 " (dchk-fmt (dchk-total p)))))
      )
    )
    (setq verdict (cond (bad "불일치") (warn "확인") (judged "OK") (T "-")))
    ;; CSV 비고: 합산 산식 (왼쪽 -> 오른쪽)
    (setq note
      (dchk-join
        (vl-remove-if 'null
          (list (if (null m) "자재내역에 없음" nil)
                (if (/= (dchk-formula l) "") (strcat "라벨 " (dchk-formula l)) nil)
                (if (/= (dchk-formula f) "") (strcat "Fitting " (dchk-formula f)) nil)
                (if (and (or (= kind "TEE") (= kind "S.TEE")) (not small)
                         (not (dchk-eq (dchk-total l) (dchk-total f))))
                  "상단 라벨 개수는 참고(판정 제외)" nil)
                (if g (strcat "평면 63mm 선 꺾임 " (dchk-formula g)) nil)
                (if (and small (member kind '("TEE" "S.TEE" "RED")) p (/= (dchk-formula p) "")) (strcat "평면 분기 " (dchk-formula p)) nil)
                xn
                (if (and (not judged) (not hasprof)) "종단면도 없음" nil)))
        " / "))
    ;; 모든 출처가 0(빈칸)인 항목은 CSV에 적지 않음
    (if (or bad warn (> mv 0.0) l f d g (and p (/= kind "직관")))
      (dchk-out dno kind spec
                (if m (dchk-fmt mv) "")
                (dchk-show l) (dchk-show f) (dchk-show d)
                (if (= kind "직관")
                  (dchk-join (mapcar '(lambda (v) (dchk-fmt (cdr v))) p) "/")
                  (dchk-show p))
                "" verdict note)
    )
    ;; 도면 표시
    (if (or bad warn)
      (progn
        (if bad (setq fbad (1+ fbad)) (setq fwarn (1+ fwarn)))
        (setq col (if bad 1 2))
        (setq msg (strcat kind (if (= spec "") "" (strcat " " spec)) ": 자재 "
                          (if m (dchk-fmt mv) "없음") " / "
                          (dchk-join (vl-remove-if 'null parts) " / ")
                          (if xn (strcat " / " xn) "")))
        (setq ry (cdr (assoc key *dchk-rowy*)))
        (if (and ry qx)
          (progn
            (dchk-mk-circle qx ry (* 0.55 pitch) col)
            (dchk-mk-text notex (- ry (* 0.5 *dchk-note-h*)) *dchk-note-h* col msg)
          )
          (progn
            (setq nstack (1+ nstack))
            (dchk-mk-text notex (+ topy (* pitch (+ 1.0 nstack)) (* -0.5 *dchk-note-h*))
                          *dchk-note-h* col msg)
          )
        )
        (princ (strcat "\n    [" verdict "] " msg))
      )
    )
    ;; 이상 없는 항목: 무엇과 무엇을 비교했는지 초록 문구
    (if (= verdict "OK")
      (progn
        (setq okj (dchk-join (vl-remove-if '(lambda (q) (or (null q) (dchk-has q "참고"))) parts) " = "))
        (setq okm (strcat "[이상없음] "
                          ;; 표 행 옆에 쓰는 문구는 항목명 생략, 행이 없어 위쪽에 쌓는 문구만 항목명 표기
                          (if (and qx (cdr (assoc key *dchk-rowy*))) ""
                            (strcat kind (if (= spec "") "" (strcat " " spec)) ": "))
                          "자재 " (dchk-fmt mv)
                          (if (= okj "") "" (strcat " = " okj))))
        (if (dchk-ok-text okm (cdr (assoc key *dchk-rowy*)) qx notex topy pitch (1+ nstack))
          (setq nstack (1+ nstack)))
      )
    )
  )

  ;; ---- 6-2) 자재내역 표 내부 점검: 63mm 캡 수 = 63mm 분기 끝 수 ----
  ;; 63mm 라인은 S.TEE / TEE(x63) / 레듀샤(x63)마다 하나씩 시작해 캡으로 끝나고,
  ;; TEE 63x63은 라인을 둘로 갈라 끝이 하나 늘어남 -> 각 이음관 수량의 합이 캡 수와 같아야 함
  (setq e63 0.0 e63s nil cap63 nil)
  (foreach key keys
    (setq nm (cdr (assoc key *dchk-names*)))
    (setq kind (car nm) spec (cadr nm))
    (if (<= (dchk-minsz spec) *dchk-small-dia*)
      (cond
        ((member kind '("S.TEE" "TEE" "RED"))
         (setq mv (dchk-total (dchk-vals key "M")))
         (if (> mv 0.0)
           (setq e63 (+ e63 mv)
                 e63s (cons (strcat kind " " spec " " (dchk-fmt mv)) e63s))
         )
        )
        ((and (= kind "CAP") (dchk-vals key "M")) (setq cap63 key))
      )
    )
  )
  (if (or cap63 (> e63 0.0))
    (progn
      (setq cm (if cap63 (dchk-total (dchk-vals cap63 "M")) 0.0))
      (setq verdict (if (dchk-eq cm e63) "OK" "확인"))
      (setq note (strcat "분기 끝 수 " (dchk-fmt e63) " = " (dchk-join (reverse e63s) " + ")
                         (if cap63 "" " / 자재내역에 CAP 63 행 없음")))
      (dchk-out dno "63mm 캡 수 점검" "" (dchk-fmt cm) "" "" "" "" "" verdict note)
      (if (= verdict "확인")
        (progn
          (setq fwarn (1+ fwarn) nstack (1+ nstack))
          (setq msg (strcat "63mm 캡 수: 자재 " (dchk-fmt cm) " / 분기 끝 수 " (dchk-fmt e63)))
          (setq ry (if cap63 (cdr (assoc cap63 *dchk-rowy*)) nil))
          (if (and ry qx)
            (progn
              (dchk-mk-circle qx ry (* 0.55 pitch) 2)
              (dchk-mk-text notex (- ry (* 0.5 *dchk-note-h*)) *dchk-note-h* 2 msg)
            )
            (dchk-mk-text notex (+ topy (* pitch (+ 1.0 nstack)) (* -0.5 *dchk-note-h*))
                          *dchk-note-h* 2 msg)
          )
          (princ (strcat "\n    [확인] " msg))
        )
        (if (dchk-ok-text (strcat "[이상없음] 63mm 캡 수: 자재 " (dchk-fmt cm) " = 분기 끝 수 " (dchk-fmt e63)
                                  " (" (dchk-join (reverse e63s) " + ") ")")
                          nil qx notex topy pitch (1+ nstack))
          (setq nstack (1+ nstack)))
      )
    )
  )

  ;; ---- 6-4) 63mm 엘보 / 연결관: 디테일 도면 대조 ----
  (if (and dets havel)
    (progn
      (setq kel (dchk-key "ELBOW90" (list 63)) kcn (dchk-key "연결관" (list 63)))
      (setq mel (dchk-total (dchk-vals kel "M")) mcn (dchk-total (dchk-vals kcn "M")))
      (setq nblk (dchk-total (dchk-vals kel "P")))
      (setq dtxt (dchk-join (mapcar '(lambda (d) (strcat (car d) " 엘보 " (dchk-fmt (cadr d)) "개 연결관 " (dchk-fmt (caddr d)) "M")) dets) " / "))
      (setq dtxc (dchk-join (mapcar '(lambda (d) (strcat (car d) " " (dchk-fmt (caddr d)) "M")) (vl-remove-if '(lambda (d) (< (caddr d) 0.001)) dets)) ", "))
      (setq dtxe (dchk-join (mapcar '(lambda (d) (strcat (car d) " " (dchk-fmt (cadr d)) "개")) (vl-remove-if '(lambda (d) (< (cadr d) 0.5)) dets)) ", "))
      ;; --- 연결관 (디테일에 연결관 길이가 있을 때만) ---
      (if (> (apply (quote +) (mapcar (quote caddr) dets)) 0.001) (progn
      (setq verdict "확인")
      (setq note (strcat "디테일 " dtxc " - 확인 필요"))
      (dchk-out dno "63mm 연결관(디테일)" "" (dchk-fmt mcn) "" "" "" "" "" verdict note)
      (setq ry (cdr (assoc kcn *dchk-rowy*)))
      (if (= verdict "OK")
        (progn
          (setq msg (strcat "[이상없음] 자재 " (dchk-fmt mcn) " = " note))
          (if (dchk-ok-text msg ry qx notex topy pitch (1+ nstack)) (setq nstack (1+ nstack)))
        )
        (progn
          (setq fwarn (1+ fwarn))
          (setq msg (strcat "63mm 연결관: 자재 " (dchk-fmt mcn) " / " note))
          (if (and ry qx)
            (progn
              (dchk-mk-circle qx ry (* 0.55 pitch) 2)
              (dchk-mk-text notex (- ry (* 0.5 *dchk-note-h*)) *dchk-note-h* 2 msg)
            )
            (progn
              (setq nstack (1+ nstack))
              (dchk-mk-text notex (+ topy (* pitch (+ 1.0 nstack)) (* -0.5 *dchk-note-h*)) *dchk-note-h* 2 msg)
            )
          )
          (princ (strcat "\n    [확인] " msg))
        )
      )
      ))
      ;; --- 엘보 ---
      (setq verdict "확인")
      (setq note (strcat "디테일 " dtxe " - 확인 필요"))
      (dchk-out dno "63mm 엘보(디테일)" "" (dchk-fmt mel) "" "" "" (dchk-fmt nblk) "" verdict note)
      (setq ry (cdr (assoc kel *dchk-rowy*)))
      (if (= verdict "OK")
        (progn
          (setq msg (strcat "[이상없음] 자재 " (dchk-fmt mel) " = " note))
          (if (dchk-ok-text msg ry qx notex topy pitch (1+ nstack)) (setq nstack (1+ nstack)))
        )
        (progn
          (if (= verdict "불일치") (setq fbad (1+ fbad)) (setq fwarn (1+ fwarn)))
          (setq col (if (= verdict "불일치") 1 2))
          (setq msg (strcat "63mm 엘보: 자재 " (dchk-fmt mel) " / " note))
          (if (and ry qx)
            (progn
              (dchk-mk-circle qx ry (* 0.55 pitch) col)
              (dchk-mk-text notex (- ry (* 0.5 *dchk-note-h*)) *dchk-note-h* col msg)
            )
            (progn
              (setq nstack (1+ nstack))
              (dchk-mk-text notex (+ topy (* pitch (+ 1.0 nstack)) (* -0.5 *dchk-note-h*)) *dchk-note-h* col msg)
            )
          )
          (princ (strcat "\n    [" verdict "] " msg))
        )
      )
    )
  )

  ;; ---- 6-3) 평면 제외 내역 ----
  (setq exn (+ ex-hid ex-hb ex-nc ex-mark ex-cap ex-label (length exold)))
  (if (> exn 0)
    (progn
      (setq note
        (dchk-join
          (vl-remove-if 'null
            (list (if (> ex-hid 0) (strcat "히든 신설관 " (itoa ex-hid) "개(63mm " (itoa (length hsm)) "개 포함)") nil)
                  (if (> ex-hb 0) (strcat "히든 관에서 분기한 63mm " (itoa ex-hb) "개") nil)
                  (if (> ex-nc 0) (strcat "신설관과 이어지지 않은 63mm " (itoa ex-nc) "개") nil)
                  (if (> ex-cap 0) (strcat "캡 " (itoa ex-cap) "개") nil)
                  (if (> ex-mark 0) (strcat "라인마크 " (itoa ex-mark) "개") nil)
                  (if (> ex-label 0) (strcat "인입관 문구 " (itoa ex-label) "개") nil)
                  (if exold (strcat "히든 기존관 " (dchk-join (reverse exold) ",") "mm 표기") nil)))
          " / "))
      (dchk-out dno "평면 제외" "" "" "" "" "" "" "" "-" note)
      (setq nstack (1+ nstack))
      (dchk-mk-text-on *dchk-hist-layer* notex (+ topy (* pitch (+ 1.0 nstack)) (* -0.5 *dchk-note-h*))
                       *dchk-note-h* 8 (strcat "[평면 제외] " note))
      (princ (strcat "\n    [제외] " note))
    )
  )

  ;; ---- 7) 횡단면도 ----
  (setq crs nil cdep nil)
  (foreach it txts
    (if (wcmatch (nth 5 it) *dchk-lay-cross*)
      (progn
        (setq z (dchk-nz (nth 4 it)))
        (if (dchk-has z "신설관")
          (progn
            (setq n (dchk-nums z))
            (setq crs
              (cons (list (strcat (cond ((dchk-has z "PLP") "PLP") ((dchk-has z "PE") "PE") (T ""))
                                  " " (if n (itoa (dchk-round (car n))) "?"))
                          (nth 2 it) (nth 3 it))
                    crs))
          )
        )
      )
    )
  )
  (foreach it inss
    (if (wcmatch (nth 5 it) *dchk-lay-cross*)
      (setq cdep (append cdep (dchk-block-nums (nth 4 it))))
    )
  )
  (setq cdep (dchk-sort (dchk-uniq cdep) '<))
  (setq profks (dchk-uniq (mapcar '(lambda (pp) (strcat (cadr pp) " " (itoa (car pp)))) pipes)))
  (if (or crs cdep)
    (progn
      ;; 7-1) 관종·관경
      (if crs
        (progn
          (setq bad nil cx nil cy nil)
          (foreach ck crs
            (setq ok T)
            (if (and profks (not (member (car ck) profks))) (setq ok nil))
            (if (and planks (not (member (car ck) planks))) (setq ok nil))
            (if (not ok) (setq bad T cx (cadr ck) cy (caddr ck)))
          )
          (setq judged (or profks planks))
          (setq verdict (cond (bad "불일치") (judged "OK") (T "-")))
          (setq lst (dchk-join (dchk-uniq (mapcar 'car crs)) "/"))
          (dchk-out dno "횡단 관종·관경" "" "" (dchk-join profks "/") "" ""
                    (dchk-join planks "/") lst verdict "")
 (if (and (= verdict "OK") (dchk-ok-text (strcat "[이상없음] 횡단 관종·관경: 횡단 " lst " = 종단 " (dchk-join profks "/") " = 평면 " (dchk-join planks "/"))
                                                       nil qx notex topy pitch (1+ nstack)))
            (setq nstack (1+ nstack)))
          (if bad
            (progn
              (setq fbad (1+ fbad) nstack (1+ nstack))
              (setq msg (strcat "횡단 관종·관경: 횡단 " lst " / 종단 " (dchk-join profks "/")
                                " / 평면 " (dchk-join planks "/")))
              (dchk-mk-circle cx cy 4.0 1)
              (dchk-mk-text notex (+ topy (* pitch (+ 1.0 nstack)) (* -0.5 *dchk-note-h*))
                            *dchk-note-h* 1 msg)
              (princ (strcat "\n    [불일치] " msg))
            )
          )
        )
      )
      ;; 7-2) 심도
      (setq bad nil warn nil)
      (cond
        ((null cdep) (setq warn T note "횡단면도 심도 값을 찾지 못함"))
        ((null depv) (setq note "종단 EXCAVATION HEIGHT 행을 찾지 못함"))
        (T
         (setq note "")
         (foreach v cdep
           (setq ok nil)
           (foreach s depv
             (if (< (abs (- v s)) *dchk-depth-tol*) (setq ok T))
           )
           (if (not ok) (setq bad T))
         )
        )
      )
      (setq verdict (cond (bad "불일치") (warn "확인") ((and cdep depv) "OK") (T "-")))
      (dchk-out dno "횡단 심도" "" "" (dchk-join (mapcar 'dchk-fmt depv) "/") "" "" ""
                (dchk-join (mapcar 'dchk-fmt cdep) "/") verdict note)
      (if (and (= verdict "OK")
               (dchk-ok-text (strcat "[이상없음] 횡단 심도: 횡단 " (dchk-join (mapcar 'dchk-fmt cdep) "/")
                                     " = 종단 EXCAVATION HEIGHT 행에 있는 값")
                             nil qx notex topy pitch (1+ nstack)))
        (setq nstack (1+ nstack)))
      (if (or bad warn)
        (progn
          (if bad (setq fbad (1+ fbad)) (setq fwarn (1+ fwarn)))
          (setq nstack (1+ nstack) col (if bad 1 2))
          (setq msg
            (if bad
              (strcat "횡단 심도: 횡단 " (dchk-join (mapcar 'dchk-fmt cdep) "/")
                      " / 종단 " (dchk-join (mapcar 'dchk-fmt depv) "/"))
              (strcat "횡단 심도: " note)
            )
          )
          (if crs (dchk-mk-circle (cadr (car crs)) (caddr (car crs)) 5.0 col))
          (dchk-mk-text notex (+ topy (* pitch (+ 1.0 nstack)) (* -0.5 *dchk-note-h*))
                        *dchk-note-h* col msg)
          (princ (strcat "\n    [" verdict "] " msg))
        )
      )
    )
  )

  ;; ---- 7-3) 종단 표: 거리 / 레벨 / 측점번호 ----
  (setq pck (dchk-prof-check txts starts rightx))
  (foreach ck pck
    (setq verdict (nth 1 ck))
    (dchk-out dno (car ck) "" "" "" "" "" "" "" verdict (nth 3 ck))
    (if (= verdict "OK")
      (if (dchk-ok-text (nth 5 ck) nil qx notex topy pitch (1+ nstack))
        (setq nstack (1+ nstack)))
      (progn
        (if (= verdict "불일치") (setq fbad (1+ fbad)) (setq fwarn (1+ fwarn)))
        (setq col (if (= verdict "불일치") 1 2) nstack (1+ nstack))
        (foreach pt (nth 4 ck) (dchk-mk-circle (car pt) (cadr pt) 1.2 col))
        (setq msg (strcat (car ck) ": " (nth 3 ck)))
        (dchk-mk-text notex (+ topy (* pitch (+ 1.0 nstack)) (* -0.5 *dchk-note-h*)) *dchk-note-h* col msg)
        (princ (strcat "\n    [" verdict "] " msg))
      )
    )
  )

  ;; ---- 8) 자재표 자체를 못 읽은 경우 ----
  (if (null hdr)
    (progn
      (setq fwarn (1+ fwarn))
      (dchk-out dno "자재내역 표" "" "" "" "" "" "" "" "확인" "표 머리글(번호/품명/규격/단위/수량/비고)을 찾지 못함")
      (princ "\n    [확인] 자재내역 표 머리글을 찾지 못했습니다.")
    )
  )

  ;; ---- 9) 도곽 위 요약 ----
  (if (and (= fbad 0) (= fwarn 0))
    ;; 이상 없음: 자재내역 우측 맨 위에 초록 요약 (날짜·시간)
    (progn
      (setq nstack (1+ nstack))
      (dchk-mk-text-on *dchk-hist-layer* notex (+ topy (* pitch (+ 1.0 nstack)) (* -0.5 *dchk-note-h*))
                       *dchk-note-h* 3
                       (strcat "[검수 이상없음] " (dchk-stamp) "  " dno "  대조 " (itoa *dchk-nokf*) "개 항목 모두 일치"))
    )
    (dchk-mk-text ox (+ oy h 2.0) 3.0 (if (> fbad 0) 1 2)
                  (strcat "[검수] " dno "  " (dchk-stamp) "  불일치 " (itoa fbad) " / 확인 " (itoa fwarn)))
  )
  (list dno fbad fwarn)
)

;; ============================================================
;; CSV 저장
;; ============================================================
(defun dchk-output-dir (/ d)
  (setq d (strcat (getvar "DWGPREFIX") "DCHK\\"))
  (if (not (vl-file-directory-p d)) (vl-mkdir d))
  d
)

(defun dchk-write-csv (/ path f row)
  (setq path (strcat (dchk-output-dir) "검수결과.csv"))
  (setq f (open path "w"))
  (if f
    (progn
      (write-line "도면번호,항목,규격,자재내역,종단라벨,종단Fitting행,종단누적거리,평면도,횡단면도,판정,비고" f)
      (foreach row (reverse *dchk-rows*)
        (write-line (dchk-join (mapcar 'dchk-csv-esc row) ",") f)
      )
      (close f)
      (princ (strcat "\n[DCHK] 결과 CSV: " path))
    )
    (progn
      (princ (strcat "\n[DCHK] CSV를 저장하지 못했습니다: " path))
      (princ "\n  (엑셀에서 열려 있으면 닫고 다시 실행하세요. 도면 표시는 정상적으로 그려졌습니다.)")
    )
  )
)

;; ============================================================
;; 명령
;; ============================================================
(defun c:DCHK (/ items fi fr its r old nf)
  (setq old (ssget "_X" (list (cons 8 "0검수*"))))
  (cond
    (old
     (princ (strcat "\n[DCHK] 이전 검수 표시가 " (itoa (sslength old)) "개 남아 있습니다."))
     (princ "\n  DCHKDEL로 지운 뒤 다시 실행하세요. (검수 표시는 자동으로 지우지 않습니다)")
    )
    (T
     (setq *dchk-frames* (dchk-collect-frames))
     (if (null *dchk-frames*)
       (princ "\n[DCHK] FORM 블록 / FORM_ 레이어 도곽을 찾지 못했습니다.")
       (progn
         (setq nf (length *dchk-frames*))
         (princ (strcat "\n[DCHK] 도곽 " (itoa nf) "개 발견. 도면 요소를 읽는 중..."))
         (setq *dchk-style* nil)
         (dchk-ensure-layer *dchk-mark-layer* 1)
         (setq items (dchk-scan))
         (setq *dchk-rows* nil *dchk-nbad* 0 *dchk-nwarn* 0)
         (setq fi 0)
         (foreach fr *dchk-frames*
           (setq its (vl-remove-if-not '(lambda (it) (= (car it) fi)) items))
           (setq r (dchk-proc-frame fi fr its))
           (princ (strcat "\n  " (car r) " : 불일치 " (itoa (cadr r)) " / 확인 " (itoa (caddr r))))
           (setq fi (1+ fi))
         )
         (dchk-write-csv)
         (princ (strcat "\n[DCHK] 완료. 도곽 " (itoa nf) "개 - 불일치 " (itoa *dchk-nbad*)
                        "건 / 확인 " (itoa *dchk-nwarn*) "건"))
         (princ (strcat "\n  표시(불일치·확인)와 이상없음 이력(초록 문구)을 \"" *dchk-mark-layer* "\" 레이어에 그렸습니다. 지우려면 DCHKDEL."))
       )
     )
    )
  )
  (princ)
)

(defun c:DCHKDEL (/ ss i n)
  (setq ss (ssget "_X" (list (cons 8 "0검수*"))))
  (if ss
    (progn
      (setq i 0 n (sslength ss))
      (while (< i n)
        (entdel (ssname ss i))
        (setq i (1+ i))
      )
      (princ (strcat "\n[DCHKDEL] 검수 표시 " (itoa n) "개를 삭제했습니다."))
    )
    (princ "\n[DCHKDEL] 지울 검수 표시가 없습니다.")
  )
  (princ)
)

(princ "\n[DCHK] 로드 완료 - 명령: DCHK (검수), DCHKDEL (검수 표시·이력 삭제)")
(princ)
