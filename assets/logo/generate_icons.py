"""
Generate Miee launcher icon PNG files from scratch using Pillow.
Creates a 1024x1024 master PNG and a 512x512 favicon PNG
representing the "ee" crosshair compact mark on a dark background.
"""
from PIL import Image, ImageDraw
import math, os

OUTPUT_DIR = os.path.join(os.path.dirname(__file__), '..', 'assets', 'logo')
os.makedirs(OUTPUT_DIR, exist_ok=True)

BG_COLOR  = (13, 13, 13, 255)      # #0D0D0D
FG_COLOR  = (240, 237, 232, 255)   # #F0EDE8 — off-white

def draw_ee_icon(draw: ImageDraw.ImageDraw, size: int):
    """Draw the double-ee crosshair mark centred in a square of `size` px."""
    pad   = int(size * 0.10)     # outer padding
    gap   = int(size * 0.04)     # gap between two e's
    e_w   = (size - 2 * pad - gap) // 2   # width of each e bounding box
    e_h   = int(size * 0.55)              # height of each e
    top_y = (size - e_h) // 2            # vertical centre

    stroke = max(2, int(size * 0.040))   # ring stroke width
    bar_w  = max(2, int(size * 0.030))   # crosshair bar width

    for idx in range(2):
        x0 = pad + idx * (e_w + gap)
        x1 = x0 + e_w
        y0 = top_y
        y1 = top_y + e_h
        cx = (x0 + x1) // 2
        cy = (y0 + y1) // 2

        r = e_w // 2  # radius for the "e" arc

        # Draw "e" as a full circle minus a bite at ~3 o'clock (right side gap),
        # using a simple approach: draw full circle then overdraw bg in the opening.
        # We approximate with a bounding-box ellipse (open on right) via arc.

        # Full circle arc 0°–330° (leaving a 30° opening on right for the e counter)
        # PIL angles: 0 = 3 o'clock, going clockwise.
        draw.arc(
            [x0 + stroke//2, y0 + stroke//2, x1 - stroke//2, y1 - stroke//2],
            start=40,    # ~1:20 position (just past the mid-bar opening)
            end=320,     # ~10:40 position
            fill=FG_COLOR,
            width=stroke,
        )

        # Horizontal crosshair bar (full width of bounding box)
        draw.line(
            [(x0, cy), (x1, cy)],
            fill=FG_COLOR,
            width=bar_w,
        )
        # Vertical crosshair bar (full height of bounding box)
        draw.line(
            [(cx, y0), (cx, y1)],
            fill=FG_COLOR,
            width=bar_w,
        )

# ── 1024×1024 master launcher icon ──
SIZE = 1024
img = Image.new('RGBA', (SIZE, SIZE), BG_COLOR)
draw = ImageDraw.Draw(img)
# Rounded square mask
mask = Image.new('L', (SIZE, SIZE), 0)
mask_draw = ImageDraw.Draw(mask)
radius = int(SIZE * 0.22)
mask_draw.rounded_rectangle([0, 0, SIZE, SIZE], radius=radius, fill=255)
img.putalpha(mask)

draw_ee_icon(draw, SIZE)
out_path = os.path.join(OUTPUT_DIR, 'miee_launcher_1024.png')
img.save(out_path, 'PNG')
print(f'Saved {out_path}')

# ── 512×512 ──
SIZE = 512
img2 = img.resize((SIZE, SIZE), Image.LANCZOS)
out_path2 = os.path.join(OUTPUT_DIR, 'miee_launcher_512.png')
img2.save(out_path2, 'PNG')
print(f'Saved {out_path2}')

# ── 192×192 web icon ──
SIZE = 192
img3 = img.resize((SIZE, SIZE), Image.LANCZOS)
out_path3 = os.path.join(OUTPUT_DIR, 'miee_web_192.png')
img3.save(out_path3, 'PNG')
print(f'Saved {out_path3}')

# ── 32×32 favicon ──
SIZE = 32
img4 = img.resize((SIZE, SIZE), Image.LANCZOS)
out_path4 = os.path.join(OUTPUT_DIR, 'miee_favicon_32.png')
img4.save(out_path4, 'PNG')
print(f'Saved {out_path4}')

print('All icons generated successfully.')
