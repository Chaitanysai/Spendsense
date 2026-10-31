from PIL import Image, ImageDraw, ImageFilter
import numpy as np
import math, os

S = 2048
OUT = "assets/icons"
os.makedirs(OUT, exist_ok=True)

def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))

def bg():
    # diagonal deep-navy gradient
    y, x = np.mgrid[0:S, 0:S].astype(np.float32)
    t = (x + y) / (2.0 * (S - 1))
    stops = [(0.0, (2, 16, 36)), (0.55, (5, 38, 89)), (1.0, (10, 52, 104))]
    arr = np.zeros((S, S, 3), np.float32)
    for i in range(len(stops) - 1):
        a, ca = stops[i]
        b, cb = stops[i + 1]
        m = (t >= a) & (t <= b)
        local = np.clip((t - a) / (b - a), 0, 1)
        for c in range(3):
            arr[..., c][m] = ca[c] + (cb[c] - ca[c]) * local[m]
    img = Image.fromarray(arr.astype(np.uint8), "RGB")

    # soft radial lights
    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(glow)
    d.ellipse([-350, -420, 1250, 1180], fill=(81, 135, 193, 105))
    d.ellipse([1050, 1050, 2450, 2450], fill=(193, 232, 255, 55))
    glow = glow.filter(ImageFilter.GaussianBlur(170))
    img = Image.alpha_composite(img.convert("RGBA"), glow).convert("RGB")
    return img

def draw_content(base, scale, transparent=False):
    """Draw ring + glass disc + ascending line, centred. scale 1 = full icon."""
    img = base.convert("RGBA")
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    cx = cy = S / 2
    R = 700 * scale
    stroke = 92 * scale
    box = [cx - R, cy - R, cx + R, cy + R]

    # faint complete track
    d.arc(box, 0, 360, fill=(255, 255, 255, 34), width=max(2, int(6 * scale)))

    # glow behind the active arc
    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.arc(box, -90, 250, fill=(125, 160, 202, 135), width=int(stroke * 1.25))
    glow = glow.filter(ImageFilter.GaussianBlur(38 * scale))
    img = Image.alpha_composite(img, glow)

    # gradient arc
    start, end = -90, 250
    steps = 120
    for i in range(steps):
        a0 = start + (end - start) * i / steps
        a1 = start + (end - start) * (i + 1) / steps + 0.8
        t = i / (steps - 1)
        col = lerp((84, 131, 179), (193, 232, 255), t) + (255,)
        d.arc(box, a0, a1, fill=col, width=int(stroke))
    # rounded caps
    for ang, col in [(start, (84, 131, 179)), (end, (193, 232, 255))]:
        px = cx + math.cos(math.radians(ang)) * R
        py = cy + math.sin(math.radians(ang)) * R
        r = stroke / 2
        d.ellipse([px - r, py - r, px + r, py + r], fill=col + (255,))

    # glass disc
    dr = 470 * scale
    disc = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    dd = ImageDraw.Draw(disc)
    dd.ellipse([cx - dr, cy - dr, cx + dr, cy + dr], fill=(255, 255, 255, 28))
    dd.ellipse(
        [cx - dr, cy - dr, cx + dr, cy + dr],
        outline=(255, 255, 255, 64),
        width=max(2, int(3 * scale)),
    )
    # top-left glass sheen
    sheen = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sheen)
    sd.ellipse(
        [cx - dr * 0.92, cy - dr * 1.05, cx + dr * 0.15, cy + dr * 0.05],
        fill=(255, 255, 255, 18),
    )
    sheen = sheen.filter(ImageFilter.GaussianBlur(45 * scale))
    img = Image.alpha_composite(img, sheen)
    img = Image.alpha_composite(img, disc)

    # ascending line
    pts = [
        (cx - 330 * scale, cy + 100 * scale),
        (cx - 100 * scale, cy - 100 * scale),
        (cx + 100 * scale, cy - 20 * scale),
        (cx + 350 * scale, cy - 260 * scale),
    ]
    width = max(3, int(96 * scale))
    d.line(pts, fill=(244, 250, 255, 255), width=width, joint="curve")
    for p in pts:
        r = width / 2
        d.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], fill=(244, 250, 255, 255))

    # endpoint light
    ex, ey = pts[-1]
    halo = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    hd = ImageDraw.Draw(halo)
    hr = 132 * scale
    hd.ellipse(
        [ex - hr, ey - hr, ex + hr, ey + hr],
        fill=(193, 232, 255, 150),
    )
    halo = halo.filter(ImageFilter.GaussianBlur(22 * scale))
    img = Image.alpha_composite(img, halo)
    img = Image.alpha_composite(img, layer)
    # re-draw the line above the disc layer (layer was ring only)
    line = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ld = ImageDraw.Draw(line)
    ld.line(pts, fill=(244, 250, 255, 255), width=width, joint="curve")
    for p in pts:
        r = width / 2
        ld.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], fill=(244, 250, 255, 255))
    ld.ellipse(
        [ex - 56 * scale, ey - 56 * scale, ex + 56 * scale, ey + 56 * scale],
        fill=(193, 232, 255, 255),
    )
    img = Image.alpha_composite(img, line)
    return img

base = bg()
full = draw_content(base.convert("RGBA"), 1.0).convert("RGB")
full.resize((1024, 1024), Image.LANCZOS).save(os.path.join(OUT, "app_icon.png"), optimize=True)

# Adaptive foreground: transparent, content at 64% inside the safe zone.
fg = Image.new("RGBA", (S, S), (0, 0, 0, 0))
content = draw_content(Image.new("RGBA", (S, S), (0, 0, 0, 0)), 0.74)
fg = Image.alpha_composite(fg, content)
fg.resize((1024, 1024), Image.LANCZOS).save(os.path.join(OUT, "app_icon_foreground.png"), optimize=True)

print("written")
