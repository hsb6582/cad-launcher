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
	defID    int // Enter 키로 눌리는 기본 버튼 id
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
		return 0
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
	owner := topOwner()
	style := uint32(WS_POPUP | WS_CAPTION | WS_SYSMENU)
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
		if c(pIsDialogMessageW, d.h, uintptr(P(&m))) != 0 {
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
	if !ask("이 리습을 런처의 lsp 폴더로 복사할까요?\n(복사하면 런처 폴더째 옮겨도 동작합니다)\n\n" + p) {
		return filepath.ToSlash(p)
	}
	dst := filepath.Join(lspDir, filepath.Base(p))
	if _, err := os.Stat(dst); err == nil {
		if !ask("lsp 폴더에 같은 이름의 파일이 있습니다. 덮어쓸까요?\n" + filepath.Base(p)) {
			return relPath(dst)
		}
	}
	_ = os.MkdirAll(lspDir, 0755)
	b, err := os.ReadFile(p)
	if err == nil {
		err = os.WriteFile(dst, b, 0644)
	}
	if err != nil {
		msgBox("복사 실패\n"+err.Error(), MB_ICONERROR)
		return filepath.ToSlash(p)
	}
	return relPath(dst)
}

// ───────────────────────── 설정 창 ─────────────────────────
// 평소에는 거의 건드릴 일이 없는 설정(전송 방식·취소·항상 위·인코딩)과
// 직접 명령 입력을 메인 화면에서 빼서 여기에 모아둔다.
func advancedDialog() {
	d := newDialog("설정", 480, 392)
	const lx, ex, ew = 14, 150, 310

	d.label("전송 방식", lx, 18, 100)
	hMethod := d.mk("COMBOBOX", "", CBS_DROPDOWNLIST|WS_TABSTOP, 0, idAdvMethod)
	mv(hMethod, ex, 14, 150, 200)
	comboFill(hMethod, methods, indexOf(methods, st.Method))
	d.note("WM_COPYDATA가 안 먹히면 '키입력'으로 바꿔보세요", ex+158, 18, ew-158, 36)

	hCancel := d.mk("BUTTON", "실행 전 진행 중 명령 취소", BS_AUTOCHECKBOX|WS_TABSTOP, 0, idAdvCancel)
	mv(hCancel, lx, 56, 300, 22)
	setCheck(hCancel, st.Cancel)

	hTop := d.mk("BUTTON", "항상 위 (런처 창을 다른 창 위에 고정)", BS_AUTOCHECKBOX|WS_TABSTOP, 0, idAdvTop)
	mv(hTop, lx, 84, 320, 22)
	setCheck(hTop, st.Topmost)

	hAuto := d.mk("BUTTON", "런처를 켤 때 자동으로 업데이트 확인", BS_AUTOCHECKBOX|WS_TABSTOP, 0, idAdvAuto)
	mv(hAuto, lx, 112, 320, 22)
	setCheck(hAuto, st.AutoUpdate)
	upd := "받는 곳: github.com/" + fixedRepo + " (" + fixedBranch + ")"
	if localCatalogChanged() {
		upd += "\n※ 이 PC에서 리습 목록을 수정했습니다. 다음 업데이트 때 덮어쓸지 물어봅니다."
	}
	d.note(upd, lx+20, 136, 440, 36)

	hTrust := d.mk("BUTTON", "런처 폴더를 AutoCAD '신뢰할 수 있는 위치'에 자동 추가", BS_AUTOCHECKBOX|WS_TABSTOP, 0, idAdvTrust)
	mv(hTrust, lx, 176, 440, 22)
	setCheck(hTrust, st.Trust != "no")
	d.note("끄면 리습 로드가 '파일 로드 취소됨'으로 막힐 수 있습니다", lx+20, 198, 440, 20)

	d.label("옵션파일 인코딩", lx, 232, 105)
	hEnc := d.mk("COMBOBOX", "", CBS_DROPDOWNLIST|WS_TABSTOP, 0, idAdvEnc)
	mv(hEnc, ex, 228, 100, 200)
	comboFill(hEnc, encodings, indexOf(encodings, st.Encoding))
	d.note("보통 cp949 그대로 두세요 (한글이 깨질 때만 utf-8)", ex+108, 232, ew-108, 20)

	d.label("직접 명령", lx, 274, 100)
	hFree := d.edit("", ex, 270, 230)
	d.button("보내기", idAdvSend, ex+238, 269, 90, true)
	d.note("목록에 없는 명령어를 바로 AutoCAD로 보냅니다", ex, 298, ew, 20)

	d.button("닫기", IDCANCEL, 370, 346, 95, false)

	d.onCmd = func(id, code int) {
		switch {
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
		case id == idAdvTop && code == BN_CLICKED:
			st.Topmost = isChecked(hTop)
			applyTopmost()
		case id == idAdvSend && code == BN_CLICKED:
			sendFreeFrom(hFree)
		}
	}
	d.run(hFree)
}

var typeCodes = []string{"text", "number", "int", "check", "choice", "file", "folder"}
var typeNames = []string{"문자", "실수", "정수", "체크", "선택목록", "파일 경로", "폴더 경로"}

func typeName(t string) string {
	for i, c := range typeCodes {
		if c == t {
			return typeNames[i]
		}
	}
	return "문자"
}

func escNL(s string) string   { return strings.ReplaceAll(s, "\n", `\n`) }
func unescNL(s string) string { return strings.ReplaceAll(s, `\n`, "\n") }

// ───────────────────────── 옵션 편집 창 ─────────────────────────
var keyRe = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_]*$`)

func editOptionDialog(o *Option, all []Option, self int) bool {
	d := newDialog("옵션 편집", 480, 440)
	const lx, ex, ew = 14, 110, 350

	d.label("키 (영문)", lx, 16, 90)
	hKey := d.edit(o.Key, ex, 12, 160)
	d.note("리습에서 (LO:get \"키\" …) 로 읽는 이름", ex+168, 16, ew-168, 20)
	d.label("표시 이름", lx, 48, 90)
	hLabel := d.edit(o.Label, ex, 44, ew)
	d.label("종류", lx, 80, 90)
	hType := d.mk("COMBOBOX", "", CBS_DROPDOWNLIST|WS_TABSTOP, 0, 401)
	mv(hType, ex, 76, 160, 220)
	ti := 0
	for i, t := range typeCodes {
		if t == o.Type {
			ti = i
		}
	}
	comboFill(hType, typeNames, ti)
	d.label("기본값", lx, 112, 90)
	hDef := d.edit(toStr(o.Default), ex, 108, ew)
	d.note("체크는 1 / 0, 선택목록은 아래 항목의 '값'", ex, 136, ew, 18)
	d.label("도움말", lx, 164, 90)
	hHint := d.edit(o.Hint, ex, 160, ew)

	d.label("LISP 변수", lx, 196, 90)
	hVar := d.edit(o.Var, ex, 192, 200)
	d.note("예: *TEE-RADIUS* (비우면 옵션파일 방식)", ex+206, 196, ew-206, 20)
	d.label("선택 항목", lx, 228, 90)
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
	d.note("선택목록일 때만 사용. 한 줄에 하나씩 '값=표시명' (예: all=도면 전체)", ex, 338, ew, 34)

	d.button("확인", IDOK, 270, 396, 95, true)
	d.button("취소", IDCANCEL, 370, 396, 95, false)

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
			msgBox("키는 영문으로 시작하는 영문·숫자·_ 만 쓸 수 있습니다.", MB_ICONWARNING)
			return
		}
		for i, x := range all {
			if i != self && strings.EqualFold(x.Key, key) {
				msgBox("같은 키가 이미 있습니다: "+key, MB_ICONWARNING)
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
				msgBox("선택목록 항목을 한 줄 이상 입력하세요.", MB_ICONWARNING)
				return
			}
		}
		if typ == "number" && def != "" {
			if _, err := parseFloat(def); err != nil {
				msgBox("기본값이 숫자가 아닙니다.", MB_ICONWARNING)
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
