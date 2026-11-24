package main

// MATX.lsp 가 "--matx-fill <출력폴더>" 인자로 CAD런처.exe 를 호출하면
// (출력폴더)\excel_matched.csv 를 읽어 자재내역.xlsx 양식에 채운 뒤
// (출력폴더)\자재내역_결과.xlsx 로 저장하고 엑셀로 바로 연다.
// (예전 mapping_engine.exe + run_after_matx.bat + 파이썬 의존을 대체)

import (
	_ "embed"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"
)

//go:embed assets/matx_template.xlsx
var matxTemplateXlsx []byte

const matxResultName = "자재내역_결과.xlsx"
const matxCsvName = "excel_matched.csv"
const matxLogName = "auto_matx_log.txt"

func matxLog(dir string, format string, a ...interface{}) {
	line := time.Now().Format("2006-01-02 15:04:05") + "  " + fmt.Sprintf(format, a...) + "\r\n"
	f, err := os.OpenFile(filepath.Join(dir, matxLogName), os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		return
	}
	defer f.Close()
	_, _ = f.WriteString(line)
}

// MATX.lsp가 넘겨주는 출력 폴더(도면 폴더\MATX\) 하나를 받아 처리.
// 성공하면 0, 실패하면 1을 반환 (exe 자체는 콘솔이 없어서 결과는 auto_matx_log.txt로 확인).
func runMatxFill(dir string) int {
	dir = strings.TrimSpace(dir)
	if dir == "" {
		return 1
	}
	csvPath := filepath.Join(dir, matxCsvName)
	csvBytes, err := os.ReadFile(csvPath)
	if err != nil {
		matxLog(dir, "[실패] %s 를 읽을 수 없습니다: %v", csvPath, err)
		return 1
	}
	out, warnings, err := matxBuildExcel(matxTemplateXlsx, string(csvBytes))
	for _, w := range warnings {
		matxLog(dir, "[경고] %s", w)
	}
	if err != nil {
		matxLog(dir, "[실패] 엑셀 생성 중 오류: %v", err)
		return 1
	}
	outPath := filepath.Join(dir, matxResultName)
	if err := os.WriteFile(outPath, out, 0644); err != nil {
		matxLog(dir, "[실패] %s 저장 실패: %v", outPath, err)
		return 1
	}
	matxLog(dir, "완료: %s 생성 (경고 %d건)", outPath, len(warnings))
	c(pShellExecuteW, 0, uintptr(P(ws("open"))), uintptr(P(ws(outPath))), 0, 0, SW_SHOWNORMAL)
	return 0
}
