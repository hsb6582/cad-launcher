package main

// 즐겨찾기: 기능별로 이 PC에만 저장 (launcher_state.json 의 favorites, "리습|명령어").
//  - 목록 맨 위 '★ 즐겨찾기' 묶음에 바로가기로 한 번 더 보이고, 원래 분류의 이름 뒤에는 작은 노란 별
//  - 넣고 빼기: 설명서 머리 줄 별 버튼(☆/★) 또는 목록 오른쪽 클릭 메뉴
//  - 즐겨찾기 묶음 안에서 ▲▼ 로 순서 변경. 목록에서 없어진 기능은 조용히 빠짐

import "unsafe"

var (
	pCreatePopupMenu = user32.NewProc("CreatePopupMenu")
	pAppendMenuW     = user32.NewProc("AppendMenuW")
	pTrackPopupMenu  = user32.NewProc("TrackPopupMenu")
	pDestroyMenu     = user32.NewProc("DestroyMenu")
)

const nmRClick = -5 // NM_RCLICK

var (
	favHandle  = map[uintptr]bool{}    // 즐겨찾기 묶음 안의 트리 항목
	favNode    = map[nodeRef]uintptr{} // 기능 → 즐겨찾기 묶음 안의 트리 항목
	curFav     bool                    // 지금 고른 항목이 즐겨찾기 묶음 안에 있음
	selFavNext bool                    // 다음 refreshTree 때 즐겨찾기 묶음 쪽을 선택
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

// refreshTree 맨 앞에서: '★ 즐겨찾기' 묶음과 바로가기 항목
func insertFavTree() {
	favHandle, favNode = map[uintptr]bool{}, map[nodeRef]uintptr{}
	refs := favRefs()
	if len(refs) == 0 {
		return
	}
	state := uint32(TVIS_BOLD)
	if !isCollapsed("f:") {
		state |= TVIS_EXPANDED
	}
	hg := tvInsertItem(tviRoot, T("fav.001"), state)
	itemNode[hg] = nodeRef{nkFavGroup, 0, 0}
	for _, n := range refs {
		it := n.item()
		rs := uint32(0)
		if it.Recommend {
			rs = stateRecommend
		}
		h := tvInsertItem(hg, it.Name, rs)
		itemNode[h] = n // 같은 기능을 가리킴 (원래 분류 쪽 nodeItem 은 그대로)
		favHandle[h] = true
		favNode[n] = h
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

// 목록 오른쪽 클릭: 그 항목을 고르고 [▶ 실행 / 즐겨찾기에 추가·빼기] 메뉴
func onTreeRClick() {
	var pt [2]int32
	c(pGetCursorPos, uintptr(P(&pt)))
	scr := pt
	c(pScreenToClient, hList, uintptr(P(&pt)))
	ht := struct {
		pt    [2]int32
		flags uint32
		item  uintptr
	}{pt: pt}
	h := c(pSendMessageW, hList, TVM_HITTEST, 0, uintptr(unsafe.Pointer(&ht)))
	if h == 0 {
		return
	}
	c(pSendMessageW, hList, TVM_SELECTITEM, TVGN_CARET, h)
	n, ok := itemNode[h]
	if !ok || n.kind != nkItem {
		return
	}
	it := n.item()
	m := c(pCreatePopupMenu)
	c(pAppendMenuW, m, 0 /*MF_STRING*/, 1, uintptr(P(ws(T("fav.002")))))
	c(pAppendMenuW, m, 0x800 /*MF_SEPARATOR*/, 0, 0)
	favLabel := T("fav.003")
	if isFav(it) {
		favLabel = T("fav.006")
	}
	c(pAppendMenuW, m, 0, 2, uintptr(P(ws(favLabel))))
	cmd := c(pTrackPopupMenu, m, 0x0100|0x0002 /*TPM_RETURNCMD|TPM_RIGHTBUTTON*/, uintptr(scr[0]), uintptr(scr[1]), 0, hMain, 0)
	c(pDestroyMenu, m)
	switch cmd {
	case 1:
		runCurrent()
	case 2:
		toggleFav(it)
	}
}
