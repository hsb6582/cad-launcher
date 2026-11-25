package main

// 리습 목록(catalog.json) v2: 기능 분류 → 기능
//   기능 = 이름(간단한 한국어) + 리습 + 명령어 + 설명서 + 옵션
//   리습 = 파일, 공통 안내, 외부 프로그램 (여러 기능이 같은 리습을 씀)

import (
	"bytes"
	"encoding/json"
	"os"
	"sort"
	"strings"
	"unicode/utf16"
	"unsafe"
)

type Lisp struct {
	ID     string `json:"id"`
	Desc   string `json:"desc,omitempty"`
	File   string `json:"file,omitempty"`   // 런처 폴더 기준 상대경로 (예: lsp/GGv2.lsp)
	Manual string `json:"manual,omitempty"` // 리습 공통 안내 (준비사항 등)
	Tools  []Tool `json:"tools,omitempty"`  // 함께 쓰는 외부 프로그램
}

type Item struct {
	Name    string   `json:"name"`    // 기능 이름
	Desc    string   `json:"desc"`    // 간단한 설명
	Lisp    string   `json:"lisp"`    // Lisp.ID (기본 명령이면 빈칸)
	Command string   `json:"command"` // 명령어
	Manual  string   `json:"manual,omitempty"`
	Options []Option `json:"options,omitempty"`
}

type Category struct {
	Name  string `json:"name"`
	Items []Item `json:"items"`
}

type Catalog struct {
	Version    int        `json:"version"`
	Lisps      []Lisp     `json:"lisps"`
	Categories []Category `json:"categories"`
}

// v1 (분류 → 리습 → 명령) 읽기용
type v1Lisp struct {
	Name, Desc, File, Manual string
	Commands                 []struct {
		Command, Desc, Manual string
		Options               []Option
	}
	Tools []Tool
}

var cat Catalog

var loadedSha = map[string]string{} // 이번 런처 실행 중 마지막으로 로드한 리습 파일 내용

func utf16Z(s string) []uint16 { return utf16.Encode([]rune(s)) }

func loadCatalog() {
	cat = Catalog{Version: 2}
	b, err := os.ReadFile(catalogPath)
	if err != nil {
		logf("catalog.json 없음 - 빈 목록으로 시작")
		return
	}
	var raw struct {
		Version    int    `json:"version"`
		Lisps      []Lisp `json:"lisps"`
		Categories []struct {
			Name  string   `json:"name"`
			Items []Item   `json:"items"`
			Lisps []v1Lisp `json:"lisps"`
		} `json:"categories"`
	}
	if err := json.Unmarshal(b, &raw); err != nil {
		msgBox("catalog.json 형식 오류\n"+err.Error(), MB_ICONERROR)
		return
	}
	cat.Lisps = raw.Lisps
	for _, rc := range raw.Categories {
		ct := Category{Name: rc.Name, Items: rc.Items}
		for _, l := range rc.Lisps { // v1 → v2 변환
			cat.Lisps = append(cat.Lisps, Lisp{ID: l.Name, Desc: l.Desc, File: l.File, Manual: l.Manual, Tools: l.Tools})
			for _, m := range l.Commands {
				name := m.Desc
				if name == "" {
					name = cmdID(m.Command)
				}
				ct.Items = append(ct.Items, Item{Name: name, Lisp: l.Name, Command: m.Command, Manual: m.Manual, Options: m.Options})
			}
		}
		cat.Categories = append(cat.Categories, ct)
	}
	applyOrder()
	n := 0
	for _, ct := range cat.Categories {
		n += len(ct.Items)
	}
	logf("리습 목록 불러옴 (기능 %d개)", n)
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

func lispByID(id string) *Lisp {
	for i := range cat.Lisps {
		if cat.Lisps[i].ID == id {
			return &cat.Lisps[i]
		}
	}
	return nil
}

func itemKey(it *Item) string { return it.Lisp + "|" + cmdID(it.Command) }

// "(GGv2 · GGD)" 처럼 리습·명령어 표시
func itemTag(it *Item) string {
	if it.Lisp == "" {
		return "(" + cmdID(it.Command) + ")"
	}
	return "(" + it.Lisp + " · " + cmdID(it.Command) + ")"
}

// "(GGD)" 처럼 명령어만 표시 (리습 이름은 상위 분류에 표시)
func cmdTag(it *Item) string {
	return "(" + cmdID(it.Command) + ")"
}

// 분류 아래 기능들이 쓰는 리습 이름을 모아 "(GGv2)" 처럼 표시 (여러 개면 "(GGv2 · BPDF)")
func catLispTag(ct *Category) string {
	var ids []string
	seen := map[string]bool{}
	for i := range ct.Items {
		id := ct.Items[i].Lisp
		if id != "" && !seen[id] {
			seen[id] = true
			ids = append(ids, id)
		}
	}
	if len(ids) == 0 {
		return ""
	}
	return "  (" + strings.Join(ids, " · ") + ")"
}

// ───────────── 트리 ─────────────
const (
	nkNone = iota
	nkCat
	nkItem
)

type nodeRef struct{ kind, ci, ii int }

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
func (n nodeRef) item() *Item {
	if ct := n.category(); ct != nil && n.kind == nkItem && n.ii < len(ct.Items) {
		return &ct.Items[n.ii]
	}
	return nil
}
func (n nodeRef) lisp() *Lisp {
	if it := n.item(); it != nil {
		return lispByID(it.Lisp)
	}
	return nil
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

func refreshTree(sel nodeRef) {
	building = true
	c(pSendMessageW, hList, TVM_DELETEITEM, 0, tviRoot)
	itemNode, nodeItem = map[uintptr]nodeRef{}, map[nodeRef]uintptr{}
	for ci, ct := range cat.Categories {
		cn := nodeRef{nkCat, ci, 0}
		state := uint32(TVIS_BOLD)
		if !isCollapsed("c:" + ct.Name) {
			state |= TVIS_EXPANDED
		}
		hc := tvInsertItem(tviRoot, ct.Name+catLispTag(&ct), state)
		itemNode[hc], nodeItem[cn] = cn, hc
		for ii := range ct.Items {
			in := nodeRef{nkItem, ci, ii}
			it := &cat.Categories[ci].Items[ii]
			hi := tvInsertItem(hc, it.Name+"   "+cmdTag(it), 0)
			itemNode[hi], nodeItem[in] = in, hi
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
		if n, ok := itemNode[nm.itemNew.hItem]; ok && !building && n.kind == nkCat {
			setCollapsed("c:"+n.category().Name, nm.action == TVE_COLLAPSE)
		}
	case nmDblClk:
		if cur.kind == nkItem {
			runCurrent()
			return 1
		}
	}
	return 0
}

func showNode(n nodeRef) {
	cur = n
	clearOptions()
	run := uintptr(0)
	switch n.kind {
	case nkCat:
		ct := n.category()
		setText(hTitle, ct.Name+catLispTag(ct))
		setText(hDesc, "기능 "+itoa(len(ct.Items))+"개")
		var sb strings.Builder
		for i := range ct.Items {
			it := &ct.Items[i]
			sb.WriteString("■ " + it.Name + "   " + cmdTag(it) + "\n")
			if it.Desc != "" {
				sb.WriteString("    " + it.Desc + "\n")
			}
		}
		setManual(sb.String())
	case nkItem:
		it := n.item()
		setText(hTitle, it.Name)
		setText(hDesc, strings.TrimSpace(it.Desc+"   "+cmdTag(it)))
		man := it.Manual
		if man == "" {
			man = it.Desc
		}
		if l := n.lisp(); l != nil {
			man += "\n\n────────────────────\n[" + l.ID + " 공통 안내]"
			if l.Desc != "" {
				man += "  " + l.Desc
			}
			if l.Manual != "" {
				man += "\n" + l.Manual
			}
			man += "\n" + toolsSummary(l)
		}
		setManual(man)
		buildOptions(it.Options, st.Values[itemKey(it)])
		run = 1
	default:
		setText(hTitle, "기능을 선택하세요")
		setText(hDesc, "")
		setManual("왼쪽 목록에서 기능을 선택하면 설명이 여기에 표시됩니다.\n\n더블클릭하거나 ▶ 실행을 누르면 AutoCAD LT에서 실행됩니다.\n괄호 안은 (리습 · 명령어) 입니다.")
	}
	c(pEnableWindow, hRun, run)
	l := n.lisp()
	show(hTools, l != nil && len(l.Tools) > 0)
	show(hStartup, n.kind == nkItem && l != nil && l.File != "")
	if l != nil {
		setCheck(hStartup, isStartup(l.ID))
	}
	reset := uintptr(0)
	if len(optCtls) > 0 {
		reset = 1
	}
	c(pEnableWindow, hReset, reset)
	layout()
}

func resetOptions() {
	if it := cur.item(); it != nil {
		delete(st.Values, itemKey(it))
		showNode(cur)
	}
}

func runCurrent() {
	it := cur.item()
	if it == nil {
		return
	}
	l := cur.lisp()
	if it.Lisp != "" && l == nil {
		msgBox("목록에 리습 '"+it.Lisp+"' 정보가 없습니다.", MB_ICONWARNING)
		return
	}
	if l != nil && !ensureTools(l) {
		return
	}
	readSettings()
	vals, keep, ok := collect()
	if !ok {
		return
	}
	if len(keep) > 0 {
		st.Values[itemKey(it)] = keep
	}
	var sb strings.Builder
	needHelper := false
	for _, o := range it.Options {
		if o.Var == "" {
			needHelper = true
		}
	}
	if needHelper {
		if err := writeOptFile(cmdID(it.Command), vals); err != nil {
			msgBox("옵션 파일 저장 실패\n"+err.Error(), MB_ICONERROR)
			return
		}
		sb.WriteString(`(load "` + lispPath("lsp/launcher_opt.lsp") + `")` + "\n")
	}
	if l != nil && l.File != "" {
		if _, err := os.Stat(absPath(l.File)); err != nil {
			msgBox("리습 파일을 찾을 수 없습니다.\n"+absPath(l.File), MB_ICONWARNING)
			return
		}
		// 파일이 바뀌었으면 다시 로드, 아니면 아직 로드되지 않았을 때만 로드
		// (FORMSETAREA 처럼 세션 중 바꾼 설정값이 매번 초기화되지 않도록)
		lp := lispPath(l.File)
		sha := gitBlobSha(absPath(l.File))
		id := cmdID(it.Command)
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
	sb.WriteString("(setq *CADLAUNCHER-EXE* " + lispValue(Option{Type: "file"}, exePath) + ")\n")
	if l != nil {
		sb.WriteString(toolVarLines(l))
	}
	// LISP 변수에 연결된 옵션: 로드 직후 (setq 변수 값) 으로 덮어쓰기
	for i, o := range it.Options {
		if o.Var != "" && i < len(vals) {
			sb.WriteString("(setq " + o.Var + " " + lispValue(o, vals[i].v) + ")\n")
		}
	}
	body := it.Command
	for _, p := range vals {
		body = strings.ReplaceAll(body, "{"+p.k+"}", p.v)
	}
	if !strings.HasSuffix(body, "\n") {
		body += "\n"
	}
	sb.WriteString(body)
	logf("실행: %s %s", it.Name, itemTag(it))
	send(sb.String())
}

// ───────────── 순서 변경 (이 PC에만 저장) ─────────────
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
	case nkItem:
		its := n.category().Items
		j := n.ii + dir
		if j < 0 || j >= len(its) {
			return
		}
		its[n.ii], its[j] = its[j], its[n.ii]
		n.ii = j
	default:
		return
	}
	saveOrder() // 목록 파일(catalog.json)은 건드리지 않음 → 업데이트와 충돌 없음
	refreshTree(n)
}

func rankBy(order []string) func(string, int) int {
	pos := map[string]int{}
	for i, x := range order {
		pos[x] = i
	}
	return func(name string, orig int) int {
		if p, ok := pos[name]; ok {
			return p
		}
		return len(order) + orig // 새로 생긴 항목은 원래 순서대로 뒤에
	}
}

func applyOrder() {
	if len(st.Order) == 0 {
		return
	}
	rk := rankBy(st.Order[""])
	idx := map[string]int{}
	for i, ct := range cat.Categories {
		idx[ct.Name] = i
	}
	sort.SliceStable(cat.Categories, func(a, b int) bool {
		return rk(cat.Categories[a].Name, idx[cat.Categories[a].Name]) < rk(cat.Categories[b].Name, idx[cat.Categories[b].Name])
	})
	for ci := range cat.Categories {
		ct := &cat.Categories[ci]
		ri := rankBy(st.Order["c:"+ct.Name])
		pos := map[string]int{}
		for i := range ct.Items {
			pos[itemKey(&ct.Items[i])] = i
		}
		sort.SliceStable(ct.Items, func(a, b int) bool {
			ka, kb := itemKey(&ct.Items[a]), itemKey(&ct.Items[b])
			return ri(ka, pos[ka]) < ri(kb, pos[kb])
		})
	}
}

func saveOrder() {
	o := map[string][]string{}
	for _, ct := range cat.Categories {
		o[""] = append(o[""], ct.Name)
		for i := range ct.Items {
			o["c:"+ct.Name] = append(o["c:"+ct.Name], itemKey(&ct.Items[i]))
		}
	}
	st.Order = o
	saveState()
}
