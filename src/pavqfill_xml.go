package main

// sheet1.xml / workbook.xml 의 조각(행, 병합, 조건부서식, 화면보기, 인쇄영역)을 고쳐 끼우는
// 텍스트 수술 도구들 + 요약표(summary()) 빌더.

import (
	"fmt"
	"regexp"
	"strconv"
	"strings"
)

// sheetData 안에서 r>=firstRow 인 기존 <row> 들을 모두 지우고, 그 자리(= </sheetData> 바로 앞)에
// newRowsXML 을 끼워 넣는다.
func pqReplaceRows(sheetXML string, firstRow int, newRowsXML string) string {
	re := regexp.MustCompile(`<row r="(\d+)"[^>]*>.*?</row>`)
	sheetXML = re.ReplaceAllStringFunc(sheetXML, func(m string) string {
		rm := regexp.MustCompile(`<row r="(\d+)"`).FindStringSubmatch(m)
		n, _ := strconv.Atoi(rm[1])
		if n >= firstRow {
			return ""
		}
		return m
	})
	return strings.Replace(sheetXML, "</sheetData>", newRowsXML+"</sheetData>", 1)
}

// <c r="{letter}{row}" ...> 의 s= 속성만 newStyle 로 바꾼다 (나머지 내용은 그대로 둠).
func pqSetCellStyle(sheetXML string, ref string, newStyle int) string {
	re := regexp.MustCompile(`(<c r="` + ref + `")(\s+s="\d+")?([^>]*?)(/?>)`)
	return re.ReplaceAllString(sheetXML, `${1} s="`+strconv.Itoa(newStyle)+`"${3}${4}`)
}

func pqApplyHeaderFillEdits(sheetXML string, row int, edits map[int]int) string {
	for col, style := range edits {
		sheetXML = pqSetCellStyle(sheetXML, pqColLetters(col)+strconv.Itoa(row), style)
	}
	return sheetXML
}

// A3 같은, 이미 있는(보통 빈) 칸을 텍스트 칸으로 바꾼다 (서식은 그대로 유지).
func pqSetHeaderCellText(sheetXML, ref, text string) string {
	re := regexp.MustCompile(`<c r="` + ref + `"(\s+s="(\d+)")?[^>]*?(?:/>|>.*?</c>)`)
	m := re.FindStringSubmatch(sheetXML)
	style := 0
	if m != nil && m[2] != "" {
		style, _ = strconv.Atoi(m[2])
	}
	return re.ReplaceAllLiteralString(sheetXML, pqCStr(ref, style, "▶ 공사명 : "+text))
}

// mergeCells : min_row>=7 인 기존 항목(템플릿의 "틀" 영역)은 버리고, 1~6행 머리글 병합은 그대로 두고,
// 새로 만든 데이터/합계/비고/요약표 병합을 더한다.
func pqRewriteMergeCells(sheetXML string, add []string) string {
	re := regexp.MustCompile(`<mergeCells[^>]*>(.*?)</mergeCells>`)
	m := re.FindStringSubmatch(sheetXML)
	if m == nil {
		return sheetXML
	}
	var kept []string
	for _, mc := range regexp.MustCompile(`<mergeCell ref="([^"]+)"/>`).FindAllStringSubmatch(m[1], -1) {
		ref := mc[1]
		rowPart := strings.SplitN(ref, ":", 2)[0]
		rm := regexp.MustCompile(`\d+`).FindString(rowPart)
		n, _ := strconv.Atoi(rm)
		if n < pqFirstRow {
			kept = append(kept, ref)
		}
	}
	kept = append(kept, add...)
	var sb strings.Builder
	sb.WriteString(fmt.Sprintf(`<mergeCells count="%d">`, len(kept)))
	for _, ref := range kept {
		sb.WriteString(`<mergeCell ref="` + ref + `"/>`)
	}
	sb.WriteString(`</mergeCells>`)
	return re.ReplaceAllLiteralString(sheetXML, sb.String())
}

// 유일하게 있는 H7:H81 류의 데이터영역 조건부서식 범위를 새 마지막 데이터행(last)까지로 늘림.
func pqRewriteConditionalFormatting(sheetXML string, last int) string {
	re := regexp.MustCompile(`<conditionalFormatting sqref="H\d+:H\d+">`)
	return re.ReplaceAllString(sheetXML, fmt.Sprintf(`<conditionalFormatting sqref="H%d:H%d">`, pqFirstRow, last))
}

// 화면 보기를 A1 로 되돌리고 7행(G7)부터 스크롤되도록 고정(틀고정)한다.
func pqRewriteSheetViews(sheetXML string) string {
	re := regexp.MustCompile(`<sheetViews>.*?</sheetViews>`)
	m := re.FindStringSubmatch(sheetXML)
	if m == nil {
		return sheetXML
	}
	attrs := "tabSelected=\"1\" view=\"pageBreakPreview\" topLeftCell=\"A1\" zoomScaleNormal=\"100\" zoomScaleSheetLayoutView=\"100\" workbookViewId=\"0\""
	if am := regexp.MustCompile(`<sheetView\b([^>]*)>`).FindStringSubmatch(m[0]); am != nil {
		kept := am[1]
		for _, a := range []string{"tabSelected", "view", "topLeftCell", "zoomScaleNormal", "zoomScaleSheetLayoutView", "workbookViewId"} {
			kept = regexp.MustCompile(a+`="[^"]*"`).ReplaceAllString(kept, "")
		}
		attrs = strings.TrimSpace(attrs + " " + strings.TrimSpace(kept))
	}
	newBlock := `<sheetViews><sheetView ` + attrs + `>` +
		`<pane xSplit="6" ySplit="6" topLeftCell="G7" activePane="bottomRight" state="frozen"/>` +
		`<selection pane="topRight"/><selection pane="bottomLeft"/>` +
		`<selection pane="bottomRight" activeCell="G7" sqref="G7"/>` +
		`</sheetView></sheetViews>`
	return re.ReplaceAllLiteralString(sheetXML, newBlock)
}

// workbook.xml 의 _xlnm.Print_Area 정의 이름 값을 새 마지막 행까지로 바꾼다.
func pqRewritePrintArea(workbookXML string, end int) string {
	sheetName := "복구수량산출서"
	if m := regexp.MustCompile(`<sheet name="([^"]+)"`).FindStringSubmatch(workbookXML); m != nil {
		sheetName = m[1]
	}
	re := regexp.MustCompile(`<definedName name="_xlnm\.Print_Area"[^>]*>[^<]*</definedName>`)
	repl := fmt.Sprintf(`<definedName name="_xlnm.Print_Area" localSheetId="0">'%s'!$A$1:$%s$%d</definedName>`, sheetName, pqLastCol, end)
	if re.MatchString(workbookXML) {
		return re.ReplaceAllLiteralString(workbookXML, repl)
	}
	return strings.Replace(workbookXML, "</definedNames>", repl+"</definedNames>", 1)
}

// ---------------------------------------------------------------- 요약표 (summary())

func pqBuildSummary(ss *pqStyleSheet, csv *pqCSV, top, r0, r1 int) (rows []*pqRowBuf, merges []string, end int) {
	box := ss.addBorder(pqBoxBorderXML())
	headFill := pqFindOrAddFill(ss, "FFDDEBF7")
	totFill := pqFindOrAddFill(ss, "FFF2F2F2")
	fontBoldTitle := ss.addFont(pqFontXML(true, 12))
	fontBold := ss.addFont(pqFontXML(true, 10))
	fontNorm := ss.addFont(pqFontXML(false, 10))
	numFmtID, ok := pqFindNumFmt(ss, `#,##0.0;-#,##0.0;&quot;-&quot;`)
	if !ok {
		numFmtID = ss.addNumFmt(`#,##0.0;-#,##0.0;&quot;-&quot;`)
	}

	xfPlain := func(fontID, fillID int, bold bool) int {
		b := ""
		if bold {
			b = ` applyFont="1"`
		}
		return ss.addCellXf(fmt.Sprintf(`<xf numFmtId="0" fontId="%d" fillId="%d" borderId="%d" xfId="0"%s applyBorder="1"/>`, fontID, fillID, box, b))
	}
	xfCenterWrap := func(fontID, fillID, numFmt int, bold bool) int {
		b := ""
		if bold {
			b = ` applyFont="1"`
		}
		nf := ""
		nfApply := ""
		if numFmt != 0 {
			nf = fmt.Sprintf(` numFmtId="%d"`, numFmt)
			nfApply = ` applyNumberFormat="1"`
		} else {
			nf = ` numFmtId="0"`
		}
		return ss.addCellXf(fmt.Sprintf(`<xf%s fontId="%d" fillId="%d" borderId="%d" xfId="0"%s%s applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf>`,
			nf, fontID, fillID, box, b, nfApply))
	}

	titleStyle := ss.addCellXf(fmt.Sprintf(`<xf numFmtId="0" fontId="%d" fillId="0" borderId="0" xfId="0" applyFont="1"/>`, fontBoldTitle))
	headStyle := xfCenterWrap(fontBold, headFill, 0, true)
	fillerStyle := xfPlain(0, 0, false)
	labelStyle := xfCenterWrap(fontNorm, 0, 0, false)
	valueStyle := xfCenterWrap(fontNorm, 0, numFmtID, false)
	totalLineStyle := xfCenterWrap(fontBold, 0, numFmtID, true)
	totalLabelStyle := ss.addCellXf(fmt.Sprintf(`<xf numFmtId="0" fontId="%d" fillId="%d" borderId="%d" xfId="0" applyFont="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf>`, fontBold, totFill, box))
	totalValueStyle := xfCenterWrap(fontBold, totFill, numFmtID, true)

	// 관경 목록 (CSV 원래 순서, 압력+관경값+단위 조합마다 1개)
	type pipeKey struct {
		pr, unit string
		dia      float64
	}
	var pipes []pipeKey
	seen := map[pipeKey]bool{}
	for _, r := range csv.data {
		if len(r) < 5 {
			continue
		}
		dia, ok := pqNum(r[3])
		if !ok {
			continue
		}
		k := pipeKey{strings.TrimSpace(r[2]), strings.TrimSpace(r[4]), dia}
		if !seen[k] {
			seen[k] = true
			pipes = append(pipes, k)
		}
	}

	type col struct{ name, lenCol string }
	var cols []col
	for _, name := range pqSummaryOrder {
		for _, rule := range pqPaveMap {
			if rule.label == name {
				cols = append(cols, col{name, rule.lenCol})
			}
		}
	}
	// 실제로 쓰인 열만 (G7:AT{last} 사이에 값이 하나라도 있는 열)
	hasValue := map[string]bool{}
	// (호출부에서 이미 지은 데이터 행들을 넘겨받지 않으므로, data CSV 자체에 그 포장 길이값이 있는지로 판단)
	for _, r := range csv.data {
		for _, k := range csv.kinds {
			if k.lenIdx >= len(r) {
				continue
			}
			if v, ok, _ := pqParts(r[k.lenIdx]); ok && v != 0 {
				if tg := pqPaveTarget(k.name); tg != nil {
					hasValue[tg.lenCol] = true
				}
			}
		}
	}
	var used []col
	for _, c := range cols {
		if hasValue[c.lenCol] {
			used = append(used, c)
		}
	}
	if len(used) == 0 && len(cols) >= 2 {
		used = cols[:2]
	}

	rows = append(rows, &pqRowBuf{row: top, cells: map[int]string{4: pqCStr("D"+itoa(top), titleStyle, "■ 포장구분별 연장 요약 (M)")}})

	h := top + 1
	c0 := 4 // D
	heads := append([]string{"관경"}, func() []string {
		var s []string
		for _, u := range used {
			s = append(s, u.name)
		}
		return s
	}()...)
	heads = append(heads, "계")

	merges = append(merges, fmt.Sprintf("%s%d:%s%d", pqColLetters(c0), h, pqColLetters(c0+2), h))
	pos := []int{c0}
	c := c0 + 3
	for range heads[1:] {
		merges = append(merges, fmt.Sprintf("%s%d:%s%d", pqColLetters(c), h, pqColLetters(c+1), h))
		pos = append(pos, c)
		c += 2
	}
	headRow := &pqRowBuf{row: h, ht: "22", cells: map[int]string{}}
	for i, p := range pos {
		if i == 0 {
			headRow.set(p, pqCStr(pqColLetters(p)+itoa(h), headStyle, heads[i]))
			headRow.set(p+1, pqCEmpty(pqColLetters(p+1)+itoa(h), fillerStyle))
			headRow.set(p+2, pqCEmpty(pqColLetters(p+2)+itoa(h), fillerStyle))
		} else {
			headRow.set(p, pqCStr(pqColLetters(p)+itoa(h), headStyle, heads[i]))
			headRow.set(p+1, pqCEmpty(pqColLetters(p+1)+itoa(h), fillerStyle))
		}
	}
	rows = append(rows, headRow)

	for i, pk := range pipes {
		R := h + 1 + i
		rb := &pqRowBuf{row: R, ht: "20", cells: map[int]string{}}
		merges = append(merges, fmt.Sprintf("%s%d:%s%d", pqColLetters(c0), R, pqColLetters(c0+2), R))
		lab := fmt.Sprintf("%s %s%s", pk.pr, pqIntOrNum(pk.dia), pk.unit)
		rb.set(c0, pqCStr(pqColLetters(c0)+itoa(R), labelStyle, lab))
		rb.set(c0+1, pqCEmpty(pqColLetters(c0+1)+itoa(R), fillerStyle))
		rb.set(c0+2, pqCEmpty(pqColLetters(c0+2)+itoa(R), fillerStyle))
		var sumParts []string
		for j, u := range used {
			p := pos[1+j]
			merges = append(merges, fmt.Sprintf("%s%d:%s%d", pqColLetters(p), R, pqColLetters(p+1), R))
			diaLit := pqIntOrNum(pk.dia)
			formula := fmt.Sprintf("SUMIF($D$%d:$D$%d,%s,$%s$%d:$%s$%d)", r0, r1, diaLit, u.lenCol, r0, u.lenCol, r1)
			rb.set(p, pqCFormula(pqColLetters(p)+itoa(R), valueStyle, formula))
			rb.set(p+1, pqCEmpty(pqColLetters(p+1)+itoa(R), fillerStyle))
			sumParts = append(sumParts, pqColLetters(p)+itoa(R))
		}
		p := pos[len(pos)-1]
		merges = append(merges, fmt.Sprintf("%s%d:%s%d", pqColLetters(p), R, pqColLetters(p+1), R))
		rb.set(p, pqCFormula(pqColLetters(p)+itoa(R), totalLineStyle, strings.Join(sumParts, "+")))
		rb.set(p+1, pqCEmpty(pqColLetters(p+1)+itoa(R), fillerStyle))
		rows = append(rows, rb)
	}

	R := h + 1 + len(pipes)
	rb := &pqRowBuf{row: R, ht: "22", cells: map[int]string{}}
	merges = append(merges, fmt.Sprintf("%s%d:%s%d", pqColLetters(c0), R, pqColLetters(c0+2), R))
	rb.set(c0, pqCStr(pqColLetters(c0)+itoa(R), totalLabelStyle, "합 계"))
	rb.set(c0+1, pqCEmpty(pqColLetters(c0+1)+itoa(R), fillerStyle))
	rb.set(c0+2, pqCEmpty(pqColLetters(c0+2)+itoa(R), fillerStyle))
	for _, p := range pos[1:] {
		merges = append(merges, fmt.Sprintf("%s%d:%s%d", pqColLetters(p), R, pqColLetters(p+1), R))
		formula := fmt.Sprintf("SUM(%s%d:%s%d)", pqColLetters(p), h+1, pqColLetters(p), R-1)
		rb.set(p, pqCFormula(pqColLetters(p)+itoa(R), totalValueStyle, formula))
		rb.set(p+1, pqCEmpty(pqColLetters(p+1)+itoa(R), fillerStyle))
	}
	rows = append(rows, rb)

	return rows, merges, R
}

func pqFindOrAddFill(ss *pqStyleSheet, rgb string) int {
	re := regexp.MustCompile(`fgColor rgb="` + rgb + `"`)
	for i, f := range ss.fills {
		if re.MatchString(f) {
			return i
		}
	}
	return ss.addFill(pqFillXML(rgb))
}
