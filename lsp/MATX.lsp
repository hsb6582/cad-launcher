;;; @launcher
;;; 리습: MATX
;;; 분류: 자재 · 수량
;;; 설명: 도엽별 자재내역 표 일괄 추출 → 자재내역 엑셀 자동 작성
;;; 기능: 자재내역 엑셀 자동 작성 | MATX | 모든 도곽의 자재내역 표를 읽어 자재내역_결과.xlsx 생성
;;; 기능: 자재내역 표 위치 보정 | MATCAL | 프로젝트마다 처음 1회, 도곽 하나에서 표 위치 지정
;;; 기능: 도면번호 위치만 다시 보정 | MATCAL-DRWNO | 다른 보정값은 두고 도면번호 위치만 다시 지정
;;; 기능: 보정 위치 미리보기 | MATX-VERIFY | 보정한 좌표를 현재 도곽에 표시해 확인
;;; 설명서:
;;;   도면의 자재내역 표를 도곽별로 읽어 CSV로 모은 뒤, 전자제도도우미.exe 가 바로 자재내역 엑셀 양식을 채워 줍니다.
;;;   (외부 프로그램·파이썬 설치가 필요 없습니다 - 전자제도도우미.exe 안에 매핑 엔진이 들어 있습니다.)
;;;
;;;   [사용 전 확인]
;;;   • 도곽은 FORM 블록 또는 FORM_ 레이어 사각형이어야 합니다.
;;;   • 자재내역 표는 모든 도곽에서 같은 상대 위치에 있어야 합니다 (번호/품명/규격/단위/수량/비고, 최대 20행).
;;;
;;;   [순서]
;;;   1) 새 프로젝트면 '자재내역 표 위치 보정'(MATCAL)을 먼저 1회 실행합니다. 보정값은 도면 폴더의 matx-config.txt 에 저장됩니다.
;;;   2) '자재내역 엑셀 자동 작성'(MATX)을 실행합니다.
;;;   3) 결과는 도면 폴더 안 MATX 폴더에 저장됩니다: material_export.csv, excel_matched.csv → 자재내역_결과.xlsx (생성되면 자동으로 열립니다)
;;;   4) matx-review.csv 에 엑셀에 자동으로 못 넣은 자재(매핑 규칙 없음·규격 없음·도면번호 중복 등)가 정리됩니다. 이 목록은 꼭 직접 확인하세요.
;;;
;;;   ※ 엑셀이 자동으로 안 만들어지면 MATX 폴더의 auto_matx_log.txt 를 확인하세요. (전자제도 도우미가 옛 버전이면 전자제도 도우미 '업데이트 확인'을 먼저 눌러 주세요)
;;;   ※ 도면이 40개 기준 양식(MP-001~011, LP-001~029)보다 많아 새 도면번호가 생기면, 그 열만 자동 반영에서 빠집니다 - excel_matched.csv 를 열어 해당 칸만 수동으로 옮겨 붙이세요.
;;; 기능설명서: MATX
;;;   모든 도곽을 좌측 상단부터 차례로 돌며 자재내역 표를 읽어 CSV 로 모읍니다.
;;;   끝나면 전자제도도우미.exe 가 자재내역 양식을 채운 '자재내역_결과.xlsx' 를 만들고 자동으로 엽니다.
;;;   • 매핑 규칙: MP/LP 구분, 규격이 A 호칭(예: 300A)이면 강관 규칙, LP 63mm → PE 전자류, S.TEE 부속 자동 계산(개수만큼 곱함), 관 수량은 엑셀 수식으로 기록
;;;   • MP 도면의 S.TEE 가 2개 이상이면 스토팍/PVC TAPE 칸에 '확인 필요' 메모를 붙입니다
;;;   • 도곽은 FORM_ 레이어 사각형 중 표가 들어갈 만한 크기인 것만 씁니다 (표 칸막이선 등은 자동 제외)
;;;   • 결과 위치: 도면 폴더\MATX\
;;; 기능설명서: MATCAL
;;;   도곽 하나를 골라 자재내역 표의 위치(번호·품명·규격·수량 칸 등)를 지정합니다.
;;;   프로젝트마다 처음 한 번만 하면 되고, 값은 도면 폴더의 matx-config.txt 에 저장됩니다.
;;;   보정을 하지 않으면 리습에 들어 있는 기본값을 씁니다.
;;; 기능설명서: MATCAL-DRWNO
;;;   다른 보정값은 그대로 두고, 도면번호를 읽는 위치만 다시 지정합니다.
;;; 기능설명서: MATX-VERIFY
;;;   보정한 좌표를 현재 도곽에 표시해서 표 위치가 맞는지 눈으로 확인합니다. 도면은 바꾸지 않습니다.
;;; @end
;;; ============================================================
;;; MATX.lsp  -  도엽별 자재내역 표 일괄 추출
;;; AutoCAD LT 2026 / CADian 호환 (ActiveX 미사용, entget/ssget 기반)
;;;
;;; 명령어:
;;;   MATCAL  - 캘리브레이션(도곽 1개에서 표 위치를 1회 지정)
;;;   MATX    - 전체 도곽 순회하며 자재내역 CSV로 추출
;;;   MATX-VERIFY - 캘리브레이션 좌표를 현재 도곽에 미리보기(마커 표시)
;;;
;;; 전제:
;;;   - 도곽은 FORM 블록(INSERT) 또는 FORM_ 레이어 직사각형
;;;   - 자재내역 표는 도곽 내부의 "단순 위치"에 있음(블록 아님)
;;;   - 표는 모든 도곽에서 도곽 기준점 대비 동일한 상대좌표를 가짐
;;;   - 표 구성: 번호/품명/규격/단위/수량/비고, 최대 20행, 아래에서 위로 1,2,3...
;;;   - 수량 칸은 프로젝트별로 레이어명이 다를 수 있음(고정 안 함)
;;;
;;; 설정 파일: 도면과 같은 폴더에 matx-config.txt 로 저장/로드
;;; 결과 파일: 도면 폴더\MATX\ 에 material_export.csv / excel_matched.csv / matx-review.csv (매번 새로 씀)
;;; 로그 파일: matx-log.txt
;;; ============================================================

(vl-load-com) ; entget 기반이라 필수는 아니지만 안전하게 로드

;; ---------- 전역 ----------
;; 기본 내장 캘리브레이션 (MATCAL 결과 기본값)
;; - matx-config.txt 파일이 있으면 그 값이 이걸 덮어씀 (다른 프로젝트에서 MATCAL 재실행 시 자동 반영)
;; - 파일이 없으면 이 기본값으로 바로 MATX 실행 가능 (MATCAL 생략 가능)
(setq *matx-config*
  (list
    (cons 'ROW1DY 52.742)
    (cons 'ROW1DX 332.766)
    (cons 'ROWPITCH 3.93097)
    (cons 'MAXROWS 20)
    (cons 'COLDX (list 332.766 343.514 358.767 370.402 379.473 390.328))
    (cons 'DRWNODX 375.997)
    (cons 'DRWNODY 23.2123)
  )
)

;; MATX 실행 중 도면별 엑셀 매칭 결과를 누적하는 전역 변수.
;; ((도면번호 . ((엑셀행 . 값또는수식문자열) ...)) ...) 형태.
(setq *matx-excel-matrix* nil)

(defun matx-log (msg / f path)
  (setq path (strcat (matx-output-dir) "matx-log.txt"))
  (setq f (open path "a"))
  (if f
    (progn
      (write-line (strcat (rtos (getvar "CDATE") 2 6) "  " msg) f)
      (close f)
    )
    (princ (strcat "\n[MATX] 로그 파일을 열 수 없어 기록을 건너뜁니다: " path))
  )
)

(defun matx-dwg-dir ()
  (vl-filename-directory (getvar "DWGNAME")) ; 폴더 없으면 "" 반환될 수 있음
  (if (= (getvar "DWGPREFIX") "")
    ""
    (getvar "DWGPREFIX")
  )
)

(defun matx-output-dir (/ d)
  ;; 도면 폴더 바로 밑에 "MATX" 하위 폴더를 만들어서(없으면 생성) 그 경로를 반환.
  ;; material_export.csv/excel_matched.csv/로그/결과 엑셀 등 결과물은 전부 여기로 모음.
  (setq d (strcat (matx-dwg-dir) "MATX\\"))
  (if (not (vl-file-directory-p d))
    (vl-mkdir d)
  )
  d
)

(defun matx-quote-arg (path / p)
  ;; startapp에 인자로 넘길 때 경로 안의 공백 때문에 여러 인자로 쪼개지는 걸 막기 위해
  ;; 큰따옴표로 감싸서 반환. (끝의 백슬래시가 닫는 따옴표를 이스케이프하는 걸 피하려고
  ;; 마지막 백슬래시는 미리 제거)
  (setq p path)
  (if (and (> (strlen p) 0) (= (substr p (strlen p) 1) "\\"))
    (setq p (substr p 1 (1- (strlen p))))
  )
  (strcat "\"" p "\"")
)

;; ---------- 안전한 파일 열기: 재시도(동기화 지연 대응) + 실패시 TEMP 폴백(잠금 대응) ----------
(defun matx-temp-dir (/ d)
  (setq d (getenv "TEMP"))
  (if (and d (/= d ""))
    (if (= (substr d (strlen d) 1) "\\")
      d
      (strcat d "\\")
    )
    "C:\\Temp\\"
  )
)

(defun matx-basename (path)
  (strcat (vl-filename-base path) (vl-filename-extension path))
)

(defun matx-safe-open (path mode / f tries fallback-dir fallback-path)
  ;; 1) 원래 경로에서 최대 3회, 1초 간격으로 재시도 (OneDrive 동기화 등 일시적 잠금 대응)
  (setq tries 0)
  (setq f nil)
  (while (and (null f) (< tries 3))
    (setq f (open path mode))
    (if (null f)
      (progn
        (if (= tries 0)
          (princ (strcat "\n[MATX] 파일 열기 실패, 재시도 중: " path))
        )
        (princ (strcat " (" (itoa (1+ tries)) "/3)"))
        (command "_.DELAY" 1000)
        (setq tries (1+ tries))
      )
    )
  )
  (if f
    (cons f path)
    ;; 2) 재시도로도 안 열리면(주로 다른 프로그램의 잠금) TEMP\MATX\ 폴더로 대체 저장
    (progn
      (setq fallback-dir (strcat (matx-temp-dir) "MATX\\"))
      (if (not (vl-file-directory-p fallback-dir))
        (vl-mkdir fallback-dir)
      )
      (setq fallback-path (strcat fallback-dir (matx-basename path)))
      (princ (strcat "\n[MATX] 원래 위치에 저장 실패 - 대체 경로 사용: " fallback-path))
      (princ "\n  (원인: 다른 프로그램이 파일을 열어 잠갔거나, 폴더 쓰기 권한 문제일 수 있습니다)")
      (setq f (open fallback-path mode))
      (if f
        (cons f fallback-path)
        (progn
          (princ (strcat "\n[MATX] 대체 경로도 열기 실패: " fallback-path))
          nil
        )
      )
    )
  )
)

(defun matx-find-existing-config (/ primary fallback)
  ;; matx-config.txt를 원래 경로 -> TEMP 대체 경로 순으로 탐색
  (setq primary (strcat (matx-dwg-dir) "matx-config.txt"))
  (setq fallback (strcat (matx-temp-dir) "MATX\\matx-config.txt"))
  (cond
    ((findfile primary) primary)
    ((findfile fallback) fallback)
    (T nil)
  )
)
(defun matx-save-config (/ path result f actual-path)
  (setq path (strcat (matx-dwg-dir) "matx-config.txt"))
  (setq result (matx-safe-open path "w"))
  (if (null result)
    (progn
      (princ "\n[MATX] 오류: 설정 파일을 어느 경로에도 저장하지 못했습니다.")
      (princ "\n  - 다른 프로그램(메모장/엑셀 등)에서 파일을 닫고 다시 시도하세요.")
      (princ "\n  - 캘리브레이션 좌표 자체는 정상 수집되었으니, 문제 해결 후 MATCAL만 다시 실행하면 됩니다.")
    )
    (progn
      (setq f (car result))
      (setq actual-path (cdr result))
      (prin1 *matx-config* f)
      (close f)
      (matx-log "설정 저장 완료")
      (princ (strcat "\n[MATX] 설정 저장: " actual-path))
    )
  )
)

(defun matx-load-config (/ f path s)
  (setq path (matx-find-existing-config))
  (if path
    (progn
      (setq f (open path "r"))
      (setq s (read-line f))
      (close f)
      (setq *matx-config* (read s))
      (princ (strcat "\n[MATX] 설정 로드: " path))
      T
    )
    ;; 파일이 없으면 리습에 내장된 기본 캘리브레이션 값을 그대로 사용
    (if *matx-config*
      (progn
        (princ "\n[MATX] 설정 파일 없음 - 내장 기본 캘리브레이션 값 사용")
        T
      )
      nil
    )
  )
)

;; ---------- 유틸 ----------
(defun matx-getreal-prompt (prompt default)
  (getreal (strcat prompt " <" (rtos default 2 2) ">: "))
)

(defun matx-text-position (ed / j72 j73 pt11 pt10 etype)
  ;; 정렬(justify)이 기본(왼쪽 하단)이 아니면 실제 표시 위치는 그룹코드 10이 아니라
  ;; 11번(2차 정렬점)에 들어있음. LIST에서 "중간 점"/"우측 점" 등으로 표시되는 경우가 이에 해당.
  ;; (MTEXT는 그룹 72/11의 의미가 완전히 다르므로 - 72=부착점, 11=방향벡터 - 이 로직 제외)
  (setq etype (cdr (assoc 0 ed)))
  (setq pt10 (cdr (assoc 10 ed)))
  (if (= etype "MTEXT")
    pt10
    (progn
      (setq j72 (cdr (assoc 72 ed)))
      (setq j73 (cdr (assoc 73 ed)))
      (if (null j72) (setq j72 0))
      (if (null j73) (setq j73 0))
      (setq pt11 (cdr (assoc 11 ed)))
      (if (and pt11 (or (/= j72 0) (/= j73 0)))
        pt11
        pt10
      )
    )
  )
)

(defun matx-text-center (ed / p10 box rot mx my c s)
  ;; TEXT 의 실제 글자 상자 중심점. 왼쪽 정렬 문자는 삽입점이 글자 왼쪽 끝이라
  ;; 칸 중심과 멀리 떨어져 있으므로(예: 품명 칸), 정렬 방식과 상관없이 중심점으로 비교한다.
  ;; textbox 를 못 쓰면(MTEXT 등) 기존 정렬점 방식으로 대체.
  (setq p10 (cdr (assoc 10 ed)))
  (if (and (= (cdr (assoc 0 ed)) "TEXT")
           (or (vl-catch-all-error-p (setq box (vl-catch-all-apply 'textbox (list ed))))
               (null box)))
    ;; textbox 가 안 되면 글자 수 x 높이로 폭을 어림잡음 (그룹 10 = 글자 왼쪽 아래)
    (setq box (list (list 0.0 0.0)
                    (list (* (strlen (cdr (assoc 1 ed))) (cdr (assoc 40 ed)) 0.8
                             (if (assoc 41 ed) (cdr (assoc 41 ed)) 1.0))
                          (cdr (assoc 40 ed)))))
  )
  (if (and (= (cdr (assoc 0 ed)) "TEXT") box)
    (progn
      (setq mx (/ (+ (car (car box)) (car (cadr box))) 2.0))
      (setq my (/ (+ (cadr (car box)) (cadr (cadr box))) 2.0))
      (setq rot (cdr (assoc 50 ed)))
      (if (null rot) (setq rot 0.0))
      (setq c (cos rot) s (sin rot))
      (list (+ (car p10) (- (* mx c) (* my s)))
            (+ (cadr p10) (+ (* mx s) (* my c))))
    )
    (matx-text-position ed)
  )
)

(defun matx-replace-all (s old new / p)
  (setq p (vl-string-search old s))
  (while p
    (setq s (strcat (substr s 1 p) new (substr s (+ p 1 (strlen old)))))
    (setq p (vl-string-search old s (+ p (strlen new))))
  )
  s
)

(defun matx-strip-mtext (s / out i n c nx)
  ;; MTEXT 서식 코드(\P 줄바꿈, {\f글꼴;...}, \H, \C 등) 제거
  (setq out "" i 1 n (strlen s))
  (while (<= i n)
    (setq c (substr s i 1))
    (cond
      ((or (= c "{") (= c "}")) (setq i (1+ i)))
      ((= c "\\")
       (setq nx (substr s (1+ i) 1))
       (cond
         ((member (strcase nx) '("P" "~")) (setq out (strcat out " ") i (+ i 2)))
         ((member nx '("\\" "{" "}")) (setq out (strcat out nx) i (+ i 2)))
         ((member (strcase nx) '("F" "H" "C" "W" "A" "T" "Q" "S"))
          (setq i (+ i 2))
          (while (and (<= i n) (/= (substr s i 1) ";")) (setq i (1+ i)))
          (setq i (1+ i))
         )
         (T (setq i (+ i 2)))
       )
      )
      (T (setq out (strcat out c) i (1+ i)))
    )
  )
  out
)

(defun matx-text-string (ed / s)
  ;; 문자열 정리: MTEXT 서식 제거, %%D → °, %%P → ±, 앞뒤 공백 제거
  (setq s (cdr (assoc 1 ed)))
  (if (/= (type s) 'STR) (setq s ""))
  (if (= (cdr (assoc 0 ed)) "MTEXT")
    (setq s (matx-strip-mtext
              (strcat (apply 'strcat (mapcar 'cdr (vl-remove-if-not '(lambda (x) (= (car x) 3)) ed))) s)))
  )
  (foreach pr '(("%%D" . "°") ("%%d" . "°") ("%%P" . "±") ("%%p" . "±") ("%%%" . "%"))
    (setq s (matx-replace-all s (car pr) (cdr pr)))
  )
  (vl-string-trim " \t" s)
)

;; ---------- 텍스트 색인 ----------
;; 예전에는 칸마다 ssget "_C"(화면 창 선택)를 썼는데, 이 방식은 화면 확대 상태에 따라
;; 결과가 달라지고(전체 줌에서 1mm 칸은 1픽셀도 안 됨) 도곽이 많으면 매우 느리다.
;; 그래서 도면 전체 문자를 ssget "_X" 로 한 번만 모은 뒤 좌표로 직접 거른다.
(defun matx-collect-texts (/ ss i e p result)
  (setq result '())
  (setq ss (ssget "_X" '((0 . "TEXT,MTEXT") (410 . "Model"))))
  (if ss
    (progn
      (setq i 0)
      (while (< i (sslength ss))
        (setq e (ssname ss i))
        (setq p (cdr (assoc 10 (entget e))))
        (setq result (cons (list (car p) (cadr p) e) result))
        (setq i (1+ i))
      )
    )
  )
  result
)

(defun matx-frame-roi (origin cfg / xs ys pitch r1)
  ;; 도곽 하나에서 읽을 범위(표 + 도면번호 주변). 삽입점 기준으로 대충 거르는 용도라
  ;; 왼쪽(왼쪽 정렬 문자의 삽입점)과 도면번호 쪽으로 여유를 둔다.
  (setq pitch (cdr (assoc 'ROWPITCH cfg)) r1 (cdr (assoc 'ROW1DY cfg)))
  (setq xs (cdr (assoc 'COLDX cfg)))
  (if (assoc 'DRWNODX cfg) (setq xs (cons (cdr (assoc 'DRWNODX cfg)) xs)))
  (setq ys (list r1 (+ r1 (* (cdr (assoc 'MAXROWS cfg)) pitch)) (- r1 pitch)))
  (if (assoc 'DRWNODY cfg) (setq ys (cons (cdr (assoc 'DRWNODY cfg)) ys)))
  (list (+ (car origin) (apply 'min xs) -40.0)
        (+ (cadr origin) (apply 'min ys) -25.0)
        (+ (car origin) (apply 'max xs) 25.0)
        (+ (cadr origin) (apply 'max ys) 25.0))
)

(defun matx-texts-in-box (all x1 y1 x2 y2 / result ed c)
  ;; all = ((x y ename) ...). 범위 안 문자만 골라 ((중심x 중심y 문자열) ...) 로 반환
  (setq result '())
  (foreach t1 all
    (if (and (>= (car t1) x1) (<= (car t1) x2) (>= (cadr t1) y1) (<= (cadr t1) y2))
      (progn
        (setq ed (entget (caddr t1)))
        (setq c (matx-text-center ed))
        (setq result (cons (list (car c) (cadr c) (matx-text-string ed)) result))
      )
    )
  )
  result
)

(defun matx-round (x)
  (if (< x 0) (- (fix (+ (- x) 0.5))) (fix (+ x 0.5)))
)

(defun matx-col-halfwidth (coldx i / gl gr)
  ;; i번째 열이 차지하는 폭의 절반 (양옆 열 간격 중 큰 쪽의 절반)
  (setq gl (if (> i 0) (abs (- (nth i coldx) (nth (1- i) coldx))) 0.0))
  (setq gr (if (< i (1- (length coldx))) (abs (- (nth (1+ i) coldx) (nth i coldx))) 0.0))
  (/ (max gl gr) 2.0)
)

(defun matx-join-cell (items / out seen)
  ;; 한 칸에 문자가 여러 개면 왼쪽부터 이어붙임 (같은 문자가 겹쳐 있으면 하나만)
  (setq items (vl-sort items '(lambda (a b) (< (car a) (car b)))))
  (setq out "" seen '())
  (foreach it items
    (if (and (/= (cdr it) "") (not (member (cdr it) seen)))
      (progn
        (setq seen (cons (cdr it) seen))
        (setq out (if (= out "") (cdr it) (strcat out " " (cdr it))))
      )
    )
  )
  out
)

(defun matx-read-table (origin cfg texts / coldx pitch row1y maxrows cells dy ri dx k best bd d entry rows vals)
  ;; 도곽 하나의 자재내역 표를 읽어 ((번호 품명 규격 단위 수량 비고) ...) 로 반환 (1행부터, 빈 행 제외)
  ;; 각 문자의 중심점이 어느 행/열에 속하는지 계산해서 칸에 넣는다:
  ;;  - 행: 1행 중심에서 행간격의 몇 배 떨어졌는지 (행간격의 45% 이내만 인정)
  ;;  - 열: 보정된 열 위치 중 가장 가까운 열 (표 바깥으로 벗어난 문자는 제외)
  (setq coldx (cdr (assoc 'COLDX cfg)) pitch (cdr (assoc 'ROWPITCH cfg))
        maxrows (cdr (assoc 'MAXROWS cfg)) row1y (+ (cadr origin) (cdr (assoc 'ROW1DY cfg))))
  (setq cells '())
  (foreach tx texts
    (setq dy (- (cadr tx) row1y))
    (setq ri (matx-round (/ dy pitch)))
    (if (and (>= ri 0) (< ri maxrows)
             (<= (abs (- dy (* ri pitch))) (* 0.45 (abs pitch)))
             (/= (caddr tx) ""))
      (progn
        (setq dx (- (car tx) (car origin)))
        (setq k 0 best nil bd nil)
        (foreach c coldx
          (setq d (abs (- dx c)))
          (if (or (null bd) (< d bd)) (setq bd d best k))
          (setq k (1+ k))
        )
        (if (<= bd (matx-col-halfwidth coldx best))
          (progn
            (setq entry (assoc (cons ri best) cells))
            (if entry
              (setq cells (subst (cons (car entry) (cons (cons (car tx) (caddr tx)) (cdr entry))) entry cells))
              (setq cells (cons (cons (cons ri best) (list (cons (car tx) (caddr tx)))) cells))
            )
          )
        )
      )
    )
  )
  (setq rows '() ri 0)
  (while (< ri maxrows)
    (setq vals '() k 0)
    (foreach c coldx
      (setq entry (assoc (cons ri k) cells))
      (setq vals (cons (if entry (matx-join-cell (cdr entry)) "") vals))
      (setq k (1+ k))
    )
    (setq vals (reverse vals))
    ;; 번호만 있고 나머지가 빈 행은 버림
    (if (vl-some '(lambda (v) (/= v "")) (cdr vals))
      (setq rows (cons vals rows))
    )
    (setq ri (1+ ri))
  )
  (reverse rows)
)

;; ---------- 도곽 수집 (FORM 블록 우선, 없으면 FORM_ 레이어 폴리라인) ----------
(defun matx-frame-min-size (cfg / maxdx top)
  ;; 보정값(표 위치)으로 "도곽이라면 최소 이 정도 크기는 돼야 한다"를 계산.
  ;; FORM_ 레이어에는 도곽 테두리뿐 아니라 표 칸막이선·결재란 선 같은 작은 폴리라인도
  ;; 수천 개 들어 있어서(실제 도면: 2848개 중 도곽은 20개), 크기로 걸러야 함.
  (setq maxdx (apply 'max (mapcar 'abs (cdr (assoc 'COLDX cfg)))))
  (setq top (abs (+ (cdr (assoc 'ROW1DY cfg))
                    (* (1- (cdr (assoc 'MAXROWS cfg))) (cdr (assoc 'ROWPITCH cfg))))))
  (list (* 0.9 maxdx) (* 0.9 top))
)

(defun matx-bbox-inside-p (a b / tol)
  ;; a 박스(minx miny maxx maxy)가 b 박스 안에 들어있는지 (a와 b가 같은 크기면 nil)
  (setq tol 0.5)
  (and (>= (nth 0 a) (- (nth 0 b) tol))
       (>= (nth 1 a) (- (nth 1 b) tol))
       (<= (nth 2 a) (+ (nth 2 b) tol))
       (<= (nth 3 a) (+ (nth 3 b) tol))
       (< (* (- (nth 2 a) (nth 0 a)) (- (nth 3 a) (nth 1 a)))
          (* 0.9 (- (nth 2 b) (nth 0 b)) (- (nth 3 b) (nth 1 b))))
  )
)

(defun matx-collect-frames (cfg / ss i e ed frames pt box minsz cands total kept)
  (setq frames '())
  ;; 1) FORM 블록 INSERT 우선 (모형 공간만)
  (setq ss (ssget "_X" '((0 . "INSERT") (2 . "FORM") (410 . "Model"))))
  (if ss
    (progn
      (setq i 0)
      (while (< i (sslength ss))
        (setq e (ssname ss i))
        (setq ed (entget e))
        (setq pt (cdr (assoc 10 ed))) ; 삽입점 = 도곽 기준점(좌하단으로 가정)
        (setq frames (cons (list pt e) frames))
        (setq i (1+ i))
      )
    )
  )
  ;; 2) FORM 블록이 하나도 없으면 FORM_ 레이어의 폴리라인 중 '도곽 크기'인 것만 사용
  (if (null frames)
    (progn
      (setq minsz (matx-frame-min-size cfg))
      (setq cands '() total 0)
      (setq ss (ssget "_X" '((0 . "LWPOLYLINE") (8 . "FORM_") (410 . "Model"))))
      (if ss
        (progn
          (setq total (sslength ss))
          (setq i 0)
          (while (< i total)
            (setq e (ssname ss i))
            (setq box (matx-poly-bbox e))
            (if (and box
                     (>= (- (nth 2 box) (nth 0 box)) (car minsz))
                     (>= (- (nth 3 box) (nth 1 box)) (cadr minsz)))
              (setq cands (cons (list box e) cands))
            )
            (setq i (1+ i))
          )
        )
      )
      ;; 다른 도곽 후보 안에 들어있는 사각형(안쪽 테두리 등)은 제외
      (setq kept '())
      (foreach c cands
        (if (not (vl-some '(lambda (o) (and (not (eq o c)) (matx-bbox-inside-p (car c) (car o)))) cands))
          (setq kept (cons c kept))
        )
      )
      (foreach c kept
        (setq frames (cons (list (list (nth 0 (car c)) (nth 1 (car c)) 0.0) (cadr c)) frames))
      )
      (matx-log (strcat "FORM_ 폴리라인 " (itoa total) "개 중 도곽 크기("
                        (rtos (car minsz) 2 0) "x" (rtos (cadr minsz) 2 0) " 이상) "
                        (itoa (length kept)) "개를 도곽으로 사용"))
      (princ (strcat "\n[MATX] FORM_ 폴리라인 " (itoa total) "개 중 도곽 크기인 " (itoa (length kept)) "개를 도곽으로 사용합니다."))
    )
  )
  (matx-dedupe-frames frames)
)

(defun matx-poly-bbox (ent / ed pts)
  ;; LWPOLYLINE 정점들의 (minx miny maxx maxy). 정점이 4개 미만이면 nil (선분은 도곽이 아님)
  (setq ed (entget ent))
  (setq pts (mapcar 'cdr (vl-remove-if-not '(lambda (x) (= (car x) 10)) ed)))
  (if (>= (length pts) 4)
    (list (apply 'min (mapcar 'car pts)) (apply 'min (mapcar 'cadr pts))
          (apply 'max (mapcar 'car pts)) (apply 'max (mapcar 'cadr pts)))
    nil
  )
)

(defun matx-dedupe-frames (frames / result pt dup fr2)
  ;; 원점이 거의 같은(0.5mm 이내) 도곽은 하나만 남기고 나머지는 버림
  ;; (같은 자리에 FORM 블록이 실수로 중복 삽입된 경우 대응)
  (setq result '())
  (foreach fr frames
    (setq pt (car fr))
    (setq dup nil)
    (foreach fr2 result
      (if (and (not dup) (< (distance pt (car fr2)) 0.5))
        (setq dup T)
      )
    )
    (if (not dup)
      (setq result (cons fr result))
    )
  )
  (reverse result)
)

(defun matx-bbox-bl (ent / ed pts minx miny)
  ;; LWPOLYLINE의 정점들에서 좌하단(min x, min y) 좌표 계산 (ActiveX 미사용)
  (setq ed (entget ent))
  (setq pts (mapcar 'cdr (vl-remove-if-not '(lambda (x) (= (car x) 10)) ed)))
  (setq minx (apply 'min (mapcar 'car pts)))
  (setq miny (apply 'min (mapcar 'cadr pts)))
  (list minx miny 0.0)
)

;; ---------- 도곽 정렬: 행 우선(위->아래), 각 행 내 좌->우 ----------
(defun matx-sort-frames (frames / ytol groups pt g found)
  ;; ytol: 같은 행으로 간주할 Y 오차범위. 도곽 세로길이의 절반 정도로 넉넉히 잡음.
  (setq ytol 100.0) ; mm 단위 도면이면 필요시 조정
  (setq groups '()) ; ((y-rep . (frame frame ...)) ...)
  (foreach fr frames
    (setq pt (car fr))
    (setq found nil)
    (foreach grp groups
      (if (and (not found) (< (abs (- (cadr pt) (car grp))) ytol))
        (progn
          (setq g grp)
          (setq found T)
        )
      )
    )
    (if found
      (setq groups
        (subst (cons (car g) (cons fr (cdr g))) g groups)
      )
      (setq groups (cons (cons (cadr pt) (list fr)) groups))
    )
  )
  ;; Y 큰 것(위쪽)부터, 각 그룹 내에서는 X 오름차순
  (setq groups (vl-sort groups '(lambda (a b) (> (car a) (car b)))))
  (apply 'append
    (mapcar
      '(lambda (grp)
         (vl-sort (cdr grp) '(lambda (a b) (< (car (car a)) (car (car b)))))
       )
      groups
    )
  )
)

;; ---------- 도면번호 추출: 보정된 도면번호 위치 근처의 (MP|LP)-### 문자 ----------
(defun matx-find-drawing-no (origin cfg texts / pt best bd d m near)
  ;; 보정 위치에서 25 이내의 문자 중 패턴이 맞는 가장 가까운 것.
  ;; (예전에는 못 찾으면 150 반경까지 넓혀 찾았는데, 평면도 안의 '접속 도면' 표시
  ;;  (예: 당진-2026-LP-006) 를 잘못 집어서 엉뚱한 도면번호로 기록되는 문제가 있어 없앰)
  (if (not (and (assoc 'DRWNODX cfg) (assoc 'DRWNODY cfg)))
    nil
    (progn
      (setq pt (list (+ (car origin) (cdr (assoc 'DRWNODX cfg)))
                     (+ (cadr origin) (cdr (assoc 'DRWNODY cfg)))))
      (setq best nil bd nil near '())
      (foreach tx texts
        (setq d (distance pt (list (car tx) (cadr tx))))
        (if (< d 25.0)
          (progn
            (if (< d 8.0) (setq near (cons (caddr tx) near)))
            (setq m (matx-regex-mp-lp (caddr tx)))
            (if (and m (or (null bd) (< d bd))) (setq bd d best m))
          )
        )
      )
      (if (and (null best) near)
        (progn
          (princ "\n      [진단] 도면번호 예상 위치 근처 문자(패턴 불일치): ")
          (foreach ft near (princ (strcat "'" ft "' ")))
        )
      )
      best
    )
  )
)

(defun matx-regex-mp-lp (s / pos p2 sub)
  ;; 순수 AutoLISP 문자열 검색으로 "MP-000" 또는 "LP-000" 패턴 탐색 (정규식 미지원 환경 고려)
  (matx-scan-pattern s "MP-")
)

(defun matx-scan-pattern (s prefix / n plen i sub digits)
  (setq n (strlen s))
  (setq plen (strlen prefix))
  (setq i 1)
  (setq digits nil)
  (while (and (<= i (- n plen -1)) (null digits))
    (setq sub (substr s i plen))
    (if (= sub prefix)
      (progn
        (setq digits (matx-take-digits s (+ i plen)))
        (if digits
          (progn
            ;; "MP-1" 처럼 자리수가 모자라면 엑셀 양식과 같은 3자리로 맞춤 ("MP-001")
            (while (< (strlen digits) 3) (setq digits (strcat "0" digits)))
            (setq digits (strcat prefix digits))
          )
        )
      )
    )
    (setq i (1+ i))
  )
  (if digits
    digits
    (if (= prefix "MP-")
      (matx-scan-pattern s "LP-") ; MP 못 찾으면 LP도 시도
      nil
    )
  )
)

(defun matx-take-digits (s start / n i c out)
  (setq n (strlen s))
  (setq i start)
  (setq out "")
  (while (and (<= i n) (matx-is-digit (substr s i 1)))
    (setq out (strcat out (substr s i 1)))
    (setq i (1+ i))
  )
  (if (> (strlen out) 0) out nil)
)

(defun matx-is-digit (c)
  (and (>= (ascii c) 48) (<= (ascii c) 57))
)

(defun matx-pick-text-pos (prompt / sel ed)
  ;; 좌표를 클릭하는 게 아니라 텍스트 엔티티 자체를 선택해서 정확한 좌표를 코드로 읽어옴
  ;; (클릭 오차, UCS 문제를 원천적으로 없앰)
  (princ prompt)
  (setq sel (entsel))
  (if (null sel) (progn (princ "\n취소되었습니다.") (exit)))
  (setq ed (entget (car sel)))
  (if (not (member (cdr (assoc 0 ed)) '("TEXT" "MTEXT" "ATTRIB")))
    (progn (princ (strcat "\n[MATX] 선택한 것은 텍스트가 아닙니다: " (cdr (assoc 0 ed)))) (exit))
  )
  ;; 읽을 때와 같은 기준(글자 상자 중심)으로 저장
  (matx-text-center ed)
)

;; ============================================================
;; MATCAL-DRWNO - 도면번호 위치만 재캘리브레이션 (다른 설정은 그대로 유지)
;; ============================================================
(defun c:MATCAL-DRWNO (/ sel ent ed etype origin drwno-pt)
  (if (not (matx-load-config))
    (progn (princ "\n[MATX] 기존 캘리브레이션 정보가 없습니다. MATCAL을 먼저 실행하세요.") (exit))
  )
  (princ "\n[MATCAL-DRWNO] 도면번호 위치만 다시 지정합니다.")
  (princ "\n1) 도곽(FORM 블록 또는 FORM_ 폴리라인)을 클릭해서 선택하세요: ")
  (setq sel (entsel))
  (if (null sel) (progn (princ "\n취소되었습니다.") (exit)))
  (setq ent (car sel))
  (setq ed (entget ent))
  (setq etype (cdr (assoc 0 ed)))
  (cond
    ((= etype "INSERT") (setq origin (cdr (assoc 10 ed))))
    ((= etype "LWPOLYLINE") (setq origin (matx-bbox-bl ent)))
    (T (progn (princ (strcat "\n[MATCAL-DRWNO] FORM 블록/폴리라인이 아닙니다: " etype)) (exit)))
  )

  (setq drwno-pt (matx-pick-text-pos "\n2) 이 도곽의 실제 도면번호 텍스트(예: '홍성-2026-LP-001')를 클릭해서 선택하세요: "))

  ;; 기존 설정에서 DRWNODX/DRWNODY만 교체하고 나머지는 그대로 유지
  (setq *matx-config*
    (subst
      (cons 'DRWNODX (- (car drwno-pt) (car origin)))
      (assoc 'DRWNODX *matx-config*)
      *matx-config*
    )
  )
  (setq *matx-config*
    (subst
      (cons 'DRWNODY (- (cadr drwno-pt) (cadr origin)))
      (assoc 'DRWNODY *matx-config*)
      *matx-config*
    )
  )
  (matx-save-config)
  (princ "\n[MATCAL-DRWNO] 도면번호 위치 재설정 완료.")
  (princ)
)

;; ============================================================
;; MATCAL - 캘리브레이션
;; ============================================================
(defun c:MATCAL (/ frames fr origin pt-a pt-b col-pts colnames i pitch row1 row20 tmp drwno-pt
                    sel ent ed etype)
  (princ "\n[MATCAL] 자재내역 표 캘리브레이션 - 표가 잘 보이는 도곽 1개를 화면에 준비하세요.")
  (setq colnames '("번호" "품명" "규격" "단위" "수량" "비고"))

  (princ "\n1) 캘리브레이션할 도곽(FORM 블록 자체, 또는 FORM_ 레이어 테두리선)을 클릭해서 '선택'하세요")
  (princ "\n   (좌표를 클릭하는 게 아니라 도곽 엔티티 자체를 선택하는 것입니다): ")
  (setq sel (entsel))
  (if (null sel) (progn (princ "\n취소되었습니다.") (exit)))
  (setq ent (car sel))
  (setq ed (entget ent))
  (setq etype (cdr (assoc 0 ed)))
  (cond
    ((= etype "INSERT") (setq origin (cdr (assoc 10 ed))))
    ((= etype "LWPOLYLINE") (setq origin (matx-bbox-bl ent)))
    (T
      (progn
        (princ (strcat "\n[MATCAL] 선택한 엔티티(" etype ")는 FORM 블록도 FORM_ 폴리라인도 아닙니다."))
        (exit)
      )
    )
  )
  (princ (strcat "\n   -> 원점 좌표: " (rtos (car origin) 2 4) ", " (rtos (cadr origin) 2 4)))

  (setq row1 (matx-pick-text-pos "\n2) 표의 '1'번 행(번호=1)에 있는 아무 텍스트나 클릭해서 선택하세요 (예: 그 행의 품명): "))

  (setq row20 (matx-pick-text-pos "\n3) 표의 '20'번 행(맨 위, 번호 '20' 텍스트)을 클릭해서 선택하세요: "))

  (setq pitch (/ (- (cadr row20) (cadr row1)) 19.0)) ; 1~20행이면 19칸 간격

  (setq col-pts '())
  (foreach cn colnames
    (setq tmp
      (matx-pick-text-pos
        (strcat "\n'" cn "' 열에 실제 값이 있는 텍스트를 하나 클릭해서 선택하세요 (Y값은 무시됨): ")
      )
    )
    (setq col-pts (cons (car tmp) col-pts))
  )
  (setq col-pts (reverse col-pts))

  (setq drwno-pt (matx-pick-text-pos "\n4) 도면번호 텍스트(예: '홍성-2026-LP-001')를 클릭해서 선택하세요: "))

  ;; origin 기준 상대좌표로 정규화하여 저장 (다른 도곽에도 동일 적용 가능하도록)
  (setq *matx-config*
    (list
      (cons 'ROW1DY (- (cadr row1) (cadr origin)))
      (cons 'ROW1DX (- (car row1) (car origin)))
      (cons 'ROWPITCH pitch)
      (cons 'MAXROWS 20)
      (cons 'COLDX (mapcar '(lambda (x) (- x (car origin))) col-pts))
      (cons 'DRWNODX (- (car drwno-pt) (car origin)))
      (cons 'DRWNODY (- (cadr drwno-pt) (cadr origin)))
    )
  )

  (matx-save-config)
  (princ "\n[MATCAL] 캘리브레이션 완료. MATX 명령으로 전체 도곽을 추출하세요.")
  (princ)
)

;; ============================================================
;; MATX-VERIFY - 캘리브레이션 결과를 현재 화면 도곽에 임시 마커로 표시 (검산용)
;; ============================================================
(defun c:MATX-VERIFY (/ origin cfg pt row col sel ent ed etype)
  (if (not (matx-load-config))
    (progn (princ "\n[MATX] 캘리브레이션 정보가 없습니다. 먼저 MATCAL을 실행하세요.") (exit))
  )
  (princ "\n확인할 도곽(FORM 블록 또는 FORM_ 폴리라인)을 클릭해서 선택하세요: ")
  (setq sel (entsel))
  (if (null sel) (progn (princ "\n취소되었습니다.") (exit)))
  (setq ent (car sel))
  (setq ed (entget ent))
  (setq etype (cdr (assoc 0 ed)))
  (cond
    ((= etype "INSERT") (setq origin (cdr (assoc 10 ed))))
    ((= etype "LWPOLYLINE") (setq origin (matx-bbox-bl ent)))
    (T (progn (princ (strcat "\n[MATX-VERIFY] FORM 블록/폴리라인이 아닙니다: " etype)) (exit)))
  )
  (setq cfg *matx-config*)
  (setq row 0)
  (while (< row (cdr (assoc 'MAXROWS cfg)))
    (setq col 0)
    (foreach dx (cdr (assoc 'COLDX cfg))
      (setq pt
        (list
          (+ (car origin) dx)
          (+ (cadr origin) (cdr (assoc 'ROW1DY cfg)) (* row (cdr (assoc 'ROWPITCH cfg))))
        )
      )
      (entmake (list (cons 0 "POINT") (cons 10 pt) (cons 8 "0")))
      (setq col (1+ col))
    )
    (setq row (1+ row))
  )
  (if (and (assoc 'DRWNODX cfg) (assoc 'DRWNODY cfg))
    (progn
      (setq pt
        (list
          (+ (car origin) (cdr (assoc 'DRWNODX cfg)))
          (+ (cadr origin) (cdr (assoc 'DRWNODY cfg)))
        )
      )
      (entmake (list (cons 0 "POINT") (cons 10 pt) (cons 8 "0")))
    )
  )
  (princ "\n[MATX-VERIFY] 각 셀 위치(+ 도면번호 위치)에 POINT 마커를 찍었습니다. 확대해서 표와 맞는지 확인 후, 필요시 지우고 MATCAL을 다시 실행하세요.")
  (princ)
)

;; ============================================================
;; MATX - 전체 도곽 순회 추출
;; ============================================================
(defun c:MATX (/ cfg frames sorted-frames idx fr origin drawing-no all-texts texts box rows
                 csv-path open-result f seen-dns matx-mc-err n-ok n-fail n-dup)
  (if (not (matx-load-config))
    (progn (princ "\n[MATX] 캘리브레이션 정보가 없습니다. 먼저 MATCAL을 실행하세요.") (exit))
  )
  (setq *matx-excel-matrix* nil)
  (setq *matx-review* nil)
  (setq *matx-notes* nil)
  (setq cfg *matx-config*)

  (setq frames (matx-collect-frames cfg))
  (if (null frames)
    (progn (princ "\n[MATX] FORM 블록/FORM_ 레이어 도곽을 찾지 못했습니다.") (exit))
  )
  (setq sorted-frames (matx-sort-frames frames))
  (princ (strcat "\n[MATX] 도곽 " (itoa (length sorted-frames)) "개 발견. 문자 모으는 중..."))
  (setq all-texts (matx-collect-texts))
  (princ (strcat "\n[MATX] 문자 " (itoa (length all-texts)) "개. 처리 시작..."))

  (setq open-result (matx-safe-open (strcat (matx-output-dir) "material_export.csv") "w"))
  (if (null open-result)
    (progn
      (princ "\n[MATX] 오류: 결과 CSV 파일을 어느 경로에도 열지 못했습니다.")
      (princ "\n  - 다른 프로그램(엑셀 등)에서 열려있지 않은지 확인 후 다시 시도하세요.")
      (exit)
    )
  )
  (setq f (car open-result))
  (setq csv-path (cdr open-result))
  (princ (strcat "\n[MATX] 결과 CSV 경로: " csv-path))
  (write-line "도면번호,번호,품명,규격,단위,수량,비고" f)

  (setq idx 0 seen-dns '() n-ok 0 n-fail 0 n-dup 0)
  (foreach fr sorted-frames
    (setq origin (car fr))
    (setq box (matx-frame-roi origin cfg))
    (setq texts (matx-texts-in-box all-texts (nth 0 box) (nth 1 box) (nth 2 box) (nth 3 box)))
    (setq drawing-no (matx-find-drawing-no origin cfg texts))
    (cond
      ((null drawing-no)
       (setq n-fail (1+ n-fail))
       (matx-log (strcat "도곽 #" (itoa idx) " (원점 " (rtos (car origin) 2 1) "," (rtos (cadr origin) 2 1)
                         ") 도면번호 인식 실패 - 스킵"))
       (princ (strcat "\n  [경고] 도곽 #" (itoa idx) " 도면번호를 찾지 못해 스킵합니다."))
      )
      ((member drawing-no seen-dns)
       ;; 같은 도면번호가 두 도곽에서 나오면, 나중 것이 앞의 결과를 덮어쓰지 않도록 건너뜀
       (setq n-dup (1+ n-dup))
       (matx-log (strcat "도곽 #" (itoa idx) " (원점 " (rtos (car origin) 2 1) "," (rtos (cadr origin) 2 1)
                         ") 도면번호 " drawing-no " 중복 - 스킵"))
       (setq *matx-review* (cons (list drawing-no "" "" "" "" ""
                                       (strcat "도면번호 중복 - 도곽 #" (itoa idx) " 은 건너뜀 (도면번호 문자 확인 필요)"))
                                 *matx-review*))
       (princ (strcat "\n  [경고] 도곽 #" (itoa idx) " 도면번호 " drawing-no " 가 중복되어 건너뜁니다."))
      )
      (T
       (setq seen-dns (cons drawing-no seen-dns))
       (setq n-ok (1+ n-ok))
       (princ (strcat "\n  처리중: " drawing-no))
       (setq rows (matx-read-table origin cfg texts))
       (if (null rows)
         (setq *matx-review* (cons (list drawing-no "" "" "" "" "" "자재내역 표에서 읽은 행이 없음 (표 위치 보정 확인)")
                                   *matx-review*))
       )
       (foreach vals rows
         (write-line (matx-csv-line (cons drawing-no vals)) f)
       )
       (setq *matx-excel-matrix*
         (cons (cons drawing-no (matx-classify-drawing drawing-no rows)) *matx-excel-matrix*)
       )
      )
    )
    (setq idx (1+ idx))
  )
  (close f)
  (matx-log (strcat "MATX 완료: 도곽 " (itoa (length sorted-frames)) "개 중 " (itoa n-ok) "개 추출, 도면번호 실패 "
                    (itoa n-fail) "개, 중복 " (itoa n-dup) "개 -> " csv-path))
  (princ (strcat "\n[MATX] 완료. 도곽 " (itoa n-ok) "개 추출 (도면번호 실패 " (itoa n-fail)
                 ", 중복 " (itoa n-dup) "). 결과 파일: " csv-path))

  ;; 리습 안에 포팅된 매칭 규칙으로 엑셀 위치에 맞춘 CSV도 바로 생성 (파이썬 단계 불필요)
  (if (vl-catch-all-error-p (setq matx-mc-err (vl-catch-all-apply 'matx-write-matched-csv nil)))
    (progn
      (princ "\n[MATX] 오류: 엑셀 매칭 CSV 생성 중 문제가 발생했습니다:")
      (princ (strcat "\n  " (vl-catch-all-error-message matx-mc-err)))
    )
  )
  ;; 엑셀에 자동 반영되지 않은 항목 목록 (사람이 확인할 것)
  (vl-catch-all-apply 'matx-write-review-csv nil)
  ;; 엑셀 칸에 붙일 확인 메모 (예: MP S.TEE 2개 이상)
  (vl-catch-all-apply 'matx-write-notes-csv nil)

  ;; excel_matched.csv 가 준비되면 전자제도도우미.exe 자신을 불러서 자재내역.xlsx 양식에 채워 넣고
  ;; 바로 엑셀로 연다 (전자제도 도우미 실행 때마다 (setq *CADLAUNCHER-EXE* ...) 로 경로를 받아둠).
  ;; LT 버전에 따라 startapp이 제한될 수 있어, 실패해도 CSV 추출 결과에는 영향 없도록 안전하게 처리.
  (if (and (boundp '*CADLAUNCHER-EXE*) *CADLAUNCHER-EXE* (findfile *CADLAUNCHER-EXE*))
    (progn
      (princ "\n[MATX] 전자제도도우미.exe 로 엑셀 자동 생성을 시도합니다...")
      (if (vl-catch-all-error-p
            (vl-catch-all-apply 'startapp
              (list *CADLAUNCHER-EXE* (strcat "--matx-fill " (matx-quote-arg (matx-output-dir)))))
          )
        (princ "\n[MATX] 자동 실행에 실패했습니다(LT 제한 가능성). 전자제도 도우미를 열고 아무 기능이나 한 번 실행한 뒤 MATX를 다시 실행해 보세요.")
        (princ "\n[MATX] 자동 실행을 시도했습니다. 완료되면 MATX 폴더의 auto_matx_log.txt를 확인하세요.")
      )
    )
    (princ "\n[MATX] 전자제도도우미.exe 경로를 몰라 엑셀 자동 생성을 건너뜁니다. (전자제도 도우미에서 아무 기능이나 한 번 실행한 뒤 다시 시도하거나, excel_matched.csv 를 자재내역.xlsx 의 G8 셀에 직접 붙여넣으세요)")
  )
  (princ)
)

(defun matx-csv-esc (s)
  ;; 콤마/따옴표/줄바꿈 포함 시 CSV 이스케이프 (따옴표는 전부 "" 로)
  (if (/= (type s) 'STR) (setq s (vl-princ-to-string s)))
  (if (or (vl-string-search "," s) (vl-string-search "\"" s) (vl-string-search "\n" s))
    (strcat "\"" (matx-replace-all s "\"" "\"\"") "\"")
    s
  )
)

(defun matx-csv-line (fields / s first)
  (setq s "" first T)
  (foreach v fields
    (setq s (if first (matx-csv-esc v) (strcat s "," (matx-csv-esc v))))
    (setq first nil)
  )
  s
)

(defun matx-write-review-csv (/ open-result f)
  (setq open-result (matx-safe-open (strcat (matx-output-dir) "matx-review.csv") "w"))
  (if open-result
    (progn
      (setq f (car open-result))
      (write-line "도면번호,번호,품명,규격,수량,비고,확인 사유" f)
      (foreach r (reverse *matx-review*)
        (write-line (matx-csv-line r) f)
      )
      (close f)
      (if *matx-review*
        (princ (strcat "\n[MATX] 엑셀에 자동 반영되지 않은 항목 " (itoa (length *matx-review*))
                       "건 - 꼭 확인하세요: " (cdr open-result)))
        (princ "\n[MATX] 모든 자재 행이 엑셀 위치에 매칭되었습니다.")
      )
    )
  )
)

;; ============================================================
;; 엑셀 매칭용 테이블 (mapping_engine.py에서 자동 생성 - 규칙 바뀌면 재생성 필요)
;; ============================================================

(setq ROW-PLP-PIPE
  (list
    (cons 500 8)
    (cons 400 10)
    (cons 300 12)
    (cons 200 14)
    (cons 150 15)
    (cons 100 17)
    (cons 80 18)
    (cons 65 19)
    (cons 50 20)
  )
)

(setq ROW-PE-PIPE
  (list
    (cons 315 47)
    (cons 225 49)
    (cons 160 51)
    (cons 110 53)
    (cons 63 55)
  )
)

(setq ROW-STEEL-ELBOW  ;; 키: 큰관경*10000+작은관경
  (list
    (cons 5000090 172)  ; 500x90
    (cons 5000045 173)  ; 500x45
    (cons 4000090 175)  ; 400x90
    (cons 4000045 176)  ; 400x45
    (cons 3000090 178)  ; 300x90
    (cons 3000045 179)  ; 300x45
    (cons 2000090 180)  ; 200x90
    (cons 2000045 181)  ; 200x45
    (cons 1000090 182)  ; 100x90
    (cons 1000045 183)  ; 100x45
    (cons 800090 184)  ; 80x90
    (cons 800045 185)  ; 80x45
    (cons 650090 186)  ; 65x90
    (cons 650045 187)  ; 65x45
    (cons 500090 188)  ; 50x90
    (cons 500045 189)  ; 50x45
  )
)

(setq ROW-PE-ELBOW  ;; 키: 큰관경*10000+작은관경
  (list
    (cons 3150090 57)  ; 315x90
    (cons 3150045 58)  ; 315x45
    (cons 2250090 59)  ; 225x90
    (cons 2250045 60)  ; 225x45
    (cons 1600090 61)  ; 160x90
    (cons 1600045 62)  ; 160x45
    (cons 1100090 63)  ; 110x90
    (cons 1100045 64)  ; 110x45
    (cons 900090 65)  ; 90x90
    (cons 900045 66)  ; 90x45
    (cons 630090 67)  ; 63x90
  )
)

(setq ROW-STEEL-TEE  ;; 키: 큰관경*10000+작은관경
  (list
    (cons 6000600 190)  ; 600x600
    (cons 6000500 191)  ; 600x500
    (cons 6000400 192)  ; 600x400
    (cons 5000500 193)  ; 500x500
    (cons 5000400 194)  ; 500x400
    (cons 5000300 195)  ; 500x300
    (cons 5000200 196)  ; 500x200
    (cons 4000400 197)  ; 400x400
    (cons 4000300 198)  ; 400x300
    (cons 4000200 199)  ; 400x200
    (cons 4000150 200)  ; 400x150
    (cons 3000300 201)  ; 300x300
    (cons 3000200 202)  ; 300x200
    (cons 3000150 203)  ; 300x150
    (cons 2000200 204)  ; 200x200
    (cons 2000150 205)  ; 200x150
    (cons 2000100 206)  ; 200x100
    (cons 1500150 207)  ; 150x150
    (cons 1500100 208)  ; 150x100
    (cons 1500080 209)  ; 150x80
    (cons 1500065 210)  ; 150x65
    (cons 1000100 211)  ; 100x100
    (cons 1000080 212)  ; 100x80
    (cons 1000065 213)  ; 100x65
    (cons 1000050 214)  ; 100x50
    (cons 800080 215)  ; 80x80
    (cons 800065 216)  ; 80x65
    (cons 800050 217)  ; 80x50
    (cons 650065 218)  ; 65x65
    (cons 650050 219)  ; 65x50
    (cons 500050 220)  ; 50x50
  )
)

(setq ROW-PE-TEE  ;; 키: 큰관경*10000+작은관경
  (list
    (cons 3150315 68)  ; 315x315
    (cons 3150225 69)  ; 315x225
    (cons 3150160 70)  ; 315x160
    (cons 3150110 71)  ; 315x110
    (cons 3150090 72)  ; 315x90
    (cons 3150063 73)  ; 315x63
    (cons 2250225 74)  ; 225x225
    (cons 2250160 75)  ; 225x160
    (cons 2250110 76)  ; 225x110
    (cons 2250090 77)  ; 225x90
    (cons 2250063 78)  ; 225x63
    (cons 1600160 79)  ; 160x160
    (cons 1600110 80)  ; 160x110
    (cons 1600090 81)  ; 160x90
    (cons 1600063 82)  ; 160x63
    (cons 1100110 83)  ; 110x110
    (cons 1100090 84)  ; 110x90
    (cons 1100063 85)  ; 110x63
  )
)

(setq ROW-STEEL-CAP
  (list
    (cons 600 221)
    (cons 500 222)
    (cons 400 223)
    (cons 300 224)
    (cons 200 225)
    (cons 150 226)
    (cons 100 227)
    (cons 80 228)
    (cons 65 229)
    (cons 50 230)
  )
)

(setq ROW-PE-CAP
  (list
    (cons 315 100)
    (cons 225 101)
    (cons 160 102)
    (cons 110 103)
    (cons 90 104)
    (cons 63 105)
  )
)

(setq ROW-STEEL-RD  ;; 키: 큰관경*10000+작은관경
  (list
    (cons 5000300 231)  ; 500x300
    (cons 5000400 232)  ; 500x400
    (cons 4000200 233)  ; 400x200
    (cons 4000300 234)  ; 400x300
    (cons 3000150 235)  ; 300x150
    (cons 3000200 236)  ; 300x200
    (cons 2000080 237)  ; 200x80
    (cons 2000100 238)  ; 200x100
    (cons 2000150 239)  ; 200x150
    (cons 1500065 240)  ; 150x65
    (cons 1500080 241)  ; 150x80
    (cons 1500100 242)  ; 150x100
    (cons 1000050 243)  ; 100x50
    (cons 1000065 244)  ; 100x65
    (cons 1000080 245)  ; 100x80
    (cons 800050 246)  ; 80x50
    (cons 800065 247)  ; 80x65
    (cons 650050 248)  ; 65x50
  )
)

(setq ROW-PE-RD  ;; 키: 큰관경*10000+작은관경
  (list
    (cons 3150225 86)  ; 315x225
    (cons 3150160 87)  ; 315x160
    (cons 3150110 88)  ; 315x110
    (cons 3150090 89)  ; 315x90
    (cons 3150063 90)  ; 315x63
    (cons 2250160 91)  ; 225x160
    (cons 2250110 92)  ; 225x110
    (cons 2250090 93)  ; 225x90
    (cons 2250063 94)  ; 225x63
    (cons 1600110 95)  ; 160x110
    (cons 1600090 96)  ; 160x90
    (cons 1600063 97)  ; 160x63
    (cons 1100090 98)  ; 110x90
    (cons 1100063 99)  ; 110x63
  )
)

(setq ROW-VALVE-2P
  (list
    (cons 500 250)
    (cons 400 251)
    (cons 300 252)
    (cons 200 253)
    (cons 150 255)
    (cons 100 257)
    (cons 80 259)
    (cons 65 261)
    (cons 50 263)
  )
)

(setq ROW-PE-VALVE
  (list
    (cons 315 165)
    (cons 225 166)
    (cons 160 167)
    (cons 110 168)
    (cons 90 169)
    (cons 63 170)
  )
)

(setq ROW-DIANJA-ELBOW
  (list
    (cons 225 144)
    (cons 160 145)
    (cons 110 146)
    (cons 90 147)
    (cons 63 148)
  )
)

(setq ROW-DIANJA-TEE
  (list
    (cons 225 149)
    (cons 160 150)
    (cons 110 151)
    (cons 90 152)
    (cons 63 153)
  )
)

(setq ROW-DIANJA-CAP
  (list
    (cons 160 154)
    (cons 110 155)
    (cons 90 156)
    (cons 63 157)
  )
)

(setq ROW-ST  ;; 키: 큰관경*10000+작은관경
  (list
    (cons 3150160 119)  ; 315x160
    (cons 2800160 120)  ; 280x160
    (cons 2250160 121)  ; 225x160
    (cons 3150110 122)  ; 315x110
    (cons 2800110 123)  ; 280x110
    (cons 2250110 124)  ; 225x110
    (cons 1600110 125)  ; 160x110
    (cons 3150090 126)  ; 315x90
    (cons 2800090 127)  ; 280x90
    (cons 2250090 128)  ; 225x90
    (cons 1600090 129)  ; 160x90
    (cons 1100090 130)  ; 110x90
    (cons 3150063 131)  ; 315x63
    (cons 2800063 132)  ; 280x63
    (cons 2250063 133)  ; 225x63
    (cons 1600063 134)  ; 160x63
    (cons 1100063 135)  ; 110x63
    (cons 900063 136)  ; 90x63
    (cons 630063 137)  ; 63x63
  )
)

(setq ROW-TF-SHORT
  (list
    (cons 315 106)
    (cons 225 107)
    (cons 160 108)
    (cons 110 109)
    (cons 90 110)
    (cons 63 111)
  )
)

(setq ROW-TF-LONG
  (list
    (cons 315 112)
    (cons 225 113)
    (cons 160 114)
    (cons 110 115)
    (cons 90 116)
    (cons 63 117)
  )
)
;; ============================================================
;; 엑셀 매칭 로직 - mapping_engine.py의 분류/라우팅 규칙을 그대로 포팅
;; (규칙이 바뀌면 mapping_engine.py를 고친 뒤 이 블록도 다시 생성해야 함)
;; ============================================================

;; 도곽 원본 CAD 관경단위(mm 또는 A)는 숫자만 취급하므로 단위 문자는 무시함.

(defun matx-is-digit2 (c)
  (and (>= (ascii c) 48) (<= (ascii c) 57))
)

(defun matx-all-numbers (s / n i c num result in-num)
  ;; 문자열에서 모든 숫자 덩어리를 순서대로 추출 (예: "200AX100A" -> (200 100))
  (setq n (strlen s))
  (setq i 1)
  (setq result '())
  (setq num "")
  (setq in-num nil)
  (while (<= i n)
    (setq c (substr s i 1))
    (if (matx-is-digit2 c)
      (progn (setq num (strcat num c)) (setq in-num T))
      (progn
        (if in-num (setq result (cons (atoi num) result)))
        (setq num "")
        (setq in-num nil)
      )
    )
    (setq i (1+ i))
  )
  (if in-num (setq result (cons (atoi num) result)))
  (reverse result)
)

(defun matx-norm2 (s / n i c out)
  ;; 공백 제거 + 대문자 통일
  (if (null s) (setq s ""))
  (setq n (strlen s))
  (setq i 1)
  (setq out "")
  (while (<= i n)
    (setq c (substr s i 1))
    (if (/= c " ")
      (setq out (strcat out (strcase c)))
    )
    (setq i (1+ i))
  )
  out
)

;; 품명 -> 버킷 매핑 테이블 (키는 이미 공백제거+대문자 상태)
(setq MATX-NAME-TABLE
  (list
    (cons "직관" "PIPE") (cons "인입관" "PIPE") (cons "연결관" "PIPE")
    (cons "90°ELBOW" "ELBOW") (cons "45°ELBOW" "ELBOW") (cons "ELBOW" "ELBOW")
    (cons "TEE" "TEE")
    (cons "S.TEE" "STEE") (cons "STEE" "STEE")
    (cons "REDUCER" "RD") (cons "R/D" "RD") (cons "R.D" "RD")
    (cons "CAP" "CAP")
    (cons "VALVE" "VALVE")
    (cons "MG-ANODE" "ANODE") (cons "마그네슘" "ANODE")
    (cons "TESTBOX" "TESTBOX") (cons "T.B" "TESTBOX") (cons "T/B" "TESTBOX")
    (cons "T/F" "TF")
    (cons "표지판" "SIGNBOARD")
    (cons "LINEMARK" "LINEMARK")
    (cons "보호철판" "IGNORE")
  )
)

(defun matx-classify (raw-name / key bucket bestlen pair)
  ;; 품명 안에 들어있는 표 키워드 중 가장 긴 것으로 분류
  ;; (예: "S.TEE" 는 "TEE" 보다 길어서 S.TEE 로. 예전처럼 품명이 키워드의 일부인 경우까지
  ;;  거꾸로 맞추면 "T" 같은 짧은 문자가 엉뚱한 자재로 들어갈 수 있어 뺌)
  (setq key (matx-norm2 raw-name))
  (setq bucket nil bestlen 0)
  (if (/= key "")
    (foreach pair MATX-NAME-TABLE
      (if (and (vl-string-search (car pair) key) (> (strlen (car pair)) bestlen))
        (setq bucket (cdr pair) bestlen (strlen (car pair)))
      )
    )
  )
  bucket
)

(defun matx-spec-is-steel (spec / u i n found)
  ;; 규격 단위로 강관/PE 구분: "200A", "200Ax100A" = 강관(A 호칭), "315mm" = PE
  (setq u (strcase (if spec spec "")) found nil)
  (if (not (vl-string-search "MM" u))
    (progn
      (setq i 1 n (strlen u))
      (while (and (< i n) (not found))
        (if (and (matx-is-digit (substr u i 1)) (= (substr u (1+ i) 1) "A")) (setq found T))
        (setq i (1+ i))
      )
    )
  )
  found
)

(defun matx-review (dn row reason)
  ;; 엑셀에 자동 반영 못 한 행을 matx-review.csv 용으로 모음 (+ 로그)
  (setq *matx-review*
    (cons (list dn (nth 0 row) (nth 1 row) (nth 2 row) (nth 4 row) (nth 5 row) reason) *matx-review*))
  (matx-log (strcat "[매칭] " dn " #" (nth 0 row) " " (nth 1 row) " " (nth 2 row) " - " reason))
)

(defun matx-add-note (dn xrow memo / key entry)
  ;; 엑셀 칸(도면번호 열, xrow 행)에 붙일 메모. 같은 칸에 여러 개면 " / " 로 이어붙임
  (setq key (cons dn xrow))
  (setq entry (assoc key *matx-notes*))
  (if entry
    (setq *matx-notes* (subst (cons key (strcat (cdr entry) " / " memo)) entry *matx-notes*))
    (setq *matx-notes* (cons (cons key memo) *matx-notes*))
  )
)

(defun matx-write-notes-csv (/ open-result f)
  ;; 전자제도 도우미가 읽어서 자재내역_결과.xlsx 의 해당 칸에 메모로 붙임 (도면번호,엑셀행,메모)
  (setq open-result (matx-safe-open (strcat (matx-output-dir) "excel_notes.csv") "w"))
  (if open-result
    (progn
      (setq f (car open-result))
      (write-line "도면번호,행,메모" f)
      (foreach n (reverse *matx-notes*)
        (write-line (matx-csv-line (list (car (car n)) (itoa (cdr (car n))) (cdr n))) f)
      )
      (close f)
    )
  )
)

(defun matx-extract-angle (raw-name / nums)
  ;; ELBOW 품명("90%%DELBOW" 등)에서 각도 숫자 추출
  (setq nums (matx-all-numbers raw-name))
  (if nums (car nums) nil)
)

(defun matx-is-steel-remark (remark)
  (and remark (/= remark "") (/= (vl-string-search "PLP" (strcase remark)) nil))
)

(defun matx-pair-key (a b / d1 d2)
  (if (> a b) (progn (setq d1 a) (setq d2 b)) (progn (setq d1 b) (setq d2 a)))
  (+ (* d1 10000) d2)
)

;; 단일 관경 표에서 값 조회 (없으면 nil)
(defun matx-lookup1 (table dia / found)
  (setq found (assoc dia table))
  (if found (cdr found) nil)
)

;; 2단 관경 표에서 값 조회 (크기 순서 무관하게 자동 정렬 후 조회)
(defun matx-lookup2 (table d1 d2 / found)
  (setq found (assoc (matx-pair-key d1 d2) table))
  (if found (cdr found) nil)
)

;; ------------------------------------------------------------
;; 도면 1개분의 원시행 리스트(각 행 = (번호 품명 규격 단위 수량 비고))를 받아서
;; ((엑셀행 . 값또는수식문자열) ...) 형태로 반환
;; ------------------------------------------------------------
(defun matx-classify-drawing (drawing-no rows / pressure row name spec unit qty remark
                               bucket steel dia d1 d2 angle table row-num
                               result pipe-alist entry lp300-list stee-main stee-count)
  ;; steel(강관 규칙) = 비고에 PLP 가 있거나, 규격이 A 호칭(예: 300A)인 경우.
  ;; (MP 도면은 원래 모두 강관 규칙)
  (setq pressure
    (cond
      ((/= (vl-string-search "MP" (strcase drawing-no)) nil) "MP")
      ((/= (vl-string-search "LP" (strcase drawing-no)) nil) "LP")
      (T nil)
    )
  )
  (setq result '())      ; ((엑셀행 . 숫자값) ...) - 단일값 항목
  (setq pipe-alist '())  ; ((관경 . (값 값 ...)) ...) - 일반 파이프 합산용
  (setq lp300-list '())  ; LP 도면의 300A/PLP 예외 파이프 합산용

  (if (null pressure)
    (progn
      (matx-log (strcat "[매칭] " drawing-no " - MP/LP 구분 불가, 매칭 스킵"))
      (setq result nil)
    )
    (foreach row rows
      (setq name (nth 1 row))
      (setq spec (nth 2 row))
      (setq unit (nth 3 row))
      (setq qty (matx-str-to-real (nth 4 row)))
      (setq remark (nth 5 row))
      (setq bucket (matx-classify name))
      (setq steel (or (matx-is-steel-remark remark) (matx-spec-is-steel spec)))
      (setq dia (matx-all-numbers spec))
      (setq row-num nil)

      (cond
        ;; 품명이 비었거나 무시 규칙(보호철판 등)
        ((or (= name "") (= bucket "IGNORE")) nil)

        ;; 매핑 규칙 없는 품명 - 수량이나 규격이 있으면 확인 목록에
        ((null bucket)
         (if (or (/= qty 0.0) (/= spec ""))
           (matx-review drawing-no row "품명 매핑 규칙 없음")
         )
        )

        ;; 관경이 필요한 자재인데 규격에 숫자가 없음
        ((and (member bucket '("PIPE" "ELBOW" "STEE" "TEE" "RD" "CAP" "VALVE" "TF")) (null dia))
         (if (/= qty 0.0) (matx-review drawing-no row "규격에서 관경을 읽지 못함"))
        )

        ;; ---------------- PIPE ----------------
        ((= bucket "PIPE")
         (if (and (= pressure "LP") steel)
           (if (= (car dia) 300)
             (setq lp300-list (cons qty lp300-list))
             (matx-review drawing-no row "LP 도면의 강관(PLP) 파이프는 300A 만 규칙 있음")
           )
           (progn
             (setq entry (assoc (car dia) pipe-alist))
             (if entry
               (setq pipe-alist (subst (cons (car dia) (cons qty (cdr entry))) entry pipe-alist))
               (setq pipe-alist (cons (cons (car dia) (list qty)) pipe-alist))
             )
           )
         )
        )

        ;; ---------------- ELBOW ----------------
        ((= bucket "ELBOW")
         (if (= (car dia) 63)
           (setq row-num (matx-lookup1 ROW-DIANJA-ELBOW 63))
           (progn
             (setq angle (matx-extract-angle name))
             (setq table (if (or steel (= pressure "MP")) ROW-STEEL-ELBOW ROW-PE-ELBOW))
             (setq row-num (if angle (matx-lookup2 table (car dia) angle) nil))
           )
         )
         (if row-num
           (setq result (matx-acc result row-num qty))
           (matx-review drawing-no row (if angle "엑셀에 해당 규격(관경x각도) 없음" "품명에서 각도(90/45)를 읽지 못함"))
         )
        )

        ;; ---------------- STEE (새들/서비스 티) ----------------
        ((= bucket "STEE")
         (if (= pressure "MP")
           (progn
             ;; MP의 S.TEE는 스토팍류 수량 계산에 사용 (자재 자체는 무시)
             ;; S.TEE 1개당: CZ = 큰관경/100(올림), 4100 = 그 값+1, PVC TAPE = 그 값 → S.TEE 개수만큼 곱함
             (setq stee-main (car dia))
             (setq stee-count (matx-ceil-div stee-main 100))
             (if (<= qty 0.0)
               (progn
                 (setq qty 1.0)
                 (matx-review drawing-no row "S.TEE 수량이 비어 있어 1개로 계산함")
               )
             )
             (setq result (matx-acc result ROW-STOPOK-CZ (* stee-count qty)))
             (setq result (matx-acc result ROW-STOPOK-4100 (* (+ stee-count 1) qty)))
             (setq result (matx-acc result ROW-PVC-TAPE (* stee-count qty)))
             ;; MP 서비스티는 보통 1개라, 2개 이상이면 엑셀 칸에 확인 메모
             (if (>= qty 2.0)
               (progn
                 (foreach r (list ROW-STOPOK-CZ ROW-STOPOK-4100 ROW-PVC-TAPE)
                   (matx-add-note drawing-no r
                     (strcat "확인 필요: S.TEE " spec " " (matx-fmt-num qty) "개 (MP 서비스티는 보통 1개)"))
                 )
                 (matx-review drawing-no row "MP S.TEE 2개 이상 - 스토팍/PVC TAPE 수량 확인 필요")
               )
             )
           )
           (progn
             (if (>= (length dia) 2)
               (setq row-num (matx-lookup2 ROW-ST (nth 0 dia) (nth 1 dia)))
             )
             (if row-num
               (setq result (matx-acc result row-num qty))
               (matx-review drawing-no row "S/T 표에 해당 규격 없음")
             )
           )
         )
        )

        ;; ---------------- TEE / RD ----------------
        ((or (= bucket "TEE") (= bucket "RD"))
         (if (>= (length dia) 2)
           (progn
             (setq d1 (nth 0 dia)) (setq d2 (nth 1 dia))
             (if (> d2 d1) (progn (setq d1 (nth 1 dia)) (setq d2 (nth 0 dia))))
             (if (and (= bucket "TEE") (= d1 63) (= d2 63))
               (setq row-num (matx-lookup1 ROW-DIANJA-TEE 63))
               (progn
                 (setq table
                   (cond
                     ((and (= bucket "TEE") (or steel (= pressure "MP"))) ROW-STEEL-TEE)
                     ((= bucket "TEE") ROW-PE-TEE)
                     ((or steel (= pressure "MP")) ROW-STEEL-RD)
                     (T ROW-PE-RD)
                   )
                 )
                 (setq row-num (matx-lookup2 table d1 d2))
               )
             )
           )
         )
         (if row-num
           (setq result (matx-acc result row-num qty))
           (matx-review drawing-no row "엑셀에 해당 규격 없음 (관경 2개 필요)")
         )
        )

        ;; ---------------- CAP ----------------
        ((= bucket "CAP")
         (if (= (car dia) 63)
           (setq row-num (matx-lookup1 ROW-DIANJA-CAP 63))
           (setq row-num (matx-lookup1 (if (or steel (= pressure "MP")) ROW-STEEL-CAP ROW-PE-CAP) (car dia)))
         )
         (if row-num
           (setq result (matx-acc result row-num qty))
           (matx-review drawing-no row "엑셀에 해당 규격 없음")
         )
        )

        ;; ---------------- VALVE ----------------
        ((= bucket "VALVE")
         (setq row-num (matx-lookup1 (if (or steel (= pressure "MP")) ROW-VALVE-2P ROW-PE-VALVE) (car dia)))
         (if row-num
           (setq result (matx-acc result row-num qty))
           (matx-review drawing-no row "엑셀에 해당 밸브 규격 없음")
         )
        )

        ;; ---------------- ANODE / TESTBOX / SIGNBOARD / LINEMARK ----------------
        ((= bucket "ANODE") (setq result (matx-acc result ROW-MG-ANODE-N qty)))
        ((= bucket "TESTBOX") (setq result (matx-acc result ROW-TEST-BOX-N qty)))
        ((= bucket "SIGNBOARD") (setq result (matx-acc result ROW-SIGNBOARD-N qty)))
        ((= bucket "LINEMARK") (setq result (matx-acc result ROW-LINE-MARK-N qty)))

        ;; ---------------- T/F ----------------
        ((= bucket "TF")
         (setq row-num (matx-lookup1 (if (vl-string-search "LONG" (strcase remark)) ROW-TF-LONG ROW-TF-SHORT) (car dia)))
         (if row-num
           (setq result (matx-acc result row-num qty))
           (matx-review drawing-no row "엑셀에 해당 T/F 규격 없음")
         )
        )
      ) ; cond 끝
    ) ; foreach row 끝
  )

  ;; 파이프 합산 결과를 result에 반영 (여러 값이면 수식 문자열, 하나면 숫자)
  (if pressure
    (progn
      (setq table (if (= pressure "MP") ROW-PLP-PIPE ROW-PE-PIPE))
      (foreach entry pipe-alist
        (setq row-num (matx-lookup1 table (car entry)))
        (if row-num
          (setq result (matx-acc-values result row-num (reverse (cdr entry))))
          (matx-review drawing-no (list "" "파이프" (itoa (car entry)) ""
                                        (matx-fmt-num (apply '+ (cdr entry))) "")
                       "엑셀에 해당 관경의 파이프 행 없음")
        )
      )
      (if lp300-list
        (setq result (matx-acc-values result ROW-LP-PLP-PIPE300-N (reverse lp300-list)))
      )
    )
  )

  result
)

;; result 알리스트에 (row . qty)를 더함(이미 있으면 합산)
(defun matx-acc (result row qty / entry)
  (setq entry (assoc row result))
  (if entry
    (subst (cons row (+ (cdr entry) qty)) entry result)
    (cons (cons row qty) result)
  )
)

;; values 리스트(직관/연결관 등 개별 값들)를 result에 (row . "수식또는숫자문자열")로 반영
;; 합계가 0이면 항목 자체를 만들지 않음 (품명/규격은 있지만 실질 수량이 없는 경우)
(defun matx-acc-values (result row values / total s)
  (setq total 0.0)
  (foreach v values (setq total (+ total v)))
  (cond
    ((= total 0.0) (matx-remove-row result row))
    ((> (length values) 1)
     (setq s "")
     (foreach v values
       (setq s (strcat s (if (= s "") "" "+") (matx-fmt-num v)))
     )
     (cons (cons row (strcat "=" s)) (matx-remove-row result row))
    )
    (T (matx-acc result row total))
  )
)

(defun matx-remove-row (result row)
  (vl-remove (assoc row result) result)
)

(defun matx-fmt-num (v / s)
  ;; 1.5 -> "1.5", 200.0 -> "200" (예전엔 "1.5000" 처럼 0이 붙어 나왔음)
  (setq s (rtos v 2 4))
  (if (vl-string-search "." s)
    (setq s (vl-string-right-trim "." (vl-string-right-trim "0" s)))
  )
  s
)

(defun matx-ceil-div (a b / q)
  (setq q (/ (float a) (float b)))
  (if (= q (fix q)) (fix q) (1+ (fix q)))
)

(defun matx-str-to-real (s / n)
  (if (or (null s) (= s ""))
    0.0
    ;; "1,200" 같은 천단위 콤마 제거 후 숫자로
    (atof (matx-replace-all s "," ""))
  )
)

;; 단일행 항목의 엑셀 행번호 (mapping_engine.py와 동일)
(setq ROW-MG-ANODE-N 305)
(setq ROW-TEST-BOX-N 267)
(setq ROW-SIGNBOARD-N 332)
(setq ROW-LINE-MARK-N 331)
(setq ROW-LP-PLP-PIPE300-N 330)
(setq ROW-STOPOK-CZ 286)
(setq ROW-STOPOK-4100 287)
(setq ROW-PVC-TAPE 288)

;; 엑셀 6행의 기존(현재 양식 기준) 도면번호 열 순서 - 새 도면이 이 범위를 넘어서면
;; matx-build-drawing-order가 자동으로 뒤에 이어붙여서 확장함
(setq MATX-DRAWING-ORDER-BASE
  (list
    "MP-001" "MP-002" "MP-003" "MP-004" "MP-005" "MP-006" "MP-007" "MP-008" "MP-009" "MP-010" "MP-011"
    "LP-001" "LP-002" "LP-003" "LP-004" "LP-005" "LP-006" "LP-007" "LP-008" "LP-009" "LP-010"
    "LP-011" "LP-012" "LP-013" "LP-014" "LP-015" "LP-016" "LP-017" "LP-018" "LP-019" "LP-020"
    "LP-021" "LP-022" "LP-023" "LP-024" "LP-025" "LP-026" "LP-027" "LP-028" "LP-029"
  )
)

(defun matx-parse-dn (dn / us)
  ;; "MP-012" -> (cons "MP" 12). 형식이 안 맞으면 (cons dn 999999)로 맨 뒤로 밀림
  (setq us (vl-string-search "-" dn))
  (if us
    (cons (substr dn 1 us) (atoi (substr dn (+ us 2))))
    (cons dn 999999)
  )
)

(defun matx-prefix-priority (p)
  (cond ((= p "MP") 0) ((= p "LP") 1) (T 2))
)

(defun matx-dn-less (a b / pa pb pra prb)
  (setq pa (matx-parse-dn a))
  (setq pb (matx-parse-dn b))
  (setq pra (matx-prefix-priority (car pa)))
  (setq prb (matx-prefix-priority (car pb)))
  (if (/= pra prb)
    (< pra prb)
    (< (cdr pa) (cdr pb))
  )
)

(defun matx-build-drawing-order (/ all-dns seen dn-entry dn)
  ;; 기존 40개 기준 목록 + *matx-excel-matrix*에서 실제 발견됐지만 기준 목록에 없는
  ;; 도면번호(예: MP-012, LP-030 등)를 자동으로 합쳐서 정렬된 전체 목록을 만듦
  (setq all-dns (append MATX-DRAWING-ORDER-BASE '()))
  (setq seen (mapcar 'strcase all-dns))
  (foreach dn-entry *matx-excel-matrix*
    (setq dn (car dn-entry))
    (if (not (member (strcase dn) seen))
      (progn
        (setq all-dns (cons dn all-dns))
        (setq seen (cons (strcase dn) seen))
      )
    )
  )
  (vl-sort all-dns 'matx-dn-less)
)

;; ------------------------------------------------------------
;; *matx-excel-matrix*를 엑셀 행/열 위치에 맞춘 피벗 CSV로 저장
;; ------------------------------------------------------------
(defun matx-write-matched-csv (/ path f dn entry row-list r header line cell dn-entry min-row max-row open-result actual-path drawing-order)
  (setq path (strcat (matx-output-dir) "excel_matched.csv"))
  (setq open-result (matx-safe-open path "w"))
  (if (null open-result)
    (progn
      (princ (strcat "\n[MATX] 오류: excel_matched.csv 를 어느 경로에도 저장하지 못했습니다."))
      (princ "\n  - 다른 프로그램(엑셀 등)에서 열려있지 않은지 확인 후 MATX를 다시 실행하세요.")
      (exit)
    )
  )
  (setq f (car open-result))
  (setq actual-path (cdr open-result))
  (princ (strcat "\n[MATX] 엑셀 매칭 CSV 작성 중: " actual-path))

  ;; 붙여넣기 시 행 번호가 어긋나지 않도록, 실제 사용된 행만이 아니라
  ;; 엑셀 자재수량 시트의 전체 데이터 범위(8~332)를 빈 칸 포함해서 연속으로 출력
  (setq min-row 8)
  (setq max-row 332)

  ;; 헤더 행 (기존 40개 기준 + 새로 발견된 도면번호까지 자동으로 정렬해서 확장)
  (setq drawing-order (matx-build-drawing-order))
  (setq header "행")
  (foreach dn drawing-order (setq header (strcat header "," dn)))
  (write-line header f)

  ;; 데이터 행 (min-row ~ max-row 연속)
  (setq r min-row)
  (while (<= r max-row)
    (setq line (itoa r))
    (foreach dn drawing-order
      (setq dn-entry (assoc dn *matx-excel-matrix*))
      (setq cell "")
      (if dn-entry
        (progn
          (setq entry (assoc r (cdr dn-entry)))
          (if entry
            (setq cell
              (cond
                ((= (type (cdr entry)) 'STR) (cdr entry))          ; 수식 문자열은 그대로
                ((= (cdr entry) 0.0) "")                            ; 합계가 0이면 공란 유지
                (T (matx-fmt-num (cdr entry)))
              )
            )
          )
        )
      )
      (setq line (strcat line "," cell))
    )
    (write-line line f)
    (setq r (1+ r))
  )
  (close f)
  (princ (strcat "\n[MATX] 엑셀 매칭 CSV 저장 완료: " actual-path))
  (princ "\n         (행=엑셀 행번호 8~332 연속, 열=도면번호. 자재수량 시트의 G8 셀에 그대로 붙여넣기 가능)")
)

(princ "\nMATX.lsp 로드 완료. 명령어: MATCAL(캘리브레이션), MATX-VERIFY(검산), MATX(추출)")
(princ)
