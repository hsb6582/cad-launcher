package main

// PAVQ.lsp 가 "--pavq-fill <집계CSV경로>" 인자로 CAD런처.exe 를 호출하면
// 그 PAVQ_집계_*.csv 를 복구수량산출서_양식.xlsx 에 채운 뒤 같은 폴더에
// 복구수량산출서_<도면명>.xlsx 로 저장하고 엑셀로 바로 연다.
// (예전 PAVQ_FORM.exe/py + C:\MATX-Tools 설치를 대체)

import (
	_ "embed"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"
)

//go:embed assets/pavq_template.xlsx
var pavqTemplateXlsx []byte

const pavqLogName = "pavq_form_log.txt"

func pavqLog(dir string, format string, a ...interface{}) {
	line := time.Now().Format("2006-01-02 15:04:05") + "  " + fmt.Sprintf(format, a...) + "\r\n"
	f, err := os.OpenFile(filepath.Join(dir, pavqLogName), os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		return
	}
	defer f.Close()
	_, _ = f.WriteString(line)
}

// csvPath: PAVQ_집계_<도면명>.csv 의 전체 경로. 성공 0, 실패 1 (콘솔이 없어 결과는 로그 파일로 확인).
func runPavqFill(csvPath string) int {
	csvPath = strings.TrimSpace(csvPath)
	if csvPath == "" {
		return 1
	}
	dir := filepath.Dir(csvPath)
	base := strings.TrimSuffix(filepath.Base(csvPath), filepath.Ext(csvPath))
	base = strings.TrimPrefix(base, "PAVQ_집계_")

	csvBytes, err := os.ReadFile(csvPath)
	if err != nil {
		pavqLog(dir, "[실패] %s 를 읽을 수 없습니다: %v", csvPath, err)
		return 1
	}
	// PAVQ.lsp 가 AutoLISP open/write-line 으로 쓴 파일이라 CP949(한글 윈도우 코드페이지)로
	// 저장돼 있음 - UTF-8 문자열로 바꿔서 넘김.
	out, warnings, err := pavqBuildExcel(pavqTemplateXlsx, fromCP949(csvBytes), base)
	for _, w := range warnings {
		pavqLog(dir, "[경고] %s", w)
	}
	if err != nil {
		pavqLog(dir, "[실패] 엑셀 생성 중 오류: %v", err)
		return 1
	}
	outPath := filepath.Join(dir, "복구수량산출서_"+base+".xlsx")
	if err := os.WriteFile(outPath, out, 0644); err != nil {
		pavqLog(dir, "[실패] %s 저장 실패: %v", outPath, err)
		return 1
	}
	pavqLog(dir, "완료: %s 생성 (경고 %d건)", outPath, len(warnings))
	c(pShellExecuteW, 0, uintptr(P(ws("open"))), uintptr(P(ws(outPath))), 0, 0, SW_SHOWNORMAL)
	return 0
}
