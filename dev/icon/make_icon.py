"""윈도우95 느낌 런처 아이콘(픽셀 아트) 생성 → dev/icon/launcher.ico (+ 미리보기 png)
16색 기본 팔레트 + 검은 외곽선 + 입체 테두리(밝은 왼쪽 위 / 어두운 오른쪽 아래).
실행: python dev/icon/make_icon.py
"""
from pathlib import Path
from PIL import Image

HERE = Path(__file__).parent
# Win95 16색 팔레트
P = {
    '.': None,              # 투명
    'K': (0, 0, 0),         # 검정
    'W': (255, 255, 255),   # 흰색
    'L': (192, 192, 192),   # 밝은 회색 (창 바탕)
    'D': (128, 128, 128),   # 어두운 회색
    'N': (0, 0, 128),       # 남색 (제목 표시줄)
    'B': (0, 0, 255),       # 파랑
    'C': (0, 128, 128),     # 청록 (바탕화면)
    'c': (0, 255, 255),     # 하늘색
    'R': (255, 0, 0),       # 빨강
    'r': (128, 0, 0),       # 진한 빨강
    'Y': (255, 255, 0),     # 노랑
    'y': (128, 128, 0),     # 황토
    'G': (0, 128, 0),       # 초록
}


def canvas(n):
    return [['.'] * n for _ in range(n)]


def rect(g, x0, y0, x1, y1, ch):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            g[y][x] = ch


def px(g, x, y, ch):
    if 0 <= y < len(g) and 0 <= x < len(g):
        g[y][x] = ch


def line(g, x0, y0, x1, y1, ch):
    dx, dy = abs(x1 - x0), -abs(y1 - y0)
    sx, sy = (1 if x0 < x1 else -1), (1 if y0 < y1 else -1)
    err = dx + dy
    while True:
        px(g, x0, y0, ch)
        if x0 == x1 and y0 == y1:
            break
        e2 = 2 * err
        if e2 >= dy:
            err += dy; x0 += sx
        if e2 <= dx:
            err += dx; y0 += sy


def bevel(g, x0, y0, x1, y1, raised=True):
    """Win95 입체 테두리 (2겹)"""
    a, b, c, d = ('W', 'K', 'L', 'D') if raised else ('D', 'W', 'K', 'L')
    line(g, x0, y0, x1, y0, a); line(g, x0, y0, x0, y1, a)
    line(g, x0, y1, x1, y1, b); line(g, x1, y0, x1, y1, b)
    if raised:
        line(g, x0 + 1, y1 - 1, x1 - 1, y1 - 1, d); line(g, x1 - 1, y0 + 1, x1 - 1, y1 - 1, d)
    else:
        line(g, x0 + 1, y0 + 1, x1 - 1, y0 + 1, c); line(g, x0 + 1, y0 + 1, x0 + 1, y1 - 1, c)
        line(g, x0 + 1, y1 - 1, x1 - 1, y1 - 1, d); line(g, x1 - 1, y0 + 1, x1 - 1, y1 - 1, d)


def icon32():
    g = canvas(32)
    # 창 그림자(디더) — 오른쪽·아래 1칸
    for y in range(4, 29):
        if y % 2: px(g, 29, y, 'K')
    for x in range(2, 30):
        if x % 2: px(g, x, 28, 'K')
    # 창
    rect(g, 0, 2, 28, 27, 'L')
    bevel(g, 0, 2, 28, 27, True)
    # 제목 표시줄
    rect(g, 2, 4, 26, 9, 'N')
    # 제목줄 작은 아이콘(노란 네모)·글자 흉내
    rect(g, 3, 5, 6, 8, 'Y'); line(g, 4, 8, 6, 8, 'y'); line(g, 6, 5, 6, 8, 'y')
    for x in (8, 9, 10, 12, 13, 15, 16, 17):
        px(g, x, 7, 'W')
    # 닫기 버튼
    rect(g, 21, 5, 25, 8, 'L')
    line(g, 21, 5, 25, 5, 'W'); line(g, 21, 5, 21, 8, 'W')
    line(g, 21, 8, 25, 8, 'K'); line(g, 25, 5, 25, 8, 'K')
    px(g, 22, 6, 'K'); px(g, 24, 6, 'K'); px(g, 23, 7, 'K')
    # 도면 영역(움푹 들어간 흰 칸)
    rect(g, 2, 11, 26, 25, 'W')
    bevel(g, 2, 11, 26, 25, False)
    # 격자 점
    for y in range(14, 24, 3):
        for x in range(5, 25, 3):
            px(g, x, y, 'c')
    # 도면: 파란 부품 외형 + 원(구멍)
    line(g, 5, 22, 5, 14, 'B'); line(g, 5, 14, 12, 14, 'B')
    line(g, 12, 14, 12, 18, 'B'); line(g, 12, 18, 20, 18, 'B')
    line(g, 20, 18, 20, 22, 'B'); line(g, 20, 22, 5, 22, 'B')
    for (x, y) in [(8, 16), (9, 16), (7, 17), (10, 17), (7, 18), (10, 18), (8, 19), (9, 19)]:
        px(g, x, y, 'r')
    # 치수선 (초록)
    line(g, 5, 24, 20, 24, 'G'); px(g, 6, 23, 'G'); px(g, 19, 23, 'G')
    # 빨간 십자 커서
    line(g, 21, 13, 21, 17, 'R'); line(g, 19, 15, 23, 15, 'R')
    # 연필 (창 밖으로 걸친 대각선) — 심(검정)·깎인 나무·노란 몸통·쇠붙이·빨간 지우개
    tx, ty = 17, 17                       # 연필 끝(심)
    for y in range(32):
        for x in range(32):
            u = (x - tx) + (y - ty)       # 연필 길이 방향 (0 = 끝)
            v = (x - tx) - (y - ty)       # 폭 방향
            if u < 0 or u > 28:
                continue
            half = 0 if u < 2 else (1 if u < 5 else 3)   # 끝으로 갈수록 가늘게
            if abs(v) > half:
                continue
            edge = abs(v) == half and half > 0
            if u < 2:
                ch = 'K'
            elif u < 5:
                ch = 'K' if edge else 'y'
            elif u < 22:
                ch = 'K' if edge else ('W' if v == -2 else ('y' if v >= 1 else 'Y'))
            elif u < 25:
                ch = 'K' if edge else ('W' if v < 0 else ('D' if v > 0 else 'L'))
            else:
                ch = 'K' if edge or u == 28 else ('r' if v > 0 else 'R')
            px(g, x, y, ch)
    return g


def render(g, scale=1):
    n = len(g)
    im = Image.new('RGBA', (n, n), (0, 0, 0, 0))
    for y in range(n):
        for x in range(n):
            col = P[g[y][x]]
            if col:
                im.putpixel((x, y), col + (255,))
    if scale != 1:
        im = im.resize((n * scale, n * scale), Image.NEAREST)
    return im


if __name__ == '__main__':
    g = icon32()
    base = render(g)
    sizes = [16, 32, 64, 128, 256]   # 32의 배수는 픽셀 그대로 확대, 16은 축소
    imgs = []
    for s in sizes:
        if s % 32 == 0:
            imgs.append(base.resize((s, s), Image.NEAREST))
        else:
            imgs.append(base.resize((s, s), Image.LANCZOS) if s < 32 else base.resize((s, s), Image.NEAREST))
    imgs[-1].save(HERE / 'launcher.ico', sizes=[(s, s) for s in sizes], append_images=imgs[:-1])
    base.save(HERE / 'launcher_32.png')
    # 미리보기: 청록 바탕화면 위에 8배
    prev = Image.new('RGBA', (32 * 8 + 32, 32 * 8 + 32), P['C'] + (255,))
    prev.alpha_composite(render(g, 8), (16, 16))
    prev.save(HERE / 'preview.png')
    print('ok')
