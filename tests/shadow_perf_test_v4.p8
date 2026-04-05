pico-8 cartridge // http://www.pico-8.com
version 43
__lua__

-- shadow perf test v4
-- compare lighting methods
-- arrows: move light
-- x: cycle mode, o: toggle shd

modes={"byte","zone","dither","sspr"}
cur_m=4

lights={
  {x=64,y=64,ir=40,fo=30},
  {x=36,y=36,ir=15,fo=20},
}

function _init()
  palt(0,false)
  palt(14,true)
  init_light_tables()
  fset(1,0,true)
  inner_r=40
  falloff=30
  show_shd=true
  -- backup sprite rows for sspr mode
  memcpy(0x4600,0x0000,0x0400)
  -- precompute disc tables (sqrt-free sspr_disc)
  _dtabs={}
  for i=1,#lights do
    local lt=lights[i]
    local s=lt.fo/4
    for _,r in pairs({lt.ir+lt.fo,
      lt.ir+s*3,lt.ir+s*2,lt.ir+s}) do
      if not _dtabs[r] then
        local t={}
        local R2=r*r
        for dy=0,flr(r) do
          t[dy]=sqrt(R2-dy*dy)
        end
        _dtabs[r]=t
      end
    end
  end
  -- benchmark config (multi-light focus)
  bench={
    {nm="lit:dtab  ",fn=4,shd=false,nl=3,dt=1},
    {nm="lit:h2    ",fn=4,shd=false,nl=3,dm=1},
    {nm="lit:h2dup ",fn=4,shd=false,nl=3,dm=2},
    {nm="h2+dda   ",fn=4,shd=true,nl=3,sv=5,dm=1},
    {nm="h2d+dda  ",fn=4,shd=true,nl=3,sv=5,dm=2},
  }
  bi=1 bf=0 bs=0
  bench_on=false
  printh("\n=== perf test v4 ===")
end

function _update()
  if bench_on then return end
  local pl=lights[1]
  if btn(0) then pl.x-=1 end
  if btn(1) then pl.x+=1 end
  if btn(2) then pl.y-=1 end
  if btn(3) then pl.y+=1 end
  if btnp(5) then cur_m=cur_m%#modes+1 end
  if btnp(4) then show_shd=not show_shd end
end

function do_render(fn,shd,nl)
  cls()
  local pl=lights[1]
  cam_x=pl.x-64
  cam_y=pl.y-64
  camera(cam_x,cam_y)
  map(0,0,0,0,16,16)
  local rad=inner_r+falloff
  local slx,sly=pl.x-cam_x,pl.y-cam_y
  if fn==1 then draw_byte(slx,sly,rad)
  elseif fn==2 then draw_zone(slx,sly,rad)
  elseif fn==3 then draw_dither(pl.x,pl.y,rad)
  elseif fn==4 then
    act_nl=nl
    if act_dm==2 then
      local orig=sspr_disc
      _sd_full=sspr_disc_dt
      _dm_dup=true
      sspr_disc=sspr_disc_dt_h2s
      draw_multi()
      sspr_disc=orig
      _sd_full=nil
      _dm_dup=nil
    elseif act_dm then
      local orig=sspr_disc
      _sd_full=sspr_disc_dt
      sspr_disc=sspr_disc_dt_h2
      draw_multi()
      sspr_disc=orig
      _sd_full=nil
    elseif act_dt then
      local orig=sspr_disc
      sspr_disc=sspr_disc_dt
      draw_multi()
      sspr_disc=orig
    else
      draw_multi()
    end
  end
  if shd and fn>0 then
    _lx,_ly,_lr2=slx,sly,rad*rad
    if fn==4 then
      camera()
      memcpy(0x0000,0x6000,0x2000)
      palt(0,false) palt(14,false)
      local dk3={0,0,0,0,0,0,1,1,0,0,1,0,1,1,14,1}
      for c=0,15 do pal(c,dk3[c+1]) end
      -- precompute torch clip data (sorted by x)
      _tch={} _ntch=0
      local _nl=act_nl or #lights
      for li=2,_nl do
        local lt=lights[li]
        local sx,sy=lt.x-cam_x,lt.y-cam_y
        local r=lt.ir+lt.fo
        local dt=_dtabs[r]
        if dt then
          _ntch+=1
          _tch[_ntch]={sx,sy,dt}
        end
      end
      -- sort by x for left-to-right clip
      for i=2,_ntch do
        local t=_tch[i] local j=i-1
        while j>=1 and _tch[j][1]>t[1] do
          _tch[j+1]=_tch[j] j-=1
        end
        _tch[j+1]=t
      end
      local sv=act_sv or 0
      dk_span=_ntch>0 and dk_span_torch
        or (sv==1 and dk_span_tline or dk_span_sspr)
      if sv>=2 then build_clip() end
      if sv==2 then fill_quad=fq_clip
      elseif sv==3 then fill_quad=fq_ci
      elseif sv==4 then fill_quad=fq_ci2
      elseif sv==5 then fill_quad=fq_dda
      end
      shadow_poly_merged(slx,sly,rad)
      fill_quad=fq_base
      dk_span=dk_span_byte
      pal() palt(14,true)
      memcpy(0x0000,0x4600,0x0400)
      camera(cam_x,cam_y)
    else
      shadow_poly_merged(slx,sly,rad)
    end
  end
end

function _draw()
  if bench_on then
    local t=bench[bi]
    act_sv=t.sv or 4
    act_dt=t.dt
    act_dm=t.dm
    do_render(t.fn,t.shd,t.nl)
    bf+=1
    if bf>3 then bs+=stat(1) end
    if bf>=15 then
      local avg=bs/12
      printh(t.nm..": "..avg)
      bi+=1 bf=0 bs=0
      if bi>#bench then
        bench_on=false
        printh("=== done ===\n")
      end
    end
    camera()
    rectfill(0,0,127,9,0)
    print("bench "..bi.."/"..#bench.." "
      ..bench[min(bi,#bench)].nm,1,2,7)
  else
    act_nl=#lights
    act_sv=5
    act_dt=nil
    act_dm=2
    do_render(cur_m,show_shd,act_nl)
    if cur_m==4 then
      for i=1,#lights do
        circfill(lights[i].x,lights[i].y,2,
          i==1 and 7 or 10)
      end
    else
      local pl=lights[1]
      circfill(pl.x,pl.y,2,7)
    end
    camera()
    rectfill(0,0,127,9,0)
    local t=show_shd and "+" or "-"
    local n=cur_m==4 and " x"..act_nl or ""
    print("cpu:"..stat(1).." "
      ..modes[cur_m]..t..n,1,2,7)
  end
end

----------------------------
-- lighting tables
----------------------------
function init_light_tables()
  local dk={
    {0,1,2,3,2,5,13,6,8,9,9,11,12,5,14,6},
    {0,0,1,1,2,1,5,13,2,4,4,3,1,1,14,5},
    {0,0,0,0,0,0,1,1,0,0,1,0,1,1,14,1}
  }
  for t=1,3 do
    local base=0x4200+t*256
    local d=dk[t]
    for i=0,15 do
      for j=0,15 do
        poke(base+bor(shl(i,4),j),
          bor(shl(d[i+1],4),d[j+1]))
      end
    end
  end
end

----------------------------
-- mode 1: per-byte distance
----------------------------
function draw_byte(lx,ly,rad)
  local R2=rad*rad
  local ri=inner_r
  local s=falloff/4
  local r1=ri+s
  local r2=ri+s*2
  local r3=ri+s*3
  local r12,r22,r32=r1*r1,r2*r2,r3*r3
  local t1,t2,t3=0x4300,0x4400,0x4500
  for y=0,127 do
    local row=0x6000+y*64
    local dy=ly-y
    local d2=dy*dy
    if d2>=R2 then
      memset(row,0,64)
    else
      local cdx=sqrt(R2-d2)
      local lb=max(0,(lx-cdx)\2)
      local rb=min(63,(lx+cdx)\2)
      if lb>0 then memset(row,0,lb) end
      if rb<63 then memset(row+rb+1,0,63-rb) end
      local x=lb*2+1
      for i=lb,rb do
        local dx=lx-x
        local dist=d2+dx*dx
        if dist>=R2 then
          poke(row+i,0)
        elseif dist>=r32 then
          poke(row+i,@(t3+@(row+i)))
        elseif dist>=r22 then
          poke(row+i,@(t2+@(row+i)))
        elseif dist>=r12 then
          poke(row+i,@(t1+@(row+i)))
        end
        x+=2
      end
    end
  end
end

----------------------------
-- mode 2: zone boundaries
-- per-scanline sqrt, no
-- per-byte distance math
----------------------------
function draw_zone(lx,ly,rad)
  local R2=rad*rad
  local s=falloff/4
  local r1=inner_r+s
  local r2=inner_r+s*2
  local r3=inner_r+s*3
  local r12,r22,r32=r1*r1,r2*r2,r3*r3
  local t1,t2,t3=0x4300,0x4400,0x4500
  local _sq,_mx,_mn=sqrt,max,min

  for y=0,127 do
    local row=0x6000+y*64
    local dy=ly-y
    local d2=dy*dy
    if d2>=R2 then
      memset(row,0,64)
    else
      local cdx=_sq(R2-d2)
      local bL=_mx(0,(lx-cdx)\2)
      local bR=_mn(63,(lx+cdx)\2)
      if bL>0 then memset(row,0,bL) end
      if bR<63 then memset(row+bR+1,0,63-bR) end

      if d2>=r32 then
        -- entire visible range is shade 3
        for i=bL,bR do poke(row+i,@(t3+@(row+i))) end
      else
        -- peel off shade 3 edges
        cdx=_sq(r32-d2)
        local l=_mx(bL,(lx-cdx)\2)
        local r=_mn(bR,(lx+cdx)\2)
        for i=bL,l-1 do poke(row+i,@(t3+@(row+i))) end
        for i=r+1,bR do poke(row+i,@(t3+@(row+i))) end
        bL,bR=l,r

        if d2>=r22 then
          for i=bL,bR do poke(row+i,@(t2+@(row+i))) end
        else
          cdx=_sq(r22-d2)
          l=_mx(bL,(lx-cdx)\2)
          r=_mn(bR,(lx+cdx)\2)
          for i=bL,l-1 do poke(row+i,@(t2+@(row+i))) end
          for i=r+1,bR do poke(row+i,@(t2+@(row+i))) end
          bL,bR=l,r

          if d2>=r12 then
            for i=bL,bR do poke(row+i,@(t1+@(row+i))) end
          else
            cdx=_sq(r12-d2)
            l=_mx(bL,(lx-cdx)\2)
            r=_mn(bR,(lx+cdx)\2)
            for i=bL,l-1 do poke(row+i,@(t1+@(row+i))) end
            for i=r+1,bR do poke(row+i,@(t1+@(row+i))) end
            -- inner area (l to r): fully lit
          end
        end
      end
    end
  end
end

----------------------------
-- mode 3: dithered circfill
-- uses inverted circfill
-- with ordered bayer dither
----------------------------
-- bayer 4x4 cumulative:
--  25%: 0x5f5f  (4/16 drawn)
--  50%: 0x5a5a  (8/16 drawn)
--  75%: 0x0a0a (12/16 drawn)
function draw_dither(lx,ly,rad)
  local s=falloff/4
  local r1=inner_r+s
  local r2=inner_r+s*2
  local r3=inner_r+s*3

  poke(0x5f34,0x2)

  -- 25% dark outside r1
  fillp(0x5f5f.8)
  circfill(lx,ly,r1,0x1800)

  -- cumulative 50% outside r2
  fillp(0x5a5a.8)
  circfill(lx,ly,r2,0x1800)

  -- cumulative 75% outside r3
  fillp(0x0a0a.8)
  circfill(lx,ly,r3,0x1800)

  -- solid black outside outer rad
  fillp()
  circfill(lx,ly,rad,0x1800)

  poke(0x5f34,0x0)
end

----------------------------
-- mode 4: multi-light sspr
-- saves screen to spritesheet
-- sspr w/pal dark→bright
-- brightest wins via overwrite
----------------------------
function draw_multi()
  local nl=min(act_nl or #lights,#lights)
  local _sq,_mx,_mn=sqrt,max,min

  -- precompute screen-space data
  local ld={}
  for i=1,nl do
    local lt=lights[i]
    local sx,sy=lt.x-cam_x,lt.y-cam_y
    local rad=lt.ir+lt.fo
    local s=lt.fo/4
    ld[i]={sx=sx,sy=sy,rad=rad,
      r1=lt.ir+s,r2=lt.ir+s*2,
      r3=lt.ir+s*3}
  end

  -- save screen to spritesheet
  memcpy(0x0000,0x6000,0x2000)
  -- black out screen
  memset(0x6000,0,0x2000)

  -- work in screen space
  camera()
  palt(0,false)
  palt(14,false)

  -- shade palettes
  local dk3={0,0,0,0,0,0,1,1,0,0,1,0,1,1,14,1}
  local dk2={0,0,1,1,2,1,5,13,2,4,4,3,1,1,14,5}
  local dk1={0,1,2,3,2,5,13,6,8,9,9,11,12,5,14,6}

  -- darkest→brightest: each overwrites
  -- shade 3 at full radius
  for c=0,15 do pal(c,dk3[c+1]) end
  for li=1,nl do
    local d=ld[li]
    sspr_disc(d.sx,d.sy,d.rad,_sq,_mx,_mn)
  end
  -- shade 2 at r3
  for c=0,15 do pal(c,dk2[c+1]) end
  for li=1,nl do
    local d=ld[li]
    sspr_disc(d.sx,d.sy,d.r3,_sq,_mx,_mn)
  end
  -- switch to full-res for inner shades
  if _dm_dup then
    -- row-dup: copy even rows to odd rows
    for y=0,126,2 do
      memcpy(0x6000+(y+1)*64,0x6000+y*64,64)
    end
  end
  if _sd_full then sspr_disc=_sd_full _sd_full=nil end
  -- shade 1 at r2
  for c=0,15 do pal(c,dk1[c+1]) end
  for li=1,nl do
    local d=ld[li]
    sspr_disc(d.sx,d.sy,d.r2,_sq,_mx,_mn)
  end
  -- shade 0 (original) at r1
  pal()
  palt(0,false)
  palt(14,false)
  for li=1,nl do
    local d=ld[li]
    sspr_disc(d.sx,d.sy,d.r1,_sq,_mx,_mn)
  end

  -- restore sprites + state
  memcpy(0x0000,0x4600,0x0400)
  palt(14,true)
  camera(cam_x,cam_y)
end

function sspr_disc(cx,cy,rad,_sq,_mx,_mn)
  local R2=rad*rad
  for y=_mx(0,cy-rad),_mn(127,cy+rad) do
    local dy=cy-y
    local d2=dy*dy
    if d2<R2 then
      local cdx=_sq(R2-d2)
      local x1=_mx(0,cx-cdx)
      local x2=_mn(127,cx+cdx)
      sspr(x1,y,x2-x1+1,1,x1,y)
    end
  end
end

-- sqrt-free disc via precomputed table
function sspr_disc_dt(cx,cy,rad,_,_mx,_mn)
  local dt=_dtabs[rad]
  local ir=flr(rad)
  for y=_mx(0,flr(cy)-ir),_mn(127,flr(cy)+ir) do
    local cdx=dt[flr(abs(cy-y))]
    if cdx then
      local x1=_mx(0,cx-cdx)
      local x2=_mn(127,cx+cdx)
      sspr(x1,y,x2-x1+1,1,x1,y)
    end
  end
end

-- disc table + half-res (height 2)
function sspr_disc_dt_h2(cx,cy,rad,_,_mx,_mn)
  local dt=_dtabs[rad]
  local ir=flr(rad)
  for y=_mx(0,flr(cy)-ir),_mn(127,flr(cy)+ir),2 do
    local cdx=dt[flr(abs(cy-y))]
    if cdx then
      local x1=_mx(0,cx-cdx)
      local x2=_mn(127,cx+cdx)
      sspr(x1,y,x2-x1+1,_mn(2,128-y),x1,y)
    end
  end
end

-- disc table + half-res (skip, row dup)
function sspr_disc_dt_h2s(cx,cy,rad,_,_mx,_mn)
  local dt=_dtabs[rad]
  local ir=flr(rad)
  for y=_mx(0,flr(cy)-ir),_mn(127,flr(cy)+ir),2 do
    local cdx=dt[flr(abs(cy-y))]
    if cdx then
      local x1=_mx(0,cx-cdx)
      local x2=_mn(127,cx+cdx)
      sspr(x1,y,x2-x1+1,1,x1,y)
    end
  end
end

----------------------------
-- shadow darkening
----------------------------
function dk_span_byte(y,x1,x2)
  if x1>x2 then return end
  local row=0x6000+y*64
  for i=x1\2,x2\2 do
    poke(row+i,@(0x4500+@(row+i)))
  end
end

function dk_span_sspr(y,x1,x2)
  if x1>x2 then return end
  sspr(x1,y,x2-x1+1,1,x1,y)
end

-- torch-aware: clip shadow spans
-- around non-player light discs
function dk_span_torch(y,l,r)
  if l>r then return end
  for ti=1,_ntch do
    local t=_tch[ti]
    local dy=flr(abs(t[2]-y))
    local cdx=t[3][dy]
    if cdx then
      local tl=flr(t[1]-cdx)
      local tr=flr(t[1]+cdx)
      if tl<=r and tr>=l then
        if l<tl then
          sspr(l,y,tl-l,1,l,y)
        end
        l=tr+1
        if l>r then return end
      end
    end
  end
  sspr(l,y,r-l+1,1,l,y)
end

function dk_span_tline(y,x1,x2)
  if x1>x2 then return end
  tline(x1,y,x2,y,x1/8,y/8,1/8,0)
end

dk_span=dk_span_byte

function build_clip()
  _cl={}
  for y=0,127 do
    local dy=_ly-y
    local d2=dy*dy
    if d2<_lr2 then
      local cdx=sqrt(_lr2-d2)
      local rl=max(0,_lx-cdx)
      local rr=min(127,_lx+cdx)
      _cl[y]={(flr(rl/2)+1)*2,
        flr((rr+1)/2)*2-1}
    end
  end
end

----------------------------
-- shadow: merged edges
----------------------------
function shadow_poly_merged(lx,ly,rad)
  local px,py=lx+cam_x,ly+cam_y
  local ox,oy=cam_x,cam_y
  local t1,t2=max(0,flr((py-rad)/8)),min(15,flr((py+rad)/8))
  local x1,x2=max(0,flr((px-rad)/8)),min(15,flr((px+rad)/8))
  local _fg,_mg=fget,mget
  local function w(tx,ty)
    return tx>=0 and tx<=15 and ty>=0 and ty<=15 and _fg(_mg(tx,ty),0)
  end

  for ty=t1,t2 do
    local rs=nil
    for tx=x1,x2+1 do
      if tx<=x2 and w(tx,ty) and not w(tx,ty-1) then
        if not rs then rs=tx end
      else
        if rs then opt_edge(lx,ly,rs*8-ox,ty*8-oy,tx*8-ox,ty*8-oy,rad) rs=nil end
      end
    end
  end

  for ty=t1,t2 do
    local rs=nil
    for tx=x1,x2+1 do
      if tx<=x2 and w(tx,ty) and not w(tx,ty+1) then
        if not rs then rs=tx end
      else
        if rs then opt_edge(lx,ly,tx*8-ox,(ty+1)*8-oy,rs*8-ox,(ty+1)*8-oy,rad) rs=nil end
      end
    end
  end

  for tx=x1,x2 do
    local rs=nil
    for ty=t1,t2+1 do
      if ty<=t2 and w(tx,ty) and not w(tx+1,ty) then
        if not rs then rs=ty end
      else
        if rs then opt_edge(lx,ly,(tx+1)*8-ox,rs*8-oy,(tx+1)*8-ox,ty*8-oy,rad) rs=nil end
      end
    end
  end

  for tx=x1,x2 do
    local rs=nil
    for ty=t1,t2+1 do
      if ty<=t2 and w(tx,ty) and not w(tx-1,ty) then
        if not rs then rs=ty end
      else
        if rs then opt_edge(lx,ly,tx*8-ox,ty*8-oy,tx*8-ox,rs*8-oy,rad) rs=nil end
      end
    end
  end
end

function opt_edge(lx,ly,x1,y1,x2,y2,rad)
  local mx,my=(x1+x2)/2,(y1+y2)/2
  local nx,ny=-(y2-y1),(x2-x1)
  if nx*(lx-mx)+ny*(ly-my)<=0 then return end
  local d1x,d1y=x1-lx,y1-ly
  local d2x,d2y=x2-lx,y2-ly
  local len1=max(1,max(abs(d1x),abs(d1y)))
  local len2=max(1,max(abs(d2x),abs(d2y)))
  local ext=rad*2
  fill_quad(x1,y1,x2,y2,
    lx+d2x/len2*ext,ly+d2y/len2*ext,
    lx+d1x/len1*ext,ly+d1y/len1*ext)
end

function fq_base(x1,y1,x2,y2,x3,y3,x4,y4)
  local miny=max(0,flr(min(min(y1,y2),min(y3,y4))))
  local maxy=min(127,flr(max(max(y1,y2),max(y3,y4))))
  local edges={
    {y1,y2,x1,x2},{y2,y3,x2,x3},
    {y3,y4,x3,x4},{y4,y1,x4,x1}
  }
  for y=miny,maxy do
    local dy=_ly-y
    local d2=dy*dy
    local cl,cr=1,0
    if d2<_lr2 then
      local cdx=sqrt(_lr2-d2)
      local rl=max(0,_lx-cdx)
      local rr=min(127,_lx+cdx)
      cl=(flr(rl/2)+1)*2
      cr=flr((rr+1)/2)*2-1
    end
    if cl<=cr then
      local xn,xx=127,0
      for e in all(edges) do
        local ey1,ey2,ex1,ex2=e[1],e[2],e[3],e[4]
        if (y-ey1)*(y-ey2)<=0 and ey1~=ey2 then
          local x=ex1+(ex2-ex1)*(y-ey1)/(ey2-ey1)
          if x<xn then xn=x end
          if x>xx then xx=x end
        end
      end
      if xn<=xx then
        dk_span(y,max(cl,flr(xn)),min(cr,flr(xx)))
      end
    end
  end
end
fill_quad=fq_base

-- clip table (no sqrt per scanline)
function fq_clip(x1,y1,x2,y2,x3,y3,x4,y4)
  local miny=max(0,flr(min(min(y1,y2),min(y3,y4))))
  local maxy=min(127,flr(max(max(y1,y2),max(y3,y4))))
  local edges={
    {y1,y2,x1,x2},{y2,y3,x2,x3},
    {y3,y4,x3,x4},{y4,y1,x4,x1}
  }
  for y=miny,maxy do
    local c=_cl[y]
    if c then
      local xn,xx=127,0
      for e in all(edges) do
        local ey1,ey2,ex1,ex2=e[1],e[2],e[3],e[4]
        if (y-ey1)*(y-ey2)<=0 and ey1~=ey2 then
          local x=ex1+(ex2-ex1)*(y-ey1)/(ey2-ey1)
          if x<xn then xn=x end
          if x>xx then xx=x end
        end
      end
      if xn<=xx then
        dk_span(y,max(c[1],flr(xn)),min(c[2],flr(xx)))
      end
    end
  end
end

-- clip + inline edges + locals
function fq_ci(x1,y1,x2,y2,x3,y3,x4,y4)
  local _fl,_mx,_mn=flr,max,min
  local miny=_mx(0,_fl(_mn(_mn(y1,y2),_mn(y3,y4))))
  local maxy=_mn(127,_fl(_mx(_mx(y1,y2),_mx(y3,y4))))
  for y=miny,maxy do
    local c=_cl[y]
    if c then
      local xn,xx=127,0
      if y1~=y2 and (y-y1)*(y-y2)<=0 then
        local x=x1+(x2-x1)*(y-y1)/(y2-y1)
        if x<xn then xn=x end if x>xx then xx=x end
      end
      if y2~=y3 and (y-y2)*(y-y3)<=0 then
        local x=x2+(x3-x2)*(y-y2)/(y3-y2)
        if x<xn then xn=x end if x>xx then xx=x end
      end
      if y3~=y4 and (y-y3)*(y-y4)<=0 then
        local x=x3+(x4-x3)*(y-y3)/(y4-y3)
        if x<xn then xn=x end if x>xx then xx=x end
      end
      if y4~=y1 and (y-y4)*(y-y1)<=0 then
        local x=x4+(x1-x4)*(y-y4)/(y1-y4)
        if x<xn then xn=x end if x>xx then xx=x end
      end
      if xn<=xx then
        dk_span(y,_mx(c[1],_fl(xn)),_mn(c[2],_fl(xx)))
      end
    end
  end
end

-- clip + inline + half-res
function fq_ci2(x1,y1,x2,y2,x3,y3,x4,y4)
  local _fl,_mx,_mn=flr,max,min
  local miny=_mx(0,_fl(_mn(_mn(y1,y2),_mn(y3,y4))))
  local maxy=_mn(127,_fl(_mx(_mx(y1,y2),_mx(y3,y4))))
  for y=miny,maxy,2 do
    local c=_cl[y]
    if c then
      local xn,xx=127,0
      if y1~=y2 and (y-y1)*(y-y2)<=0 then
        local x=x1+(x2-x1)*(y-y1)/(y2-y1)
        if x<xn then xn=x end if x>xx then xx=x end
      end
      if y2~=y3 and (y-y2)*(y-y3)<=0 then
        local x=x2+(x3-x2)*(y-y2)/(y3-y2)
        if x<xn then xn=x end if x>xx then xx=x end
      end
      if y3~=y4 and (y-y3)*(y-y4)<=0 then
        local x=x3+(x4-x3)*(y-y3)/(y4-y3)
        if x<xn then xn=x end if x>xx then xx=x end
      end
      if y4~=y1 and (y-y4)*(y-y1)<=0 then
        local x=x4+(x1-x4)*(y-y4)/(y1-y4)
        if x<xn then xn=x end if x>xx then xx=x end
      end
      if xn<=xx then
        local l,r=_mx(c[1],_fl(xn)),_mn(c[2],_fl(xx))
        dk_span(y,l,r)
        if y+1<=127 then dk_span(y+1,l,r) end
      end
    end
  end
end

-- clip + dda slopes + half-res
function fq_dda(x1,y1,x2,y2,x3,y3,x4,y4)
  local _fl,_mx,_mn=flr,max,min
  local miny=_mx(0,_fl(_mn(_mn(y1,y2),_mn(y3,y4))))
  local maxy=_mn(127,_fl(_mx(_mx(y1,y2),_mx(y3,y4))))
  -- precompute slopes
  local s1=y1~=y2 and (x2-x1)/(y2-y1) or 0
  local s2=y2~=y3 and (x3-x2)/(y3-y2) or 0
  local s3=y3~=y4 and (x4-x3)/(y4-y3) or 0
  local s4=y4~=y1 and (x1-x4)/(y1-y4) or 0
  -- initial x at miny (extrapolated)
  local ex1=x1+s1*(miny-y1)
  local ex2=x2+s2*(miny-y2)
  local ex3=x3+s3*(miny-y3)
  local ex4=x4+s4*(miny-y4)
  -- step-2 slopes
  local ds1,ds2,ds3,ds4=s1*2,s2*2,s3*2,s4*2
  for y=miny,maxy,2 do
    local c=_cl[y]
    if c then
      local xn,xx=127,0
      if y1~=y2 and (y-y1)*(y-y2)<=0 then
        if ex1<xn then xn=ex1 end
        if ex1>xx then xx=ex1 end
      end
      if y2~=y3 and (y-y2)*(y-y3)<=0 then
        if ex2<xn then xn=ex2 end
        if ex2>xx then xx=ex2 end
      end
      if y3~=y4 and (y-y3)*(y-y4)<=0 then
        if ex3<xn then xn=ex3 end
        if ex3>xx then xx=ex3 end
      end
      if y4~=y1 and (y-y4)*(y-y1)<=0 then
        if ex4<xn then xn=ex4 end
        if ex4>xx then xx=ex4 end
      end
      if xn<=xx then
        local l,r=_mx(c[1],_fl(xn)),_mn(c[2],_fl(xx))
        dk_span(y,l,r)
        if y+1<=127 then dk_span(y+1,l,r) end
      end
    end
    ex1+=ds1 ex2+=ds2
    ex3+=ds3 ex4+=ds4
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
