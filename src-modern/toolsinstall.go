package main

// 리습과 함께 쓰는 외부 프로그램 설치 - 실제 CAD런처(src/tools.go)와 동일한 방식.

import (
	"archive/zip"
	"fmt"
	"io"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

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

func sanitize(s string) string {
	return strings.Map(func(r rune) rune {
		if strings.ContainsRune(`\/:*?"<>|`, r) {
			return '_'
		}
		return r
	}, s)
}

func toolDir(t Tool) string {
	if strings.TrimSpace(t.Dir) != "" {
		return filepath.Clean(expandEnv(t.Dir))
	}
	return filepath.Join(toolsRoot(), sanitize(t.Name))
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

func toolVarLines(l *Lisp) string {
	var sb strings.Builder
	for _, t := range l.Tools {
		if t.Var != "" {
			sb.WriteString("(setq " + t.Var + " " + lispValue(Option{Type: "file"}, toolExePath(t)) + ")\n")
		}
	}
	return sb.String()
}

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
		if err != nil {
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

// installToolsSync: lispID 의 외부 프로그램을 전부(또는 부족한 것만) 설치하고 결과 메시지를 돌려준다.
func installToolsSync(lispID string) (string, error) {
	l := lispByID(lispID)
	if l == nil || len(l.Tools) == 0 {
		return "", fmt.Errorf("이 기능에는 외부 프로그램이 없습니다.")
	}
	var done, errs, runs []string
	for _, t := range l.Tools {
		dl, err := fetchToolSource(t)
		if err != nil {
			errs = append(errs, t.Name+": "+err.Error())
			continue
		}
		switch t.Kind {
		case "zip":
			dir := toolDir(t)
			if err := os.MkdirAll(dir, 0755); err != nil {
				errs = append(errs, t.Name+": 폴더를 만들 수 없음 "+dir)
				continue
			}
			if err := unzipTo(dl, dir); err != nil {
				errs = append(errs, t.Name+": "+err.Error()+" (프로그램이 실행 중이면 닫고 다시 시도)")
				continue
			}
			done = append(done, t.Name)
		case "file":
			dir := toolDir(t)
			_ = os.MkdirAll(dir, 0755)
			b, _ := os.ReadFile(dl)
			if err := os.WriteFile(toolExePath(t), b, 0755); err != nil {
				errs = append(errs, t.Name+": "+err.Error())
				continue
			}
			done = append(done, t.Name)
		case "msi":
			shellExec("msiexec.exe", `/i "`+dl+`" `+t.Args)
			runs = append(runs, t.Name)
			done = append(done, t.Name)
		default: // exe
			shellExec(dl, t.Args)
			runs = append(runs, t.Name)
			done = append(done, t.Name)
		}
		if t.Version != "" {
			st.Installed[t.Name] = t.Version
		} else {
			st.Installed[t.Name] = "설치됨"
		}
	}
	saveState()
	msg := ""
	if len(done) > 0 {
		msg += "설치 완료: " + strings.Join(done, ", ")
	}
	if len(runs) > 0 {
		msg += "\n(설치 프로그램 창이 열리면 안내에 따라 마무리하세요)"
	}
	if len(errs) > 0 {
		msg += "\n실패: " + strings.Join(errs, "; ")
	}
	return strings.TrimSpace(msg), nil
}
