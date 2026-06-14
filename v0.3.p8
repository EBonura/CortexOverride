pico-8 cartridge // http://www.pico-8.com
version 43
__lua__

-- cortex override v0.3.2
-- single player light, banded falloff

-- state management
current_mission=1
mission_data={{0,0,0},{0,0,0},{0,0,0},{0,0,0}}
credits=800
credits_shown=800

mission_briefings={
  "pROTOCOL zERO\n\naLPHA-7 HAS FALLEN\nTO bARRACUDA.\n\nlOCK IT DOWN,\nSECURE THE DATA,\nEXTRACT.",
  "sILICON wASTELAND\n\niNFECTION HAS\nREACHED THE\nCITY OUTSKIRTS.\n\ncROSS THE WASTES,\nPURGE THE\nSCAVENGERS,\nSECURE THE NODES.",
  "mETROPOLIS sIEGE\n\nbARRACUDA HOLDS\nTHE MAINFRAME.\n\nbREAK THROUGH,\nFREE THE TERMINALS\nSEVER ITS HOLD.",
  "fACILITY 800a\n\ntHE CORE IS ITS\nLAST STRONGHOLD.\n\nbREACH IT, RUN\ncORTEX pROTOCOL,\nPURGE IT ALL."
}

function _init()
  palt(0,false)
  palt(14,true)

  -- blob region @0x1000: [5 x 2-byte lens][4 x 72x72 map][logo]
  local o=0x100a
  map_data={}
  for i=0,4 do
    local l=peek(0x1000+i*2)*256+peek(0x1001+i*2)
    add(map_data,pack(peek(o,l)))
    o+=l
  end
  -- remap map() to extended mem @0x8000, width 72 (72x72 maps)
  poke(0x5f56,0x80) poke(0x5f57,72)
  decompress_to_mem(map_data[5],0x1c00)
  decompress_map()

  _dk1,_dk2,_dk3=
    split"0,1,2,3,2,5,13,6,8,9,9,11,12,5,14,6",
    split"0,0,1,1,2,1,5,13,2,4,4,3,1,1,14,5",
    split"0,0,0,0,0,0,1,1,0,0,1,0,1,1,14,1"
  -- menu darkening palette (v2 intro look:
  -- black bg, white->maroon, blue stays)
  local md=split"0,1,0,0,0,0,0,2,0,0,0,0,0,0,0,0"
  _mdt={}
  for i=0,255 do
    _mdt[i]=bor(shl(md[i\16+1],4),md[i%16+1])
  end

  cam=gamecam.new()

  -- build state table from naming convention
  states={}
  for name in all(split"intro,mission_select,loadout_select,gameplay") do
    states[name]={
      init=_ENV["init_"..name],
      update=_ENV["update_"..name],
      draw=_ENV["draw_"..name]
    }
  end

  change_state("intro",true)
end

function _update()
  if _tr then
    _tr+=_tr_closing and 1 or -1
    if _tr_closing and _tr>=8 then
      _tr_closing=false
      _cur_st=_nxt_st _nxt_st=nil
      _cur_st.init()
    elseif not _tr_closing and _tr<=0 then
      _tr=nil
    end
  else
    _cur_st.update()
  end
end

function _draw()
  _cur_st.draw()
  if _tr then
    local s=max(1,flr(16*_tr/8))
    for x=0,127,s do
      for y=0,127,s do
        rectfill(x,y,x+s-1,y+s-1,pget(x,y))
      end
    end
  end
end

function change_state(name,skip)
  local st=states[name]
  if skip then
    _cur_st=st
    _cur_st.init()
  else
    sfx(20)
    _nxt_st=st
    _tr=0 _tr_closing=true
  end
end

-- helper functions
function dist_trig(dx,dy)
  local ang=atan2(dx,dy)
  return dx*cos(ang)+dy*sin(ang)
end

function check_tile_flag(x,y,f)
  return fget(mget(flr(x/8),flr(y/8)),f or 0)
end

-- color name -> pico color + light rgb
color_map={
  red={8,2},
  green={11,3},
  blue={12,1}
}

-- laser door
laser_door={}
laser_door.__index=laser_door

function laser_door.new(x,y,col)
  local cm=color_map[col]
  local beams={}
  -- the door can be embedded in a wall: skip its solid body down
  -- to the doorway floor, then find the wall below. all 3 beams
  -- share that depth so they fan cleanly (offsets 11,4|9,8|7,12)
  local cx=x+8
  local fy=y+4
  while check_tile_flag(cx,fy) and fy<y+24 do fy+=1 end
  local wy=fy
  while not check_tile_flag(cx,wy) and wy<fy+48 do wy+=1 end
  for i=1,3 do
    add(beams,{x=x+13-i*2,y1=y+i*4,y2=wy-1})
  end
  return setmetatable({
    x=x,y=y,
    is_open=false,
    color=col,
    beam_col=cm[1],
    beams=beams
  },laser_door)
end

function laser_door:update()
  if self.opening then
    self.open_t-=1
    if self.open_t<=0 then
      self.is_open=true
      self.opening=false
    end
  end
end

function laser_door:draw()
  spr(14,self.x,self.y,2,2)
end

-- beams glow above the lighting pass
function laser_door:draw_beams()
  if self.is_open then return end
  if self.opening and flr(t()*8)%2!=0 then return end
  -- stagger bottom ends opposite to the tops for
  -- a fanned perspective (v2)
  for i=1,#self.beams do
    local b=self.beams[i]
    line(b.x,b.y1,b.x,b.y2+(#self.beams-i+1)*2,self.beam_col)
  end
end

-- terminal
terminal={}
terminal.__index=terminal

function terminal.new(x,y,door)
  return setmetatable({
    x=x,y=y,
    door=door,
    color=door and door.color or nil,
    done=false,
    pulse=0
  },terminal)
end

function terminal:update()
  self.pulse=(self.pulse+1)%24
end

function terminal:draw()
  if self.done or (self.door and self.door.is_open) then
    pal(7,5)
  elseif self.color then
    local cm=color_map[self.color]
    local ci=self.pulse<12 and cm[1] or cm[2]
    pal(7,ci)
  end
  spr(23,self.x,self.y)
  spr(39,self.x,self.y+8)
  reset_pal()
end

-- entity lists
terminals={}
doors={}

function create_door_terminal_pair(dx,dy,tx,ty,col)
  local d=laser_door.new(dx,dy,col)
  add(doors,d)
  add(terminals,terminal.new(tx,ty,d))
end

----------------------------
-- player light (banded falloff)
----------------------------
function setpal(t)
  for c=0,15 do pal(c,t[c+1]) end
end

function draw_multi()
  local _sq,_mx,_mn=sqrt,max,min
  local sx,sy=flr(player.x+4-cam_x),flr(player.y+4-cam_y)
  -- effect 2: breathing + subtle flicker
  local fo=light_fo+sin(t()*0.4)*2+sin(t()*1.3)*0.8
  local ir=light_ir
  local s=fo/4
  local r1,r2,r3,rad=ir+s,ir+s*2,ir+s*3,ir+fo

  memcpy(0x0000,0x6000,0x2000)
  camera()
  palt(0,false) palt(14,false)

  -- ambient base: whole scene at darkest shade,
  -- so geometry stays visible outside the light
  -- (effect 3: _dk3 carries a cool cast)
  setpal(_dk3)
  sspr(0,0,128,128,0,0)

  -- brighten inward, each band preceded by a
  -- dithered half-step (effect 1) to fuzz the ring
  setpal(_dk2)
  sspr_disc(sx,sy,(r3+rad)/2,2,_sq,_mx,_mn)
  sspr_disc(sx,sy,r3,1,_sq,_mx,_mn)
  setpal(_dk1)
  sspr_disc(sx,sy,(r2+r3)/2,2,_sq,_mx,_mn)
  sspr_disc(sx,sy,r2,1,_sq,_mx,_mn)
  pal() palt(0,false) palt(14,false)
  sspr_disc(sx,sy,(r1+r2)/2,2,_sq,_mx,_mn)
  sspr_disc(sx,sy,r1,1,_sq,_mx,_mn)

  pal()
  rss()
  palt(14,true)
  camera(cam_x,cam_y)
end

-- st=1 solid, st=2 dithered (even scanlines only,
-- so the shade interleaves with the band beneath)
function sspr_disc(cx,cy,rad,st,_sq,_mx,_mn)
  local R2=rad*rad
  local y0=_mx(0,flr(cy-rad))
  if st==2 and y0%2==1 then y0+=1 end
  for y=y0,_mn(127,cy+rad),st do
    local dy=cy-y
    local d2=dy*dy
    if d2<R2 then
      local cdx=_sq(R2-d2)*_xs
      local x1=_mx(0,cx-cdx)
      local x2=_mn(127,cx+cdx)
      sspr(x1,y,x2-x1+1,1,x1,y)
    end
  end
end

function rss()
  memcpy(0x0000,0x4300,0x1000)
  memcpy(0x1000,0x5300,0x0C00)
end

-- textpanel: menu boxes with reveal + select anim
textpanel={}
textpanel.__index=textpanel

function textpanel.new(x,y,h,w,txt,reveal)
  return setmetatable({
    x=x,y=y,h=h,w=w,
    txt=txt or "",sel=false,
    active=true,reveal=reveal,
    cc=0,exp=0,loff=0,shk=0
  },textpanel)
end

function textpanel:update()
  self.exp=mid(0,self.exp+(self.sel and 1 or -1),3)
  self.loff=self.sel
    and (self.loff+2)%(self.w+self.exp*2+1)
    or 0
  if self.reveal and self.cc<#self.txt then
    self.cc+=2
  end
  if self.shk>0 then self.shk-=1 end
end

function textpanel:draw()
  if not self.active then return end
  local dx=cam.x+self.x-self.exp
  local dy=cam.y+self.y
  if self.shk>0 then dx+=rnd(4)-2 dy+=rnd(4)-2 end
  local w=self.w+self.exp*2
  local dy2=dy+self.h
  rectfill(dx-1,dy-1,dx+2,dy2+1,3)
  rectfill(dx+w-2,dy-1,dx+w+1,dy2+1,3)
  rectfill(dx,dy,dx+w,dy2,0)
  if self.sel then
    local lx=dx+(self.loff%(w+1))
    line(lx,dy,lx,dy2,2)
  end
  local t=self.reveal
    and sub(self.txt,1,self.cc) or self.txt
  ?t,dx+2,dy+2,self.tc or (self.sel and 11 or 5)
end

function display_logo(xc,xp,y)
  spr(224,xp,y+12,9,2)
  spr(233,xc,y,7,2)
end

function reset_pal(_cls)
  pal() palt(0) palt(14,true)
  if _cls then cls() end
end

function menubg(ox,oy)
  reset_pal(true)
  map(4+(ox or 0),37+(oy or 0),0,0,16,16)
  dks()
end

function print_centered(t,x,y,c)
  ?t,x-#t*2,y,c
end

function print_shadow(t,x,y,c)
  ?t,x+1,y+1,0
  ?t,x,y,c or 7
end

function hud_bar(x,y,w,h,bg,fl,p)
  rectfill(x,y,x+w-1,y+h-1,bg)
  if p>0 then rectfill(x,y,x+max(1,flr(w*p))-1,y+h-1,fl) end
  rect(x,y,x+w-1,y+h-1,0)
end

function dks()
  for a=0x6000,0x7fff do
    poke(a,_mdt[@a])
  end
end

-- intro
-- shared parallax starfield (intro + armory)
function init_stars()
  _stars={}
  for i=1,32 do add(_stars,{rnd(128),rnd(128),rnd()}) end
end
function move_stars()
  -- wind: drifts left, vertical tilt sways over time
  local wy=sin(t()/8)*.7
  for s in all(_stars) do
    s[1]=(s[1]-.5)%128 s[2]=(s[2]+wy)%128
  end
end
function draw_stars(r)
  for s in all(_stars) do pset(s[1],s[2],s[3]>.6 and (r and 8 or 7) or (r and 2 or 5)) end
end

-- slam: fast linear in (14f), dead stop at the
-- wall, then a small recoil back off it
function islam(f)
  if f<14 then return f/14 end
  return 1+sin(mid(0,f-14,8)/16)*.1
end

function init_intro()
  music(05)
  _ic,_ip=0,1
  _shake=0
  _itp=textpanel.new(4,50,50,120,"",true)
  _itp.active=false
  init_stars()
  _ipages={
    "tHE GRID RAN EVERYTHING.\ncITIES, MARKETS, MINDS,\nKEPT IN ORDER BY MACHINES\nTHAT NEVER SLEPT.",
    "tHEN bARRACUDA WOKE.\na HOSTILE INTELLIGENCE,\nSPREADING THROUGH THE GRID,\nTURNING IT AGAINST US.\nyOU ARE THE LAST DRONE\nSTILL UNDER OUR COMMAND.",
    "dIRECTIVE:\n- aCTIVATE EVERY TERMINAL\n  TO RUN THE PURGE.\n- rEACH EXTRACTION.\nsECONDARY:\n- rECOVER DATA SHARDS.\n- eLIMINATE ALL HOSTILES.",
    "rESTORE THE SYSTEM,\nOR IT IS LOST.\nbARRACUDA IS WAITING."
  }
end

function update_intro()
  _ic+=1
  -- slam cortex (f0), then override (f14)
  _xc=90*islam(_ic)-75
  _xp=135-90*islam(_ic-16)
  -- both words smash up to the top
  _yl=30-30*max(0,islam((_ic-40)*2))
  if _ic==14 or _ic==30 or _ic==47 then _shake=4 sfx(20) end
  _shake=max(0,_shake-1.2)
  move_stars()
  -- reveal lore after the top-smash settles
  if _ic==59 then
    _itp.active=true
    _itp.txt=_ipages[1]
  end
  -- x or -> pages through lore (locked until reveal)
  if (btnp(5) or btnp(1)) and _itp.active then
    sfx(19)
    _ip+=1
    if _ip<=#_ipages then
      _itp.txt=_ipages[_ip]
      _itp.cc=0
    else
      change_state("mission_select")
    end
  end
  _itp:update()
end

function draw_intro()
  camera(rnd(2*_shake)-_shake,rnd(2*_shake)-_shake)
  menubg(4,6)
  draw_stars()
  if sin(t())<.9 then circfill(63,64,3,2) end
  display_logo(_xc,_xp,_yl)
  _itp:draw()
  if _itp.active then print("NEXT\x91",98,93,11) end
  camera()
end

-- mission select
function armed()
  for w in all(wpns) do if w.owned then return true end end
end

function init_mission_select()
  music(0)
  cam.x,cam.y=0,0
  camera(0,0)
  _minfo=textpanel.new(50,35,74,76,"",true)
  _arm=textpanel.new(4,30,9,38,"ARMORY",true)
  _msel=1
  _mpanels={}
  for i=1,4 do
    add(_mpanels,textpanel.new(4,52+(i-1)*14,9,38,
      "MISSION "..i,true))
  end
  _mshow_brief=false
end

function update_mission_select()
  move_stars()
  local dv=btnp(2) and -1 or btnp(3) and 1
  if dv then _msel=(_msel+dv)%5 _minfo.cc=0 sfx(19) end
  if _msel>=1 then
    current_mission=_msel
    if btnp(1) or btnp(0) then _mshow_brief=btnp(1) _minfo.cc=0 sfx(19) end
  end
  -- missions 3-4 lock until mission 1 or 2 cleared
  _u=mission_data[1][1]+mission_data[2][1]<1
  _lk=_msel>2 and _u
  if btnp(5) then
    if _msel==0 then change_state("loadout_select")
    elseif armed() and not _lk then change_state("gameplay") return
    else sfx(29) _mpanels[_msel].shk=5 end
  end
  if btnp(4) then change_state("intro") end
  _arm.sel=_msel==0
  for i,p in ipairs(_mpanels) do p.sel=i==_msel p.tc=i>2 and _u and 1 p:update() end
  _arm:update()
  _minfo:update()
end

function draw_mission_select()
  menubg()
  draw_stars()
  display_logo(15,45,0)
  _arm:draw()
  for p in all(_mpanels) do p:draw() end
  if _msel==0 then
    _minfo.txt="GEAR UP\n\nAMMO REFILL\nEVERY MISSION"
    _minfo:draw()
  elseif _mshow_brief then
    _minfo.txt=mission_briefings[current_mission]
    _minfo:draw()
  else
    _minfo.txt=""
    _minfo:draw()
    -- color-coded completion status
    local m=mission_data[current_mission]
    ?"STATUS:",52,37,5
    local lb=split"COMPLETED,ALL ENEMIES,ALL FRAGMENTS"
    for i=1,3 do
      local y,c=43+i*6,m[i]*6+5
      ?lb[i],52,y,c
      ?(m[i]==1 and "■" or "□"),116,y,c
    end
  end
  -- view-toggle hint (missions only)
  if _msel>=1 then
    rectfill(94,101,120,108,0)
    ?(_mshow_brief and "\x8bSTATS" or "BRIEF\x91"),96,102,11
  end
  local d,c="\x97 DEPLOY",11
  if _msel==0 then d="\x97 OPEN ARMORY"
  elseif _lk then d,c="COMPLETE M1 OR M2",8
  elseif not armed() then d,c="NO WEAPON-VISIT ARMORY",8 end
  rectfill(18,114,110,123,0)
  print_centered(d,64,117,c)
end

-- loadout select (buy ammo with credits)
function init_loadout_select()
  music(0)
  cam.x,cam.y=0,0
  camera(0,0)
  init_stars()
  _lsel=1
  -- 4 weapons + back-to-missions button
  _lpanels={}
  for i=1,5 do
    add(_lpanels,textpanel.new(14,24+(i-1)*14,10,100,"",true))
  end
end

function update_loadout_select()
  move_stars()
  if btnp(2) then _lsel=(_lsel-2)%5+1 sfx(19) end
  if btnp(3) then _lsel=_lsel%5+1 sfx(19) end
  if btnp(4) then change_state("mission_select") return end
  if btnp(5) then
    if _lsel==5 then change_state("mission_select") return end
    local w=wpns[_lsel]
    if not w.owned and credits>=w.cost then
      w.owned=true credits-=w.cost sfx(19)
    else
      sfx(29) _lpanels[_lsel].shk=5
    end
  end
  for i,p in ipairs(_lpanels) do
    p.sel=(i==_lsel)
    if i<=4 then
      local w=wpns[i]
      local s=wstat(w)
      p.txt=w.name..sub("            ",1,23-#w.name-#s)..s
      p.tc=w.owned and 13 or credits>=w.cost and (p.sel and 11 or 5) or 2
    else
      p.txt="\x8b MISSION SELECT"
      p.tc=p.sel and 11 or 5
    end
    p:update()
  end
end

function draw_loadout_select()
  menubg()
  draw_stars()
  print_centered("ARMORY",64,8,11)
  for p in all(_lpanels) do p:draw() end
  print_centered("CREDITS: "..credits,64,100,11)
  local act="\x97 CONFIRM"
  if _lsel<=4 then
    act=wpns[_lsel].owned and "EQUIPPED" or "\x97 BUY"
  end
  ?"\x94\x83 SELECT  "..act,14,110,11
end

-- gameplay
_xs=1.3 -- light horizontal stretch (1=circle)
light_ir=40
light_fo=18
cam_x,cam_y=0,0
_mg={active=false}
_dirs={"\x8b","\x91","\x94","\x83"}

-- weapons (data-driven)
wpns={
  {name="RIFLE BURST",cd=15,sfx=27,
    n=5,spd=4,fan=0.005,life=30,
    dmg=3,recoil=5.5,sz=1,col=8,
    mag=120,cost=700},
  {name="MACHINE GUN",cd=30,sfx=14,
    n=10,spd=6,spread=0.03,life=20,
    dmg=3,recoil=0.15,sz=1,col=8,
    burst=2,mag=80,cost=700},
  {name="MISSILES",cd=45,sfx=6,
    n=3,spd=0,life=60,
    dmg=15,sz=1,col=8,
    homing=true,orbit=15,aoe=16,aoe_dmg=4,
    mag=36,cost=2400},
  {name="PLASMA CANNON",cd=60,sfx=10,
    n=1,spd=5,life=120,
    dmg=75,recoil=5.5,sz=4,col=12,
    charge=20,aoe=16,aoe_dmg=10,
    mag=18,cost=5000},
}
function wstat(w) return w.owned and "sold" or "$"..w.cost end
bullets={}
parts={}

-- enemy types: col,hp,atk_range,kill,wpn
_et={
  dERVISH={15,50,60,100,2},
  vANGUARD={13,70,50,120,1},
  wARDEN={1,100,70,200,3},
  cYBERSEER={6,160,80,300,{1,3}},
  qUANTUMCLERIC={1,170,70,320,{2,4}}
}
enemies={}
data_fragments={}
barrels={}
_frag_spr=split"50,51,52,53,53,53,53,54,55"
_espawn={
  "480,112,dERVISH|464,280,vANGUARD|408,320,vANGUARD|464,400,dERVISH|384,448,wARDEN|344,200,vANGUARD|264,408,dERVISH|72,144,dERVISH|232,200,dERVISH|64,280,wARDEN|120,280,vANGUARD|280,296,cYBERSEER",
  "64,176,dERVISH|160,192,vANGUARD|224,328,dERVISH|152,80,cYBERSEER|360,168,wARDEN|216,128,dERVISH|456,64,dERVISH|520,128,wARDEN|432,192,vANGUARD|440,344,qUANTUMCLERIC|512,280,vANGUARD|336,408,wARDEN|264,376,vANGUARD|352,352,vANGUARD|144,400,wARDEN",
  "264,432,wARDEN|112,352,dERVISH|184,384,vANGUARD|56,448,wARDEN|240,120,vANGUARD|280,56,dERVISH|320,88,dERVISH|160,96,cYBERSEER|56,104,dERVISH|56,48,dERVISH|80,184,wARDEN|368,360,vANGUARD|480,352,qUANTUMCLERIC|400,424,dERVISH|440,144,vANGUARD|368,152,vANGUARD|448,112,qUANTUMCLERIC|376,256,vANGUARD|456,280,vANGUARD|520,168,wARDEN",
  "392,424,dERVISH|272,424,dERVISH|208,440,vANGUARD|112,376,wARDEN|64,416,wARDEN|104,272,vANGUARD|40,296,cYBERSEER|64,192,vANGUARD|48,112,vANGUARD|200,312,dERVISH|200,376,dERVISH|272,320,wARDEN|424,360,qUANTUMCLERIC|360,360,dERVISH|224,208,wARDEN|288,216,wARDEN|400,208,wARDEN|496,200,cYBERSEER|504,272,vANGUARD|152,48,vANGUARD|128,120,vANGUARD|48,48,dERVISH|192,112,dERVISH|216,48,dERVISH|248,120,dERVISH|408,56,qUANTUMCLERIC|480,112,cYBERSEER"
}
_doors_m={
  "480,176,504,128,red|384,112,280,416,green",
  "360,288,488,88,red|344,288,248,80,green|376,288,104,416,blue",
  "416,296,168,240,red|208,16,184,408,green|384,184,344,424,blue",
  "168,16,416,296,red|136,16,64,320,green|200,16,496,288,blue"
}
_pspawn={"160,80","96,320","280,272","488,416"}

function spawn_enemy(x,y,typ)
  local d=_et[typ]
  local e=entity.new(x,y)
  e.name=typ
  e.col,e.hp,e.mhp,e.atk,e.kv,e.wpi=d[1],d[2],d[2],d[3],d[4],d[5]
  e.ecd,e.ait,e.alt,e.flash,e.max_speed=0,0,0,0,2
  add(enemies,e)
end

function init_gameplay()
  decompress_map()
  music(0)
  init_stars()

  -- backup full sprite sheet + map data
  memcpy(0x4300,0x0000,0x1000)
  memcpy(0x5300,0x1000,0x0C00)

  -- reset state
  terminals={} doors={}
  enemies={} bullets={} parts={}
  data_fragments={} barrels={}
  _wsel=1 _wcd={0,0,0,0}
  _wmenu=false _dead=false _won=false
  _evac=1000 player=nil credits_shown=credits _ptox=0
  -- refill owned weapons; select lowest owned
  for i=1,4 do
    wpns[i].ammo=wpns[i].owned and wpns[i].mag or 0
  end
  for i=4,1,-1 do if wpns[i].owned then _wsel=i end end

  -- enemies for this mission
  for s in all(split(_espawn[current_mission],"|",false)) do
    local d=split(s)
    spawn_enemy(d[1]+0,d[2]+0,d[3])
  end

  -- scan map region: barrels(6) fragments(5)
  -- standalone terminals(4)
  for ty=0,71 do
    for tx=0,71 do
      local tile=mget(tx,ty)
      local px,py=tx*8,ty*8
      if fget(tile,6) then
        add(barrels,barrel.new(px,py))
      elseif fget(tile,5) then
        add(data_fragments,data_fragment.new(px,py))
      elseif fget(tile,4) then
        add(terminals,terminal.new(px+4,py-4))
      end
    end
  end

  -- door+terminal pairs for this mission
  for s in all(split(_doors_m[current_mission],"|",false)) do
    local d=split(s)
    create_door_terminal_pair(d[1],d[2],d[3],d[4],d[5])
  end

  -- player start (from _pspawn marker)
  spawn_player(unpack(split(_pspawn[current_mission])))
end

function spawn_player(px,py)
  player_spawn_x,player_spawn_y=px,py
  player=entity.new(px,py)
  player.hp=400 player.mhp=400 player.flash=0
  cam.x,cam.y=px-64,py-64
end

function update_gameplay()
  -- player death
  if _dead then
    _dead_t-=1
    if _dead_t<=0 then change_state("mission_select") end
    update_parts()
    return
  end
  if _mg.active then
    mg_update()
    return
  end
  -- weapon menu (hold O): pauses the game
  if btn(4) then
    if not _wmenu then wmenu_open() end
    _wmenu=true
    if btnp(2) then _wsel=(_wsel-2)%4+1 sfx(19) end
    if btnp(3) then _wsel=_wsel%4+1 sfx(19) end
    wmenu_update()
    return
  end
  _wmenu=false
  player:update()
  _tmoved=_tmoved or btn()&15>0
  move_stars()
  if player.flash>0 then player.flash-=1 end
  -- toxic pools (flag 2) hurt over time
  if check_tile_flag(player.x+4,player.y+4,2) then
    _ptox+=1
    if _ptox%6<1 then damage(player,1) end
  else _ptox=0 end
  update_target()
  cam:update()
  for t in all(terminals) do t:update() end
  for d in all(doors) do d:update() end
  for b in all(barrels) do b:update() end

  -- fragment pickup
  for f in all(data_fragments) do
    if not f.got and dist_trig(f.x-player.x,f.y-player.y)<8 then
      player.hp=min(player.hp+25,player.mhp)
      credits+=50 f.got=true _tfrag=_tfrag or 90 sfx(7) pop(f.x,f.y,50)
    end
  end

  -- smooth credit counter
  credits_shown+=ceil((credits-credits_shown)*.3)

  -- weapon cooldowns
  for i=1,4 do _wcd[i]=max(0,_wcd[i]-1) end

  -- burst fire (machine gun)
  if player._burst then
    local b=player._burst
    b.t-=1
    if b.t%b.rate==0 then shoot(b.w,{get_aim()}) end
    if b.t<=0 then player._burst=nil end
  end

  -- plasma charge
  if player._charge then
    player._charge.t-=1
    if player._charge.t<=0 then
      shoot(player._charge.w,player._charge.aim)
      player._charge=nil
    end
  end

  -- X button: interact or fire
  if btnp(5) and not _wmenu then
    local t=near_terminal()
    if t then mg_start(t) else fire_weapon(_wsel) end
  end

  -- update bullets, particles, enemies
  update_bullets()
  update_parts()
  update_enemies()

  -- mission cleared -> extraction
  if n_terminals()==0 and not _dead then
    if _evac==1000 then music(7) end
    _evac-=1
    if not _won and dist_trig(player.x-player_spawn_x,player.y-player_spawn_y)<=32 then
      _won=true
      mission_data[current_mission][1]=1
      if #enemies==0 then mission_data[current_mission][2]=1 end
      if n_fragments()==0 then mission_data[current_mission][3]=1 end
    end
    if _won and btnp(5) then change_state("mission_select") return end
    if _evac<=0 then die(player) end
  end
end

-- a terminal can be hacked if not done and its
-- door (if any) is still shut
function hackable(t)
  return not t.done
    and (not t.door or
      (not t.door.is_open and not t.door.opening))
end

function near_terminal()
  if _foe then return end
  for t in all(terminals) do
    if hackable(t) and abs(t.x-player.x)<16 and abs(t.y-player.y)<16 then return t end
  end
end

function draw_gameplay()
  cls()
  cam_x,cam_y=cam.x,cam.y
  palt(0,false)
  palt(14,true)
  camera(cam_x,cam_y)
  map(0,0,0,0,72,72)

  -- draw doors, terminals, fragments
  for d in all(doors) do d:draw() end
  for t in all(terminals) do t:draw() end
  for f in all(data_fragments) do f:draw() end

  if not _dead then player:draw() end
  for e in all(enemies) do e:draw() end
  for b in all(barrels) do b:draw() end

  -- plasma charge visual
  if player._charge then
    local ct=player._charge.t
    local cw=player._charge.w
    local r=32*(ct/cw.charge)
    circ(player.x+4,player.y+4,r,12)
  end

  -- bullets + particles (drawn before lighting)
  draw_bullets()
  draw_parts()

  -- lighting pass (single player light)
  local px,py=player.x+4,player.y+4
  draw_multi()

  -- laser beams glow over the darkness
  for d in all(doors) do d:draw_beams() end

  -- credit popups, bright over the lighting
  for p in all(parts) do
    if p.txt then print_shadow(p.txt,p.x,p.y,p.col) end
  end

  -- extraction indicator (points to spawn)
  local cl=n_terminals()==0 and not _dead
  if cl and not _won then
    local a=atan2(player_spawn_x-player.x,player_spawn_y-player.y)
    circfill(px+cos(a)*20,py+sin(a)*20,1,8)
  end

  -- targeting reticle: rotating red square, snaps in on lock (v2)
  if _ptarget and not _dead and not _mg.active then
    local x,y,hs=_ptarget.x+4,_ptarget.y+4,6+max(0,18-_lt)
    for i=0,3 do
      local a=t()*.4+i*.25
      line(x+cos(a)*hs,y+sin(a)*hs,x+cos(a+.25)*hs,y+sin(a+.25)*hs,8)
    end
  end

  -- interaction prompt (hidden during minigame)
  if not _mg.active then
    local t=near_terminal()
    if t then
      local cx=t.x+4
      local iy=t.y-8
      ovalfill(cx-6,iy-1,cx+6,iy+8,0)
      ?"\151",cx-3,iy+1,11
    end
  end

  camera()
  draw_stars(cl)
  draw_hud()
  draw_weapon_menu()
  mg_draw()

  -- extraction ui (panel, lower on screen)
  if cl then
    rectfill(28,82,100,104,0)
    if _won then
      print_centered("extraction ready",64,88,11)
      print_centered("\x97 to evacuate",64,96,7)
    else
      print_centered("system purged",64,84,11)
      print_centered("return to spawn",64,91,7)
      print_centered("evac: "..flr(_evac/30),64,98,8)
    end
  end

  -- contextual tutorial hints
  if not _mg.active and not _dead then draw_tut() end
end

-- contextual hints: show the first unmet one, until learned.
-- flags are global so each shows once across the playthrough.
function draw_tut()
  local h,n=nil,0
  for w in all(wpns) do n+=w.owned and 1 or 0 end
  if not _tmoved then h="MOVE: \x8b\x91\x94\x83"
  elseif not _tfired then h="ATTACK: \x97"
  elseif n>1 and not _tmenu then h="WEAPONS MENU: \x8e"
  elseif _tfrag and _tfrag>0 then h="FRAGMENTS RESTORE HP" _tfrag-=1
  end
  if h then
    local w=print(h,0,-99)
    rectfill(62-w/2,114,66+w/2,123,0)
    print(h,64-w/2,117,11)
  end
end

-- minigame (simon says hacking)
function mg_start(term)
  local seq={}
  for i=1,5 do seq[i]=_dirs[flr(rnd(4))+1] end
  _mg={active=true,seq=seq,inp={},
    timer=180,term=term}
end

function mg_update()
  _mg.timer-=1
  if _mg.timer<=0 then
    mg_end(false)
    return
  end
  for i=0,3 do
    if btnp(i) then
      add(_mg.inp,_dirs[i+1])
      _mg.fr=2 _mg.fc=_dirs[i+1]==_mg.seq[#_mg.inp] and 11 or 8
      if #_mg.inp==#_mg.seq then mg_check() end
      return
    end
  end
end

function mg_check()
  for i=1,#_mg.seq do
    if _mg.seq[i]!=_mg.inp[i] then
      mg_end(false)
      return
    end
  end
  mg_end(true)
end

function mg_end(win)
  local t=_mg.term
  _mg={active=false}
  _mgf=45
  if win then
    sfx(15)
    t.done=true
    if t.door then
      t.door.opening=true
      t.door.open_t=20
      _mgmsg,_mgc=t.door.color.." laser down",color_map[t.door.color][1]
    else
      _mgmsg,_mgc="terminal cleared",11
    end
  else
    sfx(29)
    _mgmsg,_mgc="access denied",8
  end
end

function mg_draw()
  if not _mg.active then return end
  local cx,cy=64,64
  rectfill(cx-35,cy-13,cx+35,cy+13,0)
  rect(cx-35,cy-13,cx+35,cy+13,3)
  local sw=#_mg.seq*12-4
  local sx=cx-sw/2
  local cur=#_mg.inp+1
  -- single row: done(green/red), current(bob), upcoming(dim)
  for i,d in ipairs(_mg.seq) do
    local c,yo=5,0
    if i<cur then c=_mg.inp[i]==d and 11 or 8
    elseif i==cur then c=7 yo=sin(t()*2)*2 end
    ?d,sx+(i-1)*12,cy-6+yo,c
  end
  -- time bar (green->yellow->red)
  local tr=_mg.timer/180
  rectfill(cx-30,cy+6,cx-30+60*tr,cy+9,tr>.5 and 11 or tr>.25 and 10 or 8)
  -- press feedback: ring on the pressed arrow's slot
  if _mg.fr and _mg.fr<10 then
    circ(sx+(#_mg.inp-1)*12+3,cy-3,_mg.fr,_mg.fc)
    _mg.fr+=2
  end
end

-- weapons: aim + fire
-- auto-aim: nearest enemy in range with sight
function update_target()
  local old=_ptarget
  _ptarget=nil
  local bd=60
  for e in all(enemies) do
    local d=dist_trig(e.x-player.x,e.y-player.y)
    if d<bd and los(player,e) then
      bd=d _ptarget=e
    end
  end
  -- reset snap-in timer whenever the locked target changes
  _lt=_ptarget==old and (_lt or 0)+1 or 0
end

function get_aim()
  if _ptarget then
    local dx,dy=_ptarget.x-player.x,_ptarget.y-player.y
    local d=dist_trig(dx,dy)
    if d>0 then return dx/d,dy/d end
  end
  local vx,vy=player.vx,player.vy
  local spd=dist_trig(vx,vy)
  if spd>0 then return vx/spd,vy/spd end
  local d=player.last_dir
  if d=="horizontal" then
    return player.face_x,0
  elseif d=="up" then return 0,-1
  else return 0,1 end
end

-- spawn a volley of orbiting homing missiles
function spawn_missiles(w,src,plr)
  local px,py=src.x+4,src.y+4
  for i=1,w.n do
    -- release like drones in a spread, then home in
    local a=rnd()
    add(bullets,{x=px,y=py,vx=cos(a)*2,vy=sin(a)*2,
      life=w.life,sz=w.sz,col=w.col,
      dmg=w.dmg,aoe=w.aoe,aoe_dmg=w.aoe_dmg,
      homing=true,plr=plr})
  end
end

function fire_weapon(wi)
  if _wcd[wi]>0 then return end
  local w=wpns[wi]
  if w.ammo<=0 then
    -- out of ammo: switch to one that has some
    for i=1,4 do
      if wpns[i].ammo>0 then
        _wsel=i fire_weapon(i) return
      end
    end
    sfx(29) return
  end
  w.ammo-=1 _tfired=true
  local ax,ay=get_aim()
  _wcd[wi]=w.cd

  if w.burst then
    -- machine gun: first shot + burst for rest
    player._burst={w=w,
      t=(w.n-1)*w.burst,rate=w.burst}
    shoot(w,{ax,ay})
  elseif w.charge then
    -- plasma: start charge
    player._charge={w=w,aim={ax,ay},
      t=w.charge}
  elseif w.homing then
    spawn_missiles(w,player,true)
    sfx(w.sfx)
  else
    -- rifle: instant fan
    firefan(w,{ax,ay},w.n)
    if w.recoil then recoil(ax,ay,w) end
    sfx(w.sfx)
  end
end

function recoil(dx,dy,w)
  player.vx-=dx*w.recoil
  player.vy-=dy*w.recoil
end
function shoot(w,aim)
  fire_single(w,aim)
  recoil(aim[1],aim[2],w)
  sfx(w.sfx)
end
function firefan(w,aim,n,src)
  for i=1,n do
    fire_single(w,aim,(i-1-(n-1)/2)*(w.fan or 0),src)
  end
end

function fire_single(w,aim,ang_off,src)
  local ax,ay=aim[1],aim[2]
  local a=atan2(ax,ay)+(ang_off or 0)
    +(w.spread and (rnd()-0.5)*w.spread or 0)
  src=src or player
  local px,py=src.x+4,src.y+4
  add(bullets,{x=px+cos(a)*5,y=py+sin(a)*5,
    vx=cos(a)*w.spd,vy=sin(a)*w.spd,
    life=w.life,sz=w.sz,col=w.col,
    dmg=w.dmg,aoe=w.aoe,aoe_dmg=w.aoe_dmg,
    plr=src==player})
end

-- enemy AI
function los(a,b)
  local x,y=a.x+4,a.y+4
  local dx,dy=b.x+4-x,b.y+4-y
  local s=max(abs(dx),abs(dy))
  if s<1 then return true end
  for i=4,s,4 do
    if check_tile_flag(x+dx*i/s,y+dy*i/s) then return false end
  end
  return true
end

function enemy_fire(e,wi)
  local w=wpns[wi]
  local dx,dy=player.x-e.x,player.y-e.y
  local d=dist_trig(dx,dy)
  if d<1 then return end
  if w.homing then
    spawn_missiles(w,e,false)
  else
    firefan(w,{dx/d,dy/d},min(w.n,3),e)
  end
  sfx(w.sfx)
end

function update_enemies()
  _foe=false
  for e in all(enemies) do
    local dx,dy=player.x-e.x,player.y-e.y
    local d=dist_trig(dx,dy)
    _foe=_foe or d<48
    e.ecd=max(0,e.ecd-1)
    e.alt=max(0,e.alt-1)
    local see=d<=e.atk and los(e,player)
    if see then
      e.lsx,e.lsy,e.alt,e.ai=player.x,player.y,180,"atk"
      -- approach when far, circle-strafe when in range
      local nx,ny=dx/d,dy/d
      if d<e.atk*.6 then e.vx,e.vy=-ny,nx
      else e.vx,e.vy=nx,ny end
      if e.ecd<=0 then
        local wi=type(e.wpi)=="table"
          and e.wpi[flr(rnd(#e.wpi))+1] or e.wpi
        enemy_fire(e,wi)
        e.ecd=wpns[wi].cd*3
      end
    elseif e.lsx then
      -- chase to last seen position
      e.ai="chase"
      local tx,ty=e.lsx-e.x,e.lsy-e.y
      local td=dist_trig(tx,ty)
      if td>2 then e.vx,e.vy=tx/td,ty/td end
    else
      -- idle wander
      e.ai="idle"
      e.ait-=1
      if e.ait<=0 then e.ait=30 local a=rnd() e.vx,e.vy=cos(a),sin(a) end
    end
    if e.alt<=0 then e.lsx=nil end
    set_dir(e)
    e.vx*=.9 e.vy*=.9
    e:apply_physics()
    if e.flash>0 then e.flash-=1 end
  end
end

-- bullet system
function update_bullets()
  for i=#bullets,1,-1 do
    local b=bullets[i]
    b.life-=1
    local dead=false

    -- homing missiles steer toward their target
    if b.homing then
      local tg=b.plr and _ptarget or not b.plr and player
      if tg then
        local tx,ty=tg.x-b.x,tg.y-b.y
        local td=dist_trig(tx,ty)+1
        b.vx+=(tx/td*2-b.vx)*.08
        b.vy+=(ty/td*2-b.vy)*.08
      end
    end
    b.x+=b.vx
    b.y+=b.vy
    -- entity collision (dead still false here)
    if b.plr then
      for e in all(enemies) do
        if bhit(b,e) then
          hurt(e,b) dead=true break
        end
      end
    elseif b.plr==false then
      if bhit(b,player) then
        hurt(player,b) dead=true
      end
    end
    -- barrel collision
    if not dead then
      for bar in all(barrels) do
        if not bar.exp and bhit(b,bar) then
          bar:take_damage(b.dmg) bullet_hit(b) dead=true break
        end
      end
    end
    -- tile collision
    if not dead and check_tile_flag(b.x,b.y) then
      bullet_hit(b) dead=true
    end

    if not dead and b.life<=0 then
      if b.aoe then bullet_explode(b) end
      dead=true
    end
    if dead then deli(bullets,i) end
  end
end

function bullet_hit(b)
  if b.aoe then
    bullet_explode(b)
  else
    spawn_impact(b.x,b.y)
  end
end

function bhit(b,o)
  return abs(b.x-o.x-4)<5 and abs(b.y-o.y-4)<5
end

-- radial particle burst (shared by impacts,
-- explosions, deaths, barrels)
function burst(x,y,n,c)
  for i=1,n do
    local a,s=rnd(),.5+rnd(1.5)
    add(parts,{x=x,y=y,vx=cos(a)*s,vy=sin(a)*s,
      life=20+rnd(10),sz=1+flr(rnd(2)),col=c})
  end
end

function bullet_explode(b)
  burst(b.x,b.y,10,9)
  sfx(28)
end

function spawn_impact(x,y)
  burst(x,y,2,6)
end

-- objectives
function ncount(l,k)
  local c=0
  for o in all(l) do if not o[k] then c+=1 end end
  return c
end
function n_terminals() return ncount(terminals,"done") end
function n_fragments() return ncount(data_fragments,"got") end

-- data fragments
data_fragment={} data_fragment.__index=data_fragment
function data_fragment.new(x,y)
  return setmetatable({x=x,y=y,got=false},data_fragment)
end
function data_fragment:draw()
  if not self.got then
    spr(_frag_spr[flr(t()/.15)%#_frag_spr+1],self.x,self.y-4)
  end
end

-- exploding barrels
barrel={} barrel.__index=barrel
function barrel.new(x,y)
  return setmetatable({x=x,y=y,
    poison=rnd()>.5,hp=1,exp=false,et=0},barrel)
end
function barrel:take_damage(a) self.hp=max(0,self.hp-a) end
function barrel:draw()
  if not self.exp then spr(self.poison and 5 or 6,self.x,self.y-8) end
end
function barrel:update()
  if self.hp<=0 and not self.exp then self.exp=true self.et=0 end
  if n_terminals()==0
    and dist_trig(player.x-self.x,player.y-self.y)<50
    and rnd()<.01 then self.hp=0 end
  if self.exp then
    self.et+=1
    if self.et==1 then
      burst(self.x+4,self.y+4,20,self.poison and 3 or 8)
      for e in all(enemies) do barrel_dmg(self,e) end
      barrel_dmg(self,player)
      sfx(28)
    end
    mset(flr(self.x/8),flr(self.y/8),self.poison and 10 or 26)
    if self.et>=15 then del(barrels,self) end
  end
end
function barrel_dmg(b,e)
  local nd=dist_trig((e.x+4-b.x-4)/64,(e.y+4-b.y-4)/32)
  if nd<.5 then damage(e,20*(1-nd*2)*(b.poison and 1.5 or 1)) end
end

-- damage + death
function damage(e,amt)
  e.hp-=amt
  e.flash=2
  if e.hp<=0 then die(e) end
end
function die(e)
  burst(e.x+4,e.y+4,e.kv and 15 or 20,9)
  sfx(30)
  if e.kv then
    credits+=e.kv
    pop(e.x+4,e.y,e.kv)
    del(enemies,e)
  else
    _dead=true _dead_t=60
  end
end
function hurt(e,b)
  bullet_hit(b)
  damage(e,b.dmg)
end

-- particles (visual only)
function update_parts()
  for i=#parts,1,-1 do
    local p=parts[i]
    p.x+=p.vx p.y+=p.vy
    p.life-=1
    if p.life<=0 then deli(parts,i) end
  end
end

function draw_bullets()
  for b in all(bullets) do
    circfill(b.x,b.y,b.sz,b.col)
  end
end

-- floating credit popup (rides the parts list)
function pop(x,y,n)
  add(parts,{x=x,y=y,vx=0,vy=-.7,life=40,col=11,txt="+"..n})
end

function draw_parts()
  for p in all(parts) do
    if not p.txt then circfill(p.x,p.y,p.sz,p.col) end
  end
end

-- weapon menu + hud
-- weapon menu: bordered panels per weapon +
-- an objectives info panel (matches v2)
function wmenu_open()
  _tmenu=true
  _wpanels={}
  for i=1,4 do
    local p=textpanel.new(37,30+(i-1)*16,10,54,wpns[i].name)
    p.wi=i
    add(_wpanels,p)
  end
  _winfo=textpanel.new(13,94,20,102,"")
  add(_wpanels,_winfo)
end

function wmenu_update()
  for p in all(_wpanels) do
    if p.wi then
      p.sel=(p.wi==_wsel)
      p.tc=wpns[p.wi].ammo>0 and (p.sel and 11 or 5) or 2
    end
    p:update()
  end
  _winfo.txt=
    "DATA SHARDS LEFT: "..n_fragments().."\n"..
    "HOSTILE UNITS:    "..#enemies.."\n"..
    "TERMINALS LEFT:   "..n_terminals()
end

function draw_weapon_menu()
  if not _wmenu then return end
  camera(cam.x,cam.y)
  for p in all(_wpanels) do p:draw() end
  camera()
end

function draw_hud()
  local w=wpns[_wsel]
  local sx,sy=2,2
  if player.flash>0 then sx+=rnd(2)-1 sy+=rnd(2)-1 end
  -- health bar (white bg, colored fill)
  local hp=player.hp/player.mhp
  local hc=hp>.6 and 11 or hp>.3 and 10 or 8
  hud_bar(sx,sy,66,5,7,hc,hp)
  -- cooldown bar (blue), below health
  local cy=sy+5
  hud_bar(sx,cy,66,3,1,12,1-_wcd[_wsel]/w.cd)
  -- weapon name + ammo, below bars
  local ac=w.ammo>0 and 7 or flr(t()*4)%2*5+2
  print_shadow(w.name.." ▶"..w.ammo.."◀",sx,cy+5,ac)
  -- credits (small font)
  print_shadow("CREDITS: "..credits_shown,sx,cy+12)
  -- charge indicator
  if player._charge then
    print_shadow("charging",sx+54,sy,flr(t()*8)%2*-5+12)
  end
  -- enemy alert bars + name (lower-left, v2 style)
  local ay=123
  for e in all(enemies) do
    if e.ai=="atk" or e.ai=="chase" then
      local bw=flr(e.mhp*.4)
      hud_bar(2,ay,bw,4,7,8,e.hp/e.mhp)
      print_shadow(e.name,bw+4,ay)
      ay-=6
    end
  end
  -- hack result flash (panel, lower on screen)
  if _mgf and _mgf>0 then
    _mgf-=1
    rectfill(28,97,100,108,0)
    print_centered(_mgmsg,64,100,_mgc)
  end
end

-- entity
entity={}
entity.__index=entity

function entity.new(x,y)
  return setmetatable({
    x=x,
    y=y,
    vx=0,
    vy=0,
    col_x=0,
    col_y=1,
    col_w=8,
    col_h=7,
    target_x=x,
    target_y=y,
    max_speed=4,
    acceleration=0.8,
    deceleration=0.9,
    last_dir="down",
    face_x=1
  },entity)
end

function entity:update()
  self:control()
  self:follow_target()
  self:apply_physics()
end

function entity:control()
  local ix=btn()\2%2-btn()%2
  local iy=btn()\8%2-btn()\4%2

  if ix==0 and iy==0 then
    self.target_x+=(self.x-self.target_x)*0.3
    self.target_y+=(self.y-self.target_y)*0.3
    return
  end

  self.target_x+=ix*6
  self.target_y+=iy*6

  local dx,dy=self.target_x-self.x,self.target_y-self.y

  if dist_trig(dx,dy)>32 then
    local angle=atan2(dx,dy)
    self.target_x=self.x+cos(angle)*32
    self.target_y=self.y+sin(angle)*32
  end
end

function set_dir(o)
  if abs(o.vx)>abs(o.vy) then
    o.last_dir="horizontal"
    o.face_x=o.vx>0 and 1 or -1
  else
    o.last_dir=o.vy<0 and "up" or "down"
  end
end

function entity:follow_target()
  local dx,dy=self.target_x-self.x,self.target_y-self.y
  local dist=dist_trig(dx,dy)

  if dist>1 then
    self.vx=self:approach(self.vx,dx*0.1,self.acceleration)
    self.vy=self:approach(self.vy,dy*0.1,self.acceleration)

    set_dir(self)
  else
    self.vx=self:approach(self.vx,0,self.deceleration)
    self.vy=self:approach(self.vy,0,self.deceleration)
  end

  -- limit speed
  local speed=dist_trig(self.vx,self.vy)
  if speed>self.max_speed then
    self.vx=(self.vx/speed)*self.max_speed
    self.vy=(self.vy/speed)*self.max_speed
  end
end

function entity:approach(current,target,step)
  if current<target then
    return min(current+step,target)
  elseif current>target then
    return max(current-step,target)
  end
  return current
end

function entity:check_tile_collision(x,y)
  local cx1,cy1=x+self.col_x,y+self.col_y
  local cx2,cy2=cx1+self.col_w-1,cy1+self.col_h-1

  local tx1,ty1=flr(cx1/8),flr(cy1/8)
  local tx2,ty2=flr(cx2/8),flr(cy2/8)

  for tx=tx1,tx2 do
    for ty=ty1,ty2 do
      if fget(mget(tx,ty),0) then
        return true
      end
    end
  end
  -- laser beam collision
  for d in all(doors) do
    if not d.is_open and not d.opening then
      for b in all(d.beams) do
        if b.x>=cx1 and b.x<=cx2
          and b.y2>=cy1 and b.y1<=cy2 then
          return true
        end
      end
    end
  end
  return false
end

function entity:apply_physics()
  local nx,ny=self.x+self.vx,self.y+self.vy

  if self:check_tile_collision(nx,ny) then
    if not self:check_tile_collision(nx,self.y) then
      ny=self.y
    elseif not self:check_tile_collision(self.x,ny) then
      nx=self.x
    else
      nx,ny=self.x,self.y
    end
  end

  self.vx=abs(self.vx)<0.01 and 0 or self.vx
  self.vy=abs(self.vy)<0.01 and 0 or self.vy
  self.x,self.y=nx,ny
end

function entity:draw()
  if self.flash and self.flash>0 then
    for i=0,15 do pal(i,7) end
  elseif self.col then
    pal(7,self.col)
  end
  if type(self.wpi)=="table" then
    -- big "preacher": 2x3 sprite, blinking red eye
    pal(0,t()\.5%2*8)
    spr(8,self.x-4,self.y-16,2,3,self.vx<0)
  else
    spr(49,self.x,self.y+1) -- shadow
    local spd=dist_trig(self.vx,self.vy)
    local moving=spd>0.2
    local s=(self.last_dir=="up" and 32 or self.last_dir=="horizontal" and 0 or 16)+(moving and 2 or 0)
    s+=flr(t()*(moving and 10+min(spd/self.max_speed,1)*10 or 3))%2
    spr(s,self.x,self.y,1,1,self.vx<0)
  end
  reset_pal()
  -- alert/attack icon above enemy (v2 style)
  local ind=self.ai=="chase" and 36 or self.ai=="atk" and 20
  if ind then spr(ind,self.x+4,self.y-8) end
end

-- camera
gamecam={}
gamecam.__index=gamecam

function gamecam.new()
  return setmetatable({
    x=0,
    y=0
  },gamecam)
end

function gamecam:update()
  self.x+=(player.x-self.x-64)*0.2
  self.y+=(player.y-self.y-64)*0.2
  self.x=mid(0,self.x,448)
  self.y=mid(0,self.y,448)
  if n_terminals()==0 then
    self.x+=rnd(4)-2 self.y+=rnd(4)-2
  end
  camera(self.x,self.y)
end

-- map decompression
function decompress_to_mem(data,dest)
  local bi,bti,di=1,0,dest
  local function read_bits(n)
    local v=0
    for _=1,n or 1 do
      if bi>#data then return end
      v=bor(shl(v,1),band(shr(data[bi],7-bti),1))
      bti+=1
      if bti==8 then
        bti=0
        bi+=1
      end
    end
    return v
  end

  while true do
    local f=read_bits()
    if not f then return end
    if f==0 then
      local byte=read_bits(8)
      if not byte then return end
      poke(di,byte)
      di+=1
    else
      local dist=di-read_bits(12)-1
      local len=read_bits(4)+1
      for _=1,len do
        poke(di,@dist)
        dist+=1
        di+=1
      end
    end
  end
end

function decompress_map()
  decompress_to_mem(map_data[current_mission],0x8000)
end

__gfx__
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee11122222eeeeeeeeeeddddee00000000eeeedddd6667eeee6b6bb6b666b666666666666600000000eeeeeeeedd6667ee
eeeeeeeeee5777eeee5777eeee5777ee11122222eeddddeeedddddde00000000eeedd66666667eeeb7bb22bb66b666666b666bb600000000eeeeeeedd666667e
ee5777eee577cc7ee577cc7ee577cc7ed112222dedbbbbdedddddddd00000000eedddd66666667ee61bbb7b66bbbbb666bb66b6621212121eeeeeeed55ddd66e
e577cc7ee777cc7ee777cc7ee777cc7e1d1222d2db7bbb7ddddddd2d00000000eeddd665dddd66ee1bb7bbb26b66bbb6bbbbbb6611111111eeeee11d5d111d6e
e777cc7ee577777ee577777ee577777e11dddd22dbbbbbbddddd22dd00000000eeddd65d1111d6ee1bbbbb72666bbbbbbbbbb66600000000eeee11dd5d181d6e
e577777ee577777e05777770e577077e11122222dbb7bbbd1ddd22d200000000e1ddd65d1001d61eb7bbbb2b66bbb7bbb7bbbb6612121212eeee1dd55d111d6e
0577707e0e0ee0e00e0e0ee00eee0ee0111222221dbbbbd211dddd220000000011115d5d1001d611611b7226666bbbbbbbbbb7b611111111eeee1d55dddd6eee
0e0ee0e00e0ee0e0eeee0eee0eeeeee06112222611dbdb221112222200000000e1ddd65d1111d61e66b6b66bb66bbbbbbbbbbbbb00000000eee11d5d111d6eee
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee7777777777777776ee1111eeeeddd665dddd66ee66666666bbbbbbbbbbbbbbbb00110120eee11d5d181d6eee
eeeeeeeeee5777eeee5777eeee5777eee00000ee7666666666666666e111111eeeddd666666666ee666266666bbb7bbb7bbbb7bb00120110ee11dd5d111d6eee
ee5777eee57cc77ee57cc77ee57cc77ee00a00ee766655555555666611166111eeddd566616166ee61662266666bbbbbbbbbbbb600110120ee1dd5ddddd66eee
e57cc77ee77cc77ee77cc77ee77cc77ee00a00ee766556666665566d01111115eed0d6606d6066ee166666626bbbbbbbbbbbbbbb00120110ee1d5d111d6eeeee
e77cc77ee577777ee5777770e577777ee00a00ee765566666666556d00111155ee02d6000d0006ee166666626b6b66b7bbbbb66b00110120e11d5d181d6eeeee
e577777ee577777e05777770e577707ee00000ee765666666666656d07005555ee02d000020006ee666666226b6bb6bbbbb6bb6b00120110e11d5d111d6eeeee
057770700e0ee0e00e0ee0ee0eeee0e0e00a00ee765666666666656d07005755eee20001520101ee61166226666b66bbbbb6bb6600110120e11d65ddd66eeeee
0eeee0ee0eeee0eeeeeee0ee0eeeeeeee00000ee765666666666656d07005755eee211015222222e666666666666666bbb666b66001201101111d66666eeeeee
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee765666666666656d00005575eee222225ee1ee2e00000000bbbbbbbb00000000000000006626666626666666
eeeeeeeeee5772eeee5772eeee5772eee00000ee765666666666656d00705555eeeeee0250eeee2e00222200b7bbbbbb00000000000000007727777727777776
ee5772eee577772ee577772ee577772ee0aaa0ee765566666666556d07005755eeeee112e0ee112e02222220bbbbb7bb00111111111111107622662226666666
e577772ee777777ee777777ee777777ee000a0ee766556666665566d00705575e000010ee0ee1eee01222250bbb7bbbb0012121212121210766221211111666d
e777777ee577777ee5777770e577777ee00aa0ee766655555555666d07005555e0eee1eee0ee1eee01115550bbbbbb7b0011000000000110766126266661166d
e577777ee577777e05777770e577707ee00000ee766666666666666d00005555e0eee1eee0ee1eee01115550b7bbbbbb00120111111102107611222666622222
057770700e0ee0e00e0ee0ee0eeee0e0e00a00ee666666666666666d00005555eeeee1ee00ee1eee01115550bbbb7bbb0011012121210110761666211622616d
0eeee0ee0eeee0eeeeeee0ee0eeeeeeee00000ee66dddddddddddddde000555eeeeee1ee0eee1eee00115500bbbbbbbb0012011000110210761666166226616d
66666666eeeeeeeeeee00eeeeee00eeeeee00eeeeee00eeeeee00eeeeee00eee5555555555555555521121125555555500110120002101107616661661222222
66222266eeeeeeeeee0000eeee0000eeee0000eeee0000eeee0000eeee0000ee555555222255555552222222555555550012011000110210761622611666616d
62222226eeeeeeeeeecccceeeecccceeeecccceeeecccceeeecccceeeeccccee555555211255555555555555555555550011012121210110761226622666616d
61222256eeeeeeeeeec77ceeee77cceeee7ccceeeecccceeeeccc7eeeecc77ee555555211255555555555555555555550012011111110210722266662266116d
61115556eeeeeeeeeec7cceeee7ccceeeecccceeeecccceeeeccc7eeeecc7cee555555222255555555555555555555550011000000000110726116666261166d
61115556ee1111eeeecccceeeecccceeeecccceeeecccceeeecccceeeeccccee555555211255555555555555555555550012121212121210226611111211666d
66115566e111111eee0000eeee0000eeee0000eeee0000eeee0000eeee0000ee555555211255555555555555522222220011111111111110766666666266666d
66666666ee1111eeeee00eeeeee00eeeeee00eeeeee00eeeeee00eeeeee00eee55555522225555555555555552112112000000000000000066ddddddd2dddddd
55555555555555515555555511555555115555555535535555555555066655550666555555556660555566600000000000000000666666666666666655555551
55555555555555115555555501555555011555555533533555555555066655553336555555556660555563330666666666666660666666666666666655555511
55555555555551115555111101111555001555555553553511111151066655550633355555556660555333600666666666666660661111111111111655555110
55555555555511105551110000111155001155555353553511001111066655550666555555556660555566600666666666666660661212121212121655551100
66666666666111005551100000001155000116666363363600000000066655553666533355556660333566600666155555516660661166666666611655511000
66666666661110005111000000000115000011666366333600000000066655553333535555556660553533300666515555156660661261111111621655110000
66666666661100001100000000000011000001166336336600000000066655550363333555556660533336330666551551556660661161212121611651100000
00000000000000001000000000000001000000000000030000000000066655550666555555556660555566600666555115556660661261166611621611000000
00000000000000001000000000000011000000000003333000000000066555550000001155556660511000000666555115556660661161266621611615555555
66666666661100001100000000000015000001166633663300000000061155550000011555551160551100000666551551556660661261166611621611555555
66666666666110005111000000000115000011666633366300000000011155550000115555511100555110000666515555156660661161212121611601155555
66666666666111005551100000011155000016666336366300000000011115550000115555111100555110000666155555516660661261111111621600115555
55555555555511105555110001111555000115555355355310110011000115550011115555110000555111100666666666666660661166666666611600011555
55555555555555115555511111155555000155555355355511111111000011550111555551100000555511100666666666666660661212121212121600001155
55555555555555515555555555555555001155555355555555555555000001150661555511000000555516600666666666666660661111111111111600000115
55555555555555555555555555555555011555555555555555555555000000110666555511000000555566600000000000000000666666666666666600000011
55555555555555531555555555555551000000111100000055555555000115550011555555511000555511005555555115555555661161266666666666666666
55555555553335335155555555555515001111155111110055555555000115550011555555511000555511005555551551555555661261166666666667777776
55555555333533355515555555555155011555555555511055555555000115550011555555511000555511005555515555155555661161262121212167666666
5555555555355555555155555555155501515555555515105511111500011555000115555551100055511000555515555551555566126116111111116766666d
5555555553355553555566666666555501551555555155105510001100001155000115555511000055511000555155555555155566116126666666666766666d
5555555555555333555566666666555500155155551551001110000100001115000115555111000055511000551555555555515566126116121212126766666d
5555555555553353555566666666555501155515515551101000000000000115001155555110000055551100515555555555551566116126111111116766666d
555555555555555555556660066655550155555115555510000000000000011500115555511000005555110015555555555555516612611666666666666ddddd
55555355000000005555666006665555015555511555555100000000000000006366633666663666666666666666666610000000000000016366666666336666
5555535500000000555566666666555501155515515555110000000000dddd0063666366666636666666666666dddd6611100000000001116337777667377776
535553530000000055556666666655550015515555155510100000010d6666d06366636633663666666666666d6666d655110000000011556736666637366333
53355333000300005555666666665555001515555551551011000111d666666d636333666333333666666666d666666d55511000000115556736666d3333636d
553555530303000055515555555515550011555555551100511111151d6666d26363666666336633666666661d6666d255551100001155556333366d6363336d
5535353303030300551555555555515500155555555551005555555501dddd2063336666666366666666666661dddd2655555110011555556366366d6366366d
53353535000000005155555555555515001155555555110055555555001222006636666666336666666666666612226655555511115555556366336d6336366d
3333353500000000155555555555555100011115511110005555555500000000663666666636666666666666666666665555555115555555636dd3dd663d3ddd
709470aa60f8600d003f300c300e120f028f81c701e3a0f160f038782c301e120f0a8f85c703e3a1a11768ff0c340e540f738ff8cf41e772ff70f348f45cfb1e
551ff88ffccfb64d55001008910cb03e8952331b8d3af014081451e85c261a44ce05083641a05a214b40441a001608113902d8033096200167004b702381c070
801090a4c0463508140cc20a810d00374870886d94a8bea84a98340c864345d2281cc1266f560f12cbede70801b9fc6e0f8dca80400816045302406c8d50c180
406f06422ca33af518050b6f35cce7c3e1f874391d2e0024a7d07802c905708200992e008cd60816b10eab6420cc534afe8015618c60442a9627cbe0841f8031
d304101e83098485324a52840c96885f4c942e8e061d8eaa94aed7f3f11e0b050d84d619eb10b8e01b5038020b562d475225802ea528f36cde78289dd4038a9e
415cb88609c84c2613896807a83e548626e203a9843588c2abe603212af3188ddd0c8ab3c185181f19804020c0cb45881428060c83844a30914890113b081168
1e43137629c52860343022178204300e120f02933211046e06731cd13aa7177629930b1c00f0194004f1e4017e3516cb5fd067d81981d035d9279b28149ae01c
511842c32fd29521cac7e800f3b15cf80dc8f0448d3249af811da017d3794a430574014ee3c0904124c8098c9a945a3e4d00e32021f6e21c8164508e7d9c0a3c
22402813e14a6b1b9d118503edf6092fbc101407f086749eae114ea769c7a922e6292b92434ab4816df608c5c102f11d7f3297aef166f67371f87c8ebf9c26a1
4ee479291822e664224000807c913308b504f3cc668b2341b1ede238538f428112180294704918cc7e40579384849809f02fcd91c0611638879cc3468b23e421
4ed70e7df1b7288f8cd1326b668fc091ea10ff6017935c0438073623c839a4f87e9556d23c025ae6094c251ec11c2444e81cfc048ae203f0a9d1c1308c9d4220
731c1fdc27fc9c66435b097e40471a91cc4f06e8463840cf0280b728938922ec49d71285eac07e267b69f7accb4a5d000bc5118c3c3498c99b21a40f75a8f6c0
8860264f0669b184ab821e212e11c5f12d936f94598b38f00584983d4d90cc5fe47389e11cd1a01ffc9eb5c89ae836be251728d3b90a005597234f1a6e734f85
53eca806f129ba3440f8eec592e24649b364ef3ee915dc8970ca6a8d91e33fc2ed543ee1663fc6cca905de94f049b7bd40de8929ba040223687f813fd98d3c06
8a80030e32106219ff22775aa349a85ca3b4930b93743f436ceb9aab3b6781744a1aad19d332576b92b9961443c6b2719ce580aed668bbc15ae0679a1458c966
80de9448632de43c4773aaf3890ccde5b8a3a96e6b4bfb0ec511adbb72d48b8813b98aff4b8fa17bcb1a2ffdb4253a48b7b16c108b25c81ae9ae9497973a9fb9
e63675041858692dcc747522d9979cc9fc57738632dff18f80c67aa775e3d00f10b4fec0df6d5d5e311428330e8a3a2c757938d8f18f4c360a4924e3720d45f3
040e075f719afa815c05fafb45f7af749bc80cf688bfe9081976b7f1cd5ec471d75f83ddd3a47b252fda65fdd0e04028f3accc68613fc3f7996c9eff84f75b56
24f3dc1bf715d5d02f2940c15b36b9e6170e04421a6e809f592eacd31cd15ae46e8dffd49ee1262fa7db4ab196c399f8225dd0fe637e375c4998cde3e061742b
9bea3e6af76325f7def760c1146a85e51096074f3ada9dc1e842365a60e45e3009173211c62c958121c2004c98b6af3a9fb91e4e9f7fa5344b17fc56363b3e2c
b8e9f86d02d939997c66e4175c9b55c53fcd54adda5b33bd220f259d1f41ccabd8d18ae026a4af202782d99ff110ddc955f14dbd435b0832b9cc637bd339e1b9
c090414fcd8bb9007946341884ce35839187210b743fd6656e11ee06f3e16fc449f1c5bb98e0e1909b26f3c60e9c0f748f326cf940c5f2bc00b9dc6caeb2eaf0
6c2956bb36f2b64a1409f9329836f62087ad35e9f41d0286b65d76ccb9a520dd0ef8785fb5c3ac52dccc9034670e0b78f0affd2264a64c1fdb43c3fe46df4228
1cce74ee7d4ee5d355e6770e79730362084d5f2a332d97a1f0c546d4ecf1d18c9f61f7cabf078b0aa96df7c67f98ff0466978145dfc0b3ff317a83b927a057b8
f399cc81e5a5da9b6332ce862ba31c02b46cbff26b1e48d8db3908a2a7d236f5663860b349abe4fbb29e06afe152c8de5af78cdfec27f339ff54df0b19758b65
117e034bd9340ec73c897fa5ff7af4b47a360f5c83cff5e013fa2c5cd3ed78117c1fa89b36cd1869bafaff8faa11bfb887626ccc1cb708e388c81178e2be4b16
63e9bb877cf9ff0b3baa3cad5ce0bc1306f84bf418e50ec4adb10da307cb770c62fdc2f22640cfc7ce2d30c745388c40f10aa4a04677a9dfa19fe16ae605665c
8c9eac89837499fb5f748117977c91ae5402c9a70c138dd298984148443aa7dc0484d5fb825f71e580d89ff8cfeff7ffff7effffffffcf28ef34e770587e3c33
ef5c748181c7f0e7f4f160f2497cac3a5e172f8c9fc6c7abe3f5f103f8897ccc3a6e173f849fcac7ade3f6f183f8c97cec3a7e173f8c9fcec7afe3f7f104f80a
7c0d3a8e174f84afc2d7a1e3f8f184f8df9e08300c300e120f0237c8a0e770f320f318f81c7a0e9b0f988fc4cf12eb31f5c0f968fc3c7a1e3f1f908fa795c20a
0582d9a813b2211a44ca65b3410200448c80c920ac20ba001e30a80a1005e281319165404e55082104872acc4c3716080e060341e86c800013ca39102108160c
5506c1228a5b83673340a2b20c17e070801143b06413e07403b1986c3f974bfd00730314c1c400348701fd0030200402c450897d8b0bb7e14012f9087838cfc0
40cfd6f3b1fc0f203110a2110f0673e9fc743a96ae00a6b773899403118302c840805f4037438c87e42f1204cef78def97c30ccbf4402d4fd040df203d19be59
0ee8033422ce328cdb303a48a7b10eca050a82701286a1d0e19cd050050e0493c4ed872882e9f4603d4c10403f90100314e1d0017434c7010da9e608003cc5c8
03743287212078d02742ac910ee85a3890afd09c6025502cc5f40f7d3944d044a9e44810e90aa803ba0242320dbba0238114410a0b623049f6e4637c6137835c
83f87e89b3c1a18473d01d68db54c9b81d56219e8bc5f2f224450ee80be88232800cdde01a73a93ea81ffa857a910e5f60458801e9f415763d4df1c8c7f368ae
b10ee80d1e1148b6a4d252b159889344d794017d81f141b2402f0372e12aa4623f1062807f113e634c183aee139784cfc8842df37871200996b022ec0bf8389c
67d046e603297aa81f55823dc164ece19a321fb8ac10424a15eb939419ea905c021de19c9bfc7e88bc9147d9611f689b6916f129d091b3c910a8809e50492929
8481c864334052a8d22c153a13599029e632ccb64d1f404743ace1d80f3395644af84dfdb16c734c9b2ecd5492d149dc4009064913ac5d4ac823e58132cd5c29
36d2405708b85c9d6e4435709229491d68055082288980ac83fc6291b89cca1c0090532c100232669c30428ce81626b799922132ee35c793fac87d84fd82779a
98618c0100221381885412118060334087c47b007e08207102e80b8f94f590a6e04c0738b8b102cc59d916559666d826372893c9a801008da0c0bca42836b355
421c9d804085eb4106a8c07c4087e99691a0453c2199e4094cc673b91edc07ad36d7308190b1367aa6c90ee876a2360daa396c34730c203c16acd3520249ed03
e845e1f805468a831bca3940b730e90a100f74a41442110ffd60b17a158926f3321cc611cd80a72014347eae0321051247d960fb7aaa29dacb5d9b3188673956
60e85038122d3e30d74329ca22d678dd3c6da2fa20aafd990d1ed5570394b29261354132c79d61f2fb161a1265ca4acb7481320dc1cc6419b60461c06691aa99
6618bae141295a9ccc8873fa2342d7ae39be2116ca83b8f63e74a36691aa9c4a40daa95595fedd2ff788325c8ae0842e679249da4973019288419f057e40e783
0efe0ef87281329ce06352834f4b8dcc8fa6812748a5a78a67fe767754cb10b41d9c097dbe89120afd043b5b9b9586d47a997153a5cc3c3634e0dddecc114938
481aae3dbc806ff3cd42dacf05b4a2cf908b7f40673b2ec5035475b7a37dd991a21a3fa3a74897a5c6d60c7354a2c959ccecaa98d067ca2f14d1928e7d0533d7
974e5579a5e191dc3fc19df1dbdc84b31683d3b496a6ce4cc98d4b32eeee26f71ca82d98f07c3f9faa9cda447b2a2131fa88795ca8f3efb8c48e2432015e4203
3081309081dc002412d9d6c562c07199ea8865d6eb32065326f37ec1aa6459b8a23087296a32b13ee61fdb37d61f41d948565384ef57f69552a39698e4d647c6
731e118a5b714cb63812abec0fa2aabe2e55963a008410820c81c05138d282088b30e231648f59582543c9b6f318056bc5f4d124d0732d929ee13a008dea3a3c
093b50a85c47b4c394d91fe1809ee5e721982b2e1d9fc98c8a0c9334b7535edaf6881b768fb66bd50d6af6685c1892e878b8c0da31f07396c764d33126f3cf02
295cb8e7996c973d267056f07d5c267dd0ad80afb55af70e0917cd742f61db453e4a5b0ce6a19611bf49a7608b77a1da0a2e73494bc36c3710cbfd40b7731eeb
7be92b9736993b830b77bdaf51cc4320321fba55cc8503b10e108df63a5641a2ae508b13d33def8e40a34e319f7d76ae70eb3e8d25d448c9b51efb7137c756bd
cbd1c2c2b778c692da48439b8bd798cee99ae62c1a752777077c5557c9b0555797e40f8ba1506a3fe8f5528b38ad821cf18fabb9ece325c20ec66d94cdd3f693
10b775017691e8865e5c44e1a591ec035d97fb7262bc1666e72037c29fe47570875ef95140adc0a904ed8234c9ea923a09caedf40eb3af66d683cd41341d3e10
ceb75dd714d1b0bbdb8396c111e8273e1180bad92799d47ec8d49547ddac97c207417fecdbb3c2d7c87f885fc089bc1041cccb6a993ee58b75768fc0cd2375e8
fa058bfcb202908fefa668dc0cca1a32b9f3e9fb09fa079ca42ab8918f02fc29033793cf6ff653471d9bc4788e6c71b740d9297f69b7c126ec1adc3c82e2a136
612c4e1dde47dfab32fdff983a7c24e792571fe0dfdcb48211afac86e77d1db90c688ff86e1e4961c1dc3b1803fb61043198c0bef1962a7bccf553143f53fc50
f3ed6da8fd13b799c9d63f500500fcffcf30ef30ff20ff18ff5ef00adb9f36cfbb47e0efa0f9a0fd58fe3c731ebb0fde8fe7cf34e732fb21fd98fe5c732ebb1f
d68febcf36e733fba1fdd8fe7c733ebb1fde8fefcf38e734fb22fd19fe9c734ebb2fd69fe3cf3ae735fba2fd59febc735ebb2fde9fe7cf3ce736fbbf7930c904
0f008f80c7806140ff30f628730cfc029c0f258ff21ec20a15b2d1a85885204910480a6508850c820a005225c8208589a20830290ec2548101902440a00508b4
39120a4e3716080c07838102100f01359562e16ed118b30c790e040f743410eb0041a708000c930c090031970829d0b31cd1e00f7282800101bd101573b10a06
628d0192eb4050317f2883b9f8463e4d0081eda7084014d11ae119d8110e63808ea7630c5a905a8e81c130a8801f804fd371940db81608c261c028392c89cc60
89b61c023ca03c28a3b9068809bb8301c2700efd806c73685c07ec0146424e0ca6099b5cca46a3643840116d026ae528a3e90e047e81f01beb516cd472040218
__label__
00000000000000000000000000000000001101000000000000000000000000000000000000000000000000000011010000000000000000000000000000000000
02000000020000002000020000000000001001100000000000000000000000000000000000000000000000000010011000000000000000000000000000000000
00000200000002000000000000000000001101000000000000000000000000000000000000000000000000000011010000000000000000000000000000000000
00020000000200000000000000000000001001100000000000000000000000000000000000000000000000000010011000000000000000000000000000000000
00000020000000200000000000000000001101000000000000000000000000000000000000000000000000000011010000000000000000000000000000000000
02000000020000000000000000000000001001100000000000000000000000000000000000000000000000000010011000000000000000000000000000000000
00002000000020000000000000000000001101000000000000000000000000000000000000000000000000000011010000000000000000000000000000000000
00000000000000000000000000000000001001100000000000000000000000000000000000000000000000000010011000000000000000000000000000000000
00000000000000000000000000000000001101000000000000000000000000000000000000000000000000000001011000000000000000000000000000000000
00002000200002000222222002222220001001100222222002222220022222200222222002222220000000000011001002222220022222200000000000000000
00000000000000000200000002000000001101000200000002000000020000000200000002000000001111110101011002000000020000000000000000000000
00000000000000000200000002000000001001100200000002000000020000000200000002000000001010101111001002000000020000000000000000000000
00000002000000000200000002000000001101000200000002000000020000000200000002000000001100000000011002000000020000000000000000000000
00000000000000000200000002000000001001100200000002000000020000000200000002000000001001111010101002000000020000000000000000000000
00000000000000000200000002000000001101000200000002000000020000000200000002000000001101011111111002000000020000000000000000000000
00000000000000000000000000000000001001100000000000000000000000000000000000000000001001100000000000000000000000000000000000000000
00000000000000000000000000000000001101000000000000000000000000000000000000000000001101000000000000000000000000000000000000000000
00000000022222200222222000000000001001100000000000000000000000000000000000000000001001100000000000000000022222200222222000000000
00000000020000000200000000000000001101011111111000000000000000000000000000000000001101000000000000000000020000000200000000000000
00000000020000000200000000000000001001111010101000000000000000000000000000000000001001100000000000000000020000000200000000000000
00000000020000000200000000000000001100000000011000000000000000000000000000000000001101000000000000000000020000000200000000000000
00000000020000000200000000000000001010101111001000000000000000000000000000000000001001100000000000000000020000000200000000000000
00000000020000000200000000000000001111110101011000000000000000000000000000000000001101000000000000000000020000000200000000000000
00000000000000000000000000000000000000000011001000000000000000000000000000000000001001100000000000000000000000000000000000000000
00000000000000000000000000000000000000000011010000000000000000000000000000000000001101000000000000000000000000000000000000000000
02222220022222200000000000000000000000000010011000000000000000000000000000000000001001100000000000000000000000000222222002222220
02000000020000000000000000000000000000000011010000000000000000000000000000000000001101000000000000000000000000000200000002000000
02000000020000000000000000000000000000000010011000000000000000000000000000000000001001100000000000000000000000000200000002000000
02000000020000000000000000000000000000000011010000000000000000000000000000000000001101000000000000000000000000000200000002000000
02000000020000000000000000000000000000000010011000000000000000000000000000000000001001100000000000000000000000000200000002000000
02000000020000000000000000000000000000000011010000000000000000000000000000000000001101000000000000000000000000000200000002000000
00000000000000000000000000000000000000000010011000000000000000000000000000000000001001100000000000000000000000000000000000000000
00000000000000000000000000000000000000000011010000000000000000000000000000000000000101100000000000000000000000000000000000000000
00000000000000000000000000000000000000000010011002222220022232200222222002222220001100100000000000000000000000000000000002222220
01010101010101033333333033333333033333333033333333033333333033000233300002000000010101100000000000000000000000000000000002000000
11111111111111133333333033333333033333333033333333033333333033300333000002000000111100100000000000000000000000000000000002000000
00000000000000033000011033000033000000033011033002000000020003333330000002000000000001100000000000000000000000000000000002000000
10101010101010133111001033000033033333333010133002033333333000333300000002000000101010100000000000000000000000000000000002000000
11111111111111133101011033000033033333333011133102033333333000333300000002000000111111100000000000000000000000000000000002000000
00000000000000033011001033000033033033300000033000000000000003333330000000000000000000000000000000000000000000000000000000000000
00000000000000033333333033333333033003330000033000033333333033300333000000000000000000000000000000000000000000000000000000000000
02222220000000033333333033333333033000333222233000033333333333000033000000000000022222200000000000000000000000000000000002222220
02000000000000000011010000000000000000033200000000000000000000000003000000000000020000000000000000000000000000000000000002000000
02000000000000000010011000000000000000003200000000000000000000000000000000000000020000000000000000000000000000000000000002000000
02000000000000000011010000000000000000000200000000000000000000000000000000000000020000000000000000000000000000000000000002000000
02000000000000000010011000000000000000000200000000000000000000000000000000000000020000000000000000000000000000000000000002000000
02000000000000000011010000000000000000000200033333333033000333033333333033333333033333333033033333333033333333000000000002000000
00000000000000000010011000000000000000000000033333333033003330033333333033333333033333333033033333333033333333000000000000000000
00000000000000000011010000000000000000000011033000033033033300000000000000000033000000033033033000033000000000000000000000000000
02222220000000000010011000000000022222200010033000033033333000033333333033333333033333333233233000033033333333000000000002222220
02000000000000000011010000000000020000000011033000033033330000033333333033333333033333333233033000333033333333000000000002000000
02000000000000000010011000000000020000000010033000033033300000000000000033033300033033300233033003330000000000000000000002000000
02000000000000000011010000000000020000000011033333333033000000033333333033003330033003330233033033300033333333000000000002000000
02000000000000000010011000000000020000000010033333333030000000033333333033000333033000333233033333000033333333000000000002000000
02000000000000000011010000000000020000000011010000000000000000000000000000000033000000033200033330000000000000000000000002000000
00000000000000000010011000000000000000000010011000000000000000000000000000000003000000003000033300000000000000000000000000000000
00000000000000000011010000000000000000000011010000000000000000000000000000000000000000000000033000000000000000000000000000000000
02222220000000000010011000000000022222200010011000000000220222220222222000000000000000000222232000000000000000000000000000000000
02000000000000000011010000000000020000000011010101010101200000000000000000000000001111110200000001010101010101010101010101010101
02000000000000000010011000000000020000000010011111111111200001011111000000000000001010100200000011111111111111111111111111111111
02000000000000000011010000000000020000000011000000000000200100000001100000000000001100000200000000000000000000000000000000000000
02000000000000000010011000000000020000000010101010101010201100000000000000000000001001110200000010101010101010101010101010101010
02000000000000000011010000000000020000000011111111111111201000011000010000000000001101010200000011111111111111111111111111111111
00000000000000000010011000000000000000000000000000000000201000100000010000000000001001100000000000000000000000000000000000000000
00000000000000000011010000000000000000000000000000000000201000100100000000000000000101100000000000000000000000000000000000000000
02222220000000000010011000000000022222200000000000000000201000011000010000000000001100100222222000000000000000000000000000000000
02000000001111110011010101010101020000000000000000000000201000000000010001010101010101100200000000000000000000000000000000000000
02000000001010100010011111111111020000000000000000000000200000000000110011111111111100100200000000000000000000000000000000000000
02000000001100000011000000000000020000000000000000000000200110000001100000000000000001100200000000000000000000000000000000000000
02000000001001110010101010101010020000000000000000000000000011111011000010101010101010100200000000000000000000000000000000000000
02000000001101010011111111111111020000000000000000000000200000000000000011111111111111100200000000000000000000000000000000000000
00000000001001100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000101100000000000000000000000000000000000000000001101000000000000000000000000000000000000000000000000000000000000000000
00000000001100100000000000000000022222200000000000000000001001100000000000000000000000000222222000000000000000000000000002222220
01010101010101100000000000000000020000000000000000000000001101000000000000000000000000000200000000000000000000000000000002000000
11111111111100100000000000000000020000000000000000000000001001100000000000000000000000000200000000000000000000000000000002000000
00000000000001100000000000000000020000000000000000000000001101000000000000000000000000000200000000000000000000000000000002000000
10101010101010100000000000000000020000000000000000000000001001100000000000000000000000000200000000000000000000000000000002000000
11111111111111100000000000000000020000000000000000000000001101000000000000000000000000000200000000000000000000000000000002000000
00000000000000000000000000000000000000000000000000000000001001100000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000101100000000000000000000000000000000000000000000000000000000000000000
02222220000000000000000000000000000000000222222000000000001100100000000000000000022222200000000000000000000000000000000002222220
02000000000000000000000000000000000000000200000001010101010101100000000000000000020000000000000000000000000000000000000002000000
02000000000000000000000000000000000000000200000011111111111100100000000000000000020000000000000000000000000000000000000002000000
02000000000000000000000000000000000000000200000000000000000001100000000000000000020000000000000000000000000000000000000002000000
02000000000000000000000000000000000000000200000010101010101010100000000000000000020000000000000000000000000000000000000002000000
02000000000000000000000000000000000000000200000011111111111111100000000000000000020000000000000000000000000000000000000002000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000001011000000000000000000000000000000000000000000000000000000000000000000000000000000000
02222220000000000000000000000000000000000011001002222220022222200222222002222220000000000000000000000000000000000000000000000000
02000000000000000000000000000000001111110101011002000000020000000200000002000000000000000000000000111111010101010101010101010101
02000000000000000000000000000000001010101111001002000000020000000200000002000000000000000000000000101010111111111111111111111111
02000000000000000000000000000000001100000000011002000000020000000200000002000000000000000000000000110000000000000000000000000000
02000000000000000000000000000000001001111010101002000000020000000200000002000000000000000000000000100111101010101010101010101010
02000000000000000000000000000000001101011111111002000000020000000200000002000000000000000000000000110101111111111111111111111111
00000000000000000000000000000000001001100000000000000000000000000000000000000000000000000000000000100110000000000000000000000000
00000000000000000000000000000000001101000000000000000000000000000000000000000000000000000000000000110100000000000000000000000000
02222220022222200000000000000000001001100000000000000000000000000000000000000000000000000000000000100110000000000222222002222220
02000000020000000000000000000000001101011111111000000000000000000000000000000000000000000000000000110100000000000200000002000000
02000000020000000000000000000000001001111010101000000000000000000000000000000000000000000000000000100110000000000200000002000000
02000000020000000000000000000000001100000000011000000000000000000000000000000000000000000000000000110100000000000200000002000000
02000000020000000000000000000000001010101111001000000000000000000000000000000000000000000000000000100110000000000200000002000000
02000000020000000000000000000000001111110101011000000000000000000000000000000000000000000000000000110100000000000200000002000000
00000000000000000000000000000000000000000011001000000000000000000000000000000000000000000000000000100110000000000000000000000000
00000000000000000000000000000000000000000011010000000000000000000000000000000000000000000000000000110100000000000000000000000000
00000000022222200222222000000000000000000010011000000000000000000000000000000000000000000000000000100110022222200222222000000000
00000000020000000200000000000000000000000011010000000000000000000000000000000000000000000000000000110100020000000200000000000000
00000000020000000200000000000000000000000010011000000000000000000000000000000000000000000000000000100110020000000200000000000000
00000000020000000200000000000000000000000011010000000000000000000000000000000000000000000000000000110100020000000200000000000000
00000000020000000200000000000000000000000010011000000000000000000000000000000000000000000000000000100110020000000200000000000200
00000000020000000200000000000000000000000011010000000000000000000000000000000000000000000000000000110100020000000200000000000000
00000000000000000000000000000000000000000010011000000000000000000000000000000000000000000000000000100110000000000000000000000000
00000000000000000000000000000000000000000011010000000000000000000000000000000000000000000000000000110100000000000000000000000000
00000000000000000222222002222220022222200010011002222220022222200222222002222220022222200222222000100110022222200000000000000000
00000000000000000200000002000000020000000011010002000000020000000200000002000000020000000200000000110100020000000000000000000000
00000000000000000200000002000000020000000010011002000000020000000200000002000000020000000200000000100110020000000000000000000000
00000000000000000200000002000000020000000011010002000000020000000200000002000000020000000200000000110100020000000000000000000000
00000000000000000200000002000000020000000010011002000000020000000200000002000000020000000200000000100110020000000000000000000200
00000000000000000200000002000000020000000011010002000000020000000200000002000000020000000200000000110100020000000000000000000000
00000000000000000000000000000000000000000010011000000000000000000000000000000000000000000000000000100110000000000000000000000000
00000000000000000000000000000000000000000001011000000000000000000000000000000000000000000000000000110100000000000000000000000000
00000000000000000000000000000000000000000011001000000000000000000000000000000000000000000000000000100110000000000000000020000200
00000000000000000011111101010101010101010101011000000000000000000000000000000000000000000000000000110101111111100000000000000000
00000000000000000010101011111111111111111111001000000000000000000000000000000000000000000000000000100111101010100000000000000000
00000000000000000011000000000000000000000000011000000000000000000000000000000000000000000000000000110000000001100000000000000000
00000000000000000010011110101010101010101010101000000000000002000000020002000000000000000000000000101010111100100000020000000000
00000000000000000011010111111111111111111111111000000000000000000000000000000200000000000000000000111111010101100000000000000000
00000000000000000010011000000000000000000000000000000000000000000000000000000000000000000000000000000000001100100000000000000000

__gff__
0000000041000100000004040400000000000000000000000000000404000000000000000000800000000104000011010100000000000000010101010000010103030303030303030303030303000001030303030303030003030303030000010101030301010303030303010100000001000303010103200000002001050000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__map__
711520e436e4c269823c12208e85d84a21be041c0780fb411c85c2f2f174dc4e8479c11a4f27e847a1c636084730c58049d140488e893631e44d374000e160b1f7487b91be08423e1fc6a4a0d05045a823bc7e1611e70d528d68c1c44ba5e803117a280a6a847e45054df0b0890519f8f318e80ec47da1623218126c1c5243e7
25033648fe227e905f38fa143e08f320243f4a7088537a121c098e5a220d1ec59e212666d823b180c440800097208f64d852248588610ce43d47f460462419e09910b91ad69e7096235e84d8d594894a486711b12cc72ce786f01f23d978f52166379e4f07982310ac5725f998aace184e71f73940141c5623e725c23b9c4553
17a36cc65a5da47a3c4694837047638c11ea70c26c379be59cd14c592e18740e2aa2b391cd73a3a384450a22a27089fdcc4845b02643041a5a0e2e7b374bb0a08ef4c522dc4b088a413311a00024480395359201026689fccfb98d13164184002cc05a9bb1435e055105ba8ec8aa01552ce98015cbb04d5333415411fe08ff04
7906c000608ff3a332d1c611142a81428f6b15c2aadc7529b6952749c12501e08fe71ae67c123e31cd5378359be818f08fa88e61c626f764e98c71463062fe318b12011a58a463300128f71047f8b47d9d3ac1e36004b068952c0e473823a16a35107196c2c6b3e241f6e432bd79f0d94b4230c47dce30d7c38c1cded0ea4c8b
6790cfc6f3f9fe004360368b3bc7de41b1ac924596dad0e567138d9f1fa4814043d578d0e207943fc2ed6d0627e83a959c8e7515047d0257854f508f795c7df0d0867eb393c11ef008a5337c188edac604b78a98493047fc1649e0f17096b4c48b259a42da3f94f3ee49086c823fc11eed887698581ea5e55ae0c20d9e789167
7c24380189167a23245320542da74fe71c60a9e608c630b5cb076783f8e4c0ec7d6e011510353cc23dad7270852154da7e08ff047aca54d60c4fd749dcb288542d949fcab38768bfa2ac82b154ab2ee3a541c11f04a26ccbfd49e01b88b3a63cdef5320a59043977162b846184a3c4828b28aa62dcfdfd17fe08f66037c85d71
1e75344ca0cd4abea6ffa4051565b88e38bd43d5e4a8df047c25e7a9352479f57d049e75f4557bd5c6e9012fb347f847e67ed0c05296991c2998da097cfc19c608fd93d69e99411e0782d942267ed0ff72423fe80e663cb98f9bdebe61d0097fc4becbdd32331657b133cccd0c173f17cf290c26c6b67781564948560c3d5ff1
afb317948cc5ae10d0162b0658cf208fa2ac9288ac39018ede224d60ace8d42d6bd99032cf7672da13d45905508f924f0af8e396b6d693c1230166bda140ab20ad08f7396f7db753374cdd44887039054a020aed8d9a8d1d2ea9bcd75576dd4d447e21b2da879c7098aecfd858301bf66b3b82acd9b6ced0087a8007c4b90c10
d7b967ef04981b4ca7cc594ef5374e2049bf257b2613a5b1b338e661c8e6037c1bf7872871ca23f20de08e9c887e0dade7b71bc404c26f1a7792e71cb5b9c2276f7de3e423ee29f48ca483001208ffc129cb589172d477dd6ad115f784ff38d5d7d9ebe9a08efd3bb186fc73377196b82bc93df5f685c847d6896712255e93dd
4d66cebd9ce433f9e3990c59cebd1c744a64522c2e8f122508f505f32672d8d96bb03cec8809cc842d6823fc80ddf629302ed06ae1222ad279668737eed8734ce061c6e6e677823a799cf71387703d69aff546533fde90bbd084afcbb8ab76fbb4e83612757bdad1abd1a1c204ba2a83aced39a3c49c81215400240e2a800616
f3c725cd947db5ffffff9fafd057c1abb453f48ded47fe963f4d1fa78fd447eb7ff5dff7ccfbea7eb63f5d1faf8fd847ec63f651fb38fda47ed63f6d1fb78fdc47ee63f751fbb8fde47ef63f7d1fbf8fe047f063f851fc38fe247f163f8d1fc78fe447f263f951fcb8fe647f363f9d1fcf8fe847f463fa51fd38fea47f563fad
1fd78fec47f663fb51ff9d60039c40f000480334017e033f013f81afc0ebe0abf06bf83afc230455000825940ec5528940a2563b150aa5080011da0082558032c01c6020501912b40046032501f42ac059204450242264349055002486da1a0d86038182000470802a402d8c060803540318e1013b3592611cb11e10ec469890
6037c0004da6f8004c02ee02bf026830411e0ef162623984fc7a3d1b4f5000426978f500b58256406d2042d01f583c8984d308f78d6b95cc104713c9749d08fa82399b21833047f833a423cce311c98fe990cde783c9ea0e946f27409ccc440800298cc108f5834cc11e211f124563cc119e1ac87a8299c3fc8971bd38cb091c
c10da637c361e0ce861823e4a39608e27e36c40e49a4e84e1451c88f1c738cb091cd719c2371b89d0ee380d1407ce0ce911f638cb368f07837974dc2e179ba006517118038c02c6000504723046590b70da536c0890db01e22f1760aa70d7d98e214cf2783fc6c447c3f801cc23d641e27b8ef09ca1b4b11e137c088cdb01e63
6c47f26c6a588d789e0df1ee536c2288bc7a823a9a62305255186a09c0d7099389a248704bb01e636c47fe59e723f33fc11d4f51679354580a41a860823ac9484dc5e80f41b623f13e79244096651aa6f26c4808c308f23d02cda7a84cb4a88e52d101f12f47dfe62e87e80ca4afa4db08f6058acba4e84cb4b3ee03ea6938c2
3fcc26f98b39b663910d740d87265e46f84c99b8dd0d4799129be47ff4ce234182735c6d37c4560080486d8c4a52765f3a78a3fa4e9d4d7427ca1931b208ed0db18b891ae897f01f3a9bcd2054b7348620998806680199126b02469ad917211ea1b15ca292030d01fba89d568d4c8763b196b5a24ba7dcc0014e70d75945254b
56a32b02062657224553ef73d9a81a0d9a7153eea1b4927a4379aea1b7520835926b47563463f1f8d548628db09faa3051eb115832a3f12403a907d4e5a74e671b3830aacf0d5571355218cff4f8388788ac39440880689b68f4a7a91e654b8cc04988ffce9c608eb48613c479ca3d2304628f7101256a500d33d1e8f500683d
40352944b1f7f9d399fcfe6aa67340e6a7605047f02012b47159fd967b1fa11ee7897edd772226475e9daabfde6cca91df13fc47d0a67eaaf9442b2c8cd1325899c411fefc4864b8191b22ce9486137d33c6222911883d447ea25ae6f89a2012a1fe68b8189fe3dc31f7116c378ecfc3117388c21ee2c167a896c82c1701a280
81d55f8cf045191e8c35c8780da1f11feddb20b0603222666d37c4bf6254f7371af3e423d0c44123198eb5163bcf09fa95912463bd715c7ae02d37773b5fd0b261820d86b89fce4513b14ccb7e63304c63e021f82169099d9de208643d88fa43544fe6f98b9cfd9c813d5c8087dd7ce2dc97df238df7ea08e51203354fbcf204
255c748cfd27222256c8a9645d8a3905328407caebe604bcbfe76c4e97333c5b8e0f0458483663bf4e18f7a86a516713c31fa3b83fe89448980829f78c39048f16739f8955284602b8b22e448e6e0430802a64888391792b471d5ac461827faf3acd7c4d38be4c3b14e590601b0e4e3deb4221b180c263899221181eabe8a6f8
2308c0dd6bfbd59ad1e0a08e78be13c4d7cb29ca3005c01966ac81b823949f4692a2308432deb8e11e3287f969a9fa86e943618482ca108607a82448120825047286a88c2eccf31b39aff69b0cd07e823b65344f12b5618425ee12055ed10e4c4441975c535d8bec555e97d5c119e08ef0d770587211ef4b45890a06e9c640cc
63a4bfc4884522d8bdb5e8b2d11847a50ddb3bc76f9388894d116372303a2ab59c39ce08e42b0264f9f672ba1f8d7d29d2bbe275a8b250a962cc74b859008c26460b0d04838000d0b88d5c4b7154016eeab37e620246b60381b823b072b21154ec3bc11fb9496683055f9e47c27bba28c45e248cd5de7357021455047fc83501
20913590396c15445f55310d74039c61af7d38fdeb0d83e65a0b0475e077df5361aff9967b175ca3177b3470c3341c623ff11fbd9a91fb94573a023d1ef7b275302236218aa6e35381c334c59fe2cf27e3d9bcd9d2dce2ca48cabc7d91f788d9759dc8fd07b3c80b64188c660e90b9dfc05bdbea15609a80f996738659673515
9794157b26c2a168d4c0ab7a9f9961cc71662c4b807c474e618e23265c93778944d2cfb3bca37fe75ff3cfc7750aa7d35f62ff816fe07ff3ffede898cfe8db455fdbfff3f8abef3f006fd8719c6039f02bf154e7ffff3fff2f87b7c413e7ddf266fa077c517e5234719527c68fe8b5f46afa3d7d22be935f4aafa5d7d32be9b5
f4eafa7d7d42bea35f52afa9d7d52beab5f56afabd7d62beb35f5aafadd7d72bebb5f5eafafd7d82bec35f62afb1d7d92becb5f66afb3d7da2bed35f6aafb5d7db2bedb5f6eafb7d7dc2bee35f72afb9d7dd2beeb5f76afbbd7de2ac774003e021f020f8187c103e0a1f060f8387c203e121f0a0f8587c303e1a1f0e0f87840f
a1f483380010f9c6ee19b8e010900d28042c03a6046f01a8811cbb87c3381fb4021e07ff03ff8246c1d49dc33841141b4a0cc70955838241fca134519b78041c1b4e1169017985d1403d616c50a4f81fa42fe207ef0ec38212c0ecc7d0dc381fac020e07fe3e81ffc0ffe07f50bc88689c454a17e70d3983fcc0a5217fb17f58
c43c544e318502a58bffc151a1d9113f48df9c723617271ce28cf1c6ffe36270ff78101c5da242b316478bec4c87602db03ff80934968a3a33275f9b8fce07e0cff3a1f9d8fcf07e133f3e1f9f8e8000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__sfx__
151000000c0730000000000000000c013000000000000000266550d0000e625000000e615000000e615000000c0730000000000000000c013000000c07300000266550d0000e625000000e615000000e61500000
d1100000021450e14502115021450212502115021450e11502145021250211502145021250211502145021150f145031250311503145031250f1150314503115021450e1250211502145021250e1150214502115
c3100000027500e73002710027500272002710027500271002750027300271002750027200271002750027100f750037200371003750037200f7100374003710027500e7300271002750027200e7100275002710
a71000000c0730c0000c033000000c023000000c013000000c003000000000000000000000000000000000000c0730c0000c033000000c023000000c013000000000000000000000000000000000000000000000
151000000c0730000000000000000c013000000c0730c000266550d0000e625000000e625000000e615000000c0730000000000000000c013000000c07300000266550d0000e625000000e615000000e61528600
cd0e000008d500cd5010d5013d5017d5018d5017d5014d500ed5009d5005d5001d5005d5008d500dd5010d5008d500cd5010d5013d5017d5018d5017d5014d5010d500bd5009d5008d5007d5009d500dd500fd50
47010000000000000000000000003706035060310600000000000000002506000000000000000000000160600000000000000000a060000000000000000000000000000000000000000000000000000000000000
46010000000000000009770097700a7700a7700a6700b7700c7700d7700f77011670117701377015770177701b6701b7701d77021770267702877000000000000000000000000000000000000000000000000000
93010000000000000009770097700a7700a7700a6700b7700c7700d7700f77011670117701377015770177701b6701b7701d77021770267702877000000000000000000000000000000000000000000000000000
cb0600000f5503c6002d6001f60000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000050000000
d5040000393712d37129371243711e37118371123710c3710a3510535105351053510435104351033510235101331013310033100331003210032100321003210031100311003110131101311013110131101311
a702000035453334532f4532b4532645325453234531e4531e4531945316453174531145310453104530d4530a453094530745302453034530045300000000000000000000000000000000000000000000000000
a702000000453024530445306453084530b4530e45311453164531a4531c4531e45320453224532445327453294532c4532f45332453344533745300000000000000000000000000000000000000000000000000
d1090000397702d67029770246701e77018670127700c6700a7400564005740056400474004640037400264001720016200072000620007100061000710006100000000000000000000000000000000000000000
17050000246552f655276553000600000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006
1703000000453024530445306453084530b4530e45311453164531a4531c4531e45320453224532445327453294532c4532f45332453344533745300000000000000000000000000000000000000000000000000
170400003745337453354533345332453304532c4532945326453224531f4531c4531b4531945315453114530e4530c4530945307453044530245300000000000000000000000000000000000000000000000000
a5100000021450e14502115021450a12502115021450e1150214502125021150a145091250211502145021150f14503125031150a145031250f115031450b115021450a125021150a145021250a1150214502115
a30300002d1212212118121121210e121111030010000100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100
d7020000251501b150141500010000100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100
d107000037650316502f65029650226501e65019650166501465012640106400e6400903005630036300262000620006200062000620016200162000620006100061000610006100061000610006100061000610
d70e00000f2400c2401024013240172401824017240142400e24009240052400124005240082400d24010240082400c240102401324017240182401724014240102400b240092400824007240092400d24013240
d70e00000c2400f240132400c2400f240122400c2400f240102400c2400f240132400c2400f24014240122400c2400f240132400c2400f240122400c2400f2400e2400c2400f2401324016240152401424012240
311000000675506755027550275502745027450273502735027250272502715027150271502715027150271507755077550275502755027450274502735027350272502725027150271502715027150271502715
c31000000f7550f755037550375503745037450373503735037250372503715037150975509755097450974501755017550275502755027450274502735027350272502725027150271502715027150271502715
c3100000027500e730027100275002720027100275002710027500273002710027500272002710027500271001750017200171001750017200171001740017100075000720007100075000720007100074000710
010e00000c0730000000000000000c013000000c07300003266550d0000d625000000e6150e6050c6150e6050c0730000000000000000c073000000000000000266550d0000d625000000e6150e6050c6150e600
15040000306503b65027650246501865018650186500c650000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
590400002b6502865026650216501f6501c6501a650186501665013640116400f6400d63009630076300662004610026100061000000000000000000000000000000000000000000000000000000000000000000
a70800000137001300003700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
8d0600002b6502865026650216501f6501c6501a650186501665013640116400f6400d63009630076300662004610026100061000600006000060000600006000060000600006000060000600006000060000600
__music__
01 00175144
00 00184344
00 00170144
00 04185844
00 00171144
00 02034344
02 19034344
01 1a154344
02 1a164344
00 02424344
