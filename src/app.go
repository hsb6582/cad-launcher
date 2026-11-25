// CAD 런처 - AutoCAD LT 2026 리습 실행 / 옵션 조정 / 설명서 / GitHub 자동 업데이트
// 외부 라이브러리 없이 Win32 API 직접 사용 (Go 표준 라이브러리만)
// 빌드: GOOS=windows GOARCH=amd64 go build -ldflags "-H windowsgui -s -w" -o CAD런처.exe
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
	"unsafe"
)

var exeRepoName = "CAD런처.exe" // 저장소 안의 런처 파일 이름 (테스트용은 빌드 때 CAD런처-테스트.exe 로 바꿈)

// ───────────────────────── 상태 ─────────────────────────
type State struct {
	Keyword    string                            `json:"keyword"`
	Method     string                            `json:"method"`
	Encoding   string                            `json:"encoding"`
	Cancel     bool                              `json:"cancel"`
	Topmost    bool                              `json:"topmost"`
	Values     map[string]map[string]interface{} `json:"values"`
	Collapsed  []string                          `json:"collapsed,omitempty"`
	AutoUpdate bool                              `json:"autoUpdate"`
	Token      string                            `json:"token,omitempty"`
	Synced     map[string]string                 `json:"synced,omitempty"`
	Installed  map[string]string                 `json:"installed,omitempty"` // 외부 프로그램 이름 → 설치한 버전
	LeftW      int                               `json:"leftW,omitempty"`     // 목록 칸 폭
	Order      map[string][]string               `json:"order,omitempty"`     // 이 PC에서 바꾼 목록 순서
	Startup    []string                          `json:"startup,omitempty"`   // 시작하기 세트로 모든 도면에 자동 로드할 리습 id
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
	idGitHub
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
	idOptBase    = 1000
	idBrowseBase = 2000
)

// 고급 설정 창(dialogs.go의 advancedDialog) 안에서만 쓰는 컨트롤 id
const (
	idAdvMethod = 500 + iota
	idAdvCancel
	idAdvTop
	idAdvEnc
	idAdvSend
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
	hUpdate, hGitHub, hAdvanced                                 uintptr
	hList, hAddCat, hAddLisp, hAddCmd, hEdit, hDel, hUp, hDown  uintptr
	hTitle, hDesc, hOptGroup, hLblManual, hManual, hRun, hReset uintptr
	hLog                                                        uintptr
	hTools, hStartup                                            uintptr

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
}

func ctlColor(hdc, ctl uintptr) uintptr {
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
	hLblKw = mk("STATIC", "창 제목 키워드", SS_LEFT, 0, 0)
	hKeyword = mk("EDIT", st.Keyword, ES_AUTOHSCROLL|WS_TABSTOP, WS_EX_CLIENTEDGE, idKeyword)
	hFind = mk("BUTTON", "창 찾기", WS_TABSTOP, 0, idFind)
	hWinCombo = mk("COMBOBOX", "", CBS_DROPDOWNLIST|WS_VSCROLL|WS_TABSTOP, 0, idWinCombo)

	hUpdate = mk("BUTTON", "업데이트 확인", WS_TABSTOP, 0, idUpdate)
	hGitHub = mk("BUTTON", "업데이트 설정", WS_TABSTOP, 0, idGitHub)
	hAdvanced = mk("BUTTON", "고급 설정", WS_TABSTOP, 0, idAdvanced)

	hList = mk("SysTreeView32", "", TVS_HASBUTTONS|TVS_LINESATROOT|TVS_SHOWSELALWAYS|0x0010 /*TVS_DISABLEDRAGDROP*/ |WS_TABSTOP, WS_EX_CLIENTEDGE, idList)
	c(pSetWindowTheme, hList, uintptr(P(ws("Explorer"))), 0) // 탐색기 스타일 트리(선택 표시가 더 매끈해짐)
	c(pSendMessageW, hList, TVM_SETEXTENDEDSTYLE, TVS_EX_DOUBLEBUFFER, TVS_EX_DOUBLEBUFFER)
	styleTree()
	setupRecommendIcon()
	// 목록 편집은 엑셀(dev/catalog.xlsx) → 저장소에서 하고, 런처에서는 순서만 바꿈
	hUp = mk("BUTTON", "▲ 위로", WS_TABSTOP, 0, idUp)
	hDown = mk("BUTTON", "▼ 아래로", WS_TABSTOP, 0, idDown)
	hAddCat = mk("STATIC", "순서는 이 PC에만 저장", SS_LEFT, 0, 0)
	grey[hAddCat] = true

	hTitle = mk("STATIC", "", SS_LEFT, 0, 0)
	c(pSendMessageW, hTitle, WM_SETFONT, hFontBold, 1)
	hDesc = mk("STATIC", "", SS_LEFT, 0, 0)
	grey[hDesc] = true
	hOptGroup = mk("BUTTON", "옵션", 0x0007 /*BS_GROUPBOX*/, 0, 0)
	hLblManual = mk("STATIC", "설명서", SS_LEFT, 0, 0)
	hManual = mk("EDIT", "", ES_MULTILINE|ES_AUTOVSCROLL|ES_READONLY|WS_VSCROLL, WS_EX_CLIENTEDGE, idManual)
	hRun = mk("BUTTON", "▶ 실행", WS_TABSTOP|BS_OWNERDRAW, 0, idRun) // 직접 그려서 강조색(테라코타) 버튼으로 표시
	hReset = mk("BUTTON", "옵션 기본값", WS_TABSTOP, 0, idReset)
	hTools = mk("BUTTON", "외부 프로그램 설치", WS_TABSTOP, 0, idTools)
	hStartup = mk("BUTTON", "모든 도면에서 자동 로드 (시작하기 세트)", BS_AUTOCHECKBOX|WS_TABSTOP, 0, idStartup)

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
	return x >= 8+leftW-1 && x <= rightX+1 && y >= 78 && y <= H-168
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

func layout() {
	W, H := clientSize()
	mv(hLblKw, 8, 12, 95, 20)
	mv(hKeyword, 105, 8, 130, 24)
	mv(hFind, 241, 7, 75, 26)
	mv(hWinCombo, 322, 8, max(W-330, 100), 300)

	mv(hGitHub, W-108, 41, 100, 26)
	mv(hUpdate, W-214, 41, 102, 26)
	mv(hAdvanced, W-320, 41, 100, 26)

	top := 78
	bottomH := 120
	mainBottom := H - bottomH - 8
	mv(hList, 8, top, leftW, max(mainBottom-top-32, 60))
	mv(hUp, 8, mainBottom-28, 80, 28)
	mv(hDown, 92, mainBottom-28, 80, 28)
	mv(hAddCat, 180, mainBottom-22, max(leftW-172, 10), 20)

	rw := max(W-rightX-8, 200)
	mv(hTitle, rightX, top, rw, 26)
	mv(hDesc, rightX, top+28, rw, 20)
	y := top + 54
	if len(optCtls) > 0 {
		gh := 26 + 30*len(optCtls) + 4
		show(hOptGroup, true)
		mv(hOptGroup, rightX, y, rw, gh)
		oy := y + 22
		for _, oc := range optCtls {
			x := rightX + 12
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
		y += gh + 6
	} else {
		show(hOptGroup, false)
	}
	mv(hLblManual, rightX, y+2, 80, 20)
	mv(hManual, rightX, y+24, rw, max(mainBottom-36-(y+24), 40))
	mv(hGuide, rightX, y+24, rw, max(mainBottom-36-(y+24), 40))
	mv(hRun, rightX, mainBottom-28, 110, 30)
	mv(hReset, rightX+118, mainBottom-28, 110, 30)
	mv(hTools, rightX+rw-150, mainBottom-28, 150, 30)
	mv(hStartup, rightX+236, mainBottom-24, max(rw-236-158, 60), 24)

	by := mainBottom + 10
	mv(hLog, 8, by, W-16, max(H-by-16, 40))
	c(pInvalidateRect, hMain, 0, 1) // 입력칸 둘레 테두리(부모가 그림)를 새 위치에 다시 그림
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
					msgBox("'"+label+"' 값이 숫자가 아닙니다: "+v, MB_ICONWARNING)
					return nil, nil, false
				}
			} else if o.Type == "int" {
				if _, err := strconv.Atoi(v); err != nil {
					msgBox("'"+label+"' 값이 정수가 아닙니다: "+v, MB_ICONWARNING)
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
		bi := browseInfo{hwndOwner: hMain, pszDisplayName: &buf[0], lpszTitle: ws("폴더 선택"), ulFlags: 0x0001 | 0x0040}
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
// 전송 방식 · 인코딩 · 취소 · 항상 위는 '고급 설정' 창에서 바꿀 때 바로 st에 반영되므로
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
	if len(windows) > 0 {
		logf("CAD 창 %d개 찾음", len(windows))
	} else {
		logf("CAD 창을 찾지 못함 - LT 실행 여부와 키워드를 확인하세요")
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
		msgBox("대상 CAD 창이 없습니다. AutoCAD LT를 켜고 '창 찾기'를 눌러 주세요.", MB_ICONWARNING)
		return false
	}
	var err error
	if st.Method == "키입력" {
		sendKeys(h, text, st.Cancel)
	} else {
		err = sendCopyData(h, text, st.Cancel)
	}
	if err != nil {
		logf("전송 오류: %v", err)
		return false
	}
	logf("전송: %s", strings.ReplaceAll(text, "\n", "⏎"))
	return true
}

// '고급 설정' 창의 직접 명령 입력칸에서 호출 (dialogs.go의 advancedDialog 참고)
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
	if code != BN_CLICKED {
		return
	}
	switch {
	case id == idFind:
		refreshWindows()
	case id == idUpdate:
		startUpdateCheck(true)
	case id == idGitHub:
		githubDialog()
	case id == idAdvanced:
		advancedDialog()
	case id == idUp:
		moveNode(-1)
	case id == idDown:
		moveNode(1)
	case id == idRun:
		runCurrent()
	case id == idTools:
		installCurrentTools()
	case id == idStartup:
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
	case WM_DRAWITEM:
		return drawButton(lp)
	case WM_PAINT:
		paintFrames(h)
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

func makeFont(pt int, bold bool) uintptr {
	weight := uintptr(400)
	if bold {
		weight = 700
	}
	height := -int(float64(pt) * scale * 96 / 72)
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
	hBgBrush = c(pCreateSolidBrush, clrBg)
	hPanelBrush = c(pCreateSolidBrush, clrPanelBg)

	hInst = c(pGetModuleHandleW, 0)
	cls := ws("CADLauncherWnd")
	wc := wndClassEx{
		lpfnWndProc:   syscall.NewCallback(wndProc),
		hInstance:     hInst,
		hIcon:         c(pLoadIconW, 0, 32512),
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
		startUpdateCheck(false)
	}

	var m msgT
	for {
		r := int32(c(pGetMessageW, uintptr(P(&m)), 0, 0, 0))
		if r <= 0 {
			break
		}
		if c(pIsDialogMessageW, hMain, uintptr(P(&m))) != 0 {
			continue
		}
		c(pTranslateMessage, uintptr(P(&m)))
		c(pDispatchMessageW, uintptr(P(&m)))
	}
}
