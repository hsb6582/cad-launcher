package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"unicode/utf16"
	"unsafe"
)

const appTitle = "CAD 런처"

type P = unsafe.Pointer

// ───────────────────────── Win32 ─────────────────────────
var (
	user32   = syscall.NewLazyDLL("user32.dll")
	kernel32 = syscall.NewLazyDLL("kernel32.dll")
	gdi32    = syscall.NewLazyDLL("gdi32.dll")
	comctl32 = syscall.NewLazyDLL("comctl32.dll")
	comdlg32 = syscall.NewLazyDLL("comdlg32.dll")
	shell32  = syscall.NewLazyDLL("shell32.dll")
	ole32    = syscall.NewLazyDLL("ole32.dll")

	pRegisterClassExW     = user32.NewProc("RegisterClassExW")
	pCreateWindowExW      = user32.NewProc("CreateWindowExW")
	pDefWindowProcW       = user32.NewProc("DefWindowProcW")
	pGetMessageW          = user32.NewProc("GetMessageW")
	pTranslateMessage     = user32.NewProc("TranslateMessage")
	pDispatchMessageW     = user32.NewProc("DispatchMessageW")
	pIsDialogMessageW     = user32.NewProc("IsDialogMessageW")
	pPostQuitMessage      = user32.NewProc("PostQuitMessage")
	pDestroyWindow        = user32.NewProc("DestroyWindow")
	pShowWindow           = user32.NewProc("ShowWindow")
	pUpdateWindow         = user32.NewProc("UpdateWindow")
	pMoveWindow           = user32.NewProc("MoveWindow")
	pSetWindowPos         = user32.NewProc("SetWindowPos")
	pGetClientRect        = user32.NewProc("GetClientRect")
	pSendMessageW         = user32.NewProc("SendMessageW")
	pSendMessageTimeoutW  = user32.NewProc("SendMessageTimeoutW")
	pSetWindowTextW       = user32.NewProc("SetWindowTextW")
	pGetWindowTextW       = user32.NewProc("GetWindowTextW")
	pGetWindowTextLengthW = user32.NewProc("GetWindowTextLengthW")
	pEnumWindows          = user32.NewProc("EnumWindows")
	pIsWindowVisible      = user32.NewProc("IsWindowVisible")
	pIsWindow             = user32.NewProc("IsWindow")
	pIsIconic             = user32.NewProc("IsIconic")
	pSetForegroundWindow  = user32.NewProc("SetForegroundWindow")
	pSendInput            = user32.NewProc("SendInput")
	pMessageBoxW          = user32.NewProc("MessageBoxW")
	pLoadCursorW          = user32.NewProc("LoadCursorW")
	pLoadIconW            = user32.NewProc("LoadIconW")
	pGetSysColor          = user32.NewProc("GetSysColor")
	pGetSysColorBrush     = user32.NewProc("GetSysColorBrush")
	pSetProcessDPIAware   = user32.NewProc("SetProcessDPIAware")
	pGetDC                = user32.NewProc("GetDC")
	pAdjustWindowRectEx   = user32.NewProc("AdjustWindowRectEx")
	pGetWindowRect        = user32.NewProc("GetWindowRect")
	pEnableWindow         = user32.NewProc("EnableWindow")
	pSetFocus             = user32.NewProc("SetFocus")
	pSetCapture           = user32.NewProc("SetCapture")
	pReleaseCapture       = user32.NewProc("ReleaseCapture")
	pMapWindowPoints      = user32.NewProc("MapWindowPoints")
	pReleaseDC            = user32.NewProc("ReleaseDC")

	pCreateFontW   = gdi32.NewProc("CreateFontW")
	pGetDeviceCaps = gdi32.NewProc("GetDeviceCaps")
	pSetBkColor    = gdi32.NewProc("SetBkColor")
	pSetTextColor  = gdi32.NewProc("SetTextColor")

	pGetModuleHandleW    = kernel32.NewProc("GetModuleHandleW")
	pCreateActCtxW       = kernel32.NewProc("CreateActCtxW")
	pActivateActCtx      = kernel32.NewProc("ActivateActCtx")
	pWideCharToMultiByte = kernel32.NewProc("WideCharToMultiByte")

	pInitCommonControlsEx = comctl32.NewProc("InitCommonControlsEx")
	pGetOpenFileNameW     = comdlg32.NewProc("GetOpenFileNameW")
	pShellExecuteW        = shell32.NewProc("ShellExecuteW")
	pSHBrowseForFolderW   = shell32.NewProc("SHBrowseForFolderW")
	pSHGetPathFromIDListW = shell32.NewProc("SHGetPathFromIDListW")
	pCoInitializeEx       = ole32.NewProc("CoInitializeEx")
	pCoTaskMemFree        = ole32.NewProc("CoTaskMemFree")
)

const (
	WS_OVERLAPPEDWINDOW = 0x00CF0000
	WS_CLIPCHILDREN     = 0x02000000
	WS_CHILD            = 0x40000000
	WS_VISIBLE          = 0x10000000
	WS_TABSTOP          = 0x00010000
	WS_VSCROLL          = 0x00200000
	WS_BORDER           = 0x00800000
	WS_EX_CLIENTEDGE    = 0x00000200

	ES_MULTILINE         = 0x0004
	ES_AUTOVSCROLL       = 0x0040
	ES_AUTOHSCROLL       = 0x0080
	ES_READONLY          = 0x0800
	BS_AUTOCHECKBOX      = 0x0003
	BS_DEFPUSHBUTTON     = 0x0001
	CBS_DROPDOWNLIST     = 0x0003
	LBS_NOTIFY           = 0x0001
	LBS_NOINTEGRALHEIGHT = 0x0100
	SS_LEFT              = 0x0000

	WM_DESTROY        = 0x0002
	WM_SIZE           = 0x0005
	WM_CLOSE          = 0x0010
	WM_GETMINMAXINFO  = 0x0024
	WM_SETFONT        = 0x0030
	WM_COPYDATA       = 0x004A
	WM_KEYDOWN        = 0x0100
	WM_COMMAND        = 0x0111
	WM_CTLCOLORSTATIC = 0x0138

	EM_SETSEL       = 0x00B1
	EM_REPLACESEL   = 0x00C2
	BM_GETCHECK     = 0x00F0
	BM_SETCHECK     = 0x00F1
	CB_ADDSTRING    = 0x0143
	CB_GETCURSEL    = 0x0147
	CB_RESETCONTENT = 0x014B
	CB_SETCURSEL    = 0x014E
	LB_ADDSTRING    = 0x0180
	LB_RESETCONTENT = 0x0184
	LB_GETCURSEL    = 0x0188
	LBN_SELCHANGE   = 1
	LBN_DBLCLK      = 2
	BN_CLICKED      = 0

	SMTO_ABORTIFHUNG    = 0x0002
	INPUT_KEYBOARD      = 1
	KEYEVENTF_KEYUP     = 0x0002
	KEYEVENTF_UNICODE   = 0x0004
	VK_RETURN           = 0x0D
	VK_ESCAPE           = 0x1B
	SW_SHOWNORMAL       = 1
	SW_RESTORE          = 9
	COLOR_WINDOW        = 5
	COLOR_BTNFACE       = 15
	MB_ICONWARNING      = 0x30
	MB_ICONERROR        = 0x10
	MB_ICONQUESTION     = 0x20
	MB_YESNO            = 0x04
	IDYES               = 6
	IDOK                = 1
	IDCANCEL            = 2
	WS_POPUP            = 0x80000000
	WS_CAPTION          = 0x00C00000
	WS_SYSMENU          = 0x00080000
	WS_EX_DLGMODALFRAME = 0x00000001
	CBS_DROPDOWN        = 0x0002
	ES_WANTRETURN       = 0x1000
	LB_SETCURSEL        = 0x0186
)

type wndClassEx struct {
	cbSize        uint32
	style         uint32
	lpfnWndProc   uintptr
	cbClsExtra    int32
	cbWndExtra    int32
	hInstance     uintptr
	hIcon         uintptr
	hCursor       uintptr
	hbrBackground uintptr
	lpszMenuName  *uint16
	lpszClassName *uint16
	hIconSm       uintptr
}

type msgT struct {
	hwnd    uintptr
	message uint32
	wParam  uintptr
	lParam  uintptr
	time    uint32
	ptX     int32
	ptY     int32
	private uint32
}

type rectT struct{ left, top, right, bottom int32 }

type actCtx struct {
	cbSize                 uint32
	dwFlags                uint32
	lpSource               *uint16
	wProcessorArchitecture uint16
	wLangId                uint16
	lpAssemblyDirectory    *uint16
	lpResourceName         *uint16
	lpApplicationName      *uint16
	hModule                uintptr
}

type copyDataStruct struct {
	dwData uintptr
	cbData uint32
	lpData uintptr
}

type keybdInput struct {
	wVk         uint16
	wScan       uint16
	dwFlags     uint32
	time        uint32
	dwExtraInfo uintptr
}

type inputT struct { // sizeof(INPUT)=40 on x64
	typ uint32
	_   uint32
	ki  keybdInput
	_   [8]byte
}

type openFileName struct {
	lStructSize       uint32
	hwndOwner         uintptr
	hInstance         uintptr
	lpstrFilter       *uint16
	lpstrCustomFilter *uint16
	nMaxCustFilter    uint32
	nFilterIndex      uint32
	lpstrFile         *uint16
	nMaxFile          uint32
	lpstrFileTitle    *uint16
	nMaxFileTitle     uint32
	lpstrInitialDir   *uint16
	lpstrTitle        *uint16
	Flags             uint32
	nFileOffset       uint16
	nFileExtension    uint16
	lpstrDefExt       *uint16
	lCustData         uintptr
	lpfnHook          uintptr
	lpTemplateName    *uint16
	pvReserved        uintptr
	dwReserved        uint32
	FlagsEx           uint32
}

type browseInfo struct {
	hwndOwner      uintptr
	pidlRoot       uintptr
	pszDisplayName *uint16
	lpszTitle      *uint16
	ulFlags        uint32
	lpfn           uintptr
	lParam         uintptr
	iImage         int32
}

func c(p *syscall.LazyProc, a ...uintptr) uintptr { r, _, _ := p.Call(a...); return r }

func ws(s string) *uint16 {
	p, _ := syscall.UTF16PtrFromString(strings.ReplaceAll(s, "\x00", ""))
	return p
}

func getText(h uintptr) string {
	n := c(pGetWindowTextLengthW, h)
	buf := make([]uint16, n+1)
	c(pGetWindowTextW, h, uintptr(P(&buf[0])), n+1)
	return syscall.UTF16ToString(buf)
}

func setText(h uintptr, s string) { c(pSetWindowTextW, h, uintptr(P(ws(s)))) }

func msgBox(text string, flags uintptr) uintptr {
	return c(pMessageBoxW, topOwner(), uintptr(P(ws(text))), uintptr(P(ws(appTitle))), flags)
}

func ask(text string) bool { return msgBox(text, MB_YESNO|MB_ICONQUESTION) == IDYES }

type ChoiceItem struct {
	Value string `json:"value"`
	Label string `json:"label"`
}

type Option struct {
	Key     string            `json:"key"`
	Label   string            `json:"label"`
	Type    string            `json:"type"`
	Hint    string            `json:"hint,omitempty"`
	Default interface{}       `json:"default"`
	Values  []json.RawMessage `json:"values,omitempty"`
	Var     string            `json:"var,omitempty"` // 연결할 AutoLISP 전역변수 (예: *TEE-RADIUS*)
}

func (o Option) items() []ChoiceItem {
	var out []ChoiceItem
	for _, raw := range o.Values {
		var s string
		if json.Unmarshal(raw, &s) == nil {
			out = append(out, ChoiceItem{s, s})
			continue
		}
		var ci ChoiceItem
		if json.Unmarshal(raw, &ci) == nil {
			if ci.Label == "" {
				ci.Label = ci.Value
			}
			out = append(out, ci)
		}
	}
	return out
}

func toStr(v interface{}) string {
	switch x := v.(type) {
	case nil:
		return ""
	case string:
		return x
	case float64:
		return strconv.FormatFloat(x, 'f', -1, 64)
	case bool:
		if x {
			return "1"
		}
		return "0"
	}
	return fmt.Sprint(v)
}

func toBool(v interface{}) bool {
	switch x := v.(type) {
	case bool:
		return x
	case float64:
		return x != 0
	case string:
		return x == "1" || strings.EqualFold(x, "true")
	}
	return false
}

func toCP949(s string) []byte {
	u := utf16.Encode([]rune(s))
	if len(u) == 0 {
		return nil
	}
	n := c(pWideCharToMultiByte, 949, 0, uintptr(P(&u[0])), uintptr(len(u)), 0, 0, 0, 0)
	if n == 0 {
		return []byte(s)
	}
	out := make([]byte, n)
	c(pWideCharToMultiByte, 949, 0, uintptr(P(&u[0])), uintptr(len(u)), uintptr(P(&out[0])), n, 0, 0)
	return out
}

func s(v int) uintptr { return uintptr(int(float64(v) * scale)) }

func mk(class, text string, style, ex uint32, id int) uintptr {
	return mkp(hMain, class, text, style, ex, id)
}

func mkp(parent uintptr, class, text string, style, ex uint32, id int) uintptr {
	h := c(pCreateWindowExW, uintptr(ex), uintptr(P(ws(class))), uintptr(P(ws(text))),
		uintptr(style|WS_CHILD|WS_VISIBLE), 0, 0, 10, 10, parent, uintptr(id), hInst, 0)
	c(pSendMessageW, h, WM_SETFONT, hFont, 1)
	return h
}

func mv(h uintptr, x, y, w, hh int) { c(pMoveWindow, h, s(x), s(y), s(w), s(hh), 1) }

func isChecked(h uintptr) bool { return c(pSendMessageW, h, BM_GETCHECK, 0, 0) == 1 }
func setCheck(h uintptr, b bool) {
	v := uintptr(0)
	if b {
		v = 1
	}
	c(pSendMessageW, h, BM_SETCHECK, v, 0)
}

func comboFill(h uintptr, items []string, sel int) {
	c(pSendMessageW, h, CB_RESETCONTENT, 0, 0)
	for _, it := range items {
		c(pSendMessageW, h, CB_ADDSTRING, 0, uintptr(P(ws(it))))
	}
	if sel >= 0 {
		c(pSendMessageW, h, CB_SETCURSEL, uintptr(sel), 0)
	}
}

func comboSel(h uintptr) int { return int(int32(c(pSendMessageW, h, CB_GETCURSEL, 0, 0))) }

func indexOf(list []string, v string) int {
	for i, x := range list {
		if x == v {
			return i
		}
	}
	return 0
}

func max(a, b int) int {
	if a > b {
		return a
	}
	return b
}

const manifest = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">
<dependency><dependentAssembly>
<assemblyIdentity type="win32" name="Microsoft.Windows.Common-Controls" version="6.0.0.0"
 processorArchitecture="*" publicKeyToken="6595b64144ccf1df" language="*"/>
</dependentAssembly></dependency>
</assembly>`

func enableVisualStyles() {
	path := filepath.Join(os.TempDir(), "cad_launcher.manifest")
	if os.WriteFile(path, []byte(manifest), 0644) != nil {
		return
	}
	ac := actCtx{lpSource: ws(path)}
	ac.cbSize = uint32(unsafe.Sizeof(ac))
	h := c(pCreateActCtxW, uintptr(P(&ac)))
	if h != 0 && h != ^uintptr(0) {
		var cookie uintptr
		c(pActivateActCtx, h, uintptr(P(&cookie)))
	}
}

const (
	TVS_HASBUTTONS    = 0x0001
	TVS_HASLINES      = 0x0002
	TVS_LINESATROOT   = 0x0004
	TVS_SHOWSELALWAYS = 0x0020

	TVM_DELETEITEM    = 0x1101
	TVM_EXPAND        = 0x1102
	TVM_SELECTITEM    = 0x110B
	TVM_HITTEST       = 0x1111
	TVM_ENSUREVISIBLE = 0x1114
	TVM_INSERTITEMW   = 0x1132

	TVGN_DROPHILITE = 0x0008
	TVGN_CARET      = 0x0009
	TVE_COLLAPSE    = 0x0001
	TVE_EXPAND      = 0x0002

	TVIF_TEXT     = 0x0001
	TVIF_STATE    = 0x0008
	TVIS_BOLD     = 0x0010
	TVIS_EXPANDED = 0x0020

	TVHT_ABOVE   = 0x0100
	TVHT_BELOW   = 0x0200
	TVHT_TORIGHT = 0x0400
	TVHT_TOLEFT  = 0x0800

	WM_NOTIFY         = 0x004E
	WM_MOUSEMOVE      = 0x0200
	WM_LBUTTONUP      = 0x0202
	WM_CAPTURECHANGED = 0x0215

	tvnSelChanged   = -451 // TVN_SELCHANGEDW
	tvnItemExpanded = -455 // TVN_ITEMEXPANDEDW
	tvnBeginDrag    = -456 // TVN_BEGINDRAGW
	nmDblClk        = -3
)

type nmhdr struct {
	hwndFrom uintptr
	idFrom   uintptr
	code     uint32
}

type tvItem struct {
	mask           uint32
	hItem          uintptr
	state          uint32
	stateMask      uint32
	pszText        *uint16
	cchTextMax     int32
	iImage         int32
	iSelectedImage int32
	cChildren      int32
	lParam         uintptr
}

type nmTreeView struct {
	hdr     nmhdr
	action  uint32
	itemOld tvItem
	itemNew tvItem
	ptDrag  [2]int32
}

type tvInsert struct {
	hParent      uintptr
	hInsertAfter uintptr
	item         tvItem
	_            [24]byte // TVITEMEX 크기 맞춤
}

type tvHit struct {
	x, y  int32
	flags uint32
	hItem uintptr
}

var tviRoot = ^uintptr(0xFFFF) // TVI_ROOT  (-0x10000)
var tviLast = ^uintptr(0xFFFD) // TVI_LAST  (-0xFFFE)

var _ = fmt.Sprint
var _ = os.Getenv
var _ = filepath.Join
var _ = strconv.Itoa
