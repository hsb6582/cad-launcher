;;; ======================================================================
;;; BPDF.lsp
;;; AutoCAD / AutoCAD LT 2024 이상에서 동작
;;;
;;; 기능: "FORM" 블록(도곽/타이틀블록) 또는 "FORM_" 레이어의 지정 크기 사각형을
;;;       기준으로, 하나당 한 장씩 그 경계상자(Window) 영역만 잘라서
;;;       개별 PDF 파일로 출력합니다.
;;;       (PDF는 "원본 DWG 파일이 있는 폴더"에 저장됩니다)
;;;
;;; 도면번호 자동 넘버링: 도곽 안의 도면번호(예: 홍성-2026-LP-001)와 내용을 읽어
;;;       "LP001_A" 처럼 파일명을 붙입니다. 같은 번호인데 도곽 안에 평면도/종단면도
;;;       글자가 없으면 "LP001_B", "LP001_C"... (도곽 밖의 글자는 무시)
;;;       끄려면 run-bpdf 안의 (setq auto-number T) 를 nil 로 바꾸세요.
;;;
;;; 플롯 스타일: "평면도A3.ctb" 파일이 필요합니다. 플롯 스타일 폴더
;;;       (옵션 > 파일 탭 > "플롯 스타일 테이블 검색 경로")에 없으면,
;;;       런처와 함께 받은 lsp\평면도A3.ctb 를 그 폴더로 자동 복사해서 씁니다.
;;;
;;; 사용법:
;;;   1) APPLOAD 명령으로 이 파일을 로드
;;;   2) 명령행에 아래 둘 중 하나 입력
;;;        BPDF    -> 자동감지 모드 (위치순으로 자동 정렬되어 번호 매김)
;;;        BPDF_S  -> 직접선택 모드 (화면에서 클릭한 순서대로 번호 매김)
;;;
;;; 참고: 원본 폴더가 OneDrive 등 클라우드 동기화 폴더라면 쓰기 지연/충돌로
;;;       파일 생성이 안 될 수 있습니다. 그럴 경우 로컬 저장 버전
;;;       (BatchPlotFormBlocks.lsp / 명령어 BPDFFORM)을 사용하세요.
;;; ======================================================================

;; Visual LISP / ActiveX(COM) 환경 초기화 - vla-*, vlax-* 함수 사용 전 필수
(vl-load-com)

(defun pad2 (n / s)
  (setq s (itoa n))
  (if (< n 10) (strcat "0" s) s)
)

(defun sanitize-filename (s)
  ;; 파일명에 쓸 수 없는 문자를 밑줄로 치환
  (vl-string-translate "\\/:*?\"<>|" "__________" s)
)

(defun get-ins-pt (ent)
  (cdr (assoc 10 (entget ent)))
)

(defun get-attrib-value (vla-obj tag / atts result att)
  (setq result nil)
  (if (and vla-obj (= (vla-get-hasattributes vla-obj) :vlax-true))
    (progn
      (setq atts (vlax-invoke vla-obj 'GetAttributes))
      (foreach att atts
        (if (and (not result)
                 (= (strcase (vla-get-tagstring att)) (strcase tag)))
          (setq result (vla-get-textstring att))
        )
      )
    )
  )
  result
)

;; 사용자가 화면에서 직접 하나씩 선택 (선택한 순서 그대로 리스트 반환)
(defun manual-pick-list ( / result sel ent)
  (setq result nil)
  (princ "\n시트 영역이 될 객체(FORM 블록 또는 사각형)를 원하는 순서대로 선택하세요.")
  (while (setq sel (entsel "\n객체 선택 (Enter=완료): "))
    (setq ent (car sel))
    (setq result (append result (list ent)))
    (princ (strcat "  [" (itoa (length result)) "번째 선택됨]"))
  )
  result
)

;; LWPOLYLINE의 꼭지점 개수 세기
(defun count-vertices (e / cnt)
  (setq cnt 0)
  (foreach pair (entget e)
    (if (= (car pair) 10) (setq cnt (1+ cnt)))
  )
  cnt
)

;; layer-name 레이어에서 닫힌 4각형 LWPOLYLINE 중, 지정한 가로/세로/둘레 값과
;; 각각의 허용오차 이내로 일치하는 것만 찾아서 반환 (회전으로 가로세로가 뒤바뀐 경우도 인식)
(defun find-form-rects (layer-name target-w target-h ratio-tol min-w
                         / ss idx e vc candidates
                           vla-obj minpt maxpt minlst maxlst w h ratio target-ratio result)
  ;; layer-name 레이어(쉼표로 여러 개 가능)의 LWPOLYLINE 중, 꼭지점 4~6개이고
  ;; 가로세로 비율이 도곽(target-w : target-h)과 같으며(오차 ratio-tol) 가로/세로 중
  ;; 짧은 변이 min-w 이상인 것을 도곽으로 인식. 크기는 상관없음(축소/확대 도곽 대응).
  (setq candidates nil)
  (setq target-ratio (/ (max target-w target-h) (min target-w target-h)))
  (setq ss (ssget "X" (list (cons 0 "LWPOLYLINE") (cons 8 layer-name))))
  (if ss
    (progn
      (setq idx 0)
      (while (setq e (ssname ss idx))
        (setq vc (count-vertices e))
        (if (and (>= vc 4) (<= vc 6)                   ;; 꼭지점 4~6개 (열린 폴리선/중복 꼭지점 포함)
                 (/= (cdr (assoc 67 (entget e))) 1))     ;; 배치공간 제외
          (setq candidates (cons e candidates))
        )
        (setq idx (1+ idx))
      )
    )
  )
  (setq result nil)
  (foreach e candidates
    (setq vla-obj (vlax-ename->vla-object e))
    (if (not (vl-catch-all-error-p
               (vl-catch-all-apply 'vla-getboundingbox (list vla-obj 'minpt 'maxpt))))
      (progn
        (setq minlst (vlax-safearray->list minpt))
        (setq maxlst (vlax-safearray->list maxpt))
        (setq w (- (car maxlst) (car minlst)))
        (setq h (- (cadr maxlst) (cadr minlst)))
        (if (and (> (min w h) 0.0) (>= (min w h) min-w))
          (progn
            (setq ratio (/ (max w h) (min w h)))
            (if (< (abs (- ratio target-ratio)) ratio-tol)
              (setq result (cons e result)))
          )
        )
      )
    )
  )
  result
)

;; ======================================================================
;; 도면번호 자동 넘버링 (도곽 안의 글자만 사용, 도곽 밖 글자는 무시)
;;   예) 홍성-2026-LP-001 -> LP001_A
;;       같은 번호인데 도곽 안에 평면도/종단면도 글자가 없으면 -> LP001_B, C ...
;; ======================================================================

;; 단계별 오류를 잡아서 어느 단계에서 실패했는지 표시 (실패해도 출력은 계속)
(defun dn-stage (name fn / r)
  (setq r (vl-catch-all-apply fn nil))
  (if (vl-catch-all-error-p r)
    (progn
      (princ (strcat "\n[자동넘버링 오류 " name "] " (vl-catch-all-error-message r)))
      nil
    )
    r
  )
)

;; AutoLISP 의 (or ..) 는 값이 아니라 T/nil 만 돌려주므로, 기본값 처리는 이 함수로 한다
(defun dn-def (v d)
  (if v v d)
)

;; 문자열을 최대 n글자로 자름 (한글 등 2바이트 문자는 반으로 잘리지 않게 처리)
(defun dn-trunc (str n / i cnt c res)
  (setq i 1 cnt 0 res "")
  (while (and (<= i (strlen str)) (< cnt n))
    (setq c (ascii (substr str i 1)))
    (if (> c 127)
      (progn (setq res (strcat res (substr str i 2))) (setq i (+ i 2)))
      (progn (setq res (strcat res (substr str i 1))) (setq i (1+ i)))
    )
    (setq cnt (1+ cnt))
  )
  ;; 끝의 공백/마침표 제거 (파일명으로 쓸 수 없음)
  (while (and (> (strlen res) 0) (member (substr res (strlen res) 1) '(" " ".")))
    (setq res (substr res 1 (1- (strlen res))))
  )
  res
)

(defun dn-digit-p (c)
  (and c (>= c 48) (<= c 57))
)

(defun dn-nospace (s)
  (while (vl-string-search " " s)
    (setq s (vl-string-subst "" " " s))
  )
  s
)

;; 대문자 문자열 u 에서 kind("LP"/"MP")로 시작해 "-숫자"로 끝나는 토큰을 찾는다.
;; 반환: (kind 숫자 원문토큰) 또는 nil.  영문자 바로 뒤의 LP/MP(예: TEMP-001)는 제외.
(defun dn-try (u kind / start p len tok-end tok j res prev)
  (setq start 0 res nil len (strlen u))
  (while (and (not res) (setq p (vl-string-search kind u start)))
    (setq start (1+ p))
    (setq prev (if (> p 0) (ascii (substr u p 1)) 0))
    (if (not (and (>= prev 65) (<= prev 90)))
      (progn
        (setq tok-end p)
        (while (and (< tok-end len)
                    (not (member (substr u (1+ tok-end) 1)
                                 '(" " "\\" "{" "}" ";" "\t" "\n"))))
          (setq tok-end (1+ tok-end))
        )
        (setq tok (substr u (1+ p) (- tok-end p)))
        (setq j (strlen tok))
        (while (and (> j 0) (dn-digit-p (ascii (substr tok j 1))))
          (setq j (1- j))
        )
        (if (and (> j 0) (< j (strlen tok)) (= (substr tok j 1) "-"))
          (setq res (list kind (atoi (substr tok (1+ j))) tok))
        )
      )
    )
  )
  res
)

(defun dn-parse (s / u)
  (setq u (strcase s))
  (dn-def (dn-try u "LP") (dn-try u "MP"))
)

(defun dn-has-keyword (s kws / ns found)
  (setq ns (dn-nospace s) found nil)
  (foreach kw kws
    (if (vl-string-search kw ns) (setq found T))
  )
  found
)

;; TEXT/ATTRIB 의 실제 위치 (정렬이 기본값이 아니면 group 11)
(defun dn-text-pos (ed / typ h v)
  (setq typ (cdr (assoc 0 ed)))
  (setq h (dn-def (cdr (assoc 72 ed)) 0))
  (setq v (dn-def (cdr (assoc (if (= typ "ATTRIB") 74 73) ed)) 0))
  (if (and (member typ '("TEXT" "ATTRIB")) (or (/= h 0) (/= v 0)) (assoc 11 ed))
    (cdr (assoc 11 ed))
    (cdr (assoc 10 ed))
  )
)

;; TEXT/MTEXT/ATTRIB 엔티티 데이터에서 문자열 얻기
(defun dn-ent-string (ed / s pr)
  (if (= (cdr (assoc 0 ed)) "MTEXT")
    (progn
      (setq s "")
      (foreach pr ed
        (if (member (car pr) '(3 1)) (setq s (strcat s (cdr pr))))
      )
      s
    )
    (cdr (assoc 1 ed))
  )
)

;; 블록 좌표 -> 상위 좌표 변환. xf = (삽입x 삽입y 배율x 배율y 회전(rad) 기준x 기준y)
(defun dn-xf (p xf / x y c sn)
  (setq x (* (- (car p) (nth 5 xf)) (nth 2 xf))
        y (* (- (cadr p) (nth 6 xf)) (nth 3 xf)))
  (setq c (cos (nth 4 xf)) sn (sin (nth 4 xf)))
  (list (+ (nth 0 xf) (- (* x c) (* y sn)))
        (+ (nth 1 xf) (+ (* x sn) (* y c))))
)

(defun dn-xf-chain (p chain / xf)
  (foreach xf chain (setq p (dn-xf p xf)))
  p
)

;; 블록 정의 안의 글자(중첩 블록 포함)를 월드 좌표로 변환해서 (문자열 x y) 리스트로 반환
;;  ins = (삽입x 삽입y 배율x 배율y 회전), parent = 상위 변환 목록(안쪽->바깥쪽 순)
(defun dn-walk-block (bname ins parent depth / be base chain a ad typ s p res nm nins)
  (setq res nil)
  (setq be (tblobjname "BLOCK" bname))
  (if (and be (< depth 4))
    (progn
      (setq base (cdr (assoc 10 (entget be))))
      (setq chain (cons (append ins (list (car base) (cadr base))) parent))
      (setq a (entnext be))
      (while (and a (/= (cdr (assoc 0 (setq ad (entget a)))) "ENDBLK"))
        (setq typ (cdr (assoc 0 ad)))
        (cond
          ((member typ '("TEXT" "MTEXT" "ATTRIB"))
           (setq s (dn-ent-string ad))
           (setq p (dn-text-pos ad))
           (if (and s p)
             (progn
               (setq p (dn-xf-chain p chain))
               (setq res (cons (list s (car p) (cadr p)) res))
             )
           )
          )
          ((= typ "INSERT")
           (setq nm (cdr (assoc 2 ad)))
           (setq p (cdr (assoc 10 ad)))
           (setq nins (list (car p) (cadr p)
                            (dn-def (cdr (assoc 41 ad)) 1.0)
                            (dn-def (cdr (assoc 42 ad)) 1.0)
                            (dn-def (cdr (assoc 50 ad)) 0.0)))
           (setq res (append (dn-walk-block nm nins chain (1+ depth)) res))
          )
        )
        (setq a (entnext a))
      )
    )
  )
  res
)

(defun dn-in-regions (x y regions tol / r hit)
  (setq hit nil)
  (foreach r regions
    (if (and r (>= x (- (car (car r)) tol)) (<= x (+ (car (cadr r)) tol))
               (>= y (- (cadr (car r)) tol)) (<= y (+ (cadr (cadr r)) tol)))
      (setq hit T))
  )
  hit
)

;; 모형공간의 TEXT / MTEXT / 블록 속성(ATTRIB)을 (문자열 x y) 리스트로 수집
(defun dn-collect-texts (regions / res ss i e ed s p a pr ip)
  (setq res nil)
  (setq ss (ssget "X" (list (cons 0 "TEXT,MTEXT"))))
  (if ss
    (progn
      (setq i 0)
      (while (setq e (ssname ss i))
        (setq ed (entget e))
        (if (/= (cdr (assoc 67 ed)) 1)
          (progn
            (if (= (cdr (assoc 0 ed)) "MTEXT")
              (progn
                (setq s "")
                (foreach pr ed
                  (if (member (car pr) '(3 1)) (setq s (strcat s (cdr pr))))
                )
              )
              (setq s (cdr (assoc 1 ed)))
            )
            (setq p (dn-text-pos ed))
            (if (and s p) (setq res (cons (list s (car p) (cadr p)) res)))
          )
        )
        (setq i (1+ i))
      )
    )
  )
  (setq ss (ssget "X" (list (cons 0 "INSERT"))))
  (if ss
    (progn
      (setq i 0)
      (while (setq e (ssname ss i))
        (setq ed (entget e))
        ;; 도곽 영역 안에 삽입된 블록은 블록 정의 속 글자(중첩 포함)도 수집
        (if (/= (cdr (assoc 67 ed)) 1)
          (progn
            (setq ip (cdr (assoc 10 ed)))
            (if (dn-in-regions (car ip) (cadr ip) regions 2.0)
              (setq res (append
                          (dn-walk-block (cdr (assoc 2 ed))
                                         (list (car ip) (cadr ip)
                                               (dn-def (cdr (assoc 41 ed)) 1.0)
                                               (dn-def (cdr (assoc 42 ed)) 1.0)
                                               (dn-def (cdr (assoc 50 ed)) 0.0))
                                         nil 0)
                          res))
            )
          )
        )
        (if (and (/= (cdr (assoc 67 ed)) 1) (= (cdr (assoc 66 ed)) 1))
          (progn
            (setq a (entnext e))
            (while (and a (/= (cdr (assoc 0 (entget a))) "SEQEND"))
              (setq ed (entget a))
              (if (= (cdr (assoc 0 ed)) "ATTRIB")
                (progn
                  (setq s (cdr (assoc 1 ed)))
                  (setq p (dn-text-pos ed))
                  (if (and s p) (setq res (cons (list s (car p) (cadr p)) res)))
                )
              )
              (setq a (entnext a))
            )
          )
        )
        (setq i (1+ i))
      )
    )
  )
  res
)

;; 엔티티 경계상자 -> (minlst maxlst), 실패하면 nil
(defun get-ent-bbox (ent / vla-obj minpt maxpt)
  (setq vla-obj (vlax-ename->vla-object ent))
  (if (not (vl-catch-all-error-p
             (vl-catch-all-apply 'vla-getboundingbox (list vla-obj 'minpt 'maxpt))))
    (list (vlax-safearray->list minpt) (vlax-safearray->list maxpt))
    nil
  )
)

;; 숫자만 있는 글자("000", "001")를 도면번호로 인식 -> ("" 숫자 원문), 아니면 nil
(defun dn-plain-num (str / ns i ok)
  (setq ns (dn-nospace str) ok T)
  (if (and (>= (strlen ns) 1) (<= (strlen ns) 4))
    (progn
      (setq i 1)
      (while (and ok (<= i (strlen ns)))
        (if (not (dn-digit-p (ascii (substr ns i 1)))) (setq ok nil))
        (setq i (1+ i))
      )
      (if ok (list "" (atoi ns) ns) nil)
    )
    nil
  )
)

;; 도곽별 정보 -> (kind 숫자 원문 평면도/종단면도유무) 의 리스트 (도곽 순서와 동일)
;;  1순위: 도곽 우측 하단(표제란)에 있는 도면번호 (숫자만 "000" 또는 LP/MP-숫자)
;;  2순위: 도곽 안 어디서든 찾은 LP/MP-숫자 (우측 하단에 가까운 것)
(defun dn-analyze (frames texts kws / infos fr x0 y0 x1 y1 fw fh tx sx sy r pn d
                                       best bestd brbest brd has keys)
  (setq infos nil)
  (foreach fr frames
    (setq best nil bestd nil brbest nil brd nil has nil keys nil)
    (if fr
      (progn
        (setq x0 (car (car fr)) y0 (cadr (car fr))
              x1 (car (cadr fr)) y1 (cadr (cadr fr)))
        (setq fw (- x1 x0) fh (- y1 y0))
        (foreach tx texts
          (setq sx (cadr tx) sy (caddr tx))
          (if (and (>= sx x0) (<= sx x1) (>= sy y0) (<= sy y1))
            (progn
              (if (dn-has-keyword (car tx) kws) (setq has T))
              (setq r (dn-parse (car tx)))
              (setq d (sqrt (+ (* (- sx x1) (- sx x1)) (* (- sy y0) (- sy y0)))))
              ;; 우측 하단 영역(가로 12%, 세로 10%) 안의 번호 -> 1순위
              (if (and (>= sx (- x1 (* 0.12 fw))) (<= sy (+ y0 (* 0.10 fh))))
                (progn
                  (setq pn (dn-def r (dn-plain-num (car tx))))
                  (if (and pn (or (not brd) (< d brd)))
                    (setq brd d brbest pn))
                )
              )
              ;; 2순위용: 도곽 안의 LP/MP 번호
              (if r
                (progn
                  (if (not (member (list (car r) (cadr r)) keys))
                    (setq keys (cons (list (car r) (cadr r)) keys)))
                  (if (or (not bestd) (< d bestd))
                    (setq bestd d best r))
                )
              )
            )
          )
        )
        (if brbest
          (setq best brbest)
          (if (> (length keys) 1)
            (princ (strcat "\n  [주의] 한 도곽에 서로 다른 도면번호가 " (itoa (length keys))
                           "개 있음 -> 우측 하단에 가까운 " (caddr best) " 사용"))
          )
        )
      )
    )
    (setq infos (append infos
                  (list (if best (list (car best) (cadr best) (caddr best) has)
                                 (list nil nil nil has)))))
  )
  infos
)

(defun dn-set-nth (n val lst / i)
  (setq i -1)
  (mapcar '(lambda (x) (setq i (1+ i)) (if (= i n) val x)) lst)
)

(defun dn-pad3 (n / str)
  (setq str (itoa n))
  (while (< (strlen str) 3) (setq str (strcat "0" str)))
  str
)

(defun dn-letter (k)
  (if (< k 26)
    (chr (+ 65 k))
    (strcat (chr (+ 64 (/ k 26))) (chr (+ 65 (rem k 26))))
  )
)

;; 같은 번호끼리 묶어 "LP001_A/B/.." 라벨 리스트 생성 (번호 없는 도곽은 nil)
(defun dn-build-labels (infos / n labels keys kinds inf key idxs main rest i k lbl prefix)
  (setq n (length infos))
  (setq labels nil)
  (repeat n (setq labels (cons nil labels)))
  (setq keys nil kinds nil)
  (foreach inf infos
    (if (cadr inf)
      (progn
        (if (not (member (list (car inf) (cadr inf)) keys))
          (setq keys (append keys (list (list (car inf) (cadr inf))))))
        (if (not (member (car inf) kinds))
          (setq kinds (cons (car inf) kinds)))
      )
    )
  )
  (foreach key keys
    (setq idxs nil i 0)
    (foreach inf infos
      (if (and (cadr inf) (= (car inf) (car key)) (= (cadr inf) (cadr key)))
        (setq idxs (append idxs (list i))))
      (setq i (1+ i))
    )
    (setq main nil rest nil)
    (foreach i idxs
      (if (nth 3 (nth i infos))
        (setq main (append main (list i)))
        (setq rest (append rest (list i)))
      )
    )
    (cond
      ((not main)
       (princ (strcat "\n  [확인 필요] " (car key) "-" (itoa (cadr key))
                      "번에 평면도/종단면도가 있는 도곽이 없음 -> 읽기 순서대로 A부터 부여")))
      ((> (length main) 1)
       (princ (strcat "\n  [확인 필요] " (car key) "-" (itoa (cadr key))
                      "번에 평면도/종단면도가 있는 도곽이 " (itoa (length main))
                      "장 있음 -> 읽기 순서대로 A, B.. 부여")))
    )
    (setq k 0)
    (foreach i (append main rest)
      (setq lbl
        (if (and (= (car key) "") (= (length idxs) 1))
          (dn-pad3 (cadr key))                                   ;; 숫자만 있는 도면번호, 한 장뿐이면 "000"
          (strcat (car key) (dn-pad3 (cadr key)) "_" (dn-letter k))))
      (setq labels (dn-set-nth i lbl labels))
      (setq k (1+ k))
    )
  )
  labels
)

;; 같은 위치(경계상자 중심이 tol 이내)에 겹쳐 있는 도곽은 하나만 남김
(defun dn-center (ent / bb ip)
  (setq bb (get-ent-bbox ent))
  (if bb
    (list (/ (+ (car (car bb)) (car (cadr bb))) 2.0)
          (/ (+ (cadr (car bb)) (cadr (cadr bb))) 2.0))
    (progn (setq ip (get-ins-pt ent)) (list (car ip) (cadr ip)))
  )
)

(defun dn-dedupe (lst tol / kept centers pk dup c)
  (setq kept nil centers nil)
  (foreach e lst
    (setq pk (dn-center e) dup nil)
    (foreach c centers
      (if (and (not dup)
               (< (abs (- (car pk) (car c))) tol)
               (< (abs (- (cadr pk) (cadr c))) tol))
        (setq dup T))
    )
    (if (not dup)
      (progn (setq kept (append kept (list e))) (setq centers (append centers (list pk))))
    )
  )
  kept
)

;; 좌측 상단 기준 읽기 순서 정렬: 위->아래(윗변 높이), 같은 행이면 왼->오른쪽
(defun sort-by-topleft (lst / pairs bb ip)
  (setq pairs nil)
  (foreach e lst
    (setq bb (get-ent-bbox e))
    (if bb
      (setq pairs (cons (list e (car (car bb)) (cadr (cadr bb))) pairs))
      (progn (setq ip (get-ins-pt e))
             (setq pairs (cons (list e (car ip) (cadr ip)) pairs)))
    )
  )
  (setq pairs
    (vl-sort pairs
      (function
        (lambda (a b)
          (cond
            ((> (caddr a) (+ (caddr b) 1.0)) T)
            ((< (caddr a) (- (caddr b) 1.0)) nil)
            (T (< (cadr a) (cadr b)))
          )
        )
      )
    )
  )
  (mapcar 'car pairs)
)

;; ----------------------------------------------------------------------
;; 플롯 스타일(ctb)이 이 PC 의 플롯 스타일 폴더에 없으면, 런처와 함께 받은
;; lsp\평면도A3.ctb 를 플롯 스타일 폴더로 복사해서 쓴다. 이미 있으면 그대로 둔다.
;; ----------------------------------------------------------------------
(defun bpdf:split (s d / i r)
  (while (setq i (vl-string-search d s))
    (setq r (cons (substr s 1 i) r) s (substr s (+ i 2))))
  (reverse (cons s r)))

(defun bpdf:ensure-ctb (name / dirs found src dst root)
  ;; 1) 플롯 스타일 검색 경로 (옵션 > 파일 > 플롯 스타일 테이블 검색 경로)
  (if (getenv "PrinterStyleSheetDir")
    (foreach d (bpdf:split (getenv "PrinterStyleSheetDir") ";")
      (setq d (vl-string-right-trim "\\ " (vl-string-trim " " d)))
      (if (/= d "") (setq dirs (cons d dirs)))))
  (setq dirs (reverse dirs))
  (if (null dirs)
    (if (setq root (getvar "ROAMABLEROOTPREFIX"))
      (setq dirs (list (strcat (vl-string-right-trim "\\" root) "\\Plotters\\Plot Styles")))))
  (foreach d dirs
    (if (and (not found) (findfile (strcat d "\\" name))) (setq found T)))
  (cond
    (found T)
    ((null dirs)
     (princ (strcat "\n[주의] 플롯 스타일 폴더를 찾지 못했습니다. '" name "' 를 직접 복사해 주세요.")) nil)
    (T
     ;; 2) 런처와 함께 받은 파일 (런처폴더\lsp\) 또는 지원 경로
     (setq src (or (if (and (boundp '*CADLAUNCHER-EXE*) *CADLAUNCHER-EXE*)
                     (findfile (strcat (vl-filename-directory *CADLAUNCHER-EXE*) "\\lsp\\" name)))
                   (findfile name)))
     (setq dst (strcat (car dirs) "\\" name))
     (cond
       ((null src)
        (princ (strcat "\n[주의] '" name "' 가 플롯 스타일 폴더에 없고, 런처 lsp 폴더에서도 찾지 못했습니다.")) nil)
       ((vl-file-copy src dst)
        (princ (strcat "\n플롯 스타일 '" name "' 가 없어 런처의 파일을 복사했습니다: " dst)) T)
       (T
        (princ (strcat "\n[주의] '" name "' 복사 실패: " dst)) nil)))))

(defun run-bpdf (mode / *error* old-cmdecho old-filedia old-bgplot old-ucs
                   dwg-path dwg-name out-dir
                   plotter-name paper-size paper-units orientation
                   plot-scale ctb-name
                   form-block-name name-attrib-tag window-margin
                   rect-layer rect-target-w rect-target-h rect-wh-tol
                   rect-target-perim rect-perim-tol selection-mode
                   ss ent-list idx e ent vla-obj
                   minpt maxpt minlst maxlst pt1-str pt2-str
                   fname-base pdf-file counter
                   auto-number plan-keywords frames texts infos labels alt-dir open-folder name-max-chars fw fh cur-scale fit-nonstd std-size-tol rect-list cover-name rect-ratio-tol rect-min-w )

  (defun *error* (msg)
    (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
    (if old-filedia (setvar "FILEDIA" old-filedia))
    (if old-bgplot  (setvar "BACKGROUNDPLOT" old-bgplot))
    (if old-ucs (command-s "_.UCS" "_World"))
    (if (and msg (/= msg "Function cancelled"))
      (princ (strcat "\n오류 발생: " msg))
    )
    (princ)
  )

  ;; 시스템 변수 저장 및 설정
  (setq old-cmdecho (getvar "CMDECHO"))
  (setq old-filedia (getvar "FILEDIA"))
  (setq old-bgplot  (getvar "BACKGROUNDPLOT"))
  (setvar "CMDECHO" 0)          ;; 명령 echo 끄기
  (setvar "FILEDIA" 0)          ;; 파일 대화상자 끄기 (명령행으로 처리)
  (setvar "BACKGROUNDPLOT" 0)   ;; 백그라운드 플롯 끄기 (순차적으로 완료될 때까지 대기)

  ;; 좌표 기준을 통일하기 위해 World UCS로 전환
  (setq old-ucs T)
  (command "_.UCS" "_World")

  (setq dwg-path (getvar "DWGPREFIX"))
  (setq dwg-name (vl-filename-base (getvar "DWGNAME")))
  ;; 도면 파일명이 길면 앞 N글자만 PDF 파일명에 사용 (0 이하이면 전체 사용)
  (setq name-max-chars 10)
  (if (> name-max-chars 0)
    (setq dwg-name (dn-trunc dwg-name name-max-chars)))

  ;; ----------------------------------------------------------------
  ;; ▼▼▼ 출력 폴더: 원본 DWG 파일이 있는 폴더 그대로 사용 ▼▼▼
  (setq out-dir dwg-path)
  (if (/= (substr out-dir (strlen out-dir) 1) "\\")
    (setq out-dir (strcat out-dir "\\"))
  )
  ;; ----------------------------------------------------------------

  ;; ▼▼▼ 플롯 고정 옵션 ▼▼▼
  (setq plotter-name "DWG To PDF.pc3")
  (setq paper-size    "ISO 확장 A3 (420.00 x 297.00 MM)")
  (setq paper-units   "M")
  (setq orientation   "L")
  (setq plot-scale    "1=1")
  (setq ctb-name      "평면도A3.ctb")   ;; 이 파일이 플롯 스타일 검색 경로에 있어야 함
  (bpdf:ensure-ctb ctb-name)          ;; 없으면 런처의 lsp\평면도A3.ctb 를 플롯 스타일 폴더로 복사

  ;; ▼▼▼ FORM 블록 관련 설정 ▼▼▼
  (setq form-block-name "FORM,576353141081")   ;; 도곽 블록 이름 (쉼표로 여러 개 지정 가능)
  (setq name-attrib-tag nil)      ;; 파일명에 쓸 속성 태그명. 없으면 nil (순서번호 사용)
  ;; 예) 블록 속성 중 태그가 "도면번호" 라면:
  ;; (setq name-attrib-tag "도면번호")
  (setq window-margin 0.0)        ;; 잘라낼 영역 여유(도면단위). 경계선이 잘리면 값을 늘리세요.

  ;; ▼▼▼ 도면번호 자동 넘버링 ▼▼▼
  ;; T 이면 도곽 안의 도면번호(LP/MP-숫자)를 읽어 "LP001_A/B.." 로 파일명 부여, nil 이면 Sheet01.. 순번
  (setq auto-number T)
  ;; 맨 앞 도곽(표지)에 도면번호가 없을 때 쓸 파일명. 기호로 시작해서 탐색기에서 숫자보다 앞에 정렬됨. nil 이면 Sheet01
  (setq cover-name "_표지")
  ;; T 이면 출력이 모두 끝난 뒤 저장 폴더를 탐색기로 열기, nil 이면 열지 않음
  (setq open-folder T)

  ;; 도곽 크기가 일정하지 않은 경우: T 이면 표준 크기(아래 rect-target-w/h)가 아닌 도곽을
  ;; A3 용지에 꽉 차게(Fit) 출력, nil 이면 모두 1:1
  (setq fit-nonstd T)
  (setq std-size-tol 3.0)   ;; 표준 크기로 인정할 가로/세로 오차(mm)
  ;; 이 글자가 도곽 안에 있으면 A도면(본도면), 없으면 B, C.. 로 구분 (공백 없이 입력)
  (setq plan-keywords '("평면도" "종단면도"))

  ;; ▼▼▼ 자동감지 방식 설정 (BPDF 자동감지 모드에서만 사용됨) ▼▼▼
  ;; 도곽 블록과 함께, 아래 레이어에서 치수가 일치하는 폴리선(사각형)도 도곽으로 찾음
  ;; (표지처럼 블록이 아닌 폴리선 도곽 대응. 블록과 같은 위치면 중복 제거)
  (setq rect-layer        "FORM_,FROM,BOX")   ;; 도곽 폴리선을 찾을 레이어 이름 (쉼표로 여러 개)
  (setq rect-target-w     396.9333)  ;; 기준 도곽 가로 (가로세로 비율 계산용, 1:1 판별용)
  (setq rect-target-h     273.9767)  ;; 기준 도곽 세로
  (setq rect-ratio-tol    0.01)      ;; 가로세로 비율 허용오차 (크기가 달라도 같은 비율이면 도곽으로 인정)
  (setq rect-min-w        40.0)      ;; 짧은 변 최소 길이(mm). 이보다 작은 사각형은 도곽으로 보지 않음
  ;; ----------------------------------------------------------------

  ;; 선택 방식: 호출한 명령어(BPDF=자동 / BPDF_S=수동)에 따라 결정됨
  (setq selection-mode mode)

  (setq ent-list nil)

  (cond
    ;; ---------------- 직접 선택 모드: 선택한 순서 그대로 번호 매김 ----------------
    ((= selection-mode "MANUAL")
     (setq ent-list (manual-pick-list))
    )

    ;; ---------------- 자동감지 모드 ----------------
    (T
     ;; 1) FORM 블록 우선 검색
     (setq ss (ssget "X" (list (cons 0 "INSERT") (cons 2 form-block-name))))
     (if ss
       (progn
         (setq idx 0)
         (while (setq e (ssname ss idx))
           (if (/= (cdr (assoc 67 (entget e))) 1)   ;; 배치공간 제외
             (setq ent-list (cons e ent-list))
           )
           (setq idx (1+ idx))
         )
       )
     )

     ;; 2) 폴리선 도곽(예: 표지) - 지정 레이어에서 치수가 일치하는 폴리선도 함께 찾음
     (setq rect-list
       (find-form-rects rect-layer rect-target-w rect-target-h
                         rect-ratio-tol rect-min-w))
     (if rect-list
       (princ (strcat "\n폴리선 도곽 " (itoa (length rect-list)) "개 발견 (레이어: " rect-layer ")")))
     (setq ent-list (append ent-list rect-list))

     ;; 좌측 상단부터 위->아래, 왼->오른쪽 순으로 정렬
     (if ent-list (setq ent-list (sort-by-topleft ent-list)))
     ;; 같은 위치에 겹친 중복 도곽 제거 (경계상자 중심 2mm 이내)
     (if ent-list
       (progn
         (setq idx (length ent-list))
         (setq ent-list (dn-dedupe ent-list 2.0))
         (if (< (length ent-list) idx)
           (princ (strcat "\n같은 위치에 겹친 도곽 " (itoa (- idx (length ent-list)))
                          "개는 중복으로 보고 제외했습니다.")))
       )
     )
    )
  )

  (if (not ent-list)
    (princ "\n출력할 대상(FORM 블록/선택한 객체/사각형)을 찾을 수 없습니다.")
    (progn

      (princ (strcat "\n총 " (itoa (length ent-list)) "개 대상을 PDF로 출력합니다"
                     (if (= selection-mode "MANUAL") " (선택한 순서대로)" "")
                     "...\n"))

      ;; 도곽 안의 도면번호/내용을 읽어 번호 매기기
      (setq labels nil)
      (if auto-number
        (progn
          (princ "\n도곽 안의 도면번호/내용(평면도·종단면도)을 확인합니다...")
          (setq frames (dn-stage "1.경계상자" '(lambda () (mapcar 'get-ent-bbox ent-list))))
          (setq texts  (dn-stage "2.글자수집" '(lambda () (dn-collect-texts frames))))
          (setq infos  (dn-stage "3.번호분석" '(lambda () (dn-analyze frames texts plan-keywords))))
          (setq labels (dn-stage "4.이름생성" '(lambda () (dn-build-labels infos))))
          ;; 표지: 맨 앞(좌측 상단) 도곽에 도면번호가 없으면 cover-name 으로 저장 (탐색기에서 000보다 위에 정렬)
          (if (and labels cover-name (not (nth 0 labels)))
            (setq labels (dn-set-nth 0 cover-name labels)))
          (if (and labels infos)
            (progn
              (setq counter 0)
              (foreach ent ent-list
                (setq counter (1+ counter))
                (princ (strcat "\n  " (itoa counter) "번째 도곽: "
                               (if (nth (1- counter) labels)
                                 (strcat (if (caddr (nth (1- counter) infos))
                                           (caddr (nth (1- counter) infos))
                                           "번호 없음")
                                         " -> " (nth (1- counter) labels))
                                 (strcat "도면번호 못 찾음 -> Sheet" (pad2 counter)))))
              )
            )
            (princ "\n  자동 넘버링 실패 -> Sheet01.. 순번으로 저장합니다.")
          )
        )
      )

      (setq counter 0)
      (foreach ent ent-list
        (setq counter (1+ counter))
        (setq vla-obj (vlax-ename->vla-object ent))

        ;; 경계상자 계산 (실패 시 해당 블록은 건너뜀)
        (if (not (vl-catch-all-error-p
                   (vl-catch-all-apply 'vla-getboundingbox (list vla-obj 'minpt 'maxpt))
                 ))
          (progn
            (setq minlst (vlax-safearray->list minpt))
            (setq maxlst (vlax-safearray->list maxpt))

            ;; 도곽 크기가 표준(A3 도곽)과 같으면 1:1, 다르면 A3 용지에 맞춤(Fit)으로 출력
            (setq fw (- (car maxlst) (car minlst)))
            (setq fh (- (cadr maxlst) (cadr minlst)))
            (setq cur-scale
              (if (and fit-nonstd
                       ;; 표준 크기(오차 이내)이면서 인쇄 가능 영역(396.93 x 273.98)에 들어갈 때만 1:1,
                       ;; 조금이라도 크면 잘리지 않게 Fit
                       (not (and (< (abs (- fw rect-target-w)) std-size-tol)
                                 (< (abs (- fh rect-target-h)) std-size-tol)
                                 (<= fw (+ rect-target-w 0.05))
                                 (<= fh (+ rect-target-h 0.05)))))
                "F"
                plot-scale))
            (if (= cur-scale "F")
              (princ (strcat "\n  [참고] 도곽 크기 " (rtos fw 2 1) " x " (rtos fh 2 1)
                             " -> A3 용지에 맞춰 출력(Fit)")))

            (setq pt1-str (strcat (rtos (- (car minlst) window-margin) 2 4) ","
                                   (rtos (- (cadr minlst) window-margin) 2 4)))
            (setq pt2-str (strcat (rtos (+ (car maxlst) window-margin) 2 4) ","
                                   (rtos (+ (cadr maxlst) window-margin) 2 4)))

            ;; 파일명 결정: 속성값 우선, 없으면 순서번호
            (setq fname-base (if labels (nth (1- counter) labels) nil))
            (if (and (not fname-base) name-attrib-tag)
              (setq fname-base (get-attrib-value vla-obj name-attrib-tag))
            )
            (if (or (not fname-base) (= fname-base ""))
              (setq fname-base (strcat "Sheet" (pad2 counter)))
              (setq fname-base (sanitize-filename fname-base))
            )

            (setq pdf-file (strcat out-dir dwg-name "-" fname-base ".pdf"))
            ;; Windows 경로 길이 제한(약 260자) 대비: 너무 길면 파일명을 줄이고, 그래도 길면 대체 폴더 사용
            (if (> (strlen pdf-file) 240)
              (progn
                (setq pdf-file (strcat out-dir fname-base ".pdf"))
                (princ "\n  [참고] 경로가 너무 길어 파일명에서 원본 도면명을 뺐습니다.")
              )
            )
            (if (> (strlen pdf-file) 240)
              (progn
                (setq alt-dir (strcat (if (getenv "USERPROFILE") (getenv "USERPROFILE") "C:") "\\Documents\\BPDF_Output"))
                (if (not (vl-file-directory-p alt-dir)) (vl-mkdir alt-dir))
                (setq pdf-file (strcat alt-dir "\\" fname-base ".pdf"))
                (princ (strcat "\n  [참고] 폴더 경로가 너무 길어 대체 폴더에 저장: " alt-dir))
              )
            )
            (princ (strcat "\n[진행] " fname-base " -> " pdf-file))

            (vl-catch-all-apply
              '(lambda ()
                 (command
                   "_.-PLOT"
                   "Y"            ;; Detailed plot configuration? Yes
                   "Model"        ;; 항상 모형탭에서 출력
                   plotter-name
                   paper-size
                   paper-units
                   orientation
                   "N"            ;; Plot upside down? No
                   "Window"       ;; 플롯 영역: 지정한 경계상자만
                   pt1-str        ;; 첫 번째 코너
                   pt2-str        ;; 두 번째 코너
                   cur-scale      ;; 표준 도곽=1=1, 크기가 다른 도곽=F(Fit)
                   "Center"       ;; 오프셋: 용지 중앙에 배치
                   "Y"            ;; Plot with plot styles? Yes
                   ctb-name
                   "Y"            ;; Plot with lineweights? Yes
                   "A"            ;; Shade plot: As displayed
                   pdf-file       ;; (DWG To PDF.pc3는 파일전용 플로터라 write-to-file 질문 없이 바로 파일명)
                   "N"            ;; Save changes to page setup? No
                   "Y"            ;; Proceed with plot? Yes
                 )
               )
            )
            (if (= (type (vl-catch-all-apply 'findfile (list pdf-file))) 'STR)
              (princ "  [저장 완료]")
              (princ "\n  [출력 실패] PDF가 만들어지지 않음")
            )
          )
          (princ (strcat "\n[건너뜀] " (itoa counter) "번째 블록: 경계상자 계산 실패"))
        )
      )
      (princ "\n\n모든 대상 출력이 완료되었습니다.")
      ;; 저장이 끝나면 PDF가 저장된 폴더를 탐색기로 연다 (끄려면 open-folder 를 nil 로)
      (if (and open-folder pdf-file)
        (vl-catch-all-apply
          '(lambda ()
             (startapp "explorer.exe"
                       (strcat "\"" (vl-filename-directory pdf-file) "\""))
           )
        )
      )
    )
  )

  ;; 시스템 변수 및 UCS 복원
  (setvar "CMDECHO" old-cmdecho)
  (setvar "FILEDIA" old-filedia)
  (setvar "BACKGROUNDPLOT" old-bgplot)

  (princ)
)


;; 진단용: 도면번호 글자를 직접 클릭하면 객체 종류/문자열/인식결과를 보여줌 (블록 안 글자도 가능)
(defun c:BPDF_DN ( / sel ed typ s r)
  (setq sel (nentsel "\n도면번호 글자를 클릭하세요: "))
  (if sel
    (progn
      (setq ed (entget (car sel)))
      (setq typ (cdr (assoc 0 ed)))
      (princ (strcat "\n객체 종류: " typ "   레이어: " (cdr (assoc 8 ed))
                     (if (= (length sel) 4) "   (블록 안에 들어있는 글자)" "   (모형공간 직접 객체)")))
      (if (member typ '("TEXT" "MTEXT" "ATTRIB"))
        (progn
          (setq s (dn-ent-string ed))
          (princ (strcat "\n문자열: [" s "]"))
          (setq r (dn-def (dn-parse s) (dn-plain-num s)))
          (if r
            (princ (strcat "\n인식 결과: " (if (= (car r) "") "숫자만 있는 도면번호 " (car r)) (dn-pad3 (cadr r))
                         (if (= (car r) "") " (도곽 우측 하단에 있으면 이 번호 사용)" "_A/B.. 형태로 이름 부여")))
            (princ "\n인식 결과: 도면번호로 인식 못함 (LP/MP-숫자 형식이 아님)")
          )
        )
        (princ "\nTEXT/MTEXT/ATTRIB 가 아닙니다 (글자가 아닌 도형/선일 수 있음)")
      )
    )
  )
  (princ)
)

;; ---- 실제 명령어 정의 ----
(defun c:BPDF   () (run-bpdf "AUTO"))    ;; 자동감지: FORM 블록/사각형을 자동으로 찾아 위치순으로 출력
(defun c:BPDF_S () (run-bpdf "MANUAL"))  ;; 수동선택: 화면에서 직접 선택한 순서대로 출력

(princ "\nBPDF.lsp 로드 완료. 명령어: BPDF(자동감지) / BPDF_S(직접선택) / BPDF_DN(도면번호 인식 진단)")
(princ)
