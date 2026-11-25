;;; @launcher
;;; 리습: HGTOOL
;;; 분류: 허가도면
;;; 설명: 허가도면 작성 도구 (지적 교차 끊기 → 허가구간 종단 반영 → 도곽 복사)
;;; 기능: 허가도면 한 번에 작성 | HG0 | 지적 선택 한 번으로 1~3단계(끊기·종단 반영·도곽 복사)를 연속 실행
;;; 기능: 1) 지적 교차 끊기 | HG1BRK | 지적과 교차하는 신설관을 끊고 지적 안 신설관을 색상 210 으로
;;; 기능: 2) 허가구간 종단 반영 | HG2PRF | 끊어 놓은 주관로 구간을 종단면도에 반영하고 허가구간 밴드 작도
;;; 기능: 3) 도곽 복사 | HG3CPY | 도곽을 허가도면용으로 복사하고 관경별 연장 텍스트 작성
;;; 설명서:
;;;   허가도면 작성을 돕는 도구입니다. 보통 'HG0' 하나로 1~3단계를 연속 실행합니다.
;;;   (각 단계를 따로 실행해도 됩니다. 실행 결과는 U 한 번으로 되돌릴 수 있습니다.)
;;;
;;;   [사용 전 확인]
;;;   • 지적 레이어: 이름에 '지적' 포함 / 신설관 레이어: '신설관'으로 시작
;;;   • 구역선(도로구역·도시계획·하천구역) 판정은 현재 꺼져 있습니다 - 지적 안 신설관은 구역과 상관없이 모두 210 대상입니다.
;;;     (다시 쓰려면 리습의 *JB:USE-ZONE* 를 T 로)
;;;   • 종단: Q-종단가스관로, Q-종단측점, Q-종단그래프 레이어 / 도곽: FORM 블록 또는 사각 테두리
;;;
;;;   [순서]
;;;   1) 지적 교차 끊기(HG1BRK): 지적 선택 → 교차하는 신설관을 끊고, 지적 안 신설관을 색상 210 으로 (바꾸기 전에 강조해서 확인받음)
;;;   2) 허가구간 종단 반영(HG2PRF): 색상 210 주관로 구간을 종단에 반영 (구간 밖 검은색, 시/종점 수직선 + 허가구간 밴드)
;;;   3) 도곽 복사(HG3CPY): 도곽을 삽입점에 복사 (평면도 안은 보존 레이어만) + 원본 도곽 아래에 관경별·지번별 연장 작성
;;; 기능설명서: HG0
;;;   지적을 한 번 선택하면, 그 지적이 들어 있는 도곽을 자동으로 찾아
;;;   1) 지적 교차 끊기 → 2) 허가구간 종단 반영 → 3) 도곽 복사 를 이어서 실행합니다.
;;;   • 2단계에서 반영할 주관로가 없으면 건너뛰고 3단계로 갑니다.
;;;   • 전체가 한 묶음이라 U 한 번으로 모두 되돌릴 수 있습니다.
;;; 기능설명서: HG1BRK
;;;   선택한 지적과 교차하는 신설관을 교차점에서 끊습니다.
;;;   닫힌 지적 안의 신설관은 색상 210, 나머지 끊은 조각은 ByLayer 로 바꿉니다.
;;;   • 색상을 바꾸기 전에 대상을 화면에 강조해서 추가/제외를 확인받음
;;;   • 구역선(도로·도시계획·하천) 제외 판정은 꺼져 있음 (*JB:USE-ZONE* = T 로 켜면 예전처럼 구역 안 제외)
;;;   • 관로명/63 관로명 글자도 해당 신설관 색상에 맞춤, 선택한 지적은 폴리선 두께 0.15
;;; 기능설명서: HG2PRF
;;;   끊어 놓은 평면 신설관(주관로) 조각을 선택하면, 같은 측점에서 종단 관로를 잘라
;;;   구간 밖은 검은색으로 바꾸고, 구간 시/종점 수직선과 허가구간 밴드를 그립니다(0허가도면 레이어).
;;; 기능설명서: HG3CPY
;;;   도곽(블록/테두리 폴리선/창 지정) 안의 객체를 지정한 삽입점에 복사합니다.
;;;   평면도 틀 안은 보존 레이어(평면도틀·신설관·캡·지적·지번·L)만 복사하고,
;;;   원본 도곽 아래에 색상 210 신설관의 관경별(지번별) 연장 텍스트를 작성합니다.
;;; @end
;;; ==========================================================================
;;;  HGTOOL.lsp  -  허가도면 작성 도구 (AutoCAD LT 2026, ActiveX 미사용)
;;;
;;;  명령어
;;;   HG0    : (0) 지적 선택 한 번으로 HG1BRK -> HG2PRF -> HG3CPY 연속 실행
;;;
;;;   HG1BRK : (1) 지적 교차 끊기
;;;           지적 객체 선택 -> 교차하는 신설관을 교차점에서 끊음
;;;           닫힌 지적 내부의 신설관(끊은 조각 + 원래 내부에 있던 관)은 색상 210
;;;           (*JB:USE-ZONE* = T 일 때만) 도로구역(지방도·국도)·도시계획·하천·소하천 구역 안은 제외 (가장 바깥 경계 기준),
;;;           구역선도 절단 경계로 사용  - 기본값 nil: 구역선 판정 안 함
;;;           색상을 바꾸기 전에 대상을 강조해 보여 주고 추가/제외(/구역포함)를 확인받음
;;;           관로명/63 관로명도 해당 신설관 색상에 맞춤 (63은 캡으로 매칭), 나머지 끊은 조각은 ByLayer, 모든 신설관 레이어 색상은 흰색(7)
;;;           (숨은선 신설관 제외, 관 시/종점 0.01 이내 교차는 무시)
;;;           선택한 지적은 폴리선 두께 0.15 적용
;;;
;;;   HG2PRF : (2) 허가구간 종단 반영
;;;           끊어 놓은 평면 신설관(주관로) 조각 선택 ->
;;;           Q-종단가스관로를 같은 측점에서 잘라 구간 밖 검은색,
;;;           도시가스관로(종단) 구간 밖 검은색,
;;;           구간 시/종점 수직선 + 허가구간 밴드 작도 (0허가도면 레이어)
;;;           종단 위치가 종단 관로 범위를 넘으면 시/종점으로 맞춤
;;;
;;;   HG3CPY : (3) 도곽 복사
;;;           도곽(블록/테두리 폴리선/창) 안의 객체를 삽입점에 복사
;;;           평면도 틀 안은 보존 레이어(평면도틀·신설관·캡·지적·지번·L)만 복사
;;;           복사 후 원본 도곽 하단에 색상 210 신설관 관경별 연장 텍스트 작성
;;;
;;;
;;;  작업 순서 예 : HG1BRK(지적 경계에서 끊기) -> HG2PRF(종단 반영) -> HG3CPY(허가도면 복사)
;;; ==========================================================================

;;; ##########################################################################
;;;  [1] HG1BRK - 지적 교차 끊기
;;; ##########################################################################

;;; ---------------- 설정 ----------------
(setq *JB:LAY-JIJUK*   "*지적*")     ; 지적 레이어 (선택 필터)
(setq *JB:LAY-PIPE*    "신설관*")    ; 신설관 레이어
(setq *JB:HIDDEN*      "*HIDDEN*")   ; 제외할 선종류
(setq *JB:SKIP-HIDDEN* T)            ; 숨은선 신설관 제외 여부 (nil = 포함)
(setq *JB:EPS*         1e-7)         ; 구간 판정 허용오차(비율)
(setq *JB:PTOL*        1e-4)         ; 같은 점 판정 거리
(setq *JB:MINLEN*      0.1)          ; 관 끝/꼭짓점/다른 절단점에서 이 거리 이내 교차는 새로 끊지 않음
(setq *JB:USE-ZONE*    nil)          ; 구역선 판정 사용 여부 (nil = 안 함: 구역선을 읽지 않고, 구역선에서 끊지도 않고, 구역 안도 210 대상에 포함 / T = 예전처럼 구역 안 제외)
(setq *JB:LAY-ZONE*    "*도로구역*,*도시계획*,*하천구역*")  ; 구역선 (지방도·국도, 도시계획, 하천·소하천)
(setq *JB:ZONE-MAXW*   60.0)         ; 구역 판정 최대 폭 (양쪽 구역선 사이 거리)
(setq *JB:IN-COL*      210)          ; 닫힌 지적 내부의 끊은 신설관 색상
(setq *JB:CONFIRM*     T)            ; 210 대상을 강조해 보여 주고 확인받기 (nil = 확인 생략)
(setq *JB:JJ-WIDTH*    0.15)         ; 선택한 지적의 폴리선 두께(전역 폭)
(setq *JB:LAY-COL*     7)            ; 모든 신설관 레이어(및 관로명 레이어) 색상 (7 = 흰색)
(setq *JB:LAY-NAME*    "관로명")         ; 주관로 관로명 레이어
(setq *JB:LAY-NAME63*  "LPPE63A관로명")  ; 63관 관로명 레이어
(setq *JB:LAY-CAP*     "LPPE63ACAP")     ; 63관 캡 레이어 (관로명 <-> 공급관 연결용)
(setq *JB:NAME-DIST*   3.0)              ; 관로명 - 신설관 최대 거리
(setq *JB:CAP-DIST*    20.0)             ; 63 관로명 - 캡 최대 거리
                                     ; 지적 밖 조각은 ByLayer 로 바꿔 레이어 색을 따름

;;; ---------------- 유틸 ----------------
(defun jb:dxf (c ed) (cdr (assoc c ed)))
(defun jb:pt (v) (list (car v) (cadr v)))

(defun jb:verts (ed / res v)
  (cond
    ((= (jb:dxf 0 ed) "LINE")
     (list (list (car (jb:dxf 10 ed)) (cadr (jb:dxf 10 ed)) 0.0 0.0 0.0)
           (list (car (jb:dxf 11 ed)) (cadr (jb:dxf 11 ed)) 0.0 0.0 0.0)))
    ((= (jb:dxf 0 ed) "LWPOLYLINE")
     (foreach p ed
       (cond
         ((= (car p) 10)
          (if v (setq res (cons v res)))
          (setq v (list (cadr p) (caddr p) 0.0 0.0 0.0)))
         ((and v (= (car p) 40)) (setq v (list (car v) (cadr v) (cdr p) (cadddr v) (nth 4 v))))
         ((and v (= (car p) 41)) (setq v (list (car v) (cadr v) (caddr v) (cdr p) (nth 4 v))))
         ((and v (= (car p) 42)) (setq v (list (car v) (cadr v) (caddr v) (cadddr v) (cdr p))))))
     (if v (setq res (cons v res)))
     (reverse res)))
)

(defun jb:closed-p (ed)
  (and (= (jb:dxf 0 ed) "LWPOLYLINE") (= 1 (logand 1 (jb:dxf 70 ed))))
)

;; 세그먼트 목록 ((p1 p2 bulge) ...)
(defun jb:segs (vs closed / res)
  (setq res nil)
  (if closed (setq vs (append vs (list (car vs)))))
  (while (cdr vs)
    (setq res (cons (list (jb:pt (car vs)) (jb:pt (cadr vs)) (nth 4 (car vs))) res)
          vs  (cdr vs)))
  (reverse res)
)

(defun jb:isarc (s) (> (abs (caddr s)) 1e-9))

;; 호 정보 (중심 반지름 시작각 사잇각[부호])
(defun jb:arc (s / p1 p2 th r a ca)
  (setq p1 (car s) p2 (cadr s)
        th (* 4.0 (atan (caddr s)))
        r  (/ (distance p1 p2) (* 2.0 (sin (/ (abs th) 2.0))))
        a  (angle p1 p2)
        ca (if (> th 0.0)
             (- (+ a (/ pi 2.0)) (/ th 2.0))
             (- (- a (/ pi 2.0)) (/ th 2.0))))
  (list (polar p1 ca r) r (angle (polar p1 ca r) p1) th)
)

;; 세그먼트 경계상자 (호는 원 전체로 보수적으로)
(defun jb:segbox (s / ar)
  (if (jb:isarc s)
    (progn
      (setq ar (jb:arc s))
      (list (list (- (car (car ar)) (cadr ar)) (- (cadr (car ar)) (cadr ar)))
            (list (+ (car (car ar)) (cadr ar)) (+ (cadr (car ar)) (cadr ar)))))
    (list (list (min (car (car s)) (car (cadr s))) (min (cadr (car s)) (cadr (cadr s))))
          (list (max (car (car s)) (car (cadr s))) (max (cadr (car s)) (cadr (cadr s))))))
)

(defun jb:boxu (a b)
  (if (null a) b
    (list (list (min (car (car a)) (car (car b))) (min (cadr (car a)) (cadr (car b))))
          (list (max (car (cadr a)) (car (cadr b))) (max (cadr (cadr a)) (cadr (cadr b))))))
)

(defun jb:boxhit (a b / t1)
  (setq t1 1e-6)
  (and a b
       (<= (car (car a)) (+ (car (cadr b)) t1)) (>= (car (cadr a)) (- (car (car b)) t1))
       (<= (cadr (car a)) (+ (cadr (cadr b)) t1)) (>= (cadr (cadr a)) (- (cadr (car b)) t1)))
)

;; 점 q 의 세그먼트상 위치 비율 (0=시작, 1=끝)
(defun jb:frac (s q / ar d l)
  (if (jb:isarc s)
    (progn
      (setq ar (jb:arc s)
            d  (- (angle (car ar) q) (caddr ar)))
      (if (< (cadddr ar) 0.0) (setq d (- d)))
      (if (< d 0.0) (setq d (+ d (* 2.0 pi))))
      (if (> d (- (* 2.0 pi) 1e-9)) (setq d 0.0))
      (/ d (abs (cadddr ar))))
    (progn
      (setq l (distance (car s) (cadr s)))
      (/ (+ (* (- (car q) (car (car s))) (- (car (cadr s)) (car (car s))))
            (* (- (cadr q) (cadr (car s))) (- (cadr (cadr s)) (cadr (car s)))))
         (* l l))))
)

;; 비율 f 위치의 점
(defun jb:ptat (s f / ar)
  (if (jb:isarc s)
    (progn
      (setq ar (jb:arc s))
      (polar (car ar) (+ (caddr ar) (* (cadddr ar) f)) (cadr ar)))
    (list (+ (car (car s)) (* f (- (car (cadr s)) (car (car s)))))
          (+ (cadr (car s)) (* f (- (cadr (cadr s)) (cadr (car s)))))))
)

;; 직선(a-b) x 원
(defun jb:lc (a b ar / dx dy fx fy qa qb qc disc sq res tt)
  (setq dx (- (car b) (car a)) dy (- (cadr b) (cadr a))
        fx (- (car a) (car (car ar))) fy (- (cadr a) (cadr (car ar)))
        qa (+ (* dx dx) (* dy dy))
        qb (* 2.0 (+ (* fx dx) (* fy dy)))
        qc (- (+ (* fx fx) (* fy fy)) (* (cadr ar) (cadr ar)))
        disc (- (* qb qb) (* 4.0 qa qc)))
  (if (and (> qa 1e-12) (>= disc (- (* 1e-9 qa))))
    (progn
      (setq sq (sqrt (max 0.0 disc)))
      (foreach tt (list (/ (+ (- qb) sq) (* 2.0 qa)) (/ (- (- qb) sq) (* 2.0 qa)))
        (setq res (cons (list (+ (car a) (* tt dx)) (+ (cadr a) (* tt dy))) res)))))
  res
)

;; 원 x 원
(defun jb:cc (a1 a2 / c1 c2 r1 r2 d a h pm ux uy)
  (setq c1 (car a1) r1 (cadr a1) c2 (car a2) r2 (cadr a2) d (distance c1 c2))
  (if (and (> d 1e-9) (<= d (+ r1 r2 1e-7)) (>= d (- (abs (- r1 r2)) 1e-7)))
    (progn
      (setq a  (/ (+ (- (* r1 r1) (* r2 r2)) (* d d)) (* 2.0 d))
            h  (sqrt (max 0.0 (- (* r1 r1) (* a a))))
            ux (/ (- (car c2) (car c1)) d)
            uy (/ (- (cadr c2) (cadr c1)) d)
            pm (list (+ (car c1) (* a ux)) (+ (cadr c1) (* a uy))))
      (list (list (- (car pm) (* h uy)) (+ (cadr pm) (* h ux)))
            (list (+ (car pm) (* h uy)) (- (cadr pm) (* h ux))))))
)

;; 두 세그먼트의 교차점 후보 (무한 직선/원 기준, 이후 구간 검증)
(defun jb:cand (s1 s2 / p)
  (cond
    ((and (not (jb:isarc s1)) (not (jb:isarc s2)))
     (if (setq p (inters (car s1) (cadr s1) (car s2) (cadr s2) nil)) (list (jb:pt p))))
    ((not (jb:isarc s1)) (jb:lc (car s1) (cadr s1) (jb:arc s2)))
    ((not (jb:isarc s2)) (jb:lc (car s2) (cadr s2) (jb:arc s1)))
    (T (jb:cc (jb:arc s1) (jb:arc s2))))
)

(defun jb:in01 (f) (and (>= f (- *JB:EPS*)) (<= f (+ 1.0 *JB:EPS*))))

(defun jb:hidden-p (ed / la lt)
  (setq la (tblsearch "LAYER" (jb:dxf 8 ed))
        lt (jb:dxf 6 ed))
  (if (or (null lt) (= (strcase lt) "BYLAYER")) (setq lt (jb:dxf 6 la)))
  (and lt (wcmatch (strcase lt) *JB:HIDDEN*))
)

;;; ---------------- 객체 생성 ----------------
(defun jb:hdr (ed / r)
  (foreach p ed
    (if (not (member (car p) '(-1 330 5 102 360 10 11 40 41 42 90 91 210)))
      (setq r (cons p r))))
  (reverse r)
)

(defun jb:mkpl (ed vs / r flag cw)
  (setq flag (cond ((jb:dxf 70 ed)) (0))
        cw   (and (jb:dxf 43 ed) (/= 0.0 (jb:dxf 43 ed))))
  (foreach p (jb:hdr ed)
    (cond
      ((= (car p) 70) (setq r (cons (cons 70 (logand flag 128)) r)))
      (T
       (setq r (cons p r))
       (if (equal p '(100 . "AcDbPolyline")) (setq r (cons (cons 90 (length vs)) r))))))
  (setq r (reverse r))
  (foreach v vs
    (setq r (append r (if cw
                        (list (list 10 (car v) (cadr v)) (cons 42 (nth 4 v)))
                        (list (list 10 (car v) (cadr v))
                              (cons 40 (caddr v)) (cons 41 (cadddr v)) (cons 42 (nth 4 v)))))))
  (if (assoc 210 ed) (setq r (append r (list (assoc 210 ed)))))
  (entmake r)
)

(defun jb:mkln (ed vs / z1 z2)
  (setq z1 (cond ((caddr (jb:dxf 10 ed))) (0.0))
        z2 (cond ((caddr (jb:dxf 11 ed))) (0.0)))
  (entmake
    (append (jb:hdr ed)
            (list (list 10 (car (car vs)) (cadr (car vs)) z1)
                  (list 11 (car (cadr vs)) (cadr (cadr vs)) z2))
            (if (assoc 210 ed) (list (assoc 210 ed)))))
)

;;; ---------------- 신설관 1개 처리 ----------------
;; bsegs: 지적 세그먼트 목록. 끊었으면 새 조각 ename 목록, 아니면 nil
(defun jb:dopipe (e bsegs / ed vs segs n i s cuts f1 f2 p l q vcut fs out j v ar th fl k
                    pieces cur pstart pend)
  (setq ed   (entget e)
        vs   (jb:verts ed)
        segs (jb:segs vs nil)
        n    (length segs)
        pstart (jb:pt (car vs))
        pend   (jb:pt (last vs))
        i 0)
  ;; 교차점 수집 : (세그번호 비율)
  (foreach s segs
    (if (> (distance (car s) (cadr s)) 1e-9)
      (foreach bs bsegs
        (if (and (> (distance (car bs) (cadr bs)) 1e-9)
                 (jb:boxhit (jb:segbox s) (jb:segbox bs)))
          (foreach p (jb:cand s bs)
            (setq f1 (jb:frac s p) f2 (jb:frac bs p))
            (if (and (jb:in01 f1) (jb:in01 f2)
                     (> (distance p pstart) *JB:MINLEN*)
                     (> (distance p pend) *JB:MINLEN*))
              (setq cuts (cons (list i (max 0.0 (min 1.0 f1))) cuts)))))))
    (setq i (1+ i)))
  (if (null cuts)
    nil
    (progn
      ;; 끝(1.0)은 다음 세그 시작(0.0)으로, 꼭짓점 절단 / 내부 절단 분리
      (foreach c cuts
        (setq i (car c) f1 (cadr c)
              l (* (distance (car (nth i segs)) (cadr (nth i segs))) (if (jb:isarc (nth i segs)) 2.0 1.0)))
        (cond
          ((<= (* (- 1.0 f1) l) *JB:MINLEN*)
           (if (not (member (1+ i) vcut)) (setq vcut (cons (1+ i) vcut))))
          ((<= (* f1 l) *JB:MINLEN*)
           (if (not (member i vcut)) (setq vcut (cons i vcut))))
          (T
           (setq q (assoc i fs))
           (if q
             (if (not (vl-some '(lambda (x) (<= (* (abs (- x f1)) l) *JB:MINLEN*)) (cdr q)))
               (setq fs (subst (cons i (cons f1 (cdr q))) q fs)))
             (setq fs (cons (list i f1) fs))))))
      ;; 새 꼭짓점 목록 ((정점 . 절단여부) ...)
      (setq j 0)
      (foreach v vs
        (cond
          ((>= j n) (setq out (cons (cons v nil) out)))
          ((setq q (assoc j fs))
           (setq s  (nth j segs)
                 fl (append (list 0.0) (vl-sort (cdr q) '<) (list 1.0)))
           (if (jb:isarc s) (setq ar (jb:arc s) th (cadddr ar)))
           (setq k 0)
           (while (cdr fl)
             (setq p (jb:ptat s (car fl)))
             (setq v (if (= k 0)
                       (list (car v) (cadr v) (caddr v) (cadddr v)
                             (if (jb:isarc s) (/ (sin (/ (* th (- (cadr fl) (car fl))) 4.0))
                                                (cos (/ (* th (- (cadr fl) (car fl))) 4.0)))
                                              0.0))
                       (list (car p) (cadr p) (caddr v) (caddr v)
                             (if (jb:isarc s) (/ (sin (/ (* th (- (cadr fl) (car fl))) 4.0))
                                                (cos (/ (* th (- (cadr fl) (car fl))) 4.0)))
                                              0.0))))
             (setq out (cons (cons v (if (= k 0) (member j vcut) T)) out)
                   fl  (cdr fl)
                   k   (1+ k))))
          (T (setq out (cons (cons v (member j vcut)) out))))
        (setq j (1+ j)))
      (setq out (reverse out))
      ;; 조각 분리
      (foreach o out
        (setq cur (cons (car o) cur))
        (if (and (cdr o) (cdr cur))
          (setq pieces (cons (reverse cur) pieces)
                cur    (list (car o)))))
      (if (cdr cur) (setq pieces (cons (reverse cur) pieces)))
      (if (> (length pieces) 1)
        (progn
          (setq out nil)
          (foreach pc (reverse pieces)
            (if (if (= (jb:dxf 0 ed) "LINE") (jb:mkln ed pc) (jb:mkpl ed pc))
              (setq out (cons (entlast) out))))
          (entdel e)
          out)
        nil)))
)

;;; ---------------- 내부 판정 ----------------
;; 닫힌 지적 -> 다각형 점 목록 (호는 8등분)
(defun jb:poly (ed / res k)
  (foreach s (jb:segs (jb:verts ed) T)
    (setq res (cons (car s) res))
    (if (jb:isarc s)
      (progn
        (setq k 1)
        (repeat 7
          (setq res (cons (jb:ptat s (/ k 8.0)) res) k (1+ k))))))
  (reverse res)
)

;; 점 p 가 다각형 내부인지 (ray casting)
(defun jb:inpoly (p pl / in a b n i)
  (setq n (length pl) i 0 in nil)
  (while (< i n)
    (setq a (nth i pl) b (nth (rem (1+ i) n) pl))
    (if (and (/= (> (cadr a) (cadr p)) (> (cadr b) (cadr p)))
             (< (car p) (+ (car a) (/ (* (- (cadr p) (cadr a)) (- (car b) (car a)))
                                      (- (cadr b) (cadr a))))))
      (setq in (not in)))
    (setq i (1+ i)))
  in
)

;; 조각의 대표점 (첫 유효 세그먼트 중간)
(defun jb:midpt (ed / segs s)
  (setq segs (jb:segs (jb:verts ed) nil))
  (while (and segs (< (distance (car (car segs)) (cadr (car segs))) 1e-9))
    (setq segs (cdr segs)))
  (if segs (jb:ptat (car segs) 0.5))
)

;; 레이어 자체 색상 변경 (꺼진 레이어는 음수 유지)
(defun jb:laycol (lay col / ld old)
  (if (setq ld (entget (tblobjname "LAYER" lay)))
    (progn
      (setq old (cdr (assoc 62 ld)))
      (entmod (subst (cons 62 (if (and old (minusp old)) (- col) col)) (assoc 62 ld) ld))))
)

;;; ---------------- 관로명 색상 ----------------
(defun jb:psd (p a b / dx dy l2 t1)
  (setq dx (- (car b) (car a)) dy (- (cadr b) (cadr a)) l2 (+ (* dx dx) (* dy dy)))
  (setq t1 (if (< l2 1e-12) 0.0
             (max 0.0 (min 1.0 (/ (+ (* (- (car p) (car a)) dx) (* (- (cadr p) (cadr a)) dy)) l2)))))
  (distance p (list (+ (car a) (* t1 dx)) (+ (cadr a) (* t1 dy))))
)

(defun jb:pldist (p pts / d)
  (setq d (distance p (car pts)))
  (while (cdr pts)
    (setq d (min d (jb:psd p (car pts) (cadr pts))) pts (cdr pts)))
  d
)

(defun jb:endsnear (pts q)
  (or (< (distance (car pts) q) 0.05) (< (distance (last pts) q) 0.05))
)

;; pinfo 항목 : (ename 레이어 점목록 색상 길이)
;; st 와 끝점으로 이어진 같은 레이어 신설관 (63 공급관 가지)
(defun jb:branch (st pinfo / br same chg)
  (setq br (list st) chg T
        same (vl-remove-if-not '(lambda (q) (= (cadr q) (cadr st))) pinfo))
  (while chg
    (setq chg nil)
    (foreach q same
      (if (and (not (member q br))
               (vl-some '(lambda (r) (or (jb:endsnear (caddr r) (car (caddr q)))
                                          (jb:endsnear (caddr r) (last (caddr q)))))
                        br))
        (setq br (cons q br) chg T))))
  br
)

;; 관로명 / 63 관로명 색상 맞추기. aff = 이번에 처리한 신설관. 반환 (개수 레이어목록)
(defun jb:donames (aff pinfo / ss i e ed pt r v c dist perp caps pairs used-t used-c
                     m st br l210 lt n lays best bd d)
  (setq n 0)
  ;; 캡 : (ename . 현 중점)
  (if (setq ss (ssget "_X" (list '(0 . "LWPOLYLINE,LINE") (cons 8 *JB:LAY-CAP*) '(410 . "Model"))))
    (repeat (setq i (sslength ss))
      (setq e (ssname ss (setq i (1- i)))
            v (mapcar 'jb:pt (jb:verts (entget e))))
      (setq caps (cons (cons e (list (/ (+ (car (car v)) (car (last v))) 2.0)
                                     (/ (+ (cadr (car v)) (cadr (last v))) 2.0)))
                       caps))))
  ;; 63 관로명 <-> 캡 : 거리 + 글자 방향 직각거리 x5 점수로 1:1 매칭
  (if (and caps (setq ss (ssget "_X" (list '(0 . "TEXT") (cons 8 *JB:LAY-NAME63*) '(410 . "Model")))))
    (repeat (setq i (sslength ss))
      (setq e  (ssname ss (setq i (1- i)))
            ed (entget e)
            pt (jb:pt (qc:txtpt ed))
            r  (cond ((jb:dxf 50 ed)) (0.0)))
      (foreach c caps
        (setq v    (list (- (car (cdr c)) (car pt)) (- (cadr (cdr c)) (cadr pt)))
              dist (distance pt (cdr c))
              perp (abs (- (* (cos r) (cadr v)) (* (sin r) (car v)))))
        (if (<= dist *JB:CAP-DIST*)
          (setq pairs (cons (list (+ dist (* 5.0 perp)) e c) pairs))))))
  (setq pairs (vl-sort pairs '(lambda (a b) (< (car a) (car b)))))
  (foreach pr pairs
    (if (and (not (member (cadr pr) used-t)) (not (member (car (caddr pr)) used-c)))
      (progn
        (setq used-t (cons (cadr pr) used-t)
              used-c (cons (car (caddr pr)) used-c)
              m      (cdr (caddr pr))
              st     nil)
        ;; 캡 -> 공급관 -> 가지 전체
        (foreach q pinfo (if (and (null st) (jb:endsnear (caddr q) m)) (setq st q)))
        (if st
          (progn
            (setq br (jb:branch st pinfo) l210 0.0 lt 0.0)
            (foreach q br
              (setq lt (+ lt (nth 4 q)))
              (if (= (cadddr q) *JB:IN-COL*) (setq l210 (+ l210 (nth 4 q)))))
            (if (vl-some '(lambda (q) (member (car q) aff)) br)
              (progn
                ;; 가지 길이의 절반 이상이 210 이면 210, 아니면 ByLayer
                (jb:setcol (cadr pr) (if (and (> lt 0.0) (>= (* 2.0 l210) lt)) *JB:IN-COL* 256))
                (setq n (1+ n))
                (if (not (member *JB:LAY-NAME63* lays)) (setq lays (cons *JB:LAY-NAME63* lays))))))))))
  ;; 주관로 관로명 : 가장 가까운 신설관 색상을 따름
  (if (setq ss (ssget "_X" (list '(0 . "TEXT,MTEXT") (cons 8 *JB:LAY-NAME*) '(410 . "Model"))))
    (repeat (setq i (sslength ss))
      (setq e  (ssname ss (setq i (1- i)))
            ed (entget e)
            pt (jb:pt (if (= (jb:dxf 0 ed) "MTEXT") (jb:dxf 10 ed) (qc:txtpt ed)))
            best nil bd *JB:NAME-DIST*)
      (foreach q pinfo
        (if (<= (setq d (jb:pldist pt (caddr q))) bd) (setq best q bd d)))
      (if (and best (member (car best) aff))
        (progn
          (jb:setcol e (if (= (cadddr best) *JB:IN-COL*) *JB:IN-COL* 256))
          (setq n (1+ n))
          (if (not (member *JB:LAY-NAME* lays)) (setq lays (cons *JB:LAY-NAME* lays)))))))
  (list n lays)
)

;; 폴리선 전역 폭 지정. LINE 은 같은 속성의 2점 폴리선으로 바꿈
(defun jb:setwidth (e ed w / r has43)
  (cond
    ((= (jb:dxf 0 ed) "LWPOLYLINE")
     (foreach p ed
       (cond
         ((member (car p) '(40 41)) (setq r (cons (cons (car p) w) r)))
         ((= (car p) 43) (setq r (cons (cons 43 w) r) has43 T))
         ((= (car p) 70)
          (setq r (cons p r))
          (if (not (assoc 43 ed)) (setq r (cons (cons 43 w) r))))
         (T (setq r (cons p r)))))
     (entmod (reverse r)))
    ((= (jb:dxf 0 ed) "LINE")
     (if (entmake
           (append
             (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity"))
             (vl-remove-if-not '(lambda (p) (member (car p) '(8 6 48 62 370 420))) ed)
             (list '(100 . "AcDbPolyline") '(90 . 2) '(70 . 0) (cons 43 w)
                   (list 10 (car (jb:dxf 10 ed)) (cadr (jb:dxf 10 ed)))
                   (list 10 (car (jb:dxf 11 ed)) (cadr (jb:dxf 11 ed))))))
       (progn (entdel e) T))))
)

;;; ---------------- 구역 판정 (도로·도시계획·하천) ----------------
;; p 에서 ang 방향으로 최대폭 거리 안의 가장 가까운 구역선까지 거리
;; p 에서 ang 방향으로 최대폭 거리 안의 가장 가까운 구역선 -> (거리 . 선 번호)
;;  구역선 세그먼트는 (p1 p2 bulge 선번호) - 선번호는 같은 선(중복 작도 포함)이면 같음
(defun jb:rayhit (p ang segs / rs best f1 f2 d)
  (setq rs (list p (polar p ang *JB:ZONE-MAXW*) 0.0))
  (foreach s segs
    (if (jb:boxhit (jb:segbox rs) (jb:segbox s))
      (foreach x (jb:cand rs s)
        (setq f1 (jb:frac rs x) f2 (jb:frac s x))
        (if (and (jb:in01 f1) (jb:in01 f2))
          (progn
            (setq d (distance p x))
            (if (or (null best) (< d (car best))) (setq best (cons d (cadddr s)))))))))
  best
)

;; 점 p 가 구역 안인지 : 한 방향(0/45/90/135도) 양쪽에서 같은 레이어의 "서로 다른" 구역선이
;; 걸리고 그 폭이 최대폭 이하이면 구역 안 -> 레이어명 반환, 아니면 nil
;; (굽은 경계선 안쪽에서 같은 선에 두 번 걸리는 경우는 구역 밖으로 봄.
;;  접도구역 등 여러 겹이어도 가장 바깥 경계 기준이 됨)
(defun jb:inzone (p zl / res h1 h2)
  (foreach z zl
    (foreach ang (list 0.0 (/ pi 4.0) (/ pi 2.0) (* 0.75 pi))
      (if (null res)
        (progn
          (setq h1 (jb:rayhit p ang (cdr z)) h2 nil)
          (if h1 (setq h2 (jb:rayhit p (+ ang pi) (cdr z))))
          (if (and h1 h2
                   (/= (cdr h1) (cdr h2))
                   (<= (+ (car h1) (car h2)) *JB:ZONE-MAXW*))
            (setq res (car z)))))))
  res
)

;; 구역선 객체의 선번호 : 같은 꼭짓점(정·역방향, 0.01 이내)이면 앞서 나온 선과 같은 번호
;;  zkeys : ((점목록 . 번호) ...) 전역 누적, 반환 번호
(defun jb:zoneid (ed / pts r k)
  (setq pts (mapcar 'jb:pt (jb:verts ed)))
  (foreach z *JB:ZKEYS*
    (if (and (null r) (= (length (car z)) (length pts))
             (or (vl-every '(lambda (a b) (< (distance a b) 0.01)) (car z) pts)
                 (vl-every '(lambda (a b) (< (distance a b) 0.01)) (car z) (reverse pts))))
      (setq r (cdr z))))
  (if (null r)
    (setq r (1+ (length *JB:ZKEYS*)) *JB:ZKEYS* (cons (cons pts r) *JB:ZKEYS*)))
  r
)

;;; ---------------- 210 대상 확인 ----------------
;; 관경별 길이 요약 "315mm 61.0m, 63mm 12.9m"
(defun jb:sumlen (lst / r ed k l a)
  (foreach x lst
    (if (setq ed (entget x))
      (progn
        (setq k (cdr (hg:diakey (jb:dxf 8 ed))) l (qc:len (jb:verts ed)))
        (if (setq a (assoc k r))
          (setq r (subst (cons k (+ l (cdr a))) a r))
          (setq r (cons (cons k l) r))))))
  (if r (hg:join (mapcar '(lambda (a) (strcat (car a) " " (rtos (cdr a) 2 1) "m")) (reverse r)) ", ") "없음")
)

(defun jb:hl (lst mode) (foreach x lst (if (entget x) (redraw x mode))))

;; a : 210 후보, z : 구역 안이라 제외된 후보 -> 사용자가 확정한 210 목록 반환
(defun jb:confirm (a z / ans ss i e done)
  (while (not done)
    (jb:hl z 4)
    (jb:hl a 3)
    (princ (strcat "\n\n[허가구간 확인] 색상 " (itoa *JB:IN-COL*) " 대상 " (itoa (length a)) "개 : " (jb:sumlen a)))
    (if z (princ (strcat "\n  구역(도로·하천·도시계획) 안이라 제외 " (itoa (length z)) "개 : " (jb:sumlen z))))
    (princ "\n  화면에 강조된 선이 색상이 바뀔 신설관입니다.")
    (if *JB:USE-ZONE*
      (progn
        (initget "Yes Add Remove Zone View")
        (setq ans (getkword "\n포함 여부 [확인(Y)/추가(A)/제외(R)/구역포함(Z)/구역보기(V)] <확인>: ")))
      (progn
        (initget "Yes Add Remove")
        (setq ans (getkword "\n포함 여부 [확인(Y)/추가(A)/제외(R)] <확인>: "))))
    (cond
      ((or (null ans) (= ans "Yes")) (setq done T))
      ((= ans "Add")
       (princ "\n추가할 신설관 선택: ")
       (if (setq ss (ssget (list '(0 . "LWPOLYLINE,LINE") (cons 8 *JB:LAY-PIPE*))))
         (repeat (setq i (sslength ss))
           (setq e (ssname ss (setq i (1- i))))
           (if (not (member e a)) (setq a (cons e a)))
           (setq z (vl-remove e z)))))
      ((= ans "Remove")
       (princ "\n제외할 신설관 선택: ")
       (if (setq ss (ssget (list '(0 . "LWPOLYLINE,LINE") (cons 8 *JB:LAY-PIPE*))))
         (repeat (setq i (sslength ss))
           (setq e (ssname ss (setq i (1- i))))
           (jb:hl (list e) 4)
           (setq a (vl-remove e a)))))
      ((= ans "Zone")
       (foreach e z (if (not (member e a)) (setq a (cons e a))))
       (setq z nil))
      ((= ans "View")
       (jb:hl a 4)
       (jb:hl z 3)
       (getstring "\n강조된 선은 구역 안이라 제외된 신설관입니다. Enter 로 돌아가기: "))))
  (jb:hl a 4)
  (jb:hl z 4)
  a
)

;; 허가 색상 대상 : 닫힌 지적 안 + 구역 밖
(defun jb:permit-p (p polys zl)
  (and p
       (vl-some '(lambda (pl) (jb:inpoly p pl)) polys)
       (not (jb:inzone p zl)))
)

;;; ---------------- 평면도 틀에 잘린 지적 닫기 ----------------
;; 열린 지적 폴리선 점 목록 (호는 8등분, 닫지 않음)
(defun jb:polyopen (ed / res k)
  (foreach s (jb:segs (jb:verts ed) nil)
    (setq res (cons (car s) res))
    (if (jb:isarc s)
      (progn (setq k 1)
             (repeat 7 (setq res (cons (jb:ptat s (/ k 8.0)) res) k (1+ k))))))
  (if res (setq res (cons (last (mapcar 'jb:pt (jb:verts ed))) res)))
  (reverse res)
)

;; 사각 틀 경계까지 거리
(defun hg:ondist (p b)
  (min (abs (- (car p) (car (car b)))) (abs (- (car p) (car (cadr b))))
       (abs (- (cadr p) (cadr (car b)))) (abs (- (cadr p) (cadr (cadr b)))))
)

;; 틀 둘레 위치 (좌하단에서 반시계 : 아래변 -> 오른변 -> 윗변 -> 왼변)
(defun hg:perim (p b / x0 y0 x1 y1 w h db dr dt dl m)
  (setq x0 (car (car b)) y0 (cadr (car b)) x1 (car (cadr b)) y1 (cadr (cadr b))
        w (- x1 x0) h (- y1 y0)
        db (abs (- (cadr p) y0)) dr (abs (- (car p) x1))
        dt (abs (- (cadr p) y1)) dl (abs (- (car p) x0))
        m (min db dr dt dl))
  (cond ((= m db) (- (car p) x0))
        ((= m dr) (+ w (- (cadr p) y0)))
        ((= m dt) (+ w h (- x1 (car p))))
        (T (+ w h w (- y1 (cadr p)))))
)

(defun hg:parea (pl / a p q)
  (setq a 0.0 p (last pl))
  (foreach q pl (setq a (+ a (- (* (car p) (cadr q)) (* (car q) (cadr p)))) p q))
  (abs (/ a 2.0))
)

;; 여러 열린 지적선(양 끝이 틀 위)을 틀 경계와 이어 면을 추적
;;  lines : 점 목록들, i : 시작 선, dir : 1 = 반시계(둘레 증가), -1 = 시계
;;  반환 (다각형 점목록 . 사용한 선 번호목록) 또는 nil
(defun hg:trace (lines b i dir / x0 y0 x1 y1 w h per cs ends cur ring used n k j best bd d pos jend done cnt)
  (setq x0 (car (car b)) y0 (cadr (car b)) x1 (car (cadr b)) y1 (cadr (cadr b))
        w (- x1 x0) h (- y1 y0) per (* 2.0 (+ w h))
        cs (list (cons w (list x1 y0)) (cons (+ w h) (list x1 y1))
                 (cons (+ w h w) (list x0 y1)) (cons 0.0 (list x0 y0)))
        n (length lines) k 0 ends nil)
  ;; 끝점 목록 (둘레위치 선번호 'S/'E)
  (foreach ln lines
    (setq ends (cons (list (hg:perim (car ln) b) k 'S) (cons (list (hg:perim (last ln) b) k 'E) ends))
          k (1+ k)))
  (defun hg:dd (from to) ; dir 방향으로 from -> to 거리
    (setq d (* dir (- to from)))
    (while (< d 0.0) (setq d (+ d per)))
    (while (>= d per) (setq d (- d per)))
    d)
  (setq ring (nth i lines) used (list i) cur (hg:perim (last (nth i lines)) b) cnt 0)
  (while (and (not done) (< cnt (* 2 (1+ n))))
    (setq cnt (1+ cnt) best nil bd nil)
    (foreach en ends
      (setq d (hg:dd cur (car en)))
      (if (and (> d 1e-9) (or (null bd) (< d bd))) (setq best en bd d)))
    (if (null best)
      (setq done 'fail)
      (progn
        ;; 지나가는 모서리
        (foreach c (vl-sort (vl-remove-if-not '(lambda (c) (< 1e-9 (hg:dd cur (car c)) bd)) cs)
                            '(lambda (a z) (< (hg:dd cur (car a)) (hg:dd cur (car z)))))
          (setq ring (append ring (list (cdr c)))))
        (setq j (cadr best) jend (caddr best))
        (if (and (= j i) (eq jend 'S))
          (setq done T)
          (progn
            (setq ring (append ring (if (eq jend 'S) (nth j lines) (reverse (nth j lines))))
                  used (if (member j used) used (cons j used))
                  cur  (hg:perim (if (eq jend 'S) (last (nth j lines)) (car (nth j lines))) b)))))))
  (if (eq done T) (cons ring used))
)

;; 선택한 열린 지적선들로 필지 다각형 만들기 (틀에 잘려 여러 선으로 나뉜 필지 포함)
;;  각 선의 양방향 면 중 선택한 선을 가장 많이 품은 면(같으면 작은 면)을 필지로 사용
(defun hg:clipfaces (lines b / res covered i f1 f2 s1 s2 pick)
  (setq i 0)
  (foreach ln lines
    (if (not (member i covered))
      (progn
        (setq f1 (hg:trace lines b i 1) f2 (hg:trace lines b i -1))
        (setq s1 (if f1 (length (cdr f1)) -1) s2 (if f2 (length (cdr f2)) -1))
        (setq pick (cond ((> s1 s2) f1)
                         ((> s2 s1) f2)
                         ((and f1 f2) (if (<= (hg:parea (car f1)) (hg:parea (car f2))) f1 f2))
                         (T (or f1 f2))))
        (if pick
          (setq res (cons (car pick) res) covered (append (cdr pick) covered)))))
    (setq i (1+ i)))
  res
)

;; 다각형 안 지번 글자 -> 지번 이름 (없으면 nil, 여러 개면 "/(확인필요)")
(defun hg:lotname (pl / ss i ed pt nm in)
  (if (setq ss (ssget "_X" (list '(0 . "TEXT,MTEXT") (cons 8 *HG:LAY-JIBUN*) '(410 . "Model"))))
    (repeat (setq i (sslength ss))
      (setq ed (entget (ssname ss (setq i (1- i))))
            pt (jb:pt (if (= (qc:dxf 0 ed) "MTEXT") (qc:dxf 10 ed) (qc:txtpt ed)))
            nm (hg:trim (qc:dxf 1 ed)))
      (if (and (jb:inpoly pt pl) (not (member nm in))) (setq in (cons nm in)))))
  (cond ((null in) nil)
        ((= (length in) 1) (car in))
        (T (strcat (hg:join in "/") "(확인필요)")))
)

;; 열린 지적 pts 가 양 끝이 평면도 틀(b) 위에 있으면 틀 경계를 따라 닫은 다각형 반환
;; (두 방향 중 면적이 작은 쪽 = 잘린 필지). 시작=끝이면 그대로 닫음. 아니면 nil
(defun hg:closeclip (pts b / x0 y0 x1 y1 w h per cs ts te dts cw ccw p1 p2 d)
  (cond
    ((or (null pts) (< (length pts) 3)) nil)
    ((< (distance (car pts) (last pts)) 0.01) pts)
    ((and b (<= (hg:ondist (car pts) b) 0.5) (<= (hg:ondist (last pts) b) 0.5))
     (setq x0 (car (car b)) y0 (cadr (car b)) x1 (car (cadr b)) y1 (cadr (cadr b))
           w (- x1 x0) h (- y1 y0) per (* 2.0 (+ w h))
           cs (list (cons w (list x1 y0)) (cons (+ w h) (list x1 y1))
                    (cons (+ w h w) (list x0 y1)) (cons per (list x0 y0)))
           ts (hg:perim (car pts) b) te (hg:perim (last pts) b))
     (defun hg:md (x) (setq x (- x te)) (while (< x 0.0) (setq x (+ x per))) (while (>= x per) (setq x (- x per))) x)
     (setq dts (hg:md ts))
     (foreach c cs
       (setq d (hg:md (car c)))
       (if (and (> d 1e-9) (< d dts)) (setq ccw (cons (cons d (cdr c)) ccw)))
       (if (> d dts) (setq cw (cons (cons d (cdr c)) cw))))
     (setq p1 (append pts (mapcar 'cdr (vl-sort ccw '(lambda (a b) (< (car a) (car b))))))
           p2 (append pts (mapcar 'cdr (vl-sort cw '(lambda (a b) (> (car a) (car b)))))))
     (if (<= (hg:parea p1) (hg:parea p2)) p1 p2))
    (T nil))
)

(defun jb:setcol (e col / ed r)
  (setq ed (entget e))
  (foreach p ed
    (cond
      ((member (car p) '(62 420 430)))
      ((= (car p) 8) (setq r (cons (cons 62 col) (cons p r))))
      (T (setq r (cons p r)))))
  (entmod (reverse r))
)

;;; ==========================================================================
(defun c:HG1BRK (/ *error* ce ss i ed bsegs bbox pipes e pbox s np nc k polys ni p lay lays nu
                   newp aff pinfo nm v x nw zbox zl nz zss nzu cpb cfr cpl nclip clines zid
                   pool sel210 selz)
  (defun *error* (m)
    (if (not (wcmatch (strcase m) "*CANCEL*,*QUIT*,*BREAK*,*취소*"))
      (princ (strcat "\n오류: " m)))
    (hg0:clear)
    (command-s "_.UNDO" "_E")
    (if ce (setvar "CMDECHO" ce))
    (princ)
  )
  (setq ce (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)

  (princ "\n지적 객체 선택: ")
  (if (null (setq ss (if *HG0* *HG0-SS* (ssget (list '(0 . "LWPOLYLINE,LINE") (cons 8 *JB:LAY-JIJUK*))))))
    (progn (princ "\n선택된 지적 객체가 없습니다.") (exit)))

  ;; 선택 지적이 들어 있는 평면도 틀 (틀에 잘려 열린 지적을 닫는 데 사용)
  (setq ed (entget (ssname ss 0))
        cpb (if (setq cfr (hg:findframe (jb:pt (car (jb:verts ed))))) (hg:planbox (car cfr)))
        nclip 0)

  ;; 지적 세그먼트
  (repeat (setq i (sslength ss))
    (setq ed (entget (ssname ss (setq i (1- i)))))
    (cond
      ((jb:closed-p ed) (setq polys (cons (jb:poly ed) polys)))
      ((and (= (jb:dxf 0 ed) "LWPOLYLINE") (setq cpl (jb:polyopen ed)))
       (cond
         ((< (distance (car cpl) (last cpl)) 0.01) (setq polys (cons cpl polys)))
         ((and cpb (<= (hg:ondist (car cpl) cpb) 0.5) (<= (hg:ondist (last cpl) cpb) 0.5))
          (setq clines (cons cpl clines))))))
    (foreach s (jb:segs (jb:verts ed) (jb:closed-p ed))
      (setq bsegs (cons s bsegs)
            bbox  (jb:boxu bbox (jb:segbox s)))))

  ;; 구역선 (도로구역·도시계획·하천구역) : 판정용 + 선택 지적 범위 안은 절단 경계로도 사용
  ;; (*JB:USE-ZONE* 가 nil 이면 이 단계를 통째로 건너뜀 -> zl 이 비어 구역 판정/구역선 절단 없음)
  (setq zbox (qc:grow bbox *JB:ZONE-MAXW*) zl nil nz 0 *JB:ZKEYS* nil)
  (if (and *JB:USE-ZONE*
           (setq zss (ssget "_X" (list '(0 . "LWPOLYLINE,LINE") (cons 8 *JB:LAY-ZONE*) '(410 . "Model")))))
    (repeat (setq i (sslength zss))
      (setq ed (entget (ssname zss (setq i (1- i)))) lay (jb:dxf 8 ed) zid nil)
      (foreach s (jb:segs (jb:verts ed) (jb:closed-p ed))
        (if (and (> (distance (car s) (cadr s)) 1e-9) (jb:boxhit (jb:segbox s) zbox))
          (progn
            (if (null zid) (setq zid (jb:zoneid ed)))
            (setq s (append s (list zid)))
            (if (assoc lay zl)
              (setq zl (subst (cons lay (cons s (cdr (assoc lay zl)))) (assoc lay zl) zl))
              (setq zl (cons (list lay s) zl)))
            (if (jb:boxhit (jb:segbox s) bbox)
              (setq bsegs (cons s bsegs) nz (1+ nz))))))))
  (if zl (princ (strcat "\n구역선 레이어: " (hg:join (mapcar 'car zl) ", "))))

  ;; 평면도 틀에 잘린 열린 지적선들 -> 함께 이어서 필지로 닫기
  (if clines
    (foreach pl (hg:clipfaces (reverse clines) cpb)
      (setq polys (cons pl polys) nclip (1+ nclip))))
  ;; 선택 필지를 HG3 지번 집계에서 우선 사용하도록 기억 : ((지번 면적 다각형) ...)
  (setq *HG:SELLOTS* (mapcar '(lambda (pl) (list (hg:lotname pl) (hg:parea pl) pl)) polys))

  (hg0:undo "_BE")

  ;; 선택한 지적 두께 적용 (선은 폴리선으로 변환)
  (setq nw 0)
  (repeat (setq i (sslength ss))
    (setq e (ssname ss (setq i (1- i))) ed (entget e))
    (if (jb:setwidth e ed *JB:JJ-WIDTH*) (setq nw (1+ nw))))

  ;; 신설관 후보
  (if (setq ss (ssget "_X" (list '(0 . "LWPOLYLINE,LINE") (cons 8 *JB:LAY-PIPE*) '(410 . "Model"))))
    (repeat (setq i (sslength ss))
      (setq e (ssname ss (setq i (1- i))) ed (entget e) pbox nil)
      (if (and (not (jb:closed-p ed))
               (not (and *JB:SKIP-HIDDEN* (jb:hidden-p ed))))
        (progn
          (foreach s (jb:segs (jb:verts ed) nil) (setq pbox (jb:boxu pbox (jb:segbox s))))
          (if (jb:boxhit pbox bbox) (setq pipes (cons e pipes)))))))

  ;; 끊기
  (setq np 0 nc 0 ni 0)
  (foreach e pipes
    (if (setq k (jb:dopipe e bsegs))
      (setq np (1+ np) nc (+ nc (1- (length k))) newp (append k newp))))

  ;; 판정 대상 : 끊은 조각 + 끊기지 않았지만 선택 지적 안에 있는 신설관
  ;; (처음부터 지적 안에 있거나, 관 끝이 경계에 닿아 끊지 않은 경우)
  (setq pool newp sel210 nil selz nil)
  (foreach e pipes
    (if (and (setq ed (entget e))
             (setq p (jb:midpt ed))
             (vl-some '(lambda (pl) (jb:inpoly p pl)) polys))
      (setq pool (cons e pool))))
  ;; 지적 안 + 구역 밖 = 210 후보, 지적 안 + 구역 안 = 제외 후보
  (foreach x pool
    (setq p (jb:midpt (entget x)))
    (if (and p (vl-some '(lambda (pl) (jb:inpoly p pl)) polys))
      (if (jb:inzone p zl) (setq selz (cons x selz)) (setq sel210 (cons x sel210)))))

  ;; 사용자 확인 (강조 표시 후 추가/제외/구역포함)
  (if *JB:CONFIRM* (setq sel210 (jb:confirm sel210 selz)))

  ;; 색상 적용 : 확정된 대상 210, 나머지 판정 대상 ByLayer
  (setq nu 0 nzu 0)
  (foreach x pool
    (if (member x sel210)
      (progn (jb:setcol x *JB:IN-COL*) (setq ni (1+ ni)) (if (not (member x newp)) (setq nu (1+ nu))))
      (progn (jb:setcol x 256) (if (member x selz) (setq nzu (1+ nzu)))))
    (if (not (member (setq lay (jb:dxf 8 (entget x))) lays)) (setq lays (cons lay lays))))
  ;; 사용자가 직접 추가한 신설관
  (foreach x sel210
    (if (not (member x pool))
      (progn
        (jb:setcol x *JB:IN-COL*) (setq ni (1+ ni) nu (1+ nu))
        (if (not (member (setq lay (jb:dxf 8 (entget x))) lays)) (setq lays (cons lay lays))))))
  ;; 관로명 색상 (이번에 처리한 신설관과 연결된 것만)
  (setq aff (append newp (vl-remove-if-not 'entget pipes)) pinfo nil)
  (if (setq ss (ssget "_X" (list '(0 . "LWPOLYLINE,LINE") (cons 8 *JB:LAY-PIPE*) '(410 . "Model"))))
    (repeat (setq i (sslength ss))
      (setq e (ssname ss (setq i (1- i))) ed (entget e))
      (if (and (not (jb:closed-p ed)) (not (and *JB:SKIP-HIDDEN* (jb:hidden-p ed))))
        (progn
          (setq v (jb:verts ed))
          (setq pinfo (cons (list e (jb:dxf 8 ed) (mapcar 'jb:pt v)
                                  (cond ((jb:dxf 62 ed)) (256)) (qc:len v))
                            pinfo))))))
  (setq nm (jb:donames aff pinfo))
  (foreach x (cadr nm) (if (not (member x lays)) (setq lays (cons x lays))))
  ;; 레이어 자체 색상 변경 (꺼짐 상태 유지)
  ;; 모든 신설관 레이어 + 색상을 맞춘 관로명 레이어
  (setq x (tblnext "LAYER" T))
  (while x
    (if (and (wcmatch (strcase (cdr (assoc 2 x))) (strcase *JB:LAY-PIPE*))
             (not (member (cdr (assoc 2 x)) lays)))
      (setq lays (cons (cdr (assoc 2 x)) lays)))
    (setq x (tblnext "LAYER")))
  (foreach lay lays (jb:laycol lay *JB:LAY-COL*))

  (princ (strcat "\n완료: 신설관 " (itoa np) "개를 " (itoa nc) "곳에서 끊었습니다."
                 "\n색상 " (itoa *JB:IN-COL*) " : " (itoa ni) "개 (그중 끊지 않은 관 " (itoa nu) "개)"
                 (if (> nzu 0) (strcat "\n구역(도로·하천·도시계획) 안이라 제외 : " (itoa nzu) "개") "")
                 "\n관로명 " (itoa (car nm)) "개 색상 맞춤"
                 "\n지적 " (itoa nw) "개 두께 " (rtos *JB:JJ-WIDTH* 2 2) " 적용"
                 (if (> nclip 0) (strcat "\n평면도 틀에 잘린 열린 지적으로 필지 " (itoa nclip) "개를 틀 경계와 이어 닫음") "")
                 (if lays (strcat "\n레이어 색상 " (itoa *JB:LAY-COL*) " 변경: "
                                  (apply 'strcat (mapcar '(lambda (x) (strcat "[" x "] ")) lays)))
                     "")))
  (hg0:undo "_E")
  (setvar "CMDECHO" ce)
  (princ)
)

;;; ##########################################################################
;;;  [2] HG2PRF - 허가구간 종단 반영
;;; ##########################################################################

;;; ---------------- 설정 ----------------
(setq *QC:LAY-PIPE*  "신설관*")          ; 평면 신설관 레이어(와일드카드)
(setq *QC:LAY-QPIPE* "Q-종단가스관로")   ; 종단 관로
(setq *QC:LAY-GAS*   "도시가스관로")     ; 종단 관로 부속 표기
(setq *QC:LAY-GRAPH* "Q-종단그래프")     ; 종단 그래프(수직선)
(setq *QC:LAY-QSTA*  "Q-종단측점")       ; 종단 측점 글자
(setq *QC:HIDDEN*    "*HIDDEN*")         ; 제외할 선종류
(setq *QC:STA-INT*   20.0)               ; 측점 간격(m)
(setq *QC:STA-TXTD*  10.0)               ; 평면 측점 글자 - 주관로 최대 거리
(setq *QC:ACI*       250)                ; 검은색 ACI (트루컬러 대체값)
(setq *QC:TRUE*      0)                  ; 트루컬러 RGB(0,0,0). nil 이면 ACI만 사용
(setq *QC:TOL*       0.05)               ; 평면 끝점 연결 허용오차
(setq *QC:LAY-NEW*   "0허가도면")        ; 새로 그리는 객체 레이어
(setq *QC:NEW-COL*   211)                ; 새로 그리는 문구 색상
(setq *QC:NEW-COL-G* 7)                  ; 새로 그리는 선/화살표 색상 (7 = 흰색)
(setq *QC:BAND-TXT*  "허가구간")         ; 밴드 위 문구
(setq *QC:BAND-OFS*  5.0)                ; 기존 관경밴드 대비 위로 띄우는 거리 (0 = 같은 줄)
(setq *QC:ARW-L*     2.236)              ; 화살표 길이
(setq *QC:ARW-H*     0.671)              ; 화살표 높이
(setq *QC:TXT-H*     1.4)                ; 문구 높이(기존 밴드 문구를 못 찾을 때)

;;; ---------------- 기본 유틸 ----------------
(defun qc:dxf (c ed) (cdr (assoc c ed)))
(defun qc:pt (v) (list (car v) (cadr v)))

(defun qc:bbox (pts / x1 y1 x2 y2)
  (setq x1 (apply 'min (mapcar 'car pts))  y1 (apply 'min (mapcar 'cadr pts))
        x2 (apply 'max (mapcar 'car pts))  y2 (apply 'max (mapcar 'cadr pts)))
  (list (list x1 y1) (list x2 y2))
)

(defun qc:inbox (p b)
  (and p b
       (>= (car p) (car (car b)))  (<= (car p) (car (cadr b)))
       (>= (cadr p) (cadr (car b))) (<= (cadr p) (cadr (cadr b))))
)

(defun qc:grow (b d)
  (list (list (- (car (car b)) d) (- (cadr (car b)) d))
        (list (+ (car (cadr b)) d) (+ (cadr (cadr b)) d)))
)

(defun qc:nospace (s / r i ch)
  (setq r "" i 1)
  (repeat (strlen s)
    (setq ch (substr s i 1) i (1+ i))
    (if (/= ch " ") (setq r (strcat r ch))))
  r
)

;; "NO.3" -> 3 , 그 외 nil
(defun qc:stano (s / u)
  (setq u (strcase (qc:nospace s)))
  (if (wcmatch u "NO.#,NO.##,NO.###") (atoi (substr u 4)))
)

;; TEXT 정렬점
(defun qc:txtpt (ed)
  (if (and (= 0 (cond ((qc:dxf 72 ed)) (0))) (= 0 (cond ((qc:dxf 73 ed)) (0))))
    (qc:dxf 10 ed)
    (qc:dxf 11 ed))
)

;; 정점 목록 ((x y sw ew bulge) ...)  - LWPOLYLINE / LINE
(defun qc:verts (ed / res v)
  (cond
    ((= (qc:dxf 0 ed) "LINE")
     (list (list (car (qc:dxf 10 ed)) (cadr (qc:dxf 10 ed)) 0.0 0.0 0.0)
           (list (car (qc:dxf 11 ed)) (cadr (qc:dxf 11 ed)) 0.0 0.0 0.0)))
    ((= (qc:dxf 0 ed) "LWPOLYLINE")
     (foreach p ed
       (cond
         ((= (car p) 10)
          (if v (setq res (cons v res)))
          (setq v (list (cadr p) (caddr p) 0.0 0.0 0.0)))
         ((and v (= (car p) 40)) (setq v (list (car v) (cadr v) (cdr p) (cadddr v) (nth 4 v))))
         ((and v (= (car p) 41)) (setq v (list (car v) (cadr v) (caddr v) (cdr p) (nth 4 v))))
         ((and v (= (car p) 42)) (setq v (list (car v) (cadr v) (caddr v) (cadddr v) (cdr p))))))
     (if v (setq res (cons v res)))
     (reverse res)))
)

;; 객체 대표점들
(defun qc:entpts (ed / ty)
  (setq ty (qc:dxf 0 ed))
  (cond
    ((member ty '("LINE" "LWPOLYLINE")) (mapcar 'qc:pt (qc:verts ed)))
    ((= ty "TEXT") (list (qc:pt (qc:txtpt ed))))
    ((qc:dxf 10 ed) (list (qc:pt (qc:dxf 10 ed)))))
)

;; 세그먼트 길이 (bulge 고려)
(defun qc:seglen (p1 p2 b / c th)
  (setq c (distance p1 p2))
  (if (or (null b) (equal b 0.0 1e-9))
    c
    (progn
      (setq th (* 4.0 (atan (abs b))))
      (/ (* c th) (* 2.0 (sin (/ th 2.0))))))
)

(defun qc:len (vs / l)
  (setq l 0.0)
  (while (cdr vs)
    (setq l  (+ l (qc:seglen (qc:pt (car vs)) (qc:pt (cadr vs)) (nth 4 (car vs))))
          vs (cdr vs)))
  l
)

;; pts 첫 점(끝점) 방향으로 나가는 벡터 (중복점 건너뜀)
(defun qc:dir (pts / a)
  (setq a (car pts) pts (cdr pts))
  (while (and pts (< (distance a (car pts)) 1e-6)) (setq pts (cdr pts)))
  (if pts (list (- (car a) (car (car pts))) (- (cadr a) (cadr (car pts)))))
)

(defun qc:cos (a b / la lb)
  (if (and a b)
    (progn
      (setq la (sqrt (+ (* (car a) (car a)) (* (cadr a) (cadr a))))
            lb (sqrt (+ (* (car b) (car b)) (* (cadr b) (cadr b)))))
      (if (and (> la 1e-9) (> lb 1e-9))
        (/ (+ (* (car a) (car b)) (* (cadr a) (cadr b))) (* la lb))
        -2.0))
    -2.0)
)

(defun qc:neg (v) (if v (list (- (car v)) (- (cadr v)))))

;; 숨은선/꺼진·동결 레이어 여부
(defun qc:hidden-p (ed / la lt)
  (setq la (tblsearch "LAYER" (qc:dxf 8 ed))
        lt (qc:dxf 6 ed))
  (if (or (null lt) (= (strcase lt) "BYLAYER")) (setq lt (qc:dxf 6 la)))
  (or (and lt (wcmatch (strcase lt) *QC:HIDDEN*))
      (minusp (qc:dxf 62 la))
      (= 1 (logand 1 (qc:dxf 70 la))))
)

;;; ---------------- 도곽(FORM) ----------------
(defun qc:blkext (nm / e ed pts)
  (setq e (tblobjname "BLOCK" nm))
  (while (setq e (entnext e))
    (setq ed (entget e))
    (cond
      ((= (qc:dxf 0 ed) "LINE")
       (setq pts (cons (qc:pt (qc:dxf 10 ed)) (cons (qc:pt (qc:dxf 11 ed)) pts))))
      ((= (qc:dxf 0 ed) "LWPOLYLINE")
       (foreach v (qc:verts ed) (setq pts (cons (qc:pt v) pts))))))
  (if pts (qc:bbox pts))
)

(defun qc:formboxes (/ ss i ed nm ext bp ins sx sy r res crn)
  (if (setq ss (ssget "_X" '((0 . "INSERT") (2 . "FORM*") (410 . "Model"))))
    (repeat (setq i (sslength ss))
      (setq ed (entget (ssname ss (setq i (1- i))))
            nm (qc:dxf 2 ed))
      (if (setq ext (qc:blkext nm))
        (progn
          (setq bp  (qc:dxf 10 (tblsearch "BLOCK" nm))
                ins (qc:dxf 10 ed)
                sx  (cond ((qc:dxf 41 ed)) (1.0))
                sy  (cond ((qc:dxf 42 ed)) (1.0))
                r   (cond ((qc:dxf 50 ed)) (0.0)))
          (setq crn
            (mapcar
              '(lambda (p / x y)
                 (setq x (* (- (car p) (car bp)) sx)
                       y (* (- (cadr p) (cadr bp)) sy))
                 (list (+ (car ins) (- (* x (cos r)) (* y (sin r))))
                       (+ (cadr ins) (+ (* x (sin r)) (* y (cos r))))))
              (list (car ext) (cadr ext)
                    (list (car (car ext)) (cadr (cadr ext)))
                    (list (car (cadr ext)) (cadr (car ext))))))
          (setq res (cons (qc:bbox crn) res))))))
  res
)

;; 필터로 모형공간 객체 수집 (box 안 대표점 기준)
(defun qc:collect (flt box / ss i e res p)
  (if (setq ss (ssget "_X" (append flt '((410 . "Model")))))
    (repeat (setq i (sslength ss))
      (setq e (ssname ss (setq i (1- i)))
            p (car (qc:entpts (entget e))))
      (if (or (null box) (qc:inbox p box)) (setq res (cons e res)))))
  res
)

;;; ---------------- 색상 / 객체 생성 ----------------
(defun qc:setcol (ed / r)
  (foreach p ed
    (cond
      ((member (car p) '(62 420 430)))
      ((= (car p) 8)
       (setq r (cons p r))
       (setq r (cons (cons 62 *QC:ACI*) r))
       (if *QC:TRUE* (setq r (cons (cons 420 *QC:TRUE*) r))))
      (T (setq r (cons p r)))))
  (reverse r)
)

;; 원본 속성(형상 제외)
(defun qc:hdr (ed / r)
  (foreach p ed
    (if (not (member (car p) '(-1 330 5 102 360 10 11 40 41 42 90 91 210)))
      (setq r (cons p r))))
  (reverse r)
)

(defun qc:mkpl (ed vs black / r flag cw)
  (setq flag (cond ((qc:dxf 70 ed)) (0)))
  (foreach p (qc:hdr ed)
    (cond
      ((= (car p) 70) (setq r (cons (cons 70 (logand flag 128)) r)))
      (T
       (setq r (cons p r))
       (if (equal p '(100 . "AcDbPolyline")) (setq r (cons (cons 90 (length vs)) r))))))
  (setq r (reverse r))
  (if black (setq r (qc:setcol r)))
  (setq cw (and (qc:dxf 43 ed) (/= 0.0 (qc:dxf 43 ed))))
  (foreach v vs
    (setq r (append r (if cw
                        (list (list 10 (car v) (cadr v)) (cons 42 (nth 4 v)))
                        (list (list 10 (car v) (cadr v))
                              (cons 40 (caddr v)) (cons 41 (cadddr v)) (cons 42 (nth 4 v)))))))
  (if (assoc 210 ed) (setq r (append r (list (assoc 210 ed)))))
  (entmake r)
)

(defun qc:mkln (ed vs black / r z1 z2)
  (setq r  (qc:hdr ed)
        z1 (cond ((caddr (qc:dxf 10 ed))) (0.0))
        z2 (cond ((caddr (qc:dxf 11 ed))) (0.0)))
  (if black (setq r (qc:setcol r)))
  (entmake
    (append r
            (list (list 10 (car (car vs)) (cadr (car vs)) z1)
                  (list 11 (car (cadr vs)) (cadr (cadr vs)) z2))
            (if (assoc 210 ed) (list (assoc 210 ed)))))
)

;;; ---------------- X 기준 분할 ----------------
(defun qc:atcut (x cuts)
  (vl-some '(lambda (c) (equal x c 1e-4)) cuts)
)

;; vs 를 cuts(X값) 위치에서 분할 -> 조각 목록
(defun qc:split (vs cuts / out a b xa xb cs t1 pieces cur)
  (while (cdr vs)
    (setq a (car vs) b (cadr vs) xa (car a) xb (car b))
    (setq out (cons (cons a (qc:atcut xa cuts)) out))
    (if (equal (nth 4 a) 0.0 1e-9)
      (progn
        (setq cs (vl-remove-if-not
                   '(lambda (c) (and (> c (+ (min xa xb) 1e-6)) (< c (- (max xa xb) 1e-6))))
                   cuts))
        (setq cs (if (< xa xb) (vl-sort cs '<) (vl-sort cs '>)))
        (foreach c cs
          (setq t1 (/ (- c xa) (- xb xa)))
          (setq out (cons (cons (list c (+ (cadr a) (* t1 (- (cadr b) (cadr a))))
                                      (caddr a) (caddr a) 0.0)
                                T)
                          out)))))
    (setq vs (cdr vs)))
  (setq out (reverse (cons (cons (car vs) nil) out)))
  (foreach o out
    (setq cur (cons (car o) cur))
    (if (and (cdr o) (cdr cur))
      (setq pieces (cons (reverse cur) pieces)
            cur    (list (car o)))))
  (if (cdr cur) (setq pieces (cons (reverse cur) pieces)))
  (reverse pieces)
)

(defun qc:xin (x rngs)
  (vl-some '(lambda (r) (and (>= x (- (car r) 1e-3)) (<= x (+ (cadr r) 1e-3)))) rngs)
)

(defun qc:pcin (vs rngs / xs)
  (setq xs (mapcar 'car vs))
  (vl-some '(lambda (r) (and (>= (apply 'min xs) (- (car r) 1e-3))
                             (<= (apply 'max xs) (+ (cadr r) 1e-3))))
           rngs)
)

;; 점 p 를 주관로 체인에 투영 -> (거리 . 체인 누적거리)
(defun qc:proj (p chain / best a b dx dy l2 t1 q d s0)
  (foreach c chain
    (setq s0 (cadr c) a nil)
    (foreach b (cadddr c)
      (if a
        (progn
          (setq dx (- (car b) (car a)) dy (- (cadr b) (cadr a)) l2 (+ (* dx dx) (* dy dy)))
          (if (> l2 1e-12)
            (progn
              (setq t1 (max 0.0 (min 1.0 (/ (+ (* (- (car p) (car a)) dx) (* (- (cadr p) (cadr a)) dy)) l2)))
                    q  (list (+ (car a) (* t1 dx)) (+ (cadr a) (* t1 dy)))
                    d  (distance p q))
              (if (or (null best) (< d (car best)))
                (setq best (cons d (+ s0 (* t1 (sqrt l2))))))
              (setq s0 (+ s0 (sqrt l2)))))))
      (setq a b)))
  best
)

;; 측점 표기 "NO.2+12.66"
(defun qc:stastr (s / n)
  (setq n (fix (/ (+ s 1e-6) *QC:STA-INT*)))
  (if (< s 0.0) (setq n (1- n)))
  (strcat "NO." (itoa n) "+" (rtos (- s (* n *QC:STA-INT*)) 2 2))
)

;;; ---------------- 허가구간 밴드 ----------------
;; 문자열을 공백으로 분리
(defun qc:split-sp (s / r w i ch)
  (setq w "" i 1)
  (repeat (strlen s)
    (setq ch (substr s i 1) i (1+ i))
    (if (= ch " ")
      (if (/= w "") (setq r (cons w r) w ""))
      (setq w (strcat w ch))))
  (if (/= w "") (setq r (cons w r)))
  (reverse r)
)

;; "신설관 LP PE 225mm" -> "LP 225mm PE"
(defun qc:diastr (lay / p d m u res)
  (foreach w (qc:split-sp lay)
    (setq u (strcase w))
    (cond
      ((= w "신설관"))
      ((member u '("LP" "MP" "HP")) (setq p w))
      ((and (null d) (wcmatch u "#*MM,#*A")) (setq d w))
      (T (setq m (if m (strcat m " " w) w)))))
  (foreach x (list p d m) (if x (setq res (if res (strcat res " " x) x))))
  (cond (res) (lay))
)

;; info ((레이어 . 길이) ...) -> "LP 110mm PE(5.2m)"
(defun qc:bandlabel (info / agg k res)
  (foreach i info
    (setq k (qc:diastr (car i)))
    (if (assoc k agg)
      (setq agg (subst (cons k (+ (cdr i) (cdr (assoc k agg)))) (assoc k agg) agg))
      (setq agg (cons (cons k (cdr i)) agg))))
  (foreach a (reverse agg)
    (setq k (strcat (car a) "(" (rtos (cdr a) 2 1) "m)")
          res (if res (strcat res ", " k) k)))
  res
)

(defun qc:newlayer ()
  (if (not (tblsearch "LAYER" *QC:LAY-NEW*))
    (entmake (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord") '(100 . "AcDbLayerTableRecord")
                   (cons 2 *QC:LAY-NEW*) '(70 . 0) '(62 . 7) '(6 . "Continuous"))))
)

(defun qc:newhdr (typ)
  (list (cons 0 typ) (cons 8 *QC:LAY-NEW*)
        (cons 62 (if (= typ "TEXT") *QC:NEW-COL* *QC:NEW-COL-G*)))
)

(defun qc:mktxt (str x y h sty)
  (entmake (append (qc:newhdr "TEXT")
                   (list (list 10 x y 0.0) (cons 40 h) (cons 1 str) (cons 7 sty)
                         '(72 . 1) (list 11 x y 0.0) '(73 . 2))))
)

;; 밴드 1개: 수평선 + 양끝 반화살표 + 위/아래 문구
(defun qc:band (xa xb y up dn h sty / al ah xm)
  (setq al (min *QC:ARW-L* (* 0.45 (- xb xa)))
        ah (* al (/ *QC:ARW-H* *QC:ARW-L*))
        xm (/ (+ xa xb) 2.0))
  (entmake (append (qc:newhdr "LINE") (list (list 10 xa y 0.0) (list 11 xb y 0.0))))
  (entmake (append (qc:newhdr "SOLID")
                   (list (list 10 xa y 0.0) (list 11 (+ xa al) (+ y ah) 0.0)
                         (list 12 (+ xa al) y 0.0) (list 13 (+ xa al) y 0.0))))
  (entmake (append (qc:newhdr "SOLID")
                   (list (list 10 xb y 0.0) (list 11 (- xb al) (+ y ah) 0.0)
                         (list 12 (- xb al) y 0.0) (list 13 (- xb al) y 0.0))))
  (qc:mktxt up xm (+ y (* 1.19 h)) h sty)
  (qc:mktxt dn xm (- y (* 1.11 h)) h sty)
)

;;; ==========================================================================
(defun c:HG2PRF (/ *error* ce sel box boxes e ed i cands no0 best d p0 pts
                 chain used s cur fwd vs len endp dir nxt nfwd bc c2 q
                 rngs bad stas k x0 nmin nmax xr cuts parea pcs np ng nv
                 vl cnt basey bv l r top ref n0 tmp b
                 bandy th tsty nb lay dz pmin pmax pnos pnmin cs pr)
  (defun *error* (m)
    (if (not (wcmatch (strcase m) "*CANCEL*,*QUIT*,*BREAK*,*취소*"))
      (princ (strcat "\n오류: " m)))
    (hg0:clear)
    (command-s "_.UNDO" "_E")
    (if ce (setvar "CMDECHO" ce))
    (if dz (setvar "DIMZIN" dz))
    (princ)
  )
  (setq ce (getvar "CMDECHO") dz (getvar "DIMZIN"))
  (setvar "CMDECHO" 0)
  (setvar "DIMZIN" 0)

  (princ "\n분리한 평면 신설관(주관로) 객체 선택: ")
  (setq sel (if *HG0* *HG0-SEL* (ssget (list '(0 . "LWPOLYLINE,LINE") (cons 8 *QC:LAY-PIPE*)))))
  (if (null sel) (progn (princ "\n선택 없음.") (exit)))

  (hg0:undo "_BE")
  (qc:newlayer)

  ;; --- 도곽 판별
  (setq p0 (car (qc:entpts (entget (ssname sel 0)))))
  (foreach b (qc:formboxes) (if (and (null box) (qc:inbox p0 b)) (setq box b)))
  (if (null box) (princ "\n※ FORM 도곽을 찾지 못해 도면 전체를 대상으로 합니다."))

  ;; --- 종단 측점 -> 수평축척
  (foreach e (qc:collect (list '(0 . "TEXT") (cons 8 *QC:LAY-QSTA*)) box)
    (setq ed (entget e))
    (if (setq n0 (qc:stano (qc:dxf 1 ed)))
      (setq stas (cons (cons n0 (car (qc:txtpt ed))) stas))))
  (if (< (length stas) 2)
    (progn (princ "\n종단 측점(NO.n) 글자를 2개 이상 찾지 못했습니다.") (exit)))
  (setq nmin (apply 'min (mapcar 'car stas))
        nmax (apply 'max (mapcar 'car stas)))
  (if (= nmin nmax)
    (progn (princ "\n종단 측점이 하나뿐입니다.") (exit)))
  (setq k  (/ (- (cdr (assoc nmax stas)) (cdr (assoc nmin stas)))
              (* (- nmax nmin) *QC:STA-INT*))
        x0 (- (cdr (assoc nmin stas)) (* nmin *QC:STA-INT* k)))

  ;; --- 종단면도 영역
  (foreach e (qc:collect (list (cons 8 (strcat *QC:LAY-GRAPH* "," *QC:LAY-QPIPE* "," *QC:LAY-QSTA*))) box)
    (setq pts (append (qc:entpts (entget e)) pts)))
  (setq parea (qc:grow (qc:bbox pts) 1.0))

  ;; --- 평면 신설관 후보 (숨은선 제외)
  (foreach e (qc:collect (list '(0 . "LWPOLYLINE,LINE") (cons 8 *QC:LAY-PIPE*)) box)
    (setq ed (entget e))
    (if (not (qc:hidden-p ed))
      (setq cands (cons (list e (mapcar 'qc:pt (qc:verts ed)) ed) cands))))

  ;; --- 평면 측점 글자 (NO.n) : 가장 낮은 번호가 이 도면의 시점
  (setq pnos nil)
  (foreach e (qc:collect '((0 . "TEXT")) box)
    (setq ed (entget e))
    (if (and (setq n0 (qc:stano (qc:dxf 1 ed)))
             (not (qc:inbox (qc:pt (qc:txtpt ed)) parea)))
      (setq pnos (cons (list n0 (qc:pt (qc:txtpt ed))) pnos))))
  (if (null pnos)
    (progn
      (setq p0 (getpoint "\n평면 측점(NO.) 글자를 못 찾음 - 주관로 시점 지정: "))
      (if (null p0) (exit))
      (setq n0 (getint "\n시점 측점 번호 NO.<0>: "))
      (setq pnos (list (list (cond (n0) (0)) (qc:pt p0))))))
  (setq pnmin (apply 'min (mapcar 'car pnos))
        no0  (mapcar 'cadr (vl-remove-if-not '(lambda (x) (= (car x) pnmin)) pnos)))
  (princ (strcat "\n평면 시점 : NO." (itoa pnmin) "  (평면 측점 글자 " (itoa (length pnos)) "개)"))

  ;; --- 시점 객체 결정
  (foreach c cands
    (foreach np no0
      (if (or (null best) (< (distance np (car (cadr c))) (car best)))
        (setq best (list (distance np (car (cadr c))) c T)))
      (if (< (distance np (last (cadr c))) (car best))
        (setq best (list (distance np (last (cadr c))) c nil)))))
  (if (null best) (progn (princ "\n신설관 객체가 없습니다.") (exit)))

  ;; --- 주관로 체인 (측점 누적)
  (setq cur (cadr best) fwd (caddr best) s 0.0)
  (while cur
    (setq used  (cons (car cur) used)
          len   (qc:len (qc:verts (caddr cur)))
          pts   (if fwd (cadr cur) (reverse (cadr cur)))
          chain (cons (list (car cur) s (+ s len) pts) chain)
          s     (+ s len)
          endp  (last pts)
          dir   (qc:dir (reverse pts))
          nxt   nil bc -1.5)
    (foreach c cands
      (if (not (member (car c) used))
        (progn
          (if (< (distance (car (cadr c)) endp) *QC:TOL*)
            (if (> (setq c2 (qc:cos dir (qc:neg (qc:dir (cadr c))))) bc)
              (setq bc c2 nxt c nfwd T)))
          (if (< (distance (last (cadr c)) endp) *QC:TOL*)
            (if (> (setq c2 (qc:cos dir (qc:neg (qc:dir (reverse (cadr c)))))) bc)
              (setq bc c2 nxt c nfwd nil))))))
    (if (and nxt (> bc -0.7))
      (setq cur nxt fwd nfwd)
      (setq cur nil)))

  ;; --- 체인 거리 -> 측점 : 측점 = 체인거리 - cs
  ;;     cs = 평면 측점 글자를 주관로에 투영한 거리 - 번호x간격 의 중앙값
  ;;     (글자 위치 오차를 줄이려고 여러 측점의 중앙값 사용, 주관로에서 먼 글자는 제외)
  (setq tmp nil)
  (foreach x pnos
    (setq pr (qc:proj (cadr x) chain))
    (if (and pr (<= (car pr) *QC:STA-TXTD*))
      (setq tmp (cons (- (cdr pr) (* (car x) *QC:STA-INT*)) tmp))))
  (setq cs (if tmp (nth (/ (length tmp) 2) (vl-sort tmp '<)) (- (* pnmin *QC:STA-INT*))))
  (princ (strcat "\n주관로 시작점 측점 : " (qc:stastr (- cs))))

  ;; --- 선택 객체 -> 측점 구간
  (repeat (setq i (sslength sel))
    (setq e (ssname sel (setq i (1- i))))
    (if (setq q (assoc e chain))
      (setq rngs (cons (list (- (cadr q) cs) (- (caddr q) cs)
                             (list (cons (qc:dxf 8 (entget e)) (- (caddr q) (cadr q)))))
                       rngs))
      (setq bad (1+ (cond (bad) (0))))))
  (if bad (princ (strcat "\n※ 주관로에 연결되지 않은(또는 숨은선) 객체 " (itoa bad) "개 제외")))
  (if (null rngs) (progn (princ "\n주관로 구간이 없습니다.") (exit)))
  ;; 정렬 및 인접구간 병합
  (setq rngs (vl-sort rngs '(lambda (a b) (< (car a) (car b)))) tmp nil)
  (foreach r rngs
    (if (and tmp (<= (car r) (+ (cadr (car tmp)) 1e-3)))
      (setq tmp (cons (list (car (car tmp)) (max (cadr r) (cadr (car tmp)))
                            (append (caddr (car tmp)) (caddr r)))
                      (cdr tmp)))
      (setq tmp (cons r tmp))))
  (setq rngs (reverse tmp))

  ;; --- 종단 X 구간 (종단 관로 시/종점 범위로 제한)
  (setq xr (mapcar '(lambda (r) (list (+ x0 (* k (car r))) (+ x0 (* k (cadr r))))) rngs))
  (setq tmp nil)
  (foreach e (qc:collect (list '(0 . "LWPOLYLINE,LINE") (cons 8 *QC:LAY-QPIPE*)) box)
    (setq tmp (append (mapcar 'car (qc:verts (entget e))) tmp)))
  (if tmp
    (progn
      (setq pmin (apply 'min tmp) pmax (apply 'max tmp) tmp nil)
      (mapcar
        '(lambda (r x / a b)
           (setq a (max (car x) pmin) b (min (cadr x) pmax))
           (if (or (< (car x) (- pmin 1e-3)) (> (cadr x) (+ pmax 1e-3)))
             (princ (strcat "\n※ " (qc:stastr (car r)) " ~ " (qc:stastr (cadr r))
                            " 구간이 종단 관로 범위를 벗어나 종단 시/종점으로 맞춤")))
           (if (> b (+ a 1e-3))
             (setq tmp (cons (list r (list a b)) tmp))
             (princ "\n※ 종단 관로 범위 밖 구간 1개 제외")))
        rngs xr)
      (setq tmp  (reverse tmp)
            rngs (mapcar 'car tmp)
            xr   (mapcar 'cadr tmp))))
  (if (null xr) (progn (princ "\n종단에 반영할 구간이 없습니다.") (exit)))
  (foreach r xr (setq cuts (cons (car r) (cons (cadr r) cuts))))

  (princ (strcat "\n주관로 총연장 " (rtos s 2 2) "m, 종단 수평축척계수 " (rtos k 2 4)))
  (mapcar
    '(lambda (r x)
       (princ (strcat "\n  구간 " (qc:stastr (car r)) " ~ " (qc:stastr (cadr r))
                      "  (L=" (rtos (- (cadr r) (car r)) 2 2) "m)  -> 종단 X "
                      (rtos (car x) 2 3) " ~ " (rtos (cadr x) 2 3))))
    rngs xr)

  ;; --- 1) Q-종단가스관로 자르기 + 구간 밖 검은색
  (setq np 0)
  (foreach e (qc:collect (list '(0 . "LWPOLYLINE,LINE") (cons 8 *QC:LAY-QPIPE*)) box)
    (setq ed (entget e) vs (qc:verts ed))
    (setq pcs (if (and (= (qc:dxf 0 ed) "LWPOLYLINE") (= 1 (logand 1 (qc:dxf 70 ed))))
                (list vs)
                (qc:split vs cuts)))
    (if (> (length pcs) 1)
      (progn
        (foreach pc pcs
          (if (= (qc:dxf 0 ed) "LINE")
            (qc:mkln ed pc (not (qc:pcin pc xr)))
            (qc:mkpl ed pc (not (qc:pcin pc xr))))
          (if (not (qc:pcin pc xr)) (setq np (1+ np))))
        (entdel e))
      (if (not (qc:pcin vs xr))
        (progn (entmod (qc:setcol ed)) (setq np (1+ np))))))

  ;; --- 2) 도시가스관로 (종단 영역) 구간 밖 검은색
  (setq ng 0)
  (foreach e (qc:collect (list (cons 8 *QC:LAY-GAS*)) box)
    (setq ed (entget e) pts (qc:entpts ed))
    (if pts
      (progn
        (setq tmp (qc:bbox pts))
        (if (and (qc:inbox (car tmp) parea) (qc:inbox (cadr tmp) parea)
                 (not (qc:xin (/ (+ (car (car tmp)) (car (cadr tmp))) 2.0) xr)))
          (progn (entmod (qc:setcol ed)) (setq ng (1+ ng)))))))

  ;; --- 3) Q-종단그래프 수직선 (기준선 ~ 지반선)
  (foreach e (qc:collect (list '(0 . "LINE") (cons 8 *QC:LAY-GRAPH*)) box)
    (setq ed (entget e))
    (if (and (equal (car (qc:dxf 10 ed)) (car (qc:dxf 11 ed)) 1e-4)
             (> (abs (- (cadr (qc:dxf 10 ed)) (cadr (qc:dxf 11 ed)))) 1.0))
      (setq vl (cons (list (car (qc:dxf 10 ed))
                           (min (cadr (qc:dxf 10 ed)) (cadr (qc:dxf 11 ed)))
                           (max (cadr (qc:dxf 10 ed)) (cadr (qc:dxf 11 ed)))
                           ed)
                     vl))))
  ;; 기준선 Y = 가장 많은 수직선 하단
  (foreach v vl
    (setq q (fix (+ 0.5 (* (cadr v) 100.0))))
    (if (assoc q cnt)
      (setq cnt (subst (cons q (1+ (cdr (assoc q cnt)))) (assoc q cnt) cnt))
      (setq cnt (cons (cons q 1) cnt))))
  (setq nv 0)
  (if cnt
    (progn
      (setq q (car (car (vl-sort cnt '(lambda (a b) (> (cdr a) (cdr b)))))))
      (foreach v vl
        (if (and (= (fix (+ 0.5 (* (cadr v) 100.0))) q) (>= (car v) (- x0 0.01)))
          (setq bv (cons v bv))))
      (setq basey (cadr (car bv)))
      (foreach c (vl-sort cuts '<)
        (if (not (vl-some '(lambda (v) (equal (car v) c 0.005)) bv))
          (progn
            (setq l nil r nil)
            (foreach v bv
              (if (and (< (car v) c) (or (null l) (> (car v) (car l)))) (setq l v))
              (if (and (> (car v) c) (or (null r) (< (car v) (car r)))) (setq r v)))
            (setq top
              (cond
                ((and l r) (+ (caddr l) (* (/ (- c (car l)) (- (car r) (car l))) (- (caddr r) (caddr l)))))
                (l (caddr l))
                (r (caddr r))))
            (if top
              (progn
                (setq ref (cadddr (if l l r)))
                (entmake
                  (append
                    (qc:newhdr "LINE")
                    (vl-remove-if-not '(lambda (p) (member (car p) '(6 48 370))) ref)
                    (list (list 10 c basey 0.0) (list 11 c top 0.0))))
                (setq bv (cons (list c basey top ref) bv) nv (1+ nv)))))))))

  ;; --- 4) 허가구간 밴드
  (setq nb 0)
  (if basey
    (progn
      ;; 기존 관경밴드 수평선 (기준선 위 가장 낮은 긴 수평선)
      (setq bandy nil)
      (foreach e (qc:collect (list '(0 . "LINE,LWPOLYLINE") (cons 8 *QC:LAY-GRAPH*)) box)
        (setq pts (qc:entpts (entget e)))
        (if (and (= (length pts) 2)
                 (equal (cadr (car pts)) (cadr (cadr pts)) 1e-4)
                 (> (abs (- (car (car pts)) (car (cadr pts)))) 5.0)
                 (>= (min (car (car pts)) (car (cadr pts))) (- x0 0.01))
                 (> (cadr (car pts)) (+ basey 0.5))
                 (< (cadr (car pts)) (+ basey 15.0))
                 (or (null bandy) (< (cadr (car pts)) bandy)))
          (setq bandy (cadr (car pts)))))
      ;; 기존 밴드 문구의 글꼴/높이
      (setq th *QC:TXT-H* tsty (getvar "TEXTSTYLE"))
      (if (tblsearch "STYLE" "굴림") (setq tsty "굴림"))
      (if bandy
        (foreach e (qc:collect '((0 . "TEXT")) box)
          (setq ed (entget e))
          (if (and (wcmatch (strcase (qc:dxf 1 ed)) "*MM*")
                   (< (abs (- (cadr (qc:txtpt ed)) bandy)) 3.0)
                   (equal (cond ((qc:dxf 50 ed)) (0.0)) 0.0 1e-6))
            (setq th (qc:dxf 40 ed) tsty (qc:dxf 7 ed)))))
      (setq bandy (+ (cond (bandy) ((+ basey 5.57))) *QC:BAND-OFS*))
      (mapcar
        '(lambda (r x)
           (qc:band (car x) (cadr x) bandy *QC:BAND-TXT* (qc:bandlabel (caddr r)) th tsty)
           (setq nb (1+ nb)))
        rngs xr)))

  (princ (strcat "\n완료: 종단관로 검은색 " (itoa np) "개, 도시가스관로 검은색 " (itoa ng)
                 "개, 수직선 " (itoa nv) "개, 허가구간 밴드 " (itoa nb) "개 작도"))
  (hg0:undo "_E")
  (setvar "CMDECHO" ce)
  (setvar "DIMZIN" dz)
  (princ)
)

;;; ##########################################################################
;;;  [3] HG3CPY - 도곽 복사 (평면도는 보존 레이어만)
;;; ##########################################################################
;;;  1) 도곽 인식 : FORM 블록 -> (블록이 아니면) 사각 테두리 폴리선 -> 창 지정
;;;  2) 도곽 안에 완전히 들어있는 모든 객체를 복사 대상으로 수집
;;;  3) 평면도 틀 안의 객체는 보존 패턴(PDEL 규칙) 레이어만 복사
;;;  4) 결과 확인 후 삽입점(도곽 좌측상단 기준)을 지정해 복사
;;;  5) 원본 도곽 하단(-Y 5)에 관경별 연장 텍스트 작성
;;;     - 평면도 안 신설관 중 숨은선 제외, 색상 210 인 것만
;;;     - 객체별 길이를 소수 첫째 자리로 반올림한 뒤 관경별 합계
;;;     - 닫힌 지적 안 지번 글자로 필지를 구분해 지번별 관경별 연장도 작성

;;; ---------------- 설정 ----------------
;; 평면도 안에서 남길 레이어(또는 블록명) 패턴 - 대소문자 무시, wcmatch
(setq *HG:KEEP*
  '(("평면도틀" . "*평면도틀*,*평면틀*")
    ("신설관"   . "*신설*")
    ("캡"       . "*캡*,*CAP*")
    ("지적"     . "*지적*")
    ("지번"     . "*지번*")
    ("L"        . "L")))
(setq *HG:PLANFRAME*   "*평면도틀*,*평면틀*,L")  ; 평면도 틀 레이어
(setq *HG:FRAME-RATIO* '(1.30 . 1.60))          ; 블록이 아닌 도곽 테두리 가로/세로 비 범위
(setq *HG:TOL*         0.01)                    ; 도곽 경계 허용오차
;; 관경별 연장 텍스트 (원본 도곽 하단)
(setq *HG:LEN-COL*     210)                     ; 집계할 신설관 색상
(setq *HG:LEN-TITLE*   nil)                     ; 첫 줄 제목 (예: "허가구간 연장", nil = 없음)
(setq *HG:LEN-DY*      5.0)                     ; 도곽 하단에서 -Y 방향 거리
(setq *HG:LEN-TH*      3.0)                     ; 글자 높이
(setq *HG:LEN-LSP*     2.0)                     ; 줄 간격 (글자 높이 배수)
(setq *HG:LEN-GAP*     2.0)                     ; 지번/관경/연장 칸 사이 간격 (글자 높이 배수)
(setq *HG:LEN-BYLOT*   T)                       ; 지번별 연장도 작성 (nil = 관경별 합계만)
(setq *HG:LAY-JIJUK*   "*지적*")                ; 지적 레이어 (닫힌 폴리선 = 필지)
(setq *HG:LAY-JIBUN*   "*지번*")                ; 지번 글자 레이어

;;; ---------------- 유틸 ----------------
(defun hg:keep-group (name / u r lst)
  (if name
    (progn
      (setq u (strcase name) lst *HG:KEEP*)
      (while (and lst (not r))
        (if (wcmatch u (strcase (cdar lst))) (setq r (caar lst)))
        (setq lst (cdr lst)))
      r))
)

(defun hg:inc (key alst / p)
  (if (setq p (assoc key alst))
    (subst (cons key (1+ (cdr p))) p alst)
    (cons (cons key 1) alst))
)

(defun hg:area (b)
  (* (- (car (cadr b)) (car (car b))) (- (cadr (cadr b)) (cadr (car b))))
)

(defun hg:laystat (lay / d f)
  ;; 1=잠김, 2=동결/꺼짐 아님 구분용 : 잠김이면 "LOCK", 동결이면 "FRZ"
  (setq d (tblsearch "LAYER" lay) f (cond ((qc:dxf 70 d)) (0)))
  (cond ((= 1 (logand 1 f)) "FRZ") ((= 4 (logand 4 f)) "LOCK"))
)

;; 객체 범위 판정용 점들 (ActiveX 없이)
(defun hg:refpts (e ed / ty res first r c v codes)
  (setq ty (qc:dxf 0 ed))
  (cond
    ((member ty '("XLINE" "RAY")) nil)
    ;; 블록 : XCLIP 이 있으면 클립 경계, 없으면 실제 그려진 범위의 네 모서리
    ;;        (삽입점이 멀리 있거나 XCLIP 으로 잘려 보이는 블록 대비)
    ((= ty "INSERT")
     (cond ((hg:xclip ed))
           (T (cons (qc:pt (qc:dxf 10 ed)) (hg:insext ed)))))
    ((= ty "LWPOLYLINE") (mapcar 'qc:pt (qc:verts ed)))
    ((= ty "POLYLINE")
     (setq v (entnext e))
     (while (and v (= (qc:dxf 0 (setq c (entget v))) "VERTEX"))
       (setq res (cons (qc:pt (qc:dxf 10 c)) res)
             v   (entnext v)))
     res)
    ((member ty '("CIRCLE" "ARC"))
     (setq c (qc:dxf 10 ed) r (qc:dxf 40 ed))
     (list (list (- (car c) r) (- (cadr c) r)) (list (+ (car c) r) (+ (cadr c) r))))
    ((= ty "ELLIPSE")
     (setq c (qc:dxf 10 ed) r (distance '(0.0 0.0) (qc:pt (qc:dxf 11 ed))))
     (list (list (- (car c) r) (- (cadr c) r)) (list (+ (car c) r) (+ (cadr c) r))))
    ((= ty "HATCH")
     ;; 첫 10(고도점) 제외, 경계 정점/시드점
     (foreach p ed
       (if (= (car p) 10)
         (if first (setq res (cons (qc:pt (cdr p)) res)) (setq first T))))
     res)
    (T
     (setq codes
       (cond
         ((= ty "LINE") '(10 11))
         ((member ty '("SOLID" "TRACE" "3DFACE")) '(10 11 12 13))
         ((= ty "DIMENSION") '(10 11 13 14))
         ((= ty "SPLINE") '(10 11))
         ((member ty '("TEXT" "ATTDEF"))
          (if (and (= 0 (cond ((qc:dxf 72 ed)) (0))) (= 0 (cond ((qc:dxf 73 ed)) (0))))
            '(10) '(10 11)))
         (T '(10))))
     (foreach p ed
       (if (member (car p) codes) (setq res (cons (qc:pt (cdr p)) res))))
     res))
)

;; 블록 정의 범위 (선·폴리선·원·호·글자·하위 블록 삽입점), 블록 이름별로 기억
(setq *HG:BLKEXT* nil)
(setq *HG:SELLOTS* nil)
(setq *JB:ZKEYS* nil)
(defun hg:blkext (nm / e ed pts c r)
  (if (assoc nm *HG:BLKEXT*)
    (cdr (assoc nm *HG:BLKEXT*))
    (progn
      (setq e (tblobjname "BLOCK" nm))
      (while (setq e (entnext e))
        (setq ed (entget e))
        (cond
          ((= (qc:dxf 0 ed) "LINE")
           (setq pts (cons (qc:pt (qc:dxf 10 ed)) (cons (qc:pt (qc:dxf 11 ed)) pts))))
          ((= (qc:dxf 0 ed) "LWPOLYLINE")
           (foreach v (qc:verts ed) (setq pts (cons (qc:pt v) pts))))
          ((member (qc:dxf 0 ed) '("CIRCLE" "ARC"))
           (setq c (qc:dxf 10 ed) r (qc:dxf 40 ed)
                 pts (cons (list (- (car c) r) (- (cadr c) r)) (cons (list (+ (car c) r) (+ (cadr c) r)) pts))))
          ((member (qc:dxf 0 ed) '("TEXT" "MTEXT" "INSERT" "POINT" "ATTDEF"))
           (setq pts (cons (qc:pt (qc:dxf 10 ed)) pts)))))
      (setq r (if pts (qc:bbox pts)))
      (setq *HG:BLKEXT* (cons (cons nm r) *HG:BLKEXT*))
      r))
)

;; 블록 삽입점·축척·회전으로 블록 좌표 p -> 실제 좌표
(defun hg:blk2w (p ed / nm bp ins sx sy r x y)
  (setq nm  (qc:dxf 2 ed)
        bp  (qc:dxf 10 (tblsearch "BLOCK" nm))
        ins (qc:dxf 10 ed)
        sx  (cond ((qc:dxf 41 ed)) (1.0))
        sy  (cond ((qc:dxf 42 ed)) (1.0))
        r   (cond ((qc:dxf 50 ed)) (0.0))
        x   (* (- (car p) (car bp)) sx)
        y   (* (- (cadr p) (cadr bp)) sy))
  (list (+ (car ins) (- (* x (cos r)) (* y (sin r))))
        (+ (cadr ins) (+ (* x (sin r)) (* y (cos r)))))
)

;; XCLIP 클립 경계 (실제 좌표 점 목록). 공간 필터가 없으면 nil
;;  SPATIAL_FILTER : 10 = 경계점(2점이면 사각형), 73 뒤의 40 x12 = 클립 -> 블록 좌표 변환 (3x4 행 우선)
(defun hg:xclip (ed / xd fd sf pts vals m x1 y1 x2 y2)
  (setq xd (cdr (assoc 360 (member '(102 . "{ACAD_XDICTIONARY") ed))))
  (if (and xd
           (setq fd (dictsearch xd "ACAD_FILTER"))
           (setq sf (dictsearch (cdr (assoc -1 fd)) "SPATIAL"))
           (/= 0 (cond ((cdr (assoc 71 sf))) (1))))
    (progn
      (foreach p sf (if (= (car p) 10) (setq pts (cons (qc:pt (cdr p)) pts))))
      (setq pts (reverse pts))
      (foreach p (member (assoc 73 sf) sf) (if (= (car p) 40) (setq vals (cons (cdr p) vals))))
      (setq vals (reverse vals))
      (if (= (length pts) 2)
        (setq x1 (car (car pts)) y1 (cadr (car pts)) x2 (car (cadr pts)) y2 (cadr (cadr pts))
              pts (list (list x1 y1) (list x2 y1) (list x2 y2) (list x1 y2))))
      (if (and (>= (length pts) 3) (>= (length vals) 8))
        (mapcar
          '(lambda (p)
             (hg:blk2w (list (+ (* (nth 0 vals) (car p)) (* (nth 1 vals) (cadr p)) (nth 3 vals))
                             (+ (* (nth 4 vals) (car p)) (* (nth 5 vals) (cadr p)) (nth 7 vals)))
                       ed))
          pts))))
)

;; 블록 삽입의 실제 범위 네 모서리 (삽입점·축척·회전 반영)
(defun hg:insext (ed / nm ext bp ins sx sy r)
  (setq nm (qc:dxf 2 ed))
  (if (setq ext (hg:blkext nm))
    (progn
      (setq bp  (qc:dxf 10 (tblsearch "BLOCK" nm))
            ins (qc:dxf 10 ed)
            sx  (cond ((qc:dxf 41 ed)) (1.0))
            sy  (cond ((qc:dxf 42 ed)) (1.0))
            r   (cond ((qc:dxf 50 ed)) (0.0)))
      (mapcar
        '(lambda (p / x y)
           (setq x (* (- (car p) (car bp)) sx)
                 y (* (- (cadr p) (cadr bp)) sy))
           (list (+ (car ins) (- (* x (cos r)) (* y (sin r))))
                 (+ (cadr ins) (+ (* x (sin r)) (* y (cos r))))))
        (list (car ext) (cadr ext)
              (list (car (car ext)) (cadr (cadr ext)))
              (list (car (cadr ext)) (cadr (car ext)))))))
)

(defun hg:allin (pts b)
  (and pts (not (vl-some '(lambda (p) (not (qc:inbox p b))) pts)))
)

;; 닫힌 4~5점 사각 폴리선이고 비율이 도곽 같으면 범위 반환
(defun hg:rectlike (ed / vs n b w h a)
  (setq vs (qc:verts ed) n (length vs))
  (if (and (<= 4 n 5)
           (or (= 1 (logand 1 (cond ((qc:dxf 70 ed)) (0))))
               (and (= n 5) (equal (qc:pt (car vs)) (qc:pt (last vs)) 1e-6))))
    (progn
      (setq b (qc:bbox (mapcar 'qc:pt vs))
            w (- (car (cadr b)) (car (car b)))
            h (- (cadr (cadr b)) (cadr (car b))))
      (if (and (> w 0.0) (> h 0.0))
        (progn
          (setq a (/ (max w h) (min w h)))
          (if (and (>= a (car *HG:FRAME-RATIO*)) (<= a (cdr *HG:FRAME-RATIO*))) b)))))
)

;; 점 p 를 포함하는 도곽 (FORM 블록 우선, 없으면 사각 테두리 폴리선) -> (범위 . 종류)
(defun hg:findframe (p / best area b ss i ed kind)
  (setq area 0.0)
  (foreach b (qc:formboxes)
    (if (and (qc:inbox p b) (> (hg:area b) area))
      (setq best b area (hg:area b) kind "FORM 블록")))
  (if (and (null best) (setq ss (ssget "_X" '((0 . "LWPOLYLINE") (410 . "Model")))))
    (repeat (setq i (sslength ss))
      (setq ed (entget (ssname ss (setq i (1- i)))))
      (if (and (setq b (hg:rectlike ed)) (qc:inbox p b) (> (hg:area b) area))
        (setq best b area (hg:area b) kind (strcat "테두리 폴리선(" (qc:dxf 8 ed) ")")))))
  (if best (cons best kind))
)

;; 도곽 안 평면도 틀
(defun hg:planbox (fb / ss i ed vs b best area fg)
  (setq area 0.0 fg (qc:grow fb *HG:TOL*))
  (if (setq ss (ssget "_X" (list '(0 . "LWPOLYLINE") (cons 8 *HG:PLANFRAME*) '(410 . "Model"))))
    (repeat (setq i (sslength ss))
      (setq ed (entget (ssname ss (setq i (1- i))))
            vs (qc:verts ed))
      (if (>= (length vs) 4)
        (progn
          (setq b (qc:bbox (mapcar 'qc:pt vs)))
          (if (and (qc:inbox (car b) fg) (qc:inbox (cadr b) fg)
                   (< (hg:area b) (* 0.9 (hg:area fb)))
                   (> (hg:area b) area))
            (setq best b area (hg:area b)))))))
  best
)

;; 실제 색상 (객체 색상, ByLayer 면 레이어 색상)
(defun hg:color (ed / c)
  (setq c (qc:dxf 62 ed))
  (if (or (null c) (= c 256))
    (abs (cond ((qc:dxf 62 (tblsearch "LAYER" (qc:dxf 8 ed)))) (7)))
    c)
)

(defun hg:r1 (x) (/ (fix (+ (* x 10.0) 0.5)) 10.0))

;; 레이어명 -> (정렬키 . 표기) : "신설관 LP 110mm PE" -> (110 . "110mm"), MP 는 "MP 100A"
(defun hg:diakey (lay / p d u)
  (foreach w (qc:split-sp lay)
    (setq u (strcase w))
    (cond
      ((member u '("LP" "MP" "HP")) (setq p u))
      ((and (null d) (wcmatch u "#*MM,#*A")) (setq d w))))
  (if d
    (cons (+ (atof d) (if (member p '("MP" "HP")) 100000.0 0.0))
          (if (member p '("MP" "HP")) (strcat p " " d) d))
    (cons 1e9 lay))
)

;; 글자 폭 (textbox, 실패 시 추정)
(defun hg:tw (str h sty / tb)
  (if (and (/= str "") (setq tb (textbox (list (cons 1 str) (cons 40 h) (cons 7 sty)))))
    (- (car (cadr tb)) (car (car tb)))
    (* (strlen str) h 0.8))
)

(defun hg:mktext (str x y h sty ha)
  ;; ha : 0 = 왼쪽 위, 2 = 오른쪽 위
  (if (/= str "")
    (entmake (append (qc:newhdr "TEXT")
                     (list (list 10 x y 0.0) (cons 40 h) (cons 1 str) (cons 7 sty)
                           (cons 72 ha) (list 11 x y 0.0) '(73 . 3)))))
)

;; 도곽 하단 텍스트 여러 줄. 왼쪽 위 기준 (x, yt) 부터 아래로
;; 항목이 문자열이면 한 줄, (지번 관경 연장) 목록이면 3칸으로 나눠 정렬
;;   지번·관경 칸은 왼쪽 정렬, 연장 칸은 오른쪽 정렬
(defun hg:lentext (strs x yt / h sty y w1 w2 w3 gap x2 x3)
  (setq h   *HG:LEN-TH*
        sty (if (tblsearch "STYLE" "굴림") "굴림" (getvar "TEXTSTYLE"))
        y   yt w1 0.0 w2 0.0 w3 0.0 gap (* h *HG:LEN-GAP*))
  (foreach r strs
    (if (listp r)
      (setq w1 (max w1 (hg:tw (car r) h sty))
            w2 (max w2 (hg:tw (cadr r) h sty))
            w3 (max w3 (hg:tw (caddr r) h sty)))))
  ;; 최소 칸 폭 : 관경 3자리(예 315mm), 연장 3자리(예 999.9m) 기준
  (setq w2 (max w2 (hg:tw "000mm " h sty))
        w3 (max w3 (hg:tw "000.0m" h sty)))
  (setq x2 (+ x w1 gap)
        x3 (+ x2 w2 gap w3))
  (foreach r strs
    (if (listp r)
      (progn
        (hg:mktext (car r) x y h sty 0)
        (hg:mktext (cadr r) x2 y h sty 0)
        (hg:mktext (caddr r) x3 y h sty 2))
      (hg:mktext r x y h sty 0))
    (setq y (- y (* h *HG:LEN-LSP*))))
)

(defun hg:trim (s)
  (while (and (> (strlen s) 0) (= (substr s 1 1) " ")) (setq s (substr s 2)))
  (while (and (> (strlen s) 0) (= (substr s (strlen s) 1) " ")) (setq s (substr s 1 (1- (strlen s)))))
  s
)

(defun hg:join (lst sep / r)
  (foreach x lst (setq r (if r (strcat r sep x) x)))
  (cond (r) (""))
)

;; 지번 정렬키 : "376-14전" -> 376*100000+14, 미확인은 맨 뒤
(defun hg:lotkey (nm / i ch a b sub)
  (if (null nm)
    1e12
    (progn
      (setq i 1 a "" b "" sub nil)
      (while (<= i (strlen nm))
        (setq ch (substr nm i 1) i (1+ i))
        (cond
          ((wcmatch ch "#") (if sub (setq b (strcat b ch)) (setq a (strcat a ch))))
          ((and (= ch "-") (/= a "")) (setq sub T))
          ((/= a "") (setq i (1+ (strlen nm))))))
      (if (= a "") 1e11 (+ (* (atoi a) 100000.0) (atoi b)))))
)

;; 도곽 안 필지 : ((지번 면적 다각형) ...) 작은 필지 순
(defun hg:lots (fb / fg ss i ed e pl polys txts pt in nm res pbx)
  (setq fg (qc:grow fb *HG:TOL*) pbx (hg:planbox fb))
  (if (setq ss (ssget "_X" (list '(0 . "LWPOLYLINE") (cons 8 *HG:LAY-JIJUK*) '(410 . "Model"))))
    (repeat (setq i (sslength ss))
      (setq ed (entget (ssname ss (setq i (1- i)))))
      (setq pl (cond ((jb:closed-p ed) (jb:poly ed))
                     ;; 평면도 틀에 잘린 열린 지적은 틀 경계로 닫음
                     (pbx (hg:closeclip (jb:polyopen ed) pbx))))
      (if (and pl (hg:allin pl fg))
        (setq polys (cons (list pl (hg:parea pl)) polys)))))
  (if (setq ss (ssget "_X" (list '(0 . "TEXT,MTEXT") (cons 8 *HG:LAY-JIBUN*) '(410 . "Model"))))
    (repeat (setq i (sslength ss))
      (setq ed (entget (ssname ss (setq i (1- i))))
            pt (jb:pt (if (= (qc:dxf 0 ed) "MTEXT") (qc:dxf 10 ed) (qc:txtpt ed))))
      (if (qc:inbox pt fg)
        (setq txts (cons (cons (hg:trim (qc:dxf 1 ed)) pt) txts)))))
  (foreach p polys
    (setq in nil)
    (foreach tx txts
      ;; 같은 지번 글자가 중복으로 있으면 하나로
      (if (and (jb:inpoly (cdr tx) (car p)) (not (member (car tx) in)))
        (setq in (cons (car tx) in))))
    (setq nm (cond ((null in) nil)
                   ((= (length in) 1) (car in))
                   (T (strcat (hg:join in "/") "(확인필요)"))))
    (setq res (cons (list nm (cadr p) (car p)) res)))
  (setq res (vl-sort res '(lambda (a b) (< (cadr a) (cadr b)))))
  ;; HG1 에서 선택한 필지(틀에 잘린 필지 포함)를 먼저 사용
  (append (vl-remove-if-not '(lambda (l) (hg:allin (caddr l) fg)) *HG:SELLOTS*) res)
)

;; 점이 속한 필지 지번 (없으면 nil)
(defun hg:lotof (p lots / r)
  (foreach l lots
    (if (and (null r) (jb:inpoly p (caddr l))) (setq r (cond ((car l)) ("지번없음")))))
  r
)

;;; ==========================================================================
(defun c:HG3CPY (/ *error* ce cm dz p p1 p2 fr fb fg pb ss i e ed pts cb c lay grp bname nm
                  cpy ncp keepcnt delcnt nlock ans bp dp lens dk q rows tot lots lot lotlens strs lnames ln k)
  (defun *error* (m)
    (if (not (wcmatch (strcase m) "*CANCEL*,*QUIT*,*BREAK*,*취소*"))
      (princ (strcat "\n오류: " m)))
    (hg0:clear)
    (command-s "_.UNDO" "_E")
    (if cm (setvar "COPYMODE" cm))
    (if dz (setvar "DIMZIN" dz))
    (if ce (setvar "CMDECHO" ce))
    (princ)
  )
  (setq ce (getvar "CMDECHO") dz (getvar "DIMZIN"))
  (setvar "CMDECHO" 0)
  (setvar "DIMZIN" 0)

  ;; --- 1) 도곽
  (if *HG0*
    (setq p *HG0-PT*)
    (progn
      (initget "Window")
      (setq p (getpoint "\n도곽 안의 한 점 지정 또는 [창(W)]: "))))
  (cond
    ((null p) (exit))
    ((= p "Window")
     (setq p1 (getpoint "\n도곽 첫 번째 구석: ")
           p2 (getcorner p1 "\n반대 구석: ")
           fb (qc:bbox (list (qc:pt p1) (qc:pt p2))))
     (princ "\n도곽: 창 지정"))
    (T
     (if (setq fr (hg:findframe (qc:pt p)))
       (setq fb (car fr))
       (progn (princ "\n도곽을 찾지 못했습니다. 다시 실행해 [창(W)]으로 지정하세요.") (exit)))
     (princ (strcat "\n도곽: " (cdr fr)))))
  (princ (strcat "  크기 " (rtos (- (car (cadr fb)) (car (car fb))) 2 1)
                 " x " (rtos (- (cadr (cadr fb)) (cadr (car fb))) 2 1)))
  (setq fg (qc:grow fb *HG:TOL*))

  ;; --- 2) 평면도 틀
  (if (setq pb (hg:planbox fb))
    (princ "\n평면도 틀: 자동 인식")
    (progn
      (setq p1 (getpoint "\n평면도 틀을 찾지 못했습니다. 평면도 영역 첫 구석 <평면도 정리 안 함>: "))
      (if p1
        (setq p2 (getcorner p1 "\n반대 구석: ")
              pb (qc:bbox (list (qc:pt p1) (qc:pt p2)))))))

  ;; --- 3) 분류
  (setq cpy (ssadd) ncp 0 nlock 0 *HG:BLKEXT* nil)
  (if *HG:LEN-BYLOT* (setq lots (hg:lots fb)))
  (princ "\n도곽 안 객체 확인 중...")
  (if (setq ss (ssget "_X" '((410 . "Model"))))
    (repeat (setq i (sslength ss))
      (setq e   (ssname ss (setq i (1- i)))
            ed  (entget e)
            pts (hg:refpts e ed))
      (if (hg:allin pts fg)
        (progn
          (setq lay (qc:dxf 8 ed) grp nil)
          (setq cb (qc:bbox pts)
                c  (list (/ (+ (car (car cb)) (car (cadr cb))) 2.0)
                         (/ (+ (cadr (car cb)) (cadr (cadr cb))) 2.0)))
          ;; 관경별 연장 집계 : 신설관, 숨은선 제외, 색상 210, 평면도 안(평면도 틀이 없으면 도곽 안)
          (if (and (member (qc:dxf 0 ed) '("LWPOLYLINE" "LINE"))
                   (wcmatch (strcase lay) (strcase *QC:LAY-PIPE*))
                   (not (qc:hidden-p ed))
                   (= (hg:color ed) *HG:LEN-COL*)
                   (or (null pb) (qc:inbox c pb)))
            (progn
              (setq dk (hg:diakey lay)
                    q  (hg:r1 (qc:len (qc:verts ed))))
              (if (assoc dk lens)
                (setq lens (subst (cons dk (+ q (cdr (assoc dk lens)))) (assoc dk lens) lens))
                (setq lens (cons (cons dk q) lens)))
              ;; 지번별
              (if *HG:LEN-BYLOT*
                (progn
                  (setq lot (cond ((hg:lotof (jb:midpt ed) lots)) ("지번 미확인"))
                        ln  (cons lot dk))
                  (if (assoc ln lotlens)
                    (setq lotlens (subst (cons ln (+ q (cdr (assoc ln lotlens)))) (assoc ln lotlens) lotlens))
                    (setq lotlens (cons (cons ln q) lotlens)))))))
          (if (and pb (qc:inbox c pb))
            (progn
              ;; 평면도 안 : 보존 패턴만
              (setq grp (hg:keep-group lay))
              (if (and (not grp) (= "INSERT" (qc:dxf 0 ed)))
                (progn
                  (setq bname (qc:dxf 2 ed))
                  (if (not (wcmatch bname "`*U*")) (setq grp (hg:keep-group bname)))))
              (if grp
                (setq keepcnt (hg:inc grp keepcnt))
                (setq delcnt (hg:inc lay delcnt))))
            (setq grp "도곽"))
          (if grp
            (if (hg:laystat lay)
              (setq nlock (1+ nlock))
              (setq cpy (ssadd e cpy) ncp (1+ ncp))))))))

  ;; --- 결과 표시
  (if pb
    (progn
      (princ "\n\n===== 평면도 보존 =====")
      (if keepcnt
        (foreach x (reverse keepcnt) (princ (strcat "\n  " (car x) " : " (itoa (cdr x)) "개")))
        (princ "\n  (없음)"))
      (princ "\n===== 평면도 제외 레이어 =====")
      (if delcnt
        (foreach x (vl-sort delcnt '(lambda (a b) (< (car a) (car b))))
          (princ (strcat "\n  " (car x) " : " (itoa (cdr x)) "개")))
        (princ "\n  (없음)"))))
  (if (> nlock 0)
    (princ (strcat "\n※ 잠김/동결 레이어 객체 " (itoa nlock) "개는 복사에서 제외")))
  (if (= ncp 0)
    (progn (princ "\n복사할 객체가 없습니다.") (exit)))

  (if (not *HG0*)
    (progn
      (initget "Yes No")
      (setq ans (getkword (strcat "\n\n" (itoa ncp) "개 객체를 복사할까요? [Yes/No] <Yes>: ")))))
  (if (= ans "No") (progn (princ "\n취소했습니다.") (exit)))

  ;; --- 4) 삽입점 지정 후 복사
  (setq bp (list (car (car fb)) (cadr (cadr fb))))      ; 도곽 좌측상단
  (setq dp (getpoint (list (car bp) (cadr bp) 0.0) "\n삽입점 지정 (도곽 좌측상단 기준): "))
  (if (null dp) (progn (princ "\n취소했습니다.") (exit)))
  (hg0:undo "_BE")
  (setq cm (getvar "COPYMODE"))
  (setvar "COPYMODE" 1)
  (command "_.COPY" cpy "" "_non" (list (car bp) (cadr bp) 0.0) "_non" dp)
  (setvar "COPYMODE" cm)

  ;; --- 5) 원본 도곽 하단 관경별 연장 텍스트
  (if lens
    (progn
      (qc:newlayer)
      (setq rows (mapcar '(lambda (x) (cons (cdr (car x)) (cdr x)))
                         (vl-sort lens '(lambda (a b) (< (car (car a)) (car (car b)))))))
      ;; 관경별 합계 줄
      (setq strs (append (if *HG:LEN-TITLE* (list *HG:LEN-TITLE*))
                         (mapcar '(lambda (r) (strcat (car r) " : " (rtos (cdr r) 2 1) "m")) rows)))
      ;; 지번별 줄 : "376-14전 : 63mm 0.3m, 110mm 36.9m"
      (if (and *HG:LEN-BYLOT* lotlens)
        (progn
          (foreach x lotlens (if (not (member (car (car x)) lnames)) (setq lnames (cons (car (car x)) lnames))))
          (setq lnames (vl-sort lnames '(lambda (a b) (< (hg:lotkey (if (= a "지번 미확인") nil a))
                                                          (hg:lotkey (if (= b "지번 미확인") nil b))))))
          (setq strs (append strs (list "" "[지번별]")))
          (foreach nm lnames
            (setq k T)
            (foreach x (vl-sort (vl-remove-if-not '(lambda (x) (= (car (car x)) nm)) lotlens)
                                '(lambda (a b) (< (cadr (car a)) (cadr (car b)))))
              ;; (지번 관경 연장) 3칸, 같은 지번의 둘째 관경부터는 지번 칸 비움
              (setq strs (append strs (list (list (if k (strcat nm " : ") "")
                                                  (strcat (cddr (car x)) " ")
                                                  (strcat (rtos (cdr x) 2 1) "m"))))
                    k nil)))))
      (hg:lentext strs (car (car fb)) (- (cadr (car fb)) *HG:LEN-DY*))
      (princ "\n관경별 연장 (색상 210 신설관):")
      (setq tot 0.0)
      (foreach r rows
        (princ (strcat "\n  " (car r) " : " (rtos (cdr r) 2 1) "m"))
        (setq tot (+ tot (cdr r))))
      (princ (strcat "\n  합계 : " (rtos tot 2 1) "m"))
      (if (and *HG:LEN-BYLOT* lotlens)
        (progn
          (princ "\n지번별:")
          (foreach x (cdr (member "[지번별]" strs))
            (princ (strcat "\n  " (if (listp x) (strcat (car x) (cadr x) (caddr x)) x)))))))
    (princ "\n※ 색상 210 신설관이 없어 연장은 작성하지 않았습니다."))

  (hg0:undo "_E")
  (princ (strcat "\n완료: " (itoa ncp) "개 복사  (U 로 한 번에 되돌릴 수 있음)"))
  (setvar "DIMZIN" dz)
  (setvar "CMDECHO" ce)
  (princ)
)


;;; ##########################################################################
;;;  [0] HG0 - 지적 선택 한 번으로 HG1BRK -> HG2PRF -> HG3CPY 연속 실행
;;; ##########################################################################
;;;  1) 지적 객체 선택 (HG1 과 같은 선택)
;;;  2) 선택한 지적이 들어 있는 도곽을 자동 인식
;;;  3) HG1BRK : 지적 교차 끊기 / 색상
;;;  4) HG2PRF : 그 도곽 안의 색상 210 신설관(주관로)을 자동 선택해 종단 반영
;;;  5) HG3CPY : 도곽 복사 (복사 확인 생략, 삽입점만 지정) + 연장 텍스트
;;;  - 전체가 UNDO 한 묶음 (U 한 번으로 모두 되돌림)
;;;  - HG2 단계에서 반영할 주관로가 없으면 건너뛰고 HG3 진행

(setq *HG0* nil *HG0-SS* nil *HG0-SEL* nil *HG0-PT* nil)

;; 단독 실행일 때만 UNDO 묶음 (HG0 안에서는 HG0 이 한 번에 묶음)
(defun hg0:undo (op) (if (not *HG0*) (command "_.UNDO" op)))

(defun hg0:clear () (setq *HG0* nil *HG0-SS* nil *HG0-SEL* nil *HG0-PT* nil))

;; 단계 실행. 취소(ESC)면 전체 중단, 그 외 오류는 메시지 후 계속 여부 반환
(defun hg0:step (fn title / r m)
  (princ (strcat "\n\n========== " title " =========="))
  (setq r (vl-catch-all-apply fn nil))
  (if (vl-catch-all-error-p r)
    (progn
      (setq m (vl-catch-all-error-message r))
      (if (wcmatch (strcase m) "*CANCEL*,*취소*,*BREAK*")
        (progn (princ "\n[HG0] 취소했습니다.") (exit)))
      (if (not (wcmatch (strcase m) "*QUIT*,*EXIT*"))
        (princ (strcat "\n[HG0] " title " 오류: " m)))
      nil)
    T)
)

(defun c:HG0 (/ *error* ce dz cm ss p fr fb fg sel s2 i e)
  (defun *error* (m)
    (if (not (wcmatch (strcase m) "*CANCEL*,*QUIT*,*BREAK*,*취소*"))
      (princ (strcat "\n오류: " m)))
    (hg0:clear)
    (command-s "_.UNDO" "_E")
    (if ce (setvar "CMDECHO" ce))
    (if dz (setvar "DIMZIN" dz))
    (if cm (setvar "COPYMODE" cm))
    (princ)
  )
  (setq ce (getvar "CMDECHO") dz (getvar "DIMZIN") cm (getvar "COPYMODE"))
  (hg0:clear)

  (princ "\n[HG0] 지적 객체 선택: ")
  (if (null (setq ss (ssget (list '(0 . "LWPOLYLINE,LINE") (cons 8 *JB:LAY-JIJUK*)))))
    (progn (princ "\n선택된 지적 객체가 없습니다.") (exit)))

  ;; 선택한 지적이 들어 있는 도곽
  (setq p (car (hg:refpts (ssname ss 0) (entget (ssname ss 0)))))
  (if (null (setq fr (hg:findframe p)))
    (progn (princ "\n선택한 지적이 들어 있는 도곽을 찾지 못했습니다. HG1BRK~HG3CPY 를 따로 실행하세요.") (exit)))
  (setq fb (car fr) fg (qc:grow fb *HG:TOL*))
  (princ (strcat "\n도곽: " (cdr fr)))

  (setvar "CMDECHO" 0)
  (command "_.UNDO" "_BE")
  (setq *HG0* T *HG0-SS* ss *HG0-PT* p)

  ;; 1) HG1
  (if (not (hg0:step 'c:HG1BRK "[1/3] HG1BRK 지적 교차 끊기"))
    (progn (princ "\n[HG0] 1단계 실패로 중단합니다.") (exit)))

  ;; 2) HG2 : 도곽 안 색상 210 신설관 자동 선택
  (setq sel (ssadd))
  (if (setq s2 (ssget "_X" (list '(0 . "LWPOLYLINE,LINE") (cons 8 *QC:LAY-PIPE*)
                                 (cons 62 *JB:IN-COL*) '(410 . "Model"))))
    (repeat (setq i (sslength s2))
      (setq e (ssname s2 (setq i (1- i))))
      (if (hg:allin (hg:refpts e (entget e)) fg) (ssadd e sel))))
  (if (> (sslength sel) 0)
    (progn
      (setq *HG0-SEL* sel)
      (princ (strcat "\n도곽 안 색상 " (itoa *JB:IN-COL*) " 신설관 " (itoa (sslength sel)) "개 (주관로에 이어진 것만 반영)"))
      (hg0:step 'c:HG2PRF "[2/3] HG2PRF 허가구간 종단 반영"))
    (princ (strcat "\n\n※ 도곽 안에 색상 " (itoa *JB:IN-COL*) " 신설관이 없어 HG2PRF 를 건너뜁니다.")))

  ;; 3) HG3
  (hg0:step 'c:HG3CPY "[3/3] HG3CPY 도곽 복사")

  (hg0:clear)
  (command "_.UNDO" "_E")
  (setvar "CMDECHO" ce)
  (setvar "DIMZIN" dz)
  (setvar "COPYMODE" cm)
  (princ "\n\n[HG0] 완료 - U 한 번으로 전체를 되돌릴 수 있습니다.")
  (princ)
)

(princ "\nHGTOOL 로드됨 - HG0(1~3 연속), HG1BRK(지적 교차 끊기), HG2PRF(허가구간 종단 반영), HG3CPY(도곽 복사)")
(princ)
