pico-8 cartridge // http://www.pico-8.com
version 43
__lua__

-- palette darkening test
-- left/right: cycle mode
-- up/down: shades (1-8)
-- o: cycle curve
-- x: print to console

-- pico-8 palette rgb
pr={0,29,126,0,171,95,194,255,255,255,255,0,41,131,255,255}
pg={0,43,37,135,82,87,195,241,0,163,236,228,173,118,119,204}
pb={0,83,83,81,54,79,199,232,77,0,39,54,255,156,168,170}

-- skip 14 (transparency)
clist={0,1,2,3,4,5,6,7,8,9,10,11,12,13,15}

modes={"hand","nearest","percep"}
cur_m=1
shd=4
curves={"gentle","linear","fast","steep"}
cur_c=2

-- hand-picked dark map (current game)
hand_dk={[0]=0,1,1,1,1,0,5,6,2,5,9,3,1,2,2,4}

function curve_val(s,n)
  local t=(n-s)/n
  if cur_c==1 then return sqrt(t)
  elseif cur_c==3 then return t*t
  elseif cur_c==4 then return t*t*t
  end
  return t
end

function find_near(tr,tg,tb,mode)
  local best,bd=0,32767
  for i=0,15 do
    if i~=14 then
      local dr=pr[i+1]-tr
      local dg=pg[i+1]-tg
      local db=pb[i+1]-tb
      local d
      if mode==3 then
        -- perceptual: weight green more
        d=abs(dr)*3+abs(dg)*6+abs(db)
      else
        -- manhattan
        d=abs(dr)+abs(dg)+abs(db)
      end
      if d<bd then best,bd=i,d end
    end
  end
  return best
end

function get_shade(c,s)
  if c==14 then return 14 end
  if s==0 then return c end
  if cur_m==1 then
    -- hand: apply mapping s times
    local col=c
    for i=1,s do col=hand_dk[col] end
    return col
  else
    -- direct: scale rgb by curve
    local b=curve_val(s,shd)
    return find_near(
      pr[c+1]*b,pg[c+1]*b,pb[c+1]*b,
      cur_m)
  end
end

function _update()
  if btnp(0) then cur_m=max(1,cur_m-1) end
  if btnp(1) then cur_m=min(#modes,cur_m+1) end
  if btnp(2) then shd=min(8,shd+1) end
  if btnp(3) then shd=max(1,shd-1) end
  if btnp(5) then cur_c=cur_c%#curves+1 end
  if btnp(4) then print_info() end
end

function _draw()
  cls()

  -- header
  print(modes[cur_m].." shd:"..shd.." "..curves[cur_c],1,1,7)
  print("\x8b\x91:mode \x8e\x83:shd o:curve",1,8,6)

  -- 15 color rows
  local y0=16
  local sh=7
  local x0=12
  local sw=max(6,115\(shd+1)-1)

  for ci=1,#clist do
    local c=clist[ci]
    local y=y0+(ci-1)*(sh+1)
    -- color index
    if c<10 then
      print(c,2,y+1,7)
    else
      print(c,0,y+1,7)
    end
    -- swatch chain
    for s=0,shd do
      local x=x0+s*(sw+1)
      rectfill(x,y,x+sw-1,y+sh-1,get_shade(c,s))
    end
  end
end

function print_info()
  local hex={
    "#000000","#1d2b53","#7e2553","#008751",
    "#ab5236","#5f574f","#c2c3c7","#fff1e8",
    "#ff004d","#ffa300","#ffec27","#00e436",
    "#29adff","#83769c","#ff77a8","#ffccaa"
  }
  local names={
    "black","dk-blue","dk-purple","dk-green",
    "brown","dk-grey","lt-grey","white",
    "red","orange","yellow","green",
    "blue","lavender","pink","peach"
  }
  printh("=== "..modes[cur_m].." shd:"..shd.." curve:"..curves[cur_c].." ===")
  for ci=1,#clist do
    local c=clist[ci]
    local s=c.." "..hex[c+1].." "..names[c+1]..":"
    for i=0,shd do
      s=s.." "..get_shade(c,i)
    end
    printh(s)
  end
  printh("---")
end
