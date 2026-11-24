package main

// catalog.json(v2) 읽기 + 명령 실행에 필요한 업무 로직.
// 실제 CAD런처(src/catalog.go, src/win32.go)의 로직을 그대로 옮겨왔다.

import (
	"crypto/sha1"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"regexp"
	"strconv"
	"strings"
)

type ChoiceItem struct {
	Value string `json:"value"`
	Label string `json:"label"`
}

type Option struct {
	Key     string            `json:"key"`
	Label   string            `json:"label"`
	Type    string            `json:"type"`
	Hint    string            `json:"hint,omitempty"`
	Default interface{}       `json:"default"`
	Values  []json.RawMessage `json:"values,omitempty"`
	Var     string            `json:"var,omitempty"`
}

func (o Option) items() []ChoiceItem {
	var out []ChoiceItem
	for _, raw := range o.Values {
		var s string
		if json.Unmarshal(raw, &s) == nil {
			out = append(out, ChoiceItem{s, s})
			continue
		}
		var ci ChoiceItem
		if json.Unmarshal(raw, &ci) == nil {
			if ci.Label == "" {
				ci.Label = ci.Value
			}
			out = append(out, ci)
		}
	}
	return out
}

type Tool struct {
	Name    string `json:"name"`
	Version string `json:"version,omitempty"`
	Desc    string `json:"desc,omitempty"`
	Source  string `json:"source"`
	Kind    string `json:"kind"`
	Exe     string `json:"exe,omitempty"`
	Args    string `json:"args,omitempty"`
	Var     string `json:"var,omitempty"`
	Dir     string `json:"dir,omitempty"`
}

type Lisp struct {
	ID     string `json:"id"`
	Desc   string `json:"desc,omitempty"`
	File   string `json:"file,omitempty"`
	Manual string `json:"manual,omitempty"`
	Tools  []Tool `json:"tools,omitempty"`
}

type Item struct {
	Name    string   `json:"name"`
	Desc    string   `json:"desc"`
	Lisp    string   `json:"lisp"`
	Command string   `json:"command"`
	Manual  string   `json:"manual,omitempty"`
	Options []Option `json:"options,omitempty"`
}

type Category struct {
	Name  string `json:"name"`
	Items []Item `json:"items"`
}

type Catalog struct {
	Version    int        `json:"version"`
	Lisps      []Lisp     `json:"lisps"`
	Categories []Category `json:"categories"`
}

var cat Catalog
var loadedSha = map[string]string{}

func loadCatalog() error {
	cat = Catalog{Version: 2}
	b, err := os.ReadFile(catalogPath)
	if err != nil {
		return err
	}
	return json.Unmarshal(b, &cat)
}

func cmdID(command string) string {
	return strings.ToUpper(strings.TrimLeft(strings.TrimSpace(strings.SplitN(command, "\n", 2)[0]), "_."))
}

func lispByID(id string) *Lisp {
	for i := range cat.Lisps {
		if cat.Lisps[i].ID == id {
			return &cat.Lisps[i]
		}
	}
	return nil
}

func findItem(lispID, command string) (*Item, *Category) {
	cid := cmdID(command)
	for ci := range cat.Categories {
		for ii := range cat.Categories[ci].Items {
			it := &cat.Categories[ci].Items[ii]
			if it.Lisp == lispID && cmdID(it.Command) == cid {
				return it, &cat.Categories[ci]
			}
		}
	}
	return nil, nil
}

func itemKey(it *Item) string { return it.Lisp + "|" + cmdID(it.Command) }

func toStr(v interface{}) string {
	switch x := v.(type) {
	case nil:
		return ""
	case string:
		return x
	case float64:
		return strconv.FormatFloat(x, 'f', -1, 64)
	case bool:
		if x {
			return "1"
		}
		return "0"
	}
	return fmt.Sprint(v)
}

// 옵션값(문자열) → AutoLISP 값 표현
func lispValue(o Option, v string) string {
	switch o.Type {
	case "number", "int":
		if _, err := strconv.ParseFloat(v, 64); err == nil {
			return v
		}
		return "nil"
	case "check":
		if v == "1" || strings.EqualFold(v, "true") {
			return "T"
		}
		return "nil"
	case "file", "folder":
		v = strings.ReplaceAll(v, "\\", "/")
	}
	return `"` + strings.NewReplacer(`\`, `\\`, `"`, `\"`).Replace(v) + `"`
}

func gitBlobSha(path string) string {
	b, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	return gitBlobShaBytes(b)
}

func gitBlobShaBytes(b []byte) string {
	h := sha1.New()
	fmt.Fprintf(h, "blob %d\x00", len(b))
	h.Write(b)
	return hex.EncodeToString(h.Sum(nil))
}

var defunRe = regexp.MustCompile(`(?i)\(\s*defun\s+c:([A-Za-z0-9_\-.]+)`)

func lispFuncs(path string) []string {
	if path == "" {
		return nil
	}
	b, err := os.ReadFile(absPath(path))
	if err != nil {
		return nil
	}
	seen := map[string]bool{}
	var out []string
	for _, m := range defunRe.FindAllSubmatch(b, -1) {
		n := strings.ToUpper(string(m[1]))
		if !seen[n] && n != "LO_SHOW" {
			seen[n] = true
			out = append(out, n)
		}
	}
	return out
}
