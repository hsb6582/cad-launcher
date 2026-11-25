;;;=======================================================================
;;; GGv2.lsp  (구 FormCheck.lsp)
;;; AutoCAD LT 2026 용 - FORM 블록(도면경계) 인식 및 LP/MP 도면번호 판별
;;;                     + 종단그래프/DISTANCE(M)/자재내역 자동 수정 통합
;;;-----------------------------------------------------------------------
;;; 기능 요약
;;;  1) "FORM" 블록(도면 경계)을 도면 전체에서 검색
;;;  2) 동일 위치(허용오차 이내)에 중복 삽입된 FORM 블록은 1개만 사용
;;;  3) 각 FORM 블록 내부에 있는 레이어 "T"의 텍스트 중
;;;     "지역-년도-압력-번호" 형식(예: 홍성-2026-LP-001)을 탐색
;;;  4) 압력구분(LP=저압, MP=중압)과 도면번호를 추출
;;;  5) FORM 블록 처리 순서 = 좌측상단 -> 우측, 다음 줄로 내려가며 반복
;;;  6) [MARKTEE] 레이어 "Q-종단TEXT"의 특정 관경 문구(S.TEE/TEE ...)를 찾아
;;;     해당 텍스트 삽입기준점에 반지름 2 원을 "0기술검토" 레이어에 표시
;;;
;;; 명령어 목록
;;;  FORMSETAREA : FORM 블록 내 도면번호 텍스트 위치 범위 자동 계산
;;;  FORMCHECK   : FORM 블록별 도면번호(LP/MP) 판별
;;;  MARKTEE     : 관경 문구 위치에 표시용 원 생성
;;;  MARKLINE    : 종단선(폴리선) 번호 매기기용 원 생성
;;;  GGL  (구 TEELINE)   : MARKTEE+MARKLINE 통합 자동 판별 (원 미생성)
;;;  TEELINE1    : 텍스트A 직접 선택 검증용 (GGL 디버깅용)
;;;  GGD  (구 DISTCHAIN) : DISTANCE(M) 우측 텍스트 체인 - 상단 프라임값 차이로 자동 수정
;;;  GGM         : 63mm 관련 자재 레이어 이관 + 틀(프레임) 내부 빈 행 재정렬
;;;  GGM2        : 어휘 기반 자재내역 63mm 그룹 인식/이관 (자재구분/단위/수량/재질)
;;;  GGM3        : 자재내역 "직관" 그룹 기준 정렬 (빈칸 채우기, GGM2와 별도 실행)
;;;  GGF         : 지정 레이어(LPPE63ACAP 등)가 켜져있으면 끄기 + "관로명" 레이어 63mm 텍스트 이관
;;;  GGA         : GGL -> GGD -> GGM2 -> GGF 순차 실행 (전체 일괄 처리)
;;;
;;; 사용법
;;;  1) APPLOAD 명령으로 이 파일을 로드
;;;  2) 명령행에 원하는 명령어 입력 후 Enter
;;;  3) 명령행 결과창에서 각 FORM 블록 순서별 처리 결과 확인
;;;
;;; 주의 / 전제조건
;;;  - FORM 블록은 모델스페이스(또는 현재 도면공간) 최상위에 삽입되어 있어야 함
;;;    (다른 블록 내부에 중첩된 FORM은 인식하지 않음)
;;;  - 다이나믹 블록도 인식하도록 EffectiveName 기준으로 비교함
;;;  - 텍스트 형식은 반드시 "-" 4개 필드(지역-년도-압력-번호)로 구성되어야 함
;;;=======================================================================

(vl-load-com)

;; ==== 사용자 설정값 (필요시 수정) =======================================
(setq *FORM-BLKNAME*  "FORM")   ; 도면경계 블록 이름
(setq *TEXT-LAYER*    "T")      ; 도면번호 텍스트가 위치한 레이어
(setq *DUP-TOL*       1.0)      ; 동일 위치로 판단할 삽입점 거리 허용오차(도면단위)
(setq *ROW-TOL-RATIO* 0.5)      ; 같은 행으로 볼 Y편차 비율 (블록 평균높이 대비)

;; 아래 두 값은 FORMSETAREA 명령으로 자동 계산하거나, 직접 값을 넣어도 됩니다.
;; FORM 블록의 "삽입점 기준 로컬좌표계"에서 도면번호 텍스트가 위치하는 범위(사각형)
(setq *TEXT-LOCAL-MIN* (list 353.8706 20.0000))
(setq *TEXT-LOCAL-MAX* (list 396.8706 27.0000))

;; ---- MARKTEE 기능 설정값 ----
(setq *TEE-LAYER*   "Q-종단TEXT")  ; 관경 문구가 있는 레이어
(setq *MARK-LAYER*  "0기술검토")   ; 원을 그릴 레이어 (없으면 자동 생성)
(setq *TEE-ROT-MIN* 28.0)         ; 대상으로 볼 최소 회전각(도)
(setq *TEE-ROT-MAX* 32.0)         ; 대상으로 볼 최대 회전각(도)
(setq *TEE-COLOR*   1)            ; ACI 색상번호 (1 = 빨강)
(setq *TEE-RADIUS*  1.0)          ; 표시할 원의 반지름
(setq *TEE-TEXTLIST*
  (list "S.TEE 315mmx63mm" "S.TEE 225mmx63mm" "S.TEE 160mmx63mm"
        "S.TEE 110mmx63mm" "TEE 110mmx63mm")
)
(setq *RAD2DEG* (/ 180.0 (* 4.0 (atan 1.0))))  ; 라디안->도 변환 계수

;; ---- MARKLINE 기능 설정값 ----
(setq *PROFILE-LAYER*   "Q-종단그래프")  ; 종단선(폴리선)이 있는 레이어
(setq *PROFILE-LEN-MIN* 5.0)            ; 대상으로 볼 최소 길이
(setq *PROFILE-LEN-MAX* 20.0)           ; 대상으로 볼 최대 길이
(setq *LINE-MATCH-TOL*  1.0)            ; 원 중심 ~ 선분 사이 허용거리(교차 판정, 기본=원 반지름)
(setq *LINE-ROW-TOL*    50.0)           ; 번호 매길 때 같은 줄로 볼 Y편차 허용치(도면단위)

;; ---- 선B(수직선) 탐색 설정값 ----
(setq *VERT-TOL*        0.01)           ; 이 값 이하의 X편차는 "수직선"으로 간주
(setq *LINEB-MATCH-TOL* 0.15)           ; 선A 좌측끝점 ~ 선B 사이 허용거리 (0~0.1 미만 + 여유)
(setq *LINEC-MATCH-TOL* 0.2)            ; 선B 최하단점 ~ 선C 사이 허용거리

;; ---- 선D(도시가스관로, 선C와 교차) 탐색 설정값 ----
(setq *GAS-LAYER* "도시가스관로")       ; 도시가스관로가 있는 레이어

;; ---- 선그룹Q / 텍스트그룹Q 탐색 설정값 ----
;; 선C 최하단점에서 -Y 방향으로 길이 *VLINE-LENGTH* 인 가상의 선을 만들고,
;; 그 범위와 겹치는 짧은 수직선(선그룹Q)과 텍스트(텍스트그룹Q)를 찾는다.
(setq *VLINE-LENGTH*        52.0)          ; 가상의 선 길이
(setq *LINEQ-LAYER1*        "line")        ; 선그룹Q가 있을 수 있는 레이어1
(setq *LINEQ-LAYER2*        "Q-종단선")    ; 선그룹Q가 있을 수 있는 레이어2
(setq *LINEQ-LEN-MAX*       2.0)           ; 선그룹Q 대상 최대 길이 (이 값 미만)
(setq *LINEQ-X-TOL*         0.1)           ; 선그룹Q 후보선이 같은 세로열(X)로 볼 허용오차
(setq *LINEQ-Y-TOL*         0.1)           ; 가상의 선 끝점 부근 허용오차(Y방향 겹침 판정)
(setq *LINEQ-EXPECTED-COUNT* 7)            ; 선그룹Q 예상 개수 (많지도 적지도 않아야 함)
(setq *TEXTQ-LAYER*         "Q-종단측점")  ; 텍스트그룹Q가 있는 레이어
(setq *TEXTQ-ROT-DEG*       90.0)          ; 텍스트그룹Q 기대 회전각(도)
(setq *TEXTQ-ROT-TOL*       1.0)           ; 회전각 허용오차(도)
(setq *TEXTQ-X-TOL*         0.5)           ; (미사용, 이전 근접도 판정용 - 호환을 위해 유지)
(setq *TEXTQ-INTERSECT-TOL* 0.01)          ; 텍스트 바운딩박스 vs 가상의 선 교차 판정 허용오차
(setq *TEXTQ-EXPECTED-COUNT* 6)            ; 텍스트그룹Q 통상 개수 (0개일 수도 있음, 참고용)
(setq *TEXTQ-Y-DUP-TOL*     1.0)           ; 텍스트그룹Q 6개 초과시, 중복 의심으로 볼 Y편차 허용치
(setq *TEXTQ-NO-KEYWORD*    "NO.")         ; 이 문구를 포함하면 텍스트그룹Q/선그룹Q 전체를 선택 제외

;; ---- 텍스트B / 선F 탐색 설정값 ----
;; 텍스트B: *TEE-LAYER*("Q-종단TEXT")에서 "63mm-3M" 또는 "63mm-45M, 10M" 같은 형식의 텍스트
(setq *TEXTB-ROT-MIN* 28.0)             ; 텍스트B 최소 회전각(도)
(setq *TEXTB-ROT-MAX* 32.0)             ; 텍스트B 최대 회전각(도)

;; ---- FORM 블록 대체(사각형) 탐색 설정값 ----
(setq *FORM-FALLBACK-LAYER* "FORM_")    ; FORM 블록이 없을 때 대신 찾을 사각형이 있는 레이어
(setq *FORM-SIZE-TOL*       0.2)        ; FORM 블록과 사각형 크기 비교 허용오차
(setq *FORM-FALLBACK-WIDTH*  396.9333)  ; "FORM" 블록 정의를 못 찾을 때 사용할 기준 가로 크기
(setq *FORM-FALLBACK-HEIGHT* 273.9767)  ; "FORM" 블록 정의를 못 찾을 때 사용할 기준 세로 크기

;; ==== 유틸리티 함수 ======================================================

;; layerName 레이어가 없으면 생성
(defun fc:ensure-layer (layerName)
  (if (not (tblsearch "LAYER" layerName))
    (entmake
      (list
        (cons 0 "LAYER")
        (cons 100 "AcDbSymbolTableRecord")
        (cons 100 "AcDbLayerTableRecord")
        (cons 2 layerName)
        (cons 70 0)
        (cons 62 7)
        (cons 6 "CONTINUOUS")
      )
    )
  )
)

;; 선택 세트(ss)에 포함된 모든 엔티티를 layerName 레이어로 이관 (레이어 없으면 생성)
(defun fc:move-selection-to-layer (ss layerName / i ent)
  (fc:ensure-layer layerName)
  (if ss
    (progn
      (setq i 0)
      (repeat (sslength ss)
        (setq ent (ssname ss i))
        (vla-put-layer (vlax-ename->vla-object ent) layerName)
        (setq i (1+ i))
      )
    )
  )
)


;; 두 점이 허용오차 이내로 같은 위치인지 (2D)
(defun fc:pt-equal-p (p1 p2 tol)
  (and (<= (abs (- (car p1) (car p2))) tol)
       (<= (abs (- (cadr p1) (cadr p2))) tol))
)

;; 점이 사각형(bmin~bmax) 내부에 있는지 (2D)
(defun fc:pt-in-box-p (pt bmin bmax)
  (and (>= (car  pt) (car  bmin)) (<= (car  pt) (car  bmax))
       (>= (cadr pt) (cadr bmin)) (<= (cadr pt) (cadr bmax)))
)

;; 문자열을 구분자로 분리 -> 리스트
(defun fc:str-split (str delim / pos result)
  (setq result '())
  (while (setq pos (vl-string-search delim str))
    (setq result (append result (list (substr str 1 pos))))
    (setq str (substr str (+ pos 1 (strlen delim))))
  )
  (append result (list str))
)

;; VLA 객체의 바운딩박스 (min max) 반환 -> (bmin bmax)
(defun fc:get-bbox (obj / minp maxp)
  (vla-getboundingbox obj 'minp 'maxp)
  (list (vlax-safearray->list minp) (vlax-safearray->list maxp))
)

;; 월드좌표 점을 블록참조의 로컬좌표(삽입점=원점, 회전/축척 역변환)로 변환
;; insPt: 블록 삽입점(list x y), ang: 회전각(라디안), sx/sy: X/Y축척
(defun fc:world->local (pt insPt ang sx sy / dx dy rx ry)
  (setq dx (- (car pt)  (car insPt)))
  (setq dy (- (cadr pt) (cadr insPt)))
  ;; 역회전 (R(-ang))
  (setq rx (+ (*    dx  (cos ang)) (* dy (sin ang))))
  (setq ry (+ (* (- dx) (sin ang)) (* dy (cos ang))))
  ;; 역축척
  (list (/ rx sx) (/ ry sy))
)

;; "지역-년도-압력-번호" 형식인지 확인 (LP 또는 MP 포함)
(defun fc:is-drawing-code-p (txt)
  (or (wcmatch txt "*-*-LP-*") (wcmatch txt "*-*-MP-*"))
)

;; 객체의 "실질 색상"(ACI) 반환 - ByLayer(256)면 레이어의 색상을 따라감
(defun fc:get-effective-color (obj / col layerName laylist)
  (setq col (vla-get-color obj))
  (if (= col 256)  ; ByLayer
    (progn
      (setq layerName (vla-get-layer obj))
      (setq laylist (tblsearch "LAYER" layerName))
      (if laylist (abs (cdr (assoc 62 laylist))) col)
    )
    col
  )
)

;; 텍스트가 지정된 관경 문구 목록에 포함되는지 확인 (앞뒤 공백 제거 후 정확히 일치)
(defun fc:is-tee-text-p (txt)
  (member (vl-string-trim " " txt) *TEE-TEXTLIST*)
)

;; 점 p 에서 선분 a-b 까지의 최단거리 (2D)
(defun fc:pt-seg-dist (p a b / abx aby apx apy ab2 tt projx projy dx dy)
  (setq abx (- (car b) (car a)) aby (- (cadr b) (cadr a)))
  (setq apx (- (car p) (car a)) apy (- (cadr p) (cadr a)))
  (setq ab2 (+ (* abx abx) (* aby aby)))
  (if (< ab2 1e-9)
    (setq tt 0.0)
    (setq tt (/ (+ (* apx abx) (* apy aby)) ab2))
  )
  (if (< tt 0.0) (setq tt 0.0))
  (if (> tt 1.0) (setq tt 1.0))
  (setq projx (+ (car a) (* tt abx)))
  (setq projy (+ (cadr a) (* tt aby)))
  (setq dx (- (car p) projx) dy (- (cadr p) projy))
  (sqrt (+ (* dx dx) (* dy dy)))
)

;; 평평한 좌표 리스트 (x1 y1 x2 y2 ...) 를 점 쌍 리스트로 변환
(defun fc:pair-flat (lst / result)
  (setq result '())
  (while lst
    (setq result (append result (list (list (car lst) (cadr lst)))))
    (setq lst (cddr lst))
  )
  result
)

;; LINE / LWPOLYLINE 의 정점 리스트(2D) 반환
(defun fc:get-entity-vertices (ent obj / etype)
  (setq etype (cdr (assoc 0 (entget ent))))
  (cond
    ((= etype "LINE")
     (list (vlax-get obj 'StartPoint) (vlax-get obj 'EndPoint))
    )
    ((= etype "LWPOLYLINE")
     (fc:pair-flat (vlax-get obj 'Coordinates))
    )
    (T nil)
  )
)

;; 점 pt 에서 정점 리스트(연결된 선분들)까지의 최단거리
(defun fc:min-dist-to-vertices (pt vertices / v1 v2 minD d)
  (setq minD nil)
  (if (and vertices (>= (length vertices) 2))
    (progn
      (setq v1 (car vertices))
      (foreach v2 (cdr vertices)
        (setq d (fc:pt-seg-dist pt v1 v2))
        (if (or (null minD) (< d minD)) (setq minD d))
        (setq v1 v2)
      )
    )
  )
  minD
)

;; 좌표점을 좌상단->우측, 다음 줄로 정렬 (items: (x y payload) 리스트)
(defun fc:sort-xy-reading-order (items tol / sortedByY rows row curY it r sorted)
  (setq sortedByY (vl-sort items (function (lambda (a b) (> (cadr a) (cadr b))))))
  (setq rows '() row '() curY nil)
  (foreach it sortedByY
    (cond
      ((null curY) (setq curY (cadr it)) (setq row (list it)))
      ((<= (abs (- (cadr it) curY)) tol) (setq row (append row (list it))))
      (T (setq rows (append rows (list row))) (setq row (list it)) (setq curY (cadr it)))
    )
  )
  (if row (setq rows (append rows (list row))))
  (setq sorted '())
  (foreach r rows
    (setq r (vl-sort r (function (lambda (a b) (< (car a) (car b))))))
    (setq sorted (append sorted r))
  )
  sorted
)

;; 정점 리스트가 전부 X편차 tol 이내인 "수직선"인지 확인
(defun fc:is-vertical-vertices (vertices tol / v1 v2 ok)
  (setq ok T)
  (if (and vertices (>= (length vertices) 2))
    (progn
      (setq v1 (car vertices))
      (foreach v2 (cdr vertices)
        (if (> (abs (- (car v2) (car v1))) tol) (setq ok nil))
        (setq v1 v2)
      )
    )
    (setq ok nil)
  )
  ok
)

;; vertices 안에서 refPt 와 맞닿은 "수직 구간"의 두 점을 반환 (없으면 nil)
(defun fc:get-vertical-segment-at (vertices refPt tol / v1 v2 result)
  (setq result nil)
  (if (and vertices (>= (length vertices) 2))
    (progn
      (setq v1 (car vertices))
      (foreach v2 (cdr vertices)
        (if (and (not result)
                 (<= (abs (- (car v2) (car v1))) tol)
                 (or (<= (distance refPt v1) tol) (<= (distance refPt v2) tol)))
          (setq result (list v1 v2))
        )
        (setq v1 v2)
      )
    )
  )
  result
)

;; 선B(lineBEnt) 개체에서 실제 "수직 구간"의 X좌표 및 Y범위를 구함.
;; lineBEnt 전체가 순수 수직선이면 전체 정점 기준, 대각선+수직이 섞인 혼합개체이면
;; refPt 와 맞닿은 수직 구간만 골라서 그 구간 기준으로 계산한다.
;; 리턴: (xB minY maxY) / 알 수 없으면 (nil nil nil)
(defun fc:get-vertical-part-range (lineBEnt refPt tol / verts seg xB minY maxY)
  (setq verts (fc:get-entity-vertices lineBEnt (vlax-ename->vla-object lineBEnt)))
  (if (fc:is-vertical-vertices verts tol)
    (progn
      (setq xB (car (car verts)))
      (setq minY (apply 'min (mapcar 'cadr verts)))
      (setq maxY (apply 'max (mapcar 'cadr verts)))
    )
    (progn
      (setq seg (fc:get-vertical-segment-at verts refPt tol))
      (if seg
        (progn
          (setq xB (car (car seg)))
          (setq minY (min (cadr (car seg)) (cadr (cadr seg))))
          (setq maxY (max (cadr (car seg)) (cadr (cadr seg))))
        )
      )
    )
  )
  (list xB minY maxY)
)

;; 선B(lineBEnt) 기준 우측(X ~ X+1 이내), 같은 Y범위 안에 'RED' 포함 텍스트가 있는지 확인
;; refPt: 혼합개체(대각선+수직)일 때 수직 구간을 특정하기 위한 기준점 (예: leftPt 또는 텍스트A 좌표)
(defun fc:has-red-text-nearby (lineBEnt refPt / rng xB minY maxY ss i ent obj txt pt found)
  (setq rng (fc:get-vertical-part-range lineBEnt refPt *VERT-TOL*))
  (setq xB (nth 0 rng) minY (nth 1 rng) maxY (nth 2 rng))
  (setq found nil)
  (if xB
    (progn
      (setq ss (ssget "_X" (list (cons 0 "TEXT,MTEXT") (cons 8 *TEE-LAYER*))))
      (if ss
        (progn
          (setq i 0)
          (repeat (sslength ss)
            (setq ent (ssname ss i))
            (if (not found)
              (progn
                (setq obj (vlax-ename->vla-object ent))
                (setq txt (vla-get-textstring obj))
                (if (vl-string-search "RED" txt)
                  (progn
                    (setq pt (vlax-get obj 'InsertionPoint))
                    (if (and (>= (car pt) xB) (<= (car pt) (+ xB 1.0))
                             (>= (cadr pt) minY) (<= (cadr pt) maxY))
                      (setq found T)
                    )
                  )
                )
              )
            )
            (setq i (1+ i))
          )
        )
      )
    )
  )
  found
)

;; 정점 리스트 중 X가 가장 작은(가장 왼쪽) 점 반환
(defun fc:get-left-vertex (vertices / minV v)
  (setq minV (car vertices))
  (foreach v (cdr vertices)
    (if (< (car v) (car minV)) (setq minV v))
  )
  minV
)

;; 하나의 폴리선(vertices) 안에 leftPt 와 맞닿은 "수직 구간"이 포함되어 있는지 확인
;; (선A와 선B가 정점 여러 개짜리 폴리선 하나로 합쳐져 있는 경우를 위함)
(defun fc:find-internal-vertical (vertices refPt tol / v1 v2 found)
  (setq found nil)
  (if (and vertices (>= (length vertices) 2))
    (progn
      (setq v1 (car vertices))
      (foreach v2 (cdr vertices)
        (if (and (not found)
                 (<= (abs (- (car v2) (car v1))) tol)          ; 수직 구간 (X편차 거의 없음)
                 (or (<= (distance refPt v1) tol) (<= (distance refPt v2) tol))  ; leftPt와 맞닿음
            )
          (setq found T)
        )
        (setq v1 v2)
      )
    )
  )
  found
)

;; 정점 리스트 중 Y가 가장 작은(가장 아래) 점 반환
(defun fc:get-bottom-vertex (vertices / minV v)
  (setq minV (car vertices))
  (foreach v (cdr vertices)
    (if (< (cadr v) (cadr minV)) (setq minV v))
  )
  minV
)

;; bottomPt(선B의 최하단점) 기준으로, 그 아래에 맞닿은 수직선(선C) 탐색
;; excludeEnt(선B 자신)는 후보에서 제외
;; 리턴: (line-ent distance) / 못 찾으면 (nil nil)
(defun fc:find-vertical-line-below (bottomPt excludeEnt / ss i ent obj verts best bestD d)
  (setq best nil bestD nil)
  (setq ss (ssget "_X" (list (cons 0 "LINE,LWPOLYLINE") (cons 8 *PROFILE-LAYER*))))
  (if ss
    (progn
      (setq i 0)
      (repeat (sslength ss)
        (setq ent (ssname ss i))
        (if (not (equal ent excludeEnt))
          (progn
            (setq obj (vlax-ename->vla-object ent))
            (setq verts (fc:get-entity-vertices ent obj))
            (if (fc:is-vertical-vertices verts *VERT-TOL*)
              (progn
                (setq d (fc:min-dist-to-vertices bottomPt verts))
                (if (and d (<= d *LINEC-MATCH-TOL*) (or (null bestD) (< d bestD)))
                  (progn (setq best ent) (setq bestD d))
                )
              )
            )
          )
        )
        (setq i (1+ i))
      )
    )
  )
  (list best bestD)
)

;; 텍스트 엔티티 리스트 중 *TEXTQ-NO-KEYWORD* 문구를 포함한 것이 하나라도 있는지 확인
(defun fc:group-has-keyword (entList keyword / e txt found)
  (setq found nil)
  (foreach e entList
    (if (not found)
      (progn
        (setq txt (vla-get-textstring (vlax-ename->vla-object e)))
        (if (vl-string-search keyword txt) (setq found T))
      )
    )
  )
  found
)

;; 텍스트 엔티티 리스트 중 Y좌표가 서로 tol 이내로 비슷한(중복 의심) 것들을 모두 반환
(defun fc:find-duplicate-y-texts (entList tol / items i j n e1 e2 y1 y2 result)
  (setq items
    (mapcar
      (function
        (lambda (e / pt)
          (setq pt (vlax-get (vlax-ename->vla-object e) 'InsertionPoint))
          (cons e (cadr pt))
        )
      )
      entList
    )
  )
  (setq result '())
  (setq n (length items))
  (setq i 0)
  (while (< i n)
    (setq e1 (car (nth i items)) y1 (cdr (nth i items)))
    (setq j (1+ i))
    (while (< j n)
      (setq e2 (car (nth j items)) y2 (cdr (nth j items)))
      (if (<= (abs (- y1 y2)) tol)
        (progn
          (if (not (member e1 result)) (setq result (cons e1 result)))
          (if (not (member e2 result)) (setq result (cons e2 result)))
        )
      )
      (setq j (1+ j))
    )
    (setq i (1+ i))
  )
  result
)

;; TEXT/MTEXT 의 실제 "표시 위치"를 정확히 반환 (2D)
;; TEXT가 Left/Baseline이 아닌 정렬(중간, 중앙 등)일 경우 InsertionPoint(그룹10)가 아니라
;; 정렬점(그룹11)을 사용해야 정확한 위치가 나옴 - ActiveX InsertionPoint 속성의 함정을 우회
(defun fc:get-text-position (ent / elist etype h v p10 p11)
  (setq elist (entget ent))
  (setq etype (cdr (assoc 0 elist)))
  (cond
    ((= etype "TEXT")
     (setq h (cdr (assoc 72 elist)))
     (setq v (cdr (assoc 73 elist)))
     (setq p10 (cdr (assoc 10 elist)))
     (setq p11 (cdr (assoc 11 elist)))
     (if (and (or (and h (/= h 0)) (and v (/= v 0))) p11)
       (list (car p11) (cadr p11))
       (list (car p10) (cadr p10))
     )
    )
    (T
     (setq p10 (cdr (assoc 10 elist)))
     (list (car p10) (cadr p10))
    )
  )
)

;; 문자열이 전부 숫자(0-9)로만 이루어져 있는지 확인 (길이 0이면 nil)
(defun fc:all-digits-p (str / i c ok)
  (setq ok (> (strlen str) 0))
  (setq i 1)
  (while (and ok (<= i (strlen str)))
    (setq c (substr str i 1))
    (if (not (wcmatch c "#")) (setq ok nil))
    (setq i (1+ i))
  )
  ok
)

;; "<숫자>M" 형식(끝이 반드시 M, 그 앞은 전부 숫자)인지 확인
(defun fc:is-digitM-token-p (tok / part)
  (if (or (= (strlen tok) 0) (/= (substr tok (strlen tok) 1) "M"))
    nil
    (progn
      (setq part (substr tok 1 (1- (strlen tok))))
      (fc:all-digits-p part)
    )
  )
)

;; "63mm-3M" 또는 "63mm-45M, 10M" 과 같은 형식인지 확인
;; ("mm-" 뒤에 ","로 구분된 "<숫자>M" 토큰이 1개 이상 이어지는 형식)
(defun fc:is-textB-code-p (txt / pos part1 rest tokens tok valid)
  (setq pos (vl-string-search "mm-" txt))
  (if (not pos)
    nil
    (progn
      (setq part1 (substr txt 1 pos))
      (setq rest  (substr txt (+ pos 4)))
      (if (or (= (strlen rest) 0) (not (fc:all-digits-p part1)))
        nil
        (progn
          (setq tokens (fc:str-split rest ","))
          (setq valid T)
          (foreach tok tokens
            (setq tok (vl-string-trim " " tok))
            (if (not (fc:is-digitM-token-p tok))
              (setq valid nil)
            )
          )
          (and valid (> (length tokens) 0))
        )
      )
    )
  )
)

;; *TEE-LAYER* 에서 텍스트B 후보(문구형식 + 회전각) 를 모두 수집
;; 리턴: ((x y ent txt) ...)
(defun fc:find-textB-candidates ( / ss i ent obj txt rot deg pt lst)
  (setq lst '())
  (setq ss (ssget "_X" (list (cons 0 "TEXT,MTEXT") (cons 8 *TEE-LAYER*))))
  (if ss
    (progn
      (setq i 0)
      (repeat (sslength ss)
        (setq ent (ssname ss i))
        (setq obj (vlax-ename->vla-object ent))
        (setq txt (vla-get-textstring obj))
        (if (fc:is-textB-code-p txt)
          (progn
            (setq rot (vla-get-rotation obj))
            (setq deg (* rot *RAD2DEG*))
            (if (< deg 0) (setq deg (+ deg 360.0)))
            (if (and (>= deg *TEXTB-ROT-MIN*) (<= deg *TEXTB-ROT-MAX*))
              (progn
                (setq pt (vlax-get obj 'InsertionPoint))
                (setq lst (append lst (list (list (car pt) (cadr pt) ent txt))))
              )
            )
          )
        )
        (setq i (1+ i))
      )
    )
  )
  lst
)

;; candidates(텍스트B 후보 전체) 중에서 curY 보다 아래(-Y)에 있는 것이 하나라도 있는지 확인
(defun fc:has-text-below-p (curY candidates / found c)
  (setq found nil)
  (foreach c candidates
    (if (and (not found) (< (cadr c) (- curY 1e-6))) (setq found T))
  )
  found
)

;; 지정 레이어에서 keyword 를 포함하는 텍스트를 모두 찾음
;; 리턴: ((ent (x y) txt) ...)
(defun fc:find-text-by-content (layerName keyword / ss i ent obj txt lst pt)
  (setq lst '())
  (setq ss (ssget "_X" (list (cons 0 "TEXT,MTEXT") (cons 8 layerName))))
  (if ss
    (progn
      (setq i 0)
      (repeat (sslength ss)
        (setq ent (ssname ss i))
        (setq obj (vlax-ename->vla-object ent))
        (setq txt (vla-get-textstring obj))
        (if (vl-string-search keyword txt)
          (progn
            (setq pt (vlax-get obj 'InsertionPoint))
            (setq lst (append lst (list (list ent (list (car pt) (cadr pt)) txt))))
          )
        )
        (setq i (1+ i))
      )
    )
  )
  lst
)

;; (tx ty) 지점을 기준으로 선A->선B->선C->선그룹Q->텍스트그룹Q 를 동일한 방식으로 탐색해서
;; 발견된 엔티티를 모두 리스트로 반환 (선택 여부와 무관하게 순수 탐색만 수행)
(defun fc:find-chain-entities (tx ty / result res lineEnt lineVerts leftPt lineBEnt
                                  resB fallbackEnt lineBVerts bottomPt resC lineCEnt
                                  lineCVerts bottomPtC groupQLines groupQTexts lineDEnt)
  (setq result '())
  (setq lineBEnt nil)
  (setq res (fc:find-profile-line (list tx ty)))
  (setq lineEnt (car res))
  (if lineEnt
    (progn
      (setq result (cons lineEnt result))
      (setq lineVerts (fc:get-entity-vertices lineEnt (vlax-ename->vla-object lineEnt)))
      (setq leftPt (fc:get-left-vertex lineVerts))
      (if (fc:find-internal-vertical lineVerts leftPt *VERT-TOL*)
        (setq lineBEnt lineEnt)
        (progn
          (setq resB (fc:find-vertical-line-left leftPt))
          (setq lineBEnt (car resB))
          (if lineBEnt (setq result (cons lineBEnt result)))
        )
      )
    )
    (progn
      (setq fallbackEnt (fc:find-line-3pt-fallback (list tx ty)))
      (if fallbackEnt
        (progn
          (setq lineBEnt fallbackEnt)
          (setq result (cons lineBEnt result))
        )
      )
    )
  )
  (if lineBEnt
    (progn
      (setq lineBVerts (fc:get-entity-vertices lineBEnt (vlax-ename->vla-object lineBEnt)))
      (setq bottomPt (fc:get-bottom-vertex lineBVerts))
      (setq resC (fc:find-vertical-line-below bottomPt lineBEnt))
      (setq lineCEnt (car resC))
      (if lineCEnt
        (progn
          (setq result (cons lineCEnt result))
          (setq lineDEnt (fc:find-intersecting-gas-pipe lineCEnt))
          (if lineDEnt (setq result (cons lineDEnt result)))
          (setq lineCVerts (fc:get-entity-vertices lineCEnt (vlax-ename->vla-object lineCEnt)))
          (setq bottomPtC (fc:get-bottom-vertex lineCVerts))
          (setq groupQLines (fc:find-line-group-q bottomPtC *VLINE-LENGTH*))
          (setq groupQTexts (fc:find-text-group-q bottomPtC *VLINE-LENGTH*))
          (setq result (append result groupQLines groupQTexts))
        )
      )
    )
  )
  result
)

;; 여러 레이어에서 지정된 타입의 엔티티를 모두 모아서 반환
(defun fc:collect-from-layers (types layers / ss i ent lst ly)
  (setq lst '())
  (foreach ly layers
    (setq ss (ssget "_X" (list (cons 0 types) (cons 8 ly))))
    (if ss
      (progn
        (setq i 0)
        (repeat (sslength ss)
          (setq lst (append lst (list (ssname ss i))))
          (setq i (1+ i))
        )
      )
    )
  )
  lst
)

;; 선C 최하단점(topPt) 기준 -Y 방향 길이 vlen 인 가상의 선과 겹치는
;; 짧은 수직선(길이 < *LINEQ-LEN-MAX*)들을 *LINEQ-LAYER1*/*LINEQ-LAYER2* 에서 찾음 (선그룹Q)
(defun fc:find-line-group-q (topPt vlen / bx byTop byBottom ents ent obj verts len candX minY maxY lst)
  (setq bx (car topPt) byTop (cadr topPt) byBottom (- byTop vlen))
  (setq lst '())
  (setq ents (fc:collect-from-layers "LINE,LWPOLYLINE" (list *LINEQ-LAYER1* *LINEQ-LAYER2*)))
  (foreach ent ents
    (setq obj (vlax-ename->vla-object ent))
    (setq verts (fc:get-entity-vertices ent obj))
    (setq len (vla-get-length obj))
    (if (and verts (fc:is-vertical-vertices verts *VERT-TOL*) (< len *LINEQ-LEN-MAX*))
      (progn
        (setq candX (car (car verts)))
        (setq minY (apply 'min (mapcar 'cadr verts)))
        (setq maxY (apply 'max (mapcar 'cadr verts)))
        (if (and (<= (abs (- candX bx)) *LINEQ-X-TOL*)
                 (<= minY (+ byTop *LINEQ-Y-TOL*))
                 (>= maxY (- byBottom *LINEQ-Y-TOL*)))
          (setq lst (append lst (list ent)))
        )
      )
    )
  )
  lst
)

;; 선C 최하단점(topPt) 기준 -Y 방향 길이 vlen 인 가상의 선이
;; 실제로 지나가는(바운딩박스 교차) 회전각 *TEXTQ-ROT-DEG* 인
;; *TEXTQ-LAYER* 텍스트를 찾음 (텍스트그룹Q)
(defun fc:find-text-group-q (topPt vlen / bx byTop byBottom ss i ent obj rot deg bbox bmin bmax lst)
  (setq bx (car topPt) byTop (cadr topPt) byBottom (- byTop vlen))
  (setq lst '())
  (setq ss (ssget "_X" (list (cons 0 "TEXT,MTEXT") (cons 8 *TEXTQ-LAYER*))))
  (if ss
    (progn
      (setq i 0)
      (repeat (sslength ss)
        (setq ent (ssname ss i))
        (setq obj (vlax-ename->vla-object ent))
        (setq rot (vla-get-rotation obj))
        (setq deg (* rot *RAD2DEG*))
        (if (< deg 0) (setq deg (+ deg 360.0)))
        (if (<= (abs (- deg *TEXTQ-ROT-DEG*)) *TEXTQ-ROT-TOL*)
          (progn
            ;; 텍스트의 실제 바운딩박스를 가상의 선(X=bx, Y=[byBottom,byTop])이
            ;; 실제로 지나가는지 확인 (근접도가 아니라 실제 교차)
            (setq bbox (fc:get-bbox obj))
            (setq bmin (car bbox) bmax (cadr bbox))
            (if (and (>= bx (- (car bmin) *TEXTQ-INTERSECT-TOL*))
                     (<= bx (+ (car bmax) *TEXTQ-INTERSECT-TOL*))
                     (<= (cadr bmin) (+ byTop *TEXTQ-INTERSECT-TOL*))
                     (>= (cadr bmax) (- byBottom *TEXTQ-INTERSECT-TOL*)))
              (setq lst (append lst (list ent)))
            )
          )
        )
        (setq i (1+ i))
      )
    )
  )
  lst
)

;; 선C(lineCEnt)와 실제로 기하학적으로 교차하는 *GAS-LAYER* 개체를 찾음
;; ActiveX IntersectWith 를 사용하므로 호(bulge)가 섞인 폴리선도 정확히 처리됨
;; 리턴: 교차하는 엔티티 / 없으면 nil
(defun fc:find-intersecting-gas-pipe (lineCEnt / ss i ent obj lineCObj result interArr)
  (setq lineCObj (vlax-ename->vla-object lineCEnt))
  (setq result nil)
  (setq ss (ssget "_X" (list (cons 0 "LINE,LWPOLYLINE") (cons 8 *GAS-LAYER*))))
  (if ss
    (progn
      (setq i 0)
      (repeat (sslength ss)
        (setq ent (ssname ss i))
        (if (not result)
          (progn
            (setq obj (vlax-ename->vla-object ent))
            (setq interArr (vl-catch-all-apply 'vlax-invoke (list lineCObj 'IntersectWith obj 0)))
            (if (and (not (vl-catch-all-error-p interArr)) interArr (> (length interArr) 0))
              (setq result ent)
            )
          )
        )
        (setq i (1+ i))
      )
    )
  )
  result
)

;; leftPt(선A의 좌측끝점) 기준으로, 왼쪽(또는 같은 X)에 있는 수직선(선B) 탐색
;; 리턴: (line-ent distance) / 못 찾으면 (nil nil)
(defun fc:find-vertical-line-left (leftPt / ss i ent obj verts best bestD d xB)
  (setq best nil bestD nil)
  (setq ss (ssget "_X" (list (cons 0 "LINE,LWPOLYLINE") (cons 8 *PROFILE-LAYER*))))
  (if ss
    (progn
      (setq i 0)
      (repeat (sslength ss)
        (setq ent (ssname ss i))
        (setq obj (vlax-ename->vla-object ent))
        (setq verts (fc:get-entity-vertices ent obj))
        (if (fc:is-vertical-vertices verts *VERT-TOL*)
          (progn
            (setq xB (car (car verts)))
            (if (<= xB (+ (car leftPt) *VERT-TOL*))
              (progn
                (setq d (fc:min-dist-to-vertices leftPt verts))
                (if (and d (<= d *LINEB-MATCH-TOL*) (or (null bestD) (< d bestD)))
                  (progn (setq best ent) (setq bestD d))
                )
              )
            )
          )
        )
        (setq i (1+ i))
      )
    )
  )
  (list best bestD)
)
;; 리턴: (line-ent distance) / 못 찾으면 (nil nil)
(defun fc:find-profile-line (centerPt / ss i ent obj len verts d best bestD)
  (setq best nil bestD nil)
  (setq ss (ssget "_X" (list (cons 0 "LINE,LWPOLYLINE") (cons 8 *PROFILE-LAYER*))))
  (if ss
    (progn
      (setq i 0)
      (repeat (sslength ss)
        (setq ent (ssname ss i))
        (setq obj (vlax-ename->vla-object ent))
        (setq len (vla-get-length obj))
        (if (and (>= len *PROFILE-LEN-MIN*) (<= len *PROFILE-LEN-MAX*))
          (progn
            (setq verts (fc:get-entity-vertices ent obj))
            (setq d (fc:min-dist-to-vertices centerPt verts))
            (if (and d (<= d *LINE-MATCH-TOL*) (or (null bestD) (< d bestD)))
              (progn (setq best ent) (setq bestD d))
            )
          )
        )
        (setq i (1+ i))
      )
    )
  )
  (list best bestD)
)

;; 정점 리스트 중 centerPt 와의 거리가 tol 이내인 "구간(세그먼트)" 개수 반환
(defun fc:count-near-segments (centerPt vertices tol / v1 v2 cnt d)
  (setq cnt 0)
  (if (and vertices (>= (length vertices) 2))
    (progn
      (setq v1 (car vertices))
      (foreach v2 (cdr vertices)
        (setq d (fc:pt-seg-dist centerPt v1 v2))
        (if (<= d tol) (setq cnt (1+ cnt)))
        (setq v1 v2)
      )
    )
  )
  cnt
)

;; [예외케이스] 선A 를 못 찾았을 때만 사용:
;; 정점이 정확히 3개이고, 가상의 원(반지름 *LINE-MATCH-TOL*)이 두 구간 모두와 맞닿는(교차점 2개)
;; 선/폴리선을 찾음 -> 이 경우 선A가 아니라 선B 로 간주
;; 리턴: line-ent / 못 찾으면 nil
(defun fc:find-line-3pt-fallback (centerPt / ss i ent obj verts cnt best)
  (setq best nil)
  (setq ss (ssget "_X" (list (cons 0 "LINE,LWPOLYLINE") (cons 8 *PROFILE-LAYER*))))
  (if ss
    (progn
      (setq i 0)
      (repeat (sslength ss)
        (setq ent (ssname ss i))
        (setq obj (vlax-ename->vla-object ent))
        (setq verts (fc:get-entity-vertices ent obj))
        (if (and verts (= (length verts) 3) (not best))
          (progn
            (setq cnt (fc:count-near-segments centerPt verts *LINE-MATCH-TOL*))
            (if (= cnt 2) (setq best ent))
          )
        )
        (setq i (1+ i))
      )
    )
  )
  best
)

;; 코드 문자열 파싱 -> (지역 년도 압력 번호) / 형식 불일치시 nil
(defun fc:parse-code (txt / parts)
  (setq parts (fc:str-split txt "-"))
  (if (= (length parts) 4)
    parts
    nil
  )
)

;; ==== 1) FORM 블록 수집 (다이나믹블록 EffectiveName 기준) + 중복 제거 ======
;; 리턴 항목 형식: (ent bmin bmax insPt ang sx sy)

(defun fc:get-form-blocks ( / ss i ent obj insPt ang sx sy bbox bmin bmax lst found)
  (setq lst '())
  (setq ss (ssget "_X" (list (cons 0 "INSERT"))))
  (if ss
    (progn
      (setq i 0)
      (repeat (sslength ss)
        (setq ent (ssname ss i))
        (setq obj (vlax-ename->vla-object ent))
        (if (= (strcase (vla-get-effectivename obj)) (strcase *FORM-BLKNAME*))
          (progn
            (setq insPt (vlax-get obj 'InsertionPoint))
            (setq insPt (list (car insPt) (cadr insPt)))
            (setq found nil)
            (foreach item lst
              (if (fc:pt-equal-p insPt (nth 3 item) *DUP-TOL*)
                (setq found T)
              )
            )
            (if (not found)
              (progn
                (setq ang (vla-get-rotation obj))
                (setq sx  (vla-get-xscalefactor obj))
                (setq sy  (vla-get-yscalefactor obj))
                (setq bbox (fc:get-bbox obj))
                (setq bmin (car bbox) bmax (cadr bbox))
                (setq lst (append lst (list (list ent bmin bmax insPt ang sx sy))))
              )
            )
          )
        )
        (setq i (1+ i))
      )
    )
  )
  lst
)

;; ==== 1-1) FORM 블록이 없을 때: FORM_ 레이어의 대체 사각형 탐색 ============

;; 정점 리스트가 정확히 4개이고, 축에 정렬된 직사각형 모양인지 확인
(defun fc:is-axis-rect (vertices tol / minX maxX minY maxY v ok)
  (setq ok T)
  (if (/= (length vertices) 4)
    (setq ok nil)
    (progn
      (setq minX (car (car vertices)) maxX minX)
      (setq minY (cadr (car vertices)) maxY minY)
      (foreach v vertices
        (if (< (car  v) minX) (setq minX (car  v)))
        (if (> (car  v) maxX) (setq maxX (car  v)))
        (if (< (cadr v) minY) (setq minY (cadr v)))
        (if (> (cadr v) maxY) (setq maxY (cadr v)))
      )
      (foreach v vertices
        (if (not (and (or (<= (abs (- (car  v) minX)) tol) (<= (abs (- (car  v) maxX)) tol))
                      (or (<= (abs (- (cadr v) minY)) tol) (<= (abs (- (cadr v) maxY)) tol))))
          (setq ok nil)
        )
      )
    )
  )
  ok
)

;; FORM 블록 "정의"의 바운딩박스 반환 (블록 정의 자체 좌표계, 원점=삽입기준점)
;; 리턴: (defMin defMax) / 정의를 찾을 수 없으면 nil
(defun fc:get-block-def-bbox (blkName / doc blocks res minp maxp)
  (setq doc (vla-get-activedocument (vlax-get-acad-object)))
  (setq blocks (vla-get-blocks doc))
  (setq res (vl-catch-all-apply 'vla-item (list blocks blkName)))
  (if (vl-catch-all-error-p res)
    nil
    (progn
      (setq res (vl-catch-all-apply 'vla-getboundingbox (list res 'minp 'maxp)))
      (if (vl-catch-all-error-p res)
        nil
        (list (vlax-safearray->list minp) (vlax-safearray->list maxp))
      )
    )
  )
)

;; *FORM-FALLBACK-LAYER* 에서 FORM 블록과 같은 크기(오차 *FORM-SIZE-TOL*)의
;; 축정렬 직사각형(닫힌 LWPOLYLINE, 정점4개)을 찾아 FORM 블록 대체용으로 반환
;; 리턴 항목 형식: (ent bmin bmax insPt ang sx sy) - ang=0, sx=sy=1
(defun fc:get-form-rectangles (refMin refMax / refW refH ss i ent obj verts
                                 bmin bmax w h insPtSub lst found item closedFlag)
  (setq refW (- (car refMax) (car refMin)))
  (setq refH (- (cadr refMax) (cadr refMin)))
  (setq lst '())
  (setq ss (ssget "_X" (list (cons 0 "LWPOLYLINE") (cons 8 *FORM-FALLBACK-LAYER*))))
  (if ss
    (progn
      (setq i 0)
      (repeat (sslength ss)
        (setq ent (ssname ss i))
        (setq obj (vlax-ename->vla-object ent))
        (setq verts (fc:get-entity-vertices ent obj))
        (setq closedFlag (cdr (assoc 70 (entget ent))))
        (if (and verts (fc:is-axis-rect verts 1e-4)
                 closedFlag (= (logand closedFlag 1) 1))
          (progn
            (setq bmin (list (apply 'min (mapcar 'car verts)) (apply 'min (mapcar 'cadr verts))))
            (setq bmax (list (apply 'max (mapcar 'car verts)) (apply 'max (mapcar 'cadr verts))))
            (setq w (- (car bmax) (car bmin)))
            (setq h (- (cadr bmax) (cadr bmin)))
            (if (and (<= (abs (- w refW)) *FORM-SIZE-TOL*) (<= (abs (- h refH)) *FORM-SIZE-TOL*))
              (progn
                ;; FORM 블록 삽입기준점에 대응하는 위치로 환산(사각형 최소점 - 블록정의 최소점)
                (setq insPtSub (list (- (car bmin) (car refMin)) (- (cadr bmin) (cadr refMin))))
                (setq found nil)
                (foreach item lst
                  (if (fc:pt-equal-p insPtSub (nth 3 item) *DUP-TOL*) (setq found T))
                )
                (if (not found)
                  (setq lst (append lst (list (list ent bmin bmax insPtSub 0.0 1.0 1.0))))
                )
              )
            )
          )
        )
        (setq i (1+ i))
      )
    )
  )
  lst
)

;; FORM 블록을 우선 찾고, 없으면 FORM_ 레이어의 대체 사각형으로 대신함
;; 기준 크기: "FORM" 블록 정의가 있으면 그 바운딩박스를 사용하고,
;; 블록 정의 자체가 없으면(도면에 FORM 블록이 전혀 없는 경우) *FORM-FALLBACK-WIDTH*/
;; *FORM-FALLBACK-HEIGHT* 고정값을 기준으로 사용한다.
(defun fc:get-form-blocks-or-fallback ( / lst defbbox refMin refMax)
  (setq lst (fc:get-form-blocks))
  (if lst
    lst
    (progn
      (princ (strcat "\n>> FORM 블록을 찾지 못해 레이어 \"" *FORM-FALLBACK-LAYER*
                      "\" 에서 대체 사각형을 탐색합니다..."))
      (setq defbbox (fc:get-block-def-bbox *FORM-BLKNAME*))
      (if defbbox
        (progn
          (setq refMin (car defbbox) refMax (cadr defbbox))
          (princ (strcat "\n>> \"" *FORM-BLKNAME* "\" 블록 정의 기준 크기 사용"))
        )
        (progn
          (setq refMin (list 0.0 0.0))
          (setq refMax (list *FORM-FALLBACK-WIDTH* *FORM-FALLBACK-HEIGHT*))
          (princ (strcat "\n>> \"" *FORM-BLKNAME* "\" 블록 정의를 찾을 수 없어 고정 기준 크기("
                          (rtos *FORM-FALLBACK-WIDTH* 2 4) " x " (rtos *FORM-FALLBACK-HEIGHT* 2 4)
                          ")를 사용합니다."))
        )
      )
      (setq lst (fc:get-form-rectangles refMin refMax))
      (if lst
        (princ (strcat "\n>> 대체 사각형 " (itoa (length lst)) "개 발견"))
        (princ (strcat "\n>> 레이어 \"" *FORM-FALLBACK-LAYER* "\" 에서도 조건에 맞는 사각형을 찾지 못했습니다."))
      )
      lst
    )
  )
)

;; ==== 2) 읽기순서 정렬 (좌상단 -> 우측, 다음 줄로) =========================
;; blkList 의 각 항목: (ent bmin bmax insPt ang sx sy)
;; 리턴: 동일한 형식의 리스트, 읽기순서대로 정렬됨

(defun fc:sort-reading-order (blkList / info avgH tol sorted rows row curRowY it r)
  ;; 각 블록의 중심점 / 높이 계산 (bbox는 이미 blkList에 포함되어 있음)
  (setq info
    (mapcar
      (function
        (lambda (b / bmin bmax cx cy h)
          (setq bmin (nth 1 b) bmax (nth 2 b))
          (setq cx (/ (+ (car  bmin) (car  bmax)) 2.0))
          (setq cy (/ (+ (cadr bmin) (cadr bmax)) 2.0))
          (setq h  (- (cadr bmax) (cadr bmin)))
          (list b cx cy h)
        )
      )
      blkList
    )
  )
  ;; 평균 높이로 행 구분 허용오차 산출
  (setq avgH (/ (apply '+ (mapcar (function (lambda (x) (nth 3 x))) info))
                (float (length info))))
  (setq tol (* avgH *ROW-TOL-RATIO*))
  ;; Y 내림차순(위->아래) 우선 정렬
  (setq info (vl-sort info (function (lambda (a b) (> (nth 2 a) (nth 2 b))))))
  ;; 행 그룹핑
  (setq rows '())
  (setq row '())
  (setq curRowY nil)
  (foreach it info
    (cond
      ((null curRowY)
       (setq curRowY (nth 2 it))
       (setq row (list it))
      )
      ((<= (abs (- (nth 2 it) curRowY)) tol)
       (setq row (append row (list it)))
      )
      (T
       (setq rows (append rows (list row)))
       (setq row (list it))
       (setq curRowY (nth 2 it))
      )
    )
  )
  (if row (setq rows (append rows (list row))))
  ;; 각 행 내부는 X 오름차순(좌->우) 정렬
  (setq sorted '())
  (foreach r rows
    (setq r (vl-sort r (function (lambda (a b) (< (nth 1 a) (nth 1 b))))))
    (setq sorted (append sorted r))
  )
  ;; 원본 레코드(ent bmin bmax insPt ang sx sy)만 추출해서 반환
  (mapcar (function (lambda (x) (nth 0 x))) sorted)
)

;; ==== 3) 레이어 T 의 도면번호 텍스트 전체 수집 =============================
;; 리턴: ((pt txt) (pt txt) ...) - 형식에 맞는 것만

(defun fc:collect-code-texts ( / ss i ent obj txt pt lst)
  (setq lst '())
  (setq ss (ssget "_X" (list (cons 0 "TEXT,MTEXT") (cons 8 *TEXT-LAYER*))))
  (if ss
    (progn
      (setq i 0)
      (repeat (sslength ss)
        (setq ent (ssname ss i))
        (setq obj (vlax-ename->vla-object ent))
        (setq txt (vla-get-textstring obj))
        (if (fc:is-drawing-code-p txt)
          (progn
            (setq pt (vlax-get obj 'InsertionPoint))
            (setq pt (list (car pt) (cadr pt)))
            (setq lst (append lst (list (list pt txt))))
          )
        )
        (setq i (1+ i))
      )
    )
  )
  lst
)

;; ==== 3-1) 텍스트 위치 범위(로컬좌표) 자동 설정 명령 =======================
;; FORM 블록 1개를 선택하고, 텍스트가 위치하는 영역의 두 코너를 지정하면
;; 그 블록 기준 로컬좌표 범위를 계산해서 *TEXT-LOCAL-MIN* / *TEXT-LOCAL-MAX* 에 저장

(defun c:FORMSETAREA ( / ent elist obj insPt ang sx sy p1 p2 lp1 lp2)
  (princ "\n기준으로 사용할 FORM 블록을 선택하세요: ")
  (setq ent (car (entsel)))
  (if (not ent)
    (princ "\n>> 선택되지 않았습니다.")
    (progn
      (setq elist (entget ent))
      (if (/= (cdr (assoc 0 elist)) "INSERT")
        (princ "\n>> 블록(INSERT)이 아닙니다. 다시 시도하세요.")
        (progn
          (setq obj   (vlax-ename->vla-object ent))
          (setq insPt (vlax-get obj 'InsertionPoint))
          (setq ang   (vla-get-rotation obj))
          (setq sx    (vla-get-xscalefactor obj))
          (setq sy    (vla-get-yscalefactor obj))
          (setq p1 (getpoint "\n텍스트 영역의 한쪽 코너를 지정하세요: "))
          (setq p2 (getpoint p1 "\n반대쪽 코너를 지정하세요: "))
          (setq lp1 (fc:world->local p1 insPt ang sx sy))
          (setq lp2 (fc:world->local p2 insPt ang sx sy))
          (setq *TEXT-LOCAL-MIN*
            (list (min (car lp1) (car lp2)) (min (cadr lp1) (cadr lp2))))
          (setq *TEXT-LOCAL-MAX*
            (list (max (car lp1) (car lp2)) (max (cadr lp1) (cadr lp2))))
          (princ "\n>> 로컬좌표 범위가 설정되었습니다 (이번 세션에서 바로 사용 가능):")
          (princ (strcat "\n   MIN = (" (rtos (car *TEXT-LOCAL-MIN*) 2 4)
                          ", " (rtos (cadr *TEXT-LOCAL-MIN*) 2 4) ")"))
          (princ (strcat "\n   MAX = (" (rtos (car *TEXT-LOCAL-MAX*) 2 4)
                          ", " (rtos (cadr *TEXT-LOCAL-MAX*) 2 4) ")"))
          (princ "\n>> 다음 실행부터 매번 다시 지정하지 않으려면, 아래 두 줄을")
          (princ "\n   FormCheck.lsp 상단 설정값 부분에 붙여넣어 영구 저장하세요:")
          (princ (strcat "\n(setq *TEXT-LOCAL-MIN* (list " (rtos (car *TEXT-LOCAL-MIN*) 2 4)
                          " " (rtos (cadr *TEXT-LOCAL-MIN*) 2 4) "))"))
          (princ (strcat "\n(setq *TEXT-LOCAL-MAX* (list " (rtos (car *TEXT-LOCAL-MAX*) 2 4)
                          " " (rtos (cadr *TEXT-LOCAL-MAX*) 2 4) "))"))
        )
      )
    )
  )
  (princ)
)

;; ==== 4) 블록 <-> 텍스트 매칭 (로컬좌표 범위 기준) ==========================
;; 각 블록의 삽입점/회전/축척으로 "로컬좌표계"를 만들고, 모든 후보 텍스트를
;; 그 로컬좌표로 변환해서 *TEXT-LOCAL-MIN*~*TEXT-LOCAL-MAX* 범위 안에 드는지만 검사한다.
;; 그래도 혹시 후보가 2개 이상 걸리면(진짜 중복 등) 블록 중심에 가까운 순으로 그리디 배정.
;; 리턴: ((blockIndex . text) (blockIndex . text) ...), 진단정보는 전역변수(*fc-cand-count*)에 저장

(defun fc:assign-texts (sortedList textList / pairs bi ti blk bmin bmax cx cy
                          dx dy d usedBlocks usedTexts result txtItem candCount
                          insPt ang sx sy lpt)
  (if (or (null *TEXT-LOCAL-MIN*) (null *TEXT-LOCAL-MAX*))
    (progn
      (princ "\n>> 오류: *TEXT-LOCAL-MIN* / *TEXT-LOCAL-MAX* 가 설정되지 않았습니다.")
      (princ "\n>> 먼저 FORMSETAREA 명령을 실행해 텍스트 위치 범위를 지정하세요.")
      nil
    )
    (progn
      (setq *fc-cand-count* '())  ; 블록별 후보 텍스트 개수(진단용)
      (setq pairs '())
      (setq bi 0)
      (foreach blk sortedList
        (setq bmin (nth 1 blk) bmax (nth 2 blk))
        (setq insPt (nth 3 blk) ang (nth 4 blk) sx (nth 5 blk) sy (nth 6 blk))
        (setq cx (/ (+ (car bmin) (car bmax)) 2.0))
        (setq cy (/ (+ (cadr bmin) (cadr bmax)) 2.0))
        (setq candCount 0)
        (setq ti 0)
        (foreach txtItem textList
          (setq lpt (fc:world->local (car txtItem) insPt ang sx sy))
          (if (fc:pt-in-box-p lpt *TEXT-LOCAL-MIN* *TEXT-LOCAL-MAX*)
            (progn
              (setq candCount (1+ candCount))
              (setq dx (- (car (car txtItem)) cx))
              (setq dy (- (cadr (car txtItem)) cy))
              (setq d (sqrt (+ (* dx dx) (* dy dy))))
              (setq pairs (cons (list d bi ti) pairs))
            )
          )
          (setq ti (1+ ti))
        )
        (setq *fc-cand-count* (append *fc-cand-count* (list candCount)))
        (setq bi (1+ bi))
      )
      ;; 거리 오름차순 정렬 (가까운 조합부터 확정) - 진짜 중복이 있을 때의 안전장치
      (setq pairs (vl-sort pairs (function (lambda (a b) (< (car a) (car b))))))
      (setq usedBlocks '())
      (setq usedTexts  '())
      (setq result '())
      (foreach p pairs
        (setq bi (nth 1 p) ti (nth 2 p))
        (if (and (not (member bi usedBlocks)) (not (member ti usedTexts)))
          (progn
            (setq usedBlocks (cons bi usedBlocks))
            (setq usedTexts  (cons ti usedTexts))
            (setq result (cons (cons bi (cadr (nth ti textList))) result))
          )
        )
      )
      result
    )
  )
)

;; ==== 메인 명령 ===========================================================

(defun c:FORMCHECK ( / formList sortedList textList idx b bmin bmax
                        matchTxt code press num lpCount mpCount unknownCount noTextCount
                        assignList bi0 cnt)
  (vl-load-com)
  (princ "\n[FORM 블록 검색 중...]")
  (setq formList (fc:get-form-blocks-or-fallback))

  (cond
    ((not formList)
     (princ "\n>> FORM 블록도, 대체 사각형도 찾을 수 없습니다.")
    )
    (T
     (princ (strcat "\n>> 총 " (itoa (length formList)) "개 FORM(또는 대체) 발견(중복 제거 후)"))
     (setq sortedList (fc:sort-reading-order formList))
     (setq textList (fc:collect-code-texts))
     (princ (strcat "\n>> 레이어 \"" *TEXT-LAYER* "\" 에서 형식에 맞는 텍스트 "
                     (itoa (length textList)) "개 발견"))

     (if (or (null *TEXT-LOCAL-MIN*) (null *TEXT-LOCAL-MAX*))
       (princ "\n>> 먼저 FORMSETAREA 명령으로 텍스트 위치 범위를 지정한 뒤 다시 실행하세요.")
       (progn
     (setq assignList (fc:assign-texts sortedList textList))

     (setq idx 0 lpCount 0 mpCount 0 unknownCount 0 noTextCount 0)
     (foreach b sortedList
       (setq idx (1+ idx))
       (setq bi0 (1- idx))
       (setq bmin (nth 1 b) bmax (nth 2 b))
       (setq matchTxt (cdr (assoc bi0 assignList)))
       ;; 바운딩박스 중첩으로 후보가 2개 이상이었던 경우 경고 표시
       (setq cnt (nth bi0 *fc-cand-count*))
       (if (and cnt (> cnt 1))
         (princ (strcat "\n   [경고] 순서 " (itoa idx)
                         " 블록 바운딩박스 안에 텍스트 후보 " (itoa cnt)
                         "개 발견됨 (겹침 가능성, 최근접 텍스트로 자동 선택됨)"))
       )
       (cond
         ((not matchTxt)
          (setq noTextCount (1+ noTextCount))
          (princ (strcat "\n[순서 " (itoa idx) "] 도면번호 텍스트를 찾을 수 없음"))
         )
         (T
          (setq code (fc:parse-code matchTxt))
          (if (not code)
            (progn
              (setq unknownCount (1+ unknownCount))
              (princ (strcat "\n[순서 " (itoa idx) "] 형식 불일치 텍스트: " matchTxt))
            )
            (progn
              (setq press (strcase (nth 2 code)))
              (setq num   (nth 3 code))
              (cond
                ((= press "LP")
                 (setq lpCount (1+ lpCount))
                 (princ (strcat "\n[순서 " (itoa idx) "] 저압(LP) 도면번호: "
                                 num "   (" matchTxt ")"))
                )
                ((= press "MP")
                 (setq mpCount (1+ mpCount))
                 (princ (strcat "\n[순서 " (itoa idx) "] 중압(MP) 도면번호: "
                                 num "   (" matchTxt ")"))
                )
                (T
                 (setq unknownCount (1+ unknownCount))
                 (princ (strcat "\n[순서 " (itoa idx) "] 압력구분 불명: " matchTxt))
                )
              )
            )
          )
         )
       )
     )
     (princ (strcat "\n\n>> 결과: 저압(LP) " (itoa lpCount)
                     "개, 중압(MP) " (itoa mpCount)
                     "개, 형식불일치/불명 " (itoa unknownCount)
                     "개, 텍스트없음 " (itoa noTextCount) "개"))
       )
     )
    )
  )
  (princ)
  (princ)
)

(princ "\nFormCheck.lsp 로드 완료 - 명령: FORMCHECK")
(princ)

;;;=======================================================================
;;; MARKTEE - 관경 문구 텍스트 위치에 원 표시
;;;-----------------------------------------------------------------------
;;; 대상 조건 (전부 만족해야 함)
;;;  - 레이어 : *TEE-LAYER*  (기본 "Q-종단TEXT")
;;;  - 문구   : *TEE-TEXTLIST* 목록과 정확히 일치
;;;  - 회전각 : *TEE-ROT-MIN* ~ *TEE-ROT-MAX* 도 (기본 28~32)
;;;  - 색상   : *TEE-COLOR*  (기본 1 = 빨강, ByLayer인 경우 레이어 색상으로 판단)
;;; 동작
;;;  - 조건에 맞는 텍스트의 삽입기준점에 반지름 *TEE-RADIUS* 원을
;;;    *MARK-LAYER* 레이어(기본 "0기술검토")에 생성. 레이어 없으면 자동 생성.
;;;=======================================================================

(defun c:MARKTEE ( / ss i ent obj txt rot deg ecol pt cnt skipRot skipColor)
  (vl-load-com)

  ;; 표시용 레이어가 없으면 생성 (색상 7=흰/검정, 실선)
  (if (not (tblsearch "LAYER" *MARK-LAYER*))
    (progn
      (entmake
        (list
          (cons 0 "LAYER")
          (cons 100 "AcDbSymbolTableRecord")
          (cons 100 "AcDbLayerTableRecord")
          (cons 2 *MARK-LAYER*)
          (cons 70 0)
          (cons 62 7)
          (cons 6 "CONTINUOUS")
        )
      )
      (princ (strcat "\n>> 레이어 \"" *MARK-LAYER* "\" 생성됨"))
    )
  )

  (setq cnt 0 skipRot 0 skipColor 0)
  (setq ss (ssget "_X" (list (cons 0 "TEXT,MTEXT") (cons 8 *TEE-LAYER*))))
  (if ss
    (progn
      (setq i 0)
      (repeat (sslength ss)
        (setq ent (ssname ss i))
        (setq obj (vlax-ename->vla-object ent))
        (setq txt (vla-get-textstring obj))
        (if (fc:is-tee-text-p txt)
          (progn
            (setq rot (vla-get-rotation obj))
            (setq deg (* rot *RAD2DEG*))
            (if (< deg 0) (setq deg (+ deg 360.0)))
            (setq ecol (fc:get-effective-color obj))
            (cond
              ((not (and (>= deg *TEE-ROT-MIN*) (<= deg *TEE-ROT-MAX*)))
               (setq skipRot (1+ skipRot))
              )
              ((/= ecol *TEE-COLOR*)
               (setq skipColor (1+ skipColor))
              )
              (T
               (setq pt (vlax-get obj 'InsertionPoint))
               (setq pt (list (car pt) (cadr pt)
                               (if (caddr pt) (caddr pt) 0.0)))
               (entmake
                 (list
                   (cons 0 "CIRCLE")
                   (cons 8 *MARK-LAYER*)
                   (cons 10 pt)
                   (cons 40 *TEE-RADIUS*)
                 )
               )
               (setq cnt (1+ cnt))
              )
            )
          )
        )
        (setq i (1+ i))
      )
    )
  )
  (princ (strcat "\n>> 원 " (itoa cnt) "개 생성 완료 (레이어: " *MARK-LAYER*
                  ", 반지름 " (rtos *TEE-RADIUS* 2 1) ")"))
  (if (> skipRot 0)
    (princ (strcat "\n   (문구는 일치하나 회전각 조건(28~32도) 불충족: " (itoa skipRot) "개 제외)")))
  (if (> skipColor 0)
    (princ (strcat "\n   (문구/회전각은 일치하나 색상(빨강) 조건 불충족: " (itoa skipColor) "개 제외)")))
  (princ)
)

(princ "\nMARKTEE 명령 사용 가능")
(princ)

;;;=======================================================================
;;; MARKLINE - MARKTEE 원과 교차하는 종단선(폴리선) 찾기 + 번호 매기기
;;;-----------------------------------------------------------------------
;;; 대상 조건
;;;  - 레이어 : *PROFILE-LAYER*  (기본 "Q-종단그래프")
;;;  - 개체   : LINE 또는 LWPOLYLINE
;;;  - 길이   : *PROFILE-LEN-MIN* ~ *PROFILE-LEN-MAX* (기본 5~20)
;;;  - 원(0기술검토 레이어, 반지름 *TEE-RADIUS*)의 중심점과 선분 사이 최단거리가
;;;    *LINE-MATCH-TOL* 이내이면 "교차/접촉"으로 판단
;;; 동작
;;;  - 원들을 좌상단->우측, 다음 줄로 정렬 후 순서대로 매칭된 선을
;;;    "N번 선"으로 명명(명령행 출력) 하고, 찾은 선들을 그립 선택 상태로 표시
;;;=======================================================================

(defun c:MARKLINE ( / ss i ent obj cen items sortedItems idx it cx cy circEnt
                       res lineEnt lineDist matchSS foundCount notFoundCount)
  (vl-load-com)
  (setq ss (ssget "_X" (list (cons 0 "CIRCLE") (cons 8 *MARK-LAYER*) (cons 40 *TEE-RADIUS*))))
  (cond
    ((not ss)
     (princ (strcat "\n>> 레이어 \"" *MARK-LAYER* "\" 에서 반지름 " (rtos *TEE-RADIUS* 2 1)
                     " 원을 찾을 수 없습니다. 먼저 MARKTEE를 실행하세요."))
    )
    (T
     (setq items '())
     (setq i 0)
     (repeat (sslength ss)
       (setq ent (ssname ss i))
       (setq obj (vlax-ename->vla-object ent))
       (setq cen (vlax-get obj 'Center))
       (setq items (append items (list (list (car cen) (cadr cen) ent))))
       (setq i (1+ i))
     )
     (setq sortedItems (fc:sort-xy-reading-order items *LINE-ROW-TOL*))
     (setq idx 0 foundCount 0 notFoundCount 0)
     (setq matchSS (ssadd))
     (foreach it sortedItems
       (setq idx (1+ idx))
       (setq cx (car it) cy (cadr it) circEnt (caddr it))
       (setq res (fc:find-profile-line (list cx cy)))
       (setq lineEnt (car res) lineDist (cadr res))
       (if lineEnt
         (progn
           (setq foundCount (1+ foundCount))
           (ssadd lineEnt matchSS)
           (princ (strcat "\n[" (itoa idx) "번 선] 핸들=" (cdr (assoc 5 (entget lineEnt)))
                           "  길이=" (rtos (vla-get-length (vlax-ename->vla-object lineEnt)) 2 4)
                           "  원과의거리=" (rtos lineDist 2 4)))
         )
         (progn
           (setq notFoundCount (1+ notFoundCount))
           (princ (strcat "\n[" (itoa idx) "번] 조건에 맞는 선(폴리선)을 찾을 수 없음"))
         )
       )
     )
     (princ (strcat "\n\n>> 총 " (itoa (sslength ss)) "개 원 중 "
                     (itoa foundCount) "개 선 매칭, " (itoa notFoundCount) "개 미검출"))
     (if (> foundCount 0) (sssetfirst nil matchSS))
    )
  )
  (princ)
)

(princ "\nMARKLINE 명령 사용 가능")
(princ)

;;;=======================================================================
;;; GGL (구 TEELINE) - MARKTEE + MARKLINE 통합 (원을 실제로 그리지 않고 가상 좌표로 매칭)
;;;-----------------------------------------------------------------------
;;; 1) 레이어 *TEE-LAYER* 에서 조건(문구/회전각/색상)에 맞는 텍스트를 찾음
;;;    -> 이것을 "텍스트A" 라고 명명
;;; 2) 텍스트A 의 삽입기준점을 "가상의 원 중심"으로 사용해서
;;;    레이어 *PROFILE-LAYER* 에서 조건(길이)에 맞고 그 점과 맞닿는 선을 찾음
;;;    -> 이것을 "선A1, 선A2 ..." 라고 명명 (텍스트A 처리 순서와 동일한 번호)
;;; 3) 실제 CIRCLE 엔티티는 생성하지 않음
;;;=======================================================================

(defun c:GGL ( / ss i ent obj txt rot deg ecol pt items sortedItems idx it
                      tx ty payload res lineEnt lineDist foundCount notFoundCount matchSS
                      lineVerts leftPt resB lineBEnt lineBDist foundBCount notFoundBCount
                      fallbackEnt lineBVerts bottomPt resC lineCEnt lineCDist
                      foundCCount notFoundCCount lineDEnt foundDCount notFoundDCount
                      lineBIsSeparate hasRedNearby lineBRefPt
                      lineCVerts bottomPtC groupQLines groupQTexts e
                      skipGroupQ dupQTexts dq
                      textBList textBSorted idxB tb payloadB tbx tby tbEnt tbTxt
                      resF lineFEnt lineFDist foundFCount notFoundFCount skippedNoBelowCount
                      gjList gjIdx gj gjPt gjChain gjRemoved ce)
  (vl-load-com)
  (setq *GGL-REDCOUNT* 0)  ; 텍스트그룹Q 중복(빨간색 표시) 개수 추적용 전역변수 초기화

  ;; ---- 1) 텍스트A 후보 수집 (MARKTEE와 동일한 조건, 원은 만들지 않음) ----
  (setq items '())
  (setq ss (ssget "_X" (list (cons 0 "TEXT,MTEXT") (cons 8 *TEE-LAYER*))))
  (if ss
    (progn
      (setq i 0)
      (repeat (sslength ss)
        (setq ent (ssname ss i))
        (setq obj (vlax-ename->vla-object ent))
        (setq txt (vla-get-textstring obj))
        (if (fc:is-tee-text-p txt)
          (progn
            (setq rot (vla-get-rotation obj))
            (setq deg (* rot *RAD2DEG*))
            (if (< deg 0) (setq deg (+ deg 360.0)))
            (setq ecol (fc:get-effective-color obj))
            (if (and (>= deg *TEE-ROT-MIN*) (<= deg *TEE-ROT-MAX*) (= ecol *TEE-COLOR*))
              (progn
                (setq pt (vlax-get obj 'InsertionPoint))
                ;; payload: (텍스트엔티티 . 텍스트문자열)
                (setq items (append items (list (list (car pt) (cadr pt) (cons ent txt)))))
              )
            )
          )
        )
        (setq i (1+ i))
      )
    )
  )

  (cond
    ((= (length items) 0)
     (princ "\n>> 조건에 맞는 텍스트A 후보를 찾을 수 없습니다.")
    )
    (T
     ;; ---- 2) 텍스트A 를 좌상단->우측, 다음 줄로 정렬 ----
     (setq sortedItems (fc:sort-xy-reading-order items *LINE-ROW-TOL*))
     (setq idx 0 foundCount 0 notFoundCount 0 foundBCount 0 notFoundBCount 0
           foundCCount 0 notFoundCCount 0 foundDCount 0 notFoundDCount 0)
     (setq matchSS (ssadd))

     ;; ---- 3) 각 텍스트A 의 위치(가상 원 중심)로 선 탐색 ----
     (foreach it sortedItems
       (setq idx (1+ idx))
       (setq tx (car it) ty (cadr it) payload (caddr it))
       (setq lineBEnt nil lineBIsSeparate nil hasRedNearby nil lineBRefPt nil)  ; 매 반복마다 초기화
       (setq res (fc:find-profile-line (list tx ty)))
       (setq lineEnt (car res) lineDist (cadr res))
       (ssadd (car payload) matchSS)  ; 텍스트A 엔티티 선택 대상에 포함
       (princ (strcat "\n[텍스트A " (itoa idx) "] " (cdr payload)))
       (if lineEnt
         (progn
           (setq foundCount (1+ foundCount))
           (ssadd lineEnt matchSS)    ; 매칭된 선A 엔티티도 선택 대상에 포함
           (princ (strcat "  ->  [선A" (itoa idx) "] 핸들=" (cdr (assoc 5 (entget lineEnt)))
                           "  길이=" (rtos (vla-get-length (vlax-ename->vla-object lineEnt)) 2 4)
                           "  거리=" (rtos lineDist 2 4)))
           ;; ---- 선A 의 좌측끝점 기준으로 선B(수직선) 탐색 ----
           (setq lineVerts (fc:get-entity-vertices lineEnt (vlax-ename->vla-object lineEnt)))
           (setq leftPt (fc:get-left-vertex lineVerts))
           ;; 먼저 선A 자신(폴리선 내부)에 수직구간이 포함되어 있는지 확인
           (if (fc:find-internal-vertical lineVerts leftPt *VERT-TOL*)
             (progn
               (setq lineBEnt lineEnt lineBDist 0.0 lineBIsSeparate nil lineBRefPt leftPt)
               (setq foundBCount (1+ foundBCount))
               (princ (strcat "  ->  [선B" (itoa idx) "] 선A와 동일 개체 (내부 수직구간 포함)"))
             )
             (progn
               (setq resB (fc:find-vertical-line-left leftPt))
               (setq lineBEnt (car resB) lineBDist (cadr resB) lineBIsSeparate T lineBRefPt leftPt)
               (if lineBEnt
                 (progn
                   (setq foundBCount (1+ foundBCount))
                   (princ (strcat "  ->  [선B" (itoa idx) "] 핸들=" (cdr (assoc 5 (entget lineBEnt)))
                                   "  길이=" (rtos (vla-get-length (vlax-ename->vla-object lineBEnt)) 2 4)
                                   "  거리=" (rtos lineBDist 2 4)))
                 )
                 (progn
                   (setq notFoundBCount (1+ notFoundBCount))
                   (princ "  ->  [선B] 대응하는 수직선을 찾을 수 없음")
                 )
               )
             )
           )
         )
         (progn
           (setq notFoundCount (1+ notFoundCount))
           ;; ---- [예외케이스] 선A 를 못 찾았을 때만: 3점 폴리선 + 교차점2개 -> 선B로 간주 ----
           (setq fallbackEnt (fc:find-line-3pt-fallback (list tx ty)))
           (if fallbackEnt
             (progn
               (setq lineBEnt fallbackEnt lineBIsSeparate T lineBRefPt (list tx ty))
               (setq foundBCount (1+ foundBCount))
               (princ (strcat "  ->  대응하는 선A 없음, 대신 [선B" (itoa idx) "] 핸들="
                               (cdr (assoc 5 (entget fallbackEnt)))
                               "  (예외케이스: 3점 폴리선, 교차점2개)"))
             )
             (princ "  ->  대응하는 선을 찾을 수 없음")
           )
         )
       )
       ;; ---- 선B 우측(X+1 이내)에 'RED' 포함 텍스트가 있는지 확인 ----
       ;; 있으면 선B/선C/선D/선그룹Q/텍스트그룹Q 는 선택(그립)과 레이어 이관에서 모두 제외 (선A는 그대로 선택)
       (setq hasRedNearby (if lineBEnt (fc:has-red-text-nearby lineBEnt lineBRefPt) nil))
       (if (and lineBEnt lineBIsSeparate (not hasRedNearby))
         (ssadd lineBEnt matchSS)
       )
       (if hasRedNearby
         (princ (strcat "  ->  [경고] 선B" (itoa idx) " 우측 X+1 이내 'RED' 텍스트 발견 - "
                         "선B/선C/선D/선그룹Q/텍스트그룹Q 선택 제외"))
       )
       ;; ---- 선B가 있으면(어떤 경로로 찾았든), 그 최하단점 기준으로 선C 탐색 ----
       (if lineBEnt
         (progn
           (setq lineBVerts (fc:get-entity-vertices lineBEnt (vlax-ename->vla-object lineBEnt)))
           (setq bottomPt (fc:get-bottom-vertex lineBVerts))
           (setq resC (fc:find-vertical-line-below bottomPt lineBEnt))
           (setq lineCEnt (car resC) lineCDist (cadr resC))
           (if lineCEnt
             (progn
               (setq foundCCount (1+ foundCCount))
               (if (not hasRedNearby) (ssadd lineCEnt matchSS))
               (princ (strcat "  ->  [선C" (itoa idx) "] 핸들=" (cdr (assoc 5 (entget lineCEnt)))
                               "  길이=" (rtos (vla-get-length (vlax-ename->vla-object lineCEnt)) 2 4)
                               "  거리=" (rtos lineCDist 2 4)))
               ;; ---- 선C와 교차하는 도시가스관로(선D) 탐색 ----
               (setq lineDEnt (fc:find-intersecting-gas-pipe lineCEnt))
               (if lineDEnt
                 (progn
                   (setq foundDCount (1+ foundDCount))
                   (if (not hasRedNearby) (ssadd lineDEnt matchSS))
                   (princ (strcat "  ->  [선D" (itoa idx) "] 핸들=" (cdr (assoc 5 (entget lineDEnt)))))
                 )
                 (progn
                   (setq notFoundDCount (1+ notFoundDCount))
                   (princ "  ->  [선D] 교차하는 도시가스관로를 찾을 수 없음")
                 )
               )
               ;; ---- 선C 최하단점 기준 가상의 선(-Y, 길이52) 범위의 선그룹Q / 텍스트그룹Q 탐색 ----
               (setq lineCVerts (fc:get-entity-vertices lineCEnt (vlax-ename->vla-object lineCEnt)))
               (setq bottomPtC (fc:get-bottom-vertex lineCVerts))
               (setq groupQLines (fc:find-line-group-q bottomPtC *VLINE-LENGTH*))
               (setq groupQTexts (fc:find-text-group-q bottomPtC *VLINE-LENGTH*))
               (setq skipGroupQ nil dupQTexts nil)
               (cond
                 ;; 1) 'NO.' 포함 텍스트가 있으면 그룹 전체와 선C를 선택 대상에서 제외
                 ((fc:group-has-keyword groupQTexts *TEXTQ-NO-KEYWORD*)
                  (setq skipGroupQ T)
                  (ssdel lineCEnt matchSS)  ; 이미 선택된 선C를 선택 목록에서 제거
                  (princ (strcat "  ->  [선C" (itoa idx) "/선그룹Q" (itoa idx) "/텍스트그룹Q" (itoa idx)
                                  "] '" *TEXTQ-NO-KEYWORD* "' 포함 텍스트 발견 - 선택 제외"))
                 )
                 ;; 2) 6개 초과이면서 Y좌표 유사(중복 의심) 텍스트가 있으면 빨간색 처리 후 선택 제외
                 ((> (length groupQTexts) *TEXTQ-EXPECTED-COUNT*)
                  (setq dupQTexts (fc:find-duplicate-y-texts groupQTexts *TEXTQ-Y-DUP-TOL*))
                  (if dupQTexts
                    (progn
                      (foreach dq dupQTexts (vla-put-color (vlax-ename->vla-object dq) 1))
                      (setq groupQTexts (vl-remove-if (function (lambda (x) (member x dupQTexts))) groupQTexts))
                      (setq *GGL-REDCOUNT* (+ *GGL-REDCOUNT* (length dupQTexts)))
                      (princ (strcat "  ->  [텍스트그룹Q" (itoa idx) "] 6개 초과, Y좌표 유사 "
                                      (itoa (length dupQTexts)) "개를 빨간색으로 표시하고 선택 제외"))
                    )
                  )
                 )
               )
               (if (and (not skipGroupQ) (not hasRedNearby))
                 (progn
                   (foreach e groupQLines (ssadd e matchSS))
                   (foreach e groupQTexts (ssadd e matchSS))
                 )
               )
               (princ (strcat "  ->  [선그룹Q" (itoa idx) "] " (itoa (length groupQLines)) "개 발견"
                               (if (/= (length groupQLines) *LINEQ-EXPECTED-COUNT*)
                                 (strcat " (경고: 예상 " (itoa *LINEQ-EXPECTED-COUNT*) "개와 다름)")
                                 ""
                               )))
               (princ (strcat "  ->  [텍스트그룹Q" (itoa idx) "] " (itoa (length groupQTexts)) "개 발견"))
             )
             (progn
               (setq notFoundCCount (1+ notFoundCCount))
               (princ "  ->  [선C] 대응하는 하단 수직선을 찾을 수 없음")
             )
           )
         )
       )
     )
     (princ (strcat "\n\n>> 총 텍스트A " (itoa (length sortedItems)) "개 중 "
                     (itoa foundCount) "개 선A 매칭, " (itoa notFoundCount) "개 미검출"))
     (princ (strcat "\n>> 선B " (itoa foundBCount) "개 매칭, " (itoa notFoundBCount) "개 미검출"))
     (princ (strcat "\n>> 선C " (itoa foundCCount) "개 매칭, " (itoa notFoundCCount) "개 미검출"))
     (princ (strcat "\n>> 선D " (itoa foundDCount) "개 매칭, " (itoa notFoundDCount) "개 미검출"))

     ;; ==== 2단계: 텍스트B / 선F (텍스트A 체인과 독립적인 별도 그룹) ====
     (princ "\n\n[텍스트B / 선F 검색]")
     (setq textBList (fc:find-textB-candidates))
     (setq textBSorted
       (fc:sort-xy-reading-order
         (mapcar (function (lambda (c) (list (car c) (cadr c) c))) textBList)
         *LINE-ROW-TOL*
       )
     )
     (setq idxB 0 foundFCount 0 notFoundFCount 0 skippedNoBelowCount 0)
     (foreach tb textBSorted
       (setq idxB (1+ idxB))
       (setq payloadB (caddr tb))
       (setq tbx (car payloadB) tby (cadr payloadB) tbEnt (caddr payloadB) tbTxt (cadddr payloadB))
       (ssadd tbEnt matchSS)
       (princ (strcat "\n[텍스트B " (itoa idxB) "] " tbTxt))
       (if (fc:has-text-below-p tby textBList)
         (progn
           (setq resF (fc:find-profile-line (list tbx tby)))
           (setq lineFEnt (car resF) lineFDist (cadr resF))
           (if lineFEnt
             (progn
               (setq foundFCount (1+ foundFCount))
               (ssadd lineFEnt matchSS)
               (princ (strcat "  ->  [선F" (itoa idxB) "] 핸들=" (cdr (assoc 5 (entget lineFEnt)))
                               "  길이=" (rtos (vla-get-length (vlax-ename->vla-object lineFEnt)) 2 4)
                               "  거리=" (rtos lineFDist 2 4)))
             )
             (progn
               (setq notFoundFCount (1+ notFoundFCount))
               (princ "  ->  [선F] 대응하는 선을 찾을 수 없음")
             )
           )
         )
         (progn
           (setq skippedNoBelowCount (1+ skippedNoBelowCount))
           (princ "  ->  하단에 동일 조건 텍스트B 없음 - 선F 매칭 대상 아님")
         )
       )
     )
     (princ (strcat "\n\n>> 텍스트B " (itoa (length textBList)) "개 중 선F "
                     (itoa foundFCount) "개 매칭, " (itoa notFoundFCount) "개 미검출, "
                     (itoa skippedNoBelowCount) "개는 하단 텍스트 없어 대상제외"))

     ;; ==== 3단계: '공사종점' 텍스트 기준 체인은 선택(및 레이어 이관)에서 제외 ====
     (princ "\n\n[공사종점 확인]")
     (setq gjList (fc:find-text-by-content *TEE-LAYER* "공사종점"))
     (if (= (length gjList) 0)
       (princ "\n>> '공사종점' 텍스트를 찾을 수 없습니다.")
       (progn
         (setq gjIdx 0)
         (foreach gj gjList
           (setq gjIdx (1+ gjIdx))
           (setq gjPt (cadr gj))
           (setq gjChain (fc:find-chain-entities (car gjPt) (cadr gjPt)))
           (setq gjRemoved 0)
           (foreach ce gjChain
             (if (ssdel ce matchSS) (setq gjRemoved (1+ gjRemoved)))
           )
           (princ (strcat "\n[공사종점 " (itoa gjIdx) "] 연관 엔티티 " (itoa (length gjChain))
                           "개 확인, 이미 선택되어 있던 " (itoa gjRemoved) "개를 선택 제외"))
         )
       )
     )

     ;; ---- 선택된 엔티티들을 *MARK-LAYER*("0기술검토") 레이어로 이관 ----
     (if (> (sslength matchSS) 0)
       (progn
         (fc:move-selection-to-layer matchSS *MARK-LAYER*)
         (princ (strcat "\n>> 선택된 엔티티 " (itoa (sslength matchSS))
                         "개를 \"" *MARK-LAYER* "\" 레이어로 이관했습니다."))
       )
     )
     (if (> (sslength matchSS) 0) (sssetfirst nil matchSS))
    )
  )
  (princ)
)

(princ "\nGGL 명령 사용 가능 (구 TEELINE, MARKTEE+MARKLINE 통합, 원 미생성)")
(princ)

;;;=======================================================================
;;; TEELINE1 - 텍스트A 를 직접 선택해서 동일한 탐색 체인을 검증
;;;-----------------------------------------------------------------------
;;; GGL(구 TEELINE) 의 자동 필터(문구/회전각/색상)를 거치지 않고, 사용자가 직접 선택한
;;; TEXT/MTEXT 하나를 기준으로 선A->선B->선C->선D->선그룹Q->텍스트그룹Q 를
;;; 그대로 실행해서 결과를 확인한다. (디버깅/검증용)
;;;=======================================================================

(defun c:TEELINE1 ( / ent obj txt tx ty pt res lineEnt lineDist lineVerts leftPt
                       lineBEnt resB fallbackEnt lineBVerts bottomPt resC lineCEnt
                       lineDEnt lineCVerts bottomPtC groupQLines groupQTexts matchSS e
                       skipGroupQ dupQTexts dq)
  (vl-load-com)
  (princ "\n검증할 텍스트A 후보를 선택하세요: ")
  (setq ent (car (entsel)))
  (cond
    ((not ent)
     (princ "\n>> 선택되지 않았습니다.")
    )
    ((not (member (cdr (assoc 0 (entget ent))) (list "TEXT" "MTEXT")))
     (princ "\n>> TEXT 또는 MTEXT 가 아닙니다.")
    )
    (T
     (setq obj (vlax-ename->vla-object ent))
     (setq txt (vla-get-textstring obj))
     (setq pt (vlax-get obj 'InsertionPoint))
     (setq tx (car pt) ty (cadr pt))
     (setq matchSS (ssadd))
     (ssadd ent matchSS)
     (princ (strcat "\n[텍스트A(선택)] " txt))

     ;; ---- 선A ----
     (setq res (fc:find-profile-line (list tx ty)))
     (setq lineEnt (car res) lineDist (cadr res))
     (setq lineBEnt nil)
     (if lineEnt
       (progn
         (ssadd lineEnt matchSS)
         (princ (strcat "  ->  [선A] 핸들=" (cdr (assoc 5 (entget lineEnt)))
                         "  길이=" (rtos (vla-get-length (vlax-ename->vla-object lineEnt)) 2 4)
                         "  거리=" (rtos lineDist 2 4)))
         ;; ---- 선B (선A 내부 수직구간 우선 확인, 없으면 좌측 별도 탐색) ----
         (setq lineVerts (fc:get-entity-vertices lineEnt (vlax-ename->vla-object lineEnt)))
         (setq leftPt (fc:get-left-vertex lineVerts))
         (if (fc:find-internal-vertical lineVerts leftPt *VERT-TOL*)
           (progn
             (setq lineBEnt lineEnt)
             (princ "  ->  [선B] 선A와 동일 개체 (내부 수직구간 포함)")
           )
           (progn
             (setq resB (fc:find-vertical-line-left leftPt))
             (setq lineBEnt (car resB))
             (if lineBEnt
               (progn
                 (ssadd lineBEnt matchSS)
                 (princ (strcat "  ->  [선B] 핸들=" (cdr (assoc 5 (entget lineBEnt)))
                                 "  길이=" (rtos (vla-get-length (vlax-ename->vla-object lineBEnt)) 2 4)
                                 "  거리=" (rtos (cadr resB) 2 4)))
               )
               (princ "  ->  [선B] 대응하는 수직선을 찾을 수 없음")
             )
           )
         )
       )
       (progn
         (princ "  ->  대응하는 선A 없음")
         ;; ---- [예외케이스] 3점 폴리선 + 교차점2개 -> 선B로 간주 ----
         (setq fallbackEnt (fc:find-line-3pt-fallback (list tx ty)))
         (if fallbackEnt
           (progn
             (setq lineBEnt fallbackEnt)
             (ssadd fallbackEnt matchSS)
             (princ (strcat "  ->  대신 [선B] 핸들=" (cdr (assoc 5 (entget fallbackEnt)))
                             "  (예외케이스: 3점 폴리선, 교차점2개)"))
           )
           (princ "  ->  대응하는 선을 찾을 수 없음")
         )
       )
     )

     ;; ---- 선C ----
     (if lineBEnt
       (progn
         (setq lineBVerts (fc:get-entity-vertices lineBEnt (vlax-ename->vla-object lineBEnt)))
         (setq bottomPt (fc:get-bottom-vertex lineBVerts))
         (setq resC (fc:find-vertical-line-below bottomPt lineBEnt))
         (setq lineCEnt (car resC))
         (if lineCEnt
           (progn
             (ssadd lineCEnt matchSS)
             (princ (strcat "  ->  [선C] 핸들=" (cdr (assoc 5 (entget lineCEnt)))
                             "  길이=" (rtos (vla-get-length (vlax-ename->vla-object lineCEnt)) 2 4)
                             "  거리=" (rtos (cadr resC) 2 4)))
             ;; ---- 선D ----
             (setq lineDEnt (fc:find-intersecting-gas-pipe lineCEnt))
             (if lineDEnt
               (progn
                 (ssadd lineDEnt matchSS)
                 (princ (strcat "  ->  [선D] 핸들=" (cdr (assoc 5 (entget lineDEnt)))))
               )
               (princ "  ->  [선D] 교차하는 도시가스관로를 찾을 수 없음")
             )
             ;; ---- 선그룹Q / 텍스트그룹Q ----
             (setq lineCVerts (fc:get-entity-vertices lineCEnt (vlax-ename->vla-object lineCEnt)))
             (setq bottomPtC (fc:get-bottom-vertex lineCVerts))
             (setq groupQLines (fc:find-line-group-q bottomPtC *VLINE-LENGTH*))
             (setq groupQTexts (fc:find-text-group-q bottomPtC *VLINE-LENGTH*))
             (setq skipGroupQ nil dupQTexts nil)
             (cond
               ((fc:group-has-keyword groupQTexts *TEXTQ-NO-KEYWORD*)
                (setq skipGroupQ T)
                (ssdel lineCEnt matchSS)  ; 이미 선택된 선C를 선택 목록에서 제거
                (princ (strcat "  ->  [선C/선그룹Q/텍스트그룹Q] '" *TEXTQ-NO-KEYWORD*
                                "' 포함 텍스트 발견 - 선택 제외"))
               )
               ((> (length groupQTexts) *TEXTQ-EXPECTED-COUNT*)
                (setq dupQTexts (fc:find-duplicate-y-texts groupQTexts *TEXTQ-Y-DUP-TOL*))
                (if dupQTexts
                  (progn
                    (foreach dq dupQTexts (vla-put-color (vlax-ename->vla-object dq) 1))
                    (setq groupQTexts (vl-remove-if (function (lambda (x) (member x dupQTexts))) groupQTexts))
                    (princ (strcat "  ->  [텍스트그룹Q] 6개 초과, Y좌표 유사 "
                                    (itoa (length dupQTexts)) "개를 빨간색으로 표시하고 선택 제외"))
                  )
                )
               )
             )
             (if (not skipGroupQ)
               (progn
                 (foreach e groupQLines (ssadd e matchSS))
                 (foreach e groupQTexts (ssadd e matchSS))
               )
             )
             (princ (strcat "  ->  [선그룹Q] " (itoa (length groupQLines)) "개 발견"
                             (if (/= (length groupQLines) *LINEQ-EXPECTED-COUNT*)
                               (strcat " (경고: 예상 " (itoa *LINEQ-EXPECTED-COUNT*) "개와 다름)")
                               ""
                             )))
             (princ (strcat "  ->  [텍스트그룹Q] " (itoa (length groupQTexts)) "개 발견"))
           )
           (princ "  ->  [선C] 대응하는 하단 수직선을 찾을 수 없음")
         )
       )
     )
     (sssetfirst nil matchSS)
    )
  )
  (princ)
)

(princ "\nTEELINE1 명령 사용 가능 (텍스트A를 직접 선택해서 검증)")
(princ)

;;;=======================================================================
;;; GGD (구 DISTCHAIN) 명령 (gg-l 의 "DISTANCE(M) 텍스트 체인 계산" 기능 이식)
;;;-----------------------------------------------------------------------
;;; 기능 요약
;;;  1) FORM 블록(또는 대체 사각형) 내부에서 "DISTANCE(M)" 포함 텍스트(텍스트1)를 찾음
;;;     단, 텍스트1 바로 위(*DISTCHAIN-TEXT1-ADJ-RANGE* 이내, 같은 열)에
;;;     다른 텍스트가 있으면 그 텍스트1은 건너뜀
;;;  2) 텍스트1 우측(Y오차 이내, 회전각 89~91도)에서 가장 가까운 텍스트를
;;;     "A"로 삼고, 이후 A의 우측에서 B, B의 우측에서 C ... 식으로
;;;     텍스트가 더 이상 없을 때까지 우측으로 이어지는 체인을 따라감
;;;  3) 체인의 각 글자(A,B,C,...)마다 그 위쪽(Y차 6~8, X오차 2 이내,
;;;     회전각 89~91도)에서 "프라임" 텍스트를 찾음 (A',B',C',...)
;;;  4) 현재 글자의 값 = (현재 프라임값 - 직전 프라임값) 로 계산하여
;;;     계산값이 0 이상이면 현재 글자(B,C,D,... / A는 제외)의 텍스트를
;;;     그 값("0.00" 형식)으로 덮어씀. 음수이면 수정하지 않음.
;;;     상단 프라임을 찾지 못한 글자는 수정하지 않고 기준값을 유지함
;;;
;;;  * 기존 DISTFIX(거리A/B/C 고정 3역할) 와는 별개의 로직이며,
;;;    이 명령은 원본 gg-l 리습(gg3-1 단계)의 "체인" 방식을 그대로 이식한 것임
;;;
;;;  5) [추가기능] 도곽 좌측하단점 기준 (X+350~395, Y+20~27) 범위에서
;;;     "지역-년도-압력-번호"(예: 홍성-2026-LP-001) 형식의 도면번호 텍스트를
;;;     찾는다. 지역명은 당진/서산/홍성/예산/태안, 압력구분은 LP/MP 만 인정.
;;;     압력구분이 LP 이면, 도곽 좌측하단점 기준 (X+18, Y+2) 위치에
;;;     레이어 "0", 색상 흰색, 높이 1.1 로 안내문구를 삽입한다.
;;;=======================================================================

;; ---- DISTCHAIN 설정값 ----
(setq *DISTCHAIN-PATTERN*        "DISTANCE(M)")
(setq *DISTCHAIN-TEXT1-ADJ-RANGE* 2.5)  ; 텍스트1 상단 인접 판정 범위
(setq *DISTCHAIN-COL-TOL*         1.0)  ; 텍스트1 상단 인접 판정 X오차(같은 열)
(setq *DISTCHAIN-RIGHT-YTOL*      2.0)  ; 우측 탐색 Y오차
(setq *DISTCHAIN-ABOVE-YMIN*      6.0)  ; 상단(프라임) 탐색 Y범위 최소
(setq *DISTCHAIN-ABOVE-YMAX*      8.0)  ; 상단(프라임) 탐색 Y범위 최대
(setq *DISTCHAIN-ABOVE-XTOL*      2.0)  ; 상단(프라임) 탐색 X오차
(setq *DISTCHAIN-ROTV-MIN*       89.0)  ; 수직 텍스트 회전각 최소(도)
(setq *DISTCHAIN-ROTV-MAX*       91.0)  ; 수직 텍스트 회전각 최대(도)

;; ---- GGD 추가기능: 도면번호(지역-년도-압력-번호) 확인 + LP 안내문구 삽입 ----
(setq *GGD-CODE-XMIN-OFFSET* 350.0)  ; 도곽 좌측하단점 기준 탐색범위 X 시작 오프셋
(setq *GGD-CODE-XMAX-OFFSET* 395.0)  ; 도곽 좌측하단점 기준 탐색범위 X 끝 오프셋
(setq *GGD-CODE-YMIN-OFFSET*  20.0)  ; 도곽 좌측하단점 기준 탐색범위 Y 시작 오프셋
(setq *GGD-CODE-YMAX-OFFSET*  27.0)  ; 도곽 좌측하단점 기준 탐색범위 Y 끝 오프셋
(setq *GGD-CODE-REGIONS* (list "당진" "서산" "홍성" "예산" "태안"))  ; 유효 지역명 목록
(setq *GGD-NOTE-DX*     18.0)   ; 안내문구 삽입위치 X 오프셋 (도곽 좌측하단점 기준)
(setq *GGD-NOTE-DY*      2.0)   ; 안내문구 삽입위치 Y 오프셋 (도곽 좌측하단점 기준)
(setq *GGD-NOTE-LAYER*  "0")    ; 안내문구 삽입 레이어
(setq *GGD-NOTE-COLOR*   7)     ; ACI 7 = 흰색(백그라운드 기본색)
(setq *GGD-NOTE-HEIGHT*  1.1)   ; 안내문구 글자 높이
(setq *GGD-NOTE-CONTENT*
  "*공급관 PE 63mm의 경우 안전공사 기술검토 비대상으로, 라인마크 개수가 제외되어 도면과 상이할 수 있습니다."
)

;; bmin~bmax 범위 안의 TEXT/MTEXT 를 (ent x y rotdeg text) 리스트로 수집
;; *MARK-LAYER*("0기술검토") 텍스트는 검색 대상에서 제외
(defun fc:distchain-gather-texts (bmin bmax / ss i ent obj pt rot txt lst)
  (setq lst '())
  (setq ss
    (ssget "_X"
      (list
        (cons -4 "<AND")
          (cons -4 "<OR") (cons 0 "TEXT") (cons 0 "MTEXT") (cons -4 "OR>")
          (cons -4 "<NOT")
            (cons 8 *MARK-LAYER*)
          (cons -4 "NOT>")
        (cons -4 "AND>")
      )
    )
  )
  (if ss
    (progn
      (setq i 0)
      (repeat (sslength ss)
        (setq ent (ssname ss i))
        (setq pt (fc:get-text-position ent))
        (if (fc:pt-in-box-p pt bmin bmax)
          (progn
            (setq obj (vlax-ename->vla-object ent))
            (setq txt (vla-get-textstring obj))
            (setq rot (* (vla-get-rotation obj) *RAD2DEG*))
            (setq lst (append lst (list (list ent (car pt) (cadr pt) rot txt))))
          )
        )
        (setq i (1+ i))
      )
    )
  )
  lst
)

;; basept 기준 "우측"(X가 더 큼, Y오차=ytol 이내)에서
;; 회전각이 rotmin~rotmax 인 가장 가까운 텍스트 찾기
(defun fc:distchain-find-right (basept items exclude ytol rotmin rotmax / best bestd it rot d)
  (setq best nil bestd nil)
  (foreach it items
    (if (not (member (car it) exclude))
      (if (and (> (nth 1 it) (car basept))
               (<= (abs (- (nth 2 it) (cadr basept))) ytol))
        (progn
          (setq rot (nth 3 it))
          (if (and (>= rot rotmin) (<= rot rotmax))
            (progn
              (setq d (distance basept (list (nth 1 it) (nth 2 it))))
              (if (or (not bestd) (< d bestd))
                (progn (setq best it) (setq bestd d))
              )
            )
          )
        )
      )
    )
  )
  best
)

;; basept 기준 "상단"(Y차이가 ymin~ymax 범위, X오차=xtol 이내)에서
;; 회전각이 rotmin~rotmax 인 가장 가까운 텍스트 찾기
(defun fc:distchain-find-above (basept items exclude ymin ymax xtol rotmin rotmax / best bestd it dy dx rot d)
  (setq best nil bestd nil)
  (foreach it items
    (if (not (member (car it) exclude))
      (progn
        (setq dy (- (nth 2 it) (cadr basept)))
        (setq dx (abs (- (nth 1 it) (car basept))))
        (if (and (>= dy ymin) (<= dy ymax) (<= dx xtol))
          (progn
            (setq rot (nth 3 it))
            (if (and (>= rot rotmin) (<= rot rotmax))
              (progn
                (setq d (distance basept (list (nth 1 it) (nth 2 it))))
                (if (or (not bestd) (< d bestd))
                  (progn (setq best it) (setq bestd d))
                )
              )
            )
          )
        )
      )
    )
  )
  best
)

;; basept(텍스트1) 상단 yrange 이내, 같은 세로열(X오차=xtol)에
;; 다른 텍스트가 있는지 확인 (있으면 텍스트1 제외 대상)
(defun fc:distchain-has-above-p (basept items exclude yrange xtol / found it dy dx)
  (setq found nil)
  (foreach it items
    (if (not (member (car it) exclude))
      (progn
        (setq dy (- (nth 2 it) (cadr basept)))
        (setq dx (abs (- (nth 1 it) (car basept))))
        (if (and (> dy 0) (<= dy yrange) (<= dx xtol))
          (setq found T)
        )
      )
    )
  )
  found
)

;; 문자열에서 숫자값 추출 (앞뒤 공백 제거 후 atof)
(defun fc:distchain-parse-num (str / s)
  (setq s (vl-string-trim " \t" str))
  (atof s)
)

;; TEXT/MTEXT 엔티티의 내용을 새 문자열로 교체
(defun fc:distchain-set-text (ent newstr)
  (vla-put-textstring (vlax-ename->vla-object ent) newstr)
)

;; 하나의 FORM 블록 범위(bmin~bmax) 안에서 DISTANCE(M) 텍스트 체인 계산 처리
;; 리턴값: 이 FORM 블록에서 처리(시도)한 텍스트1 매치 건수
(defun fc:distchain-process (bmin bmax / items text1List it t1 textA exclude
                               primeA prevPrimeVal haveBaseline current
                               letterCount loopFlag newLetter newPrime
                               diffVal formatted matchcount)
  (setq items (fc:distchain-gather-texts bmin bmax))
  (setq matchcount 0)
  (if (not items)
    (princ "\n  TEXT/MTEXT를 찾을 수 없습니다.")
    (progn
      (setq text1List '())
      (foreach it items
        (if (vl-string-search *DISTCHAIN-PATTERN* (nth 4 it))
          (setq text1List (append text1List (list it)))
        )
      )
      (if (= (length text1List) 0)
        (princ (strcat "\n  \"" *DISTCHAIN-PATTERN* "\" 텍스트를 찾을 수 없습니다."))
        (foreach t1 text1List
          (if (fc:distchain-has-above-p (list (nth 1 t1) (nth 2 t1)) items (list (car t1))
                                          *DISTCHAIN-TEXT1-ADJ-RANGE* *DISTCHAIN-COL-TOL*)
            (princ (strcat "\n  [건너뜀] 텍스트1 상단 인접 텍스트 존재: " (nth 4 t1)))
            (progn
              (setq matchcount (1+ matchcount))
              (princ (strcat "\n\n  [GGD 매치 " (itoa matchcount) "] 텍스트1: " (nth 4 t1)))

              ;; 텍스트A = 텍스트1 우측
              (setq textA (fc:distchain-find-right (list (nth 1 t1) (nth 2 t1)) items
                             (list (car t1)) *DISTCHAIN-RIGHT-YTOL*
                             *DISTCHAIN-ROTV-MIN* *DISTCHAIN-ROTV-MAX*))
              (if (not textA)
                (princ "\n    텍스트A를 찾지 못했습니다.")
                (progn
                  (princ (strcat "\n    텍스트A: " (nth 4 textA)))
                  (setq exclude (list (car t1) (car textA)))

                  ;; 텍스트A' = 텍스트A 상단 (최초 기준 프라임값)
                  (setq primeA (fc:distchain-find-above (list (nth 1 textA) (nth 2 textA)) items
                                  exclude *DISTCHAIN-ABOVE-YMIN* *DISTCHAIN-ABOVE-YMAX*
                                  *DISTCHAIN-ABOVE-XTOL* *DISTCHAIN-ROTV-MIN* *DISTCHAIN-ROTV-MAX*))
                  (if primeA
                    (progn
                      (princ (strcat "\n    텍스트A': " (nth 4 primeA)))
                      (setq prevPrimeVal (fc:distchain-parse-num (nth 4 primeA)))
                      (setq haveBaseline T)
                    )
                    (progn
                      (princ "\n    텍스트A'를 찾지 못했습니다 (기준값 없음).")
                      (setq haveBaseline nil)
                    )
                  )

                  (setq current textA)
                  (setq letterCount 1)   ; A=1
                  (setq loopFlag T)

                  (while loopFlag
                    (setq newLetter (fc:distchain-find-right (list (nth 1 current) (nth 2 current)) items
                                       exclude *DISTCHAIN-RIGHT-YTOL*
                                       *DISTCHAIN-ROTV-MIN* *DISTCHAIN-ROTV-MAX*))
                    (if (not newLetter)
                      (setq loopFlag nil)
                      (progn
                        (setq letterCount (1+ letterCount))
                        (princ (strcat "\n    텍스트" (chr (+ 64 letterCount)) ": " (nth 4 newLetter)))
                        (setq exclude (append exclude (list (car newLetter))))

                        ;; 새 글자의 상단(프라임) 탐색
                        (setq newPrime (fc:distchain-find-above (list (nth 1 newLetter) (nth 2 newLetter)) items
                                          exclude *DISTCHAIN-ABOVE-YMIN* *DISTCHAIN-ABOVE-YMAX*
                                          *DISTCHAIN-ABOVE-XTOL* *DISTCHAIN-ROTV-MIN* *DISTCHAIN-ROTV-MAX*))
                        (if newPrime
                          (progn
                            (princ (strcat "\n      상단(프라임): " (nth 4 newPrime)))
                            (if haveBaseline
                              (progn
                                (setq diffVal (- (fc:distchain-parse-num (nth 4 newPrime)) prevPrimeVal))
                                (if (>= diffVal 0)
                                  (progn
                                    (setq formatted (rtos diffVal 2 2))
                                    (fc:distchain-set-text (car newLetter) formatted)
                                    (princ (strcat "\n      -> 값 갱신: " formatted))
                                  )
                                  (princ "\n      -> 계산값 음수, 수정하지 않음")
                                )
                              )
                              (princ "\n      -> 이전 기준값이 없어 계산을 건너뜁니다.")
                            )
                            ;; 다음 글자 계산을 위해 기준 프라임값 갱신
                            (setq prevPrimeVal (fc:distchain-parse-num (nth 4 newPrime)))
                            (setq haveBaseline T)
                          )
                          (princ "\n      상단(프라임) 텍스트 없음 - 이 글자는 수정하지 않고 기준값 유지")
                        )
                        (setq current newLetter)
                      )
                    )
                  )
                )
              )
            )
          )
        )
      )
    )
  )
  matchcount
)

;; 도곽 코드 텍스트("지역-년도-압력-번호", 예: 홍성-2026-LP-001)가 유효한
;; 형식인지 확인. 지역명은 *GGD-CODE-REGIONS* 목록에 있어야 하고,
;; 압력구분은 LP/MP 만 인정. 리턴: (지역 년도 압력 번호) / 형식불일치시 nil
(defun fc:ggd-parse-code (txt / parts region press)
  (setq parts (fc:str-split txt "-"))
  (if (= (length parts) 4)
    (progn
      (setq region (nth 0 parts))
      (setq press (strcase (nth 2 parts)))
      (if (and (member region *GGD-CODE-REGIONS*)
               (or (= press "LP") (= press "MP")))
        (list region (nth 1 parts) press (nth 3 parts))
        nil
      )
    )
    nil
  )
)

;; bmin(도곽 좌측하단점) 기준 (X+350~395, Y+20~27) 범위 안에서
;; "지역-년도-압력-번호" 형식의 도면번호 텍스트를 찾음
;; 리턴: (ent x y rawtext code) / 없으면 nil (여러 개면 첫 매치)
(defun fc:ggd-find-drawing-code (bmin / ss i n ent pt txt code xmin xmax ymin ymax found)
  (setq xmin (+ (car bmin) *GGD-CODE-XMIN-OFFSET*))
  (setq xmax (+ (car bmin) *GGD-CODE-XMAX-OFFSET*))
  (setq ymin (+ (cadr bmin) *GGD-CODE-YMIN-OFFSET*))
  (setq ymax (+ (cadr bmin) *GGD-CODE-YMAX-OFFSET*))
  (setq found nil)
  (setq ss (ssget "_X" (list (cons -4 "<OR") (cons 0 "TEXT") (cons 0 "MTEXT") (cons -4 "OR>"))))
  (if ss
    (progn
      (setq n (sslength ss))
      (setq i 0)
      (while (and (not found) (< i n))
        (setq ent (ssname ss i))
        (setq pt (fc:get-text-position ent))
        (if (and (>= (car pt) xmin) (<= (car pt) xmax)
                 (>= (cadr pt) ymin) (<= (cadr pt) ymax))
          (progn
            (setq txt (vla-get-textstring (vlax-ename->vla-object ent)))
            (setq code (fc:ggd-parse-code txt))
            (if code
              (setq found (list ent (car pt) (cadr pt) txt code))
            )
          )
        )
        (setq i (1+ i))
      )
    )
  )
  found
)

;; bmin(도곽 좌측하단점) 기준 (X+*GGD-NOTE-DX*, Y+*GGD-NOTE-DY*) 위치에
;; LP 안내문구 TEXT 생성 (레이어 *GGD-NOTE-LAYER*, 색상 *GGD-NOTE-COLOR*,
;; 높이 *GGD-NOTE-HEIGHT*)
(defun fc:ggd-insert-lp-note (bmin / px py)
  (setq px (+ (car bmin) *GGD-NOTE-DX*))
  (setq py (+ (cadr bmin) *GGD-NOTE-DY*))
  (entmake
    (list
      (cons 0 "TEXT")
      (cons 8 *GGD-NOTE-LAYER*)
      (cons 62 *GGD-NOTE-COLOR*)
      (cons 10 (list px py 0.0))
      (cons 40 *GGD-NOTE-HEIGHT*)
      (cons 1 *GGD-NOTE-CONTENT*)
    )
  )
)

;; 하나의 FORM 블록(bmin 기준)에서 도면번호 텍스트를 확인하고,
;; 압력구분이 LP 이면 안내문구를 삽입한다.
;; 리턴값: 안내문구를 삽입했으면 T, 아니면 nil
(defun fc:ggd-process-drawing-code (bmin / result code press inserted)
  (setq inserted nil)
  (setq result (fc:ggd-find-drawing-code bmin))
  (if (not result)
    (princ "\n  [도면번호] 지역-년도-압력-번호 형식 텍스트를 찾을 수 없습니다.")
    (progn
      (setq code (nth 4 result))
      (setq press (nth 2 code))
      (princ (strcat "\n  [도면번호] " (nth 3 result) " (압력구분: " press ")"))
      (if (= press "LP")
        (progn
          (fc:ggd-insert-lp-note bmin)
          (setq inserted T)
          (princ "\n    -> LP 확인: 안내문구 삽입 완료")
        )
        (princ "\n    -> MP: 안내문구 삽입 대상 아님")
      )
    )
  )
  inserted
)

;; 메인 명령: 모든 FORM 블록(또는 대체 사각형)에 대해 순서대로 DISTCHAIN(GGD) 처리
(defun c:GGD ( / formList sortedList b idx bmin bmax total noteCount)
  (vl-load-com)
  (princ "\n[FORM 블록 검색 중...]")
  (setq formList (fc:get-form-blocks-or-fallback))
  (if (not formList)
    (princ "\n>> FORM 블록도, 대체 사각형도 찾을 수 없습니다.")
    (progn
      (setq sortedList (fc:sort-reading-order formList))
      (princ (strcat "\n>> 총 " (itoa (length sortedList)) "개 FORM(또는 대체) 발견"))
      (setq idx 0 total 0 noteCount 0)
      (foreach b sortedList
        (setq idx (1+ idx))
        (setq bmin (nth 1 b) bmax (nth 2 b))
        (princ (strcat "\n\n=== FORM 블록 " (itoa idx) " ==="))
        (setq total (+ total (fc:distchain-process bmin bmax)))
        (if (fc:ggd-process-drawing-code bmin)
          (setq noteCount (1+ noteCount))
        )
      )
      (princ (strcat "\n\n>> 전체 완료: 텍스트1 기준 총 " (itoa total)
                      "건 처리 / LP 안내문구 " (itoa noteCount) "건 삽입했습니다."))
    )
  )
  (princ)
  (princ)
)

(princ "\nGGD 명령 사용 가능 (구 DISTCHAIN, DISTANCE(M) 텍스트체인 자동수정 + LP 도면 안내문구 삽입)")
(princ)

;;;=======================================================================
;;; GGM 명령 (원본 gg.lsp / gg-m 의 "자재내역 수정" 기능 이식)
;;;-----------------------------------------------------------------------
;;; 기능 요약 (원본 gg-m 의 1,2단계에 해당, 3단계 종단그래프 이관은 GGL 기능임)
;;;  [1/2] FORM 블록(또는 대체 사각형) 내부에서 *GGM-SRC-LAYER*("X-물량TEXT")
;;;        레이어의 "63mm" 문구를 찾아, 63mm 요소 자체 + 좌측 1개 +
;;;        우측 전체(최대 3개)를 *MARK-LAYER*("0기술검토") 레이어로 이관한다.
;;;        단, 좌측 텍스트가 "REDUCER"를 부분일치로라도 포함하면 건너뛴다.
;;;  [2/2] 도면 전체에서 크기(가로 *GGM-FRAME-WIDTH*, 세로 *GGM-FRAME-HEIGHT*,
;;;        오차 *GGM-FRAME-TOL-PCT*)가 일치하는 LWPOLYLINE 사각 틀을 찾아,
;;;        [1/2]에서 *MARK-LAYER*로 이관되어 빈 행이 된 자리를 틀 내부에서
;;;        아래쪽부터 재정렬한다. (이 단계는 FORM 블록 단위가 아닌 도면 전체 대상)
;;;=======================================================================

;; ---- GGM 설정값 ----
(setq *GGM-SRC-LAYER*      "X-물량TEXT")  ; 63mm 문구가 있는 원본 레이어
(setq *GGM-BOX-EPS*        5.0)           ; FORM 블록 박스 판정 여유(도면단위)
(setq *GGM-COL-GAP-MAX*    30.0)          ; 같은 행에서 인접 컬럼으로 볼 최대 X간격
                                           ; (실측 컬럼간격: 이름-지름 약 20, 지름-단위 약 12 -> 여유를 둔 값)
(setq *GGM-FRAME-WIDTH*    66.4770)       ; 틀(사각형) 가로 크기
(setq *GGM-FRAME-HEIGHT*   82.5520)       ; 틀(사각형) 세로 크기
(setq *GGM-FRAME-TOL-PCT*  0.05)          ; 틀 크기 오차 허용범위(5%)
(setq *GGM-FRAME-BOX-EPS*  2.0)           ; 틀 내부 텍스트 판정 여유
(setq *GGM-DIVIDER-X-TOL*  1.0)           ; 행 구분선 X범위가 틀 폭과 일치하는지 판정 허용오차
(setq *GGM-DIVIDER-DUP-TOL* 0.01)         ; 행 구분선 Y중복 제거 허용오차

;; 공백 제거 + 대문자화 (63MM / REDUCER 부분일치 판정용)
(defun fc:ggm-normalize-str (s / r i ch)
  (setq r "" i 1)
  (while (<= i (strlen s))
    (setq ch (substr s i 1))
    (if (/= ch " ")
      (setq r (strcat r ch))
    )
    (setq i (1+ i))
  )
  (strcase r)
)

;; TEXT/MTEXT 엔티티 하나를 (ent x y height rawtext normtext layer) 로 변환
(defun fc:ggm-text-item (ent / edata pt h str nstr lyr)
  (setq edata (entget ent))
  (setq pt (fc:get-text-position ent))
  (setq h (cdr (assoc 40 edata)))
  (if (not h) (setq h 2.5))
  (setq str (vla-get-textstring (vlax-ename->vla-object ent)))
  (setq nstr (fc:ggm-normalize-str str))
  (setq lyr (cdr (assoc 8 edata)))
  (list ent (car pt) (cadr pt) h str nstr lyr)
)

;; bmin~bmax(여유 *GGM-BOX-EPS* 포함) 범위 안의 TEXT/MTEXT 를
;; (ent x y height rawtext normtext layer) 리스트로 수집
(defun fc:ggm-gather-texts (bmin bmax / ss i ent pt lst xmin ymin xmax ymax)
  (setq xmin (- (car bmin) *GGM-BOX-EPS*) ymin (- (cadr bmin) *GGM-BOX-EPS*))
  (setq xmax (+ (car bmax) *GGM-BOX-EPS*) ymax (+ (cadr bmax) *GGM-BOX-EPS*))
  (setq lst '())
  (setq ss (ssget "_X" (list (cons -4 "<OR") (cons 0 "TEXT") (cons 0 "MTEXT") (cons -4 "OR>"))))
  (if ss
    (progn
      (setq i 0)
      (repeat (sslength ss)
        (setq ent (ssname ss i))
        (setq pt (fc:get-text-position ent))
        (if (and (>= (car pt) xmin) (<= (car pt) xmax)
                 (>= (cadr pt) ymin) (<= (cadr pt) ymax))
          (setq lst (append lst (list (fc:ggm-text-item ent))))
        )
        (setq i (1+ i))
      )
    )
  )
  lst
)

;; 텍스트 아이템 리스트를 Y기준 행(row)으로 묶고, 각 행을 X오름차순 정렬
;; item: (ent x y height rawtext normtext layer)
(defun fc:ggm-group-rows (items / sorted rows placed row it)
  (setq sorted (vl-sort items (function (lambda (a b) (> (nth 2 a) (nth 2 b)))))) ; y desc
  (setq rows '())
  (foreach it sorted
    (setq placed nil)
    (setq rows
      (mapcar
        (function
          (lambda (row / repY tol)
            (if (and (not placed) row)
              (progn
                (setq repY (nth 2 (car row)))
                (setq tol (/ (max (nth 3 it) (nth 3 (car row))) 2.0))
                (if (<= (abs (- (nth 2 it) repY)) tol)
                  (progn (setq placed T) (append row (list it)))
                  row
                )
              )
              row
            )
          )
        )
        rows
      )
    )
    (if (not placed)
      (setq rows (append rows (list (list it))))
    )
  )
  ;; 각 행을 x 오름차순 정렬
  (mapcar
    (function (lambda (row) (vl-sort row (function (lambda (a b) (< (nth 1 a) (nth 1 b)))))))
    rows
  )
)

;; ---- 틀 내부 "행 구분선" 기반 실제 행 슬롯 계산 ----
;; (텍스트 존재 여부로 행을 추측하지 않고, 실제로 그려진 가로 구분선으로
;;  물리적 행 경계를 정확히 구해서 완전히 빈 행도 놓치지 않도록 함)

;; 도면 전체에서 *FORM-FALLBACK-LAYER* 의 수평 열린 2점 선/폴리선을
;; (y xmin xmax) 리스트로 수집 (틀 내부 행 구분선 후보)
(defun fc:ggm-collect-hlines ( / ss i ent obj edata closedFlag verts p1 p2 lst)
  (setq lst '())
  (setq ss (ssget "_X" (list (cons 0 "LINE,LWPOLYLINE") (cons 8 *FORM-FALLBACK-LAYER*))))
  (if ss
    (progn
      (setq i 0)
      (repeat (sslength ss)
        (setq ent (ssname ss i))
        (setq edata (entget ent))
        (setq closedFlag (cdr (assoc 70 edata)))
        (if (or (not closedFlag) (= (logand closedFlag 1) 0))
          (progn
            (setq obj (vlax-ename->vla-object ent))
            (setq verts (fc:get-entity-vertices ent obj))
            (if (= (length verts) 2)
              (progn
                (setq p1 (car verts) p2 (cadr verts))
                (if (<= (abs (- (cadr p1) (cadr p2))) 1e-4)
                  (setq lst
                    (append lst
                      (list (list (cadr p1) (min (car p1) (car p2)) (max (car p1) (car p2))))
                    )
                  )
                )
              )
            )
          )
        )
        (setq i (1+ i))
      )
    )
  )
  lst
)

;; frame-bbox(minx miny maxx maxy) 안에서, hlines(fc:ggm-collect-hlines 결과) 중
;; 틀 폭과 X범위가 일치하는 것만 골라 행 경계 Y좌표 목록을 만든다.
;; 틀 상/하단 모서리도 경계에 포함되며, 결과는 내림차순(위->아래) 정렬 후 중복 제거됨.
(defun fc:ggm-find-row-dividers (frame-bbox hlines / minx miny maxx maxy boundaries hl y x1 x2 sorted uniqueB last b)
  (setq minx (car frame-bbox) miny (cadr frame-bbox) maxx (caddr frame-bbox) maxy (cadddr frame-bbox))
  (setq boundaries (list maxy miny))
  (foreach hl hlines
    (setq y (car hl) x1 (cadr hl) x2 (caddr hl))
    (if (and (>= y (- miny *GGM-FRAME-BOX-EPS*)) (<= y (+ maxy *GGM-FRAME-BOX-EPS*))
             (<= (abs (- x1 minx)) *GGM-DIVIDER-X-TOL*)
             (<= (abs (- x2 maxx)) *GGM-DIVIDER-X-TOL*))
      (setq boundaries (append boundaries (list y)))
    )
  )
  (setq sorted (vl-sort boundaries (function >)))
  (setq uniqueB '() last nil)
  (foreach b sorted
    (if (or (not last) (> (- last b) *GGM-DIVIDER-DUP-TOL*))
      (progn (setq uniqueB (append uniqueB (list b))) (setq last b))
    )
  )
  uniqueB
)

;; y좌표가 boundaries(내림차순, 위->아래)가 정의하는 슬롯 중 몇 번째(0-based, 위부터)에
;; 속하는지 반환. 정확히 안 맞으면 슬롯 중심에 가장 가까운 슬롯으로 대체
(defun fc:ggm-find-slot-index (y boundaries / n i idx best bestd mid d)
  (setq n (1- (length boundaries)))
  (setq idx nil i 0)
  (while (and (not idx) (< i n))
    (if (and (<= y (+ (nth i boundaries) 1e-6))
             (>= y (- (nth (1+ i) boundaries) 1e-6)))
      (setq idx i)
    )
    (setq i (1+ i))
  )
  (if (not idx)
    (progn
      (setq best nil bestd nil i 0)
      (while (< i n)
        (setq mid (/ (+ (nth i boundaries) (nth (1+ i) boundaries)) 2.0))
        (setq d (abs (- y mid)))
        (if (or (not bestd) (< d bestd))
          (progn (setq best i) (setq bestd d))
        )
        (setq i (1+ i))
      )
      (setq idx best)
    )
  )
  idx
)

;; items(틀 내부 텍스트 아이템)를 boundaries 가 정의하는 실제 행 슬롯별로 분류
;; 리턴: 슬롯 개수만큼의 리스트(각 슬롯의 아이템 리스트, 비어있을 수 있음), 위->아래 순서
(defun fc:ggm-build-slot-rows (items boundaries / n slots it idx i row result)
  (setq n (1- (length boundaries)))
  (setq slots '())
  (repeat n (setq slots (append slots (list '()))))
  (foreach it items
    (setq idx (fc:ggm-find-slot-index (nth 2 it) boundaries))
    (if idx
      (progn
        (setq result '() i 0)
        (foreach row slots
          (if (= i idx)
            (setq result (append result (list (append row (list it)))))
            (setq result (append result (list row)))
          )
          (setq i (1+ i))
        )
        (setq slots result)
      )
    )
  )
  slots
)

;; 엔티티를 *MARK-LAYER*("0기술검토") 레이어로 이관 (레이어 없으면 생성)
(defun fc:ggm-move-to-mark (ent)
  (fc:ensure-layer *MARK-LAYER*)
  (vla-put-layer (vlax-ename->vla-object ent) *MARK-LAYER*)
)

;; 그룹(항목 리스트)의 원문 텍스트를 ", "로 이어붙인 문자열 생성 (로그 출력용)
(defun fc:ggm-join-texts (group / s first it)
  (setq s "" first T)
  (foreach it group
    (if first
      (progn (setq s (nth 4 it)) (setq first nil))
      (setq s (strcat s ", " (nth 4 it)))
    )
  )
  s
)

;; 한 행(row, X오름차순) 안에서 *GGM-SRC-LAYER* 의 "63MM" 텍스트를 찾아,
;; 그 좌측 1개 + 63mm 자신 + 우측(최대 3개)을 하나의 "그룹"으로 모아
;; *MARK-LAYER* 로 한번에 이관한다.
;; 좌/우로 그룹을 확장할 때는 직전 항목과의 X간격이 *GGM-COL-GAP-MAX* 이내인
;; 경우에만 포함시켜, 간격이 벌어진(같은 행이지만 무관한) 항목이 잘못
;; 딸려오지 않도록 한다. 좌측 텍스트가 "REDUCER"를 포함하면 그룹 전체를 건너뜀.
;; 리턴값: 이 행에서 이관한 항목 개수
(defun fc:ggm-process-row (row / n idx i it leftItem hasLeft gap group gItem
                            prevX k rightCount movedCount)
  (setq n (length row))
  (setq idx nil i 0)
  (setq movedCount 0)
  (while (and (< i n) (not idx))
    (setq it (nth i row))
    (if (and (= (nth 6 it) *GGM-SRC-LAYER*)
             (vl-string-search "63MM" (nth 5 it)))
      (setq idx i)
    )
    (setq i (1+ i))
  )
  (if idx
    (progn
      ;; 좌측 항목: 존재하고 63mm 항목과의 X간격이 *GGM-COL-GAP-MAX* 이내일 때만 포함
      (setq hasLeft nil leftItem nil)
      (if (> idx 0)
        (progn
          (setq leftItem (nth (1- idx) row))
          (setq gap (- (nth 1 (nth idx row)) (nth 1 leftItem)))
          (if (<= gap *GGM-COL-GAP-MAX*)
            (setq hasLeft T)
            (princ (strcat "\n    [참고] 좌측 항목 간격 초과(" (rtos gap 2 2)
                            ") -> 그룹에서 제외: " (nth 4 leftItem)))
          )
        )
        (princ "\n    [참고] 좌측 텍스트가 없는 행입니다. 우측만 처리합니다.")
      )
      (if (and hasLeft (vl-string-search "REDUCER" (nth 5 leftItem)))
        (princ (strcat "\n    [건너뜀] 좌측이 REDUCER: " (nth 4 leftItem)))
        (progn
          ;; 그룹 구성: 좌측(있으면) + 63mm 자신
          (setq group '())
          (if hasLeft (setq group (append group (list leftItem))))
          (setq group (append group (list (nth idx row))))

          ;; 우측: 직전 항목과의 간격이 *GGM-COL-GAP-MAX* 이내인 동안 최대 3개까지 연속 포함
          (setq prevX (nth 1 (nth idx row)))
          (setq k (1+ idx))
          (setq rightCount 0)
          (while (and (< k n) (< rightCount 3))
            (setq it (nth k row))
            (setq gap (- (nth 1 it) prevX))
            (if (<= gap *GGM-COL-GAP-MAX*)
              (progn
                (setq group (append group (list it)))
                (setq prevX (nth 1 it))
                (setq rightCount (1+ rightCount))
                (setq k (1+ k))
              )
              (setq k n)  ; 간격 초과 -> 더 이상 확장하지 않고 중단
            )
          )

          ;; 완성된 그룹을 하나의 단위로 이관 (전부 이관 후 한번에 보고)
          (foreach gItem group (fc:ggm-move-to-mark (car gItem)))
          (setq movedCount (length group))
          (princ (strcat "\n    [이관] 그룹(" (itoa movedCount) "개): " (fc:ggm-join-texts group)))
          (if (< movedCount 3)
            (princ (strcat "\n    [참고] 그룹 크기가 " (itoa movedCount)
                            "개로 예상(4~5개)보다 작습니다. 확인이 필요할 수 있습니다."))
          )
        )
      )
    )
  )
  movedCount
)

;; 하나의 FORM 블록 범위(bmin~bmax) 안에서 63mm 관련 자재 이관 처리
;; 리턴값: 이관된 항목 총 개수
(defun fc:ggm-step1 (bmin bmax / items rows row total)
  (setq items (fc:ggm-gather-texts bmin bmax))
  (setq total 0)
  (if (not items)
    (princ "\n  TEXT/MTEXT를 찾을 수 없습니다.")
    (progn
      (setq rows (fc:ggm-group-rows items))
      (foreach row rows
        (setq total (+ total (fc:ggm-process-row row)))
      )
      (if (= total 0)
        (princ (strcat "\n  \"" *GGM-SRC-LAYER* "\" 레이어에서 63mm 관련 항목을 찾지 못했습니다."))
        (princ (strcat "\n  63mm 관련 총 " (itoa total) "개 항목을 \"" *MARK-LAYER* "\" 레이어로 이관했습니다."))
      )
    )
  )
  total
)

;; ---- 틀(프레임) 내부 빈 행 재정렬 ----

;; LWPOLYLINE 엔티티의 축정렬 바운딩박스 (minx miny maxx maxy) 계산
(defun fc:ggm-lwpoly-bbox (ent / edata pts pair minx miny maxx maxy first p)
  (setq edata (entget ent))
  (setq pts '())
  (foreach pair edata
    (if (= (car pair) 10)
      (setq pts (append pts (list (cdr pair))))
    )
  )
  (if (not pts)
    nil
    (progn
      (setq first (car pts))
      (setq minx (car first) maxx (car first) miny (cadr first) maxy (cadr first))
      (foreach p pts
        (if (< (car p) minx) (setq minx (car p)))
        (if (> (car p) maxx) (setq maxx (car p)))
        (if (< (cadr p) miny) (setq miny (cadr p)))
        (if (> (cadr p) maxy) (setq maxy (cadr p)))
      )
      (list minx miny maxx maxy)
    )
  )
)

;; 값이 target 대비 pct 오차범위 이내인지 확인
(defun fc:ggm-within-tol (val target pct)
  (and (>= val (* target (- 1.0 pct)))
       (<= val (* target (+ 1.0 pct))))
)

;; TEXT/MTEXT 엔티티를 Y방향으로 deltaY 만큼 평행이동
(defun fc:ggm-translate-text-y (ent deltaY / edata etype p10 p11)
  (setq edata (entget ent))
  (setq etype (cdr (assoc 0 edata)))
  (setq p10 (cdr (assoc 10 edata)))
  (if p10
    (setq edata
      (subst
        (cons 10 (list (car p10) (+ (cadr p10) deltaY) (caddr p10)))
        (assoc 10 edata)
        edata
      )
    )
  )
  (if (= etype "TEXT")
    (progn
      (setq p11 (cdr (assoc 11 edata)))
      (if p11
        (setq edata
          (subst
            (cons 11 (list (car p11) (+ (cadr p11) deltaY) (caddr p11)))
            (assoc 11 edata)
            edata
          )
        )
      )
    )
  )
  (entmod edata)
  (entupd ent)
)

;; 한 틀(프레임) 내부 정렬 처리
;; frame-bbox: (minx miny maxx maxy) / all-items: (ent x y height rawtext normtext layer)
;; frame-bbox: (minx miny maxx maxy) / all-items: (ent x y height rawtext normtext layer)
;; hlines: fc:ggm-collect-hlines 결과 (도면 전체 수평 구분선 후보, 미리 한 번만 수집해서 전달)
(defun fc:ggm-process-frame (frame-bbox all-items hlines / minx miny maxx maxy items-in-frame
                              it x y boundaries nSlots rows row nv nb N slotYs participatingYs
                              validRows blankRows lockedCount hasItemsP
                              i deltaY repY targetY item allMarkP anyMarkP)
  (setq minx (- (car frame-bbox) *GGM-FRAME-BOX-EPS*))
  (setq miny (- (cadr frame-bbox) *GGM-FRAME-BOX-EPS*))
  (setq maxx (+ (caddr frame-bbox) *GGM-FRAME-BOX-EPS*))
  (setq maxy (+ (cadddr frame-bbox) *GGM-FRAME-BOX-EPS*))

  (setq items-in-frame '())
  (foreach it all-items
    (setq x (nth 1 it) y (nth 2 it))
    (if (and (>= x minx) (<= x maxx) (>= y miny) (<= y maxy))
      (setq items-in-frame (append items-in-frame (list it)))
    )
  )

  ;; 틀 내부 실제 행 구분선 + 틀 상/하단 모서리로 물리적 행 슬롯 경계를 구성
  ;; (텍스트 존재 여부와 무관하게, 완전히 빈 슬롯도 정확히 포함됨)
  (setq boundaries (fc:ggm-find-row-dividers frame-bbox hlines))
  (setq nSlots (1- (length boundaries)))

  (if (< nSlots 1)
    (princ "\n    [틀 처리] 행 구분선을 찾을 수 없어 재정렬을 건너뜁니다.")
    (progn
      (setq rows (fc:ggm-build-slot-rows items-in-frame boundaries)) ; 상->하 순서, 슬롯별(비어있을 수 있음)

      (setq slotYs '())
      (setq i 0)
      (while (< i nSlots)
        (setq slotYs (append slotYs (list (/ (+ (nth i boundaries) (nth (1+ i) boundaries)) 2.0))))
        (setq i (1+ i))
      )

      ;; 행 분류 (3가지):
      ;;  - 슬롯에 항목이 아예 없음, 또는 모든 항목이 *MARK-LAYER* -> 빈 행 (재배치 대상)
      ;;  - 모든 항목이 원래 레이어(항목 1개 이상) -> 정상 행 (재배치 대상)
      ;;  - 일부만 *MARK-LAYER* -> "부분 이관 행" : 아직 유효한 내용이 남아있으므로
      ;;    재배치 대상에서 제외하고 원래 위치를 그대로 유지한다
      (setq validRows '() blankRows '() participatingYs '() lockedCount 0)
      (setq i 0)
      (foreach row rows
        (setq hasItemsP (> (length row) 0))
        (setq allMarkP T anyMarkP nil)
        (foreach item row
          (if (= (nth 6 item) *MARK-LAYER*)
            (setq anyMarkP T)
            (setq allMarkP nil)
          )
        )
        (cond
          ((not hasItemsP)
           (setq blankRows (append blankRows (list row)))
           (setq participatingYs (append participatingYs (list (nth i slotYs))))
          )
          (allMarkP
           (setq blankRows (append blankRows (list row)))
           (setq participatingYs (append participatingYs (list (nth i slotYs))))
          )
          (anyMarkP
           (setq lockedCount (1+ lockedCount))
          )
          (T
           (setq validRows (append validRows (list row)))
           (setq participatingYs (append participatingYs (list (nth i slotYs))))
          )
        )
        (setq i (1+ i))
      )
      (setq nv (length validRows))
      (setq nb (length blankRows))
      (setq N (+ nv nb))  ; 재배치에 실제로 참여하는 슬롯 수 (부분 이관 행 제외)

      (if (> nb 0)
        (progn
          ;; 정상 행: 원래 순서 유지, 참여 슬롯의 "아래쪽"부터 채움
          (setq i 0)
          (foreach row validRows
            (setq targetY (nth (+ (- N nv) i) participatingYs))
            (setq repY (nth 2 (car row)))
            (setq deltaY (- targetY repY))
            (if (> (abs deltaY) 1e-6)
              (foreach item row (fc:ggm-translate-text-y (car item) deltaY))
            )
            (setq i (1+ i))
          )

          ;; 빈 행: 원래 순서 유지, 참여 슬롯의 "위쪽"으로 이동 (항목 없는 슬롯은 아무일도 안 함)
          (setq i 0)
          (foreach row blankRows
            (if row
              (progn
                (setq targetY (nth i participatingYs))
                (setq repY (nth 2 (car row)))
                (setq deltaY (- targetY repY))
                (if (> (abs deltaY) 1e-6)
                  (foreach item row (fc:ggm-translate-text-y (car item) deltaY))
                )
              )
            )
            (setq i (1+ i))
          )
          (princ (strcat "\n    [틀 처리] 실제 행 슬롯 " (itoa nSlots) "개 중 재배치 대상 " (itoa N)
                          "개 (정상 " (itoa nv) " / 빈 " (itoa nb) ") -> 재배치 완료"
                          (if (> lockedCount 0)
                            (strcat " (부분 이관 행 " (itoa lockedCount) "개는 유지)")
                            ""
                          )))
        )
        (princ (strcat "\n    [틀 처리] 빈 행 없음 (실제 슬롯 " (itoa nSlots) "개) - 재배치 불필요"
                        (if (> lockedCount 0)
                          (strcat " (부분 이관 행 " (itoa lockedCount) "개는 유지)")
                          ""
                        )))
      )
    )
  )
)

;; 도면 전체에서 *GGM-FRAME-WIDTH* x *GGM-FRAME-HEIGHT* 크기(오차 *GGM-FRAME-TOL-PCT*)의
;; LWPOLYLINE 틀을 찾아, *MARK-LAYER*로 이관되어 빈 행이 된 자리를 틀 내부에서 재정렬
;; (FORM 블록 단위가 아닌 도면 전체 대상)
;; 리턴값: 처리한 틀 개수
(defun fc:ggm-step2 ( / ss-poly ss-text n polyent txtent bbox w h all-items hlines frame-count)
  (setq ss-poly (ssget "_X" (list (cons 0 "LWPOLYLINE"))))
  (setq frame-count 0)
  (if (not ss-poly)
    (princ "\n  도면에서 LWPOLYLINE을 찾을 수 없습니다.")
    (progn
      (setq ss-text
        (ssget "_X"
          (list
            (cons -4 "<AND")
              (cons -4 "<OR")
                (cons 0 "TEXT")
                (cons 0 "MTEXT")
              (cons -4 "OR>")
              (cons -4 "<OR")
                (cons 8 *GGM-SRC-LAYER*)
                (cons 8 *MARK-LAYER*)
                (cons 8 "LP*TEXT*")
              (cons -4 "OR>")
            (cons -4 "AND>")
          )
        )
      )
      (if (not ss-text)
        (princ (strcat "\n  대상 레이어(\"" *GGM-SRC-LAYER* "\", \"" *MARK-LAYER* "\")에 텍스트가 없습니다."))
        (progn
          (setq all-items '())
          (setq n 0)
          (repeat (sslength ss-text)
            (setq txtent (ssname ss-text n))
            (setq all-items (append all-items (list (fc:ggm-text-item txtent))))
            (setq n (1+ n))
          )
          (setq hlines (fc:ggm-collect-hlines))  ; 행 구분선 후보, 틀마다 재검색하지 않도록 한 번만 수집
          (setq n 0)
          (repeat (sslength ss-poly)
            (setq polyent (ssname ss-poly n))
            (setq bbox (fc:ggm-lwpoly-bbox polyent))
            (if bbox
              (progn
                (setq w (- (caddr bbox) (car bbox)))
                (setq h (- (cadddr bbox) (cadr bbox)))
                (if (and (fc:ggm-within-tol w *GGM-FRAME-WIDTH* *GGM-FRAME-TOL-PCT*)
                         (fc:ggm-within-tol h *GGM-FRAME-HEIGHT* *GGM-FRAME-TOL-PCT*))
                  (progn
                    (setq frame-count (1+ frame-count))
                    (fc:ggm-process-frame bbox all-items hlines)
                  )
                )
              )
            )
            (setq n (1+ n))
          )
          (princ (strcat "\n  크기 일치 틀 " (itoa frame-count) "개 처리했습니다."))
        )
      )
    )
  )
  frame-count
)

;; 메인 명령: [1/2] FORM 블록별 63mm 관련 자재 이관 -> [2/2] 틀 내부 빈 행 재정렬
(defun c:GGM ( / formList sortedList b idx bmin bmax total1 total2)
  (vl-load-com)
  (fc:ensure-layer *MARK-LAYER*)
  (princ "\n========== [1/2] FORM 블록별 63mm 관련 자재 이관 ==========")
  (princ "\n[FORM 블록 검색 중...]")
  (setq formList (fc:get-form-blocks-or-fallback))
  (setq total1 0)
  (if (not formList)
    (princ "\n>> FORM 블록도, 대체 사각형도 찾을 수 없습니다.")
    (progn
      (setq sortedList (fc:sort-reading-order formList))
      (princ (strcat "\n>> 총 " (itoa (length sortedList)) "개 FORM(또는 대체) 발견"))
      (setq idx 0)
      (foreach b sortedList
        (setq idx (1+ idx))
        (setq bmin (nth 1 b) bmax (nth 2 b))
        (princ (strcat "\n\n=== FORM 블록 " (itoa idx) " ==="))
        (setq total1 (+ total1 (fc:ggm-step1 bmin bmax)))
      )
      (princ (strcat "\n\n>> [1/2] 완료: 총 " (itoa total1) "개 항목 이관"))
    )
  )
  (princ "\n\n========== [2/2] 틀(프레임) 내부 빈 행 재정렬 ==========")
  (setq total2 (fc:ggm-step2))
  (princ (strcat "\n\n========== GGM 완료 (63mm 이관 " (itoa total1) "건 / 틀 " (itoa total2) "개 처리) =========="))
  (princ)
  (princ)
)

(princ "\nGGM 명령 사용 가능 (원본 gg-m: 63mm 관련 자재 레이어 이관 + 틀 내부 빈 행 재정렬)")
(princ)

;;;=======================================================================
;;; GGF 명령
;;;-----------------------------------------------------------------------
;;; 기능 요약
;;;  [1/2] *GGF-LAYERS* 목록의 각 레이어가 현재 켜져(ON) 있으면 끈다(OFF).
;;;        이미 꺼져 있는 레이어는 건드리지 않고, 도면에 없는 레이어는 건너뛴다.
;;;        대상 레이어: LPPE63ACAP, LPPE63A관로명, LPPE63A라인마크,
;;;                    신설관 LP PE 63mm, 신설관 LP 63mm PE
;;;  [2/2] "관로명" 레이어에서 "63mm PE(2m)"처럼 "63mm" 관경이 포함된
;;;        텍스트를 찾아 "0기술검토"(*MARK-LAYER*) 레이어로 이관한다.
;;;        (레이어 없으면 생성. 길이(괄호 안 숫자)는 얼마든 상관없음)
;;;=======================================================================

;; ---- GGF 설정값 ----
(setq *GGF-LAYERS*
  (list "LPPE63ACAP" "LPPE63A관로명" "LPPE63A라인마크"
        "신설관 LP PE 63mm" "신설관 LP 63mm PE")
)

;; 메인 명령: *GGF-LAYERS* 의 각 레이어가 켜져 있으면 끈다
;; ---- GGF 추가기능: "관로명" 레이어의 63mm 관경 텍스트 이관 ----
(setq *GGF-PIPENAME-LAYER* "관로명")  ; "63mm PE(2m)" 같은 관로명 텍스트가 있는 레이어

;; *GGF-PIPENAME-LAYER* 에서 텍스트 안에 "63mm"이 포함된 것을 찾아
;; *MARK-LAYER*("0기술검토")로 이관 (레이어 없으면 생성). 길이(괄호 안 숫자)는
;; 얼마든 상관없이 "63mm" 관경만 포함되면 대상이 됨.
;; 단, "225mmX63mm" 처럼 여러 관경이 결합된 형태는 제외한다.
;; 리턴값: 이관한 텍스트 개수
(defun fc:ggf-migrate-pipename-63mm ( / ss i ent obj txt ntxt cnt)
  (fc:ensure-layer *MARK-LAYER*)
  (setq cnt 0)
  (setq ss
    (ssget "_X"
      (list
        (cons -4 "<AND")
          (cons -4 "<OR") (cons 0 "TEXT") (cons 0 "MTEXT") (cons -4 "OR>")
          (cons 8 *GGF-PIPENAME-LAYER*)
        (cons -4 "AND>")
      )
    )
  )
  (if (not ss)
    (princ (strcat "\n  레이어 \"" *GGF-PIPENAME-LAYER* "\"에서 텍스트를 찾을 수 없습니다."))
    (progn
      (setq i 0)
      (repeat (sslength ss)
        (setq ent (ssname ss i))
        (setq obj (vlax-ename->vla-object ent))
        (setq txt (vla-get-textstring obj))
        (setq ntxt (fc:ggm-normalize-str txt))
        (cond
          ;; 결합형("225MMX63MM..." 처럼 MM 뒤에 X, 그 뒤에 또 MM이 나오는 형태)은 제외
          ((wcmatch ntxt "*MMX*MM*")
           (princ (strcat "\n  [건너뜀] 결합형 관경: " txt))
          )
          ((vl-string-search "63MM" ntxt)
           (vla-put-layer obj *MARK-LAYER*)
           (setq cnt (1+ cnt))
           (princ (strcat "\n  [이관] " txt))
          )
        )
        (setq i (1+ i))
      )
      (if (= cnt 0)
        (princ (strcat "\n  레이어 \"" *GGF-PIPENAME-LAYER* "\"에서 63mm 관련 텍스트를 찾지 못했습니다."))
      )
    )
  )
  cnt
)

(defun c:GGF ( / doc layers lyr layerObj offCount alreadyOffCount notFoundCount pipeCnt)
  (vl-load-com)
  (setq doc (vla-get-activedocument (vlax-get-acad-object)))
  (setq layers (vla-get-layers doc))
  (setq offCount 0 alreadyOffCount 0 notFoundCount 0)
  (princ "\n-- [1/2] 지정 레이어 끄기 --")
  (foreach lyr *GGF-LAYERS*
    (setq layerObj (vl-catch-all-apply 'vla-item (list layers lyr)))
    (if (vl-catch-all-error-p layerObj)
      (progn
        (setq notFoundCount (1+ notFoundCount))
        (princ (strcat "\n  [" lyr "] 레이어를 찾을 수 없습니다."))
      )
      (if (= (vla-get-layeron layerObj) :vlax-true)
        (progn
          (vla-put-layeron layerObj :vlax-false)
          (setq offCount (1+ offCount))
          (princ (strcat "\n  [" lyr "] 켜져 있음 -> 껐습니다"))
        )
        (progn
          (setq alreadyOffCount (1+ alreadyOffCount))
          (princ (strcat "\n  [" lyr "] 이미 꺼져 있음 (변경 없음)"))
        )
      )
    )
  )
  (princ "\n\n-- [2/2] \"관로명\" 레이어 63mm 텍스트 이관 --")
  (setq pipeCnt (fc:ggf-migrate-pipename-63mm))
  (princ (strcat "\n\n>> GGF 완료: " (itoa offCount) "개 레이어를 껐습니다. (이미 꺼짐 "
                  (itoa alreadyOffCount) "개 / 레이어 없음 " (itoa notFoundCount) "개) / \""
                  *GGF-PIPENAME-LAYER* "\" 63mm 텍스트 " (itoa pipeCnt) "개를 \""
                  *MARK-LAYER* "\" 레이어로 이관했습니다."))
  (princ)
  (princ)
)

(princ "\nGGF 명령 사용 가능 (지정 레이어가 켜져있으면 끄기 + \"관로명\" 63mm 텍스트 이관)")
(princ)

;;;=======================================================================
;;; GGA 명령 (통합 실행)
;;;-----------------------------------------------------------------------
;;; 순서대로 실행: GGL -> GGD -> GGM2 -> GGF, 끝나면 "0기술검토" 레이어 끄기
;;;=======================================================================

;; GGA 마지막: *MARK-LAYER*("0기술검토") 레이어를 끈다 (현재 레이어면 먼저 "0"으로 바꿈)
(defun fc:gga-hide-mark-layer ( / doc lyrObj)
  (setq doc (vla-get-activedocument (vlax-get-acad-object)))
  (setq lyrObj (vl-catch-all-apply 'vla-item (list (vla-get-layers doc) *MARK-LAYER*)))
  (if (vl-catch-all-error-p lyrObj)
    (princ (strcat "\n  [" *MARK-LAYER* "] 레이어가 없어 끄지 않았습니다."))
    (progn
      (if (= (strcase (getvar "CLAYER")) (strcase *MARK-LAYER*))
        (setvar "CLAYER" "0")
      )
      (vla-put-layeron lyrObj :vlax-false)
      (princ (strcat "\n  [" *MARK-LAYER* "] 레이어를 껐습니다."))
    )
  )
  (princ)
)

(defun c:GGA ( / doc *error*)
  (vl-load-com)
  (setq doc (vla-get-activedocument (vlax-get-acad-object)))
  ;; U 한 번으로 GGA 전체를 되돌릴 수 있게 하나의 되돌리기 묶음으로 처리
  (vla-startundomark doc)
  (defun *error* (msg)
    (vl-catch-all-apply 'vla-endundomark (list doc))
    (if (not (member msg '("Function cancelled" "quit / exit abort" "함수 취소됨")))
      (princ (strcat "\n>> GGA 오류: " msg))
    )
    (princ "\n>> GGA 중단됨. U 를 입력하면 실행 전으로 되돌립니다.")
    (princ)
  )
  (princ "\n========== [1/4] GGL 실행 ==========")
  (c:GGL)
  (princ "\n========== [2/4] GGD 실행 ==========")
  (c:GGD)
  (princ "\n========== [3/4] GGM2 실행 ==========")
  (c:GGM2)
  (princ "\n========== [4/4] GGF 실행 ==========")
  (c:GGF)
  (fc:gga-hide-mark-layer)
  (princ "\n\n========== GGA 완료 (GGL -> GGD -> GGM2 -> GGF) ==========")
  (sssetfirst nil nil)  ; 남아있는 선택(그립 표시) 해제
  (vla-endundomark doc)
  (princ "\n   (U 를 입력하면 GGA 실행 전으로 되돌립니다)")
  (if (and (boundp '*GGL-REDCOUNT*) (> *GGL-REDCOUNT* 0))
    (alert (strcat "종단면도 심도 및 관상부 레벨값 "
                    (itoa *GGL-REDCOUNT*) "건 확인이 필요합니다.(빨간색으로 표시됨)"))
  )
  (princ)
)

(princ "\nGGA 명령 사용 가능 (GGL -> GGD -> GGM2 -> GGF 순차 실행, 완료 후 GGL 텍스트그룹Q 오류시 팝업 확인)")
(princ)

;;;=======================================================================
;;; GGM2 명령 (자재내역 63mm 그룹 이관 - 어휘 기반 재구현)
;;;-----------------------------------------------------------------------
;;; 기능 요약
;;;  1) 도면 전체에서 크기 66.4770 x 82.5520(오차 5%, *GGM-FRAME-WIDTH*/
;;;     *GGM-FRAME-HEIGHT* 재사용)인 LWPOLYLINE "자재내역 틀"을 찾는다.
;;;     (도곽 자체는 크기가 훨씬 커서 자동으로 제외됨)
;;;  2) 틀 내부의 텍스트를 Y좌표로 행(Row)별로 묶는다.
;;;  3) 각 행에서 다음 항목들을 "내용(어휘)"으로 인식한다:
;;;     - 텍스트A(관경): "63mm" 처럼 "mm"을 포함하는 텍스트
;;;       (복합형 "225mmX110mm" 도 인식됨)
;;;     - 자재구분(좌측): 직 관/연결관/인입관/TEE/S.TEE/90°ELBOW/45°ELBOW/
;;;       C A P/VALVE/REDUCER 중 하나 (공백 유무 무관, 도(度)기호는
;;;       "%%D" 제어코드/"°" 문자 둘 다 인식)
;;;     - 단위: EA 또는 m
;;;     - 수량: 정수 또는 소수 숫자
;;;     - 재질(선택): PE 또는 PLP (없을 수 있음)
;;;  4) 텍스트A에 "63mm"이 포함된 행을 찾아 그 행의 인식된 항목들을
;;;     하나의 그룹으로 묶어 "0기술검토" 레이어로 이관한다(레이어 없으면 생성).
;;;     단, 자재구분이 REDUCER인 경우는 이관하지 않는다.
;;;=======================================================================

;; ---- GGM2 어휘(수정 가능) ----
(setq *GGM2-CATEGORY-RAW*
  (list "직 관" "연결관" "인입관" "TEE" "S.TEE"
        "90%%DELBOW" "90°ELBOW"
        "45%%DELBOW" "45°ELBOW"
        "C  A  P" "VALVE" "REDUCER")
)
(setq *GGM2-UNIT-RAW*     (list "EA" "m"))
(setq *GGM2-MATERIAL-RAW* (list "PE" "PLP"))
(setq *GGM2-QTY-YTOL*     1.0)    ; 수량 텍스트를 텍스트A와 "같은 행"으로 볼 Y오차
(setq *GGM2-SEQ-X-TOL*    2.0)    ; 순번 컬럼(같은 세로열) 판정 X오차
(setq *GGM2-SEQ-MIN-COUNT* 3)     ; 순번 컬럼으로 인정할 최소 연속 개수(1,2,3...)

;; 어휘를 정규화(공백 제거+대문자화)해서 비교용 목록 생성
(setq *GGM2-CATEGORY-NORM* (mapcar 'fc:ggm-normalize-str *GGM2-CATEGORY-RAW*))
(setq *GGM2-UNIT-NORM*     (mapcar 'fc:ggm-normalize-str *GGM2-UNIT-RAW*))
(setq *GGM2-MATERIAL-NORM* (mapcar 'fc:ggm-normalize-str *GGM2-MATERIAL-RAW*))

;; 정규화된 문자열이 "정수" 또는 "소수"(수량) 형식인지 확인
(defun fc:ggm2-is-quantity-p (s / dotpos intpart decpart)
  (setq dotpos (vl-string-search "." s))
  (if dotpos
    (progn
      (setq intpart (substr s 1 dotpos))
      (setq decpart (substr s (+ dotpos 2)))
      (and (> (strlen intpart) 0) (> (strlen decpart) 0)
           (fc:all-digits-p intpart) (fc:all-digits-p decpart))
    )
    (fc:all-digits-p s)
  )
)

;; 정규화된 텍스트 하나를 어휘 종류로 분류: CATEGORY/UNIT/MATERIAL/DIASPEC/QUANTITY/UNKNOWN
(defun fc:ggm2-classify (normtext)
  (cond
    ((member normtext *GGM2-CATEGORY-NORM*) "CATEGORY")
    ((member normtext *GGM2-UNIT-NORM*) "UNIT")
    ((member normtext *GGM2-MATERIAL-NORM*) "MATERIAL")
    ((wcmatch normtext "*MM*") "DIASPEC")
    ((fc:ggm2-is-quantity-p normtext) "QUANTITY")
    (T "UNKNOWN")
  )
)

;; ---- 순번(1,2,3...) 컬럼 판별 및 제외 ----

;; 정수 텍스트 아이템들을 X좌표(같은 세로열, 오차 tol)로 그룹핑
(defun fc:ggm2-group-by-x (items tol / sorted groups placed it)
  (setq sorted (vl-sort items (function (lambda (a b) (< (nth 1 a) (nth 1 b)))))) ; x asc
  (setq groups '())
  (foreach it sorted
    (setq placed nil)
    (setq groups
      (mapcar
        (function
          (lambda (grp)
            (if (and (not placed) grp (<= (abs (- (nth 1 it) (nth 1 (car grp)))) tol))
              (progn (setq placed T) (append grp (list it)))
              grp
            )
          )
        )
        groups
      )
    )
    (if (not placed) (setq groups (append groups (list (list it)))))
  )
  groups
)

;; 한 컬럼(grp)이 "아래(Y작음)->위(Y큼)" 순서로 정렬했을 때
;; 값이 정확히 1,2,3,...N 으로 오름차순인지 확인 (순번 컬럼 판정)
(defun fc:ggm2-is-ascending-seq-p (grp / sorted n i v ok)
  (setq n (length grp))
  (if (< n *GGM2-SEQ-MIN-COUNT*)
    nil
    (progn
      (setq sorted (vl-sort grp (function (lambda (a b) (< (nth 2 a) (nth 2 b)))))) ; y asc
      (setq ok T i 0)
      (while (and ok (< i n))
        (setq v (atoi (nth 5 (nth i sorted))))
        (if (/= v (1+ i)) (setq ok nil))
        (setq i (1+ i))
      )
      ok
    )
  )
)

;; items 중 "좌측하단부터 1,2,3...으로 오름차순인 순번 컬럼"에 속하는 항목을 찾아
;; 전체 목록에서 제외한 결과를 반환 (행 분류 이전에 미리 걸러내기 위함)
(defun fc:ggm2-exclude-seqnum (items / candidates colGroups grp excludeEnts it)
  (setq candidates '())
  (foreach it items
    (if (fc:all-digits-p (nth 5 it))  ; 소수점 있는 텍스트는 all-digits-p가 nil이라 자동 제외됨
      (setq candidates (append candidates (list it)))
    )
  )
  (setq colGroups (fc:ggm2-group-by-x candidates *GGM2-SEQ-X-TOL*))
  (setq excludeEnts '())
  (foreach grp colGroups
    (if (fc:ggm2-is-ascending-seq-p grp)
      (foreach it grp (setq excludeEnts (append excludeEnts (list (car it)))))
    )
  )
  (if excludeEnts
    (vl-remove-if (function (lambda (it) (member (car it) excludeEnts))) items)
    items
  )
)

;; ---- GGM2 전용: 틀 안쪽으로 엄격하게 제한된 텍스트 수집 + 무관한 텍스트 필터링 ----
;; (fc:ggm-gather-texts 는 FORM 블록 규모(약 397x274)용 여유값(*GGM-BOX-EPS*=5.0)을
;;  쓰는데, GGM2의 자재내역 틀은 훨씬 작아서(66.477x82.552) 같은 여유값을 쓰면
;;  틀 바깥의 무관한 도면 주석(담장/제수변/통신주 등)까지 끌려들어올 수 있음)
(setq *GGM2-BOX-EPS* 0.5)  ; 자재내역 틀 경계 판정 여유(도면단위) - 최소한으로 제한

(defun fc:ggm2-gather-texts (bmin bmax / ss i ent pt lst xmin ymin xmax ymax)
  (setq xmin (- (car bmin) *GGM2-BOX-EPS*) ymin (- (cadr bmin) *GGM2-BOX-EPS*))
  (setq xmax (+ (car bmax) *GGM2-BOX-EPS*) ymax (+ (cadr bmax) *GGM2-BOX-EPS*))
  (setq lst '())
  (setq ss (ssget "_X" (list (cons -4 "<OR") (cons 0 "TEXT") (cons 0 "MTEXT") (cons -4 "OR>"))))
  (if ss
    (progn
      (setq i 0)
      (repeat (sslength ss)
        (setq ent (ssname ss i))
        (setq pt (fc:get-text-position ent))
        (if (and (>= (car pt) xmin) (<= (car pt) xmax)
                 (>= (cadr pt) ymin) (<= (cadr pt) ymax))
          (setq lst (append lst (list (fc:ggm-text-item ent))))
        )
        (setq i (1+ i))
      )
    )
  )
  lst
)

;; items 중 자재내역 어휘(자재구분/단위/재질/관경/수량)로 분류되는 것만 남긴다.
;; (담장/제수변/통신주 같은 자재내역과 무관한 텍스트가 행에 섞여 함께
;;  이동하지 않도록, 정렬/이관 대상 자체를 어휘 기준으로 한정함)
(defun fc:ggm2-filter-relevant (items / it cls result)
  (setq result '())
  (foreach it items
    (setq cls (fc:ggm2-classify (nth 5 it)))
    (if (member cls (list "CATEGORY" "UNIT" "MATERIAL" "DIASPEC" "QUANTITY"))
      (setq result (append result (list it)))
    )
  )
  result
)

;; 한 행(row, X오름차순)에서 텍스트A(관경, "63mm" 포함)를 찾고,
;; 같은 행에서 자재구분/단위/재질 항목을 각각 하나씩 인식하고,
;; 수량은 텍스트A의 +X 방향(Y오차 *GGM2-QTY-YTOL* 이내)에서 가장 가까운
;; 숫자 텍스트로 찾는다. 이렇게 모은 항목을 하나의 그룹으로 묶어
;; "0기술검토" 레이어로 이관한다. 단, 자재구분이 REDUCER면 이관하지 않는다.
;; 리턴값: 이 행에서 이관한 항목 개수
(defun fc:ggm2-process-row (row / it cls textA category unit material
                             quantity bestD d group hasReducer movedCount)
  (setq textA nil category nil unit nil material nil)
  (foreach it row
    (setq cls (fc:ggm2-classify (nth 5 it)))
    (cond
      ((and (= cls "DIASPEC") (not textA)) (setq textA it))
      ((and (= cls "CATEGORY") (not category)) (setq category it))
      ((and (= cls "UNIT") (not unit)) (setq unit it))
      ((and (= cls "MATERIAL") (not material)) (setq material it))
    )
  )
  (setq movedCount 0)
  (if (and textA (vl-string-search "63MM" (nth 5 textA)))
    (progn
      (setq hasReducer (and category (= (nth 5 category) "REDUCER")))
      (if hasReducer
        (princ (strcat "\n    [건너뜀] REDUCER: " (nth 4 textA)
                        " (" (nth 4 category) ")"))
        (progn
          ;; 수량: 텍스트A의 +X 방향, Y오차 *GGM2-QTY-YTOL* 이내에서 가장 가까운 숫자 텍스트
          (setq quantity nil bestD nil)
          (foreach it row
            (if (and (/= (car it) (car textA))
                     (> (nth 1 it) (nth 1 textA))
                     (<= (abs (- (nth 2 it) (nth 2 textA))) *GGM2-QTY-YTOL*)
                     (fc:ggm2-is-quantity-p (nth 5 it)))
              (progn
                (setq d (- (nth 1 it) (nth 1 textA)))
                (if (or (not bestD) (< d bestD))
                  (progn (setq quantity it) (setq bestD d))
                )
              )
            )
          )

          (setq group '())
          (if category (setq group (append group (list category))))
          (setq group (append group (list textA)))
          (if unit (setq group (append group (list unit))))
          (if quantity (setq group (append group (list quantity))))
          (if material (setq group (append group (list material))))
          ;; X좌표 순으로 정렬해서 자연스러운 순서로 출력
          (setq group (vl-sort group (function (lambda (a b) (< (nth 1 a) (nth 1 b))))))
          (foreach it group (fc:ggm-move-to-mark (car it)))
          (setq movedCount (length group))
          (princ (strcat "\n    [이관] 그룹(" (itoa movedCount) "개): " (fc:ggm-join-texts group)))
          (if (not category)
            (princ "\n    [참고] 자재구분(카테고리) 항목을 찾지 못했습니다.")
          )
          (if (not quantity)
            (princ "\n    [참고] 수량 항목을 찾지 못했습니다.")
          )
        )
      )
    )
  )
  movedCount
)

;; 하나의 "자재내역 틀"(bbox: minx miny maxx maxy) 안에서 GGM2 처리
;; 리턴값: 이관된 항목 총 개수
(defun fc:ggm2-process-frame (bbox / bmin bmax items rows row total excludedN)
  (setq bmin (list (car bbox) (cadr bbox)))
  (setq bmax (list (caddr bbox) (cadddr bbox)))
  (setq items (fc:ggm2-gather-texts bmin bmax))  ; 틀 안쪽으로 엄격 제한
  (setq total 0)
  (if (not items)
    (princ "\n  틀 내부에서 텍스트를 찾을 수 없습니다.")
    (progn
      (setq excludedN (length items))
      (setq items (fc:ggm2-exclude-seqnum items))
      (setq excludedN (- excludedN (length items)))
      (if (> excludedN 0)
        (princ (strcat "\n  [순번 제외] 오름차순 순번 컬럼 " (itoa excludedN) "개 항목을 분류 대상에서 제외했습니다."))
      )
      (setq items (fc:ggm2-filter-relevant items))  ; 자재내역 어휘와 무관한 텍스트 제거
      (setq rows (fc:ggm-group-rows items))
      (foreach row rows
        (setq total (+ total (fc:ggm2-process-row row)))
      )
      (if (= total 0)
        (princ "\n  63mm 관련 자재 그룹을 찾지 못했습니다.")
        (princ (strcat "\n  63mm 관련 총 " (itoa total) "개 항목을 \"" *MARK-LAYER* "\" 레이어로 이관했습니다."))
      )
    )
  )
  total
)

;; 메인 명령: 도면 전체에서 자재내역 틀(66.477 x 82.552)을 찾아 63mm 그룹 이관
(defun c:GGM2 ( / ss-poly n polyent bbox w h frameCount total)
  (vl-load-com)
  (fc:ensure-layer *MARK-LAYER*)
  (princ "\n[자재내역 틀 검색 중...]")
  (setq ss-poly (ssget "_X" (list (cons 0 "LWPOLYLINE"))))
  (setq frameCount 0 total 0)
  (if (not ss-poly)
    (princ "\n>> 도면에서 LWPOLYLINE을 찾을 수 없습니다.")
    (progn
      (setq n 0)
      (repeat (sslength ss-poly)
        (setq polyent (ssname ss-poly n))
        (setq bbox (fc:ggm-lwpoly-bbox polyent))
        (if bbox
          (progn
            (setq w (- (caddr bbox) (car bbox)))
            (setq h (- (cadddr bbox) (cadr bbox)))
            (if (and (fc:ggm-within-tol w *GGM-FRAME-WIDTH* *GGM-FRAME-TOL-PCT*)
                     (fc:ggm-within-tol h *GGM-FRAME-HEIGHT* *GGM-FRAME-TOL-PCT*))
              (progn
                (setq frameCount (1+ frameCount))
                (princ (strcat "\n\n=== 자재내역 틀 " (itoa frameCount) " ==="))
                (setq total (+ total (fc:ggm2-process-frame bbox)))
              )
            )
          )
        )
        (setq n (1+ n))
      )
      (princ (strcat "\n\n>> GGM2 완료: 틀 " (itoa frameCount) "개 / 63mm 관련 그룹 총 "
                      (itoa total) "개 항목 이관"))
    )
  )
  (princ)
  (princ)
)

(princ "\nGGM2 명령 사용 가능 (어휘 기반 자재내역 63mm 그룹 인식/이관)")
(princ)

;;;=======================================================================
;;; GGM3 명령 (자재내역 정렬 - "직관" 그룹 기준, GGM2에서 분리됨)
;;;-----------------------------------------------------------------------
;;; 기능 요약
;;;  GGM2 이관 이후, 자재내역 틀(66.477 x 82.552) 안에서 빈칸을 채운다.
;;;  0기술검토 레이어는 완전히 제외하고, "직관" 텍스트가 포함된 행 중
;;;  가장 아래(마지막 슬롯) 것을 기준으로 고정한 뒤, 기준보다 위에 있는
;;;  내용 있는 행들만 원래 순서를 유지한 채 기준 바로 위부터 빈틈없이 채운다.
;;;  기준(anchor) 자체는 레이어와 무관하게 "직관" 텍스트가 있던 슬롯으로
;;;  찾으므로, 직관 항목 자체가 63mm 이관 대상이어서 이미 0기술검토로
;;;  옮겨졌어도 그 위치는 여전히 기준점으로 유효하다.
;;;=======================================================================

;; rows(슬롯별 아이템 리스트, 상->하) 중 "직관" 텍스트가 포함된
;; 가장 마지막(가장 아래) 슬롯의 인덱스를 반환 (없으면 nil)
(defun fc:ggm3-find-anchor-index (rows / idx i it row found)
  (setq idx nil i 0)
  (foreach row rows
    (setq found nil)
    (foreach it row
      (if (= (nth 5 it) "직관") (setq found T))
    )
    (if found (setq idx i))  ; 계속 덮어써서 마지막(가장 아래) 매치가 남도록 함
    (setq i (1+ i))
  )
  idx
)

;; 하나의 자재내역 틀(bbox)에서 "직관" 그룹 기준 정렬 수행
;; 리턴값: 이동(재배치)한 행 개수
(defun fc:ggm3-align-frame (bbox hlines / boundaries nSlots bmin bmax allItems contentItems
                             allRows contentRows anchorIdx slotYs validAbove i j row cnt target
                             repY deltaY item movedRows)
  (setq boundaries (fc:ggm-find-row-dividers bbox hlines))
  (setq nSlots (1- (length boundaries)))
  (setq movedRows 0)
  (if (< nSlots 1)
    (princ "\n  [정렬] 행 구분선을 찾을 수 없어 정렬을 건너뜁니다.")
    (progn
      (setq bmin (list (car bbox) (cadr bbox)))
      (setq bmax (list (caddr bbox) (cadddr bbox)))
      (setq allItems (fc:ggm2-gather-texts bmin bmax))  ; 틀 안쪽으로 엄격 제한, 레이어 무관(기준 탐색용)
      (setq allItems (fc:ggm2-exclude-seqnum allItems))
      (setq allItems (fc:ggm2-filter-relevant allItems))  ; 자재내역 어휘와 무관한 텍스트 제거
      ;; 압축 대상 판단용: 0기술검토 레이어는 완전히 제외
      (setq contentItems (vl-remove-if (function (lambda (it) (= (nth 6 it) *MARK-LAYER*))) allItems))
      (setq allRows (fc:ggm-build-slot-rows allItems boundaries))         ; 기준(anchor) 탐색용
      (setq contentRows (fc:ggm-build-slot-rows contentItems boundaries)) ; 압축 대상 판단용

      ;; 기준은 레이어와 무관하게 "직관" 텍스트가 있던 슬롯 중 가장 아래(마지막)로 찾는다.
      (setq anchorIdx (fc:ggm3-find-anchor-index allRows))
      (if (not anchorIdx)
        (princ "\n  [정렬] \"직관\" 그룹을 찾지 못해 정렬을 건너뜁니다.")
        (progn
          ;; 슬롯별 대표 Y(경계 중간값) 목록
          (setq slotYs '() i 0)
          (while (< i nSlots)
            (setq slotYs (append slotYs (list (/ (+ (nth i boundaries) (nth (1+ i) boundaries)) 2.0))))
            (setq i (1+ i))
          )

          ;; 기준(anchorIdx) 위쪽(0..anchorIdx-1) 중 "현재 내용이 남아있는"(0기술검토 제외) 행만
          ;; 원래 순서(위->아래) 그대로 수집
          (setq validAbove '() i 0)
          (while (< i anchorIdx)
            (setq row (nth i contentRows))
            (if row (setq validAbove (append validAbove (list row))))
            (setq i (1+ i))
          )
          (setq cnt (length validAbove))

          (if (= cnt 0)
            (princ "\n  [정렬] 기준(직관) 위에 채울 내용이 없습니다.")
            (progn
              ;; validAbove 의 j번째(0부터, 원래 순서) -> 슬롯 (anchorIdx-cnt+j)
              ;; 즉 기준에 가장 가까웠던 행(마지막 요소)이 anchorIdx-1 슬롯으로,
              ;; 순서를 유지한 채 기준 바로 위부터 빈틈없이 채워짐
              (setq j 0)
              (foreach row validAbove
                (setq target (+ (- anchorIdx cnt) j))
                (setq repY (nth 2 (car row)))
                (setq deltaY (- (nth target slotYs) repY))
                (if (> (abs deltaY) 1e-6)
                  (progn
                    (foreach item row (fc:ggm-translate-text-y (car item) deltaY))
                    (setq movedRows (1+ movedRows))
                  )
                )
                (setq j (1+ j))
              )
              (princ (strcat "\n  [정렬] 기준(직관) 위 " (itoa cnt) "개 행 중 "
                              (itoa movedRows) "개 재배치 완료"))
            )
          )
        )
      )
    )
  )
  movedRows
)

;; 메인 명령: 도면 전체에서 자재내역 틀(66.477 x 82.552)을 찾아 "직관" 기준 정렬
(defun c:GGM3 ( / ss-poly n polyent bbox w h hlines frameCount totalAligned)
  (vl-load-com)
  (princ "\n[자재내역 틀 검색 중...]")
  (setq ss-poly (ssget "_X" (list (cons 0 "LWPOLYLINE"))))
  (setq frameCount 0 totalAligned 0)
  (if (not ss-poly)
    (princ "\n>> 도면에서 LWPOLYLINE을 찾을 수 없습니다.")
    (progn
      (setq hlines (fc:ggm-collect-hlines))  ; 행 구분선 후보, 틀마다 재검색하지 않도록 한 번만 수집
      (setq n 0)
      (repeat (sslength ss-poly)
        (setq polyent (ssname ss-poly n))
        (setq bbox (fc:ggm-lwpoly-bbox polyent))
        (if bbox
          (progn
            (setq w (- (caddr bbox) (car bbox)))
            (setq h (- (cadddr bbox) (cadr bbox)))
            (if (and (fc:ggm-within-tol w *GGM-FRAME-WIDTH* *GGM-FRAME-TOL-PCT*)
                     (fc:ggm-within-tol h *GGM-FRAME-HEIGHT* *GGM-FRAME-TOL-PCT*))
              (progn
                (setq frameCount (1+ frameCount))
                (princ (strcat "\n\n=== 자재내역 틀 " (itoa frameCount) " ==="))
                (setq totalAligned (+ totalAligned (fc:ggm3-align-frame bbox hlines)))
              )
            )
          )
        )
        (setq n (1+ n))
      )
      (princ (strcat "\n\n>> GGM3 완료: 틀 " (itoa frameCount) "개 / 정렬로 재배치된 행 총 "
                      (itoa totalAligned) "개"))
    )
  )
  (princ)
  (princ)
)

(princ "\nGGM3 명령 사용 가능 (자재내역 \"직관\" 그룹 기준 정렬 - GGM2에서 분리됨)")
(princ)
