#!/usr/bin/env python3
"""기능 목록 엑셀(한 시트) ↔ catalog.json

  python dev/catalog_xlsx.py export              catalog.json → dev/catalog.xlsx
  python dev/catalog_xlsx.py import [파일.xlsx]   엑셀 → catalog.json (검사 후 반영)

엑셀은 '기능 목록' 시트 하나: 한 행 = 기능 하나, 행 순서 = 런처 목록 순서.
옵션·외부 프로그램·리습 공통 안내는 엑셀에 없고 catalog.json 에 그대로 보존됩니다.
(리습 + 명령어 가 같은 행끼리 옵션이 이어짐)
"""
import json, sys
from pathlib import Path
from openpyxl import Workbook, load_workbook
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from openpyxl.worksheet.datavalidation import DataValidation

ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "catalog.json"
XLSX = ROOT / "dev" / "catalog.xlsx"
FONT = "맑은 고딕"
MAXROW = 300
SHEET = "기능 목록"
COLS = [("분류", 16), ("기능 이름", 26), ("간단한 설명", 46), ("리습", 10), ("명령어", 13), ("설명서", 80)]
EDIT = PatternFill("solid", fgColor="1F4E78")
KEYF = PatternFill("solid", fgColor="808080")
ROWFILL = PatternFill("solid", fgColor="F2F2F2")
THIN = Side(style="thin", color="D9D9D9")


def export():
    cat = json.loads(CATALOG.read_text(encoding="utf-8"))
    wb = Workbook()
    ws = wb.active
    ws.title = SHEET
    for i, (h, w) in enumerate(COLS, 1):
        c = ws.cell(1, i, h)
        c.font = Font(name=FONT, bold=True, color="FFFFFF")
        c.fill = KEYF if h in ("리습", "명령어") else EDIT
        c.alignment = Alignment(horizontal="center", vertical="center")
        ws.column_dimensions[c.column_letter].width = w
    chk = ws.cell(1, 7, "확인")
    chk.font = Font(name=FONT, bold=True, color="FFFFFF")
    chk.fill = KEYF
    ws.column_dimensions["G"].width = 22
    ws.row_dimensions[1].height = 22
    r = 2
    for ct in cat["categories"]:
        for it in ct["items"]:
            row = [ct["name"], it["name"], it.get("desc", ""), it.get("lisp", ""), it["command"].replace("\n", "\\n"), it.get("manual", "")]
            for i, v in enumerate(row, 1):
                c = ws.cell(r, i, v)
                c.font = Font(name=FONT, size=10, color="595959" if i in (4, 5) else "000000")
                c.alignment = Alignment(vertical="top", wrap_text=(i in (3, 6)))
                c.border = Border(bottom=THIN)
                if i in (4, 5):
                    c.fill = ROWFILL
            ws.row_dimensions[r].height = 30  # 설명서는 셀을 눌러 수식 입력줄에서 보기 (행이 너무 커지지 않게)
            r += 1
    for rr in range(2, MAXROW + 1):
        c = ws.cell(rr, 7, f'=IF(B{rr}="","",IF(A{rr}="","분류를 적으세요",IF(AND(D{rr}<>"",COUNTIF(리습목록!$A:$A,D{rr})=0),"없는 리습",IF(E{rr}="","명령어를 적으세요",IF(COUNTIFS($D$2:$D${MAXROW},D{rr},$E$2:$E${MAXROW},E{rr})>1,"같은 기능이 두 번","")))))')
        c.font = Font(name=FONT, size=9, color="C00000")
        for i in range(1, 7):
            if rr >= r:
                ws.cell(rr, i).font = Font(name=FONT, size=10)
                ws.cell(rr, i).alignment = Alignment(vertical="top", wrap_text=(i in (3, 6)))
    ws.freeze_panes = "C2"
    ws.auto_filter.ref = f"A1:F{r - 1}"
    # 리습 목록(드롭다운용)
    ls = wb.create_sheet("리습목록")
    ls.cell(1, 1, "리습").font = Font(name=FONT, bold=True)
    ls.cell(1, 2, "파일").font = Font(name=FONT, bold=True)
    ls.cell(1, 3, "설명").font = Font(name=FONT, bold=True)
    for i, l in enumerate(cat["lisps"], 2):
        for j, v in enumerate([l["id"], l.get("file", ""), l.get("desc", "")], 1):
            ls.cell(i, j, v).font = Font(name=FONT, size=10)
    ls.column_dimensions["A"].width = 12
    ls.column_dimensions["B"].width = 20
    ls.column_dimensions["C"].width = 50
    dv = DataValidation(type="list", formula1=f"=리습목록!$A$2:$A${max(len(cat['lisps']) + 1, 2) + 20}", allow_blank=True,
                        showErrorMessage=True, errorTitle="리습", error="리습목록 시트에 있는 리습만 고를 수 있습니다.")
    ws.add_data_validation(dv)
    dv.add(f"D2:D{MAXROW}")
    cats = []
    for ct in cat["categories"]:
        if ct["name"] not in cats:
            cats.append(ct["name"])
    dv2 = DataValidation(type="list", formula1='"' + ",".join(cats) + '"', allow_blank=True, showErrorMessage=False)
    ws.add_data_validation(dv2)
    dv2.add(f"A2:A{MAXROW}")
    # 안내
    g = wb.create_sheet("안내")
    g.column_dimensions["A"].width = 120
    tips = [
        ("CAD 런처 기능 목록 편집", 14, True),
        ("한 행이 런처 목록의 기능 하나입니다. 고친 뒤 이 파일을 Claude 에게 올려 주면 반영해서 GitHub 에 올립니다.", 10, False),
        ("", 10, False),
        ("고치는 칸 (파란 제목)", 11, True),
        ("• 분류: 런처 목록의 묶음 이름. 새 이름을 적으면 새 분류가 생깁니다. 분류 순서는 위에서 처음 나오는 순서.", 10, False),
        ("• 기능 이름: 런처 목록에 보이는 이름.  • 간단한 설명: 이름 옆·설명서 위에 보이는 한 줄.", 10, False),
        ("• 설명서: 오른쪽 설명서 창 내용. 셀 안 줄바꿈은 Alt + Enter.", 10, False),
        ("• 행 순서 = 목록 순서. 행을 잘라내서 끼워 넣으면 순서가 바뀝니다. 행을 지우면 목록에서 빠집니다.", 10, False),
        ("", 10, False),
        ("회색 칸 (리습 · 명령어)", 11, True),
        ("• 어느 리습의 어떤 명령을 실행할지 정합니다. 보통은 그대로 두세요.", 10, False),
        ("• 같은 리습에 있는 다른 명령을 목록에 추가할 때만 새 행에 적습니다.", 10, False),
        ("• 오른쪽 '확인' 칸에 빨간 글씨가 나오면 그 행을 고쳐 주세요.", 10, False),
        ("", 10, False),
        ("이 엑셀에 없는 것", 11, True),
        ("• 옵션, 외부 프로그램, 리습 공통 안내는 그대로 유지됩니다. 바꾸고 싶으면 대화로 말해 주세요.", 10, False),
        ("  예) \"거리값 수정에 글자 높이 옵션 빼줘\", \"MATX 프로그램 버전 1.1로 올려줘\"", 10, False),
        ("• 이름 하나만 바꾸는 정도라면 엑셀 없이 대화로 \"○○을 △△로 바꿔줘\" 라고 해도 됩니다.", 10, False),
    ]
    for i, (t, size, bold) in enumerate(tips, 1):
        c = g.cell(i, 1, t)
        c.font = Font(name=FONT, size=size, bold=bold, color="1F4E78" if bold else "000000")
        c.alignment = Alignment(wrap_text=True, vertical="top")
    XLSX.parent.mkdir(exist_ok=True)
    wb.save(XLSX)
    print(f"{XLSX.relative_to(ROOT)} 저장: 기능 {r - 2}개")


def do_import(path):
    wb = load_workbook(path)
    if SHEET not in wb.sheetnames:
        sys.exit(f"'{SHEET}' 시트가 없습니다.")
    ws = wb[SHEET]
    cat = json.loads(CATALOG.read_text(encoding="utf-8"))
    lisp_ids = {l["id"] for l in cat["lisps"]}
    old = {}
    for ct in cat["categories"]:
        for it in ct["items"]:
            old[(it.get("lisp", ""), it["command"].split("\n")[0].strip("_.").upper())] = it
    errs, seen, cats = [], set(), []
    for r in range(2, ws.max_row + 1):
        v = [("" if ws.cell(r, i).value is None else str(ws.cell(r, i).value).strip()) for i in range(1, 7)]
        if not any(v):
            continue
        cname, name, desc, lisp, cmd, man = v
        if not name:
            errs.append(f"{r}행: 기능 이름이 비어 있습니다")
            continue
        if not cname:
            errs.append(f"{r}행: 분류가 비어 있습니다")
            continue
        if lisp and lisp not in lisp_ids:
            errs.append(f"{r}행: 리습 '{lisp}' 이 없습니다 (새 리습이면 .lsp 파일을 함께 올려 주세요)")
            continue
        if not cmd:
            errs.append(f"{r}행: 명령어가 비어 있습니다")
            continue
        cmd = cmd.replace("\\n", "\n")
        key = (lisp, cmd.split("\n")[0].strip("_.").upper())
        if key in seen:
            errs.append(f"{r}행: {lisp} · {key[1]} 이 두 번 들어 있습니다")
            continue
        seen.add(key)
        it = {"name": name, "desc": desc, "lisp": lisp, "command": cmd if "\n" in cmd else cmd.upper()}
        if man:
            it["manual"] = man.replace("\r\n", "\n")
        if key in old and old[key].get("options"):
            it["options"] = old[key]["options"]  # 옵션은 그대로 이어받음
        ct = next((c for c in cats if c["name"] == cname), None)
        if not ct:
            ct = {"name": cname, "items": []}
            cats.append(ct)
        ct["items"].append(it)
    if errs:
        print("\n".join("오류: " + e for e in errs))
        sys.exit("반영하지 않았습니다. 위 행을 고쳐 주세요.")
    removed = [f"{k[0]} · {k[1]}" for k in old if k not in seen]
    cat["categories"] = cats
    CATALOG.write_text(json.dumps(cat, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"catalog.json 반영: 분류 {len(cats)} / 기능 {len(seen)}")
    if removed:
        print("목록에서 빠진 기능:", ", ".join(removed))


if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in ("export", "import"):
        sys.exit(__doc__)
    export() if sys.argv[1] == "export" else do_import(Path(sys.argv[2]) if len(sys.argv) > 2 else XLSX)
