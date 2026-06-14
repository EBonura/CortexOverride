#!/usr/bin/env python3
# Convert the current 2-shared maps -> 4 individual 72x72 maps stored
# as single CONTIGUOUS blobs (for the extended map @0x8000, width 72).
# Emits cart data sections + normalized _espawn/_doors_m, and simulates
# the new cart load (decompress->0x8000, mget width-72, scan).
import re, os
from lz3 import compress, decompress
here = os.path.dirname(__file__)
src = open(os.path.join(here, "../v0.3.p8")).read()
W = H = 72                                   # new map size
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
off=0x100a;lens=[(mem[0x1000+2*i]<<8)|mem[0x1001+2*i] for i in range(5)]
cur=[]
for L in lens:cur.append(bytes(mem[off:off+L]));off+=L
logo=cur[4]
def grid(t,b):
    dt=decompress(t);db=decompress(b);g=[]
    for y in range(56):
        g.append([(dt[y*128+x] if y<32 else (db[(y-32)*128+x] if (y-32)*128+x<len(db) else 96)) for x in range(128)])
    return g
A=grid(cur[0],cur[1]);B=grid(cur[2],cur[3]);WALL=96
sides=[0,64,0,64];SRC=[A,A,B,B]
# build 4 individual 72x72 terrain maps (content cols 0-63 rows 0-55 + wall)
maps=[]
for mi in range(4):
    g=SRC[mi];c0=sides[mi]
    maps.append([[ (g[y][c0+x] if (x<64 and y<56) else WALL) for x in range(W)] for y in range(H)])
# compress each as one contiguous blob
blobs=[compress(bytes(t for row in m for t in row)) for m in maps]+[logo]
hdr=bytearray()
for b in blobs: hdr+=bytes([len(b)>>8, len(b)&255])
region=bytes(hdr)+b"".join(blobs)
print("data region:",len(region),"/8192",("FITS, free "+str(8192-len(region))) if len(region)<=0x2000 else "OVER")
region=region.ljust(0x2000,b"\0")
# normalized _espawn/_doors_m (right missions shift -512px)
esp=re.findall(r'"([^"]*)"',re.search(r"_espawn=\{(.*?)\n\}",src,re.S).group(1))
dor=re.findall(r'"([^"]*)"',re.search(r"_doors_m=\{(.*?)\n\}",src,re.S).group(1))
def shift(s,xo,n):
    out=[]
    for u in s.split("|"):
        if not u:continue
        p=u.split(",")
        # x at positions 0 (and 2 for doors) shift by xo
        for idx in ([0,2] if n==5 else [0]):
            p[idx]=str(int(p[idx])-xo)
        out.append(",".join(p))
    return "|".join(out)
nesp=[shift(esp[m],sides[m]*8,3) for m in range(4)]
ndor=[shift(dor[m],sides[m]*8,5) for m in range(4)]
lua=lambda L:"{\n  "+",\n  ".join('"'+s+'"' for s in L)+"\n}"
open(os.path.join(here,"m72_lua.txt"),"w").write("_espawn="+lua(nesp)+"\n_doors_m="+lua(ndor)+"\n")
maphex="\n".join("".join("%02x"%region[0x1000+r*128+c] for c in range(128)) for r in range(32))
gfxbot="\n".join("".join("%x%x"%(region[r*64+i]&15,region[r*64+i]>>4) for i in range(64)) for r in range(64))
open(os.path.join(here,"m72_map.hex"),"w").write(maphex)
open(os.path.join(here,"m72_gfx.hex"),"w").write(gfxbot)

# ---- simulate new cart load ----
gff=sec("gff").ljust(512,"0");flags=[int(gff[2*i:2*i+2],16) for i in range(256)]
o=0x100a;L=[(region[0x1000+2*i-0x1000]<<8)|region[0x1000+2*i+1-0x1000] for i in range(5)]
bl=[]
for n in L:bl.append(region[o-0x1000:o-0x1000+n]);o+=n
ok=True
for mi in range(4):
    flat=decompress(bl[mi])                     # -> 0x8000, contiguous
    mg=lambda x,y:flat[y*W+x] if y*W+x<len(flat) else 0   # width-72 mget
    fr=ba=te=sp=0
    for ty in range(H):
        for tx in range(W):
            t=mg(tx,ty)
            if flags[t]&0x40:ba+=1
            elif flags[t]&0x20:fr+=1
            elif flags[t]&0x10:te+=1
            elif flags[t]&0x80:sp+=1
    got=set((p.split(",")[2],int(p.split(",")[0]),int(p.split(",")[1])) for p in nesp[mi].split("|") if p)
    exp=set((t,int(x)-sides[mi]*8,int(y)) for u in esp[mi].split("|") for x,y,t in [u.split(",")])
    if got!=exp or sp!=1:ok=False
    print(f"M{mi+1}: enemies {len(got)} {'OK' if got==exp else 'BAD'} | doors {len(ndor[mi].split('|'))} | frags {fr} barrels {ba} terms {te} spawn {sp}")
print("72x72 CART SIM:","PASS" if ok else "FAIL")
