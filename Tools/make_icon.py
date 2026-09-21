#!/usr/bin/env python3
"""生成 Shelf 的 AppIcon —— 三层架子 + 文件的隐喻，走 macOS 原生配色。"""
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.expanduser("~/Projects/Shelf/Resources/AppIcon.iconset")
os.makedirs(OUT, exist_ok=True)

BASE = 1024

# ---------- 形状 ----------

def squircle_mask(size: int) -> Image.Image:
    """macOS 风格的连续曲率圆角，用超椭圆生成后轻微模糊获得平滑边缘。"""
    n = size
    yy, xx = np.mgrid[0:n, 0:n]
    # 归一化到 [-1, 1]
    x = (xx + 0.5) / n * 2 - 1
    y = (yy + 0.5) / n * 2 - 1
    # 超椭圆 |x|^m + |y|^m <= 1，m≈4.2 接近 Apple squircle
    m = 4.2
    inside = (np.abs(x) ** m + np.abs(y) ** m) <= 1.0
    msk = Image.fromarray((inside * 255).astype(np.uint8), "L")
    # 两像素抗锯齿
    return msk.filter(ImageFilter.GaussianBlur(n / 512.0))


def linear_gradient(size, top_rgb, bot_rgb):
    ys = np.linspace(0, 1, size, dtype=np.float32)[:, None]
    arr = (np.array(top_rgb, dtype=np.float32) * (1 - ys) +
           np.array(bot_rgb, dtype=np.float32) * ys)
    img = np.repeat(arr[:, None, :], size, axis=1).astype(np.uint8)
    return Image.fromarray(img, "RGB")


def radial_light(size, cx, cy, radius, strength):
    """左上柔光"""
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    d = np.sqrt((xx - cx * size) ** 2 + (yy - cy * size) ** 2) / (radius * size)
    a = np.clip(1 - d, 0, 1) ** 2 * strength
    return Image.fromarray((a * 255).astype(np.uint8), "L")


# ---------- 图标内容 ----------

def draw_icon(size: int, detail: bool = True) -> Image.Image:
    s = size / BASE  # 缩放因子

    # 背景渐变
    bg = linear_gradient(size, (0x6F, 0xCF, 0xFB), (0x0B, 0x5C, 0xD9))
    bg = bg.convert("RGBA")

    # 顶部柔光
    bg.putalpha(Image.new("L", (size, size), 255))
    light = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    la = radial_light(size, 0.30, 0.16, 0.85, 0.34).point(lambda v: int(v * 0.55))
    light.putalpha(la)
    bg = Image.alpha_composite(bg, light)

    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.paste(bg, (0, 0), squircle_mask(size))

    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)

    WHITE = (255, 255, 255, 252)
    WHITE_SOFT = (255, 255, 255, 214)
    ACCENT = (0xFF, 0xD6, 0x0A, 255)      # 黄
    ACCENT2 = (0x8E, 0xF0, 0xFF, 235)     # 淡青

    def rr(x0, y0, x1, y1, r, fill):
        d.rounded_rectangle([x0 * s, y0 * s, x1 * s, y1 * s],
                            radius=r * s, fill=fill)

    # 侧板
    rr(196, 236, 216, 790, 10, WHITE_SOFT)
    rr(808, 236, 828, 790, 10, WHITE_SOFT)

    # 三块横板（自下而上）
    shelves = [(742, 790), (512, 560), (282, 330)]
    for y0, y1 in shelves:
        rr(196, y0, 828, y1, 14, WHITE)
        # 板上高光
        if detail:
            rr(206, y0 + 4, 818, y0 + 8, 4, (255, 255, 255, 170))

    # --- 底层：两个文件 + 一个斜靠的文件夹 + 一个盒子
    rr(248, 606, 356, 742, 14, WHITE)
    rr(386, 578, 494, 742, 14, WHITE_SOFT)
    # 斜靠的黄文件夹
    d.polygon([(536 * s, 742 * s), (604 * s, 742 * s),
               (640 * s, 596 * s), (572 * s, 596 * s)], fill=ACCENT)
    # 右侧盒子
    rr(668, 646, 792, 742, 16, ACCENT2)
    rr(668, 646, 792, 686, 16, (255, 255, 255, 200))

    # --- 中层：一摞横放的书 + 一个文件
    rr(250, 388, 358, 512, 14, WHITE)
    rr(392, 480, 616, 512, 10, ACCENT)
    rr(404, 452, 604, 480, 10, WHITE)
    rr(416, 424, 592, 452, 10, WHITE_SOFT)
    rr(652, 372, 760, 512, 14, WHITE)

    # --- 顶层：小方块 + 文件 + 球
    rr(252, 176, 372, 282, 16, WHITE_SOFT)
    rr(404, 140, 512, 282, 14, WHITE)
    d.ellipse([556 * s, 200 * s, 636 * s, 282 * s], fill=ACCENT2)

    # --- 细节：文件上的横线
    if detail:
        line_a = (0x0B, 0x5C, 0xD9, 90)
        line_w = max(1, int(7 * s))
        for x0, x1, ys in [
            (268, 336, (630, 660, 690)),
            (406, 474, (604, 634, 664, 694)),
            (668, 756, (410, 442, 474)),
            (422, 494, (176, 208, 240)),
        ]:
            for y in ys:
                d.line([(x0 * s, y * s), (x1 * s, y * s)], fill=line_a, width=line_w)

        # 盒子上的分隔线
        d.line([(668 * s, 690 * s), (792 * s, 690 * s)],
               fill=(0x0B, 0x5C, 0xD9, 70), width=max(1, int(5 * s)))

    # 合成到圆角画布
    out = Image.alpha_composite(canvas, layer)
    out = Image.alpha_composite(out, Image.new("RGBA", (size, size), (0, 0, 0, 0)))
    # 用背景 mask 裁掉圆角外的前景
    mask = squircle_mask(size)
    r, g, b, a = out.split()
    a = Image.composite(a, Image.new("L", (size, size), 0), mask)
    return Image.merge("RGBA", (r, g, b, a))


# ---------- 输出 ----------

targets = [
    ("icon_16x16.png", 16, False),
    ("icon_16x16@2x.png", 32, False),
    ("icon_32x32.png", 32, False),
    ("icon_32x32@2x.png", 64, True),
    ("icon_128x128.png", 128, True),
    ("icon_128x128@2x.png", 256, True),
    ("icon_256x256.png", 256, True),
    ("icon_256x256@2x.png", 512, True),
    ("icon_512x512.png", 512, True),
    ("icon_512x512@2x.png", 1024, True),
]

big = draw_icon(1024, detail=True)
big.save(os.path.expanduser("~/Projects/Shelf/Resources/AppIcon_1024.png"))

for name, px, detail in targets:
    if px >= 512:
        img = big.resize((px, px), Image.LANCZOS)
    else:
        img = draw_icon(max(px, 128), detail=detail).resize((px, px), Image.LANCZOS)
    img.save(os.path.join(OUT, name))

print("iconset written ->", OUT)
