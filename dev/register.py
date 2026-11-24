#!/usr/bin/env python3
"""리습 머리말(@launcher)을 읽어 catalog.json 에 등록/갱신한다.

사용:  python dev/register.py lsp/새리습.lsp [lsp/다른.lsp ...]
- 리습 파일은 lsp/ 폴더에 둔다. 머리말 규칙은 README '리습 머리말' 참고 (런처의 '리습 추가'와 같은 규칙).
- 같은 파일이 이미 목록에 있으면 머리말에 적힌 항목만 갱신하고, 나머지(직접 편집한 내용)는 그대로 둔다.
- 머리말이 없어도 (defun c:이름) 명령은 자동 등록된다.
"""
import json, re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "catalog.json"


def bar(s):
    return [p.strip() for p in s.split("|")]


def parse(path: Path):
    text = path.read_text(encoding="utf-8-sig", errors="replace").replace("\r\n", "\n")
    h = {"category": "", "name": "", "desc": "", "manual": "", "cmds": [], "tools": []}
    cmds = {}

    def cmd(name):
        cid = name.strip().upper()
        if cid not in cmds:
            cmds[cid] = {"command": cid, "desc": "", "manual": ""}
            h["cmds"].append(cmds[cid])
        return cmds[cid]

    inside, block = False, None  # block = (dict, key)
    for raw in text.split("\n"):
        t = raw.strip()
        if not t.startswith(";"):
            if inside:
                break
            continue
        body = t.lstrip(";")
        if body.startswith(" "):
            body = body[1:]
        if body.strip() == "@launcher":
            inside = True
            continue
        if not inside:
            continue
        if body.strip() == "@end":
            break
        if block and (body.startswith("  ") or body.strip() == ""):
            d, k = block
            line = body[2:] if body.startswith("  ") else ""
            d[k] = line if d[k] == "" else d[k] + "\n" + line
            continue
        block = None
        if ":" not in body:
            continue
        k, v = (x.strip() for x in body.split(":", 1))
        if k == "분류":
            h["category"] = v
        elif k == "이름":
            h["name"] = v
        elif k == "설명":
            h["desc"] = v
        elif k == "설명서":
            block = (h, "manual")
        elif k == "명령":
            p = bar(v)
            m = cmd(p[0])
            if len(p) > 1:
                m["desc"] = p[1]
        elif k == "명령설명서":
            block = (cmd(v), "manual")
        elif k == "옵션":  # 명령 | 변수 | 표시이름 | 종류 | 기본값 | 도움말
            p = bar(v)
            if len(p) >= 3:
                key = re.sub(r"[^A-Za-z0-9]+", "_", p[1]).strip("_")
                if not key or key[0].isdigit():
                    key = "v_" + key
                o = {"key": key, "label": p[2], "type": (p[3] if len(p) > 3 and p[3] else "text"), "var": p[1]}
                if len(p) > 4:
                    o["default"] = (p[4] in ("1", "true")) if o["type"] == "check" else p[4]
                if len(p) > 5 and p[5]:
                    o["hint"] = p[5]
                cmd(p[0]).setdefault("options", []).append(o)
        elif k == "외부프로그램":  # 이름 | 설치파일 | 종류 | 실행파일 | LISP변수 | 버전 | 설치옵션
            p = bar(v) + [""] * 7
            if p[0] and p[1]:
                kind = p[2] or Path(p[1]).suffix.lstrip(".").lower()
                tool = {"name": p[0], "source": p[1], "kind": kind}
                for f, val in (("exe", p[3]), ("var", p[4]), ("version", p[5]), ("args", p[6])):
                    if val:
                        tool[f] = val
                h["tools"].append(tool)
    h["manual"] = h["manual"].strip()
    for m in h["cmds"]:
        m["manual"] = m["manual"].strip()
    funcs = []
    for f in re.findall(r"(?i)\(\s*defun\s+c:([A-Za-z0-9_\-.]+)", text):
        f = f.upper()
        if f not in funcs and f != "LO_SHOW":
            funcs.append(f)
    return h, funcs


def register(rel: str, cat: dict):
    path = (ROOT / rel).resolve()
    rel = path.relative_to(ROOT).as_posix()
    h, funcs = parse(path)
    found = None
    for ct in cat["categories"]:
        for l in ct["lisps"]:
            if l.get("file") == rel:
                found = (ct, l)
    if found:
        ct, l = found
    else:
        cname = h["category"] or "새 리습"
        ct = next((c for c in cat["categories"] if c["name"] == cname), None)
        if ct is None:
            ct = {"name": cname, "lisps": []}
            cat["categories"].append(ct)
        l = {"name": h["name"] or path.stem, "desc": "", "file": rel, "commands": []}
        ct["lisps"].append(l)
    for k in ("name", "desc", "manual"):
        if h[k]:
            l[k] = h[k]
    if h["tools"]:
        l["tools"] = h["tools"]
    have = {m["command"].upper(): m for m in l["commands"]}
    for m in h["cmds"]:
        old = have.get(m["command"])
        if old:
            for k in ("desc", "manual", "options"):
                if m.get(k):
                    old[k] = m[k]
        else:
            l["commands"].append({k: v for k, v in m.items() if v not in ("", None)})
            have[m["command"]] = m
    for f in funcs:
        if f not in have:
            l["commands"].append({"command": f, "desc": ""})
            have[f] = True
    missing = [c for c in have if c not in funcs]
    print(f"{rel}: 분류 '{ct['name']}' / 리습 '{l['name']}' / 명령 {len(l['commands'])}개"
          + (f" / 도구 {len(l.get('tools', []))}개" if l.get("tools") else ""))
    if missing:
        print(f"  ※ 파일에 (defun c:) 가 없는 명령: {', '.join(missing)}")


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    cat = json.loads(CATALOG.read_text(encoding="utf-8"))
    for rel in sys.argv[1:]:
        register(rel, cat)
    cat["version"] = int(cat.get("version", 1))
    CATALOG.write_text(json.dumps(cat, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
