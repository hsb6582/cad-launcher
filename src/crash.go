package main

// 오류 기록 (crash.log, 런처 폴더)
//   런처가 오류로 꺼질 때 어느 코드에서 무슨 오류였는지 남긴다. 원인을 찾을 때 이 파일을 받아 본다.
//   - 창 메시지 처리 중 오류(panic): 시각 · 프로그램 · 그리기 자원 개수(GDI/USER) · 호출 경로를 쓰고 종료
//   - 되살릴 수 없는 오류(동시 접근 등 Go 실행기 오류, 메모리 접근 오류): debug.SetCrashOutput 으로 그대로 기록
//   런처를 다시 켰을 때 최근(7일 안) 기록이 있으면 실행 기록 줄에 안내한다.

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime/debug"
	"time"
)

var (
	crashPath          string
	crashNotice        bool
	pGetGuiResources   = user32.NewProc("GetGuiResources")
	pGetCurrentProcess = kernel32.NewProc("GetCurrentProcess")
)

func setupCrashLog() {
	crashPath = filepath.Join(appDir, "crash.log")
	if fi, err := os.Stat(crashPath); err == nil && fi.Size() > 0 && time.Since(fi.ModTime()) < 7*24*time.Hour {
		crashNotice = true
	}
	debug.SetTraceback("all")
	f, err := os.OpenFile(crashPath, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0644)
	if err != nil {
		return
	}
	_ = debug.SetCrashOutput(f, debug.CrashOptions{}) // 파일을 복제해 쓰므로 여기서 닫아도 됨
	f.Close()
}

// 그리기 자원 개수 (GDI 개체 / USER 개체) - 1만 개 가까이면 자원 누수
func guiResources() (int, int) {
	p := c(pGetCurrentProcess)
	return int(c(pGetGuiResources, p, 0)), int(c(pGetGuiResources, p, 1))
}

// 창 처리 함수 맨 앞에서 defer guardCrash() : 오류가 나면 기록하고 종료
func guardCrash() {
	r := recover()
	if r == nil {
		return
	}
	gdi, usr := guiResources()
	msg := fmt.Sprintf("==== %s  %s  (GDI %d, USER %d) ====\npanic: %v\n\n%s\n",
		time.Now().Format("2006-01-02 15:04:05"), exeRepoName, gdi, usr, r, debug.Stack())
	if f, err := os.OpenFile(crashPath, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0644); err == nil {
		f.WriteString(msg)
		f.Close()
	}
	os.Exit(2)
}

// 켤 때 (실행 기록 칸을 만든 뒤): 최근에 비정상 종료된 기록이 있으면 안내
func noticeCrashLog() {
	if crashNotice {
		logf(T("crash.001"), crashPath)
	}
}
