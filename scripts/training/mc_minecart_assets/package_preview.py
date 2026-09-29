from pathlib import Path
from PIL import Image
p = Path(__file__).resolve().parents[3] / "tests/minecart_direction_capture"
frames = [Image.open(p/f"frame_{i:02d}.png").convert("RGB").resize((256,256),Image.Resampling.NEAREST) for i in range(64)]
frames[0].save(p/"minecart_directions.gif",save_all=True,append_images=frames[1:],duration=80,loop=0,disposal=2)
Image.open(p/"contact.png").save(p/"contact.jpg",quality=82)
print("GIF bytes:", (p/"minecart_directions.gif").stat().st_size)
