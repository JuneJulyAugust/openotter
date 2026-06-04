#!/usr/bin/env python3
"""Render H12Y VL53L8 mechanical integration concept images.

This script intentionally uses local user photos as inputs and commits only the
derived design artifacts. It is a visual planning helper, not dimensional CAD.
"""

from __future__ import annotations

import argparse
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[2]
ASSET_DIR = ROOT / "docs" / "dev" / "assets"


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = [
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf" if bold else "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
        "/Library/Fonts/Arial.ttf",
    ]
    for candidate in candidates:
        try:
            return ImageFont.truetype(candidate, size)
        except OSError:
            continue
    return ImageFont.load_default()


def fit_crop(img: Image.Image, crop: tuple[int, int, int, int], width: int) -> Image.Image:
    cropped = img.crop(crop)
    height = round(cropped.height * width / cropped.width)
    return cropped.resize((width, height), Image.Resampling.LANCZOS)


def label(draw: ImageDraw.ImageDraw, xy: tuple[int, int], text: str, color: str = "#111827") -> None:
    f = font(28, True)
    pad = 10
    bbox = draw.textbbox(xy, text, font=f)
    box = (bbox[0] - pad, bbox[1] - pad, bbox[2] + pad, bbox[3] + pad)
    draw.rounded_rectangle(box, radius=10, fill=(255, 255, 255, 218), outline=color, width=2)
    draw.text(xy, text, font=f, fill=color)


def small_label(draw: ImageDraw.ImageDraw, xy: tuple[int, int], text: str, color: str = "#111827") -> None:
    f = font(20, True)
    pad = 7
    bbox = draw.textbbox(xy, text, font=f)
    box = (bbox[0] - pad, bbox[1] - pad, bbox[2] + pad, bbox[3] + pad)
    draw.rounded_rectangle(box, radius=8, fill=(255, 255, 255, 210), outline=color, width=1)
    draw.text(xy, text, font=f, fill=color)


def rotated_rect(cx: float, cy: float, w: float, h: float, deg: float) -> list[tuple[float, float]]:
    rad = math.radians(deg)
    c = math.cos(rad)
    s = math.sin(rad)
    points = [(-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2)]
    return [(cx + x * c - y * s, cy + x * s + y * c) for x, y in points]


def draw_case(
    overlay: Image.Image,
    cx: int,
    cy: int,
    w: int,
    h: int,
    deg: float,
    label_text: str,
    accent: tuple[int, int, int],
    aperture_side: str,
) -> tuple[int, int]:
    draw = ImageDraw.Draw(overlay, "RGBA")
    base = rotated_rect(cx, cy, w, h, deg)
    side = [(x + 16, y - 14) for x, y in base]

    draw.polygon([(x + 10, y + 16) for x, y in base], fill=(0, 0, 0, 80))
    draw.polygon(side, fill=(30, 42, 55, 235), outline=(4, 12, 24, 255))
    draw.polygon(base, fill=(17, 24, 39, 245), outline=(148, 163, 184, 255))

    inner = rotated_rect(cx, cy, max(12, w - 24), max(12, h - 24), deg)
    draw.polygon(inner, outline=(71, 85, 105, 255), width=2)

    # Lid accent and role label.
    accent_pts = rotated_rect(cx, cy - h * 0.34, w * 0.70, 18, deg)
    draw.polygon(accent_pts, fill=accent + (245,), outline=(255, 255, 255, 190))
    lf = font(18, True)
    text_w = draw.textlength(label_text, font=lf)
    draw.text((cx - text_w / 2, cy - h * 0.40), label_text, font=lf, fill=(255, 255, 255, 245))

    # Optical aperture on the outward-facing side.
    side_sign = -1 if aperture_side == "left" else 1
    ax = cx + side_sign * w * 0.34 * math.cos(math.radians(deg))
    ay = cy + side_sign * w * 0.34 * math.sin(math.radians(deg))
    aperture = rotated_rect(ax, ay, 28, 42, deg)
    draw.polygon(aperture, fill=(3, 7, 18, 255), outline=(203, 213, 225, 240))
    optic = rotated_rect(ax, ay, 14, 18, deg)
    draw.polygon(optic, fill=(56, 189, 248, 180))

    # Screw ears.
    for ey in (-h * 0.42, h * 0.42):
        ex = cx - side_sign * w * 0.55 * math.cos(math.radians(deg)) - ey * math.sin(math.radians(deg)) * 0.02
        sy = cy + ey * math.cos(math.radians(deg))
        draw.ellipse((ex - 9, sy - 9, ex + 9, sy + 9), fill=(15, 23, 42, 245), outline=(203, 213, 225, 220), width=2)
        draw.ellipse((ex - 3, sy - 3, ex + 3, sy + 3), fill=(148, 163, 184, 255))

    return int(ax), int(ay)


def draw_curve(draw: ImageDraw.ImageDraw, points: list[tuple[int, int]], color: tuple[int, int, int, int], width: int) -> None:
    if len(points) < 3:
        draw.line(points, fill=color, width=width, joint="curve")
        return
    sampled: list[tuple[int, int]] = []
    for p0, p1, p2 in zip(points, points[1:], points[2:]):
        for i in range(10):
            t = i / 10
            x = (1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t**2 * p2[0]
            y = (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t**2 * p2[1]
            sampled.append((int(x), int(y)))
    sampled.append(points[-1])
    draw.line(sampled, fill=color, width=width, joint="curve")


def render_car_photo(car_photo: Path, out: Path) -> None:
    base = Image.open(car_photo).convert("RGB")
    img = fit_crop(base, (260, 520, 3740, 2570), 1900)
    bg = img.filter(ImageFilter.GaussianBlur(1.2))
    img = Image.blend(bg, img, 0.82)
    overlay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay, "RGBA")

    # Subtle focus dim at the top and desk background.
    draw.rectangle((0, 0, img.width, 145), fill=(255, 255, 255, 75))
    draw.rectangle((0, img.height - 140, img.width, img.height), fill=(255, 255, 255, 55))

    # Front sensor on the front guard, rear sensor on the rear upper rail/tray.
    front_ap = draw_case(overlay, 185, 645, 92, 178, -4, "FRONT", (245, 158, 11), "left")
    rear_ap = draw_case(overlay, 1515, 380, 100, 190, 2, "REAR", (34, 197, 94), "right")

    # FOV cones.
    draw.polygon([(front_ap[0], front_ap[1]), (10, front_ap[1] - 155), (10, front_ap[1] + 155)], fill=(251, 191, 36, 52), outline=(245, 158, 11, 120))
    draw.polygon([(rear_ap[0], rear_ap[1]), (1860, rear_ap[1] - 155), (1860, rear_ap[1] + 155)], fill=(34, 197, 94, 45), outline=(22, 163, 74, 125))

    # Harness routes along protected frame zones.
    colors = [(239, 68, 68, 210), (30, 64, 175, 210), (15, 23, 42, 210), (22, 163, 74, 210), (245, 158, 11, 210)]
    for i, color in enumerate(colors):
        draw_curve(draw, [(240, 615 + i * 5), (470, 700 + i * 3), (810, 585 + i * 2), (1125, 525 + i * 3)], color, 4)
        draw_curve(draw, [(1450, 455 + i * 5), (1340, 530 + i * 3), (1180, 545 + i * 2), (1125, 525 + i * 3)], color, 4)

    # Zip tie markers and adapter bay.
    for x, y in [(455, 700), (820, 585), (1325, 530)]:
        draw.rounded_rectangle((x - 22, y - 8, x + 22, y + 8), radius=5, fill=(15, 23, 42, 220))
        draw.line((x - 18, y, x + 18, y), fill=(226, 232, 240, 255), width=2)

    draw.rounded_rectangle((990, 445, 1205, 555), radius=14, fill=(15, 23, 42, 220), outline=(148, 163, 184, 230), width=2)
    draw.text((1014, 466), "ToF adapter", font=font(26, True), fill=(255, 255, 255, 245))
    draw.text((1014, 502), "inside chassis", font=font(22), fill=(226, 232, 240, 245))

    label(draw, (90, 60), "H12Y front/rear VL53L8 case concept")
    small_label(draw, (320, 765), "front harness returns behind bumper")
    small_label(draw, (1280, 640), "rear harness follows frame rail")
    small_label(draw, (1110, 104), "faint cones = keepout / no wires")

    final = Image.alpha_composite(img.convert("RGBA"), overlay)
    out.parent.mkdir(parents=True, exist_ok=True)
    final.save(out)


def render_bench_upgrade(bench_photo: Path, out: Path) -> None:
    base = Image.open(bench_photo).convert("RGB")
    img = fit_crop(base, (0, 430, 4032, 2470), 1900)
    overlay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay, "RGBA")

    draw.rectangle((0, 0, img.width, 120), fill=(255, 255, 255, 190))
    label(draw, (58, 38), "Bench wiring -> car harness transition")

    # Highlight current Dupont bundle.
    draw.rounded_rectangle((460, 230, 1160, 705), radius=24, outline=(239, 68, 68, 220), width=6)
    small_label(draw, (555, 190), "current loose Dupont arc: bench only", "#991b1b")

    # Proposed adapter and harness.
    draw.rounded_rectangle((225, 620, 620, 820), radius=20, fill=(15, 23, 42, 218), outline=(148, 163, 184, 230), width=3)
    draw.text((250, 650), "board-side ToF adapter", font=font(30, True), fill=(255, 255, 255, 245))
    draw.text((250, 690), "2x keyed JST-GH 10-pin", font=font(24), fill=(226, 232, 240, 245))
    draw.text((250, 725), "shared SPI + power", font=font(24), fill=(226, 232, 240, 245))

    for i, color in enumerate([(239, 68, 68, 230), (15, 23, 42, 230), (37, 99, 235, 230), (22, 163, 74, 230), (245, 158, 11, 230)]):
        draw_curve(draw, [(620, 700 + i * 9), (900, 720 + i * 4), (1230, 660 + i * 4), (1580, 770 + i * 8)], color, 5)

    draw.rounded_rectangle((1510, 700, 1770, 900), radius=18, fill=(17, 24, 39, 225), outline=(251, 191, 36, 230), width=3)
    draw.text((1534, 732), "single wrapped", font=font(28, True), fill=(255, 255, 255, 245))
    draw.text((1534, 770), "silicone harness", font=font(28, True), fill=(255, 255, 255, 245))
    draw.text((1534, 812), "to sensor case", font=font(24), fill=(226, 232, 240, 245))

    draw.line((1160, 465, 1450, 465), fill=(239, 68, 68, 230), width=5)
    draw.polygon([(1450, 465), (1420, 448), (1420, 482)], fill=(239, 68, 68, 230))
    small_label(draw, (1190, 410), "replace with strain-relieved harness", "#991b1b")

    final = Image.alpha_composite(img.convert("RGBA"), overlay)
    out.parent.mkdir(parents=True, exist_ok=True)
    final.save(out)


def draw_sensor(draw: ImageDraw.ImageDraw, x: int, y: int, label_text: str, color: tuple[int, int, int]) -> None:
    draw.rounded_rectangle((x - 42, y - 32, x + 42, y + 32), radius=10, fill=(17, 24, 39, 255), outline=color, width=4)
    draw.rectangle((x - 36, y - 24, x - 10, y + 24), fill=(3, 7, 18, 255), outline=(226, 232, 240, 255), width=2)
    draw.text((x - 32, y - 58), label_text, font=font(20, True), fill=color)


def render_harness_layout(out: Path) -> None:
    canvas = Image.new("RGB", (1800, 1050), "#f8fafc")
    overlay = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay, "RGBA")

    label(draw, (58, 42), "MJX H12Y final ToF mechanical layout")
    draw.text((62, 102), "H12Y reference dimensions: 390 x 205 x 185 mm, wheelbase 232 mm, tire diameter 90 mm", font=font(24), fill=(51, 65, 85))

    car = (250, 210, 1550, 820)
    draw.rounded_rectangle(car, radius=90, fill=(226, 232, 240, 255), outline=(71, 85, 105, 255), width=4)
    draw.rounded_rectangle((390, 315, 1410, 715), radius=46, fill=(30, 41, 59, 255), outline=(148, 163, 184, 255), width=3)
    draw.rounded_rectangle((710, 330, 1245, 685), radius=24, fill=(71, 85, 105, 255), outline=(203, 213, 225, 255), width=3)
    draw.text((780, 460), "controller + ToF adapter tray", font=font(34, True), fill=(255, 255, 255, 245))
    draw.text((780, 508), "B-L475E now; B-U585I can use the same Arduino-header adapter concept", font=font(22), fill=(226, 232, 240, 245))

    # Wheels.
    for x in [380, 1420]:
        for y in [250, 780]:
            draw.ellipse((x - 115, y - 68, x + 115, y + 68), fill=(15, 23, 42, 255), outline=(51, 65, 85, 255), width=4)
            draw.ellipse((x - 48, y - 28, x + 48, y + 28), fill=(30, 41, 59, 255), outline=(148, 163, 184, 255), width=3)

    # Sensors and FOVs.
    draw_sensor(draw, 250, 510, "FRONT", (245, 158, 11))
    draw_sensor(draw, 1550, 510, "REAR", (34, 197, 94))
    draw.polygon([(215, 510), (40, 365), (40, 655)], fill=(251, 191, 36, 62), outline=(245, 158, 11, 140))
    draw.polygon([(1585, 510), (1760, 365), (1760, 655)], fill=(34, 197, 94, 55), outline=(22, 163, 74, 140))

    # Harness trunk routes.
    trunk = [(315, 535), (520, 610), (760, 650), (980, 650), (1280, 610), (1485, 535)]
    for i, color in enumerate([(239, 68, 68, 235), (15, 23, 42, 235), (37, 99, 235, 235), (22, 163, 74, 235), (245, 158, 11, 235)]):
        shifted = [(x, y + i * 7) for x, y in trunk]
        draw_curve(draw, shifted, color, 5)
    for x, y in [(520, 610), (760, 650), (1280, 610)]:
        draw.rounded_rectangle((x - 28, y - 14, x + 28, y + 14), radius=6, fill=(15, 23, 42, 245))
        draw.line((x - 22, y, x + 22, y), fill=(226, 232, 240, 255), width=2)

    # Callouts.
    small_label(draw, (80, 720), "front case bottom mounts to bumper/guard saddle", "#92400e")
    small_label(draw, (1260, 720), "rear case bottom mounts to rear tray/rail", "#166534")
    small_label(draw, (690, 745), "zip ties every 30-50 mm; keep loops below FOV")
    small_label(draw, (652, 232), "two JST-GH sensor ports: FRONT + REAR")

    # Legend.
    legend_y = 900
    draw.text((245, legend_y), "Harness: shared 5V/GND/SCK/MOSI/MISO, separate NCS/LPn/GPIO1 per sensor", font=font(26, True), fill=(15, 23, 42))
    draw.text((245, legend_y + 42), "Preferred first two-sensor deployment: shared SPI1 bus, separate chip selects, full SATEL carrier cases.", font=font(24), fill=(51, 65, 85))

    out.parent.mkdir(parents=True, exist_ok=True)
    Image.alpha_composite(canvas.convert("RGBA"), overlay).save(out)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--car-photo", type=Path, default=Path("/Users/fang/Downloads/IMG_0904.jpg"))
    parser.add_argument("--bench-photo", type=Path, default=Path("/Users/fang/Downloads/IMG_0903.jpg"))
    parser.add_argument("--out-dir", type=Path, default=ASSET_DIR)
    args = parser.parse_args()

    render_car_photo(args.car_photo, args.out_dir / "vl53l8-h12y-photo-mount-concept.png")
    render_bench_upgrade(args.bench_photo, args.out_dir / "vl53l8-bench-harness-upgrade.png")
    render_harness_layout(args.out_dir / "vl53l8-h12y-harness-layout.png")


if __name__ == "__main__":
    main()
