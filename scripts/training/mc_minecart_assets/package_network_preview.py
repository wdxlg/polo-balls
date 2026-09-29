"""Package real Godot frames plus their recorded telemetry; does not synthesize gameplay."""
from pathlib import Path
import json, shutil, subprocess
from PIL import Image, ImageDraw, ImageFont
ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT/'tests/rail_grid_capture'
records = json.loads((SOURCE/'frames.json').read_text(encoding='utf-8'))
font_path = Path('C:/Windows/Fonts/msyh.ttc')
chinese = font_path.exists()
if not chinese:
    font_path = Path('C:/Windows/Fonts/arial.ttf')
title_font = ImageFont.truetype(str(font_path),24)
body_font = ImageFont.truetype(str(font_path),17)
small_font = ImageFont.truetype(str(font_path),13)
frames = []
durations = []
for i,record in enumerate(records):
    image = Image.new('RGB',(720,620),(19,27,30))
    image.paste(Image.open(SOURCE/record['file']).convert('RGB'),(0,64))
    draw = ImageDraw.Draw(image)
    draw.text((18,9),'矿车 · 网格与层级修复' if chinese else 'MINECART / GRID AND LAYER FIX',font=title_font,fill=(232,238,223))
    status = ('动力段加速' if record['powered'] else '沿轨提速') if record['phase']==2 else '随机离轨 / 正常移动'
    if not chinese: status = 'POWERED' if record['powered'] else 'RAIL TRAVEL' if record['phase']==2 else 'NORMAL MOVEMENT'
    line = f"车速 {record['speed']:.0f}  |  {status}  |  {'同格合并 · 动力优先' if record['merged'] else '一格一轨'}" if chinese else f"SPEED {record['speed']:.0f} | {status} | {'MERGED / POWER PRIORITY' if record['merged'] else 'ONE TILE PER CELL'}"
    draw.text((18,40),line,font=body_font,fill=(137,205,174) if record['powered'] else (180,199,199))
    footer = f"轨格 {record['cells']}  ·  过弯 {record['turns']} 次  ·  到站随机换向 {record['departures']} 次" if chinese else f"CELLS {record['cells']} | CORNERS {record['turns']} | RANDOM DEPARTURES {record['departures']}"
    draw.text((18,588),footer,font=small_font,fill=(166,190,184))
    frames.append(image)
    delta = records[i+1]['time_ms']-record['time_ms'] if i+1 < len(records) else 150
    durations.append(max(30,min(250,int(delta))))
# A common palette prevents stationary grass/colors flickering between frames.
samples = Image.new('RGB',(720*4,620))
for i,index in enumerate([0,len(frames)//3,2*len(frames)//3,len(frames)-1]): samples.paste(frames[index],(i*720,0))
palette = samples.quantize(colors=256,method=Image.Quantize.MEDIANCUT)
indexed = [frame.quantize(palette=palette,dither=Image.Dither.NONE) for frame in frames]
output = ROOT/'tests/minecart_grid_fix_preview.gif'
indexed[0].save(output,save_all=True,append_images=indexed[1:],duration=durations,loop=0,optimize=True,disposal=2)
frames[len(frames)//2].save(ROOT/'tests/minecart_grid_fix_preview.png')
print('NETWORK_PREVIEW',len(frames),'real frames;',output.stat().st_size,'bytes; connection seen:',any(r['merged'] and r['power_kept'] for r in records),'max boards:',max(r['boards'] for r in records))

ffmpeg = shutil.which('ffmpeg')
if ffmpeg:
    video = output.with_suffix('.mp4')
    subprocess.run([ffmpeg,'-y','-hide_banner','-loglevel','error','-ignore_loop','1','-i',str(output),'-vf','fps=30','-c:v','libx264','-crf','20','-pix_fmt','yuv420p','-movflags','+faststart',str(video)],check=True,timeout=60)
    print('NETWORK_VIDEO',video.stat().st_size,'bytes')
