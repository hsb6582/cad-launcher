package main

// 화면 색상: 차콜 다크 / 크림 / 슬레이트(#454F61, 기본·켤 때 고정). 설정 버튼 옆 전구 버튼으로 차례로 바꾼다.
//  - 누르면 바로 바뀌고, launcher_state.json 의 "theme" 에 저장된다.
//  - 다크에서는 체크박스·옵션 묶음 테두리를 Windows 기본(밝은) 테마 대신 직접 색으로 그리게 하고,
//    입력칸·목록·스크롤바는 Windows 의 어두운 테마(DarkMode_Explorer / DarkMode_CFD)를 입힌다.

import "syscall"

var (
	pEnumChildWindows  = user32.NewProc("EnumChildWindows")
	pGetClassNameW     = user32.NewProc("GetClassNameW")
	pGetWindowLongPtrW = user32.NewProc("GetWindowLongPtrW")
	pRedrawWindow      = user32.NewProc("RedrawWindow")
)

const (
	WM_CTLCOLOREDIT    = 0x0133
	WM_CTLCOLORLISTBOX = 0x0134

	DWMWA_USE_IMMERSIVE_DARK_MODE = 20
	DWMWA_TEXT_COLOR              = 36
)

type theme struct {
	key, name                                      string
	dark                                           bool
	bg, text, sub, panel                           uintptr
	accent, accentDk, disBg, disBorder             uintptr
	accentHot, accentPress                         uintptr // 강조 버튼에 마우스를 올렸을 때 / 눌렀을 때
	border, winBorder, hover, hoverTxt, press, sel uintptr
	selText, hot, soft, line                       uintptr
	warnBar, warnTxt                               uintptr // 설명서 주의 상자: 왼쪽 띠 / 글자 (바탕은 soft)
	btn, btnBorder, btnHover                       uintptr // 일반 버튼(실행 외) 바탕 / 테두리 / 마우스를 올렸을 때 바탕
}

func rgbHex(v uint32) uintptr { return RGB(byte(v>>16), byte(v>>8), byte(v)) }

var themes = []theme{
	{key: "dark", name: T("theme.001"), dark: true, // 강조색: 파랑 #3A6EA5 (크림은 테라코타)
		bg: rgbHex(0x2B2E34), text: rgbHex(0xF7F5F1), sub: rgbHex(0xBCC2CA), panel: rgbHex(0x22252A),
		accent: rgbHex(0x3A6EA5), accentDk: rgbHex(0x2B5278), accentHot: rgbHex(0x4D84BE), accentPress: rgbHex(0x2B5278), disBg: rgbHex(0x3A3E45), disBorder: rgbHex(0x4A4F57),
		border: rgbHex(0x454A52), winBorder: rgbHex(0x3A3E45), hover: rgbHex(0x2C3440), hoverTxt: rgbHex(0xB9D3EE), press: rgbHex(0x2A3A4E), sel: rgbHex(0x2C3A4A),
		selText: rgbHex(0xB9D3EE), hot: rgbHex(0x33373E), soft: rgbHex(0x3A3326), line: rgbHex(0x3A3E45),
		warnBar: rgbHex(0xE3A23B), warnTxt: rgbHex(0xF2E3C4),
		btn: rgbHex(0x40454E), btnBorder: rgbHex(0x5C626C), btnHover: rgbHex(0x4A5363)},
	{key: "cream", name: T("theme.002"),
		bg: rgbHex(0xF7F4EC), text: rgbHex(0x2D2924), sub: rgbHex(0x8C857A), panel: rgbHex(0xFFFFFF),
		accent: rgbHex(0xCC785C), accentDk: rgbHex(0xAD5F46), accentHot: rgbHex(0x9A4630), accentPress: rgbHex(0x7A3523), disBg: rgbHex(0xE4E0D8), disBorder: rgbHex(0xC9C4BA),
		border: rgbHex(0xE0D9CC), winBorder: rgbHex(0xD9D2C4), hover: rgbHex(0xFBEFEA), hoverTxt: rgbHex(0xAD5F46), press: rgbHex(0xF4DFD6), sel: rgbHex(0xF6E4DC),
		selText: rgbHex(0x7A3E2A), hot: rgbHex(0xFAF6EF), soft: rgbHex(0xFFF4DC), line: rgbHex(0xE4DFD4),
		warnBar: rgbHex(0xE0A030), warnTxt: rgbHex(0x6B4A12),
		btn: rgbHex(0xFFFFFF), btnBorder: rgbHex(0xE0D9CC), btnHover: rgbHex(0xFBEFEA)},
	{key: "slate", name: T("theme.003"), dark: true, // 배경 #454F61 (사용자 지정), 강조색: 진한 파랑
		bg: rgbHex(0x454F61), text: rgbHex(0xF3F5F9), sub: rgbHex(0xC4CBD7), panel: rgbHex(0x3A4352),
		accent: rgbHex(0x2F6FB8), accentDk: rgbHex(0x255A96), accentHot: rgbHex(0x3E82CF), accentPress: rgbHex(0x255A96), disBg: rgbHex(0x4F596B), disBorder: rgbHex(0x5F6A7D),
		border: rgbHex(0x5C6779), winBorder: rgbHex(0x505A6C), hover: rgbHex(0x4C5A70), hoverTxt: rgbHex(0xCFE1F6), press: rgbHex(0x42536B), sel: rgbHex(0x55667F),
		selText: rgbHex(0xE1ECF9), hot: rgbHex(0x4B5568), soft: rgbHex(0x4A4638), line: rgbHex(0x505A6C),
		warnBar: rgbHex(0xE6B04A), warnTxt: rgbHex(0xF5E6C4),
		btn: rgbHex(0x5A657A), btnBorder: rgbHex(0x75819A), btnHover: rgbHex(0x63738D)},
}

// 런처를 켤 때 항상 쓰는 화면 색상 (저장된 값과 상관없이). 전구 버튼은 켜져 있는 동안만 바꾼다.
const startTheme = "slate"

var (
	curTheme    = themes[2]
	clrHoverTxt = curTheme.hoverTxt // 버튼에 마우스를 올렸을 때 글자
)

func themeIndex(key string) int {
	for i, t := range themes {
		if t.key == key {
			return i
		}
	}
	return 2 // 모르는 값이면 슬레이트(중간색)
}

// 색 값만 바꾼다 (창을 만들기 전 main()에서도 호출)
func setThemeColors(key string) {
	t := themes[themeIndex(key)]
	curTheme = t
	clrBg, clrText, clrSubText, clrPanelBg = t.bg, t.text, t.sub, t.panel
	clrAccent, clrAccentDk, clrDisBg, clrDisBorder = t.accent, t.accentDk, t.disBg, t.disBorder
	clrAccentHot, clrAccentPress = t.accentHot, t.accentPress
	clrBorder, clrWinBorder, clrHoverBg, clrHoverTxt, clrPressBg = t.border, t.winBorder, t.hover, t.hoverTxt, t.press
	clrSelBg, clrSelText, clrHotBg, clrSoft, clrLine = t.sel, t.selText, t.hot, t.soft, t.line
	clrWarnBar, clrWarnTxt = t.warnBar, t.warnTxt
	clrBtnBg, clrBtnBorder, clrBtnHover = t.btn, t.btnBorder, t.btnHover
}

// 설정 창에서 고르면: 색·브러시를 바꾸고 열려 있는 모든 창을 다시 그린다
func applyTheme(key string) {
	st.Theme = themes[themeIndex(key)].key
	setThemeColors(key)
	oldBg, oldPanel := hBgBrush, hPanelBrush
	hBgBrush = c(pCreateSolidBrush, clrBg)
	hPanelBrush = c(pCreateSolidBrush, clrPanelBg)

	wins := []uintptr{hMain}
	for _, d := range dlgStack {
		wins = append(wins, d.h)
	}
	for _, w := range wins {
		styleWindow(w)
		c(pEnumChildWindows, w, themeEnumCB, 0)
	}
	styleTree()
	for _, w := range wins {
		c(pRedrawWindow, w, 0, 0, 0x0001|0x0004|0x0080|0x0400) // INVALIDATE|ERASE|ALLCHILDREN|FRAME
	}
	// 처음 만든 브러시는 창 클래스에 등록돼 있으므로 지우지 않는다
	if oldBg != classBgBrush {
		c(pDeleteObject, oldBg)
	}
	if oldPanel != classPanelBrush {
		c(pDeleteObject, oldPanel)
	}
}

var classBgBrush, classPanelBrush uintptr

var themeEnumCB = syscall.NewCallback(func(h, _ uintptr) uintptr {
	styleControl(h)
	return 1
})

func className(h uintptr) string {
	var buf [64]uint16
	n := c(pGetClassNameW, h, uintptr(P(&buf[0])), 64)
	return syscall.UTF16ToString(buf[:n])
}

// 컨트롤 하나에 현재 테마(밝음/어두움)에 맞는 Windows 테마를 입힌다. 만들 때(mkp)와 테마를 바꿀 때 호출.
func styleControl(h uintptr) {
	dark := curTheme.dark
	setTheme := func(app string) {
		if app == "" {
			c(pSetWindowTheme, h, 0, 0) // 원래(밝은) 테마로
		} else {
			c(pSetWindowTheme, h, uintptr(P(ws(app))), 0)
		}
	}
	switch className(h) {
	case "Button":
		style := c(pGetWindowLongPtrW, h, ^uintptr(15) /*GWL_STYLE = -16*/) & 0xF
		if style == BS_OWNERDRAW {
			return
		}
		// 체크박스·옵션 묶음: 밝은 테마는 글자색을 무시하고 검게 그리므로 다크에서는 테마를 끈다
		if dark {
			empty := ws("")
			c(pSetWindowTheme, h, uintptr(P(empty)), uintptr(P(empty)))
		} else {
			setTheme("")
		}
	case "Edit", "CADGuidePane":
		if dark {
			setTheme("DarkMode_Explorer") // 어두운 스크롤바
		} else {
			setTheme("")
		}
	case "ComboBox":
		if dark {
			setTheme("DarkMode_CFD")
		} else {
			setTheme("")
		}
	case "SysTreeView32":
		if dark {
			setTheme("DarkMode_Explorer")
		} else {
			setTheme("Explorer")
		}
	}
}

// 입력칸·선택 목록(콤보 펼침) 색 (WM_CTLCOLOREDIT / WM_CTLCOLORLISTBOX)
func editColor(hdc uintptr) uintptr {
	c(pSetBkColor, hdc, clrPanelBg)
	c(pSetTextColor, hdc, clrText)
	return hPanelBrush
}

// 창 배경 (창 클래스의 브러시는 바꿀 수 없으므로 직접 칠한다)
func eraseBg(h, hdc uintptr) uintptr {
	var r rectT
	c(pGetClientRect, h, uintptr(P(&r)))
	c(pFillRect, hdc, uintptr(P(&r)), hBgBrush)
	return 1
}

// 전구 버튼: 차콜 다크 → 크림 → 슬레이트 → 차콜 다크 … 차례로
func toggleTheme() {
	next := themes[(themeIndex(curTheme.key)+1)%len(themes)].key
	applyTheme(next)
	saveState()
}
