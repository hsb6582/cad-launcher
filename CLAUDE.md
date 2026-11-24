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
