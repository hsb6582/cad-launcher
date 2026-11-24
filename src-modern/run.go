package main

// '▶ 실행' 버튼 하나로 들어오는 요청을 실제 CAD런처(src/catalog.go runCurrent, src/app.go)와
// 같은 순서로 처리해서 AutoCAD로 보낸다.

import (
	"fmt"
	"os"
	"strconv"
	"strings"
)

var windows []cadWin

func refreshWindows(keyword string) []string {
	windows = findWindows(keyword)
	titles := make([]string, len(windows))
	for i, w := range windows {
		titles[i] = w.title
	}
	return titles
}

func targetHwnd(index int) (uintptr, error) {
	if index < 0 || index >= len(windows) {
		return 0, fmt.Errorf("대상 CAD 창이 없습니다. '창 찾기'를 다시 눌러 주세요.")
	}
	h := windows[index].h
	if c(pIsWindow, h) == 0 {
		return 0, fmt.Errorf("창이 사라졌습니다. '창 찾기'를 다시 눌러 주세요.")
	}
	return h, nil
}

func sendText(windowIndex int, text string) (string, error) {
	h, err := targetHwnd(windowIndex)
	if err != nil {
		return "", err
	}
	if st.Method == "키입력" {
		sendKeys(h, text, st.Cancel)
	} else if err := sendCopyData(h, text, st.Cancel); err != nil {
		return "", err
	}
	return "전송: " + strings.ReplaceAll(text, "\n", "⏎"), nil
}

type kv struct{ k, v string }

func writeOptFile(id string, vals []kv) error {
	lines := []string{"_CMD=" + id}
	for _, p := range vals {
		v := strings.NewReplacer("\r", " ", "\n", " ").Replace(p.v)
		lines = append(lines, p.k+"="+v)
	}
	content := strings.Join(lines, "\r\n") + "\r\n"
	var b []byte
	if st.Encoding == "utf-8" {
		b = []byte(content)
	} else {
		b = toCP949(content)
	}
	return os.WriteFile(optPath, b, 0644)
}

// runItem: lispID+command 로 기능을 찾아, 옵션값을 반영한 명령을 만들어 windowIndex 의 창으로 보낸다.
// values 는 화면의 입력칸에서 모은 현재 값 (옵션 Key → 문자열. check 는 "1"/"0").
func runItem(lispID, command string, values map[string]string, windowIndex int) (string, error) {
	it, _ := findItem(lispID, command)
	if it == nil {
		return "", fmt.Errorf("목록에서 기능을 찾을 수 없습니다: %s / %s", lispID, command)
	}
	var l *Lisp
	if it.Lisp != "" {
		l = lispByID(it.Lisp)
		if l == nil {
			return "", fmt.Errorf("목록에 리습 '%s' 정보가 없습니다.", it.Lisp)
		}
	}

	var warn string
	if l != nil {
		var miss []string
		for _, t := range l.Tools {
			if toolState(t) == 0 {
				miss = append(miss, t.Name)
			}
		}
		if len(miss) > 0 {
			warn = "⚠ 필요한 외부 프로그램이 설치되어 있지 않습니다: " + strings.Join(miss, ", ") + " (실행은 계속 진행)\n"
		}
	}

	vals, keep, err := collectValues(it.Options, values)
	if err != nil {
		return "", err
	}
	if len(keep) > 0 {
		st.Values[itemKey(it)] = keep
		saveState()
	}

	var sb strings.Builder
	needHelper := false
	for _, o := range it.Options {
		if o.Var == "" {
			needHelper = true
		}
	}
	if needHelper {
		if err := writeOptFile(cmdID(it.Command), vals); err != nil {
			return "", fmt.Errorf("옵션 파일 저장 실패: %w", err)
		}
		sb.WriteString(`(load "` + lispPath("lsp/launcher_opt.lsp") + `")` + "\n")
	}
	if l != nil && l.File != "" {
		if _, err := os.Stat(absPath(l.File)); err != nil {
			return "", fmt.Errorf("리습 파일을 찾을 수 없습니다: %s", absPath(l.File))
		}
		lp := lispPath(l.File)
		sha := gitBlobSha(absPath(l.File))
		id := cmdID(it.Command)
		isFunc := false
		for _, f := range lispFuncs(l.File) {
			if f == id {
				isFunc = true
			}
		}
		if loadedSha[lp] != sha || !isFunc {
			sb.WriteString(`(load "` + lp + `")` + "\n")
			loadedSha[lp] = sha
		} else {
			sb.WriteString(`(if (not c:` + id + `) (load "` + lp + `"))` + "\n")
		}
	}
	if l != nil {
		sb.WriteString(toolVarLines(l))
	}
	for i, o := range it.Options {
		if o.Var != "" && i < len(vals) {
			sb.WriteString("(setq " + o.Var + " " + lispValue(o, vals[i].v) + ")\n")
		}
	}
	body := it.Command
	for _, p := range vals {
		body = strings.ReplaceAll(body, "{"+p.k+"}", p.v)
	}
	if !strings.HasSuffix(body, "\n") {
		body += "\n"
	}
	sb.WriteString(body)

	msg, err := sendText(windowIndex, sb.String())
	if err != nil {
		return "", err
	}
	return warn + "실행: " + it.Name + "   " + msg, nil
}

// values(옵션 Key→문자열) → (명령 치환/옵션파일용 순서쌍, 저장용 맵)
func collectValues(opts []Option, values map[string]string) ([]kv, map[string]interface{}, error) {
	var out []kv
	keep := map[string]interface{}{}
	for _, o := range opts {
		label := o.Label
		if label == "" {
			label = o.Key
		}
		v := strings.TrimSpace(values[o.Key])
		switch o.Type {
		case "check":
			b := v == "1" || strings.EqualFold(v, "true")
			keep[o.Key] = b
			out = append(out, kv{o.Key, toStr(b)})
		case "number":
			if v != "" {
				if _, err := strconv.ParseFloat(v, 64); err != nil {
					return nil, nil, fmt.Errorf("'%s' 값이 숫자가 아닙니다: %s", label, v)
				}
			}
			keep[o.Key] = v
			out = append(out, kv{o.Key, v})
		case "int":
			if v != "" {
				if _, err := strconv.Atoi(v); err != nil {
					return nil, nil, fmt.Errorf("'%s' 값이 정수가 아닙니다: %s", label, v)
				}
			}
			keep[o.Key] = v
			out = append(out, kv{o.Key, v})
		default:
			keep[o.Key] = v
			out = append(out, kv{o.Key, v})
		}
	}
	return out, keep, nil
}
