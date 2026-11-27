package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"syscall"
	"unicode/utf16"
	"unsafe"
)

var identRe = regexp.MustCompile(`^[A-Za-z0-9_\-.:]+$`)

func itoa(n int) string { return strconv.Itoa(n) }

func parseFloat(v string) (float64, error) { return strconv.ParseFloat(v, 64) }

var defunRe = regexp.MustCompile(`(?i)\(\s*defun\s+c:([A-Za-z0-9_\-.]+)`)

func lispFuncs(path string) []string {
	if path == "" {
		return nil
	}
	if !filepath.IsAbs(path) {
		path = filepath.Join(appDir, path)
	}
	b, err := os.ReadFile(path)
	if err != nil {
		return nil
	}
	seen := map[string]bool{}
	var out []string
	for _, m := range defunRe.FindAllSubmatch(b, -1) {
		n := strings.ToUpper(string(m[1]))
		if !seen[n] && n != "LO_SHOW" {
			seen[n] = true
			out = append(out, n)
		}
	}
	return out
}

func relPath(p string) string {
	if rel, err := filepath.Rel(appDir, p); err == nil && !strings.HasPrefix(rel, "..") {
		return filepath.ToSlash(rel)
	}
	return filepath.ToSlash(p)
}

func isHelper(p string) bool {
	return strings.EqualFold(filepath.Base(filepath.FromSlash(p)), "launcher_opt.lsp")
}

func getLispList(raw json.RawMessage) []string {
	var list []string
	var one string
	if len(raw) == 0 {
		return nil
	}
	if json.Unmarshal(raw, &one) == nil {
		return []string{one}
	}
	_ = json.Unmarshal(raw, &list)
	return list
}

func setLispList(list []string) json.RawMessage {
	if len(list) == 0 {
		return nil
	}
	b, _ := json.Marshal(list)
	return b
}

// ───────────────────────── 모달 창 ─────────────────────────
type dialog struct {
	h, owner uintptr
	done, ok bool
	onCmd    func(id, code int)
	defID    int               // Enter 키로 눌리는 기본 버튼 id
	paint    func(hdc uintptr) // 컨트롤 테두리를 그린 뒤 추가로 그릴 것 (질문 창의 띠·테두리 등)
	onSize   func(w, h int)    // 크기 조절 가능한 창: 바뀐 크기(96DPI 기준)로 컨트롤 다시 배치
	minW     int32             // 크기 조절 가능한 창의 최소 크기(픽셀, 창 테두리 포함)
	minH     int32
}

var (
	dialogs  = map[uintptr]*dialog{}
	dlgStack []*dialog
	dlgClass = ws("CADLauncherDlg")
)

func topOwner() uintptr {
	if n := len(dlgStack); n > 0 {
		return dlgStack[n-1].h
	}
	return hMain
}

func dlgProc(h, msg, wp, lp uintptr) uintptr {
	d := dialogs[h]
	switch msg {
	case WM_COMMAND:
		id, code := int(wp&0xFFFF), int((wp>>16)&0xFFFF)
		if d != nil {
			if id == IDCANCEL {
				d.done = true
				return 0
			}
			if d.onCmd != nil {
				d.onCmd(id, code)
			}
		}
		return 0
	case WM_CTLCOLORSTATIC:
		return ctlColor(wp, lp)
	case WM_CTLCOLOREDIT, WM_CTLCOLORLISTBOX:
		return editColor(wp)
	case WM_ERASEBKGND:
		return eraseBg(h, wp)
	case WM_DRAWITEM:
		return drawButton(lp)
	case WM_PAINT:
		paintFrames(h)
		if d != nil && d.paint != nil {
			hdc := c(pGetDC, h)
			d.paint(hdc)
			c(pReleaseDC, h, hdc)
		}
		return 0
	case WM_SIZE:
		if d != nil && d.onSize != nil {
			d.onSize(int(float64(lp&0xFFFF)/scale), int(float64((lp>>16)&0xFFFF)/scale))
			c(pInvalidateRect, h, 0, 1)
		}
		return 0
	case WM_GETMINMAXINFO:
		if d != nil && d.minW > 0 {
			pt := (*[2]int32)(P(lp + 24)) // ptMinTrackSize
			pt[0], pt[1] = d.minW, d.minH
			return 0
		}
	case DM_GETDEFID: // 직접 그리는 버튼은 '기본 버튼' 표시가 없으므로 Enter 키 대상을 알려 준다
		if d != nil && d.defID != 0 {
			return DC_HASDEFID<<16 | uintptr(d.defID)
		}
	case WM_CLOSE:
		if d != nil {
			d.done = true
		}
		return 0
	}
	return c(pDefWindowProcW, h, msg, wp, lp)
}

func registerDialogClass() {
	wc := wndClassEx{
		lpfnWndProc:   syscall.NewCallback(dlgProc),
		hInstance:     hInst,
		hCursor:       c(pLoadCursorW, 0, 32512),
		hbrBackground: hBgBrush,
		lpszClassName: dlgClass,
	}
	wc.cbSize = uint32(unsafe.Sizeof(wc))
	c(pRegisterClassExW, uintptr(P(&wc)))
}

func newDialog(title string, w, h int) *dialog {
	return newDialogStyle(title, w, h, false)
}

// resizable: 테두리를 끌어 크기 조절 + 최대화 버튼. 처음 크기가 최소 크기.
func newDialogStyle(title string, w, h int, resizable bool) *dialog {
	owner := topOwner()
	style := uint32(WS_POPUP | WS_CAPTION | WS_SYSMENU)
	if resizable {
		style |= 0x00040000 | 0x00010000 // WS_THICKFRAME | WS_MAXIMIZEBOX
	}
	r := rectT{0, 0, int32(s(w)), int32(s(h))}
	c(pAdjustWindowRectEx, uintptr(P(&r)), uintptr(style), 0, WS_EX_DLGMODALFRAME)
	ow, oh := r.right-r.left, r.bottom-r.top
	var or rectT
	c(pGetWindowRect, owner, uintptr(P(&or)))
	x := or.left + (or.right-or.left-ow)/2
	y := or.top + (or.bottom-or.top-oh)/2
	if y < 0 {
		y = 0
	}
	hwnd := c(pCreateWindowExW, WS_EX_DLGMODALFRAME, uintptr(P(dlgClass)), uintptr(P(ws(title))), uintptr(style),
		uintptr(x), uintptr(y), uintptr(ow), uintptr(oh), owner, 0, hInst, 0)
	styleWindow(hwnd)
	d := &dialog{h: hwnd, owner: owner}
	if resizable {
		d.minW, d.minH = ow*80/100, oh // 높이는 처음 크기보다 줄이지 않음 (내용이 잘리지 않게)
	}
	dialogs[hwnd] = d
	return d
}

func (d *dialog) mk(class, text string, style, ex uint32, id int) uintptr {
	return mkp(d.h, class, text, style, ex, id)
}

func (d *dialog) label(text string, x, y, w int) uintptr {
	h := d.mk("STATIC", text, SS_LEFT, 0, 0)
	mv(h, x, y, w, 20)
	return h
}

func (d *dialog) note(text string, x, y, w, hh int) uintptr {
	h := d.mk("STATIC", text, SS_LEFT, 0, 0)
	grey[h] = true
	mv(h, x, y, w, hh)
	return h
}

func (d *dialog) edit(text string, x, y, w int) uintptr {
	h := d.mk("EDIT", text, ES_AUTOHSCROLL|WS_TABSTOP, WS_EX_CLIENTEDGE, 0)
	mv(h, x, y, w, 24)
	return h
}

func (d *dialog) button(text string, id, x, y, w int, def bool) uintptr {
	st := uint32(WS_TABSTOP)
	if def {
		st |= BS_DEFPUSHBUTTON
		d.defID = id
	}
	h := d.mk("BUTTON", text, st, 0, id)
	mv(h, x, y, w, 28)
	return h
}

func (d *dialog) run(focus uintptr) bool {
	dlgStack = append(dlgStack, d)
	c(pEnableWindow, d.owner, 0)
	c(pShowWindow, d.h, SW_SHOWNORMAL)
	if focus != 0 {
		c(pSetFocus, focus)
	}
	var m msgT
	for !d.done {
		if int32(c(pGetMessageW, uintptr(P(&m)), 0, 0, 0)) <= 0 {
			c(pPostQuitMessage, 0)
			break
		}
		if eatEscape(&m) || c(pIsDialogMessageW, d.h, uintptr(P(&m))) != 0 {
			continue
		}
		c(pTranslateMessage, uintptr(P(&m)))
		c(pDispatchMessageW, uintptr(P(&m)))
	}
	c(pEnableWindow, d.owner, 1)
	c(pSetForegroundWindow, d.owner)
	c(pDestroyWindow, d.h)
	delete(dialogs, d.h)
	dlgStack = dlgStack[:len(dlgStack)-1]
	return d.ok
}

func openLispFile(owner uintptr) string {
	buf := make([]uint16, 1024)
	filter := utf16.Encode([]rune("리습 파일 (*.lsp)\x00*.lsp\x00모든 파일\x00*.*\x00\x00"))
	init := ws(lspDir)
	ofn := openFileName{hwndOwner: owner, lpstrFilter: &filter[0], lpstrFile: &buf[0], nMaxFile: uint32(len(buf)),
		lpstrInitialDir: init, Flags: 0x00001000 | 0x00000008 | 0x00080000}
	ofn.lStructSize = uint32(unsafe.Sizeof(ofn))
	ok := c(pGetOpenFileNameW, uintptr(P(&ofn)))
	_ = filter
	if ok == 0 {
		return ""
	}
	return syscall.UTF16ToString(buf)
}

// 런처 폴더 밖의 리습이면 lsp 폴더로 복사할지 묻는다 → 저장할 경로 반환
func adoptLisp(p string) string {
	rel, err := filepath.Rel(appDir, p)
	if err == nil && !strings.HasPrefix(rel, "..") {
		return filepath.ToSlash(rel)
	}
	if !ask(T("dialogs.001") + p) {
		return filepath.ToSlash(p)
	}
	dst := filepath.Join(lspDir, filepath.Base(p))
	if _, err := os.Stat(dst); err == nil {
		if !ask(T("dialogs.002") + filepath.Base(p)) {
			return relPath(dst)
		}
	}
	_ = os.MkdirAll(lspDir, 0755)
	b, err := os.ReadFile(p)
	if err == nil {
		err = os.WriteFile(dst, b, 0644)
	}
	if err != nil {
		msgBox(T("dialogs.003")+err.Error(), MB_ICONERROR)
		return filepath.ToSlash(p)
	}
	return relPath(dst)
}

// ───────────────────────── 설정 창 ─────────────────────────
// 평소에는 거의 건드릴 일이 없는 설정(전송 방식·취소·항상 위·인코딩)과
// 직접 명령 입력을 메인 화면에서 빼서 여기에 모아둔다.
func advancedDialog() {
	d := newDialogStyle(T("dialogs.004"), 860, 600, true)
	// 구역 제목: 굵은 글씨, 폭은 글자만큼 (오른쪽에 구분선을 그림)
	var heads []uintptr
	head := func(t string) uintptr {
		h := d.label(t, 0, 0, 10)
		c(pSendMessageW, h, WM_SETFONT, hFontBtnBold, 1)
		heads = append(heads, h)
		return h
	}
	label := func(t string) uintptr { return d.label(t, 0, 0, 10) }
	hint := func(t string) uintptr { return d.note(t, 0, 0, 10, 20) }
	check := func(t string, id int, on bool) uintptr {
		h := d.mk("BUTTON", t, BS_AUTOCHECKBOX|WS_TABSTOP, 0, id)
		setCheck(h, on)
		return h
	}
	combo := func(id int, items []string, sel int) uintptr {
		h := d.mk("COMBOBOX", "", CBS_DROPDOWNLIST|WS_TABSTOP, 0, id)
		comboFill(h, items, sel)
		return h
	}
	readSettings()

	// ── 왼쪽 단: 화면 / CAD 연결 / 직접 명령 ──
	hHeadView := head(T("dialogs.090"))
	hLblFont := label(T("dialogs.091"))
	hFontSel := combo(idAdvFont, []string{T("dialogs.094"), T("dialogs.095"), T("dialogs.096"), T("dialogs.097"), T("dialogs.098")}, fontLevel()-1)
	hNoteFont := hint(T("dialogs.092"))
	fontChanged := false
	hTop := check(T("dialogs.011"), idAdvTop, st.Topmost)

	hHeadSend := head(T("dialogs.005"))
	hLblMethod := label(T("dialogs.006"))
	hMethod := combo(idAdvMethod, methods, indexOf(methods, st.Method))
	hNoteMethod := hint(T("dialogs.007"))
	hLblKw2 := label(T("dialogs.008"))
	hKw2 := d.mk("EDIT", st.Keyword, ES_AUTOHSCROLL|WS_TABSTOP, WS_EX_CLIENTEDGE, idAdvKw)
	kwVal := st.Keyword
	hNoteKw := hint(T("dialogs.009"))
	hCancel := check(T("dialogs.010"), idAdvCancel, st.Cancel)

	hHeadFree := head(T("dialogs.026"))
	hFree := d.edit("", 0, 0, 10)
	hSend := d.button(T("dialogs.027"), idAdvSend, 0, 0, 90, true)
	hNoteFree := hint(T("dialogs.028"))

	// ── 오른쪽 단: 업데이트 / AutoCAD ──
	hHeadUpd := head(T("dialogs.012"))
	hAuto := check(T("dialogs.013"), idAdvAuto, st.AutoUpdate)
	hNoteAuto := hint(T("dialogs.099"))
	pcDate := fmtStamp(st.LastUpdate)
	if pcDate == "" {
		if fi, err := os.Stat(catalogPath); err == nil {
			pcDate = fi.ModTime().Format("2006-01-02 15:04") + T("dialogs.016")
		} else {
			pcDate = T("dialogs.017")
		}
	}
	ghDate := fmtStamp(st.GitHubDate)
	if ghDate == "" {
		ghDate = T("dialogs.018")
	}
	ckDate := fmtStamp(st.LastCheck)
	if ckDate == "" {
		ckDate = T("dialogs.017")
	}
	type infoRow struct{ k, v uintptr }
	info := []infoRow{
		{hint(T("dialogs.020")), label(pcDate)},
		{hint(T("dialogs.021")), label(ghDate)},
		{hint(T("dialogs.100")), label(ckDate)},
		{hint(T("dialogs.014")), hint("github.com/" + fixedRepo + " (" + fixedBranch + ")")},
	}
	var hNoteLocal uintptr
	if localCatalogChanged() {
		k := "dialogs.015"
		if lockedRelease() {
			k = "dialogs.112" // 배포용: 다음 확인 때 원래대로 되돌림
		}
		hNoteLocal = hint(strings.TrimPrefix(T(k), "\n"))
	}

	// GitHub 토큰 (선택): 설정 창에는 상태만 보이고, 입력은 [토큰 설정…] 버튼으로 여는 작은 창에서
	hLblTok := label(T("dialogs.101"))
	hTokBtn := d.button(T("dialogs.105"), idAdvToken, 0, 0, 10, false)
	tokState := func() string {
		if st.Token != "" {
			return T("dialogs.106")
		}
		return T("dialogs.107")
	}
	hTokState := hint(tokState())

	hHeadCad := head("AutoCAD")
	hTrust := check(T("dialogs.022"), idAdvTrust, st.Trust != "no")
	hNoteTrust := hint(T("dialogs.023"))
	hLblEnc := label(T("dialogs.024"))
	hEnc := combo(idAdvEnc, encodings, indexOf(encodings, st.Encoding))
	hNoteEnc := hint(T("dialogs.025"))

	hClose := d.button(T("dialogs.029"), IDCANCEL, 0, 0, 95, false)

	// 구역 제목 오른쪽 구분선 + 닫기 버튼 위 선 (컨트롤이 없는 자리에만 그림)
	var lines []rectT
	d.paint = func(hdc uintptr) {
		br := c(pCreateSolidBrush, clrBorder)
		for _, r := range lines {
			rr := rectT{int32(s(int(r.left))), int32(s(int(r.top))), int32(s(int(r.right))), int32(s(int(r.top))) + 1}
			c(pFillRect, hdc, uintptr(P(&rr)), br)
		}
		c(pDeleteObject, br)
	}

	// 설명 글이 칸 폭보다 길면 두 줄 높이
	noteH := func(h uintptr, w int) int {
		if textW(h, hFont) > w-4 {
			return 38
		}
		return 20
	}

	// 배치: 두 단, 각 단은 [이름 칸 | 입력 칸], 설명은 입력 칸 아래 회색 글씨
	const pad, gap, lblW = 20, 28, 118
	d.onSize = func(W, H int) {
		lines = lines[:0]
		colW := (W - pad*2 - gap) / 2
		type col struct{ x, y int }
		sec := func(cl *col, h uintptr) {
			tw := textW(h, hFontBtnBold) + 4
			mv(h, cl.x, cl.y, tw, 22)
			lines = append(lines, rectT{int32(cl.x + tw + 8), int32(cl.y + 11), int32(cl.x + colW), 0})
			cl.y += 32
		}
		row := func(cl *col, lbl, ctl uintptr, ctlW, ctlH int, note uintptr) {
			cx := cl.x + lblW
			if ctlW <= 0 {
				ctlW = colW - lblW
			}
			mv(lbl, cl.x, cl.y+4, lblW-6, 22)
			mv(ctl, cx, cl.y, ctlW, ctlH)
			cl.y += 30
			if note != 0 {
				nh := noteH(note, colW-lblW)
				mv(note, cx, cl.y-2, colW-lblW, nh)
				cl.y += nh + 2
			}
		}
		chk := func(cl *col, h, note uintptr) {
			mv(h, cl.x, cl.y, colW, 24)
			cl.y += 26
			if note != 0 {
				nh := noteH(note, colW-20)
				mv(note, cl.x+20, cl.y-2, colW-20, nh)
				cl.y += nh + 2
			}
		}

		L := &col{pad, 16}
		sec(L, hHeadView)
		row(L, hLblFont, hFontSel, 160, 300, hNoteFont)
		chk(L, hTop, 0)
		L.y += 16
		sec(L, hHeadSend)
		row(L, hLblMethod, hMethod, 160, 300, hNoteMethod)
		row(L, hLblKw2, hKw2, 160, 24, hNoteKw)
		chk(L, hCancel, 0)
		L.y += 16
		sec(L, hHeadFree)
		ew := max(colW-98, 80)
		mv(hFree, L.x, L.y, ew, 24)
		mv(hSend, L.x+ew+8, L.y-2, 90, 28)
		L.y += 30
		mv(hNoteFree, L.x, L.y-2, colW, noteH(hNoteFree, colW))

		R := &col{pad + colW + gap, 16}
		sec(R, hHeadUpd)
		chk(R, hAuto, hNoteAuto)
		R.y += 4
		for _, ir := range info {
			mv(ir.k, R.x+20, R.y, lblW+20, 20)
			mv(ir.v, R.x+20+lblW+24, R.y, colW-lblW-44, 20)
			R.y += 22
		}
		if hNoteLocal != 0 {
			mv(hNoteLocal, R.x+20, R.y+2, colW-20, 40)
			R.y += 44
		}
		R.y += 6
		tokY := R.y
		row(R, hLblTok, hTokBtn, 120, 28, 0)
		mv(hTokState, R.x+lblW+130, tokY+5, colW-lblW-130, 20) // 버튼 오른쪽: 설정됨 / 설정 안 됨
		R.y += 16
		sec(R, hHeadCad)
		chk(R, hTrust, hNoteTrust)
		R.y += 4
		row(R, hLblEnc, hEnc, 110, 300, hNoteEnc)

		lines = append(lines, rectT{int32(pad), int32(H - 58), int32(W - pad), 0})
		mv(hClose, W-pad-95, H-16-30, 95, 30)
	}
	var cr rectT
	c(pGetClientRect, d.h, uintptr(P(&cr)))
	d.onSize(int(float64(cr.right)/scale), int(float64(cr.bottom)/scale))

	d.onCmd = func(id, code int) {
		switch {
		case id == idAdvToken && code == BN_CLICKED:
			if tokenDialog() {
				setText(hTokState, tokState())
			}
		case id == idAdvKw && code == 0x0300: // EN_CHANGE (창이 닫히면 글자를 못 읽으므로 바뀔 때마다 보관)
			kwVal = getText(hKw2)
		case id == idAdvMethod && code == CBN_SELCHANGE:
			if i := comboSel(hMethod); i >= 0 {
				st.Method = methods[i]
			}
		case id == idAdvEnc && code == CBN_SELCHANGE:
			if i := comboSel(hEnc); i >= 0 {
				st.Encoding = encodings[i]
			}
		case id == idAdvCancel && code == BN_CLICKED:
			st.Cancel = isChecked(hCancel)
		case id == idAdvTrust && code == BN_CLICKED:
			st.Trust = "no"
			if isChecked(hTrust) {
				st.Trust = "yes"
			}
			saveState()
		case id == idAdvAuto && code == BN_CLICKED:
			st.AutoUpdate = isChecked(hAuto)
			saveState()
		case id == idAdvFont && code == CBN_SELCHANGE:
			if i := comboSel(hFontSel); i >= 0 && i+1 != fontLevel() {
				st.FontLevel = i + 1
				saveState()
				fontChanged = true
			}
		case id == idAdvTop && code == BN_CLICKED:
			st.Topmost = isChecked(hTop)
			applyTopmost()
		case id == idAdvSend && code == BN_CLICKED:
			sendFreeFrom(hFree)
		}
	}
	d.run(hFree)
	// 글자 크기는 글꼴을 처음에 만들므로 다시 켜야 적용됨
	if fontChanged && ask(T("dialogs.093")) {
		c(pShellExecuteW, 0, uintptr(P(ws("open"))), uintptr(P(ws(exePath))), 0, uintptr(P(ws(appDir))), SW_SHOWNORMAL)
		c(pPostMessageW, hMain, WM_CLOSE, 0, 0)
	}
	// 창 제목 키워드가 바뀌었으면 CAD 창을 다시 찾음
	if kw := strings.TrimSpace(kwVal); kw != "" && kw != st.Keyword {
		st.Keyword = kw
		setText(hKeyword, kw)
		saveState()
		refreshWindows()
	}
}

var typeCodes = []string{"text", "number", "int", "check", "choice", "file", "folder"}
var typeNames = []string{T("dialogs.030"), T("dialogs.031"), T("dialogs.032"), T("dialogs.033"), T("dialogs.034"), T("dialogs.035"), T("dialogs.036")}

func typeName(t string) string {
	for i, c := range typeCodes {
		if c == t {
			return typeNames[i]
		}
	}
	return T("dialogs.037")
}

func escNL(s string) string   { return strings.ReplaceAll(s, "\n", `\n`) }
func unescNL(s string) string { return strings.ReplaceAll(s, `\n`, "\n") }

// ───────────────────────── 옵션 편집 창 ─────────────────────────
var keyRe = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_]*$`)

func editOptionDialog(o *Option, all []Option, self int) bool {
	d := newDialog(T("dialogs.038"), 480, 440)
	const lx, ex, ew = 14, 110, 350

	d.label(T("dialogs.039"), lx, 16, 90)
	hKey := d.edit(o.Key, ex, 12, 160)
	d.note(T("dialogs.040"), ex+168, 16, ew-168, 20)
	d.label(T("dialogs.041"), lx, 48, 90)
	hLabel := d.edit(o.Label, ex, 44, ew)
	d.label(T("dialogs.042"), lx, 80, 90)
	hType := d.mk("COMBOBOX", "", CBS_DROPDOWNLIST|WS_TABSTOP, 0, 401)
	mv(hType, ex, 76, 160, 220)
	ti := 0
	for i, t := range typeCodes {
		if t == o.Type {
			ti = i
		}
	}
	comboFill(hType, typeNames, ti)
	d.label(T("dialogs.043"), lx, 112, 90)
	hDef := d.edit(toStr(o.Default), ex, 108, ew)
	d.note(T("dialogs.044"), ex, 136, ew, 18)
	d.label(T("dialogs.045"), lx, 164, 90)
	hHint := d.edit(o.Hint, ex, 160, ew)

	d.label(T("dialogs.046"), lx, 196, 90)
	hVar := d.edit(o.Var, ex, 192, 200)
	d.note(T("dialogs.047"), ex+206, 196, ew-206, 20)
	d.label(T("dialogs.048"), lx, 228, 90)
	var lines []string
	for _, it := range o.items() {
		if it.Label == it.Value {
			lines = append(lines, it.Value)
		} else {
			lines = append(lines, it.Value+"="+it.Label)
		}
	}
	hVals := d.mk("EDIT", strings.Join(lines, "\r\n"),
		ES_MULTILINE|ES_AUTOVSCROLL|ES_WANTRETURN|WS_VSCROLL|WS_TABSTOP, WS_EX_CLIENTEDGE, 0)
	mv(hVals, ex, 224, ew, 110)
	d.note(T("dialogs.049"), ex, 338, ew, 34)

	d.button(T("dialogs.050"), IDOK, 270, 396, 95, true)
	d.button(T("dialogs.051"), IDCANCEL, 370, 396, 95, false)

	d.onCmd = func(id, code int) {
		if id != IDOK {
			return
		}
		key := strings.TrimSpace(getText(hKey))
		if key == "" && strings.TrimSpace(getText(hVar)) != "" { // 변수 연결이면 키 자동 생성
			key = strings.Trim(regexp.MustCompile(`[^A-Za-z0-9]+`).ReplaceAllString(getText(hVar), "_"), "_")
			if key == "" || (key[0] >= '0' && key[0] <= '9') {
				key = "v_" + key
			}
		}
		if !keyRe.MatchString(key) {
			msgBox(T("dialogs.052"), MB_ICONWARNING)
			return
		}
		for i, x := range all {
			if i != self && strings.EqualFold(x.Key, key) {
				msgBox(T("dialogs.053")+key, MB_ICONWARNING)
				return
			}
		}
		typ := "text"
		if i := comboSel(hType); i >= 0 {
			typ = typeCodes[i]
		}
		def := strings.TrimSpace(getText(hDef))
		var vals []json.RawMessage
		if typ == "choice" {
			for _, ln := range strings.Split(strings.ReplaceAll(getText(hVals), "\r", ""), "\n") {
				ln = strings.TrimSpace(ln)
				if ln == "" {
					continue
				}
				v, l := ln, ln
				if k := strings.Index(ln, "="); k > 0 {
					v, l = strings.TrimSpace(ln[:k]), strings.TrimSpace(ln[k+1:])
				}
				var b []byte
				if v == l {
					b, _ = json.Marshal(v)
				} else {
					b, _ = json.Marshal(ChoiceItem{v, l})
				}
				vals = append(vals, b)
			}
			if len(vals) == 0 {
				msgBox(T("dialogs.054"), MB_ICONWARNING)
				return
			}
		}
		if typ == "number" && def != "" {
			if _, err := parseFloat(def); err != nil {
				msgBox(T("dialogs.055"), MB_ICONWARNING)
				return
			}
		}
		label := strings.TrimSpace(getText(hLabel))
		if label == "" {
			label = key
		}
		o.Key, o.Label, o.Type, o.Hint, o.Values = key, label, typ, strings.TrimSpace(getText(hHint)), vals
		o.Var = strings.TrimSpace(getText(hVar))
		if typ == "check" {
			o.Default = toBool(def)
		} else {
			o.Default = def
		}
		d.ok, d.done = true, true
	}
	return d.run(hKey)
}

// GitHub 토큰 입력 창 (설정 창의 [토큰 설정…] 버튼). 저장했거나 지웠으면 true.
// 입력한 글자는 ● 로 가리고, 기존 토큰은 칸에 채우지 않는다 (비워 두고 확인 = 그대로 둠).
func tokenDialog() bool {
	d := newDialog(T("dialogs.108"), 460, 210)
	d.note(T("dialogs.102"), 16, 14, 428, 38)
	d.label(T("dialogs.101"), 16, 62, 100)
	hTok := d.mk("EDIT", "", ES_AUTOHSCROLL|0x0020 /*ES_PASSWORD*/ |WS_TABSTOP, WS_EX_CLIENTEDGE, 0)
	mv(hTok, 110, 58, 334, 24)
	state := T("dialogs.107")
	if st.Token != "" {
		state = T("dialogs.109")
	}
	d.note(state, 110, 86, 334, 20)
	const idClear = 9001
	hClear := d.button(T("dialogs.110"), idClear, 16, 160, 110, false)
	show(hClear, st.Token != "")
	d.button(T("dialogs.050"), IDOK, 250, 160, 95, true)
	d.button(T("dialogs.051"), IDCANCEL, 350, 160, 95, false)
	changed := false
	d.onCmd = func(id, code int) {
		switch id {
		case IDOK:
			if tv := strings.TrimSpace(getText(hTok)); tv != "" && tv != st.Token {
				st.Token = tv
				saveState()
				logf("%s", T("dialogs.103"))
				changed = true
			}
			d.ok, d.done = true, true
		case idClear:
			if ask(T("dialogs.111")) {
				st.Token = ""
				saveState()
				logf("%s", T("dialogs.104"))
				changed = true
				d.ok, d.done = true, true
			}
		}
	}
	d.run(hTok)
	return changed
}
