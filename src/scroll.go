package main

// 직접 그리는 세로 스크롤 막대 (왼쪽 목록·설명서 칸 공통)
//   Windows 기본 어두운 스크롤 막대는 가늘고 흐려서 잘 안 보이므로,
//   내용이 넘칠 때 오른쪽에 둥근 막대를 또렷한 색으로 늘 보여 준다.
//   마우스를 올리면 굵어지고, 끌기·빈 곳 누르기(한 화면씩)·휠로 움직인다.

import "unsafe"

const sbW = 14 // 스크롤 막대 자리 폭 (96DPI 기준, 내용은 이만큼 덜 씀)

type vscroll struct {
	pos, total, view int // 장치 픽셀
	hot, drag        bool
	grab             int // 끄는 중: 마우스 y - 막대 위끝
}

func (v *vscroll) need() bool { return v.total > v.view+1 }

func (v *vscroll) clamp() {
	if mx := max(v.total-v.view, 0); v.pos > mx {
		v.pos = mx
	}
	if v.pos < 0 {
		v.pos = 0
	}
}

func (v *vscroll) track(H int) (int, int) { return si(4), max(H-si(8), 1) }

func (v *vscroll) thumbLen(H int) int {
	_, th := v.track(H)
	return min(max(th*v.view/max(v.total, 1), si(32)), th)
}

func (v *vscroll) thumbTop(H int) int {
	top, th := v.track(H)
	span := max(v.total-v.view, 1)
	return top + (th-v.thumbLen(H))*v.pos/span
}

func (v *vscroll) inBar(W, x int) bool { return v.need() && x >= W-si(sbW) }

func scrollColors() (track, thumb, thumbHot uintptr) {
	if curTheme.dark {
		return mixClr(clrBg, white, 0.07), mixClr(clrBg, white, 0.42), mixClr(clrBg, white, 0.62)
	}
	return mixClr(clrBg, 0, 0.06), mixClr(clrBg, 0, 0.32), mixClr(clrBg, 0, 0.50)
}

func (v *vscroll) paint(hdc uintptr, W, H int) {
	if !v.need() {
		return
	}
	track, thumb, thumbHot := scrollColors()
	w := si(7)
	if v.hot || v.drag {
		w, thumb = si(10), thumbHot
	}
	x := W - si(3) - w
	top, th := v.track(H)
	fillRound(hdc, x, top, w, th, track, track, w)
	fillRound(hdc, x, v.thumbTop(H), w, v.thumbLen(H), thumb, thumb, w)
}

// 누른 곳이 막대 자리면 true (막대를 잡거나 한 화면 넘김)
func (v *vscroll) mouseDown(W, H, x, y int) bool {
	if !v.inBar(W, x) {
		return false
	}
	t := v.thumbTop(H)
	if y >= t && y < t+v.thumbLen(H) {
		v.drag, v.grab = true, y-t
	} else if y < t {
		v.pos -= v.view * 9 / 10
	} else {
		v.pos += v.view * 9 / 10
	}
	v.clamp()
	return true
}

func (v *vscroll) mouseDrag(H, y int) {
	top, th := v.track(H)
	room := max(th-v.thumbLen(H), 1)
	v.pos = (y - v.grab - top) * max(v.total-v.view, 0) / room
	v.clamp()
}

func (v *vscroll) wheel(delta int) {
	v.pos -= delta * si(48) / 120
	v.clamp()
}

// 마우스가 창 밖으로 나가면 WM_MOUSELEAVE 받기
func trackLeave(h uintptr) {
	tme := trackMouseEvent{flags: TME_LEAVE, hwnd: h}
	tme.size = uint32(unsafe.Sizeof(tme))
	c(pTrackMouseEvent, uintptr(P(&tme)))
}
