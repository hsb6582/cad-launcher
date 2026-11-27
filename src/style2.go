package main

// 화면 꾸밈 (추가 설치 없이 Windows 기본 기능만 사용)
//  - 제목 표시줄·창 테두리 색을 배경(크림색)에 맞춤 (Windows 11 전용, 10에서는 조용히 무시)
//  - 일반 버튼을 직접 그림: 흰 바탕 둥근 버튼, 마우스를 올리면 테라코타, 기본(확인) 버튼은 강조색
//  - 입력칸·목록·설명서·로그의 3D 테두리 대신 얇은 둥근 테두리를 부모 창이 그림
//  - 목록 선택 표시를 파란색 대신 연한 테라코타로

import (
	"strings"
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
	case WM_DESTROY:
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
	if h != hRun && !flatBtn[h] {
		return 0
	}
	hdc := dis.hDC
	c(pFillRect, hdc, uintptr(P(&dis.rcItem)), hBgBrush) // 둥근 모서리 바깥은 창 배경색

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
		fill, border, txt = clrPanelBg, clrBorder, clrText
		switch {
		case disabled:
			fill, border, txt = clrBg, clrBorder, clrSubText
		case pressed:
			fill, border, txt = clrPressBg, clrAccent, clrHoverTxt
		case hot:
			fill, border, txt = clrHoverBg, clrAccent, clrHoverTxt
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
	c(pDrawTextW, hdc, uintptr(P(ws(label))), ^uintptr(0), uintptr(P(&rc)), DT_CENTER|DT_VCENTER|DT_SINGLELINE)
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

// ───────────── 목록(트리) 선택 색 ─────────────
type nmTVCustomDraw struct {
	hdr        nmhdr
	drawStage  uint32
	hdc        uintptr
	rc         rectT
	itemSpec   uintptr
	itemState  uint32
	itemlParam uintptr
	clrText    uint32
	clrTextBk  uint32
	level      int32
}

func styleTree() {
	c(pSendMessageW, hList, TVM_SETITEMHEIGHT, s(24), 0)
	c(pSendMessageW, hList, TVM_SETTEXTCOLOR, 0, clrText)
	c(pSendMessageW, hList, TVM_SETBKCOLOR, 0, clrPanelBg)
}

func treeCustomDraw(lp uintptr) uintptr {
	cd := (*nmTVCustomDraw)(unsafe.Pointer(lp))
	switch cd.drawStage {
	case CDDS_PREPAINT:
		return CDRF_NOTIFYITEM
	case CDDS_ITEMPREPAINT:
		if n, ok := itemNode[cd.itemSpec]; ok && (n.kind == nkGroup || n.kind == nkFavGroup) {
			drawGroupRow(cd, n) // 상위 분류·즐겨찾기 묶음: 줄 전체를 직접 그림
			return 0x04         // CDRF_SKIPDEFAULT
		}
		switch {
		case cd.itemState&CDIS_SELECTED != 0:
			cd.itemState &^= CDIS_SELECTED | CDIS_FOCUS | CDIS_HOT // 탐색기 테마의 파란 선택 표시 대신
			cd.clrText = uint32(clrSelText)
			cd.clrTextBk = uint32(clrSelBg)
		case cd.itemState&CDIS_HOT != 0:
			cd.itemState &^= CDIS_HOT
			cd.clrTextBk = uint32(clrHotBg)
		}
		if n, ok := itemNode[cd.itemSpec]; ok && n.kind == nkItem && !favHandle[cd.itemSpec] && isFav(n.item()) {
			return 0x10 // CDRF_NOTIFYPOSTPAINT: 이름 뒤 작은 별
		}
		return 0 // 목록에는 기능 이름만 (명령어는 설명서 머리 줄에 표시)
	case 0x10002: // CDDS_ITEMPOSTPAINT
		// 즐겨찾기 기능: 원래 분류 쪽 이름 뒤에 작은 노란 별
		var r struct {
			h    uintptr
			_, _ int32
		}
		r.h = cd.itemSpec
		if c(pSendMessageW, hList, 0x1104 /*TVM_GETITEMRECT*/, 1, uintptr(unsafe.Pointer(&r))) == 0 {
			break
		}
		rc := (*rectT)(unsafe.Pointer(&r))
		old := c(pSelectObject, cd.hdc, hFont)
		c(pSetBkMode, cd.hdc, TRANSPARENT)
		c(pSetTextColor, cd.hdc, favStarClr)
		tr := rectT{rc.right + int32(s(4)), rc.top, cd.rc.right, rc.bottom}
		c(pDrawTextW, cd.hdc, uintptr(P(ws("★"))), ^uintptr(0), uintptr(P(&tr)), DT_VCENTER|DT_SINGLELINE|DT_NOPREFIX)
		c(pSelectObject, cd.hdc, old)
	}
	return CDRF_DODEFAULT
}

// ───────────── 상위 분류·즐겨찾기 묶음 줄 (줄 전체를 직접 그림) ─────────────
var (
	pPolyline  = gdi32.NewProc("Polyline")
	hFontGroup uintptr // 상위 분류 글꼴 (다른 줄보다 조금 큰 굵은 글씨)
)

func drawGroupRow(cd *nmTVCustomDraw, n nodeRef) {
	if hFontGroup == 0 {
		hFontGroup = makeFont(11, true)
	}
	hdc, rc := cd.hdc, cd.rc
	// 줄 바탕 → 띠 (양옆 4px 여백, 위아래 2px)
	bg := c(pCreateSolidBrush, clrPanelBg)
	c(pFillRect, hdc, uintptr(P(&rc)), bg)
	c(pDeleteObject, bg)
	band := rc
	band.left += int32(s(4))
	band.right -= int32(s(4))
	band.top += int32(s(2))
	band.bottom -= int32(s(2))
	fill, txt := clrHotBg, clrText
	switch {
	case cd.itemState&CDIS_SELECTED != 0:
		fill, txt = clrSelBg, clrSelText
	case cd.itemState&CDIS_HOT != 0:
		fill = clrHoverBg
	}
	roundBox(hdc, band, fill, fill, 6)
	// 띠 왼쪽 세로줄: 상위 분류는 강조색, 즐겨찾기는 노랑
	barClr := clrAccent
	if n.kind == nkFavGroup {
		barClr = favStarClr
	}
	bar := rectT{band.left, band.top, band.left + int32(s(3)), band.bottom}
	br := c(pCreateSolidBrush, barClr)
	c(pFillRect, hdc, uintptr(P(&bar)), br)
	c(pDeleteObject, br)
	// 펼침 화살표 (펼침 ∨ / 접힘 ›) - 트리의 원래 펼침 단추 자리
	expanded := c(pSendMessageW, hList, 0x1127 /*TVM_GETITEMSTATE*/, cd.itemSpec, TVIS_EXPANDED)&TVIS_EXPANDED != 0
	cx, cy := int32(band.left)+int32(s(9)), (rc.top+rc.bottom)/2 // 원래 펼침 단추를 누르는 자리 안쪽
	w := int32(s(4))
	var pts [3][2]int32
	if expanded {
		pts = [3][2]int32{{cx - w, cy - w/2}, {cx, cy + w/2}, {cx + w, cy - w/2}}
	} else {
		pts = [3][2]int32{{cx - w/2, cy - w}, {cx + w/2, cy}, {cx - w/2, cy + w}}
	}
	pen := c(pCreatePen, PS_SOLID, uintptr(s(2)), txt)
	op := c(pSelectObject, hdc, pen)
	c(pPolyline, hdc, uintptr(P(&pts[0])), 3)
	c(pSelectObject, hdc, op)
	c(pDeleteObject, pen)
	// 이름 (즐겨찾기는 노란 별 + 이름)
	x := cx + int32(s(12))
	old := c(pSelectObject, hdc, hFontGroup)
	c(pSetBkMode, hdc, TRANSPARENT)
	name := ""
	if n.kind == nkFavGroup {
		c(pSetTextColor, hdc, favStarClr)
		sr := rectT{x, rc.top, band.right, rc.bottom}
		c(pDrawTextW, hdc, uintptr(P(ws("★"))), ^uintptr(0), uintptr(P(&sr)), DT_VCENTER|DT_SINGLELINE|DT_NOPREFIX)
		x += int32(s(strW("★", hFontGroup) + 6))
		name = strings.TrimSpace(strings.TrimPrefix(T("fav.001"), "★"))
	} else if n.ci < len(groupNames) {
		name = groupNames[n.ci]
	}
	c(pSetTextColor, hdc, txt)
	tr := rectT{x, rc.top, band.right - int32(s(6)), rc.bottom}
	c(pDrawTextW, hdc, uintptr(P(ws(name))), ^uintptr(0), uintptr(P(&tr)), DT_VCENTER|DT_SINGLELINE|DT_NOPREFIX|0x8000 /*DT_END_ELLIPSIS*/)
	c(pSelectObject, hdc, old)
}
