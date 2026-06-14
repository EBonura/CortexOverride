#!/usr/bin/env python3
# Swap the cart's __map__ + __gfx__(rows 64-127) with the 72x72 blob
# region (m72_map.hex / m72_gfx.hex). Lua (_espawn/_doors_m) already
# edited by hand. Keeps __gfx__ rows 0-63 (tileset) and all code.
import os
here=os.path.dirname(__file__)
cart=os.path.join(here,"../v0.3.p8")
lines=open(cart).read().split("\n")
maphex=open(os.path.join(here,"m72_map.hex")).read().split("\n")
gfxbot=open(os.path.join(here,"m72_gfx.hex")).read().split("\n")
assert len(maphex)==32 and len(gfxbot)==64,(len(maphex),len(gfxbot))
def bounds(name):
    s=None
    for i,l in enumerate(lines):
        if l.startswith("__"+name+"__"): s=i; continue
        if s is not None and l.startswith("__") and i>s: return s,i
    return s,len(lines)
gs,ge=bounds("gfx")
gfx_rows=[r for r in lines[gs+1:ge] if r]
assert len(gfx_rows)>=64,len(gfx_rows)
lines[gs+1:ge]=gfx_rows[:64]+gfxbot
ms,me=bounds("map")
lines[ms+1:me]=maphex
open(cart,"w").write("\n".join(lines))
print("swapped __map__ (32 rows) + __gfx__ rows 64-127 with 72x72 data")
