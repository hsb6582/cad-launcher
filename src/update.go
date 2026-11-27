package main

// GitHub 저장소와 동기화 (리습 · 목록 · 런처 자체 업데이트)
//  - 저장소 파일 목록과 각 파일의 git blob SHA 를 한 번에 받아(git trees API) 로컬 파일과 비교
//  - 바뀐 파일만 raw.githubusercontent.com 에서 내려받아 교체 (기존 파일은 _backup 폴더에 보관)
//  - 로컬에서 직접 고친 파일은 덮어쓰기 전에 따로 물어봄

import (
	"crypto/sha1"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"
)

type remoteFile struct {
	Path string `json:"path"`
	Type string `json:"type"`
	Sha  string `json:"sha"`
	Size int64  `json:"size"`
}

type updatePlan struct {
	interactive bool
	err         error
	updates     []remoteFile // 로컬이 손대지 않았거나 새 파일 → 바로 교체 가능
	conflicts   []remoteFile // 로컬에서도 수정된 파일
	sameAll     []remoteFile // 이미 같은 파일 (동기화 기록만 갱신)
	ghDate      string       // GitHub 브랜치의 마지막 커밋 시각 (RFC3339, 못 읽으면 "")
}

// GitHub 브랜치의 마지막 변경(커밋) 시각
func fetchBranchDate() string {
	body, err := ghGet("https://api.github.com/repos/"+fixedRepo+"/branches/"+url.PathEscape(branch()), "application/vnd.github+json")
	if err != nil {
		return ""
	}
	var b struct {
		Commit struct {
			Commit struct {
				Committer struct {
					Date string `json:"date"`
				} `json:"committer"`
			} `json:"commit"`
		} `json:"commit"`
	}
	if json.Unmarshal(body, &b) != nil {
		return ""
	}
	return b.Commit.Commit.Committer.Date
}

// 설정 창 표시용: RFC3339 → 이 PC 시각 "2026-11-25 16:30"
func fmtStamp(v string) string {
	t, err := time.Parse(time.RFC3339, v)
	if err != nil {
		return ""
	}
	return t.Local().Format("2006-01-02 15:04")
}

var (
	pendingPlan *updatePlan
	updating    bool
	httpClient  = &http.Client{Timeout: 30 * time.Second}
)

func syncTarget(p string) bool {
	return p == "catalog.json" || p == exeRepoName || p == "README.md" || strings.HasPrefix(p, "lsp/")
}

func localFor(p string) string {
	if p == exeRepoName {
		return exePath
	}
	return absPath(p)
}

func gitBlobSha(path string) string {
	b, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	h := sha1.New()
	fmt.Fprintf(h, "blob %d\x00", len(b))
	h.Write(b)
	return hex.EncodeToString(h.Sum(nil))
}

// ── GitHub API 응답 보관 (ETag) ──
// 토큰 없이 쓰는 GitHub API 는 같은 인터넷 주소(IP)당 1시간 60회로 제한된다.
// 지난 응답의 ETag 를 보내 "바뀐 게 없음(304)" 답을 받으면 횟수에서 빠지므로,
// api.github.com 응답은 launcher_ghcache.json 에 보관해 두고 다시 쓴다.
type ghCacheEntry struct {
	ETag string `json:"etag"`
	Body string `json:"body"`
}

var (
	ghCacheMu     sync.Mutex
	ghCache       map[string]ghCacheEntry
	ghCacheLoaded bool
)

func ghCachePath() string { return filepath.Join(appDir, "launcher_ghcache.json") }

func ghCacheGet(u string) (ghCacheEntry, bool) {
	ghCacheMu.Lock()
	defer ghCacheMu.Unlock()
	if !ghCacheLoaded {
		ghCacheLoaded = true
		ghCache = map[string]ghCacheEntry{}
		if b, err := os.ReadFile(ghCachePath()); err == nil {
			_ = json.Unmarshal(b, &ghCache)
		}
	}
	e, ok := ghCache[u]
	return e, ok
}

func ghCachePut(u string, e ghCacheEntry) {
	ghCacheMu.Lock()
	defer ghCacheMu.Unlock()
	if ghCache == nil {
		ghCache = map[string]ghCacheEntry{}
	}
	ghCache[u] = e
	if b, err := json.Marshal(ghCache); err == nil {
		_ = os.WriteFile(ghCachePath(), b, 0644)
	}
}

// 횟수 제한 응답이면 안내 문구(풀리는 시각 포함)를, 아니면 "" 를 돌려준다.
func ghRateLimitMsg(resp *http.Response, body []byte) string {
	if resp.StatusCode != 403 && resp.StatusCode != 429 {
		return ""
	}
	if resp.Header.Get("X-RateLimit-Remaining") != "0" && !strings.Contains(strings.ToLower(string(body)), "rate limit") {
		return ""
	}
	var at time.Time
	if v, err := strconv.ParseInt(resp.Header.Get("X-RateLimit-Reset"), 10, 64); err == nil && v > 0 {
		at = time.Unix(v, 0)
	} else if v, err := strconv.Atoi(resp.Header.Get("Retry-After")); err == nil && v > 0 {
		at = time.Now().Add(time.Duration(v) * time.Second)
	}
	if at.IsZero() {
		return T("update.028")
	}
	return fmt.Sprintf(T("update.027"), at.Local().Format("15:04"))
}

func ghGet(rawURL string, accept string) ([]byte, error) {
	req, err := http.NewRequest("GET", rawURL, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", "CADLauncher")
	if accept != "" {
		req.Header.Set("Accept", accept)
	}
	if st.Token != "" {
		req.Header.Set("Authorization", "Bearer "+st.Token)
	}
	isAPI := strings.HasPrefix(rawURL, "https://api.github.com/")
	cached, hasCache := ghCacheEntry{}, false
	if isAPI {
		if cached, hasCache = ghCacheGet(rawURL); hasCache && cached.ETag != "" {
			req.Header.Set("If-None-Match", cached.ETag)
		}
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
	if msg := ghRateLimitMsg(resp, body); msg != "" {
		return nil, fmt.Errorf("%s", msg)
	}
	switch resp.StatusCode {
	case 304: // 지난번과 같음 (횟수에서 빠짐)
		if hasCache {
			return []byte(cached.Body), nil
		}
		return nil, fmt.Errorf("HTTP 304")
	case 200:
		if isAPI {
			if et := resp.Header.Get("ETag"); et != "" {
				ghCachePut(rawURL, ghCacheEntry{ETag: et, Body: string(body)})
			}
		}
		return body, nil
	case 401, 403:
		return nil, fmt.Errorf(T("update.001"), resp.StatusCode)
	case 404:
		return nil, fmt.Errorf("%s", T("update.002"))
	}
	return nil, fmt.Errorf("HTTP %d", resp.StatusCode)
}

// 업데이트 저장소는 프로그램에 고정 (목록 파일이나 설정으로 바뀌지 않음)
const fixedRepo = "hsb6582/cad-launcher"

// 받을 브랜치는 빌드할 때 정한다 (기본 = 배포용 main)
//
//	테스트용: -ldflags "-X main.fixedBranch=dev -X main.exeRepoName=전자제도_도우미-테스트.exe"
var fixedBranch = "main"

func init() {
	if fixedBranch != "main" {
		appTitle += T("update.003") // 창 제목으로 테스트용 런처임을 구분
	}
}

func branch() string { return fixedBranch }

func fetchPlan(interactive bool) *updatePlan {
	plan := &updatePlan{interactive: interactive}
	repo := fixedRepo
	body, err := ghGet("https://api.github.com/repos/"+repo+"/git/trees/"+url.PathEscape(branch())+"?recursive=1",
		"application/vnd.github+json")
	if err != nil {
		plan.err = err
		return plan
	}
	var tree struct {
		Tree []remoteFile `json:"tree"`
	}
	if err := json.Unmarshal(body, &tree); err != nil {
		plan.err = err
		return plan
	}
	plan.ghDate = fetchBranchDate()
	for _, f := range tree.Tree {
		if f.Type != "blob" || !syncTarget(f.Path) {
			continue
		}
		local := gitBlobSha(localFor(f.Path))
		synced := st.Synced[f.Path]
		switch {
		case local == f.Sha:
			plan.sameAll = append(plan.sameAll, f)
		case local == "" || (synced != "" && local == synced) || f.Path == exeRepoName:
			plan.updates = append(plan.updates, f)
		default:
			plan.conflicts = append(plan.conflicts, f)
		}
	}
	return plan
}

// 자동 확인 주기: 런처를 켜 둔 동안 1시간마다 (설정의 '업데이트 자동 확인'이 켜져 있을 때)
const (
	updTimerID = 78
	updEvery   = 60 * 60 * 1000 // ms
)

// interactive=false (켤 때·1시간마다 자동 확인): 묻는 창 없이 받을 것이 있으면 빨간 점만 띄운다.
// interactive=true (업데이트 버튼): 받을 파일 목록을 보여 주고 묻는다.
func startUpdateCheck(interactive bool) {
	if updating {
		return
	}
	updating = true
	c(pEnableWindow, hUpdate, 0)
	logf(T("update.004"), fixedRepo, branch())
	go func() {
		p := fetchPlan(interactive)
		pendingPlan = p
		c(pPostMessageW, hMain, WM_APP_UPDATE, 0, 0)
	}()
}

func pathList(fs []remoteFile) string {
	var sb strings.Builder
	for i, f := range fs {
		if i == 12 {
			sb.WriteString(T("update.005") + itoa(len(fs)-12) + T("update.006"))
			break
		}
		sb.WriteString("  • " + f.Path + "\n")
	}
	return sb.String()
}

// 메인 스레드에서 실행
func onUpdateResult() {
	p := pendingPlan
	pendingPlan = nil
	updating = false
	c(pEnableWindow, hUpdate, 1)
	if p == nil {
		return
	}
	if p.err != nil {
		logf(T("update.007"), p.err)
		if p.interactive {
			msgBox(T("update.008")+p.err.Error(), MB_ICONWARNING)
		}
		return
	}
	for _, f := range p.sameAll {
		st.Synced[f.Path] = f.Sha
	}
	st.LastCheck = time.Now().Format(time.RFC3339)
	if p.ghDate != "" {
		st.GitHubDate = p.ghDate
	}
	saveState()
	if len(p.updates) == 0 && len(p.conflicts) == 0 {
		setUpdateAvail(false)
		logf("%s", T("update.009"))
		if p.interactive {
			msgBox(T("update.010"), 0x40)
		}
		return
	}
	if !p.interactive { // 자동 확인: 묻지 않고 빨간 점으로만 알림 (이 PC에서 고친 파일만 다른 경우는 점 없음)
		setUpdateAvail(len(p.updates) > 0)
		if len(p.updates) > 0 {
			logf(T("update.026"), len(p.updates))
		}
		return
	}
	todo := p.updates
	if len(p.updates) > 0 {
		if !ask(T("update.011") + pathList(p.updates) + T("update.012")) {
			todo = nil
		}
	}
	setUpdateAvail(len(p.updates) > 0 && len(todo) == 0) // 새 버전을 안 받았으면 빨간 점 유지
	if len(p.conflicts) > 0 {
		if ask(T("update.013") + pathList(p.conflicts) +
			T("update.014")) {
			todo = append(todo, p.conflicts...)
		} else {
			logf(T("update.015"), len(p.conflicts))
		}
	}
	if len(todo) > 0 {
		applyUpdates(todo)
	}
}

func applyUpdates(files []remoteFile) {
	backup := filepath.Join(appDir, "_backup", time.Now().Format("20060102-150405"))
	okN, exeUpdated, catUpdated := 0, false, false
	for _, f := range files {
		segs := strings.Split(f.Path, "/")
		for i := range segs {
			segs[i] = url.PathEscape(segs[i])
		}
		data, err := ghGet("https://raw.githubusercontent.com/"+fixedRepo+"/"+url.PathEscape(branch())+"/"+strings.Join(segs, "/"), "")
		if err != nil {
			logf(T("update.016"), f.Path, err)
			continue
		}
		h := sha1.New()
		fmt.Fprintf(h, "blob %d\x00", len(data))
		h.Write(data)
		if hex.EncodeToString(h.Sum(nil)) != f.Sha {
			logf(T("update.017"), f.Path)
			continue
		}
		dst := localFor(f.Path)
		if old, err := os.ReadFile(dst); err == nil {
			bp := filepath.Join(backup, filepath.FromSlash(f.Path))
			_ = os.MkdirAll(filepath.Dir(bp), 0755)
			_ = os.WriteFile(bp, old, 0644)
		}
		if f.Path == exeRepoName {
			// 실행 중인 exe 는 덮어쓸 수 없지만 이름은 바꿀 수 있음 → .old 로 옮기고 새 파일을 놓는다
			tmp := exePath + ".new"
			if err := os.WriteFile(tmp, data, 0755); err != nil {
				logf(T("update.018"), err)
				continue
			}
			_ = os.Remove(exePath + ".old")
			if err := os.Rename(exePath, exePath+".old"); err != nil {
				logf(T("update.019"), err)
				_ = os.Remove(tmp)
				continue
			}
			if err := os.Rename(tmp, exePath); err != nil {
				_ = os.Rename(exePath+".old", exePath)
				logf(T("update.020"), err)
				continue
			}
			exeUpdated = true
		} else {
			_ = os.MkdirAll(filepath.Dir(dst), 0755)
			if err := os.WriteFile(dst, data, 0644); err != nil {
				logf(T("update.021"), f.Path, err)
				continue
			}
			if f.Path == "catalog.json" {
				catUpdated = true
			}
		}
		st.Synced[f.Path] = f.Sha
		okN++
		logf(T("update.022"), f.Path)
	}
	if okN > 0 {
		st.LastUpdate = time.Now().Format(time.RFC3339)
	}
	saveState()
	if catUpdated {
		loadCatalog()
		refreshTree(nodeRef{})
	}
	logf(T("update.023"), okN, len(files))
	if exeUpdated {
		if ask(T("update.024")) {
			c(pShellExecuteW, 0, uintptr(P(ws("open"))), uintptr(P(ws(exePath))), 0, uintptr(P(ws(appDir))), SW_SHOWNORMAL)
			c(pPostMessageW, hMain, WM_CLOSE, 0, 0)
		}
	} else if okN > 0 {
		msgBox(itoa(okN)+T("update.025"), 0x40)
	}
}

// 로컬에서 고친 목록(catalog.json)을 동기화 기록과 비교해 안내
func localCatalogChanged() bool {
	s := st.Synced["catalog.json"]
	return s != "" && gitBlobSha(catalogPath) != s
}
