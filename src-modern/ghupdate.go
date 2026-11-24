package main

// GitHub 저장소와 동기화 - 실제 CAD런처(src/update.go)와 같은 방식.
//  - git trees API 로 파일 목록 + sha 를 받아 로컬과 비교
//  - 바뀐 파일만 raw.githubusercontent.com 에서 받아 교체
//  - 이 미리보기 자신의 실행파일(exe)은 이름이 달라서 교체 대상에서 제외한다 (정보만 표시)

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"
)

const (
	fixedRepo   = "hsb6582/cad-launcher"
	fixedBranch = "main"
	exeRepoName = "CAD런처.exe" // 저장소 안 실제 런처 파일 이름 (이 미리보기 자신과는 다름)
)

func branch() string { return fixedBranch }

var httpClient = &http.Client{Timeout: 30 * time.Second}

func ghGet(rawURL string, accept string) ([]byte, error) {
	req, err := http.NewRequest("GET", rawURL, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", "CADLauncherPreview")
	if accept != "" {
		req.Header.Set("Accept", accept)
	}
	if st.Token != "" {
		req.Header.Set("Authorization", "Bearer "+st.Token)
	}
	resp, err := httpClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	switch resp.StatusCode {
	case 200:
		return body, nil
	case 401, 403:
		return nil, fmt.Errorf("접근 거부(%d) - 비공개 저장소면 토큰을 확인하세요", resp.StatusCode)
	case 404:
		return nil, fmt.Errorf("저장소 또는 브랜치를 찾을 수 없음(404)")
	}
	return nil, fmt.Errorf("HTTP %d", resp.StatusCode)
}

type remoteFile struct {
	Path string `json:"path"`
	Type string `json:"type"`
	Sha  string `json:"sha"`
	Size int64  `json:"size"`
}

func syncTarget(p string) bool {
	return p == "catalog.json" || p == "README.md" || strings.HasPrefix(p, "lsp/")
}

func fetchTree() ([]remoteFile, error) {
	body, err := ghGet("https://api.github.com/repos/"+fixedRepo+"/git/trees/"+url.PathEscape(branch())+"?recursive=1",
		"application/vnd.github+json")
	if err != nil {
		return nil, err
	}
	var tree struct {
		Tree []remoteFile `json:"tree"`
	}
	if err := json.Unmarshal(body, &tree); err != nil {
		return nil, err
	}
	return tree.Tree, nil
}

// checkAndApplyUpdates: 바뀐 catalog.json/lsp/README.md 를 받아서 바로 적용하고,
// 사람이 읽을 결과 메시지를 돌려준다. (exe 는 이 미리보기 자신이 아니라서 정보만 알려줌)
func checkAndApplyUpdates() (string, error) {
	tree, err := fetchTree()
	if err != nil {
		return "", err
	}
	var lines []string
	exeNote := ""
	updated := 0
	for _, f := range tree {
		if f.Type != "blob" {
			continue
		}
		if f.Path == exeRepoName {
			exeNote = "런처 프로그램(" + exeRepoName + ")도 저장소에 있습니다. 이 미리보기 파일은 자동으로 바꾸지 않습니다."
			continue
		}
		if !syncTarget(f.Path) {
			continue
		}
		local := absPath(f.Path)
		localSha := gitBlobSha(local)
		if localSha == f.Sha {
			continue
		}
		segs := strings.Split(f.Path, "/")
		for i := range segs {
			segs[i] = url.PathEscape(segs[i])
		}
		data, err := ghGet("https://raw.githubusercontent.com/"+fixedRepo+"/"+url.PathEscape(branch())+"/"+strings.Join(segs, "/"), "")
		if err != nil {
			lines = append(lines, "받기 실패 "+f.Path+": "+err.Error())
			continue
		}
		if gitBlobShaBytes(data) != f.Sha {
			lines = append(lines, "검증 실패 "+f.Path+" (내용 불일치) - 건너뜀")
			continue
		}
		if err := os.MkdirAll(filepath.Dir(local), 0755); err != nil {
			lines = append(lines, "폴더 생성 실패 "+f.Path+": "+err.Error())
			continue
		}
		if err := os.WriteFile(local, data, 0644); err != nil {
			lines = append(lines, "저장 실패 "+f.Path+": "+err.Error())
			continue
		}
		lines = append(lines, "업데이트: "+f.Path)
		updated++
	}
	if updated > 0 {
		_ = loadCatalog()
	}
	msg := fmt.Sprintf("업데이트 확인 완료. %d개 파일 갱신.", updated)
	if len(lines) > 0 {
		msg += "\n" + strings.Join(lines, "\n")
	}
	if exeNote != "" {
		msg += "\n" + exeNote
	}
	return msg, nil
}
