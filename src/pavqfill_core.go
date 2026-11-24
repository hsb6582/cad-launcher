package main

// PAVQ_집계_*.csv -> 복구수량산출서_양식.xlsx 채우기
// (예전 PAVQ_FORM.exe/py 가 하던 일을 Go로 통합. pavq_form.py 전체를 참고해 그대로 포팅함 - 규칙이
// 바뀌면 그 파이썬 원본을 기준으로 이 파일도 같이 고쳐야 함)
//
// pavq_form.py 와 다른 점(일부러 단순화한 부분):
//   - 병합 범위 안의 칸마다 자리에 따라 변이 있던 테두리를 전부 "같은 두꺼운 상자" 하나로 통일.
//     (엑셀은 병합된 범위 안쪽 경계선은 그려도 보이지 않으므로 화면상 차이 없음)
//   - 커스텀 숫자서식 ID 는 openpyxl처럼 다시 번호를 매기지 않고 템플릿 끝에 하나만 새로 추가.

import (
	"fmt"
	"math"
	"regexp"
	"strconv"
	"strings"
)

// ---------------------------------------------------------------- CSV 모델

type pqKind struct {
	name           string
	lenIdx, widIdx int // CSV 안에서의 칸 번호 (0부터). widIdx<0 이면 굴착폭 칸 없음.
}

type pqMatKey struct {
	dwg  string
	dia  int // round(num(dia)) 가 없으면 minInt
	unit string
}

const pqNoDia = -1 << 30

type pqCSV struct {
	kinds  []pqKind
	data   [][]string
	notes  []string
	merges [][]string // 도면번호,핸들,관로명길이,병합포장,길이,합산포장
	accs   [][]string // 도면번호,구분,핸들,면적[,수식]
	mats   map[pqMatKey]float64
	matf   map[pqMatKey]string
}

func pqMatKeyOf(dwg, dia, unit string) pqMatKey {
	v, ok := pqNum(dia)
	d := pqNoDia
	if ok {
		d = int(v + 0.5)
		if v < 0 {
			d = -int(-v + 0.5)
		}
	}
	return pqMatKey{strings.TrimSpace(dwg), d, strings.ToUpper(strings.TrimSpace(unit))}
}

// "12.5" -> (12.5, true) / "=4+4" -> (8.0, true) / 빈칸·숫자아님 -> (0, false)
func pqParts(s string) (float64, bool, []string) {
	s = strings.TrimSpace(s)
	if s == "" {
		return 0, false, nil
	}
	if strings.HasPrefix(s, "=") {
		items := []string{}
		for _, it := range strings.Split(s[1:], "+") {
			it = strings.TrimSpace(it)
			if it != "" {
				items = append(items, it)
			}
		}
		sum := 0.0
		for _, it := range items {
			v, err := strconv.ParseFloat(it, 64)
			if err != nil {
				return 0, false, nil
			}
			sum += v
		}
		return sum, true, items
	}
	v, err := strconv.ParseFloat(s, 64)
	if err != nil {
		return 0, false, nil
	}
	return v, true, []string{s}
}

func pqNum(s string) (float64, bool) {
	v, ok, _ := pqParts(s)
	return v, ok
}

// 4.00 -> "4" / 0.50 -> "0.5" (nstr)
func pqNumStr(v float64) string {
	s := strconv.FormatFloat(v, 'f', 2, 64)
	s = strings.TrimRight(s, "0")
	s = strings.TrimSuffix(s, ".")
	if s == "" || s == "-" {
		s = "0"
	}
	return s
}

// 관경 등 "정수면 정수로" 표시
func pqIntOrNum(v float64) string {
	if v == float64(int64(v)) {
		return strconv.FormatInt(int64(v), 10)
	}
	return pqNumStr(v)
}

func pqNorm(s string) string {
	s = strings.ToUpper(s)
	for _, ch := range []string{" ", ".", "'", "`", "-", "\t"} {
		s = strings.ReplaceAll(s, ch, "")
	}
	return s
}

func pqParseCSV(text string) (*pqCSV, error) {
	lines := strings.Split(strings.ReplaceAll(text, "\r\n", "\n"), "\n")
	out := &pqCSV{mats: map[pqMatKey]float64{}, matf: map[pqMatKey]string{}}
	var head []string
	section := "head"
	for _, raw := range lines {
		line := strings.TrimRight(raw, "\r")
		r := strings.Split(line, ",")
		if head == nil {
			head = r
			i := 6
			for i < len(head) && head[i] != "계" {
				widIdx := -1
				if i+1 < len(head) && strings.HasSuffix(head[i+1], "굴착폭(M)") {
					widIdx = i + 1
				}
				out.kinds = append(out.kinds, pqKind{head[i], i, widIdx})
				if widIdx >= 0 {
					i += 2
				} else {
					i++
				}
			}
			section = "data"
			continue
		}
		blank := true
		for _, c := range r {
			if strings.TrimSpace(c) != "" {
				blank = false
				break
			}
		}
		if blank {
			if section == "data" {
				section = "total"
			}
			continue
		}
		switch {
		case strings.HasPrefix(r[0], "[검토 사항]"):
			section = "notes"
			continue
		case strings.HasPrefix(r[0], "[비고"):
			section = "merge"
			continue
		case strings.HasPrefix(r[0], "[포장 부속"):
			section = "acc"
			continue
		case strings.HasPrefix(r[0], "[자재내역 관경별"):
			section = "mat"
			continue
		}
		switch section {
		case "data":
			out.data = append(out.data, r)
		case "notes":
			out.notes = append(out.notes, r[0])
		case "merge":
			if r[0] != "도면번호" {
				out.merges = append(out.merges, r)
			}
		case "acc":
			if r[0] != "도면번호" && len(r) >= 4 {
				out.accs = append(out.accs, r)
			}
		case "mat":
			if r[0] != "도면번호" && len(r) >= 4 {
				v, ok := pqNum(r[3])
				if ok {
					k := pqMatKeyOf(r[0], r[1], r[2])
					out.mats[k] = v
					if len(r) >= 5 && strings.Contains(r[4], "+") {
						out.matf[k] = strings.TrimSpace(r[4])
					}
				}
			}
		}
	}
	if head == nil {
		return nil, fmt.Errorf("CSV가 비어 있습니다")
	}
	return out, nil
}

// ---------------------------------------------------------------- 포장구분 매핑 (PAVE_MAP 그대로)

type pqPaveRule struct {
	words                            []string
	lenCol, widCol, thickCol, volCol string // "" = 없음
	hasThick                         bool
	thickVal                         float64
	label                            string
}

var pqPaveMap = []pqPaveRule{
	{words: []string{"칼라아스콘"}, lenCol: "AR", widCol: "AS", thickCol: "", volCol: "AT", label: "칼라아스콘"},
	{words: []string{"ASP", "아스팔트", "아스콘"}, lenCol: "I", widCol: "J", thickCol: "K", volCol: "L", hasThick: true, thickVal: 0.2, label: "A.S.P"},
	{words: []string{"CONC", "콘크리트"}, lenCol: "V", widCol: "W", thickCol: "X", volCol: "Y", hasThick: true, thickVal: 0.2, label: "CON'C"},
	{words: []string{"보도", "BL", "블럭", "블록"}, lenCol: "AH", label: "보도"},
	{words: []string{"하천"}, lenCol: "AZ", label: "하천"},
	{words: []string{"법면"}, lenCol: "BB", label: "법면"},
	{words: []string{"녹지", "잡종지", "비포장", "사리", "토사", "자갈", "도로개설"}, lenCol: "BD", label: "사리도"},
}

var pqSummaryOrder = []string{"A.S.P", "CON'C", "칼라아스콘", "보도", "하천", "법면", "사리도"}
var pqLenCols = []string{"I", "V", "AH", "AI", "AK", "AR", "AZ", "BA", "BB", "BD"}

func pqPaveTarget(kind string) *pqPaveRule {
	n := pqNorm(kind)
	for i := range pqPaveMap {
		for _, w := range pqPaveMap[i].words {
			if strings.Contains(n, pqNorm(w)) {
				return &pqPaveMap[i]
			}
		}
	}
	return nil
}

// ---------------------------------------------------------------- 스프레드시트 열 문자

func pqColLetters(n int) string { return colLetters(n) } // matxfill_core.go 의 것 재사용

func pqColIndex(letters string) int {
	n := 0
	for _, c := range letters {
		n = n*26 + int(c-'A'+1)
	}
	return n
}

// ---------------------------------------------------------------- 템플릿 행의 칸별 서식(s) 추출

var pqCellTag = regexp.MustCompile(`<c r="([A-Z]+)(\d+)"(?:\s+s="(\d+)")?[^>]*?(?:/>|>.*?</c>)`)

// row 의 1~lastCol 칸 서식 인덱스. XML에 그 칸이 없으면 0(기본 서식).
func pqRowStyleMap(sheetXML string, row, lastCol int) map[int]int {
	out := map[int]int{}
	re := regexp.MustCompile(`<row r="` + strconv.Itoa(row) + `"[^>]*>(.*?)</row>`)
	m := re.FindStringSubmatch(sheetXML)
	if m != nil {
		for _, cm := range pqCellTag.FindAllStringSubmatch(m[1], -1) {
			if cm[2] != strconv.Itoa(row) {
				continue
			}
			col := pqColIndex(cm[1])
			s := 0
			if cm[3] != "" {
				s, _ = strconv.Atoi(cm[3])
			}
			out[col] = s
		}
	}
	for c := 1; c <= lastCol; c++ {
		if _, ok := out[c]; !ok {
			out[c] = 0
		}
	}
	return out
}

// ---------------------------------------------------------------- styles.xml 편집 (append-only)

type pqStyleSheet struct {
	fonts, fills, borders, numFmts, cellXfs                []string // 원본에서 그대로 읽은 항목들(문자열)
	newFonts, newFills, newBorders, newNumFmts, newCellXfs []string
	cellXfAttrs                                            []string       // cellXfs[i] 의 속성 문자열(파싱해 둔 것) - fillId 치환용
	fillClone                                              map[[2]int]int // (baseXfIdx, fillId) -> 새 cellXf idx
}

var pqListRe = func(tag string) *regexp.Regexp {
	return regexp.MustCompile(`<` + tag + ` count="(\d+)"[^>]*>(.*)</` + tag + `>`)
}

func pqSplitTopLevel(body string, itemRe *regexp.Regexp) []string {
	return itemRe.FindAllString(body, -1)
}

var pqFontItemRe = regexp.MustCompile(`<font>.*?</font>`)
var pqFillItemRe = regexp.MustCompile(`<fill>.*?</fill>`)
var pqBorderItemRe = regexp.MustCompile(`<border[^>]*>.*?</border>`)
var pqNumFmtItemRe = regexp.MustCompile(`<numFmt [^/]*/>`)
var pqXfItemRe = regexp.MustCompile(`<xf\b[^>]*?(?:/>|>.*?</xf>)`)

func pqLoadStyles(stylesXML string) (*pqStyleSheet, error) {
	ss := &pqStyleSheet{fillClone: map[[2]int]int{}}
	grab := func(tag string, itemRe *regexp.Regexp) ([]string, error) {
		re := pqListRe(tag)
		m := re.FindStringSubmatch(stylesXML)
		if m == nil {
			return nil, fmt.Errorf("styles.xml 에 <%s> 를 찾지 못함", tag)
		}
		return pqSplitTopLevel(m[2], itemRe), nil
	}
	var err error
	if ss.fonts, err = grab("fonts", pqFontItemRe); err != nil {
		return nil, err
	}
	if ss.fills, err = grab("fills", pqFillItemRe); err != nil {
		return nil, err
	}
	if ss.borders, err = grab("borders", pqBorderItemRe); err != nil {
		return nil, err
	}
	if ss.numFmts, err = grab("numFmts", pqNumFmtItemRe); err != nil {
		ss.numFmts = nil // 없을 수도 있음(옵션 블록)
	}
	if ss.cellXfs, err = grab("cellXfs", pqXfItemRe); err != nil {
		return nil, err
	}
	return ss, nil
}

func (ss *pqStyleSheet) addFont(xml string) int {
	ss.newFonts = append(ss.newFonts, xml)
	return len(ss.fonts) + len(ss.newFonts) - 1
}
func (ss *pqStyleSheet) addFill(xml string) int {
	ss.newFills = append(ss.newFills, xml)
	return len(ss.fills) + len(ss.newFills) - 1
}
func (ss *pqStyleSheet) addBorder(xml string) int {
	ss.newBorders = append(ss.newBorders, xml)
	return len(ss.borders) + len(ss.newBorders) - 1
}
func (ss *pqStyleSheet) addNumFmt(code string) int {
	id := 164
	re := regexp.MustCompile(`numFmtId="(\d+)"`)
	for _, nf := range ss.numFmts {
		m := re.FindStringSubmatch(nf)
		if m != nil {
			if v, _ := strconv.Atoi(m[1]); v >= id {
				id = v + 1
			}
		}
	}
	for _, nf := range ss.newNumFmts {
		m := re.FindStringSubmatch(nf)
		if m != nil {
			if v, _ := strconv.Atoi(m[1]); v >= id {
				id = v + 1
			}
		}
	}
	ss.newNumFmts = append(ss.newNumFmts, fmt.Sprintf(`<numFmt numFmtId="%d" formatCode="%s"/>`, id, code))
	return id
}
func (ss *pqStyleSheet) addCellXf(xml string) int {
	ss.newCellXfs = append(ss.newCellXfs, xml)
	return len(ss.cellXfs) + len(ss.newCellXfs) - 1
}

// base 서식(인덱스)의 cellXf 원문을 돌려줌 (새로 추가된 것 포함).
func (ss *pqStyleSheet) xfXML(base int) string {
	if base < len(ss.cellXfs) {
		return ss.cellXfs[base]
	}
	i := base - len(ss.cellXfs)
	if i >= 0 && i < len(ss.newCellXfs) {
		return ss.newCellXfs[i]
	}
	return ss.cellXfs[0]
}

var pqAttrCache = map[string]*regexp.Regexp{}

func pqAttrRe(attr string) *regexp.Regexp {
	if re, ok := pqAttrCache[attr]; ok {
		return re
	}
	re := regexp.MustCompile(attr + `="\d+"`)
	pqAttrCache[attr] = re
	return re
}

// base 서식의 특정 속성(attr, 예: "fillId"/"numFmtId")만 value 로 바꾼 새 cellXf 를
// 만들어(또는 캐시에서 재사용) 그 인덱스를 돌려줌. 속성이 원래 없던 xf 면 새로 끼워 넣음.
func (ss *pqStyleSheet) withAttr(base int, attr, value string) int {
	key := [2]int{base, hashAttr(attr, value)}
	if v, ok := ss.fillClone[key]; ok {
		return v
	}
	baseXML := ss.xfXML(base)
	re := pqAttrRe(attr)
	repl := attr + `="` + value + `"`
	var newXML string
	if re.MatchString(baseXML) {
		newXML = re.ReplaceAllString(baseXML, repl)
	} else {
		newXML = strings.Replace(baseXML, "<xf ", "<xf "+repl+" ", 1)
	}
	idx := ss.addCellXf(newXML)
	ss.fillClone[key] = idx
	return idx
}

func (ss *pqStyleSheet) withFill(base, fillID int) int {
	return ss.withAttr(base, "fillId", strconv.Itoa(fillID))
}

func hashAttr(attr, value string) int {
	h := 0
	for _, c := range attr + "=" + value {
		h = h*131 + int(c)
	}
	return h
}

// styles.xml 전체를 새 항목이 반영된 내용으로 다시 만든다.
func (ss *pqStyleSheet) render(stylesXML string) string {
	bump := func(tag string, extra []string) func(string) string {
		return func(s string) string {
			if len(extra) == 0 {
				return s
			}
			re := pqListRe(tag)
			return re.ReplaceAllStringFunc(s, func(block string) string {
				m := re.FindStringSubmatch(block)
				n, _ := strconv.Atoi(m[1])
				n += len(extra)
				body := m[2] + strings.Join(extra, "")
				return fmt.Sprintf(`<%s count="%d"%s>%s</%s>`, tag, n, "", body, tag)
			})
		}
	}
	out := stylesXML
	out = bump("fonts", ss.newFonts)(out)
	out = bump("fills", ss.newFills)(out)
	out = bump("borders", ss.newBorders)(out)
	out = bump("cellXfs", ss.newCellXfs)(out)
	if len(ss.newNumFmts) > 0 {
		if strings.Contains(out, "<numFmts ") {
			out = bump("numFmts", ss.newNumFmts)(out)
		} else {
			// numFmts 블록이 아예 없던 경우 - cellXfs 앞에 새로 추가 (스키마 순서상 numFmts 가 fonts 보다 먼저 와야 함)
			block := fmt.Sprintf(`<numFmts count="%d">%s</numFmts>`, len(ss.newNumFmts), strings.Join(ss.newNumFmts, ""))
			out = strings.Replace(out, "<fonts ", block+"<fonts ", 1)
		}
	}
	return out
}

// 맑은고딕 계열이 아닌 기본(이름 없음) 폰트 - pavq_form.py 의 Font(...) 와 동일
func pqFontXML(bold bool, size int) string {
	if bold {
		return fmt.Sprintf(`<font><b val="1"/><sz val="%d"/></font>`, size)
	}
	return fmt.Sprintf(`<font><sz val="%d"/></font>`, size)
}

func pqFillXML(rgb string) string {
	return fmt.Sprintf(`<fill><patternFill patternType="solid"><fgColor rgb="%s"/></patternFill></fill>`, rgb)
}

func pqBoxBorderXML() string {
	return `<border><left style="thin"><color indexed="64"/></left><right style="thin"><color indexed="64"/></right>` +
		`<top style="thin"><color indexed="64"/></top><bottom style="thin"><color indexed="64"/></bottom><diagonal/></border>`
}

// ---------------------------------------------------------------- 잡다한 헬퍼

func round2(v float64) float64 {
	return math.Round(v*100) / 100
}
func absf(v float64) float64 {
	if v < 0 {
		return -v
	}
	return v
}

func dispRow(r []string) string {
	if len(r) > 1 {
		return r[1]
	}
	return ""
}

func firstN(lst []string, n int) []string {
	if len(lst) <= n {
		return lst
	}
	return lst[:n]
}

func prefixEach(lst []string, prefix string) []string {
	out := make([]string, len(lst))
	for i, s := range lst {
		out[i] = prefix + s
	}
	return out
}

// 템플릿 원본 numFmts 에서 formatCode(이미 &quot; 로 escape 된 상태)가 같은 항목을 찾음.
func pqFindNumFmt(ss *pqStyleSheet, code string) (int, bool) {
	re := regexp.MustCompile(`numFmtId="(\d+)" formatCode="` + regexp.QuoteMeta(code) + `"`)
	for _, nf := range ss.numFmts {
		if m := re.FindStringSubmatch(nf); m != nil {
			id, _ := strconv.Atoi(m[1])
			return id, true
		}
	}
	return 0, false
}

// base 서식의 numFmtId/fillId/borderId 는 두고, 글꼴과 정렬만 새로 지정한 cellXf 를 만든다.
// (비고 칸처럼 줄바꿈+좌측정렬+작은 글꼴로 바꿔야 하는, 한 번만 쓰는 특수 서식용)
func pqCloneWithAlignFont(ss *pqStyleSheet, base, fontID int, alignmentAttrs string) int {
	baseXML := ss.xfXML(base)
	get := func(attr string) string {
		m := regexp.MustCompile(attr + `="(\d+)"`).FindStringSubmatch(baseXML)
		if m == nil {
			return "0"
		}
		return m[1]
	}
	xf := fmt.Sprintf(`<xf numFmtId="%s" fontId="%d" fillId="%s" borderId="%s" xfId="0" applyFont="1" applyAlignment="1"><alignment %s/></xf>`,
		get("numFmtId"), fontID, get("fillId"), get("borderId"), alignmentAttrs)
	return ss.addCellXf(xf)
}
