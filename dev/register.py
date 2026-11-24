#!/usr/bin/env python3
"""리습 머리말(@launcher)을 읽어 catalog.json 에 등록/갱신 (catalog v2: 분류 → 기능)

사용:  python dev/register.py lsp/새리습.lsp [...]   (등록 후 dev/catalog_xlsx.py export 로 엑셀도 갱신)

머리말 예:
;;; @launcher
;;; 리습: MATX                      (생략하면 파일 이름)
;;; 분류: 도면 검수                  (기능별 분류를 안 적으면 이 분류)
;;; 설명: 리습 한 줄 설명
;;; 기능: 수량 대조 | MATX | 평면도·종단·자재내역 수량 비교 [| 분류]
;;; 옵션: MATX | *MATX-TOL* | 허용오차 | number | 0.5 | 도움말
;;; 외부프로그램: MATX뷰어 | tools/MATXView.zip | zip | MATXView.exe | *MATX-EXE* | 1.0
;;; 설명서:
;;;   리습 공통 안내 (두 칸 들여쓰기, 여러 줄)
;;; 기능설명서: MATX
;;;   기능별 설명서
;;; @end
같은 리습·명령어가 이미 목록에 있으면 머리말에 적힌 항목만 갱신하고 나머지는 그대로 둔다.
"""
import json, re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "catalog.json"


def bar(s):
    return [p.strip() for p in s.split("|")]


def okey(var):
    k = re.sub(r"[^A-Za-z0-9]+", "_", var).strip("_").lower()
    return k if k and not k[0].isdigit() else "v_" + k


def parse(path: Path):
    text = path.read_text(encoding="utf-8-sig", errors="replace").replace("\r\n", "\n")
    h = {"id": "", "category": "", "desc": "", "manual": "", "items": [], "tools": []}
    items = {}

    def item(cmd):
        k = cmd.strip().upper()
        if k not in items:
            items[k] = {"name": "", "desc": "", "command": k, "manual": "", "category": ""}
            h["items"].append(items[k])
        return items[k]

    inside, block = False, None
    for raw in text.split("\n"):
        t = raw.strip()
        if not t.startswith(";"):
            if inside:
                break
            continue
        body = t.lstrip(";")
        body = body[1:] if body.startswith(" ") else body
        if body.strip() == "@launcher":
            inside = True
            continue
        if not inside:
            continue
        if body.strip() == "@end":
            break
        if block and (body.startswith("  ") or not body.strip()):
            d, k = block
            line = body[2:] if body.startswith("  ") else ""
            d[k] = line if not d[k] else d[k] + "\n" + line
            continue
        block = None
        if ":" not in body:
            continue
        k, v = (x.strip() for x in body.split(":", 1))
        if k in ("리습", "이름"):
            h["id"] = v
        elif k == "분류":
            h["category"] = v
        elif k == "설명":
            h["desc"] = v
        elif k == "설명서":
            block = (h, "manual")
        elif k == "기능":  # 이름 | 명령어 | 설명 | 분류
            p = bar(v) + ["", "", ""]
            it = item(p[1] or p[0])
            it["name"], it["desc"], it["category"] = p[0], p[2], p[3]
        elif k == "명령":  # (구 형식) 명령어 | 설명
            p = bar(v) + [""]
            it = item(p[0])
            it["desc"] = it["desc"] or p[1]
            it["name"] = it["name"] or p[1] or p[0].upper()
        elif k in ("기능설명서", "명령설명서"):
            block = (item(v), "manual")
        elif k == "옵션":  # 명령어 | 변수 | 표시이름 | 종류 | 기본값 | 도움말
            p = bar(v)
            if len(p) >= 3:
                o = {"key": okey(p[1]), "label": p[2], "type": (p[3] if len(p) > 3 and p[3] else "text"), "var": p[1]}
                if len(p) > 4:
                    o["default"] = (p[4] in ("1", "true")) if o["type"] == "check" else p[4]
                if len(p) > 5 and p[5]:
                    o["hint"] = p[5]
                item(p[0]).setdefault("options", []).append(o)
        elif k == "외부프로그램":  # 이름 | 설치파일 | 종류 | 실행파일 | LISP변수 | 버전 | 설치옵션
            p = bar(v) + [""] * 7
            if p[0] and p[1]:
                t2 = {"name": p[0], "source": p[1], "kind": p[2] or Path(p[1]).suffix.lstrip(".").lower()}
                for f, val in (("exe", p[3]), ("var", p[4]), ("version", p[5]), ("args", p[6])):
                    if val:
                        t2[f] = val
                h["tools"].append(t2)
    funcs = []
    for f in re.findall(r"(?i)\(\s*defun\s+c:([A-Za-z0-9_\-.]+)", text):
        if f.upper() not in funcs and f.upper() != "LO_SHOW":
            funcs.append(f.upper())
    return h, funcs


def register(rel, cat):
    path = (ROOT / rel).resolve()
    rel = path.relative_to(ROOT).as_posix()
    h, funcs = parse(path)
    lid = h["id"] or path.stem
    l = next((x for x in cat["lisps"] if x["id"] == lid or x.get("file") == rel), None)
    if not l:
        l = {"id": lid, "file": rel}
        cat["lisps"].append(l)
    lid = l["id"]
    l["file"] = rel
    for k in ("desc", "manual"):
        if h[k].strip():
            l[k] = h[k].strip()
    if h["tools"]:
        l["tools"] = h["tools"]
    existing = {}
    for ct in cat["categories"]:
        for it in ct["items"]:
            if it.get("lisp") == lid:
                existing[it["command"].upper()] = it
    added = 0
    want = list(h["items"]) + [{"name": f, "desc": "", "command": f, "manual": "", "category": "", "auto": True}
                               for f in funcs if f not in {i["command"] for i in h["items"]}]
    for hi in want:
        cmd = hi["command"]
        it = existing.get(cmd)
        if it:  # 머리말에 적힌 값만 갱신 (머리말 없이 찾은 명령은 건드리지 않음)
            if hi.get("auto"):
                continue
            for k in ("name", "desc", "manual", "options"):
                if hi.get(k):
                    it[k] = hi[k].strip() if isinstance(hi[k], str) else hi[k]
            continue
        cname = hi.get("category") or h["category"] or "새 기능"
        ct = next((c for c in cat["categories"] if c["name"] == cname), None)
        if not ct:
            ct = {"name": cname, "items": []}
            cat["categories"].append(ct)
        new = {"name": hi.get("name") or cmd, "desc": hi.get("desc", ""), "lisp": lid, "command": cmd}
        if hi.get("manual", "").strip():
            new["manual"] = hi["manual"].strip()
        if hi.get("options"):
            new["options"] = hi["options"]
        ct["items"].append(new)
        added += 1
    print(f"{rel}: 리습 '{lid}' / 새 기능 {added}개 / 기존 기능 {len(existing)}개" + (f" / 외부프로그램 {len(h['tools'])}개" if h["tools"] else ""))
    miss = [i["command"] for i in h["items"] if i["command"] not in funcs]
    if miss:
        print("  ※ 파일에 (defun c:) 가 없는 명령:", ", ".join(miss))


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    cat = json.loads(CATALOG.read_text(encoding="utf-8"))
    for rel in sys.argv[1:]:
        register(rel, cat)
    CATALOG.write_text(json.dumps(cat, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
