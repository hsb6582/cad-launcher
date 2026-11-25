package main

// 간단 설명서 칸
//   catalog.json 기능에 when(언제 쓰나) / steps(사용 순서) / warn(주의) / before·after(실행 전·후 그림)가
//   있으면 글상자(hManual) 대신 이 칸을 직접 그려서 보여 준다.
//   원래 설명서(manual + 리습 공통 안내)는 맨 아래 '자세한 설명 보기'를 눌러야 펼쳐진다.
//   그림은 Go 표준 라이브러리(image/png, image/jpeg)로 읽어 DIB 로 만들어 그린다 (파일을 잠그지 않음).

import (
	"image"
	"image/color"
	"image/draw"
	_ "image/jpeg"
	_ "image/png"
	"os"
	"syscall"
	"time"
	"unsafe"
)

var (
	pBeginPaint             = user32.NewProc("BeginPaint")
	pEndPaint               = user32.NewProc("EndPaint")
	pInvalidateRect         = user32.NewProc("InvalidateRect")
	pSetScrollInfo          = user32.NewProc("SetScrollInfo")
	pCreateCompatibleDC     = gdi32.NewProc("CreateCompatibleDC")
	pCreateCompatibleBitmap = gdi32.NewProc("CreateCompatibleBitmap")
	pCreateDIBSection       = gdi32.NewProc("CreateDIBSection")
	pDeleteDC               = gdi32.NewProc("DeleteDC")
	pBitBlt                 = gdi32.NewProc("BitBlt")
	pStretchBlt             = gdi32.NewProc("StretchBlt")
	pSetStretchBltMode      = gdi32.NewProc("SetStretchBltMode")
	pSetBrushOrgEx          = gdi32.NewProc("SetBrushOrgEx")
	pEllipse                = gdi32.NewProc("Ellipse")
)

const (
	WM_PAINT      = 0x000F
	WM_ERASEBKGND = 0x0014
	WM_VSCROLL    = 0x0115
	WM_MOUSEWHEEL = 0x020A
	SRCCOPY       = 0x00CC0020
	HALFTONE      = 4

	DT_WORDBREAK   = 0x0010
	DT_CALCRECT    = 0x0400
	DT_NOPREFIX    = 0x0800
	DT_EDITCONTROL = 0x2000
)

var (
	clrSoft = RGB(0xF3, 0xE6, 0xDF) // 주의 상자 바탕
	clrLine = RGB(0xE4, 0xDF, 0xD4) // 구분선·그림 테두리
)

type guideDoc struct {
	when, warn, detail string
	steps              []string
	pics               [2]string // 실행 전 / 실행 후 그림 (런처 폴더 기준 상대경로)
}

type paintStruct struct {
	hdc        uintptr
	fErase     int32
	rc         rectT
	fRestore   int32
	fIncUpdate int32
	reserved   [32]byte
}

type scrollInfo struct {
	cbSize, fMask   uint32
	nMin, nMax      int32
	nPage           uint32
	nPos, nTrackPos int32
}

type bitmapInfoHeader struct {
	biSize                       uint32
	biWidth, biHeight            int32
	biPlanes, biBitCount         uint16
	biCompression, biSizeImage   uint32
	biXPelsPerMeter, biYPelsPerM int32
	biClrUsed, biClrImportant    uint32
}

var (
	hGuide     uintptr
	hFontMid   uintptr // 한 줄 설명(굵게)
	hFontNum   uintptr // 단계 번호
	gdoc       *guideDoc
	gOpen      bool  // 자세한 설명 펼침
	gScroll    int   // 위에서부터 숨겨진 높이 (픽셀)
	gTotal     int   // 내용 전체 높이 (픽셀)
	gToggle    rectT // '자세한 설명' 줄 (내용 좌표)
	gPicRects  [2]rectT
	guideClass = ws("CADGuidePane")
	picCache   = map[string]*picEntry{}
)

type picEntry struct {
	hbm  uintptr
	w, h int
	mod  time.Time
	size int64
}

func registerGuideClass() {
	wc := wndClassEx{
		lpfnWndProc:   syscall.NewCallback(guideProc),
		hInstance:     hInst,
		hCursor:       c(pLoadCursorW, 0, 32512),
		hbrBackground: hPanelBrush,
		lpszClassName: guideClass,
	}
	wc.cbSize = uint32(unsafe.Sizeof(wc))
	c(pRegisterClassExW, uintptr(P(&wc)))
}

func createGuide() {
	hFontMid = makeFont(10, true)
	hFontNum = makeFont(9, true)
	registerGuideClass()
	hGuide = c(pCreateWindowExW, 0, uintptr(P(guideClass)), 0,
		WS_CHILD|WS_VSCROLL, 0, 0, 10, 10, hMain, 0, hInst, 0)
	styleControl(hGuide)
	framed[hGuide] = true // 3D 테두리 대신 부모가 얇은 둥근 테두리를 그림 (style2.go)
}

// doc 이 nil 이면 원래 글상자(hManual)를 보여 준다
func setGuide(doc *guideDoc) {
	gdoc, gOpen, gScroll = doc, false, 0
	show(hGuide, doc != nil)
	show(hManual, doc == nil)
	if doc != nil {
		guideRelayout()
	}
}

func si(v int) int { return int(s(v)) }

func guideClient() (int, int) {
	var r rectT
	c(pGetClientRect, hGuide, uintptr(P(&r)))
	return int(r.right), int(r.bottom)
}

// 내용 높이를 다시 재고 스크롤 막대를 맞춘다 (창 크기·내용·펼침이 바뀔 때)
func guideRelayout() {
	if hGuide == 0 || gdoc == nil {
		return
	}
	W, H := guideClient()
	dc := c(pGetDC, hGuide)
	gTotal = guideRender(dc, W, false)
	c(pReleaseDC, hGuide, dc)
	if mx := max(gTotal-H, 0); gScroll > mx {
		gScroll = mx
	}
	if gScroll < 0 {
		gScroll = 0
	}
	sc := scrollInfo{fMask: 0x1 | 0x2 | 0x4 | 0x8, nMax: int32(max(gTotal-1, 0)), nPage: uint32(H), nPos: int32(gScroll)} // RANGE|PAGE|POS|DISABLENOSCROLL
	sc.cbSize = uint32(unsafe.Sizeof(sc))
	c(pSetScrollInfo, hGuide, 1 /*SB_VERT*/, uintptr(P(&sc)), 1)
	c(pInvalidateRect, hGuide, 0, 0)
}

func guideScrollTo(y int) {
	gScroll = y
	guideRelayout()
}

// 글자를 너비 w 안에서 줄바꿈해 그리고(draw) 높이를 돌려준다
func gText(hdc, font, clr uintptr, x, y, w int, text string, draw bool) int {
	old := c(pSelectObject, hdc, font)
	rc := rectT{int32(x), int32(y), int32(x + w), int32(y)}
	flags := uintptr(DT_WORDBREAK | DT_NOPREFIX | DT_EDITCONTROL)
	c(pDrawTextW, hdc, uintptr(P(ws(text))), ^uintptr(0), uintptr(P(&rc)), flags|DT_CALCRECT)
	if draw {
		c(pSetTextColor, hdc, clr)
		rc.right = int32(x + w)
		c(pDrawTextW, hdc, uintptr(P(ws(text))), ^uintptr(0), uintptr(P(&rc)), flags)
	}
	c(pSelectObject, hdc, old)
	return int(rc.bottom - rc.top)
}

func fillRound(hdc uintptr, x, y, w, h int, fill, border uintptr, r int) {
	br := c(pCreateSolidBrush, fill)
	pen := c(pCreatePen, PS_SOLID, 1, border)
	ob, op := c(pSelectObject, hdc, br), c(pSelectObject, hdc, pen)
	c(pRoundRect, hdc, uintptr(x), uintptr(y), uintptr(x+w), uintptr(y+h), uintptr(r), uintptr(r))
	c(pSelectObject, hdc, ob)
	c(pSelectObject, hdc, op)
	c(pDeleteObject, br)
	c(pDeleteObject, pen)
}

func fillBox(hdc uintptr, x, y, w, h int, clr uintptr) {
	br := c(pCreateSolidBrush, clr)
	rc := rectT{int32(x), int32(y), int32(x + w), int32(y + h)}
	c(pFillRect, hdc, uintptr(P(&rc)), br)
	c(pDeleteObject, br)
}

// 그림 파일을 읽어 흰 바탕에 합성한 32비트 DIB 로 보관 (파일이 바뀌면 다시 읽음)
func loadPic(rel string) *picEntry {
	if rel == "" {
		return nil
	}
	path := absPath(rel)
	fi, err := os.Stat(path)
	if err != nil {
		return nil
	}
	if p := picCache[path]; p != nil && p.mod.Equal(fi.ModTime()) && p.size == fi.Size() {
		return p
	}
	if p := picCache[path]; p != nil {
		c(pDeleteObject, p.hbm)
		delete(picCache, path)
	}
	f, err := os.Open(path)
	if err != nil {
		return nil
	}
	img, _, err := image.Decode(f)
	f.Close()
	if err != nil {
		logf("그림을 읽지 못함 %s: %v", rel, err)
		return nil
	}
	b := img.Bounds()
	w, h := b.Dx(), b.Dy()
	if w == 0 || h == 0 {
		return nil
	}
	rgba := image.NewRGBA(image.Rect(0, 0, w, h))
	draw.Draw(rgba, rgba.Rect, &image.Uniform{color.White}, image.Point{}, draw.Src)
	draw.Draw(rgba, rgba.Rect, img, b.Min, draw.Over)
	bi := bitmapInfoHeader{biWidth: int32(w), biHeight: -int32(h), biPlanes: 1, biBitCount: 32}
	bi.biSize = uint32(unsafe.Sizeof(bi))
	var bits uintptr
	hbm := c(pCreateDIBSection, 0, uintptr(P(&bi)), 0, uintptr(P(&bits)), 0, 0)
	if hbm == 0 || bits == 0 {
		return nil
	}
	dst := unsafe.Slice((*byte)(unsafe.Pointer(bits)), w*h*4)
	for i := 0; i < w*h; i++ {
		dst[i*4], dst[i*4+1], dst[i*4+2], dst[i*4+3] = rgba.Pix[i*4+2], rgba.Pix[i*4+1], rgba.Pix[i*4], 0xFF
	}
	p := &picEntry{hbm: hbm, w: w, h: h, mod: fi.ModTime(), size: fi.Size()}
	picCache[path] = p
	return p
}

func drawPic(hdc uintptr, p *picEntry, x, y, w, h int) {
	src := c(pCreateCompatibleDC, hdc)
	old := c(pSelectObject, src, p.hbm)
	c(pSetStretchBltMode, hdc, HALFTONE)
	c(pSetBrushOrgEx, hdc, 0, 0, 0)
	c(pStretchBlt, hdc, uintptr(x), uintptr(y), uintptr(w), uintptr(h), src, 0, 0, uintptr(p.w), uintptr(p.h), SRCCOPY)
	c(pSelectObject, src, old)
	c(pDeleteDC, src)
}

// 내용 전체를 그리거나(draw) 높이만 잰다. 좌표는 장치 픽셀, 스크롤(gScroll)만큼 위로 밀어서 그림.
func guideRender(hdc uintptr, W int, draw bool) int {
	d := gdoc
	if d == nil {
		return 0
	}
	c(pSetBkMode, hdc, TRANSPARENT)
	pad := si(12)
	x, w := pad, max(W-2*pad, si(60))
	top := -gScroll
	if !draw {
		top = 0
	}
	y := top + pad

	// 1) 언제 쓰나
	if d.when != "" {
		y += gText(hdc, hFontMid, clrText, x, y, w, d.when, draw) + si(10)
	}

	// 2) 사용 순서
	for i, stp := range d.steps {
		tx := x + si(40)
		th := gText(hdc, hFont, clrText, tx, 0, w-si(50), stp, false)
		rh := max(th+si(14), si(34))
		if draw {
			fillRound(hdc, x, y, w, rh, guideStepBg(), guideStepBg(), si(8))
			cy := y + rh/2
			fillRoundEllipse(hdc, x+si(9), cy-si(11), si(22), clrAccent)
			old := c(pSelectObject, hdc, hFontNum)
			c(pSetTextColor, hdc, clrAccentTxt)
			rc := rectT{int32(x + si(9)), int32(cy - si(11)), int32(x + si(31)), int32(cy + si(11))}
			c(pDrawTextW, hdc, uintptr(P(ws(itoa(i+1)))), ^uintptr(0), uintptr(P(&rc)), DT_CENTER|DT_VCENTER|DT_SINGLELINE)
			c(pSelectObject, hdc, old)
			gText(hdc, hFont, clrText, tx, y+(rh-th)/2, w-si(50), stp, true)
		}
		y += rh + si(6)
	}
	if len(d.steps) > 0 {
		y += si(6)
	}

	// 3) 실행 전 / 후 그림
	var pics [2]*picEntry
	n := 0
	for i, p := range d.pics {
		if pics[i] = loadPic(p); pics[i] != nil {
			n++
		}
	}
	gPicRects = [2]rectT{}
	if n > 0 {
		caps := [2]string{"실행 전", "실행 후"}
		gap := si(30)
		side := n == 2 && w >= si(440)
		colW := w
		if side {
			colW = (w - gap) / 2
		}
		capH := si(24)
		maxH := si(260)
		// 두 그림을 같은 높이로 맞춤
		imgH := 0
		for _, p := range pics {
			if p != nil {
				imgH = max(imgH, min(p.h*(colW-2)/p.w, maxH))
			}
		}
		fx, fy := x, y
		for i, p := range pics {
			if p == nil {
				continue
			}
			fh := capH + imgH + 2
			if draw {
				fillRound(hdc, fx, fy, colW, fh, clrPanelBg, clrLine, si(6))
				fillBox(hdc, fx+1, fy+1, colW-2, capH-1, clrBg)
				fillBox(hdc, fx+1, fy+capH, colW-2, 1, clrLine)
				gText(hdc, hFontNum, clrText, fx+si(10), fy+si(4), colW-si(20), caps[i], true)
				dw := min(colW-2, p.w*imgH/p.h)
				dh := p.h * dw / p.w
				drawPic(hdc, p, fx+1+(colW-2-dw)/2, fy+capH+1+(imgH-dh)/2, dw, dh)
			}
			gPicRects[i] = rectT{int32(fx), int32(fy - top), int32(fx + colW), int32(fy - top + fh)}
			if side {
				if i == 0 {
					if draw {
						old := c(pSelectObject, hdc, hFontBold)
						c(pSetTextColor, hdc, clrAccent)
						rc := rectT{int32(fx + colW), int32(fy), int32(fx + colW + gap), int32(fy + fh)}
						c(pDrawTextW, hdc, uintptr(P(ws("→"))), ^uintptr(0), uintptr(P(&rc)), DT_CENTER|DT_VCENTER|DT_SINGLELINE)
						c(pSelectObject, hdc, old)
					}
					fx += colW + gap
				} else {
					fy += fh + si(12)
				}
			} else {
				fy += fh + si(10)
			}
		}
		y = fy + si(2)
	}

	// 4) 주의
	if d.warn != "" {
		t := "※ " + d.warn
		th := gText(hdc, hFont, clrText, x+si(12), 0, w-si(24), t, false)
		bh := th + si(16)
		if draw {
			fillRound(hdc, x, y, w, bh, clrSoft, clrSoft, si(8))
			gText(hdc, hFont, clrText, x+si(12), y+si(8), w-si(24), t, true)
		}
		y += bh + si(12)
	}

	// 5) 자세한 설명 (접기/펼치기)
	if d.detail != "" {
		if draw {
			fillBox(hdc, x, y, w, 1, clrLine)
		}
		y += si(8)
		label := "▶ 자세한 설명 보기"
		if gOpen {
			label = "▼ 자세한 설명 접기"
		}
		th := gText(hdc, hFontNum, guideLinkColor(), x, y, w, label, draw)
		gToggle = rectT{int32(x), int32(y - top - si(4)), int32(x + w), int32(y - top + th + si(4))}
		y += th + si(8)
		if gOpen {
			y += gText(hdc, hFont, guideDetailColor(), x, y, w, d.detail, draw) + si(4)
		}
	} else {
		gToggle = rectT{}
	}
	return y + pad - top
}

// 차콜(어두운) 화면에서는 설명서 글자·상자를 더 밝게 (크림은 그대로)
func guideLinkColor() uintptr { // '▶ 자세한 설명 보기'
	if curTheme.dark {
		return clrHoverTxt // 연한 하늘색
	}
	return clrAccentDk
}

func guideDetailColor() uintptr { // 펼친 자세한 설명 글자
	if curTheme.dark {
		return clrText
	}
	return clrSubText
}

func guideStepBg() uintptr { // 사용 순서 한 줄 바탕
	if curTheme.dark {
		return RGB(0x34, 0x38, 0x40)
	}
	return clrBg
}

func fillRoundEllipse(hdc uintptr, x, y, d int, clr uintptr) {
	br := c(pCreateSolidBrush, clr)
	pen := c(pCreatePen, PS_SOLID, 1, clr)
	ob, op := c(pSelectObject, hdc, br), c(pSelectObject, hdc, pen)
	c(pEllipse, hdc, uintptr(x), uintptr(y), uintptr(x+d), uintptr(y+d))
	c(pSelectObject, hdc, ob)
	c(pSelectObject, hdc, op)
	c(pDeleteObject, br)
	c(pDeleteObject, pen)
}

func inRect(r rectT, x, y int) bool {
	return r.right > r.left && x >= int(r.left) && x < int(r.right) && y >= int(r.top) && y < int(r.bottom)
}

func guideProc(h, msg, wp, lp uintptr) uintptr {
	switch msg {
	case WM_ERASEBKGND:
		return 1
	case WM_PAINT:
		var ps paintStruct
		hdc := c(pBeginPaint, h, uintptr(P(&ps)))
		W, H := guideClient()
		mem := c(pCreateCompatibleDC, hdc)
		bmp := c(pCreateCompatibleBitmap, hdc, uintptr(max(W, 1)), uintptr(max(H, 1)))
		old := c(pSelectObject, mem, bmp)
		fillBox(mem, 0, 0, W, H, clrPanelBg)
		guideRender(mem, W, true)
		c(pBitBlt, hdc, 0, 0, uintptr(W), uintptr(H), mem, 0, 0, SRCCOPY)
		c(pSelectObject, mem, old)
		c(pDeleteObject, bmp)
		c(pDeleteDC, mem)
		c(pEndPaint, h, uintptr(P(&ps)))
		return 0
	case WM_SIZE:
		guideRelayout()
		return 0
	case WM_VSCROLL:
		_, H := guideClient()
		line := si(30)
		switch wp & 0xFFFF {
		case 0: // SB_LINEUP
			guideScrollTo(gScroll - line)
		case 1: // SB_LINEDOWN
			guideScrollTo(gScroll + line)
		case 2: // SB_PAGEUP
			guideScrollTo(gScroll - H)
		case 3: // SB_PAGEDOWN
			guideScrollTo(gScroll + H)
		case 4, 5: // SB_THUMBPOSITION, SB_THUMBTRACK
			guideScrollTo(int(uint16(wp >> 16)))
		case 6:
			guideScrollTo(0)
		case 7:
			guideScrollTo(gTotal)
		}
		return 0
	case WM_MOUSEWHEEL:
		delta := int(int16(wp >> 16))
		guideScrollTo(gScroll - delta*si(40)/120)
		return 0
	case 0x0201: // WM_LBUTTONDOWN
		x, y := int(int16(lp&0xFFFF)), int(int16((lp>>16)&0xFFFF))+gScroll
		c(pSetFocus, h) // 마우스 휠이 이 칸으로 오도록
		if inRect(gToggle, x, y) {
			gOpen = !gOpen
			guideRelayout()
			return 0
		}
		for i, r := range gPicRects {
			if inRect(r, x, y) && gdoc != nil { // 그림을 누르면 크게 보기 (기본 사진 보기 프로그램)
				c(pShellExecuteW, 0, uintptr(P(ws("open"))), uintptr(P(ws(absPath(gdoc.pics[i])))), 0, 0, SW_SHOWNORMAL)
			}
		}
		return 0
	case 0x0020: // WM_SETCURSOR
		if lp&0xFFFF == 1 { // HTCLIENT
			var pt [2]int32
			c(pGetCursorPos, uintptr(P(&pt)))
			c(pScreenToClient, h, uintptr(P(&pt)))
			x, y := int(pt[0]), int(pt[1])+gScroll
			if inRect(gToggle, x, y) || inRect(gPicRects[0], x, y) || inRect(gPicRects[1], x, y) {
				c(pSetCursor, c(pLoadCursorW, 0, 32649)) // IDC_HAND
				return 1
			}
		}
	}
	return c(pDefWindowProcW, h, msg, wp, lp)
}
