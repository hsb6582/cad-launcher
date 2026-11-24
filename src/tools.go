package main

// 리습과 함께 쓰는 외부 프로그램 설치 + 리습 머리말(@launcher) 읽기

import (
	"archive/zip"
	"fmt"
	"io"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"syscall"
	"unsafe"
)

// Tool: 리습과 세트로 쓰는 외부 프로그램
type Tool struct {
	Name    string `json:"name"`
	Version string `json:"version,omitempty"`
	Desc    string `json:"desc,omitempty"`
	Source  string `json:"source"`         // 저장소 안 경로(tools/MATX.zip) 또는 https 주소
	Kind    string `json:"kind"`           // zip | exe | msi | file
	Exe     string `json:"exe,omitempty"`  // zip/file: 설치 폴더 안 실행파일 / exe·msi: 설치 후 확인할 경로(%ProgramFiles% 등 사용 가능)
	Args    string `json:"args,omitempty"` // exe·msi 설치 옵션 (예: /S)
	Var     string `json:"var,omitempty"`  // 실행파일 경로를 받을 LISP 변수 (예: *MATX-EXE*)
}

var toolKinds = []string{"zip", "exe", "msi", "file"}
var toolKindNames = []string{"zip (압축 풀어 설치)", "exe 설치 프로그램 실행", "msi 설치 패키지 실행", "file (파일 하나 복사)"}

var envRe = regexp.MustCompile(`%([^%]+)%`)

func expandEnv(s string) string {
	return envRe.ReplaceAllStringFunc(s, func(m string) string {
		if v := os.Getenv(m[1 : len(m)-1]); v != "" {
			return v
		}
		return m
	})
}

func toolsRoot() string {
	base := os.Getenv("LOCALAPPDATA")
	if base == "" {
		base = appDir
	}
	return filepath.Join(base, "CADLauncher", "tools")
}

func toolDir(t Tool) string { return filepath.Join(toolsRoot(), sanitize(t.Name)) }

func sanitize(s string) string {
	return strings.Map(func(r rune) rune {
		if strings.ContainsRune(`\/:*?"<>|`, r) {
			return '_'
		}
		return r
	}, s)
}

func toolExePath(t Tool) string {
	switch t.Kind {
	case "exe", "msi":
		return expandEnv(t.Exe)
	}
	exe := t.Exe
	if exe == "" {
		exe = filepath.Base(filepath.FromSlash(t.Source))
	}
	return filepath.Join(toolDir(t), filepath.FromSlash(exe))
}

func toolInstalled(t Tool) bool {
	if p := toolExePath(t); p != "" {
		if _, err := os.Stat(p); err == nil {
			return true
		}
		if t.Exe != "" || t.Kind == "zip" || t.Kind == "file" {
			return false
		}
	}
	_, ok := st.Installed[t.Name]
	return ok
}

// 0 설치 안 됨 / 1 설치됨 / 2 새 버전 있음
func toolState(t Tool) int {
	if !toolInstalled(t) {
		return 0
	}
	if t.Version != "" && st.Installed[t.Name] != "" && st.Installed[t.Name] != t.Version {
		return 2
	}
	return 1
}

func toolStatusText(t Tool) string {
	v := ""
	if t.Version != "" {
		v = " v" + t.Version
	}
	switch toolState(t) {
	case 0:
		return t.Name + v + " — 설치 안 됨"
	case 2:
		return t.Name + v + " — 새 버전 있음 (설치된 버전 " + st.Installed[t.Name] + ")"
	}
	return t.Name + v + " — 설치됨"
}

func toolsSummary(l *Lisp) string {
	if len(l.Tools) == 0 {
		return ""
	}
	var sb strings.Builder
	sb.WriteString("\n[외부 프로그램]  ('외부 프로그램' 버튼으로 설치)\n")
	for _, t := range l.Tools {
		sb.WriteString("  • " + toolStatusText(t) + "\n")
		if t.Desc != "" {
			sb.WriteString("      " + t.Desc + "\n")
		}
	}
	return sb.String()
}

// 설치 파일 받기: 저장소가 설정돼 있으면 저장소에서, 아니면 런처 폴더의 같은 경로에서
func fetchToolSource(t Tool) (string, error) {
	src := strings.TrimSpace(t.Source)
	if src == "" {
		return "", fmt.Errorf("설치 파일 위치가 비어 있습니다")
	}
	name := filepath.Base(filepath.FromSlash(strings.SplitN(src, "?", 2)[0]))
	dl := filepath.Join(os.TempDir(), "CADLauncher_"+sanitize(name))
	var data []byte
	var err error
	switch {
	case strings.HasPrefix(src, "http://") || strings.HasPrefix(src, "https://"):
		data, err = ghGet(src, "")
	default:
		segs := strings.Split(strings.TrimPrefix(filepath.ToSlash(src), "/"), "/")
		for i := range segs {
			segs[i] = url.PathEscape(segs[i])
		}
		data, err = ghGet("https://raw.githubusercontent.com/"+fixedRepo+"/"+url.PathEscape(branch())+"/"+strings.Join(segs, "/"), "")
		if err != nil { // 저장소에 없으면 로컬 파일로
			if b, e2 := os.ReadFile(absPath(src)); e2 == nil {
				data, err = b, nil
			}
		}
	}
	if err != nil {
		return "", err
	}
	if err := os.WriteFile(dl, data, 0755); err != nil {
		return "", err
	}
	return dl, nil
}

func unzipTo(zipPath, dir string) error {
	r, err := zip.OpenReader(zipPath)
	if err != nil {
		return err
	}
	defer r.Close()
	root, _ := filepath.Abs(dir)
	for _, f := range r.File {
		p := filepath.Join(dir, filepath.FromSlash(f.Name))
		ap, _ := filepath.Abs(p)
		if ap != root && !strings.HasPrefix(ap, root+string(os.PathSeparator)) {
			return fmt.Errorf("압축 파일에 잘못된 경로가 있습니다: %s", f.Name)
		}
		if f.FileInfo().IsDir() {
			_ = os.MkdirAll(p, 0755)
			continue
		}
		_ = os.MkdirAll(filepath.Dir(p), 0755)
		rc, err := f.Open()
		if err != nil {
			return err
		}
		out, err := os.Create(p)
		if err != nil {
			rc.Close()
			return err
		}
		_, err = io.Copy(out, rc)
		out.Close()
		rc.Close()
		if err != nil {
			return err
		}
	}
	return nil
}

// 백그라운드에서 받기/풀기, 실행형 설치는 메인 스레드에서 ShellExecute
type toolJob struct {
	tools []Tool
	err   []string
	runs  [][2]string // 실행할 설치 프로그램 (파일, 인자)
	done  []string
}

var pendingJob *toolJob

func installTools(ts []Tool) {
	if updating {
		msgBox("다른 작업이 진행 중입니다. 잠시 후 다시 시도하세요.", MB_ICONWARNING)
		return
	}
	updating = true
	c(pEnableWindow, hTools, 0)
	logf("외부 프로그램 설치 준비 중…")
	go func() {
		job := &toolJob{tools: ts}
		for _, t := range ts {
			dl, err := fetchToolSource(t)
			if err != nil {
				job.err = append(job.err, t.Name+": "+err.Error())
				continue
			}
			switch t.Kind {
			case "zip":
				dir := toolDir(t)
				_ = os.RemoveAll(dir + ".old")
				_ = os.Rename(dir, dir+".old")
				if err := unzipTo(dl, dir); err != nil {
					_ = os.RemoveAll(dir)
					_ = os.Rename(dir+".old", dir)
					job.err = append(job.err, t.Name+": "+err.Error())
					continue
				}
				_ = os.RemoveAll(dir + ".old")
				job.done = append(job.done, t.Name)
			case "file":
				dir := toolDir(t)
				_ = os.MkdirAll(dir, 0755)
				b, _ := os.ReadFile(dl)
				if err := os.WriteFile(toolExePath(t), b, 0755); err != nil {
					job.err = append(job.err, t.Name+": "+err.Error())
					continue
				}
				job.done = append(job.done, t.Name)
			case "msi":
				job.runs = append(job.runs, [2]string{"msiexec.exe", `/i "` + dl + `" ` + t.Args})
				job.done = append(job.done, t.Name)
			default: // exe
				job.runs = append(job.runs, [2]string{dl, t.Args})
				job.done = append(job.done, t.Name)
			}
		}
		pendingJob = job
		c(pPostMessageW, hMain, WM_APP_TOOLS, 0, 0)
	}()
}

func onToolsResult() {
	job := pendingJob
	pendingJob = nil
	updating = false
	c(pEnableWindow, hTools, 1)
	if job == nil {
		return
	}
	for _, r := range job.runs {
		logf("설치 프로그램 실행: %s %s", r[0], r[1])
		c(pShellExecuteW, hMain, uintptr(P(ws("open"))), uintptr(P(ws(r[0]))), uintptr(P(ws(r[1]))), 0, SW_SHOWNORMAL)
	}
	for _, t := range job.tools {
		for _, n := range job.done {
			if n == t.Name {
				st.Installed[t.Name] = t.Version
				if st.Installed[t.Name] == "" {
					st.Installed[t.Name] = "설치됨"
				}
			}
		}
	}
	saveState()
	msg := ""
	if len(job.done) > 0 {
		msg += "설치 완료: " + strings.Join(job.done, ", ")
		if len(job.runs) > 0 {
			msg += "\n(설치 프로그램 창이 열리면 안내에 따라 마무리하세요)"
		}
	}
	if len(job.err) > 0 {
		msg += "\n\n실패:\n" + strings.Join(job.err, "\n")
	}
	logf("외부 프로그램: 완료 %d, 실패 %d", len(job.done), len(job.err))
	if msg != "" {
		msgBox(strings.TrimSpace(msg), 0x40)
	}
	showNode(cur)
}

// 현재 선택한 리습의 외부 프로그램 설치 버튼
func installCurrentTools() {
	l := cur.lisp()
	if l == nil || len(l.Tools) == 0 {
		return
	}
	var need []Tool
	for _, t := range l.Tools {
		if toolState(t) != 1 {
			need = append(need, t)
		}
	}
	list := need
	q := "아래 외부 프로그램을 설치할까요?\n\n"
	if len(need) == 0 {
		list = l.Tools
		q = "모두 설치되어 있습니다. 다시 설치할까요?\n\n"
	}
	for _, t := range list {
		q += "  • " + toolStatusText(t) + "\n     받는 곳: " + t.Source + "\n"
	}
	if ask(q) {
		installTools(list)
	}
}

// 실행 전: 설치 안 된 외부 프로그램 확인 → true 면 실행 계속
func ensureTools(l *Lisp) bool {
	var miss []Tool
	for _, t := range l.Tools {
		if toolState(t) == 0 {
			miss = append(miss, t)
		}
	}
	if len(miss) == 0 {
		return true
	}
	names := []string{}
	for _, t := range miss {
		names = append(names, t.Name)
	}
	r := msgBox("이 리습에 필요한 외부 프로그램이 설치되어 있지 않습니다: "+strings.Join(names, ", ")+
		"\n\n지금 설치할까요?\n(예 = 설치 / 아니오 = 설치 없이 실행 / 취소 = 실행 안 함)", 0x03|MB_ICONQUESTION)
	switch r {
	case IDYES:
		installTools(miss)
		return false
	case 7: // IDNO
		return true
	}
	return false
}

func toolVarLines(l *Lisp) string {
	var sb strings.Builder
	for _, t := range l.Tools {
		if t.Var != "" {
			sb.WriteString("(setq " + t.Var + " " + lispValue(Option{Type: "file"}, toolExePath(t)) + ")\n")
		}
	}
	return sb.String()
}

// ───────────── 외부 프로그램 편집 창 ─────────────
func toolDialog(t *Tool) bool {
	d := newDialog("외부 프로그램", 560, 400)
	const lx, ex, ew = 14, 120, 420
	d.label("이름", lx, 16, 100)
	hName := d.edit(t.Name, ex, 12, 200)
	d.label("버전", lx+330, 16, 40)
	hVer := d.edit(t.Version, ex+260, 12, 160)
	d.label("설명", lx, 48, 100)
	hDesc := d.edit(t.Desc, ex, 44, ew)
	d.label("설치 파일", lx, 80, 100)
	hSrc := d.edit(t.Source, ex, 76, ew-40)
	d.button("…", 801, ex+ew-34, 74, 34, false)
	d.note("저장소 안 경로(tools/MATX.zip) 또는 https 주소 (큰 파일은 GitHub Releases 주소 권장)", ex, 104, ew, 20)
	d.label("종류", lx, 132, 100)
	hKind := d.mk("COMBOBOX", "", CBS_DROPDOWNLIST|WS_TABSTOP, 0, 802)
	mv(hKind, ex, 128, 250, 200)
	comboFill(hKind, toolKindNames, max(indexOf(toolKinds, t.Kind), 0))
	d.label("실행 파일", lx, 164, 100)
	hExe := d.edit(t.Exe, ex, 160, ew)
	d.note("zip·file: 설치 폴더 안 실행파일 (예: MATX.exe)  /  exe·msi: 설치 후 확인할 경로 (예: %ProgramFiles%\\MATX\\MATX.exe)", ex, 188, ew, 34)
	d.label("설치 옵션", lx, 230, 100)
	hArgs := d.edit(t.Args, ex, 226, 200)
	d.note("exe·msi 전용 (예: /S, /quiet)", ex+208, 230, ew-208, 20)
	d.label("LISP 변수", lx, 262, 100)
	hVar := d.edit(t.Var, ex, 258, 200)
	d.note("실행파일 경로를 리습에 넘김 (예: *MATX-EXE*)", ex+208, 262, ew-208, 20)
	d.note("zip·file 은 %LOCALAPPDATA%\\CADLauncher\\tools\\이름 폴더에 설치됩니다.", ex, 296, ew, 20)
	d.button("확인", IDOK, 350, 356, 95, true)
	d.button("취소", IDCANCEL, 450, 356, 95, false)
	d.onCmd = func(id, code int) {
		switch {
		case id == 801 && code == BN_CLICKED:
			buf := make([]uint16, 1024)
			filter := utf16Z("설치 파일 (*.zip;*.exe;*.msi)\x00*.zip;*.exe;*.msi\x00모든 파일\x00*.*\x00\x00")
			ofn := openFileName{hwndOwner: d.h, lpstrFilter: &filter[0], lpstrFile: &buf[0], nMaxFile: uint32(len(buf)), Flags: 0x00001000 | 0x00000008 | 0x00080000}
			ofn.lStructSize = uint32(unsafe.Sizeof(ofn))
			if c(pGetOpenFileNameW, uintptr(P(&ofn))) != 0 {
				p := syscall.UTF16ToString(buf)
				// 런처 폴더의 tools 로 복사해 두면 저장소에 함께 올릴 수 있음
				dst := filepath.Join(appDir, "tools", filepath.Base(p))
				if rel, err := filepath.Rel(appDir, p); err == nil && !strings.HasPrefix(rel, "..") {
					setText(hSrc, filepath.ToSlash(rel))
				} else if b, err := os.ReadFile(p); err == nil {
					_ = os.MkdirAll(filepath.Dir(dst), 0755)
					if os.WriteFile(dst, b, 0644) == nil {
						setText(hSrc, "tools/"+filepath.Base(p))
					}
				}
				ext := strings.ToLower(filepath.Ext(p))
				if i := indexOf(toolKinds, strings.TrimPrefix(ext, ".")); ext != "" && contains(toolKinds, strings.TrimPrefix(ext, ".")) {
					c(pSendMessageW, hKind, CB_SETCURSEL, uintptr(i), 0)
				}
				if strings.TrimSpace(getText(hName)) == "" {
					setText(hName, strings.TrimSuffix(filepath.Base(p), ext))
				}
			}
			_ = filter
		case id == IDOK:
			name := strings.TrimSpace(getText(hName))
			src := strings.TrimSpace(getText(hSrc))
			if name == "" || src == "" {
				msgBox("이름과 설치 파일을 입력하세요.", MB_ICONWARNING)
				return
			}
			k := "zip"
			if i := comboSel(hKind); i >= 0 {
				k = toolKinds[i]
			}
			*t = Tool{Name: name, Version: strings.TrimSpace(getText(hVer)), Desc: strings.TrimSpace(getText(hDesc)),
				Source: filepath.ToSlash(src), Kind: k, Exe: strings.TrimSpace(getText(hExe)),
				Args: strings.TrimSpace(getText(hArgs)), Var: strings.TrimSpace(getText(hVar))}
			d.ok, d.done = true, true
		}
	}
	return d.run(hName)
}

func contains(list []string, v string) bool {
	for _, x := range list {
		if x == v {
			return true
		}
	}
	return false
}
