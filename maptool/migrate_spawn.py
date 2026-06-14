#!/usr/bin/env python3
# Spawn migration: the player start is now a Lua _pspawn marker, so the
# old flag-7 spawn tile (38) is dead data in the maps. Replace 38->FLOOR
# (122) in all 4 maps, recompress, and rewrite __map__/__gfx__ in place.
import os
from lz3 import compress, decompress
here=os.path.dirname(__file__)
cart=os.path.join(here,"../v0.3.p8")
src=open(cart).read()
FLOOR=122
def sec(n):
    o=[];f=False
    for l in src.split("\n"):
        if l.startswith("__"+n+"__"):f=True;continue
        if f and l.startswith("__"):break
        if f:o.append(l.strip())
    return "".join(o)
gfx=sec("gfx").ljust(128*128,"0");mp=sec("map").ljust(32*256,"0")
mem=bytearray(0x3000)
for r in range(128):
    for b in range(64): i=r*128+2*b;mem[r*64+b]=int(gfx[i],16)|(int(gfx[i+1],16)<<4)
for r in range(32):
    row=mp[r*256:(r+1)*256]
    for c in range(128):mem[0x2000+r*128+c]=int(row[2*c:2*c+2],16)
o=0x100a;L=[(mem[0x1000+2*i]<<8)|mem[0x1001+2*i] for i in range(5)]
bl=[]
for n in L:bl.append(bytes(mem[o:o+n]));o+=n
blobs=[]
for mi in range(4):
    flat=bytearray(decompress(bl[mi]))
    n=flat.count(38)
    for i,v in enumerate(flat):
        if v==38: flat[i]=FLOOR
    print(f"M{mi+1}: replaced {n} spawn tile(s)")
    blobs.append(compress(bytes(flat)))
blobs.append(bl[4])                              # logo unchanged
hdr=bytearray()
for b in blobs: hdr+=bytes([len(b)>>8,len(b)&255])
region=bytes(hdr)+b"".join(blobs)
print("region:",len(region),"/8192")
assert len(region)<=0x2000
region=region.ljust(0x2000,b"\0")
maphex=["".join("%02x"%region[0x1000+r*128+c] for c in range(128)) for r in range(32)]
gfxbot=["".join("%x%x"%(region[r*64+i]&15,region[r*64+i]>>4) for i in range(64)) for r in range(64)]
lines=src.split("\n")
def bounds(name):
    s=None
    for i,l in enumerate(lines):
        if l.startswith("__"+name+"__"): s=i; continue
        if s is not None and l.startswith("__") and i>s: return s,i
    return s,len(lines)
gs,ge=bounds("gfx");gfx_rows=[r for r in lines[gs+1:ge] if r]
lines[gs+1:ge]=gfx_rows[:64]+gfxbot
ms,me=bounds("map");lines[ms+1:me]=maphex
open(cart,"w").write("\n".join(lines))
print("rewrote __map__/__gfx__ (spawn tiles -> floor)")
