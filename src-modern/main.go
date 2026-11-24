// CAD 런처 - "요즘 앱" 스타일 미리보기 (WebView2 기반)
//
// 진짜 CAD런처(../src)는 그대로 두고, 디자인만 먼저 확인해보기 위한 별도 시험판입니다.
// catalog.json은 실제 파일을 읽어서 보여주지만, 창 찾기/실행/업데이트는 전부 가짜(로그만 남김)입니다.
// 스타일이 마음에 들면 이 틀에 실제 동작(send.go, update.go 등)을 연결합니다.
//
// 빌드: GOOS=windows GOARCH=amd64 go build -ldflags "-H windowsgui -s -w" -o CAD런처-미리보기.exe
//
// 실행 전 필요: Windows에 Microsoft Edge WebView2 런타임 (Windows 11은 기본 포함,
// Windows 10은 대부분 Edge 자동 업데이트로 이미 설치돼 있음. 없으면 webview 창이 안 뜸)
package main

import (
	_ "embed"
	"encoding/json"
	"os"
	"path/filepath"

	webview2 "github.com/jchv/go-webview2"
)

//go:embed ui.html
var uiHTML string

func readCatalogJSON() string {
	exePath, err := os.Executable()
	if err != nil {
		return "null"
	}
	path := filepath.Join(filepath.Dir(exePath), "catalog.json")
	data, err := os.ReadFile(path)
	if err != nil {
		return "null"
	}
	var v interface{}
	if json.Unmarshal(data, &v) != nil {
		return "null"
	}
	return string(data)
}

func main() {
	html := `<script>window.__CATALOG__ = ` + readCatalogJSON() + `;</script>` + uiHTML

	w := webview2.NewWithOptions(webview2.WebViewOptions{
		WindowOptions: webview2.WindowOptions{
			Title:  "CAD 런처 (미리보기)",
			Width:  1180,
			Height: 760,
			Center: true,
		},
	})
	defer w.Destroy()
	w.SetHtml(html)
	w.Run()
}
