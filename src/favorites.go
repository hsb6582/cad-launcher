package main

// 즐겨찾기: 기능별로 이 PC에만 저장 (launcher_state.json 의 favorites, "리습|명령어").
//  - 목록 맨 위 '★ 즐겨찾기' 묶음에 바로가기로 한 번 더 보이고, 원래 분류의 이름 뒤에는 작은 노란 별
//  - 넣고 빼기: 설명서 머리 줄 별 버튼(☆/★) 또는 목록 오른쪽 클릭 메뉴
//  - 즐겨찾기 묶음 안에서 ▲▼ 로 순서 변경. 목록에서 없어진 기능은 조용히 빠짐

import (
	"math"
	"unsafe"
)

var (
	pCreatePopupMenu = user32.NewProc("CreatePopupMenu")
	pAppendMenuW     = user32.NewProc("AppendMenuW")
	pTrackPopupMenu  = user32.NewProc("TrackPopupMenu")
	pDestroyMenu     = user32.NewProc("DestroyMenu")
	pSetMenuItemInfo = user32.NewProc("SetMenuItemInfoW")
)

const nmRClick = -5 // NM_RCLICK

var (
	hFavBtn    uintptr                 // 설명서 머리 줄 별 버튼
	favStarClr = RGB(0xF5, 0xBE, 0x3C) // 노란 별
)

func isFav(it *Item) bool {
	if it == nil {
		return false
	}
	k := itemKey(it)
	for _, f := range st.Favorites {
		if f == k {
			return true
		}
	}
	return false
}

// 즐겨찾기 순서대로 목록 위치를 찾음 (목록에 없는 것은 건너뜀)
func favRefs() []nodeRef {
	pos := map[string]nodeRef{}
	for ci := range cat.Categories {
		for ii := range cat.Categories[ci].Items {
			pos[itemKey(&cat.Categories[ci].Items[ii])] = nodeRef{nkItem, ci, ii}
		}
	}
	var out []nodeRef
	for _, f := range st.Favorites {
		if n, ok := pos[f]; ok {
			out = append(out, n)
		}
	}
	return out
}

// 목록에서 없어진 기능은 즐겨찾기에서 뺀다 (목록을 읽은 뒤)
func pruneFavs() {
	if len(st.Favorites) == 0 || len(cat.Categories) == 0 {
		return
	}
	have := map[string]bool{}
	for ci := range cat.Categories {
		for ii := range cat.Categories[ci].Items {
			have[itemKey(&cat.Categories[ci].Items[ii])] = true
		}
	}
	var keep []string
	for _, f := range st.Favorites {
		if have[f] {
			keep = append(keep, f)
		}
	}
	if len(keep) != len(st.Favorites) {
		st.Favorites = keep
		saveState()
	}
}

func toggleFav(it *Item) {
	if it == nil {
		return
	}
	k := itemKey(it)
	if isFav(it) {
		var keep []string
		for _, f := range st.Favorites {
			if f != k {
				keep = append(keep, f)
			}
		}
		st.Favorites = keep
		logf(T("fav.004"), it.Name)
		selFavNext = false
	} else {
		st.Favorites = append(st.Favorites, k)
		logf(T("fav.005"), it.Name)
		selFavNext = curFav
	}
	saveState()
	refreshTree(cur)
}

// 즐겨찾기 묶음 안에서 ▲▼
func moveFav(dir int) {
	it := cur.item()
	if it == nil {
		return
	}
	k := itemKey(it)
	i := -1
	for j, f := range st.Favorites {
		if f == k {
			i = j
		}
	}
	j := i + dir
	if i < 0 || j < 0 || j >= len(st.Favorites) {
		return
	}
	st.Favorites[i], st.Favorites[j] = st.Favorites[j], st.Favorites[i]
	saveState()
	selFavNext = true
	refreshTree(cur)
}

// 설명서 머리 줄 별 버튼: 기능을 골랐을 때만 보이고, 즐겨찾기면 ★ 아니면 ☆
func updateFavBtn() {
	if hFavBtn == 0 {
		return
	}
	it := cur.item()
	show(hFavBtn, it != nil)
	if isFav(it) {
		setText(hFavBtn, "★")
	} else {
		setText(hFavBtn, "☆")
	}
	c(pInvalidateRect, hFavBtn, 0, 1)
}

// 목록 오른쪽 클릭 (listpane.go 가 그 기능을 고른 뒤 부름): [▶ 실행 / 즐겨찾기]
func onTreeRClick() {
	var scr [2]int32
	c(pGetCursorPos, uintptr(P(&scr)))
	it := cur.item()
	if it == nil {
		return
	}
	m := c(pCreatePopupMenu)
	c(pAppendMenuW, m, 0 /*MF_STRING*/, 1, uintptr(P(ws(T("fav.002")))))
	c(pAppendMenuW, m, 0x800 /*MF_SEPARATOR*/, 0, 0)
	favLabel := T("fav.003")
	if isFav(it) {
		favLabel = T("fav.006")
	}
	c(pAppendMenuW, m, 0, 2, uintptr(P(ws(favLabel))))
	// 메뉴 왼쪽 그림: 실행 = 파란 재생 삼각형, 즐겨찾기 추가 = 노란 별, 빼기 = 노란 빈 별
	setMenuIcon(m, 1, menuIcon(iconPlay))
	if isFav(it) {
		setMenuIcon(m, 2, menuIcon(iconStarOutline))
	} else {
		setMenuIcon(m, 2, menuIcon(iconStar))
	}
	cmd := c(pTrackPopupMenu, m, 0x0100|0x0002 /*TPM_RETURNCMD|TPM_RIGHTBUTTON*/, uintptr(scr[0]), uintptr(scr[1]), 0, hMain, 0)
	c(pDestroyMenu, m)
	switch cmd {
	case 1:
		runCurrent()
	case 2:
		toggleFav(it)
	}
}

// ───────────── 메뉴 그림 (부드러운 가장자리로 직접 그림) ─────────────

const (
	iconPlay = iota
	iconStar
	iconStarOutline
)

var menuIcons = map[int]uintptr{}

type menuItemInfo struct {
	cbSize        uint32
	fMask         uint32
	fType         uint32
	fState        uint32
	wID           uint32
	hSubMenu      uintptr
	hbmpChecked   uintptr
	hbmpUnchecked uintptr
	dwItemData    uintptr
	dwTypeData    uintptr
	cch           uint32
	hbmpItem      uintptr
}

func setMenuIcon(m uintptr, id int, hbm uintptr) {
	if hbm == 0 {
		return
	}
	mi := menuItemInfo{fMask: 0x80 /*MIIM_BITMAP*/, hbmpItem: hbm}
	mi.cbSize = uint32(unsafe.Sizeof(mi))
	c(pSetMenuItemInfo, m, uintptr(id), 0, uintptr(P(&mi)))
}

// 점이 다각형 안에 있는지 (짝수-홀수 규칙)
func inPoly(x, y float64, pts [][2]float64) bool {
	in := false
	for i, j := 0, len(pts)-1; i < len(pts); j, i = i, i+1 {
		xi, yi, xj, yj := pts[i][0], pts[i][1], pts[j][0], pts[j][1]
		if (yi > y) != (yj > y) && x < (xj-xi)*(y-yi)/(yj-yi)+xi {
			in = !in
		}
	}
	return in
}

func starPts(cx, cy, r, ri float64) [][2]float64 {
	var p [][2]float64
	for k := 0; k < 10; k++ {
		a := -math.Pi/2 + float64(k)*math.Pi/5
		rr := r
		if k%2 == 1 {
			rr = ri
		}
		p = append(p, [2]float64{cx + rr*math.Cos(a), cy + rr*math.Sin(a)})
	}
	return p
}

// 32비트 알파 비트맵 (메뉴 항목 왼쪽 그림). 4×4 표본으로 가장자리를 부드럽게
func menuIcon(kind int) uintptr {
	if h, ok := menuIcons[kind]; ok {
		return h
	}
	n := int(s(16))
	var clr [3]float64
	var cover func(x, y float64) bool
	switch kind {
	case iconPlay:
		clr = [3]float64{0x2F, 0x6F, 0xB8}
		tri := [][2]float64{{0.28, 0.18}, {0.28, 0.82}, {0.84, 0.50}}
		cover = func(x, y float64) bool { return inPoly(x, y, tri) }
	case iconStar:
		clr = [3]float64{0xF5, 0xBE, 0x3C}
		st := starPts(0.5, 0.53, 0.48, 0.20)
		cover = func(x, y float64) bool { return inPoly(x, y, st) }
	default: // 빈 별: 바깥 별 - 안쪽 별
		clr = [3]float64{0xE0, 0xA5, 0x25}
		outer := starPts(0.5, 0.53, 0.48, 0.20)
		inner := starPts(0.5, 0.53, 0.30, 0.125)
		cover = func(x, y float64) bool { return inPoly(x, y, outer) && !inPoly(x, y, inner) }
	}
	bi := bitmapInfoHeader{biWidth: int32(n), biHeight: -int32(n), biPlanes: 1, biBitCount: 32}
	bi.biSize = uint32(unsafe.Sizeof(bi))
	var bits uintptr
	hbm := c(pCreateDIBSection, 0, uintptr(P(&bi)), 0, uintptr(P(&bits)), 0, 0)
	if hbm == 0 || bits == 0 {
		return 0
	}
	dst := unsafe.Slice((*byte)(unsafe.Pointer(bits)), n*n*4)
	const ss = 4
	for py := 0; py < n; py++ {
		for px := 0; px < n; px++ {
			hit := 0
			for sy := 0; sy < ss; sy++ {
				for sx := 0; sx < ss; sx++ {
					x := (float64(px) + (float64(sx)+0.5)/ss) / float64(n)
					y := (float64(py) + (float64(sy)+0.5)/ss) / float64(n)
					if cover(x, y) {
						hit++
					}
				}
			}
			a := float64(hit) / (ss * ss)
			i := (py*n + px) * 4 // BGRA, 알파를 곱한 값 (메뉴 그림 형식)
			dst[i], dst[i+1], dst[i+2], dst[i+3] = byte(clr[2]*a), byte(clr[1]*a), byte(clr[0]*a), byte(255*a)
		}
	}
	menuIcons[kind] = hbm
	return hbm
}
