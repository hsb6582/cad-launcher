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
	"strings"
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
		return nil, fmt.Errorf("저장소 또는 브랜치를 찾을 수 없음(404) - GitHub 설정을 확인하세요")
	}
	return nil, fmt.Errorf("HTTP %d", resp.StatusCode)
}

func branch() string {
	if cat.Update.Branch == "" {
		return "main"
	}
	return cat.Update.Branch
}

func fetchPlan(interactive bool) *updatePlan {
	plan := &updatePlan{interactive: interactive}
	repo := strings.TrimSpace(cat.Update.Repo)
	if repo == "" {
		plan.err = fmt.Errorf("GitHub 저장소가 설정되지 않았습니다 ('GitHub 설정' 버튼)")
		return plan
	}
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

func startUpdateCheck(interactive bool) {
	if updating {
		return
	}
	if cat.Update.Repo == "" {
		if interactive {
			githubDialog()
		}
		return
	}
	updating = true
	c(pEnableWindow, hUpdate, 0)
	logf("업데이트 확인 중… (%s, %s)", cat.Update.Repo, branch())
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
			sb.WriteString("  … 외 " + itoa(len(fs)-12) + "개\n")
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
		logf("업데이트 확인 실패: %v", p.err)
		if p.interactive {
			msgBox("업데이트 확인 실패\n\n"+p.err.Error(), MB_ICONWARNING)
		}
		return
	}
	for _, f := range p.sameAll {
		st.Synced[f.Path] = f.Sha
	}
	saveState()
	if len(p.updates) == 0 && len(p.conflicts) == 0 {
		logf("최신 상태입니다")
		if p.interactive {
			msgBox("모든 리습과 런처가 최신 상태입니다.", 0x40)
		}
		return
	}
	todo := p.updates
	if len(p.updates) > 0 {
		if !ask("GitHub에 새 버전이 있습니다.\n\n" + pathList(p.updates) + "\n지금 내려받을까요?\n(기존 파일은 _backup 폴더에 보관됩니다)") {
			todo = nil
		}
	}
	if len(p.conflicts) > 0 {
		if ask("아래 파일은 이 PC에서도 수정되었습니다.\n\n" + pathList(p.conflicts) +
			"\nGitHub 버전으로 덮어쓸까요?\n(아니오 = 이 PC 버전 유지, 기존 파일은 _backup 에 보관)") {
			todo = append(todo, p.conflicts...)
		} else {
			logf("로컬 수정 파일 %d개는 유지", len(p.conflicts))
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
		data, err := ghGet("https://raw.githubusercontent.com/"+cat.Update.Repo+"/"+url.PathEscape(branch())+"/"+strings.Join(segs, "/"), "")
		if err != nil {
			logf("받기 실패 %s: %v", f.Path, err)
			continue
		}
		h := sha1.New()
		fmt.Fprintf(h, "blob %d\x00", len(data))
		h.Write(data)
		if hex.EncodeToString(h.Sum(nil)) != f.Sha {
			logf("검증 실패 %s (내용 불일치) - 건너뜀", f.Path)
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
				logf("런처 업데이트 실패: %v", err)
				continue
			}
			_ = os.Remove(exePath + ".old")
			if err := os.Rename(exePath, exePath+".old"); err != nil {
				logf("런처 업데이트 실패: %v", err)
				_ = os.Remove(tmp)
				continue
			}
			if err := os.Rename(tmp, exePath); err != nil {
				_ = os.Rename(exePath+".old", exePath)
				logf("런처 업데이트 실패: %v", err)
				continue
			}
			exeUpdated = true
		} else {
			_ = os.MkdirAll(filepath.Dir(dst), 0755)
			if err := os.WriteFile(dst, data, 0644); err != nil {
				logf("저장 실패 %s: %v", f.Path, err)
				continue
			}
			if f.Path == "catalog.json" {
				catUpdated = true
			}
		}
		st.Synced[f.Path] = f.Sha
		okN++
		logf("업데이트: %s", f.Path)
	}
	saveState()
	if catUpdated {
		loadCatalog()
		refreshTree(nodeRef{})
	}
	logf("업데이트 완료 %d/%d개", okN, len(files))
	if exeUpdated {
		if ask("런처 프로그램이 새 버전으로 바뀌었습니다.\n지금 다시 시작할까요?") {
			c(pShellExecuteW, 0, uintptr(P(ws("open"))), uintptr(P(ws(exePath))), 0, uintptr(P(ws(appDir))), SW_SHOWNORMAL)
			c(pPostMessageW, hMain, WM_CLOSE, 0, 0)
		}
	} else if okN > 0 {
		msgBox(itoa(okN)+"개 파일을 최신 버전으로 업데이트했습니다.", 0x40)
	}
}

// 로컬에서 고친 목록(catalog.json)을 동기화 기록과 비교해 안내
func localCatalogChanged() bool {
	s := st.Synced["catalog.json"]
	return s != "" && gitBlobSha(catalogPath) != s
}

func githubDialog() {
	d := newDialog("GitHub 자동 업데이트 설정", 520, 300)
	const lx, ex = 14, 130
	d.label("저장소", lx, 18, 110)
	hRepo := d.edit(cat.Update.Repo, ex, 14, 250)
	d.note("예: 계정이름/cad-launcher", ex+258, 18, 120, 20)
	d.label("브랜치", lx, 50, 110)
	hBranch := d.edit(branch(), ex, 46, 120)
	d.label("토큰 (선택)", lx, 82, 110)
	hTok := d.mk("EDIT", st.Token, ES_AUTOHSCROLL|0x0020 /*ES_PASSWORD*/ |WS_TABSTOP, WS_EX_CLIENTEDGE, 0)
	mv(hTok, ex, 78, 370, 24)
	d.note("공개 저장소면 비워 두세요. 비공개 저장소는 읽기 권한(Contents: Read) 토큰 필요 — 이 PC의 launcher_state.json 에만 저장됩니다.", ex, 106, 370, 36)
	hAuto := d.mk("BUTTON", "런처를 켤 때 자동으로 업데이트 확인", BS_AUTOCHECKBOX|WS_TABSTOP, 0, 0)
	mv(hAuto, ex, 150, 370, 22)
	setCheck(hAuto, st.AutoUpdate)
	msg := "업데이트 대상: lsp 폴더, catalog.json(리습 목록), " + exeRepoName + ", README.md"
	if localCatalogChanged() {
		msg += "\n※ 이 PC에서 리습 목록을 수정했습니다. 다른 PC에도 쓰려면 catalog.json 을 저장소에 올리세요."
	}
	d.note(msg, ex, 180, 370, 50)
	d.button("확인", IDOK, 310, 258, 95, true)
	d.button("취소", IDCANCEL, 410, 258, 95, false)
	d.onCmd = func(id, code int) {
		if id != IDOK {
			return
		}
		repo := strings.Trim(strings.TrimSpace(getText(hRepo)), "/")
		repo = strings.TrimPrefix(strings.TrimPrefix(repo, "https://github.com/"), "github.com/")
		if repo != "" && strings.Count(repo, "/") != 1 {
			msgBox("저장소는 '계정/저장소이름' 형식으로 입력하세요.", MB_ICONWARNING)
			return
		}
		cat.Update.Repo = repo
		cat.Update.Branch = strings.TrimSpace(getText(hBranch))
		st.Token = strings.TrimSpace(getText(hTok))
		st.AutoUpdate = isChecked(hAuto)
		d.ok, d.done = true, true
	}
	if d.run(hRepo) {
		saveCatalog()
		saveState()
		logf("GitHub 설정 저장: %s (%s)", cat.Update.Repo, branch())
	}
}
