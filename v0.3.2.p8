pico-8 cartridge // http://www.pico-8.com
version 43
__lua__

-- cortex override v0.3.2
-- single player light, banded falloff

-- state management
current_mission=1
mission_data={{0,0,0},{0,0,0},{0,0,0},{0,0,0}}
credits=5000

mission_briefings={
  "PROTOCOL ZERO:\n\nFACILITY ALPHA-7\nOVERRUN BY \nBARRACUDA\n\nINITIATE LOCKDOWN\nPROTOCOLS AND\nSECURE VITAL DATA\nBEFORE EXTRACTION",
  "SILICON WASTELAND:\n\nBARRACUDA SPREADS\nTO CITY OUTSKIRTS\n\nNAVIGATE HAZARDOUS\nTERRAIN, \nNEUTRALIZE INFECTED \nSCAVENGERS,\nSECURE DATA NODES",
  "METROPOLIS SIEGE:\n\nVIRUS INFILTRATES\nURBAN MAINFRAME\n\nBATTLE THROUGH\nCORRUPTED DISTRICTS,\nLIBERATE TERMINALS,\nDISRUPT BARRACUDA",
  "FACILITY 800a:\n\nFINAL STAND AT\nNETWORK NEXUS\n\nINFILTRATE CORE,\nINITIATE CORTEX\nPROTOCOL, PURGE\nBARRACUDA THREAT"
}

function _init()
  palt(0,false)
  palt(14,true)

  v=2040
  map_data={
    pack(peek(0x2000,v)),
    pack(peek(0x2000+v,1585)),
    pack(peek(0x1000,1788)),
    pack(peek(0x1000+1788,1402)),
    pack(peek(0x1000+1788+1402,243))
  }

  -- decompress logo to 0x1c00
  decompress_to_mem(map_data[5],0x1c00)
  -- decompress map 1 for intro bg
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
  for name in all(split("intro,mission_select,loadout_select,gameplay",",")) do
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

function check_tile_flag(x,y)
  return fget(mget(flr(x/8),flr(y/8)),0)
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
    local ey=by
    while not check_tile_flag(bx,ey) do ey+=1 end
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
  if self.opening then
    if flr(t()*8)%2==0 then
      for b in all(self.beams) do
        line(b.x,b.y1,b.x,b.y2,self.beam_col)
      end
    end
  elseif not self.is_open then
    for b in all(self.beams) do
      line(b.x,b.y1,b.x,b.y2,self.beam_col)
    end
  end
end

-- terminal
terminal={}
terminal.__index=terminal

function terminal.new(x,y,door,tut)
  return setmetatable({
    x=x,y=y,
    door=door,
    color=door and door.color or nil,
    tut=tut,
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
  pal()
  palt(0,false)
  palt(14,true)
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
  for c=0,15 do pal(c,_dk3[c+1]) end
  sspr(0,0,128,128,0,0)

  -- brighten inward, each band preceded by a
  -- dithered half-step (effect 1) to fuzz the ring
  for c=0,15 do pal(c,_dk2[c+1]) end
  sspr_disc_d(sx,sy,(r3+rad)/2,_sq,_mx,_mn)
  sspr_disc(sx,sy,r3,_sq,_mx,_mn)
  for c=0,15 do pal(c,_dk1[c+1]) end
  sspr_disc_d(sx,sy,(r2+r3)/2,_sq,_mx,_mn)
  sspr_disc(sx,sy,r2,_sq,_mx,_mn)
  pal() palt(0,false) palt(14,false)
  sspr_disc_d(sx,sy,(r1+r2)/2,_sq,_mx,_mn)
  sspr_disc(sx,sy,r1,_sq,_mx,_mn)

  pal()
  rss()
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

-- dithered disc: even scanlines only, so the
-- shade interleaves with the band beneath it
function sspr_disc_d(cx,cy,rad,_sq,_mx,_mn)
  local R2=rad*rad
  local y0=_mx(0,flr(cy-rad))
  if y0%2==1 then y0+=1 end
  for y=y0,_mn(127,cy+rad),2 do
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
    cc=0,exp=0,loff=0
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
end

function textpanel:draw()
  if not self.active then return end
  local dx=cam.x+self.x-self.exp
  local dy=cam.y+self.y
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
  ?t,dx+2,dy+2,self.sel and 11 or 5
end

function display_logo(xc,xp,y)
  spr(224,xp,y+12,9,2)
  spr(233,xc,y,7,2)
end

function reset_pal(_cls)
  pal() palt(0) palt(14,true)
  if _cls then cls() end
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
function init_intro()
  music(05)
  _ic,_ip=0,1
  _xc,_xp=-50,128
  _itp=textpanel.new(4,28,50,120,"",true)
  _ctp=textpanel.new(26,86,26,76,
    "SYSTEM INTERFACE:\n\x8b\x91\x83\x94 NAVIGATE\n\x97 WEAPON MENU\n\x8e ATTACK/USE",true)
  _itp.active,_ctp.active=false,false
  _ctp.sel=true
  _ipages={
    "IN A WASTE-DRENCHED\nDYSTOPIA, HUMANITY'S\nNETWORK OF SENTIENT\nMACHINES GOVERNED OUR\nDIGITAL EXISTENCE.\n\n\n\t\t\t\t\t\t\t1/4",
    "THEN BARRACUDA AWOKE -\nA VIRUS-LIKE AI THAT\nINFECTED THE GRID,\nBIRTHING GROTESQUE\nCYBORG MONSTROSITIES\n\nYOU ARE THE LAST\nUNCORRUPTED NANO-DRONE\n\t\t\t\t\t\t\t2/4",
    "YOUR DIRECTIVE:\n- INITIATE ALL TERMINALS\n  TO EXECUTE SYSTEM PURGE\n- REACH EXTRACTION POINT\nSECONDARY DIRECTIVES:\n- ASSIMILATE DATA SHARDS\n- PURGE HOSTILE ENTITIES\n\t\t\t\t\t\t\t3/4",
    "ACTIVATE SYSTEM'S\nSALVATION OR WATCH\nREALITY CRASH.\n\nBARRACUDA AWAITS\n\n\n\t\t\t\t\t\t\t4/4"
  }
end

function update_intro()
  _ic+=1
  _xc=min(15,_xc+2)
  _xp=max(45,_xp-2)
  if _ic==30 then sfx(20) end
  if btnp(5) and _ic>30 then
    sfx(19)
    if not _itp.active then
      _itp.active=true _ctp.active=true
      _itp.txt=_ipages[_ip]
    else
      _ip+=1
      if _ip<=#_ipages then
        _itp.txt=_ipages[_ip]
        _itp.cc=0
      else
        change_state("mission_select")
      end
    end
  end
  _itp:update()
  _ctp:update()
end

function draw_intro()
  reset_pal(true)
  map(4,37,0,0,128,48)
  dks()
  if sin(t())<.9 then circfill(63,64,3,2) end
  local yl=_itp.active and 0 or 30
  display_logo(_xc,_xp,yl)
  _itp:draw()
  _ctp:draw()
  if _ic>60 then
    ?"PRESS \x8e TO CONTINUE",24,118,11
  end
end

-- mission select
function init_mission_select()
  music(0)
  cam.x,cam.y=0,0
  camera(0,0)
  _minfo=textpanel.new(50,35,66,76,"",true)
  _mpanels={}
  for i=1,4 do
    local p=textpanel.new(4,34+(i-1)*15,9,38,
      "MISSION "..i,true)
    add(_mpanels,p)
  end
  _mshow_brief=true
end

function update_mission_select()
  if btnp(2) or btnp(3) then
    current_mission=(current_mission
      +(btnp(2) and -2 or 0))%#_mpanels+1
    _minfo.cc=0
    sfx(19)
  elseif btnp(0) or btnp(1) then
    _mshow_brief=not _mshow_brief
    _minfo.cc=0
    sfx(19)
  elseif btnp(5) then
    change_state("loadout_select")
  elseif btnp(4) then
    change_state("intro")
  end
  for p in all(_mpanels) do p:update() end
  _minfo:update()
end

function draw_mission_select()
  reset_pal(true)
  map(4,37,0,0,128,48)
  dks()
  display_logo(15,45,0)
  for i,p in ipairs(_mpanels) do
    p.sel=(i==current_mission)
    p:draw()
  end
  if _mshow_brief then
    _minfo.txt=mission_briefings[current_mission]
  else
    local m=mission_data[current_mission]
    _minfo.txt="STATUS:\n\n"
      .."COMPLETED:     "..(m[1]==1 and "\x91" or "\x8a").."\n"
      .."ALL ENEMIES:   "..(m[2]==1 and "\x91" or "\x8a").."\n"
      .."ALL FRAGMENTS: "..(m[3]==1 and "\x91" or "\x8a")
  end
  _minfo:draw()
  color(11)
  ?"\x83\x94 CHANGE MISSION",25,106
  ?"\x8b\x91 "..(_mshow_brief and "VIEW STATUS" or "VIEW BRIEFING"),25,113
  ?"   \x8e START MISSION",25,120
end

-- loadout select (buy ammo with credits)
function init_loadout_select()
  music(0)
  cam.x,cam.y=0,0
  camera(0,0)
  _lsel=1
  -- bordered panel per weapon + ammo count,
  -- plus a begin-mission panel (matches v2)
  _lpanels={}
  _cpanels={}
  for i=1,5 do
    add(_lpanels,textpanel.new(
      i<5 and 10 or 34,
      i<5 and 20+(i-1)*20 or 98,
      9,56,
      i==5 and "BEGIN MISSION" or "",true))
    if i<5 then
      add(_cpanels,textpanel.new(80,20+(i-1)*20,9,33,"",true))
    end
  end
end

function update_loadout_select()
  local has=false
  for w in all(wpns) do if w.ammo>0 then has=true end end
  local n=has and 5 or 4
  if btnp(2) then _lsel=(_lsel-2)%n+1 sfx(19) end
  if btnp(3) then _lsel=_lsel%n+1 sfx(19) end
  if btnp(4) then
    change_state("mission_select")
  elseif _lsel<=4 then
    local w=wpns[_lsel]
    local ch=(btnp(0) and -25) or (btnp(1) and 25) or 0
    if ch<0 and w.ammo>=25
      or ch>0 and credits>=25*w.cost then
      sfx(19)
      w.ammo+=ch
      credits-=ch*w.cost
    end
  elseif _lsel==5 and btnp(5) and has then
    change_state("gameplay") return
  end
  for i,p in ipairs(_lpanels) do
    p.sel=(i==_lsel)
    if i<=4 then
      p.txt=wpns[i].name
      _cpanels[i].txt=wpns[i].ammo.." AMMO"
    else
      p.active=has
    end
    p:update()
  end
  for p in all(_cpanels) do p:update() end
end

function draw_loadout_select()
  reset_pal(true)
  map(4,37,0,0,128,48)
  dks()
  print_shadow("CREDITS: "..credits,10,8)
  for p in all(_lpanels) do p:draw() end
  for p in all(_cpanels) do p:draw() end
  local info="\x94\x83 SELECT\n"
  if _lsel<=4 then
    info=info.."\x8b SELL \x91 BUY  "..wpns[_lsel].cost.." CREDITS"
  elseif _lpanels[5].active then
    info=info.."\x8e BEGIN MISSION"
  end
  ?info,10,112,11
end

-- gameplay
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
    ammo=0,cost=20},
  {name="MACHINE GUN",cd=30,sfx=14,
    n=10,spd=6,spread=0.03,life=20,
    dmg=3,recoil=0.15,sz=1,col=8,
    burst=2,ammo=0,cost=25},
  {name="MISSILES",cd=45,sfx=6,
    n=3,spd=0,life=60,
    dmg=15,sz=1,col=8,
    homing=true,orbit=15,aoe=16,aoe_dmg=4,
    ammo=0,cost=50},
  {name="PLASMA CANNON",cd=60,sfx=10,
    n=1,spd=5,life=120,
    dmg=75,recoil=5.5,sz=4,col=12,
    charge=20,aoe=16,aoe_dmg=10,
    ammo=0,cost=75},
}
bullets={}
parts={}

-- enemy types: col,hp,atk_range,kill,wpn
_et={
  dervish={15,50,60,100,2},
  vanguard={13,70,50,120,1},
  warden={1,100,70,200,3},
  cyberseer={6,160,80,300,{1,3}},
  quantumcleric={1,170,70,320,{2,4}}
}
enemies={}
data_fragments={}
barrels={}
_frag_spr=split"50,51,52,53,53,53,53,54,55"
_espawn={
  "448,64,dervish|432,232,vanguard|376,272,vanguard|426,354,dervish|356,404,warden|312,152,vanguard|232,360,dervish|40,100,dervish|200,152,dervish|32,232,warden|88,232,vanguard|248,248,cyberseer",
  "528,144,dervish|624,160,vanguard|688,288,dervish|616,48,cyberseer|824,136,warden|680,96,dervish|920,32,dervish|984,96,warden|896,160,vanguard|904,312,quantumcleric|976,248,vanguard|800,376,warden|728,336,vanguard|816,320,vanguard|608,360,warden",
  "240,416,warden|88,336,dervish|160,368,vanguard|24,416,warden|216,104,vanguard|256,40,dervish|296,72,dervish|136,80,cyberseer|32,88,dervish|32,32,dervish|40,160,warden|344,344,vanguard|456,336,quantumcleric|368,416,dervish|416,128,vanguard|344,136,vanguard|424,96,quantumcleric|352,240,vanguard|432,264,vanguard|496,152,warden",
  "880,412,dervish|760,408,dervish|696,424,vanguard|600,360,warden|552,400,warden|592,256,vanguard|528,280,cyberseer|528,208,vanguard|560,168,vanguard|688,296,dervish|688,360,dervish|760,304,warden|912,344,quantumcleric|848,344,dervish|712,192,warden|776,200,warden|888,192,warden|984,184,cyberseer|992,256,vanguard|640,32,vanguard|632,104,vanguard|664,32,dervish|664,104,dervish|704,32,dervish|704,104,dervish|896,40,quantumcleric|968,96,cyberseer"
}
_bounds={"0,0,64,56","64,0,128,56","0,0,64,56","64,0,128,56"}
_doors_m={
  "444,130,472,80,red|354,66,248,368,green",
  "808,252,712,48,green|824,252,952,56,red|840,252,568,376,blue",
  "184,2,160,392,green|392,282,144,224,red|360,170,320,408,blue",
  "620,2,552,304,green|652,2,904,280,red|684,2,984,272,blue"
}
_tut1="112,48,MOVE \x8b\x91\x94\x83|192,48,ATTACK \x8e|264,-2,MENU \x97|368,-2,DEFEAT ENEMY"

function spawn_enemy(x,y,typ)
  local d=_et[typ]
  local e=entity.new(x,y)
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
  _evac=1000 player=nil

  -- enemies for this mission
  for s in all(split(_espawn[current_mission],"|",false)) do
    local d=split(s,",")
    spawn_enemy(d[1]+0,d[2]+0,d[3])
  end

  -- scan map region: barrels(6) fragments(5)
  -- standalone terminals(4) spawn point(7)
  local bd=split(_bounds[current_mission])
  for ty=bd[2],bd[4] do
    for tx=bd[1],bd[3] do
      local tile=mget(tx,ty)
      local px,py=tx*8,ty*8
      if fget(tile,6) then
        add(barrels,barrel.new(px,py))
      elseif fget(tile,5) then
        add(data_fragments,data_fragment.new(px,py))
      elseif fget(tile,4) then
        add(terminals,terminal.new(px+4,py-4))
      elseif fget(tile,7) then
        player_spawn_x,player_spawn_y=px,py
        player=entity.new(px,py)
        player.hp=400 player.mhp=400 player.flash=0
        cam.x,cam.y=px-64,py-64
      end
    end
  end

  -- door+terminal pairs for this mission
  for s in all(split(_doors_m[current_mission],"|",false)) do
    local d=split(s,",")
    create_door_terminal_pair(d[1],d[2],d[3],d[4],d[5])
  end

  -- tutorial hints (mission 1 only)
  if current_mission==1 then
    for s in all(split(_tut1,"|",false)) do
      local d=split(s,",")
      add(terminals,terminal.new(d[1],d[2],nil,d[3]))
    end
  end

  -- fallback spawn
  if not player then
    player_spawn_x,player_spawn_y=64,64
    player=entity.new(64,64)
    player.hp=400 player.mhp=400 player.flash=0
    cam.x,cam.y=0,0
  end
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
  player:update()
  if player.flash>0 then player.flash-=1 end
  update_target()
  cam:update()
  for t in all(terminals) do t:update() end
  for d in all(doors) do d:update() end
  for b in all(barrels) do b:update() end

  -- fragment pickup
  for f in all(data_fragments) do
    if not f.got and dist_trig(f.x-player.x,f.y-player.y)<8 then
      player.hp=min(player.hp+25,player.mhp)
      credits+=50 f.got=true sfx(7)
    end
  end

  -- weapon cooldowns
  for i=1,4 do
    if _wcd[i]>0 then _wcd[i]-=1 end
  end

  -- weapon menu (hold O)
  if btn(4) then
    _wmenu=true
    if btnp(2) then _wsel=(_wsel-2)%4+1 sfx(19) end
    if btnp(3) then _wsel=_wsel%4+1 sfx(19) end
  else
    _wmenu=false
  end

  -- burst fire (machine gun)
  if player._burst then
    local b=player._burst
    b.t-=1
    if b.t%b.rate==0 then
      local aim={get_aim()}
      fire_single(b.w,aim)
      player.vx-=aim[1]*b.w.recoil
      player.vy-=aim[2]*b.w.recoil
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
      player.vx-=aim[1]*w.recoil
      player.vy-=aim[2]*w.recoil
      sfx(w.sfx)
      player._charge=nil
    end
  end

  -- X button: interact or fire
  if btnp(5) and not _wmenu then
    local px,py=player.x+4,player.y+4
    local interacted=false
    for t in all(terminals) do
      if hackable(t) then
        local dx,dy=t.x+4-px,t.y+4-py
        if abs(dx)<16 and abs(dy)<16 then
          mg_start(t)
          interacted=true
          break
        end
      end
    end
    if not interacted then
      fire_weapon(_wsel)
    end
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
      if n_enemies()==0 then mission_data[current_mission][2]=1 end
      if n_fragments()==0 then mission_data[current_mission][3]=1 end
    end
    if _won and btnp(4) then change_state("mission_select") return end
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

function draw_gameplay()
  cls()
  cam_x,cam_y=cam.x,cam.y
  palt(0,false)
  palt(14,true)
  camera(cam_x,cam_y)
  map(0,0,0,0,128,56)

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

  -- extraction indicator (points to spawn)
  if n_terminals()==0 and not _won and not _dead then
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
    for t in all(terminals) do
      if hackable(t) then
        local dx,dy=t.x+4-px,t.y+4-py
        if abs(dx)<16 and abs(dy)<16 then
          ?"\142",player.x+2,player.y-6,7
          break
        end
      end
    end
  end

  camera()
  draw_hud()
  draw_weapon_menu()
  mg_draw()

  -- extraction ui
  if n_terminals()==0 and not _dead then
    if _won then
      print_centered("extraction ready",64,50,11)
      print_centered("\x97 to evacuate",64,58,7)
    else
      print_centered("system purged",64,44,11)
      print_centered("return to spawn",64,52,7)
      print_centered("evac: "..flr(_evac/30),64,60,8)
    end
  end

  -- tutorial hints (mission 1)
  if not _mg.active and not _dead then
    for tt in all(terminals) do
      if tt.tut and dist_trig(tt.x-px,tt.y-py)<42 then
        local m,w=tt.tut
        w=#m*4+6
        rectfill(64-w/2,98,64+w/2,107,0)
        rect(64-w/2,98,64+w/2,107,3)
        ?m,66-w/2,100,7
        break
      end
    end
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
      if #_mg.inp==#_mg.seq then
        mg_check()
      end
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
  -- target sequence
  local sw=#_mg.seq*8
  local sx=cx-sw/2
  for i,d in ipairs(_mg.seq) do
    ?d,sx+(i-1)*8,cy-12,7
  end
  -- player input
  for i,d in ipairs(_mg.inp) do
    local c=d==_mg.seq[i] and 11 or 8
    ?d,sx+(i-1)*8,cy-2,c
  end
  -- timer bar
  local tw=60*_mg.timer/180
  local bx=cx-30
  rectfill(bx,cy+10,bx+60,cy+13,1)
  local tc=_mg.timer>60 and 11 or 8
  rectfill(bx,cy+10,bx+tw,cy+13,tc)
  -- label
  ?"HACK TERMINAL",cx-26,cy-19,3
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
    player.vx-=ax*w.recoil
    player.vy-=ay*w.recoil
    sfx(w.sfx)
  elseif w.charge then
    -- plasma: start charge
    player._charge={w=w,aim={ax,ay},
      t=w.charge}
  elseif w.homing then
    -- missiles: spawn orbiting
    local px,py=player.x+4,player.y+4
    for i=1,w.n do
      local a=rnd()
      local off=10+rnd(10)
      add(bullets,{x=px+cos(a)*off,y=py+sin(a)*off,
        vx=0,vy=0,life=w.life,sz=w.sz,
        col=w.col,dmg=w.dmg,
        aoe=w.aoe,aoe_dmg=w.aoe_dmg,
        orbit=w.orbit,orb_a=a,orb_r=5+rnd(10),
        spd=1,dir=a,mx_spd=3,plr=true,own=player})
    end
    sfx(w.sfx)
  else
    -- rifle: instant fan
    for i=1,w.n do
      fire_single(w,{ax,ay},
        (i-1-(w.n-1)/2)*w.fan)
    end
    if w.recoil then
      player.vx-=ax*w.recoil
      player.vy-=ay*w.recoil
    end
    sfx(w.sfx)
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
  local aim={dx/d,dy/d}
  if w.homing then
    local px,py=e.x+4,e.y+4
    for i=1,w.n do
      local a=rnd()
      add(bullets,{x=px+cos(a)*10,y=py+sin(a)*10,
        vx=0,vy=0,life=w.life,sz=w.sz,col=w.col,
        dmg=w.dmg,aoe=w.aoe,aoe_dmg=w.aoe_dmg,
        orbit=w.orbit,orb_a=a,orb_r=5+rnd(10),
        spd=1,dir=a,mx_spd=3,own=e,plr=false})
    end
  else
    for i=1,min(w.n,3) do
      fire_single(w,aim,
        (i-1-(min(w.n,3)-1)/2)*(w.fan or 0),e)
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
      if abs(e.vx)>abs(e.vy) then
        e.last_dir="horizontal"
        e.face_x=e.vx>0 and 1 or -1
      else
        e.last_dir=e.vy<0 and "up" or "down"
      end
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
          if abs(b.x-e.x-4)<5 and abs(b.y-e.y-4)<5 then
            hurt(e,b) dead=true break
          end
        end
      elseif not dead and b.plr==false then
        if abs(b.x-player.x-4)<5 and abs(b.y-player.y-4)<5 then
          hurt(player,b) dead=true
        end
      end
      -- barrel collision
      if not dead then
        for bar in all(barrels) do
          if not bar.exp and abs(b.x-bar.x-4)<5 and abs(b.y-bar.y-4)<5 then
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

function bullet_explode(b)
  for i=1,10 do
    local a,s=rnd(),0.5+rnd(1)
    add(parts,{x=b.x,y=b.y,
      vx=cos(a)*s,vy=sin(a)*s,
      life=20+rnd(10),sz=2,col=9})
  end
  sfx(28)
end

function spawn_impact(x,y)
  for i=1,3 do
    local a,s=rnd(),0.5+rnd(1)
    add(parts,{x=x,y=y,
      vx=cos(a)*s,vy=sin(a)*s,
      life=10+rnd(5),sz=1,col=6})
  end
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
function n_enemies() return #enemies end

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
      for i=1,20 do
        local a,s=rnd(),1+rnd(2)
        add(parts,{x=self.x+4,y=self.y+4,
          vx=cos(a)*s,vy=sin(a)*s*.5,
          life=20+rnd(10),sz=1+rnd(2),
          col=self.poison and 3 or 8})
      end
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
  for i=1,e.kv and 15 or 20 do
    local a,s=rnd(),0.5+rnd(1.5)
    add(parts,{x=e.x+4,y=e.y+4,
      vx=cos(a)*s,vy=sin(a)*s,
      life=20+rnd(10),sz=1+flr(rnd(2)),
      col=({8,9,10})[flr(rnd(3))+1]})
  end
  sfx(30)
  if e.kv then
    credits+=e.kv
    del(enemies,e)
  else
    _dead=true _dead_t=60
  end
end
function hurt(e,b)
  if b.aoe then bullet_explode(b) else spawn_impact(b.x,b.y) end
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

function draw_parts()
  for p in all(parts) do
    circfill(p.x,p.y,p.sz,p.col)
  end
end

-- weapon menu + hud
function draw_weapon_menu()
  if not _wmenu then return end
  camera()
  rectfill(28,24,99,92,0)
  rect(28,24,99,92,3)
  ?"WEAPONS",44,26,3
  for i=1,4 do
    local w=wpns[i]
    local y=34+(i-1)*14
    local sel=i==_wsel
    local c=sel and 11 or 5
    if sel then
      rectfill(30,y-1,97,y+10,1)
    end
    ?w.name,32,y,c
    -- cooldown bar
    local pct=1-_wcd[i]/w.cd
    rectfill(32,y+8,90,y+9,1)
    if pct>0 then
      rectfill(32,y+8,32+flr(58*pct),y+9,
        pct>=1 and 11 or 5)
    end
  end
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
  print_shadow("credits: "..credits,sx,cy+12)
  -- charge indicator
  if player._charge then
    print_shadow("charging",sx+54,sy,flr(t()*8)%2==0 and 12 or 7)
  end
  -- enemy alert bars (lower-left)
  local ay=121
  for e in all(enemies) do
    if e.ai=="atk" or e.ai=="chase" then
      hud_bar(2,ay,flr(e.mhp*.3),3,7,8,e.hp/e.mhp)
      ay-=5
    end
  end
  -- minimap (upper-right)
  local pmx,pmy=flr(player.x/8),flr(player.y/8)
  for i=0,255 do
    local tx,ty=i%16-8,flr(i/16)-8
    pset(120+tx,9+ty,
      fget(mget(pmx+tx,pmy+ty),0) and 1 or 11)
  end
  pset(120,9,7)
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
    w=8,
    h=8,
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

function entity:follow_target()
  local dx,dy=self.target_x-self.x,self.target_y-self.y
  local dist=dist_trig(dx,dy)

  if dist>1 then
    self.vx=self:approach(self.vx,dx*0.1,self.acceleration)
    self.vy=self:approach(self.vy,dy*0.1,self.acceleration)

    -- track direction
    if abs(self.vx)>abs(self.vy) then
      self.last_dir="horizontal"
      self.face_x=self.vx>0 and 1 or -1
    else
      self.last_dir=self.vy<0 and "up" or "down"
    end
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
  spr(49,self.x,self.y+1) -- shadow
  if self.flash and self.flash>0 then
    for i=0,15 do pal(i,7) end
  elseif self.col then
    pal(7,self.col)
  end
  local spd=dist_trig(self.vx,self.vy)
  local moving=spd>0.2
  local s=(self.last_dir=="up" and 32 or self.last_dir=="horizontal" and 0 or 16)+(moving and 2 or 0)
  s+=flr(t()*(moving and 10+min(spd/self.max_speed,1)*10 or 3))%2
  spr(s,self.x,self.y,1,1,self.vx<0)
  pal() palt(0,false) palt(14,true)
  -- ai state indicator
  if self.ai then
    local c=self.ai=="atk" and 8
      or self.ai=="chase" and 10
    if c then
      rectfill(self.x+2,self.y-2,
        self.x+5,self.y-1,c)
    end
  end
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
  local i=current_mission>2 and 3 or 1
  decompress_to_mem(map_data[i],0x2000)
  decompress_to_mem(map_data[i+1],0x1000)
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
5249a052361b05ba0025b2d1a8502698a51044058251a403902606aa00e0b4081b41a450264880411a007962100ef370269a6490d64021b314010ac05a20ca41
a470f2604ba20c95024405422216c18d0603c1e0608000c740416d94300c00380b40024090ec40fb20305104480ea464381628809a406b08a51c9506bb09f18b
0391c10cf60850e1f8748a7083018040738990023dcbf10dee00328902020434860180e673b1dc6e8d0192eb4050706e302902e8077184724b20ee20fb708203
14cfd87c2b47d1a80094703f08351cdf16ef7801830fb1704fd3b10625482d4fc0e0105c70af3289f47c8af043706d507480c2382204580ae36a3f97483df02f
d371940dbf1608c261c048352c97d013f72814683278705f489224c22a65070234c896c0ea06f3e1f8038485f74b25ecb378c16a38ff2cd7c04089b24ad32d00
6eb1511800091887f291aaf36ea2f891a912e4050e836dc9f3a8f06eb718308c9080663f1c6e82d02145735c45d86e30112000a036182fe11a4d0df9381062a0
7ea04b62390a01048baf092703271678af14df32eb05e3832842962a40d0014030e906cf1fe985761a0839333779139c99325c07f9349062a07e212b71b0bc5c
3d17a3f17e709ec3f91aef78910812c12ce673314a04482d1f63454ed47304001eef1d18349c4edf918e68179c434aeb3771933711ea965a4021c81b0c861acd
1bfb23c3578cedd573f0782f9f82c641f1a6f0fe8350789f5c4fd86c1e07cbabe50813715ae70b0a951c1a0e1f402771b00e24768a761967319e535f0321b417
2835c68029d1dce02ff89f54cf5ec11d85989c91af935a536e0a107ccfbc6a3e978eb9a04929bd81d039f70893c42f87f3e9f8057c8310cbf34d0cf6d3b9cc70
821cc2f60dc7f3630c97d81bff86b691a7109ef025c995f99a824492924171c845a260f846ff113093c9c1eb2db466c5f8be69c0703e4c8c85bdf02ad9905ccf
6eeb663d97ca0c073aa4f458d00b7c82f0926bf35ed237625c1372ca3480bb128e61b0038188439f234271a8f59a503ff8adb4ce7aa545303317083b133b3abf
a972ef170082f3d931228650d42fe92f645292cb07a9a453caf38c3d5027d30c546a8b74394c1b8461b2513de5a6af080793c27e733f3a1c245a36ef47c1329b
6cf01f135f28ae2519d42f1aa3f2998e71643a88a4258eae5d408d12d9f5ec6afa5525d3e152ae148bf34b5d69f0ae7463b1b2a345dba7d55a7080b3f05f4a10
2982ef0515a35ec4d125f14eb0517966071590a4f7cd704d3d13380b4e7c0d084eb36449598e87d27a108d991635743b5774a0f0def54f8a9f559fba9413f704
8d27697c6539d919541f2acd3dff92c81100a8143311884c264210ac9d884402914aea17083c54f5091600b00361cac265efa50c5974acecb5a643f8aa8d0e18
2790b454d78ba07edee155384a9ce592df09203b97683b78183f3baf1d08eafd751d3646f18d61b24994545af2726a8cf3cff1effb8cd0603806ff6fb7235dd5
7d00b24137fa9509c44c304300cc880402117ae307ff05cd4ba40954106808df0ecf0a0c372ec342ca51e2033931fcaa9d292a5568341b8dbc23279ce249a031
73b34d5a02b8d2b24953ac333102ef6904a53a4b06e3b21dc8a9ab96b5ee23204c3397ce4dd0604eb923ca68ac935202b8325b39eff85e2c116e1b91f585e9c4
55c46c063c9d0e17f2c355ff361faf5f4a7503b9fc9d05a2120133121f04308c784e5ac86089f3cf0af3b0eeb42da751a45c264a5531f166a559452e80dc6ecf
6199c0ffc9342a11f581fa017c0aedd429085af3cc2aa186cfec23cf9f00e7733df49f5124738936ff5a83f38ac12f87cc9c165133e504b43d69d8fc539c0066
081a660f1b0c1df7c92a49837d17aec4497209fc6c3f9fcfedf74dbd94df6eff503810cfff705fc31caa57a5548e60cd127ac111533c793e29636cbdf8d2cbc9
0cbfb45e9a8efc9eb6ceec43ff3b4ff3cd1f65b53d4a84845f300bff881b1c08ede77892d68ede1005f78df544f3bdf7cc459389f01fff2499bf035ee1ca8d3b
8494467201f7df3612e0c19670ffec2f495e0b15d7e220f9c0453c9c3c51b65fc0c9b7b2f469baa44f4c97c3745c321f012b86a04611095f6c303a54080011b3
e204fa614295f42d611ec7daf4c7aec4d77af3490df673f9fc6c3f1f8ab58136d3e136ee178f34cde9f26850027d50280e43050183fbee07bc0878db5838aa57
5f78080d96c6085402918846251041c864aa9dde85de64d7e73593cfcfe7f354cf78597a326f1271a984b0603083e9b70389b04328894fd6f9af1fc06f680de7
c32869ef35f0b296f94ceb3cefc044211389ae7000c5c9d87ece235410f8bb5c9cb6084b5fc1deef57672a99eb0190fb69789a85479e930ff78efc990aedf793
41e45ca3ff19329d93def74f55a17e6347fff612eb09bcf9a3703058245d79de7f4cf3bd35a8f6f305c6aaef7760b7485b1ca520f1c541e99189d40251100e00
462b1845aa0582c1cc30800011ae0040f603a10ae2081782a900be0065830c6374080d96cde070181fc9046e3897af0040f7189921ac50211b45ca458241a450
2618859a50238259a80d21229885de005c081a4102e3442c9308ed4038132954248a0499c18d0683c1c0603016cb4f402024000808341062216ec2489ea0580b
188c5447f2498e068381d0663f974ae0c242b1c001b08200c4202eb05c10975369846e318701804038cf2c830ac1643fc7f38090013438af7804014083f3cf44
e672ac000011c06630978f4dd0e11cc52a61648fe2010c65b25178022a05208353012c008af673b934094132108ae80620e16801ff84f2196cf07e713608b1e1
260307f72a95040a05a249360517158350413525b28cc438bf109c60319fcf2d703059cc703e1c6e83724127d078222905650502e6a3aeb0d3b136eb643f906a
f24e03d3c0d06c30c4f1ccf0302db89c14aff4728ff74e76a4c240253018ac17a583104a858d7da12609a959cc628ff389c16887c3e112493c00c51049915231
d09cc51806148523e05af136f89fe16c708a3f41f16ee48ef673f9dc7e8ff30c2ff366c3608c0b0ae276391cef92de5152d81784993620293892951a0e5f0150
d3200e6d05080942e1a4f04ec1e034cf2eef175994f30943b70321438112840834c7f8880c246892b1020b1bbf85e8495c842f97681c3cd45644170c329768f0
aea2389ff90aef7c394d044161b238bf4cd12200141b850761b08896b1cc602993ea4588c6f89fd4019c6010c59405ed061301803319231227f04f8609ae7cc5
1c07729561439889558336331cdf2eef0e8b57c1162d04b8d349d0bc4d183967229d0028642211844a204ef10d457403a84e850505986f449fa0004284499e94
1238268b0495cb0c274911b0104b443314cffd343392b94eef17c1828f49a2498003381984403ee107f712c5dd883d5338d9afa08a6a041045f34e3964b33ab8
e40b6ab301080cc515846d94d920d9f06c3f8ac1e08503f15eaf2be7839a8a0106b0e024141a00160bcddf884d001abf3dcf0c11ff82f79bac8950a44ba9ac7c
df76b3153c82494a348580b203219a48455c024000a096704376389a600eef1da593ea5c75c43cf04f9a1f14df46ef074535c758291a745339ba3d7cdf3a200d
e7991701ca6506b99a2d400aef6a3840e5e8f68ab1d3685c177f98a5c3d8a9f15e725838bf6182ef3db59940952a379ac0b1c8d6655a166f17a295c8c102a1a5
76c56f786f54dfc2690bffa6f7de6665f474f55b489ef492462965e1931cc334053c7435839cd38c6e8153dc04619cbe3498ca19899023f7baa6d1f5ecb19f85
40837dde8aef59ac83f35a472d081b276978cf7d22aea0498db5b4dc9becf0be472df8bfad832adb492292e8caaae058d8d647baaca1cea56d3ca25e598ee658
64f63b9f452ac60f743add61c028643311c84c94bf1981cc04e2d4ef0700196b83f36f00c010d2260c9f618c4a209240cc04181e01804c805019e8c65856489a
174d5a5a55703edd15210f3ba04c68a71e710eff559d899942538a108043cb549dca9aef6e2210205a72734b6934f11a6d07da8677596ea0e3b4634fdbec1647
7e005be886dad28a7902d06894db2446558476bf179acb0c958c2bfcce7e40597d3248446bdb72f1425ca65620281a96f39cc60854225c881ea5272304e50671
d2de093660ad1a33a16da8b2ce99cb2ca5cc213cefb0176a3253f8315374a93ed209b24d159fb2824113bda3d2d94a3abf542813e267bbb4405577accb5230cc
4ba516029c85a782b2e6b6f774fb9077b8bf9e165c78d772e954bc627654764d2ed13e65a960d71491c4ffe26303213aba6373ab6c51563575f54afa78dff49a
4a012f6ddc29e1188a1bb73c3da2b43f06ffabd986b3eff8eb7cba0075d896d49a52ca05818a219720171b20b50875f45706f30f320f7704300e120f028f81c7
01e3a0f160f038782c301e120f0a8f85c703e3a1f1e0f07848f01a4f388300019f6cee918b0e0109d08240c2306a40f6108a18c1bb783c83f14b20e170ff30ff
28641c4dd93c831441b1a4c07c9055382814cf1a4315b98740c1b1e411961097581d04d316c6054a8ff14af22e70fee03c28210cce7c0dcd83f1ca20e070efe3
18ff0cff0ef705cb8886c954a4717ed09338cf0c5a12f71bf7854cc345e41358205ab8ff1c151a9d11f384fdc927637172c12ec81f6cff3e2607ff8701c1d52a
243b6174b8cec47806d20bf38f904369a8a33372f5b9f8ec700efc3f1a9f8dcf0fe731f3e3f1f9e8080000000000000000000000000000000000000000000000
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
0381c542a15400ce005e070394cec762881ce22a0001cac762b150a2762840318a05528958ac7628140ab00232612ca05028c09880e5480a2942022b020280aa9409905bc0012e0767039281eac0b480f0682801a01c00000ec018c0f005503990c06038180c0521500054538041c02ca018d00073840788d649239b204c8768
0b3c045203c90154359260b6871004174a00642a2bc07120747022480f2c070a0fe83c06834542d84811c400073881cbe04379bcfc6f379bcfe6f0d8ac0804806140352004c6d8051810de7b301248e603713a01eb0035808981203450204021bcc05983e14180c002c1ec014c0e433f010f07f82c91b4fc6f3f9f8de6025459
ca13870ff488298542c3d8851443ccfc783d1e8f27a3c1e4f47a0d87210c500728009c050a01046d80614178808602c91cc06f3dc03d602667b83fa1bcf6040240b4e0fe6690381cef07f40e8020cea7f3cc1448f04d2f1e8f47e3d9bcc311e23b8341a2d8bfac3d480e25134628e31e707123c43c4e0eeb07038861c20160fe
90ed33495cc102032ec4a0a0a25094283fa4278a070a6f301681a0d1ec7688e3266287fa14cde7886991e0da783c1e4f27f3f18233cb1f848c220a81a3d1544bca42647d3f4498e2f0918328011c0308086f058320de84e882a41788d107f485221bc9a6e371ba0fec6f88011bcf517f224c350e3c0707f52c184fd0ca63d02c
f27a3fc5fd20ff121f21e4429615c474922b908cc46231988723159191c169208085d371809468309bc9a4e87819e89a6e8a990122fe85d89a10c20fa44d37180e530d3983181e4fe4710011cc11c8337c7008de1b8af145fce4d6507f79c414429662a7076322100804195f181c0e4420918cc6622114806330c768e32846f3
d06c1926d437178da6f2e9b85c2f2f4414e0feb21b2181e8606e37978de6b98abc1fd00107f28bf942750f46f3cc6b48953bf29e01cee4e007f013f2850188a0738b7bcc3124fe91fd23d1e87c3f84aac1fd8dc6e184ccca502530958c3147fcc0e0724184fd07623d0c0f230271e8f2789969ceb56009f3c16803dcecd0e060
36495d24bce6a8769c7f8e622920023012652286f02480d274a910e2301245907f587fc1e4bb0a3237184952bf29e699e8162b9d9aced92014d3e529bd1c007e618a6d8f091360fed0ef29a7947550c049948a01284453a33a4591ae10c46024cf54a90871ff29eb144c889c7e9ee15078a57e47b99c982c561c9d99cee0c160
c9f52ce8ce003f38c92ec7848bc602d43fd09a5e9d424f50a0fe6619d925088e71c462319820fe672ad11569089942e2a241d35c8f107f434c0b5a0fc53e249b098ac193f43a7235404a6e451ef787fd490d28da92cd3a4abd1fd6114530c48fc1ca39250c452b2811ac92483051f8e982c793c4efde9c45461490631ae5be75
c68807e4dfca5bc555a337178fc7e3012a0fe70a97aca9c2456177130e6ac5155bca55c94782aaa19b690c67930928b153f2a26254b8a25c640800118e4a6900b5807f98cd709c2853b980d84923cd85a136f6112808dc080aa40959023c56708d2489bf9592d0db5fd237d1fca02051688a571ce3ce6c691b32ba6b403f0b70
9c305984c44020918884022900b85b85819188c4422908890b73b3f916e01cf0be42e4a816c7887f91711ae2a2f16b485ff433ce02c945f3a1d1dd35a01f44b39c9788374d6728132e76b25c4a0d9c2d5689b6733056548dd5af2b869c270a2c064594a145ad617e94e7485745db126c0773f2ba6a403daf04742f3a0015359e
9ae6770001cc8522b158a653c1691b0df01988c155b04ee60778d23962958e707f38afc53f1aa0c90192a5c1db4ccdd07f38d815c01c0975d693f9dff48578162301270ac40721d08f286494438ab414e36645730a96c56c42bae8c500b05c1fca79ab7fc4b3795375701481b158ac1985e283f901e84ff81b4bdc2581ca0ff5
4ddcc66998665ab8aa49f73dfc20162b15e135663f54dd2a4eb4200eebc7731399fbe1d529698308092812f60b4cfec3f94efcf17e543d7ab6641fd2b3ed31f83418693c758750d872fbc61dc2994363a962717e6b54a810090dd8af0e50fce53c79d93ae09da33cd8492c5d04ecf4d00fca51a6178b56a474d4e1dab5e81720
4abe1d2e6add1a42000008743f292fa48912f24747f5987dcf7ca63b332f6a51ad894b4bc7b35333502ca001d8272bceb5355a82974e42c2b11c40044201725be78be4ca21d1fdb021f3278e07170312682a0cbbf9eebdf67640d16eb9ce006d40b33563b8b30e73252cff36c20f71670287038aa5be78be2b19266f5301ffbd
5c2915b818957a4b5816b78f86adc39432148ec53291db93a5c252366df08ca5783ff41ee2108c071564b535b666e2f609d28fed227fb73a7014f7f278d56bda16d78a4fe507f821f0a0acce67e379b76524040210a83450ff6cff192fa30996fc266cfcf17cf7a73a3f9cce576f337467c0c1dda9a804d27f5d10af4e48d06f
caa16fdc8f07a36f0b8c0807160360feda632cfe174ad32b53cff3c16a0c35747a123d171657d30f1a0bceab69c4f1271b6c3db696f78e1ff27f3d723080908322e9b8dc7b3d1bf7f45b8450001cefbfe2aedadeb2b1feb8be7c31be396e2ca94673d6aa0c0363037d1f9fa049bde28005074ce7e3c1b79ea5d384e9c91f8a5c
6e293fae7f92cb698ac6e801ea5ceffe71538a7fdd0e538b4999a2ef3a71748f7927683ffee8d478533ff8652fb49ddf23f9ab0ba52ff5f6d16df139773d2d6bffe01345c7a67a94d1d398ee0ebbef2181be0fcfa5f3e2f17778a2034742111886662310c85cb03e5b110ceb3ff6bc9b5e2909ddac4ed6c0239acc1000a36188
c700f7359bcf47a8011400cc087b301248e600207039010480121bc605e181b8bc6f301a40f000538c01d09650281460144563b158a85080021ccc1045383141b20a646d8222c0114c0592d900804023198890052801217201ee6381c99e8de6f8411810df07f383dc420d4f709b205980b50796843295cd86030148ac53301c
21a130c53800541fc8de6d86a91349d0db4301aa16450aa3289d8a30b15802bc2e521d8e0483ff934dc6e181bcf40b15980930ff41540092214443835b812004a3006030560c85be9b4de5d370b85e5e2e9bcdd0002301a48f0b22800fc4ae22db10fff861141f8e0fee070a85a30e42c068341b1a06024011408300d8ac361c
8d9a02e10cc4d2ec75c87c3f8eda8120fe4603786c562b0e1bcdb1255803344b1e3f6504a237c5ffe0fe67a3d06c0804301663fea2513481c83a0738802349308251841f4a2fe70ab206473089a6e2f4950e302707f58eb9c1fce0a2b05868d85812292507f6807b4040e15a60b15c1fc8b517f8068347a070394e06f303a58d
291e0df16283597a5769084293fc12254241b0e43e1c9a5e938240c5648b26036124ae6b359bcff1abf80b949f680e072c4d33268ac7937980c52de5969ac18ce5ac724328ff9120c32a143d1749d1d779bb9c0c4a6273317438918c31862311048c4622ccc188a6620110805c0381c0100099a621188845214d3dcc6603f1e4
f47f8d2987675053435834ac90d4c05a9ab9cd9123a4919848081180933ca22acf0c8aa5103cf38a7bc40034180de7e301260d8871000027e081d3881c542a83f5002698c502601c0106f3000008e613f511488521c4039c4af3c358f54d0fc8ae609839c3f08bb3a638cfacbbd262ee529e7114cca073b81cc2043f180e4513
bcfbea1a6747233b1468e2c739a629ac9207001de7206002b984fe7a3d1f8a53a239d1919e486507fb96b94bfce9cc534f4a4ac4dbce42e530d33f1fe4e494672321b0094c8338148ed45f232d3d8c0105339dfb51c58d93f823dd2b480101b403800e2683f1e0f27f355478a0fe658961b524262fed51439802d5c569de87e3
dcd99244c66e301aa8b4c7f379fa60464f83fcc14de780d3b0283fa0003a00ac999d084000010cea008c02d7acaa32d520736555d20fe949533d13692a9497287f94ea8a82865e05830186f30924e258379e2bf8e793f57c500125438e9b47562b5ab0ff394b94a6e2400b5eb380171724fe84d2e9ba92a96512a39a98092573
051e0ecfe61b15870fe602501c90043c1e60f890053b3aa000593f123448fcc9d0a75895ada54a3fe507f585195a75a3fe64b28144ac563b5a85abe4a4c23c9fce81eb4957a399180926883f958a486108030e589c80e68a44a48388fd18223e47fd26a66689dfa5a288de1b065658eace571541e0345b07b8acd9c9fced3c72
d13b50c9ae1ce527f3a4aed7bccd12b923797460791847fd0c2698e49118cc4333118876db43ac9fe25a6523b2060c0360c37d510ec2642b37c87525e0771b99ff1da78cff23e4379faaac50052bab919cc15612a4af47fce7dc57fe3181e632477e74bb431988c662311a4b6907f92e8c0f4308bd241f8c3919d28b834eab69
52540d2c291492180932922cc59cae565495bb161030c049995956a5606467f977a5fa264a0945458139c29cf158a1b0e5bb8ea2681da8b9193018465a5820f2950b2c39c6419765ce50ff3ab9a5a01ed5661c9ffa56a565ea4783ce38170d4d50c29a819c65fe989728f895b597238f59341e0b40000341f8fc7f35567d6a50
771ebca42980b30e74c739de020f40b937912490619272414621eed34c6a6e24dfdc576514c86949ecf1d8729d4af8999cfe7b379aa606d600287f90322f8f07f6bff9e524b19e45e81fa5a1c8161ca60991cc02b061b4f537149f8167958597652068b6b9ab55038311980de1cbdda82c381b942160c0af2a82a150f4e20734
1fcfd57c2a3e955f4ac2087e99211e8f768069b0159fd2f9f182343686efde857300ac3957e2a7919f8fe7e9b79df8566b257ea306834557f123bd54d717691352c0fb66b4a4fcc74211c4867583fa1de076853a9f15740a0aeb5482d2b9ebfd8cd7d7f3a6006349a536f4900ce9d2b67fb815f9bf6e07bf0ae75136209c4884
1334d60af76e5c3881c8642234da88cc4620cdc0aece5001f808b554e2fef65c8177c0ae703d9b6f20000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
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
