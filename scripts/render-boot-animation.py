#!/usr/bin/env python3
"""Create original, deterministic boot-theme sprites and an animated review preview."""
from pathlib import Path
import math
import random
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'assets/boot/crimson-apollo'
OUT.mkdir(parents=True, exist_ok=True)
W, H = 1024, 640
CX, CY, R, ORBIT = 512, 248, 120, 170
rng = random.Random(19690720)
base = Image.new('RGB', (W, H), '#030305')
draw = ImageDraw.Draw(base)
for _ in range(110):
    x, y = rng.randrange(70, W-70), rng.randrange(35, H-70)
    if math.hypot(x-CX, y-CY) < 145:
        continue
    value = rng.randrange(35, 95)
    draw.ellipse((x,y,x+1,y+1), fill=(value, int(value*.63), int(value*.7)))
# Very restrained rim glow; the canvas remains predominantly black.
glow = Image.new('RGB', (W,H))
gd = ImageDraw.Draw(glow)
gd.ellipse((CX-R-2,CY-R-2,CX+R+2,CY+R+2),outline='#c32047',width=4)
glow = glow.filter(ImageFilter.GaussianBlur(11))
from PIL import ImageChops
base = ImageChops.add(base, glow)
draw = ImageDraw.Draw(base)
for angle in range(0,360,6):
    draw.arc((CX-ORBIT,CY-ORBIT,CX+ORBIT,CY+ORBIT),angle,angle+2,fill='#542034',width=1)
# Spherical lighting in black/crimson, with a muted illuminated lunar edge.
moon = Image.new('RGBA',(2*R,2*R))
pix=moon.load()
for y in range(2*R):
    for x in range(2*R):
        nx,ny=(x-R)/R,(y-R)/R
        q=nx*nx+ny*ny
        if q>=1: continue
        nz=math.sqrt(1-q)
        light=max(0,-.71*nx-.28*ny+.64*nz)
        texture=rng.uniform(.86,1.10)
        value=int((11+62*light)*texture)
        pix[x,y]=(int(value*1.24),int(value*.52),int(value*.64),255)
md=ImageDraw.Draw(moon)
for _ in range(62):
    x,y=rng.randrange(16,2*R-16),rng.randrange(16,2*R-16)
    rad=rng.randrange(3,13)
    if math.hypot(x-R,y-R)+rad > R-4: continue
    md.ellipse((x-rad,y-rad*.7,x+rad,y+rad*.7),fill=(19,12,17,255),outline=(63,29,38,255),width=1)
mask=Image.new('L',(2*R,2*R));ImageDraw.Draw(mask).ellipse((0,0,2*R-1,2*R-1),fill=255)
moon.putalpha(mask)
base.paste(moon,(CX-R,CY-R),moon)
draw=ImageDraw.Draw(base)
draw.arc((CX-R,CY-R,CX+R,CY+R),112,269,fill='#de3457',width=2)
font_dir=Path('/usr/share/fonts/truetype/dejavu')
font=ImageFont.truetype(str(font_dir/'DejaVuSans.ttf'),35)
small=ImageFont.truetype(str(font_dir/'DejaVuSansMono.ttf'),12)
def spaced(text,y,font,color,gap):
    widths=[draw.textlength(c,font=font) for c in text]
    x=(W-sum(widths)-gap*(len(text)-1))/2
    for c,width in zip(text,widths):
        draw.text((x,y),c,font=font,fill=color)
        x+=width+gap
spaced('MOONLIGHT-OS',490,font,'#f0e9ec',5)
spaced('APOLLO  /  LUNAR ORBIT',543,small,'#c24764',2)
spaced('STARTING MOONLIGHT-OS',587,small,'#968890',1)
base.save(OUT/'background.png',optimize=True)
# Original Apollo-inspired command/service module, pointing upward.
ship=Image.new('RGBA',(76,88));sd=ImageDraw.Draw(ship)
sd.polygon([(38,7),(22,30),(54,30)],fill='#caaeb7',outline='#f0d8df')
sd.rectangle((22,31,54,60),fill='#481c2c',outline='#cc526e',width=2)
sd.rectangle((27,36,49,54),fill='#21141e',outline='#775063')
sd.line((38,32,38,60),fill='#c25873',width=1)
sd.polygon([(31,61),(45,61),(50,68),(26,68)],fill='#65505a',outline='#dcb8c4')
sd.polygon([(33,69),(43,69),(38,83)],fill='#de3457')
sd.line((17,42,22,42),fill='#ec879c',width=2)
sd.line((54,42,59,42),fill='#ec879c',width=2)
ship.save(OUT/'apollo.png',optimize=True)
# A faint red lunar-module silhouette anchors the moon's Apollo motif.
# No NASA logos, downloaded artwork or photorealistic mission footage.
lander=Image.new('RGBA',(80,80));ld=ImageDraw.Draw(lander)
ld.polygon([(28,15),(48,15),(56,30),(52,40),(24,40),(20,30)],fill='#361525',outline='#a34a61',width=2)
ld.rectangle((24,42,52,54),fill='#642139',outline='#c9617b',width=2)
ld.rectangle((28,24,35,30),fill='#bd7890')
ld.line((25,53,14,69),fill='#d1788f',width=2);ld.line((51,53,63,69),fill='#d1788f',width=2)
ld.line((9,69,21,69),fill='#d1788f',width=2);ld.line((57,69,69,69),fill='#d1788f',width=2)
ld.line((40,15,40,6),fill='#bd7890',width=1)
lander.save(OUT/'lander.png',optimize=True)
base.paste(lander,(CX-40,CY-37),lander)
base.save(OUT/'background.png',optimize=True)
frames=[]
for i in range(72):
    t=2*math.pi*i/72
    frame=base.copy()
    # Circular orbital path, smooth infinite loop.
    x=CX+ORBIT*math.cos(t)
    y=CY+ORBIT*math.sin(t)
    rotated=ship.rotate(-math.degrees(t)-180,resample=Image.Resampling.BICUBIC,expand=True)
    frame.paste(rotated,(round(x-rotated.width/2),round(y-rotated.height/2)),rotated)
    fd=ImageDraw.Draw(frame)
    for j in range(3):
        color='#ed5473' if (i//8)%3==j else '#4b2431'
        fd.ellipse((CX-18+j*15,617,CX-12+j*15,623),fill=color)
    frames.append(frame.resize((800,500),Image.Resampling.LANCZOS))
# Shared palette avoids GIF color flicker. 10 fps, 7.2 seconds.
palette=Image.new('RGB',(800,500*3))
for j,i in enumerate((0,24,48)): palette.paste(frames[i],(0,500*j))
palette=palette.quantize(colors=128)
indexed=[f.quantize(palette=palette,dither=Image.Dither.NONE) for f in frames]
indexed[0].save(OUT/'preview.gif',save_all=True,append_images=indexed[1:],duration=100,loop=0,disposal=1,optimize=True)
frames[0].save(OUT/'poster.png',optimize=True)
print('Created 72-frame black/crimson Apollo preview and three boot sprites')
