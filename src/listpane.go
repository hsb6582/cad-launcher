package main

// 왼쪽 작업 목록 (새 화면 2단계) - Windows 트리 대신 직접 그리는 평평한 목록
//   (전체) (★ 즐겨찾기) (추천)
//   ★ 즐겨찾기 ⌄           ← 즐겨찾기가 있을 때 맨 위 (전체 보기에서만)
//   공통 ⌄                  ← 상위 분류: 작은 회색 글씨, 누르면 접기/펼치기
//    [아이콘] 기능 이름   👍 ★
//   ('단순기능'·'개발 중' 기능도 모두 바로 보이고, 넘치면 스크롤)
//   스크롤 막대는 scroll.go (잘 보이게 직접 그림)

import (
	"strings"
	"syscall"
	"time"
	"unsafe"
)

const (
	rowGroup = iota // 상위 분류 머리 (key 로 접기/펼치기)
	rowItem         // 기능
	rowCat          // 중간 분류 (key c:분류이름 으로 접기/펼치기)
)

type listRow struct {
	kind  int
	label string
	key   string // 접기 키 (g:상위분류, c:분류, f: 즐겨찾기)
	fav   bool   // 즐겨찾기 묶음 머리 / 그 안의 바로가기
	sub   bool   // 중간 분류 아래 기능 (한 칸 들여씀)
	node  nodeRef
	y, h  int    // 내용 좌표 (장치 픽셀), h = 원래 높이
	vh    int    // 지금 보이는 높이 (펼치기·접기 애니메이션 중에는 h 보다 작음)
	gkey  string // 이 줄을 감춘 상위 분류(또는 즐겨찾기) 접기 키
	ckey  string // 이 줄을 감춘 중간 분류 접기 키
}

// ───────────── 펼치기·접기 애니메이션 ─────────────
// 머리를 누르면 그 아래 줄들의 높이가 0↔원래 높이로 부드럽게 변한다 (약 0.18초, 처음 빠르고 끝에 느려짐)
type listAnim struct {
	start time.Time
	open  bool
}

const (
	animDur     = 180 * time.Millisecond
	animTimerID = 7
)

var (
	lanims             = map[string]listAnim{}
	pKillTimer         = user32.NewProc("KillTimer")
	pSaveDC            = gdi32.NewProc("SaveDC")
	pRestoreDC         = gdi32.NewProc("RestoreDC")
	pIntersectClipRect = gdi32.NewProc("IntersectClipRect")
)

// 키 하나의 펼침 비율 (0 = 접힘 ~ 1 = 펼침). 애니메이션이 없으면 1
func animF(k string) float64 {
	a, ok := lanims[k]
	if k == "" || !ok {
		return 1
	}
	p := float64(time.Since(a.start)) / float64(animDur)
	if p > 1 {
		p = 1
	}
	e := 1 - (1-p)*(1-p)*(1-p) // 끝에 느려짐
	if a.open {
		return e
	}
	return 1 - e
}

// 접는 중인 묶음은 애니메이션이 끝날 때까지 줄을 남겨 둔다
func isOpen(k string) bool {
	_, anim := lanims[k]
	return !isCollapsed(k) || anim
}

func startListAnim(k string, open bool) {
	lanims[k] = listAnim{start: time.Now(), open: open}
	c(pSetTimer, hList, animTimerID, 15, 0)
}

func onListAnimTimer() {
	for k, a := range lanims {
		if time.Since(a.start) >= animDur {
			delete(lanims, k)
		}
	}
	if len(lanims) == 0 {
		c(pKillTimer, hList, animTimerID)
	}
	refilterList()
}

const (
	lmAll = iota // 보기: 전체
	lmFav        // 즐겨찾기만
	lmRec        // 추천만
)

var (
	lrows                  []listRow
	lsel                   = -1 // 고른 행
	lhot                   = -1 // 마우스가 올라간 행
	lsb                    vscroll
	lmode                  = lmAll
	listClass              = ws("CADListPane")
	hSearch                uintptr
	hChipAll               uintptr
	hChipFav               uintptr
	hChipRec               uintptr
	hFontGrp               uintptr // 상위 분류 머리 (작은 굵은 글씨)
	hFontGlyph             uintptr // 기능 아이콘 기호
	curFav                 bool    // 지금 고른 항목이 즐겨찾기 묶음 안에 있음
	selFavNext             bool    // 다음 refreshTree 때 즐겨찾기 묶음 쪽을 선택
	listMouseIn            bool
	pPolyline              = gdi32.NewProc("Polyline")
	hFontGrpS              uintptr
	pSetTextCharacterExtra = gdi32.NewProc("SetTextCharacterExtra")
)

const (
	idSearch  = 3000
	idChipAll = 3001
	idChipFav = 3002
	idChipRec = 3003
)

func isChip(h uintptr) bool { return h != 0 && (h == hChipAll || h == hChipFav || h == hChipRec) }

// ───────────── 펼침 상태 ─────────────
// 목록 분류는 런처를 켤 때 펼친 상태로 시작한다. 단, 개발 중 분류와 '단순기능' 은 닫힌 상태('세부 기능')로 시작.
// 켜 둔 동안 펼치거나 닫은 묶음은 기억해서, 업데이트로 목록을 다시 그려도 그대로 둔다 (파일에는 저장하지 않음).
var collapsedNow = map[string]bool{}

func defaultCollapsed(k string) bool {
	if strings.HasPrefix(k, "g:") || k == "f:" {
		return false
	}
	name := strings.TrimPrefix(k, "c:")
	return isDevCategory(name) || strings.ReplaceAll(name, " ", "") == "단순기능"
}

func isCollapsed(k string) bool {
	if v, ok := collapsedNow[k]; ok {
		return v
	}
	if strings.HasPrefix(k, "t:") { // 상위 분류 없이 맨 위에 놓인 분류는 상위 분류 머리로 보여 줌 → 펼친 채
		return false
	}
	return defaultCollapsed(k)
}

func setCollapsed(k string, on bool) { collapsedNow[k] = on }

// ───────────── 만들기 ─────────────
func createListPane() {
	wc := wndClassEx{
		lpfnWndProc:   syscall.NewCallback(listProc),
		hInstance:     hInst,
		hCursor:       c(pLoadCursorW, 0, 32512),
		hbrBackground: hBgBrush,
		lpszClassName: listClass,
	}
	wc.cbSize = uint32(unsafe.Sizeof(wc))
	c(pRegisterClassExW, uintptr(P(&wc)))
	hList = c(pCreateWindowExW, 0, uintptr(P(listClass)), 0, WS_CHILD|WS_VISIBLE|WS_TABSTOP, 0, 0, 10, 10, hMain, idList, hInst, 0)
	hFontGrp = makeFont(10, true)
	hFontGrpS = makeFont(8, true) // 상위 분류 머리 (작은 굵은 글씨)
	hFontGlyph = makeIconFont(10)

	// 검색칸은 쓰지 않음 (hSearch = 0 → 검색어 없음)
	hChipAll = mk("BUTTON", T("list.002"), WS_TABSTOP, 0, idChipAll)
	hChipFav = mk("BUTTON", T("list.003"), WS_TABSTOP, 0, idChipFav)
	hChipRec = mk("BUTTON", T("list.004"), WS_TABSTOP, 0, idChipRec)
}

// 왼쪽 칸 배치: 검색칸 / 보기 버튼 / 목록
func layoutListPane(mainBottom int) {
	x := 8
	for _, h := range []uintptr{hChipAll, hChipFav, hChipRec} {
		w := strW(getText(h), hFont) + 26
		mv(h, x, secTop, w, 28)
		x += w + 6
	}
	lt := secTop + 36
	mv(hList, 8, lt, leftW, max(mainBottom-lt, 60))
}

// ───────────── 목록 행 만들기 ─────────────
func searchText() string {
	if hSearch == 0 {
		return ""
	}
	return strings.ToLower(strings.TrimSpace(getText(hSearch)))
}

func itemMatches(it *Item, q string) bool {
	switch lmode {
	case lmFav:
		if !isFav(it) {
			return false
		}
	case lmRec:
		if !it.Recommend {
			return false
		}
	}
	if q == "" {
		return true
	}
	hay := strings.ToLower(it.Name + " " + it.Desc + " " + cmdID(it.Command) + " " + it.Lisp + " " + it.When)
	for _, w := range strings.Fields(q) { // 여러 낱말은 모두 들어 있어야
		if !strings.Contains(hay, w) {
			return false
		}
	}
	return true
}

func buildRows() {
	q := searchText()
	filtering := q != "" || lmode != lmAll
	var rows []listRow
	if !filtering {
		if refs := favRefs(); len(refs) > 0 {
			// 노란 별은 따로 그리므로 문구 앞 ★ 는 뗌 (별이 두 개로 보이지 않게)
			rows = append(rows, listRow{kind: rowGroup, label: strings.TrimSpace(strings.TrimPrefix(T("fav.001"), "★")), key: "f:", fav: true})
			if isOpen("f:") {
				for _, n := range refs {
					rows = append(rows, listRow{kind: rowItem, label: n.item().Name, node: n, fav: true, gkey: "f:"})
				}
			}
		}
	}
	type catPart struct {
		ci    int
		items []nodeRef
	}
	type grp struct {
		label, key string
		top        bool // 상위 분류 없는 분류 (중간 분류 줄 없이 기능을 바로)
		cats       []*catPart
	}
	var groups []*grp
	byKey := map[string]*grp{}
	for ci := range cat.Categories {
		ct := &cat.Categories[ci]
		label, key := ct.Group, "g:"+ct.Group
		if ct.Group == "" {
			label, key = ct.Name, "t:"+ct.Name
		}
		g := byKey[key]
		if g == nil {
			g = &grp{label: label, key: key, top: ct.Group == ""}
			byKey[key] = g
			groups = append(groups, g)
		}
		cp := &catPart{ci: ci}
		for ii := range ct.Items {
			if itemMatches(&ct.Items[ii], q) {
				cp.items = append(cp.items, nodeRef{nkItem, ci, ii})
			}
		}
		if len(cp.items) > 0 {
			g.cats = append(g.cats, cp)
		}
	}
	for _, g := range groups {
		if len(g.cats) == 0 {
			continue
		}
		rows = append(rows, listRow{kind: rowGroup, label: g.label, key: g.key})
		if !filtering && !isOpen(g.key) {
			continue
		}
		gk := g.key
		if filtering {
			gk = ""
		}
		for _, cp := range g.cats {
			name := cat.Categories[cp.ci].Name
			ck := ""
			if !g.top {
				ck = "c:" + name
				rows = append(rows, listRow{kind: rowCat, label: name, key: ck, gkey: gk})
				if !filtering && !isOpen(ck) {
					continue
				}
				if filtering {
					ck = ""
				}
			}
			for _, n := range cp.items {
				rows = append(rows, listRow{kind: rowItem, label: n.item().Name, node: n, sub: !g.top, gkey: gk, ckey: ck})
			}
		}
	}
	// 행 위치
	y := si(2)
	for i := range rows {
		switch rows[i].kind {
		case rowGroup:
			if i > 0 {
				y += si(10)
			}
			rows[i].h = si(24)
		case rowItem:
			rows[i].h = si(28)
		case rowCat:
			y += int(float64(si(2)) * animF(rows[i].gkey))
			rows[i].h = si(28)
		}
		rows[i].y = y
		rows[i].vh = int(float64(rows[i].h)*animF(rows[i].gkey)*animF(rows[i].ckey) + 0.5)
		y += rows[i].vh
	}
	lrows = rows
	lsb.total = y + si(6)
}

// 목록을 다시 만들고 sel 을 고른다 (없으면 오른쪽을 비움). 즐겨찾기·순서·업데이트 뒤에 부름
func refreshTree(sel nodeRef) {
	buildRows()
	lsel = findRow(sel, selFavNext)
	selFavNext = false
	listRelayout()
	if lsel >= 0 {
		curFav = lrows[lsel].fav
		ensureRowVisible(lsel)
		showNode(lrows[lsel].node)
	} else {
		showNode(nodeRef{})
	}
}

// 검색·보기 버튼·펼침이 바뀔 때: 목록만 다시 만들고 오른쪽 설명은 그대로 둔다
func refilterList() {
	buildRows()
	lsel = findRow(cur, curFav)
	listRelayout()
}

func findRow(n nodeRef, preferFav bool) int {
	if n.kind != nkItem {
		return -1
	}
	found := -1
	for i, r := range lrows {
		if r.kind == rowItem && r.node == n {
			if r.fav == preferFav {
				return i
			}
			if found < 0 {
				found = i
			}
		}
	}
	return found
}

func listClient() (int, int) {
	var r rectT
	c(pGetClientRect, hList, uintptr(P(&r)))
	return int(r.right), int(r.bottom)
}

func listRelayout() {
	if hList == 0 {
		return
	}
	_, H := listClient()
	lsb.view = H
	lsb.clamp()
	c(pInvalidateRect, hList, 0, 0)
}

func ensureRowVisible(i int) {
	if i < 0 || i >= len(lrows) {
		return
	}
	_, H := listClient()
	r := lrows[i]
	if r.y < lsb.pos {
		lsb.pos = r.y - si(4)
	} else if r.y+r.h > lsb.pos+H {
		lsb.pos = r.y + r.h - H + si(4)
	}
	lsb.view = H
	lsb.clamp()
}

func rowAt(y int) int {
	y += lsb.pos
	for i, r := range lrows {
		if y >= r.y && y < r.y+r.vh {
			return i
		}
	}
	return -1
}

func selectRow(i int) {
	if i < 0 || i >= len(lrows) || lrows[i].kind != rowItem {
		return
	}
	lsel = i
	curFav = lrows[i].fav
	ensureRowVisible(i)
	c(pInvalidateRect, hList, 0, 0)
	showNode(lrows[i].node)
}

// 머리·더 보기 행을 누르면 접기/펼치기
func activateRow(i int) {
	if i < 0 || i >= len(lrows) {
		return
	}
	switch r := lrows[i]; r.kind {
	case rowItem:
		selectRow(i)
	case rowGroup, rowCat:
		if searchText() != "" || lmode != lmAll {
			return // 걸러 보는 중에는 늘 펼침
		}
		open := isCollapsed(r.key) // 지금 접혀 있으면 펼침
		setCollapsed(r.key, !open)
		startListAnim(r.key, open)
		refilterList()
	}
}

func setListMode(m int) {
	lmode = m
	for _, h := range []uintptr{hChipAll, hChipFav, hChipRec} {
		c(pInvalidateRect, h, 0, 0)
	}
	lsb.pos = 0
	refilterList()
}

func chipOn(h uintptr) bool {
	return (h == hChipAll && lmode == lmAll) || (h == hChipFav && lmode == lmFav) || (h == hChipRec && lmode == lmRec)
}

// 보기 버튼: 둥근 알약. 고른 것은 강조색
func drawChip(dis *drawItemStruct) {
	hdc, r := dis.hDC, dis.rcItem
	W, H := int(r.right-r.left), int(r.bottom-r.top)
	on := chipOn(dis.hwndItem)
	fill, txt := mixClr(clrBg, clrText, 0.08), clrSubText
	if hotBtn == dis.hwndItem {
		fill, txt = mixClr(clrBg, clrText, 0.14), clrText
	}
	if on {
		_, fill = runColors(false, false)
		txt = white
	}
	cv := newCanvas(W, H, clrBg)
	fw, fh := float64(W), float64(H)
	cv.paint(func(x, y float64) float64 { return aa(sdRoundRect(x, y, 0.5, 0.5, fw-0.5, fh-0.5, fh/2)) }, solid(fill))
	cv.blit(hdc, int(r.left), int(r.top))
	label := getText(dis.hwndItem)
	if dis.hwndItem == hChipFav {
		label = strings.TrimSpace(strings.TrimPrefix(label, "★"))
		sw, _ := textSize(hdc, hFont, "★ ")
		lw, lh := textSize(hdc, hFont, label)
		x := int(r.left) + (W-sw-lw)/2
		star := favStarClr
		if on {
			star = white
		}
		drawTextAt(hdc, hFont, star, x, int(r.top)+(H-lh)/2, "★")
		drawTextAt(hdc, hFont, txt, x+sw, int(r.top)+(H-lh)/2, label)
		return
	}
	lw, lh := textSize(hdc, hFont, label)
	drawTextAt(hdc, hFont, txt, int(r.left)+(W-lw)/2, int(r.top)+(H-lh)/2, label)
}

// ───────────── 그리기 ─────────────
func drawChevron(hdc uintptr, cx, cy int, open bool, clr uintptr) {
	w := int32(si(4))
	x, y := int32(cx), int32(cy)
	var pts [3][2]int32
	if open {
		pts = [3][2]int32{{x - w, y - w/2}, {x, y + w/2}, {x + w, y - w/2}}
	} else {
		pts = [3][2]int32{{x - w/2, y - w}, {x + w/2, y}, {x - w/2, y + w}}
	}
	pen := c(pCreatePen, PS_SOLID, uintptr(max(si(2)-1, 1)), clr)
	op := c(pSelectObject, hdc, pen)
	c(pPolyline, hdc, uintptr(P(&pts[0])), 3)
	c(pSelectObject, hdc, op)
	c(pDeleteObject, pen)
}

func paintList(hdc uintptr, W, H int) {
	fillBox(hdc, 0, 0, W, H, clrBg)
	c(pSetBkMode, hdc, TRANSPARENT)
	cw := W - si(sbW) // 내용 폭 (스크롤 막대 자리 빼고)
	filtering := searchText() != "" || lmode != lmAll
	if len(lrows) == 0 {
		msg := T("list.007")
		if lmode == lmFav && searchText() == "" {
			msg = T("list.008")
		}
		gText(hdc, hFont, clrSubText, si(10), si(14), cw-si(20), msg, true)
	}
	for i, r := range lrows {
		y := r.y - lsb.pos
		if y+r.h < 0 || y > H || r.vh <= 0 {
			continue
		}
		hot := i == lhot
		clip := r.vh < r.h // 펼치기·접기 중: 보이는 높이만큼만 그림
		if clip {
			c(pSaveDC, hdc)
			c(pIntersectClipRect, hdc, 0, uintptr(y), uintptr(W), uintptr(y+r.vh))
		}
		switch r.kind {
		case rowGroup: // 상위 분류: 띠 없이 작은 회색 굵은 글씨 + 넓은 글자 간격 (제목처럼)
			clr := clrSubText
			if hot && !filtering {
				clr = clrText
			}
			x := si(10)
			if r.fav {
				_, sh := textSize(hdc, hFontGrpS, "★")
				drawTextAt(hdc, hFontGrpS, favStarClr, x, y+(r.h-sh)/2, "★")
				x += si(16)
			}
			old := c(pSetTextCharacterExtra, hdc, uintptr(si(2)))
			_, th := textSize(hdc, hFontGrpS, r.label)
			drawTextAt(hdc, hFontGrpS, clr, x, y+(r.h-th)/2, r.label)
			c(pSetTextCharacterExtra, hdc, old)
			if !filtering {
				drawChevron(hdc, cw-si(14), y+r.h/2, !isCollapsed(r.key), clr)
			}
		case rowCat: // 중간 분류: 띠 없이 왼쪽 펼침 화살표 + 굵은 글씨
			if hot && !filtering {
				fillRound(hdc, si(4), y+si(1), cw-si(4), r.h-si(2), clrHotBg, clrHotBg, si(6))
			}
			if !filtering {
				drawChevron(hdc, si(14), y+r.h/2, !isCollapsed(r.key), clrSubText)
			}
			old := c(pSelectObject, hdc, hFontBtnBold)
			c(pSetTextColor, hdc, clrText)
			tr := rectT{int32(si(26)), int32(y), int32(cw - si(8)), int32(y + r.h)}
			c(pDrawTextW, hdc, uintptr(P(ws(r.label))), ^uintptr(0), uintptr(P(&tr)), DT_VCENTER|DT_SINGLELINE|DT_NOPREFIX|0x8000)
			c(pSelectObject, hdc, old)
		case rowItem:
			paintItemRow(hdc, r, y, cw, i == lsel, hot)
		}
		if clip {
			c(pRestoreDC, hdc, ^uintptr(0)) // -1: 바로 전 SaveDC 로
		}
	}
	lsb.paint(hdc, W, H)
}

func paintItemRow(hdc uintptr, r listRow, y, cw int, sel, hot bool) {
	it := r.node.item()
	if it == nil {
		return
	}
	x0, x1 := si(4), cw-si(2)
	gx := si(14) // 중간 분류 아래 기능: 화살표 아래로 내려오는 얇은 세로 안내선
	if r.sub {
		x0 = gx
	}
	switch {
	case sel:
		fillRound(hdc, x0, y+si(1), x1-x0, r.h-si(2), clrSelBg, clrSelBg, si(8))
		fillBox(hdc, x0, y+si(1), si(4), r.h-si(2), clrSelBg) // 안내선 쪽 모서리는 각지게
	case hot:
		fillRound(hdc, x0, y+si(1), x1-x0, r.h-si(2), clrHotBg, clrHotBg, si(8))
	}
	if r.sub || sel {
		lc, lw := guideLineClr(), 1
		if sel {
			_, b := runColors(false, false)
			lc, lw = mixClr(b, white, 0.35), si(2) // 고른 기능: 밝은 파랑으로 굵게
		}
		fillBox(hdc, x0, y, lw, r.h, lc)
	}
	// 오른쪽 표시: 추천(엄지척) · 즐겨찾기 별
	rx := x1 - si(10)
	if isFav(it) && !r.fav {
		sw, sh := textSize(hdc, hFont, "★")
		rx -= sw
		drawTextAt(hdc, hFont, favStarClr, rx, y+(r.h-sh)/2, "★")
		rx -= si(6)
	}
	if it.Recommend && recIcon != 0 {
		rx -= recIconW
		c(pDrawIconEx, hdc, uintptr(rx), uintptr(y+(r.h-recIconW)/2), recIcon, uintptr(recIconW), uintptr(recIconW), 0, 0, 3 /*DI_NORMAL*/)
		rx -= si(6)
	}
	// 이름
	nclr := clrText
	if sel {
		nclr = clrSelText
	}
	tx := x0 + si(12) // 기능 이름
	old := c(pSelectObject, hdc, hFont)
	c(pSetTextColor, hdc, nclr)
	tr := rectT{int32(tx), int32(y), int32(max(rx, tx+si(20))), int32(y + r.h)}
	c(pDrawTextW, hdc, uintptr(P(ws(r.label))), ^uintptr(0), uintptr(P(&tr)), DT_VCENTER|DT_SINGLELINE|DT_NOPREFIX|0x8000 /*DT_END_ELLIPSIS*/)
	c(pSelectObject, hdc, old)
}

func rowBg(sel, hot bool) uintptr {
	switch {
	case sel:
		return clrSelBg
	case hot:
		return clrHotBg
	}
	return clrBg
}

// ───────────── 메시지 ─────────────
func setListHot(i int) {
	if i != lhot {
		lhot = i
		c(pInvalidateRect, hList, 0, 0)
	}
}

func listProc(h, msg, wp, lp uintptr) uintptr {
	defer guardCrash() // 오류가 나면 crash.log 에 기록 (crash.go)
	switch msg {
	case WM_ERASEBKGND:
		return 1
	case WM_PAINT:
		var ps paintStruct
		hdc := c(pBeginPaint, h, uintptr(P(&ps)))
		W, H := listClient()
		mem := c(pCreateCompatibleDC, hdc)
		bmp := c(pCreateCompatibleBitmap, hdc, uintptr(max(W, 1)), uintptr(max(H, 1)))
		old := c(pSelectObject, mem, bmp)
		paintList(mem, W, H)
		c(pBitBlt, hdc, 0, 0, uintptr(W), uintptr(H), mem, 0, 0, SRCCOPY)
		c(pSelectObject, mem, old)
		c(pDeleteObject, bmp)
		c(pDeleteDC, mem)
		c(pEndPaint, h, uintptr(P(&ps)))
		return 0
	case WM_SIZE:
		listRelayout()
		return 0
	case WM_TIMER:
		if wp == animTimerID {
			onListAnimTimer()
		}
		return 0
	case 0x0087: // WM_GETDLGCODE: 위·아래 화살표는 목록이 받음
		return 0x0001 // DLGC_WANTARROWS
	case WM_MOUSEWHEEL:
		lsb.wheel(int(int16(wp >> 16)))
		c(pInvalidateRect, h, 0, 0)
		return 0
	case WM_LBUTTONDOWN, WM_LBUTTONDBLCLK:
		c(pSetFocus, h)
		x, y := int(int16(lp&0xFFFF)), int(int16((lp>>16)&0xFFFF))
		W, H := listClient()
		if lsb.mouseDown(W, H, x, y) {
			if lsb.drag {
				c(pSetCaptureM, h)
			}
			c(pInvalidateRect, h, 0, 0)
			return 0
		}
		activateRow(rowAt(y))
		return 0
	case WM_MOUSEMOVE:
		x, y := int(int16(lp&0xFFFF)), int(int16((lp>>16)&0xFFFF))
		if !listMouseIn {
			listMouseIn = true
			trackLeave(h)
		}
		if lsb.drag {
			_, H := listClient()
			lsb.mouseDrag(H, y)
			c(pInvalidateRect, h, 0, 0)
			return 0
		}
		W, _ := listClient()
		if hb := lsb.inBar(W, x); hb != lsb.hot {
			lsb.hot = hb
			c(pInvalidateRect, h, 0, 0)
		}
		if lsb.hot {
			setListHot(-1)
		} else {
			setListHot(rowAt(y))
		}
		return 0
	case WM_LBUTTONUP:
		if lsb.drag {
			lsb.drag = false
			c(pReleaseCaptM)
			c(pInvalidateRect, h, 0, 0)
		}
		return 0
	case WM_CAPTURECHANGED:
		lsb.drag = false
		return 0
	case WM_MOUSELEAVE:
		listMouseIn = false
		lsb.hot = false
		setListHot(-1)
		c(pInvalidateRect, h, 0, 0)
		return 0
	case 0x0204: // WM_RBUTTONDOWN: 그 기능을 고르고 메뉴
		c(pSetFocus, h)
		y := int(int16((lp >> 16) & 0xFFFF))
		if i := rowAt(y); i >= 0 && lrows[i].kind == rowItem {
			selectRow(i)
			onTreeRClick()
		}
		return 0
	case WM_KEYDOWN:
		switch wp {
		case 0x26, 0x28: // VK_UP, VK_DOWN: 위·아래 기능으로
			step := 1
			if wp == 0x26 {
				step = -1
			}
			for i := lsel + step; i >= 0 && i < len(lrows); i += step {
				if lrows[i].kind == rowItem {
					selectRow(i)
					break
				}
			}
			if lsel < 0 {
				for i := range lrows {
					if lrows[i].kind == rowItem {
						selectRow(i)
						break
					}
				}
			}
			return 0
		}
	}
	return c(pDefWindowProcW, h, msg, wp, lp)
}

// 명암 계단 (시안 24번): 상위 분류 띠가 가장 진하고, 중간 분류 띠는 그 중간, 기능 줄은 창 바탕
func groupBandClr() uintptr {
	if curTheme.dark {
		return mixClr(clrBg, 0, 0.50)
	}
	return mixClr(clrBg, 0, 0.16)
}

func groupTextClr() uintptr {
	if curTheme.dark {
		return white
	}
	return clrText
}

// 중간 분류: 세로줄 / 글자 / 띠 색
func catColors() (bar, txt, bg uintptr) {
	if curTheme.dark {
		return clrSubText, mixClr(clrText, white, 0.3), mixClr(clrBg, 0, 0.22)
	}
	return clrSubText, clrText, mixClr(clrBg, 0, 0.07)
}

// 기능 줄 왼쪽 안내선 색 (바탕보다 살짝 밝게/진하게)
func guideLineClr() uintptr {
	if curTheme.dark {
		return mixClr(clrBg, white, 0.16)
	}
	return mixClr(clrBg, 0, 0.14)
}
