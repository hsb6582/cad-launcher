// CAD 런처 - "요즘 앱" 스타일 (WebView2 기반)
//
// 화면은 HTML/CSS/JS(ui.html)로 그리고, AutoCAD 창 찾기·명령 전송·GitHub 업데이트·
// 외부 프로그램 설치 같은 실제 동작은 실제 CAD런처(../src)와 동일한 Win32 API를
// 그대로 호출해서 처리한다 (winapi.go, run.go, ghupdate.go, toolsinstall.go).
//
// 빌드: GOOS=windows GOARCH=amd64 go build -ldflags "-H windowsgui -s -w" -o CAD런처.exe
// 실행 전 필요: Windows의 Microsoft Edge WebView2 런타임 (Win11은 기본 포함)
package main

import (
	_ "embed"
	"encoding/json"

	webview2 "github.com/jchv/go-webview2"
)

//go:embed ui.html
var uiHTML string

func main() {
	initPaths()
	loadState()
	_ = loadCatalog() // 실패해도 빈 목록으로 계속 (파일이 없을 수 있음)

	catalogJSON := "null"
	if b, err := json.Marshal(cat); err == nil {
		catalogJSON = string(b)
	}
	stateJSON := "null"
	if b, err := json.Marshal(map[string]interface{}{
		"keyword": st.Keyword, "method": st.Method, "encoding": st.Encoding,
		"cancel": st.Cancel, "topmost": st.Topmost, "values": st.Values,
	}); err == nil {
		stateJSON = string(b)
	}

	html := `<script>window.__CATALOG__ = ` + catalogJSON + `; window.__STATE__ = ` + stateJSON + `;</script>` + uiHTML

	w := webview2.NewWithOptions(webview2.WebViewOptions{
		WindowOptions: webview2.WindowOptions{
			Title:  "CAD 런처",
			Width:  1180,
			Height: 760,
			Center: true,
		},
	})
	defer w.Destroy()

	selfHwnd = uintptr(w.Window())
	if st.Topmost {
		setTopmost(true)
	}

	setupBindings(w)
	w.SetHtml(html)
	w.Run()
}
