"""Draw the project's own Composer icons; generic Door Lock tiles keep native icons."""

from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]


def render(role: str, size: int) -> Image.Image:
    image = Image.new("RGBA", (256, 256))
    d = ImageDraw.Draw(image)
    blue = "#109EFF"
    d.rounded_rectangle((10, 10, 246, 246), radius=48, fill=blue)
    d.arc((77, 42, 179, 153), 180, 360, fill="white", width=15)
    d.rounded_rectangle((63, 92, 193, 202), radius=20, fill="white")
    d.ellipse((116, 127, 140, 151), fill=blue)
    d.rounded_rectangle((121, 139, 135, 173), radius=5, fill=blue)
    if role == "account":
        d.ellipse((173, 167, 247, 241), fill="#075797", outline="white", width=7)
        d.line((194, 190, 224, 217), fill="white", width=5)
        d.line((224, 190, 194, 217), fill="white", width=5)
        for x, y in ((194, 190), (224, 190), (194, 217), (224, 217)):
            d.ellipse((x - 6, y - 6, x + 6, y + 6), fill="white")
    return image.resize((size, size), Image.Resampling.LANCZOS)


def main():
    for role in ("account", "lock"):
        folder = ROOT / "drivers" / f"schlage_{role}" / "www" / "icons"
        folder.mkdir(parents=True, exist_ok=True)
        for size in (16, 32, 64, 300):
            render(role, size).save(folder / f"composer_{size}.png")


if __name__ == "__main__":
    main()
