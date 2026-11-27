package main

// AutoCAD '신뢰할 수 있는 위치'(TRUSTEDPATHS) 자동 추가
//   런처 폴더가 신뢰 위치가 아니면 SECURELOAD 때문에 리습 로드가 '파일 로드 취소됨'으로 막힌다.
//   리습을 로드하기 직전에, 런처 폴더(시작하기 세트용 launcher_startup.lsp)와 lsp 폴더가
//   TRUSTEDPATHS 에 없으면 추가하는 줄을 함께 보낸다.
//   (이미 있으면 아무것도 바꾸지 않음. 처음 한 번은 사용자에게 묻고, 설정 창에서 켜고 끌 수 있음)

import (
	"path/filepath"
	"strings"
)

// st.Trust: "" = 아직 안 물어봄, "yes" = 자동 추가, "no" = 하지 않음

func trustDirs() []string { return []string{filepath.Clean(appDir), filepath.Clean(lspDir)} }

// AutoLISP 문자열 안에 넣을 수 있게 \ 와 " 를 이스케이프
func lispStr(s string) string {
	return `"` + strings.NewReplacer(`\`, `\\`, `"`, `\"`).Replace(s) + `"`
}

// wcmatch 특수문자 앞에 ` 를 붙임
func wcEscape(s string) string {
	var b strings.Builder
	for _, r := range s {
		if strings.ContainsRune("#@.*?~[]-,`", r) {
			b.WriteRune('`')
		}
		b.WriteRune(r)
	}
	return b.String()
}

// 처음 한 번 묻기. true 면 신뢰 위치 줄을 붙인다.
func wantTrust() bool {
	if st.Trust == "" {
		if ask(T("trust.001") + strings.Join(trustDirs(), "\n") +
			T("trust.002")) {
			st.Trust = "yes"
		} else {
			st.Trust = "no"
		}
		saveState()
	}
	return st.Trust == "yes"
}

// 폴더가 TRUSTEDPATHS 에 없을 때만 덧붙이는 AutoLISP 줄
//
//	(경로 끝에 ; 나 \ 가 붙은 형태로 등록돼 있어도 찾도록 앞뒤를 구분자로 감싸서 비교)
func trustLines() string {
	var sb strings.Builder
	for _, dir := range trustDirs() {
		u := wcEscape(strings.ToUpper(dir))
		pat := "*;" + u + ";*,*;" + u + "\\;*" // ";경로;" 또는 ";경로\;"
		tp := `(strcat ";" (strcase (getvar "TRUSTEDPATHS")) ";")`
		sb.WriteString(`(if (not (wcmatch ` + tp + ` ` + lispStr(pat) + `)) ` +
			`(setvar "TRUSTEDPATHS" (strcat (getvar "TRUSTEDPATHS") (if (= (getvar "TRUSTEDPATHS") "") "" ";") ` + lispStr(dir) + `)))` + "\n")
	}
	return sb.String()
}
