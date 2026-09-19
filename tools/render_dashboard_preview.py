#!/usr/bin/env python3
"""Render actual dashboard draw commands with fixture data, not an MT5 screenshot.

Requires Pillow only for the PNG review image. SVG uses browser font fallbacks.
Usage: python3 tools/render_dashboard_preview.py /tmp/xspark-scenes.txt docs/dashboard-preview.svg /tmp/dashboard-preview.png
"""
import html
from pathlib import Path
import shlex
import sys
from PIL import Image, ImageDraw, ImageFont

scenes = {}
for line in Path(sys.argv[1]).read_text().splitlines():
    if line.startswith('SCENE '):
        current = line[6:]; scenes[current] = []
    elif line.startswith('OBJECT '):
        scenes[current].append(shlex.split(line)[1:])
W,H=1316,802
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
text(28,22,'XSPARK  /  CHART CONSOLE',24,'#ecf0f4','Arial Bold')
text(28,57,'Illustrative source render with sample data. Native MT5 appearance remains to be verified.',12,'#899bab')
for scene,offset,label in [('live',16,'01  LIVE / MANAGING'),('stale',446,'02  PRICE FEED PAUSED'),('compact',876,'03  COMPACT VIEW')]:
    text(offset+12,90,label,10,'#f7b955','Arial Bold')
    for o in scenes[scene]:
        kind,x,y,w,h,bg,fg,pt,right=map(int,o[:9]);face,value,name=o[9:]
        x+=offset;y+=104
        if kind in (10,12):rect(x,y,w,h,f'#{bg:06x}',f'#{fg:06x}')
        if kind in (11,12):
            if kind==12:x+=w/2;y+=(h-pt*4/3)/2;right=False
            if kind==12:x-=draw.textlength(value,font=font(pt*4/3,face))/S/2
            text(x,y,value,pt*4/3,f'#{fg:06x}',face,bool(right))
text(892,448,'CONNECTED TO REAL STATE',12,'#f7b955','Arial Bold')
for i,line in enumerate(['Sampled bid activity and candle countdown.','Latest setup, score and entry-filter results.','Per-position profit and available trade slots.','Clear reason for waiting, plus the next step.','Compact mode for smaller chart windows.']):
    text(892,478+i*27,line,12,'#899bab')
svg.append('</svg>')
Path(sys.argv[2]).write_text('\n'.join(svg)+'\n')
im.save(sys.argv[3])
