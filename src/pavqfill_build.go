package main

// pavqfill_core.go 의 모델/서식 도구를 이용해 실제 시트를 만든다.
// pavq_form.py 의 build()/summary() 를 그대로 옮긴 것.

import (
	"archive/zip"
	"bytes"
	"fmt"
	"io"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

const (
	pqFirstRow = 7
	pqLastCol  = "CQ"
	pqStFirst  = 17
	pqStMid    = 18
	pqStLast   = 19
	pqStSingle = 36
	pqStTotal  = 83
	pqStNote   = 84
)

var pqExcludedSumCols = map[string]bool{
	"J": true, "K": true, "W": true, "X": true, "AA": true, "AB": true, "AS": true,
	"AM": true, "AP": true, "AV": true, "AW": true, "BE": true,
}

func pqEsc(s string) string {
	s = strings.ReplaceAll(s, "&", "&amp;")
	s = strings.ReplaceAll(s, "<", "&lt;")
	s = strings.ReplaceAll(s, ">", "&gt;")
	return s
}

func pqCEmpty(ref string, s int) string {
	if s == 0 {
		return `<c r="` + ref + `"/>`
	}
	return fmt.Sprintf(`<c r="%s" s="%d"/>`, ref, s)
}
func pqCNum(ref string, s int, v float64) string {
	sa := ""
	if s != 0 {
		sa = fmt.Sprintf(` s="%d"`, s)
	}
	return fmt.Sprintf(`<c r="%s"%s><v>%s</v></c>`, ref, sa, pqIntOrNum(v))
}
func pqCFormula(ref string, s int, formula string) string {
	sa := ""
	if s != 0 {
		sa = fmt.Sprintf(` s="%d"`, s)
	}
	return fmt.Sprintf(`<c r="%s"%s><f>%s</f><v>0</v></c>`, ref, sa, pqEsc(formula))
}
func pqCStr(ref string, s int, text string) string {
	sa := ""
	if s != 0 {
		sa = fmt.Sprintf(` s="%d"`, s)
	}
	return fmt.Sprintf(`<c r="%s"%s t="inlineStr"><is><t xml:space="preserve">%s</t></is></c>`, ref, sa, pqEsc(text))
}

// ---------------------------------------------------------------- 도곽/행 빌더

type pqRowBuf struct {
	row   int
	ht    string
	cells map[int]string // col(1-based) -> 완성된 <c .../>
}

func newPqRow(row int, ht string) *pqRowBuf {
	return &pqRowBuf{row: row, ht: ht, cells: map[int]string{}}
}

func (rb *pqRowBuf) set(col int, xml string) { rb.cells[col] = xml }

func (rb *pqRowBuf) render(lastCol int) string {
	var sb strings.Builder
	htAttr := ""
	if rb.ht != "" {
		htAttr = fmt.Sprintf(` ht="%s" customHeight="1"`, rb.ht)
	}
	sb.WriteString(fmt.Sprintf(`<row r="%d"%s>`, rb.row, htAttr))
	for c := 1; c <= lastCol; c++ {
		if x, ok := rb.cells[c]; ok {
			sb.WriteString(x)
		}
	}
	sb.WriteString(`</row>`)
	return sb.String()
}

// ---------------------------------------------------------------- 템플릿에서 읽어야 하는 값들

type pqTemplateInfo struct {
	lastColIdx               int
	donorStyle               map[string]map[int]int // "first"/"mid"/... -> col -> s
	heightFirst, heightTotal string
	sumCols                  []string // 83행에 =SUM.. 이 있던(제외목록 뺀) 열
}

func pqReadTemplate(sheetXML string) (*pqTemplateInfo, error) {
	ti := &pqTemplateInfo{lastColIdx: pqColIndex(pqLastCol), donorStyle: map[string]map[int]int{}}
	rows := map[string]int{"first": pqStFirst, "mid": pqStMid, "last": pqStLast, "single": pqStSingle, "total": pqStTotal, "note": pqStNote}
	for k, r := range rows {
		ti.donorStyle[k] = pqRowStyleMap(sheetXML, r, ti.lastColIdx)
	}
	getHt := func(row int) string {
		re := regexp.MustCompile(`<row r="` + strconv.Itoa(row) + `"([^>]*)>`)
		m := re.FindStringSubmatch(sheetXML)
		if m == nil {
			return ""
		}
		hm := regexp.MustCompile(`ht="([0-9.]+)"`).FindStringSubmatch(m[1])
		if hm == nil {
			return ""
		}
		return hm[1]
	}
	ti.heightFirst = getHt(pqStFirst)
	ti.heightTotal = getHt(pqStTotal)

	// 83행에서 =SUM 으로 시작하는 열 (제외목록 제외)
	re := regexp.MustCompile(`<row r="` + strconv.Itoa(pqStTotal) + `"[^>]*>(.*?)</row>`)
	m := re.FindStringSubmatch(sheetXML)
	if m != nil {
		for _, cm := range regexp.MustCompile(`<c r="([A-Z]+)`+strconv.Itoa(pqStTotal)+`"[^>]*>(?:<f>(SUM[^<]*)</f>)?`).FindAllStringSubmatch(m[1], -1) {
			if cm[2] != "" && !pqExcludedSumCols[cm[1]] {
				ti.sumCols = append(ti.sumCols, cm[1])
			}
		}
	}
	return ti, nil
}

// ---------------------------------------------------------------- 메인 빌드

// csvText: PAVQ_집계_*.csv 내용. baseName: 결과 제목에 쓸 "공사명" (파일명에서 PAVQ_집계_ 접두어를 뗀 것)
func pavqBuildExcel(templateXlsx []byte, csvText, baseName string) (outBytes []byte, warnings []string, err error) {
	csv, err := pqParseCSV(csvText)
	if err != nil {
		return nil, nil, err
	}

	zr, err := zip.NewReader(bytes.NewReader(templateXlsx), int64(len(templateXlsx)))
	if err != nil {
		return nil, nil, fmt.Errorf("템플릿 xlsx 열기 실패: %w", err)
	}
	files := map[string][]byte{}
	var order []string
	for _, f := range zr.File {
		rc, e := f.Open()
		if e != nil {
			return nil, nil, e
		}
		data, e := io.ReadAll(rc)
		rc.Close()
		if e != nil {
			return nil, nil, e
		}
		files[f.Name] = data
		order = append(order, f.Name)
	}
	sheetXML := string(files["xl/worksheets/sheet1.xml"])
	stylesXML := string(files["xl/styles.xml"])
	workbookXML := string(files["xl/workbook.xml"])

	ti, err := pqReadTemplate(sheetXML)
	if err != nil {
		return nil, nil, err
	}
	ss, err := pqLoadStyles(stylesXML)
	if err != nil {
		return nil, nil, err
	}

	yellowFill := ss.addFill(pqFillXML("FFFFFF00"))
	mmFmt, ok := pqFindNumFmt(ss, `#,##0&quot;mm&quot;`)
	if !ok {
		mmFmt = ss.addNumFmt(`#,##0&quot;mm&quot;`)
	}
	aFmt, ok := pqFindNumFmt(ss, `#,##0&quot;A&quot;`)
	if !ok {
		aFmt = ss.addNumFmt(`#,##0&quot;A&quot;`)
	}

	// -------- 도곽(도면)별 묶기 (CSV 순서 유지) --------
	type block struct {
		dwg  string
		rows [][]string
	}
	var blocks []*block
	idxOf := map[string]int{}
	for _, r := range csv.data {
		if len(r) == 0 {
			continue
		}
		i, ok := idxOf[r[0]]
		if !ok {
			i = len(blocks)
			idxOf[r[0]] = i
			blocks = append(blocks, &block{dwg: r[0]})
		}
		blocks[i].rows = append(blocks[i].rows, r)
	}

	mergeNote := map[string][]string{} // dwg -> ["63mm 칼라아스콘 0.3m→A.S.P", ...]
	for _, m := range csv.merges {
		if len(m) >= 6 {
			mergeNote[m[0]] = append(mergeNote[m[0]], fmt.Sprintf("63mm %s %sm→%s", m[3], m[4], m[5]))
		}
	}
	accMap := map[string]map[string][]string{} // dwg -> kind -> [면적/수식, ...]
	for _, a := range csv.accs {
		v := strings.TrimSpace(a[3])
		if len(a) > 4 && strings.TrimSpace(a[4]) != "" {
			v = strings.TrimSpace(a[4])
		}
		if accMap[a[0]] == nil {
			accMap[a[0]] = map[string][]string{}
		}
		kind := strings.TrimSpace(a[1])
		accMap[a[0]][kind] = append(accMap[a[0]][kind], v)
	}

	var mergesOut []string
	memos := &pqMemos{}
	var mism, unknown []string
	var newRows []*pqRowBuf
	row := pqFirstRow

	for _, b := range blocks {
		rs := append([][]string{}, b.rows...)
		sort.SliceStable(rs, func(i, j int) bool {
			vi, _ := pqNum(rs[i][3])
			vj, _ := pqNum(rs[j][3])
			return vi > vj
		})
		n := len(rs)
		for i, r := range rs {
			key := "mid"
			switch {
			case n == 1:
				key = "single"
			case i == 0:
				key = "first"
			case i == n-1:
				key = "last"
			}
			R := row + i
			rb := newPqRow(R, ti.heightFirst)
			styleMap := ti.donorStyle[key]
			for c := 1; c <= ti.lastColIdx; c++ {
				rb.set(c, pqCEmpty(pqColLetters(c)+itoa(R), styleMap[c]))
			}

			dia, diaOK := pqNum(r[3])
			unit := strings.TrimSpace(r[4])

			dCol := pqColIndex("D")
			dStyle := styleMap[dCol]
			if unit == "A" {
				dStyle = ss.withAttr(dStyle, "numFmtId", strconv.Itoa(aFmt))
			} else {
				dStyle = ss.withAttr(dStyle, "numFmtId", strconv.Itoa(mmFmt))
			}
			if diaOK {
				rb.set(dCol, pqCNum("D"+itoa(R), dStyle, dia))
			} else {
				rb.set(dCol, pqCEmpty("D"+itoa(R), dStyle))
			}

			acc := map[string]float64{}
			accParts := map[string][]string{}
			bigW := map[string][2]float64{} // col -> (width, lengthUsedToPick)
			var rem []string

			for _, k := range csv.kinds {
				if k.lenIdx >= len(r) {
					continue
				}
				L, lok, parts := pqParts(r[k.lenIdx])
				if !lok || L == 0 {
					continue
				}
				var W float64
				wok := false
				if k.widIdx >= 0 && k.widIdx < len(r) {
					W, wok = pqNum(r[k.widIdx])
				}
				tg := pqPaveTarget(k.name)
				if tg == nil {
					unknown = append(unknown, fmt.Sprintf("%s %s : %s %sm", b.dwg, dispRow(r), k.name, pqIntOrNum(L)))
					rem = append(rem, fmt.Sprintf("%s %sm", k.name, pqIntOrNum(L)))
					continue
				}
				col := tg.lenCol
				acc[col] += L
				if len(parts) > 0 {
					accParts[col] = append(accParts[col], parts...)
				} else {
					accParts[col] = append(accParts[col], pqNumStr(L))
				}
				if wok {
					if cur, ok := bigW[col]; !ok || L > cur[1] {
						bigW[col] = [2]float64{W, L}
					}
				}
			}

			for _, rule := range pqPaveMap {
				lc := rule.lenCol
				if _, ok := acc[lc]; !ok {
					continue
				}
				lcIdx := pqColIndex(lc)
				if len(accParts[lc]) > 1 {
					rb.set(lcIdx, pqCFormula(lc+itoa(R), styleMap[lcIdx], strings.Join(accParts[lc], "+")))
				} else {
					rb.set(lcIdx, pqCNum(lc+itoa(R), styleMap[lcIdx], round2(acc[lc])))
				}
				if rule.widCol != "" {
					if w, ok := bigW[lc]; ok {
						wcIdx := pqColIndex(rule.widCol)
						rb.set(wcIdx, pqCNum(rule.widCol+itoa(R), styleMap[wcIdx], w[0]))
					}
				}
				if rule.thickCol != "" {
					tcIdx := pqColIndex(rule.thickCol)
					rb.set(tcIdx, pqCNum(rule.thickCol+itoa(R), styleMap[tcIdx], rule.thickVal))
				}
				if rule.volCol != "" {
					vcIdx := pqColIndex(rule.volCol)
					var formula string
					if rule.thickCol != "" {
						formula = fmt.Sprintf("ROUND(%s%d*%s%d*%s%d,2)", lc, R, rule.widCol, R, rule.thickCol, R)
					} else if rule.widCol != "" {
						formula = fmt.Sprintf("ROUND(%s%d*%s%d,2)", lc, R, rule.widCol, R)
					}
					if formula != "" {
						rb.set(vcIdx, pqCFormula(rule.volCol+itoa(R), styleMap[vcIdx], formula))
					}
				}
			}

			hIdx := pqColIndex("H")
			var hParts []string
			for _, c := range pqLenCols {
				hParts = append(hParts, c+itoa(R))
			}

			gIdx := pqColIndex("G")
			key2 := pqMatKeyOf(b.dwg, r[3], unit)
			mq, hasMq := csv.mats[key2]
			tot := 0.0
			for _, v := range acc {
				tot += v
			}
			gStyle, hStyle := styleMap[gIdx], styleMap[hIdx]
			mismatched := false
			if hasMq {
				mismatched = absf(tot-mq) > 0.01
			} else if len(csv.mats) > 0 {
				mismatched = true
			}
			if mismatched {
				// 빨간색이면 메모 표시(빨간 삼각형)가 안 보여서 노란색으로 칠함
				gStyle = ss.withFill(gStyle, yellowFill)
				hStyle = ss.withFill(hStyle, yellowFill)
			}
			switch {
			case hasMq:
				if f, ok := csv.matf[key2]; ok {
					rb.set(gIdx, pqCFormula("G"+itoa(R), gStyle, f))
				} else {
					rb.set(gIdx, pqCNum("G"+itoa(R), gStyle, mq))
				}
				if mismatched {
					memos.add(hIdx, R, fmt.Sprintf("자재내역 %sm / 집계 %sm (차 %sm)\n관로 길이 확인 필요", pqNumStr(mq), pqNumStr(tot), pqNumStr(tot-mq)))
					mism = append(mism, fmt.Sprintf("%s %s : 자재내역 %sm / 집계 %sm (차 %sm)", b.dwg, dispRow(r), pqNumStr(mq), pqNumStr(tot), pqNumStr(tot-mq)))
				}
			case len(csv.mats) > 0:
				rb.set(gIdx, pqCEmpty("G"+itoa(R), gStyle))
				memos.add(hIdx, R, fmt.Sprintf("자재내역에 이 관경 수량이 없음 (집계 %sm)\n관경·자재내역 확인 필요", pqNumStr(tot)))
				mism = append(mism, fmt.Sprintf("%s %s : 자재내역 수량 없음 / 집계 %sm", b.dwg, dispRow(r), pqNumStr(tot)))
			default:
				rb.set(gIdx, pqCEmpty("G"+itoa(R), gStyle))
			}
			rb.set(hIdx, pqCFormula("H"+itoa(R), hStyle, strings.Join(hParts, "+")))

			if diaOK && dia == 63 {
				rem = append(rem, mergeNote[b.dwg]...)
			}
			if len(rem) > 0 {
				lastIdx := pqColIndex(pqLastCol)
				rb.set(lastIdx, pqCStr(pqLastCol+itoa(R), styleMap[lastIdx], strings.Join(rem, ", ")))
			}
			newRows = append(newRows, rb)
		}

		// 횡단보도/과속방지턱/미끄럼방지MMA (도면 첫 행에 기록)
		am := accMap[b.dwg]
		first := newRows[len(newRows)-n]
		firstKey := "first"
		if n == 1 {
			firstKey = "single"
		}
		firstStyle := ti.donorStyle[firstKey]
		for _, kv := range []struct{ kind, col1, col2 string }{{"횡단보도", "BF", "BG"}, {"과속방지턱", "BO", ""}} {
			ar := am[kv.kind]
			if len(ar) == 0 {
				continue
			}
			c1 := pqColIndex(kv.col1)
			var formula string
			if len(ar) == 1 {
				formula = ar[0] + "/4"
			} else {
				formula = "(" + strings.Join(ar, "+") + ")/4"
			}
			first.set(c1, pqCFormula(kv.col1+itoa(row), firstStyle[c1], formula))
			if kv.col2 != "" {
				c2 := pqColIndex(kv.col2)
				first.set(c2, pqCNum(kv.col2+itoa(row), firstStyle[c2], float64(len(ar))))
			}
		}
		if ar := am["미끄럼방지 MMA"]; len(ar) > 0 {
			blIdx := pqColIndex("BL")
			first.set(blIdx, pqCFormula("BL"+itoa(row), firstStyle[blIdx], strings.Join(ar, "+")))
		}
		aIdx := pqColIndex("A")
		first.set(aIdx, pqCStr("A"+itoa(row), firstStyle[aIdx], strings.ReplaceAll(b.dwg, "-", " ")))
		mergesOut = append(mergesOut, fmt.Sprintf("A%d:C%d", row, row+n-1))
		row += n
	}
	for d := range accMap {
		if _, ok := idxOf[d]; !ok {
			unknown = append(unknown, d+" : 횡단보도/과속방지턱이 있으나 집계 행이 없음")
		}
	}

	last := row - 1
	if last < pqFirstRow {
		last = pqFirstRow - 1
	}

	// -------- 합계 행 --------
	T := row
	rbT := newPqRow(T, ti.heightTotal)
	tStyle := ti.donorStyle["total"]
	for c := 1; c <= ti.lastColIdx; c++ {
		rbT.set(c, pqCEmpty(pqColLetters(c)+itoa(T), tStyle[c]))
	}
	aIdx := pqColIndex("A")
	rbT.set(aIdx, pqCStr("A"+itoa(T), tStyle[aIdx], "합 계"))
	mergesOut = append(mergesOut, fmt.Sprintf("A%d:C%d", T, T))
	for _, lc := range ti.sumCols {
		ci := pqColIndex(lc)
		rbT.set(ci, pqCFormula(lc+itoa(T), tStyle[ci], fmt.Sprintf("SUM(%s%d:%s%d)", lc, pqFirstRow, lc, last)))
	}
	newRows = append(newRows, rbT)

	// -------- 비고 행 --------
	N := T + 1
	rbN := newPqRow(N, ti.heightTotal)
	nStyle := ti.donorStyle["note"]
	for c := 1; c <= ti.lastColIdx; c++ {
		rbN.set(c, pqCEmpty(pqColLetters(c)+itoa(N), nStyle[c]))
	}
	rbN.set(aIdx, pqCStr("A"+itoa(N), nStyle[aIdx], "비  고"))
	mergesOut = append(mergesOut, fmt.Sprintf("A%d:C%d", N, N))
	mergesOut = append(mergesOut, fmt.Sprintf("D%d:%s%d", N, pqLastCol, N))
	noteText := strings.Join(firstN(csv.notes, 12), "\n")
	if len(csv.notes) > 12 {
		noteText += fmt.Sprintf("\n… 외 %d건 (PAVQ_오류 파일 참고)", len(csv.notes)-12)
	}
	dIdx := pqColIndex("D")
	noteFont := ss.addFont(pqFontXML(false, 9))
	noteStyle := pqCloneWithAlignFont(ss, nStyle[dIdx], noteFont, `wrapText="1" vertical="top" horizontal="left"`)
	rbN.set(dIdx, pqCStr("D"+itoa(N), noteStyle, noteText))
	newRows = append(newRows, rbN)

	// -------- 요약표 --------
	sumTop := N + 2
	sumRows, sumMerges, sumEnd := pqBuildSummary(ss, csv, sumTop, pqFirstRow, last)
	newRows = append(newRows, sumRows...)
	mergesOut = append(mergesOut, sumMerges...)

	// -------- 노란 머리글 (값 있는 열, H 제외) --------
	usedCols := map[int]bool{}
	for _, rb := range newRows[:len(newRows)-len(sumRows)] { // 데이터+합계+비고 구간만
		for c, x := range rb.cells {
			if c == pqColIndex("H") {
				continue
			}
			if strings.Contains(x, "<v>") || strings.Contains(x, "<f>") {
				usedCols[c] = true
			}
		}
	}
	headerEdits := map[int]int{}
	gIdxMin := pqColIndex("G")
	row6Style := pqRowStyleMap(sheetXML, 6, ti.lastColIdx)
	for c := range usedCols {
		if c < gIdxMin {
			continue
		}
		headerEdits[c] = ss.withFill(row6Style[c], yellowFill)
	}

	// 메모가 달린 H 칸은 노란색 (연장 불일치)
	pqYellowMemoCells(ss, newRows, memos, yellowFill)

	warnings = append(warnings, prefixEach(mism, "자재내역 불일치: ")...)
	warnings = append(warnings, prefixEach(unknown, "양식 열 없음: ")...)

	// -------- sheetData 갈아 끼우기 --------
	var rowsXML strings.Builder
	for _, rb := range newRows {
		rowsXML.WriteString(rb.render(ti.lastColIdx))
	}
	sheetXML = pqReplaceRows(sheetXML, pqFirstRow, rowsXML.String())
	sheetXML = pqApplyHeaderFillEdits(sheetXML, 6, headerEdits)
	sheetXML = pqSetHeaderCellText(sheetXML, "A3", baseName)
	sheetXML = pqRewriteMergeCells(sheetXML, mergesOut)
	sheetXML = pqRewriteConditionalFormatting(sheetXML, last)
	sheetXML = pqRewriteSheetViews(sheetXML)

	stylesXML = ss.render(stylesXML)
	workbookXML = pqRewritePrintArea(workbookXML, sumEnd)
	workbookXML = pqForceFullCalcOnLoad(workbookXML)

	files["xl/worksheets/sheet1.xml"] = []byte(sheetXML)
	files["xl/styles.xml"] = []byte(stylesXML)
	files["xl/workbook.xml"] = []byte(workbookXML)
	pqAttachMemos(files, &order, memos)

	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)
	for _, name := range order {
		w, e := zw.Create(name)
		if e != nil {
			return nil, warnings, e
		}
		if _, e := w.Write(files[name]); e != nil {
			return nil, warnings, e
		}
	}
	if e := zw.Close(); e != nil {
		return nil, warnings, e
	}
	return buf.Bytes(), warnings, nil
}

func pqForceFullCalcOnLoad(workbookXML string) string {
	if strings.Contains(workbookXML, "fullCalcOnLoad") {
		return workbookXML
	}
	re := regexp.MustCompile(`<calcPr([^>]*)/>`)
	return re.ReplaceAllString(workbookXML, `<calcPr$1 fullCalcOnLoad="1"/>`)
}

var pqCellStyleRe = regexp.MustCompile(`^<c r="[A-Z]+\d+"(?: s="(\d+)")?`)

func pqYellowMemoCells(ss *pqStyleSheet, rows []*pqRowBuf, memos *pqMemos, fill int) {
	byRow := map[int]*pqRowBuf{}
	for _, rb := range rows {
		byRow[rb.row] = rb
	}
	for _, m := range memos.list {
		rb := byRow[m.row]
		if rb == nil {
			continue
		}
		x, ok := rb.cells[m.col]
		if !ok {
			continue
		}
		sm := pqCellStyleRe.FindStringSubmatchIndex(x)
		if sm == nil {
			continue
		}
		base := 0
		if sm[2] >= 0 {
			base, _ = strconv.Atoi(x[sm[2]:sm[3]])
		}
		if strings.Contains(ss.xfXML(base), `fillId="`+strconv.Itoa(fill)+`"`) {
			continue // 이미 노란색
		}
		ns := ss.withFill(base, fill)
		ref := pqColLetters(m.col) + itoa(m.row)
		rb.cells[m.col] = fmt.Sprintf(`<c r="%s" s="%d"`, ref, ns) + x[sm[1]:]
	}
}
