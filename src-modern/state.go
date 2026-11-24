package main

// 설정 저장/불러오기 - 실제 CAD런처(src/app.go)와 같은 파일 형식(launcher_state.json)을 쓴다.

import (
	"encoding/json"
	"os"
)

type State struct {
	Keyword    string                            `json:"keyword"`
	Method     string                            `json:"method"`
	Encoding   string                            `json:"encoding"`
	Cancel     bool                              `json:"cancel"`
	Topmost    bool                              `json:"topmost"`
	Values     map[string]map[string]interface{} `json:"values"`
	AutoUpdate bool                              `json:"autoUpdate"`
	Token      string                            `json:"token,omitempty"`
	Synced     map[string]string                 `json:"synced,omitempty"`
	Installed  map[string]string                 `json:"installed,omitempty"`
}

var st State

func loadState() {
	st = State{Keyword: "AutoCAD LT", Method: "WM_COPYDATA", Encoding: "cp949", Cancel: true, AutoUpdate: true}
	if b, err := os.ReadFile(statePath); err == nil {
		_ = json.Unmarshal(b, &st)
	}
	if st.Values == nil {
		st.Values = map[string]map[string]interface{}{}
	}
	if st.Synced == nil {
		st.Synced = map[string]string{}
	}
	if st.Installed == nil {
		st.Installed = map[string]string{}
	}
}

func saveState() {
	if b, err := json.MarshalIndent(st, "", "  "); err == nil {
		_ = os.WriteFile(statePath, b, 0644)
	}
}
