pico-8 cartridge // http://www.pico-8.com
version 43
__lua__

-- color light benchmark
-- fixed 4-light scene
-- x: cycle mode (scan/quad)
-- prints cpu to console

-- pico-8 palette rgb
pr={0,29,126,0,171,95,194,255,255,255,255,0,41,131,255,255}
pg={0,43,37,135,82,87,195,241,0,163,236,228,173,118,119,204}
pb={0,83,83,81,54,79,199,232,77,0,39,54,255,156,168,170}

-- memory layout:
-- 0x4300: 4-ramp tint (125×16=2000b)
tint_addr=0x4300

-- quadtree helper state
_lsx,_lsy,_lR2={},{},{}
_lir2,_lr12,_lr22={},{},{}
_llr,_llg,_llb={},{},{}
_ldy2={}
_nl=0

function _init()
 palt(0,false)
 palt(14,true)
 fset(1,0,true)
 init_tint(tint_addr,4)

 all_lights={
  {x=64,y=64,ir=25,fo=25,lr=1,lg=1,lb=1},
  {x=36,y=36,ir=18,fo=22,lr=1,lg=0.1,lb=0.05},
  {x=100,y=36,ir=18,fo=22,lr=0.05,lg=0.1,lb=1},
  {x=64,y=100,ir=15,fo=20,lr=0.1,lg=1,lb=0.1},
 }

 modes={"unr2","unr4"}
 -- benchmark state
 bmi=1
 bfr=0
 bsum=0
 brun=6
 bavg={}
 bdone=false
end

----------------------------
-- nearest color (manhattan)
-- skips color 14 (transp)
----------------------------
function find_near(tr,tg,tb)
 local best,bd=0,32767
 for i=0,15 do
  if i~=14 then
   local dr=pr[i+1]-tr
   local dg=pg[i+1]-tg
   local db=pb[i+1]-tb
   local d=abs(dr)+abs(dg)+abs(db)
   if d<bd then best,bd=i,d end
  end
 end
 return best
end

----------------------------
-- build tint table
-- ml=3: 64 states (r*16+g*4+b)
-- ml=4: 125 states (r*25+g*5+b)
-- blended model: 60% color,
-- 40% uniform darkening
----------------------------
function init_tint(addr,ml)
 local s2=ml+1
 local s1=s2*s2
 local full=ml*s1+ml*s2+ml
 for r=0,ml do
  for g=0,ml do
   for b=0,ml do
    local state=r*s1+g*s2+b
    local lr,lg,lb=r/ml,g/ml,b/ml
    local mx=max(lr,max(lg,lb))
    local mn=min(lr,min(lg,lb))
    local sat=0
    if mx>0 then sat=(mx-mn)/mx end
    local blend=sat*0.6
    for c=0,15 do
     local out
     if state==0 then
      out=0
     elseif state==full then
      out=c
     else
      local ur=pr[c+1]*mx
      local ug=pg[c+1]*mx
      local ub=pb[c+1]*mx
      local mr=pr[c+1]*lr
      local mg=pg[c+1]*lg
      local mb=pb[c+1]*lb
      local b1=1-blend
      out=find_near(
       ur*b1+mr*blend,
       ug*b1+mg*blend,
       ub*b1+mb*blend)
     end
     poke(addr+state*16+c,out)
    end
   end
  end
 end
end

----------------------------
-- update
----------------------------
function _update()
end

----------------------------
-- draw
----------------------------
function _draw()
 if bdone then return end

 cls()
 cam_x=0 cam_y=0
 camera(cam_x,cam_y)
 map(0,0,0,0,16,16)

 local nl=4
 local lights={}
 local sc=0.5

 for i=1,nl do
  local lt=all_lights[i]
  lights[i]=lt
  lt.sx=(lt.x-cam_x)*sc
  lt.sy=(lt.y-cam_y)*sc
  local ir=lt.ir*sc
  local fo=lt.fo*sc
  local rad=ir+fo
  lt.ir2=ir*ir
  lt.R2=rad*rad
  local s=fo/3
  lt.r12=(ir+s)*(ir+s)
  lt.r22=(ir+s*2)*(ir+s*2)
 end

 if bmi==1 then
  apply_unr2(lights,nl)
 else
  apply_unr4(lights,nl)
 end

 local cpu=stat(1)
 bfr+=1
 -- skip first frame (warmup)
 if bfr>1 then bsum+=cpu end

 camera()
 rectfill(0,0,127,13,0)
 local name=modes[bmi]
 print(name.." fr:"..bfr.."/"..brun
  .." cpu:"..cpu,1,2,7)
 if bfr>1 then
  print("avg:"..(bsum/(bfr-1)),1,8,6)
 end

 if bfr>=brun then
  local avg=bsum/(brun-1)
  bavg[bmi]=avg
  printh(name..": avg="..avg
   .." ("..(brun-1).." frames)")
  bmi+=1
  bfr=0 bsum=0
  if bmi>#modes then
   printh("--- results ---")
   for i=1,#modes do
    printh(modes[i]..": "..bavg[i])
   end
   bdone=true
  end
 end
end

----------------------------
-- quadtree: memset dark block
----------------------------
function quad_dark(x0,y0,sz)
 for y=y0,y0+sz-1 do
  local a=0x6000+y*128+x0
  memset(a,0,sz) memset(a+64,0,sz)
 end
end

----------------------------
-- quadtree: per-pixel 8x8
----------------------------
function quad_lit(x0,y0)
 local nl=_nl
 local sx,sy,R2=_lsx,_lsy,_lR2
 local ir2,r12,r22=_lir2,_lr12,_lr22
 local lr,lg,lb=_llr,_llg,_llb
 local dy2=_ldy2
 local ta=tint_addr
 local mn,ms=min,memset

 for y=y0,y0+7 do
  local row1=0x6000+y*128
  local row2=row1+64
  local any=false
  for i=1,nl do
   local d=sy[i]-y
   dy2[i]=d*d
   if dy2[i]<R2[i] then any=true end
  end
  if not any then
   ms(row1+x0,0,8) ms(row2+x0,0,8)
  else
   for x=x0,x0+7 do
    local ar,ag,ab=0,0,0
    for i=1,nl do
     if dy2[i]<R2[i] then
      local dx=sx[i]-x
      local d2=dy2[i]+dx*dx
      if d2<R2[i] then
       local lev
       if d2<=ir2[i] then lev=4
       elseif d2<r12[i] then lev=3
       elseif d2<r22[i] then lev=2
       else lev=1 end
       ar+=lr[i]*lev
       ag+=lg[i]*lev
       ab+=lb[i]*lev
      end
     end
    end
    local ri=mn(4,(ar+0.5)\1)
    local gi=mn(4,(ag+0.5)\1)
    local bi=mn(4,(ab+0.5)\1)
    local state=ri*25+gi*5+bi
    if state==0 then
     poke(row1+x,0) poke(row2+x,0)
    elseif state~=124 then
     local base=ta+state*16
     local sv=@(row1+x)
     poke(row1+x,@(base+sv\16)*16+@(base+sv%16))
     sv=@(row2+x)
     poke(row2+x,@(base+sv\16)*16+@(base+sv%16))
    end
   end
  end
 end
end

----------------------------
-- quadtree: subdivide
-- 64→32→16→8 then per-pixel
----------------------------
function quad_proc(x0,y0,sz)
 local x1=x0+sz-1
 local y1=y0+sz-1
 local hit=false
 local sx,sy,R2=_lsx,_lsy,_lR2
 local mn,mx=min,max
 for i=1,_nl do
  local cx=mx(x0,mn(x1,sx[i]))
  local cy=mx(y0,mn(y1,sy[i]))
  local dx=sx[i]-cx
  local dy=sy[i]-cy
  if dx*dx+dy*dy<R2[i] then
   hit=true break
  end
 end
 if not hit then
  quad_dark(x0,y0,sz)
  return
 end
 if sz<=8 then
  quad_lit(x0,y0)
  return
 end
 local h=sz\2
 quad_proc(x0,y0,h)
 quad_proc(x0+h,y0,h)
 quad_proc(x0,y0+h,h)
 quad_proc(x0+h,y0+h,h)
end

----------------------------
-- 64x64 quadtree mode
-- subdivides 64→32→16→8
----------------------------
function apply_quad(lights,nl)
 _nl=nl
 for i=1,nl do
  local lt=lights[i]
  _lsx[i]=lt.sx _lsy[i]=lt.sy
  _lR2[i]=lt.R2 _lir2[i]=lt.ir2
  _lr12[i]=lt.r12 _lr22[i]=lt.r22
  _llr[i]=lt.lr _llg[i]=lt.lg _llb[i]=lt.lb
 end
 quad_proc(0,0,64)
end

----------------------------
-- 64x64 optimized row-scan
-- arrays instead of hash,
-- \1 instead of flr()
----------------------------
function apply_opt(lights,nl)
 -- extract to flat arrays
 local sx,sy,R2=_lsx,_lsy,_lR2
 local ir2,r12,r22=_lir2,_lr12,_lr22
 local lr,lg,lb=_llr,_llg,_llb
 local dy2=_ldy2
 for i=1,nl do
  local lt=lights[i]
  sx[i]=lt.sx sy[i]=lt.sy
  R2[i]=lt.R2 ir2[i]=lt.ir2
  r12[i]=lt.r12 r22[i]=lt.r22
  lr[i]=lt.lr lg[i]=lt.lg lb[i]=lt.lb
 end

 local _sq,_mn,_mx,_ms=sqrt,min,max,memset
 local _ta=tint_addr

 for y=0,63 do
  local row1=0x6000+y*128
  local row2=row1+64

  local any=false
  for i=1,nl do
   local d=sy[i]-y
   dy2[i]=d*d
   if dy2[i]<R2[i] then any=true end
  end

  if not any then
   _ms(row1,0,64)
   _ms(row2,0,64)
  else
   local lx,rx=63,0
   for i=1,nl do
    if dy2[i]<R2[i] then
     local cdx=_sq(R2[i]-dy2[i])
     local l=_mx(0,(sx[i]-cdx)\1)
     local r=_mn(63,(sx[i]+cdx)\1)
     if l<lx then lx=l end
     if r>rx then rx=r end
    end
   end

   if lx>0 then
    _ms(row1,0,lx)
    _ms(row2,0,lx)
   end
   if rx<63 then
    _ms(row1+rx+1,0,63-rx)
    _ms(row2+rx+1,0,63-rx)
   end

   for x=lx,rx do
    local ar,ag,ab=0,0,0
    for i=1,nl do
     if dy2[i]<R2[i] then
      local dx=sx[i]-x
      local d2=dy2[i]+dx*dx
      if d2<R2[i] then
       local lev
       if d2<=ir2[i] then lev=4
       elseif d2<r12[i] then lev=3
       elseif d2<r22[i] then lev=2
       else lev=1 end
       ar+=lr[i]*lev
       ag+=lg[i]*lev
       ab+=lb[i]*lev
      end
     end
    end

    local ri=_mn(4,(ar+0.5)\1)
    local gi=_mn(4,(ag+0.5)\1)
    local bi=_mn(4,(ab+0.5)\1)
    local state=ri*25+gi*5+bi

    if state==0 then
     poke(row1+x,0)
     poke(row2+x,0)
    elseif state~=124 then
     local base=_ta+state*16
     local sv=@(row1+x)
     poke(row1+x,@(base+sv\16)*16+@(base+sv%16))
     sv=@(row2+x)
     poke(row2+x,@(base+sv\16)*16+@(base+sv%16))
    end
   end
  end
 end
end

----------------------------
-- 64x64 unr4: stepped distance
-- dd-=td; td-=2 per step
-- no multiply in inner loop
----------------------------
function apply_unr4(lights,nl)
 local _sq,_ms=sqrt,memset
 local _ta=tint_addr
 local l=lights[1]
 local sx1,sy1,R21=l.sx,l.sy,l.R2
 local ir21,r121,r221=l.ir2,l.r12,l.r22
 local r1a,r1b,r1c,r1d=l.lr,l.lr*2,l.lr*3,l.lr*4
 local g1a,g1b,g1c,g1d=l.lg,l.lg*2,l.lg*3,l.lg*4
 local b1a,b1b,b1c,b1d=l.lb,l.lb*2,l.lb*3,l.lb*4
 l=lights[2]
 local sx2,sy2,R22=l.sx,l.sy,l.R2
 local ir22,r122,r222=l.ir2,l.r12,l.r22
 local r2a,r2b,r2c,r2d=l.lr,l.lr*2,l.lr*3,l.lr*4
 local g2a,g2b,g2c,g2d=l.lg,l.lg*2,l.lg*3,l.lg*4
 local b2a,b2b,b2c,b2d=l.lb,l.lb*2,l.lb*3,l.lb*4
 l=lights[3]
 local sx3,sy3,R23=l.sx,l.sy,l.R2
 local ir23,r123,r223=l.ir2,l.r12,l.r22
 local r3a,r3b,r3c,r3d=l.lr,l.lr*2,l.lr*3,l.lr*4
 local g3a,g3b,g3c,g3d=l.lg,l.lg*2,l.lg*3,l.lg*4
 local b3a,b3b,b3c,b3d=l.lb,l.lb*2,l.lb*3,l.lb*4
 l=lights[4]
 local sx4,sy4,R24=l.sx,l.sy,l.R2
 local ir24,r124,r224=l.ir2,l.r12,l.r22
 local r4a,r4b,r4c,r4d=l.lr,l.lr*2,l.lr*3,l.lr*4
 local g4a,g4b,g4c,g4d=l.lg,l.lg*2,l.lg*3,l.lg*4
 local b4a,b4b,b4c,b4d=l.lb,l.lb*2,l.lb*3,l.lb*4

 for y=0,63 do
  local row1=0x6000+y*128
  local row2=row1+64
  local d=sy1-y local dy21=d*d
  d=sy2-y local dy22=d*d
  d=sy3-y local dy23=d*d
  d=sy4-y local dy24=d*d
  local h1=dy21<R21
  local h2=dy22<R22
  local h3=dy23<R23
  local h4=dy24<R24

  if not (h1 or h2 or h3 or h4) then
   _ms(row1,0,64)
   _ms(row2,0,64)
  else
   local lx,rx=63,0
   if h1 then
    local c=_sq(R21-dy21)
    local a=(sx1-c)\1 if a<0 then a=0 end
    local b=(sx1+c)\1 if b>63 then b=63 end
    if a<lx then lx=a end
    if b>rx then rx=b end
   end
   if h2 then
    local c=_sq(R22-dy22)
    local a=(sx2-c)\1 if a<0 then a=0 end
    local b=(sx2+c)\1 if b>63 then b=63 end
    if a<lx then lx=a end
    if b>rx then rx=b end
   end
   if h3 then
    local c=_sq(R23-dy23)
    local a=(sx3-c)\1 if a<0 then a=0 end
    local b=(sx3+c)\1 if b>63 then b=63 end
    if a<lx then lx=a end
    if b>rx then rx=b end
   end
   if h4 then
    local c=_sq(R24-dy24)
    local a=(sx4-c)\1 if a<0 then a=0 end
    local b=(sx4+c)\1 if b>63 then b=63 end
    if a<lx then lx=a end
    if b>rx then rx=b end
   end

   if lx>0 then
    _ms(row1,0,lx)
    _ms(row2,0,lx)
   end
   if rx<63 then
    _ms(row1+rx+1,0,63-rx)
    _ms(row2+rx+1,0,63-rx)
   end

   -- init stepped dd per light
   local dd1,td1,dd2,td2
   local dd3,td3,dd4,td4
   if h1 then
    d=sx1-lx dd1=dy21+d*d td1=d+d-1
   end
   if h2 then
    d=sx2-lx dd2=dy22+d*d td2=d+d-1
   end
   if h3 then
    d=sx3-lx dd3=dy23+d*d td3=d+d-1
   end
   if h4 then
    d=sx4-lx dd4=dy24+d*d td4=d+d-1
   end

   for x=lx,rx do
    local ar,ag,ab=0,0,0
    if h1 then
     if dd1<R21 then
      if dd1<=ir21 then ar+=r1d ag+=g1d ab+=b1d
      elseif dd1<r121 then ar+=r1c ag+=g1c ab+=b1c
      elseif dd1<r221 then ar+=r1b ag+=g1b ab+=b1b
      else ar+=r1a ag+=g1a ab+=b1a end
     end
     dd1-=td1 td1-=2
    end
    if h2 then
     if dd2<R22 then
      if dd2<=ir22 then ar+=r2d ag+=g2d ab+=b2d
      elseif dd2<r122 then ar+=r2c ag+=g2c ab+=b2c
      elseif dd2<r222 then ar+=r2b ag+=g2b ab+=b2b
      else ar+=r2a ag+=g2a ab+=b2a end
     end
     dd2-=td2 td2-=2
    end
    if h3 then
     if dd3<R23 then
      if dd3<=ir23 then ar+=r3d ag+=g3d ab+=b3d
      elseif dd3<r123 then ar+=r3c ag+=g3c ab+=b3c
      elseif dd3<r223 then ar+=r3b ag+=g3b ab+=b3b
      else ar+=r3a ag+=g3a ab+=b3a end
     end
     dd3-=td3 td3-=2
    end
    if h4 then
     if dd4<R24 then
      if dd4<=ir24 then ar+=r4d ag+=g4d ab+=b4d
      elseif dd4<r124 then ar+=r4c ag+=g4c ab+=b4c
      elseif dd4<r224 then ar+=r4b ag+=g4b ab+=b4b
      else ar+=r4a ag+=g4a ab+=b4a end
     end
     dd4-=td4 td4-=2
    end

    local ri=(ar+0.5)\1 if ri>4 then ri=4 end
    local gi=(ag+0.5)\1 if gi>4 then gi=4 end
    local bi=(ab+0.5)\1 if bi>4 then bi=4 end
    local state=ri*25+gi*5+bi

    if state==0 then
     poke(row1+x,0)
     poke(row2+x,0)
    elseif state~=124 then
     local base=_ta+state*16
     local sv=@(row1+x)
     poke(row1+x,@(base+sv\16)*16+@(base+sv%16))
     sv=@(row2+x)
     poke(row2+x,@(base+sv\16)*16+@(base+sv%16))
    end
   end
  end
 end
end

----------------------------
-- 64x64 unr3: state lookup
-- 625-entry (l1,l2,l3,l4)→state
-- eliminates rgb accum+round
----------------------------
function apply_unr3(lights,nl)
 local _sq,_ms=sqrt,memset
 local _ta=tint_addr
 local _sa=0x4ad0
 local l=lights[1]
 local sx1,sy1,R21=l.sx,l.sy,l.R2
 local ir21,r121,r221=l.ir2,l.r12,l.r22
 local lr1,lg1,lb1=l.lr,l.lg,l.lb
 l=lights[2]
 local sx2,sy2,R22=l.sx,l.sy,l.R2
 local ir22,r122,r222=l.ir2,l.r12,l.r22
 local lr2,lg2,lb2=l.lr,l.lg,l.lb
 l=lights[3]
 local sx3,sy3,R23=l.sx,l.sy,l.R2
 local ir23,r123,r223=l.ir2,l.r12,l.r22
 local lr3,lg3,lb3=l.lr,l.lg,l.lb
 l=lights[4]
 local sx4,sy4,R24=l.sx,l.sy,l.R2
 local ir24,r124,r224=l.ir2,l.r12,l.r22
 local lr4,lg4,lb4=l.lr,l.lg,l.lb

 -- build 625-entry state lookup
 local sa=_sa
 for a=0,4 do
  for b=0,4 do
   for c=0,4 do
    for d=0,4 do
     local ar=lr1*a+lr2*b+lr3*c+lr4*d
     local ag=lg1*a+lg2*b+lg3*c+lg4*d
     local ab=lb1*a+lb2*b+lb3*c+lb4*d
     local ri=(ar+0.5)\1 if ri>4 then ri=4 end
     local gi=(ag+0.5)\1 if gi>4 then gi=4 end
     local bi=(ab+0.5)\1 if bi>4 then bi=4 end
     poke(sa,ri*25+gi*5+bi)
     sa+=1
    end
   end
  end
 end

 for y=0,63 do
  local row1=0x6000+y*128
  local row2=row1+64
  local d=sy1-y local dy21=d*d
  d=sy2-y local dy22=d*d
  d=sy3-y local dy23=d*d
  d=sy4-y local dy24=d*d
  local h1=dy21<R21
  local h2=dy22<R22
  local h3=dy23<R23
  local h4=dy24<R24

  if not (h1 or h2 or h3 or h4) then
   _ms(row1,0,64)
   _ms(row2,0,64)
  else
   local lx,rx=63,0
   if h1 then
    local c=_sq(R21-dy21)
    local a=(sx1-c)\1 if a<0 then a=0 end
    local b=(sx1+c)\1 if b>63 then b=63 end
    if a<lx then lx=a end
    if b>rx then rx=b end
   end
   if h2 then
    local c=_sq(R22-dy22)
    local a=(sx2-c)\1 if a<0 then a=0 end
    local b=(sx2+c)\1 if b>63 then b=63 end
    if a<lx then lx=a end
    if b>rx then rx=b end
   end
   if h3 then
    local c=_sq(R23-dy23)
    local a=(sx3-c)\1 if a<0 then a=0 end
    local b=(sx3+c)\1 if b>63 then b=63 end
    if a<lx then lx=a end
    if b>rx then rx=b end
   end
   if h4 then
    local c=_sq(R24-dy24)
    local a=(sx4-c)\1 if a<0 then a=0 end
    local b=(sx4+c)\1 if b>63 then b=63 end
    if a<lx then lx=a end
    if b>rx then rx=b end
   end

   if lx>0 then
    _ms(row1,0,lx)
    _ms(row2,0,lx)
   end
   if rx<63 then
    _ms(row1+rx+1,0,63-rx)
    _ms(row2+rx+1,0,63-rx)
   end

   for x=lx,rx do
    local v1,v2,v3,v4=0,0,0,0
    if h1 then
     local dx=sx1-x
     local dd=dy21+dx*dx
     if dd<R21 then
      if dd<=ir21 then v1=4
      elseif dd<r121 then v1=3
      elseif dd<r221 then v1=2
      else v1=1 end
     end
    end
    if h2 then
     local dx=sx2-x
     local dd=dy22+dx*dx
     if dd<R22 then
      if dd<=ir22 then v2=4
      elseif dd<r122 then v2=3
      elseif dd<r222 then v2=2
      else v2=1 end
     end
    end
    if h3 then
     local dx=sx3-x
     local dd=dy23+dx*dx
     if dd<R23 then
      if dd<=ir23 then v3=4
      elseif dd<r123 then v3=3
      elseif dd<r223 then v3=2
      else v3=1 end
     end
    end
    if h4 then
     local dx=sx4-x
     local dd=dy24+dx*dx
     if dd<R24 then
      if dd<=ir24 then v4=4
      elseif dd<r124 then v4=3
      elseif dd<r224 then v4=2
      else v4=1 end
     end
    end

    local state=@(_sa+v1*125+v2*25+v3*5+v4)
    if state==0 then
     poke(row1+x,0)
     poke(row2+x,0)
    elseif state~=124 then
     local base=_ta+state*16
     local sv=@(row1+x)
     poke(row1+x,@(base+sv\16)*16+@(base+sv%16))
     sv=@(row2+x)
     poke(row2+x,@(base+sv\16)*16+@(base+sv%16))
    end
   end
  end
 end
end

----------------------------
-- 64x64 unr2: pre-multiplied
-- levels + inline min
-- zero mults in inner loop
----------------------------
function apply_unr2(lights,nl)
 local _sq,_ms=sqrt,memset
 local _ta=tint_addr
 local l=lights[1]
 local sx1,sy1,R21=l.sx,l.sy,l.R2
 local ir21,r121,r221=l.ir2,l.r12,l.r22
 local r1a,r1b,r1c,r1d=l.lr,l.lr*2,l.lr*3,l.lr*4
 local g1a,g1b,g1c,g1d=l.lg,l.lg*2,l.lg*3,l.lg*4
 local b1a,b1b,b1c,b1d=l.lb,l.lb*2,l.lb*3,l.lb*4
 l=lights[2]
 local sx2,sy2,R22=l.sx,l.sy,l.R2
 local ir22,r122,r222=l.ir2,l.r12,l.r22
 local r2a,r2b,r2c,r2d=l.lr,l.lr*2,l.lr*3,l.lr*4
 local g2a,g2b,g2c,g2d=l.lg,l.lg*2,l.lg*3,l.lg*4
 local b2a,b2b,b2c,b2d=l.lb,l.lb*2,l.lb*3,l.lb*4
 l=lights[3]
 local sx3,sy3,R23=l.sx,l.sy,l.R2
 local ir23,r123,r223=l.ir2,l.r12,l.r22
 local r3a,r3b,r3c,r3d=l.lr,l.lr*2,l.lr*3,l.lr*4
 local g3a,g3b,g3c,g3d=l.lg,l.lg*2,l.lg*3,l.lg*4
 local b3a,b3b,b3c,b3d=l.lb,l.lb*2,l.lb*3,l.lb*4
 l=lights[4]
 local sx4,sy4,R24=l.sx,l.sy,l.R2
 local ir24,r124,r224=l.ir2,l.r12,l.r22
 local r4a,r4b,r4c,r4d=l.lr,l.lr*2,l.lr*3,l.lr*4
 local g4a,g4b,g4c,g4d=l.lg,l.lg*2,l.lg*3,l.lg*4
 local b4a,b4b,b4c,b4d=l.lb,l.lb*2,l.lb*3,l.lb*4

 for y=0,63 do
  local row1=0x6000+y*128
  local row2=row1+64
  local d=sy1-y local dy21=d*d
  d=sy2-y local dy22=d*d
  d=sy3-y local dy23=d*d
  d=sy4-y local dy24=d*d
  local h1=dy21<R21
  local h2=dy22<R22
  local h3=dy23<R23
  local h4=dy24<R24

  if not (h1 or h2 or h3 or h4) then
   _ms(row1,0,64)
   _ms(row2,0,64)
  else
   local lx,rx=63,0
   if h1 then
    local c=_sq(R21-dy21)
    local a=(sx1-c)\1 if a<0 then a=0 end
    local b=(sx1+c)\1 if b>63 then b=63 end
    if a<lx then lx=a end
    if b>rx then rx=b end
   end
   if h2 then
    local c=_sq(R22-dy22)
    local a=(sx2-c)\1 if a<0 then a=0 end
    local b=(sx2+c)\1 if b>63 then b=63 end
    if a<lx then lx=a end
    if b>rx then rx=b end
   end
   if h3 then
    local c=_sq(R23-dy23)
    local a=(sx3-c)\1 if a<0 then a=0 end
    local b=(sx3+c)\1 if b>63 then b=63 end
    if a<lx then lx=a end
    if b>rx then rx=b end
   end
   if h4 then
    local c=_sq(R24-dy24)
    local a=(sx4-c)\1 if a<0 then a=0 end
    local b=(sx4+c)\1 if b>63 then b=63 end
    if a<lx then lx=a end
    if b>rx then rx=b end
   end

   if lx>0 then
    _ms(row1,0,lx)
    _ms(row2,0,lx)
   end
   if rx<63 then
    _ms(row1+rx+1,0,63-rx)
    _ms(row2+rx+1,0,63-rx)
   end

   for x=lx,rx do
    local ar,ag,ab=0,0,0
    if h1 then
     local dx=sx1-x
     local dd=dy21+dx*dx
     if dd<R21 then
      if dd<=ir21 then ar+=r1d ag+=g1d ab+=b1d
      elseif dd<r121 then ar+=r1c ag+=g1c ab+=b1c
      elseif dd<r221 then ar+=r1b ag+=g1b ab+=b1b
      else ar+=r1a ag+=g1a ab+=b1a end
     end
    end
    if h2 then
     local dx=sx2-x
     local dd=dy22+dx*dx
     if dd<R22 then
      if dd<=ir22 then ar+=r2d ag+=g2d ab+=b2d
      elseif dd<r122 then ar+=r2c ag+=g2c ab+=b2c
      elseif dd<r222 then ar+=r2b ag+=g2b ab+=b2b
      else ar+=r2a ag+=g2a ab+=b2a end
     end
    end
    if h3 then
     local dx=sx3-x
     local dd=dy23+dx*dx
     if dd<R23 then
      if dd<=ir23 then ar+=r3d ag+=g3d ab+=b3d
      elseif dd<r123 then ar+=r3c ag+=g3c ab+=b3c
      elseif dd<r223 then ar+=r3b ag+=g3b ab+=b3b
      else ar+=r3a ag+=g3a ab+=b3a end
     end
    end
    if h4 then
     local dx=sx4-x
     local dd=dy24+dx*dx
     if dd<R24 then
      if dd<=ir24 then ar+=r4d ag+=g4d ab+=b4d
      elseif dd<r124 then ar+=r4c ag+=g4c ab+=b4c
      elseif dd<r224 then ar+=r4b ag+=g4b ab+=b4b
      else ar+=r4a ag+=g4a ab+=b4a end
     end
    end

    local ri=(ar+0.5)\1 if ri>4 then ri=4 end
    local gi=(ag+0.5)\1 if gi>4 then gi=4 end
    local bi=(ab+0.5)\1 if bi>4 then bi=4 end
    local state=ri*25+gi*5+bi

    if state==0 then
     poke(row1+x,0)
     poke(row2+x,0)
    elseif state~=124 then
     local base=_ta+state*16
     local sv=@(row1+x)
     poke(row1+x,@(base+sv\16)*16+@(base+sv%16))
     sv=@(row2+x)
     poke(row2+x,@(base+sv\16)*16+@(base+sv%16))
    end
   end
  end
 end
end

----------------------------
-- 64x64 unrolled 4-light
-- all fields as plain locals
-- zero table access in loop
----------------------------
function apply_unrl(lights,nl)
 local _sq,_mn,_ms=sqrt,min,memset
 local _ta=tint_addr
 local l=lights[1]
 local sx1,sy1,R21=l.sx,l.sy,l.R2
 local ir21,r121,r221=l.ir2,l.r12,l.r22
 local lr1,lg1,lb1=l.lr,l.lg,l.lb
 l=lights[2]
 local sx2,sy2,R22=l.sx,l.sy,l.R2
 local ir22,r122,r222=l.ir2,l.r12,l.r22
 local lr2,lg2,lb2=l.lr,l.lg,l.lb
 l=lights[3]
 local sx3,sy3,R23=l.sx,l.sy,l.R2
 local ir23,r123,r223=l.ir2,l.r12,l.r22
 local lr3,lg3,lb3=l.lr,l.lg,l.lb
 l=lights[4]
 local sx4,sy4,R24=l.sx,l.sy,l.R2
 local ir24,r124,r224=l.ir2,l.r12,l.r22
 local lr4,lg4,lb4=l.lr,l.lg,l.lb

 for y=0,63 do
  local row1=0x6000+y*128
  local row2=row1+64
  local d=sy1-y local dy21=d*d
  d=sy2-y local dy22=d*d
  d=sy3-y local dy23=d*d
  d=sy4-y local dy24=d*d
  local h1=dy21<R21
  local h2=dy22<R22
  local h3=dy23<R23
  local h4=dy24<R24

  if not (h1 or h2 or h3 or h4) then
   _ms(row1,0,64)
   _ms(row2,0,64)
  else
   local lx,rx=63,0
   if h1 then
    local c=_sq(R21-dy21)
    local a=(sx1-c)\1 if a<0 then a=0 end
    local b=(sx1+c)\1 if b>63 then b=63 end
    if a<lx then lx=a end
    if b>rx then rx=b end
   end
   if h2 then
    local c=_sq(R22-dy22)
    local a=(sx2-c)\1 if a<0 then a=0 end
    local b=(sx2+c)\1 if b>63 then b=63 end
    if a<lx then lx=a end
    if b>rx then rx=b end
   end
   if h3 then
    local c=_sq(R23-dy23)
    local a=(sx3-c)\1 if a<0 then a=0 end
    local b=(sx3+c)\1 if b>63 then b=63 end
    if a<lx then lx=a end
    if b>rx then rx=b end
   end
   if h4 then
    local c=_sq(R24-dy24)
    local a=(sx4-c)\1 if a<0 then a=0 end
    local b=(sx4+c)\1 if b>63 then b=63 end
    if a<lx then lx=a end
    if b>rx then rx=b end
   end

   if lx>0 then
    _ms(row1,0,lx)
    _ms(row2,0,lx)
   end
   if rx<63 then
    _ms(row1+rx+1,0,63-rx)
    _ms(row2+rx+1,0,63-rx)
   end

   for x=lx,rx do
    local ar,ag,ab=0,0,0
    if h1 then
     local dx=sx1-x
     local dd=dy21+dx*dx
     if dd<R21 then
      local lv
      if dd<=ir21 then lv=4
      elseif dd<r121 then lv=3
      elseif dd<r221 then lv=2
      else lv=1 end
      ar+=lr1*lv ag+=lg1*lv ab+=lb1*lv
     end
    end
    if h2 then
     local dx=sx2-x
     local dd=dy22+dx*dx
     if dd<R22 then
      local lv
      if dd<=ir22 then lv=4
      elseif dd<r122 then lv=3
      elseif dd<r222 then lv=2
      else lv=1 end
      ar+=lr2*lv ag+=lg2*lv ab+=lb2*lv
     end
    end
    if h3 then
     local dx=sx3-x
     local dd=dy23+dx*dx
     if dd<R23 then
      local lv
      if dd<=ir23 then lv=4
      elseif dd<r123 then lv=3
      elseif dd<r223 then lv=2
      else lv=1 end
      ar+=lr3*lv ag+=lg3*lv ab+=lb3*lv
     end
    end
    if h4 then
     local dx=sx4-x
     local dd=dy24+dx*dx
     if dd<R24 then
      local lv
      if dd<=ir24 then lv=4
      elseif dd<r124 then lv=3
      elseif dd<r224 then lv=2
      else lv=1 end
      ar+=lr4*lv ag+=lg4*lv ab+=lb4*lv
     end
    end

    local ri=_mn(4,(ar+0.5)\1)
    local gi=_mn(4,(ag+0.5)\1)
    local bi=_mn(4,(ab+0.5)\1)
    local state=ri*25+gi*5+bi

    if state==0 then
     poke(row1+x,0)
     poke(row2+x,0)
    elseif state~=124 then
     local base=_ta+state*16
     local sv=@(row1+x)
     poke(row1+x,@(base+sv\16)*16+@(base+sv%16))
     sv=@(row2+x)
     poke(row2+x,@(base+sv\16)*16+@(base+sv%16))
    end
   end
  end
 end
end

----------------------------
-- 64x64 row-scan mode
-- original approach
----------------------------
function apply_scan(lights,nl)
 local _sq,_mn,_mx,_ms=sqrt,min,max,memset
 local _fl=flr
 local _ta=tint_addr

 for y=0,63 do
  local row1=0x6000+y*128
  local row2=row1+64

  local any=false
  for li=1,nl do
   local lt=lights[li]
   local dy=lt.sy-y
   lt._dy2=dy*dy
   if lt._dy2<lt.R2 then any=true end
  end

  if not any then
   _ms(row1,0,64)
   _ms(row2,0,64)
  else
   local lb,rb=63,0
   for li=1,nl do
    local lt=lights[li]
    if lt._dy2<lt.R2 then
     local cdx=_sq(lt.R2-lt._dy2)
     local l=_mx(0,_fl(lt.sx-cdx))
     local r=_mn(63,_fl(lt.sx+cdx))
     if l<lb then lb=l end
     if r>rb then rb=r end
    end
   end

   if lb>0 then
    _ms(row1,0,lb)
    _ms(row2,0,lb)
   end
   if rb<63 then
    _ms(row1+rb+1,0,63-rb)
    _ms(row2+rb+1,0,63-rb)
   end

   for x=lb,rb do
    local r,g,b=0,0,0
    for li=1,nl do
     local lt=lights[li]
     if lt._dy2<lt.R2 then
      local dx=lt.sx-x
      local dist2=lt._dy2+dx*dx
      if dist2<lt.R2 then
       local lev
       if dist2<=lt.ir2 then lev=4
       elseif dist2<lt.r12 then lev=3
       elseif dist2<lt.r22 then lev=2
       else lev=1 end
       r+=lt.lr*lev
       g+=lt.lg*lev
       b+=lt.lb*lev
      end
     end
    end

    local ri=_mn(4,_fl(r+0.5))
    local gi=_mn(4,_fl(g+0.5))
    local bi=_mn(4,_fl(b+0.5))
    local state=ri*25+gi*5+bi

    if state==0 then
     poke(row1+x,0)
     poke(row2+x,0)
    elseif state~=124 then
     local base=_ta+state*16
     local sv=@(row1+x)
     poke(row1+x,
      @(base+sv\16)*16+@(base+sv%16))
     sv=@(row2+x)
     poke(row2+x,
      @(base+sv\16)*16+@(base+sv%16))
    end
   end
  end
 end
end

cam_x,cam_y=0,0

__gfx__
00000000dddddddd0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000d666666d0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000d666666d0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000d666666d0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000d666666d0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000d666666d0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000d666666d0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000dddddddd0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000555555550000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000555555550000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000555555550000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000555555550000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000555555550000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000555555550000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000555555550000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000555555550000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__gff__
0001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__map__
0101010101010101010101010101010100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0111111111111111111111111111110100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0111111111111111111111111111110100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0111111111111111111111111111110100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0111111111111111111111111111110100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0111111101010101011111111111110100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0111111111111111111111111111110100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0111111111111111111111111111110100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0111111111111111111101011111110100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0111111111111111111101011111110100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0101010111111111111101011111110100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0111111111111111111101011111110100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0111111111111111111101011111110100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0111111111111111111111111111110100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0111111111111111111111111111110100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0101010101010101010101010101010100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
