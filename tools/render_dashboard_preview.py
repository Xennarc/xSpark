#!/usr/bin/env python3
"""Render actual dashboard draw commands with fixture data, not an MT5 screenshot.

Requires Pillow only for the PNG review image. SVG uses browser font fallbacks.
Usage: python3 tools/render_dashboard_preview.py /tmp/xspark-scenes.txt docs/dashboard-preview.svg /tmp/dashboard-preview.png
"""
import argparse
import html
from pathlib import Path
import shlex
from PIL import Image, ImageDraw, ImageFont

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('source', type=Path)
parser.add_argument('svg', type=Path)
parser.add_argument('png', type=Path)
parser.add_argument('--scene', help='Render one captured scene instead of the overview')
parser.add_argument('--dpi', type=int, default=96, help='Font DPI used by the captured fixture')
args=parser.parse_args()
scenes = {}
for line in args.source.read_text().splitlines():
    if line.startswith('SCENE '):
        current = line[6:]; scenes[current] = []
    elif line.startswith('OBJECT '):
        scenes[current].append(shlex.split(line)[1:])
def panel_size(scene):
    bg=next(o for o in scenes[scene] if o[-1]=='ScoreBotV3_Dashboard_bg')
    return int(bg[3]),int(bg[4])
choices=[(args.scene,f'READABLE SIZE / {args.dpi} DPI FIXTURE')] if args.scene else [('live','01  LIVE / MANAGING'),('stale','02  PRICE FEED PAUSED'),('compact','03  COMPACT VIEW')]
layout=[];offset=12
for scene,label in choices:
    layout.append((scene,offset,label));offset+=panel_size(scene)[0]+32
W=offset+12;H=max(panel_size(scene)[1] for scene,label in choices)+150
S=2
im=Image.new('RGB',(W*S,H*S),'#080e16');draw=ImageDraw.Draw(im)
svg=[f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">',f'<rect width="{W}" height="{H}" fill="#080e16"/>']
def font(size,face=''):
    base='/usr/share/fonts/truetype/dejavu/DejaVuSans'
    if face=='Consolas':base+='Mono'
    if 'Bold' in face:base+='-Bold'
    return ImageFont.truetype(base+'.ttf',round(size*S))
def text(x,y,value,size,fill,face='',right=False):
    f=font(size,face);length=draw.textlength(value,font=f)
    draw.text((x*S-length if right else x*S,y*S),value,font=f,fill=fill,anchor='lt')
    svg.append(f'<text x="{x}" y="{y+size*.8}" fill="{fill}" font-size="{size}" font-family="{html.escape(face or "Segoe UI")}, {"monospace" if face=="Consolas" else "sans-serif"}" font-weight="{"bold" if "Bold" in face else "normal"}" text-anchor="{"end" if right else "start"}">{html.escape(value)}</text>')
def rect(x,y,w,h,fill,border):
    draw.rectangle((x*S,y*S,(x+w)*S,(y+h)*S),fill=fill,outline=border,width=S)
    svg.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{fill}" stroke="{border}"/>')
text(28,22,'XSPARK  /  CHART CONSOLE',18 if args.scene else 24,'#ecf0f4','Arial Bold')
text(28,57,'Illustrative source render; not a native MT5 screenshot.' if args.scene else 'Illustrative source render with sample data. Native MT5 appearance remains to be verified.',10 if args.scene else 12,'#899bab')
for scene,offset,label in layout:
    text(offset+12,90,label,10,'#f7b955','Arial Bold')
    for o in scenes[scene]:
        kind,x,y,w,h,bg,fg,pt,right=map(int,o[:9]);face,value,name=o[9:]
        x+=offset;y+=104
        if kind in (10,12):rect(x,y,w,h,f'#{bg:06x}',f'#{fg:06x}')
        if kind in (11,12):
            if kind==12:x+=w/2;y+=(h-pt*args.dpi/72)/2;right=False
            if kind==12:x-=draw.textlength(value,font=font(pt*args.dpi/72,face))/S/2
            text(x,y,value,pt*args.dpi/72,f'#{fg:06x}',face,bool(right))
if not args.scene:
    notes_x=layout[-1][1]+12;notes_y=panel_size('compact')[1]+180
    text(notes_x,notes_y,'CONNECTED TO REAL STATE',12,'#f7b955','Arial Bold')
    for i,line in enumerate(['Sampled bid activity and candle countdown.','Latest setup, score and entry-filter results.','Per-position profit and available trade slots.','Clear reason for waiting, plus the next step.','Compact mode for smaller chart windows.']):
        text(notes_x,notes_y+30+i*27,line,12,'#899bab')
svg.append('</svg>')
args.svg.write_text('\n'.join(svg)+'\n')
im.save(args.png)
