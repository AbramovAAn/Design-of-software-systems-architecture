from PIL import Image, ImageDraw, ImageFont


W, H = 794, 425
IMG_PATH = r"c:\Users\LENOVO\Desktop\ЛР3\sequence_diagram_lr3_final.png"


def load_font(name: str, size: int):
    try:
        return ImageFont.truetype(name, size)
    except Exception:
        return ImageFont.load_default()


img = Image.new("RGB", (W, H), "white")
draw = ImageDraw.Draw(img)

title_font = load_font("arial.ttf", 26)
label_font = load_font("arial.ttf", 18)
text_font = load_font("arial.ttf", 16)


def draw_centered_text(x: float, y: float, text: str, font, fill: str = "black") -> None:
    bbox = draw.textbbox((0, 0), text, font=font)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    draw.text((x - tw / 2, y - th / 2), text, font=font, fill=fill)


def draw_dashed_line(
    x1: float,
    y1: float,
    x2: float,
    y2: float,
    dash: int = 8,
    gap: int = 5,
    fill: str = "black",
    width: int = 2,
) -> None:
    if y1 == y2:
        step = dash + gap
        if x2 >= x1:
            x = x1
            while x < x2:
                xe = min(x + dash, x2)
                draw.line((x, y1, xe, y2), fill=fill, width=width)
                x += step
        else:
            x = x1
            while x > x2:
                xe = max(x - dash, x2)
                draw.line((x, y1, xe, y2), fill=fill, width=width)
                x -= step
    elif x1 == x2:
        step = dash + gap
        if y2 >= y1:
            y = y1
            while y < y2:
                ye = min(y + dash, y2)
                draw.line((x1, y, x2, ye), fill=fill, width=width)
                y += step
        else:
            y = y1
            while y > y2:
                ye = max(y - dash, y2)
                draw.line((x1, y, x2, ye), fill=fill, width=width)
                y -= step


def draw_arrow(x1: int, y1: int, x2: int, y2: int, text: str, dashed: bool = False) -> None:
    if dashed:
        draw_dashed_line(x1, y1, x2, y2, fill="black", width=2)
    else:
        draw.line((x1, y1, x2, y2), fill="black", width=2)

    head = 9
    if x2 >= x1:
        draw.polygon([(x2, y2), (x2 - head, y2 - 4), (x2 - head, y2 + 4)], fill="black")
    else:
        draw.polygon([(x2, y2), (x2 + head, y2 - 4), (x2 + head, y2 + 4)], fill="black")

    tx = (x1 + x2) / 2
    ty = y1 - 14
    draw_centered_text(tx, ty, text, text_font)


draw_centered_text(W / 2, 20, "Диаграмма последовательностей: Инспекция и предложение", title_font)

participants = [
    ("Инспектор", 65),
    ("API", 176),
    ("Контроллер", 287),
    ("Инспекция", 398),
    ("Предложения", 509),
    ("Платежи", 620),
    ("Передача", 731),
]

box_y = 42
box_h = 24
line_top = 84
line_bottom = 398
box_fill = (173, 216, 230)

for name, x in participants:
    bbox = draw.textbbox((0, 0), name, font=label_font)
    tw = bbox[2] - bbox[0]
    pad = 8
    x1 = int(x - tw / 2 - pad)
    x2 = int(x + tw / 2 + pad)
    draw.rounded_rectangle(
        (x1, box_y - box_h / 2, x2, box_y + box_h / 2),
        radius=4,
        fill=box_fill,
        outline="black",
        width=1,
    )
    draw_centered_text(x, box_y, name, label_font)
    draw_dashed_line(x, line_top, x, line_bottom, dash=8, gap=5, fill="black", width=2)

coords = {name: x for name, x in participants}
messages = [
    ("Инспектор", "API", 120, "Отправляет данные", False),
    ("API", "Контроллер", 160, "Пересылает запрос", False),
    ("Контроллер", "Инспекция", 196, "Проверка и сохранение", False),
    ("Инспекция", "Предложения", 240, "Передает результаты", False),
    ("Предложения", "Платежи", 274, "Выплата", False),
    ("Предложения", "Передача", 310, "Передача на обработку", False),
    ("Контроллер", "API", 360, "Ответ API", True),
    ("API", "Инспектор", 394, "Ответ инспектору", True),
]

for src, dst, y, text, dashed in messages:
    draw_arrow(coords[src], y, coords[dst], y, text, dashed=dashed)

img.save(IMG_PATH)
print(f"saved: {IMG_PATH}")
