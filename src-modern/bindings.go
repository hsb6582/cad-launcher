package main

// JS(ui.html) ↔ Go 연결. window.<이름>(...) 으로 호출하면 여기로 들어온다.

import (
	"encoding/json"

	webview2 "github.com/jchv/go-webview2"
)

var wv webview2.WebView

// 시간이 걸리는 작업(업데이트 확인, 외부 프로그램 설치)의 결과를 화면에 비동기로 밀어넣는다.
func pushEvent(kind string, payload interface{}) {
	if wv == nil {
		return
	}
	k, _ := json.Marshal(kind)
	p, _ := json.Marshal(payload)
	js := "window.onBackendEvent && window.onBackendEvent(" + string(k) + "," + string(p) + ")"
	wv.Dispatch(func() { wv.Eval(js) })
}

func setupBindings(w webview2.WebView) {
	wv = w

	// 비동기 처리: EnumWindows 자체는 빠르지만, 화면에 떠 있는 다른 프로그램이
	// 멈춰있으면 제목을 읽어오는 동안 잠깐씩 걸릴 수 있어서, 메인 화면이 멈춘
	// 것처럼 보이지 않도록 백그라운드에서 돌리고 결과만 나중에 밀어넣는다.
	_ = w.Bind("findWindows", func(keyword string) error {
		go func() {
			titles := refreshWindows(keyword)
			pushEvent("windowList", map[string]interface{}{"titles": titles})
		}()
		return nil
	})

	_ = w.Bind("getSettings", func() map[string]interface{} {
		return map[string]interface{}{
			"keyword": st.Keyword, "method": st.Method, "encoding": st.Encoding,
			"cancel": st.Cancel, "topmost": st.Topmost, "values": st.Values,
		}
	})

	_ = w.Bind("setKeyword", func(v string) { st.Keyword = v; saveState() })
	_ = w.Bind("setMethod", func(v string) { st.Method = v; saveState() })
	_ = w.Bind("setEncoding", func(v string) { st.Encoding = v; saveState() })
	_ = w.Bind("setCancel", func(v bool) { st.Cancel = v; saveState() })
	_ = w.Bind("setTopmost", func(v bool) { st.Topmost = v; setTopmost(v); saveState() })

	_ = w.Bind("sendFree", func(windowIndex int, text string) (string, error) {
		return sendText(windowIndex, text)
	})

	_ = w.Bind("runItem", func(lispID, command string, windowIndex int, values map[string]string) (string, error) {
		return runItem(lispID, command, values, windowIndex)
	})

	_ = w.Bind("installTools", func(lispID string) error {
		go func() {
			msg, err := installToolsSync(lispID)
			if err != nil {
				pushEvent("toolsResult", map[string]string{"error": err.Error()})
				return
			}
			pushEvent("toolsResult", map[string]string{"message": msg})
		}()
		return nil
	})

	_ = w.Bind("checkForUpdates", func() error {
		go func() {
			msg, err := checkAndApplyUpdates()
			if err != nil {
				pushEvent("updateResult", map[string]string{"error": err.Error()})
				return
			}
			pushEvent("updateResult", map[string]string{"message": msg})
		}()
		return nil
	})
}
