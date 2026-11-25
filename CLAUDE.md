# cad-launcher 작업 규칙 (Claude용)

AutoCAD LT 2026 리습 런처. 각 PC의 CAD런처.exe 가 실행 때마다 이 저장소(main)에서
`lsp/`, `catalog.json`, `CAD런처.exe`, `README.md` 변경분을 자동으로 받는다. 공개 저장소이므로 도면·개인정보·토큰은 올리지 않는다.

## 브랜치: dev = 테스트, main = 배포 (가장 중요)
- 평소 모든 작업은 `dev` 브랜치에 커밋하고 `git -c push.negotiate=true push origin dev` 로 올린다. 사용자의 테스트용 런처(CAD런처-테스트.exe)만 dev 를 받는다.
- `main` 은 모든 PC가 받는 배포용이다. 사용자가 "배포해줘"처럼 분명히 지시할 때만 바꾼다. 그 전에는 main 에 push 하지 않는다.
- 배포 절차: dev 를 main 에 merge → main 에서 배포용 exe 빌드(아래 '배포용') → 커밋·`push origin main` → main 을 다시 dev 에 merge 해서 두 브랜치를 맞춘다.

## 목록 구조 (catalog.json v2)
- `lisps[]`: id, file(lsp/파일.lsp), desc, manual(공통 안내), tools(외부 프로그램)
- `categories[].items[]`: name(짧은 한국어 기능 이름), desc, lisp(id), command, manual, options
  - 간단 설명서(선택): when(언제 쓰나 한 줄), steps[](사용 순서), warn(주의), before/after(실행 전·후 그림 `lsp/img/명령어_before.png`·`_after.png`).
    하나라도 있으면 네이티브 런처 설명서 칸이 간단 버전으로 바뀌고 manual 은 '자세한 설명 보기'에 접힌다. 그림은 600×340 정도 PNG, 공개 저장소이므로 실제 도면 캡처는 정보를 지운 뒤 올린다.
  - recommend(선택, true): 런처 목록에서 이름 앞에 엄지척 추천 아이콘 (아이콘은 exe 안 src/assets/thumb_*.png). 엑셀 '추천' 칸에 O.
- 런처 목록 표시: `기능 이름   (리습 · 명령어)`

## 새 리습 추가 (토큰 절약: catalog.json 을 직접 읽거나 손으로 고치지 말 것)
1. 리습 맨 위에 @launcher 머리말 작성 (형식은 dev/register.py 맨 위 설명). 기능 이름은 짧은 한국어.
2. `lsp/파일.lsp` 저장 → `python dev/register.py lsp/파일.lsp` → `python dev/catalog_xlsx.py export`
3. 외부 프로그램 설치 파일은 `tools/이름.zip` (50MB 이상은 GitHub Release 주소). 리습이 고정 경로(예: C:\MATX-Tools)를 쓰면 머리말 8번째 칸 '설치폴더'에 그 경로를 적는다.
   엑셀 양식 등을 올리기 전에는 작성자(docProps)·외부 연결·공사명 등 회사/개인 정보를 반드시 지운다 (공개 저장소).
4. 커밋(한국어 짧게) → `git -c push.negotiate=true push origin dev` (배포 지시 전까지 main 금지)

## 사용자가 엑셀을 올렸을 때
`python dev/catalog_xlsx.py import 올린파일.xlsx` → 오류가 나오면 행 번호를 사용자에게 전달 → 성공하면 `export` 로 dev/catalog.xlsx 갱신 → 커밋·push

## 대화로 고쳐 달라고 할 때 ("○○ 이름을 △△로")
catalog.json 에서 해당 항목만 python 한두 줄로 수정 → `export` → 커밋·push

## 런처 코드 (src/, Go 표준 라이브러리 + Win32, 외부 라이브러리 없음)
- 테스트용 (dev 에서 평소): `cd src && GOOS=windows GOARCH=amd64 go build -ldflags "-H windowsgui -s -w -X main.fixedBranch=dev -X main.exeRepoName=CAD런처-테스트.exe" -o ../CAD런처-테스트.exe .`
- 배포용 (배포 지시 때 main 에서만): `cd src && GOOS=windows GOARCH=amd64 go build -ldflags "-H windowsgui -s -w" -o ../CAD런처.exe .`
- dev 에서는 CAD런처.exe(배포용)를 다시 빌드하지 않는다. 코드를 안 바꿨으면 exe 를 다시 빌드하지 않는다. Windows에서 실행 테스트는 못 하므로 사용자에게 확인을 부탁한다.

## 네이티브 우선 (src/ = CAD런처.exe)
- 런처 코드 작업은 항상 네이티브 버전(src/)에만 한다. WebView2 버전(src-modern/, CAD런처-WebView2.exe)은 사용자가 요청할 때만 고친다.
- 리습(lsp/)·catalog.json 은 두 버전이 함께 받으므로 평소대로 고치면 된다.
- 기능 차이(예: MATX/PAVQ 엑셀 자동 작성은 네이티브에만 있음)를 사용자에게 설명할 때만 WebView2 를 언급한다.
- 대화와 중간 진행 메시지는 모두 한국어로 쓴다.
- 사용자가 "왜 ~해?" 처럼 이유를 물으면 리습·코드를 고치지 말고 원인 분석만 먼저 답한다. 수정은 사용자가 요청할 때만 한다.
