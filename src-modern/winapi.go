package main

// 실제 CAD 창을 찾고 명령을 보내는 부분 - 실제 CAD런처(src/send.go, src/win32.go)와 동일한 Win32 API를 직접 호출한다.
// (WebView2는 화면만 그릴 뿐, AutoCAD와 통신하는 이 부분은 그대로 재사용한다)

import (
	"fmt"
	"runtime"
	"strings"
	"syscall"
	"time"
	"unicode/utf16"
	"unsafe"
)

var (
	user32   = syscall.NewLazyDLL("user32.dll")
	shell32  = syscall.NewLazyDLL("shell32.dll")
	kernel32 = syscall.NewLazyDLL("kernel32.dll")

	pEnumWindows          = user32.NewProc("EnumWindows")
	pIsWindowVisible      = user32.NewProc("IsWindowVisible")
	pGetWindowTextW       = user32.NewProc("GetWindowTextW")
	pGetWindowTextLengthW = user32.NewProc("GetWindowTextLengthW")
	pIsWindow             = user32.NewProc("IsWindow")
	pIsIconic             = user32.NewProc("IsIconic")
	pShowWindow           = user32.NewProc("ShowWindow")
	pSetForegroundWindow  = user32.NewProc("SetForegroundWindow")
	pSendMessageTimeoutW  = user32.NewProc("SendMessageTimeoutW")
	pSendInput            = user32.NewProc("SendInput")
	pSetWindowPos         = user32.NewProc("SetWindowPos")
	pShellExecuteW        = shell32.NewProc("ShellExecuteW")

	pWideCharToMultiByte = kernel32.NewProc("WideCharToMultiByte")
)

func c(p *syscall.LazyProc, a ...uintptr) uintptr { r, _, _ := p.Call(a...); return r }

func ws(s string) *uint16 {
	p, _ := syscall.UTF16PtrFromString(strings.ReplaceAll(s, "\x00", ""))
	return p
}

func getWindowText(h uintptr) string {
	n := c(pGetWindowTextLengthW, h)
	buf := make([]uint16, n+1)
	c(pGetWindowTextW, h, uintptr(unsafe.Pointer(&buf[0])), n+1)
	return syscall.UTF16ToString(buf)
}

type cadWin struct {
	h     uintptr
	title string
}

const (
	WM_COPYDATA       = 0x004A
	SMTO_ABORTIFHUNG  = 0x0002
	SW_RESTORE        = 9
	VK_RETURN         = 0x0D
	VK_ESCAPE         = 0x1B
	INPUT_KEYBOARD    = 1
	KEYEVENTF_KEYUP   = 0x0002
	KEYEVENTF_UNICODE = 0x0004
	SW_SHOWNORMAL     = 1
)

type copyDataStruct struct {
	dwData uintptr
	cbData uint32
	lpData uintptr
}

type keybdInput struct {
	wVk         uint16
	wScan       uint16
	dwFlags     uint32
	time        uint32
	dwExtraInfo uintptr
}

type inputT struct {
	typ uint32
	_   uint32
	ki  keybdInput
	_   [8]byte
}

// 창 목록에서 제외할 이 프로그램 자신의 창 핸들 (main에서 설정)
var selfHwnd uintptr

func findWindows(keyword string) []cadWin {
	kw := strings.ToLower(strings.TrimSpace(keyword))
	if kw == "" {
		kw = "autocad"
	}
	var found []cadWin
	cb := syscall.NewCallback(func(h, lp uintptr) uintptr {
		if h != selfHwnd && c(pIsWindowVisible, h) != 0 {
			t := getWindowText(h)
			if t != "" && strings.Contains(strings.ToLower(t), kw) {
				found = append(found, cadWin{h, t})
			}
		}
		return 1
	})
	c(pEnumWindows, cb, 0)
	return found
}

func sendCopyData(h uintptr, text string, cancel bool) error {
	if cancel {
		text = "\x03\x03" + text
	}
	u := append(utf16.Encode([]rune(text)), 0)
	cds := copyDataStruct{dwData: 1, cbData: uint32(len(u) * 2), lpData: uintptr(unsafe.Pointer(&u[0]))}
	var res uintptr
	r := c(pSendMessageTimeoutW, h, WM_COPYDATA, selfHwnd, uintptr(unsafe.Pointer(&cds)), SMTO_ABORTIFHUNG, 5000, uintptr(unsafe.Pointer(&res)))
	runtime.KeepAlive(u)
	if r == 0 {
		return fmt.Errorf("WM_COPYDATA 전송 실패 (CAD 응답 없음/시간 초과)")
	}
	return nil
}

func keyEvent(vk, scan uint16, flags uint32) {
	in := inputT{typ: INPUT_KEYBOARD, ki: keybdInput{wVk: vk, wScan: scan, dwFlags: flags}}
	c(pSendInput, 1, uintptr(unsafe.Pointer(&in)), unsafe.Sizeof(in))
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

func setTopmost(on bool) {
	after := ^uintptr(1) // HWND_NOTOPMOST
	if on {
		after = ^uintptr(0) // HWND_TOPMOST
	}
	c(pSetWindowPos, selfHwnd, after, 0, 0, 0, 0, 0x0003)
}

func toCP949(s string) []byte {
	u := utf16.Encode([]rune(s))
	if len(u) == 0 {
		return nil
	}
	n := c(pWideCharToMultiByte, 949, 0, uintptr(unsafe.Pointer(&u[0])), uintptr(len(u)), 0, 0, 0, 0)
	if n == 0 {
		return []byte(s)
	}
	out := make([]byte, n)
	c(pWideCharToMultiByte, 949, 0, uintptr(unsafe.Pointer(&u[0])), uintptr(len(u)), uintptr(unsafe.Pointer(&out[0])), n, 0, 0)
	return out
}

func shellExec(file, args string) {
	c(pShellExecuteW, 0, uintptr(unsafe.Pointer(ws("open"))), uintptr(unsafe.Pointer(ws(file))), uintptr(unsafe.Pointer(ws(args))), 0, SW_SHOWNORMAL)
}
