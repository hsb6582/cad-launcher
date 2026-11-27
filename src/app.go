// CAD 런처 - AutoCAD LT 2026 리습 실행 / 옵션 조정 / 설명서 / GitHub 자동 업데이트
// 외부 라이브러리 없이 Win32 API 직접 사용 (Go 표준 라이브러리만)
// 빌드: GOOS=windows GOARCH=amd64 go build -ldflags "-H windowsgui -s -w" -o 전자제도_도우미.exe
package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"syscall"
	"time"
	"unicode/utf16"
	"unsafe"
)

var exeRepoName = "전자제도_도우미.exe" // 저장소 안의 프로그램 파일 이름 (테스트용은 빌드 때 전자제도_도우미-테스트.exe 로 바꿈)

// ───────────────────────── 상태 ─────────────────────────
type State struct {
	Keyword    string                            `json:"keyword"`
	Method     string                            `json:"method"`
	Encoding   string                            `json:"encoding"`
	Cancel     bool                              `json:"cancel"`
	Topmost    bool                              `json:"topmost"`
	Values     map[string]map[string]interface{} `json:"values"`
	AutoUpdate bool                              `json:"autoUpdate"`
	Token      string                            `json:"token,omitempty"`
	Synced     map[string]string                 `json:"synced,omitempty"`
	Installed  map[string]string                 `json:"installed,omitempty"`  // 외부 프로그램 이름 → 설치한 버전
	LeftW      int                               `json:"leftW,omitempty"`      // 목록 칸 폭
	Order      map[string][]string               `json:"order,omitempty"`      // 이 PC에서 바꾼 목록 순서
	Favorites  []string                          `json:"favorites,omitempty"`  // 즐겨찾기 기능 (리습|명령어, favorites.go)
	Startup    []string                          `json:"startup,omitempty"`    // 시작하기 세트로 모든 도면에 자동 로드할 리습 id
	FontLevel  int                               `json:"fontLevel,omitempty"`  // 글자 크기 1~5단계 (0 = 기본 3단계, 설정 창)
	Theme      string                            `json:"theme,omitempty"`      // 화면 색상: dark(기본)/cream/slate (theme.go, 전구 버튼)
	Trust      string                            `json:"trust,omitempty"`      // AutoCAD 신뢰 위치 자동 추가: ""(아직 안 물음)/"yes"/"no" (trust.go)
	LastUpdate string                            `json:"lastUpdate,omitempty"` // 이 PC가 마지막으로 파일을 내려받은 시각 (RFC3339)
	LastCheck  string                            `json:"lastCheck,omitempty"`  // 마지막으로 업데이트를 확인한 시각
	GitHubDate string                            `json:"githubDate,omitempty"` // 마지막 확인 때 본 GitHub 브랜치의 마지막 변경 시각
	LogOpen    bool                              `json:"logOpen,omitempty"`    // 아래 실행 기록 칸을 펼쳐 둠
}

var (
	appDir, catalogPath, statePath, optPath, lspDir, exePath string
	st                                                       State
)

func loadState() {
	st = State{Keyword: "AutoCAD LT", Method: "WM_COPYDATA", Encoding: "cp949", Cancel: true, AutoUpdate: true}
	if b, err := os.ReadFile(statePath); err == nil {
		_ = json.Unmarshal(b, &st)
	}
	if st.Values == nil {
		st.Values = map[string]map[string]interface{}{}
	}
	if st.Synced == nil {
		st.Synced = map[string]string{}
	}
	if st.Installed == nil {
		st.Installed = map[string]string{}
	}
}

func saveState() {
	if b, err := json.MarshalIndent(st, "", "  "); err == nil {
		_ = os.WriteFile(statePath, b, 0644)
	}
}

type kv struct{ k, v string }

func writeOptFile(id string, vals []kv) error {
	lines := []string{"_CMD=" + id}
	for _, p := range vals {
		v := strings.NewReplacer("\r", " ", "\n", " ").Replace(p.v)
		lines = append(lines, p.k+"="+v)
	}
	content := strings.Join(lines, "\r\n") + "\r\n"
	var b []byte
	if st.Encoding == "utf-8" {
		b = []byte(content)
	} else {
		b = toCP949(content)
	}
	return os.WriteFile(optPath, b, 0644)
}

func absPath(p string) string {
	if p == "" || filepath.IsAbs(p) {
		return p
	}
	return filepath.Join(appDir, filepath.FromSlash(p))
}

func lispPath(p string) string { return strings.ReplaceAll(filepath.Clean(absPath(p)), "\\", "/") }

// ───────────────────────── GUI ─────────────────────────
const (
	idKeyword = 100 + iota
	idFind
	idWinCombo
	idUpdate
	idAdvanced
	idList
	idAddCat
	idAddLisp
	idAddCmd
	idEdit
	idDel
	idUp
	idDown
	idRun
	idReset
	idLog
	idManual
	idTools
	idStartup
	idLogToggle
	idOptBase    = 1000
	idBrowseBase = 2000
)

// 설정 창(dialogs.go의 advancedDialog) 안에서만 쓰는 컨트롤 id
const (
	idAdvMethod = 500 + iota
	idAdvCancel
	idAdvTop
	idAdvEnc
	idAdvSend
	idAdvAuto
	idAdvTrust
	idThemeBtn
	idFav
	idAdvKw
	idAdvFont
	idAdvToken
)

const WM_APP_UPDATE = 0x8001
const WM_APP_TOOLS = 0x8002

var methods = []string{"WM_COPYDATA", "키입력"}
var encodings = []string{"cp949", "utf-8"}

var (
	hInst, hMain, hFont, hFontBold uintptr
	scale                          = 1.0
	grey                           = map[uintptr]bool{}

	hLblKw, hKeyword, hFind, hWinCombo                          uintptr
	hUpdate, hAdvanced, hThemeBtn                               uintptr
	hList, hAddCat, hAddLisp, hAddCmd, hEdit, hDel, hUp, hDown  uintptr
	hTitle, hDesc, hOptGroup, hLblManual, hManual, hRun, hReset uintptr
	hLog                                                        uintptr
	hTools, hStartup                                            uintptr
	hListHdr, hListCnt, hChip, hOptHdr, hStatus, hLogToggle     uintptr
	hFontSec                                                    uintptr // 칸 제목(리습 목록·옵션·설명서) 글꼴
	hFontTitle                                                  uintptr // 오른쪽 기능 제목 (크게)

	pPostMessageW = user32.NewProc("PostMessageW")
)

type optCtl struct {
	opt                    Option
	label, ctrl, btn, hint uintptr
	items                  []ChoiceItem
}

var optCtls []optCtl

func logf(format string, a ...interface{}) {
	line := time.Now().Format("[15:04:05] ") + fmt.Sprintf(format, a...) + "\r\n"
	n := c(pGetWindowTextLengthW, hLog)
	c(pSendMessageW, hLog, EM_SETSEL, n, n)
	c(pSendMessageW, hLog, EM_REPLACESEL, 0, uintptr(P(ws(line))))
	if hStatus != 0 {
		setText(hStatus, strings.TrimRight(line, "\r\n"))
	}
}

var chipBrush, chipBrushClr uintptr

func ctlColor(hdc, ctl uintptr) uintptr {
	if ctl == hChip { // 설명서 머리 줄의 명령어·리습 꼬리표: 한 톤 다른 바탕 + 흐린 글자
		if chipBrush == 0 || chipBrushClr != clrHotBg {
			if chipBrush != 0 {
				c(pDeleteObject, chipBrush)
			}
			chipBrush, chipBrushClr = c(pCreateSolidBrush, clrHotBg), clrHotBg
		}
		c(pSetBkColor, hdc, clrHotBg)
		c(pSetTextColor, hdc, clrSubText)
		return chipBrush
	}
	if ctl == hCadState { // 연결 상태 문구: 연결됨 초록 / 못 찾음 빨강
		c(pSetBkColor, hdc, clrBg)
		if cadStateOn == 1 {
			c(pSetTextColor, hdc, RGB(0x4C, 0xC3, 0x8A))
		} else {
			c(pSetTextColor, hdc, RGB(0xD9, 0x5C, 0x5C))
		}
		return hBgBrush
	}
	if ctl == hLog || ctl == hManual {
		c(pSetBkColor, hdc, clrPanelBg)
		c(pSetTextColor, hdc, clrText)
		return hPanelBrush
	}
	c(pSetBkColor, hdc, clrBg)
	if grey[ctl] {
		c(pSetTextColor, hdc, clrSubText)
	} else {
		c(pSetTextColor, hdc, clrText)
	}
	return hBgBrush
}

func createControls() {
	hFontSec = makeFont(11, true) // 작업할 도면·작업 목록·기능 제목·설명서 모두 같은 크기
	// 대상 CAD 창: 제목 옆 선택칸 + 다시 찾기(↻). 창 제목 키워드는 설정 창에서 바꿈 (입력칸은 숨겨서 값만 보관)
	hLblKw = mk("STATIC", T("app.001"), SS_LEFT, 0, 0)
	hKeyword = mk("EDIT", st.Keyword, ES_AUTOHSCROLL|WS_TABSTOP, WS_EX_CLIENTEDGE, idKeyword)
	show(hLblKw, false)
	show(hKeyword, false)
	hFind = mk("BUTTON", "↻", WS_TABSTOP, 0, idFind) // 새로고침 아이콘으로 그림 (style2.go)
	hCadLbl = mk("STATIC", T("app.101"), SS_LEFT, 0, 0)
	show(hCadLbl, false) // 새 화면: 이름표 없이 선택칸 안에 연결 점·도면 이름·연결 상태를 그림 (ui2.go)
	hWinCombo = mk("COMBOBOX", "", CBS_DROPDOWNLIST|0x0010 /*CBS_OWNERDRAWFIXED*/ |0x0200 /*CBS_HASSTRINGS*/ |WS_VSCROLL|WS_TABSTOP, 0, idWinCombo)
	hCadState = mk("STATIC", "", SS_LEFT|0x4000 /*SS_ENDELLIPSIS*/, 0, 0)
	show(hCadState, false)

	hUpdate = mk("BUTTON", T("app.002"), WS_TABSTOP, 0, idUpdate)
	hAdvanced = mk("BUTTON", T("app.003"), WS_TABSTOP, 0, idAdvanced)
	hThemeBtn = mk("BUTTON", T("app.004"), WS_TABSTOP, 0, idThemeBtn) // 전구 모양으로 그림 (style2.go)

	// 왼쪽: '작업 목록' 제목 + 개수 + 순서 바꾸기(▲▼)
	// 왼쪽: 검색칸 + 보기 버튼(전체/즐겨찾기/추천) + 직접 그리는 목록 (listpane.go)
	hListHdr = mk("STATIC", T("app.005"), SS_LEFT, 0, 0)
	hListCnt = mk("STATIC", "", SS_LEFT, 0, 0)
	hUp = mk("BUTTON", "▲", WS_TABSTOP, 0, idUp)
	hDown = mk("BUTTON", "▼", WS_TABSTOP, 0, idDown)
	for _, h := range []uintptr{hListHdr, hListCnt, hUp, hDown} {
		show(h, false)
	}
	setupRecommendIcon()
	createListPane()
	hAddCat = mk("STATIC", "", SS_LEFT, 0, 0) // (예전 '순서는 이 PC에만 저장' 안내 자리, 쓰지 않음)
	show(hAddCat, false)

	// 오른쪽: 제목 + (리습 · 명령어) 꼬리표 / 설명 / 옵션 / 설명서 / 실행 줄
	hTitle = mk("STATIC", "", SS_LEFT|0x4000 /*SS_ENDELLIPSIS*/, 0, 0)
	hFontTitle = makeFont(15, true)
	c(pSendMessageW, hTitle, WM_SETFONT, hFontTitle, 1)
	hChip = mk("STATIC", "", 0x0001|0x0200|0x4000 /*SS_CENTER|SS_CENTERIMAGE|SS_ENDELLIPSIS: 한 줄, 넘치면 …*/, 0, 0)
	hDesc = mk("STATIC", "", SS_LEFT, 0, 0)
	grey[hDesc] = true
	hOptGroup = mk("STATIC", T("app.006"), SS_LEFT, 0, 0)
	c(pSendMessageW, hOptGroup, WM_SETFONT, hFontSec, 1)
	hReset = mk("BUTTON", T("app.007"), WS_TABSTOP, 0, idReset)
	hLblManual = mk("STATIC", T("app.008"), SS_LEFT, 0, 0)
	c(pSendMessageW, hLblManual, WM_SETFONT, hFontSec, 1)
	show(hLblManual, false) // 새 화면: '설명서' 제목 없이 바로 내용
	hManual = mk("EDIT", "", ES_MULTILINE|ES_AUTOVSCROLL|ES_READONLY|WS_VSCROLL, WS_EX_CLIENTEDGE, idManual)
	hRun = mk("BUTTON", T("app.009"), WS_TABSTOP|BS_OWNERDRAW, 0, idRun) // 직접 그려서 강조색 버튼으로 표시
	hFavBtn = mk("BUTTON", "☆", WS_TABSTOP, 0, idFav)                    // 설명서 머리 줄 즐겨찾기 별 (favorites.go)
	show(hFavBtn, false)
	hTools = mk("BUTTON", T("app.010"), WS_TABSTOP, 0, idTools)
	hStartup = mk("BUTTON", T("app.011"), BS_OWNERDRAW|WS_TABSTOP, 0, idStartup) // 켜고 끄는 스위치로 그림 (ui2.go)

	// 아래: 마지막 결과 한 줄 + 실행 기록 펼치기
	hStatus = mk("STATIC", "", SS_LEFT|0x0100 /*SS_NOTIFY*/ |0x4000 /*SS_ENDELLIPSIS*/, 0, 0)
	grey[hStatus] = true
	hLogToggle = mk("BUTTON", "", WS_TABSTOP, 0, idLogToggle)
	hLog = mk("EDIT", "", ES_MULTILINE|ES_AUTOVSCROLL|ES_READONLY|WS_VSCROLL, WS_EX_CLIENTEDGE, idLog)
	createGuide()
}

// 목록 칸 폭 (경계를 끌어서 조절, 96DPI 기준)
var leftW = 300
var rightX = 8 + leftW + 10

const minLeftW = 220

var (
	splitDrag       bool
	pGetCursorPos   = user32.NewProc("GetCursorPos")
	pScreenToClient = user32.NewProc("ScreenToClient")
	pSetCursor      = user32.NewProc("SetCursor")
	pSetCaptureM    = user32.NewProc("SetCapture")
	pReleaseCaptM   = user32.NewProc("ReleaseCapture")
)

func setLeftW(w int) {
	W, _ := clientSize()
	if mx := W - 420; w > mx {
		w = mx
	}
	if w < minLeftW {
		w = minLeftW
	}
	leftW, rightX = w, 8+w+10
}

// 마우스 위치(클라이언트, 96DPI 기준)가 목록·설명 사이 경계 위인지
func onSplitter(x, y int) bool {
	_, H := clientSize()
	return x >= 8+leftW-1 && x <= rightX+1 && y >= listTop && y <= mainBottomY(H)
}

func mouseXY(lp uintptr) (int, int) {
	return int(float64(int16(lp&0xFFFF)) / scale), int(float64(int16((lp>>16)&0xFFFF)) / scale)
}

func clientSize() (int, int) {
	var r rectT
	c(pGetClientRect, hMain, uintptr(P(&r)))
	return int(float64(r.right) / scale), int(float64(r.bottom) / scale)
}

func show(h uintptr, on bool) {
	v := uintptr(0)
	if on {
		v = 5 // SW_SHOW
	}
	c(pShowWindow, h, v)
}

const (
	hdrH    = 54          // 맨 위 제목 줄 높이 (96DPI 기준)
	secTop  = hdrH + 10   // '리습 목록' 제목 줄 y
	listTop = secTop + 30 // 목록 칸 시작 y
	statusH = 36          // 맨 아래 상태 줄 높이
	logH    = 130         // 펼친 실행 기록 칸 높이
)

// 목록·설명 칸의 아래 끝 y (아래 상태 줄·펼친 기록 칸 위)
func mainBottomY(H int) int {
	b := H - statusH - 8
	if st.LogOpen {
		b -= logH + 6
	}
	return b
}

// 맨 위 줄: '작업할 도면' 이름표 → 연결 점(titleEndX+16) → CAD 창 선택칸(titleEndX+30). layout 에서 잼
var titleEndX = -4
var hCadLbl, hCadState uintptr // '작업할 도면' 이름표 / ↻ 오른쪽 연결 상태 문구

// ↻ 오른쪽 연결 상태 문구: 연결됨(초록) / 못 찾음(빨강). 바뀔 때만 다시 그림
var cadStateOn = -1

func updateCadState() {
	if hCadState == 0 {
		return
	}
	on := 0
	if cadConnected() {
		on = 1
	}
	if on == cadStateOn {
		return
	}
	cadStateOn = on
	if on == 1 {
		setText(hCadState, T("app.102"))
	} else {
		setText(hCadState, T("app.103"))
	}
	c(pInvalidateRect, hWinCombo, 0, 1) // 선택칸 안의 연결 점·상태 문구 (ui2.go)
}

// 대상 CAD 창 연결 표시 (초록 = 선택된 CAD 창이 살아 있음)
func cadConnected() bool {
	i := comboSel(hWinCombo)
	return i >= 0 && i < len(windows) && c(pIsWindow, windows[i].h) != 0
}

// 맨 위 줄 아래·상태 줄 위 구분선 + 오른쪽 머리의 기능 아이콘 (ui2.go)
func paintHeader(hdc uintptr) {
	W, H := clientSize()
	br := c(pCreateSolidBrush, clrBorder)
	for _, ln := range []rectT{
		{0, int32(s(hdrH)), int32(s(W)), int32(s(hdrH)) + 1},                                          // 제목 줄 아래
		{int32(s(8 + leftW + 4)), int32(s(hdrH)) + 1, int32(s(8+leftW+4)) + 1, int32(s(H - statusH))}, // 목록·설명 사이 세로줄
		{0, int32(s(H - statusH)), int32(s(W)), int32(s(H-statusH)) + 1},                              // 상태 줄 위
	} {
		c(pFillRect, hdc, uintptr(P(&ln)), br)
	}
	c(pDeleteObject, br)
}

func layout() {
	W, H := clientSize()
	// 맨 위 줄: [● 도면 이름 ······ AutoCAD LT 2026 · 연결됨 ▾] ↻ 전구 ⚙ [업데이트]
	const by, bh = 10, 34
	uw := strW(T("app.002"), hFont) + 34
	mv(hUpdate, W-10-uw, by-updPad, uw+updPad, bh+updPad) // 위·오른쪽 여백에 업데이트 알림 빨간 점 (style2.go)
	gx := W - 10 - uw - 8 - bh
	mv(hAdvanced, gx, by, bh, bh)
	mv(hThemeBtn, gx-6-bh, by, bh, bh)
	fx := gx - 6 - bh - 6 - bh
	mv(hFind, fx, by, bh, bh)
	mv(hWinCombo, 12, by, max(fx-10-12, 160), 300)

	mainBottom := mainBottomY(H)
	// 왼쪽: 리습 목록
	layoutListPane(mainBottom) // 검색칸 / 보기 버튼 / 목록 (listpane.go)

	// 오른쪽 머리: [아이콘] 제목 / 설명 / 명령어·리습 꼬리표 ········ ☆ [▶ 실행]
	rw := max(W-rightX-8, 200)
	ix := rightX // 제목은 왼쪽 끝부터 (아이콘·설명 문구는 뺌)
	const runW, runH = 160 + 2*runPadX, 58 + runPadTop + runPadBot
	mv(hRun, rightX+rw-runW+runPadX, secTop-1, runW, runH) // 그림자 여백만큼 바깥으로
	tr := rightX + rw - ix                                 // 제목·설명이 쓸 수 있는 폭
	if c(pIsWindowVisible, hRun) != 0 {
		tr = max(tr-160-16, 120)
	}
	if c(pIsWindowVisible, hFavBtn) != 0 {
		mv(hFavBtn, rightX+rw-160-12-30, secTop+15, 30, 28)
		tr = max(tr-36, 100)
	}
	mv(hTitle, ix, secTop-2, tr, 30)
	show(hDesc, false)
	y := secTop + 72 // 실행 버튼 아래부터
	if len(optCtls) > 0 {
		show(hOptGroup, true)
		show(hReset, true)
		mv(hOptGroup, rightX, y+1, 90, 26)
		mv(hReset, rightX+rw-86, y, 86, 24)
		oy := y + 30
		for _, oc := range optCtls {
			x := rightX + 4
			mv(oc.label, x, oy+4, 150, 20)
			cw := 240
			switch oc.opt.Type {
			case "check":
				mv(oc.ctrl, x+155, oy+2, 24, 22)
			case "choice":
				mv(oc.ctrl, x+155, oy, cw, 300)
			default:
				mv(oc.ctrl, x+155, oy, cw, 24)
			}
			if oc.btn != 0 {
				mv(oc.btn, x+155+cw+4, oy, 30, 24)
			}
			if oc.hint != 0 {
				hx := x + 155 + cw + 40
				mv(oc.hint, hx, oy+4, max(rightX+rw-hx-8, 20), 20)
			}
			oy += 30
		}
		y = oy + 6
	} else {
		show(hOptGroup, false)
		show(hReset, false)
	}
	actTop := mainBottom - 38 // 아래 줄 (자동 로드 스위치·외부 프로그램 설치)
	mh := max(actTop-6-y, 40)
	mv(hManual, rightX, y, rw, mh)
	mv(hGuide, rightX, y, rw, mh)

	// 아래 줄: 자동 로드 스위치 + 외부 프로그램 설치
	sx := rightX
	swW := 36 + 10 + strW(getText(hStartup), hFont) + 8
	mv(hStartup, sx, actTop+6, swW, 26)
	if c(pIsWindowVisible, hStartup) != 0 {
		sx += swW + 14
	}
	mv(hTools, sx, actTop+4, 140, 28)
	// 명령어·리습 꼬리표: 아래 줄 오른쪽 끝
	chip := getText(hChip)
	show(hChip, chip != "")
	chipW := min(textW(hChip, hFont)+16, max(rightX+rw-sx-150, 60))
	mv(hChip, rightX+rw-chipW, actTop+9, chipW, 20)
	c(pInvalidateRect, hChip, 0, 1) // 폭·위치가 바뀌면 예전 글자 조각이 남지 않게 전체를 다시 그림

	// 맨 아래: 마지막 결과 한 줄 + 실행 기록 펼치기 / 펼친 기록 칸
	show(hLog, st.LogOpen)
	if st.LogOpen {
		setText(hLogToggle, T("app.012"))
		mv(hLog, 8, H-statusH-6-logH, W-16, logH)
	} else {
		setText(hLogToggle, T("app.013"))
	}
	mv(hStatus, 12, H-statusH+9, W-12-150, 20)
	mv(hLogToggle, W-8-136, H-statusH+5, 136, 26)
	c(pInvalidateRect, hMain, 0, 1) // 입력칸 둘레 테두리(부모가 그림)를 새 위치에 다시 그림
}

// 컨트롤 글자 폭 (96DPI 기준)
// 글자열 폭 (96DPI 기준) - 컨트롤 없이 잴 때
func strW(str string, font uintptr) int {
	t := utf16.Encode([]rune(str))
	if len(t) == 0 {
		return 0
	}
	dc := c(pGetDC, hMain)
	old := c(pSelectObject, dc, font)
	var sz [2]int32
	c(pGetTextExtentPoint32W, dc, uintptr(P(&t[0])), uintptr(len(t)), uintptr(P(&sz)))
	c(pSelectObject, dc, old)
	c(pReleaseDC, hMain, dc)
	return int(float64(sz[0]) / scale)
}

func textW(h, font uintptr) int {
	t := utf16.Encode([]rune(getText(h)))
	if len(t) == 0 {
		return 0
	}
	dc := c(pGetDC, h)
	old := c(pSelectObject, dc, font)
	var sz [2]int32
	c(pGetTextExtentPoint32W, dc, uintptr(P(&t[0])), uintptr(len(t)), uintptr(P(&sz)))
	c(pSelectObject, dc, old)
	c(pReleaseDC, h, dc)
	return int(float64(sz[0]) / scale)
}

func applyTopmost() {
	after := ^uintptr(1) // HWND_NOTOPMOST
	if st.Topmost {
		after = ^uintptr(0) // HWND_TOPMOST
	}
	c(pSetWindowPos, hMain, after, 0, 0, 0, 0, 0x0003)
}

func setManual(text string) {
	text = strings.ReplaceAll(strings.ReplaceAll(text, "\r\n", "\n"), "\n", "\r\n")
	setText(hManual, text)
}

// ───────────── 옵션 패널 ─────────────
func clearOptions() {
	for _, oc := range optCtls {
		for _, h := range []uintptr{oc.label, oc.ctrl, oc.btn, oc.hint} {
			if h != 0 {
				delete(grey, h)
				c(pDestroyWindow, h)
			}
		}
	}
	optCtls = nil
}

func buildOptions(opts []Option, saved map[string]interface{}) {
	clearOptions()
	for i, o := range opts {
		if o.Type == "" {
			o.Type = "text"
		}
		label := o.Label
		if label == "" {
			label = o.Key
		}
		val := o.Default
		if saved != nil {
			if v, ok := saved[o.Key]; ok {
				val = v
			}
		}
		oc := optCtl{opt: o}
		oc.label = mk("STATIC", label, SS_LEFT, 0, 0)
		id := idOptBase + i
		switch o.Type {
		case "check":
			oc.ctrl = mk("BUTTON", "", BS_AUTOCHECKBOX|WS_TABSTOP, 0, id)
			setCheck(oc.ctrl, toBool(val))
		case "choice":
			oc.items = o.items()
			labels := make([]string, len(oc.items))
			sel := 0
			for j, it := range oc.items {
				labels[j] = it.Label
				if it.Value == toStr(val) {
					sel = j
				}
			}
			oc.ctrl = mk("COMBOBOX", "", CBS_DROPDOWNLIST|WS_VSCROLL|WS_TABSTOP, 0, id)
			comboFill(oc.ctrl, labels, sel)
		default:
			oc.ctrl = mk("EDIT", toStr(val), ES_AUTOHSCROLL|WS_TABSTOP, WS_EX_CLIENTEDGE, id)
			if o.Type == "file" || o.Type == "folder" {
				oc.btn = mk("BUTTON", "…", WS_TABSTOP, 0, idBrowseBase+i)
			}
		}
		if o.Hint != "" {
			oc.hint = mk("STATIC", o.Hint, SS_LEFT, 0, 0)
			grey[oc.hint] = true
		}
		optCtls = append(optCtls, oc)
	}
}

func collect() ([]kv, map[string]interface{}, bool) {
	var out []kv
	keep := map[string]interface{}{}
	for _, oc := range optCtls {
		o := oc.opt
		label := o.Label
		if label == "" {
			label = o.Key
		}
		switch o.Type {
		case "check":
			b := isChecked(oc.ctrl)
			keep[o.Key] = b
			out = append(out, kv{o.Key, toStr(b)})
		case "choice":
			v := ""
			if i := comboSel(oc.ctrl); i >= 0 && i < len(oc.items) {
				v = oc.items[i].Value
			}
			keep[o.Key] = v
			out = append(out, kv{o.Key, v})
		default:
			v := strings.TrimSpace(getText(oc.ctrl))
			if o.Type == "number" {
				if _, err := strconv.ParseFloat(v, 64); err != nil {
					msgBox("'"+label+T("app.014")+v, MB_ICONWARNING)
					return nil, nil, false
				}
			} else if o.Type == "int" {
				if _, err := strconv.Atoi(v); err != nil {
					msgBox("'"+label+T("app.015")+v, MB_ICONWARNING)
					return nil, nil, false
				}
			}
			keep[o.Key] = v
			out = append(out, kv{o.Key, v})
		}
	}
	return out, keep, true
}

// 옵션값 → AutoLISP 값 표현
func lispValue(o Option, v string) string {
	switch o.Type {
	case "number", "int":
		if _, err := strconv.ParseFloat(v, 64); err == nil {
			return v
		}
		return "nil"
	case "check":
		if v == "1" {
			return "T"
		}
		return "nil"
	case "file", "folder":
		v = strings.ReplaceAll(v, "\\", "/")
	}
	return `"` + strings.NewReplacer(`\`, `\\`, `"`, `\"`).Replace(v) + `"`
}

func browse(i int) {
	if i < 0 || i >= len(optCtls) {
		return
	}
	oc := optCtls[i]
	buf := make([]uint16, 1024)
	if oc.opt.Type == "folder" {
		bi := browseInfo{hwndOwner: hMain, pszDisplayName: &buf[0], lpszTitle: ws(T("app.016")), ulFlags: 0x0001 | 0x0040}
		pidl := c(pSHBrowseForFolderW, uintptr(P(&bi)))
		if pidl == 0 {
			return
		}
		c(pSHGetPathFromIDListW, pidl, uintptr(P(&buf[0])))
		c(pCoTaskMemFree, pidl)
	} else {
		filter := utf16Z("모든 파일\x00*.*\x00\x00")
		ofn := openFileName{hwndOwner: hMain, lpstrFilter: &filter[0], lpstrFile: &buf[0], nMaxFile: uint32(len(buf)),
			Flags: 0x00001000 | 0x00000008 | 0x00080000}
		ofn.lStructSize = uint32(unsafe.Sizeof(ofn))
		ok := c(pGetOpenFileNameW, uintptr(P(&ofn)))
		runtime.KeepAlive(filter)
		if ok == 0 {
			return
		}
	}
	if p := syscall.UTF16ToString(buf); p != "" {
		setText(oc.ctrl, p)
	}
}

// ───────────── CAD 창 / 실행 ─────────────
// 전송 방식 · 인코딩 · 취소 · 항상 위는 '설정' 창에서 바꿀 때 바로 st에 반영되므로
// (advancedDialog 참고) 여기서는 메인 창에 남아있는 값만 거둬들인다.
func readSettings() {
	st.Keyword = getText(hKeyword)
}

func refreshWindows() {
	enumKW = strings.ToLower(strings.TrimSpace(getText(hKeyword)))
	if enumKW == "" {
		enumKW = "autocad"
	}
	windows = nil
	c(pEnumWindows, enumCB, 0)
	titles := make([]string, len(windows))
	for i, w := range windows {
		titles[i] = w.title
	}
	sel := -1
	if len(windows) > 0 {
		sel = 0
	}
	comboFill(hWinCombo, titles, sel)
	cadStateOn = -1
	updateCadState() // 연결 표시 점·상태 문구
	if len(windows) > 0 {
		logf(T("app.017"), len(windows))
	} else {
		logf("%s", T("app.018"))
	}
}

func targetHwnd() uintptr {
	i := comboSel(hWinCombo)
	if i < 0 || i >= len(windows) || c(pIsWindow, windows[i].h) == 0 {
		refreshWindows()
		i = comboSel(hWinCombo)
		if i < 0 || i >= len(windows) {
			return 0
		}
	}
	return windows[i].h
}

func send(text string) bool {
	readSettings()
	h := targetHwnd()
	if h == 0 {
		msgBox(T("app.019"), MB_ICONWARNING)
		return false
	}
	var err error
	if st.Method == "키입력" {
		sendKeys(h, text, st.Cancel)
	} else {
		err = sendCopyData(h, text, st.Cancel)
	}
	if err != nil {
		logf(T("app.020"), err)
		return false
	}
	logf(T("app.021"), strings.ReplaceAll(text, "\n", "⏎"))
	return true
}

// '설정' 창의 직접 명령 입력칸에서 호출 (dialogs.go의 advancedDialog 참고)
func sendFreeFrom(hEdit uintptr) {
	t := strings.TrimRight(getText(hEdit), "\r\n")
	if strings.TrimSpace(t) == "" {
		return
	}
	if send(t + "\n") {
		setText(hEdit, "")
	}
}

// ───────────── 메시지 처리 ─────────────
func onCommand(id, code int) {
	if id == idSearch && code == 0x0300 /*EN_CHANGE*/ { // 검색: 글자를 칠 때마다 목록을 거름
		lsb.pos = 0
		refilterList()
		return
	}
	if id == idWinCombo && code == CBN_SELCHANGE {
		cadStateOn = -1
		updateCadState() // 연결 표시 점·상태 문구
		return
	}
	if code != BN_CLICKED {
		return
	}
	switch {
	case id == IDOK: // Enter: 목록이나 실행 버튼에 있을 때만 실행 (입력칸에서 누른 Enter 는 무시)
		f := c(pGetFocus)
		if hSearch != 0 && f == hSearch { // 검색칸에서 Enter: 첫 번째 결과를 고르고 목록으로 (한 번 더 Enter 면 실행)
			for i := range lrows {
				if lrows[i].kind == rowItem {
					selectRow(i)
					c(pSetFocus, hList)
					break
				}
			}
		} else if (f == hList || f == hRun) && c(pIsWindowEnabled, hRun) != 0 {
			runCurrent()
		}
	case id == idChipAll:
		setListMode(lmAll)
	case id == idChipFav:
		setListMode(lmFav)
	case id == idChipRec:
		setListMode(lmRec)
	case id == idFind:
		refreshWindows()
	case id == idUpdate:
		startUpdateCheck(true)
	case id == idThemeBtn:
		toggleTheme()
	case id == idAdvanced:
		advancedDialog()
	case id == idUp:
		moveNode(-1)
	case id == idDown:
		moveNode(1)
	case id == idFav:
		toggleFav(cur.item())
	case id == idRun:
		runCurrent()
	case id == idTools:
		installCurrentTools()
	case id == idLogToggle:
		st.LogOpen = !st.LogOpen
		layout()
	case id == idStartup:
		startupOn = !startupOn // 스위치 (ui2.go) - toggleStartup 이 isChecked 로 읽음
		c(pInvalidateRect, hStartup, 0, 0)
		toggleStartup()
	case id == idReset:
		resetOptions()
	case id >= idBrowseBase && id < idBrowseBase+500:
		browse(id - idBrowseBase)
	}
}

func wndProc(h, msg, wp, lp uintptr) uintptr {
	switch msg {
	case WM_COMMAND:
		onCommand(int(wp&0xFFFF), int((wp>>16)&0xFFFF))
		return 0
	case WM_NOTIFY:
		return onNotify(lp)
	case WM_APP_UPDATE:
		onUpdateResult()
		return 0
	case WM_APP_TOOLS:
		onToolsResult()
		return 0
	case WM_TIMER:
		if wp == askTimerID {
			updateCadState() // CAD 를 닫거나 다시 열면 0.4초 안에 상태 문구가 바뀜
			onAskTimer()
		}
		if wp == updTimerID && st.AutoUpdate {
			startUpdateCheck(false)
		}
		return 0
	case WM_SIZE:
		if hLog != 0 {
			setLeftW(leftW)
			layout()
		}
		return 0
	case 0x0020: // WM_SETCURSOR
		if h == wp && lp&0xFFFF == 1 { // HTCLIENT
			var pt [2]int32
			c(pGetCursorPos, uintptr(P(&pt)))
			c(pScreenToClient, hMain, uintptr(P(&pt)))
			if splitDrag || onSplitter(int(float64(pt[0])/scale), int(float64(pt[1])/scale)) {
				c(pSetCursor, c(pLoadCursorW, 0, 32644)) // IDC_SIZEWE
				return 1
			}
		}
	case 0x0201: // WM_LBUTTONDOWN
		if x, y := mouseXY(lp); onSplitter(x, y) {
			splitDrag = true
			c(pSetCaptureM, hMain)
		}
		return 0
	case WM_MOUSEMOVE:
		if splitDrag {
			x, _ := mouseXY(lp)
			setLeftW(x - 8 - 5)
			layout()
		}
		return 0
	case WM_LBUTTONUP:
		if splitDrag {
			splitDrag = false
			c(pReleaseCaptM)
			st.LeftW = leftW
		}
		return 0
	case WM_CAPTURECHANGED:
		splitDrag = false
		return 0
	case WM_GETMINMAXINFO:
		pt := (*[2]int32)(P(lp + 24)) // ptMinTrackSize
		pt[0], pt[1] = int32(s(900)), int32(s(600))
		return 0
	case WM_CTLCOLORSTATIC:
		return ctlColor(wp, lp)
	case WM_CTLCOLOREDIT, WM_CTLCOLORLISTBOX:
		return editColor(wp)
	case WM_ERASEBKGND:
		return eraseBg(h, wp)
	case WM_DRAWITEM:
		return drawButton(lp)
	case 0x002C: // WM_MEASUREITEM: 작업할 도면 선택칸 높이 (ui2.go)
		if mi := (*measureItemStruct)(P(lp)); mi.ctlID == idWinCombo {
			if int32(mi.itemID) == -1 {
				mi.itemHeight = uint32(s(26))
			} else {
				mi.itemHeight = uint32(s(28))
			}
			return 1
		}
	case WM_PAINT:
		paintFrames(h)
		hdc := c(pGetDC, h)
		paintHeader(hdc)
		c(pReleaseDC, h, hdc)
		return 0
	case WM_CLOSE:
		readSettings()
		saveState()
		c(pDestroyWindow, h)
		return 0
	case WM_DESTROY:
		c(pPostQuitMessage, 0)
		return 0
	}
	return c(pDefWindowProcW, h, msg, wp, lp)
}

// 글자 크기 단계 → 배율 (2단계 = 예전 크기, 기본은 3단계)
var fontScales = []float64{0.9, 1.0, 1.1, 1.2, 1.3}

func fontLevel() int {
	if st.FontLevel < 1 || st.FontLevel > len(fontScales) {
		return 3
	}
	return st.FontLevel
}

func fontScale() float64 { return fontScales[fontLevel()-1] }

func makeFont(pt int, bold bool) uintptr {
	weight := uintptr(400)
	if bold {
		weight = 700
	}
	height := -int(float64(pt) * fontScale() * scale * 96 / 72)
	return c(pCreateFontW, uintptr(height), 0, 0, 0, weight, 0, 0, 0, 1, 0, 0, 5, 0, uintptr(P(ws("맑은 고딕"))))
}

func main() {
	runtime.LockOSThread()

	exePath, _ = os.Executable()
	appDir = filepath.Dir(exePath)
	if len(os.Args) >= 3 && os.Args[1] == "--matx-fill" {
		os.Exit(runMatxFill(os.Args[2]))
	}
	if len(os.Args) >= 3 && os.Args[1] == "--pavq-fill" {
		os.Exit(runPavqFill(os.Args[2]))
	}
	catalogPath = filepath.Join(appDir, "catalog.json")
	statePath = filepath.Join(appDir, "launcher_state.json")
	lspDir = filepath.Join(appDir, "lsp")
	tmp := os.Getenv("TEMP")
	if tmp == "" {
		tmp = os.TempDir()
	}
	optPath = filepath.Join(tmp, "cad_launcher_opt.txt")
	_ = os.Remove(exePath + ".old") // 지난 자체 업데이트의 잔여 파일
	loadState()

	c(pSetProcessDPIAware)
	enableVisualStyles()
	icc := [2]uint32{8, 0x0000FFFF}
	c(pInitCommonControlsEx, uintptr(P(&icc)))
	c(pCoInitializeEx, 0, 2)

	dc := c(pGetDC, 0)
	scale = float64(c(pGetDeviceCaps, dc, 90)) / 96.0
	c(pReleaseDC, 0, dc)
	if scale <= 0 {
		scale = 1
	}
	hFont = makeFont(9, false)
	hFontBold = makeFont(12, true)
	hFontBtnBold = makeFont(9, true)
	hFontRun = makeFont(13, true)
	hFontIcon = makeIconFont(12)
	setThemeColors(st.Theme) // 화면 색상 (theme.go, 기본 차콜 다크)
	hBgBrush = c(pCreateSolidBrush, clrBg)
	hPanelBrush = c(pCreateSolidBrush, clrPanelBg)
	classBgBrush, classPanelBrush = hBgBrush, hPanelBrush

	hInst = c(pGetModuleHandleW, 0)
	cls := ws("CADLauncherWnd")
	wc := wndClassEx{
		lpfnWndProc:   syscall.NewCallback(wndProc),
		hInstance:     hInst,
		hIcon:         c(pLoadIconW, hInst, 1), // 런처 아이콘 (rsrc_windows_amd64.syso, dev/icon 에서 생성)
		hIconSm:       c(pLoadImageW, hInst, 1, 1, 16, 16, 0),
		hCursor:       c(pLoadCursorW, 0, 32512),
		hbrBackground: hBgBrush,
		lpszClassName: cls,
	}
	wc.cbSize = uint32(unsafe.Sizeof(wc))
	c(pRegisterClassExW, uintptr(P(&wc)))
	registerDialogClass()

	cw := uintptr(0x80000000)
	hMain = c(pCreateWindowExW, 0, uintptr(P(cls)), uintptr(P(ws(appTitle))),
		WS_OVERLAPPEDWINDOW|WS_CLIPCHILDREN, cw, cw, s(1000), s(720), 0, 0, hInst, 0)
	styleWindow(hMain) // 둥근 모서리 + 제목 표시줄·테두리 색 (Windows 11)
	if st.LeftW > 0 {
		leftW, rightX = st.LeftW, 8+st.LeftW+10
	}
	createControls()
	loadCatalog()
	if len(st.Startup) > 0 {
		_ = writeStartupLoader() // 경로·외부 프로그램 위치가 바뀌었을 수 있으니 매번 새로 씀
	}
	layout()
	refreshTree(nodeRef{})
	refreshWindows()
	if st.Topmost {
		applyTopmost()
	}
	c(pShowWindow, hMain, SW_SHOWNORMAL)
	c(pUpdateWindow, hMain)
	if st.AutoUpdate {
		startUpdateCheck(false) // 묻지 않고 받을 것이 있으면 업데이트 버튼에 빨간 점만
	}
	c(pSetTimer, hMain, updTimerID, updEvery, 0) // 켜 둔 동안 1시간마다 조용히 확인 (update.go)
	startAskWatch()                              // 리습 질문을 런처 창으로 (ask.go)

	var m msgT
	for {
		r := int32(c(pGetMessageW, uintptr(P(&m)), 0, 0, 0))
		if r <= 0 {
			break
		}
		if eatEscape(&m) || c(pIsDialogMessageW, hMain, uintptr(P(&m))) != 0 {
			continue
		}
		c(pTranslateMessage, uintptr(P(&m)))
		c(pDispatchMessageW, uintptr(P(&m)))
	}
}
