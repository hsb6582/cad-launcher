#!/usr/bin/env python3
"""배포(main)용 catalog.json 에서 '개발 중' 기능을 뺀다. (lsp 파일은 그대로 둔다)

사용:  python dev/release_filter.py          (main 에서 dev 를 merge 한 직후 실행, catalog.json 을 고침)
       → 고치기 전 전체 목록은 catalog_full.json 으로 저장 (베타 런처 전자제도_도우미-베타.exe 가 받음)
       python dev/release_filter.py --check  (고치지 않고 뺄 목록만 출력)

빼는 기준: 분류 이름·기능 이름·리습 설명에 '개발 중' 또는 '개발중' 이 들어 있으면 제외.
  → 남은 기능이 없는 분류와, 어느 기능도 쓰지 않는 리습(lisps[])도 함께 뺀다.
"""
import json, re, sys
from pathlib import Path

CATALOG = Path(__file__).resolve().parent.parent / "catalog.json"
FULL = CATALOG.with_name("catalog_full.json")  # 베타용 전체 목록 ('개발 중' 포함)
DEV = re.compile(r"개발\s*중")


def main():
    check = "--check" in sys.argv[1:]
    full_text = CATALOG.read_text(encoding="utf-8")
    cat = json.loads(full_text)
    dev_lisps = {l["id"] for l in cat["lisps"] if DEV.search(l.get("desc", ""))}
    removed, cats = [], []
    for ct in cat["categories"]:
        dev_cat = bool(DEV.search(ct["name"]))
        keep = []
        for it in ct["items"]:
            if dev_cat or DEV.search(it.get("name", "")) or it.get("lisp") in dev_lisps:
                removed.append(f"{ct['name']} / {it.get('name')} ({it.get('lisp')} · {it.get('command')})")
            else:
                keep.append(it)
        if keep:
            ct["items"] = keep
            cats.append(ct)
    used = {it.get("lisp") for ct in cats for it in ct["items"]}
    gone = [l["id"] for l in cat["lisps"] if l["id"] not in used]
    print(f"제외할 기능 {len(removed)}개" + ("" if removed else " (없음)"))
    for r in removed:
        print("  -", r)
    if gone:
        print("목록에서 빠지는 리습:", ", ".join(gone))
    if check:
        return
    if removed or not FULL.exists() or not DEV.search(FULL.read_text(encoding="utf-8")):
        FULL.write_text(full_text, encoding="utf-8")
        print("catalog_full.json 저장 (베타용 전체 목록)")
    else:  # 이미 걸러진 catalog.json 으로 다시 실행한 경우: 앞서 저장한 전체 목록을 지우지 않음
        print("catalog_full.json 은 그대로 둠 (이미 걸러진 목록으로 다시 실행)")
    cat["categories"] = cats
    cat["lisps"] = [l for l in cat["lisps"] if l["id"] in used]
    CATALOG.write_text(json.dumps(cat, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("catalog.json 저장 (배포용)")


if __name__ == "__main__":
    main()
