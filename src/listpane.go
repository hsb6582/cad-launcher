package main

// 왼쪽 작업 목록 (새 화면 2단계) - Windows 트리 대신 직접 그리는 평평한 목록
//   [검색칸]
//   (전체) (★ 즐겨찾기) (추천)
//   ★ 즐겨찾기 ⌄           ← 즐겨찾기가 있을 때 맨 위 (전체 보기에서만)
//   공통 ⌄                  ← 상위 분류: 작은 회색 글씨, 누르면 접기/펼치기
//    [아이콘] 기능 이름   👍 ★
//   ＋ 세부 기능 N개 더 보기  ← 처음에 닫혀 있던 분류('단순기능'·'개발 중')는 여기 모아 둠
//   스크롤 막대는 scroll.go (잘 보이게 직접 그림)

import (
	"fmt"
	"strings"
	"syscall"
	"unsafe"
)

const (
	rowGroup = iota // 상위 분류 머리 (key 로 접기/펼치기)
	rowItem         // 기능
	rowMore         // 세부 기능 더 보기 / 접기
)

type listRow struct {
	kind  int
	label string
	key   string // 접기 키 (g:상위분류, c:분류, f: 즐겨찾기)
	fav   bool   // 즐겨찾기 묶음 머리 / 그 안의 바로가기
	node  nodeRef
	y, h  int // 내용 좌표 (장치 픽셀)
}

const (
	lmAll = iota // 보기: 전체
	lmFav        // 즐겨찾기만
	lmRec        // 추천만
)

var (
	lrows       []listRow
	lsel        = -1 // 고른 행
	lhot        = -1 // 마우스가 올라간 행
	lsb         vscroll
	lmode       = lmAll
	showMore    bool // 세부 기능 펼침
	listClass   = ws("CADListPane")
	hSearch     uintptr
	hChipAll    uintptr
	hChipFav    uintptr
	hChipRec    uintptr
	hFontGrp    uintptr // 상위 분류 머리 (작은 굵은 글씨)
	hFontGlyph  uintptr // 기능 아이콘 기호
	curFav      bool    // 지금 고른 항목이 즐겨찾기 묶음 안에 있음
	selFavNext  bool    // 다음 refreshTree 때 즐겨찾기 묶음 쪽을 선택
	listMouseIn bool
	pPolyline   = gdi32.NewProc("Polyline")
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
	if strings.HasPrefix(k, "c:") { // 상위 분류 없이 맨 위에 놓인 분류는 머리로 보여 줌 → 펼친 채
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
	hFontGrp = makeFont(8, true)
	hFontGlyph = makeIconFont(10)

	hSearch = mk("EDIT", "", ES_AUTOHSCROLL|WS_TABSTOP, WS_EX_CLIENTEDGE, idSearch)
	c(pSendMessageW, hSearch, 0x1501 /*EM_SETCUEBANNER*/, 1, uintptr(P(ws(T("list.001")))))
	hChipAll = mk("BUTTON", T("list.002"), WS_TABSTOP, 0, idChipAll)
	hChipFav = mk("BUTTON", T("list.003"), WS_TABSTOP, 0, idChipFav)
	hChipRec = mk("BUTTON", T("list.004"), WS_TABSTOP, 0, idChipRec)
}

// 왼쪽 칸 배치: 검색칸 / 보기 버튼 / 목록
func layoutListPane(mainBottom int) {
	mv(hSearch, 8, secTop, leftW, 34)
	x := 8
	for _, h := range []uintptr{hChipAll, hChipFav, hChipRec} {
		w := strW(getText(h), hFont) + 26
		mv(h, x, secTop+42, w, 28)
		x += w + 6
	}
	lt := secTop + 78
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
			rows = append(rows, listRow{kind: rowGroup, label: T("fav.001"), key: "f:", fav: true})
			if !isCollapsed("f:") {
				for _, n := range refs {
					rows = append(rows, listRow{kind: rowItem, label: n.item().Name, node: n, fav: true})
				}
			}
		}
	}
	type grp struct {
		label, key string
		items      []nodeRef
	}
	var groups []*grp
	byKey := map[string]*grp{}
	hidden := 0
	for ci := range cat.Categories {
		ct := &cat.Categories[ci]
		label, key := ct.Group, "g:"+ct.Group
		if ct.Group == "" {
			label, key = ct.Name, "c:"+ct.Name
		}
		g := byKey[key]
		if g == nil {
			g = &grp{label: label, key: key}
			byKey[key] = g
			groups = append(groups, g)
		}
		sub := ct.Group != "" && defaultCollapsed("c:"+ct.Name) // 처음에 닫혀 있던 분류 → '세부 기능'
		for ii := range ct.Items {
			if !itemMatches(&ct.Items[ii], q) {
				continue
			}
			if sub && !filtering && !showMore {
				hidden++
				continue
			}
			g.items = append(g.items, nodeRef{nkItem, ci, ii})
		}
	}
	for _, g := range groups {
		if len(g.items) == 0 {
			continue
		}
		rows = append(rows, listRow{kind: rowGroup, label: g.label, key: g.key})
		if filtering || !isCollapsed(g.key) {
			for _, n := range g.items {
				rows = append(rows, listRow{kind: rowItem, label: n.item().Name, node: n})
			}
		}
	}
	if !filtering && (hidden > 0 || showMore) {
		label := T("list.006")
		if !showMore {
			label = fmt.Sprintf(T("list.005"), hidden)
		}
		rows = append(rows, listRow{kind: rowMore, label: label})
	}
	// 행 위치
	y := si(2)
	for i := range rows {
		switch rows[i].kind {
		case rowGroup:
			if i > 0 {
				y += si(8)
			}
			rows[i].h = si(28)
		case rowItem:
			rows[i].h = si(38)
		case rowMore:
			y += si(8)
			rows[i].h = si(36)
		}
		rows[i].y = y
		y += rows[i].h
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
		if y >= r.y && y < r.y+r.h {
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
	case rowGroup:
		if searchText() != "" || lmode != lmAll {
			return // 찾는 중에는 늘 펼침
		}
		setCollapsed(r.key, !isCollapsed(r.key))
		refilterList()
	case rowMore:
		showMore = !showMore
		refilterList()
		if showMore { // 펼친 세부 기능이 보이도록 맨 아래로
			_, H := listClient()
			lsb.pos = lsb.total - H
			lsb.clamp()
		}
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
		if y+r.h < 0 || y > H {
			continue
		}
		hot := i == lhot
		switch r.kind {
		case rowGroup:
			x := si(8)
			if r.fav {
				drawTextAt(hdc, hFontGrp, favStarClr, x, y+(r.h-si(14))/2, "★")
				x += si(16)
			}
			clr := clrSubText
			if hot && !filtering {
				clr = clrText
			}
			_, th := textSize(hdc, hFontGrp, r.label)
			drawTextAt(hdc, hFontGrp, clr, x, y+(r.h-th)/2, r.label)
			if !filtering {
				drawChevron(hdc, cw-si(14), y+r.h/2, !isCollapsed(r.key), clr)
			}
		case rowItem:
			paintItemRow(hdc, r, y, cw, i == lsel, hot)
		case rowMore:
			fillBox(hdc, si(8), y, cw-si(16), 1, clrLine)
			clr := guideLinkColor()
			if hot {
				clr = clrText
			}
			sign := "＋ "
			if showMore {
				sign = "－ "
			}
			_, th := textSize(hdc, hFont, r.label)
			drawTextAt(hdc, hFont, clr, si(12), y+(r.h-th)/2+si(2), sign+r.label)
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
	switch {
	case sel:
		fillRound(hdc, x0, y+si(1), x1-x0, r.h-si(2), clrSelBg, clrSelBg, si(10))
		bar, _ := runColors(false, false)
		fillRound(hdc, x0, y+si(8), si(3), r.h-si(16), bar, bar, si(3))
	case hot:
		fillRound(hdc, x0, y+si(1), x1-x0, r.h-si(2), clrHotBg, clrHotBg, si(10))
	}
	// 아이콘 (둥근 사각형 + 기호)
	isz := si(26)
	ix, iy := x0+si(10), y+(r.h-isz)/2
	ibg := mixClr(clrBg, clrText, 0.10)
	gclr := clrSubText
	if sel {
		a, b := heroColors()
		ibg, gclr = mixClr(a, b, 0.5), white
	}
	cv := newCanvas(isz, isz, rowBg(sel, hot))
	f := float64(isz)
	cv.paint(func(px, py float64) float64 { return aa(sdRoundRect(px, py, 0.5, 0.5, f-0.5, f-0.5, float64(si(7)))) }, solid(ibg))
	cv.blit(hdc, ix, iy)
	old := c(pSelectObject, hdc, hFontGlyph)
	c(pSetTextColor, hdc, gclr)
	gr := rectT{int32(ix), int32(iy), int32(ix + isz), int32(iy + isz)}
	c(pDrawTextW, hdc, uintptr(P(ws(pickGlyph(r.node)))), ^uintptr(0), uintptr(P(&gr)), DT_CENTER|DT_VCENTER|DT_SINGLELINE)
	c(pSelectObject, hdc, old)
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
	tx := ix + isz + si(10)
	old = c(pSelectObject, hdc, hFont)
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
