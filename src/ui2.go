package main

// 새 화면(시안) 꾸밈 - Windows GDI 는 둥근 모서리·그라데이션을 매끄럽게 못 그리므로
// 작은 그림(실행 버튼, 기능 아이콘, 자동 로드 스위치)은 Go 로 픽셀을 직접 계산해서(부드러운 가장자리)
// DIB 로 만든 뒤 한 번에 찍는다. 글자는 그 위에 GDI 로 쓴다.
//  - 실행 버튼: 파랑 그라데이션 + 아래 그림자 + 둥근 재생 아이콘 + '실행' / 'Enter'
//  - 오른쪽 머리: 기능 아이콘(둥근 사각형 + Segoe MDL2 기호)
//  - 맨 위 줄: 작업할 도면 선택칸을 직접 그림 (● 도면 이름 ······ AutoCAD LT 2026 · 연결됨)
//  - 자동 로드: 체크박스 대신 켜고 끄는 스위치

import (
	"math"
	"strings"
	"unsafe"
)

// ───────────── 부드러운 가장자리로 그리는 작은 캔버스 ─────────────
type canvas struct {
	w, h int
	pix  []float64 // r,g,b
}

func rgbOf(v uintptr) (float64, float64, float64) {
	return float64(v & 0xFF), float64(v >> 8 & 0xFF), float64(v >> 16 & 0xFF)
}

func newCanvas(w, h int, bg uintptr) *canvas {
	w, h = max(w, 1), max(h, 1)
	cv := &canvas{w: w, h: h, pix: make([]float64, w*h*3)}
	r, g, b := rgbOf(bg)
	for i := 0; i < w*h; i++ {
		cv.pix[i*3], cv.pix[i*3+1], cv.pix[i*3+2] = r, g, b
	}
	return cv
}

// cover(x,y) 0~1 만큼 color 를 덮어 칠한다 (x,y 는 픽셀 가운데)
func (cv *canvas) paint(cover func(x, y float64) float64, color func(x, y float64) (float64, float64, float64)) {
	for y := 0; y < cv.h; y++ {
		for x := 0; x < cv.w; x++ {
			px, py := float64(x)+0.5, float64(y)+0.5
			a := cover(px, py)
			if a <= 0 {
				continue
			}
			if a > 1 {
				a = 1
			}
			r, g, b := color(px, py)
			i := (y*cv.w + x) * 3
			cv.pix[i] += (r - cv.pix[i]) * a
			cv.pix[i+1] += (g - cv.pix[i+1]) * a
			cv.pix[i+2] += (b - cv.pix[i+2]) * a
		}
	}
}

func (cv *canvas) blit(hdc uintptr, x, y int) {
	bi := bitmapInfoHeader{biWidth: int32(cv.w), biHeight: -int32(cv.h), biPlanes: 1, biBitCount: 32}
	bi.biSize = uint32(unsafe.Sizeof(bi))
	var bits uintptr
	hbm := c(pCreateDIBSection, hdc, uintptr(P(&bi)), 0, uintptr(P(&bits)), 0, 0)
	if hbm == 0 || bits == 0 {
		return
	}
	dst := unsafe.Slice((*byte)(unsafe.Pointer(bits)), cv.w*cv.h*4)
	for i := 0; i < cv.w*cv.h; i++ {
		dst[i*4] = clampByte(cv.pix[i*3+2])
		dst[i*4+1] = clampByte(cv.pix[i*3+1])
		dst[i*4+2] = clampByte(cv.pix[i*3])
		dst[i*4+3] = 0xFF
	}
	mem := c(pCreateCompatibleDC, hdc)
	old := c(pSelectObject, mem, hbm)
	c(pBitBlt, hdc, uintptr(x), uintptr(y), uintptr(cv.w), uintptr(cv.h), mem, 0, 0, SRCCOPY)
	c(pSelectObject, mem, old)
	c(pDeleteDC, mem)
	c(pDeleteObject, hbm)
}

func clampByte(v float64) byte {
	if v <= 0 {
		return 0
	}
	if v >= 255 {
		return 255
	}
	return byte(v + 0.5)
}

func solid(v uintptr) func(x, y float64) (float64, float64, float64) {
	r, g, b := rgbOf(v)
	return func(_, _ float64) (float64, float64, float64) { return r, g, b }
}

// 위(y0)→아래(y1) 그라데이션
func vgrad(top, bot uintptr, y0, y1 float64) func(x, y float64) (float64, float64, float64) {
	r0, g0, b0 := rgbOf(top)
	r1, g1, b1 := rgbOf(bot)
	return func(_, y float64) (float64, float64, float64) {
		t := math.Max(0, math.Min(1, (y-y0)/math.Max(y1-y0, 1)))
		return r0 + (r1-r0)*t, g0 + (g1-g0)*t, b0 + (b1-b0)*t
	}
}

// 왼쪽 위 → 오른쪽 아래 그라데이션
func dgrad(a, b uintptr, size float64) func(x, y float64) (float64, float64, float64) {
	r0, g0, b0 := rgbOf(a)
	r1, g1, b1 := rgbOf(b)
	return func(x, y float64) (float64, float64, float64) {
		t := math.Max(0, math.Min(1, (x+y)/math.Max(2*size, 1)))
		return r0 + (r1-r0)*t, g0 + (g1-g0)*t, b0 + (b1-b0)*t
	}
}

// 둥근 사각형까지의 거리 (안쪽은 음수)
func sdRoundRect(px, py, x0, y0, x1, y1, r float64) float64 {
	cx, cy := (x0+x1)/2, (y0+y1)/2
	hw, hh := (x1-x0)/2, (y1-y0)/2
	r = math.Min(r, math.Min(hw, hh))
	qx := math.Abs(px-cx) - (hw - r)
	qy := math.Abs(py-cy) - (hh - r)
	out := math.Hypot(math.Max(qx, 0), math.Max(qy, 0))
	return out + math.Min(math.Max(qx, qy), 0) - r
}

func aa(d float64) float64 { return math.Max(0, math.Min(1, 0.5-d)) }

func smoothstep(e0, e1, x float64) float64 {
	t := math.Max(0, math.Min(1, (x-e0)/(e1-e0)))
	return t * t * (3 - 2*t)
}

// 삼각형 (4×4 표본으로 가장자리를 부드럽게)
func triCover(ax, ay, bx, by, cx, cy float64) func(x, y float64) float64 {
	edge := func(x0, y0, x1, y1, x, y float64) float64 { return (x1-x0)*(y-y0) - (y1-y0)*(x-x0) }
	return func(px, py float64) float64 {
		n := 0
		for i := 0; i < 4; i++ {
			for j := 0; j < 4; j++ {
				x, y := px-0.5+(float64(i)+0.5)/4, py-0.5+(float64(j)+0.5)/4
				e1, e2, e3 := edge(ax, ay, bx, by, x, y), edge(bx, by, cx, cy, x, y), edge(cx, cy, ax, ay, x, y)
				if (e1 >= 0 && e2 >= 0 && e3 >= 0) || (e1 <= 0 && e2 <= 0 && e3 <= 0) {
					n++
				}
			}
		}
		return float64(n) / 16
	}
}

func mixClr(a, b uintptr, t float64) uintptr {
	r0, g0, b0 := rgbOf(a)
	r1, g1, b1 := rgbOf(b)
	return RGB(clampByte(r0+(r1-r0)*t), clampByte(g0+(g1-g0)*t), clampByte(b0+(b1-b0)*t))
}

var white = RGB(0xFF, 0xFF, 0xFF)

// 글자 크기 (장치 픽셀)
func textSize(hdc, font uintptr, str string) (int, int) {
	old := c(pSelectObject, hdc, font)
	t := ws(str)
	n := len([]rune(str))
	var sz [2]int32
	if n > 0 {
		c(pGetTextExtentPoint32W, hdc, uintptr(P(t)), uintptr(len(utf16Of(str))), uintptr(P(&sz)))
	}
	c(pSelectObject, hdc, old)
	return int(sz[0]), int(sz[1])
}

func utf16Of(str string) []uint16 {
	out := []uint16{}
	for _, r := range str {
		if r >= 0x10000 {
			r -= 0x10000
			out = append(out, uint16(0xD800+(r>>10)), uint16(0xDC00+(r&0x3FF)))
		} else {
			out = append(out, uint16(r))
		}
	}
	return out
}

func drawTextAt(hdc, font, clr uintptr, x, y int, str string) {
	old := c(pSelectObject, hdc, font)
	c(pSetBkMode, hdc, TRANSPARENT)
	c(pSetTextColor, hdc, clr)
	rc := rectT{int32(x), int32(y), int32(x + 4000), int32(y + 400)}
	c(pDrawTextW, hdc, uintptr(P(ws(str))), ^uintptr(0), uintptr(P(&rc)), DT_SINGLELINE|DT_NOPREFIX)
	c(pSelectObject, hdc, old)
}

// ───────────── 실행 버튼 ─────────────
var hFontRunSub uintptr // 실행 버튼 아래 작은 'Enter'

// 실행 버튼 색 (위·아래 그라데이션). 크림 화면은 테라코타
func runColors(hot, pressed bool) (uintptr, uintptr) {
	top, bot := rgbHex(0x4F8CFF), rgbHex(0x2F63E0)
	if curTheme.key == "cream" {
		top, bot = rgbHex(0xE3906F), rgbHex(0xC0664A)
	}
	switch {
	case pressed:
		top, bot = mixClr(top, 0, 0.15), mixClr(bot, 0, 0.15)
	case hot:
		top, bot = mixClr(top, white, 0.12), mixClr(bot, white, 0.10)
	}
	return top, bot
}

// 버튼 칸 안의 실제 버튼 여백 (그림자 자리)
const runPadX, runPadTop, runPadBot = 6, 3, 10

func drawRunButton(dis *drawItemStruct) {
	hdc := dis.hDC
	r := dis.rcItem
	W, H := int(r.right-r.left), int(r.bottom-r.top)
	disabled := dis.itemState&ODS_DISABLED != 0
	pressed := dis.itemState&ODS_SELECTED != 0
	hot := hotBtn == dis.hwndItem

	cv := newCanvas(W, H, clrBg)
	x0, y0 := float64(si(runPadX)), float64(si(runPadTop))
	x1, y1 := float64(W-si(runPadX)), float64(H-si(runPadBot))
	if pressed {
		y0, y1 = y0+1, y1+1
	}
	rad := float64(si(14))
	top, bot := runColors(hot, pressed)
	txt := white
	if disabled {
		top, bot, txt = clrDisBg, clrDisBg, clrSubText
	}
	body := func(x, y float64) float64 { return aa(sdRoundRect(x, y, x0, y0, x1, y1, rad)) }
	if !disabled && !pressed { // 아래로 번지는 그림자
		blur, off := float64(si(7)), float64(si(4))
		sh := mixClr(bot, clrBg, 0.25)
		cv.paint(func(x, y float64) float64 {
			d := sdRoundRect(x, y-off, x0+float64(si(6)), y0, x1-float64(si(6)), y1, rad)
			return 0.55 * (1 - smoothstep(-blur, blur, d))
		}, solid(sh))
	}
	cv.paint(body, vgrad(top, bot, y0, y1))
	if !disabled { // 위쪽 가는 빛 / 아래쪽 가는 그늘
		cv.paint(func(x, y float64) float64 {
			return 0.35 * body(x, y) * (1 - aa(sdRoundRect(x, y, x0, y0+1.4, x1, y1+1.4, rad)))
		}, solid(white))
		cv.paint(func(x, y float64) float64 {
			return 0.25 * body(x, y) * (1 - aa(sdRoundRect(x, y, x0, y0-1.6, x1, y1-1.6, rad)))
		}, solid(0))
	}
	if hFontRunSub == 0 {
		hFontRunSub = makeFont(7, false)
	}
	// 재생 원 + 글자 묶음을 버튼 가운데에
	label := strings.TrimSpace(strings.TrimLeft(getText(dis.hwndItem), "▶"))
	sub := T("app.104")
	lw, lh := textSize(hdc, hFontRun, label)
	sw, sh := textSize(hdc, hFontRunSub, sub)
	tw := max(lw, sw) // '실행' / 'Enter' 를 버튼 가운데에
	cx0 := (x0+x1)/2 - float64(tw)/2
	cy := (y0 + y1) / 2
	cv.blit(hdc, int(r.left), int(r.top))

	tx := int(r.left) + int(cx0)
	th := lh + sh - si(2)
	ty := int(r.top) + int(cy) - th/2
	drawTextAt(hdc, hFontRun, txt, tx+(tw-lw)/2, ty, label)
	subClr := mixClr(txt, bot, 0.35)
	drawTextAt(hdc, hFontRunSub, subClr, tx+(tw-sw)/2, ty+lh-si(2), sub)
}

// ───────────── 오른쪽 머리: 기능 아이콘 ─────────────
var (
	heroGlyph  = ""
	hFontHero  uintptr
	heroIconSz = 56
)

// 기능 이름으로 아이콘 기호 고르기 (Segoe MDL2 Assets, Windows 10/11 기본 글꼴)
func pickGlyph(n nodeRef) string {
	switch n.kind {
	case nkFavGroup:
		return "" // 별
	case nkGroup, nkCat:
		return "" // 폴더
	case nkItem:
	default:
		return ""
	}
	it := n.item()
	if it == nil {
		return ""
	}
	name := it.Name + " " + it.Desc
	has := func(ws ...string) bool {
		for _, w := range ws {
			if strings.Contains(name, w) {
				return true
			}
		}
		return false
	}
	switch {
	case has("PDF", "출력", "인쇄"):
		return "" // 프린터
	case has("엑셀", "자재", "수량", "내역"):
		return "" // 계산기
	case has("검토", "검수", "점검"):
		return "" // 체크
	case has("복사"):
		return "" // 복사
	case has("끊기", "자르", "교차"):
		return "" // 가위
	case has("위치", "이동", "보정"):
		return "" // 이동
	case has("수정", "편집", "작성", "허가", "반영"):
		return "" // 연필
	}
	return "" // 문서
}

func heroColors() (uintptr, uintptr) {
	if curTheme.key == "cream" {
		return rgbHex(0xE3906F), rgbHex(0xB85A3E)
	}
	return rgbHex(0x3B7CFF), rgbHex(0x7B5CFF)
}

func paintHeroIcon(hdc uintptr) {
	if hFontHero == 0 {
		hFontHero = makeIconFont(18)
	}
	sz := si(heroIconSz)
	x, y := si(rightX), si(secTop)
	cv := newCanvas(sz, sz, clrBg)
	a, b := heroColors()
	f := float64(sz)
	cv.paint(func(px, py float64) float64 { return aa(sdRoundRect(px, py, 0.5, 0.5, f-0.5, f-0.5, float64(si(14)))) }, dgrad(a, b, f))
	cv.blit(hdc, x, y)
	old := c(pSelectObject, hdc, hFontHero)
	c(pSetBkMode, hdc, TRANSPARENT)
	c(pSetTextColor, hdc, white)
	rc := rectT{int32(x), int32(y), int32(x + sz), int32(y + sz)}
	c(pDrawTextW, hdc, uintptr(P(ws(heroGlyph))), ^uintptr(0), uintptr(P(&rc)), DT_CENTER|DT_VCENTER|DT_SINGLELINE)
	c(pSelectObject, hdc, old)
}

// ───────────── 자동 로드 스위치 ─────────────
var startupOn bool

func drawSwitch(dis *drawItemStruct) {
	hdc := dis.hDC
	r := dis.rcItem
	c(pFillRect, hdc, uintptr(P(&r)), hBgBrush)
	H := int(r.bottom - r.top)
	tw, th := si(36), si(20)
	cv := newCanvas(tw+2, th+2, clrBg)
	on := startupOn
	track := clrBtnBorder
	if on {
		_, track = runColors(false, false)
	}
	if dis.itemState&ODS_DISABLED != 0 {
		track = clrDisBg
	}
	ftw, fth := float64(tw), float64(th)
	cv.paint(func(x, y float64) float64 { return aa(sdRoundRect(x, y, 1, 1, ftw+1, fth+1, fth/2)) }, solid(track))
	kr := fth/2 - float64(si(3))
	kx := 1 + fth/2
	if on {
		kx = 1 + ftw - fth/2
	}
	cv.paint(func(x, y float64) float64 { return aa(math.Hypot(x-kx, y-(1+fth/2)) - kr) }, solid(white))
	cv.blit(hdc, int(r.left), int(r.top)+(H-th-2)/2)
	clr := clrSubText
	if hotBtn == dis.hwndItem {
		clr = clrText
	}
	_, lh := textSize(hdc, hFont, getText(dis.hwndItem))
	drawTextAt(hdc, hFont, clr, int(r.left)+tw+si(10), int(r.top)+(H-lh)/2, getText(dis.hwndItem))
}

// ───────────── 작업할 도면 선택칸 ─────────────
type measureItemStruct struct {
	ctlType, ctlID, itemID, itemWidth, itemHeight uint32
	itemData                                      uintptr
}

const ODS_COMBOBOXEDIT = 0x1000

// "Autodesk AutoCAD LT 2026 - [도면.dwg]" → "도면.dwg", "AutoCAD LT 2026"
func splitCadTitle(t string) (string, string) {
	t = strings.TrimSpace(t)
	i, j := strings.LastIndex(t, "["), strings.LastIndex(t, "]")
	if i < 0 || j <= i {
		return t, ""
	}
	app := strings.TrimSpace(t[:i])
	app = strings.TrimSpace(strings.TrimSuffix(app, "-"))
	app = strings.TrimPrefix(app, "Autodesk ")
	return strings.TrimSpace(t[i+1 : j]), app
}

func drawCadItem(dis *drawItemStruct) {
	hdc, rc := dis.hDC, dis.rcItem
	field := dis.itemState&ODS_COMBOBOXEDIT != 0
	sel := !field && dis.itemState&ODS_SELECTED != 0
	bg := clrPanelBg
	if sel {
		bg = clrSelBg
	}
	br := c(pCreateSolidBrush, bg)
	c(pFillRect, hdc, uintptr(P(&rc)), br)
	c(pDeleteObject, br)

	id := int(int32(dis.itemID))
	name, app := "", ""
	alive := false
	if id >= 0 && id < len(windows) {
		name, app = splitCadTitle(windows[id].title)
		alive = c(pIsWindow, windows[id].h) != 0
	}
	x := int(rc.left) + si(8)
	H := int(rc.bottom - rc.top)
	if field {
		dot := RGB(0x3E, 0xCF, 0x8E)
		if !alive {
			dot = RGB(0xE8, 0x5A, 0x52)
		}
		fillRoundEllipse(hdc, x, int(rc.top)+(H-si(9))/2, si(9), dot)
		x += si(19)
		if id < 0 { // CAD 창이 없으면 안내 문구를 빨갛게
			name = T("app.103")
		}
	}
	right, rclr := app, clrSubText
	if field && id >= 0 { // 선택칸: 연결 상태에 따라 초록(연결됨) / 빨강(연결 끊김)
		state := T("app.106")
		rclr = RGB(0xE8, 0x5A, 0x52)
		if alive {
			state, rclr = T("app.105"), RGB(0x3E, 0xCF, 0x8E)
		}
		if right == "" {
			right = state
		} else {
			right += " · " + state
		}
	}
	rx := int(rc.right) - si(10)
	if right != "" {
		w, h := textSize(hdc, hFont, right)
		rx -= w
		drawTextAt(hdc, hFont, rclr, rx, int(rc.top)+(H-h)/2, right)
		rx -= si(14)
	}
	nameClr := clrText
	if field && id < 0 {
		nameClr = RGB(0xE8, 0x5A, 0x52)
	}
	if sel {
		nameClr = clrSelText
	}
	font := hFont
	if field {
		font = hFontBtnBold
	}
	old := c(pSelectObject, hdc, font)
	c(pSetBkMode, hdc, TRANSPARENT)
	c(pSetTextColor, hdc, nameClr)
	tr := rectT{int32(x), rc.top, int32(max(rx, x+si(20))), rc.bottom}
	c(pDrawTextW, hdc, uintptr(P(ws(name))), ^uintptr(0), uintptr(P(&tr)), DT_VCENTER|DT_SINGLELINE|DT_NOPREFIX|0x8000 /*DT_END_ELLIPSIS*/)
	c(pSelectObject, hdc, old)
}
