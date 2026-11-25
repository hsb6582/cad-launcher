package main

// 연장(자재내역 길이 vs 집계 길이)에 오류가 있는 행의 H 칸에 엑셀 메모(노란 쪽지)를 단다.
// 양식에는 메모가 없고, 메모가 하나라도 생길 때만 comments1.xml / vmlDrawing1.vml 을 새로 만들어 넣는다.

import (
	"fmt"
	"regexp"
	"sort"
	"strings"
)

type pqMemo struct {
	col, row int // 1부터
	text     string
}

type pqMemos struct {
	list []pqMemo
	idx  map[string]int // "열,행" -> list 위치 (같은 칸이면 줄을 이어 붙임)
}

func (m *pqMemos) add(col, row int, text string) {
	if m.idx == nil {
		m.idx = map[string]int{}
	}
	k := fmt.Sprintf("%d,%d", col, row)
	if i, ok := m.idx[k]; ok {
		m.list[i].text += "\n" + text
		return
	}
	m.idx[k] = len(m.list)
	m.list = append(m.list, pqMemo{col, row, text})
}

func pqXMLText(s string) string {
	s = pqEsc(s)
	return strings.ReplaceAll(s, `"`, "&quot;")
}

func pqCommentsXML(memos []pqMemo) string {
	var b strings.Builder
	b.WriteString(`<?xml version="1.0" encoding="UTF-8" standalone="yes"?>` + "\n")
	b.WriteString(`<comments xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><authors><author>PAVQ</author></authors><commentList>`)
	for _, m := range memos {
		fmt.Fprintf(&b, `<comment ref="%s%d" authorId="0"><text><r><rPr><sz val="9"/><color indexed="81"/><rFont val="맑은 고딕"/><family val="3"/><charset val="129"/></rPr><t xml:space="preserve">%s</t></r></text></comment>`,
			pqColLetters(m.col), m.row, pqXMLText(m.text))
	}
	b.WriteString(`</commentList></comments>`)
	return b.String()
}

func pqVMLXML(memos []pqMemo) string {
	var b strings.Builder
	b.WriteString(`<xml xmlns:v="urn:schemas-microsoft-com:vml" xmlns:o="urn:schemas-microsoft-com:office:office" xmlns:x="urn:schemas-microsoft-com:office:excel">` +
		`<o:shapelayout v:ext="edit"><o:idmap v:ext="edit" data="1"/></o:shapelayout>` +
		`<v:shapetype id="_x0000_t202" coordsize="21600,21600" o:spt="202" path="m,l,21600r21600,l21600,xe">` +
		`<v:stroke joinstyle="miter"/><v:path gradientshapeok="t" o:connecttype="rect"/></v:shapetype>`)
	for i, m := range memos {
		lines := strings.Count(m.text, "\n") + 1
		c0, r0 := m.col-1, m.row-1 // 0부터
		top := r0 - 1
		if top < 0 {
			top = 0
		}
		fmt.Fprintf(&b, `<v:shape id="_x0000_s%d" type="#_x0000_t202" style="position:absolute;margin-left:0;margin-top:0;width:220pt;height:%dpt;z-index:%d;visibility:hidden" fillcolor="infoBackground [80]" strokecolor="none [81]" o:insetmode="auto">`+
			`<v:fill color2="infoBackground [80]"/><v:shadow color="none [81]" obscured="t"/><v:path o:connecttype="none"/>`+
			`<v:textbox style="mso-direction-alt:auto"><div style="text-align:left"></div></v:textbox>`+
			`<x:ClientData ObjectType="Note"><x:MoveWithCells/><x:SizeWithCells/><x:Anchor>%d, 15, %d, 2, %d, 15, %d, 16</x:Anchor><x:AutoFill>False</x:AutoFill><x:Row>%d</x:Row><x:Column>%d</x:Column></x:ClientData></v:shape>`,
			1025+i, 14*lines+8, i+1, c0+1, top, c0+5, top+lines+2, r0, c0)
	}
	b.WriteString(`</xml>`)
	return b.String()
}

// files/order 에 메모 파일을 넣고 시트·관계·콘텐츠 형식을 연결한다. 메모가 없으면 아무것도 하지 않음.
func pqAttachMemos(files map[string][]byte, order *[]string, m *pqMemos) {
	if m == nil || len(m.list) == 0 {
		return
	}
	memos := append([]pqMemo{}, m.list...)
	sort.SliceStable(memos, func(i, j int) bool {
		if memos[i].row != memos[j].row {
			return memos[i].row < memos[j].row
		}
		return memos[i].col < memos[j].col
	})
	const cPath, vPath = "xl/comments1.xml", "xl/drawings/vmlDrawing1.vml"
	for _, p := range []string{cPath, vPath} {
		if _, ok := files[p]; !ok {
			*order = append(*order, p)
		}
	}
	files[cPath] = []byte(pqCommentsXML(memos))
	files[vPath] = []byte(pqVMLXML(memos))

	// 시트 관계
	relPath := "xl/worksheets/_rels/sheet1.xml.rels"
	rels := string(files[relPath])
	if rels == "" {
		*order = append(*order, relPath)
		rels = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>` + "\n" +
			`<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"></Relationships>`
	}
	rels = strings.Replace(rels, "</Relationships>",
		`<Relationship Id="rIdPqVml" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/vmlDrawing" Target="../drawings/vmlDrawing1.vml"/>`+
			`<Relationship Id="rIdPqCmt" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/comments" Target="../comments1.xml"/></Relationships>`, 1)
	files[relPath] = []byte(rels)

	// 시트에 legacyDrawing (스키마 순서: drawing 바로 뒤, 없으면 legacyDrawingHF/picture/.../extLst 앞)
	sheet := string(files["xl/worksheets/sheet1.xml"])
	tag := `<legacyDrawing r:id="rIdPqVml"/>`
	if loc := regexp.MustCompile(`<drawing [^>]*/>`).FindStringIndex(sheet); loc != nil {
		sheet = sheet[:loc[1]] + tag + sheet[loc[1]:]
	} else {
		for _, next := range []string{"<legacyDrawingHF", "<picture", "<oleObjects", "<controls", "<webPublishItems", "<tableParts", "<extLst", "</worksheet>"} {
			if i := strings.Index(sheet, next); i >= 0 {
				sheet = sheet[:i] + tag + sheet[i:]
				break
			}
		}
	}
	files["xl/worksheets/sheet1.xml"] = []byte(sheet)

	// 콘텐츠 형식
	ct := string(files["[Content_Types].xml"])
	if !strings.Contains(ct, `Extension="vml"`) {
		ct = strings.Replace(ct, "</Types>", `<Default Extension="vml" ContentType="application/vnd.openxmlformats-officedocument.vmlDrawing"/></Types>`, 1)
	}
	if !strings.Contains(ct, `/xl/comments1.xml`) {
		ct = strings.Replace(ct, "</Types>", `<Override PartName="/xl/comments1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.comments+xml"/></Types>`, 1)
	}
	files["[Content_Types].xml"] = []byte(ct)
}
