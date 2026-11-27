package main

// 리습 목록(catalog.json) v2: 기능 분류 → 기능
//   기능 = 이름(간단한 한국어) + 리습 + 명령어 + 설명서 + 옵션
//   리습 = 파일, 공통 안내, 외부 프로그램 (여러 기능이 같은 리습을 씀)

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"unicode/utf16"
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
	// 간단 설명서 (하나라도 있으면 설명서 칸을 간단 버전으로, manual 은 '자세한 설명'에 접어 둠)
	When   string   `json:"when,omitempty"`   // 언제 쓰나 (한 줄)
	Steps  []string `json:"steps,omitempty"`  // 사용 순서
	Warn   string   `json:"warn,omitempty"`   // 주의 (한 줄)
	Before string   `json:"before,omitempty"` // 실행 전 그림 (예: lsp/img/HG1BRK_before.png)
	After  string   `json:"after,omitempty"`  // 실행 후 그림
	// 추천 기능: 목록에서 이름 앞에 엄지척 아이콘
	Recommend bool `json:"recommend,omitempty"`
}

func (it *Item) hasGuide() bool {
	return it.When != "" || len(it.Steps) > 0 || it.Warn != "" || it.Before != "" || it.After != ""
}

type Category struct {
	Name  string `json:"name"`
	Group string `json:"group,omitempty"` // 상위 분류 (예: 공통·도면수정·설계). 비우면 맨 위 단계에 바로 표시
	Items []Item `json:"items"`
}

// 상위 분류 이름 (catalog.json 에서 처음 나오는 순서). 순서는 목록 파일이 정하고 ▲▼로는 바꾸지 않는다
var groupNames []string

func groupRank(g string) int {
	for i, x := range groupNames {
		if x == g {
			return i
		}
	}
	return len(groupNames) // 상위 분류 없는 분류는 맨 뒤
}

func computeGroups() {
	groupNames = nil
	seen := map[string]bool{}
	for _, ct := range cat.Categories {
		if ct.Group != "" && !seen[ct.Group] {
			seen[ct.Group] = true
			groupNames = append(groupNames, ct.Group)
		}
	}
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
		logf("%s", T("catalog.001"))
		return
	}
	var raw struct {
		Version    int    `json:"version"`
		Lisps      []Lisp `json:"lisps"`
		Categories []struct {
			Name  string   `json:"name"`
			Group string   `json:"group"`
			Items []Item   `json:"items"`
			Lisps []v1Lisp `json:"lisps"`
		} `json:"categories"`
	}
	if err := json.Unmarshal(b, &raw); err != nil {
		msgBox(T("catalog.002")+err.Error(), MB_ICONERROR)
		return
	}
	cat.Lisps = raw.Lisps
	for _, rc := range raw.Categories {
		ct := Category{Name: rc.Name, Group: rc.Group, Items: rc.Items}
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
	computeGroups()
	applyOrder()
	pruneFavs()
	n := 0
	for _, ct := range cat.Categories {
		n += len(ct.Items)
	}
	logf(T("catalog.003"), n)
}

func saveCatalog() {
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	enc.SetEscapeHTML(false)
	enc.SetIndent("", "  ")
	_ = enc.Encode(cat)
	if err := os.WriteFile(catalogPath, buf.Bytes(), 0644); err != nil {
		msgBox(T("catalog.004")+err.Error(), MB_ICONERROR)
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
// 오른쪽 제목 옆 꼬리표: "BPDF · BPDF_S" (리습 · 명령어)
// 설명서 머리 줄 꼬리표: "명령어  GLC    리습  GLC.lsp"
func itemChip(it *Item) string {
	s := fmt.Sprintf(T("catalog.017"), cmdID(it.Command))
	if l := lispByID(it.Lisp); l != nil && l.File != "" {
		s += fmt.Sprintf(T("catalog.018"), filepath.Base(filepath.FromSlash(l.File)))
	}
	return s
}

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
	nkGroup    // 상위 분류 (ci = groupNames 위치)
	nkFavGroup // '★ 즐겨찾기' 묶음 (favorites.go)
)

type nodeRef struct{ kind, ci, ii int }

var (
	itemNode = map[uintptr]nodeRef{}
	nodeItem = map[nodeRef]uintptr{}
	cur      nodeRef
	building bool
)

func (n nodeRef) category() *Category {
	if (n.kind == nkCat || n.kind == nkItem) && n.ci < len(cat.Categories) {
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

// 목록(왼쪽 칸)은 listpane.go 에서 직접 그린다
func onNotify(lp uintptr) uintptr { return 0 }

func showNode(n nodeRef) {
	cur = n
	clearOptions()
	run := uintptr(0)
	var guide *guideDoc
	switch n.kind {
	case nkFavGroup: // 즐겨찾기 묶음
		setText(hTitle, T("fav.001"))
		setText(hChip, "")
		var sb strings.Builder
		refs := favRefs()
		for _, r := range refs {
			sb.WriteString("■ " + r.item().Name + "\n")
		}
		setText(hDesc, fmt.Sprintf(T("fav.007"), len(refs)))
		setManual(sb.String())
	case nkGroup: // 상위 분류: 안에 든 분류와 기능 목록
		g := groupNames[n.ci]
		setText(hTitle, g)
		setText(hChip, "")
		nc, ni := 0, 0
		var sb strings.Builder
		for ci := range cat.Categories {
			ct := &cat.Categories[ci]
			if ct.Group != g {
				continue
			}
			nc++
			sb.WriteString("■ " + ct.Name + "\n")
			for i := range ct.Items {
				ni++
				sb.WriteString("    · " + ct.Items[i].Name + "\n")
			}
		}
		setText(hDesc, fmt.Sprintf(T("catalog.020"), nc, ni))
		setManual(sb.String())
	case nkCat:
		ct := n.category()
		setText(hTitle, ct.Name)
		if tag := strings.Trim(strings.TrimSpace(catLispTag(ct)), "()"); tag != "" {
			setText(hChip, fmt.Sprintf(T("catalog.019"), tag))
		} else {
			setText(hChip, "")
		}
		setText(hDesc, T("catalog.006")+itoa(len(ct.Items))+T("catalog.007"))
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
		setText(hChip, itemChip(it))
		setText(hDesc, it.Desc)
		man := it.Manual
		if man == "" {
			man = it.Desc
		}
		if l := n.lisp(); l != nil {
			man += "\n\n────────────────────\n[" + l.ID + T("catalog.008")
			if l.Desc != "" {
				man += "  " + l.Desc
			}
			if l.Manual != "" {
				man += "\n" + l.Manual
			}
			man += "\n" + toolsSummary(l)
		}
		setManual(man)
		if it.hasGuide() {
			guide = &guideDoc{when: it.When, steps: it.Steps, warn: it.Warn, detail: strings.TrimSpace(man), pics: [2]string{it.Before, it.After}}
		}
		buildOptions(it.Options, st.Values[itemKey(it)])
		run = 1
	default:
		setText(hTitle, T("catalog.009"))
		setText(hChip, "")
		setText(hDesc, "")
		setManual(T("catalog.010"))
	}
	c(pEnableWindow, hRun, run)
	heroGlyph = pickGlyph(n) // 오른쪽 머리 아이콘 (ui2.go)
	setGuide(guide)
	updateFavBtn()
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
		msgBox(T("catalog.011")+it.Lisp+T("catalog.012"), MB_ICONWARNING)
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
	// 리습을 로드하기 전에 런처 폴더를 AutoCAD 신뢰 위치에 추가 (trust.go)
	if (needHelper || (l != nil && l.File != "")) && wantTrust() {
		sb.WriteString(trustLines())
	}
	if needHelper {
		if err := writeOptFile(cmdID(it.Command), vals); err != nil {
			msgBox(T("catalog.013")+err.Error(), MB_ICONERROR)
			return
		}
		sb.WriteString(`(load "` + lispPath("lsp/launcher_opt.lsp") + `")` + "\n")
	}
	if l != nil && l.File != "" {
		if _, err := os.Stat(absPath(l.File)); err != nil {
			msgBox(T("catalog.014")+absPath(l.File), MB_ICONWARNING)
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
	logf(T("catalog.015"), it.Name, itemTag(it))
	send(sb.String())
}

// ───────────── 순서 변경 (이 PC에만 저장) ─────────────
var orderNoted bool

func moveNode(dir int) {
	n := cur
	if !orderNoted && n.kind != nkNone {
		orderNoted = true
		logf("%s", T("catalog.016"))
	}
	if curFav && n.kind == nkItem { // 즐겨찾기 묶음 안에서는 즐겨찾기 순서만 바꿈
		moveFav(dir)
		return
	}
	switch n.kind {
	case nkCat:
		j := n.ci + dir
		if j < 0 || j >= len(cat.Categories) {
			return
		}
		if isDevCategory(cat.Categories[n.ci].Name) != isDevCategory(cat.Categories[j].Name) {
			return // 개발 중 분류는 맨 아래 고정
		}
		if cat.Categories[n.ci].Group != cat.Categories[j].Group {
			return // 상위 분류 안에서만 순서를 바꿈
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

// 개발 중인 분류 (이름에 '개발 중' 이 들어감) - 목록 맨 아래에 고정
func isDevCategory(name string) bool {
	return strings.Contains(name, "개발 중") || strings.Contains(name, "개발중")
}

func applyOrder() {
	defer devLast()
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

// 상위 분류 순서대로 모으고, 이 PC에서 순서를 바꿨더라도 개발 중 분류는 각 상위 분류의 맨 아래로
func devLast() {
	sort.SliceStable(cat.Categories, func(a, b int) bool {
		ga, gb := groupRank(cat.Categories[a].Group), groupRank(cat.Categories[b].Group)
		if ga != gb {
			return ga < gb
		}
		return !isDevCategory(cat.Categories[a].Name) && isDevCategory(cat.Categories[b].Name)
	})
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
