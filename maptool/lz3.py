#!/usr/bin/env python3
# Greedy vs lazy LZ (LB=4, decoder-compatible with the cart).
def decompress(data):
    bi=0;bti=0;out=[]
    def rb(n=1):
        nonlocal bi,bti;v=0
        for _ in range(n):
            if bi>=len(data):return None
            v=(v<<1)|((data[bi]>>(7-bti))&1);bti+=1
            if bti==8:bti=0;bi+=1
        return v
    while True:
        f=rb()
        if f is None:return out
        if f==0:
            b=rb(8)
            if b is None:return out
            out.append(b)
        else:
            off=rb(12);ln=rb(4)
            if off is None:return out
            d=len(out)-off-1;ln+=1
            for _ in range(ln):out.append(out[d] if 0<=d<len(out) else 0);d+=1
class BW:
    def __init__(s):s.b=bytearray();s.c=0;s.n=0
    def w(s,val,n):
        for i in range(n-1,-1,-1):
            s.c=(s.c<<1)|((val>>i)&1);s.n+=1
            if s.n==8:s.b.append(s.c);s.c=0;s.n=0
    def fin(s):
        if s.n:s.b.append(s.c<<(8-s.n))
        return bytes(s.b)
MAXD=4096; MAXL=16
def best(data,i):
    n=len(data);bl=0;bo=0
    for j in range(max(0,i-MAXD),i):
        l=0
        while l<MAXL and i+l<n and data[j+l]==data[i+l]:l+=1
        if l>bl:
            bl=l;bo=i-j-1
            if l==MAXL:break
    return bl,bo
def compress(data,lazy=True):
    w=BW();i=0;n=len(data)
    while i<n:
        bl,bo=best(data,i)
        if bl>=2 and lazy and i+1<n:
            nl,_=best(data,i+1)
            if nl>bl:                 # defer: literal now, longer match next
                w.w(0,1);w.w(data[i],8);i+=1;continue
        if bl>=2:
            w.w(1,1);w.w(bo,12);w.w(bl-1,4);i+=bl
        else:
            w.w(0,1);w.w(data[i],8);i+=1
    return w.fin()

if __name__=="__main__":
    import json,os
    b=json.load(open(os.path.join(os.path.dirname(__file__),"bundle.json")))
    maps=b["maps"];sides=[0,64,0,64]
    def half64(g,c0):return [[g[y][c0+x] for x in range(64)] for y in range(64)]
    for lazy in (False,True):
        tot=0;per=[]
        for mi,g in enumerate(maps):
            h=half64(g,sides[mi])
            top=bytes(h[y][x] for y in range(32) for x in range(64))
            bot=bytes(h[y][x] for y in range(32,64) for x in range(64))
            ct,cb=compress(top,lazy),compress(bot,lazy)
            assert decompress(ct)==list(top) and decompress(cb)==list(bot)
            per.append(len(ct)+len(cb));tot+=len(ct)+len(cb)
        tot+=243
        print(f"lazy={lazy}: 64-wide per-map {per} total(+logo) {tot} -> {'FITS' if tot<=8192 else 'OVER'} (free {8192-tot})")
