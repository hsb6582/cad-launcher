package main

import (
	"os"
	"path/filepath"
	"strings"
)

var (
	exePath, appDir, catalogPath, statePath, optPath, lspDir string
)

func initPaths() {
	exePath, _ = os.Executable()
	appDir = filepath.Dir(exePath)
	catalogPath = filepath.Join(appDir, "catalog.json")
	// 실제 런처와 같은 폴더를 쓰지만, launcher_state.json은 공유하지 않는다
	// (이 미리보기 전용 설정 파일을 따로 써서 실제 런처 설정을 건드리지 않음)
	statePath = filepath.Join(appDir, "launcher_state_preview.json")
	lspDir = filepath.Join(appDir, "lsp")
	tmp := os.Getenv("TEMP")
	if tmp == "" {
		tmp = os.TempDir()
	}
	optPath = filepath.Join(tmp, "cad_launcher_opt.txt")
}

func absPath(p string) string {
	if p == "" || filepath.IsAbs(p) {
		return p
	}
	return filepath.Join(appDir, filepath.FromSlash(p))
}

func lispPath(p string) string { return strings.ReplaceAll(filepath.Clean(absPath(p)), "\\", "/") }
