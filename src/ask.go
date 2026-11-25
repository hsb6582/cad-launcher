package main

// 리습 질문을 런처 창으로 띄우기
//
// 리습이 선택형 질문(getkword) 직전에 %TEMP%\cad_launcher_ask.txt 를 쓰면 런처가 0.4초마다 확인해서
// 버튼이 있는 질문 창을 띄운다. 버튼을 누르면 고른 키워드 + Enter 를 CAD 로 보내고 CAD 창을 앞으로 가져온다.
// 리습은 답을 받으면(캐드에서 직접 쳐도) 파일을 지우고, 런처는 파일이 없어지면 질문 창을 닫는다.
//
// 파일 형식 (한 줄에 하나, CP949 또는 UTF-8):
//   _ASK=질문ID
//   TITLE=질문 제목
//   DEFAULT=기본 키워드
//   CHOICE=키워드|버튼 이름|한 줄 설명     (여러 줄)
//   HELP=자세한 설명 한 줄                (여러 줄)

import (
	"os"
	"path/filepath"
	"strings"
	"time"
	"unicode/utf8"
)

const (
	askTimerID = 77
	WM_TIMER   = 0x0113
	idAskBase  = 3000
)

var (
	pSetTimer = user32.NewProc("SetTimer")

	askPath   string
	askSeen   time.Time // 이미 띄운(또는 사용자가 닫은) 질문 파일의 수정 시각
	askDlg    *dialog
	askActive bool
)

type askChoice struct{ kw, label, desc string }

type askReq struct {
	id, title, def string
	choices        []askChoice
	help           []string
}

func startAskWatch() {
	askPath = filepath.Join(filepath.Dir(optPath), "cad_launcher_ask.txt")
	c(pSetTimer, hMain, askTimerID, 400, 0)
}

func readAsk() (*askReq, time.Time, bool) {
	fi, err := os.Stat(askPath)
	if err != nil {
		return nil, time.Time{}, false
	}
	b, err := os.ReadFile(askPath)
	if err != nil {
		return nil, fi.ModTime(), false
	}
	text := string(b)
	if !utf8.Valid(b) {
		text = fromCP949(b) // AutoLISP write-line 은 보통 CP949
	}
	text = strings.TrimPrefix(text, "\xef\xbb\xbf")
	r := &askReq{}
	for _, line := range strings.Split(text, "\n") {
		line = strings.TrimRight(line, "\r")
		i := strings.Index(line, "=")
		if i < 0 {
			continue
		}
		k, v := strings.ToUpper(strings.TrimSpace(line[:i])), strings.TrimSpace(line[i+1:])
		switch k {
		case "_ASK":
			r.id = v
		case "TITLE":
			r.title = v
		case "DEFAULT":
			r.def = v
		case "CHOICE":
			p := strings.SplitN(v, "|", 3)
			for len(p) < 3 {
				p = append(p, "")
			}
			if p[0] != "" {
				if p[1] == "" {
					p[1] = p[0]
				}
				r.choices = append(r.choices, askChoice{p[0], p[1], p[2]})
			}
		case "HELP":
			r.help = append(r.help, line[i+1:])
		}
	}
	return r, fi.ModTime(), len(r.choices) > 0
}

// 런처 타이머 (0.4초)
func onAskTimer() {
	if askActive {
		if askDlg != nil {
			if _, err := os.Stat(askPath); err != nil {
				askDlg.done = true // 캐드에서 직접 답했거나 명령이 끝남
			} else {
				keepAskOnTop(askDlg.h) // CAD 를 클릭해도 질문 창이 뒤로 가지 않게 계속 맨 위로
			}
		}
		return
	}
	r, mt, ok := readAsk()
	if !ok || mt.Equal(askSeen) {
		return
	}
	if time.Since(mt) > 30*time.Minute { // 리습이 비정상 종료해 남은 오래된 파일
		askSeen = mt
		return
	}
	if len(dlgStack) > 0 { // 다른 창(설정 등)이 열려 있으면 닫힌 뒤에 띄움
		return
	}
	askSeen = mt
	askActive = true
	defer func() { askActive, askDlg = false, nil }()
	if kw, ok := askDialog(r); ok {
		sendAnswer(kw)
	}
}

func askDialog(r *askReq) (string, bool) {
	const W = 520
	title := r.title
	if title == "" {
		title = "CAD 질문"
	}
	helpText := strings.Join(r.help, "\r\n")
	helpLines := len(r.help)
	for _, l := range r.help {
		helpLines += utf8.RuneCountInString(l) / 34 // 긴 줄은 줄바꿈 됨
	}
	helpH := 0
	if helpText != "" {
		helpH = helpLines*20 + 8
	}
	descW := W - 16 - 170 - 10 - 16
	rowH := make([]int, len(r.choices))
	listH := 0
	for i, ch := range r.choices {
		n := 1 + utf8.RuneCountInString(ch.desc)/20
		rowH[i] = 34
		if n*20+8 > rowH[i] {
			rowH[i] = n*20 + 8
		}
		listH += rowH[i] + 6
	}
	H := 16 + 26 + 8 + helpH + 8 + listH + 8 + 20 + 16
	d := newDialog("CAD 질문 - "+title, W, H)
	askDlg = d
	placeAskDialog(d)

	y := 16
	t := d.label(title, 16, y, W-32)
	c(pSendMessageW, t, WM_SETFONT, hFontBold, 1)
	mv(t, 16, y, W-32, 26)
	y += 34
	if helpText != "" {
		d.note(helpText, 16, y, W-32, helpH)
		y += helpH + 8
	}
	answer := ""
	var focus uintptr
	for i, ch := range r.choices {
		label := ch.label
		isDef := strings.EqualFold(ch.kw, r.def)
		if isDef {
			label += "  (기본)"
		}
		b := d.button(label, idAskBase+i, 16, y+(rowH[i]-30)/2, 170, isDef)
		if isDef || focus == 0 {
			focus = b
		}
		if ch.desc != "" {
			l := d.label(ch.desc, 16+170+10, y+4, descW)
			mv(l, 16+170+10, y+4, descW, rowH[i]-8)
		}
		y += rowH[i] + 6
	}
	d.note("창을 닫으면 캐드 명령줄에서 직접 답할 수 있습니다.", 16, y+8, W-32, 20)
	d.onCmd = func(id, code int) {
		if code == BN_CLICKED && id >= idAskBase && id < idAskBase+len(r.choices) {
			answer = r.choices[id-idAskBase].kw
			d.ok, d.done = true, true
		}
	}
	// 런처를 최소화해도 같이 숨지 않도록 런처 소속에서 빼고(독립 창), 항상 맨 위에 둠
	c(pSetWindowLongPtrW, d.h, ^uintptr(7) /*GWLP_HWNDPARENT = -8*/, 0)
	keepAskOnTop(d.h)
	c(pSetForegroundWindow, d.h)
	ok := d.run(focus)
	return answer, ok && answer != ""
}

// 항상 위 (HWND_TOPMOST, 이동·크기·포커스는 그대로)
func keepAskOnTop(h uintptr) {
	c(pSetWindowPos, h, ^uintptr(0), 0, 0, 0, 0, 0x0001|0x0002|0x0010) // NOSIZE|NOMOVE|NOACTIVATE
}

// 질문 창은 CAD 도면 창 위(오른쪽 위)에 띄움. 도면 가운데의 굵게 표시한 경계를 가리지 않도록 오른쪽에 붙임.
// CAD 창을 못 찾으면 런처 가운데 (newDialog 기본 위치)
func placeAskDialog(d *dialog) {
	cad := targetHwnd()
	if cad == 0 || c(pIsIconic, cad) != 0 {
		return
	}
	var cr, dr rectT
	c(pGetWindowRect, cad, uintptr(P(&cr)))
	c(pGetWindowRect, d.h, uintptr(P(&dr)))
	w := dr.right - dr.left
	x := cr.right - w - int32(s(60))
	y := cr.top + int32(s(140)) // 리본 메뉴 아래
	if x < cr.left {
		x = cr.left
	}
	c(pSetWindowPos, d.h, 0, uintptr(x), uintptr(y), 0, 0, 0x0001|0x0004) // NOSIZE|NOZORDER
}

// 답 보내기: 진행 중 명령을 취소(Ctrl+C)하면 안 되므로 '보내기 전 취소' 설정과 상관없이 그대로 보냄
func sendAnswer(kw string) {
	readSettings()
	h := targetHwnd()
	if h == 0 {
		msgBox("대상 CAD 창이 없습니다. 캐드 명령줄에서 직접 답해 주세요.", MB_ICONWARNING)
		return
	}
	text := kw + "\n"
	if st.Method == "키입력" {
		sendKeys(h, text, false)
	} else {
		if err := sendCopyData(h, text, false); err != nil {
			logf("질문 답 전송 오류: %v", err)
			return
		}
		if c(pIsIconic, h) != 0 {
			c(pShowWindow, h, SW_RESTORE)
		}
		c(pSetForegroundWindow, h)
	}
	logf("질문 답: %s", kw)
}
