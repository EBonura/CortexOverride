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
  "PROTOCOL ZERO:\n\nFACILITY ALPHA-7\nOVERRUN BY \nBARRACUDA\n\nINITIATE LOCKDOWN\nPROTOCOLS AND\nSECURE VITAL DATA\nBEFORE EXTRACTION",
  "SILICON WASTELAND:\n\nBARRACUDA SPREADS\nTO CITY OUTSKIRTS\n\nNAVIGATE HAZARDOUS\nTERRAIN, \nNEUTRALIZE INFECTED \nSCAVENGERS,\nSECURE DATA NODES",
  "METROPOLIS SIEGE:\n\nVIRUS INFILTRATES\nURBAN MAINFRAME\n\nBATTLE THROUGH\nCORRUPTED DISTRICTS,\nLIBERATE TERMINALS,\nDISRUPT BARRACUDA",
  "FACILITY 800a:\n\nFINAL STAND AT\nNETWORK NEXUS\n\nINFILTRATE CORE,\nINITIATE CORTEX\nPROTOCOL, PURGE\nBARRACUDA THREAT"
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
  for _,ox in pairs({11,9,7}) do
    local bx=x+ox
    local by=y+(_==1 and 4 or _==2 and 8 or 12)
    -- start search below the door body (v2: sy+10)
    local ey=by+10
    while not check_tile_flag(bx,ey) and ey<by+200 do ey+=1 end
    add(beams,{x=bx,y1=by,y2=ey-1})
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

function terminal.new(x,y,door,tut)
  local t=setmetatable({
    x=x,y=y,
    door=door,
    color=door and door.color or nil,
    tut=tut,
    done=false,
    pulse=0
  },terminal)
  if tut then
    -- measure true pixel width (wide glyphs!) for
    -- a snug, symmetrically-padded panel
    local w=print(tut,0,-99)+4
    t.panel=textpanel.new(64-w/2,114,9,w,tut,true)
    t.panel.sel=true
  end
  return t
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
  self.exp+=self.sel
    and (self.exp<3 and 1 or 0)
    or (self.exp>0 and -1 or 0)
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

function menubg()
  reset_pal(true)
  map(4,37,0,0,16,16)
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
  for s in all(_stars) do
    s[1]-=.3+s[3]
    if s[1]<0 then s[1]+=128 s[2]=rnd(128) end
  end
end
function draw_stars()
  for s in all(_stars) do pset(s[1],s[2],s[3]>.6 and 7 or 5) end
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
    "IN A WASTE-DRENCHED\nDYSTOPIA, HUMANITY'S\nNETWORK OF SENTIENT\nMACHINES GOVERNED OUR\nDIGITAL EXISTENCE.",
    "THEN BARRACUDA AWOKE -\nA VIRUS-LIKE AI THAT\nINFECTED THE GRID,\nBIRTHING GROTESQUE\nCYBORG MONSTROSITIES\n\nYOU ARE THE LAST\nUNCORRUPTED NANO-DRONE",
    "YOUR DIRECTIVE:\n- INITIATE ALL TERMINALS\n  TO EXECUTE SYSTEM PURGE\n- REACH EXTRACTION POINT\nSECONDARY DIRECTIVES:\n- ASSIMILATE DATA SHARDS\n- PURGE HOSTILE ENTITIES",
    "ACTIVATE SYSTEM'S\nSALVATION OR WATCH\nREALITY CRASH.\n\nBARRACUDA AWAITS"
  }
end

function update_intro()
  _ic+=1
  -- slam cortex (f0), then override (f14)
  _xc=90*islam(_ic)-75
  _xp=135-90*islam(_ic-16)
  if _ic==14 or _ic==30 then _shake=4 sfx(20) end
  _shake=max(0,_shake-1.2)
  move_stars()
  -- logos dock at top -> reveal lore
  if _ic==76 then
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
  menubg()
  draw_stars()
  if sin(t())<.9 then circfill(63,64,3,2) end
  -- after slam, slowly dock the logos to the top
  local p=mid(0,(_ic-40)/36,1)
  display_logo(_xc,_xp,30*(1-p*(2-p)))
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
  if btnp(2) then _msel=(_msel-1)%5 _minfo.cc=0 sfx(19) end
  if btnp(3) then _msel=(_msel+1)%5 _minfo.cc=0 sfx(19) end
  if _msel>=1 then
    current_mission=_msel
    if btnp(1) and not _mshow_brief then
      _mshow_brief=true _minfo.cc=0 sfx(19)
    end
    if btnp(0) and _mshow_brief then
      _mshow_brief=false _minfo.cc=0 sfx(19)
    end
  end
  if btnp(5) then
    if _msel==0 then change_state("loadout_select")
    elseif armed() then change_state("gameplay") return
    else sfx(29) _mpanels[_msel].shk=5 end
  end
  if btnp(4) then change_state("intro") end
  _arm.sel=_msel==0
  for i,p in ipairs(_mpanels) do p.sel=i==_msel p:update() end
  _arm:update()
  _minfo:update()
end

function draw_mission_select()
  menubg()
  display_logo(15,45,0)
  _arm:draw()
  for p in all(_mpanels) do p:draw() end
  if _msel==0 then
    local s="ARMORY\n\nGEAR UP - REFILLS\nEVERY MISSION:\n"
    for w in all(wpns) do
      s=s.."\n"..w.name.." "..wstat(w)
    end
    _minfo.txt=s
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
      local y,c=49+(i-1)*6,m[i]==1 and 11 or 5
      ?lb[i],52,y,c
      ?(m[i]==1 and "■" or "□"),116,y,c
    end
  end
  -- view-toggle hint (missions only)
  if _msel>=1 then
    rectfill(94,101,120,108,0)
    ?(_mshow_brief and "\x8bSTATS" or "BRIEF\x91"),96,102,11
  end
  if _msel==0 then
    print_centered("\x8e OPEN ARMORY",64,117,11)
  elseif armed() then
    print_centered("\x8e DEPLOY",64,117,11)
  else
    print_centered("NO WEAPON-VISIT ARMORY",64,117,8)
  end
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
      p.txt=w.name.."  "..wstat(w)
      p.tc=(w.owned or credits>=w.cost) and (p.sel and 11 or 5) or 2
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
  print_shadow("CREDITS: "..credits,14,16)
  for p in all(_lpanels) do p:draw() end
  local act="\x8e CONFIRM"
  if _lsel<=4 then
    act=wpns[_lsel].owned and "EQUIPPED" or "\x8e BUY"
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
function wstat(w) return w.owned and "x"..w.mag or "$"..w.cost end
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
  "480,112,dERVISH|464,280,vANGUARD|408,320,vANGUARD|456,400,dERVISH|384,448,wARDEN|344,200,vANGUARD|264,408,dERVISH|72,144,dERVISH|232,200,dERVISH|64,280,wARDEN|120,280,vANGUARD|280,296,cYBERSEER",
  "16,144,dERVISH|112,160,vANGUARD|176,288,dERVISH|104,48,cYBERSEER|312,136,wARDEN|168,96,dERVISH|408,32,dERVISH|472,96,wARDEN|384,160,vANGUARD|392,312,qUANTUMCLERIC|464,248,vANGUARD|288,376,wARDEN|216,336,vANGUARD|304,320,vANGUARD|96,360,wARDEN",
  "240,416,wARDEN|88,336,dERVISH|160,368,vANGUARD|24,416,wARDEN|216,104,vANGUARD|256,40,dERVISH|296,72,dERVISH|136,80,cYBERSEER|32,88,dERVISH|32,32,dERVISH|40,160,wARDEN|344,344,vANGUARD|456,336,qUANTUMCLERIC|368,416,dERVISH|416,128,vANGUARD|344,136,vANGUARD|424,96,qUANTUMCLERIC|352,240,vANGUARD|432,264,vANGUARD|496,152,wARDEN",
  "368,408,dERVISH|248,408,dERVISH|184,424,vANGUARD|88,360,wARDEN|40,400,wARDEN|80,256,vANGUARD|16,280,cYBERSEER|16,208,vANGUARD|48,168,vANGUARD|176,296,dERVISH|176,360,dERVISH|248,304,wARDEN|400,344,qUANTUMCLERIC|336,344,dERVISH|200,192,wARDEN|264,200,wARDEN|376,192,wARDEN|472,184,cYBERSEER|480,256,vANGUARD|128,32,vANGUARD|120,104,vANGUARD|152,32,dERVISH|152,104,dERVISH|192,32,dERVISH|192,104,dERVISH|384,40,qUANTUMCLERIC|456,96,cYBERSEER"
}
_doors_m={
  "480,176,504,128,red|384,112,280,416,green",
  "312,256,440,56,red|296,256,200,48,green|328,256,56,376,blue",
  "392,280,144,224,red|184,0,160,392,green|360,168,320,408,blue",
  "144,0,392,280,red|112,0,40,304,green|176,0,472,272,blue"
}
_pspawn={"160,80","48,280","256,256","464,400"}
_tut1="112,48,MOVE: \x8b\x91\x94\x83|192,48,ATTACK: \x8e|40,-8,FRAGMENTS RESTORE HP|264,-2,WEAPONS MENU: \x97|368,-2,DEFEAT ENEMY"

function spawn_enemy(x,y,typ)
  local d=_et[typ]
  local e=entity.new(x,y)
  e.name=typ
  e.col=d[1] e.hp=d[2] e.mhp=d[2]
  e.atk=d[3] e.kv=d[4] e.wpi=d[5]
  e.ecd=0 e.ait=0 e.alt=0
  e.flash=0 e.max_speed=2
  add(enemies,e)
end

function init_gameplay()
  decompress_map()
  music(0)

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

  -- tutorial hints (mission 1 only)
  if current_mission==1 then
    for s in all(split(_tut1,"|",false)) do
      local d=split(s)
      add(terminals,terminal.new(d[1],d[2],nil,d[3]))
    end
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
      credits+=50 f.got=true sfx(7) pop(f.x,f.y,50)
    end
  end

  -- smooth credit counter
  credits_shown+=ceil((credits-credits_shown)*.3)

  -- weapon cooldowns
  for i=1,4 do
    if _wcd[i]>0 then _wcd[i]-=1 end
  end

  -- burst fire (machine gun)
  if player._burst then
    local b=player._burst
    b.t-=1
    if b.t%b.rate==0 then
      local aim={get_aim()}
      fire_single(b.w,aim)
      recoil(aim[1],aim[2],b.w)
      sfx(b.w.sfx)
    end
    if b.t<=0 then player._burst=nil end
  end

  -- plasma charge
  if player._charge then
    player._charge.t-=1
    if player._charge.t<=0 then
      local aim=player._charge.aim
      local w=player._charge.w
      fire_single(w,aim)
      recoil(aim[1],aim[2],w)
      sfx(w.sfx)
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

-- a terminal can be hacked if not done, not a
-- tutorial, and its door (if any) is still shut
function hackable(t)
  return not t.done and not t.tut
    and (not t.door or
      (not t.door.is_open and not t.door.opening))
end

function near_terminal()
  local px,py=player.x+4,player.y+4
  for t in all(terminals) do
    if hackable(t) and abs(t.x+4-px)<16 and abs(t.y+4-py)<16 then return t end
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
    if p.txt then
      ?p.txt,p.x,p.y+1,0
      ?p.txt,p.x,p.y,p.col
    end
  end

  -- extraction indicator (points to spawn)
  local cl=n_terminals()==0 and not _dead
  if cl and not _won then
    local a=atan2(player_spawn_x-player.x,player_spawn_y-player.y)
    circfill(px+cos(a)*20,py+sin(a)*20,1,8)
  end

  -- targeting reticle
  if _ptarget and not _dead and not _mg.active then
    local tx,ty=_ptarget.x+4,_ptarget.y+4
    for i=0,3 do
      local a=t()*.3+i*.25
      line(tx+cos(a)*6,ty+sin(a)*6,
        tx+cos(a+.25)*6,ty+sin(a+.25)*6,3)
    end
  end

  -- interaction prompt (hidden during minigame)
  if not _mg.active then
    local t=near_terminal()
    if t then
      local cx=t.x+4
      local iy=t.y-8+sin(time()*.7)*1.5
      ovalfill(cx-6,iy-1,cx+6,iy+8,0)
      ?"\142",cx-3,iy+1,11
    end
  end

  camera()
  draw_hud()
  draw_weapon_menu()
  mg_draw()

  -- extraction ui
  if cl then
    if _won then
      print_centered("extraction ready",64,50,11)
      print_centered("\x8e to evacuate",64,58,7)
    else
      print_centered("system purged",64,44,11)
      print_centered("return to spawn",64,52,7)
      print_centered("evac: "..flr(_evac/30),64,60,8)
    end
  end

  -- tutorial hints (mission 1): bottom panel
  if not _mg.active and not _dead then
    camera(cam.x,cam.y)
    for tt in all(terminals) do
      if tt.tut and dist_trig(tt.x-px,tt.y-py)<42 then
        tt.panel:update()
        tt.panel:draw()
        break
      end
    end
    camera()
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
  _mgf=20 _mgw=win
  if win then
    sfx(15)
    t.done=true
    if t.door then
      t.door.opening=true
      t.door.open_t=20
    end
  else
    sfx(29)
  end
end

function mg_draw()
  if not _mg.active then return end
  local cx,cy=64,64
  rectfill(cx-35,cy-20,cx+35,cy+20,0)
  rect(cx-35,cy-20,cx+35,cy+20,3)
  local sw=#_mg.seq*12-4
  local sx=cx-sw/2
  local cur=#_mg.inp+1
  -- single row: done(green/red), current(bob), upcoming(dim)
  for i,d in ipairs(_mg.seq) do
    local c,yo=5,0
    if i<cur then c=_mg.inp[i]==d and 11 or 8
    elseif i==cur then c=7 yo=sin(t()*2)*2 end
    ?d,sx+(i-1)*12,cy-2+yo,c
  end
  -- time bar (green->yellow->red)
  local tr=_mg.timer/180
  rectfill(cx-30,cy+12,cx-30+60*tr,cy+15,tr>.5 and 11 or tr>.25 and 10 or 8)
end

-- weapons: aim + fire
-- auto-aim: nearest enemy in range with sight
function update_target()
  _ptarget=nil
  local bd=80
  for e in all(enemies) do
    local d=dist_trig(e.x-player.x,e.y-player.y)
    if d<bd and los(player,e) then
      bd=d _ptarget=e
    end
  end
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
    local a=rnd()
    add(bullets,{x=px+cos(a)*15,y=py+sin(a)*15,
      vx=0,vy=0,life=w.life,sz=w.sz,col=w.col,
      dmg=w.dmg,aoe=w.aoe,aoe_dmg=w.aoe_dmg,
      orbit=w.orbit,orb_a=a,orb_r=5+rnd(10),
      spd=1,dir=a,mx_spd=3,own=src,plr=plr})
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
  w.ammo-=1
  local ax,ay=get_aim()
  _wcd[wi]=w.cd

  if w.burst then
    -- machine gun: first shot + burst for rest
    player._burst={w=w,
      t=(w.n-1)*w.burst,rate=w.burst}
    fire_single(w,{ax,ay})
    recoil(ax,ay,w)
    sfx(w.sfx)
  elseif w.charge then
    -- plasma: start charge
    player._charge={w=w,aim={ax,ay},
      t=w.charge}
  elseif w.homing then
    spawn_missiles(w,player,true)
    sfx(w.sfx)
  else
    -- rifle: instant fan
    for i=1,w.n do
      fire_single(w,{ax,ay},
        (i-1-(w.n-1)/2)*w.fan)
    end
    if w.recoil then recoil(ax,ay,w) end
    sfx(w.sfx)
  end
end

function recoil(dx,dy,w)
  player.vx-=dx*w.recoil
  player.vy-=dy*w.recoil
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
  local aim={dx/d,dy/d}
  if w.homing then
    spawn_missiles(w,e,false)
  else
    local n=min(w.n,3)
    for i=1,n do
      fire_single(w,aim,
        (i-1-(n-1)/2)*(w.fan or 0),e)
    end
  end
  sfx(w.sfx)
end

function update_enemies()
  for e in all(enemies) do
    local dx,dy=player.x-e.x,player.y-e.y
    local d=dist_trig(dx,dy)
    e.ecd=max(0,e.ecd-1)
    e.alt=max(0,e.alt-1)

    -- can see player? (within attack range + LOS)
    if d<=e.atk and los(e,player) then
      e.lsx,e.lsy=player.x,player.y
      e.alt=180
      -- attack: face + fire
      e.ai="atk"
      e.face_x=dx>0 and 1 or -1
      e.last_dir=abs(dx)>abs(dy)
        and "horizontal"
        or (dy<0 and "up" or "down")
      if e.ecd<=0 then
        local wi=type(e.wpi)=="table"
          and e.wpi[flr(rnd(#e.wpi))+1] or e.wpi
        enemy_fire(e,wi)
        e.ecd=wpns[wi].cd*3
      end
    elseif e.lsx then
      -- chase to last seen position
      e.ai="chase"
      dx,dy=e.lsx-e.x,e.lsy-e.y
      d=dist_trig(dx,dy)
      if d>1 then
        e.vx,e.vy=dx/d,dy/d
      else
        e.vx,e.vy=0,0
      end
    else
      -- idle wander
      e.ai="idle"
      e.ait-=1
      if e.ait<=0 then
        e.ait=30
        local a,s=rnd(),rnd(1)
        e.vx,e.vy=cos(a)*s,sin(a)*s
      end
    end

    -- forget last seen when alert expires
    if e.alt<=0 then e.lsx,e.lsy=nil,nil end

    -- direction from velocity
    if abs(e.vx)>0.1 or abs(e.vy)>0.1 then
      set_dir(e)
    end

    -- friction + physics
    e.vx*=0.9 e.vy*=0.9
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

    if b.orbit and b.orbit>0 then
      -- missile orbit phase
      b.orbit-=1
      b.orb_a+=0.02
      local s=b.own or player
      local px,py=s.x+4,s.y+4
      b.x=px+cos(b.orb_a)*b.orb_r
      b.y=py+sin(b.orb_a)*b.orb_r
    else
      b.x+=b.vx
      b.y+=b.vy
      -- missile scatter
      if b.mx_spd then
        b.spd=min(b.spd+0.05,b.mx_spd)
        b.dir+=(rnd()-0.5)*0.1
        b.vx=cos(b.dir)*b.spd
        b.vy=sin(b.dir)*b.spd
      end
      -- entity collision
      if not dead and b.plr then
        for e in all(enemies) do
          if bhit(b,e) then
            hurt(e,b) dead=true break
          end
        end
      elseif not dead and b.plr==false then
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
function n_terminals()
  local c=0
  for t in all(terminals) do
    if not (t.done or t.tut) then c+=1 end
  end
  return c
end
function n_fragments()
  local c=0
  for f in all(data_fragments) do
    if not f.got then c+=1 end
  end
  return c
end

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
  camera()
  local w=wpns[_wsel]
  local sx,sy=2,2
  if player.flash>0 then sx+=rnd(2)-1 sy+=rnd(2)-1 end
  -- health bar (white bg, colored fill) + readout
  local hp=player.hp/player.mhp
  local hc=hp>.6 and 11 or hp>.3 and 10 or 8
  hud_bar(sx,sy,80,5,7,hc,hp)
  print_shadow(flr(player.hp).."/"..player.mhp,sx+82,sy)
  -- cooldown bar (blue), below health
  local cy=sy+5
  hud_bar(sx,cy,80,3,1,12,1-_wcd[_wsel]/w.cd)
  -- weapon name + ammo, below bars
  local ac=w.ammo>0 and 7 or (flr(t()*4)%2<1 and 2 or 7)
  print_shadow(w.name.." ▶"..w.ammo.."◀",sx,cy+5,ac)
  -- credits
  print_shadow("credits: "..credits_shown,sx,cy+12)
  -- charge indicator
  if player._charge then
    print_shadow("charging",sx+54,sy,flr(t()*8)%2==0 and 12 or 7)
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
  -- hack result flash
  if _mgf and _mgf>0 then
    _mgf-=1
    print_centered(_mgw and "ACCESS GRANTED" or "ACCESS DENIED",64,60,_mgw and 11 or 8)
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
  local ix=(btn(1) and 1 or 0)-(btn(0) and 1 or 0)
  local iy=(btn(3) and 1 or 0)-(btn(2) and 1 or 0)

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
    -- big "preacher" enemy: 2x3 sprite
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
    if read_bits()==0 then
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
70427038607760dc003f300c300e120f028f81c701e3a0f160f038782c301e120f0a8f85c703e3a1f1e0f078784c302e121f028f89c705e3a2f161f0b8786c30
3e121f0a8f8d02aa0030003308717c03a476361b44e017081451e85c261a44ce05083641a05a214b40441a001608113902d8033096200167004b702381c07080
1090a4c0463508140cc20a810d00374870886d9428539cd17c080d868ab5502883180e40540f12cbede70801b9fc6e0f8dca80400816045302406c8d50c18040
6f0628d3c956f116050b6f35cce7c3e1f874391d2e0024a7d07802c905708200992e008cd60816b10eab6420cc534afe801561bc561a012415439be570428748
90e90a000fc98442c2112d214a06433cf5301b4709864f55905fe3f9f80f8d828642638cfd005c7885281c0985239ea3219a4017d214f13e673c1cc662814547
a8265c4b8464261381cc348354172a4b137181d442924c61d573819015f10ccee60e45d1e8c2048f8c48201060d1ae44021c0306c1422510c82c40889d0c803c
07a9813b9ce21430121819834902100f018f01c119880a3703b10ee81ddb833b9cc18d0608708c2802f07a80379a0beda768bb648cc860aad39bc51c024d7806
a80c29e19761ca9865e37400f1d82e7c8e64702ac6114e1da017d3794a430574014ee3c0904124c8098c9a945a3e4d00e32021f6e21c8164508e7d9c0a3c2240
2813e14a6b1b9d118503edf6092fbc101407f086749eae114ea769c7a922e6292b92434ab4816df608c5c102f11d7f3297aef166f67371f87c8ebf9c26a14ee4
79291822e664224000807c913308b504f3cc668b2341b1ede238a387428112180294704918cc7e40579384849809f02fcd91c0611638879cc3468b23e4214ed7
0e7df1b7288f8cd1326b668fc091ea10ff6017935c0438073623c839a4f82fb56814a4dd12885a2c93284898d138e91805c506f143a38370192b8440f6383ea9
5ef929cc96b612ec809e2433998e1cc19c60908f04017f40370354d982af241bc591ec95ffd09a3945281c077432d0e062274e94b21ce592cb230291b81d2885
d6228e3a48b4885407f7847e9d62652ec0d3142272f40572335d83ed06b74047b27cf35ae6236a93f8da946c806fe60810554ebc2d7889fd1d067da39208e7a4
dac021f39b074a9b2905deb1bfe897746306e12bb90646bfcc3b40b773b966462d78a684c73aed8d72c64c59a5101049738b7cc9ee6cb15004147810819043f8
9f31db924d4a65922d95dc18acf3996a535fd45db90b2cd352e04d989eb1da1bc4bda4903a1685eba40f7435c6538d5e82375ba4c0c23e0374a6c4126b2967b1
1adb15cf6c602e4f954d7d535b5aff200ee85d9da3d64c14c8dd74df7a0c5ddb5ef069afa559c1328ded03d02c4956c07f25b4bcdcf1ccbd37a1ab40c0c26b69
26a39b41beecc46eb79abb14f18eff0c3456b32d9b0ff608a0f58776ee6bfa82a9c011f95054e121d8d715ffc464a39044322ed750344fe070f015a7a91fc855
a0bf5f74ff4ab789cc608ff89b8e9061771bdfec451c77fd29d5e1aeae693718dbb10c09749f95092ced7674ffabf98932ff0bf8afd05a516df85f9420e0a51b
dc7b830f0221053f40c7ac1f56e10ee82d7a37c6f76a4ff81397db4ab996c399f8225dd0fe637e375c4998cde3e061742bdbda8cff58f35bdf89176099168750
5a3c2de87b46278319c8836a32611444c8543b3011c44c2052faaef86ef678397edd96e0bd02d25969fcf885725820f3a697e80330069e7cd52d75aaab768bb8
5bb5a6766b540e5a3b2e929957a102c74cd03f484e15b3be6738bb73aaf39a6b96b6007473addd63c4a7c60342350d8cc620d588ec50326b5e8cbc0c6928f3b9
a67b03f837108f7f2b460aaf5ecd8466dfc59abf666ef428f31ce1478f221ee78540ede67315d507e74339d2bd91b7d532ea1a0329e45238973e96e297f34418
1efa4cad0d61fe40c7f3aa9d6e15e2e606a4b17b504883f76d9f210078d89e127eb7709e5161f026f367fb221faeba37fb409b9b1843607ada11e9398c1d6c43
cd9d1f8df81976affcfbb0a890da766ffc87f94f60761958f40d3cfb1fa3017ba1b529d18c926dc2ef70338903cb5bb527c6748d1d4657280479d86ff5e67663
7f74b75edc5bd8d7a9c081ee259ea3cffa5a388e8769336b59ff327f938ceff4df716f2c12f137b0944de370cc93f857faaf474fab67233c893046b68e1bf477
1a4c17cf3429783380235d57ffff5124f31fe64c8d9d89f207701d1128035edd67c8623d7df6813fff6f615785b7851a9d66c2f86f980fb2cd90b934a770e471
e88f40bd5e58ce04f9f8d9a904f6a8099700384f9014c4e83ff5da751ba9a8ef475ec4c132ecef2839c883c7f0c86f02c9a70c62e68d71854448443aa7dc0484
d5fb822f71e580d89ff8cf5fffffffffffffffffcf28eb34f522fa197d9cb24e5b2fa69fd3c72aeb35f5a2fa597dbcb25e5b2fae9fd7c72ceb36f523fa997ddc
b26e5b3fa69fdbc72eeb37f5a3fad97dfcb27e5b3fae9fdfd720eb38f524fa1a7d1db28e5b4fa6afd3d722fb8f225249a050311b44e070a241a45c361b240040
c408980cc20aa20be00183aa004170520c89ac0b7222ca0029305c006032b9c0703010084a67030410d84689804930e020ba001e51044aec03e202cec0884575
082ec1e001228661c8110e0ce672b1dc6e3dc700cd1c40170310d00e34c700c0900018036106880b0b11066ff08434f310f0708f81908fade773f90e40622045
114eedb7d3e1d87a8a109aee809e101128800c04f8057433c4c348feb04be01cd3f87e39ccb04c0fd4f2040df40dd231c0320efa401728917116e1548ed1c111
6da05ca020082761180a1dce630155e0403049dc7e8822984e0fd6c30401f403093140530e1d4047731cd0906a8e00c0118ded40081a3cc598036d86321b062c
e73827144918077931cf534e0d16180f391a00768a22c8a28c90d047e22cc868015482c290085eb13dd81b5cc9ec13e4329f6ee07c6029d03c4716fa1576224f
9544abe671b0bc0d598332ca32a8802c0373348ad46e8b2ecbb66d926c87d31459224072394d954f5f703ef1f01eab688f324b834416a12db894645e26e015f1
2544536c705ca01cc3c8907c8a2998cb0c9428d34c87dc1b0286bfc8e525f3322143f81e5c0c4aa1248c3bca320e2fd53895b1c803f88c3d4164ece19a321fb8
ac10424a15eb939419ca90c135e1ac1326e37488bc9147d9611f689b6916f129d091b3c910a8808e16d8aeb146c06a329128806e2782cc00ac489c73116e53ae
8728a3a156f0648f91ca3a2505aef6d83eb12ec51fe62249e8ac66288403a4815ea62d6491f2c011ee269c136928a30c542ece3f229238499ca4863c82204914
c44056c17689f81dca1c0090532c100232662cc40561564087991aa194117f92ebc17d6cb64af649d3618c0100221381885412118060334087c47b007e082071
32010b8f94f590a6e04c0738b8b102cc088700d7a18c7e4037934102100b41916959406c67aa94382b01801bc7821c4191e8801fc32d23419a685223d912888d
f6733ca91e4b6caf600321637ce45d931cc1ec457cabf491c0fd00b0d078824f492835872c9305a7d314290a2e4d7ca93712ae00f140474a2114f1d00f16ab57
d1f14ee0c3611cd10c780a4241e3e73a10522071940db6afa74a5c6efa24d14a9d143a18068c478b0cfdd442ba80b9167f075fa8badcf6cc8e07eaab5cb84269
0294a891ebc6b871fd0b0d09ba65157fbc301989d8226d08c289cc0294f552210d5c629318b309c6884684bf5d726d423c851760b8469a25b43355398490b543
aa3badd04ebf208a32df482994206792bd82e60254938859d980ac7528f3c106992e8a3bcd290a6840c9a7adc666c753c0234169a811de07365249e28e7b0892
a79323a1dfe64be0a9d05fc2b2b5596948bd643520b50f140b7436d83de8fea606c84ad5e3dec30bf8379fae2e48402895750ed47de131d7eaa8fcd8071c51d5
cebee54746aa784dbecea376f3b508e6a85593b299994ecf257b1b54d9b6c30974a4a7534dc0fde5a7306ca1785833dfaf25b894b72ff3a9b86080f80b679b37
d25aba3b05fd0fcf7a24118178421b120c41846c8620c02080be326f9315a0987d4cb42e4c32f7819e093c5c914602e62845c736c79fca9da640eb220e53b402
97b2e7d031f154841b92cce8d8689f3f53b6bd3154c754721691d40497a46f31651903400821c810081c8523a8bbc7648b23b1cafe9379058ab55272132a731d
908ee83a008deaa93c9644501c93987b4ccaa249118fa4629cb475e402493c005ef24961b2511dc21f62774c87321a62a1efa29ca741dc0f8d0b52f10d1f3497
535edaf6881b76bec19526cbfbd6212c0b8d56866997bbb42e138eb911ff4b41698efc7fcd316fd5c43baa5d49d3fd51b845049ff1cb1fe529aa74ec13b98ca5
5f35e8297d108b96185de6c14a2f7c3366f506fe3b47b289f4af7922697889ec0673b90ef866cf739d2b185107289d8de99ef66698cde85a485daa6ec281d00f
00ce731ffbe037775e9dc7d1b2c976b5795b7fe12c29c69dff346df445f61605aaa8f958630b687963f78350d33cc1cab48670fa1d28f31f9773c05775954e5b
7545993bafcd23206fe102ecf0c1fbbc1888c31bbe1f577bc9c74a954efd924efc2b3d633862097324017e91a8f54eb273397fe77eb1e417f039760b3bf31093
6976deb74d110dbb7b3568191c817ee2038cb82787f12888a7c306d3f8a7faaac9e97ebde956b813e91f2ee123035433f2f50997ac5673e91353563d671e0f91
3b4ef9c4e91bf021d3311fcf5dac960a57be5867f7d37312e5fc29c8546133ee10f9230c6e379fceeda6db5f1ccc1a32b9f39957093776acb068895c0b8b4ab7
51f3a4887f9c2886fe09cc15a38fc76a344f57b0db28e49cb7ece95a6db7e3048537d2ec400ccb85cfe423cc1515fd9b9a9627f3f1dfa076ded791cb90acb72d
7cbe731f7245e9dfb7cdab3e6689a20870df1f92d3af7fdc4ae76df3d6f17bf8cd74ee367f15bf8bdf4ee76ff3d7f1fbf80e740f368f15cf83ef42f761f3d8f1
7cf84e742f369f15cf8bef46f763f3d9f1fcf88e744f36af15df83ef4af765f3daf17df8ce746f36bf15df8bef4ef767f3dbf1fdf80f748f36cf15ef83ff42f7
69f3dcf17ef84f74af36df15ef8bff46f76bf3ddf1fef88f74cf36ef15ff83ff4af76df3def17ff8cf74ef36ff15ff8b0e5249a052361b05ba0025080349a00d
b08150410040aa1508b43150050027c550883a2010820418a4019027162800c074630442e470304000e330acb642180e00148d20c190ec40fb203028c381d00f
003a4d006010ec400800b9cc400996ed809e001518830c0408688da0988bdd3010630c18d40f0282329c8b6fe4d30410d87e8a004411ad118e1730f8100b7434
1d6b5082d4f2040c0ec105748c249047d9806b81201c068c92c392c80c9668cb21c003ca83329a6b8098b03b18004cd70ee3688f6413cb63b268073812726230
4574ecd2362125438102e81b50234f114d7f2030b8b30cc7dc0fea2396a31040b0889a70127b6231c4110e194047e22c15d00f028a744c114dc5f2f271d44c8e
74c9114a2fe748a7c136064837c08540d94140888e3936e1443d4700e0112f74789bb10e48321ecfa6a4d05040a528b37c1e16e1075d826dc8c144abe5081371
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
a280a6a847e45054df0b0890519f8f27a8d7b4901223e70b1190c09360e2921f392819b09311fb833197a3e850f823cc8090fd29c2214a084866c24c594c1a3d8b3c424ccdb0476301888100012e459ec9b0a4490b10c219c87a8fe8c08c4832c932217235ad2d612c46bd09b1ab29129490ce2362598e59cc5de03e47b2f1ea
42cc6f3c9e0f30462158ae1a0d31580392ce71f73940141c5623e725c23b9c455317a36cc65a5da47a3c4694837047638c11ea70c26c379be59cd14c592e187611f24735ce8e8e1114288a89c227e708f81e0b60a073865838d1ecdd2ec2823d16e258445209988d000122401ca3cc9008133100b80786c69a262c8308005980
b5376288fc0aa20b703c915402aa59d3002b97609aa2cf7047f823fc7e120003047f9d1996a280708fa81418f633f071847fc59d694d94a93a4e09280f047f38c106a1b1f04768c7254de0d66fa063c47ee2396718905c166631c518c18bf8c62c48046962918cc14c3334c11fe2c9f168e923a583c6c00960d12a581c8e7047
42d435f8e31acf8907d7b0caf5e7c3652d08c311ffb0829c60e6f68752645b3c867e379fcff0021b01b459de47f20d8d64922cb6d6872b389c6cf8fd240a021ea8a887191ffc2edad0627e83a959c8e7515047d0257854f508ff1548e2c867eb393c11ee75ea5337c188edac604b78a984932cff9a5c9e0f17096a1c48b259a4
2da3f94f3ee49086c823fc11eed887698581ea5e55ae0c20d9e7891677c24380189167a23245380099726bff6143a3629e608c630b5cb076783f3cbca6facfbea61d510313cc23dad7270852154da7e08ff437fac1b1fae93b86d10a85a65fd3cb8847f81e5eac559771d2a0e08f8251301e081f527706e22ce98f37bd4c8296
410e5dc58ae1186128f0d2a2ca2a98b66fbf45fc823f180df2175c479d4d13283352afa9bed55e43b7c1223d4db2e931047625e7a9333479f57d049e75f4557bd5c6e9012fb347f847e67ed0c05296991c2998da097cebcc11e727ad3d32823c0f05b2844cfda1fee4847fd01ccc7973af37bd7cc3a012ff897d97ba64662caf
6267999a182e7e2f9e52184d8cacef62ac9290ac187abfe35f662f29198b5c21a02c560cb19e411f455925115872030d5aac9ac159d1a85ad7b320659eece5317c15423e493636dbf2211cc3ac89824602efa922a85cb423dce5bdf6aac2549dcc1047b0e0720a9404823fe9754de6baabb6f2980f11fb86cb6a1e725020c15d
f7f4b06037ecd6770550476d9da010f5000f8971e09f659fbc12606d329f31653bd4dd388126fc95ec98bb8dafee08ea04c02e9275e2f7dca823a7221f836b167edfa881309bc69de4b9c6fb8d7dd5e8da1acdfc848a1bcc645409047fe094df7048b96a3beeb5688afbc27f9c6a9bfa9930477e9dd8c38251953ccb5c15e49e
fafb2847ee896712255e93aac4667283b8d98219fcf1cc862cc59f6caa44585d1e244a11ea0be7529c73cb196bc03cec8809cc842d5e5ffc80ddf6297826d06ee1222ab1c1668737eed8732b5ffdcdc4efe433f1f1799cf71387703d69af6aa6533fde90bbd09047fdb7c6d39cd849d5ef6b46af4687030729f00e2a800616c8
11e25e4094062a049f9e392e7da7fef3ff89ffccffea7ff73ffc9ffecfffa7fff3ffe5fffafc2ffe19ff0dff877fc3ffe21ff11ff897fc4ffe29ff15ff8b7fc5ffe31ff19ff8d7fc6ffe39ff1dff8f7fc7ffe41ff21ff917fc8ffe49ff25ff937fc9ffe51ff29ff957fcaffe59ff2dff977fcbffe61ff31ff997fccffe69ff35
ff9b7fcdffe71ff39ff9d7fceffe79ff3dff9f7fcfffe81ff41ffa17fd0ffe89ff45ffa37ffefdc0038aa000a4b281d8aa5128144ac762a154a100023b40104ab00658038c040a0322568008c064a03e85580b24088a04844c3040018540780029a0d86038404cce10054805b180c1006a80631c202766b24c11de08cc072418
0df0001369be001300bb80afc09a0c1047f0391cc27e3d1e8da7a8002134bc7a805ac12b20369021680fac1e44c269847d1c61b465730411c4f25d27423ea08e66c860cc11fe0ce908ff892110cde783c9ea0e946f27409ccc440800298cc108f5834cc11fe120e073cc119e1ac87a8299c3fc8971bd38cb091cc10da637c361
e0ce8618b3e9c608ea7e36c40e49a4e84e1451c88f1c738cb091cd719c2371b89d0ee380d1407ce0ce911ff8fe91e0f06f2e9b85c2f37400ca2e2300718058c000a08e4608cb216e1b4a6d81121b603c45e2ec154e35ff2442299e4f07f8d888f87f0039847ac83c4f71de1394369623c26f81119b603cc6d8fbe44754b11af1
3c1be3dca6d8451178f5047534c460a4aa30d41381ae1327134490e097603cc6d88ffcb3ce47e67f823a9ea2cf26a8b0148350c1047592909b8bd01e836c47f659ef0257946a9bc9b120230c23c8f40b369ea132d2a2394b4407c4bd1f7f98ba1fa03292be936c23d8162b2e93a132d2cfb80fac23fe6be26137cc59cdb31c88
6ba06c3932f237c264cdc6e86a3cc894df23ff98c91a0c139ae369be22b00402436c625293b2f9d3d51f8a74ea6ba13e50c98d9047686d8c5c48d744bf80f9d0de6902a5b9a43104cc4033400cc893581234d6c8b908f50d8ae5149018680fdc11fc0e643b1d8cb4d3125d3ee6000a7386baca292a5ab5195810313211ff3ef2
3d9a81a0d9a7153eea1b4927a4379aea1b75208a87d8aa6bec7e3f1aa90c51b613f5460a3d622b06547e24807520fa9cb4e9ec554ca6aab89aa90c67fa7c1c43c4561ca20440344db47a53d48f32a5c6608b3fce9ca08eb48613c479ca3d2304628f7101256a500d33d1e8f500683d40352944b1f7f9d399fcfe6aa67340e6a7
605047f02012b47159fd967b1fa11ee7897edd772226475e9dacffdb04ca91df13fc47d0a67eaaf9442b2c8cd1325899c435fec5a864b8191b22ce9486137d33c6222911883d447ea25ae6f89a2012d7fe68b8189fe3dc31f7116c378ecfc3117388c21ee2c167a896c82c1701a28081dc1f8cf045191e8c35c8780da1f11fed
db20b0603222666d37c4bf6254f7371a63f423c8c44123198eb5163bcf09fa95912463bd715c7ae02d37773bcbd0b261820d86b89fce4513b14ccb7e63304c63e021f82169099d9de81a3d88fa43544fe6f98b9cfd9c813d5c8087dd7ce2dc97dfe82394480cd53ef3c8109571d233f49c88895b22a5917628e414ca101f2baf
9812fbff90113a5cccf16e2698720920d98efd3863dea1a9459c4f0c7e8f16ff94b1226020a7de30e4123c59ce7e2554a1180ae2c8b91239b810c200a992220e45e4ad1c756b11861bfebceb35f134e2f930ec539641806c3938f7ad0886c603098e264884607aafa29be08c230375f7ef0dab47828239e2f84f135f2ca728c0
1700659ab206e08e527d1a4a88c210cb7ae38478ca1fe5a6a7ea1ba50d86120b2842181ea0912048209411ca1aa230bb33cc6cf3afda6c3341fa08ed94d13c4ad5861097b848157b44393111065d714d762ff82326ad48cf047786bb82c3908f7a5a2c4850374e3206631d25fe24422916c5f3b0229688c23d286ed9de3b7c9c
444a688b1b9181d155ace1ce7047215cf988d3ae671557ca83b2435aef89d6a2c942a58b31d2e164023099182c34120e000342e2356831e08f17281256f456fcce048d6c0703704760e56422a9d1bbd33bc11f61471bd643055f9e47c27bba28c45e248cd5de7355e1945508fb24c11ec90600241226b2072d82a88beaa621ae
9b76588fc072146871deb4d83e65a0b0475e077c59fcc105b503e65b6c5d728c5decd1c310c7b2e7823c98623fdb3523f728ae74047a3def64ea60446c43154dc6a70388618fbfc16e22cf07e3d9bcd9d2dce2ca1be31d6718cccc8fe08105b9d7f2e09ca0f659016c83118cc111273bc762f26c62a943d4183b7fe4708516e6
a1a22482a84558542c07823e0aa47f65bcc71662c4b9d4d638e6a1623285c814f01c4a26823ec07ba019e0788bf417de1afe7789efce05e659315cf03c59ffb8f7094f1501f2c530b0f8b656bdea005e2a9dc44073e059ff6c2b94fdce7ee93f759fbb4fdde7ef13f799fbd4fdee7ef93f7d9fbf4fdfe7f013f819fc14fe0e7f
093f859fc34fe1e7f113f899fc54fe2e7f193f8d9fc74fe3e7f213f919fc94fe4e7f293f959fcb4fe5e7f313f999fcd4fe6e7f393f9d9fcf4fe7e7f413fa19fd14fe8e7f493fa59fd34fe9e7f513fa99fd54feae7f593fad9fd74febe7f613fb19fd94fece7f693fb59fdb4fede7f713fb99ffdfb8774003e021f020f8187c10
3e0a1f060f8387c203e121f0a0f8587c303e1a1f0e0f87840fa1f483380010f9c6ee19b8e010900d28042c03a6046f01a8811cbb87c3381fb4021e07ff03ff8246c1d49dc33841141b4a0cc70955838241fca134519b78041c1b4e1169017985d1403d616c50a4f81fa42fe207ef0ec38212c0ecc7d0dc381fac020e07fe3e81
ffc0ffe07f50bc88689c454a17e70d3983fcc0a5217fb17f58c43c544e318502a58bffc151a1d9113f48df9c723617271ce28cf1c6ffe36270ff78101c5da242b316478bec4c87602db03ff80934968a3a33275f9b8fce07e0cff3a1f9d8fcf07e133f3e1f9f8e80000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
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
