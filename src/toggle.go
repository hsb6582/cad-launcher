package main

// 켜고 끄는 토글 스위치 - 런처의 모든 체크박스(BS_AUTOCHECKBOX)를 이 모양으로 그린다.
//   mkp 에서 체크박스를 직접 그리는 버튼으로 바꿔 등록하고, 눌리면(BN_CLICKED) 상태를 뒤집는다.
//   isChecked / setCheck 는 그대로 쓰면 된다 (win32.go).
//   누르면 동그란 손잡이가 약 0.15초 동안 미끄러지고 바탕색이 회색 ↔ 파랑으로 바뀐다.

import (
	"math"
	"time"
)

type toggleState struct {
	on    bool
	start time.Time // 애니메이션 시작 (zero = 움직이지 않음)
}

var toggles = map[uintptr]*toggleState{}

const (
	toggleDur     = 150 * time.Millisecond
	toggleTimerID = 9
	swTrackW      = 34 // 스위치 크기 (96DPI 기준)
	swTrackH      = 19
	swGap         = 9 // 스위치와 글자 사이
)

func isToggle(h uintptr) bool { return h != 0 && toggles[h] != nil }

// 손잡이 위치 0(꺼짐) ~ 1(켜짐), 애니메이션 중이면 그 사이
func toggleFrac(h uintptr) float64 {
	t := toggles[h]
	if t == nil {
		return 0
	}
	target := 0.0
	if t.on {
		target = 1
	}
	if t.start.IsZero() {
		return target
	}
	p := float64(time.Since(t.start)) / float64(toggleDur)
	if p >= 1 {
		return target
	}
	e := 1 - (1-p)*(1-p)*(1-p) // 끝에 느려짐
	if t.on {
		return e
	}
	return 1 - e
}

// 눌렀을 때 (WM_COMMAND BN_CLICKED 를 처리하기 전에 부름)
func toggleFlip(h uintptr) {
	t := toggles[h]
	if t == nil {
		return
	}
	t.on = !t.on
	t.start = time.Now()
	c(pSetTimer, h, toggleTimerID, 15, 0)
	c(pInvalidateRect, h, 0, 0)
}

// 버튼 창의 WM_TIMER (btnProc)
func toggleTick(h uintptr) {
	t := toggles[h]
	if t == nil || t.start.IsZero() || time.Since(t.start) >= toggleDur {
		if t != nil {
			t.start = time.Time{}
		}
		c(pKillTimer, h, toggleTimerID)
	}
	c(pInvalidateRect, h, 0, 0)
}

// 스위치 + 글자 (WM_DRAWITEM)
func drawSwitch(dis *drawItemStruct) {
	hdc := dis.hDC
	r := dis.rcItem
	h := dis.hwndItem
	under := ctlBg(h)
	fillBox(hdc, int(r.left), int(r.top), int(r.right-r.left), int(r.bottom-r.top), under)
	H := int(r.bottom - r.top)
	tw, th := si(swTrackW), si(swTrackH)
	f := toggleFrac(h)
	_, onClr := runColors(false, false)
	offClr := clrBtnBorder
	disabled := dis.itemState&ODS_DISABLED != 0
	track := mixClr(offClr, onClr, f)
	knob := white
	if disabled {
		track, knob = clrDisBg, mixClr(white, clrDisBg, 0.4)
	}
	cv := newCanvas(tw+2, th+2, under)
	ftw, fth := float64(tw), float64(th)
	cv.paint(func(x, y float64) float64 { return aa(sdRoundRect(x, y, 1, 1, ftw+1, fth+1, fth/2)) }, solid(track))
	kr := fth/2 - float64(si(3))
	kx := 1 + fth/2 + (ftw-fth)*f
	cv.paint(func(x, y float64) float64 { return aa(math.Hypot(x-kx, y-(1+fth/2)) - kr) }, solid(knob))
	cv.blit(hdc, int(r.left), int(r.top)+(H-th-2)/2)
	if label := getText(h); label != "" {
		clr := clrText
		if disabled {
			clr = clrSubText
		}
		_, lh := textSize(hdc, hFont, label)
		drawTextAt(hdc, hFont, clr, int(r.left)+tw+si(swGap), int(r.top)+(H-lh)/2, label)
	}
}
