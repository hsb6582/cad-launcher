#!/usr/bin/env python3
"""리습 목록 엑셀 ↔ catalog.json 변환

  python dev/catalog_xlsx.py export            catalog.json → dev/catalog.xlsx (편집용 엑셀 만들기)
  python dev/catalog_xlsx.py import [파일.xlsx]  엑셀 → catalog.json (검사 후 반영)

엑셀 시트: 안내 / 리습 / 명령어 / 옵션 / 외부프로그램
- 행 순서 = 런처 목록 순서. 분류 순서는 '리습' 시트에서 처음 나오는 순서.
- '리습 이름'이 시트를 잇는 열쇠입니다 (리습 이름은 겹치면 안 됨).
- 회색 '확인' 열은 자동 검사용 수식입니다 (변환 때 무시).
"""
import json, re, sys
from pathlib import Path
from openpyxl import Workbook, load_workbook
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from openpyxl.worksheet.datavalidation import DataValidation

ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "catalog.json"
XLSX = ROOT / "dev" / "catalog.xlsx"

FONT = "맑은 고딕"
OPT_TYPES = ["text", "number", "int", "check", "choice", "file", "folder"]
TOOL_KINDS = ["zip", "exe", "msi", "file"]
MAXROW = 400

SHEETS = {
    "리습": [("분류", 16, True), ("리습 이름", 14, True), ("간단한 설명", 44, False), ("리습 파일", 18, True), ("설명서", 90, False)],
    "명령어": [("리습 이름", 14, True), ("명령어", 14, True), ("간단한 설명", 44, False), ("설명서", 90, False)],
    "옵션": [("리습 이름", 14, True), ("명령어", 14, True), ("표시 이름", 20, True), ("LISP 변수", 22, False), ("종류", 10, True),
             ("기본값", 24, False), ("도움말", 22, False), ("선택 항목", 26, False), ("키(변수 없을 때)", 16, False)],
    "외부프로그램": [("리습 이름", 14, True), ("이름", 16, True), ("버전", 8, False), ("설명", 30, False), ("설치 파일", 28, True),
                ("종류", 8, True), ("실행 파일", 28, False), ("설치 옵션", 12, False), ("LISP 변수", 18, False)],
}
CHECKS = {  # 시트: 확인 수식 (행 번호 {r})
    "명령어": '=IF(A{r}="","",IF(COUNTIF(리습!$B:$B,A{r})=0,"리습 시트에 없는 리습 이름",""))',
    "옵션": '=IF(A{r}="","",IF(COUNTIF(리습!$B:$B,A{r})=0,"리습 시트에 없는 리습 이름",'
            'IF(COUNTIFS(명령어!$A:$A,A{r},명령어!$B:$B,B{r})=0,"명령어 시트에 없는 명령","")))',
    "외부프로그램": '=IF(A{r}="","",IF(COUNTIF(리습!$B:$B,A{r})=0,"리습 시트에 없는 리습 이름",""))',
}

HEAD_REQ = PatternFill("solid", fgColor="1F4E78")
HEAD_OPT = PatternFill("solid", fgColor="5B9BD5")
HEAD_CHK = PatternFill("solid", fgColor="A6A6A6")
THIN = Side(style="thin", color="D9D9D9")


def lines(s):
    return max(1, str(s or "").count("\n") + 1)


# ───────────── export ─────────────
def export():
    cat = json.loads(CATALOG.read_text(encoding="utf-8"))
    wb = Workbook()
    guide = wb.active
    guide.title = "안내"
    rows = {k: [] for k in SHEETS}
    for ct in cat.get("categories", []):
        for l in ct.get("lisps", []):
            rows["리습"].append([ct["name"], l["name"], l.get("desc", ""), l.get("file", ""), l.get("manual", "")])
            for m in l.get("commands", []):
                rows["명령어"].append([l["name"], m["command"], m.get("desc", ""), m.get("manual", "")])
                for o in m.get("options", []):
                    vals = []
                    for v in o.get("values", []) or []:
                        vals.append(v if isinstance(v, str) else (v["value"] if v.get("label", v["value"]) == v["value"] else f'{v["value"]}={v["label"]}'))
                    d = o.get("default", "")
                    if isinstance(d, bool):
                        d = "1" if d else "0"
                    rows["옵션"].append([l["name"], m["command"], o.get("label", ""), o.get("var", ""), o.get("type", "text"),
                                        str(d if d is not None else ""), o.get("hint", ""), "\n".join(vals),
                                        "" if o.get("var") else o.get("key", "")])
            for t in l.get("tools", []) or []:
                rows["외부프로그램"].append([l["name"], t["name"], t.get("version", ""), t.get("desc", ""), t["source"],
                                        t.get("kind", "zip"), t.get("exe", ""), t.get("args", ""), t.get("var", "")])

    for name, cols in SHEETS.items():
        ws = wb.create_sheet(name)
        ncol = len(cols)
        for i, (h, w, req) in enumerate(cols, 1):
            c = ws.cell(1, i, h)
            c.font = Font(name=FONT, bold=True, color="FFFFFF")
            c.fill = HEAD_REQ if req else HEAD_OPT
            c.alignment = Alignment(horizontal="center", vertical="center", wrap_text=True)
            ws.column_dimensions[c.column_letter].width = w
        if name in CHECKS:
            c = ws.cell(1, ncol + 1, "확인 (자동)")
            c.font = Font(name=FONT, bold=True, color="FFFFFF")
            c.fill = HEAD_CHK
            c.alignment = Alignment(horizontal="center", vertical="center")
            ws.column_dimensions[c.column_letter].width = 26
        ws.row_dimensions[1].height = 22
        for r, row in enumerate(rows[name], 2):
            for i, v in enumerate(row, 1):
                c = ws.cell(r, i, v)
                c.font = Font(name=FONT, size=10)
                c.alignment = Alignment(vertical="top", wrap_text=True)
                c.border = Border(bottom=THIN)
            ws.row_dimensions[r].height = min(15 * max(lines(v) for v in row) + 3, 409)
        for r in range(2, MAXROW + 1):
            if name in CHECKS:
                c = ws.cell(r, ncol + 1, CHECKS[name].format(r=r))
                c.font = Font(name=FONT, size=9, color="C00000")
                c.alignment = Alignment(vertical="top")
            if r > len(rows[name]) + 1:
                for i in range(1, ncol + 1):
                    ws.cell(r, i).font = Font(name=FONT, size=10)
                    ws.cell(r, i).alignment = Alignment(vertical="top", wrap_text=True)
        ws.freeze_panes = "C2" if name != "리습" else "C2"
        ws.auto_filter.ref = f"A1:{ws.cell(1, ncol).column_letter}{max(len(rows[name]) + 1, 2)}"
        # 입력 목록
        if name != "리습":
            dv = DataValidation(type="list", formula1=f"=리습!$B$2:$B${MAXROW}", allow_blank=True,
                                showErrorMessage=True, errorTitle="리습 이름", error="'리습' 시트에 있는 리습 이름을 고르세요.")
            ws.add_data_validation(dv)
            dv.add(f"A2:A{MAXROW}")
        if name == "옵션":
            dv = DataValidation(type="list", formula1='"' + ",".join(OPT_TYPES) + '"', allow_blank=True)
            ws.add_data_validation(dv)
            dv.add(f"E2:E{MAXROW}")
        if name == "외부프로그램":
            dv = DataValidation(type="list", formula1='"' + ",".join(TOOL_KINDS) + '"', allow_blank=True)
            ws.add_data_validation(dv)
            dv.add(f"F2:F{MAXROW}")

    g = [
        ("CAD 런처 리습 목록 편집", "title"),
        ("이 파일을 고친 뒤 Claude 에게 올려 주면, 런처 목록(catalog.json)에 반영해 GitHub 에 올립니다. 각 PC 런처는 다음 실행 때 자동으로 받습니다.", ""),
        ("", ""),
        ("시트", "h"),
        ("리습 — 기능 분류, 리습 이름, 설명, 파일(lsp/파일명.lsp), 설명서. 분류 순서는 이 시트에서 처음 나오는 순서입니다.", ""),
        ("명령어 — 리습마다 명령어와 설명·설명서. 행 순서가 런처 목록 순서입니다.", ""),
        ("옵션 — 실행 전에 값을 바꿀 수 있는 항목. 있으면 런처 오른쪽 '옵션' 칸에 나오고, 없으면 칸이 비어 있습니다.", ""),
        ("외부프로그램 — 리습과 함께 쓰는 프로그램(설치 파일). 런처에서 '외부 프로그램 설치' 버튼으로 설치합니다.", ""),
        ("", ""),
        ("편집 규칙", "h"),
        ("진한 파란색 제목 = 꼭 채울 칸, 밝은 파란색 제목 = 비워도 되는 칸, 회색 '확인 (자동)' 열 = 오타 검사 (고치지 마세요).", ""),
        ("'리습 이름'이 시트를 잇는 열쇠입니다. 리습 이름을 바꾸면 명령어·옵션·외부프로그램 시트의 같은 이름도 함께 바꾸세요.", ""),
        ("설명서 칸 안에서 줄을 바꾸려면 Alt + Enter.", ""),
        ("행을 지우면 목록에서 빠집니다. 리습 파일 자체는 지워지지 않습니다.", ""),
        ("새 리습을 넣을 때는 리습 파일(.lsp)도 함께 올려 주세요.", ""),
        ("", ""),
        ("옵션 시트", "h"),
        ("LISP 변수: 리습 위쪽의 (setq *변수* 값) 이름. 런처가 실행 직전에 그 값을 바꿔 줍니다. 예: *TEE-RADIUS*", ""),
        ("종류: text(문자) / number(실수) / int(정수) / check(체크, 기본값 1 또는 0) / choice(선택목록) / file(파일 경로) / folder(폴더 경로)", ""),
        ("선택 항목: choice 일 때만. 한 줄에 하나씩 '값=표시명' (예: all=도면 전체). 기본값에는 '값'을 적습니다.", ""),
        ("키(변수 없을 때): LISP 변수 없이 옵션 파일 방식((LO:get \"키\"))으로 읽을 때만 적습니다.", ""),
        ("", ""),
        ("외부프로그램 시트", "h"),
        ("설치 파일: 저장소 안 경로(tools/MATX.zip) 또는 https 주소. 50MB 넘는 파일은 GitHub Releases 주소를 쓰세요.", ""),
        ("종류: zip(압축 풀기, 권장) / exe·msi(설치 프로그램 실행) / file(파일 하나 복사)", ""),
        ("실행 파일: zip·file 은 설치 폴더 안 파일 이름(예: MATX.exe), exe·msi 는 설치 후 확인할 경로(예: %ProgramFiles%\\MATX\\MATX.exe)", ""),
        ("버전: 올리면 이미 설치한 PC에 '새 버전 있음'으로 표시됩니다.", ""),
        ("", ""),
        ("예시 (옵션 시트 한 줄)", "h"),
        ("GGv2 | MARKTEE | 원 반지름 | *TEE-RADIUS* | number | 1.0 | MARKLINE 과 같은 값으로", ""),
    ]
    guide.column_dimensions["A"].width = 130
    for r, (t, kind) in enumerate(g, 1):
        c = guide.cell(r, 1, t)
        c.alignment = Alignment(wrap_text=True, vertical="top")
        if kind == "title":
            c.font = Font(name=FONT, size=14, bold=True, color="1F4E78")
            guide.row_dimensions[r].height = 24
        elif kind == "h":
            c.font = Font(name=FONT, size=11, bold=True, color="1F4E78")
        else:
            c.font = Font(name=FONT, size=10)
    wb.active = 1
    XLSX.parent.mkdir(exist_ok=True)
    wb.save(XLSX)
    print(f"{XLSX.relative_to(ROOT)} 저장: 리습 {len(rows['리습'])} / 명령 {len(rows['명령어'])} / 옵션 {len(rows['옵션'])} / 외부프로그램 {len(rows['외부프로그램'])}")


# ───────────── import ─────────────
def sheet_rows(wb, name):
    ws = wb[name]
    n = len(SHEETS[name])
    out = []
    for r in range(2, ws.max_row + 1):
        vals = []
        for i in range(1, n + 1):
            v = ws.cell(r, i).value
            vals.append("" if v is None else (str(v).strip() if not isinstance(v, bool) else ("1" if v else "0")))
        if any(vals):
            out.append((r, vals))
    return out


def num_str(v):
    # 엑셀이 1.0 을 1 로 바꾼 경우 등은 그대로 문자열로 둔다
    return v


def do_import(path):
    wb = load_workbook(path, data_only=False)
    for s in SHEETS:
        if s not in wb.sheetnames:
            sys.exit(f"'{s}' 시트가 없습니다.")
    errs, warns = [], []
    old = json.loads(CATALOG.read_text(encoding="utf-8")) if CATALOG.exists() else {}
    cats, lisps = [], {}
    for r, (c, name, desc, f, man) in sheet_rows(wb, "리습"):
        if not c or not name:
            errs.append(f"리습 {r}행: 분류와 리습 이름은 꼭 필요합니다")
            continue
        if name in lisps:
            errs.append(f"리습 {r}행: 리습 이름 '{name}' 이 겹칩니다")
            continue
        f = f.replace("\\", "/")
        if f and not (ROOT / f).exists():
            warns.append(f"리습 {r}행: 파일 '{f}' 이 저장소에 없습니다 (리습 파일도 올려 주세요)")
        l = {"name": name, "desc": desc, "file": f, "commands": []}
        if man:
            l["manual"] = man.replace("\r\n", "\n")
        lisps[name] = (c, l)
        ct = next((x for x in cats if x["name"] == c), None)
        if not ct:
            ct = {"name": c, "lisps": []}
            cats.append(ct)
        ct["lisps"].append(l)
    cmds = {}
    for r, (ln, cmd, desc, man) in sheet_rows(wb, "명령어"):
        if ln not in lisps:
            errs.append(f"명령어 {r}행: '리습' 시트에 없는 리습 이름 '{ln}'")
            continue
        if not cmd:
            errs.append(f"명령어 {r}행: 명령어가 비어 있습니다")
            continue
        key = (ln, cmd.upper())
        if key in cmds:
            errs.append(f"명령어 {r}행: {ln} 의 명령 '{cmd}' 이 겹칩니다")
            continue
        m = {"command": cmd if "\\n" in cmd else cmd.upper(), "desc": desc}
        m["command"] = m["command"].replace("\\n", "\n")
        if man:
            m["manual"] = man.replace("\r\n", "\n")
        cmds[key] = m
        lisps[ln][1]["commands"].append(m)
    for r, (ln, cmd, label, var, typ, d, hint, choices, key) in sheet_rows(wb, "옵션"):
        m = cmds.get((ln, cmd.upper()))
        if not m:
            errs.append(f"옵션 {r}행: 명령어 시트에 없는 '{ln} / {cmd}'")
            continue
        typ = typ or "text"
        if typ not in OPT_TYPES:
            errs.append(f"옵션 {r}행: 종류 '{typ}' 는 {', '.join(OPT_TYPES)} 중 하나여야 합니다")
            continue
        if not var and not key:
            errs.append(f"옵션 {r}행: LISP 변수나 키 중 하나는 있어야 합니다")
            continue
        k = key or re.sub(r"[^A-Za-z0-9]+", "_", var).strip("_").lower()
        if not k or k[0].isdigit():
            k = "v_" + k
        o = {"key": k, "label": label or var or k, "type": typ}
        if var:
            o["var"] = var
        if typ == "check":
            o["default"] = d.lower() in ("1", "true", "예", "y")
        else:
            o["default"] = d
            if typ in ("number", "int") and d:
                try:
                    float(d)
                except ValueError:
                    errs.append(f"옵션 {r}행: 기본값 '{d}' 이 숫자가 아닙니다")
        if hint:
            o["hint"] = hint
        if typ == "choice":
            vals = []
            for ln2 in choices.replace("\r", "").split("\n"):
                ln2 = ln2.strip()
                if not ln2:
                    continue
                if "=" in ln2:
                    v, lb = (x.strip() for x in ln2.split("=", 1))
                    vals.append(v if v == lb else {"value": v, "label": lb})
                else:
                    vals.append(ln2)
            if not vals:
                errs.append(f"옵션 {r}행: choice 는 선택 항목이 필요합니다")
            o["values"] = vals
        m.setdefault("options", []).append(o)
    for r, (ln, name, ver, desc, src, kind, exe, args, var) in sheet_rows(wb, "외부프로그램"):
        if ln not in lisps:
            errs.append(f"외부프로그램 {r}행: '리습' 시트에 없는 리습 이름 '{ln}'")
            continue
        if not name or not src:
            errs.append(f"외부프로그램 {r}행: 이름과 설치 파일은 꼭 필요합니다")
            continue
        kind = kind or Path(src).suffix.lstrip(".").lower() or "zip"
        if kind not in TOOL_KINDS:
            errs.append(f"외부프로그램 {r}행: 종류 '{kind}' 는 {', '.join(TOOL_KINDS)} 중 하나여야 합니다")
            continue
        src = src.replace("\\", "/") if not src.startswith("http") else src
        if not src.startswith("http") and not (ROOT / src).exists():
            warns.append(f"외부프로그램 {r}행: '{src}' 이 저장소에 없습니다 (설치 파일도 올려 주세요)")
        t = {"name": name, "source": src, "kind": kind}
        for f, v in (("version", ver), ("desc", desc), ("exe", exe), ("args", args), ("var", var)):
            if v:
                t[f] = v
        lisps[ln][1].setdefault("tools", []).append(t)
    for w in warns:
        print("주의:", w)
    if errs:
        print("\n".join("오류: " + e for e in errs))
        sys.exit("반영하지 않았습니다. 위 오류를 고쳐 주세요.")
    new = {"version": int(old.get("version", 1)), "categories": cats}
    CATALOG.write_text(json.dumps(new, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    n = sum(len(l["commands"]) for c in cats for l in c["lisps"])
    print(f"catalog.json 반영: 분류 {len(cats)} / 리습 {len(lisps)} / 명령 {n}")


if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in ("export", "import"):
        sys.exit(__doc__)
    if sys.argv[1] == "export":
        export()
    else:
        do_import(Path(sys.argv[2]) if len(sys.argv) > 2 else XLSX)
