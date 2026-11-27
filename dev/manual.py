"""설명서 문구를 catalog.json 전체를 읽지 않고 찾고 고치는 도구 (토큰 절약용).

  python dev/manual.py find 단어          설명서·기능 이름·설명에서 단어가 들어간 곳 찾기
  python dev/manual.py show MATCAL        명령어(또는 리습 ID)의 문구 전부 보기
  python dev/manual.py set MATCAL warn "새 문구"
  python dev/manual.py set MATCAL steps "1단계|2단계|3단계"   (steps 는 | 로 나눔)
  python dev/manual.py set lisp:MATX manual "리습 공통 안내"

  고칠 수 있는 칸: name, desc, manual, when, steps, warn  (리습은 desc, manual)
  문구 안의 줄바꿈은 \\n 으로 쓴다. 고친 뒤 catalog_xlsx.py export → 커밋·push (exe 빌드 필요 없음)
"""
import json
import sys
from pathlib import Path

CATALOG = Path(__file__).resolve().parent.parent / "catalog.json"
FIELDS = ("name", "desc", "when", "steps", "warn", "manual")


def load():
    return json.loads(CATALOG.read_text(encoding="utf-8"))


def save(cat):
    CATALOG.write_text(json.dumps(cat, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def targets(cat):
    """(표시 이름, 항목 dict) 목록: 리습은 lisp:ID, 기능은 명령어"""
    for l in cat["lisps"]:
        yield "lisp:" + l["id"], l
    for c in cat["categories"]:
        for it in c["items"]:
            yield it.get("command") or it.get("name"), it


def find_target(cat, key):
    hits = [d for k, d in targets(cat) if k.upper() == key.upper()]
    if not hits:
        sys.exit(f"'{key}' 를 찾지 못함 (명령어 또는 lisp:리습ID)")
    return hits


def show_value(v):
    if isinstance(v, list):
        return " | ".join(v)
    return str(v).replace("\n", "\\n")


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    cmd = sys.argv[1]
    cat = load()
    if cmd == "find":
        word = sys.argv[2]
        for k, d in targets(cat):
            for f in FIELDS:
                v = d.get(f)
                if v and word in show_value(v):
                    print(f"{k}.{f}: {show_value(v)[:200]}")
    elif cmd == "show":
        for d in find_target(cat, sys.argv[2]):
            for f in FIELDS:
                if d.get(f):
                    print(f"{f}: {show_value(d[f])}")
            print("---")
    elif cmd == "set":
        if len(sys.argv) < 5:
            sys.exit(__doc__)
        key, field, value = sys.argv[2], sys.argv[3], sys.argv[4]
        if field not in FIELDS:
            sys.exit(f"고칠 수 있는 칸: {', '.join(FIELDS)}")
        value = value.replace("\\n", "\n")
        for d in find_target(cat, key):
            if field == "steps":
                d[field] = [s.strip() for s in value.split("|") if s.strip()]
            elif value == "":
                d.pop(field, None)
            else:
                d[field] = value
        save(cat)
        print(f"{key}.{field} 수정 완료")
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
