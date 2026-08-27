#!/usr/bin/env python3
"""生成 MiniBrowser 应用图标：深色渐变圆角矩形 + 极简指南针，输出 1024x1024 PNG"""
from PIL import Image, ImageDraw
import math
import sys

SIZE = 1024
OUT = sys.argv[1] if len(sys.argv) > 1 else "AppIcon.png"

# 圆角矩形遮罩（macOS squircle 近似）
mask = Image.new("L", (SIZE, SIZE), 0)
md = ImageDraw.Draw(mask)
md.rounded_rectangle([0, 0, SIZE - 1, SIZE - 1], radius=int(SIZE * 0.2237), fill=255)

# 背景：上浅下深的灰色渐变（呼应新标签页）
top, bot = (62, 59, 59), (30, 28, 28)
grad = Image.new("RGB", (1, SIZE))
for y in range(SIZE):
    t = y / (SIZE - 1)
    grad.putpixel((0, y), tuple(round(top[i] + (bot[i] - top[i]) * t) for i in range(3)))
img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
img.paste(grad.resize((SIZE, SIZE)).convert("RGBA"), (0, 0), mask)

d = ImageDraw.Draw(img)
cx = cy = SIZE / 2

# 指南针外环
ring_r = SIZE * 0.30
d.ellipse([cx - ring_r, cy - ring_r, cx + ring_r, cy + ring_r],
          outline=(255, 255, 255, 225), width=round(SIZE * 0.028))

# 指针（指向东北方向的两半菱形：蓝色指向 + 白色尾部）
def rot(px, py, deg):
    r = math.radians(deg)
    return (cx + px * math.cos(r) - py * math.sin(r),
            cy + px * math.sin(r) + py * math.cos(r))

L, W, A = ring_r * 0.82, ring_r * 0.30, 45
tip, tail = rot(0, -L, A), rot(0, L * 0.85, A)
right, left, ctr = rot(W, 0, A), rot(-W, 0, A), rot(0, 0, A)
d.polygon([tip, right, ctr], fill=(90, 168, 255, 255))
d.polygon([tip, left, ctr], fill=(130, 195, 255, 255))
d.polygon([tail, right, ctr], fill=(228, 228, 236, 255))
d.polygon([tail, left, ctr], fill=(192, 192, 205, 255))

# 中心圆点
dot = SIZE * 0.016
d.ellipse([cx - dot, cy - dot, cx + dot, cy + dot], fill=(255, 255, 255, 255))

img.save(OUT)
print(f"已生成 {OUT}")
