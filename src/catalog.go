package main

// 리습 목록(catalog.json): 기능 분류 → 리습 → 명령어

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"unicode/utf16"
	"unsafe"
)

type UpdateCfg struct {
	Repo   string `json:"repo"`   // "계정/저장소"
	Branch string `json:"branch"` // 기본 main
}

type Cmd struct {
	Command string   `json:"command"`
	Desc    string   `json:"desc"`
	Manual  string   `json:"manual,omitempty"`
	Options []Option `json:"options,omitempty"`
}

type Lisp struct {
	Name     string `json:"name"`
	Desc     string `json:"desc"`
	File     string `json:"file,omitempty"` // 런처 폴더 기준 상대경로 (예: lsp/GGv2.lsp)
	Manual   string `json:"manual,omitempty"`
	Commands []Cmd  `json:"commands"`
	Tools    []Tool `json:"tools,omitempty"` // 함께 쓰는 외부 프로그램
}

type Category struct {
	Name  string `json:"name"`
	Lisps []Lisp `json:"lisps"`
}

type Catalog struct {
	Version    int        `json:"version"`
	Update     UpdateCfg  `json:"update"`
	Categories []Category `json:"categories"`
}

var cat Catalog

var loadedSha = map[string]string{} // 이번 런처 실행 중 마지막으로 로드한 리습 파일 내용

func utf16Z(s string) []uint16 { return utf16.Encode([]rune(s)) }

func loadCatalog() {
	cat = Catalog{Version: 1}
	b, err := os.ReadFile(catalogPath)
	if err != nil {
		logf("catalog.json 없음 - 빈 목록으로 시작")
		return
	}
	if err := json.Unmarshal(b, &cat); err != nil {
		msgBox("catalog.json 형식 오류\n"+err.Error(), MB_ICONERROR)
	}
	n := 0
	for _, ct := range cat.Categories {
		for _, l := range ct.Lisps {
			n += len(l.Commands)
		}
	}
	logf("리습 목록 불러옴 (명령 %d개)", n)
}

func saveCatalog() {
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	enc.SetEscapeHTML(false)
	enc.SetIndent("", "  ")
	_ = enc.Encode(cat)
	if err := os.WriteFile(catalogPath, buf.Bytes(), 0644); err != nil {
		msgBox("목록 저장 실패\n"+err.Error(), MB_ICONERROR)
	}
}

func cmdID(command string) string {
	return strings.ToUpper(strings.TrimLeft(strings.TrimSpace(strings.SplitN(command, "\n", 2)[0]), "_."))
}

// ───────────── 트리 ─────────────
const (
	nkNone = iota
	nkCat
	nkLisp
	nkCmd
)

type nodeRef struct{ kind, ci, li, mi int }

var (
	itemNode = map[uintptr]nodeRef{}
	nodeItem = map[nodeRef]uintptr{}
	cur      nodeRef
	building bool
)

func (n nodeRef) category() *Category {
	if n.kind >= nkCat && n.ci < len(cat.Categories) {
		return &cat.Categories[n.ci]
	}
	return nil
}
func (n nodeRef) lisp() *Lisp {
	if ct := n.category(); ct != nil && n.kind >= nkLisp && n.li < len(ct.Lisps) {
		return &ct.Lisps[n.li]
	}
	return nil
}
func (n nodeRef) cmd() *Cmd {
	if l := n.lisp(); l != nil && n.kind == nkCmd && n.mi < len(l.Commands) {
		return &l.Commands[n.mi]
	}
	return nil
}

func collapseKey(n nodeRef) string {
	switch n.kind {
	case nkCat:
		return "c:" + n.category().Name
	case nkLisp:
		return "l:" + n.category().Name + "/" + n.lisp().Name
	}
	return ""
}

func isCollapsed(k string) bool {
	for _, x := range st.Collapsed {
		if x == k {
			return true
		}
	}
	return false
}

func setCollapsed(k string, on bool) {
	out := st.Collapsed[:0]
	for _, x := range st.Collapsed {
		if x != k {
			out = append(out, x)
		}
	}
	if on {
		out = append(out, k)
	}
	st.Collapsed = out
}

func tvInsertItem(parent uintptr, text string, state uint32) uintptr {
	ins := tvInsert{hParent: parent, hInsertAfter: tviLast}
	ins.item.mask = TVIF_TEXT | TVIF_STATE
	ins.item.pszText = ws(text)
	ins.item.state = state
	ins.item.stateMask = TVIS_BOLD | TVIS_EXPANDED
	return c(pSendMessageW, hList, TVM_INSERTITEMW, 0, uintptr(unsafe.Pointer(&ins)))
}

func withDesc(name, desc string) string {
	if desc == "" {
		return name
	}
	return name + "  —  " + desc
}

func refreshTree(sel nodeRef) {
	building = true
	c(pSendMessageW, hList, TVM_DELETEITEM, 0, tviRoot)
	itemNode, nodeItem = map[uintptr]nodeRef{}, map[nodeRef]uintptr{}
	exp := func(n nodeRef, bold bool) uint32 {
		s := uint32(0)
		if bold {
			s |= TVIS_BOLD
		}
		if !isCollapsed(collapseKey(n)) {
			s |= TVIS_EXPANDED
		}
		return s
	}
	for ci, ct := range cat.Categories {
		cn := nodeRef{nkCat, ci, 0, 0}
		hc := tvInsertItem(tviRoot, ct.Name, exp(cn, true))
		itemNode[hc], nodeItem[cn] = cn, hc
		for li, l := range ct.Lisps {
			ln := nodeRef{nkLisp, ci, li, 0}
			hl := tvInsertItem(hc, withDesc(l.Name, l.Desc), exp(ln, false))
			itemNode[hl], nodeItem[ln] = ln, hl
			for mi, m := range l.Commands {
				mn := nodeRef{nkCmd, ci, li, mi}
				hm := tvInsertItem(hl, withDesc(cmdID(m.Command), m.Desc), 0)
				itemNode[hm], nodeItem[mn] = mn, hm
			}
		}
	}
	building = false
	if h := nodeItem[sel]; h != 0 {
		c(pSendMessageW, hList, TVM_SELECTITEM, TVGN_CARET, h)
		c(pSendMessageW, hList, TVM_ENSUREVISIBLE, 0, h)
	} else {
		showNode(nodeRef{})
	}
}

func onNotify(lp uintptr) uintptr {
	hdr := (*nmhdr)(unsafe.Pointer(lp))
	if hdr.hwndFrom != hList {
		return 0
	}
	switch int32(hdr.code) {
	case tvnSelChanged:
		if !building {
			showNode(itemNode[(*nmTreeView)(unsafe.Pointer(lp)).itemNew.hItem])
		}
	case tvnItemExpanded:
		nm := (*nmTreeView)(unsafe.Pointer(lp))
		if n, ok := itemNode[nm.itemNew.hItem]; ok && !building {
			setCollapsed(collapseKey(n), nm.action == TVE_COLLAPSE)
		}
	case nmDblClk:
		if cur.kind == nkCmd {
			runCurrent()
			return 1
		}
	}
	return 0
}

func valuesKey(n nodeRef) string {
	return n.lisp().Name + "|" + cmdID(n.cmd().Command)
}

func showNode(n nodeRef) {
	cur = n
	clearOptions()
	run := uintptr(0)
	switch n.kind {
	case nkCat:
		ct := n.category()
		setText(hTitle, ct.Name)
		setText(hDesc, "기능 분류 · 리습 "+itoa(len(ct.Lisps))+"개")
		var sb strings.Builder
		for _, l := range ct.Lisps {
			sb.WriteString("■ " + withDesc(l.Name, l.Desc) + "\n")
			for _, m := range l.Commands {
				sb.WriteString("    " + withDesc(cmdID(m.Command), m.Desc) + "\n")
			}
			sb.WriteString("\n")
		}
		setManual(sb.String())
	case nkLisp:
		l := n.lisp()
		setText(hTitle, l.Name)
		info := l.Desc
		if l.File != "" {
			info += "   (" + l.File + ")"
		}
		setText(hDesc, info)
		var sb strings.Builder
		if l.Manual != "" {
			sb.WriteString(l.Manual + "\n\n")
		}
		sb.WriteString("[명령어]\n")
		for _, m := range l.Commands {
			sb.WriteString("  " + withDesc(cmdID(m.Command), m.Desc) + "\n")
		}
		sb.WriteString(toolsSummary(l))
		setManual(sb.String())
	case nkCmd:
		l, m := n.lisp(), n.cmd()
		setText(hTitle, cmdID(m.Command)+"   ("+l.Name+")")
		setText(hDesc, m.Desc)
		man := m.Manual
		if man == "" {
			man = m.Desc
		}
		setManual(man + "\n" + toolsSummary(l))
		buildOptions(m.Options, st.Values[valuesKey(n)])
		run = 1
	default:
		setText(hTitle, "리습을 선택하세요")
		setText(hDesc, "")
		setManual("왼쪽 목록에서 기능 분류 › 리습 › 명령어를 선택하면 설명이 여기에 표시됩니다.\n\n명령어를 더블클릭하거나 ▶ 실행을 누르면 AutoCAD LT에서 실행됩니다.")
	}
	c(pEnableWindow, hRun, run)
	show(hTools, n.lisp() != nil && len(n.lisp().Tools) > 0)
	reset := uintptr(0)
	if len(optCtls) > 0 {
		reset = 1
	}
	c(pEnableWindow, hReset, reset)
	layout()
}

func resetOptions() {
	if cur.kind == nkCmd {
		delete(st.Values, valuesKey(cur))
		showNode(cur)
	}
}

func runCurrent() {
	if cur.kind != nkCmd {
		return
	}
	l, m := cur.lisp(), cur.cmd()
	if !ensureTools(l) {
		return
	}
	readSettings()
	vals, keep, ok := collect()
	if !ok {
		return
	}
	if len(keep) > 0 {
		st.Values[valuesKey(cur)] = keep
	}
	var sb strings.Builder
	needHelper := false
	for _, o := range m.Options {
		if o.Var == "" {
			needHelper = true
		}
	}
	if needHelper {
		if err := writeOptFile(cmdID(m.Command), vals); err != nil {
			msgBox("옵션 파일 저장 실패\n"+err.Error(), MB_ICONERROR)
			return
		}
		sb.WriteString(`(load "` + lispPath("lsp/launcher_opt.lsp") + `")` + "\n")
	}
	if l.File != "" {
		if _, err := os.Stat(absPath(l.File)); err != nil {
			msgBox("리습 파일을 찾을 수 없습니다.\n"+absPath(l.File), MB_ICONWARNING)
			return
		}
		// 파일이 바뀌었으면 다시 로드, 아니면 아직 로드되지 않았을 때만 로드
		// (FORMSETAREA 처럼 세션 중 바꾼 설정값이 매번 초기화되지 않도록)
		lp := lispPath(l.File)
		sha := gitBlobSha(absPath(l.File))
		id := cmdID(m.Command)
		isFunc := false
		for _, f := range lispFuncs(l.File) {
			if f == id {
				isFunc = true
			}
		}
		if loadedSha[lp] != sha || !isFunc {
			sb.WriteString(`(load "` + lp + `")` + "\n")
			loadedSha[lp] = sha
		} else {
			sb.WriteString(`(if (not c:` + id + `) (load "` + lp + `"))` + "\n")
		}
	}
	sb.WriteString(toolVarLines(l))
	// LISP 변수에 연결된 옵션: 로드 직후 (setq 변수 값) 으로 덮어쓰기
	for i, o := range m.Options {
		if o.Var != "" && i < len(vals) {
			sb.WriteString("(setq " + o.Var + " " + lispValue(o, vals[i].v) + ")\n")
		}
	}
	body := m.Command
	for _, p := range vals {
		body = strings.ReplaceAll(body, "{"+p.k+"}", p.v)
	}
	if !strings.HasSuffix(body, "\n") {
		body += "\n"
	}
	sb.WriteString(body)
	send(sb.String())
}

// ───────────── 목록 편집 ─────────────
func uniqueName(list []string, name, self string) bool {
	for _, x := range list {
		if x == name && x != self {
			return false
		}
	}
	return true
}

func catNames() []string {
	var out []string
	for _, ct := range cat.Categories {
		out = append(out, ct.Name)
	}
	return out
}

func nameDialog(title, label, value string) (string, bool) {
	d := newDialog(title, 420, 110)
	d.label(label, 14, 18, 90)
	h := d.edit(value, 110, 14, 290)
	d.button("확인", IDOK, 200, 66, 95, true)
	d.button("취소", IDCANCEL, 305, 66, 95, false)
	var out string
	d.onCmd = func(id, code int) {
		if id == IDOK {
			out = strings.TrimSpace(getText(h))
			if out == "" {
				msgBox(label+"을(를) 입력하세요.", MB_ICONWARNING)
				return
			}
			d.ok, d.done = true, true
		}
	}
	return out, d.run(h)
}

func addCategory() {
	name, ok := nameDialog("분류 추가", "분류 이름", "")
	if !ok {
		return
	}
	if !uniqueName(catNames(), name, "") {
		msgBox("같은 이름의 분류가 있습니다.", MB_ICONWARNING)
		return
	}
	cat.Categories = append(cat.Categories, Category{Name: name})
	saveCatalog()
	refreshTree(nodeRef{nkCat, len(cat.Categories) - 1, 0, 0})
}

func addLisp() {
	if len(cat.Categories) == 0 {
		msgBox("먼저 '분류 추가'로 기능 분류를 만드세요.", MB_ICONWARNING)
		return
	}
	ci := 0
	if cur.kind >= nkCat {
		ci = cur.ci
	}
	l := Lisp{}
	if !lispDialog(&l, &ci, true) {
		return
	}
	// 머리말에 적힌 분류가 아직 없으면 새로 만들어 넣음
	if h := parseLispHeader(l.File); h != nil && h.Category != "" && !contains(catNames(), h.Category) &&
		ask("리습 머리말의 분류 '"+h.Category+"' 가 없습니다. 새로 만들어 넣을까요?\n(아니오 = 선택한 분류에 넣음)") {
		cat.Categories = append(cat.Categories, Category{Name: h.Category})
		ci = len(cat.Categories) - 1
	}
	cat.Categories[ci].Lisps = append(cat.Categories[ci].Lisps, l)
	saveCatalog()
	refreshTree(nodeRef{nkLisp, ci, len(cat.Categories[ci].Lisps) - 1, 0})
	logf("리습 추가: %s (명령 %d개)", l.Name, len(l.Commands))
}

func addCmd() {
	if cur.kind < nkLisp {
		msgBox("명령을 넣을 리습을 목록에서 선택하세요.", MB_ICONWARNING)
		return
	}
	l := cur.lisp()
	m := Cmd{}
	if !cmdDialog(&m, l, -1) {
		return
	}
	l.Commands = append(l.Commands, m)
	saveCatalog()
	refreshTree(nodeRef{nkCmd, cur.ci, cur.li, len(l.Commands) - 1})
}

func editNode() {
	switch cur.kind {
	case nkCat:
		ct := cur.category()
		name, ok := nameDialog("분류 이름 바꾸기", "분류 이름", ct.Name)
		if !ok || name == ct.Name {
			return
		}
		if !uniqueName(catNames(), name, ct.Name) {
			msgBox("같은 이름의 분류가 있습니다.", MB_ICONWARNING)
			return
		}
		ct.Name = name
		saveCatalog()
		refreshTree(cur)
	case nkLisp:
		l := *cur.lisp()
		ci := cur.ci
		if !lispDialog(&l, &ci, false) {
			return
		}
		if ci == cur.ci {
			*cur.lisp() = l
			saveCatalog()
			refreshTree(cur)
			return
		}
		// 다른 분류로 이동
		src := &cat.Categories[cur.ci]
		src.Lisps = append(src.Lisps[:cur.li], src.Lisps[cur.li+1:]...)
		cat.Categories[ci].Lisps = append(cat.Categories[ci].Lisps, l)
		saveCatalog()
		refreshTree(nodeRef{nkLisp, ci, len(cat.Categories[ci].Lisps) - 1, 0})
	case nkCmd:
		m := *cur.cmd()
		oldKey := valuesKey(cur)
		if !cmdDialog(&m, cur.lisp(), cur.mi) {
			return
		}
		*cur.cmd() = m
		if nk := valuesKey(cur); nk != oldKey {
			if v, ok := st.Values[oldKey]; ok {
				st.Values[nk] = v
				delete(st.Values, oldKey)
			}
		}
		saveCatalog()
		refreshTree(cur)
	default:
		msgBox("편집할 분류·리습·명령을 선택하세요.", MB_ICONWARNING)
	}
}

func deleteNode() {
	switch cur.kind {
	case nkCat:
		ct := cur.category()
		if !ask("분류 '" + ct.Name + "' 와 그 안의 리습 " + itoa(len(ct.Lisps)) + "개를 목록에서 삭제할까요?\n(리습 파일은 지우지 않습니다)") {
			return
		}
		cat.Categories = append(cat.Categories[:cur.ci], cat.Categories[cur.ci+1:]...)
		saveCatalog()
		refreshTree(nodeRef{nkCat, max(cur.ci-1, 0), 0, 0})
	case nkLisp:
		ct := cur.category()
		if !ask("리습 '" + cur.lisp().Name + "' 을(를) 목록에서 삭제할까요?\n(리습 파일은 지우지 않습니다)") {
			return
		}
		ct.Lisps = append(ct.Lisps[:cur.li], ct.Lisps[cur.li+1:]...)
		saveCatalog()
		refreshTree(nodeRef{nkCat, cur.ci, 0, 0})
	case nkCmd:
		l := cur.lisp()
		if !ask("명령 '" + cmdID(cur.cmd().Command) + "' 을(를) 목록에서 삭제할까요?") {
			return
		}
		l.Commands = append(l.Commands[:cur.mi], l.Commands[cur.mi+1:]...)
		saveCatalog()
		refreshTree(nodeRef{nkLisp, cur.ci, cur.li, 0})
	}
}

func moveNode(dir int) {
	n := cur
	switch n.kind {
	case nkCat:
		j := n.ci + dir
		if j < 0 || j >= len(cat.Categories) {
			return
		}
		cat.Categories[n.ci], cat.Categories[j] = cat.Categories[j], cat.Categories[n.ci]
		n.ci = j
	case nkLisp:
		ls := n.category().Lisps
		j := n.li + dir
		if j < 0 || j >= len(ls) {
			return
		}
		ls[n.li], ls[j] = ls[j], ls[n.li]
		n.li = j
	case nkCmd:
		ms := n.lisp().Commands
		j := n.mi + dir
		if j < 0 || j >= len(ms) {
			return
		}
		ms[n.mi], ms[j] = ms[j], ms[n.mi]
		n.mi = j
	default:
		return
	}
	saveCatalog()
	refreshTree(n)
}

// ───────────── 리습 편집 창 ─────────────
func multiEdit(d *dialog, text string, x, y, w, h int) uintptr {
	text = strings.ReplaceAll(strings.ReplaceAll(text, "\r\n", "\n"), "\n", "\r\n")
	e := d.mk("EDIT", text, ES_MULTILINE|ES_AUTOVSCROLL|ES_WANTRETURN|WS_VSCROLL|WS_TABSTOP, WS_EX_CLIENTEDGE, 0)
	mv(e, x, y, w, h)
	return e
}

func multiText(h uintptr) string {
	return strings.TrimSpace(strings.ReplaceAll(getText(h), "\r\n", "\n"))
}

func lispDialog(l *Lisp, ci *int, isNew bool) bool {
	title := "리습 편집"
	if isNew {
		title = "리습 추가"
	}
	d := newDialog(title, 620, 600)
	const lx, ex, ew = 14, 110, 490
	d.label("기능 분류", lx, 16, 90)
	hCat := d.mk("COMBOBOX", "", CBS_DROPDOWNLIST|WS_VSCROLL|WS_TABSTOP, 0, 601)
	mv(hCat, ex, 12, 250, 260)
	comboFill(hCat, catNames(), *ci)
	d.label("리습 이름", lx, 48, 90)
	hName := d.edit(l.Name, ex, 44, 250)
	d.label("간단한 설명", lx, 80, 90)
	hDesc := d.edit(l.Desc, ex, 76, ew)
	d.label("리습 파일", lx, 112, 90)
	hFile := d.edit(l.File, ex, 108, ew-40)
	d.button("…", 602, ex+ew-34, 106, 34, false)
	hAuto := d.mk("BUTTON", "파일 안의 명령어 (defun c:이름) 을 목록에 자동 추가", BS_AUTOCHECKBOX|WS_TABSTOP, 0, 603)
	mv(hAuto, ex, 138, ew, 22)
	setCheck(hAuto, isNew)
	d.label("설명서", lx, 168, 90)
	hMan := multiEdit(d, l.Manual, ex, 166, ew, 230)
	d.note("리습 전체 설명 (사용 전 준비사항, 주의점 등). 명령어 목록은 자동으로 붙습니다.", ex, 398, ew, 20)

	tools := append([]Tool(nil), l.Tools...)
	d.label("외부 프로그램", lx, 428, 95)
	hTl := d.mk("LISTBOX", "", LBS_NOTIFY|LBS_NOINTEGRALHEIGHT|WS_VSCROLL|WS_TABSTOP, WS_EX_CLIENTEDGE, 610)
	mv(hTl, ex, 424, ew-100, 100)
	bx := ex + ew - 94
	d.button("추가", 611, bx, 424, 94, false)
	d.button("편집", 612, bx, 456, 94, false)
	d.button("삭제", 613, bx, 488, 94, false)
	refreshTools := func(sel int) {
		c(pSendMessageW, hTl, LB_RESETCONTENT, 0, 0)
		for _, t := range tools {
			line := t.Name
			if t.Version != "" {
				line += " v" + t.Version
			}
			line += "  ·  " + t.Kind + "  ·  " + t.Source
			c(pSendMessageW, hTl, LB_ADDSTRING, 0, uintptr(P(ws(line))))
		}
		if sel >= 0 && sel < len(tools) {
			c(pSendMessageW, hTl, LB_SETCURSEL, uintptr(sel), 0)
		}
	}
	refreshTools(-1)
	tlSel := func() int { return int(int32(c(pSendMessageW, hTl, LB_GETCURSEL, 0, 0))) }

	d.button("확인", IDOK, 410, 562, 95, true)
	d.button("취소", IDCANCEL, 510, 562, 95, false)

	// 리습 머리말(@launcher)이 있으면 비어 있는 칸을 채움
	applyHeader := func(f string) {
		h := parseLispHeader(f)
		if h == nil {
			return
		}
		if strings.TrimSpace(getText(hName)) == "" && h.Name != "" {
			setText(hName, h.Name)
		}
		if strings.TrimSpace(getText(hDesc)) == "" {
			setText(hDesc, h.Desc)
		}
		if multiText(hMan) == "" && h.Manual != "" {
			setText(hMan, strings.ReplaceAll(h.Manual, "\n", "\r\n"))
		}
		if h.Category != "" && contains(catNames(), h.Category) {
			c(pSendMessageW, hCat, CB_SETCURSEL, uintptr(indexOf(catNames(), h.Category)), 0)
		}
		if len(tools) == 0 && len(h.Tools) > 0 {
			tools = append(tools, h.Tools...)
			refreshTools(-1)
		}
	}

	d.onCmd = func(id, code int) {
		switch {
		case id == 602 && code == BN_CLICKED:
			if p := openLispFile(d.h); p != "" {
				p = adoptLisp(p)
				setText(hFile, p)
				applyHeader(p)
				if strings.TrimSpace(getText(hName)) == "" {
					base := filepath.Base(filepath.FromSlash(p))
					setText(hName, strings.TrimSuffix(base, filepath.Ext(base)))
				}
			}
		case id == 611 && code == BN_CLICKED:
			t := Tool{Kind: "zip"}
			if toolDialog(&t) {
				tools = append(tools, t)
				refreshTools(len(tools) - 1)
			}
		case (id == 612 && code == BN_CLICKED) || (id == 610 && code == LBN_DBLCLK):
			if i := tlSel(); i >= 0 {
				t := tools[i]
				if toolDialog(&t) {
					tools[i] = t
					refreshTools(i)
				}
			}
		case id == 613 && code == BN_CLICKED:
			if i := tlSel(); i >= 0 && ask("외부 프로그램 '"+tools[i].Name+"' 을(를) 목록에서 뺄까요?") {
				tools = append(tools[:i], tools[i+1:]...)
				refreshTools(i - 1)
			}
		case id == IDOK:
			name := strings.TrimSpace(getText(hName))
			f := filepath.ToSlash(strings.TrimSpace(getText(hFile)))
			if name == "" {
				msgBox("리습 이름을 입력하세요.", MB_ICONWARNING)
				return
			}
			if f != "" {
				if _, err := os.Stat(absPath(f)); err != nil {
					msgBox("리습 파일을 찾을 수 없습니다.\n"+f, MB_ICONWARNING)
					return
				}
			}
			if i := comboSel(hCat); i >= 0 {
				*ci = i
			}
			l.Name, l.Desc, l.File, l.Manual, l.Tools = name, strings.TrimSpace(getText(hDesc)), f, multiText(hMan), tools
			if isChecked(hAuto) && f != "" {
				have := map[string]bool{}
				for _, m := range l.Commands {
					have[cmdID(m.Command)] = true
				}
				// 머리말(@launcher)에 적힌 명령(설명·설명서·옵션 포함)을 먼저, 그다음 나머지 c: 함수
				if h := parseLispHeader(f); h != nil {
					for _, m := range h.Cmds {
						if !have[cmdID(m.Command)] {
							l.Commands = append(l.Commands, m)
							have[cmdID(m.Command)] = true
						}
					}
				}
				for _, fn := range lispFuncs(f) {
					if !have[fn] {
						l.Commands = append(l.Commands, Cmd{Command: fn})
					}
				}
			}
			d.ok, d.done = true, true
		}
	}
	return d.run(hName)
}

// ───────────── 명령 편집 창 ─────────────
func cmdDialog(m *Cmd, l *Lisp, self int) bool {
	d := newDialog("명령어 편집 — "+l.Name, 620, 560)
	const lx, ex, ew = 14, 110, 490
	d.label("명령어", lx, 16, 90)
	hCmd := d.mk("COMBOBOX", "", CBS_DROPDOWN|WS_VSCROLL|WS_TABSTOP, 0, 701)
	mv(hCmd, ex, 12, 250, 240)
	comboFill(hCmd, lispFuncs(l.File), -1)
	setText(hCmd, escNL(m.Command))
	d.note(`리습의 c: 함수 / 기본 명령은 Enter 자리에 \n`, ex+258, 16, ew-258, 20)
	d.label("간단한 설명", lx, 48, 90)
	hDesc := d.edit(m.Desc, ex, 44, ew)
	d.label("설명서", lx, 80, 90)
	hMan := multiEdit(d, m.Manual, ex, 78, ew, 200)

	opts := append([]Option(nil), m.Options...)
	d.label("옵션", lx, 292, 90)
	hOpts := d.mk("LISTBOX", "", LBS_NOTIFY|LBS_NOINTEGRALHEIGHT|WS_VSCROLL|WS_TABSTOP, WS_EX_CLIENTEDGE, 710)
	mv(hOpts, ex, 288, ew-100, 150)
	bx := ex + ew - 94
	d.button("추가", 711, bx, 288, 94, false)
	d.button("편집", 712, bx, 320, 94, false)
	d.button("삭제", 713, bx, 352, 94, false)
	d.button("▲", 714, bx, 384, 45, false)
	d.button("▼", 715, bx+49, 384, 45, false)
	d.note("옵션이 없으면 실행 화면의 옵션 칸은 비워집니다. 'LISP 변수'를 지정하면 리습을 고치지 않고 (setq 변수 값) 으로 전달합니다.", ex, 444, ew, 36)
	d.button("확인", IDOK, 410, 522, 95, true)
	d.button("취소", IDCANCEL, 510, 522, 95, false)

	refresh := func(sel int) {
		c(pSendMessageW, hOpts, LB_RESETCONTENT, 0, 0)
		for _, o := range opts {
			line := o.Label + "  ·  " + typeName(o.Type)
			if o.Var != "" {
				line += "  ·  " + o.Var
			} else {
				line += "  ·  키=" + o.Key
			}
			if dv := toStr(o.Default); dv != "" {
				line += "  ·  기본=" + dv
			}
			c(pSendMessageW, hOpts, LB_ADDSTRING, 0, uintptr(P(ws(line))))
		}
		if sel >= 0 && sel < len(opts) {
			c(pSendMessageW, hOpts, LB_SETCURSEL, uintptr(sel), 0)
		}
	}
	refresh(-1)
	selIdx := func() int { return int(int32(c(pSendMessageW, hOpts, LB_GETCURSEL, 0, 0))) }

	d.onCmd = func(id, code int) {
		switch {
		case id == 711 && code == BN_CLICKED:
			o := Option{Type: "text"}
			if editOptionDialog(&o, opts, -1) {
				opts = append(opts, o)
				refresh(len(opts) - 1)
			}
		case (id == 712 && code == BN_CLICKED) || (id == 710 && code == LBN_DBLCLK):
			if i := selIdx(); i >= 0 {
				o := opts[i]
				if editOptionDialog(&o, opts, i) {
					opts[i] = o
					refresh(i)
				}
			}
		case id == 713 && code == BN_CLICKED:
			if i := selIdx(); i >= 0 && ask("옵션 '"+opts[i].Label+"' 을(를) 삭제할까요?") {
				opts = append(opts[:i], opts[i+1:]...)
				refresh(i - 1)
			}
		case (id == 714 || id == 715) && code == BN_CLICKED:
			i := selIdx()
			j := i - 1
			if id == 715 {
				j = i + 1
			}
			if i >= 0 && j >= 0 && j < len(opts) {
				opts[i], opts[j] = opts[j], opts[i]
				refresh(j)
			}
		case id == IDOK:
			command := unescNL(strings.TrimSpace(getText(hCmd)))
			if command == "" {
				msgBox("명령어를 입력하세요.", MB_ICONWARNING)
				return
			}
			for i, x := range l.Commands {
				if i != self && cmdID(x.Command) == cmdID(command) {
					msgBox("이 리습에 같은 명령어가 이미 있습니다: "+cmdID(command), MB_ICONWARNING)
					return
				}
			}
			m.Command, m.Desc, m.Manual, m.Options = command, strings.TrimSpace(getText(hDesc)), multiText(hMan), opts
			d.ok, d.done = true, true
		}
	}
	return d.run(hCmd)
}
