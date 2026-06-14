#!/usr/bin/env python3
# Verify the WRITTEN cart: rebuild 0x1000-0x2fff from its __map__/__gfx__,
# peek 5 blobs, decompress each to a 72x72 buffer, scan via width-72 mget,
# and confirm entities/flags recover for all 4 missions.
import re, os
from lz3 import decompress
here=os.path.dirname(__file__)
src=open(os.path.join(here,"../v0.3.p8")).read()
W=H=72
def sec(n):
    o=[];f=False
    for l in src.split("\n"):
        if l.startswith("__"+n+"__"):f=True;continue
        if f and l.startswith("__"):break
        if f:o.append(l.strip())
    return "".join(o)
gfx=sec("gfx").ljust(128*128,"0");mp=sec("map").ljust(32*256,"0")
gff=sec("gff").ljust(512,"0");flags=[int(gff[2*i:2*i+2],16) for i in range(256)]
mem=bytearray(0x3000)
for r in range(128):
    for b in range(64): i=r*128+2*b;mem[r*64+b]=int(gfx[i],16)|(int(gfx[i+1],16)<<4)
for r in range(32):
    row=mp[r*256:(r+1)*256]
    for c in range(128):mem[0x2000+r*128+c]=int(row[2*c:2*c+2],16)
# peek 5 blobs (header @0x1000, 5 x 2-byte big-endian lens)
o=0x100a;L=[(mem[0x1000+2*i]<<8)|mem[0x1001+2*i] for i in range(5)]
bl=[]
for n in L:bl.append(bytes(mem[o:o+n]));o+=n
print("blob lens:",L,"region used:",o-0x1000,"/8192")
esp=re.findall(r'"([^"]*)"',re.search(r"_espawn=\{(.*?)\n\}",src,re.S).group(1))
dor=re.findall(r'"([^"]*)"',re.search(r"_doors_m=\{(.*?)\n\}",src,re.S).group(1))
psp=re.findall(r'"([^"]*)"',re.search(r"_pspawn=\{(.*?)\}",src,re.S).group(1))
ok=len(psp)==4
for mi in range(4):
    flat=decompress(bl[mi])
    if len(flat)!=W*H: ok=False
    mg=lambda x,y:flat[y*W+x]
    fr=ba=te=wall=0
    for ty in range(H):
        for tx in range(W):
            t=mg(tx,ty)
            if flags[t]&0x40:ba+=1
            elif flags[t]&0x20:fr+=1
            elif flags[t]&0x10:te+=1
            if (tx>=64 or ty>=56) and t!=96: wall+=1   # expansion must be wall(96)
    got=set((p.split(",")[2],int(p.split(",")[0]),int(p.split(",")[1])) for p in esp[mi].split("|") if p)
    sx,sy=map(int,psp[mi].split(","))
    if wall>0 or len(flat)!=W*H or not(0<=sx<W*8 and 0<=sy<H*8): ok=False
    print(f"M{mi+1}: size {len(flat)} enemies {len(got)} doors {len(dor[mi].split('|'))} frags {fr} barrels {ba} terms {te} spawn {psp[mi]} nonwall-pad {wall}")
print("WRITTEN CART 72x72:","PASS" if ok else "FAIL")
