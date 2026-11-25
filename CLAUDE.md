# cad-launcher 작업 규칙 (Claude용)

AutoCAD LT 2026 리습 런처. 각 PC의 CAD런처.exe 가 실행 때마다 이 저장소(main)에서
`lsp/`, `catalog.json`, `CAD런처.exe`, `README.md` 변경분을 자동으로 받는다. 공개 저장소이므로 도면·개인정보·토큰은 올리지 않는다.

## 목록 구조 (catalog.json v2)
- `lisps[]`: id, file(lsp/파일.lsp), desc, manual(공통 안내), tools(외부 프로그램)
- `categories[].items[]`: name(짧은 한국어 기능 이름), desc, lisp(id), command, manual, options
- 런처 목록 표시: `기능 이름   (리습 · 명령어)`

## 새 리습 추가 (토큰 절약: catalog.json 을 직접 읽거나 손으로 고치지 말 것)
1. 리습 맨 위에 @launcher 머리말 작성 (형식은 dev/register.py 맨 위 설명). 기능 이름은 짧은 한국어.
2. `lsp/파일.lsp` 저장 → `python dev/register.py lsp/파일.lsp` → `python dev/catalog_xlsx.py export`
3. 외부 프로그램 설치 파일은 `tools/이름.zip` (50MB 이상은 GitHub Release 주소). 리습이 고정 경로(예: C:\MATX-Tools)를 쓰면 머리말 8번째 칸 '설치폴더'에 그 경로를 적는다.
   엑셀 양식 등을 올리기 전에는 작성자(docProps)·외부 연결·공사명 등 회사/개인 정보를 반드시 지운다 (공개 저장소).
4. 커밋(한국어 짧게) → `git -c push.negotiate=true push origin main`

## 사용자가 엑셀을 올렸을 때
`python dev/catalog_xlsx.py import 올린파일.xlsx` → 오류가 나오면 행 번호를 사용자에게 전달 → 성공하면 `export` 로 dev/catalog.xlsx 갱신 → 커밋·push

## 대화로 고쳐 달라고 할 때 ("○○ 이름을 △△로")
catalog.json 에서 해당 항목만 python 한두 줄로 수정 → `export` → 커밋·push

## 런처 코드 (src/, Go 표준 라이브러리 + Win32, 외부 라이브러리 없음)
`cd src && GOOS=windows GOARCH=amd64 go build -ldflags "-H windowsgui -s -w" -o ../CAD런처.exe .`
코드를 안 바꿨으면 exe 를 다시 빌드하지 않는다. Windows에서 실행 테스트는 못 하므로 사용자에게 확인을 부탁한다.

## 네이티브 우선 (src/ = CAD런처.exe)
- 런처 코드 작업은 항상 네이티브 버전(src/)에만 한다. WebView2 버전(src-modern/, CAD런처-WebView2.exe)은 사용자가 요청할 때만 고친다.
- `src-native2/` (CAD런처-네이티브2.exe) 는 디자인 테스트판(새 디자인은 style2.go). 사용자가 요청할 때만 고친다. 자기 exe 만 자동 업데이트하고 CAD런처.exe 는 건드리지 않는다.
  빌드: `cd src-native2 && GOOS=windows GOARCH=amd64 go build -ldflags "-H windowsgui -s -w" -o ../CAD런처-네이티브2.exe .`
- 리습(lsp/)·catalog.json 은 두 버전이 함께 받으므로 평소대로 고치면 된다.
- 기능 차이(예: MATX/PAVQ 엑셀 자동 작성은 네이티브에만 있음)를 사용자에게 설명할 때만 WebView2 를 언급한다.
- 대화와 중간 진행 메시지는 모두 한국어로 쓴다.
- 사용자가 "왜 ~해?" 처럼 이유를 물으면 리습·코드를 고치지 말고 원인 분석만 먼저 답한다. 수정은 사용자가 요청할 때만 한다.
