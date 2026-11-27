package main

// 화면 꾸밈 (추가 설치 없이 Windows 기본 기능만 사용)
//  - 제목 표시줄·창 테두리 색을 배경(크림색)에 맞춤 (Windows 11 전용, 10에서는 조용히 무시)
//  - 일반 버튼을 직접 그림: 흰 바탕 둥근 버튼, 마우스를 올리면 테라코타, 기본(확인) 버튼은 강조색
//  - 입력칸·목록·설명서·로그의 3D 테두리 대신 얇은 둥근 테두리를 부모 창이 그림
//  - 목록 선택 표시를 파란색 대신 연한 테라코타로

import (
	"syscall"
	"unsafe"
)

var (
	pSetWindowLongPtrW = user32.NewProc("SetWindowLongPtrW")
	pCallWindowProcW   = user32.NewProc("CallWindowProcW")
	pTrackMouseEvent   = user32.NewProc("TrackMouseEvent")
	pGetParent         = user32.NewProc("GetParent")
	pIsWindowEnabled   = user32.NewProc("IsWindowEnabled")
	pExcludeClipRect   = gdi32.NewProc("ExcludeClipRect")
)

const (
	WM_MOUSELEAVE    = 0x02A3
	WM_LBUTTONDBLCLK = 0x0203
	WM_LBUTTONDOWN   = 0x0201
	DM_GETDEFID      = 0x0400
	DC_HASDEFID      = 0x534B
	TME_LEAVE        = 0x0002
	ODS_FOCUS        = 0x0010
	ODS_NOFOCUSRECT  = 0x0200

	DWMWA_BORDER_COLOR  = 34
	DWMWA_CAPTION_COLOR = 35

	TVM_SETITEMHEIGHT = 0x111B
	nmCustomDraw      = -12
	CDDS_PREPAINT     = 0x00000001
	CDDS_ITEMPREPAINT = 0x00010001
	CDRF_DODEFAULT    = 0x00
	CDRF_NOTIFYITEM   = 0x20
	CDIS_SELECTED     = 0x0001
	CDIS_FOCUS        = 0x0010
	CDIS_HOT          = 0x0040
)

var (
	clrBorder    = RGB(0xE0, 0xD9, 0xCC) // 버튼·입력칸 테두리 (따뜻한 회색)
	clrWinBorder = RGB(0xD9, 0xD2, 0xC4) // 창 바깥 테두리 (Windows 11)
	clrHoverBg   = RGB(0xFB, 0xEF, 0xEA) // 버튼에 마우스를 올렸을 때 바탕
	clrPressBg   = RGB(0xF4, 0xDF, 0xD6) // 버튼을 누르고 있을 때 바탕
	clrSelBg     = RGB(0xF6, 0xE4, 0xDC) // 목록 선택 항목 바탕
	clrSelText   = RGB(0x7A, 0x3E, 0x2A) // 목록 선택 항목 글자
	clrHotBg     = RGB(0xFA, 0xF6, 0xEF) // 목록에 마우스를 올린 항목 바탕
	clrBtnBg     = RGB(0xFF, 0xFF, 0xFF) // 일반 버튼(실행 외) 바탕 - 창 배경보다 밝게 (theme.go)
	clrBtnBorder = RGB(0xE0, 0xD9, 0xCC)
	clrBtnHover  = RGB(0xFB, 0xEF, 0xEA)
)

// ───────────── 창 제목 표시줄·테두리 색 ─────────────
func styleWindow(h uintptr) {
	round := int32(DWMWC_ROUND)
	c(pDwmSetWindowAttribute, h, DWMWA_WINDOW_CORNER_PREFERENCE, uintptr(P(&round)), 4)
	dark := uint32(0)
	if curTheme.dark {
		dark = 1 // 최소·최대·닫기 단추를 밝은 색으로
	}
	c(pDwmSetWindowAttribute, h, DWMWA_USE_IMMERSIVE_DARK_MODE, uintptr(P(&dark)), 4)
	txt := uint32(clrText)
	c(pDwmSetWindowAttribute, h, DWMWA_TEXT_COLOR, uintptr(P(&txt)), 4)
	cap := uint32(clrBg)
	c(pDwmSetWindowAttribute, h, DWMWA_CAPTION_COLOR, uintptr(P(&cap)), 4)
	bd := uint32(clrWinBorder)
	c(pDwmSetWindowAttribute, h, DWMWA_BORDER_COLOR, uintptr(P(&bd)), 4)
}

// ───────────── 직접 그리는 버튼 ─────────────
type trackMouseEvent struct {
	size, flags uint32
	hwnd        uintptr
	hoverTime   uint32
}

var (
	hFontBtnBold uintptr // 강조 버튼 글꼴 (9pt 굵게)
	hFontRun     uintptr // '▶ 실행' 버튼 글꼴 (13pt 굵게)
	hFontIcon    uintptr // 전구 버튼 아이콘 글꼴 (Segoe MDL2 Assets, Windows 10/11 기본 글꼴)
)

func makeIconFont(pt int) uintptr {
	height := -int(float64(pt) * scale * 96 / 72)
	return c(pCreateFontW, uintptr(height), 0, 0, 0, 400, 0, 0, 0, 1, 0, 0, 5, 0, uintptr(P(ws("Segoe MDL2 Assets"))))
}

var (
	flatBtn    = map[uintptr]bool{} // 직접 그리는 일반 버튼
	primaryBtn = map[uintptr]bool{} // 강조색으로 그리는 기본(확인) 버튼
	oldProc    = map[uintptr]uintptr{}
	hotBtn     uintptr
	btnSubProc = syscall.NewCallback(btnProc)
)

// mkp 에서 호출: 일반 누름 버튼이면 직접 그리는 버튼으로 바꾼 스타일을 돌려준다.
func ownerDrawStyle(class string, style uint32) (uint32, bool, bool) {
	if class != "BUTTON" {
		return style, false, false
	}
	switch style & 0xF {
	case 0: // BS_PUSHBUTTON
		return style | BS_OWNERDRAW, true, false
	case BS_DEFPUSHBUTTON:
		return style&^0xF | BS_OWNERDRAW, true, true
	case BS_OWNERDRAW: // '▶ 실행' (원래부터 직접 그림) - 마우스 올림 효과만 추가
		return style, true, false
	}
	return style, false, false
}

func hookButton(h uintptr, primary bool) {
	flatBtn[h] = true
	if primary {
		primaryBtn[h] = true
	}
	oldProc[h] = c(pSetWindowLongPtrW, h, ^uintptr(3) /*GWLP_WNDPROC = -4*/, btnSubProc)
}

func btnProc(h, msg, wp, lp uintptr) uintptr {
	switch msg {
	case WM_MOUSEMOVE:
		if hotBtn != h {
			if hotBtn != 0 {
				c(pInvalidateRect, hotBtn, 0, 0)
			}
			hotBtn = h
			tme := trackMouseEvent{flags: TME_LEAVE, hwnd: h}
			tme.size = uint32(unsafe.Sizeof(tme))
			c(pTrackMouseEvent, uintptr(P(&tme)))
			c(pInvalidateRect, h, 0, 0)
		}
	case WM_MOUSELEAVE:
		if hotBtn == h {
			hotBtn = 0
		}
		c(pInvalidateRect, h, 0, 0)
	case WM_LBUTTONDBLCLK:
		msg = WM_LBUTTONDOWN // 빠르게 두 번 눌러도 두 번 다 클릭으로 (▲ 위로 등)
	case WM_TIMER:
		if wp == toggleTimerID {
			toggleTick(h)
			return 0
		}
	case WM_DESTROY:
		delete(toggles, h)
		old := oldProc[h]
		delete(oldProc, h)
		delete(flatBtn, h)
		delete(primaryBtn, h)
		if hotBtn == h {
			hotBtn = 0
		}
		return c(pCallWindowProcW, old, h, msg, wp, lp)
	}
	return c(pCallWindowProcW, oldProc[h], h, msg, wp, lp)
}

// WM_DRAWITEM 처리 (메인 창·대화상자 공통). '▶ 실행' 과 기본(확인) 버튼은 강조색, 나머지는 흰 버튼.
func drawButton(lp uintptr) uintptr {
	dis := (*drawItemStruct)(unsafe.Pointer(lp))
	h := dis.hwndItem
	if h != 0 && h == hWinCombo { // 작업할 도면 선택칸 (ui2.go)
		drawCadItem(dis)
		return 1
	}
	if h != 0 && h == hChip { // 명령어·리습 꼬리표 (ui2.go)
		drawChipTags(dis)
		return 1
	}
	if h != hRun && !flatBtn[h] {
		return 0
	}
	if isChip(h) { // 목록 보기 버튼 (listpane.go)
		drawChip(dis)
		return 1
	}
	if h == hRun { // 그라데이션·그림자 실행 버튼 (ui2.go)
		drawRunButton(dis)
		return 1
	}
	if isToggle(h) { // 체크박스 → 토글 스위치 (toggle.go)
		drawSwitch(dis)
		return 1
	}
	hdc := dis.hDC
	fillBox(hdc, int(dis.rcItem.left), int(dis.rcItem.top), int(dis.rcItem.right-dis.rcItem.left), int(dis.rcItem.bottom-dis.rcItem.top), ctlBg(h)) // 둥근 모서리 바깥은 바탕색 (실행 막대 안이면 막대색)

	disabled := dis.itemState&ODS_DISABLED != 0
	pressed := dis.itemState&ODS_SELECTED != 0
	hot := hotBtn == h
	focus := dis.itemState&ODS_FOCUS != 0 && dis.itemState&ODS_NOFOCUSRECT == 0
	font := hFont

	var fill, border, txt uintptr
	if h == hRun || primaryBtn[h] {
		font = hFontBtnBold
		if h == hRun {
			font = hFontRun
		}
		fill, border, txt = clrAccent, clrAccent, clrAccentTxt
		switch {
		case disabled:
			fill, border, txt = clrDisBg, clrDisBorder, clrSubText
		case pressed:
			fill, border = clrAccentPress, clrAccentPress
		case hot:
			fill, border = clrAccentHot, clrAccentHot // 마우스를 올리면 진한 적갈색으로 확실히 바뀜
		case focus:
			border = clrAccentDk
		}
	} else {
		fill, border, txt = clrBtnBg, clrBtnBorder, clrText
		switch {
		case disabled:
			fill, border, txt = clrBg, clrBorder, clrSubText
		case pressed:
			fill, border, txt = clrPressBg, clrAccent, clrHoverTxt
		case hot:
			fill, border, txt = clrBtnHover, clrAccent, clrHoverTxt
		case focus:
			border = clrAccent
		}
	}
	box := dis.rcItem
	if h == hUpdate { // 업데이트 버튼: 위·오른쪽 여백(updPad)을 두고 그 모서리에 알림 점
		box.top += int32(s(updPad))
		box.right -= int32(s(updPad))
	}
	roundBox(hdc, box, fill, border, 8)

	c(pSetBkMode, hdc, TRANSPARENT)
	c(pSetTextColor, hdc, txt)
	label := getText(h)
	if h == hFavBtn { // 즐겨찾기 별: 조금 큰 글씨, 즐겨찾기면 노란 별
		font = hFontBold
		if getText(h) == "★" {
			c(pSetTextColor, hdc, favStarClr)
		}
	}
	if h == hFind { // 다시 찾기: 새로고침 아이콘
		font, label = hFontIcon, "\uE72C"
	}
	if h == hAdvanced { // 설정: 톱니바퀴 아이콘
		font, label = hFontIcon, "\uE713"
	}
	if h == hThemeBtn { // 전구: 다크(불 꺼짐)는 회색, 크림(불 켜짐)은 노란색
		font, label = hFontIcon, "\uE82F"
		switch curTheme.key {
		case "cream":
			c(pSetTextColor, hdc, RGB(0xE0, 0xA1, 0x1B))
		case "slate":
			c(pSetTextColor, hdc, RGB(0x8E, 0xC5, 0xFF))
		}
	}
	oldFont := c(pSelectObject, hdc, font)
	rc := box
	if h != hFavBtn || !drawGlyphCentered(hdc, label, box) {
		c(pDrawTextW, hdc, uintptr(P(ws(label))), ^uintptr(0), uintptr(P(&rc)), DT_CENTER|DT_VCENTER|DT_SINGLELINE)
	}
	c(pSelectObject, hdc, oldFont)
	if h == hUpdate && updateAvail {
		// 버튼 오른쪽 위 모서리에 걸친 빨간 점 + 둘레에 배경색 테두리
		cx, cy := int(box.right)-int(s(2)), int(box.top)+int(s(1))
		ring, dot := int(s(11)), int(s(8))
		fillRoundEllipse(hdc, cx-ring/2, cy-ring/2, ring, clrBg)
		fillRoundEllipse(hdc, cx-dot/2, cy-dot/2, dot, RGB(0xE8, 0x40, 0x40))
	}
	return 1
}

// 업데이트 버튼 위·오른쪽 여백 (빨간 점이 버튼 밖으로 살짝 걸치는 자리)
const updPad = 4

// 받을 업데이트가 있는데 아직 받지 않았으면 true → 업데이트 버튼에 빨간 점 (update.go)
var updateAvail bool

func setUpdateAvail(v bool) {
	if updateAvail != v {
		updateAvail = v
		c(pInvalidateRect, hUpdate, 0, 0)
	}
}

func roundBox(hdc uintptr, r rectT, fill, border uintptr, radius int) {
	br := c(pCreateSolidBrush, fill)
	pen := c(pCreatePen, PS_SOLID, 1, border)
	oldBr := c(pSelectObject, hdc, br)
	oldPen := c(pSelectObject, hdc, pen)
	rd := s(radius)
	c(pRoundRect, hdc, uintptr(r.left), uintptr(r.top), uintptr(r.right), uintptr(r.bottom), rd, rd)
	c(pSelectObject, hdc, oldBr)
	c(pSelectObject, hdc, oldPen)
	c(pDeleteObject, br)
	c(pDeleteObject, pen)
}

// ───────────── 입력칸·목록 테두리 ─────────────
// 3D 테두리(WS_EX_CLIENTEDGE)를 빼고, 컨트롤을 안쪽으로 조금 줄여 놓은 뒤
// 부모 창이 그 둘레에 흰 바탕 + 얇은 둥근 테두리를 그린다.
const framePad = 3

var framed = map[uintptr]bool{}

func paintFrames(h uintptr) {
	var ps paintStruct
	hdc := c(pBeginPaint, h, uintptr(P(&ps)))
	pad := int32(s(framePad))
	for ch := range framed {
		if c(pIsWindow, ch) == 0 { // 지워진 컨트롤(옵션 칸 등)
			delete(framed, ch)
			continue
		}
		if c(pGetParent, ch) != h || c(pIsWindowVisible, ch) == 0 {
			continue
		}
		var r rectT
		c(pGetWindowRect, ch, uintptr(P(&r)))
		c(pMapWindowPoints, 0, h, uintptr(P(&r)), 2)
		c(pExcludeClipRect, hdc, uintptr(r.left), uintptr(r.top), uintptr(r.right), uintptr(r.bottom))
		outer := rectT{r.left - pad, r.top - pad, r.right + pad, r.bottom + pad}
		fill := clrPanelBg
		if c(pIsWindowEnabled, ch) == 0 {
			fill = clrBg
		}
		roundBox(hdc, outer, fill, clrBorder, 8)
	}
	c(pEndPaint, h, uintptr(P(&ps)))
}

// 목록 색 (화면 색상을 바꿀 때) - 목록은 listpane.go 가 직접 그림
func styleTree() {
	if hList != 0 {
		c(pInvalidateRect, hList, 0, 0)
	}
}

// ───────────── 글자 하나(별 등)를 버튼 정중앙에 ─────────────
// DrawText 의 가운데 맞춤은 글꼴의 줄 높이 기준이라 ★ 처럼 기호 글자는 위아래·좌우로 치우친다.
// 글자의 실제 잉크 영역(GetGlyphOutline 치수)을 재서 그 가운데가 상자 가운데에 오도록 찍는다.
var (
	pGetGlyphOutlineW = gdi32.NewProc("GetGlyphOutlineW")
	pTextOutW         = gdi32.NewProc("TextOutW")
	pSetTextAlign     = gdi32.NewProc("SetTextAlign")
)

type glyphMetrics struct {
	blackBoxX, blackBoxY uint32
	originX, originY     int32
	cellIncX, cellIncY   int16
}

func drawGlyphCentered(hdc uintptr, label string, box rectT) bool {
	r := []rune(label)
	if len(r) != 1 {
		return false
	}
	var gm glyphMetrics
	mat := [4]int32{1 << 16, 0, 0, 1 << 16} // MAT2 단위 행렬 (FIXED: 정수부가 위 16비트)
	if c(pGetGlyphOutlineW, hdc, uintptr(r[0]), 0 /*GGO_METRICS*/, uintptr(P(&gm)), 0, 0, uintptr(P(&mat))) == 0xFFFFFFFF {
		return false
	}
	cx := (int(box.left) + int(box.right)) / 2
	cy := (int(box.top) + int(box.bottom)) / 2
	x := cx - int(gm.originX) - int(gm.blackBoxX)/2
	y := cy + int(gm.originY) - int(gm.blackBoxY)/2 // 글자 기준선 (originY 는 기준선에서 잉크 위쪽까지)
	old := c(pSetTextAlign, hdc, 24 /*TA_BASELINE|TA_LEFT*/)
	s := ws(label)
	c(pTextOutW, hdc, uintptr(x), uintptr(y), uintptr(P(s)), 1)
	c(pSetTextAlign, hdc, old)
	return true
}
