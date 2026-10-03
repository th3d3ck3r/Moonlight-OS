#!/usr/bin/env python3
"""Render original Eclipse vector branding and its minimal native boot preview.
Developer tool: Inkscape and Pillow. No runtime dependency is added to the OS.
"""
import math
from pathlib import Path
import subprocess
import tempfile
from PIL import Image
ROOT = Path(__file__).resolve().parents[1]
ART = ROOT/'assets/eclipse'
BOOT = ROOT/'assets/boot/crimson-apollo'
MARK = (ART/'eclipse-icon.svg').read_text()
DEFS = MARK.split('<defs>')[1].split('</defs>')[0]
RING = '<circle cx="256" cy="256" r="144" fill="url(#rim)"/><circle cx="268" cy="249" r="136" fill="#08080b"/><path d="M151 162a143 143 0 0 1 135-48" fill="none" stroke="#ffe8ee" stroke-opacity=".55" stroke-width="3" stroke-linecap="round"/>'

def render(svg, target):
    with tempfile.TemporaryDirectory() as folder:
        source = Path(folder)/'art.svg'; source.write_text(svg)
        subprocess.run(['inkscape',str(source),'--export-type=png','--export-filename='+str(target)],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)

def canvas(width,height,size,cx,cy,label_y,maker=True):
    scale=size/512
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}"><defs>{DEFS}</defs><rect width="{width}" height="{height}" fill="#08080b"/><g transform="translate({cx-size/2} {cy-size/2}) scale({scale})">{RING}</g><text x="{cx}" y="{label_y}" text-anchor="middle" fill="#eeeaf0" font-family="DejaVu Sans" font-size="{max(24,int(size*.08))}" letter-spacing="6">ECLIPSE</text><text x="{cx}" y="{label_y+38}" text-anchor="middle" fill="#9c929b" font-family="DejaVu Sans" font-size="16">EclipseOS</text>{f'<text x="{cx}" y="{height-58}" text-anchor="middle" fill="#8c7883" font-family="DejaVu Sans" font-size="13">Made by Th3D3ck3r</text>' if maker else ''}</svg>'''

render(canvas(1024,640,360,512,248,450),BOOT/'background.png')
render('''<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128"><defs><radialGradient id="light"><stop stop-color="#ffe8ee"/><stop offset=".2" stop-color="#dc3658"/><stop offset="1" stop-color="#dc3658" stop-opacity="0"/></radialGradient></defs><ellipse cx="64" cy="64" rx="15" ry="10" fill="url(#light)"/><circle cx="64" cy="64" r="2" fill="#ffe8ee"/></svg>''',BOOT/'apollo.png')
background=Image.open(BOOT/'background.png').convert('RGBA')
light=Image.open(BOOT/'apollo.png').convert('RGBA')
frames=[]
for index in range(72):
    frame=background.copy(); angle=index*2*math.pi/72
    sprite=light.rotate(-index*5,resample=Image.Resampling.BICUBIC)
    frame.alpha_composite(sprite,(round(512+115*math.cos(angle)-64),round(248+115*math.sin(angle)-64)))
    frames.append(frame.convert('RGB').resize((800,500),Image.Resampling.LANCZOS))
palette = frames[0].quantize(colors=128, dither=Image.Dither.NONE)
gif_frames = [frame.quantize(palette=palette, dither=Image.Dither.NONE) for frame in frames]
gif_frames[0].save(BOOT/'preview.gif',save_all=True,append_images=gif_frames[1:],duration=100,loop=0,disposal=1,optimize=False)
frames[0].save(BOOT/'poster.png')
# Optional upstream checkout: replace visible artwork while preserving compatible resource paths.
import argparse
parser=argparse.ArgumentParser();parser.add_argument('--frontend',type=Path);args=parser.parse_args()
if args.frontend:
    res=args.frontend/'app/res'
    icon=Image.open(ART/'eclipse-icon.png')
    for size in (128,256,512): icon.resize((size,size),Image.Resampling.LANCZOS).save(res/f'eclipse-mark-{size}.png')
    (res/'eclipse-icon.svg').write_text(MARK)
    for size in (128,256,512):
        icon.resize((size,size),Image.Resampling.LANCZOS).save(res/f'icons/hicolor/{size}x{size}/apps/eclipse.png')
    art=res/'steam'
    for name,w,h,size,cx,cy,y in [('vibemis_p',600,900,420,300,340,650),('vibemis_hero',1920,620,380,960,230,475),('vibemis',920,430,240,460,150,300),('vibemis_logo',840,320,180,420,105,220)]:
        render(canvas(w,h,size,cx,cy,y,False),art/(name.replace('vibemis','eclipse')+'.png'))
    icon.resize((256,256),Image.Resampling.LANCZOS).save(art/'eclipse_icon.png')
