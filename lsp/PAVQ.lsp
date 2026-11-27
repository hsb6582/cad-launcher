;;; @launcher
;;; 리습: PAVQ
;;; 분류: 복구수량 (개발 중)
;;; 설명: [개발 중] 종단면도 관경 × 포장구분 연장 → 복구수량산출서 자동 작성
;;; 기능: [개발 중] 복구수량산출서 자동 작성 | PAVQ | 종단면도 관경×포장 길이 집계 후 복구수량산출서 엑셀 작성
;;; 기능: [개발 중] 검토 표시 지우기 | PAVQDEL | PAVQ 가 그린 빨간 원·번호 표시 삭제
;;; 숨김: PAVQMMA, PAVQCAL   (명령은 그대로 쓸 수 있지만 런처 목록에는 넣지 않음)
;;; 설명서:
;;;   ※ 개발 중인 기능입니다. 결과를 반드시 직접 확인하세요.
;;;
;;;   종단면도의 관경 밴드와 포장 밴드 문자를 읽어, 관경별 포장구분 길이(복구수량 기초자료)를 계산합니다.
;;;   계산이 끝나면 전자제도_도우미.exe 가 바로 복구수량산출서 양식을 채워 엑셀을 엽니다.
;;;   (외부 프로그램·파이썬 설치가 필요 없습니다 - 전자제도_도우미.exe 안에 매핑 엔진이 들어 있습니다.)
;;;
;;;   [사용 전 확인]
;;;   • 도곽(FORM) 안의 종단면도 밴드 문자 예: LP 110mm PE (187.0M), A.S.P (67.0M), CON'C (69.0M)
;;;
;;;   [결과 (도면 폴더\MATX\)]
;;;   • PAVQ_구간 / PAVQ_집계 / PAVQ_63mm CSV, PAVQ_오류 txt (검토 필요 목록)
;;;   • 복구수량산출서_<도면명>.xlsx
;;;   • 도면 폴더에 저장할 수 없으면 C:\MATX\ 에 저장합니다.
;;; 기능설명서: PAVQ
;;;   모든 도곽의 종단면도에서 관경 구간과 포장 구간이 겹치는 길이를 관경별·포장구분별로 계산합니다.
;;;   • 관경 합계와 포장 합계가 다르면 '합계불일치'로 기록하고 도면에 빨간 원을 그립니다 (PAVQDEL 로 삭제).
;;;   • 연결관은 자재내역 표 또는 종단 인출선 값으로 따로 합산합니다.
;;;   • 평면도 63mm 는 집계표에 'LP 63mm PE' 행으로 포장구분별 합산합니다.
;;;   • 도면번호는 MP/LP 별로 도곽 순서(좌측 상단부터)대로 매깁니다.
;;; 기능설명서: PAVQDEL
;;;   PAVQ·PAVQMMA 가 그린 검토 표시(빨간 원, PAVQ#번호, MMA 표시)를 지웁니다.
;;; @end
;;;=====================================================================
;;; PAVQ.lsp  -  종단면도 관경별 포장구분 길이 산출 (복구수량 기초자료)
;;; AutoCAD LT 2026 / 순수 AutoLISP (ActiveX 미사용)
;;;
;;; 명령
;;;   PAVQ     : 모든 도곽(FORM)의 종단면도에서 관경 x 포장 길이 산출
;;;              -> 도면폴더\MATX\ 에 CSV 출력
;;;   PAVQCAL  : (선택) 관경/포장 밴드 문자의 레이어를 지정 (Enter = 전체)
;;;   PAVQDEL  : 검토 표시(빨간 원 + PAVQ#번호) 삭제
;;;
;;; 원리
;;;   1) 관경 밴드 문자  예) LP 110mm PE (187.0M)
;;;      포장 밴드 문자  예) A.S.P (67.0M) / CON'C (69.0M) / 칼라아스콘 (12.0M)
;;;      -> 포장구분은 캐드 문구 그대로 (괄호 앞 문자)
;;;   2) 각 밴드를 X 순으로 정렬해 적힌 길이를 0m부터 누적 -> 구간
;;;   3) 관경 구간 x 포장 구간의 겹침 길이 = 관경별 포장 길이
;;;   4) 관경합 <> 포장합 이면 산출방식 "합계불일치" + 도면에 빨간 원
;;;      (도면에 적힌 숫자만 사용 : 포장 숫자는 그대로, 관경 경계만 누적값)
;;;   5) 연결관 : "연결관" 이 들어간 문자를 도곽별로 찾아 관경별 별도 합산
;;;      - 문자에 길이가 있으면 종단 인출선  예) 연결관 63mm PE (5.0M), L=5.0M
;;;      - 길이가 없으면 자재내역 표 행     -> 같은 행 오른쪽(+X)의 규격/수량
;;;      - 자재내역에 연결관이 있으면 자재내역만 적용, 종단 값은 대조만
;;;      - 관경이 안 적힌 연결관은 자재내역 "관" 행의 관경 중
;;;        본관에 없는 관경으로 보완 (여러 개면 최소 관경, 오류목록에 근거 기록)
;;;      - 같은 관경 행에 합산 (없으면 관경 행 새로 생성)
;;;      - 포장은 그 도면에 A.S.P 가 있으면 A.S.P, 없으면 CON'C,
;;;        둘 다 없으면 그 도면에서 가장 긴 포장구분
;;;      - 구간 CSV 의 산출방식 = 연결관(자재내역) / 연결관(종단)
;;;
;;; 출력 (도면폴더\MATX\)
;;;   PAVQ_구간_<도면명>.csv : 도면번호/종단번호/관경/포장/길이 (연동용 원자료)
;;;   PAVQ_집계_<도면명>.csv : 도면번호 x 관경 행, 포장구분 열 (산출서용)
;;;   PAVQ_오류_<도면명>.txt : 검토 필요 목록
;;;   PAVQ_63mm_<도면명>.csv : 63mm 자재내역 연장 / 평면도 포장구분 상세 / 도면별 대조
;;;   (평면도 63mm 는 집계표에 "LP 63mm PE" 행으로 포장구분별 합산)
;;;   도면번호 = MP/LP 별도 순번 (MP-001, MP-002 ... / LP-001 ...)
;;;              도곽 순서(좌상단부터 우측)대로 매기며, 도곽 안 관경 문자의
;;;              종단 관경 밴드 문자의 압력으로 구분 (섞여 있으면 길이가 긴 쪽)
;;;=====================================================================

;;----------------------------- 설정 ----------------------------------
(setq *PQ-FORM*      "FORM"      ; 도곽 블럭 이름
      *PQ-FORM-LAYER* "FORM_"     ; 도곽 블럭이 없을 때 : 이 레이어의 닫힌 직사각형 폴리선을 도곽으로
      *PQ-FORM-MIN*  100.0        ; 도곽 직사각형 최소 가로·세로
      *PQ-TOL-SUM*   0.15        ; 관경합/포장합 허용오차(M)
      *PQ-MPP-DY*    3.5         ; 길이 없는 포장 문자(A.S.P)와 바로 위 관경 문자(LP 315mm PE(200.0M)) 세로 간격 한도 (글자높이 배)
      *PQ-CONN-OUT*  5.0         ; 종단 연결관 문자가 종단 범위(관경 밴드) 밖으로 이만큼 넘으면 상세도 등으로 보고 제외
      *PQ-DETAIL-LAYER* "*상세*" ; 이 레이어의 연결관 문자도 상세도로 보고 제외 (63mm 연결관은 집계)
      *PQ-CHK-LAYER* "PAVQ_CHK"  ; 검토 표시 레이어
      *PQ-LOCAL-DIR* "C:\\MATX\\"  ; 도면 폴더에 저장 못 할 때(경로가 너무 김, OneDrive 등) 대신 저장할 로컬 폴더
      *PQ-PATH-MAX*  250)         ; 경로 길이 한도 (한글 2바이트로 계산, Windows 260 바이트 제한)

;; 포장구분 : 사전 없이 캐드 문구 그대로 사용
;;   "A.S.P (67.0M)" -> "A.S.P" / "칼라아스콘 (12.0M)" -> "칼라아스콘"
;;   (마지막 괄호 앞 문자, 앞뒤 공백만 정리)
;; 아래 목록은 집계표 "열 순서"만 정함 (목록에 없는 구분은 뒤에 나온 순서대로)
(setq *PQ-PAVE-ORDER*
  '("A.S.P" "CON'C" "칼라아스콘" "투수블럭" "소형고압블럭" "보도블럭" "잡종지" "비포장"))

;; 연결관 포장 배정 우선순위 (대문자화, 공백 . ' ` - 제거 후 "일치" 비교)
(setq *PQ-CONN-PRI*
  '(("ASP" "아스팔트")      ; 1순위 A.S.P
    ("CONC" "콘크리트")))   ; 2순위 CON'C

;;------------------------- 굴착폭 (토량환산표) -------------------------
;; 굴착폭 = 토량환산표 1-LINE 터파기 "상단폭" (M)
;; 저압(mm) 관경 -> 환산표 관경 : 315->300, 225->200, 160->150, 110->100, 63->50
;; 중압(A) 관경은 그대로 (100A -> 100)
(setq *PQ-NOM-MM* '((315 . 300) (225 . 200) (160 . 150) (110 . 100) (63 . 50)))

;; 환산표 시트별 상단폭 ((환산표관경 . 상단폭) ...)
(setq *PQ-WIDTH*
  '(("ASP-LP" (500 . 1.22) (400 . 1.10) (300 . 1.02) (200 . 0.90) (150 . 0.84) (100 . 0.80) (50 . 0.80)) ; A.S.P-1LINE(LP)
    ("ASP-MP" (500 . 1.26) (400 . 1.14) (300 . 1.02) (200 . 0.90) (150 . 0.84) (100 . 0.80) (50 . 0.80)) ; A.S.P-1LINE(MP)
    ("보도블럭" (500 . 1.26) (400 . 1.14) (300 . 1.02) (200 . 0.90) (150 . 0.84) (100 . 0.80) (50 . 0.80)) ; 보도블럭-1LINE(MP,LP)
    ("사리도" (500 . 1.26) (400 . 1.14) (300 . 1.02) (200 . 0.90) (150 . 0.84) (100 . 0.80) (50 . 0.80)) ; 사리도(도로개설)-1LINE
    ("녹지"   (500 . 2.76) (400 . 2.60) (300 . 2.44) (200 . 2.28) (150 . 2.20) (100 . 2.12) (50 . 2.04)))) ; 법면,녹지-1LINE

;; 포장구분 -> 환산표 시트 (포장 이름에 단어가 들어 있으면 그 시트, 위에서부터 판단)
;;   해당 없음 -> A.S.P (A.S.P, CON'C, 칼라아스콘 등) : 압력에 따라 ASP-LP / ASP-MP
;;   법면,녹지-1LINE 은 포장구분이 "법면" 일 때만 적용
;;   녹지, 단지내(녹지), 도로개설 구간 -> 사리도(도로개설)-1LINE
(setq *PQ-PAVE-GROUP*
  '(("녹지"     "법면")
    ("보도블럭" "보도" "블럭" "블록" "BL")
    ("사리도"   "사리" "잡종지" "비포장" "토사" "자갈" "녹지" "도로개설")))

;; 63mm 포장구분 확인선 : 평면도 63mm 관 위에 포장구분별 색 폴리선 (사용자 검증용)
;;   PAVQ 를 다시 돌리면 이 레이어의 지난 확인선은 지우고 새로 그림
(setq *PQ-63-DRAW*       T
      *PQ-63-DRAW-LAYER* "0포장63"
      *PQ-63-DRAW-W*     0.2                ; 전역폭
      *PQ-63-DRAW-TXT*   0.6                ; 확인선 옆 반영 연장 문자 높이 (nil 이면 안 적음)
      ;; (색 단어...) : 최종 집계(복구수량산출서 요약표) 구분별 색
      ;;   포장 이름(대문자, 공백/./' 제거)에 단어가 들어 있으면 그 색, 위에서부터 판단 / 해당 없음 7(흰색)
      ;;   칼라아스콘은 사용자 선택에 따름 : 칼라아스콘(C) -> 자홍 / 미끄럼방지MMA(M)·A.S.P(A) -> A.S.P 색
      *PQ-63-DRAW-COLORS*
      '((6 "칼라")                                                ; 칼라아스콘 : 자홍
        (4 "ASP" "아스팔트" "아스콘" "MMA")                        ; A.S.P (MMA 포함) : 하늘색
        (8 "CON" "콘크리트")                                       ; CON'C : 8
        (21 "보도" "블럭" "블록" "BL")                             ; 보도 : 색상 21
        (5 "하천")                                                 ; 하천 : 파랑
        (30 "법면")                                                ; 법면 : 주황
        ;; 사리도로 집계되는 포장(비포장·사리·잡종지·토사·자갈·녹지·도로개설) : 모두 초록
        (3 "비포장" "사리" "잡종지" "토사" "자갈" "녹지" "도로개설")))

;; 굴착폭 보류 포장구분 (굴착폭 칸 비움, 오류목록에 "보류" 표시)
(setq *PQ-WIDTH-HOLD* '("하천"))

;; 하천 하월구간 : 종단 포장구분에 *PQ-RIVER-WORD* 가 있으면, 종단 관로(*PQ-RIVER-PIPE-LAYER*)가 직각으로 내려갔다 올라오는
;;   하월구간 전체를 포장구분에 관계없이 하천으로 집계 (연결관 제외). 하월구간 길이는 *PQ-RIVER-TXT* L= 문구와 대조
(setq *PQ-RIVER-WORD*       "하천"
      *PQ-RIVER-TXT*        "관보호공"
      *PQ-RIVER-PIPE-LAYER* "Q-종단가스관로"
      *PQ-RIVER-TOL*        0.5)   ; 직각 하월 폭과 관보호공 L 이 이 값(또는 5%) 안이면 같은 구간으로 봄

;; 63mm (인입관/연결관) : 포장구분 없이 자재내역 연장만 별도 집계
;;   T  = 63mm 연결관은 관경x포장 집계에서 빼고 PAVQ_63mm 파일로만 출력
(setq *PQ-63-SEPARATE* T)
;; 자재내역 63mm 관 행에서 제외할 품명 (이음관/부속)
(setq *PQ-63-EXCL* '("보호관" "슬리브" "소켓" "엘보" "캡" "TEE" "레듀" "리듀" "밸브" "새들" "T/F" "E/F" "전자" "이경"))

;; PAVQ 끝나면 복구수량산출서 엑셀 자동 작성 (전자제도_도우미.exe 에 집계 CSV 전달)
(setq *PQ-FORM-AUTO* T)

;; 연결관 포장 : 종단 인출선 측점이 들어 있는 포장 구간 (63mm 제외)
(setq *PQ-BAND-LAYER* "Q-종단그래프"   ; 관경 밴드 가로선 (밴드 시작/끝 X)
      *PQ-LEAD-LAYER* "Q-종단그래프"   ; 기울어진 인출선
      *PQ-CONN-TIE*   0.3              ; 포장 경계에서 이 거리 안이면 경계 위로 봄
      *PQ-CONN-PAIR*  10.0)            ; 경계 위 연결관은 이 거리 안의 다른 연결관(쌍) 포장을 따름

;; 종단 구분 : 종단마다 따로 그려진 X축(Q-종단선 수평선, 바로 위에 포장 문자) = 종단 1개
;;   측점 : X축 아래 측점표(Q-종단측점)의 누가거리 줄 (X 에 비례해 커지는 숫자 줄)
(setq *PQ-AXIS-LAYER*      "Q-종단선"
      *PQ-STA-TABLE-LAYER* "Q-종단측점")

;; 관경 밴드 화살표 블럭 레이어 (화살표가 블럭으로 그려진 경우)
(setq *PQ-ARROW-LAYER* "Q-종단그래프")

;; 포장구분 문자 대상 레이어 (wcmatch 형식, 여러 개는 쉼표)
(setq *PQ-PAVE-LAYER* "Q-종단TEXT")

;; 표준 관경 (이 값만 관경으로 인정 : 1.60 A.S.P -> 160A 같은 오인식 방지)
(setq *PQ-DIA-MM* '(16 20 25 32 40 50 63 75 90 110 125 140 160 180 200 225 250 280 315 355 400 450 500)
      *PQ-DIA-A*  '(15 20 25 32 40 50 65 80 100 125 150 200 250 300 350 400 450 500 550 600 650 700 750 800))

(setq *PQ-LAYERS* (getenv "PAVQ_LAYERS"))
(if (= *PQ-LAYERS* "") (setq *PQ-LAYERS* nil))

;;--------------------------- 문자열 도구 ------------------------------
(defun pq:trim (s) (vl-string-trim " \t" s))

(defun pq:str (x)
  (cond ((null x) "") ((= (type x) 'STR) x) (T (vl-princ-to-string x))))

(defun pq:join (lst sep / out)
  (if lst
    (progn
      (setq out (pq:str (car lst)))
      (foreach s (cdr lst) (setq out (strcat out sep (pq:str s))))
      out)
    ""))

(defun pq:sum (lst) (apply '+ (cons 0.0 lst)))

(defun pq:r2 (x) (rtos x 2 2))

;; 대문자화 + 구분기호 제거
(defun pq:norm (s / i c out)
  (setq s (strcase s) i 1 out "")
  (while (vl-string-search "%%C" s) (setq s (vl-string-subst "" "%%C" s)))
  (while (<= i (strlen s))
    (setq c (substr s i 1))
    (if (not (member c '(" " "." "'" "`" "-" "\t")))
      (setq out (strcat out c)))
    (setq i (1+ i)))
  out)

;; MTEXT 서식코드 제거 -> 줄 리스트
(defun pq:strip-mtext (s / i n c nx out lines)
  (setq i 1 n (strlen s) out "")
  (while (<= i n)
    (setq c (substr s i 1))
    (cond
      ((= c "\\")
       (setq nx (substr s (1+ i) 1))
       (cond
         ((= nx "P") (setq lines (cons out lines) out "" i (+ i 2)))
         ((member nx '("\\" "{" "}")) (setq out (strcat out nx) i (+ i 2)))
         ((member (strcase nx) '("L" "O" "K")) (setq i (+ i 2)))
         ((= nx "~") (setq out (strcat out " ") i (+ i 2)))
         (T
          (setq i (+ i 2))
          (while (and (<= i n) (/= (substr s i 1) ";")) (setq i (1+ i)))
          (setq i (1+ i)))))
      ((member c '("{" "}")) (setq i (1+ i)))
      (T (setq out (strcat out c) i (1+ i)))))
  (reverse (cons out lines)))

;; 마지막 괄호 안의 숫자 -> 길이 (없으면 nil)
(defun pq:len (s / p q sub i c num)
  (if (setq p (vl-string-position (ascii "(") s nil T))
    (progn
      (setq sub (substr s (+ p 2)))
      (if (setq q (vl-string-search ")" sub)) (setq sub (substr sub 1 q)))
      (setq num "" i 1)
      (while (<= i (strlen sub))
        (setq c (substr sub i 1))
        (if (or (wcmatch c "#") (= c ".")) (setq num (strcat num c)))
        (setq i (1+ i)))
      (if (and (> (strlen num) 0) (> (atof num) 0.0)) (atof num)))))

;; 관경 해석 -> (압력 관경값 단위 재질) 또는 nil
;;   LP 110mm PE -> ("LP" 110 "mm" "PE") / MP 100A PLP -> ("MP" 100 "A" "PLP")
(defun pq:pipe (raw / s p pr i c dia unit)
  (setq s (pq:norm raw))
  (if (setq p (vl-string-search "(" s)) (setq s (substr s 1 p)))
  (if (wcmatch s "LP#*,MP#*,HP#*")
    (progn
      (setq pr (substr s 1 2) i 3 dia "")
      (while (and (<= i (strlen s)) (wcmatch (setq c (substr s i 1)) "#"))
        (setq dia (strcat dia c) i (1+ i)))
      (cond
        ((= (substr s i 2) "MM") (setq unit "mm" i (+ i 2)))
        ((= (substr s i 1) "A")  (setq unit "A"  i (1+ i))))
      (if (and unit (> (strlen dia) 0))
        (list pr (atoi dia) unit (substr s i))))))

(defun pq:pipe-key (info)
  (strcat (nth 0 info) " " (itoa (nth 1 info)) (nth 2 info)
          (if (/= (nth 3 info) "") (strcat " " (nth 3 info)) "")))

;; 종단 관경 오기 보정 : 표준 관경(*PQ-DIA-MM* / *PQ-DIA-A*)이 아니고 자재내역에도 없는 관경
;;   -> 같은 도면 자재내역 관경 중 15% 이내로 가장 가까운 것으로 읽음  예) LP 255mm PE -> 225mm
(defun pq:fix-dia (items flines fi / mats pp d u std best bd new out msgs)
  (setq mats (mapcar 'car (pq:table-qty flines)))       ; ((관경 단위) ...)
  (foreach it items
    (if (and (eq (car it) 'P) (setq pp (nth 6 it)))
      (progn
        (setq d (nth 1 pp) u (strcase (nth 2 pp))
              std (if (= u "A") *PQ-DIA-A* *PQ-DIA-MM*) best nil bd nil)
        (if (and (numberp d) (not (member d std))
                 (not (vl-some '(lambda (m) (and (= (car m) d) (= (strcase (cadr m)) u))) mats)))
          (foreach m mats
            (if (and (= (strcase (cadr m)) u)
                     (<= (abs (- (car m) d)) (* 0.15 d))
                     (or (null bd) (< (abs (- (car m) d)) bd)))
              (setq best (car m) bd (abs (- (car m) d))))))
        (if best
          (progn
            (setq new (list (nth 0 pp) best (nth 2 pp) (nth 3 pp)))
            (if (not (member (list d best) msgs))
              (progn
                (setq msgs (cons (list d best) msgs))
                (pq:err fi nil nil nil
                        (strcat "종단 관경 [" (pq:trim (nth 7 it)) "] " (itoa d) (nth 2 pp)
                                " 은 표준 관경이 아니고 자재내역에도 없음 -> 자재내역 " (itoa best) (nth 2 pp) " 로 읽음 (확인)"))))
            (setq it (list (nth 0 it) (nth 1 it) (nth 2 it) (nth 3 it) (pq:pipe-key new) (nth 5 it) new (nth 7 it)))))))
    (setq out (cons it out)))
  (reverse out))

;;--------------------------- 도곽 검색 --------------------------------
(setq *PQ-BBCACHE* nil)

(defun pq:pts-bbox (pts / xs ys)
  (if pts
    (progn
      (setq xs (mapcar 'car pts) ys (mapcar 'cadr pts))
      (list (apply 'min xs) (apply 'min ys) (apply 'max xs) (apply 'max ys)))))

(defun pq:xf (p bp ins sx sy rot / dx dy)
  (setq dx (* sx (- (car p) (car bp)))
        dy (* sy (- (cadr p) (cadr bp))))
  (list (+ (car ins) (- (* dx (cos rot)) (* dy (sin rot))))
        (+ (cadr ins) (+ (* dx (sin rot)) (* dy (cos rot))))))

;; 블럭정의 bbox -> 삽입 객체 기준 4모서리 (WCS)
(defun pq:ins-corners (bb ed / bp ins sx sy rot)
  (setq bp  (cdr (assoc 10 (entget (tblobjname "BLOCK" (cdr (assoc 2 ed))))))
        ins (cdr (assoc 10 ed))
        sx  (cond ((cdr (assoc 41 ed))) (1.0))
        sy  (cond ((cdr (assoc 42 ed))) (1.0))
        rot (cond ((cdr (assoc 50 ed))) (0.0)))
  (mapcar '(lambda (p) (pq:xf p bp ins sx sy rot))
          (list (list (nth 0 bb) (nth 1 bb)) (list (nth 2 bb) (nth 1 bb))
                (list (nth 2 bb) (nth 3 bb)) (list (nth 0 bb) (nth 3 bb)))))

;; 블럭정의 내부 객체로 bbox 계산 (vla-getboundingbox 대체)
(defun pq:def-bbox (nm / hit e ed typ pts c r sub)
  (if (setq hit (assoc nm *PQ-BBCACHE*))
    (cdr hit)
    (progn
      (setq e (tblobjname "BLOCK" nm))
      (while (and e (setq e (entnext e)))
        (setq ed (entget e) typ (cdr (assoc 0 ed)))
        (cond
          ((= typ "LINE")
           (setq pts (cons (cdr (assoc 10 ed)) (cons (cdr (assoc 11 ed)) pts))))
          ((member typ '("LWPOLYLINE" "VERTEX" "POINT" "SOLID"))
           (foreach g ed
             (if (member (car g) '(10 11 12 13)) (setq pts (cons (cdr g) pts)))))
          ((member typ '("CIRCLE" "ARC"))
           (setq c (cdr (assoc 10 ed)) r (cdr (assoc 40 ed))
                 pts (cons (list (- (car c) r) (- (cadr c) r))
                           (cons (list (+ (car c) r) (+ (cadr c) r)) pts))))
          ((= typ "INSERT")
           (if (setq sub (pq:def-bbox (cdr (assoc 2 ed))))
             (setq pts (append (pq:ins-corners sub ed) pts))))))
      (setq pts (pq:pts-bbox pts))
      (setq *PQ-BBCACHE* (cons (cons nm pts) *PQ-BBCACHE*))
      pts)))

;; 동적블럭(*U) 원래 이름
(defun pq:effname (en / nm blk brec xd h r)
  (setq r (vl-catch-all-apply 'pq:effname0 (list en)))
  (if (vl-catch-all-error-p r) "" (pq:str r)))

(defun pq:effname0 (en / nm blk brec xd h)
  (setq nm (if en (pq:str (cdr (assoc 2 (entget en)))) ""))
  (if (wcmatch nm "`*U*")
    (progn
      (if (setq blk (tblobjname "BLOCK" nm))
        (setq brec (cdr (assoc 330 (entget blk)))))
      (if brec
        (setq xd (cdr (assoc -3 (entget brec '("AcDbBlockRepBTag"))))))
      (if xd (setq h (cdr (assoc 1005 (cdar xd)))))
      (if (and h (handent h))
        (setq nm (pq:str (cdr (assoc 2 (entget (handent h)))))))))
  nm)

(defun pq:lw-pts (ed / pts)
  (foreach g ed (if (= (car g) 10) (setq pts (cons (cdr g) pts))))
  (reverse pts))

;; FORM 이 없을 때 : 같은 크기 직사각형
(defun pq:rect-frames (/ sel ed bb w h tol ss i e2 b2 lst)
  (prompt "\nFORM 블럭이 없습니다. 도곽 대체 직사각형(폴리선) 하나를 선택하세요.")
  (setq sel (entsel "\n기준 직사각형 선택: "))
  (if (and sel (= (cdr (assoc 0 (setq ed (entget (car sel))))) "LWPOLYLINE"))
    (progn
      (setq bb  (pq:pts-bbox (pq:lw-pts ed))
            w   (- (nth 2 bb) (nth 0 bb))
            h   (- (nth 3 bb) (nth 1 bb))
            tol (* 0.01 (max w h)))
      (if (setq ss (ssget "X" '((0 . "LWPOLYLINE") (410 . "Model"))))
        (repeat (setq i (sslength ss))
          (setq e2 (entget (ssname ss (setq i (1- i))))
                b2 (pq:pts-bbox (pq:lw-pts e2)))
          (if (and (<= (cdr (assoc 90 e2)) 5)
                   (equal (- (nth 2 b2) (nth 0 b2)) w tol)
                   (equal (- (nth 3 b2) (nth 1 b2)) h tol))
            (setq lst (cons b2 lst)))))))
  lst)

;; 0.5 이내 중복 도곽 제거
(defun pq:dedup-frames (frames / out dup)
  (foreach f frames
    (setq dup nil)
    (foreach g out
      (if (and (equal (car f) (car g) 0.5) (equal (cadr f) (cadr g) 0.5))
        (setq dup T)))
    (if (not dup) (setq out (cons f out))))
  out)

;; 좌상단부터 우측 순서
(defun pq:sort-frames (frames / tol)
  (if frames
    (progn
      (setq tol (* 0.5 (- (nth 3 (car frames)) (nth 1 (car frames)))))
      (vl-sort frames
        '(lambda (a b)
           (if (> (abs (- (nth 3 a) (nth 3 b))) tol)
             (> (nth 3 a) (nth 3 b))
             (< (car a) (car b))))))))

(defun pq:get-frames (/ ss i en ed bb frames)
  (if (setq ss (ssget "X" '((0 . "INSERT") (410 . "Model"))))
    (repeat (setq i (sslength ss))
      (setq en (ssname ss (setq i (1- i))))
      (if (= (strcase (pq:effname en)) (strcase *PQ-FORM*))
        (progn
          (setq ed (entget en)
                bb (pq:def-bbox (cdr (assoc 2 ed))))
          (if bb (setq frames (cons (pq:pts-bbox (pq:ins-corners bb ed)) frames)))))))
  ;; FORM 블럭이 없으면 : 도곽 레이어(FORM_)의 닫힌 직사각형 폴리선 -> 그래도 없으면 직접 선택
  (if (not frames) (setq frames (pq:layer-frames)))
  (if (not frames) (setq frames (pq:rect-frames)))
  (pq:sort-frames (pq:dedup-frames frames)))

;; 도곽 레이어(*PQ-FORM-LAYER*)의 닫힌 직사각형 폴리선 (꼭짓점 4~5개, 가로·세로 *PQ-FORM-MIN* 이상)
;;   크기가 여러 가지면 가장 많은 크기(1% 오차)만 도곽으로
(defun pq:layer-frames (/ ss i ed bb w h cand grp g best)
  (if (and *PQ-FORM-LAYER*
           (setq ss (ssget "X" (list '(0 . "LWPOLYLINE") (cons 8 *PQ-FORM-LAYER*) '(410 . "Model")))))
    (repeat (setq i (sslength ss))
      (setq ed (entget (ssname ss (setq i (1- i)))))
      (if (and (<= 4 (cdr (assoc 90 ed)) 5)
               (or (= 1 (logand 1 (cond ((cdr (assoc 70 ed))) (0))))
                   (equal (car (pq:lw-pts ed)) (last (pq:lw-pts ed)) 0.01)))
        (progn
          (setq bb (pq:pts-bbox (pq:lw-pts ed)) w (- (nth 2 bb) (nth 0 bb)) h (- (nth 3 bb) (nth 1 bb)))
          (if (and (>= w *PQ-FORM-MIN*) (>= h *PQ-FORM-MIN*)) (setq cand (cons (list w h bb) cand)))))))
  ;; 크기별로 묶기
  (foreach c cand
    (if (setq g (vl-some '(lambda (x) (if (and (equal (car x) (car c) (* 0.01 (car c))) (equal (cadr x) (cadr c) (* 0.01 (cadr c)))) x)) grp))
      (setq grp (subst (list (car g) (cadr g) (cons (caddr c) (caddr g))) g grp))
      (setq grp (cons (list (car c) (cadr c) (list (caddr c))) grp))))
  (foreach g grp (if (or (null best) (> (length (caddr g)) (length (caddr best)))) (setq best g)))
  (if best
    (progn
      (princ (strcat "\nFORM 블럭이 없어 '" *PQ-FORM-LAYER* "' 레이어 직사각형 " (itoa (length (caddr best)))
                     "개를 도곽으로 사용 (" (rtos (car best) 2 1) " x " (rtos (cadr best) 2 1) ")"))
      (caddr best))))

;;--------------------------- 문자 수집 --------------------------------
;; 객체 1개 -> ((문자 중심X 중심Y 높이) ...)  MTEXT 는 줄 단위
(defun pq:text-lines (en / ed typ raw h p q tb w j72 j73 cx cy att ht col row top lines n k out lay)
  (setq ed  (entget en) typ (cdr (assoc 0 ed))
        h   (cond ((cdr (assoc 40 ed))) (1.0))
        lay (pq:str (cdr (assoc 8 ed)))
        *PQ-STAGE* (strcat "문자 수집 (핸들 " (pq:str (cdr (assoc 5 ed))) ")"))
  (cond
    ((= typ "TEXT")
     (setq raw (pq:str (cdr (assoc 1 ed)))
           p   (cdr (assoc 10 ed))
           q   (cdr (assoc 11 ed))
           tb  (textbox ed)
           w   (if tb (- (car (cadr tb)) (car (car tb))) 0.0)
           j72 (cond ((cdr (assoc 72 ed))) (0))
           j73 (cond ((cdr (assoc 73 ed))) (0)))
     (if (and (= j72 0) (= j73 0))
       (setq cx (+ (car p) (/ w 2.0)) cy (+ (cadr p) (/ h 2.0)))
       (setq cx (cond ((member j72 '(1 4)) (car q))
                      ((= j72 2) (- (car q) (/ w 2.0)))
                      ((member j72 '(3 5)) (/ (+ (car p) (car q)) 2.0))
                      (T (+ (car p) (/ w 2.0))))
             cy (cond ((= j72 4) (cadr q))
                      ((= j73 3) (- (cadr q) (/ h 2.0)))
                      ((= j73 2) (cadr q))
                      (T (+ (cadr q) (/ h 2.0))))))
     (list (list raw cx cy h lay (car p) (cadr p))))
    ((= typ "MTEXT")
     (setq raw "")
     (foreach g ed (if (= (car g) 3) (setq raw (strcat raw (cdr g)))))
     (setq raw   (strcat raw (pq:str (cdr (assoc 1 ed))))
           p     (cdr (assoc 10 ed))
           att   (cond ((cdr (assoc 71 ed))) (1))
           w     (cond ((cdr (assoc 42 ed))) ((cdr (assoc 41 ed))) (0.0))
           lines (pq:strip-mtext raw)
           n     (length lines)
           ht    (cond ((cdr (assoc 43 ed))) ((* h n 1.6)))
           col   (rem (1- att) 3)
           row   (/ (1- att) 3)
           cx    (+ (car p) (cond ((= col 0) (/ w 2.0)) ((= col 1) 0.0) (T (- (/ w 2.0)))))
           top   (+ (cadr p) (cond ((= row 0) 0.0) ((= row 1) (/ ht 2.0)) (T ht)))
           k     0)
     (foreach ln lines
       (if (/= (pq:trim ln) "")
         (setq out (cons (list ln cx (- top (* (+ k 0.5) (/ ht n))) h lay (car p) (cadr p)) out)))
       (setq k (1+ k)))
     (reverse out))))

;; 전체 문자 (레이어 제한 없음 : 연결관/자재내역 표는 다른 레이어일 수 있음)
;; 줄 = (문자 중심X 중심Y 높이 레이어 삽입점X)
(defun pq:all-text-lines (/ ss i res)
  (if (setq ss (ssget "X" '((0 . "TEXT,MTEXT") (410 . "Model"))))
    (repeat (setq i (sslength ss))
      (setq res (append (pq:text-lines (ssname ss (setq i (1- i)))) res))))
  res)

;; "(6.0M)" 처럼 괄호 길이만 있는 문자
(defun pq:len-only (raw / p)
  (and (pq:len raw)
       (setq p (vl-string-position (ascii "(") raw nil T))
       (= (pq:trim (substr raw 1 p)) "")))

;; 두 줄로 나뉜 밴드 문자 합치기
;;   예) CON'C          -> "CON'C (6.0M)"
;;       (6.0M)
;;   윗줄 : 길이 없는 문자, 아랫줄 : 괄호 길이만 있음
;;   (MTEXT 줄바꿈, TEXT 2개 모두 처리)
(defun pq:merge-split (lines / heads nums used uheads best bd d h out)
  (foreach ln lines
    (cond
      ((and (not (pq:len (car ln)))
            (/= (pq:trim (car ln)) "")
            (not (pq:num-only (car ln)))
            (not (vl-string-search "연결관" (pq:norm (car ln)))))
       (setq heads (cons ln heads)))
      ((pq:len-only (car ln))
       (setq nums (cons ln nums)))))
  (foreach hd heads
    (setq best nil bd nil h (cadddr hd))
    (foreach nm nums
      (setq d (- (caddr hd) (caddr nm)))          ; 윗줄 Y - 아랫줄 Y
      (if (and (not (member nm used))
               (> d (* 0.3 h)) (< d (* 2.5 h))
               (<= (abs (- (cadr hd) (cadr nm))) (* 2.0 h))
               (or (null bd) (< d bd)))
        (setq best nm bd d)))
    (if best
      (setq used   (cons best used)
            uheads (cons hd uheads)
            out    (cons (list (strcat (car hd) " " (pq:trim (car best)))
                               (cadr hd) (caddr hd) h (nth 4 hd) (nth 5 hd) (nth 6 hd))
                         out))))
  (append (vl-remove-if '(lambda (l) (or (member l uheads) (member l used))) lines)
          out))

;; 관경 문자에 길이가 있고 바로 아래 포장 문자에는 길이가 없는 경우
;;   예)      ③
;;     LP 315mm PE(200.0M)      <- 관경 + 길이
;;           A.S.P              <- 포장 (길이 없음)
;;   -> 포장 문자를 "A.S.P (200.0M)" 로 만들어 포장 구간으로 인식 (관경 문자는 그대로)
(defun pq:merge-pipe-pave (lines / pipes heads best bd d h out used L)
  (foreach ln lines
    (cond
      ((and (pq:pipe (car ln)) (pq:len (car ln)) (not (vl-string-search "연결관" (pq:norm (car ln)))))
       (setq pipes (cons ln pipes)))
      ((and (not (pq:len (car ln)))
            (/= (pq:trim (car ln)) "")
            (not (pq:num-only (car ln)))
            (pq:pave-name (car ln))
            (not (pq:pipe (car ln))))
       (setq heads (cons ln heads)))))
  (foreach hd heads
    (setq best nil bd nil h (cadddr hd))
    (foreach pp pipes
      (setq d (- (caddr pp) (caddr hd)))          ; 관경 Y - 포장 Y (관경이 위)
      (if (and (not (member pp used))
               (> d (* 0.3 h)) (< d (* *PQ-MPP-DY* h))
               (<= (abs (- (cadr hd) (cadr pp))) (* 3.0 h))
               (or (null bd) (< d bd)))
        (setq best pp bd d)))
    (if best
      (setq used (cons best used)
            L    (pq:len (car best))
            out  (cons (list hd (list (strcat (pq:trim (car hd)) " (" (rtos L 2 1) "M)")
                                      (cadr hd) (caddr hd) h (nth 4 hd) (nth 5 hd) (nth 6 hd) 'PQMERGE))
                       out))))
  (mapcar '(lambda (ln / r) (if (setq r (assoc ln out)) (cadr r) ln)) lines))

;; 항목 = (종류 X Y 높이 키 길이 관경정보 원문)
;;   종류 P=관경  V=괄호 길이가 있는 문자(포장 후보)
(defun pq:classify (ln / raw L pp pv)
  (setq raw (car ln) L (pq:len raw))
  (cond
    ((vl-string-search "연결관" (pq:norm raw)) nil)   ; 연결관은 pq:conn 에서 별도 처리
    ((setq pp (pq:pipe raw))
     (list 'P (cadr ln) (caddr ln) (cadddr ln) (pq:pipe-key pp) L pp raw))
    ((and L
          (wcmatch (strcase (pq:str (nth 4 ln))) (strcase *PQ-PAVE-LAYER*))
          (setq pv (pq:pave-name raw)))
     (list 'V (cadr ln) (caddr ln) (cadddr ln) pv L (if (eq (nth 7 ln) 'PQMERGE) 'M) raw))))

;; 포장구분 이름 : 마지막 괄호 앞 문자 그대로  예) "단지내(녹지) (16.0M)" -> "단지내(녹지)"
;;   "관" 이 들어가거나 LP/MP+숫자 가 있는 문자(인입관 LP63mm 등)는 포장이 아님 -> nil
;; 포장구분 바꿔 읽기 : 원문(정규화)에 단어가 있으면 그 포장구분으로
;;   예) "도로개설구간(A.S.P)(20.0M)" -> 비포장 (신설 도로 구간이라 기존 포장 없음)
;;   예) "화단(5.0M)" -> 보도블럭
(setq *PQ-PAVE-MAP* '(("도로개설" . "비포장")
                      ("화단"     . "보도블럭")))

(defun pq:pave-map (raw / n hit)
  (setq n (pq:norm raw))
  (foreach m *PQ-PAVE-MAP* (if (and (null hit) (vl-string-search (pq:norm (car m)) n)) (setq hit (cdr m))))
  hit)

(defun pq:pave-name (raw / p s)
  (setq s raw)
  (if (setq p (vl-string-position (ascii "(") s nil T)) (setq s (substr s 1 p)))
  (setq s (pq:trim (vl-string-translate "," " " s)))
  (if (and (/= s "") (not (pq:pipe-word s)))
    (cond ((pq:pave-map raw)) (s))))

;; 관 관련 문자는 포장구분에서 제외  예) 인입관 LP63mm, 공급관, LP 63mm
(defun pq:pipe-word (s / n)
  (setq n (pq:norm s))
  (or (vl-string-search "관" n)
      (wcmatch n "*LP#*,*MP#*,*HP#*")))

(defun pq:in-frame (it f)
  (and (>= (nth 1 it) (nth 0 f)) (<= (nth 1 it) (nth 2 f))
       (>= (nth 2 it) (nth 1 f)) (<= (nth 2 it) (nth 3 f))))

;; 같은 위치 겹친 중복 문자 제거
(defun pq:dedup-items (items / out dup)
  (foreach it items
    (setq dup nil)
    (foreach o out
      (if (and (= (nth 4 it) (nth 4 o))
               (equal (nth 5 it) (nth 5 o) 1e-6)
               (equal (nth 1 it) (nth 1 o) (* 0.2 (nth 3 it)))
               (equal (nth 2 it) (nth 2 o) (* 0.2 (nth 3 it))))
        (setq dup T)))
    (if (not dup) (setq out (cons it out))))
  (reverse out))

;;--------------------------- 종단 구성 --------------------------------
;; 포장(V) 문자를 Y 행으로 묶음 -> 행 1개 = 종단 1개
(defun pq:make-rows (items typ / vs rows cur)
  (setq vs (vl-sort (vl-remove-if-not '(lambda (a) (eq (car a) typ)) items)
                    '(lambda (a b) (> (nth 2 a) (nth 2 b)))))
  (foreach v vs
    (if (and cur (<= (abs (- (nth 2 v) (nth 2 (car cur)))) (nth 3 v)))
      (setq cur (cons v cur))
      (progn (if cur (setq rows (cons cur rows))) (setq cur (list v)))))
  (if cur (setq rows (cons cur rows)))
  (reverse rows))

;; 행 정보 (평균Y 최소X 최대X)
(defun pq:row-info (row / ys xs)
  (setq ys (mapcar '(lambda (a) (nth 2 a)) row)
        xs (mapcar 'cadr row))
  (list (/ (apply '+ ys) (length ys)) (apply 'min xs) (apply 'max xs)))

;; -> ((포장목록 관경목록 제외목록) ...)
;;   1) 괄호 길이가 있는 문자(V)를 Y 행으로 묶음
;;   2) 관경(P) : 행 바로 위의 가장 가까운 행에 붙임
;;      (포장 줄이 관경 문자보다 0.3h 이상 아래 : 길이 있는 관경 10h, 길이 없는 관경 2.5h 까지)
;;   3) 관경이 붙은 행만 종단으로 인정
;;   4) 같은 행의 다른 문자(표, 주기 등)는 관경 문자에서 가까운 순으로
;;      더해 관경합과 같아지는 데까지만 포장으로 사용
(defun pq:best-row (it infos / best bs k dy dx h sc up)
  ;; 점수 = 높이차(h 단위 반올림) 우선, 같으면 가로 거리 (가로 제한 없음)
  (setq k 0 h (nth 3 it) up (if (nth 5 it) 10.0 2.5))
  (foreach inf infos
    (setq dy (- (nth 2 it) (car inf))
          dx (cond ((< (nth 1 it) (nth 1 inf)) (- (nth 1 inf) (nth 1 it)))
                   ((> (nth 1 it) (nth 2 inf)) (- (nth 1 it) (nth 2 inf)))
                   (T 0.0))
          sc (+ (* 1.0e6 (fix (+ 0.5 (/ (abs dy) h)))) (/ dx h)))
    (if (and (>= dy (* 0.3 h)) (<= dy (* up h))
             (or (null bs) (< sc bs)))
      (setq best k bs sc))
    (setq k (1+ k)))
  best)

;; 부분합 탐색 : 가까운 문자부터 넣어보며 합이 target 이 되는 조합 -> (선택목록) / nil
(defun pq:subset (lst target / v r)
  (setq *PQ-NODES* (1+ *PQ-NODES*))
  (cond
    ((equal target 0.0 *PQ-TOL-SUM*) (list nil))
    ((or (null lst) (< target 0.0) (> *PQ-NODES* 200000)) nil)
    (T
     (setq v (car lst))
     (if (and (<= (nth 5 v) (+ target *PQ-TOL-SUM*))
              (setq r (pq:subset (cdr lst) (- target (nth 5 v)))))
       (list (cons v (car r)))
       (pq:subset (cdr lst) target)))))

;; 관경 문자 범위[x0,x1]에서 가까운 순 정렬
(defun pq:by-dist (lst x0 x1 / d)
  (mapcar 'cdr
    (vl-sort
      (mapcar '(lambda (v)
                 (setq d (cond ((< (cadr v) x0) (- x0 (cadr v)))
                               ((> (cadr v) x1) (- (cadr v) x1))
                               (T 0.0)))
                 (cons d v))
              lst)
      '(lambda (a b) (< (car a) (car b))))))

;; 관경합에 맞는 포장 문자 선택 -> (선택목록 . 제외목록)
;;   extra : 바로 아래(6h 이내) 다른 줄 문자 (칼라아스콘 처럼 아래로 빼서 쓴 문자) - 필요할 때만 사용
;;   같은 줄 문자를 관경 문자에서 가까운 순으로 정렬해 합이 관경합과 같은 조합을 찾음
;;   (중간에 끼어 있는 다른 숫자 문자도 건너뜀) / 못 찾으면 행 전체 사용 -> 합계불일치 표시
(defun pq:select-paves (row extra pipes / sp x0 x1 cands pool d nolen r sel n sv)
  (foreach p pipes (if (null (nth 5 p)) (setq nolen T)))
  ;; 길이 없는 관경 문자 : 관경이 1개면 아래 줄 다른 문자를 쓸 근거가 없으므로 같은 줄만
  ;;   관경이 여러 개면 바로 아래 포장 문자 길이로 보완한 합을 목표로 (아래로 뺀 칼라아스콘 등도 찾도록)
  (if (and nolen (null (cdr pipes)))
    (cons row nil)
    (progn
      (setq sv (pq:sum (mapcar '(lambda (a) (nth 5 a)) row))
            sp (pq:sum (mapcar '(lambda (p) (cond ((nth 5 p)) ((pq:guess-len p row (length pipes) sv)))) pipes))
            x0 (apply 'min (mapcar 'cadr pipes))
            x1 (apply 'max (mapcar 'cadr pipes))
            cands (append (pq:by-dist row x0 x1) (pq:by-dist extra x0 x1)))
      ;; 가까운 20개까지만 탐색
      (setq n 0)
      (foreach c cands (if (< n 20) (setq pool (cons c pool) n (1+ n))))
      (setq pool (reverse pool) *PQ-NODES* 0
            r (pq:subset pool sp))
      (if r
        (progn
          (setq sel (car r))
          (cons (vl-sort sel '(lambda (a b) (< (cadr a) (cadr b))))
                (vl-remove-if '(lambda (v) (member v sel)) row)))   ; 제외 보고는 같은 줄만
        (cons row nil)))))

(defun pq:profiles (items / rows infos asg k j best res pipes sp ry h extra)
  (setq rows  (pq:make-rows items 'V)
        infos (mapcar 'pq:row-info rows))
  (foreach it items
    (if (eq (car it) 'P)
      (if (setq best (pq:best-row it infos))
        (setq asg (cons (cons best it) asg)))))
  (setq k 0)
  (foreach row rows
    (setq pipes nil)
    (foreach a asg (if (= (car a) k) (setq pipes (cons (cdr a) pipes))))
    (if pipes
      (progn
        ;; 바로 아래 6h 이내 다른 줄의 문자 (관경이 붙지 않은 줄만)
        (setq ry (car (nth k infos)) h (nth 3 (car pipes)) extra nil j 0)
        (foreach r2 rows
          (if (and (/= j k)
                   (not (assoc j asg))
                   (< (car (nth j infos)) (- ry (* 0.3 h)))
                   (>= (car (nth j infos)) (- ry (* 6.0 h))))
            (setq extra (append extra r2)))
          (setq j (1+ j)))
        ;; 한 줄에 종단이 여러 개(옆으로 나란함) -> 관경 밴드 가로선 구획별로 따로 계산
        (foreach bx (pq:split-boxes row extra pipes)
          (setq sp (pq:select-paves (car bx) (cadr bx) (caddr bx)))
          (setq res (cons (list (car sp) (caddr bx) (cdr sp)) res)))))
    (setq k (1+ k)))
  (reverse res))

;; 문자 -> 가장 가까운 구획 (X 가 구획 안이면 거리 0)
(defun pq:box-of (it bxs / best bdd d)
  (foreach b bxs
    (setq d (cond ((< (cadr it) (car b)) (- (car b) (cadr it)))
                  ((> (cadr it) (cadr b)) (- (cadr it) (cadr b)))
                  (T 0.0)))
    (if (or (null bdd) (< d bdd)) (setq best b bdd d)))
  best)

;; 종단 구획 : 관경 밴드 가로선(Q-종단그래프, 끊긴 데서 나뉨) 중 관경 문자를 가로로 품는 것
;;   구획이 2개 이상이면 -> ((포장줄 아래줄 관경목록) ...) 구획별, 아니면 통째로 1개
(defun pq:split-boxes (row extra pipes / h ylo yhi bxs bd out)
  (setq h   (nth 3 (car pipes))
        ylo (- (apply 'min (mapcar 'caddr (append row extra))) h)
        yhi (+ (apply 'max (mapcar 'caddr pipes)) h))
  ;; 1순위 : 종단 X축 (종단마다 따로 그려짐) / 없으면 관경 밴드 가로선
  (setq bxs (pq:row-axes (append row extra pipes) h))
  (if (null bxs)
  (foreach p pipes
    (setq bd nil)
    (foreach hl *PQ-HLINES*
      (if (and (>= (caddr hl) ylo) (<= (caddr hl) yhi)
               (<= (car hl) (cadr p)) (>= (cadr hl) (cadr p))
               (or (null bd) (> (- (cadr hl) (car hl)) (- (cadr bd) (car bd)))))
        (setq bd hl)))
    (if (and bd (not (vl-some '(lambda (b) (and (equal (car b) (car bd) 0.01) (equal (cadr b) (cadr bd) 0.01))) bxs)))
      (setq bxs (cons bd bxs)))))
  (if (< (length bxs) 2)
    (list (list row extra pipes))
    (progn
      (setq bxs (vl-sort bxs '(lambda (a b) (< (car a) (car b)))))
      ;; 문자 X 가 구획 안이면 그 구획, 아니면 가장 가까운 구획
      (foreach b bxs
        (setq out (cons (list (vl-remove-if-not '(lambda (v) (eq (pq:box-of v bxs) b)) row)
                              (vl-remove-if-not '(lambda (v) (eq (pq:box-of v bxs) b)) extra)
                              (vl-remove-if-not '(lambda (p) (eq (pq:box-of p bxs) b)) pipes))
                        out)))
      ;; 관경 문자가 없는 구획은 버림
      (vl-remove-if '(lambda (o) (null (caddr o))) (reverse out)))))

;;--------------------------- 길이 계산 --------------------------------
(defun pq:set-len (it L)
  (list (nth 0 it) (nth 1 it) (nth 2 it) (nth 3 it) (nth 4 it) L (nth 6 it) (nth 7 it)))

;; 길이 없는 관경 문자(예: MTEXT 윗줄 "LP 225mm PE") 보완
(defun pq:guess-len (p vs nps sv / best bd d)
  (if (= nps 1)
    sv
    (progn
      (foreach v vs
        (setq d (abs (- (cadr v) (cadr p))))
        (if (and (<= d (* 2.0 (nth 3 p))) (or (null bd) (< d bd)))
          (setq best v bd d)))
      (if best (nth 5 best) 0.0))))

;; 누적 구간 : ((시작 끝 항목) ...)  단위 M
(defun pq:intervals-cum (lst / c out)
  (setq c 0.0)
  (foreach a lst
    (setq out (cons (list c (+ c (nth 5 a)) a) out)
          c   (+ c (nth 5 a))))
  (reverse out))

;; 마지막 구간 끝을 늘림 (합계 불일치 시 포장 숫자가 잘리지 않도록)
(defun pq:extend-last (ivs end / lst)
  (setq lst (reverse ivs))
  (if lst
    (reverse (cons (list (car (car lst)) (max (cadr (car lst)) end) (caddr (car lst)))
                   (cdr lst)))))

;; 관경구간 x 포장구간 겹침 -> ((관경키 포장 관경정보 길이) ...)
(defun pq:overlap (pis vis / res ov)
  (foreach pa pis
    (foreach va vis
      (setq ov (- (min (cadr pa) (cadr va)) (max (car pa) (car va))))
      (if (> ov 0.005)
        (setq res (cons (list (nth 4 (caddr pa)) (nth 4 (caddr va)) (nth 6 (caddr pa)) ov
                              (max (car pa) (car va)))
                        res)))))
  (reverse res))

;; -> (산출방식 관경합 포장합 결과 메모)
(defun pq:calc-profile (paves pipes / vs ps sv sp method res memo)
  (setq vs (vl-sort paves '(lambda (a b) (< (cadr a) (cadr b))))
        ps (vl-sort pipes '(lambda (a b) (< (cadr a) (cadr b))))
        sv (pq:sum (mapcar '(lambda (a) (nth 5 a)) vs)))
  (setq ps (mapcar '(lambda (p)
                      (if (nth 5 p) p
                        (progn
                          (if (> (length pipes) 1)
                            (setq memo (cons (strcat (nth 4 p) " 길이 없음 -> 아래 포장 문자 길이로 보완") memo)))
                          (pq:set-len p (pq:guess-len p vs (length pipes) sv)))))
                   ps))
  (setq sp (pq:sum (mapcar '(lambda (a) (nth 5 a)) ps)))
  ;; 길이 없는 포장 문자를 바로 위 관경 문자 길이로 채운 것(M)이 1개뿐이고 합이 안 맞으면
  ;;   그 포장 = 관경합 - 다른 포장합  (예 225mm 1.0M + 110mm 56.0M 아래 A.S.P 하나 -> A.S.P 57.0M)
  (if (and ps (not (equal sp sv *PQ-TOL-SUM*))
           (= 1 (length (vl-remove-if-not '(lambda (v) (eq (nth 6 v) 'M)) vs))))
    (progn
      (setq vs (mapcar '(lambda (v / L)
                          (if (eq (nth 6 v) 'M)
                            (progn
                              (setq L (- sp (- sv (nth 5 v))))
                              (if (> L 0.0)
                                (progn
                                  (setq memo (cons (strcat (nth 4 v) " 길이 없음 -> 관경합-다른 포장합 "
                                                           (rtos L 2 2) "M 적용") memo))
                                  (pq:set-len v L))
                                v))
                            v))
                       vs)
            sv (pq:sum (mapcar '(lambda (a) (nth 5 a)) vs)))))
  (cond
    ((null ps)
     (setq method "관경없음"))
    ((equal sp sv *PQ-TOL-SUM*)
     (setq method "누적"
           res (pq:overlap (pq:intervals-cum ps) (pq:intervals-cum vs))))
    (T
     ;; 합계 불일치 : 도면 숫자만 사용 (임의 소수 없음)
     ;;   포장 숫자는 그대로 유지, 마지막 관경 구간을 포장 끝까지 연장
     (setq method "합계불일치"
           res (pq:overlap (pq:extend-last (pq:intervals-cum ps) sv) (pq:intervals-cum vs)))))
  (list method sp sv res (reverse memo)))

;;------------------------ 하천 하월구간 ------------------------
;; 종단면도 포장구분에 "하천"이 있으면 : 하천을 건너는 하월구간(종단 관로가 직각으로 내려갔다 올라오는 구간)을
;;   포장구분에 관계없이 모두 하천으로 집계 (겹치는 포장 길이를 빼서 하천으로 옮김 -> 종단 합계·자재내역 그대로)
;;   연결관·63mm 는 종단 관 길이가 아니라서 해당 없음 (각자 포장구분 그대로)

;; "관보호공 L=21.0M" -> 21.0 / nil
(defun pq:river-L (raw / s k)
  (setq s (pq:nospace (strcase raw)))
  (if (setq k (vl-string-search "=" s))
    (progn
      (setq s (substr s (+ k 2)))
      (if (and (> (strlen s) 0) (wcmatch (substr s 1 1) "#")) (atof s)))))

;; 종단 관로 레이어 선분 -> 직각 하월 끝 후보 ((X 아래끝점 방향) ...)  방향 1 = 아래끝에서 +X 로 꺾임, -1 = -X 로
(defun pq:river-verts (xmin xmax ylo yhi / segs res a b lo hi)
  (foreach ed (pq:collect-x "LWPOLYLINE,LINE" *PQ-RIVER-PIPE-LAYER*)
    (foreach sg (pq:segs (pq:ent-pts ed))
      (if (and (>= (min (car (car sg)) (car (cadr sg))) (- xmin 0.5))
               (<= (max (car (car sg)) (car (cadr sg))) (+ xmax 0.5))
               (>= (max (cadr (car sg)) (cadr (cadr sg))) ylo)
               (<= (min (cadr (car sg)) (cadr (cadr sg))) yhi))
        (setq segs (cons sg segs)))))
  (foreach sg segs
    (setq a (car sg) b (cadr sg))
    (if (and (< (abs (- (car a) (car b))) 0.02) (> (abs (- (cadr a) (cadr b))) 0.3))
      (progn
        (setq lo (if (< (cadr a) (cadr b)) a b))
        ;; 아래 끝에서 옆으로(가로가 더 긴) 나가는 선분 -> 꺾이는 방향
        (foreach s2 segs
          (if (not (eq s2 sg))
            (foreach k (list (list (car s2) (cadr s2)) (list (cadr s2) (car s2)))
              (if (and (< (distance (car k) lo) 0.05)
                       (> (abs (- (car (cadr k)) (car (car k)))) (abs (- (cadr (cadr k)) (cadr (car k))))))
                (setq res (cons (list (car lo) lo (if (> (car (cadr k)) (car (car k))) 1 -1)) res)))))))))
  res)

;; 하월구간 찾기 -> (X시작 X끝 문구길이 근거) / nil
;;   paves : 이 종단의 포장 문자, sg : pq:segments 결과, sc : 종단 가로 축척(도면 단위/M)
(defun pq:river-find (paves sg flines sc / vh xh yv h xmin xmax txt L lefts rights best bd d w res)
  (setq vh (car (vl-remove-if-not '(lambda (v) (vl-string-search *PQ-RIVER-WORD* (pq:norm (nth 4 v)))) paves)))
  (if vh
    (progn
      (setq xh (cadr vh) yv (caddr vh) h (nth 3 vh)
            xmin (if sg (nth 2 sg) (apply 'min (mapcar 'cadr paves)))
            xmax (if sg (nth 3 sg) (apply 'max (mapcar 'cadr paves))))
      ;; 관보호공 L= 문구 : 이 종단 X 범위 안, 포장 문자 줄 위쪽, 하천 문자에 가장 가까운 것
      (foreach a flines
        (if (and (vl-string-search *PQ-RIVER-TXT* (pq:norm (car a)))
                 (pq:river-L (car a))
                 (>= (nth 1 a) (- xmin 1.0)) (<= (nth 1 a) (+ xmax 1.0))
                 (>= (nth 2 a) (- yv h)) (<= (nth 2 a) (+ yv (* 25.0 h)))
                 (or (null txt) (< (abs (- (nth 1 a) xh)) (abs (- (nth 1 txt) xh)))))
          (setq txt a)))
      (setq L (if txt (pq:river-L (car txt))))
      ;; 직각 하월 : 왼쪽 수직선(아래서 +X 로 꺾임) ~ 오른쪽 수직선(아래서 -X 로 꺾임), 하천 문자를 사이에 둠
      (foreach v (pq:river-verts xmin xmax (- yv h) (+ yv (* 50.0 h)))
        (cond ((and (= (caddr v) 1) (<= (car v) (+ xh 0.01))) (setq lefts (cons v lefts)))
              ((and (= (caddr v) -1) (>= (car v) (- xh 0.01))) (setq rights (cons v rights)))))
      (foreach a lefts
        (foreach b rights
          (if (> (car b) (car a))
            (progn
              (setq w (/ (- (car b) (car a)) sc)
                    ;; 문구 길이가 있으면 가장 비슷한 것, 없으면 가장 좁은 것(하천 문자 바로 양옆)
                    d (if L (abs (- w L)) w))
              (if (and (or (null L) (<= (abs (- w L)) (max *PQ-RIVER-TOL* (* 0.05 L))))
                       (or (null bd) (< d bd)))
                (setq best (list (car a) (car b)) bd d))))))
      (cond
        (best (list (car best) (cadr best) L (if L "직각 하월 + 관보호공 문구" "직각 하월")))
        (L (list (- (nth 1 txt) (* 0.5 L sc)) (+ (nth 1 txt) (* 0.5 L sc)) L "관보호공 문구 위치(가운데 ± L/2)"))))))

;; calc 의 관경x포장 결과에 하천 하월구간 적용 -> (새 calc 메모)
(defun pq:river-apply (calc paves pipes sg flines / vs ivs pint sc vh rv x2c R0 R1 hk o s e out add parts nm memo bnds)
  (setq vs (vl-sort paves '(lambda (a b) (< (cadr a) (cadr b))))
        ivs (pq:intervals-cum vs)
        pint (if sg (nth 5 sg))
        sc (cond ((and sg (nth 7 sg) (> (nth 7 sg) 0.0)) (nth 7 sg)) (1.0))
        vh (car (vl-remove-if-not '(lambda (v) (vl-string-search *PQ-RIVER-WORD* (pq:norm (nth 4 (caddr v))))) ivs)))
  (if (and vh calc (nth 3 calc) (setq rv (pq:river-find paves sg flines sc)))
    (progn
      ;; 종단 X -> 누적 길이(M) : 포장 구간 X(밴드)와 포장 순서가 맞으면 그 구간 안에서 비례, 아니면 하천 문자 기준
      (setq x2c (if (and pint (= (length pint) (length ivs)))
                  '(lambda (x / k r)
                     (setq k 0)
                     (foreach p pint
                       (if (and (null r) (>= x (- (car p) 1e-6)) (<= x (+ (cadr p) 1e-6)))
                         (setq r (+ (car (nth k ivs))
                                    (* (- x (car p)) (/ (- (cadr (nth k ivs)) (car (nth k ivs)))
                                                        (max 1e-9 (- (cadr p) (car p))))))))
                       (setq k (1+ k)))
                     (cond (r)
                           ((< x (car (car pint))) (- (car (car ivs)) (/ (- (car (car pint)) x) sc)))
                           (T (+ (cadr (last ivs)) (/ (- x (cadr (last pint))) sc)))))
                  '(lambda (x) (+ (* 0.5 (+ (car vh) (cadr vh))) (/ (- x (cadr (caddr vh))) sc)))))
      ;; 연결관 배정용 : 하월구간 종단 X (경계 위 연결관은 하천 밖 포장으로)
      (setq *PQ-RIVER-X* (cons (list (car rv) (cadr rv)) *PQ-RIVER-X*))
      (setq R0 (apply x2c (list (car rv))) R1 (apply x2c (list (cadr rv))))
      ;; 포장 경계에 0.05M 안이면 맞춤 / 하천 포장 구간은 꼭 포함
      (setq bnds (apply 'append (mapcar '(lambda (i) (list (car i) (cadr i))) ivs)))
      (foreach b bnds
        (if (< (abs (- R0 b)) 0.05) (setq R0 b))
        (if (< (abs (- R1 b)) 0.05) (setq R1 b)))
      (setq R0 (min R0 (car vh)) R1 (max R1 (cadr vh))
            nm (nth 4 (caddr vh)))
      ;; 겹치는 길이를 빼고 관경별 하천 행으로
      (foreach r (nth 3 calc)
        (setq s (cond ((nth 4 r)) (0.0)) e (+ s (cadddr r))
              o (- (min e R1) (max s R0)))
        (if (> o 0.005)
          (progn
            (setq parts (cons (strcat (cadr r) " " (rtos o 2 2)) parts))
            (if (> (- (cadddr r) o) 0.005)
              (setq out (cons (list (car r) (cadr r) (caddr r) (- (cadddr r) o) (if (< s R0) s R1)) out)))
            (if (setq hk (assoc (car r) add))
              (setq add (subst (list (car r) (+ (cadr hk) o) (caddr hk) (min (cadddr hk) (max s R0))) hk add))
              (setq add (cons (list (car r) o (caddr r) (max s R0)) add))))
          (setq out (cons r out))))
      (foreach a add
        (setq out (cons (list (car a) nm (caddr a) (cadr a) (cadddr a)) out)))
      (setq out (mapcar '(lambda (i) (nth i out))
                        (vl-sort-i out '(lambda (a b) (< (cond ((nth 4 a)) (0.0)) (cond ((nth 4 b)) (0.0)))))))
      (setq memo (strcat "하천 하월구간 " (rtos (- R1 R0) 2 2) "M = " (pq:join (reverse parts) " + ")
                         " -> 모두 [" nm "] 로 집계 (" (nth 3 rv)
                         (if (caddr rv) (strcat ", 관보호공 L=" (rtos (caddr rv) 2 2) "M") "") ")"))
      (if (and (caddr rv) (> (abs (- (- R1 R0) (caddr rv))) 0.1))
        (setq memo (strcat memo " / 관보호공 길이와 " (rtos (- (- R1 R0) (caddr rv)) 2 2) "M 차이 (확인)")))
      (list (list (nth 0 calc) (nth 1 calc) (nth 2 calc) out (nth 4 calc)) memo))
    (list calc nil)))

;;------------------------ 관경 밴드 구간(화살표) ----------------------
;; 채워진 화살표 후보 -> ((X Y 크기) ...)
;;   SOLID/TRACE, 폭이 있는 폴리선 구간, DIMENSION 치수 경계점,
;;   *PQ-ARROW-LAYER* 레이어의 블럭 (A$C... 같은 화살표 블럭) : 블럭 범위 중심
(defun pq:insert-marks (/ ss i en ed bb c res)
  (if (setq ss (ssget "X" (list '(0 . "INSERT") (cons 8 *PQ-ARROW-LAYER*) '(410 . "Model"))))
    (repeat (setq i (sslength ss))
      (setq en (ssname ss (setq i (1- i))) ed (entget en)
            bb (pq:def-bbox (cdr (assoc 2 ed))))
      (if bb
        (setq c   (pq:pts-bbox (pq:ins-corners bb ed))
              res (cons (list (/ (+ (nth 0 c) (nth 2 c)) 2.0) (/ (+ (nth 1 c) (nth 3 c)) 2.0)
                              (max (- (nth 2 c) (nth 0 c)) (- (nth 3 c) (nth 1 c))))
                        res))
        (setq res (cons (list (car (cdr (assoc 10 ed))) (cadr (cdr (assoc 10 ed))) 0.0) res)))))
  res)

(defun pq:arrow-marks (/ ss i ed typ pts res vs v sw ew cw a b)
  (if (setq ss (ssget "X" '((0 . "SOLID,TRACE,LWPOLYLINE,DIMENSION") (410 . "Model"))))
    (repeat (setq i (sslength ss))
      (setq ed (entget (ssname ss (setq i (1- i)))) typ (cdr (assoc 0 ed)))
      (cond
        ((member typ '("SOLID" "TRACE"))
         (setq pts nil)
         (foreach g ed (if (member (car g) '(10 11 12 13)) (setq pts (cons (cdr g) pts))))
         (setq a (pq:pts-bbox pts))
         (setq res (cons (list (/ (+ (nth 0 a) (nth 2 a)) 2.0) (/ (+ (nth 1 a) (nth 3 a)) 2.0)
                               (max (- (nth 2 a) (nth 0 a)) (- (nth 3 a) (nth 1 a))))
                         res)))
        ((= typ "LWPOLYLINE")
         ;; 꼭짓점별 (점 시작폭 끝폭)
         (setq vs nil cw (cond ((cdr (assoc 43 ed))) (0.0)))
         (foreach g ed
           (cond ((= (car g) 10) (setq vs (cons (list (cdr g) cw cw) vs)))
                 ((and vs (= (car g) 40)) (setq vs (cons (list (car (car vs)) (cdr g) (caddr (car vs))) (cdr vs))))
                 ((and vs (= (car g) 41)) (setq vs (cons (list (car (car vs)) (cadr (car vs)) (cdr g)) (cdr vs))))))
         (setq vs (reverse vs))
         (while (cadr vs)
           (setq v (car vs) a (car v) b (car (cadr vs)))
           (if (or (> (cadr v) 0.0) (> (caddr v) 0.0))
             (setq res (cons (list (/ (+ (car a) (car b)) 2.0) (/ (+ (cadr a) (cadr b)) 2.0)
                                   (distance (list (car a) (cadr a)) (list (car b) (cadr b))))
                             res)))
           (setq vs (cdr vs))))
        ((= typ "DIMENSION")
         (if (and (assoc 13 ed) (assoc 14 ed))
           (setq res (cons (list (car (cdr (assoc 13 ed))) (cadr (cdr (assoc 10 ed))) 0.0)
                           (cons (list (car (cdr (assoc 14 ed))) (cadr (cdr (assoc 10 ed))) 0.0) res))))))))
  res)

;; 관경 2개 사이 경계 : 길이 비례 추정 위치
(defun pq:wsplit (a b / la lb)
  (setq la (cond ((nth 5 a)) (1.0)) lb (cond ((nth 5 b)) (1.0)))
  (+ (cadr a) (* (- (cadr b) (cadr a)) (/ la (+ la lb)))))

;; 종단 1개의 관경 구간 -> (Y하한 Y상한 X최소 X최대 ((X시작 X끝 관경정보 근거) ...))
;;   경계 = 두 관경 문자 사이의 밴드 화살표 (추정 위치에서 가장 가까운 화살표 + 3h 이내 화살표 평균)
;;   화살표가 없으면 관경 길이 비례 위치 ("경계 추정")
(defun pq:segments (pipes paves / ps h ypipe ypave ylo yhi mk lst a b cs est near bx bnds srcs segs prev k xs
                                   hls ba bb band ylo2 yhi2 sv sc c pint bls bp bands)
  (setq ps    (vl-sort pipes '(lambda (a b) (< (cadr a) (cadr b))))
        h     (nth 3 (car ps))
        ypipe (/ (apply '+ (mapcar 'caddr ps)) (length ps))
        ypave (/ (apply '+ (mapcar 'caddr paves)) (length paves))
        ylo   (- ypave (* 0.5 h))
        yhi   (+ ypipe (* 0.5 h))
        mk    (vl-remove-if-not
                '(lambda (m) (and (>= (cadr m) ylo) (<= (cadr m) yhi) (<= (caddr m) (* 4.0 h))))
                *PQ-MARKS*)
        lst   ps)
  ;; 밴드 가로선 (관경 문자 ~ 포장 문자 높이)
  (setq ylo2 (- (apply 'min (mapcar 'caddr paves)) h)
        yhi2 (+ (apply 'max (mapcar 'caddr ps)) h)
        hls  (vl-remove-if-not '(lambda (hl) (and (>= (caddr hl) ylo2) (<= (caddr hl) yhi2))) *PQ-HLINES*))
  ;; 화살표 블럭은 블럭 범위 중심이 아니라 화살표 끝(밴드 가로선 끝점)으로 맞춤
  ;;   (A$C... 반쪽 화살표 블럭 : 중심은 끝에서 화살표 길이의 절반만큼 떨어져 있음)
  (setq mk (mapcar '(lambda (m / best bd d)
                      (foreach hl hls
                        (foreach x (list (car hl) (cadr hl))
                          (setq d (abs (- x (car m))))
                          (if (and (<= d (max 0.3 (caddr m))) (or (null bd) (< d bd))) (setq best x bd d))))
                      (if best (cons best (cdr m)) m))
                   mk))
  (while (cadr lst)
    (setq a (car lst) b (cadr lst)
          ba (pq:own-band (cadr a) hls)
          bb (pq:own-band (cadr b) hls)
          est (pq:wsplit a b)
          cs (vl-remove-if-not '(lambda (m) (and (> (car m) (cadr a)) (< (car m) (cadr b)))) mk)
          near nil)
    (foreach m cs
      (if (or (null near) (< (abs (- (car m) est)) (abs (- (car near) est)))) (setq near m)))
    (cond
      ;; 관경마다 따로 그린 밴드선(양끝 화살표) : 앞 관경 선 끝 ~ 뒤 관경 선 시작의 가운데
      ((and ba bb (not (equal ba bb 1e-6)) (<= (cadr ba) (+ (car bb) 0.05)))
       (setq bx (/ (+ (cadr ba) (car bb)) 2.0) srcs (cons "관경 밴드선 경계" srcs)))
      (near
       (setq cs (vl-remove-if-not '(lambda (m) (<= (abs (- (car m) (car near))) (* 3.0 h))) cs))
       (setq bx (/ (apply '+ (mapcar 'car cs)) (length cs)) srcs (cons "화살표 경계" srcs)))
      (T (setq bx est srcs (cons "경계 추정" srcs))))
    (setq bnds (cons bx bnds) lst (cdr lst)))
  ;; 관경 1개 : 경계 없음 (빈 목록에 nth 를 쓰지 않도록 따로 처리)
  (if (null (cdr ps))
    (setq segs (list (list nil nil (nth 6 (car ps)) "관경 1개")))
    (progn
      (setq bnds (reverse bnds) srcs (reverse srcs) prev nil k 0)
      (foreach p ps
        (setq segs (cons (list prev
                               (if (< k (length bnds)) (nth k bnds))
                               (nth 6 p)
                               (if (< k (length srcs)) (nth k srcs) (last srcs)))
                         segs)
              prev (if (< k (length bnds)) (nth k bnds))
              k (1+ k)))
      (setq segs (reverse segs))))
  ;; 관경 밴드 가로선 -> 밴드 시작/끝 X, 축척 -> 포장 구간 X
  ;;   한 도곽에 종단이 여러 개이고 포장 문자 줄이 같은 높이면 한 행으로 묶이므로
  ;;   관경 문자마다 자기 밴드(그 문자를 가로로 품는 가장 긴 가로선)를 찾고, 밴드별로 포장 구간을 만듦
  (setq ylo2 (- (apply 'min (mapcar 'caddr paves)) h)
        yhi2 (+ (apply 'max (mapcar 'caddr ps)) h))
  (foreach p ps
    (setq band nil)
    (foreach hl *PQ-HLINES*
      (if (and (>= (caddr hl) ylo2) (<= (caddr hl) yhi2)
               (<= (car hl) (cadr p)) (>= (cadr hl) (cadr p))
               (or (null band) (> (- (cadr hl) (car hl)) (- (cadr band) (car band)))))
        (setq band hl)))
    (if (and band (not (member band bls))) (setq bls (cons band bls))))
  (setq bls (vl-sort bls '(lambda (a b) (< (car a) (car b)))))
  (foreach bd bls
    (setq bp (vl-remove-if-not '(lambda (v) (and (>= (cadr v) (- (car bd) 1.0)) (<= (cadr v) (+ (cadr bd) 1.0)))) paves)
          sv 0.0 c 0.0)
    (foreach v bp (setq sv (+ sv (nth 5 v))))
    (if (> sv 0.0)
      (progn
        (setq sc (/ (- (cadr bd) (car bd)) sv))
        (foreach v (vl-sort bp '(lambda (a b) (< (cadr a) (cadr b))))
          (setq pint (cons (list (+ (car bd) (* c sc)) (+ (car bd) (* (+ c (nth 5 v)) sc)) (nth 4 v)) pint)
                c (+ c (nth 5 v))))
        (setq bands (cons (list (car bd) (cadr bd) sc) bands)))))
  (setq pint (reverse pint) bands (reverse bands))
  ;; 종단의 X 범위 : 이 종단의 관경/포장 문자 + 밴드선 끝만 (화살표 표시 mk 는 넣지 않음)
  ;;   mk 는 같은 높이의 모든 화살표라, 같은 도곽에 나란히 놓인 다른 종단의 화살표까지 들어가
  ;;   X 범위가 옆 종단을 덮어 버림 -> 연결관이 엉뚱한 종단(관경/포장)으로 잡히던 원인
  (setq xs (append (mapcar 'cadr ps) (mapcar 'cadr paves)
                   (apply 'append (mapcar '(lambda (b) (list (car b) (cadr b))) bands))))
  ;; (ylo yhi X최소 X최대 관경구간 포장구간 첫밴드X0 첫밴드축척 ((X0 X1 축척) ...))
  (list ylo yhi (apply 'min xs) (apply 'max xs) segs pint
        (if bands (car (car bands))) (if bands (caddr (car bands))) bands))

;; X 를 가로로 품는 밴드 가로선 중 가장 짧은 것 (관경마다 따로 그린 선) / nil
(defun pq:own-band (x hls / best)
  (foreach hl hls
    (if (and (<= (- (car hl) 0.05) x) (>= (+ (cadr hl) 0.05) x)
             (or (null best) (< (- (cadr hl) (car hl)) (- (cadr best) (car best)))))
      (setq best hl)))
  best)

;; 관경 밴드 가로선 후보 -> ((X최소 X최대 Y) ...)
;; 종단 X축 후보 : *PQ-AXIS-LAYER* 의 수평선 -> ((X최소 X최대 Y) ...)
(defun pq:axes (/ res pts ys)
  (foreach ed (pq:collect "LWPOLYLINE,LINE" *PQ-AXIS-LAYER*)
    (setq pts (pq:ent-pts ed) ys (mapcar 'cadr pts))
    (if (and (cdr pts) (< (- (apply 'max ys) (apply 'min ys)) 0.01) (> (pq:pl-len pts) 3.0))
      (setq res (cons (list (apply 'min (mapcar 'car pts)) (apply 'max (mapcar 'car pts)) (car ys)) res))))
  res)

;; 포장 줄(row, extra)과 관경(pipes) 아래 X축들 -> 겹친 중복(같은 높이, 절반 이상 겹침)은 긴 것 하나만
(defun pq:row-axes (items h / ylo xs0 xs1 cand out dup ov)
  (setq ylo (apply 'min (mapcar 'caddr items))
        xs0 (apply 'min (mapcar 'cadr items))
        xs1 (apply 'max (mapcar 'cadr items)))
  (foreach a *PQ-AXES*
    (if (and (< (caddr a) ylo) (<= (- ylo (caddr a)) (* 4.0 h))
             (<= (car a) (+ xs1 1.0)) (>= (cadr a) (- xs0 1.0))
             (vl-some '(lambda (it) (and (>= (cadr it) (- (car a) 1.0)) (<= (cadr it) (+ (cadr a) 1.0)))) items))
      (setq cand (cons a cand))))
  (foreach a (vl-sort cand '(lambda (a b) (> (- (cadr a) (car a)) (- (cadr b) (car b)))))
    (setq dup nil)
    (foreach b out
      (setq ov (- (min (cadr a) (cadr b)) (max (car a) (car b))))
      (if (and (< (abs (- (caddr a) (caddr b))) 0.5)
               (> ov (* 0.5 (min (- (cadr a) (car a)) (- (cadr b) (car b))))))
        (setq dup T)))
    (if (not dup) (setq out (cons a out))))
  (vl-sort out '(lambda (a b) (< (car a) (car b)))))

;; X축의 누가거리 줄 -> ((X . 측점) ...) / nil   (flines : 도곽 문자)
;;   X축 아래 60 이내 *PQ-STA-TABLE-LAYER* 숫자 문자를 줄로 묶고,
;;   X 순으로 계속 커지며 X 에 비례(기울기 0.2~5, 직선에서 0.6 이내)하는 줄 중 칸이 가장 많은 줄
(defun pq:axis-chain (ax flines / hit its rows r vs xs sl ok best v0 x0)
  (if (setq hit (assoc ax *PQ-ACHAIN*))
    (cdr hit)
    (progn
      (foreach ln flines
        (if (and (wcmatch (strcase (pq:str (nth 4 ln))) (strcase *PQ-STA-TABLE-LAYER*))
                 (pq:num-only (car ln))
                 (>= (cadr ln) (- (car ax) 1.0)) (<= (cadr ln) (+ (cadr ax) 1.0))
                 (< (caddr ln) (caddr ax)) (> (caddr ln) (- (caddr ax) 60.0)))
          (progn
            (setq r nil)
            (foreach rw rows (if (<= (abs (- (car rw) (caddr ln))) 0.3) (setq r rw)))
            (if r
              (setq rows (subst (cons (car r) (cons ln (cdr r))) r rows))
              (setq rows (cons (list (caddr ln) ln) rows))))))
      (foreach rw rows
        (setq its (vl-sort (cdr rw) '(lambda (a b) (< (cadr a) (cadr b))))
              vs  (mapcar '(lambda (a) (atof (pq:trim (car a)))) its)
              xs  (mapcar 'cadr its)
              ok  (cdr its))
        (if ok
          (progn
            (setq v0 (car vs) x0 (car xs))
            (foreach v (cdr vs) (if (<= v v0) (setq ok nil)) (setq v0 v))
            (setq v0 (car vs))))
        (if (and ok (> (- (last xs) x0) 1e-6))
          (progn
            (setq sl (/ (- (last vs) v0) (- (last xs) x0)))
            (if (or (< sl 0.2) (> sl 5.0)) (setq ok nil))
            (if ok
              (mapcar '(lambda (v x) (if (> (abs (- v (+ v0 (* sl (- x x0))))) 0.6) (setq ok nil))) vs xs))
            (if (and ok (or (null best) (> (length its) (length best))))
              (setq best (mapcar 'cons xs vs))))))
      (setq *PQ-ACHAIN* (cons (cons ax best) *PQ-ACHAIN*))
      best)))

;; 누가거리 줄로 X -> 측점 (구간 보간, 양 끝 밖은 끝 구간 연장)
(defun pq:chain-at (ch x / a b lst)
  (setq a (car ch) b (cadr ch) lst ch)
  (while (and (cddr lst) (> x (car (cadr lst))))
    (setq lst (cdr lst) a (car lst) b (cadr lst)))
  (+ (cdr a) (* (- x (car a)) (/ (- (cdr b) (cdr a)) (- (car b) (car a))))))

;; 점(X,Y) 아래 가장 가까운 X축 (X 가 축 범위 안)
(defun pq:axis-at (x y / best)
  (foreach a *PQ-AXES*
    (if (and (>= x (- (car a) 1.0)) (<= x (+ (cadr a) 1.0)) (< (caddr a) y)
             (or (null best) (> (caddr a) (caddr best))))
      (setq best a)))
  best)

(defun pq:hlines (/ res pts ys out)
  (foreach ed (pq:collect "LWPOLYLINE,LINE" *PQ-BAND-LAYER*)
    (setq pts (pq:ent-pts ed) ys (mapcar 'cadr pts))
    (if (and (< (- (apply 'max ys) (apply 'min ys)) 0.01) (> (pq:pl-len pts) 5.0))
      (setq res (cons (list (apply 'min (mapcar 'car pts)) (apply 'max (mapcar 'car pts)) (car ys)) res))))
  ;; 같은 높이에서 끝이 맞닿은 가로선은 하나로 이음 (관경마다 밴드 선이 끊겨 그려진 경우)
  (setq res (vl-sort res '(lambda (a b) (if (equal (caddr a) (caddr b) 0.01) (< (car a) (car b)) (< (caddr a) (caddr b))))))
  (foreach hl res
    (if (and out (equal (caddr hl) (caddr (car out)) 0.01) (<= (car hl) (+ (cadr (car out)) 0.05)))
      (setq out (cons (list (car (car out)) (max (cadr hl) (cadr (car out))) (caddr (car out))) (cdr out)))
      (setq out (cons hl out))))
  out)

;; 기울어진 인출선 (15~75도, 3m 이상) -> ((아래점 위점 길이) ...)
(defun pq:leads (/ res pts a b L ang)
  (foreach ed (pq:collect "LWPOLYLINE,LINE" *PQ-LEAD-LAYER*)
    (setq pts (pq:ent-pts ed))
    (if (= (length pts) 2)
      (progn
        (setq a (car pts) b (cadr pts))
        (if (> (cadr a) (cadr b)) (setq a (cadr pts) b (car pts)))
        (setq L (distance a b))
        (if (and (> L 3.0) (> (abs (- (car b) (car a))) 1e-6))
          (progn
            (setq ang (* (/ 180.0 pi) (atan (- (cadr b) (cadr a)) (abs (- (car b) (car a))))))
            (if (and (> ang 15.0) (< ang 75.0))
              (setq res (cons (list a b L) res))))))))
  res)

;; 종단 연결관 문자 -> 인출선 측점 X (인출선 아래 끝의 X) / 못 찾으면 nil
(defun pq:lead-station (ln / p h best bd a b L ux uy vx vy tt pp)
  (if (nth 6 ln)
    (progn
      (setq p (list (nth 5 ln) (nth 6 ln)) h (cadddr ln))
      (foreach ld *PQ-LEADS*
        (setq a (car ld) b (cadr ld) L (caddr ld)
              ux (/ (- (car b) (car a)) L) uy (/ (- (cadr b) (cadr a)) L)
              vx (- (car p) (car a)) vy (- (cadr p) (cadr a))
              tt (+ (* vx ux) (* vy uy))
              pp (abs (- (* vx uy) (* vy ux))))
        (if (and (>= tt -0.5) (<= tt L) (<= pp (* 2.5 h)) (or (null bd) (< pp bd)))
          (setq best (car a) bd pp)))))
  best)

;; 측점 X 의 포장 -> (포장 nil) / 경계 위 (nil T 왼쪽포장 오른쪽포장 왼쪽길이 오른쪽길이) / nil
(defun pq:pint-at (pint x / res prev nxt lst iv)
  (setq lst pint)
  (while (and lst (null res))
    (setq iv (car lst) nxt (cadr lst))
    (cond
      ;; 앞 구간과 이어진 경계 위
      ((and prev (<= (abs (- (cadr prev) (car iv))) *PQ-CONN-TIE*)
            (<= (abs (- x (car iv))) *PQ-CONN-TIE*))
       (setq res (list nil T (nth 2 prev) (nth 2 iv)
                       (- (cadr prev) (car prev)) (- (cadr iv) (car iv)))))
      ;; 구간 안 (뒤 구간과 이어진 끝 경계는 다음 구간에서 처리)
      ((and (>= x (- (car iv) *PQ-CONN-TIE*)) (<= x (+ (cadr iv) *PQ-CONN-TIE*))
            (not (and nxt (<= (abs (- (cadr iv) (car nxt))) *PQ-CONN-TIE*)
                      (<= (abs (- x (cadr iv))) *PQ-CONN-TIE*))))
       (setq res (list (nth 2 iv) nil))))
    (setq prev iv lst (cdr lst)))
  res)

;; 위치(X,Y) 아래의 종단 (pq:segments 결과) 중 가로로 가장 가까운 것
(defun pq:prof-at (x y fsegs / best bd d)
  (foreach fs fsegs
    (if (> y (nth 1 fs))
      (progn
        (setq d (cond ((< x (nth 2 fs)) (- (nth 2 fs) x))
                      ((> x (nth 3 fs)) (- x (nth 3 fs)))
                      (T 0.0)))
        ;; 거리가 같으면(둘 다 범위 안) X 범위가 좁은 종단
        (if (or (null bd) (< d bd)
                (and (equal d bd 1e-6) (< (- (nth 3 fs) (nth 2 fs)) (- (nth 3 best) (nth 2 best)))))
          (setq best fs bd d)))))
  best)

;; 연결관 위치(X,Y) -> 해당 관경 구간 (X시작 X끝 관경정보 근거) 또는 nil
;;   연결관 문자보다 아래에 있는 종단 중 가로로 가장 가까운 종단 사용
(defun pq:seg-info (x y fsegs / best bd d pick)
  (foreach fs fsegs
    (if (> y (nth 1 fs))
      (progn
        (setq d (cond ((< x (nth 2 fs)) (- (nth 2 fs) x))
                      ((> x (nth 3 fs)) (- x (nth 3 fs)))
                      (T 0.0)))
        (if (or (null bd) (< d bd)
                (and (equal d bd 1e-6) (< (- (nth 3 fs) (nth 2 fs)) (- (nth 3 best) (nth 2 best)))))
          (setq best fs bd d)))))
  (if best
    (foreach sg (nth 4 best)
      (if (and (or (null (car sg)) (>= x (car sg)))
               (or (null (cadr sg)) (< x (cadr sg))))
        (setq pick sg))))
  pick)

;;----------------------------- 연결관 --------------------------------
(defun pq:nospace (s)
  (while (vl-string-search " " s) (setq s (vl-string-subst "" " " s)))
  s)

;; 숫자 토큰 -> ((숫자문자열 다음글자 그다음글자) ...)
(defun pq:numtok (s / i n c tok out)
  (setq i 1 n (strlen s) tok "")
  (while (<= i (1+ n))
    (setq c (if (<= i n) (substr s i 1) ""))
    (if (or (wcmatch c "#") (and (= c ".") (> (strlen tok) 0)))
      (setq tok (strcat tok c))
      (progn
        (if (> (strlen tok) 0)
          (setq out (cons (list tok c (if (< i n) (substr s (1+ i) 1) "")) out)))
        (setq tok "")))
    (setq i (1+ i)))
  (reverse out))

;; 연결관 문자 속 길이 : (5.0M) / L=5.0M / 5.0M  (63mm 같은 관경은 제외)
(defun pq:len-any (raw / s p in q L toks)
  (setq s (strcase (pq:nospace raw)))
  (if (setq p (vl-string-position (ascii "(") s nil T))
    (progn
      (setq in (substr s (+ p 2)))
      (if (setq q (vl-string-search ")" in)) (setq in (substr in 1 q)))
      (if (not (or (vl-string-search "MM" in) (wcmatch in "*#A*")))
        (setq L (pq:len s)))))
  (if (and (null L) (setq p (vl-string-search "L=" s)))
    (if (setq toks (pq:numtok (substr s (+ p 3))))
      (setq L (atof (car (car toks))))))
  (if (null L)
    (foreach tk (pq:numtok s)
      (if (and (= (cadr tk) "M") (/= (caddr tk) "M"))
        (setq L (atof (car tk))))))
  (if (and L (> L 0.0)) L))

;; 관경 정보 (압력 관경값 단위 재질) - 문자 어디에 있든 첫 "숫자MM" 또는 "숫자A"
;;   - 소수점 뒤 숫자(1.60 의 60)는 관경으로 보지 않음
;;   - "A" 뒤가 "." 이거나 "ASP" 이면 관경 아님 (A.S.P 등)
;;   - 표준 관경 목록(*PQ-DIA-MM* / *PQ-DIA-A*)에 있는 값만 인정
(defun pq:conn-info (raw / s i n d st unit dia prev)
  (setq s (strcase (pq:nospace raw)) i 1 n (strlen s))
  (while (and (<= i n) (null unit))
    (if (wcmatch (substr s i 1) "#")
      (progn
        (setq st i d "")
        (while (and (<= i n) (wcmatch (substr s i 1) "#"))
          (setq d (strcat d (substr s i 1)) i (1+ i)))
        (setq prev (if (> st 1) (substr s (1- st) 1) ""))
        (if (/= prev ".")
          (cond
            ((and (= (substr s i 2) "MM") (member (atoi d) *PQ-DIA-MM*))
             (setq unit "mm" dia (atoi d)))
            ((and (= (substr s i 1) "A")
                  (not (= (substr s (1+ i) 1) "."))
                  (not (= (substr s i 3) "ASP"))
                  (member (atoi d) *PQ-DIA-A*))
             (setq unit "A" dia (atoi d))))))
      (setq i (1+ i))))
  ;; "160MMPE" 처럼 붙여 쓰면 MMP 속의 "MP" 를 압력으로 오인하므로 MM 뒤는 떼고 봄
  (while (vl-string-search "MMP" s) (setq s (vl-string-subst "MM_P" "MMP" s)))
  (if unit
    (list (cond ((vl-string-search "MP" s) "MP") ((vl-string-search "LP" s) "LP") (T ""))
          dia unit
          (cond ((vl-string-search "PLP" s) "PLP") ((vl-string-search "PE" s) "PE")
                ((vl-string-search "SP" s) "SP") (T "")))))

;; 키는 관경만 사용 (종단/자재내역 표기 차이로 중복 집계되지 않도록)
(defun pq:conn-key (info)
  (if info (strcat "연결관 " (itoa (nth 1 info)) (nth 2 info)) "연결관 관경미상"))

(defun pq:num-only (raw / s i ok c)
  (setq s (pq:trim raw) i 1 ok (> (strlen s) 0))
  (while (and ok (<= i (strlen s)))
    (setq c (substr s i 1))
    (if (not (or (wcmatch c "#") (= c "."))) (setq ok nil))
    (setq i (1+ i)))
  (and ok (> (atof s) 0.0)))

;; tbl : ((키 정보 길이) ...)
(defun pq:acc (tbl key info L / hit)
  (if (setq hit (assoc key tbl))
    (subst (list key (cadr hit) (+ (caddr hit) L)) hit tbl)
    (append tbl (list (list key (if info info '("" 0 "" "")) L)))))

;; 같은 행(+-0.5h) 오른쪽 문자들 (X 순)
(defun pq:row-right (ln flines)
  (vl-sort
    (vl-remove-if-not
      '(lambda (o) (and (> (cadr o) (cadr ln))
                        (<= (abs (- (caddr o) (caddr ln))) (* 0.5 (cadddr ln)))))
      flines)
    '(lambda (a b) (< (cadr a) (cadr b)))))

(defun pq:has-dia (info lst / r)
  (foreach i lst
    (if (and (= (nth 1 i) (nth 1 info)) (= (nth 2 i) (nth 2 info))) (setq r T)))
  r)

(defun pq:smallest (lst / b)
  (foreach i lst (if (or (null b) (< (nth 1 i) (nth 1 b))) (setq b i)))
  b)

;; 자재내역 표의 "관" 행(PE관, 강관, PIPE ...)에서 관경 목록
;;   조건 : 품명에 관/PIPE, 같은 행 오른쪽에 관경과 수량(숫자)이 있음
(defun pq:table-pipes (flines / s info qty res)
  (foreach ln flines
    (setq s (pq:norm (car ln)))
    (if (and (or (vl-string-search "관" s) (vl-string-search "PIPE" s))
             (not (vl-string-search "연결관" s))
             (not (vl-string-search "보호관" s)))
      (progn
        (setq info (pq:conn-info (car ln)) qty nil)
        (foreach o (pq:row-right ln flines)
          (cond
            ((and (null info) (pq:conn-info (car o))) (setq info (pq:conn-info (car o))))
            ((and (null qty) (pq:num-only (car o))) (setq qty T))))
        (if (and info qty (not (pq:has-dia info res)))
          (setq res (cons (append info (list (pq:trim (car ln)))) res))))))
  res)

;; 관경 미상 연결관의 관경 추정 -> (정보 근거) 또는 nil
;;   1) 자재내역 관경 중 본관(종단 관경)에 없는 것이 1종 -> 그 관경
;;   2) 여러 종 -> 그중 최소 관경
;;   3) 본관 외 관경이 없음 -> 자재내역 전체 중 최소 관경
(defun pq:conn-guess (flines fp / tp cand)
  (setq tp   (pq:table-pipes flines)
        cand (vl-remove-if '(lambda (i) (pq:has-dia i (mapcar 'cdr fp))) tp))
  (cond
    ((= (length cand) 1) (list (car cand) "자재내역 관경 중 본관 외 1종"))
    (cand (list (pq:smallest cand) "자재내역 본관 외 관경 여러 종 -> 최소 관경"))
    (tp   (list (pq:smallest tp) "자재내역에 본관 외 관경 없음 -> 최소 관경"))))

;; 관경 미상 종단 연결관을 자재내역 관경별 수량에 맞춰 배정
;;   관경마다 (자재내역 수량 - 이미 그 관경으로 정해진 종단 길이) 와 합이 같은
;;   미상 연결관 조합을 찾아 그 관경 지정 / 못 맞춘 나머지는 기존 규칙(최소 관경)
(defun pq:match-conn (ents tinf fi / kq unk r e0)
  (foreach ti tinf
    (setq kq 0.0)
    (foreach e ents
      (if (and (car e) (pq:has-dia (car e) (list ti)))
        (cond ((= (nth 2 e) "자재내역") (setq kq (+ kq (cadr e))))
              ((= (nth 2 e) "종단")     (setq kq (- kq (cadr e)))))))
    (setq unk (vl-remove-if-not '(lambda (e) (and (null (car e)) (= (nth 2 e) "종단"))) ents))
    (if (and unk (> kq *PQ-TOL-SUM*))
      (progn
        (setq *PQ-NODES* 0
              r (pq:subset (mapcar '(lambda (e) (list nil nil nil nil nil (cadr e) e)) unk) kq))
        (if r
          (foreach fk (car r)
            (setq e0 (nth 6 fk))
            (pq:err fi nil nil nil
                    (strcat "연결관 [" (pq:trim (nth 3 e0)) "] 관경 미상 -> "
                            (itoa (nth 1 ti)) (nth 2 ti) " 적용 (자재내역 관경별 수량에 맞춤)"))
            (setq ents (subst (cons ti (cdr e0)) e0 ents)))))))
  ents)

;; 관경 미상 종단 연결관 -> 그 위치의 종단 밴드 관경
(defun pq:conn-band (ents fsegs fi)
  (mapcar
    '(lambda (e / ln sg)
       (setq ln (nth 4 e))
       (if (or (car e) (/= (nth 2 e) "종단"))
         e
         (if (setq sg (pq:seg-info (nth 5 e) (caddr ln) fsegs))
           (progn
             (if fi (pq:err fi nil nil nil
                     (strcat "연결관 [" (pq:trim (nth 3 e)) "] 관경 미상 -> "
                             (itoa (nth 1 (nth 2 sg))) (nth 2 (nth 2 sg))
                             " 적용 (종단 밴드 관경, " (nth 3 sg) ")")))
             (cons (nth 2 sg) (cdr e)))
           e)))
    ents))

;; 종단 밴드로 정한 연결관이 자재내역 연결관 관경별 수량과 모두 맞으면 T
;;   (미상이 남거나, 자재내역에 없는 관경이 나오거나, 관경별 합이 다르면 nil)
(defun pq:conn-ok (ents tinf / ok tq lq)
  (setq ok T)
  (foreach e ents
    (if (and (= (nth 2 e) "종단") (or (null (car e)) (and (not (pq:is63 (car e))) (not (pq:has-dia (car e) tinf)))))
      (setq ok nil)))
  (if ok
    (foreach ti tinf
      (setq tq 0.0 lq 0.0)
      (foreach e ents
        (if (and (car e) (pq:has-dia (car e) (list ti)))
          (cond ((= (nth 2 e) "자재내역") (setq tq (+ tq (cadr e))))
                ((= (nth 2 e) "종단")     (setq lq (+ lq (cadr e)))))))
      (if (> (abs (- tq lq)) *PQ-TOL-SUM*) (setq ok nil))))
  ok)

;; 관경 미상 연결관 -> info 관경으로 (근거 문구)
(defun pq:conn-fill (ents info why fi)
  (mapcar
    '(lambda (e)
       (if (car e)
         e
         (progn
           (pq:err fi nil nil nil
                   (strcat "연결관 [" (pq:trim (nth 3 e)) "] 관경 미상 -> "
                           (itoa (nth 1 info)) (nth 2 info) " 적용 (" why ")"))
           (cons info (cdr e)))))
    ents))

;; 도곽 1장의 연결관 -> ((키 정보 길이 산출방식) ...)
;;   자재내역 표에 연결관이 있으면 자재내역만 사용 (종단 인출선은 대조용)
(defun pq:conn (flines fi fp fsegs / nob cl dup L info qty ents g tinf tblsum ldsum hit out bnd)
  ;; 연결관 문자만 추리고 겹친 중복 제거
  (foreach ln flines
    (if (vl-string-search "연결관" (pq:norm (car ln)))
      (progn
        (setq dup nil)
        (foreach o cl
          (if (and (= (car ln) (car o))
                   (equal (cadr ln) (cadr o) (* 0.2 (cadddr ln)))
                   (equal (caddr ln) (caddr o) (* 0.2 (cadddr ln))))
            (setq dup T)))
        (if (not dup) (setq cl (cons ln cl))))))
  ;; 1) 해석 -> ents ((정보 길이 출처 원문) ...)
  (foreach ln (reverse cl)
    (if (setq L (pq:len-any (car ln)))
      (setq ents (cons (list (pq:conn-info (car ln)) L "종단" (car ln) ln) ents))
      (progn
        (setq info (pq:conn-info (car ln)) qty nil)
        (foreach o (pq:row-right ln flines)
          (cond
            ((and (null info) (pq:conn-info (car o))) (setq info (pq:conn-info (car o))))
            ((and (null qty) (pq:num-only (car o))) (setq qty (atof (pq:trim (car o)))))))
        (if qty
          (setq ents (cons (list info qty "자재내역" (car ln) ln) ents))
          (pq:err fi nil nil nil
                  (strcat "연결관 문자 [" (pq:trim (car ln)) "] 의 길이/수량을 찾지 못함"))))))
  (setq ents (reverse ents))
  ;; 1-1) 종단 연결관 : 인출선 측점 X (못 찾으면 문자 삽입점 X) -> ents 6번째에 추가
  (setq ents
    (mapcar
      '(lambda (e / ln st)
         (if (= (nth 2 e) "종단")
           (progn
             (setq ln (nth 4 e)
                   st (cond ((pq:lead-station ln)) ((nth 5 ln)) ((cadr ln))))
             (append e (list st)))
           e))
      ents))
  ;; 1-2) 상세도 연결관 문자 제외 (63mm 연결관은 상세도에 있어도 집계)
  ;;   상세도 = *PQ-DETAIL-LAYER* 레이어 문자 또는 종단 범위(관경 밴드 X 범위)에서 *PQ-CONN-OUT* 넘게 벗어난 문자
  ;;   관경이 적혀 있지 않은 상세도 연결관(연결관L=4.0m 등)은 63mm 가 아닌 것으로 봄
  (setq ents
    (vl-remove-if
      '(lambda (e / dx lay why)
         (if (and (= (nth 2 e) "종단") (not (and (car e) (pq:is63 (car e)))))
           (progn
             (setq lay (pq:str (nth 4 (nth 4 e))) dx nil why nil)
             (if (and fsegs (numberp (nth 5 e)))
               (foreach fs fsegs
                 (setq dx (min (cond (dx) (1.0e99))
                               (cond ((< (nth 5 e) (nth 2 fs)) (- (nth 2 fs) (nth 5 e)))
                                     ((> (nth 5 e) (nth 3 fs)) (- (nth 5 e) (nth 3 fs)))
                                     (T 0.0))))))
             (cond
               ((and *PQ-DETAIL-LAYER* (wcmatch (strcase lay) (strcase *PQ-DETAIL-LAYER*)))
                (setq why (strcat "상세도 레이어 [" lay "]")))
               ((and dx (> dx *PQ-CONN-OUT*))
                (setq why (strcat "종단 범위 밖 " (pq:r2 dx) "M"))))
             (if why
               (progn
                 (pq:err fi nil nil nil
                         (strcat "연결관 [" (pq:trim (nth 3 e)) "] " why
                                 " -> 상세도 연결관으로 보고 집계 제외 (63mm 제외)"))
                 T)))))
      ents))
  ;; 2) 관경 미상 종단 연결관의 관경 : 자재내역 연결관 관경이 최우선 (최종검수 기준이 자재내역)
  ;;   tinf = 같은 도면 자재내역 연결관 관경 (63mm 제외 - 종단 연결관은 본관 연결관)
  (setq tinf nil)
  (foreach e ents
    (if (and (car e) (= (nth 2 e) "자재내역") (not (pq:is63 (car e))) (not (pq:has-dia (car e) tinf)))
      (setq tinf (cons (car e) tinf))))
  (cond
    ;; 2-1) 자재내역 연결관 관경 1종 -> 미상 종단 연결관 모두 그 관경
    ((= (length tinf) 1)
     (setq ents (pq:conn-fill ents (car tinf) "자재내역 연결관 관경" fi)))
    ;; 2-2) 여러 종 -> 먼저 종단 밴드 관경(위치)으로 정해 보고, 관경별 합이 자재내역과 모두 맞으면 그대로
    ;;      (위치로 정해야 포장구분도 맞음) / 안 맞으면 관경별 수량에 맞는 조합 -> 종단 밴드 -> 최소 관경
    ((and tinf (pq:conn-ok (pq:conn-band ents fsegs nil) tinf))
     (setq ents (pq:conn-band ents fsegs fi)))
    (tinf
     (setq ents (pq:match-conn ents tinf fi)
           ents (pq:conn-band ents fsegs fi)
           ents (pq:conn-fill ents (pq:smallest tinf) "자재내역 연결관 관경 여러 종 -> 최소" fi)))
    ;; 2-3) 자재내역에 연결관 관경 없음 -> 종단 밴드 관경 -> 자재내역 관 행 관경 추정
    (T
     (setq ents (pq:conn-band ents fsegs fi))
     (foreach e ents (if (null (car e)) (setq g T)))
     (if g
       (progn
         (setq g (pq:conn-guess flines fp))
         (if g
           (setq ents (pq:conn-fill ents (car g) (strcat (cadr g) (if (nth 4 (car g)) (strcat " : [" (nth 4 (car g)) "]") "")) fi))
           (foreach e ents
             (if (null (car e))
               (pq:err fi nil nil nil (strcat "연결관 [" (pq:trim (nth 3 e)) "] 관경 미상 - 자재내역에서도 관경을 찾지 못함")))))))))
  ;; 2-3) 63mm 제외 종단 연결관의 포장 : 측점이 들어 있는 종단 포장 구간
  (setq ents
    (mapcar
      '(lambda (e / fs pv)
         (if (and (= (nth 2 e) "종단") (car e) (not (pq:is63 (car e))))
           (progn
             (setq fs (pq:prof-at (nth 5 e) (caddr (nth 4 e)) fsegs)
                   pv (if (and fs (nth 5 fs)) (pq:pint-at (nth 5 fs) (nth 5 e))))
             (append e (list pv)))
           e))
      ents))
  ;;   경계 위 연결관 : 가까운(*PQ-CONN-PAIR* 안) 다른 연결관 쌍의 포장, 없으면 짧은 쪽 구간
  (setq ents
    (mapcar
      '(lambda (e / pv best bd d o rx)
         (setq pv (nth 6 e))
         ;; 하천 하월구간 경계와 같은 포장 경계 위 : 하천 밖 쪽 포장 (시작 경계 -> 앞 구간, 끝 경계 -> 뒤 구간)
         (if (and pv (cadr pv)
                  (setq rx (vl-some '(lambda (r) (cond ((<= (abs (- (nth 5 e) (car r))) *PQ-CONN-TIE*) 'S)
                                                       ((<= (abs (- (nth 5 e) (cadr r))) *PQ-CONN-TIE*) 'E)))
                                    *PQ-RIVER-X*)))
           (progn
             (pq:err fi nil nil nil (strcat "연결관 [" (pq:trim (nth 3 e)) "] 하천 하월구간 경계 위 -> 하천 밖 포장 ["
                                            (if (eq rx 'S) (nth 2 pv) (nth 3 pv)) "] 로 분류"))
             (setq pv (list (if (eq rx 'S) (nth 2 pv) (nth 3 pv)) nil) e (pq:set-nth e 6 pv))))
         (if (and pv (cadr pv))
           (progn
             (foreach o ents
               (if (and (not (eq o e)) (nth 6 o) (car (nth 6 o))
                        (member (car (nth 6 o)) (list (nth 2 pv) (nth 3 pv))))
                 (progn
                   (setq d (abs (- (nth 5 o) (nth 5 e))))
                   (if (and (<= d *PQ-CONN-PAIR*) (or (null bd) (< d bd))) (setq best o bd d)))))
             (pq:set-nth e 6
               (list (if best
                       (car (nth 6 best))
                       (if (<= (nth 4 pv) (nth 5 pv)) (nth 2 pv) (nth 3 pv)))
                     nil)))
           e))
      ents))
  ;; 3) 출처별 합산
  ;;   bnd : 63mm 제외 종단 연결관 중 포장을 찾은 것 ((키 정보 길이 포장) ...)
  (foreach e ents
    (cond
      ((= (nth 2 e) "자재내역")
       (setq tblsum (pq:acc tblsum (pq:conn-key (car e)) (car e) (cadr e))))
      ((and (nth 6 e) (car (nth 6 e)))
       (setq bnd (cons (list (pq:conn-key (car e)) (car e) (cadr e) (car (nth 6 e))) bnd)
             ldsum (pq:acc ldsum (pq:conn-key (car e)) (car e) (cadr e))))
      (T
       ;; 종단 연결관인데 포장을 못 찾은 것 : 같은 관경에 포장 찾은 연결관이 있어도 빠지지 않게 따로 보관
       (if (and (= (nth 2 e) "종단") (car e) (not (pq:is63 (car e))))
         (setq nob (cons (list (pq:conn-key (car e)) (car e) (cadr e) (nth 3 e) (nth 5 e)) nob)))
       (setq ldsum (pq:acc ldsum (pq:conn-key (car e)) (car e) (cadr e))))))
  (setq bnd (reverse bnd) nob (reverse nob))
  ;; 4) 관경별 : 종단 연결관 포장을 찾았으면 종단 값(포장별), 아니면 자재내역 우선
  (foreach e ldsum
    (if (assoc (car e) bnd)
      (progn
        (foreach b bnd
          (if (= (car b) (car e))
            (setq out (cons (list (car b) (cadr b) (caddr b) "종단" (cadddr b)) out))))
        ;; 같은 관경의 포장 못 찾은 종단 연결관 -> 길이는 넣고 포장은 기본 규칙(A.S.P > CON'C > 주 포장)
        (foreach b nob
          (if (= (car b) (car e))
            (progn
              (pq:err fi nil nil nil
                      (strcat "연결관 [" (pq:trim (nth 3 b)) "] 측점 X " (if (numberp (nth 4 b)) (pq:r2 (nth 4 b)) "?")
                              " : 종단 포장 구간을 찾지 못함 -> 기본 포장 규칙 적용 (확인)"))
              (setq out (cons (list (car b) (cadr b) (caddr b) "종단" nil) out)))))
        (if (and (setq hit (assoc (car e) tblsum))
                 (not (equal (caddr hit) (caddr e) *PQ-TOL-SUM*)))
          (pq:err fi nil nil nil
                  (strcat (car e) " : 종단 " (pq:r2 (caddr e)) "M / 자재내역 "
                          (pq:r2 (caddr hit)) "M 불일치 -> 종단 값 적용 (확인)"))))))
  (foreach e tblsum
    (if (not (assoc (car e) bnd))
      (progn
        (setq out (cons (list (car e) (cadr e) (caddr e) "자재내역" nil) out))
        (if (and (setq hit (assoc (car e) ldsum))
                 (not (equal (caddr hit) (caddr e) *PQ-TOL-SUM*)))
          (pq:err fi nil nil nil
                  (strcat (car e) " : 자재내역 " (pq:r2 (caddr e)) "M / 종단 "
                          (pq:r2 (caddr hit)) "M 불일치 -> 자재내역 적용"))))))
  (foreach e ldsum
    (if (and (not (assoc (car e) bnd)) (not (assoc (car e) tblsum)))
      (setq out (cons (list (car e) (cadr e) (caddr e) "종단" nil) out))))
  (reverse out))

;; 포장별 길이 누적 ((포장 . 길이) ...)
(defun pq:kacc (fk kind L / hit)
  (if (setq hit (assoc kind fk))
    (subst (cons kind (+ (cdr hit) L)) hit fk)
    (cons (cons kind L) fk)))

;; 연결관 포장 : *PQ-CONN-PRI* 순서 (A.S.P > CON'C) > 도면에서 가장 긴 포장 > "연결관"
(defun pq:conn-pave (fk / best bl hit)
  (foreach grp *PQ-CONN-PRI*
    (if (not hit)
      (foreach e fk
        (if (and (member (pq:norm (car e)) (mapcar 'pq:norm grp))
                 (or (null hit) (> (cdr e) (cdr hit))))
          (setq hit e)))))
  (cond
    (hit (car hit))
    (fk
     (foreach e fk (if (or (null bl) (> (cdr e) bl)) (setq best (car e) bl (cdr e))))
     best)
    ;; 종단 포장이 없는 도면 (63mm 만 있는 도면 등) -> 평면도 포장 문자/블럭 (비포장 등)
    ((and *PQ-CUR-F* (setq best (pq:plan-pave *PQ-CUR-F*)))
     (if *PQ-CUR-FI*
       (pq:err *PQ-CUR-FI* nil nil nil
               (strcat "종단 포장구분이 없어 평면도 포장 문자 [" best "] 적용 (확인)")))
     best)
    (T "연결관")))

;; 도곽 평면도의 포장 문자/블럭 중 63mm 관에 가장 가까운 것 (63mm 관이 없으면 가장 많은 것) -> 포장 이름 / nil
(defun pq:plan-pave (f / R labs lns best bd d cnt hit)
  (setq R    (pq:p63-rect f)
        labs (vl-remove-if-not '(lambda (l) (pq:in-r (cadr l) R)) *P63-PAVE*)
        lns  (vl-remove-if-not '(lambda (l) (pq:any-in (cadr l) R)) *P63-LINES*))
  (cond
    ((null labs) nil)
    (lns
     (foreach lb labs
       (foreach l lns
         (foreach q (cadr l)
           (setq d (distance (cadr lb) q))
           (if (or (null bd) (< d bd)) (setq best (car lb) bd d)))))
     best)
    (T
     (foreach lb labs
       (if (setq hit (assoc (car lb) cnt))
         (setq cnt (subst (cons (car lb) (1+ (cdr hit))) hit cnt))
         (setq cnt (cons (cons (car lb) 1) cnt))))
     (setq bd nil)
     (foreach c cnt (if (or (null bd) (> (cdr c) bd)) (setq best (car c) bd (cdr c))))
     best)))

;; 연결관이 들어갈 관경 행 (키 . 정보)
;;   도면에 같은 관경(값+단위) 본관이 있으면 그 행, 없으면 새 관경 행
(defun pq:conn-target (c fp / info hit pr)
  (setq info (cadr c))
  (foreach e fp
    (if (and (null hit)
             (= (nth 1 (cdr e)) (nth 1 info))
             (= (nth 2 (cdr e)) (nth 2 info)))
      (setq hit e)))
  (cond
    (hit hit)
    ((= (nth 1 info) 0) (cons (car c) info))          ; 관경미상
    (T
     (setq pr (cond ((/= (nth 0 info) "") (nth 0 info))
                    (fp (nth 0 (cdr (car fp))))
                    (T "LP"))
           info (list pr (nth 1 info) (nth 2 info)
                      (cond ((/= (nth 3 info) "") (nth 3 info))
                            ((= (nth 2 info) "mm") "PE")
                            (T ""))))
     (cons (pq:pipe-key info) info))))

;;------------------------ 자재내역 63mm 연장 ------------------------
(defun pq:is63 (info)
  (and info (= (nth 1 info) 63) (= (nth 2 info) "mm")))

;; 자재내역 표에서 63mm 관 행 -> ((품명 규격 연장) ...)
;;   품명 문자 : 인입관 또는 연결관 (띄어쓰기 무시, 예 "인  입  관"), 문자 자체에 길이 표기 없음
;;              신설관/기존관 등 본관 행은 제외
;;   같은 행 오른쪽 : 63mm 규격 문자 -> 그 뒤 첫 숫자 = 연장
;;   이음관/부속(*PQ-63-EXCL*) 행 제외, 같은 수량 칸을 두 번 세지 않음
(defun pq:table-63 (flines / s n spec qty qln used res bad)
  (foreach ln flines
    (setq s (pq:norm (car ln)) bad nil)
    (foreach w *PQ-63-EXCL* (if (vl-string-search (pq:norm w) s) (setq bad T)))
    (if (and (or (vl-string-search "인입관" s) (vl-string-search "연결관" s))
             (not bad)
             (not (pq:len-any (car ln))))
      (progn
        (setq spec (if (pq:is63 (pq:conn-info (car ln))) (car ln)) qty nil qln nil)
        (foreach o (pq:row-right ln flines)
          (cond
            (qty nil)
            ((and (null spec) (pq:conn-info (car o)))
             (if (pq:is63 (pq:conn-info (car o))) (setq spec (car o)) (setq spec "X")))
            ((and spec (pq:num-only (car o)))
             (setq qty (atof (pq:trim (car o))) qln o))))
        (if (and spec (/= spec "X") qty (not (member qln used)))
          (setq used (cons qln used)
                res  (cons (list (pq:trim (car ln)) (pq:trim spec) qty) res))))))
  (reverse res))

;;------------------------ 최종검수 : 자재내역 관경별 수량 ------------------------
;; 자재내역 표의 관 행(직관/연결관/인입관) -> (((관경 단위) . 수량합) ...)
;;   같은 행 오른쪽 : 단일 관경 규격(315mmX63mm 같은 이음관 제외) -> 그 뒤 첫 숫자 = 수량
(setq *PQ-MAT-WORDS* '("직관" "연결관" "인입관"))
;;   *PQ-TQ-PARTS* 에 관경별 구성도 남김 (((관경 단위) (품명 . 수량) ...) ...) -> G열 수식 (직관+연결관)
(defun pq:table-qty (flines / s ok bad spec info qty qln used res k hit wd pp)
  (setq *PQ-TQ-PARTS* nil *PQ-TQ-INFO* nil)
  (foreach ln flines
    (setq s (pq:norm (car ln)) ok nil bad nil)
    (foreach w *PQ-MAT-WORDS* (if (and (null ok) (vl-string-search w s)) (setq ok w)))
    (foreach w *PQ-63-EXCL* (if (vl-string-search (pq:norm w) s) (setq bad T)))
    (if (and ok (not bad) (not (pq:len-any (car ln))))
      (progn
        (setq info (pq:conn-info (car ln)) spec (if info (car ln)) qty nil qln nil)
        (foreach o (pq:row-right ln flines)
          (cond
            ((or qty (> (- (cadr o) (cadr ln)) 60.0)) nil)
            ((and (null spec) (pq:conn-info (car o)))
             (setq spec (car o) info (pq:conn-info (car o))))
            ((and spec (pq:num-only (car o)))
             (setq qty (atof (pq:trim (car o))) qln o))))
        (if (and info qty spec (not (vl-string-search "X" (strcase (pq:nospace spec)))) (not (member qln used)))
          (progn
            (setq used (cons qln used)
                  k    (list (nth 1 info) (nth 2 info))
                  hit  (assoc k res)
                  res  (if hit (subst (cons k (+ (cdr hit) qty)) hit res) (cons (cons k qty) res))
                  *PQ-TQ-INFO* (if (assoc k *PQ-TQ-INFO*) *PQ-TQ-INFO* (cons (cons k info) *PQ-TQ-INFO*))
                  pp   (assoc k *PQ-TQ-PARTS*)
                  *PQ-TQ-PARTS* (if pp
                                  (subst (append pp (list (cons ok qty))) pp *PQ-TQ-PARTS*)
                                  (cons (list k (cons ok qty)) *PQ-TQ-PARTS*))))))))
  res)

;; 관경 구성 -> "200+14.5" (연결관은 맨 뒤), 1개면 ""
(defun pq:tq-formula (parts / a b)
  (foreach p parts (if (= (car p) "연결관") (setq b (append b (list p))) (setq a (append a (list p)))))
  (if (> (length parts) 1)
    (pq:join (mapcar '(lambda (p) (pq:nz (cdr p))) (append a b)) "+")
    ""))

(defun pq:dia-str (k) (strcat (itoa (car k)) (cadr k)))

;;------------------------ 평면도 63mm 포장구분 ------------------------
;; 평면도(도곽 안 레이어 L 사각형)의 63mm 관을 포장 경계에서 잘라 포장구분별 길이 집계
;;   1) 63mm 관 : 관로 레이어(*PQ-63-PIPE-LAYER*) 중 이름에 신설관 + 63mm 가 있는 레이어, HIDDEN 제외
;;   2) 출발점 : 본관(그 밖의 관로 레이어)에 붙은 끝
;;               본관에 안 붙고 다른 63mm 관에 붙었으면 그 관의 포장을 따름
;;   3) 경계(*PQ-63-BND-LAYER*)를 지날 때마다 자름
;;      처음 경계 전 조각(도로측) : 본관을 따라(경계를 넘지 않는 범위, 앞뒤 40m) 경계에 가리지 않는 가장 가까운 포장
;;      경계를 넘은 뒤 조각(경계밖) : 조각마다 그 가운데에서 경계에 가리지 않는 가장 가까운 포장
;;   4) 길이 : 가장 가까운 관로명 "LP 63mm PE(Nm)" 의 N 을 조각 길이 비율로 배분 (소수 첫째 자리)
;; 평면도 분기관 : 종단면도 없이 평면도에만 있는 짧은 분기관 (예 "신설관 LP 315mm PE(3.0m)")
;;   관로명 문자(괄호 길이 있음) -> 같은 관경 레이어의 선 중 길이가 비슷한 선을 찾아 63mm 와 같은 방식으로 포장 집계
(setq *PQ-BR-PLAN*         T
      *PQ-BR-NAME-LAYER*   "관로명"
      *PQ-BR-WORDS*        '("신설관")
      *PQ-BR-LEADER-LAYER* "관로제원지시선")

;; 종단 기준 63mm : 종단 인출선 "63mm-8M" 의 분기 측점 포장을 평면도 63mm 의 도로측 포장으로 사용
;;   평면도 측점(NO.x) 로 63mm 분기점 측점을 구해 종단 인출선과 짝지음 (측점 차 *PQ-63-MATCH-TOL* 이내)
(setq *PQ-63-PROFILE*    T
      *PQ-STA-LAYER*     "*Y-측점"    ; 평면도 측점 문자 (NO.6 ...) - 앞에 접두어가 붙은 레이어(00Y-측점 등)도
      *PQ-STA-PITCH*     20.0         ; NO 1개 = 20m
      *PQ-63-MATCH-TOL*  5.0
      *PQ-STA-NEAR*      5.0          ; 평면도 NO 문자가 이 거리 안에 있는 관로에만 속한 것으로 봄
      *PQ-STA-START*     '("공사시점"))  ; 종단 시작에 STA 문자가 없을 때 측점 0 으로 보는 문자

;; 자재내역의 연결관 63mm 를 평면도 63mm 집계("LP 63mm PE" 행)에 더함
(setq *PQ-63-CONN-ADD* T)

(setq *PQ-63-SKIP-PR*    '("MP")   ; 평면도 63mm 집계에서 뺄 도면 (종단 관경 밴드로 정한 압력)
      *PQ-63-PLAN*       T
      ;; 관로 레이어 : 이름에 아래 패턴이 있으면 관로로 보고, 레이어 이름 속 관경(63mm, 315mm, 100A ...)을 읽음
      ;;   "신설관 LP 63mm PE", "신설관 LP PE 63mm" 처럼 순서/띄어쓰기가 달라도 됨
      *PQ-63-PIPE-LAYER* "*신설관*,*기존관*,*도시가스관로*"
      *PQ-63-NEW-WORD*   "신설관"     ; 63mm 집계 대상은 이 단어가 있는 레이어의 63mm 관
      *PQ-63-BND-LAYER*  "ADA030,ZC154,AE001"
      ;; 도로 경계 : 경계에 가려 보이는 포장 문자가 없는 조각이 이 선을 아직 안 넘었으면(도로 안) 도로측 포장
      *PQ-63-ROAD-LAYER* "ADA030"
      *PQ-63-PAVE-LAYER* "TEXT"
      *PQ-63-NAME-LAYER* "*63*관로명*" ; 63mm 관로명 문자 (먼저 이 레이어로 배정)
      *PQ-63-NAME-LAYER2* "*관로명*"  ; 위에서 짝을 못 찾은 63mm 관은 이 레이어(문자에 63 이 있는 것만)로 다시 배정
      *PQ-PLAN-LAYER*    "L"
      *PQ-63-INFO*       '("LP" 63 "mm" "PE")
      *PQ-63-TOL*        0.5      ; 끊겨 그려진 63mm 관 잇기 / 캡 거리
      *PQ-63-CONN-TOL*   0.1      ; 63mm 관이 신설관(본관 또는 다른 63mm)에 연결됐다고 보는 거리 - 넘으면 집계 제외
      *PQ-63-RANGE*      40.0     ; 도로측 포장 문자 찾는 본관 앞뒤 범위
      *PQ-63-STEP*       2.0
      *PQ-63-LABEL-R*    30.0     ; 포장 문자 찾는 반경
      *PQ-63-NAME-R*     30.0     ; 관로명 문자 찾는 반경
      *PQ-63-MIN-PAVE*   0.5      ; 한 관에 포장이 2개 이상일 때 이 길이 이하 포장은 가장 긴 포장에 합산
      ;; 63mm 캡 표시 (관 끝의 짧은 선) : 캡이 있는 끝 = 관 끝, 반대쪽 = 분기 시작
      ;;   관로명 문자는 관 끝 너머 관 방향으로 쓰여 있으므로 "문자 축선 ~ 관 끝" 거리로 짝지음
      *PQ-63-CAP-LAYER*  "*63*CAP*"
      *PQ-63-CAP-TOL*    0.3
      *PQ-63-NAME-ANG*   20.0)    ; 관로명 문자 방향과 관 끝 방향 차이 허용 (도)
;; 포장 문자로 인정할 단어 (대문자, 공백 . ' ` - 제거 후 포함 여부)
(setq *PQ-63-PAVE-WORDS*
  '("ASP" "아스팔트" "아스콘" "CON" "콘크리트" "비포장" "보도" "블럭" "블록" "잡종지"
    "녹지" "사리" "자갈" "토사" "법면" "투수" "칼라" "하천"))
;; 포장 문자 통일
(setq *PQ-63-ALIAS* '(("CON.C" . "CON'C")))
;; 보도블럭 영역 : 도로경계(*PQ-63-BND-LAYER*)로 막히지 않은 같은 영역 안에 "보도블럭" 문자(레이어 무관)가 있으면
;;   그 영역의 63mm 조각은 가까운 다른 포장 문자보다 우선해서 보도블럭
(setq *PQ-63-SW-WORDS* '("보도블럭" "보도블록")
      *PQ-63-SW-NAME*  "보도블럭"
      *PQ-63-SW-R*     20.0)       ; 보도블럭 문자를 찾는 반경
;; 포장 부속 : 신설관과 겹치는 닫힌 폴리선의 면적 집계 (구분 도면층)
;;   복구수량산출서 : 횡단보도 BF = 면적합/4, BG = 개수 / 과속방지턱 BO = 면적합/4
(setq *PQ-ACC*      '(("횡단보도" "AE130") ("과속방지턱" "방지턱"))
      *PQ-ACC-PIPE* "*신설관*")   ; 겹침을 볼 관로 레이어 (HIDDEN 선종류 제외)

;; 칼라아스콘 / 미끄럼방지 MMA 구분 : 칼라아스콘이 있는 도면마다 물어봄
;;   MMA 선택 -> 연장은 A.S.P 로 옮기고, 평면도 도로경계 객체(닫힌 폴리선) 면적을 BL(MMA 수지)에 기록
(setq *PQ-MMA-ASK*       T
      *PQ-MMA-WORD*      "칼라"                     ; 포장구분 이름에 이 단어가 있으면 물어봄
      *PQ-MMA-TO*        "A.S.P"                    ; MMA 로 정한 구간 연장을 옮길 포장구분
      *PQ-MMA-BND-LAYER* "ADA030,ZC154,AE001"       ; 칼라아스콘 영역을 찾을 닫힌 도로경계 레이어
      ;; 닫힌 폴리선 1개로 안 둘러싸인 칼라아스콘(보도 포함) : 이 레이어 선들로 BOUNDARY 영역을 만듦
      ;;   (도로경계 + 평면도 틀 L + AE001 이 함께 둘러싸는 영역)
      *PQ-MMA-REGION-LAYER* "ADA030,ZC154,AE001,L"
      *PQ-MMA-REGION-MAX* 0.5    ; BOUNDARY 영역이 평면도의 이 비율보다 크면 잘못 잡은 것으로 보고 버림
      *PQ-MMA-REGION-MAXA* 1500.0 ; BOUNDARY 영역이 이 면적(M2)보다 크거나, 안에 다른 포장 문자(A.S.P 등)가 있으면 버림
      ;; 평면도에 칼라아스콘 문자가 없을 때 : 신설관과 겹치는 이 레이어 선으로 칼라아스콘 도형을 만듦
      *PQ-MMA-ZC-LAYER*   "ZC154"
      *PQ-MMA-JOIN*       3.0    ; 끊긴 ZC154 선 끝점끼리 이 거리 안이면 이어 붙임
      *PQ-MMA-PAIR-W*     10.0   ; 나란한 두 선 간격 최대 (칼라아스콘 폭)
      *PQ-MMA-PAR-TOL*    1.5    ; 나란하다고 볼 간격 변화 허용
      *PQ-MMA-DRAW-LAYER* "0칼라아스콘" ; PAVQ 때 칼라아스콘/MMA 로 쓴 경계를 이 레이어에 그림 (다음 PAVQ 때 지우고 새로)
      *PQ-MMA-DRAW-TXT*   1.0    ; 경계 표시 문자 높이
      *PQ-MMA-DRAW-W*     0.1    ; 경계 폴리선 굵기(전역폭) - 눈에 띄게
      *PQ-MMA-GROUP-N*    3      ; 비슷한 크기 경계가 이 개수 이상이면 문자 하나로 합쳐 합계(개수) 표시
      *PQ-MMA-SAME-TOL*   0.1    ; 다른 도면과 같은 모양으로 볼 꼭짓점 오차 (뒷번호 도면에서 제외)
      *PQ-MMA-NEAR-R*     15.0   ; ZC154 도형 가운데에서 이 거리 안 가장 가까운 포장 문자가 칼라아스콘이 아니면 버림
      ;; 2차선 이상 도로 : 중앙선(차선 레이어) 기준으로 신설관이 지나는 쪽만 칼라아스콘 도형 (nil 이면 안 함)
      *PQ-MMA-LANE-LAYER*  "*차선*,*중앙선*"   ; 차선·중앙선 레이어 (중앙선이 차선 레이어에 함께 있어도, 따로 있어도 됨)
      *PQ-MMA-CENTER-LAYER* "*중앙선*"        ; 이 레이어 선은 중앙선으로 먼저 씀 (끊긴 곳은 차선 레이어 선과도 이어 봄)
      *PQ-MMA-LANE-EXCL*   "*정지선*,*횡단*"  ; 차선 레이어 중 제외 (정지선, 횡단보도)
      *PQ-MMA-LANE-BEND*   35.0   ; 중앙선은 처음~끝 방향에서 이 각도(도) 넘게 꺾이지 않는 선만 (교차로 꺾이는 차선 제외)
      *PQ-MMA-LANE-PARR*   0.7    ; 도형 안 신설관 길이 중 이 비율 이상이 중앙선과 나란해야 나눔
      *PQ-MMA-CENTER-GAP*  1.0    ; 중앙선 레이어 선은 도형 경계에서 이 거리만 안쪽이면 중앙선으로 인정
      *PQ-MMA-LANE-GAP*    2.0    ; 도형 경계에서 이 거리 안쪽 깊이 지나는 차선만 중앙선 (길가장자리 차선 무시)
      *PQ-MMA-LANE-BRIDGE* 8.0    ; 끊긴 차선(방지턱/횡단보도/점선) 끝끼리 이 거리 안이고 일직선이면 이어 봄
      *PQ-MMA-LANE-FAR*    40.0   ; 옆길 입구 등으로 길게 끊긴 중앙선 : 이 거리 안이고 두 끝이 같은 선 위(옆 어긋남 *PQ-MMA-LANE-OFF* 안)면 가상선으로 이음
      *PQ-MMA-LANE-OFF*    1.0
      *PQ-MMA-LANE-EXT*    10.0   ; 중앙선 끝이 도형 경계에 못 닿으면 진행 방향으로 이 길이까지 가상선
      *PQ-MMA-LANE-DBL*    0.6    ; 중앙선 2줄 간격이 이 값 이하면 가운데 가상 중심선 1줄
      *PQ-MMA-LANE-MINR*   0.4    ; 도형 긴 쪽 길이의 이 비율 이상 길어야 중앙선 (정지선 등 가로선 무시)
      *PQ-MMA-LANE-MINL*   1.0    ; 중앙선 양쪽 모두 신설관이 이 길이 이상 지나면 나누지 않음 (도로 횡단)
      *PQ-MMA-WIDTH*     1.0        ; 경계를 못 찾아 "연장 x 폭" 으로 할 때 기본 폭
      *PQ-MMA-LEN-TOL*   1.0)       ; 경계 안 신설관 길이와 종단 칼라아스콘 연장 허용 차 (M, 또는 5% 중 큰 값)

;; 포장 기호 블럭 (블럭이름 . 포장구분)
;;   (블럭이름 . 포장구분) 또는 (블럭이름 포장구분 도면층) - 도면층을 적으면 그 도면층의 블럭만
;; 포장 기호 블럭(위 BB 등)을 둘러싼 닫힌 영역선 레이어 : 그 영역 테두리를 포장 경계로 봄
;;   (예 비포장 도로면 DA001 안의 비포장 기호 -> 영역 밖 63mm 관에는 적용 안 됨)
(setq *PQ-63-AREA-LAYER* "DA001")

(setq *PQ-63-BLOCKS* '(("B20220502173518" . "보도블럭")
                       ("BB" "비포장" "DAA002")))

;;---- 기하 도구 ----
(defun pq:p2 (p) (list (car p) (cadr p)))

(defun pq:r1 (x) (/ (fix (+ (* x 10.0) (if (< x 0.0) -0.5 0.5))) 10.0))

(defun pq:ltype-hidden (ed / lt)
  (setq lt (cdr (assoc 6 ed)))
  (if (or (null lt) (= (strcase lt) "BYLAYER"))
    (setq lt (cdr (assoc 6 (tblsearch "LAYER" (cdr (assoc 8 ed)))))))
  (and lt (wcmatch (strcase lt) "*HIDDEN*")))

(defun pq:ent-pts (ed / typ pts)
  (setq typ (cdr (assoc 0 ed)))
  (cond
    ((= typ "LINE") (list (pq:p2 (cdr (assoc 10 ed))) (pq:p2 (cdr (assoc 11 ed)))))
    ((= typ "LWPOLYLINE")
     (setq pts (mapcar 'pq:p2 (pq:lw-pts ed)))
     (if (= 1 (logand 1 (cond ((cdr (assoc 70 ed))) (0))))
       (append pts (list (car pts)))
       pts))))

(defun pq:segs (pts / res)
  (while (cadr pts) (setq res (cons (list (car pts) (cadr pts)) res) pts (cdr pts)))
  res)

(defun pq:pl-len (pts / L)
  (setq L 0.0)
  (while (cadr pts) (setq L (+ L (distance (car pts) (cadr pts))) pts (cdr pts)))
  L)

;; 점 -> 폴리선 최단거리, 그 위치의 누적길이  (거리 누적길이)
(defun pq:pl-proj (pts p / acc a b dx dy L2 L u q d best bs)
  (setq acc 0.0)
  (while (cadr pts)
    (setq a (car pts) b (cadr pts)
          dx (- (car b) (car a)) dy (- (cadr b) (cadr a))
          L2 (+ (* dx dx) (* dy dy)) L (sqrt L2)
          u  (if (> L2 0.0)
               (/ (+ (* (- (car p) (car a)) dx) (* (- (cadr p) (cadr a)) dy)) L2)
               0.0)
          u  (max 0.0 (min 1.0 u))
          q  (list (+ (car a) (* u dx)) (+ (cadr a) (* u dy)))
          d  (distance (pq:p2 p) q))
    (if (or (null best) (< d best)) (setq best d bs (+ acc (* u L))))
    (setq acc (+ acc L) pts (cdr pts)))
  (list (cond (best) (1.0e99)) (cond (bs) (0.0))))

;; 폴리선 누적길이 s 위치의 점
(defun pq:pl-at (pts s / a b L res)
  (while (and (cadr pts) (null res))
    (setq a (car pts) b (cadr pts) L (distance a b))
    (if (or (<= s L) (null (cddr pts)))
      (setq res (if (> L 0.0)
                  (list (+ (car a) (* (/ (min s L) L) (- (car b) (car a))))
                        (+ (cadr a) (* (/ (min s L) L) (- (cadr b) (cadr a)))))
                  a))
      (setq s (- s L) pts (cdr pts))))
  (cond (res) ((car pts))))

;; 선분 p1-p2 가 q1-q2 와 교차하면 p1-p2 위 비율(0~1, 끝점 제외) / 아니면 nil
(defun pq:seg-x (p1 p2 q1 q2 / d1x d1y d2x d2y den tt uu)
  (setq d1x (- (car p2) (car p1)) d1y (- (cadr p2) (cadr p1))
        d2x (- (car q2) (car q1)) d2y (- (cadr q2) (cadr q1))
        den (- (* d1x d2y) (* d1y d2x)))
  (if (> (abs den) 1e-12)
    (progn
      (setq tt (/ (- (* (- (car q1) (car p1)) d2y) (* (- (cadr q1) (cadr p1)) d2x)) den)
            uu (/ (- (* (- (car q1) (car p1)) d1y) (* (- (cadr q1) (cadr p1)) d1x)) den))
      ;; 경계선 꼭짓점에서 두 번 세지 않도록 uu 는 [0,1)
      (if (and (> tt 1e-9) (< tt (- 1.0 1e-9)) (>= uu 0.0) (< uu 1.0)) tt))))

;; p-q 선분이 경계선을 하나라도 지나면 T
(defun pq:cross-any (p q segs / hit)
  (while (and segs (not hit))
    (if (pq:seg-x p q (car (car segs)) (cadr (car segs))) (setq hit T))
    (setq segs (cdr segs)))
  hit)

(defun pq:in-r (p R)
  (and (>= (car p) (nth 0 R)) (<= (car p) (nth 2 R))
       (>= (cadr p) (nth 1 R)) (<= (cadr p) (nth 3 R))))

(defun pq:any-in (pts R / hit)
  (foreach p pts (if (pq:in-r p R) (setq hit T)))
  hit)

;; 점 목록의 범위가 R(여유 m 포함)과 겹치면 T
(defun pq:bb-hit (pts R m / bb)
  (setq bb (pq:pts-bbox pts))
  (and bb
       (<= (nth 0 bb) (+ (nth 2 R) m)) (>= (nth 2 bb) (- (nth 0 R) m))
       (<= (nth 1 bb) (+ (nth 3 R) m)) (>= (nth 3 bb) (- (nth 1 R) m))))

(defun pq:set-nth (lst n v / i out)
  (setq i 0)
  (foreach x lst (setq out (cons (if (= i n) v x) out) i (1+ i)))
  (reverse out))

;;---- 문자/객체 수집 ----
(defun pq:collect (types laypat / ss i res)
  (if (setq ss (ssget "X" (list (cons 0 types) (cons 8 laypat) '(410 . "Model"))))
    (repeat (setq i (sslength ss))
      (setq res (cons (entget (ssname ss (setq i (1- i)))) res))))
  res)

;; 관로 수집 (블럭 안 관로 포함) : 레이어가 맞는 LWPOLYLINE/LINE + 그 레이어의 블럭(INSERT) 안 LWPOLYLINE/LINE
;;   블럭 안 객체는 좌표를 도면 좌표로 바꾼 가짜 entget 목록 ((0 . 종류) (5 . "삽입핸들.번호") (8 . 레이어) (6 . 선종류) (70 . 닫힘) (10 x y) ...)
;;   레이어 0 / 선종류 BYBLOCK 인 블럭 안 객체는 삽입 객체의 레이어 / 선종류를 따름
(defun pq:collect-x (types laypat / res ss i ed)
  (setq res (pq:collect types laypat))
  (if (setq ss (ssget "X" (list '(0 . "INSERT") (cons 8 laypat) '(410 . "Model"))))
    (repeat (setq i (sslength ss))
      (setq ed (entget (ssname ss (setq i (1- i)))))
      (setq res (append res (pq:blk-ents (cdr (assoc 2 ed)) (list (pq:ins-xf ed))
                                         (cdr (assoc 8 ed)) (cdr (assoc 6 ed)) (cdr (assoc 5 ed)) 0)))))
  res)

;; INSERT 변환 (기준점 삽입점 X축척 Y축척 회전)
(defun pq:ins-xf (ed / bp)
  (setq bp (cdr (assoc 10 (entget (tblobjname "BLOCK" (cdr (assoc 2 ed)))))))
  (list bp (cdr (assoc 10 ed)) (cond ((cdr (assoc 41 ed))) (1.0)) (cond ((cdr (assoc 42 ed))) (1.0))
        (cond ((cdr (assoc 50 ed))) (0.0))))

;; 점에 변환 목록(안쪽 블럭부터) 적용
(defun pq:xf-chain (p xfs)
  (foreach x xfs (setq p (pq:xf p (nth 0 x) (nth 1 x) (nth 2 x) (nth 3 x) (nth 4 x))))
  p)

;; 블럭 정의 안 LWPOLYLINE/LINE -> 가짜 entget 목록 (중첩 블럭 3단계까지)
(defun pq:blk-ents (nm xfs lay lt h depth / e ed typ out k la lt2 pts)
  (setq e (tblobjname "BLOCK" nm) k 0)
  (while (and e (setq e (entnext e)))
    (setq ed (entget e) typ (cdr (assoc 0 ed)) k (1+ k)
          la (cdr (assoc 8 ed)) la (if (= la "0") lay la)
          lt2 (cdr (assoc 6 ed)) lt2 (if (or (null lt2) (= (strcase lt2) "BYBLOCK")) lt lt2))
    (cond
      ((= typ "LWPOLYLINE")
       (setq pts (mapcar '(lambda (p) (pq:xf-chain (pq:p2 p) xfs)) (pq:lw-pts ed)))
       (setq out (cons (append (list '(0 . "LWPOLYLINE") (cons 5 (strcat h "." (itoa k))) (cons 8 la))
                               (if lt2 (list (cons 6 lt2)))
                               (list (cons 70 (cond ((cdr (assoc 70 ed))) (0))) (cons 90 (length pts)))
                               (mapcar '(lambda (p) (cons 10 p)) pts))
                       out)))
      ((= typ "LINE")
       (setq out (cons (append (list '(0 . "LINE") (cons 5 (strcat h "." (itoa k))) (cons 8 la))
                               (if lt2 (list (cons 6 lt2)))
                               (list (cons 10 (pq:xf-chain (pq:p2 (cdr (assoc 10 ed))) xfs))
                                     (cons 11 (pq:xf-chain (pq:p2 (cdr (assoc 11 ed))) xfs))))
                       out)))
      ((and (= typ "INSERT") (< depth 3))
       (setq out (append (reverse (pq:blk-ents (cdr (assoc 2 ed)) (cons (pq:ins-xf ed) xfs) la lt2
                                               (strcat h "." (itoa k)) (1+ depth)))
                         out)))))
  (reverse out))

;; 블럭 이름 필터로 INSERT 수집
(defun pq:collect-ins (names / ss i res)
  (if (setq ss (ssget "X" (list '(0 . "INSERT") (cons 2 names) '(410 . "Model"))))
    (repeat (setq i (sslength ss))
      (setq res (cons (entget (ssname ss (setq i (1- i)))) res))))
  res)

(defun pq:ent-text (ed / raw)
  (if (= (cdr (assoc 0 ed)) "MTEXT")
    (progn
      (setq raw "")
      (foreach g ed (if (= (car g) 3) (setq raw (strcat raw (cdr g)))))
      (pq:join (pq:strip-mtext (strcat raw (pq:str (cdr (assoc 1 ed))))) " "))
    (pq:str (cdr (assoc 1 ed)))))

;; 문자 위치 : 정렬된 TEXT 는 맞춤점(11), 그 외 삽입점(10)
(defun pq:text-pt (ed / j72 j73)
  (setq j72 (cond ((cdr (assoc 72 ed))) (0)) j73 (cond ((cdr (assoc 73 ed))) (0)))
  (if (and (= (cdr (assoc 0 ed)) "TEXT") (or (/= j72 0) (/= j73 0)))
    (pq:p2 (cdr (assoc 11 ed)))
    (pq:p2 (cdr (assoc 10 ed)))))

(defun pq:p63-pave-name (raw / s n hit)
  (setq s (pq:trim raw) n (pq:norm s))
  (if (pq:pave-map raw) (setq hit T))
  (foreach w *PQ-63-PAVE-WORDS* (if (vl-string-search (pq:norm w) n) (setq hit T)))
  (if (and hit (/= s "") (not (vl-string-search "관" n)))
    (cond ((pq:pave-map raw)) ((cdr (assoc s *PQ-63-ALIAS*))) (s))))

;; 도면 전체 수집 (PAVQ 1회)
(defun pq:p63-prep (/ nm L bb raw info hit lay linfo blkpts)
  (setq *P63-LINES* nil *P63-MAIN* nil *P63-BND* nil *P63-PAVE* nil *P63-NAME* nil *P63-PLAN* nil *P63-RDB* nil)
  (setq *P63-MAINL* nil *P63-BRN* nil *P63-LEAD* nil *P63-HID* nil *P63-CAP* nil *P63-MAINV* nil)
  (setq *PQ-STAGE* "평면도 63mm 수집 - 캡")
  (foreach ed (pq:collect "LWPOLYLINE,LINE" *PQ-63-CAP-LAYER*)
    (setq *P63-CAP* (cons (pq:ent-pts ed) *P63-CAP*)))
  (setq *PQ-STAGE* "평면도 63mm 수집 - 관로")
  ;; 관로 레이어를 관경으로 구분 : 신설관 63mm -> 63mm 관 / 그 외 -> 본관
  (foreach ed (pq:collect-x "LWPOLYLINE,LINE" *PQ-63-PIPE-LAYER*)
    (setq lay (cdr (assoc 8 ed)) linfo (pq:conn-info lay))
    (cond
      ((and (pq:is63 linfo) (vl-string-search *PQ-63-NEW-WORD* lay))
       (if (not (pq:ltype-hidden ed))
         (setq *P63-LINES* (cons (list (cdr (assoc 5 ed)) (pq:ent-pts ed)) *P63-LINES*))
         (setq *P63-HID* (cons (pq:ent-pts ed) *P63-HID*))))
      (T
       ;; 63mm 가 연결될 수 있는 본관 : 신설관 레이어 + 히든 아님
       (if (and (vl-string-search *PQ-63-NEW-WORD* lay) (not (pq:ltype-hidden ed)))
         (setq *P63-MAINV* (cons (pq:ent-pts ed) *P63-MAINV*)))
       (setq *P63-MAIN*  (cons (pq:ent-pts ed) *P63-MAIN*)
             *P63-MAINL* (cons (list (cdr (assoc 5 ed))
                                     (if linfo (strcat (itoa (nth 1 linfo)) (strcase (nth 2 linfo))) (strcase lay))
                                     (pq:ent-pts ed))
                               *P63-MAINL*)))))
  ;; 분기관 관로명 / 지시선
  (setq *PQ-STAGE* "평면도 63mm 수집 - 분기관")
  (if *PQ-BR-PLAN*
    (progn
      (foreach ed (pq:collect "TEXT,MTEXT" *PQ-BR-NAME-LAYER*)
        (setq raw (pq:ent-text ed) L (pq:len raw) info (pq:conn-info raw))
        (setq hit nil)
        (foreach w *PQ-BR-WORDS* (if (vl-string-search w raw) (setq hit T)))
        (if (and L info hit (not (pq:is63 info)))
          (setq *P63-BRN* (cons (list L (pq:text-pt ed) info (pq:trim raw) (cdr (assoc 5 ed))) *P63-BRN*))))
      (foreach ed (pq:collect "LWPOLYLINE,LINE" *PQ-BR-LEADER-LAYER*)
        (setq *P63-LEAD* (cons (pq:ent-pts ed) *P63-LEAD*)))))
  (setq *PQ-STAGE* "평면도 63mm 수집 - 경계/포장문자")
  (foreach ed (pq:collect "LWPOLYLINE,LINE" *PQ-63-BND-LAYER*)
    (setq *P63-BND* (append (pq:segs (pq:ent-pts ed)) *P63-BND*)))
  (if *PQ-63-ROAD-LAYER*
    (foreach ed (pq:collect "LWPOLYLINE,LINE" *PQ-63-ROAD-LAYER*)
      (setq *P63-RDB* (append (pq:segs (pq:ent-pts ed)) *P63-RDB*))))
  (foreach ed (pq:collect "TEXT,MTEXT" *PQ-63-PAVE-LAYER*)
    (if (setq nm (pq:p63-pave-name (pq:ent-text ed)))
      (setq *P63-PAVE* (cons (list nm (pq:text-pt ed)) *P63-PAVE*))))
  (setq *PQ-STAGE* "평면도 63mm 수집 - 포장 블럭")
  (if *PQ-63-BLOCKS*
    (foreach ed (pq:collect-ins (strcat (pq:join (mapcar 'car *PQ-63-BLOCKS*) ",") ",`*U*"))
      (if (and (setq nm (cdr (assoc (strcase (pq:effname (cdr (assoc -1 ed))))
                                    (mapcar '(lambda (b) (cons (strcase (car b)) (cdr b))) *PQ-63-BLOCKS*))))
               ;; (포장 도면층) 형식이면 도면층 확인
               (or (atom nm)
                   (null (cadr nm))
                   (wcmatch (strcase (cdr (assoc 8 ed))) (strcase (cadr nm)))))
        (setq *P63-PAVE* (cons (list (if (atom nm) nm (car nm)) (pq:p2 (cdr (assoc 10 ed)))) *P63-PAVE*)
              blkpts     (cons (pq:p2 (cdr (assoc 10 ed))) blkpts)))))
  ;; 포장 기호 블럭이 들어 있는 닫힌 영역선 -> 경계에 추가
  (setq *PQ-STAGE* "평면도 63mm 수집 - 포장 영역선")
  (if *PQ-63-AREA-LAYER*
    (foreach ed (pq:collect "LWPOLYLINE" *PQ-63-AREA-LAYER*)
      (if (= 1 (logand 1 (cond ((cdr (assoc 70 ed))) (0))))
        (progn
          (setq bb (mapcar 'pq:p2 (pq:lw-pts ed)))
          (if (vl-some '(lambda (q) (pq:pt-in-poly q bb)) blkpts)
            (setq *P63-BND* (append (pq:segs (pq:ent-pts ed)) *P63-BND*)))))))
  (setq *PQ-STAGE* "평면도 63mm 수집 - 보도블럭 문자" *P63-SW* nil)
  (foreach ed (pq:collect "TEXT,MTEXT" "*")
    (if (vl-some '(lambda (w) (vl-string-search (pq:norm w) (pq:norm (pq:ent-text ed)))) *PQ-63-SW-WORDS*)
      (setq *P63-SW* (cons (pq:text-pt ed) *P63-SW*))))
  ;; 보도블럭 블럭(*PQ-63-BLOCKS*) 위치도 포함
  (foreach lb *P63-PAVE*
    (if (= (pq:norm (car lb)) (pq:norm *PQ-63-SW-NAME*)) (setq *P63-SW* (cons (cadr lb) *P63-SW*))))
  (setq *PQ-STAGE* "평면도 63mm 수집 - 관로명/측점")
  (foreach ed (pq:collect "TEXT,MTEXT" *PQ-63-NAME-LAYER*)
    (if (setq L (pq:len (pq:ent-text ed)))
      (setq *P63-NAME* (cons (list L (pq:text-pt ed) (cdr (assoc 5 ed)) (cond ((cdr (assoc 50 ed))) (0.0))) *P63-NAME*))))
  ;; 보조 : 일반 관로명 레이어 (63mm 관로명 레이어가 아닌 것, 문자에 63 이 있는 것만)
  (setq *P63-NAME2* nil)
  (if *PQ-63-NAME-LAYER2*
    (foreach ed (pq:collect "TEXT,MTEXT" *PQ-63-NAME-LAYER2*)
      (if (and (not (wcmatch (strcase (cdr (assoc 8 ed))) (strcase *PQ-63-NAME-LAYER*)))
               (wcmatch (strcase (cond ((pq:ent-text ed)) (""))) "*63*")
               (setq L (pq:len (pq:ent-text ed))))
        (setq *P63-NAME2* (cons (list L (pq:text-pt ed) (cdr (assoc 5 ed)) (cond ((cdr (assoc 50 ed))) (0.0))) *P63-NAME2*)))))
  (setq *P63-NOS* nil)
  (if *PQ-63-PROFILE*
    (foreach ed (pq:collect "TEXT,MTEXT" *PQ-STA-LAYER*)
      (if (setq L (pq:sta-parse (pq:ent-text ed) nil))
        (setq *P63-NOS* (cons (list L (pq:text-pt ed)) *P63-NOS*)))))
  (foreach ed (pq:collect "LWPOLYLINE" *PQ-PLAN-LAYER*)
    (if (and (= 1 (logand 1 (cond ((cdr (assoc 70 ed))) (0))))
             (setq bb (pq:pts-bbox (pq:lw-pts ed))))
      (setq *P63-PLAN* (cons bb *P63-PLAN*)))))

;; 도곽의 평면도 사각형 (도곽 안 가장 큰 L 사각형, 없으면 도곽 전체)
;;   평면도가 L 사각형 여러 개로 나뉘어 나란히 있으면(위·아래 높이가 같음) 모두 합친 범위
(defun pq:p63-rect (f / best u tol)
  (setq best (pq:p63-main f) u best)
  (if (and best (not (eq best f)))
    (progn
      (setq tol (* 0.02 (- (nth 3 best) (nth 1 best))))
      (foreach r (pq:p63-plans f)
        (if (and (equal (nth 1 r) (nth 1 best) tol) (equal (nth 3 r) (nth 3 best) tol))
          (setq u (list (min (nth 0 u) (nth 0 r)) (min (nth 1 u) (nth 1 r))
                        (max (nth 2 u) (nth 2 r)) (max (nth 3 u) (nth 3 r))))))))
  u)

;; 도곽 안 L 사각형 목록
(defun pq:p63-plans (f / cx cy out)
  (foreach r *P63-PLAN*
    (setq cx (/ (+ (nth 0 r) (nth 2 r)) 2.0) cy (/ (+ (nth 1 r) (nth 3 r)) 2.0))
    (if (pq:in-r (list cx cy) f) (setq out (cons r out))))
  out)

;; 도곽 안 가장 큰 L 사각형 (주 평면도), 없으면 도곽 전체
(defun pq:p63-main (f / best ba a)
  (foreach r (pq:p63-plans f)
    (setq a (* (- (nth 2 r) (nth 0 r)) (- (nth 3 r) (nth 1 r))))
    (if (or (null ba) (> a ba)) (setq best r ba a)))
  (cond (best) (f)))

;;---- 포장 찾기 ----
;; pt 에서 경계에 가리지 않는 가장 가까운 포장 -> (포장 표시)
(defun pq:p63-sw (pt segs / hit)
  (foreach q *P63-SW*
    (if (and (null hit) (<= (distance pt q) *PQ-63-SW-R*) (not (pq:cross-any pt q segs)))
      (setq hit T)))
  hit)

(defun pq:p63-label-from (pt labs segs / srt hit)
  (if (pq:p63-sw pt segs)
    (list *PQ-63-SW-NAME* "")
  (if (null labs)
    (list "미확인" "포장문자없음")
    (progn
      (setq srt (vl-sort labs '(lambda (a b) (< (distance pt (cadr a)) (distance pt (cadr b))))))
      (foreach lb srt
        (if (and (null hit) (<= (distance pt (cadr lb)) *PQ-63-LABEL-R*)
                 (not (pq:cross-any pt (cadr lb) segs)))
          (setq hit lb)))
      (if hit (list (car hit) "") (list (car (car srt)) "가림"))))))

;; 도로측 포장 : 본관을 따라 앞뒤 *PQ-63-RANGE* 안의 지점에서 가리지 않는 포장
;;   점수 = 본관 따라 이동거리 + 문자까지 거리  (가장 작은 것)
(defun pq:p63-road (ap mains labs segs / pr s0 L k kmax s sp prev d sc best sg stop)
  ;; 본관을 따라 출발점에서 앞/뒤로 *PQ-63-STEP* 씩 이동, 경계(ADA030/ZC154/AE001)를 넘으면 그 방향은 멈춤
  (setq kmax (fix (/ *PQ-63-RANGE* *PQ-63-STEP*)))
  (foreach m mains
    (setq pr (pq:pl-proj m ap))
    (if (<= (car pr) *PQ-63-TOL*)
      (progn
        (setq s0 (cadr pr) L (pq:pl-len m))
        (foreach sg '(1 -1)
          (setq k 0 stop nil prev (pq:pl-at m s0))
          (while (and (not stop) (<= k kmax))
            (setq s (+ s0 (* sg k *PQ-63-STEP*)))
            (if (or (< s 0.0) (> s L))
              (setq stop T)
              (progn
                (setq sp (pq:pl-at m s))
                (if (and (> k 0) (pq:cross-any prev sp segs))
                  (setq stop T)
                  (progn
                    (setq prev sp)
                    (foreach lb labs
                      (setq d (distance sp (cadr lb)) sc (+ (abs (- s s0)) d))
                      (if (and (<= d *PQ-63-LABEL-R*)
                               (or (null best) (< sc (car best)))
                               (not (pq:cross-any sp (cadr lb) segs)))
                        (setq best (list sc (car lb)))))))))
            (setq k (1+ k)))))))
  (cond
    ((pq:p63-sw ap segs) (list *PQ-63-SW-NAME* ""))
    (best (list (cadr best) ""))
    (T (pq:p63-label-from ap labs segs))))

;; 경계와 만나는 누적길이 목록
(defun pq:p63-cuts (pts segs / acc a b L tt res)
  (setq acc 0.0)
  (while (cadr pts)
    (setq a (car pts) b (cadr pts) L (distance a b))
    (foreach sg segs
      (if (setq tt (pq:seg-x a b (car sg) (cadr sg)))
        (setq res (cons (+ acc (* tt L)) res))))
    (setq acc (+ acc L) pts (cdr pts)))
  (vl-sort res '<))

;; 관 1개 처리 -> (핸들 점목록 ((시작 끝 포장 위치 표시) ...))
(defun pq:p63-resolve (rc road labs segs / pts G prev k out mid lf c rd1 mg lb)
  (setq pts (cadr rc) G (pq:pl-len pts) prev 0.0 k 0)
  ;; 도로 경계(ADA030)를 처음 넘는 곳 (본관 쪽 끝부터 누적길이) / 없으면 관 끝
  (setq rd1 (car (pq:p63-cuts pts (vl-remove-if-not '(lambda (sg) (pq:bb-hit sg (pq:pts-bbox pts) 1.0)) *P63-RDB*))))
  (foreach c (append (pq:p63-cuts pts segs) (list G))
    (if (>= (- c prev) 0.05)
      ;; 처음 경계를 넘기 전 조각만 도로측, 넘은 뒤 조각은 모두 경계밖 (ADA030+ZC154+AE001 를 하나의 경계로)
      (if (= k 0)
        (setq out (cons (list prev c (car road) "도로측" (cadr road)) out))
        (progn
          (setq mid (pq:pl-at pts (/ (+ prev c) 2.0))
                lf  (pq:p63-label-from mid labs segs))
          ;; 경계에 가려 보이는 포장 문자가 없는데 아직 도로 경계(ADA030) 안쪽 -> 도로측 포장
          ;;   (예 칼라아스콘 띠와 보도 경계 사이 좁은 도로 가장자리 -> 건너편 보도블럭 기호를 잡지 않게)
          (if (= (cadr lf) "가림")
            (if (or (null rd1) (< (/ (+ prev c) 2.0) rd1))
              (setq lf (list (car road) ""))
              ;; 도로 경계 밖 : 도로 경계(ADA030)를 사이에 두지 않은 같은 쪽 문자 중 가장 가까운 것
              ;;   (보도 안 보도블럭 기호처럼 도로 경계 건너편 문자를 잡지 않게) / 없으면 그대로(가장 가까운 문자)
              (if (setq lb (pq:p63-label-side mid labs))
                (setq lf (list (car lb) "가림")))))
          (setq out (cons (list prev c (car lf) "경계밖" (cadr lf)) out)))))
    (setq prev c k (1+ k)))
  (if (null out) (setq out (list (list 0.0 G (car road) "도로측" (cadr road)))))
  ;; 이어진 조각이 같은 포장구분(칼라아스콘을 MMA/A.S.P 로 정했으면 A.S.P)이면 한 조각으로 합침
  ;;   -> 확인선 1개, 집계 수식 항목 1개
  (foreach pc (reverse out)
    (setq pc (list (nth 0 pc) (nth 1 pc) (pq:kmap *PQ-CUR-FI* (nth 2 pc)) (nth 3 pc) (nth 4 pc)))
    (if (and mg (= (nth 2 (car mg)) (nth 2 pc)))
      (setq mg (cons (list (nth 0 (car mg)) (nth 1 pc) (nth 2 pc) (nth 3 (car mg))
                           (if (/= (pq:str (nth 4 (car mg))) "") (nth 4 (car mg)) (nth 4 pc)))
                     (cdr mg)))
      (setq mg (cons pc mg))))
  (list (car rc) pts (reverse mg)))

;; pt 에서 도로 경계(*P63-RDB*)를 넘지 않는 가장 가까운 포장 문자 (*PQ-63-LABEL-R* 안) / nil
(defun pq:p63-label-side (pt labs / rd srt hit)
  (setq rd (vl-remove-if-not '(lambda (sg) (pq:bb-hit sg (list (- (car pt) *PQ-63-LABEL-R*) (- (cadr pt) *PQ-63-LABEL-R*)
                                                              (+ (car pt) *PQ-63-LABEL-R*) (+ (cadr pt) *PQ-63-LABEL-R*)) 0.0))
                             *P63-RDB*)
        srt (vl-sort labs '(lambda (a b) (< (distance pt (cadr a)) (distance pt (cadr b))))))
  (foreach lb srt
    (if (and (null hit) (<= (distance pt (cadr lb)) *PQ-63-LABEL-R*) (not (pq:cross-any pt (cadr lb) rd)))
      (setq hit lb)))
  hit)

;; 부모 관에서 점 위치의 포장
(defun pq:p63-pave-at (pr pt / s hit bd d)
  (setq s (cadr (pq:pl-proj (cadr pr) pt)))
  (foreach pc (caddr pr)
    (setq d (cond ((< s (car pc)) (- (car pc) s)) ((> s (cadr pc)) (- s (cadr pc))) (T 0.0)))
    (if (or (null bd) (< d bd)) (setq hit pc bd d)))
  (list (nth 2 hit) (nth 4 hit)))

(defun pq:min-dist (p plist / best d)
  (foreach m plist
    (setq d (car (pq:pl-proj m p)))
    (if (or (null best) (< d best)) (setq best d)))
  (cond (best) (1.0e99)))

;; 점에서 가장 가까운 다른 63mm 관 -> (거리 핸들)
(defun pq:nearest-line (p lines / best d)
  (foreach l lines
    (setq d (car (pq:pl-proj (cadr l) p)))
    (if (or (null best) (< d (car best))) (setq best (list d (car l)))))
  best)

;; 길이 N 을 조각 길이 비율로 배분 (소수 첫째, 차이는 가장 긴 조각) -> ((포장 길이 위치 표시) ...)
(defun pq:p63-alloc (N pcs G / res sum big bi i x)
  (foreach pc pcs
    (setq res (append res (list (list (nth 2 pc)
                                      (if (> G 0.0) (pq:r1 (* N (/ (- (cadr pc) (car pc)) G))) 0.0)
                                      (nth 3 pc) (nth 4 pc))))))
  (setq sum 0.0 i 0 bi 0)
  (foreach x res
    (setq sum (+ sum (cadr x)))
    (if (or (null big) (> (cadr x) big)) (setq big (cadr x) bi i))
    (setq i (1+ i)))
  (if res
    (setq x   (nth bi res)
          res (pq:set-nth res bi (list (nth 0 x) (pq:r1 (+ (cadr x) (- N sum))) (nth 2 x) (nth 3 x)))))
  (vl-remove-if '(lambda (x) (<= (cadr x) 0.0)) res))

;; 한 관의 배분 결과를 포장별로 묶고, 포장이 2개 이상이면 *PQ-63-MIN-PAVE* 이하 포장을 가장 긴 포장에 합산
;;   al = ((포장 길이 위치 표시) ...) -> 같은 형식
(defun pq:p63-merge (al / grp hit big out small)
  ;; 포장별 합계 (위치/표시는 가장 긴 조각 기준)
  (foreach x al
    (if (setq hit (assoc (car x) grp))
      (setq grp (subst (list (car x) (pq:r1 (+ (cadr hit) (cadr x)))
                             (if (> (cadr x) (cadr hit)) (nth 2 x) (nth 2 hit))
                             (if (/= (nth 3 hit) "") (nth 3 hit) (nth 3 x)))
                       hit grp))
      (setq grp (append grp (list x)))))
  (if (cdr grp)
    (progn
      (foreach x grp (if (or (null big) (> (cadr x) (cadr big))) (setq big x)))
      (foreach x grp
        (if (and (not (eq x big)) (<= (cadr x) (+ *PQ-63-MIN-PAVE* 1e-6)))
          (setq small (cons x small))))
      (foreach x small
        (setq *PQ-MERGED* (cons (list (car x) (cadr x) (car big)) *PQ-MERGED*)
              grp (vl-remove x grp)
              big (list (car big) (pq:r1 (+ (cadr big) (cadr x))) (nth 2 big) (nth 3 big))))
      (setq out nil)
      (foreach x grp
        (setq out (cons (if (= (car x) (car big)) big x) out)))
      (reverse out))
    grp))

;; 도곽 1장의 평면도 분기관 -> ((핸들 관로명길이 포장 길이 위치 표시 관경정보 관로명) ...)
(defun pq:br-frame (f fi / R mains mainl segs labs brs leads L pt info dtag spots best G d m
                       pts others ap road rc res mg out)
  (setq R     (pq:p63-rect f)
        mains (vl-remove-if-not '(lambda (m) (pq:bb-hit m R 5.0)) *P63-MAIN*)
        mainl (vl-remove-if-not '(lambda (m) (pq:bb-hit (caddr m) R 5.0)) *P63-MAINL*)
        segs  (vl-remove-if-not '(lambda (s) (pq:bb-hit s R 5.0)) *P63-BND*)
        labs  (vl-remove-if-not '(lambda (l) (pq:in-r (cadr l) R)) *P63-PAVE*)
        brs   (vl-remove-if-not '(lambda (b) (pq:in-r (cadr b) R)) *P63-BRN*)
        leads (vl-remove-if-not '(lambda (l) (pq:bb-hit l R 5.0)) *P63-LEAD*))
  ;; 종단면도에 같은 관경·같은 길이(±0.1M) 관이 있으면 그 종단에서 이미 집계 -> 제외
  (setq brs (vl-remove-if
              '(lambda (b)
                 (vl-some '(lambda (e) (and (= (nth 1 (cadr e)) (nth 1 (caddr b)))
                                            (= (nth 2 (cadr e)) (nth 2 (caddr b)))
                                            (<= (abs (- (caddr e) (car b))) 0.1)))
                          *PQ-BR-PROF*))
              brs))
  (foreach b brs
    (setq L (car b) pt (cadr b) info (caddr b)
          dtag (strcat (itoa (nth 1 info)) (if (= (nth 2 info) "mm") "MM" "A"))
          spots (list pt) best nil)
    ;; 관로명 문자에 닿은 지시선의 반대쪽 끝도 찾는 위치로 사용
    (foreach ld leads
      (cond ((<= (distance (car ld) pt) 3.0) (setq spots (cons (last ld) spots)))
            ((<= (distance (last ld) pt) 3.0) (setq spots (cons (car ld) spots)))))
    ;; 후보 : 레이어 이름에 같은 관경, 그린 길이가 관로명 길이와 비슷한 선
    (foreach m mainl
      (if (= dtag (cadr m))
        (progn
          (setq G (pq:pl-len (caddr m)))
          (if (<= (abs (- G L)) (max 0.6 (* 0.2 L)))
            (foreach sp spots
              (setq d (car (pq:pl-proj (caddr m) sp)))
              (if (and (<= d *PQ-63-NAME-R*) (or (null best) (< d (car best))))
                (setq best (list d m))))))))
    (if best
      (progn
        (setq m (cadr best) pts (caddr m)
              others (vl-remove pts mains))
        ;; 출발점 : 다른 본관에 붙은 끝
        (if (< (pq:min-dist (last pts) others) (pq:min-dist (car pts) others))
          (setq pts (reverse pts)))
        (setq ap (car pts)
              road (pq:p63-road ap others labs segs)
              rc (pq:p63-resolve (list (car m) pts 'M nil) road labs segs)
              G 0.0)
        (foreach pc (caddr rc) (setq G (+ G (- (cadr pc) (car pc)))))
        (setq *PQ-MERGED* nil
              mg (pq:p63-merge (pq:p63-alloc L (caddr rc) G)))
        (foreach mm (reverse *PQ-MERGED*)
          (setq *PQ-MERGE-NOTES* (cons (list fi (car m) L (nth 0 mm) (nth 1 mm) (nth 2 mm)) *PQ-MERGE-NOTES*)))
        (foreach x mg
          (if (= (nth 3 x) "가림")
            (pq:err fi nil nil nil
                    (strcat "평면도 분기관 [" (car m) " / " (nth 3 b) "] " (nth 2 x)
                            " 조각 : 경계에 가리지 않는 포장 문자가 없어 가장 가까운 " (nth 0 x) " 적용 (확인)")))
          (setq out (cons (list (car m) L (nth 0 x) (nth 1 x) (nth 2 x) (nth 3 x) info (nth 3 b) (car (car pts))) out))))
      (progn
        (setq res (pq:p63-label-from (car spots) labs segs))
        (pq:err fi nil nil nil
                (strcat "평면도 분기관 [" (nth 3 b) "] 같은 관경·비슷한 길이의 선을 못 찾음 -> 관로명 위치 기준 "
                        (car res) " 로 집계 (확인)"))
        (setq out (cons (list (nth 4 b) L (car res) L "관로명위치" (cadr res) info (nth 3 b) (car pt)) out)))))
  (reverse out))

;; 오류 메시지용 관 표시 : [핸들 / 평면도 LP 63mm PE(Nm)]
(defun pq:p63-tag (h asg / n)
  (setq n (cdr (assoc h asg)))
  (strcat "[" h " / 평면도 "
          (if n (strcat "LP 63mm PE(" (rtos n 2 (if (equal n (fix n) 1e-6) 0 1)) "m)") "관로명 없음")
          "]"))

;; 측점 문자 -> 거리(m)  "STA NO.6+0.00" -> 120, "NO.7" -> 140, "NO.6+14.0" -> 134
;;   need-sta : T 면 "STA" 가 있어야 함
(defun pq:sta-parse (raw need-sta / s p i n d m)
  (setq s (strcase (pq:nospace raw)))
  (if (and (setq p (vl-string-search "NO" s))
           (or (not need-sta) (vl-string-search "STA" s)))
    (progn
      (setq i (+ p 3) d "")
      (if (= (substr s i 1) ".") (setq i (1+ i)))
      (while (wcmatch (substr s i 1) "#") (setq d (strcat d (substr s i 1)) i (1+ i)))
      (if (> (strlen d) 0)
        (progn
          (setq n (* (atoi d) *PQ-STA-PITCH*) m 0.0)
          (if (= (substr s i 1) "+")
            (progn
              (setq d "" i (1+ i))
              (while (or (wcmatch (substr s i 1) "#") (= (substr s i 1) "."))
                (setq d (strcat d (substr s i 1)) i (1+ i)))
              (setq m (atof d))))
          (+ n m))))))

;; 종단 63mm 인출선 -> ((측점거리 길이 포장 원문 측점X 경계양쪽포장) ...)
;;   "63mm-8M" 처럼 63mm 와 길이가 있는 문자 (연결관 제외), 인출선 측점 X -> 종단 포장 구간
(defun pq:p63-profile (flines fsegs / raw info L st fs pv sta0 best bd out tie bnd x0 sc ach axs)
  (foreach ln flines
    (setq raw (car ln) *PQ-SUB* (strcat "종단 63mm 인출선 " (pq:str raw)))
    (if (and (not (vl-string-search "연결관" (pq:norm raw)))
             (pq:is63 (setq info (pq:conn-info raw)))
             (setq L (pq:len-any raw))
             (setq st (pq:lead-station ln))
             (setq fs (pq:prof-at st (cond ((nth 6 ln)) ((caddr ln))) fsegs))
             (nth 5 fs)
             ;; 인출선 측점을 품는 밴드 (한 행에 종단이 여러 개일 수 있음) - 측점표가 있으면 없어도 됨
             (progn (setq bnd (pq:band-at (nth 8 fs) st)) T))
      (progn
        (setq x0 (car bnd) sc (caddr bnd))
        ;; 경계 위면 (짧은 쪽, (양쪽 포장)) -> 나중에 평면도 도로측 포장이 양쪽 중 하나면 그것 사용
        (setq pv (pq:pint-at (nth 5 fs) st) tie nil)
        (if (and pv (cadr pv))
          (setq tie (list (nth 2 pv) (nth 3 pv))
                pv  (list (if (<= (nth 4 pv) (nth 5 pv)) (nth 2 pv) (nth 3 pv)) nil)))
        ;; 종단 시작 측점 : 밴드 시작 X 근처의 "STA NO.x+m" 문자
        (setq best nil bd nil)
        (if bnd
        (foreach o flines
          (if (and (setq sta0 (pq:sta-parse (car o) T))
                   (<= (abs (- (cond ((nth 5 o)) ((cadr o))) x0)) 5.0)
                   (or (null bd) (< (abs (- (cond ((nth 5 o)) ((cadr o))) x0)) bd)))
            (setq best sta0 bd (abs (- (cond ((nth 5 o)) ((cadr o))) x0))))))
        ;; STA 문자가 없으면 "공사시점" 문자를 측점 0 으로 (분기 관로 종단 등)
        (if (and bnd (null best))
          (foreach o flines
            (if (and (null best)
                     (<= (abs (- (cond ((nth 5 o)) ((cadr o))) x0)) 5.0))
              (foreach w *PQ-STA-START*
                (if (vl-string-search w (pq:norm (car o))) (setq best 0.0))))))
        ;; 측점표 누가거리 줄이 있으면 그것으로 (STA 문자/축척보다 우선)
        (setq ach (if (setq axs (pq:axis-at st (cond ((nth 6 ln)) ((caddr ln))))) (pq:axis-chain axs flines)))
        (cond
          ((and ach pv (car pv))
           (setq out (cons (list (pq:chain-at ach st) L (car pv) (pq:trim raw) st tie) out)))
          ((and bnd best pv (car pv))
           (setq out (cons (list (+ best (/ (- st x0) sc)) L (car pv) (pq:trim raw) st tie) out)))))))
  (reverse out))

;; 밴드 목록 ((X0 X1 축척) ...) 중 X 를 품는 것 (없으면 가장 가까운 것, 3m 이내)
(defun pq:band-at (bands x / best bd d)
  (foreach b bands
    (setq d (cond ((< x (car b)) (- (car b) x)) ((> x (cadr b)) (- x (cadr b))) (T 0.0)))
    (if (and (<= d 3.0) (or (null bd) (< d bd))) (setq best b bd d)))
  best)

;; 본관 m 에 속한 NO 문자 -> ((누적길이 측점) ...)
;;   NO 문자는 *PQ-STA-NEAR* 안에서 가장 가까운 본관 하나에만 속함 (분기 관로에 본관 NO 가 섞이지 않게)
(defun pq:main-nos (m mains nos / pr res)
  (foreach n nos
    (setq pr (pq:pl-proj m (cadr n)))
    (if (and (<= (car pr) *PQ-STA-NEAR*)
             (<= (car pr) (+ (pq:min-dist (cadr n) mains) 1e-6)))
      (setq res (cons (list (cadr pr) (car n)) res))))
  res)

;; 평면도 점(본관 위) -> 측점거리 (평면도 NO 문자를 같은 본관에 투영해 보간) / nil
;;   그 본관의 NO 가 2개 미만이면 끝이 맞닿은 이웃 본관의 NO 를 연장선 위치로 빌려옴
(defun pq:plan-chain (ap mains nos / m mk t0 a b up kp Lm Ln tj sj)
  (foreach mm mains
    (if (and (null m) (<= (car (pq:pl-proj mm ap)) *PQ-63-TOL*)) (setq m mm)))
  (if m
    (progn
      (setq t0 (cadr (pq:pl-proj m ap))
            mk (pq:main-nos m mains nos))
      (if (< (length mk) 2)
        (progn
          (setq Lm (pq:pl-len m))
          (foreach n mains
            (if (not (eq n m))
              (progn
                (setq Ln (pq:pl-len n))
                (foreach em (list (list (car m) 0.0) (list (last m) Lm))
                  (foreach en (list (list (car n) T) (list (last n) nil))
                    (if (<= (distance (car em) (car en)) *PQ-63-TOL*)
                      (foreach x (pq:main-nos n mains nos)
                        (setq sj (if (cadr en) (car x) (- Ln (car x)))
                              tj (cadr em)
                              mk (cons (list (if (= tj 0.0) (- sj) (+ tj sj)) (cadr x)) mk)))))))))))
      (setq mk (pq:isort mk '(lambda (x y) (< (car x) (car y)))))
      ;; 다른 관로의 NO 문자가 섞이면 순서가 어긋나므로 단조(계속 증가 또는 감소)인 것만 남김
      (if (cdr mk)
        (progn
          (setq up (> (cadr (last mk)) (cadr (car mk))) kp (list (car mk)))
          (foreach x (cdr mk)
            (if (if up (> (cadr x) (cadr (car kp))) (< (cadr x) (cadr (car kp))))
              (setq kp (cons x kp))))
          (setq mk (reverse kp))))
      (if (cdr mk)
        (progn
          ;; t0 를 감싸는 두 NO (없으면 가장 가까운 두 개)
          (setq a (car mk) b (cadr mk))
          (foreach x (cdr mk)
            (if (<= (car x) t0) (setq a x)))
          (foreach x (reverse mk)
            (if (>= (car x) t0) (setq b x)))
          (if (equal (car a) (car b) 1e-6)
            (setq a (car mk) b (cadr mk)))
          (+ (cadr a) (* (- t0 (car a)) (/ (- (cadr b) (cadr a)) (- (car b) (car a))))))))))

;;------------------------ 포장 부속 (횡단보도 / 과속방지턱) ------------------------
;; 다각형 면적 (꼭짓점 목록, 마지막=처음 이어도 됨)
(defun pq:poly-area (pts / a q)
  (setq a 0.0 q (append pts (list (car pts))))
  (while (cadr q)
    (setq a (+ a (- (* (car (car q)) (cadr (cadr q))) (* (car (cadr q)) (cadr (car q)))))
          q (cdr q)))
  (abs (/ a 2.0)))

;; 점이 다각형 안이면 T (반직선 교차 수)
(defun pq:pt-in-poly (p pts / in q a b)
  (setq q (append pts (list (car pts))))
  (while (cadr q)
    (setq a (car q) b (cadr q))
    (if (and (/= (> (cadr a) (cadr p)) (> (cadr b) (cadr p)))
             (< (car p) (+ (car a) (/ (* (- (car b) (car a)) (- (cadr p) (cadr a))) (- (cadr b) (cadr a))))))
      (setq in (not in)))
    (setq q (cdr q)))
  in)

;; 다각형과 관 폴리선이 겹치면 T (변끼리 교차 또는 관 꼭짓점이 다각형 안)
(defun pq:poly-hit (poly pipe / hit e1 q)
  (foreach v pipe (if (and (null hit) (pq:pt-in-poly v poly)) (setq hit T)))
  (setq q (append poly (list (car poly))))
  (while (and (null hit) (cadr q))
    (setq e1 pipe)
    (while (and (null hit) (cadr e1))
      (if (or (pq:seg-x (car e1) (cadr e1) (car q) (cadr q))
              (pq:seg-x (car q) (cadr q) (car e1) (cadr e1)))
        (setq hit T))
      (setq e1 (cdr e1)))
    (setq q (cdr q)))
  hit)

(defun pq:bb-over (a b)
  (and (<= (nth 0 a) (nth 2 b)) (>= (nth 2 a) (nth 0 b))
       (<= (nth 1 a) (nth 3 b)) (>= (nth 3 a) (nth 1 b))))

;; 도면 전체 -> ((도곽번호 구분 핸들 면적) ...)
(defun pq:acc-collect (frames / pipes res pts bb cen j fi gap)
  (foreach ed (pq:collect-x "LWPOLYLINE,LINE" *PQ-ACC-PIPE*)
    (if (not (pq:ltype-hidden ed))
      (setq pts (pq:ent-pts ed) pipes (cons (list (pq:pts-bbox pts) pts) pipes))))
  (foreach k *PQ-ACC*
    (foreach ed (pq:collect "LWPOLYLINE" (cadr k))
      (setq pts (mapcar 'pq:p2 (pq:lw-pts ed))
            gap (if pts (distance (car pts) (last pts)) 0.0))
      (if (and (cddr pts) (< gap 1e-6)) (setq pts (reverse (cdr (reverse pts)))))
      (if (cddr pts)
        (progn
          (setq bb (pq:pts-bbox pts)
                cen (list (/ (apply '+ (mapcar 'car pts)) (length pts)) (/ (apply '+ (mapcar 'cadr pts)) (length pts)))
                j 0 fi nil)
          (foreach f frames
            (setq j (1+ j))
            (if (and (null fi) (pq:in-r cen (pq:p63-rect f))) (setq fi j)))
          (if (and fi (vl-some '(lambda (pp) (and (pq:bb-over bb (car pp)) (pq:poly-hit pts (cadr pp)))) pipes))
            (progn
              (if (and (/= 1 (logand 1 (cond ((cdr (assoc 70 ed))) (0)))) (> gap 0.5))
                (pq:err fi nil nil nil
                        (strcat (car k) " [" (cdr (assoc 5 ed)) "] 닫히지 않은 폴리선 -> 끝점을 이어 면적 계산 (확인)")))
              (setq res (cons (list fi (car k) (cdr (assoc 5 ed)) (pq:poly-area pts) (car cen)) res))))))))
  ;; 수식 더하기 순서 = 도면 왼쪽부터 (중심 X 순)
  (mapcar '(lambda (r) (list (nth 0 r) (nth 1 r) (nth 2 r) (nth 3 r)))
          (pq:isort res '(lambda (a b) (< (nth 4 a) (nth 4 b))))))

;; 점 p 가 63mm 캡 표시에 붙어 있으면 T
(defun pq:cap-at (p caps)
  (and caps (<= (pq:min-dist p caps) *PQ-63-CAP-TOL*)))

;; 두 방향(라디안)이 tol(도) 이내로 나란하면 T (180도 반대 방향도 나란한 것으로)
(defun pq:ang-par (a1 a2 tol / d)
  (setq d (rem (abs (- a1 a2)) pi))
  (<= (min d (- pi d)) (* tol (/ pi 180.0))))

;; 점 p 와 (점 q, 방향 ang) 축선 사이 수직 거리 / 축 방향 거리
(defun pq:axis-perp (p q ang)
  (abs (- (* (- (car p) (car q)) (sin ang)) (* (- (cadr p) (cadr q)) (cos ang)))))
(defun pq:axis-along (p q ang)
  (abs (+ (* (- (car p) (car q)) (cos ang)) (* (- (cadr p) (cadr q)) (sin ang)))))

;; 끊겨 그려진 63mm 관 잇기 : 두 관 끝이 맞닿고, 그 끝에 캡/본관/제3의 63mm 관이 없으면 한 관으로
(defun pq:p63-join (lines mains caps / go l1 l2 e1 e2 p1 p2 hit rest)
  (setq go T)
  (while go
    (setq go nil hit nil)
    (foreach l1 lines
      (foreach l2 lines
        (if (and (null hit) (not (eq l1 l2)))
          (foreach e1 (list (car (cadr l1)) (last (cadr l1)))
            (foreach e2 (list (car (cadr l2)) (last (cadr l2)))
              (if (and (null hit)
                       (<= (distance e1 e2) *PQ-63-TOL*)
                       (not (pq:cap-at e1 caps)) (not (pq:cap-at e2 caps))
                       (> (pq:min-dist e1 mains) *PQ-63-TOL*)
                       (not (vl-some '(lambda (o) (and (not (eq o l1)) (not (eq o l2))
                                                       (<= (car (pq:pl-proj (cadr o) e1)) *PQ-63-TOL*)))
                                     lines)))
                (setq hit (list l1 l2 e1 e2))))))))
    (if hit
      (progn
        (setq l1 (car hit) l2 (cadr hit)
              p1 (if (equal (last (cadr l1)) (caddr hit) 1e-9) (cadr l1) (reverse (cadr l1)))
              p2 (if (equal (car (cadr l2)) (cadddr hit) 1e-9) (cadr l2) (reverse (cadr l2)))
              rest (vl-remove-if '(lambda (o) (or (eq o l1) (eq o l2))) lines)
              lines (cons (list (car l1) (append p1 (cdr p2))) rest)
              go T))))
  lines)

;; 도곽 1장 -> ((핸들 관로명길이 포장 길이 위치 표시) ...)
(defun pq:p63-frame (f fi flines fsegs / names2 nl reach vmains excl xdist cused mg pro63 nos pmatch chmap c1 best bd pe used2 d rd R lines mains segs labs names recs h pts a b dma dmb others pa pb
                       done prog pr pairs asg usedn N G out caps capped rr)
  (setq R     (pq:p63-rect f)
        lines (vl-remove-if-not '(lambda (l) (pq:any-in (cadr l) R)) *P63-LINES*)
        mains (vl-remove-if-not '(lambda (m) (pq:bb-hit m R 5.0)) *P63-MAIN*)
        segs  (vl-remove-if-not '(lambda (s) (pq:bb-hit s R 5.0)) *P63-BND*)
        labs  (vl-remove-if-not '(lambda (l) (pq:in-r (cadr l) R)) *P63-PAVE*)
        names (vl-remove-if-not '(lambda (n) (pq:in-r (cadr n) R)) *P63-NAME*)
        names2 (vl-remove-if-not '(lambda (n) (pq:in-r (cadr n) R)) *P63-NAME2*))
  ;; 0-1) 캡 표시 : 끊겨 그려진 관 잇기, 캡 있는 끝을 관 끝으로 방향 정리
  (setq *PQ-SUB* "캡/관 잇기")
  (setq caps  (vl-remove-if-not '(lambda (c) (pq:bb-hit c R 5.0)) *P63-CAP*)
        lines (pq:p63-join lines mains caps))
  (setq lines (mapcar '(lambda (l / ca cb)
                         (setq ca (pq:cap-at (car (cadr l)) caps) cb (pq:cap-at (last (cadr l)) caps))
                         (cond ((and cb (not ca)) (setq capped (cons (car l) capped)) l)
                               ((and ca (not cb)) (setq capped (cons (car l) capped)) (list (car l) (reverse (cadr l))))
                               (T l)))
                      lines))
  ;; 관과 이어지지 않은 캡 표시 -> 다른 레이어로 그린 63mm 관일 수 있음
  (foreach c caps
    ;; 평면도 테두리에 걸려 잘린 것은 제외 (테두리에서 1m 안쪽만)
    (if (and (vl-every '(lambda (q) (pq:in-r q (list (+ (nth 0 R) 1.0) (+ (nth 1 R) 1.0) (- (nth 2 R) 1.0) (- (nth 3 R) 1.0)))) c)
             (not (vl-some '(lambda (ln) (or (<= (car (pq:pl-proj c (car ln))) *PQ-63-CAP-TOL*)
                                             (<= (car (pq:pl-proj c (last ln))) *PQ-63-CAP-TOL*)))
                           (append (mapcar 'cadr lines) *P63-HID*))))
      (pq:err fi nil nil nil
              (strcat "평면도 63mm 캡 표시 (" (pq:r2 (car (car c))) "," (pq:r2 (cadr (car c)))
                      ") 에 붙은 63mm 관이 없음 -> 다른 레이어로 그린 관인지 확인"))))
  (setq *PQ-SUB* "관로명 배정")
  ;; 0-2) 관로명 (Nm) 1:1 배정 - 오류 메시지에 평면도 길이를 함께 적기 위해 먼저 배정
  ;;    캡으로 방향이 정해진 관 : 관로명 문자는 관 끝 너머 관 방향으로 쓰임
  ;;      점수 = 관 끝 ~ 문자 축선 거리 + 0.1 x 축 방향 거리 + 0.5 x |관로명 길이 - 그린 길이|
  ;;    그 밖 : 문자~관 거리 + |관로명 길이 - 그린 길이| (+10)
  ;;    1차 : 63mm 관로명 레이어 / 2차 : 1차에서 짝을 못 찾은 관만 일반 관로명 레이어로
  (foreach nl (list names names2)
    (setq pairs nil)
    (foreach l lines
      (if (not (assoc (car l) asg))
        (progn
          (setq G (pq:pl-len (cadr l)) pts (cadr l) a (last pts) b (nth (- (length pts) 2) pts))
          (foreach nm nl
            (setq d (car (pq:pl-proj pts (cadr nm))))
            (setq pairs (cons (list (if (and (member (car l) capped) (pq:ang-par (angle b a) (nth 3 nm) *PQ-63-NAME-ANG*))
                                      (+ (pq:axis-perp a (cadr nm) (nth 3 nm))
                                         (* 0.1 (pq:axis-along a (cadr nm) (nth 3 nm)))
                                         (* 0.5 (abs (- (car nm) G))))
                                      (+ d (abs (- (car nm) G)) (if (member (car l) capped) 10.0 0.0)))
                                    d (car l) nm)
                              pairs))))))
    ;; vl-sort 는 같은 점수를 지우므로 vl-sort-i
    (setq pairs (mapcar '(lambda (i) (nth i pairs)) (vl-sort-i pairs '(lambda (a b) (< (car a) (car b))))))
    (foreach p pairs
      (if (and (<= (cadr p) *PQ-63-NAME-R*)
               (not (assoc (caddr p) asg))
               (not (member (caddr (cadddr p)) usedn)))
        (setq asg   (cons (cons (caddr p) (car (cadddr p))) asg)
              usedn (cons (caddr (cadddr p)) usedn)))))
  (setq G nil d nil)
  ;; 0-3) 주 평면도(가장 큰 L 사각형) 밖의 나뉜 평면도 : 관로명이 붙은 63mm 관만 집계
  ;;      (참고용으로 그린 다른 도면 구간의 63mm 가 섞이지 않게)
  (setq rr (pq:p63-main f))
  (if (not (equal rr R 1e-6))
    (foreach l lines
      (if (and (not (pq:any-in (cadr l) rr)) (not (assoc (car l) asg)))
        (progn
          (setq excl (cons (car l) excl))
          (pq:err fi nil nil nil
                  (strcat "평면도 63mm " (pq:p63-tag (car l) asg)
                          " 주 평면도 밖(나뉜 평면도)이고 관로명이 없음 -> 집계 제외 (확인)"))))))
  (setq lines (vl-remove-if '(lambda (l) (member (car l) excl)) lines))
  (setq *PQ-SUB* "출발점")
  ;; 1) 출발점 / 종류 (M 본관, C 다른 63mm 에 붙음, F 떨어짐)
  ;;    캡으로 방향이 정해진 관은 캡 반대쪽 끝이 출발점
  ;;    연결 판단은 *PQ-63-CONN-TOL*(0.1m) 이내, 본관은 신설관(히든 아님)만
  ;;    히든/기존관 본관에 붙은 관, 어디에도 연결되지 않은 관 -> 집계 제외 (그 관에 붙은 63mm 도 제외)
  (setq vmains (vl-remove-if-not '(lambda (m) (pq:bb-hit m R 5.0)) *P63-MAINV*))
  (foreach l lines
    (setq h (car l) pts (cadr l) a (car pts) b (last pts)
          dma (pq:min-dist a vmains)
          dmb (if (member h capped) 1.0e99 (pq:min-dist b vmains)))
    (if (<= (min dma dmb) *PQ-63-CONN-TOL*)
      (setq recs (cons (list h (if (< dmb dma) (reverse pts) pts) 'M nil) recs))
      (progn
        (setq others (vl-remove-if '(lambda (o) (= (car o) h)) lines)
              pa (pq:nearest-line a others)
              pb (if (member h capped) nil (pq:nearest-line b others)))
        (cond
          ((and pa (<= (car pa) *PQ-63-CONN-TOL*) (or (null pb) (<= (car pa) (car pb))))
           (setq recs (cons (list h pts 'C (cadr pa)) recs)))
          ((and pb (<= (car pb) *PQ-63-CONN-TOL*))
           (setq recs (cons (list h (reverse pts) 'C (cadr pb)) recs)))
          (T
           (setq xdist (min dma dmb (if pa (car pa) 1.0e99) (if pb (car pb) 1.0e99))
                 excl  (cons h excl))
           (pq:err fi nil nil nil
                   (strcat "평면도 63mm " (pq:p63-tag h asg)
                           (if (<= (min (pq:min-dist a mains) (if (member h capped) 1.0e99 (pq:min-dist b mains))) *PQ-63-TOL*)
                             " 히든/기존관 본관에 연결 -> 집계 제외"
                             (strcat " 신설관에 연결되어 있지 않음 (가장 가까운 신설관 "
                                     (if (< xdist 1.0e98) (strcat (pq:r2 xdist) "M") "없음") ") -> 집계 제외")))))))))
  ;; 다른 63mm 에 붙은 관은 그 관을 따라가 신설관 본관(M)에 닿아야 집계 (제외된 관에 붙었거나 63mm 끼리만 이어진 관은 제외)
  (setq reach (mapcar 'car (vl-remove-if-not '(lambda (rc) (eq (caddr rc) 'M)) recs)) prog T)
  (while prog
    (setq prog nil)
    (foreach rc recs
      (if (and (eq (caddr rc) 'C) (member (cadddr rc) reach) (not (member (car rc) reach)))
        (setq reach (cons (car rc) reach) prog T))))
  (foreach rc recs
    (if (and (eq (caddr rc) 'C) (not (member (car rc) reach)) (not (member (car rc) excl)))
      (progn
        (setq excl (cons (car rc) excl))
        (pq:err fi nil nil nil
                (strcat "평면도 63mm " (pq:p63-tag (car rc) asg)
                        (if (member (cadddr rc) excl) " 집계 제외된 관에 연결" " 63mm 끼리만 이어지고 신설관 본관에 연결되지 않음")
                        " -> 집계 제외")))))
  (setq recs  (vl-remove-if '(lambda (rc) (member (car rc) excl)) recs)
        lines (vl-remove-if '(lambda (l) (member (car l) excl)) lines)
        prog  nil)
  ;; 1-2) 종단 기준 : 종단 63mm 인출선과 평면도 63mm 짝짓기 (측점 + 길이)
  (if *PQ-63-PROFILE*
    (progn
      (setq *PQ-SUB* "종단 63mm 인출선")
      (setq pro63 (pq:p63-profile flines fsegs)
            *PQ-SUB* "평면도 측점/짝짓기")
      (setq pro63 pro63
            nos   (vl-remove-if-not '(lambda (n) (pq:in-r (cadr n) R)) *P63-NOS*))
      (foreach rc recs
        (if (and (eq (caddr rc) 'M) (setq c1 (pq:plan-chain (car (cadr rc)) mains nos)))
          (progn
            (setq chmap (cons (cons (car rc) c1) chmap))
            (setq best nil bd nil)
            (foreach pe pro63
              (if (not (member pe used2))
                (progn
                  ;; 점수 : 측점 차 + (길이가 다르면 3)
                  (setq d (+ (abs (- (car pe) c1))
                             (if (equal (cadr pe) (cdr (assoc (car rc) asg)) 0.05) 0.0 3.0)))
                  (if (and (<= (abs (- (car pe) c1)) *PQ-63-MATCH-TOL*) (or (null bd) (< d bd)))
                    (setq best pe bd d)))))
            (if best
              (setq pmatch (cons (cons (car rc) best) pmatch) used2 (cons best used2)
                    ;; 종단과 짝지어지면 종단 측점을 순서 기준으로
                    chmap (cons (cons (car rc) (car best)) chmap))))))
      ;; 다른 63mm 에 붙은 관은 부모 관의 측점
      (foreach rc recs
        (if (and (eq (caddr rc) 'C) (assoc (cadddr rc) chmap) (not (assoc (car rc) chmap)))
          (setq chmap (cons (cons (car rc) (cdr (assoc (cadddr rc) chmap))) chmap))))
      ;; 다른 63mm 에 붙은 관도 종단 인출선과 짝지음 (부모 측점 근처 + 길이 같음)
      ;;   포장은 평면도(부모 관의 붙은 위치 포장)를 따르고, 종단 인출선은 중복 집계되지 않게 사용 처리만 함
      (foreach rc recs
        (if (and (eq (caddr rc) 'C) (setq c1 (cdr (assoc (car rc) chmap)))
                 (cdr (assoc (car rc) asg)) (not (assoc (car rc) pmatch)))
          (progn
            (setq best nil bd nil)
            (foreach pe pro63
              (if (and (not (member pe used2))
                       (equal (cadr pe) (cdr (assoc (car rc) asg)) 0.05)
                       (<= (abs (- (car pe) c1)) *PQ-63-MATCH-TOL*)
                       (or (null bd) (< (abs (- (car pe) c1)) bd)))
                (setq best pe bd (abs (- (car pe) c1)))))
            (if best (setq used2 (cons best used2) cused (cons (car rc) cused))))))
      ;; 남은 종단 인출선 : 측점이 맞지 않아도(평면도 측점을 못 구했거나 차이가 큼)
      ;;   아직 종단과 짝이 없는 평면도 63mm 중 관로명 길이가 같은 관이 있으면 그 관과 짝지음
      ;;   (같은 관을 평면도 + 종단으로 두 번 집계하지 않도록) - 여러 개면 측점이 가까운 것
      (foreach pe pro63
        (if (not (member pe used2))
          (progn
            (setq best nil bd nil)
            (foreach rc recs
              (if (and (not (assoc (car rc) pmatch)) (not (member (car rc) cused))
                       (cdr (assoc (car rc) asg))
                       (equal (cadr pe) (cdr (assoc (car rc) asg)) 0.05))
                (progn
                  (setq d (if (setq c1 (cdr (assoc (car rc) chmap))) (abs (- (car pe) c1)) 1.0e9))
                  (if (or (null bd) (< d bd)) (setq best rc bd d)))))
            (if best
              (progn
                (setq used2 (cons pe used2))
                (if (eq (caddr best) 'C)
                  (setq cused (cons (car best) cused))
                  (setq pmatch (cons (cons (car best) pe) pmatch)))
                (pq:err fi nil nil nil
                        (strcat "종단 63mm [" (nth 3 pe) "] 측점 " (pq:r2 (car pe)) "M : 측점으로 짝을 못 찾아 길이가 같은 평면도 63mm "
                                (pq:p63-tag (car best) asg)
                                (if (< bd 1.0e8) (strcat " (측점 차 " (pq:r2 bd) "M)") " (평면도 측점 없음)")
                                " 와 짝지음 (확인)")))))))
      ;; 길이 대조 / 종단에만 있는 63mm
      (foreach pm pmatch
        (if (and (cdr (assoc (car pm) asg))
                 (not (equal (cdr (assoc (car pm) asg)) (nth 2 pm) 0.05)))
          (pq:err fi nil nil nil
                  (strcat "평면도 63mm " (pq:p63-tag (car pm) asg) " 길이가 종단 [" (nth 4 pm) "] 과 다름 -> 평면도 기준"))))
      (foreach pe pro63
        (if (not (member pe used2))
          (progn
            (pq:err fi nil nil nil
                    (strcat "종단 63mm [" (nth 3 pe) "] 측점 " (pq:r2 (car pe))
                            "M : 짝지을 평면도 63mm 관이 없음 -> 종단 포장 " (nth 2 pe) " 으로 " (pq:r2 (cadr pe)) "M 집계 (확인)"))
            (setq out (cons (list (strcat "종단:" (nth 3 pe)) (cadr pe) (nth 2 pe) (cadr pe) "종단만" "" (car pe)) out)))))))
  (setq *PQ-SUB* "포장 결정")
  ;; 2) 포장 결정 (본관에 붙은 관 먼저, 붙은 63mm 는 부모 관의 포장을 따름)
  ;;    종단과 짝지어진 관은 도로측(분기 시작) 포장을 종단 포장으로, 경계밖은 평면도로
  (setq prog T)
  (while prog
    (setq prog nil)
    (foreach rc recs
      (if (not (assoc (car rc) done))
        (cond
          ((member (caddr rc) '(M F))
           (setq done (cons (pq:p63-resolve rc
                              (if (setq pe (cdr (assoc (car rc) pmatch)))
                                ;; 종단 포장 (분기점이 포장 경계 위면 평면도 도로측 포장이 양쪽 중 하나일 때 그것)
                                (if (and (nth 5 pe)
                                         (member (car (setq rd (pq:p63-road (car (cadr rc)) mains labs segs)))
                                                 (nth 5 pe)))
                                  (list (car rd) "")
                                  (list (nth 2 pe) ""))
                                (pq:p63-road (car (cadr rc)) mains labs segs))
                              labs segs)
                            done)
                 prog T))
          ((setq pr (assoc (cadddr rc) done))
           (setq done (cons (pq:p63-resolve rc (pq:p63-pave-at pr (car (cadr rc))) labs segs) done)
                 prog T))))))
  (foreach rc recs
    (if (not (assoc (car rc) done))
      (setq done (cons (pq:p63-resolve rc (pq:p63-label-from (car (cadr rc)) labs segs) labs segs) done))))
  ;; 3) 확인선 (포장구분별 색 폴리선)
  (if *PQ-63-DRAW* (progn (setq *PQ-SUB* "확인선") (pq:p63-draw done fi)))
  (setq *PQ-SUB* "길이 배분")
  ;; 4) 길이 배분 - 관 1개에서 오류가 나도 그 관만 오류목록에 남기고 나머지는 계속 집계
  (foreach rc done
    (setq rr (vl-catch-all-apply 'pq:p63-alloc-one (list rc asg chmap fi)))   ; r 은 R(평면도)과 같은 이름이라 rr
    (if (vl-catch-all-error-p rr)
      (pq:err fi nil nil nil
              (strcat "평면도 63mm [" (vl-prin1-to-string (car rc)) " / 관로명 " (vl-prin1-to-string (cdr (assoc (car rc) asg)))
                      "] 길이 배분 오류 : " (vl-catch-all-error-message rr)
                      " / 조각 " (substr (vl-prin1-to-string (caddr rc)) 1 200) " (알려주세요)"))
      (setq out (append (reverse rr) out))))
  (reverse out))

;; 확인선 조각마다 반영된 연장 문자 : "2.9m"
;;   조각 몫 = 관로명 길이 N 을 조각 길이 비율로 (소수 첫째, 차이는 가장 긴 조각)
;;   *PQ-63-MIN-PAVE* 이하라 다른 포장에 합친 포장(mg 에 없는 포장)은 문자 없이, 그 길이는 합친 포장의 가장 긴 조각에 더함
(defun pq:p63-len-label (rc N G mg fi / pcs sh sum big bi i x pts pc mid a h q ang r keep moved tgt)
  (setq pcs (vl-remove-if-not '(lambda (pc) (> (- (cadr pc) (car pc)) 0.01)) (caddr rc))
        pts (cadr rc) h *PQ-63-DRAW-TXT* sum 0.0 i 0)
  (if (and pcs (> G 0.0))
    (progn
      ;; 조각 몫
      (foreach pc pcs
        (setq x (pq:r1 (* N (/ (- (cadr pc) (car pc)) G)))
              sh (append sh (list x)) sum (+ sum x))
        (if (or (null big) (> (- (cadr pc) (car pc)) big)) (setq big (- (cadr pc) (car pc)) bi i))
        (setq i (1+ i)))
      (setq sh (pq:set-nth sh bi (pq:r1 (+ (nth bi sh) (- N sum)))))
      ;; 합쳐진(작은) 포장 -> 합친 포장의 가장 긴 조각으로 옮김
      (setq keep (mapcar 'car mg) moved 0.0 i 0)
      (foreach pc pcs
        (if (not (member (nth 2 pc) keep))
          (setq moved (+ moved (nth i sh)) sh (pq:set-nth sh i 0.0)))
        (setq i (1+ i)))
      (if (> moved 0.0)
        (progn
          ;; 합친 포장 = mg 에서 가장 긴 것
          (setq tgt (car (car (vl-sort mg '(lambda (a b) (> (cadr a) (cadr b))))))
                big nil bi nil i 0)
          (foreach pc pcs
            (if (and (= (nth 2 pc) tgt) (or (null big) (> (- (cadr pc) (car pc)) big)))
              (setq big (- (cadr pc) (car pc)) bi i))
            (setq i (1+ i)))
          (if bi (setq sh (pq:set-nth sh bi (pq:r1 (+ (nth bi sh) moved)))))))
      ;; 문자 : 조각 가운데, 선 옆(선 방향으로 회전, 거꾸로 서지 않게)
      (setq i 0)
      (foreach pc pcs
        (if (> (nth i sh) 0.0)
          (progn
            (setq mid (pq:pl-at pts (* 0.5 (+ (car pc) (cadr pc))))
                  a   (pq:pl-at pts (max 0.0 (- (* 0.5 (+ (car pc) (cadr pc))) 0.2)))
                  q   (pq:pl-at pts (+ (* 0.5 (+ (car pc) (cadr pc))) 0.2))
                  ang (angle a q))
            (if (and (> ang (+ (* 0.5 pi) 0.35)) (< ang (+ (* 1.5 pi) 0.35))) (setq ang (- ang pi)))   ; 세로 선은 아래에서 위로 읽게
            (setq r (polar mid (+ ang (* 0.5 pi)) (* 0.4 h)))
            (if (entmake (list '(0 . "TEXT") (cons 8 *PQ-63-DRAW-LAYER*)
                               (cons 62 (pq:p63-color (pq:kmap fi (nth 2 pc))))
                               (list 10 (car r) (cadr r) 0.0) (list 11 (car r) (cadr r) 0.0)
                               (cons 40 h) (cons 50 ang) (cons 1 (strcat (rtos (nth i sh) 2 1) "m"))
                               '(72 . 1) '(73 . 1)))
              (setq *PQ-63-DRAWN* (cons (entlast) *PQ-63-DRAWN*)))))
        (setq i (1+ i))))))

;; 포장 이름 -> 확인선 색
(defun pq:p63-color (pave / n hit)
  (setq n (pq:norm (pq:str pave)))
  (foreach g *PQ-63-DRAW-COLORS*
    (if (and (null hit) (vl-some '(lambda (w) (vl-string-search (strcase w) n)) (cdr g))) (setq hit (car g))))
  (cond (hit) (7)))

;; 폴리선 pts 의 s0 ~ s1 구간 점 목록
(defun pq:pl-sub (pts s0 s1 / p0 acc a b L out)
  (setq p0 pts acc 0.0 out (list (pq:pl-at p0 s0)))
  (while (cadr pts)
    (setq a (car pts) b (cadr pts) L (distance a b) acc (+ acc L))
    (if (and (> acc (+ s0 1e-6)) (< acc (- s1 1e-6))) (setq out (cons (list (car b) (cadr b)) out)))
    (setq pts (cdr pts)))
  (reverse (cons (pq:pl-at p0 s1) out)))

;; 해결된 관들(done : (핸들 점목록 ((s0 s1 포장 위치 표시) ...))) -> 조각마다 색 폴리선
(defun pq:p63-draw (done fi / pts sub en)
  (pq:mklayer *PQ-63-DRAW-LAYER*)
  (foreach rc done
    (setq pts (cadr rc))
    (foreach pc (caddr rc)
      (if (> (- (cadr pc) (car pc)) 0.01)
        (progn
          (setq sub (pq:pl-sub pts (car pc) (cadr pc)))
          (if (and (cdr sub)
                   (entmake (append (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity") (cons 8 *PQ-63-DRAW-LAYER*)
                                          ;; 최종 집계 구분 색 (칼라아스콘은 선택에 따라 : MMA/A.S.P 로 정하면 A.S.P 색)
                                          (cons 62 (pq:p63-color (pq:kmap fi (nth 2 pc))))
                                          '(100 . "AcDbPolyline") (cons 90 (length sub)) '(70 . 0)
                                          (cons 43 *PQ-63-DRAW-W*))
                                    (mapcar '(lambda (q) (cons 10 (list (float (car q)) (float (cadr q))))) sub))))
            (setq *PQ-63-DRAWN* (cons (entlast) *PQ-63-DRAWN*)))))))
  (princ))

;; 리습이 그린 객체 맨 앞으로 : 칼라아스콘 경계(0칼라아스콘)를 먼저, 그 위에 63mm 포장 확인선(0포장63)
;;   (나중에 맨 앞으로 보낸 것이 가장 위)
(defun pq:p63-front (/ ss)
  (foreach lay (list *PQ-MMA-DRAW-LAYER* *PQ-63-DRAW-LAYER*)
    (if (and lay (setq ss (ssget "X" (list (cons 8 lay) '(410 . "Model")))))
      (progn (command "_.DRAWORDER" ss "" "_F")
             (while (> (getvar "CMDACTIVE") 0) (command ""))))))

;; 목록 창 (DCL) -> 고른 순번 / 취소하면 기본 순번 / 창을 못 띄우면 'cmd
(defun pq:pick-list (title msg items def / fn f id res sel)
  (setq fn (vl-filename-mktemp "pqpick" nil ".dcl"))
  (if (setq f (open fn "w"))
    (progn
      (write-line "pqpick : dialog {" f)
      (write-line (strcat "  label = \"" title "\";") f)
      (write-line (strcat "  : text { label = \"" msg "\"; }") f)
      (write-line "  : list_box { key = \"lst\"; width = 40; height = 6; allow_accept = true; }" f)
      (write-line "  ok_cancel;" f)
      (write-line "}" f)
      (close f)))
  (setq sel (itoa def))
  (cond
    ((or (null f) (< (setq id (load_dialog fn)) 0)) (setq res 'cmd))
    ((not (new_dialog "pqpick" id)) (unload_dialog id) (setq res 'cmd))
    (T
     (start_list "lst") (mapcar 'add_list items) (end_list)
     (set_tile "lst" sel)
     (action_tile "lst" "(setq sel $value)")
     (action_tile "accept" "(setq sel (get_tile \"lst\")) (done_dialog 1)")
     (action_tile "cancel" "(done_dialog 0)")
     (setq res (if (and (= (start_dialog) 1) sel (/= sel "")) (atoi sel) def))
     (unload_dialog id)))
  (if fn (vl-file-delete fn))
  res)

;; 관 1개 길이 배분 -> ((핸들 관로명길이 포장 길이 위치 표시 측점) ...)
(defun pq:p63-alloc-one (rc asg chmap fi / N G mg res)
  (setq N (cdr (assoc (car rc) asg)) G 0.0)
  (foreach pc (caddr rc) (setq G (+ G (- (cadr pc) (car pc)))))
  (if (null N)
    (progn
      (setq N (pq:r1 G))
      (pq:err fi nil nil nil
              (strcat "평면도 63mm " (pq:p63-tag (car rc) asg) " 관로명 길이 문자를 못 찾음 -> 그린 길이 " (pq:r2 N) "M 사용"))))
  (setq *PQ-MERGED* nil mg (pq:p63-merge (pq:p63-alloc N (caddr rc) G)))
  ;; 확인선 옆에 반영 연장 (확인선과 같은 색)
  (if (and *PQ-63-DRAW* *PQ-63-DRAW-TXT*) (pq:p63-len-label rc N G mg fi))
  ;; 병합 내역 기록 (도곽 핸들 관로명길이 병합포장 길이 합산포장)
  (foreach m (reverse *PQ-MERGED*)
    (setq *PQ-MERGE-NOTES* (cons (list fi (car rc) N (nth 0 m) (nth 1 m) (nth 2 m)) *PQ-MERGE-NOTES*)))
  (foreach x mg
    ;; x = (포장 길이 위치 표시)
    (cond
      ((= (nth 3 x) "가림")
       (pq:err fi nil nil nil
               (strcat "평면도 63mm " (pq:p63-tag (car rc) asg) " " (pq:str (nth 2 x)) " 조각 : 경계에 가리지 않는 포장 문자가 없어 가장 가까운 "
                       (pq:str (nth 0 x)) " 적용 (확인)")))
      ((= (nth 3 x) "포장문자없음")
       (pq:err fi nil nil nil (strcat "평면도 63mm " (pq:p63-tag (car rc) asg) " 평면도에 포장 문자가 없음"))))
    (setq res (cons (list (car rc) N (nth 0 x) (nth 1 x) (nth 2 x) (nth 3 x)
                          (cdr (assoc (car rc) chmap))
                          (car (car (cadr rc))))      ; 평면도 시작점 X (합산식 순서)
                    res)))
  (reverse res))

;;------------------------ 칼라아스콘 / 미끄럼방지 MMA ------------------------
;; *PQ-MMA* : ((도곽 "C"|"M"|"A") ...)  C 칼라아스콘, M MMA, A A.S.P   *PQ-MMA-ACC* : ((도곽 "미끄럼방지 MMA" 핸들 면적) ...)
(defun pq:kmap (fi kind)
  (if (and *PQ-MMA-ASK* fi kind (vl-string-search *PQ-MMA-WORD* (pq:norm kind)))
    (progn
      (if (not (assoc fi *PQ-MMA*)) (pq:mma-ask fi kind))
      ;; M (미끄럼방지 MMA) / A (A.S.P) -> 연장은 A.S.P 로
      (if (member (cadr (assoc fi *PQ-MMA*)) '("M" "A")) *PQ-MMA-TO* kind))
    kind))

;; 닫힌 객체 면적 (AREA 명령)
(defun pq:ent-area (en)
  (command "_.AREA" "_O" en)
  (getvar "AREA"))

;; 숫자 -> 짧은 문자 (30.00 -> "30", 1.50 -> "1.5")
;; ------------------------------------------------------------
;; 선택형 질문 (getkword) - CAD 런처로 실행했으면 런처가 버튼 창으로도 띄움
;;   런처가 %TEMP%\cad_launcher_ask.txt 를 보고 질문 창을 띄우고, 고른 키워드+Enter 를 보내 줌.
;;   캐드 명령줄에서 직접 답해도 되고, 답을 받으면(Esc 포함) 파일을 지워 런처 창도 닫힘.
;;   choices : ((키워드 버튼이름 한줄설명) ...)   helps : 자세한 설명 줄 목록
;; ------------------------------------------------------------
(defun pq:ask (id title kws def choices helps prompt / p f r c h)
  (if (and (boundp '*CADLAUNCHER-EXE*) *CADLAUNCHER-EXE* (getenv "TEMP"))
    (progn
      (setq p (strcat (getenv "TEMP") "\\cad_launcher_ask.txt"))
      (if (setq f (open p "w"))
        (progn
          (write-line (strcat "_ASK=" id) f)
          (write-line (strcat "TITLE=" title) f)
          (write-line (strcat "DEFAULT=" def) f)
          (foreach c choices
            (write-line (strcat "CHOICE=" (car c) "|" (cadr c) "|" (caddr c)) f))
          (foreach h helps (write-line (strcat "HELP=" h) f))
          (close f))
        (setq p nil))))
  (initget kws)
  (setq r (vl-catch-all-apply 'getkword (list prompt)))
  (if p (vl-file-delete p))
  (if (vl-catch-all-error-p r) (exit))   ; Esc -> 원래처럼 명령 중단
  r)

(defun pq:nz (x / s)
  (setq s (rtos x 2 2))
  (if (vl-string-search "." s)
    (progn
      (while (= (substr s (strlen s)) "0") (setq s (substr s 1 (1- (strlen s)))))
      (if (= (substr s (strlen s)) ".") (setq s (substr s 1 (1- (strlen s)))))))
  s)

;; 길쭉한 영역의 평균 폭 (면적 A, 둘레 P : 직사각형으로 보고 짧은 변)
(defun pq:strip-w (A P / d)
  (setq d (- (* P P) (* 16.0 A)))
  (if (>= d 0.0) (/ (- P (sqrt d)) 4.0) (sqrt A)))

;; 다각형 둘레 (닫아서)
(defun pq:poly-per (pts) (pq:pl-len (append pts (list (car pts)))))

;; 도면 평면도의 칼라아스콘 경계 -> ((ename 면적 평균폭) ...)
;;   1) 칼라아스콘 문자마다 : 문자를 품은 가장 작은 경계, 없으면 3m 안에서 가장 가까운 경계
;;   2) 같은 모양(면적 ±25%, 둘레 ±15%)이 가까이(3 x sqrt(면적) 이내) 이어지면 함께 묶음
;;      -> 칼라아스콘 문자가 대표로 2~3개만 있고 작은 경계(예 1 x 2.9m)가 여러 개인 경우
;;   경계 : *PQ-MMA-BND-LAYER* 의 폴리선. 열린 폴리선(ㄷ자)은 끝점을 이어 닫힌 것으로 봄
;;          (단 이어 닫는 변이 가장 긴 변보다 길면 제외 - 긴 도로경계선)
;; 칼라아스콘 문자 위치에서 BOUNDARY 로 영역 만들기 (경계 = *PQ-MMA-REGION-LAYER* 선 중 평면도 안)
;;   -> (엔티티 점목록 면적 둘레 중심) / nil.  만든 폴리선은 검토 표시 레이어(PAVQ_CHK)에 둠
(defun pq:mma-region (pt R / ss bset i en e0 e new best ba a pts)
  (setq bset (ssadd))
  (if (setq ss (ssget "X" (list '(0 . "LWPOLYLINE,LINE,POLYLINE,ARC") (cons 8 *PQ-MMA-REGION-LAYER*) '(410 . "Model"))))
    (repeat (setq i (sslength ss))
      (setq en (ssname ss (setq i (1- i))))
      (if (pq:bb-hit (pq:ent-pts (entget en)) R 1.0) (ssadd en bset))))
  (if (> (sslength bset) 0)
    (progn
      ;; BOUNDARY 는 화면에 보이는 곳만 되므로 평면도로 확대
      (command "_.ZOOM" "_W" (list (nth 0 R) (nth 1 R)) (list (nth 2 R) (nth 3 R)))
      (setq e0 (entlast))
      (command "_.-BOUNDARY" "_A" "_B" "_N" bset "" "" pt "")
      (while (> (getvar "CMDACTIVE") 0) (command ""))
      (setq e (if e0 (entnext e0) (entnext)))
      (while e (setq new (cons e new) e (entnext e)))
      (foreach x new
        (if (= (cdr (assoc 0 (entget x))) "LWPOLYLINE")
          (progn
            (setq a (pq:poly-area (mapcar 'pq:p2 (pq:lw-pts (entget x)))))
            (if (or (null ba) (> a ba)) (setq best x ba a)))))
      (foreach x new (if (not (eq x best)) (entdel x)))
      (cond
        ((null best) nil)
        ((or (> ba (* *PQ-MMA-REGION-MAX* (- (nth 2 R) (nth 0 R)) (- (nth 3 R) (nth 1 R))))
             (> ba *PQ-MMA-REGION-MAXA*)
             (pq:mma-other-pave (mapcar 'pq:p2 (pq:lw-pts (entget best)))))
         (entdel best) nil)
        (T
         (pq:mma-mklayer)
         (entmod (subst (cons 8 *PQ-MMA-DRAW-LAYER*) (assoc 8 (entget best)) (entget best)))
         (setq *PQ-MMA-TMP* (cons best *PQ-MMA-TMP*))
         (setq pts (mapcar 'pq:p2 (pq:lw-pts (entget best))))
         (list best pts ba (pq:poly-per pts)
               (list (/ (apply '+ (mapcar 'car pts)) (length pts)) (/ (apply '+ (mapcar 'cadr pts)) (length pts)))))))))

;; 칼라아스콘 경계 후보 : 1) 평면도 칼라아스콘 문자 기준 + 2) 신설관과 겹치는 ZC154 기준 (합침, 겹치는 것은 1번 우선)
(defun pq:mma-cands (fi / a b out pa)
  (setq *PQ-MMA-USEHID* nil)
  (if (pq:mma-no-main fi)
    (progn
      (setq *PQ-MMA-USEHID* T)
      (princ "\n  평면도에 실선 신설관(본관)이 없어 히든 신설관으로 칼라아스콘 통과 여부를 판단")
      (if (numberp *PQ-ECNT*)
        (pq:err fi nil nil nil "칼라아스콘 : 평면도에 실선 본관 신설관이 없어 히든 신설관으로 경계 통과 여부 판단 (확인)"))))
  (setq a (pq:mma-cands-lbl fi)
        b (if *PQ-MMA-ZC-LAYER* (pq:mma-zc fi)))
  ;; 우선순위 : 1) 도면의 닫힌 경계(문자 기준)  2) ZC154 로 만든 띠  3) BOUNDARY 로 만든 영역(가장 불확실)
  ;;   겹치면(가운데 점이 서로 안에 있음) 앞 순위를 남기고 뒤 순위는 버림
  (setq out nil)
  (foreach c (append (vl-remove-if '(lambda (c) (pq:mma-tmp-p (car c))) a)
                     b
                     (vl-remove-if-not '(lambda (c) (pq:mma-tmp-p (car c))) a))
    (setq pa (mapcar 'pq:p2 (pq:lw-pts (entget (car c)))))
    (if (or (assoc (car c) out)
            (vl-some '(lambda (o / po) (setq po (mapcar 'pq:p2 (pq:lw-pts (entget (car o)))))
                                     (or (pq:pt-in-poly (pq:inner-pt pa) po) (pq:pt-in-poly (pq:inner-pt po) pa)))
                     out))
      (if (and (not (assoc (car c) out)) (pq:mma-tmp-p (car c)))
        (entdel (car c)))
      (setq out (append out (list c)))))
  (setq *PQ-MMA-SEEDN* (length a))
  ;; 2차선 이상 도로 : 중앙선 기준 신설관 쪽만
  (setq out (pq:mma-lane-split fi out))
  (pq:mma-dup-filter fi out))

;;---- 2차선 이상 도로 : 중앙선 기준 신설관 쪽만 칼라아스콘 도형으로 ----
;; 차선 레이어(*PQ-MMA-LANE-LAYER*) 선 중 도형 안쪽 깊이(경계에서 *PQ-MMA-LANE-GAP* 이상) 길게 지나는 선 = 중앙선
;;   끊긴 중앙선은 *PQ-MMA-LANE-BRIDGE* 안이면 이어 보고, 끝이 경계에 못 닿으면 진행 방향으로 *PQ-MMA-LANE-EXT* 까지 가상선
;;   중앙선 2줄(*PQ-MMA-LANE-DBL* 안)은 가운데 가상 중심선 1줄로
;;   중앙선으로 도형을 둘로 나눠 신설관이 지나는 쪽만 남김 (양쪽 모두 *PQ-MMA-LANE-MINL* 이상 지나면 그대로)

;; 점 목록 pts 를 다각형 poly(열린 점목록) 경계에서 자른 안쪽 조각들 -> ((점목록 시작변 끝변) ...)  변 = 다각형 변 번호 / nil(안쪽에서 끝남)
;; pq:seg-x 와 같으나 p1-p2 끝점에서 만나는 것도 셈 (차선 꼭짓점이 경계선 위에 딱 있는 경우)
(defun pq:seg-x2 (p1 p2 q1 q2 / d1x d1y d2x d2y den tt uu)
  (setq d1x (- (car p2) (car p1)) d1y (- (cadr p2) (cadr p1))
        d2x (- (car q2) (car q1)) d2y (- (cadr q2) (cadr q1))
        den (- (* d1x d2y) (* d1y d2x)))
  (if (> (abs den) 1e-12)
    (progn
      (setq tt (/ (- (* (- (car q1) (car p1)) d2y) (* (- (cadr q1) (cadr p1)) d2x)) den)
            uu (/ (- (* (- (car q1) (car p1)) d1y) (* (- (cadr q1) (cadr p1)) d1x)) den))
      (if (and (>= tt -1e-9) (<= tt (+ 1.0 1e-9)) (>= uu -1e-9) (<= uu (+ 1.0 1e-9))) (max 0.0 (min 1.0 tt))))))

(defun pq:ln-clip (pts poly / n q ev acc a b L i tt s0 e0 out ins pieces ev2)
  (setq n (length poly) q (append poly (list (car poly))) acc 0.0)
  (setq a pts)
  (while (cadr a)
    (setq L (distance (car a) (cadr a)) i 0)
    (repeat n
      (if (setq tt (pq:seg-x2 (car a) (cadr a) (nth i q) (nth (1+ i) q)))
        (setq ev (cons (list (+ acc (* tt L)) i) ev)))
      (setq i (1+ i)))
    (setq acc (+ acc L) a (cdr a)))
  (setq ev (pq:isort ev '(lambda (x y) (< (car x) (car y)))))
  ;; 같은 곳(꼭짓점에서 두 번 셈)은 하나로
  (foreach e ev (if (or (null ev2) (> (- (car e) (car (car ev2))) 1e-6)) (setq ev2 (cons e ev2))))
  (setq ev (append (list (list 0.0 nil)) (reverse ev2) (list (list acc nil))))
  (while (cadr ev)
    (setq s0 (car (car ev)) b (cadr ev))
    (if (and (> (- (car b) s0) 0.05)
             (pq:pt-in-poly (pq:pl-at pts (* 0.5 (+ s0 (car b)))) poly))
      (setq pieces (cons (list (pq:pl-sub pts s0 (car b)) (cadr (car ev)) (cadr b)) pieces)))
    (setq ev (cdr ev)))
  (reverse pieces))

;; 점 p 에서 각 ang 방향으로 다각형 경계 첫 맞는 곳 (maxd 안) -> (점 변번호) / nil
(defun pq:ray-hit (p ang poly maxd / q n i tt best bt)
  (setq q (polar p ang maxd) n (length poly) i 0 poly (append poly (list (car poly))))
  (repeat n
    (if (and (setq tt (pq:seg-x p q (nth i poly) (nth (1+ i) poly))) (or (null bt) (< tt bt)))
      (setq bt tt best i))
    (setq i (1+ i)))
  (if bt (list (polar p ang (* bt maxd)) best)))

;; 조각 끝이 안쪽에서 끝나면 진행 방향으로 늘려 경계에 닿게 -> (점목록 시작변 끝변) / nil(못 닿음)
;; 점이 다각형 변 위(0.05m 안)면 그 변 번호 / nil
(defun pq:on-edge (p poly / q n i res)
  (setq q (append poly (list (car poly))) n (length poly) i 0)
  (repeat n
    (if (and (null res) (< (car (pq:pl-proj (list (nth i q) (nth (1+ i) q)) p)) 0.05)) (setq res i))
    (setq i (1+ i)))
  res)

(defun pq:ln-extend (pc poly / pts e0 e1 h)
  (setq pts (car pc) e0 (cadr pc) e1 (caddr pc))
  (if (null e0) (setq e0 (pq:on-edge (car pts) poly)))
  (if (null e1) (setq e1 (pq:on-edge (last pts) poly)))
  (if (null e0)
    (if (setq h (pq:ray-hit (car pts) (angle (cadr pts) (car pts)) poly *PQ-MMA-LANE-EXT*))
      (setq pts (cons (car h) pts) e0 (cadr h))))
  (if (null e1)
    (if (setq h (pq:ray-hit (last pts) (angle (nth (- (length pts) 2) pts) (last pts)) poly *PQ-MMA-LANE-EXT*))
      (setq pts (append pts (list (car h))) e1 (cadr h))))
  (if (and e0 e1 (cdr pts)) (list pts e0 e1)))

;; 조각의 안쪽 깊이 : 10~90% 9곳에서 경계까지 거리의 중앙값
(defun pq:ln-depth (pts polyc / L ds k)
  (setq L (pq:pl-len pts) k 1)
  (repeat 9
    (setq ds (cons (car (pq:pl-proj polyc (pq:pl-at pts (* L 0.1 k)))) ds) k (1+ k)))
  (nth 4 (pq:isort ds '<)))                       ; vl-sort 는 같은 값을 지우므로 쓰지 않음

;; 도로를 따라 곧게 가는 선인지 : 조각마다 방향이 처음~끝 방향과 *PQ-MMA-LANE-BEND* 도 안
;;   (교차로에서 꺾여 다른 도로로 들어가는 차선은 중앙선으로 안 씀)
(defun pq:ln-straight (pts / ch ok)
  (setq ch (angle (car pts) (last pts)) ok T)
  (foreach sg (pq:segs pts)
    (if (and ok (> (distance (car sg) (cadr sg)) 0.5)
             (not (pq:ang-par2 (angle (car sg) (cadr sg)) ch *PQ-MMA-LANE-BEND*)))
      (setq ok nil)))
  ok)

;; 도형 안 신설관이 중앙선과 나란히 가는지 : 도형 안 관 길이의 *PQ-MMA-LANE-PARR* 이상이 중앙선과 25도 안
;;   (교차로에서 관이 다른 도로 쪽으로 가로지르면 나누지 않음)
(defun pq:ln-par-pipe (cl poly kd / L Lc tot ok s q st a1 a2 d)
  (setq Lc (pq:pl-len cl) tot 0.0 ok 0.0)
  (foreach pp (if (eq kd 'P63) (vl-remove nil *PQ-MMA-P63*)
                (if *PQ-MMA-USEHID* (append *PQ-MMA-PIPES* *PQ-MMA-HIDP*) *PQ-MMA-PIPES*))
    (if (pq:bb-hit pp (pq:pts-bbox poly) 0.0)
      (progn
        (setq L (pq:pl-len pp) s 0.25)
        (while (< s L)
          (setq q (pq:pl-at pp s))
          (if (pq:pt-in-poly q poly)
            (progn
              (setq st (cadr (pq:pl-proj cl q))
                    a1 (angle (pq:pl-at pp (max 0.0 (- s 0.5))) (pq:pl-at pp (min L (+ s 0.5))))
                    a2 (angle (pq:pl-at cl (max 0.0 (- st 0.5))) (pq:pl-at cl (min Lc (+ st 0.5))))
                    tot (+ tot 0.5))
              (if (or (pq:ang-par2 a1 a2 25.0) (pq:ang-par2 a1 (+ a2 pi) 25.0)) (setq ok (+ ok 0.5)))))
          (setq s (+ s 0.5))))))
  (and (> tot 0.0) (>= (/ ok tot) *PQ-MMA-LANE-PARR*)))

;; 길게 끊긴 차선 잇기 : 끝 a 와 끝 b 가 *PQ-MMA-LANE-FAR* 안이고
;;   a 의 진행 방향 연장선에서 b 가 옆으로 *PQ-MMA-LANE-OFF* 안, b 의 방향도 같은 쪽(15도 안)이면 이음 (가까운 것부터)
(defun pq:lane-far-off (a ka b kb / pa pb da db d v)
  (setq pa (if (= ka 0) (car a) (last a)) pb (if (= kb 0) (car b) (last b))
        da (pq:end-dir a ka) db (+ (pq:end-dir b kb) pi) d (distance pa pb) v (angle pa pb))
  (cond
    ;; 맞닿은 끝 : 45도 안으로 이어지면
    ((<= d 0.05) (if (pq:ang-par2 da db 45.0) d))
    ;; 떨어진 끝 : 같은 선 위 (방향 15도, 옆 어긋남 *PQ-MMA-LANE-OFF* 안) - 짧은 틈(점선)·긴 틈(옆길 입구) 모두
    ((and (<= d *PQ-MMA-LANE-FAR*)
          (pq:ang-par2 da v 30.0) (pq:ang-par2 da db 15.0)
          (<= (abs (* d (sin (- v da)))) *PQ-MMA-LANE-OFF*)
          (<= (abs (* d (sin (- v db)))) *PQ-MMA-LANE-OFF*))
     d)))

(defun pq:lane-join-far (chains / go best bd d k a b)
  (setq go T)
  (while go
    (setq go nil best nil bd nil)
    (foreach a chains
      (foreach b chains
        (if (and (not (eq a b)) (cdr a) (cdr b))
          (foreach k '((0 0) (0 1) (1 0) (1 1))
            (if (and (setq d (pq:lane-far-off a (car k) b (cadr k))) (or (null bd) (< d bd)))
              (setq best (list a b k) bd d))))))
    (if best
      (setq a (car best) b (cadr best) k (caddr best)
            a (if (= (car k) 0) (reverse a) a)
            b (if (= (cadr k) 1) (reverse b) b)
            chains (cons (append a b) (vl-remove-if '(lambda (c) (or (eq c (car best)) (eq c (cadr best)))) chains))
            go T)))
  chains)

;; 2줄 중앙선 a b -> 가운데 가상선
(defun pq:ln-mid (a b / L n k p q out)
  (setq L (pq:pl-len a) n (max 2 (min 40 (fix (/ L 2.0)))) k 0)
  (repeat (1+ n)
    (setq p (pq:pl-at a (* L (/ (float k) n)))
          q (pq:pl-at b (cadr (pq:pl-proj b p)))
          out (cons (list (* 0.5 (+ (car p) (car q))) (* 0.5 (+ (cadr p) (cadr q)))) out)
          k (1+ k)))
  (reverse out))

;; 다각형 경계를 따라 (변 e0 의 점 p0) -> (변 e1 의 점 p1) 앞으로 가며 지나는 꼭짓점
(defun pq:poly-walk (poly e0 p0 e1 p1 / n k out)
  (setq n (length poly))
  (if (and (= e0 e1) (>= (distance (nth e0 poly) p1) (distance (nth e0 poly) p0)))
    nil
    (progn
      (setq k (rem (1+ e0) n))
      (setq out (list (nth k poly)))
      (while (/= k e1)
        (setq k (rem (1+ k) n) out (cons (nth k poly) out)))
      (reverse out))))

;; 신설관이 다각형 안을 지나는 길이 (본관, 본관이 없으면 63mm)
(defun pq:poly-pipe (poly kd / L)
  (setq L 0.0)
  (foreach pp (if (eq kd 'P63) (vl-remove nil *PQ-MMA-P63*)
                (if *PQ-MMA-USEHID* (append *PQ-MMA-PIPES* *PQ-MMA-HIDP*) *PQ-MMA-PIPES*))
    (setq L (+ L (pq:len-inside pp poly))))
  L)

;; 다각형을 중앙선 후보로 한 번 나눔 -> 신설관 쪽 점목록 / nil(안 나눔)
(defun pq:lane-cut1 (poly lanes kd / polyc pcs c lg ok best bs s1 s2 l1 l2 m cfl fl)
  (setq polyc (append poly (list (car poly)))
        lg (- (* 0.5 (pq:poly-per poly)) (pq:strip-w (pq:poly-area poly) (pq:poly-per poly))))
  ;; 안쪽 조각 -> 경계까지 늘림 -> 길고 안쪽 깊은 것만
  ;; lanes = ((점목록 . 중앙선레이어여부) ...)  조각 = (점목록 시작변 끝변 중앙선레이어여부)
  (foreach ln lanes
    (foreach pc (pq:ln-clip (car ln) poly)
      (if (and *PQ-MMA-DEBUG* (>= (pq:pl-len (car pc)) (max 5.0 (* *PQ-MMA-LANE-MINR* lg))))
        (princ (strcat "\n   [중앙선] 조각 " (pq:r2 (car (car (car pc)))) "," (pq:r2 (cadr (car (car pc))))
                       " 길이 " (pq:r2 (pq:pl-len (car pc))) "m" (if (pq:ln-extend pc poly) "" " : 경계까지 못 이음")
                       " (기준 " (pq:r2 (max 5.0 (* *PQ-MMA-LANE-MINR* lg))) "m)")))
      (if (and (setq c (pq:ln-extend pc poly))
               (>= (pq:pl-len (car c)) (max 5.0 (* *PQ-MMA-LANE-MINR* lg)))
               (or (pq:ln-straight (car c))
                   (progn (if *PQ-MMA-DEBUG*
                            (princ (strcat "\n   [중앙선] 선 " (pq:r2 (car (car (car c)))) "," (pq:r2 (cadr (car (car c))))
                                           " 길이 " (pq:r2 (pq:pl-len (car c))) "m -> 교차로 등에서 꺾이는 선이라 제외")))
                          nil)))
        (setq pcs (cons (append c (list (cdr ln))) pcs)))))
  ;; 2줄 중앙선 -> 가운데
  (foreach a pcs
    (foreach b pcs
      (if (and (not (eq a b)) (not (member a ok)) (not (member b ok))
               (< (car (pq:pl-proj (car b) (pq:pl-at (car a) (* 0.5 (pq:pl-len (car a)))))) *PQ-MMA-LANE-DBL*))
        (progn
          (setq ok (cons a (cons b ok)))
          (if (setq m (pq:ln-extend (list (pq:ln-mid (car a) (car b)) nil nil) poly))
            (setq pcs (cons (append m (list (or (nth 3 a) (nth 3 b)))) pcs)))))))
  (setq pcs (vl-remove-if '(lambda (c) (member c ok)) pcs))
  ;; 중앙선 레이어 선이 있으면 그중에서, 없으면 차선 중 가장 안쪽 깊은 선 = 중앙선
  (setq cfl (vl-some '(lambda (c) (and (nth 3 c) (>= (pq:ln-depth (car c) polyc) *PQ-MMA-CENTER-GAP*))) pcs))
  (foreach c pcs
    (setq m (pq:ln-depth (car c) polyc)
          fl (if (nth 3 c) *PQ-MMA-CENTER-GAP* *PQ-MMA-LANE-GAP*))
    (if *PQ-MMA-DEBUG*
      (princ (strcat "\n   [중앙선] " (if (nth 3 c) "중앙선 레이어" "차선 레이어") " 선 " (pq:r2 (car (car (car c)))) "," (pq:r2 (cadr (car (car c))))
                     " 길이 " (pq:r2 (pq:pl-len (car c))) "m, 경계에서 깊이 " (pq:r2 m) "m"
                     (cond ((< m fl) " -> 길가장자리로 보고 제외")
                           ((and cfl (not (nth 3 c))) " -> 중앙선 레이어 선이 있어 제외")
                           (T "")))))
    (if (and (>= m fl) (or (nth 3 c) (not cfl)) (or (null bs) (> m bs))) (setq best c bs m)))
  ;; 도형 안 신설관이 중앙선과 나란히 가야 나눔 (교차로 등 제외)
  (if (and best (not (pq:ln-par-pipe (car best) poly kd)))
    (progn
      (if *PQ-MMA-DEBUG* (princ "\n   [중앙선] 도형 안 신설관이 중앙선과 나란하지 않음 (교차로 등) -> 나누지 않음"))
      (setq best nil)))
  (if best
    (progn
      (setq s1 (append (car best) (pq:poly-walk poly (caddr best) (last (car best)) (cadr best) (car (car best))))
            s2 (append (reverse (car best)) (pq:poly-walk poly (cadr best) (car (car best)) (caddr best) (last (car best))))
            l1 (pq:poly-pipe s1 kd) l2 (pq:poly-pipe s2 kd))
      (cond
        ((or (< (length s1) 3) (< (length s2) 3)) nil)
        ((and (>= l1 *PQ-MMA-LANE-MINL*) (>= l2 *PQ-MMA-LANE-MINL*)) nil)   ; 양쪽 다 지나감 (횡단 등)
        ((> l1 l2) s1)
        (T s2)))))

;; 후보 목록 ((en 면적 폭 종류) ...) -> 중앙선이 있으면 신설관 쪽만 남긴 새 도형으로 바꿈
(defun pq:mma-lane-split (fi cands / f R lanes near poly np kd k res en ar old cl)
  (setq f (nth (1- fi) *PQ-FRAMES*) R (if f (pq:p63-rect f)))
  (if (and *PQ-MMA-LANE-LAYER* R cands)
    (progn
      (pq:mma-pipe-len nil) (pq:mma-p63-len nil)          ; 신설관 목록 준비
      (foreach ed (pq:collect-x "LWPOLYLINE,LINE" *PQ-MMA-LANE-LAYER*)
        (setq k (pq:ent-pts ed))
        (if (and (cdr k) (pq:bb-hit k R 0.0)
                 (not (and *PQ-MMA-LANE-EXCL* (wcmatch (strcase (cdr (assoc 8 ed))) (strcase *PQ-MMA-LANE-EXCL*)))))
          (setq lanes (cons (cons k (and *PQ-MMA-CENTER-LAYER*
                                         (wcmatch (strcase (cdr (assoc 8 ed))) (strcase *PQ-MMA-CENTER-LAYER*))))
                            lanes))))
      (foreach c cands
        (setq poly (pq:open-pts (car c)) kd (nth 3 c) old (cadr c) np nil)
        (setq near (vl-remove-if-not
                     '(lambda (ln) (pq:bb-hit (car ln) (pq:pts-bbox poly) (+ *PQ-MMA-LANE-FAR* *PQ-MMA-LANE-EXT*)))
                     lanes))
        (if *PQ-MMA-DEBUG*
          (princ (strcat "\n   [중앙선] 경계 " (pq:r2 old) " M2 : 근처 차선 " (itoa (length near)) "개")))
        (if near
          (progn
            (setq k old)
            ;; 끊긴 곳 잇기 (중앙선 레이어 선과 차선 레이어 선도 서로 이음) -> 중앙선 레이어 선이 들어간 줄은 중앙선 표시
            ;;   (옆길로 꺾여 나가는 차선과는 잇지 않도록 같은 선 위에 있는 끝끼리만)
            (setq cl (mapcar 'car (vl-remove-if-not 'cdr near))
                  near (pq:lane-join-far (mapcar 'car near))
                  near (mapcar '(lambda (ch) (cons ch (vl-some '(lambda (q) (member (car q) ch)) cl))) near))
            (setq np nil k 0)
            (while (and (< k 1) (setq poly (pq:lane-cut1 (cond (np) (poly)) near kd)))
              (setq np poly k (1+ k)))
            (setq poly np)))
        (if (and poly np)
          (progn
            (pq:mma-mklayer)
            (entmake (append (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity") (cons 8 *PQ-MMA-DRAW-LAYER*)
                                   '(100 . "AcDbPolyline") (cons 90 (length poly)) '(70 . 1))
                             (mapcar '(lambda (p) (list 10 (car p) (cadr p))) poly)))
            (setq en (entlast) ar (pq:ent-area en))
            (if (pq:mma-tmp-p (car c)) (entdel (car c)))
            (setq *PQ-MMA-TMP* (cons en *PQ-MMA-TMP*))
            (princ (strcat "\n  [MMA] 중앙선 기준 신설관 쪽만 : " (pq:r2 old) " -> " (pq:r2 ar) " M2"))
            (setq res (cons (list en ar (pq:strip-w ar (pq:poly-per poly)) kd) res)))
          (setq res (cons c res))))
      (reverse res))
    cands))

;;---- 다른 도면과 같은 모양 경계 : 뒷번호 도면에서 제외 ----
;; *PQ-MMA-DONE* = ((도곽 점목록 면적) ...) 앞 도면에서 MMA 면적으로 쓴 경계
(defun pq:open-pts (en / pts)
  (setq pts (mapcar 'pq:p2 (pq:lw-pts (entget en))))
  (if (and (cdr pts) (< (distance (car pts) (last pts)) 0.01)) (reverse (cdr (reverse pts))) pts))

;; 변 길이 / 꺾임각 목록 ((길이 . 꺾임각) ...)
(defun pq:poly-sig (pts / n i a b c out)
  (setq n (length pts) i 0)
  (repeat n
    (setq a (nth i pts) b (nth (rem (1+ i) n) pts) c (nth (rem (+ i 2) n) pts)
          out (cons (cons (distance a b) (pq:ang-diff (angle a b) (angle b c))) out)
          i (1+ i)))
  (reverse out))

;; 각도 차 (-pi ~ pi)
(defun pq:ang-diff (a1 a2 / d)
  (setq d (rem (- a2 a1) (* 2 pi)))
  (cond ((> d pi) (- d (* 2 pi))) ((< d (- pi)) (+ d (* 2 pi))) (T d)))

;; 두 도형이 옮기고 돌려 놓은 같은 모양이면 -> (회전각 이동x 이동y) / nil
;;   변 길이·꺾임각 순서가 같은 시작점을 찾음 (반대 방향으로 그린 것도)
(defun pq:mma-same (p1 a1 p2 a2 / n s1 s2 k i ok res q2 th c1 c2 r)
  (if (and (= (length p1) (length p2)) (> (length p1) 2)
           (equal a1 a2 (max 0.05 (* 0.01 a1))))
    (foreach q2 (list p2 (reverse p2))
      (if (null res)
        (progn
          (setq n (length p1) s1 (pq:poly-sig p1) s2 (pq:poly-sig q2) k 0)
          (while (and (null res) (< k n))
            (setq ok T i 0)
            (while (and ok (< i n))
              (if (or (> (abs (- (car (nth i s1)) (car (nth (rem (+ i k) n) s2)))) *PQ-MMA-SAME-TOL*)
                      (> (abs (- (cdr (nth i s1)) (cdr (nth (rem (+ i k) n) s2)))) 0.035))
                (setq ok nil))
              (setq i (1+ i)))
            (if ok
              (setq th (pq:ang-diff (angle (nth 0 p1) (nth 1 p1))
                                    (angle (nth k q2) (nth (rem (1+ k) n) q2)))
                    c1 (pq:cen p1) c2 (pq:cen q2)
                    r  (list (- (* (car c1) (cos th)) (* (cadr c1) (sin th)))
                             (+ (* (car c1) (sin th)) (* (cadr c1) (cos th))))
                    res (list th (- (car c2) (car r)) (- (cadr c2) (cadr r)))))
            (setq k (1+ k)))))))
  res)

;; 뚜렷한 모양 (꼭짓점 6개 이상 또는 20M2 이상) - 작은 사각형 반복은 이것만으로 같다고 보지 않음
(defun pq:mma-distinct (pts a) (or (>= (length pts) 6) (>= a 20.0)))

(defun pq:mma-dup-filter (fi cands / hits pts tt fj anchors out dup)
  (setq *PQ-MMA-DUPN* 0)
  ;; 1) 앞 도면 경계와 같은 모양 찾기 -> hits ((후보 앞도곽 이동량 뚜렷함) ...)
  (foreach c cands
    (setq pts (pq:open-pts (car c)))
    (foreach d *PQ-MMA-DONE*
      (if (and (< (car d) fi) (setq tt (pq:mma-same (cadr d) (caddr d) pts (cadr c))))
        (setq hits (cons (list c (car d) tt (pq:mma-distinct pts (cadr c))) hits)))))
  ;; 2) 뚜렷한 모양이 같은 도곽·같은 이동량을 뒷받침하면 그 이동량은 확실 (anchors)
  (foreach h hits (if (nth 3 h) (setq anchors (cons (list (nth 1 h) (nth 2 h)) anchors))))
  (foreach c cands
    (setq dup nil)
    (foreach h hits
      (if (and (null dup) (eq (car h) c)
               (vl-some '(lambda (an) (and (= (car an) (nth 1 h))
                                           (< (abs (pq:ang-diff (car (cadr an)) (car (nth 2 h)))) 0.02)
                                           (equal (cdr (cadr an)) (cdr (nth 2 h)) 0.5)))
                        anchors))
        (setq dup (nth 1 h))))
    (if dup
      (progn
        (setq *PQ-MMA-DUPN* (1+ *PQ-MMA-DUPN*))
        (princ (strcat "\n  [MMA] 도면 " (pq:lbl dup) " 과 같은 모양 경계 (" (pq:r2 (cadr c))
                       " M2) -> 앞 도면에서 집계, 이 도면에서는 제외"))
        (if (numberp *PQ-ECNT*)
          (pq:err fi nil nil nil (strcat "미끄럼방지 MMA 경계 " (pq:r2 (cadr c)) "M2 : 도면 " (pq:lbl dup)
                                         " 과 같은 모양 -> 뒷번호 도면이라 제외")))
        (if (pq:mma-tmp-p (car c)) (entdel (car c))))
      (setq out (cons c out))))
  (reverse out))

;; MMA 면적으로 쓴 경계 기록
;; 칼라아스콘 레이어 만들기
(defun pq:mma-mklayer ()
  (if (and *PQ-MMA-DRAW-LAYER* (not (tblsearch "LAYER" *PQ-MMA-DRAW-LAYER*)))
    (entmake (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord") '(100 . "AcDbLayerTableRecord")
                   (cons 2 *PQ-MMA-DRAW-LAYER*) '(70 . 0) '(62 . 3) '(6 . "Continuous")))))

;; 리습이 만든 경계(ZC154 이어 그린 도형, BOUNDARY 영역)인지 - 처음부터 0칼라아스콘 레이어에 그려 둠
(defun pq:mma-tmp-p (en) (and en (member en *PQ-MMA-TMP*)))

;; 칼라아스콘/MMA 경계를 *PQ-MMA-DRAW-LAYER* 에 닫힌 폴리선 + 문자로 그림 -> 새로 만든 객체 목록
;;   리습이 만든 경계는 이미 그 레이어에 있으므로 문자만 붙임 / 도면 객체(ZC154 등)는 복사해서 그림
;;   비슷한 크기(면적 ±25%) 경계가 *PQ-MMA-GROUP-N* 개 이상 반복되면 문자 하나로 합침 : "칼라#3~21 합계 55.51M2 (19개) / 관 18.28M"
;; LWPOLYLINE 전역폭 바꾸기 : 43 코드는 꼭짓점(10) 앞에 있어야 적용됨 (뒤에 붙이면 무시됨)
(defun pq:lw-width (en w / ed out done)
  (setq ed (entget en))
  (if (assoc 43 ed)
    (setq ed (subst (cons 43 w) (assoc 43 ed) ed))
    (progn
      (foreach g ed
        (if (and (not done) (= (car g) 10)) (setq out (cons (cons 43 w) out) done T))
        (setq out (cons g out)))
      (setq ed (reverse out))))
  (entmod ed)
  (entupd en))

(defun pq:mma-draw (fi ens kind / items pts cen made grp rest g a sa sl n0 c)
  (if *PQ-MMA-DRAW-LAYER*
    (progn
      (pq:mma-mklayer)
      ;; 1) 도형
      (foreach en ens
        (if (and en (entget en) (= (cdr (assoc 0 (entget en))) "LWPOLYLINE"))
          (progn
            (setq pts (pq:open-pts en))
            (if (not (= (strcase (cdr (assoc 8 (entget en)))) (strcase *PQ-MMA-DRAW-LAYER*)))
              (progn
                (entmake (append (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity") (cons 8 *PQ-MMA-DRAW-LAYER*)
                                       '(100 . "AcDbPolyline") (cons 90 (length pts)) '(70 . 1) (cons 43 *PQ-MMA-DRAW-W*))
                                 (mapcar '(lambda (p) (list 10 (car p) (cadr p))) pts)))
                (setq made (cons (entlast) made)))
              ;; 리습이 만든 도형(이미 이 레이어) : 굵게
              (if (pq:mma-tmp-p en) (pq:lw-width en *PQ-MMA-DRAW-W*)))
            (setq items (cons (list en (pq:ent-area en) (pq:inner-pt pts)
                                    (+ (pq:mma-pipe-len (list en)) (pq:mma-p63-len (list en))))
                              items)))))
      ;; 번호 순서 : 신설관 측점(NO.0 -> NO.n) 방향, 측점을 못 구하면 뒤로 (평면도 X 순)
      (setq items (mapcar '(lambda (it) (append it (list (pq:mma-sta (pq:open-pts (car it)) fi)))) (reverse items))
            items (pq:isort items '(lambda (a b)
                                     (cond ((and (nth 4 a) (nth 4 b)) (< (nth 4 a) (nth 4 b)))
                                           ((nth 4 a) T)
                                           ((nth 4 b) nil)
                                           (T (< (car (nth 2 a)) (car (nth 2 b))))))))
      ;; 2) 반복 묶음 : 면적이 서로 ±25% 안인 것끼리
      (while items
        (setq a (cadr (car items))
              grp (vl-remove-if-not '(lambda (x) (<= (abs (- (cadr x) a)) (* 0.25 a))) items)
              rest (vl-remove-if '(lambda (x) (member x grp)) items))
        (if (< (length grp) *PQ-MMA-GROUP-N*)
          (setq rest (append (cdr grp) rest) grp (list (car items))))
        (setq items rest
              n0 (1+ (cond (*PQ-MMA-NO*) (0)))
              *PQ-MMA-NO* (+ (cond (*PQ-MMA-NO*) (0)) (length grp))
              sa (apply '+ (mapcar 'cadr grp)) sl (apply '+ (mapcar 'cadddr grp))
              c  (pq:cen (mapcar 'caddr grp)))
        (entmake (list '(0 . "TEXT") (cons 8 *PQ-MMA-DRAW-LAYER*)
                       (list 10 (car c) (cadr c) 0.0) (cons 40 *PQ-MMA-DRAW-TXT*)
                       ;; 예) #1 76.30M2 / 12.66M   (묶음 #1~3 합계 15.00M2 (3개) / 6.00M)
                       ;;     구분을 고르면 뒤에 (칼라아스콘) / (MMA) 를 붙임 -> pq:mma-label-set
                       (cons 1 (strcat (if (> (length grp) 1)
                                         (strcat "#" (itoa n0) "~" (itoa *PQ-MMA-NO*)
                                                 " 합계 " (pq:r2 sa) "M2 (" (itoa (length grp)) "개) / " (pq:r2 sl) "M")
                                         (strcat "#" (itoa n0) " " (pq:r2 sa) "M2 / " (pq:r2 sl) "M"))
                                       (if (= kind "MMA") " (MMA)" "")))))
        (setq made (cons (entlast) made)))
      (if (and ens (not *PQ-MMA-QUIET*))
        (princ (strcat "\n  경계 " (itoa (length ens)) "곳을 " *PQ-MMA-DRAW-LAYER* " 레이어에 그림 (확인용)")))))
  made)

;; 칼라아스콘 경계의 신설관 측점 (번호 순서용) -> 측점(M) / nil
;;   경계 안을 지나는 본관 신설관 부분의 가운데 -> 평면도 NO 문자로 측점 보간 (pq:plan-chain)
(defun pq:mma-sta (pts fi / R nos mains best bd pp L q s0 s1 d mid)
  (setq R (pq:p63-rect (nth (1- fi) *PQ-FRAMES*))
        nos (if R (vl-remove-if-not '(lambda (n) (pq:in-r (cadr n) R)) *P63-NOS*))
        mains (if *PQ-MMA-USEHID* (append *PQ-MMA-PIPES* *PQ-MMA-HIDP*) *PQ-MMA-PIPES*)
        mains (if R (vl-remove-if-not '(lambda (m) (pq:bb-hit m R 0.0)) mains) mains))
  ;; 경계 안을 가장 길게 지나는 본관, 그 관에서 경계 안 부분의 가운데 점
  (foreach m mains
    (if (> (setq d (pq:len-inside m pts)) (cond (bd) (0.0))) (setq best m bd d)))
  ;; 본관이 안 지나가면(63mm 만 지나는 경계) 가장 가까운 본관에 수선
  (if (null best)
    (foreach m mains
      (if (or (null bd) (< (setq d (car (pq:pl-proj m (pq:inner-pt pts)))) bd)) (setq best m bd d))))
  (if (and best nos)
    (progn
      (setq L (pq:pl-len best) s0 nil s1 nil q 0.0)
      (while (<= q L)
        (if (pq:pt-in-poly (pq:pl-at best q) pts)
          (progn (if (null s0) (setq s0 q)) (setq s1 q)))
        (setq q (+ q 0.5)))
      (setq mid (pq:pl-at best (if s0 (* 0.5 (+ s0 s1)) (cadr (pq:pl-proj best (pq:inner-pt pts))))))
      (pq:plan-chain mid mains nos))))

;; 그려 둔 경계 문자 뒤에 고른 구분 붙이기 : "#1 76.30M2 / 12.66M" -> "#1 76.30M2 / 12.66M (칼라아스콘)"
(defun pq:mma-label-set (ens word / ed)
  (foreach en ens
    (if (and en (setq ed (entget en)) (= (cdr (assoc 0 ed)) "TEXT")
             (not (vl-string-search "(칼라아스콘)" (cdr (assoc 1 ed))))
             (not (vl-string-search "(MMA)" (cdr (assoc 1 ed)))))
      (progn
        (entmod (subst (cons 1 (strcat (cdr (assoc 1 ed)) " (" word ")")) (assoc 1 ed) ed))
        (entupd en)))))

(defun pq:mma-record (fi ens)
  (foreach en ens
    (if (and en (entget en) (= (cdr (assoc 0 (entget en))) "LWPOLYLINE"))
      (setq *PQ-MMA-DONE* (cons (list fi (pq:open-pts en) (pq:ent-area en)) *PQ-MMA-DONE*)))))

(defun pq:cen (pts)
  (list (/ (apply '+ (mapcar 'car pts)) (length pts)) (/ (apply '+ (mapcar 'cadr pts)) (length pts))))

;; ZC154 로 만든 도형이 다른 포장 구간인지 : 안에 다른 포장 문자가 있거나,
;;   가운데에서 경계에 가리지 않는 가장 가까운 포장 문자(*PQ-MMA-NEAR-R* 안)가 칼라아스콘이 아니면 T
(defun pq:mma-not-color (pts segs / c best bd d)
  (cond
    ;; 칼라아스콘 문자가 도형 안에 있거나 경계 1m 안이면 칼라아스콘 구간
    ((vl-some '(lambda (l) (and (vl-string-search *PQ-MMA-WORD* (pq:norm (car l)))
                                (or (pq:pt-in-poly (cadr l) pts)
                                    (<= (car (pq:pl-proj (append pts (list (car pts))) (cadr l))) 1.0))))
              *P63-PAVE*)
     nil)
    ((pq:mma-other-pave pts) T)
    (T
     ;; 도형 안쪽 점(가는 띠는 무게중심이 밖에 있을 수 있음)에서 가장 가까운 보이는 포장 문자
     (setq c (pq:inner-pt pts))
     (foreach l *P63-PAVE*
       (setq d (distance c (cadr l)))
       (if (and (<= d *PQ-MMA-NEAR-R*) (or (null bd) (< d bd)) (not (pq:cross-any c (cadr l) segs)))
         (setq best l bd d)))
     (and best (not (vl-string-search *PQ-MMA-WORD* (pq:norm (car best))))))))

;; 다각형 안쪽 점 : 무게중심이 안이면 그것, 아니면 무게중심 높이의 가로선이 다각형을 지나는 첫 구간 가운데
(defun pq:inner-pt (pts / c y xs q a b)
  (setq c (pq:cen pts))
  (if (pq:pt-in-poly c pts)
    c
    (progn
      (setq y (cadr c) q (append pts (list (car pts))))
      (while (cadr q)
        (setq a (car q) b (cadr q) q (cdr q))
        (if (and (/= (> (cadr a) y) (> (cadr b) y)))
          (setq xs (cons (+ (car a) (/ (* (- (car b) (car a)) (- y (cadr a))) (- (cadr b) (cadr a)))) xs))))
      (setq xs (vl-sort xs '<))
      (if (cadr xs) (list (/ (+ (car xs) (cadr xs)) 2.0) y) c))))

;; 영역 안에 칼라아스콘이 아닌 포장 문자(A.S.P, 비포장 ...)가 있으면 T -> 도로 전체를 잡은 것
(defun pq:mma-other-pave (pts)
  (vl-some '(lambda (l) (and (not (vl-string-search *PQ-MMA-WORD* (pq:norm (car l))))
                             (pq:pt-in-poly (cadr l) pts)))
           *P63-PAVE*))

;;---- 칼라아스콘 문자가 없을 때 : 신설관과 겹치는 ZC154 ----
;; 끝점의 바깥 방향 (k=0 시작점 / 1 끝점)
(defun pq:end-dir (c k)
  (if (= k 0) (angle (cadr c) (car c)) (angle (nth (- (length c) 2) c) (last c))))

;; 두 끝을 이어도 되는지 : 이어지는 방향이 a 의 진행 방향과 맞고 b 로 그대로 들어가야 함 (45도 이내)
;;   나란한 두 선의 끝끼리(옆으로 이어짐)는 안 이음
(defun pq:join-ok (a ka b kb / pa pb v)
  (setq pa (if (= ka 0) (car a) (last a)) pb (if (= kb 0) (car b) (last b)))
  (or (< (distance pa pb) 0.05)
      (and (pq:ang-par2 (pq:end-dir a ka) (setq v (angle pa pb)) 45.0)
           (pq:ang-par2 (+ (pq:end-dir b kb) pi) v 45.0))))

;; 두 방향(라디안)이 같은 쪽으로 tol(도) 이내
(defun pq:ang-par2 (a1 a2 tol / d)
  (setq d (abs (- (rem (+ (- a1 a2) (* 4 pi)) (* 2 pi)) 0.0)))
  (<= (min d (- (* 2 pi) d)) (* tol (/ pi 180.0))))

;; 끊긴 선 잇기 : 끝점끼리 *PQ-MMA-JOIN* 이내이고 진행 방향이 이어지면 한 선으로 (방향 맞춤)
(defun pq:chain-join (chains / go a b best bd d k out)
  (setq go T)
  (while go
    (setq go nil best nil bd nil)
    (foreach a chains
      (foreach b chains
        (if (not (eq a b))
          (foreach k '((0 0) (0 1) (1 0) (1 1))
            (setq d (distance (if (= (car k) 0) (car a) (last a)) (if (= (cadr k) 0) (car b) (last b))))
            (if (and (<= d *PQ-MMA-JOIN*) (or (null bd) (< d bd))
                     (pq:join-ok a (car k) b (cadr k)))
              (setq best (list a b k) bd d))))))
    (if best
      (progn
        (setq a (car best) b (cadr best) k (caddr best)
              a (if (= (car k) 0) (reverse a) a)          ; a 끝 -> 이음점
              b (if (= (cadr k) 1) (reverse b) b)         ; 이음점 -> b
              chains (cons (append a b) (vl-remove-if '(lambda (c) (or (eq c (car best)) (eq c (cadr best)))) chains))
              go T))))
  chains)

;; 두 선이 나란한지 : B 의 점들을 A 에 투영 -> (평균 간격) / nil
(defun pq:par-width (A B / LA L n i s q pr ws in)
  (setq LA (pq:pl-len A) L (pq:pl-len B) n (max 4 (min 60 (fix L))) i 0 in 0)
  (repeat (1+ n)
    (setq q  (pq:pl-at B (* L (/ (float i) n)))
          pr (pq:pl-proj A q) i (1+ i))
    (if (and (> (cadr pr) 0.05) (< (cadr pr) (- LA 0.05)))
      (setq in (1+ in) ws (cons (car pr) ws))))
  (if (and ws (>= in (* 0.5 (1+ n))))
    (if (and (<= (- (apply 'max ws) (apply 'min ws)) *PQ-MMA-PAR-TOL*)
             (>= (apply 'min ws) 0.3)
             (<= (apply 'max ws) *PQ-MMA-PAIR-W*))
      (/ (apply '+ ws) (length ws)))))

;; 진단 : 두 선 짝 판정 이유
(defun pq:mma-dbg-pair (A B / w poly Lp L63)
  (setq w (cond ((pq:par-width A B)) ((pq:par-width B A))))
  (princ (strcat "\n   [진단] 선 " (pq:r2 (car (car A))) "," (pq:r2 (cadr (car A))) " (" (pq:r2 (pq:pl-len A)) "m) - 선 "
                 (pq:r2 (car (car B))) "," (pq:r2 (cadr (car B))) " (" (pq:r2 (pq:pl-len B)) "m) : "))
  (if (null w)
    (princ "나란하지 않음")
    (progn
      (setq poly (append A (reverse (if (> (+ (distance (car A) (car B)) (distance (last A) (last B)))
                                           (+ (distance (car A) (last B)) (distance (last A) (car B))))
                                        (reverse B) B)))
            Lp 0.0 L63 0.0)
      (foreach pp (if *PQ-MMA-USEHID* (append *PQ-MMA-PIPES* *PQ-MMA-HIDP*) *PQ-MMA-PIPES*)
        (setq Lp (+ Lp (pq:len-inside pp poly))))
      (pq:mma-p63-len nil)
      (foreach pp *PQ-MMA-P63* (if pp (setq L63 (+ L63 (pq:len-inside pp poly)))))
      (princ (strcat "폭 " (pq:r2 w) "m, 안 신설관 " (pq:r2 Lp) "m / 63mm " (pq:r2 L63) "m"
                     (if (pq:mma-not-color poly (vl-remove-if-not '(lambda (sg) (pq:bb-hit sg (pq:pts-bbox poly) 20.0)) *P63-BND*))
                       ", 다른 포장 구간으로 판단(제외)" ""))))))

(defun pq:mma-zc (fi / f R ents opens closed chains used res A B w best bw poly en Lp L63 ar kd segs)
  (setq f (nth (1- fi) *PQ-FRAMES*) R (if f (pq:p63-rect f)))
  (if R (setq segs (vl-remove-if-not '(lambda (sg) (pq:bb-hit sg R 5.0)) *P63-BND*)))
  (pq:mma-pipe-len nil)                                   ; 신설관 목록 준비
  (if R
    (progn
      (foreach ed (pq:collect "LWPOLYLINE,LINE" *PQ-MMA-ZC-LAYER*)
        (setq ents (pq:ent-pts ed))
        (if (pq:bb-hit ents R 0.0)
          (if (and (= (cdr (assoc 0 ed)) "LWPOLYLINE") (= 1 (logand 1 (cond ((cdr (assoc 70 ed))) (0)))))
            (setq closed (cons (cdr (assoc -1 ed)) closed))
            (setq opens (cons ents opens)))))
      ;; 1) 닫힌 ZC154 중 신설관이 지나가는 것
      (foreach en closed
        (setq ar (pq:ent-area en))
        (if (and (setq kd (pq:mma-kind en))
                 (<= ar (* *PQ-MMA-REGION-MAX* (- (nth 2 R) (nth 0 R)) (- (nth 3 R) (nth 1 R))))
                 (not (pq:mma-not-color (mapcar 'pq:p2 (pq:lw-pts (entget en))) segs)))
          (setq res (cons (list en ar (pq:strip-w ar (pq:poly-per (mapcar 'pq:p2 (pq:lw-pts (entget en))))) (if (eq kd 'P63) 'P63)) res))))
      ;; 2) 열린 ZC154 : 끊긴 곳 잇고 -> 나란한 두 선 사이를 이어 도형으로
      (setq chains (pq:chain-join opens))
      (if *PQ-MMA-DEBUG*
        (princ (strcat "\n   [진단] 평면도 " (pq:r2 (nth 0 R)) "," (pq:r2 (nth 1 R)) " ~ " (pq:r2 (nth 2 R)) "," (pq:r2 (nth 3 R))
                       " / " *PQ-MMA-ZC-LAYER* " 열린 선 " (itoa (length opens)) "개 -> 이은 뒤 " (itoa (length chains))
                       "줄, 닫힌 도형 " (itoa (length closed)) "개 / 신설관 " (itoa (length *PQ-MMA-PIPES*)) "개")))
      (foreach A chains
        (if (not (member A used))
          (progn
            (setq best nil bw nil)
            (foreach B chains
              ;; 진단 : 가까운(*PQ-MMA-PAIR-W* 안) 두 선마다 판정 이유 출력
              (if (and *PQ-MMA-DEBUG* (not (eq A B))
                       (<= (car (pq:pl-proj B (pq:pl-at A (* 0.5 (pq:pl-len A))))) *PQ-MMA-PAIR-W*))
                (pq:mma-dbg-pair A B))
              (if (and (not (eq A B)) (not (member B used))
                       (setq w (cond ((pq:par-width A B)) ((pq:par-width B A))))
                       (or (null bw) (< w bw)))
                (progn
                  ;; 방향 맞춰 닫힌 도형 = A + 거꾸로 B
                  (setq poly (append A (reverse (if (> (+ (distance (car A) (car B)) (distance (last A) (last B)))
                                                       (+ (distance (car A) (last B)) (distance (last A) (car B))))
                                                    (reverse B) B))))
                  (setq Lp 0.0 L63 0.0)
                  (foreach pp (if *PQ-MMA-USEHID* (append *PQ-MMA-PIPES* *PQ-MMA-HIDP*) *PQ-MMA-PIPES*)
                    (setq Lp (+ Lp (pq:len-inside pp poly))))
                  (pq:mma-p63-len nil)
                  (foreach pp *PQ-MMA-P63* (if pp (setq L63 (+ L63 (pq:len-inside pp poly)))))
                  (if (and (or (> Lp 0.01) (> L63 0.01))
                           (not (pq:mma-not-color poly segs)))
                    (setq best (list B poly (if (<= Lp 0.01) 'P63)) bw w)))))
            (if best
              (progn
                (setq used (cons A (cons (car best) used)))
                (pq:mma-mklayer)
                (entmake (append (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity") (cons 8 *PQ-MMA-DRAW-LAYER*)
                                       '(100 . "AcDbPolyline") (cons 90 (length (cadr best))) '(70 . 1))
                                 (mapcar '(lambda (p) (list 10 (car p) (cadr p))) (cadr best))))
                (setq en (entlast) ar (pq:ent-area en)
                      *PQ-MMA-TMP* (cons en *PQ-MMA-TMP*)
                      res (cons (list en ar bw (caddr best)) res)))))))
      (if res
        (princ (strcat "\n  칼라아스콘 문자로 경계를 못 찾아(또는 문자 없음) 신설관과 겹치는 " *PQ-MMA-ZC-LAYER* " 기준으로 "
                       (itoa (length res)) "곳 찾음 (끊긴 선은 이어서 도형 작성, 초록색)")))
      (setq *PQ-MMA-SEEDN* (length res))))
  (reverse res))

(defun pq:mma-cands-lbl (fi / f R labs polys pts cl gap mx A P cen seeds sd ins nb d grow i m res rg kd)
  (setq f (nth (1- fi) *PQ-FRAMES*) R (if f (pq:p63-rect f)))
  (if R
    (progn
      (setq labs (vl-remove-if-not
                   '(lambda (l) (and (pq:in-r (cadr l) R) (vl-string-search *PQ-MMA-WORD* (pq:norm (car l)))))
                   *P63-PAVE*))
      (foreach ed (pq:collect "LWPOLYLINE" *PQ-MMA-BND-LAYER*)
        (setq pts (mapcar 'pq:p2 (pq:lw-pts ed))
              cl  (= 1 (logand 1 (cond ((cdr (assoc 70 ed))) (0)))))
        (if (and (cdr pts) (< (distance (car pts) (last pts)) 0.01))
          (setq pts (reverse (cdr (reverse pts))) cl T))
        (if (and (cddr pts) (pq:any-in pts R))
          (progn
            (setq gap (distance (car pts) (last pts)) mx 0.0)
            (foreach sg (pq:segs pts) (setq mx (max mx (distance (car sg) (cadr sg)))))
            (if (or cl (<= gap (+ mx 1e-6)))
              (progn
                (setq A (pq:poly-area pts) P (pq:poly-per pts)
                      cen (list (/ (apply '+ (mapcar 'car pts)) (length pts)) (/ (apply '+ (mapcar 'cadr pts)) (length pts))))
                (if (> A 1e-6)
                  (setq polys (cons (list (cdr (assoc -1 ed)) pts A P cen) polys))))))))
      ;; 1) 문자 기준 경계
      (foreach lb labs
        (setq ins nil nb nil sd nil)
        (foreach pl polys
          (if (pq:pt-in-poly (cadr lb) (cadr pl))
            (if (or (null ins) (< (nth 2 pl) (nth 2 ins))) (setq ins pl))
            (progn
              (setq d (car (pq:pl-proj (append (cadr pl) (list (car (cadr pl)))) (cadr lb))))
              (if (and (<= d 3.0) (or (null nb) (< d (car nb)))) (setq nb (list d pl))))))
        ;; 닫힌 폴리선 하나 안에 없으면 -> 도로경계 + 평면도 틀(L) + AE001 로 BOUNDARY 영역 (보도 칼라아스콘 등)
        (if (and (null ins) *PQ-MMA-REGION-LAYER*
                 (not (vl-some '(lambda (s0) (pq:pt-in-poly (cadr lb) (cadr s0))) seeds))
                 (setq rg (pq:mma-region (cadr lb) R)))
          (setq ins rg))
        (setq sd (cond (ins) (nb (cadr nb))))
        (if (and sd (not (member sd seeds))) (setq seeds (cons sd seeds))))
      ;; 2) 같은 모양으로 이어진 경계 묶기
      (setq grow seeds i 0)
      (while (< i (length grow))
        (setq m (nth i grow) i (1+ i))
        (foreach pl polys
          (if (and (not (member pl grow))
                   (<= 0.75 (/ (nth 2 pl) (nth 2 m)) 1.333)
                   (<= 0.85 (/ (nth 3 pl) (nth 3 m)) 1.18)
                   (<= (distance (nth 4 pl) (nth 4 m)) (* 3.0 (sqrt (nth 2 m)))))
            (setq grow (append grow (list pl))))))
      (setq *PQ-MMA-SEEDN* (length seeds))
      (foreach pl grow
        (setq A (pq:ent-area (car pl)))
        ;; 신설관이 지나가는 경계만 후보 (BOUNDARY 로 만든 것 중 신설관이 안 지나는 것은 지움)
        (if (setq kd (pq:mma-kind (car pl)))
          (setq res (cons (list (car pl) A (pq:strip-w (nth 2 pl) (nth 3 pl)) (if (eq kd 'P63) 'P63)) res))
          (if (pq:mma-tmp-p (car pl))
            (entdel (car pl)))))))
  (reverse res))

;; 관(폴리선)이 다각형 안을 지나는 길이
(defun pq:len-inside (pipe poly / q a b ts tt t0 L)
  (setq L 0.0 q (append poly (list (car poly))))
  (foreach sg (pq:segs pipe)
    (setq a (car sg) b (cadr sg) ts (list 0.0 1.0))
    (foreach e (pq:segs q)
      (if (setq tt (pq:seg-x a b (car e) (cadr e))) (setq ts (cons tt ts))))
    (setq ts (vl-sort ts '<) t0 (car ts))
    (foreach t1 (cdr ts)
      (if (pq:pt-in-poly (list (+ (car a) (* 0.5 (+ t0 t1) (- (car b) (car a))))
                               (+ (cadr a) (* 0.5 (+ t0 t1) (- (cadr b) (cadr a)))))
                         poly)
        (setq L (+ L (* (- t1 t0) (distance a b)))))
      (setq t0 t1)))
  L)

;; 선택한 MMA 경계들을 신설관(63mm 제외)이 지나는 길이 합 -> 종단 칼라아스콘 연장과 대조
;; 63mm 신설관(히든 제외)이 경계 안을 지나는 길이
(defun pq:mma-p63-len (ens / L pts)
  (if (null *PQ-MMA-P63*)
    (progn
      (setq *PQ-MMA-P63* (list nil))                    ; 비어 있어도 다시 모으지 않게 표시
      (foreach ed (pq:collect-x "LWPOLYLINE,LINE" *PQ-ACC-PIPE*)
        (if (and (not (pq:ltype-hidden ed)) (pq:is63 (pq:conn-info (cdr (assoc 8 ed)))))
          (setq *PQ-MMA-P63* (cons (pq:ent-pts ed) *PQ-MMA-P63*))))))
  (setq L 0.0)
  (foreach en ens
    (if (= (cdr (assoc 0 (entget en))) "LWPOLYLINE")
      (progn
        (setq pts (mapcar 'pq:p2 (pq:lw-pts (entget en))))
        (if (and (cdr pts) (< (distance (car pts) (last pts)) 0.01)) (setq pts (reverse (cdr (reverse pts)))))
        (if (cddr pts)
          (foreach pp *PQ-MMA-P63* (if pp (setq L (+ L (pq:len-inside pp pts)))))))))
  L)

;; 경계 판정 : 본관 신설관이 지나가면 'M, 63mm 신설관만 지나가면 'P63, 둘 다 없으면 nil
(defun pq:mma-kind (en)
  (cond ((> (pq:mma-pipe-len (list en)) 0.01) 'M)
        ((> (pq:mma-p63-len (list en)) 0.01) 'P63)))

(defun pq:mma-pipe-len (ens / L pts)
  (if (null *PQ-MMA-PIPES*)
    (progn
      (setq *PQ-MMA-HIDP* nil)
      (foreach ed (pq:collect-x "LWPOLYLINE,LINE" *PQ-ACC-PIPE*)
        (if (not (pq:is63 (pq:conn-info (cdr (assoc 8 ed)))))
          (if (pq:ltype-hidden ed)
            (setq *PQ-MMA-HIDP* (cons (pq:ent-pts ed) *PQ-MMA-HIDP*))
            (setq *PQ-MMA-PIPES* (cons (pq:ent-pts ed) *PQ-MMA-PIPES*)))))))
  (setq L 0.0)
  (foreach en ens
    (if (= (cdr (assoc 0 (entget en))) "LWPOLYLINE")
      (progn
        (setq pts (mapcar 'pq:p2 (pq:lw-pts (entget en))))
        (if (and (cdr pts) (< (distance (car pts) (last pts)) 0.01)) (setq pts (reverse (cdr (reverse pts)))))
        (if (cddr pts)
          (foreach pp (if *PQ-MMA-USEHID* (append *PQ-MMA-PIPES* *PQ-MMA-HIDP*) *PQ-MMA-PIPES*)
            (setq L (+ L (pq:len-inside pp pts))))))))
  L)

;; 도곽 평면도에 실선(히든 아님) 본관 신설관이 하나도 없으면 T
;;   -> 그 도면은 히든 신설관으로 칼라아스콘 통과 여부를 판단 (본관을 히든으로만 그린 도면)
(defun pq:mma-no-main (fi / f R)
  (pq:mma-pipe-len nil)
  (setq f (nth (1- fi) *PQ-FRAMES*) R (if f (pq:p63-rect f)))
  (and R (not (vl-some '(lambda (pp) (pq:bb-hit pp R 0.0)) *PQ-MMA-PIPES*))
       (vl-some '(lambda (pp) (pq:bb-hit pp R 0.0)) *PQ-MMA-HIDP*)))

;; 닫힌 객체면 T (폴리선은 닫힘 표시 또는 시작=끝)
(defun pq:closed-ent (en / ed typ pts)
  (setq ed (entget en) typ (cdr (assoc 0 ed)))
  (cond
    ((member typ '("CIRCLE" "ELLIPSE" "REGION")) T)
    ((= 1 (logand 1 (cond ((cdr (assoc 70 ed))) (0)))) T)
    ;; 열린 폴리선 : 시작=끝, 또는 ㄷ자(끝점을 잇는 변이 가장 긴 변 이하)
    ((= typ "LWPOLYLINE")
     (setq pts (mapcar 'pq:p2 (pq:lw-pts ed)))
     (and (cddr pts)
          (<= (distance (car pts) (last pts))
              (+ 1e-6 (apply 'max (mapcar '(lambda (sg) (distance (car sg) (cadr sg))) (pq:segs pts)))))))))

(defun pq:mma-ask (fi kind / f ans e1 areas olde tot cands w mode bb ss m i c63 k63 drawn)
  (setq f (nth (1- fi) *PQ-FRAMES*))
  (setq olde (getvar "CMDECHO")) (setvar "CMDECHO" 0)
  ;; 1) 칼라아스콘 문자를 품은 닫힌 도로경계 영역을 먼저 찾아 선택(강조) 상태로 보여 줌
  (setq cands (pq:mma-cands fi) tot 0.0 w nil)
  (princ (strcat "\n\n[PAVQ] 도면 " (pq:lbl fi) " 에 포장구분 [" kind "] 이 있습니다."))
  ;; 1-1) 63mm 신설관만 지나가는 칼라아스콘 구간 -> 사용자가 포함 여부 선택
  (setq c63 (vl-remove-if-not '(lambda (c) (eq (nth 3 c) 'P63)) cands)
        cands (vl-remove-if '(lambda (c) (eq (nth 3 c) 'P63)) cands))
  ;;   -> 묻지 않고 모두 포함 (엑셀 미끄럼방지 수식의 마지막 항목들로 넣어 필요 없으면 수식에서 지움)
  (if c63
    (progn
      (setq cands (append cands c63))
      (princ (strcat "\n  63mm 신설관만 지나가는 칼라아스콘 구간 " (itoa (length c63)) "곳도 포함 : 면적 "
                     (pq:r2 (apply '+ (mapcar 'cadr c63))) " M2 (엑셀 미끄럼방지 수식 끝 항목 -> 필요 없으면 지우세요)"))
      (if (numberp *PQ-ECNT*)
        (pq:err fi nil nil nil
                (strcat "미끄럼방지 MMA : 63mm 신설관만 지나가는 구간 " (itoa (length c63)) "곳 "
                        (pq:join (mapcar '(lambda (c) (pq:r2 (cadr c))) c63) "+")
                        "M2 포함 -> 엑셀 미끄럼방지 수식의 끝 항목 (필요 없으면 수식에서 지우세요)")))))
  (if cands
    (progn
      (setq bb nil ss (ssadd))
      (foreach c cands
        (ssadd (car c) ss)
        (setq tot (+ tot (cadr c))
              bb  (pq:pts-bbox (append (if bb (list (list (nth 0 bb) (nth 1 bb)) (list (nth 2 bb) (nth 3 bb))))
                                       (mapcar 'pq:p2 (pq:lw-pts (entget (car c)))))))
        (if (or (null w) (< (caddr c) w)) (setq w (caddr c))))
      ;; 영역 주변이 보이도록 여유를 두고 확대
      (setq m (max 10.0 (* 0.5 (max (- (nth 2 bb) (nth 0 bb)) (- (nth 3 bb) (nth 1 bb))))))
      (command "_.ZOOM" "_W" (list (- (nth 0 bb) m) (- (nth 1 bb) m)) (list (+ (nth 2 bb) m) (+ (nth 3 bb) m)))
      (sssetfirst nil ss)
      (foreach c cands (redraw (car c) 3))
      (princ (strcat "\n  칼라아스콘 경계 " (itoa (length cands)) "곳 선택 표시"
                     (if (> (length cands) *PQ-MMA-SEEDN*)
                       (strcat " (문자 근처 " (itoa *PQ-MMA-SEEDN*) "곳 + 같은 모양 " (itoa (- (length cands) *PQ-MMA-SEEDN*)) "곳)")
                       "")
                     " : 면적 " (pq:r2 tot) " M2, 경계 안 신설관 "
                     (pq:r2 (pq:mma-pipe-len (mapcar 'car cands))) "M"
                     (if (vl-some '(lambda (c) (eq (nth 3 c) 'P63)) cands)
                       (strcat " (+ 63mm " (pq:r2 (pq:mma-p63-len (mapcar 'car cands))) "M)") ""))))
    (progn
      (if f (command "_.ZOOM" "_W" (list (nth 0 f) (nth 1 f)) (list (nth 2 f) (nth 3 f))))
      (if (> *PQ-MMA-DUPN* 0)
        (princ (strcat "\n  칼라아스콘 경계 " (itoa *PQ-MMA-DUPN*) "곳은 모두 앞 도면과 같은 모양이라 이 도면에서는 제외 (면적은 앞 도면에서 집계)"))
        (princ "\n  칼라아스콘 경계를 자동으로 찾지 못했습니다.\n  (평면도 칼라아스콘 문자 둘레에 신설관이 지나가는 닫힌 영역이 없음 -> 평면도 확인)"))))
  ;; 1-2) 구분하기 전에 경계를 0칼라아스콘 레이어에 그려 확인할 수 있게 함 (A.S.P 로 정하면 지움)
  ;;   번호는 63mm 만 지나는 구간도 함께 신설관 측점 순으로
  (setq drawn (pq:mma-draw fi (mapcar 'car cands) "칼라"))
  ;; 1-3) 새로 그린 도형을 선택 상태(그립)로 + 강조해서 눈에 띄게
  (setq ss (ssadd))
  (foreach e drawn (if (and (entget e) (= (cdr (assoc 0 (entget e))) "LWPOLYLINE")) (ssadd e ss)))
  (foreach c cands (if (pq:mma-tmp-p (car c)) (ssadd (car c) ss)))
  (if (> (sslength ss) 0)
    (progn
      (sssetfirst nil ss)
      (setq i 0)
      (repeat (sslength ss) (redraw (ssname ss i) 3) (setq i (1+ i)))
      (princ (strcat "\n  >> " *PQ-MMA-DRAW-LAYER* " 레이어에 새로 그린 경계 " (itoa (sslength ss))
                     "개를 선택(굵게) 표시했습니다. 확인 후 답하세요."))))
  ;; 2) 보여 준 경계를 보고 칼라아스콘 / MMA 결정
  ;; 캐드 옵션 목록으로 선택 : 명령행의 [ ] 항목 클릭 / 동적 입력(커서 옆) 아래 화살표 목록 / C M A 입력
  ;;   [ ] 안 항목은 initget 키워드와 같은 순서로 대응, 기본(Enter) = 미끄럼방지 MMA
  (if (and (null cands) (> *PQ-MMA-DUPN* 0))
    ;; 경계가 모두 앞 도면과 중복 -> 앞 도면에서 이미 미끄럼방지 MMA 로 정했으므로 묻지 않고 그대로 따름
    ;;   (앞 도면 기록 *PQ-MMA-DONE* 은 MMA 로 정한 경계만 남김)
    (progn
      (setq ans "M")
      (princ "\n  -> 앞 도면에서 미끄럼방지 MMA 로 정한 경계와 같으므로 묻지 않고 MMA 로 처리 (연장은 A.S.P 칸, 면적은 앞 도면에서 집계)"))
    (progn
      (princ "\n  ---------------------------------------------------------------")
      (princ "\n   C : 칼라아스콘 그대로 집계 (칼라아스콘 칸에 연장)")
      (princ "\n   M : 미끄럼방지 MMA -> 연장은 A.S.P 칸으로, 면적은 미끄럼방지(MMA) 칸으로")
      (princ "\n   A : A.S.P 로만 집계 (면적 없음)")
      (princ "\n  ---------------------------------------------------------------")
      (setq ans (pq:ask "PAVQ_PAVE" "표시한 경계의 포장 종류" "Color Mma Asp" "Mma"
                  '(("Color" "칼라아스콘 (C)" "칼라아스콘 칸에 연장으로 그대로 집계")
                    ("Mma" "미끄럼방지 MMA (M)" "연장은 A.S.P 칸, 면적은 미끄럼방지(MMA) 칸으로 집계")
                    ("Asp" "A.S.P (A)" "A.S.P 로만 집계 (면적 없음, 경계는 지움)"))
                  '("도면에 굵게 선택 표시한 경계(새로 그린 칼라아스콘 영역)를"
                    "어떤 포장으로 집계할지 고릅니다. 캐드 화면에서 경계를 확인한 뒤 고르세요."
                    "고른 구분은 경계 문자 괄호에 표시됩니다.")
                  "\n  표시한 경계의 포장 [칼라아스콘(C)/미끄럼방지MMA(M)/ASP(A)] <미끄럼방지MMA>: "))
      (setq ans (cond ((= ans "Color") "C") ((= ans "Asp") "A") (T "M")))))
  ;; 고른 구분을 경계 문자 괄호에 표시 (A.S.P 는 경계를 지우므로 없음)
  (cond ((= ans "C") (pq:mma-label-set drawn "칼라아스콘"))
        ((= ans "M") (pq:mma-label-set drawn "MMA")))
  (sssetfirst nil nil)
  (foreach c cands (redraw (car c) 4))
  (if (= ans "M")
    (progn
      ;; 3) 경계를 찾았으면 묻지 않고 표시한 경계 면적 그대로 사용
      ;;    경계를 못 찾았으면 -> 도로경계 객체 직접 선택 또는 (연장 x 폭) 일괄
      (cond
        (cands
         (setq mode "A")
         (princ (strcat "\n  표시한 경계 " (itoa (length cands)) "곳 면적 " (pq:r2 tot) " M2 사용")))
        ;; 경계가 모두 앞 도면과 중복 -> 이 도면 면적 없음 (앞 도면에서 집계)
        ((> *PQ-MMA-DUPN* 0)
         (setq mode "D")
         (princ "\n  경계가 모두 앞 도면과 중복 -> 이 도면 MMA 면적은 0 (앞 도면에서 집계)"))
        (T
         (princ "\n  ---------------------------------------------------------------")
         (princ "\n   MMA 면적을 정하는 방법")
         (princ "\n   S : 평면도에서 MMA 영역의 닫힌 폴리선(도로경계 또는 직접 그린 칼라아스콘 도형)을")
         (princ "\n       클릭해 선택 -> 선택한 도형 면적의 합 (신설관이 지나는 도형만 인정)")
         (princ "\n   W : 도형 없이 계산 -> 면적 = 종단 칼라아스콘 연장 x 폭(다음에 입력)")
         (princ "\n  ---------------------------------------------------------------")
         (setq mode (if (= (pq:ask "PAVQ_MMA_AREA" "MMA 면적을 정하는 방법" "Select Width" "Select"
                             '(("Select" "도형선택 (S)" "MMA 영역의 닫힌 폴리선을 클릭 -> 선택한 도형 면적의 합 (신설관이 지나는 도형만 인정)")
                               ("Width" "연장 x 폭 (W)" "도형 없이 계산: 면적 = 종단 칼라아스콘 연장 x 폭 (다음에 폭 입력)"))
                             '("MMA 경계를 자동으로 찾지 못해 면적을 정하는 방법을 고릅니다."
                               "도형선택은 평면도에 도로경계나 직접 그린 칼라아스콘 도형이 있을 때 씁니다.")
                             "\n  MMA 면적 [도형선택(S)/연장x폭(W)] <도형선택>: ")
                           "Width") "W" "S"))))
      (cond
        ((= mode "A")
         (foreach c cands (setq areas (cons (list (cdr (assoc 5 (entget (car c)))) (cadr c) (car c)) areas))))
        ((= mode "W")
         (initget 6)
         (setq w (getreal (strcat "\n  폭(M) <" (pq:nz (if w (atof (rtos w 2 1)) *PQ-MMA-WIDTH*)) ">: ")))
         (if (null w)
           (setq w (if cands (atof (rtos (apply 'min (mapcar 'caddr cands)) 2 1)) *PQ-MMA-WIDTH*))))
        ((= mode "S")
         ;; 평면도의 닫힌 도로경계 객체를 한 번에 선택 (클릭 반복 없음)
         (princ "\n  MMA 영역 도형(닫힌 폴리선)을 클릭해 선택하세요 (여러 개 가능, Enter 로 끝).")
         (if (setq ss (ssget '((0 . "LWPOLYLINE,POLYLINE,CIRCLE,ELLIPSE,REGION"))))
           (progn
             (setq i 0)
             (repeat (sslength ss)
               (setq e1 (ssname ss i) i (1+ i))
               (cond
                 ((not (pq:closed-ent e1))
                  (princ (strcat "\n  [" (cdr (assoc 5 (entget e1))) "] 닫힌 객체가 아니라 제외")))
                 ((and (= (cdr (assoc 0 (entget e1))) "LWPOLYLINE")
                       (null (pq:mma-kind e1)))
                  (princ (strcat "\n  [" (cdr (assoc 5 (entget e1))) "] 안에 신설관이 지나가지 않아 제외")))
                 (T
                  (setq areas (cons (list (cdr (assoc 5 (entget e1))) (pq:ent-area e1) e1) areas)))))
             (if areas (princ (strcat "\n  선택 " (itoa (length areas)) "개 면적 합 "
                                      (pq:r2 (apply '+ (mapcar 'cadr areas))) " M2")))))))
      (pq:mma-record fi (mapcar 'caddr areas))
      ;; 직접 선택(S)한 도형은 여기서 그림 (자동 경계는 질문 전에 이미 그림)
      (if (= mode "S") (pq:mma-draw fi (vl-remove nil (mapcar 'caddr areas)) "MMA"))
      ;; 연장 x 폭(W) 이면 그려 둔 경계는 면적에 안 쓰므로 지움
      (if (= mode "W")
        (progn
          (foreach e drawn (if (entget e) (entdel e)))
          (foreach c cands (if (and (pq:mma-tmp-p (car c)) (entget (car c))) (entdel (car c))))))
      (setq tot 0.0)
      ;; 수식 더하기 순서 = 도면 왼쪽부터 (경계 객체의 가장 왼쪽 X 순)
      (setq areas (mapcar '(lambda (a) (append a (list (if (and (caddr a) (= (cdr (assoc 0 (entget (caddr a)))) "LWPOLYLINE"))
                                                          (apply 'min (mapcar 'car (pq:lw-pts (entget (caddr a)))))
                                                          0.0))))
                          areas)
            ;; 63mm 만 지나가는 구간은 수식 끝으로
            areas (mapcar '(lambda (a) (if (assoc (caddr a) c63) (list (nth 0 a) (nth 1 a) (nth 2 a) (+ (nth 3 a) 1.0e9)) a)) areas)
            areas (pq:isort areas '(lambda (a b) (< (nth 3 a) (nth 3 b)))))
      (foreach a areas
        (setq tot (+ tot (cadr a))
              *PQ-MMA-ACC* (cons (list fi "미끄럼방지 MMA" (car a) (cadr a)) *PQ-MMA-ACC*)))
      ;; (도곽 "M" 일괄폭 관통과길이) - 일괄이면 면적은 출력 때 (칼라아스콘 연장 합 x 폭)
      ;;   관통과길이 : 선택한 경계 안을 신설관이 지나는 길이 -> 출력 때 종단 칼라아스콘 연장과 대조
      (setq *PQ-MMA* (cons (list fi "M" (if (= mode "W") w)
                                 (if areas (pq:mma-pipe-len (vl-remove nil (mapcar 'caddr areas)))))
                           *PQ-MMA*))
      (if (and (/= mode "W") (/= mode "D") (null areas))
        (pq:err fi nil nil nil
                (strcat "[" kind "] -> 미끄럼방지 MMA 선택했으나 경계 면적 없음 (확인)"))))
    ;; C : 칼라아스콘 그대로 / A : A.S.P 로 집계 (면적 없음)
    (progn
      ;; A.S.P(A) 로 정하면 질문 전에 그린 경계를 지움 / 칼라아스콘(C) 은 그대로 둠
      (if (= ans "A")
        (progn
          (foreach e drawn (if (entget e) (entdel e)))
          (foreach c cands (if (and (pq:mma-tmp-p (car c)) (entget (car c))) (entdel (car c))))))
      (setq *PQ-MMA* (cons (list fi (if (= ans "A") "A" "C")) *PQ-MMA*))))
  (setvar "CMDECHO" olde)
  (princ))

;;--------------------------- 집계/출력 --------------------------------
;; tbl : ((키 관경정보 ((포장 . 길이) ...)) ...)
(defun pq:add (tbl key info kind L / hit kl kh)
  ;; 칼라아스콘 -> (도면별 선택) 미끄럼방지 MMA 면 A.S.P 로
  ;;   도면별 표(키 = (도곽 ...)) 다음에 합계 표(키 = 문자열)가 이어서 불리므로 마지막 도곽 번호를 씀
  (if (listp key) (setq *PQ-ADD-FI* (car key)))
  (if (and (listp key) (not (equal (pq:kmap *PQ-ADD-FI* kind) kind)))
    (setq *PQ-MMA-LEN* (if (assoc (car key) *PQ-MMA-LEN*)
                         (subst (cons (car key) (+ (cdr (assoc (car key) *PQ-MMA-LEN*)) L))
                                (assoc (car key) *PQ-MMA-LEN*) *PQ-MMA-LEN*)
                         (cons (cons (car key) L) *PQ-MMA-LEN*))))
  (setq kind (pq:kmap *PQ-ADD-FI* kind))
  ;; 도면별 표(키가 (도곽 관경키))에 더할 때는 요소 길이도 기록 -> 집계표 합산식 (=직관+직관+연결관)
  ;;   *PQ-PART-TAG* = (단계 값) : pq:tag< 참고 (평면도 왼쪽 -> 오른쪽, 연결관 마지막)
  (if (listp key)
    (setq *PQ-PCNT* (1+ (cond (*PQ-PCNT*) (0)))
          *PQ-PARTS* (cons (list (car key) (cadr key) kind L
                                 (append (cond (*PQ-PART-TAG*) ('(2 0.0))) (list *PQ-PCNT*)))
                           *PQ-PARTS*)))
  (if (setq hit (assoc key tbl))
    (progn
      (setq kl (caddr hit))
      (if (setq kh (assoc kind kl))
        (setq kl (subst (cons kind (+ (cdr kh) L)) kh kl))
        (setq kl (append kl (list (cons kind L)))))
      (subst (list key info kl) hit tbl))
    (append tbl (list (list key info (list (cons kind L)))))))

;; MP 먼저, 같은 압력은 큰 관경 먼저
(defun pq:pipe< (ia ib)
  (if (/= (car ia) (car ib))
    (> (car ia) (car ib))
    (> (cadr ia) (cadr ib))))

(defun pq:kinds (rows / ks out)
  (foreach r rows (if (not (member (nth 4 r) ks)) (setq ks (cons (nth 4 r) ks))))
  (foreach g *PQ-PAVE-ORDER* (if (member g ks) (setq out (cons g out))))
  (setq out (reverse out))
  (foreach k (reverse ks)
    (if (and (not (member k out)) (/= k "연결관")) (setq out (append out (list k)))))
  (if (member "연결관" ks) (setq out (append out (list "연결관"))))
  out)

;; 같은 도면 안에서 본관 먼저, 연결관은 뒤
(defun pq:row< (ka ia kb ib / ca cb)
  (setq ca (wcmatch ka "연결관*") cb (wcmatch kb "연결관*"))
  (cond ((and cb (not ca)) T)
        ((and ca (not cb)) nil)
        (T (pq:pipe< ia ib))))

(defun pq:info-cols (key info)
  (list key (nth 0 info) (itoa (nth 1 info)) (nth 2 info) (nth 3 info)))

;; 포장구분 -> 환산표 시트 이름
(defun pq:pave-group (kind pr / n hit)
  (setq n (pq:norm kind))
  (foreach g *PQ-PAVE-GROUP*
    (if (not hit)
      (foreach w (cdr g) (if (vl-string-search (pq:norm w) n) (setq hit (car g))))))
  (cond (hit) ((= pr "MP") "ASP-MP") (T "ASP-LP")))

;; 굴착폭(상단폭) -> 숫자 또는 nil
(defun pq:hold-p (kind / n hit)
  (setq n (pq:norm kind))
  (foreach w *PQ-WIDTH-HOLD* (if (vl-string-search (pq:norm w) n) (setq hit T)))
  hit)

(defun pq:width (info kind / nom tb)
  (if (and info (not (pq:hold-p kind)))
    (progn
      (setq nom (if (= (nth 2 info) "mm")
                  (cdr (assoc (nth 1 info) *PQ-NOM-MM*))
                  (nth 1 info))
            tb  (cdr (assoc (pq:pave-group kind (nth 0 info)) *PQ-WIDTH*)))
      (if nom (cdr (assoc nom tb))))))

;; 굴착폭을 못 찾은 조합 기록 (중복 없이)
(defun pq:width-miss (key kind / msg)
  (setq msg (if (pq:hold-p kind)
              (strcat "굴착폭 보류 : " kind " (" key ")")
              (strcat "굴착폭 없음 : " key " / " kind " -> 토량환산표 관경/시트 확인 (*PQ-NOM-MM*, *PQ-WIDTH*)")))
  (if (not (member msg *PQ-WMISS*)) (setq *PQ-WMISS* (cons msg *PQ-WMISS*))))

;; 집계표 머리줄 : 포장마다 (길이, 굴착폭) 2칸
(defun pq:pivot-head (kinds / out)
  (foreach k kinds (setq out (append out (list k (strcat k " 굴착폭(M)")))))
  out)

;; 숫자 -> 짧은 문자 (4.00 -> "4", 0.50 -> "0.5")
(defun pq:num-str (x / s)
  (setq s (rtos x 2 2))
  (if (vl-string-search "." s)
    (progn
      (while (= (substr s (strlen s)) "0") (setq s (substr s 1 (1- (strlen s)))))
      (if (= (substr s (strlen s)) ".") (setq s (substr s 1 (1- (strlen s)))))))
  s)

;; 요소 합산식 : 도면 fi, 관경 key, 포장 kind 의 요소 길이(종단 구간, 연결관, 63mm 관, 분기관)
;;   -> "=41+56+3" (요소 1개면 nil)
;;   순서 : 종단 구간(종단번호 순, 종단면도 왼쪽 -> 오른쪽) -> 평면도 63mm(측점 순, 왼쪽 -> 오른쪽)·분기관 -> 연결관
;; 합산식 / CSV 순서 : 평면도 왼쪽 -> 오른쪽
;;   순서표 = (단계 값 일련번호)
;;     단계 0 : 평면도 X 를 아는 요소 (종단 구간은 측점 -> 평면도 NO 문자로 X, 평면도 63mm·분기관은 시작점 X)
;;     단계 1 : 평면도 X 를 못 구한 종단 구간 (종단 순서)
;;     단계 2 : 위치 없는 요소 (자재내역으로 대신한 63mm 등)
;;     단계 3 : 연결관 (항상 마지막)
;;   새 요소를 추가할 때는 *PQ-PART-TAG* 에 (단계 값) 을 정해 두면 합산식/CSV 모두 이 순서를 따름
(defun pq:tag< (ta tb)
  (cond
    ((/= (car ta) (car tb)) (< (car ta) (car tb)))
    ((not (equal (cadr ta) (cadr tb) 1e-6)) (< (cadr ta) (cadr tb)))
    (T (< (caddr ta) (caddr tb)))))

(defun pq:part< (a b) (pq:tag< (nth 4 a) (nth 4 b)))

;; 구간 CSV 행 : 관경 큰 것 먼저, 같으면 순서표
(defun pq:row-tag< (a b / da db)
  (setq da (cond ((nth 1 (nth 3 a))) (0)) db (cond ((nth 1 (nth 3 b))) (0)))
  (if (/= da db)
    (> da db)
    (pq:tag< (cond ((nth 7 a)) ('(9 0.0 0))) (cond ((nth 7 b)) ('(9 0.0 0))))))

;; 평면도 63mm / 분기관 CSV 행 : 평면도 X 순 (X 없으면 뒤)
(defun pq:x< (xa xb) (< (cond (xa) (1.0e99)) (cond (xb) (1.0e99))))

;; 현재 순서표 + 일련번호 (구간 CSV 행에 붙임)
(defun pq:rtag ()
  (setq *PQ-RCNT* (1+ (cond (*PQ-RCNT*) (0))))
  (append (cond (*PQ-PART-TAG*) ('(2 0.0))) (list *PQ-RCNT*)))

;; 측점 -> 평면도 X (도곽 평면도 R 안의 NO 문자 두 개 사이 보간) / nil
(defun pq:sta-x (R st / nos a b best bd)
  (if (and R st)
    (progn
      (setq nos (pq:isort (vl-remove-if-not '(lambda (n) (pq:in-r (cadr n) R)) *P63-NOS*)
                          '(lambda (x y) (< (car x) (car y)))))
      ;; st 를 감싸는 이웃 NO 쌍 중 측점 차가 가장 작은 것
      (setq a nos)
      (while (cadr a)
        (if (and (< (car (car a)) (car (cadr a)))
                 (<= (car (car a)) st) (>= (car (cadr a)) st)
                 (or (null bd) (< (- (car (cadr a)) (car (car a))) bd)))
          (setq best (list (car a) (cadr a)) bd (- (car (cadr a)) (car (car a)))))
        (setq a (cdr a)))
      ;; 감싸는 쌍이 없으면 끝쪽 두 개로 연장
      (if (and (null best) (cdr nos))
        (setq best (if (< st (car (car nos)))
                     (list (car nos) (cadr nos))
                     (list (nth (- (length nos) 2) nos) (last nos)))))
      (if (and best (> (abs (- (car (cadr best)) (car (car best)))) 1e-6))
        (progn
          (setq a (car best) b (cadr best))
          (+ (car (cadr a)) (* (- st (car a)) (/ (- (car (cadr b)) (car (cadr a))) (- (car b) (car a))))))))))

;; 삽입 정렬 (같은 값이 사라지지 않도록 vl-sort 대신)
(defun pq:ins (x srt fn)
  (cond ((null srt) (list x))
        ((apply fn (list x (car srt))) (cons x srt))
        (T (cons (car srt) (pq:ins x (cdr srt) fn)))))

(defun pq:isort (lst fn / out)
  (foreach x lst (setq out (pq:ins x out fn)))
  out)

(defun pq:parts (fi key kind / lst)
  (foreach r *PQ-PARTS*
    (if (and (= (car r) fi) (= (cadr r) key) (= (caddr r) kind)
             (> (cadddr r) 0.005))
      (setq lst (cons r lst))))
  (setq lst (pq:isort lst 'pq:part<))
  (if (cdr lst) (strcat "=" (pq:join (mapcar '(lambda (r) (pq:num-str (cadddr r))) lst) "+"))))

(defun pq:pivot-line (head key info kl kinds / tot vals v w fx)
  (setq tot 0.0)
  (foreach k kinds
    (setq v (cdr (assoc k kl))
          w (if v (pq:width info k))
          ;; 도면 행은 요소 길이 합산식으로 (합계 행은 숫자)
          fx (if (and v *PQ-PIVOT-FI*) (pq:parts *PQ-PIVOT-FI* key k)))
    (if (and v (null w)) (pq:width-miss key k))
    (setq vals (append vals (list (cond (fx) (v (pq:r2 v)) (T ""))
                                  (if w (pq:r2 w) ""))))
    (if v (setq tot (+ tot v))))
  (pq:join (append head vals (list (pq:r2 tot))) ","))

;; 집계표 [검토 사항] 에서 뺄 안내성 메시지 (오류 txt 에는 그대로 남음)
(setq *PQ-CSV-SKIP* '("*연결관*관경 미상*" "*길이 없음 -> 아래 포장 문자 길이로 보완*"))

(defun pq:csv-skip (m / hit)
  (foreach p *PQ-CSV-SKIP* (if (wcmatch m p) (setq hit T)))
  hit)

;; CSV 한 칸 : 쉼표/따옴표가 있으면 "..." 로 감쌈
(defun pq:csv-cell (s / out i c)
  (if (or (vl-string-search "," s) (vl-string-search "\"" s))
    (progn
      (setq out "\"" i 1)
      (while (<= i (strlen s))
        (setq c (substr s i 1) out (strcat out (if (= c "\"") "\"\"" c)) i (1+ i)))
      (strcat out "\""))
    s))

(defun pq:write (fn lines / f)
  (if (setq f (open fn "w"))
    (progn (foreach l lines (write-line l f)) (close f) fn)))

;; 저장 : 원래 이름이 막혀 있으면(다른 프로그램이 잡고 있음) 시각을 붙인 이름으로 다시 저장
;;   -> 실제 저장한 파일 이름 / 실패하면 nil. 결과는 *PQ-SAVE-LOG* 에 기록
(defun pq:write-safe (fn lines / r alt)
  (cond
    ((setq r (pq:write fn lines)) r)
    ((setq r (pq:write (setq alt (strcat (vl-filename-directory fn) "\\" (vl-filename-base fn)
                                         "_" (pq:stamp) (vl-filename-extension fn)))
                       lines))
     (setq *PQ-SAVE-LOG* (cons (strcat (vl-filename-base fn) (vl-filename-extension fn)
                                       " 은(는) 다른 프로그램이 사용 중이라 " (vl-filename-base r) (vl-filename-extension r)
                                       " 로 저장")
                               *PQ-SAVE-LOG*))
     r)
    (T (setq *PQ-SAVE-LOG* (cons (strcat (vl-filename-base fn) (vl-filename-extension fn) " 저장 실패") *PQ-SAVE-LOG*))
       nil)))

;; 시각 문자열 HHMMSS
;; 경로 바이트 길이 (한글 등 2바이트)
(defun pq:blen (s)
  (apply '+ (mapcar '(lambda (c) (if (> c 127) 2 1)) (vl-string->list s))))

;; 경로가 한도를 넘지 않게 도면 이름(base) 줄이기 : 가장 긴 파일 "PAVQ_63mm_<base>_HHMMSS.csv" 기준
(defun pq:fit-base (dir base)
  (while (and (> (strlen base) 0)
              (> (pq:blen (strcat dir "PAVQ_63mm_" base "_000000.csv")) *PQ-PATH-MAX*))
    (setq base (substr base 1 (1- (strlen base)))))
  (vl-string-right-trim " .-_" base))

;; 로컬 저장 폴더 (없으면 만듦)
(defun pq:local-dir (/ d)
  (setq d *PQ-LOCAL-DIR*)
  (if (/= (substr d (strlen d)) "\\") (setq d (strcat d "\\")))
  (if (not (vl-file-directory-p d)) (vl-mkdir d))
  d)

(defun pq:stamp (/ d)
  (setq d (rtos (getvar "CDATE") 2 6))       ; YYYYMMDD.HHMMSS
  (substr d 10 6))

(defun pq:mklayer (nm)
  (if (not (tblsearch "LAYER" nm))
    (entmake (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord")
                   '(100 . "AcDbLayerTableRecord") (cons 2 nm)
                   '(70 . 0) '(62 . 1) '(6 . "Continuous")))))

(defun pq:mark (pt h lbl)
  (entmake (list '(0 . "CIRCLE") (cons 8 *PQ-CHK-LAYER*) '(62 . 1)
                 (list 10 (car pt) (cadr pt) 0.0) (cons 40 (* 6.0 h))))
  (entmake (list '(0 . "TEXT") (cons 8 *PQ-CHK-LAYER*) '(62 . 1)
                 (list 10 (+ (car pt) (* 6.5 h)) (+ (cadr pt) (* 5.0 h)) 0.0)
                 (cons 40 (* 1.5 h)) (cons 1 lbl))))

;;----------------------- 도면번호 (MP/LP 별도) ----------------------
;; *PQ-FMAP* : ((도곽순번 도면번호 정렬키) ...)
;; 관경 문자의 압력을 길이로 가중 -> 긴 쪽 압력으로 분류
;;   -> (압력 . 압력종류수) 또는 nil
(defun pq:frame-pr (items / acc hit pr L best bl)
  (foreach it items
    (if (eq (car it) 'P)
      (setq pr  (nth 0 (nth 6 it))
            L   (cond ((nth 5 it)) (1.0))
            acc (if (setq hit (assoc pr acc))
                  (subst (cons pr (+ (cdr hit) L)) hit acc)
                  (cons (cons pr L) acc)))))
  (foreach e acc (if (or (null bl) (> (cdr e) bl)) (setq best (car e) bl (cdr e))))
  (if best (cons best (length acc))))

;; 종단 밴드에 붙은 관경 문자만 사용 (평면도/인출선 관경 문자 제외)
;; 종단이 없는 도곽만 도곽 전체 관경 문자 사용
(defun pq:prof-pipes (profs items / ps)
  (foreach pf profs (setq ps (append (cadr pf) ps)))
  (if ps ps items))

(defun pq:pad3 (n / s)
  (setq s (itoa n))
  (cond ((< n 10) (strcat "00" s)) ((< n 100) (strcat "0" s)) (T s)))

;; 압력별 순번 부여  MP-001, MP-002 ... / LP-001 ...  (좌상단부터 순서 유지)
(defun pq:set-label (fi pr / hit n rank)
  (setq hit (assoc pr *PQ-PRCNT*)
        n   (if hit (1+ (cdr hit)) 1)
        *PQ-PRCNT* (if hit (subst (cons pr n) hit *PQ-PRCNT*) (cons (cons pr n) *PQ-PRCNT*))
        rank (cond ((= pr "MP") 0) ((= pr "LP") 1) ((= pr "미구분") 9) (T 2)))
  (setq *PQ-FMAP* (cons (list fi (strcat pr "-" (pq:pad3 n)) (+ (* rank 100000) n)) *PQ-FMAP*)))

(defun pq:lbl (fi) (cond ((null fi) "전체") ((cadr (assoc fi *PQ-FMAP*))) ((itoa fi))))
(defun pq:ord (fi) (cond ((caddr (assoc fi *PQ-FMAP*))) (fi)))

(defun pq:err (fi pn pt h msg)
  (setq *PQ-ECNT* (1+ *PQ-ECNT*))
  (if pt (pq:mark pt h (strcat "PAVQ#" (itoa *PQ-ECNT*))))
  (setq *PQ-ERRS*
    (cons (strcat "#" (itoa *PQ-ECNT*) "  도면 " (pq:lbl fi)
                  (if pn (strcat " / 종단 " (itoa pn)) "") " : " msg)
          *PQ-ERRS*)))

;; 함수 실행 중 오류가 나도 멈추지 않고 오류목록에 기록 -> 결과 또는 nil
(defun pq:try (f args fi pn what / r)
  (setq *PQ-SUB* nil)
  (setq r (vl-catch-all-apply f args))
  (if (vl-catch-all-error-p r)
    (progn
      (pq:err fi pn nil nil (strcat what " 처리 중 오류 : " (vl-catch-all-error-message r)
                                    (if *PQ-SUB* (strcat " [세부 : " (pq:str *PQ-SUB*) "]") "")
                                    " (알려주세요)"))
      nil)
    r))

(defun pq:center (lst)
  (list (/ (apply '+ (mapcar 'cadr lst)) (length lst))
        (/ (apply '+ (mapcar 'caddr lst)) (length lst))))

;;----------------------------- 메인 ----------------------------------
(defun c:PAVQ (/ *error* ss63 frames acc ppl pk matq matp agg mq ok fR pst pax px alllines flines fi fpr fm pn fitems profs paves pipes mpt mh calc
                 fk fp fsegs sg ck cv cl w r63 tb63 p63 pbr l4 f4 sub sub2 tot tot2 k rows tblF tblT kinds base dir l1 l2 l3 f1 f2 f3 nprof base0 ldir)
  (setq *PQ-MMA* nil *PQ-MMA-ACC* nil *PQ-ADD-FI* nil *PQ-MMA-LEN* nil *PQ-MMA-PIPES* nil *PQ-MMA-P63* nil *PQ-MMA-DONE* nil *PQ-MMA-USEHID* nil)
  (setq *PQ-BBCACHE* nil *PQ-SAVE-LOG* nil *PQ-CUR-F* nil *PQ-CUR-FI* nil *PQ-ERRS* nil *PQ-WMISS* nil *PQ-MERGE-NOTES* nil *PQ-PARTS* nil
        *PQ-PCNT* 0 *PQ-PART-TAG* nil *PQ-RCNT* 0 *PQ-ECNT* 0 fi 0 nprof 0
        *PQ-FMAP* nil *PQ-PRCNT* nil)
  (princ "\nPAVQ : 도곽 검색 중...")
  (defun *error* (msg)
    (princ (strcat "\n[PAVQ 중단] 단계 : " (pq:str *PQ-STAGE*) "\n 오류 : " (pq:str msg)))
    (princ "\n -> 위 두 줄을 그대로 알려주세요.")
    (princ))
  (setq *PQ-STAGE* "도곽 검색")
  (setq frames (pq:get-frames) *PQ-FRAMES* frames)
  (if (null frames)
    (princ "\n도곽(FORM 블럭 또는 직사각형)을 찾지 못했습니다.")
    (progn
      (pq:mklayer *PQ-CHK-LAYER*)
      (setq alllines (pq:all-text-lines)
            *PQ-MARKS* (append (pq:arrow-marks) (pq:insert-marks))
            *PQ-HLINES* (pq:hlines)
            *PQ-AXES*   (pq:axes)
            *PQ-ACHAIN* nil
            *PQ-LEADS*  (pq:leads))
      (if *PQ-63-PLAN* (progn (setq *PQ-STAGE* "평면도 63mm 수집") (pq:p63-prep)))
      ;; 63mm 포장 확인선 : 지난번 것 지우고 새로
      (if (and *PQ-63-DRAW* (setq ss63 (ssget "X" (list (cons 8 *PQ-63-DRAW-LAYER*)))))
        (command "_.ERASE" ss63 ""))
      ;; 칼라아스콘 경계 그림 : 지난번 것 지우고 새로
      (setq *PQ-MMA-NO* 0 *PQ-MMA-TMP* nil)
      (if (and *PQ-MMA-DRAW-LAYER* (setq ss63 (ssget "X" (list (cons 8 *PQ-MMA-DRAW-LAYER*)))))
        (command "_.ERASE" ss63 ""))
      (foreach f frames
        (setq fi     (1+ fi) pn 0
              *PQ-CUR-F* f *PQ-CUR-FI* fi)
        ;; 진행 표시 (멈춘 것인지 느린 것인지 구분용)
        (princ (strcat "\nPAVQ : 도곽 " (itoa fi) " / " (itoa (length frames)) " 계산 중..."))
        (setq fi fi
              *PQ-STAGE* (strcat "도곽 " (itoa fi) " 문자 해석")
              flines (vl-remove-if-not '(lambda (a) (pq:in-frame a f)) alllines)
              fitems (pq:dedup-items
                       (vl-remove nil
                         (mapcar 'pq:classify
                           (pq:merge-pipe-pave (pq:merge-split
                             (if *PQ-LAYERS*
                               (vl-remove-if-not
                                 '(lambda (a) (wcmatch (strcase (nth 4 a)) (strcase *PQ-LAYERS*)))
                                 flines)
                               flines))))))
              fitems (pq:fix-dia fitems flines fi)
              profs  (pq:profiles fitems)
              fpr    (pq:frame-pr (pq:prof-pipes profs fitems)))
        ;; 도면번호 : MP/LP 별도 순번
        (pq:set-label fi (if fpr (car fpr) "미구분"))
        (cond
          ((null fpr)
           (if profs (pq:err fi nil nil nil "관경 문자가 없어 MP/LP 구분 불가 -> 미구분 번호 부여")))
          ((> (cdr fpr) 1)
           (pq:err fi nil nil nil (strcat "MP/LP 관경이 함께 있음 -> 길이가 긴 " (car fpr) " 도면으로 분류"))))
        (setq fk nil fp nil fsegs nil ppl nil fR (pq:p63-rect f) *PQ-RIVER-X* nil)   ; 이 도면의 포장별 길이 / 관경 목록 / 관경 구간 (연결관 배정용)
        (setq *PQ-STAGE* (strcat "도곽 " (itoa fi) " 종단 계산"))
        (foreach pf profs
          (setq pn (1+ pn) nprof (1+ nprof)
                *PQ-STAGE* (strcat "도곽 " (itoa fi) " 종단 " (itoa pn) " 준비")
                paves (car pf) pipes (cadr pf)
                mpt (pq:try 'pq:center (list paves) fi pn "포장 위치")
                mh (if (car paves) (nth 3 (car paves)) 1.0))
          (foreach v (caddr pf)
            (pq:err fi pn nil mh
                    (strcat "같은 줄 문자 [" (pq:trim (nth 7 v)) "] 는 관경합을 넘어 포장에서 제외")))
          (setq *PQ-STAGE* (strcat "도곽 " (itoa fi) " 종단 " (itoa pn) " 길이 계산")
                calc (pq:try 'pq:calc-profile (list paves pipes) fi pn "관경x포장 길이 계산"))
          (setq *PQ-STAGE* (strcat "도곽 " (itoa fi) " 종단 " (itoa pn) " 관경 구간"))
          (setq sg nil)
          (if (and pipes paves)
            (if (setq sg (pq:try 'pq:segments (list pipes paves) fi pn "관경 구간(화살표)"))
              (setq fsegs (cons sg fsegs))))
          ;; 하천 하월구간 : 겹치는 포장 길이를 하천으로 옮김
          (if (and calc paves (= (car calc) "누적"))
            (if (setq rvr (pq:try 'pq:river-apply (list calc paves pipes sg flines) fi pn "하천 하월구간"))
              (progn
                (setq calc (car rvr))
                (if (cadr rvr) (pq:err fi pn nil mh (cadr rvr))))))
          (setq *PQ-STAGE* (strcat "도곽 " (itoa fi) " 종단 " (itoa pn) " 집계"))
          (foreach m (nth 4 calc) (pq:err fi pn nil mh m))
          (cond
            ((null calc) nil)
            ((= (car calc) "관경없음")
             (pq:err fi pn mpt mh "포장 문자는 있으나 위쪽 관경 문자를 찾지 못함"))
            ((/= (car calc) "누적")
             (pq:err fi pn mpt mh
                     (strcat (car calc) " - 관경합 " (pq:r2 (nth 1 calc))
                             "M / 포장합 " (pq:r2 (nth 2 calc)) "M"))))
          ;; 종단 시작 측점 (측점표 누가거리) -> 구간 가운데 측점 -> 평면도 X
          (setq pst (if (and paves (setq pax (pq:axis-at (cadr (car paves)) (caddr (car paves)))))
                      (cdr (car (pq:axis-chain pax flines)))))
          (foreach r (nth 3 calc)
            ;; r = (관경키 포장 관경정보 길이 구간시작)
            (setq px (if pst (pq:sta-x fR (+ pst (cond ((nth 4 r)) (0.0)) (* 0.5 (cadddr r))))))
            (setq *PQ-PART-TAG* (if px (list 0 px) (list 1 (+ (* pn 1.0e6) (cond ((nth 4 r)) (0.0))))))
            (setq rows (cons (list fi pn (car r) (caddr r) (cadr r) (cadddr r) (car calc) (pq:rtag)) rows)
                  tblF (pq:add tblF (list fi (car r)) (caddr r) (cadr r) (cadddr r))
                  tblT (pq:add tblT (car r) (caddr r) (cadr r) (cadddr r))
                  fk   (pq:kacc fk (cadr r) (cadddr r))
                  fp   (if (assoc (car r) fp) fp (cons (cons (car r) (caddr r)) fp)))
            ;; 종단(pn)별 관경 길이 -> 평면도 분기관이 종단에 이미 있는지 확인용
            (setq pk (assoc (list pn (car r)) ppl)
                  ppl (if pk
                        (subst (list (car pk) (cadr pk) (+ (caddr pk) (cadddr r))) pk ppl)
                        (cons (list (list pn (car r)) (caddr r) (cadddr r)) ppl)))))
        ;; 연결관 -> 같은 관경 행에 합산, 포장은 A.S.P > CON'C > 도면의 주 포장
        (setq *PQ-STAGE* (strcat "도곽 " (itoa fi) " 연결관"))
        (setq cl (pq:conn flines fi fp fsegs)
              *PQ-PART-TAG* (list 3 0.0))
        ;; 63mm 연결관 : 평면도에 선이 없고 자재내역에만 있으므로 "LP 63mm PE" 행에 직접 더함
        ;;   포장은 다른 연결관과 같은 규칙 (A.S.P > CON'C > 도면의 주 포장), MP 도면은 제외
        (if (and *PQ-63-CONN-ADD* (not (and fpr (member (car fpr) *PQ-63-SKIP-PR*))))
          (foreach c cl
            (if (pq:is63 (cadr c))
              (progn
                (setq cv (pq:conn-pave fk))
                (if (= cv "연결관")
                  (pq:err fi nil nil nil "연결관 63mm : 도면에 포장구분이 없어 '연결관' 열에 별도 합산"))
                (setq p63  (cons (list fi (strcat "연결관(" (cadddr c) ")") (caddr c) cv (caddr c) "연결관" "") p63)
                      rows (cons (list fi 0 "LP 63mm PE" *PQ-63-INFO* cv (caddr c)
                                       (strcat "연결관63(" (cadddr c) ")") (pq:rtag)) rows)
                      tblF (pq:add tblF (list fi "LP 63mm PE") *PQ-63-INFO* cv (caddr c))
                      tblT (pq:add tblT "LP 63mm PE" *PQ-63-INFO* cv (caddr c)))))))
        (foreach c (vl-remove-if '(lambda (c) (and *PQ-63-SEPARATE* (pq:is63 (cadr c)))) cl)
          ;; c = (키 정보 길이 산출방식 포장) - 포장은 종단 측점으로 찾은 것, 없으면 A.S.P > CON'C > 주 포장
          (setq ck (pq:conn-target c fp)
                cv (cond ((nth 4 c)) ((pq:conn-pave fk))))
          (if (= cv "연결관")
            (pq:err fi nil nil nil
                    (strcat (car c) " : 도면에 포장구분이 없어 '연결관' 열에 별도 합산")))
          (setq rows (cons (list fi 0 (car ck) (cdr ck) cv (caddr c)
                                 (strcat "연결관(" (cadddr c) ")") (pq:rtag)) rows)
                tblF (pq:add tblF (list fi (car ck)) (cdr ck) cv (caddr c))
                tblT (pq:add tblT (car ck) (cdr ck) cv (caddr c))))
        (setq *PQ-PART-TAG* (list 2 0.0))
        ;; 자재내역 63mm 연장 (포장 구분 없음)
        (setq *PQ-STAGE* (strcat "도곽 " (itoa fi) " 63mm"))
        (setq tb63 (pq:table-63 flines))
        (foreach t6 tb63
          (setq r63 (cons (cons fi t6) r63)))
        ;; 평면도 63mm 포장구분 -> 관경x포장 집계에 "LP 63mm PE" 로 합산
        ;; (MP 도면은 제외 : *PQ-63-SKIP-PR*)
        (if (and *PQ-63-PLAN* (not (and fpr (member (car fpr) *PQ-63-SKIP-PR*))))
          (progn
            (setq *PQ-STAGE* (strcat "도곽 " (itoa fi) " 평면도 63mm"))
            (foreach r (pq:try 'pq:p63-frame (list f fi flines fsegs) fi nil "평면도 63mm")
              ;; r = (핸들 관로명길이 포장 길이 위치 표시 측점 평면도X)
              ;;   순서 : 평면도 시작점 X (종단에만 있는 63mm 는 측점 -> 평면도 X)
              (setq px (cond ((nth 7 r)) ((pq:sta-x fR (nth 6 r))))
                    *PQ-PART-TAG* (if px (list 0 px) (list 2 0.0)))
              (setq p63  (cons (cons fi (list (nth 0 r) (nth 1 r) (nth 2 r) (nth 3 r) (nth 4 r) (nth 5 r) (nth 6 r) px)) p63)
                    rows (cons (list fi 0 "LP 63mm PE" *PQ-63-INFO* (nth 2 r) (nth 3 r)
                                     (strcat "평면도63(" (nth 4 r) ")") (pq:rtag)) rows)
                    tblF (pq:add tblF (list fi "LP 63mm PE") *PQ-63-INFO* (nth 2 r) (nth 3 r))
                    tblT (pq:add tblT "LP 63mm PE" *PQ-63-INFO* (nth 2 r) (nth 3 r))))))
        ;; 종단/평면도에서 63mm 를 하나도 찾지 못하면 자재내역 인입관/연결관 63mm 반영 (LP 도면)
        ;;   연결관은 *PQ-63-CONN-ADD* 로 이미 더했으면 인입관만
        (if (and *PQ-63-PLAN* tb63
                 (not (and fpr (member (car fpr) *PQ-63-SKIP-PR*))))
          (progn
            (setq k 0)
            (foreach r p63
              (if (and (= (car r) fi) (not (wcmatch (nth 1 r) "연결관(*,자재내역:*"))) (setq k (1+ k))))
            (if (= k 0)
              (foreach t6 tb63
                ;; t6 = (품명 규격 연장)
                (if (not (and *PQ-63-CONN-ADD* (vl-string-search "연결관" (pq:norm (car t6)))))
                  (progn
                    (setq cv (pq:conn-pave fk)
                          *PQ-PART-TAG* (list 2 0.0))
                    (pq:err fi nil nil nil
                            (strcat "63mm : 종단/평면도에서 63mm 연장을 찾지 못함 -> 자재내역 [" (car t6) " " (cadr t6) "] "
                                    (pq:r2 (caddr t6)) "M 를 " cv " 로 반영 (확인)"))
                    (setq p63  (cons (list fi (strcat "자재내역:" (car t6)) (caddr t6) cv (caddr t6) "자재내역" "") p63)
                          rows (cons (list fi 0 "LP 63mm PE" *PQ-63-INFO* cv (caddr t6) "자재내역63" (pq:rtag)) rows)
                          tblF (pq:add tblF (list fi "LP 63mm PE") *PQ-63-INFO* cv (caddr t6))
                          tblT (pq:add tblT "LP 63mm PE" *PQ-63-INFO* cv (caddr t6)))))))))
        ;; 평면도 분기관 (종단면도 없는 짧은 분기관)
        (if *PQ-BR-PLAN*
          (progn
            (setq *PQ-STAGE* (strcat "도곽 " (itoa fi) " 평면도 분기관")
                  *PQ-BR-PROF* ppl)
            (foreach r (pq:try 'pq:br-frame (list f fi) fi nil "평면도 분기관")
              ;; r = (핸들 관로명길이 포장 길이 위치 표시 관경정보 관로명 평면도X)
              (setq *PQ-PART-TAG* (if (nth 8 r) (list 0 (nth 8 r)) (list 2 0.0)))
              (setq ck (pq:pipe-key (nth 6 r))
                    pbr  (cons (cons fi r) pbr)
                    rows (cons (list fi 0 ck (nth 6 r) (nth 2 r) (nth 3 r)
                                     (strcat "평면도분기(" (nth 4 r) ")") (pq:rtag)) rows)
                    tblF (pq:add tblF (list fi ck) (nth 6 r) (nth 2 r) (nth 3 r))
                    tblT (pq:add tblT ck (nth 6 r) (nth 2 r) (nth 3 r))))))
        ;; 최종검수용 자재내역 관경별 수량
        (setq matq (cons (cons fi (pq:try 'pq:table-qty (list flines) fi nil "자재내역 관경별 수량")) matq)
              matp (cons (cons fi *PQ-TQ-PARTS*) matp)))
      ;; 리습이 그린 객체 맨 위로 (63mm 확인선이 칼라아스콘 경계보다 위)
      (pq:p63-front)
      (setq rows  (reverse rows)
            r63   (reverse r63)
            p63   (reverse p63)
            pbr   (reverse pbr)
            kinds (pq:kinds rows)
            base  (vl-filename-base (getvar "DWGNAME"))
            dir   (strcat (getvar "DWGPREFIX") "MATX\\"))
      (if (not (vl-file-directory-p dir)) (vl-mkdir dir))
      ;; 경로가 너무 길면 파일 이름의 도면 이름 부분을 줄임 (Windows 경로 260 바이트 제한)
      (setq base0 base base (pq:fit-base dir base))
      (if (/= base base0)
        (princ (strcat "\n[저장] 경로가 길어 파일 이름을 줄임 : PAVQ_*_" base)))
      (setq *PQ-STAGE* "CSV 출력")
      ;; 1) 구간 원자료
      (setq l1 (list "도면번호,종단번호,관경,압력,관경값,단위,재질,포장구분,길이(M),굴착폭(M),산출방식"))
      (setq *PQ-FMAP* (vl-sort *PQ-FMAP* '(lambda (a b) (< (caddr a) (caddr b)))))
      (foreach fm *PQ-FMAP*
        ;; 도면 안에서 관경 큰 것부터, 같은 관경은 평면도 왼쪽 -> 오른쪽 (합산식과 같은 순서)
        (foreach r (pq:isort (vl-remove-if-not '(lambda (r) (= (nth 0 r) (car fm))) rows) 'pq:row-tag<)
          (if (= (nth 0 r) (car fm))
            (setq l1 (cons (pq:join (append (list (cadr fm)
                                                  (if (= (nth 1 r) 0) "-" (itoa (nth 1 r))))
                                            (pq:info-cols (nth 2 r) (nth 3 r))
                                            (list (pq:kmap (nth 0 r) (nth 4 r)) (pq:r2 (nth 5 r))
                                                  (if (setq w (pq:width (nth 3 r) (pq:kmap (nth 0 r) (nth 4 r))))
                                                    (pq:r2 w)
                                                    (progn (pq:width-miss (nth 2 r) (pq:kmap (nth 0 r) (nth 4 r))) ""))
                                                  (nth 6 r)))
                                    ",")
                           l1)))))
      ;; 2) 집계표 (도면별 + 합계)
      (setq tblF (vl-sort tblF
                   '(lambda (a b)
                      (if (/= (car (car a)) (car (car b)))
                        (< (pq:ord (car (car a))) (pq:ord (car (car b))))
                        (pq:row< (cadr (car a)) (cadr a) (cadr (car b)) (cadr b)))))
            tblT (vl-sort tblT '(lambda (a b) (pq:row< (car a) (cadr a) (car b) (cadr b)))))
      (setq l2 (list (pq:join (append (list "도면번호" "관경" "압력" "관경값" "단위" "재질")
                                      (pq:pivot-head kinds) (list "계")) ",")))
      (foreach e tblF
        (setq *PQ-PIVOT-FI* (car (car e)))
        (setq l2 (cons (pq:pivot-line (append (list (pq:lbl (car (car e))))
                                              (pq:info-cols (cadr (car e)) (cadr e)))
                                      (cadr (car e)) (cadr e) (caddr e) kinds)
                       l2)))
      (setq l2 (cons "" l2))
      (foreach e tblT
        (setq *PQ-PIVOT-FI* nil)
        (setq l2 (cons (pq:pivot-line (append (list "합계") (pq:info-cols (car e) (cadr e)))
                                      (car e) (cadr e) (caddr e) kinds)
                       l2)))
      ;; 4) 63mm : 자재내역 연장 / 평면도 포장구분 / 도면별 대조
      (setq l4 (list "도면번호,품명,규격,연장(M)" "[자재내역 63mm 인입관/연결관]"))
      (foreach fm *PQ-FMAP*
        (foreach r r63
          (if (= (car r) (car fm))
            (setq l4 (cons (pq:join (list (cadr fm) (nth 1 r) (nth 2 r) (pq:r2 (nth 3 r))) ",") l4)))))
      (setq l4 (cons "도면번호,핸들,관로명길이(M),포장구분,길이(M),위치,굴착폭(M),비고"
                     (cons "[평면도 63mm 포장구분]" (cons "" l4))))
      (foreach fm *PQ-FMAP*
        (foreach r (pq:isort (vl-remove-if-not '(lambda (r) (= (car r) (car fm))) p63)
                             '(lambda (a b) (pq:x< (nth 8 a) (nth 8 b))))
          (if (= (car r) (car fm))
            (setq l4 (cons (pq:join (list (cadr fm) (nth 1 r) (pq:r2 (nth 2 r)) (nth 3 r) (pq:r2 (nth 4 r))
                                          (nth 5 r)
                                          (if (setq w (pq:width *PQ-63-INFO* (nth 3 r))) (pq:r2 w) "")
                                          (nth 6 r))
                                    ",")
                           l4)))))
      (setq l4 (cons "도면번호,핸들,관로명,관로명길이(M),포장구분,길이(M),위치,굴착폭(M),비고"
                     (cons "[평면도 분기관 포장구분 (종단면도 없음)]" (cons "" l4))))
      (foreach fm *PQ-FMAP*
        (foreach r (pq:isort (vl-remove-if-not '(lambda (r) (= (car r) (car fm))) pbr)
                             '(lambda (a b) (pq:x< (nth 9 a) (nth 9 b))))
          (if (= (car r) (car fm))
            (setq l4 (cons (pq:join (list (cadr fm) (nth 1 r) (pq:csv-cell (nth 8 r)) (pq:r2 (nth 2 r)) (nth 3 r)
                                          (pq:r2 (nth 4 r)) (nth 5 r)
                                          (if (setq w (pq:width (nth 7 r) (nth 3 r))) (pq:r2 w) "")
                                          (nth 6 r))
                                    ",")
                           l4)))))
      (setq l4 (cons "도면번호,자재내역 63mm(M),평면도 63mm(M),차이(M)"
                     (cons "[도면별 대조]" (cons "" l4)))
            tot 0.0 tot2 0.0)
      (foreach fm *PQ-FMAP*
        (setq sub 0.0 sub2 0.0)
        (foreach r r63 (if (= (car r) (car fm)) (setq sub (+ sub (nth 3 r)))))
        ;; 평면도는 관마다 관로명 길이 1번만
        (setq w nil)
        (foreach r p63
          (if (and (= (car r) (car fm)) (not (member (nth 1 r) w)))
            (setq sub2 (+ sub2 (nth 2 r)) w (cons (nth 1 r) w))))
        (if (or (> sub 0.0) (> sub2 0.0))
          (progn
            (setq l4 (cons (pq:join (list (cadr fm) (pq:r2 sub) (pq:r2 sub2) (pq:r2 (- sub2 sub))) ",") l4)
                  tot (+ tot sub) tot2 (+ tot2 sub2))
            ;; 불일치 여부는 최종검수(자재내역 관경별 수량)에서 한 번만 기록
            )))
      (setq l4 (cons (pq:join (list "합계" (pq:r2 tot) (pq:r2 tot2) (pq:r2 (- tot2 tot))) ",") l4))
      (setq f4 (pq:write-safe (strcat dir "PAVQ_63mm_" base ".csv") (reverse l4)))
      ;; 포장 부속 : 신설관과 겹치는 횡단보도 / 과속방지턱
      (setq *PQ-STAGE* "횡단보도/과속방지턱")
      (setq acc (append (pq:try 'pq:acc-collect (list frames) nil nil "횡단보도/과속방지턱")
                        (reverse *PQ-MMA-ACC*)))
      ;; 미끄럼방지 MMA 일괄 : 칼라아스콘 연장 합 x 폭 -> (도곽 구분 설명 면적 수식)
      (foreach m (reverse *PQ-MMA*)
        (if (caddr m)
          (progn
            (setq cl (cond ((cdr (assoc (car m) *PQ-MMA-LEN*))) (0.0)))
            (setq acc (append acc (list (list (car m) "미끄럼방지 MMA"
                                              (strcat "일괄 연장" (pq:nz cl) "M x 폭" (pq:nz (caddr m)) "M")
                                              (* cl (caddr m))
                                              (strcat (pq:nz cl) "*" (pq:nz (caddr m)))))))
            ))
        ;; 경계 면적을 쓴 도면 : 경계 안 신설관 길이 vs 종단 칼라아스콘 연장 (맞으면 오류목록에 안 남김)
        (if (and (= (cadr m) "M") (null (caddr m)) (cadddr m))
          (progn
            (setq cl (cond ((cdr (assoc (car m) *PQ-MMA-LEN*))) (0.0)))
            (if (> (abs (- (cadddr m) cl)) (max *PQ-MMA-LEN-TOL* (* 0.05 cl)))
              (pq:err (car m) nil nil nil
                      (strcat "미끄럼방지 MMA 경계 안 신설관 길이 " (pq:r2 (cadddr m)) "M / 종단 칼라아스콘 연장 "
                              (pq:nz cl) "M 불일치 -> 경계 선택 확인"))))))
      ;; 최종검수 : 도면별 관경 연장 합계 vs 자재내역 관경별 수량 (직관+연결관+인입관)
      (setq *PQ-STAGE* "최종검수" ok 0)
      (foreach fm *PQ-FMAP*
        (setq agg nil mq (cdr (assoc (car fm) matq)))
        (foreach e tblF
          (if (= (car (car e)) (car fm))
            (progn
              (setq k (list (nth 1 (cadr e)) (nth 2 (cadr e))) w 0.0)
              (foreach kv (caddr e) (setq w (+ w (cdr kv))))
              (setq agg (if (assoc k agg) (subst (cons k (+ (cdr (assoc k agg)) w)) (assoc k agg) agg) (cons (cons k w) agg))))))
        (cond
          ((null agg) nil)
          ((null mq)
           (pq:err (car fm) nil nil nil "최종검수 : 자재내역 관 수량(직관/연결관/인입관)을 찾지 못해 검수 못 함 (확인)"))
          (T
           (foreach k (append (mapcar 'car agg) (vl-remove-if '(lambda (x) (assoc x agg)) (mapcar 'car mq)))
             (setq w (cond ((cdr (assoc k agg))) (0.0)) cv (cond ((cdr (assoc k mq))) (0.0)))
             (if (> (abs (- w cv)) *PQ-TOL-SUM*)
               (pq:err (car fm) nil nil nil
                       (strcat "최종검수 : " (pq:dia-str k) " 자재내역 " (pq:r2 cv) "M / 집계 " (pq:r2 w)
                               "M 불일치 (차 " (pq:r2 (- w cv)) "M)"))
               (setq ok (1+ ok)))))))
      ;; 집계표 아래 : 자재내역 관경별 수량 (복구수량산출서 G열 "도면별" 에 씀)
      ;;   구성 : 품명이 2줄 이상이면 "직관+연결관" 수식용 숫자 (예 200+14.5)
      (setq l2 (cons "도면번호,관경값,단위,자재내역(M),구성" (cons "[자재내역 관경별 수량]" (cons "" l2))))
      (foreach fm *PQ-FMAP*
        (foreach kv (reverse (cdr (assoc (car fm) matq)))
          (setq l2 (cons (pq:join (list (cadr fm) (itoa (car (car kv))) (cadr (car kv)) (pq:r2 (cdr kv))
                                        (pq:tq-formula (cdr (assoc (car kv) (cdr (assoc (car fm) matp))))))
                                  ",") l2))))
      ;; 3) 오류
      (setq l3 (append (reverse *PQ-ERRS*) (reverse *PQ-WMISS*)))
      (if (null l3) (setq l3 (list "검토 필요 항목 없음")))
      ;; 집계표 아래에 검토 사항 기록 (*PQ-CSV-SKIP* 안내 메시지는 제외)
      (setq l2 (cons "[검토 사항]" (cons "" l2)) k 0)
      (foreach m l3
        (if (not (pq:csv-skip m))
          (setq l2 (cons (pq:csv-cell m) l2) k (1+ k))))
      (if (= k 0) (setq l2 (cons "검토 필요 항목 없음" l2)))
      ;; 비고 : 63mm 한 관 안에서 0.5M 이하 포장구분을 가장 긴 포장에 합산한 내역
      (if *PQ-MERGE-NOTES*
        (progn
          (setq l2 (cons "도면번호,핸들,관로명길이(M),병합된 포장구분,길이(M),합산한 포장구분"
                         (cons (strcat "[비고 : 평면도 63mm·분기관 포장구분 " (pq:r2 *PQ-63-MIN-PAVE*) "M 이하 병합]")
                               (cons "" l2))))
          (foreach fm *PQ-FMAP*
            (foreach m (reverse *PQ-MERGE-NOTES*)
              (if (= (car m) (car fm))
                (setq l2 (cons (pq:join (list (cadr fm) (nth 1 m) (pq:r2 (nth 2 m))
                                              (pq:csv-cell (nth 3 m)) (pq:r2 (nth 4 m)) (pq:csv-cell (nth 5 m)))
                                        ",")
                               l2)))))))
      (if acc
        (progn
          (setq l2 (cons "도면번호,구분,핸들,면적(M2),수식"
                         (cons "[포장 부속 : 신설관과 겹치는 횡단보도·과속방지턱 / 미끄럼방지 MMA]" (cons "" l2))))
          (foreach fm *PQ-FMAP*
            (foreach a acc
              (if (= (car a) (car fm))
                (setq l2 (cons (pq:join (append (list (cadr fm) (nth 1 a) (nth 2 a) (pq:r2 (nth 3 a)))
                                                (if (nth 4 a) (list (nth 4 a))))
                                        ",")
                               l2)))))))
      (setq f1 (pq:write-safe (strcat dir "PAVQ_구간_" base ".csv") (reverse l1))
            f2 (pq:write-safe (strcat dir "PAVQ_집계_" base ".csv") (reverse l2))
            f3 (pq:write-safe (strcat dir "PAVQ_오류_" base ".txt") l3))
      ;; 도면 폴더에 저장 못 하면 -> 경고 창 + 로컬 폴더(*PQ-LOCAL-DIR*)에 4개 모두 다시 저장
      (if (and (not (and f1 f2 f3 f4)) *PQ-LOCAL-DIR*)
        (progn
          (setq ldir (pq:local-dir) base (pq:fit-base ldir base0))
          (alert (strcat "PAVQ 결과를 도면 폴더에 저장하지 못했습니다.\n\n" dir
                         "\n\n(경로가 너무 길거나 OneDrive/네트워크 폴더 권한 문제일 수 있음)"
                         "\n\n대신 로컬 폴더에 저장합니다 :\n" ldir))
          (setq dir ldir *PQ-SAVE-LOG* nil
                f4 (pq:write-safe (strcat dir "PAVQ_63mm_" base ".csv") (reverse l4))
                f1 (pq:write-safe (strcat dir "PAVQ_구간_" base ".csv") (reverse l1))
                f2 (pq:write-safe (strcat dir "PAVQ_집계_" base ".csv") (reverse l2))
                f3 (pq:write-safe (strcat dir "PAVQ_오류_" base ".txt") l3))
          (princ (strcat "\n[저장] 도면 폴더 저장 실패 -> 로컬 폴더에 저장 : " dir))))
      ;; 명령행 요약
      (princ (strcat "\n\n==== PAVQ 결과 : 도곽 " (itoa (length frames))
                     "장 / 종단 " (itoa nprof) "개 / 검토 " (itoa *PQ-ECNT*) "건 ===="))
      (foreach e tblF
        (princ (strcat "\n " (pq:lbl (car (car e))) " | " (cadr (car e)) " | "))
        (foreach kv (caddr e) (princ (strcat (car kv) " " (pq:r2 (cdr kv)) "  "))))
      (princ "\n ---- 합계 ----")
      (foreach e tblT
        (princ (strcat "\n " (car e) " | "))
        (foreach kv (caddr e) (princ (strcat (car kv) " " (pq:r2 (cdr kv)) "  "))))
      (princ (strcat "\n ---- 63mm 합계 : 자재내역 " (pq:r2 tot) " M / 평면도 " (pq:r2 tot2) " M ----"))
      (princ (strcat "\n ---- 최종검수 (자재내역 관경별 수량) : 일치 " (itoa ok) "건, 불일치는 검토 사항 참고 ----"))
      (foreach k (append *PQ-ACC* '(("미끄럼방지 MMA")))
        (setq w 0.0 cv 0)
        (foreach a acc (if (= (nth 1 a) (car k)) (setq w (+ w (nth 3 a)) cv (1+ cv))))
        (princ (strcat "\n ---- " (car k) " : " (itoa cv) "개 / " (pq:r2 w) " M2 ----")))
      (foreach m l3 (princ (strcat "\n " m)))
      (foreach m (reverse *PQ-SAVE-LOG*) (princ (strcat "\n[저장] " m)))
      (if (and f1 f2 f3 f4)
        (progn
          (princ (strcat "\n\n저장 : " dir "PAVQ_*_" base))
          ;; 복구수량산출서 자동 작성 : 전자제도_도우미.exe 자신을 불러서 집계 CSV를 넘김
          ;; (경로에 공백/한글이 있어 따옴표로 감쌈. LT 제한으로 실패해도 CSV 결과엔 영향 없음)
          (if *PQ-FORM-AUTO*
            (if (and (boundp '*CADLAUNCHER-EXE*) *CADLAUNCHER-EXE* (findfile *CADLAUNCHER-EXE*))
              (progn
                (startapp *CADLAUNCHER-EXE* (strcat "--pavq-fill " (strcat "\"" f2 "\"")))
                (princ "\n복구수량산출서 작성 중... (완료되면 엑셀이 열립니다)"))
              (princ "\n[알림] 전자제도_도우미.exe 경로를 몰라 복구수량산출서는 만들지 않았습니다. (전자제도 도우미에서 아무 기능이나 한 번 실행한 뒤 다시 시도하세요)"))))
        (progn
          (princ (strcat "\n\n[주의] 일부 파일 저장 실패 - 폴더 : " dir))
          (cond
            ((not (vl-file-directory-p dir))
             (princ "\n  MATX 폴더를 만들지 못함 -> 도면이 저장 안 된 새 도면이거나, 읽기 전용/권한 없는 위치(메일 첨부 임시폴더, 네트워크 드라이브 등)인지 확인"))
            (T
             (princ "\n  같은 이름 파일을 다른 프로그램(엑셀, 탐색기 미리보기 창, 클라우드 동기화, 이전에 실행된 PAVQ_FORM)이 잡고 있는지 확인")))))))
  (princ))

;;----------------------------- 보조 명령 ------------------------------
(defun c:PAVQCAL (/ ss i nm lays)
  (princ "\n관경/포장 밴드 문자를 선택하세요 (여러 개 가능, Enter = 전체 레이어)")
  (if (setq ss (ssget '((0 . "TEXT,MTEXT"))))
    (progn
      (repeat (setq i (sslength ss))
        (setq nm (cdr (assoc 8 (entget (ssname ss (setq i (1- i)))))))
        (if (not (member nm lays)) (setq lays (cons nm lays))))
      (setq *PQ-LAYERS* (pq:join lays ",")))
    (setq *PQ-LAYERS* nil))
  (setenv "PAVQ_LAYERS" (if *PQ-LAYERS* *PQ-LAYERS* ""))
  (princ (strcat "\n대상 레이어 : " (if *PQ-LAYERS* *PQ-LAYERS* "전체")))
  (princ))

(defun c:PAVQDEL (/ ss i n ce)
  ;; 1) 검토 표시 (PAVQ_CHK)
  (setq n 0)
  (if (setq ss (ssget "X" (list (cons 8 *PQ-CHK-LAYER*))))
    (repeat (setq i (sslength ss)) (entdel (ssname ss (setq i (1- i)))) (setq n (1+ n))))
  (princ (strcat "\n검토 표시(" *PQ-CHK-LAYER*  ") " (itoa n) "개 삭제"))
  ;; 2) 63mm 포장 확인선 (0포장63) / 3) 칼라아스콘 경계 (0칼라아스콘) : 객체 삭제 후 레이어도 삭제
  (pq:del-layer *PQ-63-DRAW-LAYER* "63mm 포장 확인선")
  (pq:del-layer *PQ-MMA-DRAW-LAYER* "칼라아스콘 경계")
  (princ))

;; 레이어 객체 삭제 + 레이어 삭제(PURGE)
(defun pq:del-layer (lay what / ss i n ce)
  (if lay
    (progn
      (setq n 0)
      (if (setq ss (ssget "X" (list (cons 8 lay))))
        (repeat (setq i (sslength ss)) (entdel (ssname ss (setq i (1- i)))) (setq n (1+ n))))
      (if (tblsearch "LAYER" lay)
        (progn
          ;; 현재 레이어면 지울 수 없으므로 0 으로 바꿈
          (if (= (strcase (getvar "CLAYER")) (strcase lay)) (setvar "CLAYER" "0"))
          (setq ce (getvar "CMDECHO"))
          (setvar "CMDECHO" 0)
          (command "_.-PURGE" "_LA" lay "_N")
          (setvar "CMDECHO" ce)
          (princ (strcat "\n" what "(" lay ") " (itoa n) "개 삭제"
                         (if (tblsearch "LAYER" lay)
                           " - 레이어는 블럭 안 객체 등이 남아 있어 삭제하지 못함 (LAYDEL 로 확인)"
                           " + 레이어 삭제"))))
        (if (> n 0) (princ (strcat "\n" what "(" lay ") " (itoa n) "개 삭제")))))))

;;----------------------------- 칼라아스콘 검증 ------------------------------
;; PAVQMMA : PAVQ 를 돌리지 않고 칼라아스콘(미끄럼방지 MMA) 경계 찾기만 도면별로 확인
;;   - 도면마다 : 평면도 칼라아스콘 문자 수 / 종단 칼라아스콘 연장 / 찾은 방법 / 경계 수·면적 / 경계 안 신설관 길이 / 판정
;;   - 찾은 경계는 선택 상태로 보여 주고, 가운데에 "MMA#번호 면적 / 관 길이" 표시 (PAVQ_CHK 레이어, PAVQDEL 로 삭제)
;;   - 판정 : 종단 연장과 경계 안 신설관 길이 차이가 *PQ-MMA-LEN-TOL*(또는 5%) 이내면 OK
(defun c:PAVQMMA (/ *error* olde frames alllines fi flines items kl kv nt lbl zc cands how pl ar tot ss k cen pts tol res nok nchk n63 dr *PQ-MMA-QUIET* *PQ-MMA-DEBUG*)
  (defun *error* (msg)
    (if olde (setvar "CMDECHO" olde))
    (princ (strcat "\n[PAVQMMA 중단] 단계 : " (pq:str *PQ-STAGE*) "\n 오류 : " (pq:str msg)))
    (princ))
  (setq olde (getvar "CMDECHO")) (setvar "CMDECHO" 0)
  (setq *PQ-STAGE* "도곽 검색" frames (pq:get-frames) *PQ-FRAMES* frames)
  (if (null frames)
    (princ "\n도곽(FORM 블럭 또는 직사각형)을 찾지 못했습니다.")
    (progn
      (pq:mklayer *PQ-CHK-LAYER*)
      (setq *PQ-STAGE* "문자/평면도 수집"
            *PQ-MMA-PIPES* nil *PQ-MMA-P63* nil *PQ-MMA-DONE* nil *PQ-BBCACHE* nil
            alllines (pq:all-text-lines))
      (pq:p63-prep)
      (setq fi 0 ss (ssadd) k 0 nok 0 nchk 0 *PQ-MMA-NO* 0 *PQ-MMA-QUIET* T *PQ-MMA-TMP* nil)
      ;; 지난번 칼라아스콘 경계 그림 지우고 새로
      (if (and *PQ-MMA-DRAW-LAYER* (setq dr (ssget "X" (list (cons 8 *PQ-MMA-DRAW-LAYER*)))))
        (command "_.ERASE" dr ""))
      (princ "\n\n==== PAVQMMA : 칼라아스콘 경계 검증 ====")
      (princ "\n 도면 | 평면 문자 | 종단 칼라 | 방법 | 경계 | 면적(M2) | 경계 안 신설관 | 판정")
      (foreach f frames
        (setq fi (1+ fi) *PQ-STAGE* (strcat "도곽 " (itoa fi))
              flines (vl-remove-if-not '(lambda (a) (pq:in-frame a f)) alllines)
              items (vl-remove nil (mapcar 'pq:classify (pq:merge-pipe-pave (pq:merge-split flines))))
              kl 0.0)
        ;; 종단 칼라아스콘 연장 (괄호 길이)
        (foreach it items
          (if (and (eq (car it) 'V) (vl-string-search *PQ-MMA-WORD* (pq:norm (nth 4 it))))
            (setq kl (+ kl (nth 5 it)))))
        ;; 평면도 칼라아스콘 문자 수
        (setq nt (length (vl-remove-if-not
                           '(lambda (l) (and (pq:in-r (cadr l) (pq:p63-rect f)) (vl-string-search *PQ-MMA-WORD* (pq:norm (car l)))))
                           *P63-PAVE*)))
        (if (or (> kl 0.0) (> nt 0))
          (progn
            (setq cands (pq:mma-cands fi)
                  how (cond ((null cands) "-")
                            ((and (> *PQ-MMA-SEEDN* 0) (> (length cands) *PQ-MMA-SEEDN*)) (strcat "문자+" *PQ-MMA-ZC-LAYER*))
                            ((> *PQ-MMA-SEEDN* 0) "문자 기준")
                            (T (strcat *PQ-MMA-ZC-LAYER* " 기준")))
                  tot 0.0)
            (foreach c cands (setq tot (+ tot (cadr c))))
            (pq:mma-record fi (mapcar 'car cands))
            ;; 경계를 못 찾은 도면 : ZC154 판정 이유 출력 (진단)
            (if (and (null cands) (= *PQ-MMA-DUPN* 0))
              (progn
                (setq *PQ-MMA-DEBUG* T)
                (foreach c (pq:mma-zc fi) (if (pq:mma-tmp-p (car c)) (entdel (car c))))
                (setq *PQ-MMA-DEBUG* nil)))
            (setq pl (if cands (pq:mma-pipe-len (mapcar 'car cands)) 0.0))
            ;; 경계를 0칼라아스콘 레이어에 그림 (PAVQ 와 같은 모양) -> 그린 도형을 선택 표시
            ;;   번호는 신설관 측점(NO) 순 (63mm 만 지나는 구간 포함)
            (if cands
              (progn
                (setq dr (pq:mma-draw fi (mapcar 'car cands) "칼라"))
                (foreach e dr (if (= (cdr (assoc 0 (entget e))) "LWPOLYLINE") (ssadd e ss)))
                (foreach c cands (if (pq:mma-tmp-p (car c)) (ssadd (car c) ss)))))
            (setq pl pl
                  tol (max *PQ-MMA-LEN-TOL* (* 0.05 kl))
                  res (cond ((and (null cands) (> *PQ-MMA-DUPN* 0))
                             (strcat "앞 도면과 같은 경계 " (itoa *PQ-MMA-DUPN*) "곳 -> 중복 제외"))
                            ((null cands) "경계 없음 (확인)")
                            ((= kl 0.0) "종단 칼라아스콘 없음 (확인)")
                            ((<= (abs (- pl kl)) tol) "OK")
                            (T (strcat "길이 차 " (pq:r2 (- pl kl)) "M (확인)"))))
            (if (= res "OK") (setq nok (1+ nok)) (setq nchk (1+ nchk)))
            (princ (strcat "\n " (if (= (length *PQ-FMAP*) (length frames)) (pq:lbl fi) (strcat "도곽 " (itoa fi)))
                           " | " (itoa nt) "개 | " (pq:r2 kl) "M | " how " | " (itoa (length cands)) "곳"
                           (if (setq n63 (length (vl-remove-if-not '(lambda (c) (eq (nth 3 c) 'P63)) cands)))
                             (if (> n63 0) (strcat "(63mm만 " (itoa n63) ")") "") "")
                           " | "
                           (pq:r2 tot) " | " (pq:r2 pl) "M | " res)))))
      (princ (strcat "\n---- 칼라아스콘 도면 : OK " (itoa nok) " / 확인 " (itoa nchk)
                     " (경계는 " *PQ-MMA-DRAW-LAYER* " 레이어에 그리고 선택 표시 -> PAVQDEL 로 삭제) ----"))
      ;; 리습이 그린 객체 맨 위로 (63mm 확인선이 칼라아스콘 경계보다 위)
      (pq:p63-front)
      (if (> (sslength ss) 0) (sssetfirst nil ss))))
  (setvar "CMDECHO" olde)
  (princ))

(princ "\nPAVQ.lsp 로드 : PAVQ (산출) / PAVQCAL (레이어 지정) / PAVQDEL (검토 표시·0포장63·0칼라아스콘 삭제) / PAVQMMA (칼라아스콘 경계 검증)")
(princ)
