// 시작하기 세트(APPLOAD > Startup Suite) 등록
// 리습마다 레지스트리에 따로 넣지 않고, 런처가 관리하는 launcher_startup.lsp 하나만 등록한다.
// 그 파일 안에서 체크한 리습들을 로드하고 *CADLAUNCHER-EXE*·외부 프로그램 경로 변수도 함께 설정한다.
// 레지스트리 위치: HKCU\Software\Autodesk\AutoCAD LT\R??\ACADLT-????:???\Profiles\<프로필>\Dialogs\Appload\Startup
//
//	NumStartup = "N",  1Startup = "C:\...\a.lsp", 2Startup = ...
package main

import (
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"unsafe"
)

const startupFile = "launcher_startup.lsp"

var (
	advapi32          = syscall.NewLazyDLL("advapi32.dll")
	pRegCreateKeyExW  = advapi32.NewProc("RegCreateKeyExW")
	pRegSetValueExW   = advapi32.NewProc("RegSetValueExW")
	pRegDeleteValueW  = advapi32.NewProc("RegDeleteValueW")
	pRegQueryValueExW = advapi32.NewProc("RegQueryValueExW")
)

func startupLoaderPath() string { return filepath.Join(appDir, startupFile) }

func isStartup(id string) bool {
	for _, s := range st.Startup {
		if s == id {
			return true
		}
	}
	return false
}

// launcher_startup.lsp 다시 쓰기 (목록에서 사라진 리습은 빠짐)
func writeStartupLoader() error {
	var sb strings.Builder
	sb.WriteString(";; CAD런처가 자동으로 만드는 파일입니다. 직접 고치지 마세요.\n")
	sb.WriteString(";; 런처에서 '모든 도면에서 자동 로드'를 체크한 리습을 도면을 열 때마다 로드합니다.\n")
	sb.WriteString("(setq *CADLAUNCHER-EXE* " + lispValue(Option{Type: "file"}, exePath) + ")\n")
	var keep []string
	for _, id := range st.Startup {
		l := lispByID(id)
		if l == nil || l.File == "" {
			continue
		}
		keep = append(keep, id)
		sb.WriteString(toolVarLines(l))
		lp := lispPath(l.File)
		sb.WriteString(`(if (findfile "` + lp + `") (load "` + lp + `" nil))` + "\n")
	}
	st.Startup = keep
	sb.WriteString("(princ)\n")
	return os.WriteFile(startupLoaderPath(), []byte(sb.String()), 0644)
}

// ───────────── 레지스트리 ─────────────
func regOpen(root syscall.Handle, path string, access uint32) (syscall.Handle, bool) {
	var h syscall.Handle
	if syscall.RegOpenKeyEx(root, ws(path), 0, access, &h) != nil {
		return 0, false
	}
	return h, true
}

func regSubKeys(h syscall.Handle) []string {
	var out []string
	for i := uint32(0); ; i++ {
		buf := make([]uint16, 512)
		n := uint32(len(buf))
		if syscall.RegEnumKeyEx(h, i, &buf[0], &n, nil, nil, nil, nil) != nil {
			break
		}
		out = append(out, syscall.UTF16ToString(buf[:n]))
	}
	return out
}

func regGetStr(h syscall.Handle, name string) string {
	buf := make([]uint16, 2048)
	n := uint32(len(buf) * 2)
	var typ uint32
	r, _, _ := pRegQueryValueExW.Call(uintptr(h), uintptr(P(ws(name))), 0, uintptr(unsafe.Pointer(&typ)), uintptr(unsafe.Pointer(&buf[0])), uintptr(unsafe.Pointer(&n)))
	if r != 0 {
		return ""
	}
	return syscall.UTF16ToString(buf)
}

func regSetStr(h syscall.Handle, name, val string) bool {
	v := syscall.StringToUTF16(val) // 끝의 0 포함
	r, _, _ := pRegSetValueExW.Call(uintptr(h), uintptr(P(ws(name))), 0, syscall.REG_SZ, uintptr(unsafe.Pointer(&v[0])), uintptr(len(v)*2))
	return r == 0
}

// AutoCAD LT 의 모든 버전·프로필에서 시작하기 세트 키 경로 찾기
func startupKeyPaths() []string {
	const base = `Software\Autodesk\AutoCAD LT`
	var out []string
	hb, ok := regOpen(syscall.HKEY_CURRENT_USER, base, syscall.KEY_READ)
	if !ok {
		return nil
	}
	defer syscall.RegCloseKey(hb)
	for _, rel := range regSubKeys(hb) { // R31 ...
		hr, ok := regOpen(hb, rel, syscall.KEY_READ)
		if !ok {
			continue
		}
		for _, prod := range regSubKeys(hr) { // ACADLT-xxxx:412 ...
			pp := rel + `\` + prod + `\Profiles`
			hp, ok := regOpen(hb, pp, syscall.KEY_READ)
			if !ok {
				continue
			}
			for _, prof := range regSubKeys(hp) {
				out = append(out, base+`\`+pp+`\`+prof+`\Dialogs\Appload\Startup`)
			}
			syscall.RegCloseKey(hp)
		}
		syscall.RegCloseKey(hr)
	}
	return out
}

// 시작하기 세트에 로더를 넣거나(add) 빼기. 바꾼 프로필 수를 돌려준다.
func setStartupSuite(add bool) int {
	loader := filepath.Clean(startupLoaderPath())
	changed := 0
	for _, kp := range startupKeyPaths() {
		var h syscall.Handle
		var disp uint32
		r, _, _ := pRegCreateKeyExW.Call(uintptr(syscall.HKEY_CURRENT_USER), uintptr(P(ws(kp))), 0, 0, 0,
			uintptr(syscall.KEY_READ|syscall.KEY_WRITE), 0, uintptr(unsafe.Pointer(&h)), uintptr(unsafe.Pointer(&disp)))
		if r != 0 {
			continue
		}
		num, _ := strconv.Atoi(strings.TrimSpace(regGetStr(h, "NumStartup")))
		var list []string
		has := false
		for i := 1; i <= num; i++ {
			v := regGetStr(h, strconv.Itoa(i)+"Startup")
			if v == "" {
				continue
			}
			if strings.EqualFold(filepath.Clean(v), loader) {
				has = true
				continue
			}
			list = append(list, v)
		}
		if add {
			list = append(list, loader)
		}
		if has != add || len(list) != num {
			for i := len(list) + 1; i <= num; i++ {
				pRegDeleteValueW.Call(uintptr(h), uintptr(P(ws(strconv.Itoa(i)+"Startup"))))
			}
			okAll := true
			for i, v := range list {
				okAll = regSetStr(h, strconv.Itoa(i+1)+"Startup", v) && okAll
			}
			okAll = regSetStr(h, "NumStartup", strconv.Itoa(len(list))) && okAll
			if okAll {
				changed++
			}
		}
		syscall.RegCloseKey(h)
	}
	return changed
}

// 체크박스를 눌렀을 때
func toggleStartup() {
	l := cur.lisp()
	if l == nil || l.File == "" {
		return
	}
	on := isChecked(hStartup)
	var next []string
	for _, s := range st.Startup {
		if s != l.ID {
			next = append(next, s)
		}
	}
	if on {
		next = append(next, l.ID)
	}
	st.Startup = next
	if err := writeStartupLoader(); err != nil {
		msgBox(T("startup.001")+err.Error(), MB_ICONERROR)
		setCheck(hStartup, !on)
		return
	}
	if len(startupKeyPaths()) == 0 {
		msgBox(T("startup.002")+startupLoaderPath(), MB_ICONWARNING)
	} else {
		setStartupSuite(len(st.Startup) > 0)
	}
	saveState()
	if on {
		logf(T("startup.003"), l.ID)
		logf(T("startup.004"), startupFile)
	} else {
		logf(T("startup.005"), l.ID)
	}
}
