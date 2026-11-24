;;; @launcher
;;; 리습: MATX
;;; 분류: 자재 · 수량
;;; 설명: 도엽별 자재내역 표 일괄 추출 → 자재내역 엑셀 자동 작성
;;; 기능: 자재내역 엑셀 자동 작성 | MATX | 모든 도곽의 자재내역 표를 읽어 자재내역_결과.xlsx 생성
;;; 기능: 자재내역 표 위치 보정 | MATCAL | 프로젝트마다 처음 1회, 도곽 하나에서 표 위치 지정
;;; 기능: 도면번호 위치만 다시 보정 | MATCAL-DRWNO | 다른 보정값은 두고 도면번호 위치만 다시 지정
;;; 기능: 보정 위치 미리보기 | MATX-VERIFY | 보정한 좌표를 현재 도곽에 표시해 확인
;;; 설명서:
;;;   도면의 자재내역 표를 도곽별로 읽어 CSV로 모은 뒤, CAD런처.exe 가 바로 자재내역 엑셀 양식을 채워 줍니다.
;;;   (외부 프로그램·파이썬 설치가 필요 없습니다 - CAD런처.exe 안에 매핑 엔진이 들어 있습니다.)
;;;
;;;   [사용 전 확인]
;;;   • 도곽은 FORM 블록 또는 FORM_ 레이어 사각형이어야 합니다.
;;;   • 자재내역 표는 모든 도곽에서 같은 상대 위치에 있어야 합니다 (번호/품명/규격/단위/수량/비고, 최대 20행).
;;;
;;;   [순서]
;;;   1) 새 프로젝트면 '자재내역 표 위치 보정'(MATCAL)을 먼저 1회 실행합니다. 보정값은 도면 폴더의 matx-config.txt 에 저장됩니다.
;;;   2) '자재내역 엑셀 자동 작성'(MATX)을 실행합니다.
;;;   3) 결과는 도면 폴더 안 MATX 폴더에 저장됩니다: material_export.csv, excel_matched.csv → 자재내역_결과.xlsx (생성되면 자동으로 열립니다)
;;;
;;;   ※ 엑셀이 자동으로 안 만들어지면 MATX 폴더의 auto_matx_log.txt 를 확인하세요. (CAD런처가 옛 버전이면 CAD런처 '업데이트 확인'을 먼저 눌러 주세요)
;;;   ※ 도면이 40개 기준 양식(MP-001~011, LP-001~029)보다 많아 새 도면번호가 생기면, 그 열만 자동 반영에서 빠집니다 - excel_matched.csv 를 열어 해당 칸만 수동으로 옮겨 붙이세요.
;;; 기능설명서: MATX
;;;   모든 도곽을 좌측 상단부터 차례로 돌며 자재내역 표를 읽어 CSV 로 모읍니다.
;;;   끝나면 CAD런처.exe 가 자재내역 양식을 채운 '자재내역_결과.xlsx' 를 만들고 자동으로 엽니다.
;;;   • 매핑 규칙: MP/LP 구분, LP 63mm → PE 전자류, S.TEE 부속 자동 계산, 관 수량은 엑셀 수식으로 기록
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
;;; 결과 파일: 도면과 같은 폴더에 material_export.csv 로 누적 저장(append)
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

(defun matx-nth-text-value (pt tol-x-left tol-x-right tol-y / ss i e ed txt best bestd d)
  ;; pt 기준 좌측 tol-x-left, 우측 tol-x-right, 상하 tol-y 반경 내에서
  ;; TEXT/MTEXT/ATTRIB 엔티티 중 기준점에 가장 가까운 것의 문자열과 레이어명을
  ;; 리스트로 반환 (text . layer). 없으면 nil.
  ;; (셀 안의 텍스트가 정렬 방식에 따라 중심이 아니라 셀 왼쪽에 붙어있는 경우가 있어
  ;;  좌우 비대칭 검색을 지원함)
  (setq ss (ssget "_C"
                  (list (- (car pt) tol-x-left) (- (cadr pt) tol-y))
                  (list (+ (car pt) tol-x-right) (+ (cadr pt) tol-y))
                  '((0 . "TEXT,MTEXT,ATTRIB"))
           )
  )
  (setq best nil bestd nil)
  (if ss
    (progn
      (setq i 0)
      (while (< i (sslength ss))
        (setq e (ssname ss i))
        (setq ed (entget e))
        (setq txt (cdr (assoc 1 ed)))
        (if (/= (type txt) 'STR) (setq txt ""))
        (setq d (distance pt (matx-text-position ed)))
        (if (or (null bestd) (< d bestd))
          (progn (setq bestd d) (setq best (cons txt (cdr (assoc 8 ed)))))
        )
        (setq i (1+ i))
      )
    )
  )
  best
)

;; ---------- 도곽 수집 (FORM 블록 우선, 없으면 FORM_ 레이어 폴리라인) ----------
(defun matx-collect-frames (/ ss i e ed name frames pt)
  (setq frames '())
  ;; 1) FORM 블록 INSERT 우선
  (setq ss (ssget "_X" '((0 . "INSERT") (2 . "FORM"))))
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
  ;; 2) FORM 블록이 하나도 없으면 FORM_ 레이어의 폴리라인 바운딩박스 좌하단 사용
  (if (null frames)
    (progn
      (setq ss (ssget "_X" '((0 . "LWPOLYLINE") (8 . "FORM_"))))
      (if ss
        (progn
          (setq i 0)
          (while (< i (sslength ss))
            (setq e (ssname ss i))
            (setq pt (matx-bbox-bl e))
            (setq frames (cons (list pt e) frames))
            (setq i (1+ i))
          )
        )
      )
    )
  )
  (matx-dedupe-frames frames)
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

;; ---------- 도면번호 추출: 도곽 내부 텍스트 중 (MP|LP)-### 패턴 검색 ----------
(defun matx-find-pattern-in-box (c1 c2 ref-pt / ss i e ed txt result all-found d bestd match)
  ;; c1~c2 사각형 범위의 모든 TEXT/MTEXT/ATTRIB 중 MP-###/LP-### 패턴에 맞는 것들을 찾아서
  ;; ref-pt에서 가장 가까운 것 하나를 고름 (첫 번째로 찾은 게 아니라 최근접 후보를 선택 -
  ;; 넓은 범위를 훑을 때 엉뚱한 곳의 패턴 텍스트를 잘못 집어오는 걸 방지)
  ;; 반환: (result . all-found-texts)  result가 nil이면 못 찾은 것, all-found-texts는 진단용
  (setq result nil bestd nil all-found '())
  (setq ss (ssget "_C" c1 c2 '((0 . "TEXT,MTEXT,ATTRIB"))))
  (if ss
    (progn
      (setq i 0)
      (while (< i (sslength ss))
        (setq e (ssname ss i))
        (setq ed (entget e))
        (setq txt (cdr (assoc 1 ed)))
        (if (and txt (= (type txt) 'STR))
          (progn
            (setq all-found (cons txt all-found))
            (setq match (matx-regex-mp-lp txt))
          )
          (setq match nil)
        )
        (if match
          (progn
            (setq d (distance ref-pt (matx-text-position ed)))
            (if (or (null bestd) (< d bestd))
              (progn (setq bestd d) (setq result match))
            )
          )
        )
        (setq i (1+ i))
      )
    )
  )
  (cons result all-found)
)

(defun matx-find-pattern-in-window (pt tol)
  ;; pt 중심 정사각(tol 반경) 범위에서 pt와 가장 가까운 패턴 매칭 텍스트를 찾음
  (matx-find-pattern-in-box
    (list (- (car pt) tol) (- (cadr pt) tol))
    (list (+ (car pt) tol) (+ (cadr pt) tol))
    pt
  )
)

(defun matx-find-drawing-no (origin size cfg tol / ss i e ed txt result pt search-result found-texts)
  (setq result nil)

  ;; 1) 캘리브레이션된 도면번호 위치 근처에서 패턴 매칭 우선 탐색
  (if (and cfg (assoc 'DRWNODX cfg) (assoc 'DRWNODY cfg))
    (progn
      (setq pt
        (list
          (+ (car origin) (cdr (assoc 'DRWNODX cfg)))
          (+ (cadr origin) (cdr (assoc 'DRWNODY cfg)))
        )
      )
      (princ (strcat "\n  [디버그] 원점=(" (rtos (car origin) 2 3) "," (rtos (cadr origin) 2 3) ")"
                     " DRWNODX=" (rtos (cdr (assoc 'DRWNODX cfg)) 2 3)
                     " DRWNODY=" (rtos (cdr (assoc 'DRWNODY cfg)) 2 3)
                     " pt=(" (rtos (car pt) 2 3) "," (rtos (cadr pt) 2 3) ")"))
      ;; 도면번호 주변엔 다른 텍스트(설계/확인/성명 등)도 몰려있을 수 있어 반경을 넉넉히 확보
      (setq search-result (matx-find-pattern-in-window pt (max tol 20.0)))
      (setq result (car search-result))
      (setq found-texts (cdr search-result))
    )
  )

  ;; 2) 못 찾았으면 캘리브레이션 지점(pt) 기준으로 더 넓게(150mm) 재탐색.
  ;;    원점 기준 박스로 하면 도면번호가 원점보다 음수 방향에 있는 경우 아예 범위 밖으로
  ;;    벗어나는 문제가 있어서, pt는 이미 방향까지 올바르게 반영된 값이므로 pt를 그대로 씀.
  ;;    150mm는 옆 도곽(간격 약 447 이상)보다 훨씬 작아 침범 위험 없음.
  (if (and (null result) pt)
    (progn
      (setq search-result (matx-find-pattern-in-window pt 150.0))
      (setq result (car search-result))
      (if (cdr search-result) (setq found-texts (cdr search-result)))
    )
  )

  ;; 3) 그래도 못 찾았으면 진단용으로 캘리브레이션 지점 근처에서 실제로 발견된 텍스트를 출력
  (if (and (null result) found-texts)
    (progn
      (princ "\n      [진단] 도면번호 예상위치 근처에서 발견된 텍스트(패턴 불일치): ")
      (foreach ft found-texts
        (if (= (type ft) 'STR)
          (princ (strcat "'" ft "' "))
          (princ (strcat "[비문자값:" (vl-princ-to-string ft) "] "))
        )
      )
    )
  )
  (if (and (null result) (null found-texts))
    (princ "\n      [진단] 도면번호 예상위치 근처에서 텍스트를 아예 찾지 못함(반경/좌표 문제 가능성)")
  )

  result
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
          (setq digits (strcat prefix digits))
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
  (matx-text-position ed)
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

(defun matx-consec-diffs (lst / result i)
  (setq result '())
  (setq i 0)
  (while (< i (1- (length lst)))
    (setq result (cons (abs (- (nth (1+ i) lst) (nth i lst))) result))
    (setq i (1+ i))
  )
  result
)

(defun matx-min-positive (lst / m)
  (setq m nil)
  (foreach v lst
    (if (and (> v 0.0) (or (null m) (< v m)))
      (setq m v)
    )
  )
  (if m m 5.0) ; 값이 하나도 없으면 기본 5mm
)

(defun matx-apply-strict (lst strict-idxs strict-val / result i)
  ;; 특정 열 인덱스(strict-idxs)만 아주 좁은 값(strict-val)으로 강제 교체.
  ;; 규격/수량처럼 원래 비어있는 경우가 많은 열은, 자기 칸에 텍스트가 없으면
  ;; 무리하게 이웃 행/열까지 찾아가지 말고 그냥 빈 값으로 남도록 하기 위함.
  (setq result '())
  (setq i 0)
  (foreach v lst
    (setq result (cons (if (member i strict-idxs) strict-val v) result))
    (setq i (1+ i))
  )
  (reverse result)
)

(defun matx-col-left-tols (coldx-list default-tol / gaps result i)
  ;; 각 열의 왼쪽 확장 반경을 "바로 왼쪽 열과의 실제 간격의 45%"로 계산 (첫 열은 default-tol).
  ;; 이렇게 하면 왼쪽 열의 텍스트를 절대 침범하지 않으면서도, 셀 안에서 왼쪽으로 치우친
  ;; 텍스트는 넉넉히 잡을 수 있음.
  (setq gaps (matx-consec-diffs coldx-list))
  (setq result (list default-tol)) ; 첫 열(번호)은 왼쪽 이웃이 없으므로 기본값
  (setq i 0)
  (while (< i (length gaps))
    (setq result (cons (* 0.45 (nth i gaps)) result))
    (setq i (1+ i))
  )
  (reverse result)
)

(defun matx-list-to-str (lst / s)
  (setq s "")
  (foreach v lst (setq s (strcat s (rtos v 2 2) " ")))
  s
)

;; ============================================================
;; MATX - 전체 도곽 순회 추출
;; ============================================================
(defun c:MATX (/ cfg frames sorted-frames idx fr origin drawing-no
                 row rowno colnames vals cell-txt csv-path csv-primary
                 csv-fallback csv-mode open-result f
                 has-any-value tol strict-tol tol-left-list tol-right-list tol-y-list colidx
                 drawing-rows-acc matx-mc-err)
  (if (not (matx-load-config))
    (progn (princ "\n[MATX] 캘리브레이션 정보가 없습니다. 먼저 MATCAL을 실행하세요.") (exit))
  )
  ;; 대용량 도면에서 ssget이 화면에 인식되지 않은 먼 영역을 놓치는 걸 방지하기 위해
  ;; 전체 도면을 한번 펼쳐서 인식시킴
  (command "_.ZOOM" "_Extents")
  (princ "\n[MATX] 전체 도면 인식을 위해 화면을 펼쳤습니다.")
  (setq *matx-excel-matrix* nil)
  (setq cfg *matx-config*)
  (setq colnames '("번호" "품명" "규격" "단위" "수량" "비고"))
  ;; 검색 반경은 행간격/열간격보다 작아야 인접 셀 텍스트를 잘못 줍지 않음
  (setq tol (* 0.4 (matx-min-positive
                      (cons (abs (cdr (assoc 'ROWPITCH cfg)))
                            (matx-consec-diffs (cdr (assoc 'COLDX cfg))))
                    )
             )
  )
  ;; 셀 텍스트가 정렬 방식에 따라 셀 중앙이 아니라 왼쪽에 붙어있는 경우가 있어
  ;; 왼쪽 방향으로는 더 넉넉하게 검색 - 단, 규격(idx 2)/수량(idx 4)/비고(idx 5)는 원래 빈
  ;; 경우가 많아 무리하게 이웃 행/열까지 찾아가지 않도록 좁게 강제 고정.
  ;; 반경은 행 높이(ROWPITCH)의 25%로 계산 - 행 높이 절반보다 충분히 작아서
  ;; 위/아래 행을 절대 침범하지 않음
  (setq strict-tol (* 0.25 (abs (cdr (assoc 'ROWPITCH cfg)))))
  (setq tol-left-list
    (matx-apply-strict (matx-col-left-tols (cdr (assoc 'COLDX cfg)) tol) '(2 4 5) strict-tol)
  )
  (setq tol-right-list (matx-apply-strict (list tol tol tol tol tol tol) '(2 4 5) strict-tol))
  ;; Y축(상하)은 어느 열이든 위/아래 행을 침범하면 안 되므로 전체 열 공통으로 좁게 고정
  (setq tol-y-list (list strict-tol strict-tol strict-tol strict-tol strict-tol strict-tol))
  (princ (strcat "\n[MATX] 텍스트 검색 반경(tol) = " (rtos tol 2 3)
                 "mm, 규격/수량/비고 반경(strict-tol) = " (rtos strict-tol 2 3)
                 "mm (열별 좌측 확장: " (matx-list-to-str tol-left-list) "mm)"))

  (setq frames (matx-collect-frames))
  (if (null frames)
    (progn (princ "\n[MATX] FORM 블록/FORM_ 레이어 도곽을 찾지 못했습니다.") (exit))
  )
  (setq sorted-frames (matx-sort-frames frames))
  (princ (strcat "\n[MATX] 도곽 " (itoa (length sorted-frames)) "개 발견. 처리 시작..."))

  (setq csv-primary (strcat (matx-output-dir) "material_export.csv"))
  (setq csv-fallback (strcat (matx-temp-dir) "MATX\\material_export.csv"))
  (setq csv-mode "w") ; 매번 새로 덮어씀 - 이전 실행 결과가 계속 쌓여 중복되는 걸 방지
  (setq open-result (matx-safe-open csv-primary csv-mode))
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
  (if (or (null (vl-file-size csv-path)) (= (vl-file-size csv-path) 0))
    (write-line "도면번호,번호,품명,규격,단위,수량,비고" f)
  )

  (setq idx 0)
  (foreach fr sorted-frames
    (setq origin (car fr))
    (setq drawing-no (matx-find-drawing-no origin (list 390.0 270.0) cfg tol)) ; 실제 도곽(396.9x273.98)보다 살짝 작게 - 이웃 도곽 침범 방지
    (if (null drawing-no)
      (progn
        (matx-log (strcat "도곽 #" (itoa idx) " 도면번호 인식 실패 - 스킵"))
        (princ (strcat "\n  [경고] 도곽 #" (itoa idx) " 도면번호를 찾지 못해 스킵합니다."))
      )
      (progn
        (princ (strcat "\n  처리중: " drawing-no))
        (setq drawing-rows-acc '())
        (setq row 0)
        (while (< row (cdr (assoc 'MAXROWS cfg)))
          (setq rowno (- (cdr (assoc 'MAXROWS cfg)) row)) ; 맨 위=20, 아래로 갈수록 감소, 1행이 제일 아래
          (setq vals '())
          (setq has-any-value nil)
          (setq colidx 0)
          (foreach dx (cdr (assoc 'COLDX cfg))
            (setq cell-txt
              (matx-nth-text-value
                (list
                  (+ (car origin) dx)
                  (+ (cadr origin) (cdr (assoc 'ROW1DY cfg)) (* row (cdr (assoc 'ROWPITCH cfg))))
                )
                (nth colidx tol-left-list)   ; 이 열의 왼쪽 확장
                (nth colidx tol-right-list)  ; 이 열의 오른쪽 확장
                (nth colidx tol-y-list)      ; 이 열의 상하 확장
              )
            )
            (setq vals (cons (if cell-txt (car cell-txt) "") vals))
            (if (and cell-txt (/= (car cell-txt) "")) (setq has-any-value T))
            (setq colidx (1+ colidx))
          )
          (setq vals (reverse vals))
          ;; vals = (번호 품명 규격 단위 수량 비고)
          (if (and has-any-value (/= (car vals) ""))
            (progn
              (write-line
                (strcat
                  drawing-no "," (nth 0 vals) "," (matx-csv-esc (nth 1 vals)) ","
                  (matx-csv-esc (nth 2 vals)) "," (nth 3 vals) "," (nth 4 vals) ","
                  (matx-csv-esc (nth 5 vals))
                )
                f
              )
              ;; 엑셀 매칭용으로도 같은 행 데이터를 누적
              (setq drawing-rows-acc (cons vals drawing-rows-acc))
            )
          )
          (setq row (1+ row))
        )
        ;; 이 도면의 20행을 다 훑었으면, 엑셀 매칭 규칙을 적용해서 결과 누적
        (setq *matx-excel-matrix*
          (cons
            (cons drawing-no (matx-classify-drawing drawing-no (reverse drawing-rows-acc)))
            *matx-excel-matrix*
          )
        )
      )
    )
    (setq idx (1+ idx))
  )
  (close f)
  (matx-log (strcat "MATX 완료: 도곽 " (itoa (length sorted-frames)) "개 처리, 결과 -> " csv-path))
  (princ (strcat "\n[MATX] 완료. 결과 파일: " csv-path))

  ;; 리습 안에 포팅된 매칭 규칙으로 엑셀 위치에 맞춘 CSV도 바로 생성 (파이썬 단계 불필요)
  (if (vl-catch-all-error-p (setq matx-mc-err (vl-catch-all-apply 'matx-write-matched-csv nil)))
    (progn
      (princ "\n[MATX] 오류: 엑셀 매칭 CSV 생성 중 문제가 발생했습니다:")
      (princ (strcat "\n  " (vl-catch-all-error-message matx-mc-err)))
    )
  )

  ;; excel_matched.csv 가 준비되면 CAD런처.exe 자신을 불러서 자재내역.xlsx 양식에 채워 넣고
  ;; 바로 엑셀로 연다 (CAD런처 실행 때마다 (setq *CADLAUNCHER-EXE* ...) 로 경로를 받아둠).
  ;; LT 버전에 따라 startapp이 제한될 수 있어, 실패해도 CSV 추출 결과에는 영향 없도록 안전하게 처리.
  (if (and (boundp '*CADLAUNCHER-EXE*) *CADLAUNCHER-EXE* (findfile *CADLAUNCHER-EXE*))
    (progn
      (princ "\n[MATX] CAD런처.exe 로 엑셀 자동 생성을 시도합니다...")
      (if (vl-catch-all-error-p
            (vl-catch-all-apply 'startapp
              (list *CADLAUNCHER-EXE* (strcat "--matx-fill " (matx-quote-arg (matx-output-dir)))))
          )
        (princ "\n[MATX] 자동 실행에 실패했습니다(LT 제한 가능성). CAD런처를 열고 아무 기능이나 한 번 실행한 뒤 MATX를 다시 실행해 보세요.")
        (princ "\n[MATX] 자동 실행을 시도했습니다. 완료되면 MATX 폴더의 auto_matx_log.txt를 확인하세요.")
      )
    )
    (princ "\n[MATX] CAD런처.exe 경로를 몰라 엑셀 자동 생성을 건너뜁니다. (CAD런처에서 아무 기능이나 한 번 실행한 뒤 다시 시도하거나, excel_matched.csv 를 자재내역.xlsx 의 G8 셀에 직접 붙여넣으세요)")
  )
  (princ)
)

(defun matx-csv-esc (s)
  ;; 콤마/따옴표 포함 시 CSV 이스케이프
  (if (or (vl-string-search "," s) (vl-string-search "\"" s))
    (strcat "\"" (vl-string-subst "\"\"" "\"" s) "\"")
    s
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

(defun matx-classify (raw-name / key found bucket pair)
  (setq key (matx-norm2 raw-name))
  (setq bucket nil)
  (if (/= key "")
    (progn
      (setq found (assoc key MATX-NAME-TABLE))
      (if found
        (setq bucket (cdr found))
        (foreach pair MATX-NAME-TABLE
          (if (and (null bucket)
                   (or (vl-string-search (car pair) key) (vl-string-search key (car pair))))
            (setq bucket (cdr pair))
          )
        )
      )
    )
  )
  bucket
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
                               result pipe-alist entry vals-list qsum
                               lp300-list stee-main stee-count)
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
      (setq steel (matx-is-steel-remark remark))

      (cond
        ;; ---------------- PIPE ----------------
        ((= bucket "PIPE")
         (setq dia (matx-all-numbers spec))
         (if dia
           (if (and (= pressure "LP") steel)
             (if (= (car dia) 300)
               (setq lp300-list (cons qty lp300-list))
               (matx-log (strcat "[매칭] " drawing-no " LP/PLP " (itoa (car dia)) "A - 300A 외 예외 규칙 없음"))
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
        )

        ;; ---------------- ELBOW ----------------
        ((= bucket "ELBOW")
         (setq dia (matx-all-numbers spec))
         (if dia
           (progn
             (if (= (car dia) 63)
               (setq row-num (matx-lookup1 ROW-DIANJA-ELBOW 63))
               (progn
                 (setq angle (matx-extract-angle name))
                 (setq table (if (or steel (= pressure "MP")) ROW-STEEL-ELBOW ROW-PE-ELBOW))
                 (setq row-num (if angle (matx-lookup2 table (car dia) angle) nil))
               )
             )
             (if row-num
               (matx-acc result row-num qty)
               (matx-log (strcat "[매칭] " drawing-no " ELBOW " spec " - 해당 규격 없음"))
             )
           )
         )
        )

        ;; ---------------- STEE (새들/서비스 티) ----------------
        ((= bucket "STEE")
         (if (= pressure "MP")
           (progn
             ;; MP의 S.TEE는 스토팍류 수량 계산에 사용 (자재 자체는 무시)
             (setq dia (matx-all-numbers spec))
             (if dia
               (progn
                 (setq stee-main (car dia))
                 (setq stee-count (matx-ceil-div stee-main 100))
                 (setq result (matx-acc result ROW-STOPOK-CZ stee-count))
                 (setq result (matx-acc result ROW-STOPOK-4100 (+ stee-count 1)))
                 (setq result (matx-acc result ROW-PVC-TAPE stee-count))
               )
             )
           )
           (progn
             (setq dia (matx-all-numbers spec))
             (if (>= (length dia) 2)
               (progn
                 (setq row-num (matx-lookup2 ROW-ST (nth 0 dia) (nth 1 dia)))
                 (if row-num
                   (setq result (matx-acc result row-num qty))
                   (matx-log (strcat "[매칭] " drawing-no " S.TEE " spec " - S/T표에 해당 규격 없음"))
                 )
               )
             )
           )
         )
        )

        ;; ---------------- TEE / RD ----------------
        ((or (= bucket "TEE") (= bucket "RD"))
         (setq dia (matx-all-numbers spec))
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
             (if row-num
               (setq result (matx-acc result row-num qty))
               (matx-log (strcat "[매칭] " drawing-no " " bucket " " spec " - 해당 규격 없음"))
             )
           )
         )
        )

        ;; ---------------- CAP ----------------
        ((= bucket "CAP")
         (setq dia (matx-all-numbers spec))
         (if dia
           (progn
             (if (= (car dia) 63)
               (setq row-num (matx-lookup1 ROW-DIANJA-CAP 63))
               (progn
                 (setq table (if (or steel (= pressure "MP")) ROW-STEEL-CAP ROW-PE-CAP))
                 (setq row-num (matx-lookup1 table (car dia)))
               )
             )
             (if row-num
               (setq result (matx-acc result row-num qty))
               (matx-log (strcat "[매칭] " drawing-no " CAP " spec " - 해당 규격 없음"))
             )
           )
         )
        )

        ;; ---------------- VALVE ----------------
        ((= bucket "VALVE")
         (setq dia (matx-all-numbers spec))
         (if dia
           (progn
             (setq table (if (= pressure "MP") ROW-VALVE-2P ROW-PE-VALVE))
             (setq row-num (matx-lookup1 table (car dia)))
             (if row-num
               (setq result (matx-acc result row-num qty))
               (matx-log (strcat "[매칭] " drawing-no " VALVE " spec " - 해당 규격(2P) 없음"))
             )
           )
         )
        )

        ;; ---------------- ANODE / TESTBOX / SIGNBOARD / LINEMARK / TF ----------------
        ((= bucket "ANODE")
         (setq result (matx-acc result ROW-MG-ANODE-N qty))
        )
        ((= bucket "TESTBOX")
         (setq result (matx-acc result ROW-TEST-BOX-N qty))
        )
        ((= bucket "SIGNBOARD")
         (setq result (matx-acc result ROW-SIGNBOARD-N qty))
        )
        ((= bucket "LINEMARK")
         (setq result (matx-acc result ROW-LINE-MARK-N qty))
        )
        ((= bucket "TF")
         (setq dia (matx-all-numbers spec))
         (if dia
           (progn
             (setq table
               (cond
                 ((/= (vl-string-search "LONG" (strcase remark)) nil) ROW-TF-LONG)
                 (T ROW-TF-SHORT)
               )
             )
             (setq row-num (matx-lookup1 table (car dia)))
             (if row-num
               (setq result (matx-acc result row-num qty))
               (matx-log (strcat "[매칭] " drawing-no " T/F " spec " - 해당 규격 없음"))
             )
           )
         )
        )
      ) ; cond 끝
    ) ; foreach row 끝
  )

  ;; 파이프 합산 결과를 result에 반영 (여러 값이면 수식 문자열, 하나면 숫자)
  (if pressure
    (progn
      (foreach entry pipe-alist
        (setq table (if (= pressure "MP") ROW-PLP-PIPE ROW-PE-PIPE))
        (setq row-num (matx-lookup1 table (car entry)))
        (if row-num
          (setq result (matx-acc-values result row-num (cdr entry)))
          (matx-log (strcat "[매칭] " drawing-no " 파이프 " (itoa (car entry)) "A - 해당 관경 없음"))
        )
      )
      (if lp300-list
        (setq result (matx-acc-values result ROW-LP-PLP-PIPE300-N lp300-list))
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

(defun matx-fmt-num (v)
  (if (= v (atoi (rtos v 2 0)))
    (rtos v 2 0)
    (rtos v 2 4)
  )
)

(defun matx-ceil-div (a b / q)
  (setq q (/ (float a) (float b)))
  (if (= q (fix q)) (fix q) (1+ (fix q)))
)

(defun matx-str-to-real (s / n)
  (if (or (null s) (= s ""))
    0.0
    (progn
      (setq n (atof s))
      n
    )
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
