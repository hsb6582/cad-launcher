"""launcher.ico → src/rsrc_windows_amd64.syso (Go 빌드 때 exe 에 자동으로 들어가는 아이콘 리소스)
외부 도구 없이 COFF .rsrc 를 직접 만든다. 아이콘 그룹 ID = 1 (런처 코드에서 LoadIcon(hInst, 1)).
실행: python dev/icon/make_syso.py
"""
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ICO = ROOT / 'dev/icon/launcher.ico'
OUT = ROOT / 'src/rsrc_windows_amd64.syso'
LANG = 0x0409

ico = ICO.read_bytes()
_, typ, n = struct.unpack_from('<HHH', ico, 0)
assert typ == 1
images, grp = [], struct.pack('<HHH', 0, 1, n)
for i in range(n):
    w, h, cc, _, planes, bpp, size, off = struct.unpack_from('<BBBBHHII', ico, 6 + 16 * i)
    images.append(ico[off:off + size])
    grp += struct.pack('<BBBBHHIH', w, h, cc, 0, planes, bpp, size, i + 1)

# (타입, [(ID, 데이터)])  — ID 오름차순
tree = [(3, [(i + 1, d) for i, d in enumerate(images)]), (14, [(1, grp)])]

def dir_hdr(cnt):
    return struct.pack('<IIHHHH', 0, 0, 0, 0, 0, cnt)

# 크기 계산
root_sz = 16 + 8 * len(tree)
name_sz = sum(16 + 8 * len(v) for _, v in tree)
nleaf = sum(len(v) for _, v in tree)
lang_sz = nleaf * (16 + 8)
data_ent_off = root_sz + name_sz + lang_sz
blob_off = data_ent_off + 16 * nleaf

root = dir_hdr(len(tree)); names = b''; langs = b''; ents = b''; blobs = b''; relocs = []
name_pos = root_sz; lang_pos = root_sz + name_sz; leaf = 0
for t, items in tree:
    root += struct.pack('<II', t, 0x80000000 | (name_pos + len(names)))
    nd = dir_hdr(len(items))
    for rid, data in items:
        nd += struct.pack('<II', rid, 0x80000000 | (lang_pos + len(langs)))
        langs += dir_hdr(1) + struct.pack('<II', LANG, data_ent_off + 16 * leaf)
        pos = blob_off + len(blobs)
        relocs.append(data_ent_off + 16 * leaf)       # OffsetToData 는 RVA → 재배치 필요
        ents += struct.pack('<IIII', pos, len(data), 0, 0)
        blobs += data + b'\0' * (-len(data) % 8)
        leaf += 1
    names += nd
raw = root + names + langs + ents + blobs
assert len(root + names + langs) == data_ent_off

HDR, SEC = 20, 40
raw_ptr = HDR + SEC
rel_ptr = raw_ptr + len(raw)
sym_ptr = rel_ptr + 10 * len(relocs)
out = struct.pack('<HHIIIHH', 0x8664, 1, 0, sym_ptr, 1, 0, 0)
out += struct.pack('<8sIIIIIIHHI', b'.rsrc', 0, 0, len(raw), raw_ptr, rel_ptr, 0, len(relocs), 0, 0x40000040)
out += raw
for r in relocs:
    out += struct.pack('<IIH', r, 0, 3)               # IMAGE_REL_AMD64_ADDR32NB, 심볼 0(.rsrc)
out += struct.pack('<8sIhHBB', b'.rsrc', 0, 1, 0, 3, 0)
out += struct.pack('<I', 4)                           # 빈 문자열 표
OUT.write_bytes(out)
print(OUT, len(out), 'bytes,', n, 'images')
