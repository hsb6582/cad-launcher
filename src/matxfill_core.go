package main

// MATX 결과(excel_matched.csv, 행=엑셀 행번호 8~332 / 열=도면번호)를
// 자재내역.xlsx 템플릿의 "자재수량" 시트 G8 이하에 그대로 채워 넣는다.
// (예전 mapping_engine.exe + run_after_matx.bat 이 하던 일을 Go로 통합)
//
// 이 파일은 Win32 호출이 전혀 없는 순수 로직만 담아서, 다른 OS에서도
// go build/go test 로 바로 돌려볼 수 있게 분리해 둔 것 (실제 실행 파일은
// Windows 전용이라 matx.go 쪽에서 이 함수를 불러 씀).

import (
	"archive/zip"
	"bytes"
	"fmt"
	"io"
	"regexp"
	"strconv"
	"strings"
)

// 엑셀 템플릿의 "자재수량" 시트 G6:AT6 에 있는 도면번호 열 순서.
// MATX.lsp 의 MATX-DRAWING-ORDER-BASE 와 반드시 같은 순서여야 함.
var matxDrawingOrderBase = []string{
	"MP-001", "MP-002", "MP-003", "MP-004", "MP-005", "MP-006", "MP-007", "MP-008", "MP-009", "MP-010", "MP-011",
	"LP-001", "LP-002", "LP-003", "LP-004", "LP-005", "LP-006", "LP-007", "LP-008", "LP-009", "LP-010",
	"LP-011", "LP-012", "LP-013", "LP-014", "LP-015", "LP-016", "LP-017", "LP-018", "LP-019", "LP-020",
	"LP-021", "LP-022", "LP-023", "LP-024", "LP-025", "LP-026", "LP-027", "LP-028", "LP-029",
}

const matxFirstCol = 7 // G열 (A=1)

// 스프레드시트 열 번호(1=A, 7=G, 27=AA ...) → 열 문자
func colLetters(n int) string {
	s := ""
	for n > 0 {
		n--
		s = string(rune('A'+n%26)) + s
		n /= 26
	}
	return s
}

func matxDrawingColumn() map[string]string {
	m := map[string]string{}
	for i, dn := range matxDrawingOrderBase {
		m[dn] = colLetters(matxFirstCol + i)
	}
	return m
}

// excel_matched.csv 한 줄: "행,MP-001값,MP-002값,...". 값은 빈칸, 정수/소수 문자열,
// 또는 "=1+2+3" 형태의 수식 문자열뿐이라 콤마·따옴표 이스케이프가 필요 없음(matx-fmt-num 참고).
func parseMatxCSV(csvText string) (drawingOrder []string, rows map[int][]string, err error) {
	lines := strings.Split(strings.ReplaceAll(csvText, "\r\n", "\n"), "\n")
	rows = map[int][]string{}
	first := true
	for _, line := range lines {
		line = strings.TrimRight(line, "\r")
		if strings.TrimSpace(line) == "" {
			continue
		}
		fields := strings.Split(line, ",")
		if first {
			// 첫 칸은 "행"이라는 한글 머리글인데, MATX.lsp 가 AutoLISP open/write-line 으로
			// 쓴 파일이라 윈도우 한글 코드페이지(CP949)로 저장돼 있어 UTF-8 "행"과 바이트가
			// 다름. 이 칸 값 자체는 어디에도 쓰이지 않으므로 내용은 보지 않고 첫 줄을 그냥
			// 머리글로 받아들인다 (도면번호 칸이 하나도 없으면만 오류로 봄).
			if len(fields) < 2 {
				return nil, nil, fmt.Errorf("CSV 헤더에 도면번호 칸이 없습니다: %q", line)
			}
			drawingOrder = fields[1:]
			first = false
			continue
		}
		r, cerr := strconv.Atoi(strings.TrimSpace(fields[0]))
		if cerr != nil {
			continue // 행번호가 아닌 줄은 무시
		}
		rows[r] = fields[1:]
	}
	if first {
		return nil, nil, fmt.Errorf("CSV에 헤더 줄이 없습니다")
	}
	return drawingOrder, rows, nil
}

type matxEdit struct {
	ref string // 예: "G8"
	val string // 숫자 문자열 또는 "=1+2+3"
}

// excel_matched.csv 내용을 분석해서 (셀, 값) 목록과 템플릿에 없는 도면번호 경고를 만든다.
func matxBuildEdits(csvText string) (edits []matxEdit, warnings []string, err error) {
	drawingOrder, rows, err := parseMatxCSV(csvText)
	if err != nil {
		return nil, nil, err
	}
	colOf := matxDrawingColumn()
	unknown := map[string]bool{}
	for r, fields := range rows {
		for j, dn := range drawingOrder {
			if j >= len(fields) {
				break
			}
			val := strings.TrimSpace(fields[j])
			if val == "" {
				continue
			}
			col, ok := colOf[dn]
			if !ok {
				unknown[dn] = true
				continue
			}
			edits = append(edits, matxEdit{ref: fmt.Sprintf("%s%d", col, r), val: val})
		}
	}
	for dn := range unknown {
		warnings = append(warnings, "도면번호 '"+dn+"' 은 엑셀 양식(G6:AT6)에 없는 열이라 자동 반영을 건너뜀 (excel_matched.csv 를 열어 수동으로 붙여넣어 주세요)")
	}
	return edits, warnings, nil
}

var matxCellSelfClose = regexp.MustCompile(`<c r="([A-Z]+[0-9]+)"([^>]*)/>`)
var matxCalcPr = regexp.MustCompile(`<calcPr([^>]*)/>`)

// 빈 셀 하나를 숫자 또는 수식이 들어간 셀로 바꾼다. s=".." 같은 기존 속성(서식)은 그대로 둠.
func matxApplyCellEdits(sheetXML string, edits map[string]string) (string, []string) {
	applied := map[string]bool{}
	out := matxCellSelfClose.ReplaceAllStringFunc(sheetXML, func(m string) string {
		sub := matxCellSelfClose.FindStringSubmatch(m)
		ref, attrs := sub[1], sub[2]
		val, ok := edits[ref]
		if !ok {
			return m
		}
		applied[ref] = true
		if strings.HasPrefix(val, "=") {
			return `<c r="` + ref + `"` + attrs + `><f>` + val[1:] + `</f><v>0</v></c>`
		}
		return `<c r="` + ref + `"` + attrs + `><v>` + val + `</v></c>`
	})
	var missed []string
	for ref := range edits {
		if !applied[ref] {
			missed = append(missed, ref)
		}
	}
	return out, missed
}

// 열면 바로 재계산하도록 fullCalcOnLoad="1" 을 추가 (안 그러면 수식 칸이 캐시된 0으로 보일 수 있음)
func matxForceFullCalcOnLoad(workbookXML string) string {
	if strings.Contains(workbookXML, "fullCalcOnLoad") {
		return workbookXML
	}
	return matxCalcPr.ReplaceAllString(workbookXML, `<calcPr$1 fullCalcOnLoad="1"/>`)
}

// templateXlsx(embed 된 자재내역.xlsx 원본)에 excel_matched.csv 내용을 채워서
// 결과 xlsx 바이트를 돌려준다.
func matxBuildExcel(templateXlsx []byte, csvText string) (outBytes []byte, warnings []string, err error) {
	edits, warn, err := matxBuildEdits(csvText)
	warnings = append(warnings, warn...)
	if err != nil {
		return nil, warnings, err
	}
	editMap := map[string]string{}
	for _, e := range edits {
		editMap[e.ref] = e.val
	}

	zr, err := zip.NewReader(bytes.NewReader(templateXlsx), int64(len(templateXlsx)))
	if err != nil {
		return nil, warnings, fmt.Errorf("템플릿 xlsx 열기 실패: %w", err)
	}

	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)
	for _, f := range zr.File {
		rc, err := f.Open()
		if err != nil {
			return nil, warnings, fmt.Errorf("템플릿 안 %s 읽기 실패: %w", f.Name, err)
		}
		data, err := io.ReadAll(rc)
		rc.Close()
		if err != nil {
			return nil, warnings, fmt.Errorf("템플릿 안 %s 읽기 실패: %w", f.Name, err)
		}
		switch f.Name {
		case "xl/worksheets/sheet1.xml":
			s, missed := matxApplyCellEdits(string(data), editMap)
			data = []byte(s)
			for _, ref := range missed {
				warnings = append(warnings, "셀 "+ref+" 을 템플릿에서 찾지 못해 값을 못 넣었습니다 (양식이 바뀌었을 수 있음)")
			}
		case "xl/workbook.xml":
			data = []byte(matxForceFullCalcOnLoad(string(data)))
		}
		w, err := zw.Create(f.Name)
		if err != nil {
			return nil, warnings, err
		}
		if _, err := w.Write(data); err != nil {
			return nil, warnings, err
		}
	}
	if err := zw.Close(); err != nil {
		return nil, warnings, err
	}
	return buf.Bytes(), warnings, nil
}
