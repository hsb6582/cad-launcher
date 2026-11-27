package main

import (
	"fmt"
	"runtime"
	"strings"
	"syscall"
	"time"
	"unicode/utf16"
	"unsafe"
)

// ───────────────────────── CAD 창 / 전송 ─────────────────────────
type cadWin struct {
	h     uintptr
	title string
}

var (
	windows []cadWin
	enumKW  string
	enumCB  = syscall.NewCallback(func(h, lp uintptr) uintptr {
		if h != hMain && c(pIsWindowVisible, h) != 0 {
			t := getText(h)
			if t != "" && strings.Contains(strings.ToLower(t), enumKW) && !strings.HasPrefix(t, appTitle) {
				windows = append(windows, cadWin{h, t})
			}
		}
		return 1
	})
)

func sendCopyData(h uintptr, text string, cancel bool) error {
	if cancel {
		text = "\x03\x03" + text // Ctrl+C ×2 = 진행 중 명령 취소
	}
	u := append(utf16.Encode([]rune(text)), 0)
	cds := copyDataStruct{dwData: 1, cbData: uint32(len(u) * 2), lpData: uintptr(P(&u[0]))}
	var res uintptr
	r := c(pSendMessageTimeoutW, h, WM_COPYDATA, hMain, uintptr(P(&cds)), SMTO_ABORTIFHUNG, 5000, uintptr(P(&res)))
	runtime.KeepAlive(u)
	if r == 0 {
		return fmt.Errorf("%s", T("send.001"))
	}
	return nil
}

func keyEvent(vk, scan uint16, flags uint32) {
	in := inputT{typ: INPUT_KEYBOARD, ki: keybdInput{wVk: vk, wScan: scan, dwFlags: flags}}
	c(pSendInput, 1, uintptr(P(&in)), unsafe.Sizeof(in))
}

func pressVK(vk uint16) { keyEvent(vk, 0, 0); keyEvent(vk, 0, KEYEVENTF_KEYUP) }

func sendKeys(h uintptr, text string, cancel bool) {
	if c(pIsIconic, h) != 0 {
		c(pShowWindow, h, SW_RESTORE)
	}
	c(pSetForegroundWindow, h)
	time.Sleep(300 * time.Millisecond)
	if cancel {
		pressVK(VK_ESCAPE)
		time.Sleep(50 * time.Millisecond)
		pressVK(VK_ESCAPE)
		time.Sleep(50 * time.Millisecond)
	}
	for _, r := range text {
		switch {
		case r == '\n':
			pressVK(VK_RETURN)
			time.Sleep(30 * time.Millisecond)
		case r == 0x1b:
			pressVK(VK_ESCAPE)
			time.Sleep(50 * time.Millisecond)
		case r <= 0xFFFF:
			keyEvent(0, uint16(r), KEYEVENTF_UNICODE)
			keyEvent(0, uint16(r), KEYEVENTF_UNICODE|KEYEVENTF_KEYUP)
		}
		time.Sleep(10 * time.Millisecond)
	}
}
