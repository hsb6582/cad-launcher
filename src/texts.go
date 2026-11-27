package main

// 화면 문구는 texts.txt 한 곳에 모아 두고 T("키") 로 불러 쓴다.
// 문구를 고칠 때는 texts.txt 에서 문구를 찾아 따옴표 안만 바꾸고 exe 를 다시 빌드한다.

import (
	_ "embed"
	"strconv"
	"strings"
)

//go:embed texts.txt
var textsRaw string

var texts = parseTexts(textsRaw)

func parseTexts(raw string) map[string]string {
	m := map[string]string{}
	for _, line := range strings.Split(raw, "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		k, v, ok := strings.Cut(line, "=")
		if !ok {
			continue
		}
		s, err := strconv.Unquote(strings.TrimSpace(v))
		if err != nil {
			s = strings.TrimSpace(v) // 따옴표가 깨졌으면 그대로라도 보여 줌
		}
		m[strings.TrimSpace(k)] = s
	}
	return m
}

// 키에 맞는 문구. 없으면 키를 그대로 보여 줘서 빠진 문구를 바로 알 수 있게 한다.
func T(key string) string {
	if s, ok := texts[key]; ok {
		return s
	}
	return "[" + key + "]"
}
