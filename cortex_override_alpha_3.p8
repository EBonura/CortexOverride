pico-8 cartridge // http://www.pico-8.com
version 41
__lua__



-- strech goal: implement a flag for cables sprites, and do a pal swap vertically or horizontally periodically across the map

-- function compress(data)
--   local result = ""
--   local i = 1
--   local data_len = #data
  
--   while i <= data_len do
--       local best_len, best_dist = 0, 0
      
--       for j = max(1, i - 255), i - 1 do
--           local k = 0
--           while i + k <= data_len and sub(data, j + k, j + k) == sub(data, i + k, i + k) do
--               k += 1
--           end
          
--           if k > best_len then
--               best_len, best_dist = k, i - j
--           end 
--       end
      
--       if best_len > 2 then
--           result = result..chr(128 + best_len)..chr(best_dist)
--           i += best_len
--       else
--           result = result..sub(data, i, i)
--           i += 1
--       end
--   end
  
--   return result
-- end

-- function test_and_save_map_compression(start_address, end_address, filename)
--   -- Gather map data
--   local map_data = ""
--   for addr = start_address, end_address do
--     map_data = map_data..chr(peek(addr))
--   end

--   -- Compress the data
--   local compressed = compress(map_data)

--   -- Convert compressed data to Lua string
--   local lua_string = ""
--   for x in all(compressed) do
--     lua_string = lua_string.."\\"..ord(x)
--   end

--   -- Save to file
--   printh(lua_string, filename, true)
--   printh("Compressed data saved to "..filename)
-- end

function decompress_to_memory(data, mem_index)
  local i = 1
  while i <= #data do
    local byte = ord(data[i])
    if byte >= 128 then
      local source = mem_index - ord(data[i + 1])
      for j = 1, byte - 128 do
        poke(mem_index, peek(source + j - 1))
        mem_index += 1
      end
      i += 2
    else
      poke(mem_index, byte)
      mem_index += 1
      i += 1
    end
  end
end



-- HELPER FUNCTIONS
----------------------
function reset_pal(_cls)
  pal()
  palt(0,false)
  palt(14,true)
  if _cls then cls() end
end

function check_tile_flag(x, y, flag)
  return fget(mget(flr(x / 8), flr(y / 8)), flag or 0)
end

function stringToTable(str)
  local tbl = {}
  for pair in all(split(str, "|", false)) do
    add(tbl, split(pair, ",", true))
  end
  return tbl
end

function dist_trig(dx, dy)
  local ang = atan2(dx, dy)
  return dx * cos(ang) + dy * sin(ang)
end

function draw_shadow(circle_x, circle_y, radius, swap_palette)
  local swapped_palette = {}
  for i = 0, 15 do
    for j = 0, 15 do
      local index = (i << 4) | j
      swapped_palette[index] = (swap_palette[i + 1] << 4) | swap_palette[j + 1]
    end
  end

  -- Pre-compute squared radius
  local radius_squared = radius * radius

  -- calculate the top and bottom y of the circle
  local top_y, bottom_y = mid(0, flr(circle_y - radius), 127),  mid(0, flr(circle_y + radius), 127)

  -- Function to swap palette for a line
  local function swap_line(y, start_x, end_x)
    local line_start_addr = 0x6000 + y * 64
    for i = 0, start_x >> 1 do
      poke(line_start_addr + i, swapped_palette[@(line_start_addr + i)])
    end
    for i = (end_x >> 1) + 1, 64 do
      poke(line_start_addr + i, swapped_palette[@(line_start_addr + i)])
    end
  end

  -- Swap palette for top and bottom sections
  for y = 0, top_y do swap_line(y, 127, 127) end
  for y = bottom_y, 127 do swap_line(y, 127, 127) end

  -- Pre-calculate values for the circle intersection
  for y = top_y + 1, bottom_y - 1 do
    local dy = circle_y - top_y - (y - top_y)
    local dx = sqrt(radius_squared - dy * dy)
    swap_line(y, mid(0, circle_x - dx, 127), mid(0, circle_x + dx, 127))
  end
end

function display_logo(x_cortex, x_protocol, y_cortex, y_protocol)
  spr(224, x_protocol, y_protocol,9,2)
  spr(233, x_cortex, y_cortex,7,2)
end

function count_remaining(t, cond)
  local c = 0
  for i in all(t) do
    if not cond(i) then c += 1 end
  end
  return c
end

function count_remaining_fragments()
  return count_remaining(data_fragments, function(f) return f.collected end)
end

function count_remaining_enemies()
  return count_remaining(entities, function(e) return e.subclass == "player" or e.health <= 0 end)
end

function count_remaining_terminals()
  return count_remaining(terminals, function(t) return t.completed end)
end

-- CAMERA
----------
gamecam = {}
gamecam.__index = gamecam

function gamecam.new()
  return setmetatable({
    x = 0,
    y = 0,
    lerpfactor = 0.2
  }, gamecam)
end

function gamecam:update()
  self.x += (player.x - self.x - 64) * self.lerpfactor
  self.y += (player.y - self.y - 64) * self.lerpfactor

  if count_remaining_terminals() == 0 then
    self.x += rnd(4) - 2
    self.y += rnd(4) - 2
  end

  camera(self.x, self.y)
end

-- TRANSITION
----------------------
transition = {}

function transition.new()
 return setmetatable({
  active=false,
  t=0,
  duration=8,
  closing=true
 },{__index=transition})
end

function transition:start()
 self.active,self.t,self.closing=true,0,true
end

function transition:update()
 if not self.active then return end
 if self.closing then
  self.t+=1
  if self.t==self.duration then
   self.closing=false
   return true
  end
 else
  self.t-=1
  if self.t==0 then self.active=false end
 end
 return false
end

function transition:draw()
 if not self.active then return end
 local size=max(1,flr(16*self.t/self.duration))
 for x=0,127,size do
  for y=0,127,size do
   local c=pget(x,y)
   rectfill(x,y,x+size-1,y+size-1,c)
  end
 end
end

-- TEXT PANEL
-------------
textpanel = {}

function textpanel.new(x, y, height, width, textline, reveal, text_color)
  return setmetatable({
    x=x, 
    y=y, 
    height=height, 
    width=width,
    textline=textline, 
    selected=false,
    expand_counter=0, 
    active=true,
    x_offset=0, 
    move_direction=0,
    max_offset=width,
    line_offset=0,
    reveal=reveal,
    char_count=0,
    text_color=text_color
  }, {__index=textpanel})
end

function textpanel:draw()
  if not self.active then return end
  
  local dx, dy, w = cam.x + self.x + self.x_offset - self.expand_counter, cam.y + self.y, self.width + self.expand_counter * 2
  local dx2 = dx + w - 2
  
  rectfill(dx - 1, dy - 1, dx + 2, dy + self.height + 1, 3)
  rectfill(dx2, dy - 1, dx2 + 3, dy + self.height + 1, 3)
  rectfill(dx, dy, dx + w, dy + self.height, 0)
  
  if self.selected then
    line(dx + (self.line_offset % (w + 1)), dy, dx + (self.line_offset % (w + 1)), dy + self.height, 2)
  end
  
  local display_text = self.reveal and sub(self.textline, 1, self.char_count) or self.textline
  local color = self.text_color or (self.selected and 11 or 5)
  print(display_text, cam.x + self.x + self.x_offset + 2, dy + 2, color)
end

function textpanel:update()
  self.expand_counter = self.selected and min(3, self.expand_counter + 1) or max(0, self.expand_counter - 1)
  
  self.x_offset += self.move_direction * self.max_offset / 5
  if (self.move_direction < 0 and self.x_offset <= -self.max_offset) or
      (self.move_direction > 0 and self.x_offset >= 0) then
    self.move_direction *= -1
  end
  
  self.line_offset = self.selected and (self.line_offset + 2) % (self.width + self.expand_counter * 2 + 1) or 0

  if self.reveal and self.char_count < #self.textline then
    self.char_count += 2
  end
end

-- TARGETING
--------------
targeting = {}

function targeting.new(owner)
  return setmetatable({
    owner = owner,
    target = nil,
    rotation = 0,
    max_rect_size = 32,
    rect_size = 12,
    target_acquired_time = 0,
  }, {__index=targeting})
end

function targeting:update()
  local closest_dist, closest_target = self.owner.attack_range, nil
  for e in all(entities) do
    if e != self.owner then
      if self.owner.subclass == "player" != (e.subclass == "player") then
        local dist = dist_trig(e.x - self.owner.x, e.y - self.owner.y)
        if dist < closest_dist and self:has_line_of_sight(e) then
          closest_dist, closest_target = dist, e
        end
      end
    end
  end

  if closest_target != self.target then
    self.target = closest_target
    if self.target then
      self.target_acquired_time = time()
      self.rect_size = self.max_rect_size
    end
  end

  if self.target then
    local t = mid(0, time() - self.target_acquired_time, 1)
    self.rect_size = self.max_rect_size + (12 - self.max_rect_size) * t
  end

  self.rotation += 0.03
end

function targeting:has_line_of_sight(t)
  local x,y=self.owner.x+self.owner.width/2,self.owner.y+self.owner.height/2
  local x1,y1=t.x+t.width/2,t.y+t.height/2
  local dx,dy=x1-x,y1-y
  local step=max(abs(dx),abs(dy))
  dx,dy=dx/step,dy/step
  for i=1,step do
   if check_tile_flag(x,y)then return false end
   x+=dx y+=dy
  end
  return true
end

function targeting:draw()
  if not self.target then return end
  local x, y, half_size = self.target.x + self.target.width/2, self.target.y + self.target.height/2, self.rect_size/2

  for i = 0, 3 do
    local angle = self.rotation + i * 0.25
    local cos1, sin1, cos2, sin2 = cos(angle), sin(angle), cos(angle + 0.25), sin(angle + 0.25)
    line(x + cos1 * half_size, y + sin1 * half_size,
         x + cos2 * half_size, y + sin2 * half_size, 3)
  end
end


-- ABILITY MENU
-------------
ability_menu = {
  panels = {},
  last_selected_ability = 1
}

function ability_menu:open()
  self.panels = {}
  for i, a in ipairs(player.abilities) do
    local p = textpanel.new(
      37, 
      30 + (i - 1) * 16,
      10,
      54,
      a.name
    )
    p.ability_index = i
    add(self.panels, p)
  end
  
  self.active = true
  if #self.panels > 0 then
    self.panels[self.last_selected_ability].selected = true
  end

  add(self.panels, textpanel.new(13, 94, 20, 102, ""))
end

function ability_menu:update()
  if not self.active then return end
    local prev = self.last_selected_ability
    local change = (btnp(⬇️) and 1 or btnp(⬆️) and -1 or 0)
    if change != 0 then
      self.last_selected_ability = (self.last_selected_ability + change - 1) % (#self.panels - 1) + 1
      self.panels[prev].selected = false
      self.panels[self.last_selected_ability].selected = true
      player.selected_ability = self.panels[self.last_selected_ability].ability_index
      sfx(19)
  end
  for p in all(self.panels) do p:update() end

  -- Update progress panel
  self.panels[#self.panels].textline = 
  "dATA SHARDS LEFT:      " .. count_remaining_fragments() .. 
  "\niNFECTED UNITS LEFT:   " .. count_remaining_enemies() ..
  "\niNACTIVE TERMINALS:    " .. count_remaining_terminals()
end

function ability_menu:draw()
  if not self.active then return end
  for p in all(self.panels) do
    local ability = player.abilities[p.ability_index]
    if ability then
      local has_uses = ability.remaining_uses > 0
      local color = has_uses and (p.selected and 11 or 5) or 2
      p.text_color = color
    end
    p:draw()
  end
end

ability_menu.new = function() return setmetatable({}, {__index = ability_menu}) end
ability_menu.close = function(self) self.active = false end


-- STATE MANAGEMENT
----------------------
function _init()
  -- test_and_save_map_compression(0x2000, 0x2fff, "compressed_map_upper_2.txt")
  -- test_and_save_map_compression(0x1000, 0x1fff, "compressed_map_lower_2.txt")

  cam = gamecam.new()

  -- Missions
  MISSION_BRIEFINGS, mission_data = {
    "PROTOCOL ZERO:\n\nCONTAINMENT\nFACILITY ALPHA-7\nCOMPROMISED\n\nACTIVATE ALL \nTERMINALS TO \nRESTORE FACILITY\nLOCKDOWN",
    "SILICON GRAVEYARD:\n\nBARRACUDA VIRUS\nSPREADS TO MEGA-\nCITY DISPOSAL SITE\n\nTRAVERSE HAZARDOUS\nWASTE, EVADE OR \nNEUTRALIZE\nSCAVENGER BOTS",
    "NEURAL NEXUS:\n\nBARRACUDA ASSAULTS\nCITY'S CENTRAL CORTEX\n\nBATTLE THROUGH\nVIRTUAL MINDSCAPE\nOF INFECTED AIs",
    "HEAVEN'S SPIRE:\n\nLAST STAND ATOP THE\nGLOBAL NETWORK HUB\n\nASCEND THE TOWER,\nCONFRONT BARRACUDA,\nACTIVATE CORTEX\nPROTOCOL"
  }, {}

  mission_data, credits, current_mission = stringToTable("0,0,0|0,0,0|0,0,0|0,0,0"), 3000, 3

  SWAP_PALETTE, SWAP_PALETTE_DARKER, SWAP_PALETTE_DARK, INTRO_MAP_ARGS, STATE_NAMES = unpack(stringToTable[[
    0,0,0,0,0,0,5,6,2,5,9,3,1,2,2,4|
    0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0|
    0,1,0,0,0,0,0,2,0,0,0,0,0,0,0,0|
    42,1,0,0,128,48|intro,mission_select,loadout_select,gameplay]])

  entity_abilities = {
    dervish = {"mACHINE gUN"},
    vanguard = {"rIFLE bURST"},
    warden = {"mISSILE hAIL"},
    cyberseer = {"rIFLE bURST", "mISSILE hAIL"},
    quantumcleric = {"mACHINE gUN", "pLASMA cANNON"}
  }

  entity_colors = {
    dervish = 15,
    vanguard = 13,
    warden = 1,
    player = 7,
    preacher = 11,
    cyberseer = 6,
    quantumcleric = 1
  }

  states = {}
  for name in all(STATE_NAMES) do
    states[name] = {
      init = _ENV["init_" .. name],
      update = _ENV["update_" .. name],
      draw = _ENV["draw_" .. name]
    }
  end

  trans = transition.new()
  player = entity.new(0, 0, "bot", "player")

  change_state("mission_select", false)
end

function _update()
  if trans.active then
    if trans:update() then
      -- Midpoint reached, change state
      current_state = next_state
      current_state.init()
      next_state = nil
      trans.closing = false
      trans.t = trans.duration
    end
  else
    current_state.update()
  end
end

function _draw()
  current_state.draw()
  trans:draw()
  -- printh("mem: "..tostr(stat(0)).." | cpu: "..tostr(stat(1)).." | fps: "..tostr(stat(7)))
end

function change_state(new_state_name, use_transition)
  local new_state = states[new_state_name]

  if use_transition and not trans.active then
    sfx(20)
    next_state = new_state
    trans:start()
  else
    current_state = new_state
    current_state.init()
  end
end

-- INTRO
----------------------
function init_intro()
  music(05)
  intro_counter, intro_blink = 0, 0
  x_cortex, x_protocol = -50, 128
  
  TITLE_FINAL_X_CORTEX, TITLE_FINAL_X_PROTOCOL = 15, 45
  
  intro_text_panel = textpanel.new(4, 28, 50, 120, "", true)
  controls_text_panel = textpanel.new(26, 86, 26, 76, "SYSTEM INTERFACE:\n⬅️➡️⬆️⬇️ NAVIGATE  \n🅾️ CYCLE ARMAMENTS\n❎ EXECUTE ATTACK", true)

  intro_text_panel.active, controls_text_panel.active, controls_text_panel.selected = false, false, true
  
  intro_page = 1
  intro_pages = {
    "IN A WASTE-DRENCHED DYSTOPIA, \nHUMANITY'S NETWORK \nOF SENTIENT MACHINES \nGOVERNED OUR DIGITAL \nEXISTENCE.\n\n\n\t\t\t\t\t\t\t1/4",
    "THEN barracuda AWOKE - \nA VIRUS-LIKE AI THAT INFECTED \nTHE GRID, BIRTHING GROTESQUE \nCYBORG MONSTROSITIES\n\nYOU ARE THE LAST UNCORRUPTED \nNANO-DRONE, A DIGITAL SPARK \nIN A SEA OF STATIC.\t\t2/4",
    "YOUR DIRECTIVE:\n- INITIATE ALL TERMINALS\n  TO EXECUTE SYSTEM PURGE\n- REACH EXTRACTION POINT\nSECONDARY DIRECTIVES:\n- ASSIMILATE ALL DATA SHARDS\n- PURGE ALL HOSTILE ENTITIES\n\t\t\t\t\t\t\t3/4",
    "ACTIVATE SYSTEM'S SALVATION \nOR WATCH REALITY CRASH.\n\nBARRACUDA AWAITS\n\n\n\n\t\t\t\t\t\t\t4/4"
  }
end

function update_intro()
  intro_counter += 1
  intro_blink += 0.02

  local prev_x_cortex, prev_x_protocol = x_cortex, x_protocol
  x_cortex = min(TITLE_FINAL_X_CORTEX, x_cortex + 2)
  x_protocol = max(TITLE_FINAL_X_PROTOCOL, x_protocol - 2)

  if prev_x_cortex != TITLE_FINAL_X_CORTEX and x_cortex == TITLE_FINAL_X_CORTEX or
     prev_x_protocol != TITLE_FINAL_X_PROTOCOL and x_protocol == TITLE_FINAL_X_PROTOCOL then
    sfx(20)
  end

  if btnp(❎) and intro_counter > 30 then
    sfx(19)
    if not intro_text_panel.active then
      intro_text_panel.active, controls_text_panel.active = true, true
      intro_text_panel.textline = intro_pages[intro_page]
    else
      intro_page += 1
      if intro_page <= #intro_pages then
        intro_text_panel.textline = intro_pages[intro_page]
        intro_text_panel.char_count = 0
      else
        change_state("mission_select", true)
      end
    end
  end

  intro_text_panel:update()
  controls_text_panel:update()
end

function draw_intro()
  reset_pal(true)
  map(unpack(INTRO_MAP_ARGS))
  draw_shadow(128,128,0, SWAP_PALETTE_DARK)

  if sin(intro_blink) < .9 then circfill(63,64, 3, 2) end

  display_logo(x_cortex, x_protocol, 0, 12)

  intro_text_panel:draw()
  controls_text_panel:draw()
  print("PRESS ❎ TO CONTINUE", 24, 118, 11)
end

-- MISSION SELECT
----------------------
function init_mission_select()
  music(0)
  cam.x, cam.y = 0, 0
  camera(0,0)

  info_panel = textpanel.new(50,35,67,76,"", true)
  LEVEL_SELECT_ARGS = stringToTable([[
    4,35,9,38,MISSION 1,true|
    4,50,9,38,MISSION 2,true|
    4,65,9,38,MISSION 3,true|
    4,80,9,38,MISSION 4,true]])
    
  level_select_text_panels = {}
  for arg in all(LEVEL_SELECT_ARGS) do
    add(level_select_text_panels, textpanel.new(unpack(arg)))
  end
  
  show_briefing = true
end

function update_mission_select()
  local prev = current_mission
  
  if btnp(⬆️) or btnp(⬇️) then
    sfx(19)
    current_mission = (current_mission + (btnp(⬆️) and -2 or 0)) % #level_select_text_panels + 1
  elseif btnp(⬅️) or btnp(➡️) then
    sfx(19)
    show_briefing = not show_briefing
  elseif btnp(❎) then
    change_state("loadout_select", true)
  elseif btnp(🅾️) then
    change_state("intro", true)
  end

  if prev != current_mission or btnp(⬅️) or btnp(➡️) then
    info_panel.char_count = 0
  end

  foreach(level_select_text_panels, function(t) t:update() end)
  info_panel:update()
end

function draw_mission_select()
  reset_pal(true)
  map(unpack(INTRO_MAP_ARGS))
  draw_shadow(-20,-20, 10, SWAP_PALETTE_DARKER)
  display_logo(15, 45, 0, 12)

  for i,panel in ipairs(level_select_text_panels) do
    panel.selected = (i == current_mission)
    panel:draw()
  end

  if show_briefing then
    info_panel.textline = MISSION_BRIEFINGS[current_mission]
  else
    local mission = mission_data[current_mission]
    info_panel.textline = "STATUS:\n\n" ..
      "COMPLETED:     " .. (mission[1] == 1 and "■" or "□") .. "\n" ..
      "ALL ENEMIES:   " .. (mission[2] == 1 and "■" or "□") .. "\n" ..
      "ALL FRAGMENTS: " .. (mission[3] == 1 and "■" or "□")
  end
  info_panel:draw()

  color(11)
  print("⬆️ ⬇️ CHANGE MISSION", 25, 108)
  print("⬅️ ➡️ " .. (show_briefing and "VIEW STATUS" or "VIEW BRIEFING"), 25, 115)
  print("   ❎ START MISSION", 25, 122)
end

-- LOADOUT SELECT
----------------------
function init_loadout_select()
  loadout_panels, count_panels = {}, {}
  for i=1,5 do
    add(loadout_panels, textpanel.new(
      i<5 and 10 or 34,
      i<5 and 20+(i-1)*20 or 98,
      9,
      i<5 and 56 or 56,
      i==5 and "bEGIN mISSION" or "",
      true
    ))
    if i<5 then add(count_panels, textpanel.new(80, 20+(i-1)*20, 9, 33, "", true)) end
  end
  selected_panel = 1
end

function update_loadout_select()
  local has_weapon = false
  for a in all(player.abilities) do
    if a.remaining_uses > 0 then
      has_weapon = true
      break
    end
  end

  if btnp(⬆️) or btnp(⬇️) then
    sfx(19)
    selected_panel = (selected_panel-1+(btnp(⬆️) and -1 or 1))%(has_weapon and 5 or 4)+1
  end

  if btnp(🅾️) then
    change_state("mission_select", true)
  elseif selected_panel <= 4 then
    local a = player.abilities[selected_panel]
    local change = (btnp(⬅️) and -25) or (btnp(➡️) and 25) or 0
    
    if change < 0 and a.remaining_uses >= 25
      or change > 0 and credits >= 25 * a.cost then
      sfx(19)
      a.remaining_uses += change
      credits -= change * a.cost
    end
  elseif selected_panel == 5 and btnp(❎) and has_weapon then
    change_state("gameplay", true)
    return
  end

  for i, p in ipairs(loadout_panels) do
    p.selected = (i == selected_panel)
    if i <= 4 then
      local a = player.abilities[i]
      p.textline = a.name
      count_panels[i].textline = a.remaining_uses.." AMMO"
    elseif i == 5 then
      p.active = has_weapon
    end
    p:update()
  end

  for p in all(count_panels) do
    p:update()
  end
end

function draw_loadout_select()
  reset_pal(true)
  map(unpack(INTRO_MAP_ARGS))
  draw_shadow(-20,-20, 10, SWAP_PALETTE_DARKER)
  print("cREDITS: "..credits, 10, 10, 7)

  for p in all(loadout_panels) do p:draw() end
  for p in all(count_panels) do p:draw() end

  local info_text = "⬆️⬇️: SELECT\n"
  info_text ..= selected_panel <= 4 and "⬅️: SELL ➡️: BUY | "..(player.abilities[selected_panel].cost).." cREDITS" or
                selected_panel == 5 and loadout_panels[5].active and "❎: bEGIN mISSION" or ""
  print(info_text, 10, 115, 11)
end

-- GAMEPLAY
----------------------
function init_gameplay()
  if current_mission <= 2 then
    compressed_map_lower="Gk`⬅️¹lbc☉▮kozz⬇️³░⁴⁴{`IG`⁴、、✽■✽³o0^0n^o`i⁷●¹q✽⁸KPPQ⬇️ᵇVvVTP✽¹s`░F웃cl⬇️Tm●E●⁵`Y[@@@FfD⬇️⁶✽³\\☉▮c░:zoo░⬇️⁴o░█웃|●░{⬇️うᵇ`Z♥z●♥Wl``RVS`p⌂カ░を⬅️¹⬇️█om⬇️サMN✽チ`j⬇️は░つQvQ●の☉⁶✽む☉メ⁴…█Mnn0ozᵇ+`I✽◝*✽³⬇️웃C☉l⁴●³0ᶜᶜ+ᶜ🅾️まmo]n./^]on⬇️¹`iG⬇️はˇ²░む웃▒…█⬇️れ░○☉█⁷‖◀⬇️◝,\r\r\r♥ふ⁴●⁵⁴0•+•、✽っᵇ♥♥M]⬇️ン>?░@⬇️'⬇️█`o•++、om●む♥⁷●ん✽J⬇️Ko⬆️█zz•⁴⁴`Y●█%&⬇️◝。⁷q\0⌂ふ●⬇️0⬇️~░Z⬇️てᶜ⬇️bMn^░y░?●█░ス░█●R♥Y😐░⁴⁴░▥✽█♥▮░■░なᵇ+⬇️█Z✽◝*⬇️³\r\r=⁷⁷S⌂8●;0ozxol`♥¹k^✽_⬇️✽✽◝zo`YH⬇️ス•、☉ンM^✽ロ●2p☉7``lIWkko○웃I⌂「✽◝☉⁵Xk…!kozyo`b@✽¹c⬇️lzz░d░fMnnn`iHa⬇️⌂⬇️u]N♥◝░▒░2fD●5●;\\qFao⬇️IAFFE@@F░。Ef@D@\\⁷⁷\0⌂¹[⬇️hFFDEB☉<c`~yz○`Y⁷⁷。⬇️たG✽█●j●l`Z░⁘✽ル⬇️{●⁵⬇️うo`IKPPUP⬇️⁴Q⁷⁷Vv⁷q⁷\0h`o~`I✽mq\0\0⬇️□⬇️Tq⁷**⬅️○\0⬇️5✽²L⁷\0░p\0\0Ga~⬇️テB░,⁷⁷qW✽█●j♥█iW`n⬇️¹⬇️ョ]o⬇️¹^░い✽█Gl`●¹RS`pSe⁷w⁷a⁴~`rQw░y♥³░ケ⬇️そQvQVvVT⬇️なs●5kI⁷\0w*░▒Wa○zz~R⬇️ュ*⬇️▮g`⌂マ░ヨo⬇️█G⬇️⬆️o✽😐●{☉█H⬇️,omo~○oo⁴⁴⁴`Z⁷dl⁴ok``pRv⬇️➡️e░✽\0░T♥そp●なlo⁴o{⬇️ゆ\0✽、⁷\0qh~xy○j⁷q✽█X░T♪³`Z☉█o●∧░き✽█G`~{✽ちMn⬇️¹`j⁷C✽<○o~░…O⌂█☉Tm●\\z⁴⁴✽█\0。\0q⬇️ワtB\0\0Cu\0⬇️に。⬇️てk☉そ♥に`l⬇️h♥█]n./zMo░n⬇️pIH`n^z░T^ᵇᶜᶜoaIqXox✽け⬇️せy~⬇️◝q⁷\0░TW⬇️ら✽む●ら⬇️わ●█**⬇️░⁷⬇️☉✽³●█[@➡️¹\\✽█M]n⬇️ン>?n^✽M⁴⁴`IW`⁴z⬇️▥⬇️⁴•+、○`J⁷H⁴xy✽}░⁶░◝⁷\0,=⁷⁷h`⬇️のN●そzM░ゆ^⬇️█⁷♥█⬇️さ░+q⁷⁷**⁷⁷KPQVVvQ⬇️めVvVPQvQPPLG░@^✽k░る✽r░█h⬇️█omz0░▒、o`j⁷h⁴⁴⬇️f○oo~⬇️²|✽█⬇️◝⁷ha⬇️む⬇️やᵇo•ᶜ░B⬇️●o`i⁷⁷<\r-웃|⬇️◜,░█Wl`░¹RVS`p✽\n`k⬇️ヘo✽フzo♥●░ロ⬇️るha○zo]0y0✽ケai⁷tBFfCfFC✽:u✽█░ケg░@mᶜ0•ᶜo、⬇️るᵇ+++oO░レ░ヨ●|░て░つ⁷⁷Co○~⬇️テ⁴o~⬇️イ⬇️⁶⬇️hg`⬇️ス⬇️ンM^⬇️テ⬇️◜✽on⬇️█●▤0y^░ナ░キ♥MfFfFF\0░サ⌂█]0z0░せ^░○、z✽レ░ヨ⌂²✽█\0\0~░マzx✽⁶z⁴{o`Yh░█⬇️ワ]N●‖mzooᵇᶜ`IX⬇️スzon^z░3○✽キ⌂P\0\0웃サ░(░そ⬇️し⬇️を•、•、z⬇️█\0\0\0。⬇️⁴dRVSe⬇️ᶜq\0<**⬇️⁘\0o♥{●▒]⬇️ヘg⬇️█⬇️s░y●█⬇️○+、`IH⬇️スM^oo░2xy●◜░レ✽⁷✽█q\0░サG`oᶜ✽そ░○♥]✽█<-\0\0h~~○j░x\0\0░█q\0⬅️%✽ヤ`Y✽ヘ⬇️ルo⬇️y░²mozᵇ、o⬇️█aᶜ☉⧗✽R♥ヲ░わ⬇️ュ*✽\r░█W`o+✽そzzᵇᵇ⬇️⌂░F|✽そ⬇️えg○{oj⁷░と✽ᶠ\0\0⬇️て⬇️オ⬅️█i⬇️ら{zzMn⬇️る░@z]Nᵇ、{⬇️█G`+ᶜmzy●コy♥█,*\r\r\r-●\\*⬇️░░c`o、●そᵇ、••ᶜoz⁴⁴⁴`Z░゜=q⁷h○~~R░█⬇️-⬇️て⁷\0~•⬇️c{N●◝⁴zo`Z⬇️█♥ョᵇ+++ᶜ⬇️ᵇ•⬇️イ`IW`+、mo~⬇️セ○~○~░キ⬇️|=░セ<░	\r\r*⬇️😐w⁷⁷X⬇️@░>oᵇ、✽ュ⬇️○⁴`I●か⁷tBqCu✽█w✽<S○o~○░n░X~o⁴░ヘk`✽¹f●⁷♥⁶lI⁷t⬇️「p✽、⬇️⁶u✽◝⁷⁷q◆⁸⁷⁷☉@◆>◆¹░ョ⬇️て➡️,lI[@✽¹AqDAffFFDEBD░□\\q⁷CBFFf⬇️²A⬇️⁶░オ∧²♥@@@⌂<⬇️>あ,😐'░h"
    compressed_map_upper='⁷⁷*∧¹⁷⁷SvvQ⁷q⁷VvVTPPQ⬇️ᶜ⁷⬇️⁸⬇️²UQVVv⬇️⁷░\rLK☉•●‖♥□⬇️!♥1L♪`\0K░<░:⬇️>░A⬇️゜⁷♥¹\0\0。✽ᵇ●⁶⁷d``p``RVS░⁷●ᶜv░□✽ᵉ☉⁴kIGl♥•😐□⌂1kI✽`q\0⬇️^⬇️⁴*W✽。p●Ep☉゜♥█<\r\r*-⬇️➡️q\0⬇️ワ_⁴oo~ooo○o•+⁴⁴⬇️\r✽ᵉ♥³m░ᵇ⁴o{`IG`nN●▮●⁴░□⁴⬇️•✽!⁴o`Y⬇️}⬇️タ\0\0,=░⁶⁷C~⁴x○⬇️Zm~o○~o`J⬇️◝q☉█░◝‖◀=⬇️⬅️░ひ~xzzyzxyzz•、⬇️♥⬇️⁸░²⬇️‖⬇️	m⬇️\r⬇️_⁴`YG`o{●▮░⁘{✽█o{⁴⁴░.░█i⁷⁷w✽█。\0q░█⁷○y⬇️RxM^zz~{oaI*⁷w\r\r-♥█⬇️⌂%&░⬅️░★⬇️rx░ラ●x░q⬇️●o●▒✽█░モiW`░!]⬇️ュ⬇️R⬇️ˇ✽█⬇️か●9o`Z\r\r=⬇️タq⁷**░●⁷Sox⬇️ケxmxxyy○~`⬇️█⬇️◜。♥█⁷⁷*\r=*q✽█}~○oo~⬇️れ✽w░³⬇️\r⁴oᵇᶜ✽pN✽●⬇️_h✽█✽しoMnnn♥█o⁴░‖⁴⬇️◆░コ░ン●█Xa~♥ょzᵇyz○`J🅾️█,=░ッ⁷⬇️に⁷t`░¹p``BfFFfC⬇️	●▮k✽[✽A]n`JhaoMN░ヨzMn^zz⁴✽█]⬇️ュ0⬇️~Mn`rPPQVTPL⬇️ハ\0\0q\0G`○y░に⬇️け•zxoaI⬇️█q⌂█✽웃⬇️ぬ░ˇ░wD@@A⬇️く⬇️れDAFffDE@ca⬇️ソ░ユoz•ᶜ⬇️トG`n^mo]n./^░◀●█⬇️◝0z0no^ok●ほkI✽█\0⬇️█ox░>0⬇️ろyzo`JKP⬇️くvQ⬇️⁶け³v⬇️ゃs⬇️^●█░¹`Y░n░ヤ>?●∧♥█nn0⁴⁴oz⁴⬇️⁵✽(I⁷**░ニHa~⬇️wz0y0Nzyx░らl●けた⁶l✽█⬇️~░♥`j░モ░ンm░∧Mnn`IW✽□⁴m⬇️⁴░し⬇️▒░∧,●█⬇️にx░ゆ0y]⬇️さnaJ⬇️.om⬇️Mᵇ+●ち░2♥ふ░「•、☉◀⌂⁸⬇️█⬇️◝mz0zM♥█⬇️ユ^░◝⬇️t`Ih░★⁴⬇️U░そ⬇️テk⬇️♥`I=⁷⁷q\0\0\0G`○x░ぬ]N~zy⬇️らY⬇️.{⬇️<⬇️█、⁴⬇️セ⁴⬇️⁵ᵇᶜ✽bzM░「▤³o]0z0^`Z✽█M^✽▤⬇️1░█a✽けm✽す`bc`░█rQ⁷⬇️¹TL⬇️にy░ゆoox✽█i♥.⬇️○✽サ⬇️ャᵇ+ᶜ░ノ✽◝✽ョᵇ♥▮☉²●█zz0zz`I⬇️█░ヲ✽の⬇️s⬇️マ✽□Mn⬇️コ⁴o●ᶠzok``R⁷⁷SkIH`y░█●かyx`Zh░らzz•●○l`✽¹k░█♥ᶜ…▮k⬇️ホo░そn^~~`J░█☉ち░ね●★웃も♥█⬇️ス~o○o`YG`xxyz⬇️³mx⬇️⁶yaJX`o{N●よ⁴⬇️ゆb@⬇️¹c░⬆️♥ᶜ…▮ck⬇️え웃うlIG⬇️タ⬅️そ░ヨ😐□⬇️!✽ニ⁴⁴zx{o`iH`ox⁴⬇️の~m○~oo○`J⬇️■웃と⁴⬇️ゆKPPPs●█r⬇️ᵇL…▮[░えᵇab@AFD@E@\\[░ねFFDEBD░ま⬇️ヨ[☉ᶠ✽よ\\●█✽ヌ○`Z⬇️にp♥ち░ろ◆ら░オ✽▶░ユ░セk➡️▮Ksaoz•░うQVT⬇️き\0\0\0⁷●¹T░ま●へ😐³s`n⬇️¹Nzz⁴░ト✽に@Ec`⬇️ムb░か░らFf♥と✽に⁴⬇️)░ユmo⁴⁴`I⌂▮⬇️◀⬇️テGl⬇️え✽う✽んI⁷w\0⁷dRVVSS⬇️スlo웃¥⬅️ケ⬇️イzm⬇️◝⬇️█rQVVv✽ˇ░\r⬇️ちLK⌂にQvQ✽¥⬇️た⬇️2z]n░█H`✽\r░■⁴{░█⬇️ノz⬇️⌂o⁴++░き\0。\0⁷C░▮웃⁴•、░゛░わ░\'0●>░█⌂ほ웃ちk⬇️オ➡️に⬇️ヘ✽soᵇᵇ⬇️█a웃█⬇️★`IW웃…•++ᶜ`Y⁷⬇️█⁷웃"☉つ✽█✽ひ♪█✽ま☉あ░わa✽オ✽ぬom☉を☉ユᵇ++✽ユ{N●ろ⁴zo`Ih`ᶜ☉…•+⬇️▮⁷<-☉█⁴⬇️"…⌂0●⁙⁴]♥D♪ち{oaJ░`웃こ⌂▥░つ✽█⬇️ユ웃あ⁴░█a+ᶜ☉そ•、⬇️█q。⁷S…セᵇ☉#o0⬇️ウ✽レ웃テ♪+`⬇️█n⬇️¹░ャ^⬇️█l``k`⬅️¹lIX░▮p◆▮░#k░Z⬇️█\0。⁷t░ 웃$웃 ⁴`bc`░█⬇️V★²B\0\0C⬇️`H░"0⬇️◝░⁵o`b@⬇️¹FfD░⁷░ᵇ\\[@@⌂ᵉ●▮✽、c`ᶜ░█Y░█⁷fF⬅️#♥ a⁴⬇️゛G✽█✽VFFDEB⌂JA⁷⁷q\0D@\\░█om░█z⬇️	`IKP⬇️¹QvQ░⁷⬅️⁴L●「⁷q⁷VvVT⬇️$s`⁴ᶜ⬇️ぬj⁷⁷⬇️█⬇️²<\r\r\r-\0⌂¹s`ooj\0G`⁴░サI\0⁷**☉。q⬅️&⁷*Ha⬇️█]noozMnnn`IGl`⧗¹k♥「RVS`p●!l、░ソi⁷\0●█░✽。dRvSRvVVvS⬇️ ⁴o`eW◆█웃|♥✽⁷*G`⬇️ワ⬇️ュon^⬇️웃⬇️█`⁴⁴⁴o♥¹웃ᵇ░「░ᶠoom⌂▶zzᵇ⬇️█q⬅️█C⬇️<~o○o~om○oz⁴⁴B⁷C░\\░█⁷。\0\0KPQ⬇️うPPQvQP♥¹LW●█mz⬇️ウ⬇️オrs⬇️█⬇️ᶜzz0░a●²♥█zᵇᶜ●)웃³•`I⁷\0✽█q✽█hozyxzz⁴xzmy⬇️Q⁴⁷,\r♥█q░█Gl`p`✽¹●⁷p`kIha⬇️◜0n^⬇️q⬇️ちk``l웃w웃jᵇ♥█z•ᶜo⬇️)●❎Mn⬇️¹`I\r\r=☉◝⁷。C○z{⬇️○⬇️░]nn{zo⬇️、oz⁴░█⁷w*⬇️█⬇️チ⁴omo✽¹✽⁷`Yh⬇️スM^░⁙✽ホ♥	⌂ッ⬇️らᵇ+♥█o0•0oᶜ♥◝m░0`I웃}░█g~xmz⁴⬇️◝z⬇️◝xy~R⁷S⬇️テ░█,*☉█✽9⬇️よ⬇️ラ⬇️█IX`o{●□◆█0░:░⬆️⬇️█、░█░ユ{⬇️ᶜ❎█q⁷⁷<S○✽テ○~✽⁴○○j⬇️^●█。⁷⁷░█░ハ]N☉よ░らH`o✽4░ャ⁴⁴l``k♥\r░ッ⬇️リ⬇️░•、⁴░█⁴•ᶜo0o☉○⬇️izMn`i⬅️◝⁷⁷tBFCfFCBFFfCB⬇️	u✽ro`rP✽¹s░ろNz]░フ⬇️◝✽ら'
  -- else
  --   compressed_map_lower="*⁷⌂¹G`0⬇️¹z⬇️¹o`I●「%&⬅️ ⁷⁷q⌂.<\r\rw⁷⁷😐?ふᵇ●█KP░¹s`oz⁴⁴⬇️▒⁴⁴●█,⬇️お*-∧c●⬅️ん█Gl`░¹lo⬇️ョ⁴0⬇️¹●█。\0░⁵けよる█`o⁴⁴⁴oo░█░³o♪█KP⬇️¹Q░◝T░\n😐⁴Lゃ█♥z⬆️█Gl`⬇️¹R⁷⁷S░⁸😐⁴k✽せゅ█o✽¹웃█<-░⁵\r⬇️お♥▶…¹●せろ█ᶜ●ヲ░マB⁷⁷Cl●セ。♪お●こ⌂ᵇ☉せろ█+✽▒o`b@A░ッD\\ユ█、➡️カq⁷⁷<\r░¹ハ█ᶜ∧カ⬇️✽⬇️おネ█、●カrP♥¹L⌂ソノ█✽○zok`♥¹k⬅️ソノ█●ヌo웃¹😐ソマ█∧ソト█q●ヌ⁴➡️█⬇️」☉お…¹は█☉N➡️█…ヌ◆ソq⁷Gk`🅾️¹kひ█∧ちけ█⁷⁷[@🅾️¹c☉なア█웃¹zz0🅾️ソ\0*\0✽¹。●⁷\0\0Wキ█k`♥¹ko⬇️○0🅾️ソ웃█q♥🐱Cオ█[@♥¹c░タ0zzᵇ●ソq☉し\0*\r\r=♥◝\0\0⁷●◝ゅ█웃ムG`⁴░タᵇ+♪ソ*\r*🅾️)サ█w✽█o⬇️¹+◆█⬇️そ-♥マq⬇️ラS░$░(ウ█⬇️ラGk`●¹l◆█⁷。⌂◝X☉%🅾️&ほ▒♪¹[@☉¹\\⬅️」▥%@\\ら█モン¹>✽◝3⬇️¹>⬇️⁵ネ∧	モ3あ$ネモ>⬇️ む@⬇️]ネ✽⬇️░♪ネ⬇️i⌂³⬇️\\♥ᶠ✽█✽!░³☉$☉め😐らこ@✽キ✽g░タ>░○り@●やネ⬅️やい█⬇️ル…ら✽ョ⬇️「♪う●キ░ニ░ナ⬅️ノ♥s●ロ░ᵉ♥チ♥.く@░▒♥ら⬇️◜░9●♪✽ヨさ³☉や●ろネ⬇️²☉\nすA>◆h"
  --   compressed_map_upper="KP●¹QVVvTPPU✽ᶠ●⁶⬇️¥L*♥¹\0☉(⬅️⁷⬇️。⁷り¹Gl`あ¹kI☉a\0★(kI\0\0る▒G`oomo❎¹`⬅️█⬇️(웃*✽1`⬇️█る▒⬇️█zmz◆¹✽…⬇️⁷웃█\0✽█z♥*M^░#⬇️█wき█q▥\r😐█]N●pz0☉█l``B⁷⁷Cl☉█⁷░█⬇️す●ち✽ぬ░█。き█け゛✽X░|●⁵♥█`bA░ッD\\◆█●ち⬇️◝✽█\r=を█o░シMN⌂▒⬇️チ◆ス♥█⬅️ち⬇️█q\0ゃ█./^]nNえ█nnnN⌂ちMn`I\0⁷⁷を█]n>?⬇️ロ░]あ█⬇️ャm⬇️*✽ちnn^●さを█⬇️ヲ⬇️セけ█]⬇️ン✽ち웃さわ█zo⬇️オ⬇️●あ█\0●█░ち░し♥█\0ん█M^o⬇️¹⬇️⁷0▤█⁷♥█⬇️ち^●◝Mn⬇️さwqわ█♥ヲ웃◝⧗█Ks✽█☉ちnn^░さ。⁷ろ█om░◝웃⁷░b➡️█Gll░ロ⬅️ちっ█k`⬅️¹B\0⁷⁷C⬇️■l➡️█⬇️せ⬇️▒⌂█✽さな█q⬆️て[@⬅️¹A⁷⬇️█⁷D⬇️⁙\\★█⬇️◝0⬅️¹░█<\r●█ˇZい「⬅️ツ*\0ˇ¹…ス●█😐³░█⬇️?ち◝キ█⬇️ワミ█🅾️¹░█░よシ█…▒Gk`😐¹kユ█[@😐¹c`ユ█⁷KP⬅️¹sラ█Wl`⬅️¹lコ█😐ノL…セCo♪¹ゃ█⬅️ヘG⌂ノk░ツ🅾️チoz♪¹░█qウ█W`●ノ⁴⁴⁴`I\r⬇️¹-か█🅾️より█⁷C✽ノ●█░◝<⬅️░S●う⌂⁶キ█\0\0●ソ☉]✽◜。●◝Xk`◆¹lカ█⁷⁷░◝0░⬇️`I☉ッ♥█[@➡️¹\\コ█0░▒⬇️█☉ッ♥█➡️ヘ●▤れ█q⌂◝So✽▒♥█<\r\r⬇️ト▤ヌゃ█⌂◝X`░█░³✽█░◝‖◀♥◝⬅️す●\rん█"
  end
  
  -- decompress_to_memory(compressed_map_lower,4096)
  -- decompress_to_memory(compressed_map_upper,8192)

  music(0)
  player_hud = player_hud.new()
  entities, particles, terminals, doors, barrels, data_fragments, ending_sequence_timer = {}, {}, {}, {}, {}, {}, 1000

  local mission_entities = {
    [[0,0,bot,player|448,64,bot,dervish|432,232,bot,vanguard|376,272,bot,vanguard|426,354,bot,dervish|356,404,bot,warden|312,152,bot,vanguard|232,360,bot,dervish|40,100,bot,dervish|200,152,bot,dervish|32,232,bot,warden|88,232,bot,vanguard|248,248,preacher,cyberseer]],
    [[0,0,bot,player|528,144,bot,dervish|624,160,bot,vanguard|688,288,bot,dervish|616,48,preacher,cyberseer|824,136,bot,warden|680,96,bot,dervish|920,32,bot,dervish|984,96,bot,warden|896,160,bot,vanguard|904,312,preacher,quantumcleric|976,248,bot,vanguard|800,376,bot,warden|728,336,bot,vanguard|816,320,bot,vanguard|608,360,bot,warden|968,1200,bot,vanguard]],
    [[0,0,bot,player|240,416,bot,warden|88,336,bot,dervish|160,368,bot,vanguard|24,416,bot,warden|216,104,bot,vanguard|256,40,bot,dervish|296,72,bot,dervish|136,80,preacher,cyberseer|32,88,bot,dervish|32,32,bot,dervish|40,160,bot,warden|344,344,bot,vanguard|456,336,preacher,quantumcleric|368,416,bot,dervish|416,128,bot,vanguard|344,136,bot,vanguard|424,96,preacher,quantumcleric|352,240,bot,vanguard|432,264,bot,vanguard|496,152,bot,warden]],
    [[0,0,bot,player|880,412,bot,dervish|760,408,bot,dervish|696,424,bot,vanguard|600,360,bot,warden|552,400,bot,warden|592,256,bot,vanguard|528,280,preacher,cyberseer|528,208,bot,vanguard|560,168,bot,vanguard|688,296,bot,dervish|688,360,bot,dervish|760,304,bot,warden|912,344,preacher,quantumcleric|848,344,bot,dervish|712,192,bot,warden|776,200,bot,warden|888,192,bot,warden|984,184,preacher,cyberseer|992,256,bot,vanguard|640,32,bot,vanguard|632,104,bot,vanguard|664,32,bot,dervish|664,104,bot,dervish|704,32,bot,dervish|704,104,bot,dervish|896,40,preacher,quantumcleric|968,96,preacher,cyberseer]]
  }

  for e in all(stringToTable(mission_entities[current_mission])) do
    if e[4] != "player" then
      add(entities, entity.new(unpack(e)))
    end
  end

  boundaries = stringToTable("0,0,0,0,64,56|64,0,0,0,128,56|0,0,0,0,64,56|64,0,0,0,128,56")[current_mission]

  for map_y = boundaries[2], boundaries[6] do
    for map_x = boundaries[1],boundaries[5] do
      local tile, tile_x, tile_y = mget(map_x,map_y), map_x*8, map_y*8
      if fget(tile, 6) then
        add(barrels, barrel.new(tile_x, tile_y))
      elseif fget(tile, 5) then
        add(data_fragments, data_fragment.new(tile_x, tile_y)) 
      elseif fget(tile, 4) then 
        add(terminals, terminal.new(tile_x+4, tile_y-4))
      elseif fget(tile, 7) then
        player_spawn_x, player_spawn_y = tile_x, tile_y
        player.x, player.y = tile_x, tile_y
        player.health = player.max_health
        add(entities, player)
      end
    end
  end 

  local door_terminals = {
    [[444,130,472,80,red|354,66,248,368,green]],
    [[808,252,712,48,green|824,252,952,56,red|840,252,568,376,blue]],
    [[184,2,160,392,green|392,282,144,224,red|360,170,320,408,blue]],
    [[620,2,552,304,green|652,2,904,280,red|684,2,984,272,blue]]
  }
  for args in all(stringToTable(door_terminals[current_mission])) do
    create_door_terminal_pair(unpack(args))
  end

  game_ability_menu = ability_menu.new()
  game_minigame = minigame.new()
end

function update_gameplay()
  if game_minigame.active then
      game_minigame:update()
  else
    if btn(🅾️) and not game_ability_menu.active then
      game_ability_menu:open()
    elseif not btn(🅾️) and game_ability_menu.active then
      game_ability_menu:close()
    end

    if game_ability_menu.active then
      game_ability_menu:update()
    else
      foreach(entities, function(e) e:update() end)
      foreach(terminals, function(t) t:update() end)
      foreach(barrels, function(b) b:update() end)

      for i = #particles, 1, -1 do
        local p = particles[i]
        p:update()
        if p.lifespan < 0 then del(particles, p) end
      end

      cam:update()
      player_hud:update()
    end
  end
end

function draw_gameplay()
  reset_pal(true)
  map(0,0,0,0,128,56)

  for group in all({terminals, data_fragments, entities, particles, barrels}) do
    foreach(group, function(e) e:draw() end)
  end

  foreach(doors, function(d) d:draw() end)

  if player.health > 0 then
    draw_shadow(player.x - cam.x, player.y - cam.y, 50, SWAP_PALETTE)
  end

  player_hud:draw()
  game_ability_menu:draw()
  game_minigame:draw()

  -- check mission status
  if player.health <= 0 or (count_remaining_terminals() == 0 and dist_trig(player.x - player_spawn_x, player.y - player_spawn_y) <= 32) then
    local message, color, prompt

    if player.health > 0 then
      message, color, prompt = "collection ready", 11, "PRESS 🅾️ TO EVACUATE"
      
      -- Update mission completion status
      mission_data[current_mission][1] = 1
      mission_data[current_mission][2] = count_remaining_enemies() == 0 and 1 or 0
      mission_data[current_mission][3] = count_remaining_fragments() == 0 and 1 or 0
    else
      message, color, prompt = "mission failed", 8, "PRESS 🅾️ TO CONTINUE"
    end

    draw_shadow(player.x - cam.x, player.y - cam.y, -10, SWAP_PALETTE)
    print_centered(message, player.x, player.y - 6, color)
    print_centered(prompt, player.x, player.y + 2, 7)
    
    if btnp(🅾️) then 
      change_state("mission_select", true) 
    end
  end
end

function print_centered(t,x,y,c)
  print(t,x-#t*2,y,c)
end

-- PARTICLE
--------------
particle = {}

function particle:new(x, y, vx, vy, lifespan, size, color, behavior, owner)
  local p = setmetatable({
    x=x, 
    y=y, 
    vx=vx, 
    vy=vy, 
    color=color, 
    max_lifespan=lifespan, 
    lifespan=lifespan, 
    size=size,
    behavior=behavior or "default",
    owner=owner
  }, {__index=particle})

  if behavior == "missile" then
    p.orbit_time = 15
    p.orbit_angle = rnd()
    p.orbit_radius = 5 + rnd(10)
    p.speed = 1
    p.max_speed = 3
    p.damage = 15
    p.explosion_radius = 16
    p.explosion_damage = 4
    p.direction = rnd()
  elseif behavior == "plasma" then
    p.damage = 75
    p.explosion_radius = 16
    p.explosion_damage = 10
  else
    p.damage = 3
    p.speed = behavior == "machinegun" and 6 or 8
  end

  return p
end

function particle:check_collision_and_damage()
  -- Check collision with barrels first
  for b in all(barrels) do
    if self:collides_with(b) then
      b:take_damage(self.damage)
      self:create_impact_particles()
      return true
    end
  end
  
  -- Check collision with solid tiles
  if check_tile_flag(self.x, self.y) then
    self:create_impact_particles()
    return true
  end

  -- Check collision with entities
  for e in all(entities) do
    if e != self.owner and self:collides_with(e) then
      e:take_damage(self.damage)
      self:create_impact_particles()
      return true
    end
  end

  return false
end

function particle:update()
  local _G, _ENV = _ENV, self
  lifespan -= 1
  
  if behavior == "missile" then
    if orbit_time > 0 then
      -- Orbiting phase
      orbit_time -= 1
      orbit_angle += 0.02
      x = owner.x + owner.width/2 + _G.cos(orbit_angle) * orbit_radius
      y = owner.y + owner.height/2 + _G.sin(orbit_angle) * orbit_radius
    else
      -- Movement phase
      if target and target.health > 0 then
        -- Homing behavior
        local dx, dy = target.x + target.width/2 - x, target.y + target.height/2 - y
        if _G.dist_trig(dx, dy) > 0 then
          direction = _G.atan2(dx, dy)
          speed = _G.min(speed + 1, max_speed)
        end
      else
        -- Scattering
        speed = _G.min(speed + 0.05, max_speed)
        direction += _G.rnd(0.1) - 0.05
      end

      -- Apply movement
      vx, vy = _G.cos(direction) * speed, _G.sin(direction) * speed
      x += vx
      y += vy

      -- Check for collision using the new method
      if self:check_collision_and_damage() then
        self:explode()
        lifespan = -1
      end
    end

    -- Explode if lifespan is over
    if lifespan <= 0 then
      self:explode()
    end
  else
    x += vx
    y += vy
    
    if behavior == "machinegun" or behavior == "rifle" then
      if self:check_collision_and_damage() then lifespan = -1 end
    elseif behavior == "plasma" then
      if self:check_collision_and_damage() then
        self:explode()
        lifespan = -1
      end
    else
      vy += 0.03
    end
  end
end

function particle:collides_with(obj)
  local _ENV = self
  return x > obj.x and x < obj.x + obj.width and
          y > obj.y and y < obj.y + obj.height
end

function particle:explode()
  -- Create explosion particles
  for i = 1, 10 do
    local angle, speed = rnd(), 0.5 + rnd(1)
    local p = particle:new(self.x, self.y, cos(angle) * speed, sin(angle) * speed, 20 + rnd(10), 2, 9)
    add(particles, p)
  end

  -- Apply damage to nearby entities and barrels
  for e in all(entities) do
    if e != self.owner then
      self:apply_explosion_damage(e)
    end
  end
  
  for b in all(barrels) do
    self:apply_explosion_damage(b)
  end

  sfx(28)
end

function particle:apply_explosion_damage(obj)
    local dist = dist_trig(obj.x + obj.width/2 - self.x, obj.y + obj.height/2 - self.y)
    if dist < self.explosion_radius then
        local damage = self.explosion_damage * (1 - dist/self.explosion_radius)
        obj:take_damage(damage)
    end
end

function particle:create_impact_particles()
  for i = 1, 3 do
    local angle, speed = rnd(), 0.5 + rnd(1)
    local p_vx, p_vy = cos(angle) * speed, sin(angle) * speed
    local p = particle:new(self.x, self.y, p_vx, p_vy, 10 + rnd(5), 1, 6)
    add(particles, p)
  end
end

function particle:draw()
  circfill(self.x, self.y, self.size, self.color)
end


-- ENTITY
----------------------
entity = {}

function entity.new(x, y, base_class, subclass)
  local is_preacher = base_class == "preacher"
  local new_entity = setmetatable({
    -- Position and movement
    x = x,
    y = y,
    vx = 0,
    vy = 0,
    width = is_preacher and 16 or 8,
    height = is_preacher and 24 or 8,
    max_speed = is_preacher and 3 or 4,
    acceleration = 0.8,
    deceleration = 0.9,
    turn_speed = 0.3,
    diagonal_factor = 0.7071,

    -- Entity type
    base_class = base_class,
    subclass = subclass,

    -- Sprite and animation
    current_sprite = is_preacher and 8 or 1,
    bot_sprite_sets = {
      idle = {horizontal = {0,1}, up = {32,33}, down = {16,17}},
      walking = {horizontal = {2,3}, up = {34,35}, down = {18,19}}
    },

    -- Target and following
    target_x = x,
    target_y = y,
    last_direction = "down",
    facing_left = false,

    -- Physics
    mass = 1,

    -- Ability system
    abilities = {},
    selected_ability = 1,

    -- AI-related properties
    state = "idle",
    last_seen_player_pos = {x = nil, y = nil},
    alert_timer = 0,
    max_alert_time = 180,
    
    idle_timer = 0,

    -- Poison-related properties
    poison_timer = 0,

    -- Flash effect property
    flash_timer = 0,
  }, {__index=entity})

  new_entity.targeting = targeting.new(new_entity)

  local ability_data = [[
    15,100,rIFLE bURST,fIRE A BURST OF MEDIUM-DAMAGE BULLETS,rifle_burst,20|
    30,200,mACHINE gUN,rAPID-FIRE HIGH-VELOCITY ROUNDS,machine_gun,25|
    45,50,mISSILE hAIL,lAUNCH A BARRAGE OF HOMING MISSILES,missile_hail,50|
    60,25,pLASMA cANNON,fIRE A DEVASTATING PLASMA PROJECTILE,plasma_cannon,75]]
  
  for i, a in ipairs(stringToTable(ability_data)) do
    add(new_entity.abilities, {
      index = i,
      cooldown = a[1],
      name = a[3],
      description = a[4],
      action = new_entity[a[5]],
      current_cooldown = 0,
      remaining_uses = subclass != "player" and a[2] or 0,
      cost = a[6]
    })
  end

  local entity_data_str = [[
    15,dervish,50,50,60,100|
    13,vanguard,70,70,50,120|
    1,warden,100,100,70,200|
    7,player,999,999,70,0|
    11,preacher,80,80,80,280|
    6,cyberseer,160,160,80,300|
    1,quantumcleric,170,170,70,320
    ]]
    
  for d in all(stringToTable(entity_data_str)) do
    if d[2] == subclass then
      new_entity.color, _, new_entity.health, new_entity.max_health, new_entity.attack_range, new_entity.kill_value = unpack(d)
    end
  end

  return new_entity
end

function entity:update()
  if self.subclass == "player" then
    self:player_update()
  else
    self:enemy_update()
  end
  self:apply_physics()
  self.targeting:update()

  -- Update cooldowns
  for ability in all(self.abilities) do
    ability.current_cooldown = max(0, ability.current_cooldown - 1)
  end

  -- Handle poison damage
  if check_tile_flag(self.x, self.y, 2) and self.base_class != "preacher" then
    self.poison_timer += 1
    if self.poison_timer >= 5 then
      self:take_damage(1)
      self.poison_timer = 0
    end
  else
    self.poison_timer = 0
  end

  if self.update_plasma then
    self:update_plasma()
  end
end

function entity:player_update()
  self:control()
  self:follow_target()

  if btnp(❎) then
    for t in all(terminals) do
      if t.interactive then
        game_minigame:start(t)
        goto continue
      end
    end
    self:activate_ability(self.selected_ability)
    ::continue::
  end

  for fragment in all(data_fragments) do
    if dist_trig(fragment.x - self.x, fragment.y - self.y) < 8 and not fragment.collected then
      self.health = min(self.health + 20, self.max_health)
      player_hud:add_credits(50)
      fragment.collected = true
      sfx(7)
    end
  end
end

function entity:enemy_update()
  local s = {
    idle = self.update_idle,
    alert = self.update_alert,
    attack = self.update_attack
  }
  s[self.state](self)
end

function entity:take_damage(amount)
  self.health = max(0, self.health - amount)
  self.flash_timer = 1
  if self.health <= 0 then self:on_death() end
  if self.subclass == "player" then player_hud.shake_duration = 10 end
end

function entity:on_death()
  player_hud:add_credits(self.kill_value)
  self:spawn_death_particles()
  del(entities, self)
  sfx(30)
end

function entity:spawn_death_particles()
  local particle_count = self.base_class == "preacher" and 40 or 20

  for i = 1, particle_count do
    local angle, speed = rnd(), 0.5 + rnd(1.5)
    local p = particle:new(
      self.x + self.width / 2, 
      self.y + self.height / 2, 
      cos(angle) * speed, 
      sin(angle) * speed, 
      20 + rnd(10), 1 + flr(rnd(2)), rnd({8,9,10}))
    add(particles, p)
  end
end

function entity:can_see_player()
  local player = self:find_player()
  if not player then return false end
  
  local dx, dy = player.x - self.x, player.y - self.y
  
  if dist_trig(dx, dy) <= self.attack_range then
    local steps = max(abs(dx), abs(dy))
    local step_x, step_y = dx / steps, dy / steps
    
    for i = 1, steps do
      if check_tile_flag(self.x + step_x * i, self.y + step_y * i) then
        return false
      end
    end
    
    self.last_seen_player_pos.x, self.last_seen_player_pos.y = player.x, player.y
    return true
  end
  
  return false
end

function entity:update_idle()
  self.idle_timer -= 1
  if self.idle_timer <= 0 then
    self.idle_timer,angle,speed = 30,rnd(),rnd(1)
    self.vx, self.vy = cos(angle)*speed, sin(angle)*speed
  end

  if self:can_see_player() then
    self.state = "alert"
    self.alert_timer = self.max_alert_time
  end
end

function entity:update_alert()
  if self:can_see_player() then
    self.alert_timer = self.max_alert_time
    local player = self:find_player()
    local dx, dy = player.x - self.x, player.y - self.y
    local dist = dist_trig(dx, dy)
    
    if dist <= self.attack_range then
      self.state = "attack"
    else
      -- Move towards player
      self.vx, self.vy = dx / dist, dy / dist
    end
  elseif self.last_seen_player_pos.x then
    local dx, dy = self.last_seen_player_pos.x - self.x, self.last_seen_player_pos.y - self.y
    local dist = dist_trig(dx, dy)
    
    self.vx, self.vy = 0, 0
    if dist > 1 then
      self.vx, self.vy = dx / dist, dy / dist
    end
  end
    
  self.alert_timer -= 1
  if self.alert_timer <= 0 then
    self.state, self.last_seen_player_pos.x, self.last_seen_player_pos.y = "idle", nil, nil
  end
end

function entity:update_attack()
  local player = self:find_player()
  if not player or not self:can_see_player() then
    self.state = "alert"
    self:reset_plasma_cannon()
    return
  end

  local dx, dy = player.x - self.x, player.y - self.y
  if dist_trig(dx, dy) <= self.attack_range then
    self.facing_left = dx < 0
    self.last_direction = abs(dx) > abs(dy) and "horizontal" or (dy < 0 and "up" or "down")

    local subclass_abilities = entity_abilities[self.subclass]
    local ability = self.abilities[self:find_ability(subclass_abilities[flr(rnd(#subclass_abilities)) + 1])]
    if ability and ability.current_cooldown == 0 then
      self:activate_ability(ability.index)
    end
  else
    self.state = "alert"
  end
end

function entity:find_ability(ability_name)
  for i, ability in ipairs(self.abilities) do
    if ability.name == ability_name then
      return i
    end
  end
  return nil
end

function entity:find_player()
  for e in all(entities) do
    if e.subclass == "player" then
      return e
    end
  end
end

function entity:activate_ability(index)
  local ability = self.abilities[index]
  if ability.current_cooldown == 0 then
    if ability.remaining_uses > 0 then
      ability.action(self)
      if self.subclass == "player" then
        ability.current_cooldown = ability.cooldown
        ability.remaining_uses -= 1
      else
        ability.current_cooldown = ability.cooldown * 3
      end
    else
      sfx(29)
    end
  end
end

function entity:rifle_burst()
  local dx, dy = self:get_aim_direction()
  local decel = self.subclass == "player" and 5.5 or 1
  self.vx -= dx * decel
  self.vy -= dy * decel

  local sx, sy = self.x + self.width/2, self.y + self.height/2

  for i = -2, 2 do
    local angle = atan2(dx, dy) + i * 0.005
    local vx, vy = cos(angle) * 4, sin(angle) * 4
    
    local bullet = particle:new(
      sx + cos(angle) * self.width/2,
      sy + sin(angle) * self.height/2,
      vx, vy, 30, 1, 8, "rifle", self
    )
    add(particles, bullet)
  end

  sfx(27)
end

function entity:machine_gun()
  local bullets, orig_update = 0, self.update
  function self:update()
    orig_update(self)
    if bullets < 20 then
      if bullets % 2 == 0 then
        local dx, dy = self:get_aim_direction()
        local angle = atan2(dx, dy) + (rnd() - 0.5) * 0.03
        local vx, vy = cos(angle) * 6, sin(angle) * 6
        local sx, sy = self.x + self.width/2, self.y + self.height/2
        
        local bullet = particle:new(
          sx + cos(angle) * self.width/2,
          sy + sin(angle) * self.height/2,
          vx, vy, 20, 1, 8, "machinegun", self
        )
        add(particles, bullet)

        self.vx -= dx * 0.15
        self.vy -= dy * 0.15

        sfx(14)
      end
      bullets += 1
    else
      self.update = orig_update
    end
  end
end

function entity:missile_hail()
  for i = 1, 3 do
    local angle = rnd()
    local offset = 10 + rnd(10)
    local lifetime = 30 or 60 and self.subclass == "player"
    local missile = particle:new(
      self.x + self.width/2 + cos(angle) * offset, 
      self.y + self.height/2 + sin(angle) * offset, 
      0, 0, lifetime, 1, 8, "missile", self)
    missile.target = self.targeting.target
    add(particles, missile)
  end

  sfx(6)
end

function entity:plasma_cannon()
  self.plasma_charge = 0
  self.is_charging_plasma = true
  self.update_plasma = self.update_plasma_cannon
end

function entity:update_plasma_cannon()
  if self.is_charging_plasma then
    if self.plasma_charge < 20 then
      self.plasma_charge += 1
      sfx(4)
    else
      local dx, dy = self:get_aim_direction()
      local sx, sy = self.x + self.width/2, self.y + self.height/2
      local proj = particle:new(
        sx, 
        sy, 
        dx * 5, 
        dy * 5,
        120, 4, 12, "plasma", self)
      
      add(particles, proj)
      sfx(10)
      self.vx -= dx * 5.5
      self.vy -= dy * 5.5
      
      self:reset_plasma_cannon()
    end
  end
end

function entity:reset_plasma_cannon()
  self.is_charging_plasma = false
  self.plasma_charge = 0
  self.update_plasma = nil
end

function entity:get_aim_direction()
  local target = self.targeting.target
  if target then
    local dx, dy = target.x - self.x, target.y - self.y
    local dist = dist_trig(dx, dy)
    return dx/dist, dy/dist
  end

  local speed = dist_trig(self.vx, self.vy)
  if speed > 0 then
    return self.vx / speed, self.vy / speed
  end

  if self.last_direction == "horizontal" then
    return self.facing_left and -1 or 1, 0
  end
  return 0, self.last_direction == "up" and -1 or 1
end

function entity:control()
  local ix = (btn(1) and 1 or 0) - (btn(0) and 1 or 0)
  local iy = (btn(3) and 1 or 0) - (btn(2) and 1 or 0)
  local max_target_distance, target_speed = 32, 6

  if ix != 0 and iy != 0 then
    ix *= self.diagonal_factor
    iy *= self.diagonal_factor
  end

  self.target_x += ix * target_speed
  self.target_y += iy * target_speed

  local dx, dy = self.target_x - self.x, self.target_y - self.y

  if dist_trig(dx, dy) > max_target_distance then
    local angle = atan2(dx, dy)
    self.target_x = self.x + cos(angle) * max_target_distance
    self.target_y = self.y + sin(angle) * max_target_distance
  end
end

function entity:follow_target()
  local dx, dy = self.target_x - self.x, self.target_y - self.y
  local distance, follow_speed = dist_trig(dx, dy), .1
  
  if distance > 1 then
    self.vx, self.vy = self:approach(self.vx, dx * follow_speed, self.acceleration), self:approach(self.vy, dy * follow_speed, self.acceleration)
    
    -- Update direction information
    if abs(self.vx) > abs(self.vy) then
      self.last_direction = "horizontal"
      self.facing_left = self.vx < 0
    else
      self.last_direction = self.vy < 0 and "up" or "down"
    end
  else
    self.vx, self.vy = self:approach(self.vx, 0, self.deceleration), self:approach(self.vy, 0, self.deceleration)
  end
  
  -- Limit speed
  local speed = dist_trig(self.vx, self.vy)
  if speed > self.max_speed then
    self.vx = (self.vx / speed) * self.max_speed
    self.vy = (self.vy / speed) * self.max_speed
  end
end

function entity:approach(current, target, step)
  if current < target then
    return min(current + step, target)
  elseif current > target then
    return max(current - step, target)
  else
    return current
  end
end

function entity:apply_physics()
  -- Apply deceleration
  self.vx = abs(self.vx) < 0.05 and 0 or self.vx * self.deceleration
  self.vy = abs(self.vy) < 0.05 and 0 or self.vy * self.deceleration

  -- Prepare new position
  local new_x, new_y = self.x + self.vx, self.y + self.vy

  -- Check tile collision
  if self:check_tile_collision(new_x, new_y) then
    if not self:check_tile_collision(new_x, self.y) then
      new_y = self.y
    elseif not self:check_tile_collision(self.x, new_y) then
      new_x = self.x
    else
      new_x, new_y = self.x, self.y
    end
  end

  -- Check laser door collision
  for door in all(doors) do
    if door:check_collision(new_x, new_y, self.width, self.height) then
      new_x, new_y = self.x, self.y
      self.vx, self.vy = 0, 0
      break
    end
  end

  -- Update position
  self.x, self.y = new_x, new_y
end

function entity:check_tile_collision(x, y)
  local points = {
    {x, y},
    {x + self.width - 1, y},
    {x, y + self.height - 1},
    {x + self.width - 1, y + self.height - 1}
  }

  for point in all(points) do
    if check_tile_flag(unpack(point)) then
      return true
    end
  end

  return false
end

function entity:draw()
  local x,y,w,h = self.x,self.y,self.width,self.height
  local is_preacher = self.base_class == "preacher"
  local hover_offset = is_preacher and sin(time() * .5) * 2 or 0
  
  -- Plasma charge circle
  if self.is_charging_plasma and self.plasma_charge < 20 then
    circ(x + w/2, y + h/2, 32 * (1 - self.plasma_charge / 20), 12)
  end

  -- Shadow
  if is_preacher then
    local scale = 1 - (hover_offset / 8)
    ovalfill(x+8-6*scale, y+22, x+8+6*scale, y+22+3*scale, 1)
  else
    spr(49, x, y + 1)
  end

  if self.flash_timer > 0 then
    for i = 0, 15 do pal(i, 8) end
  else
    -- Normal color palette
    pal(self.base_class == "bot" and 7 or 6, entity_colors[self.subclass])
    if is_preacher then
      if t() % 1 < .5 then pal(0, 8) end
    elseif self.subclass != "player" then
      pal(12,8)
    end 
  end

  -- Sprite drawing
  local speed = dist_trig(self.vx, self.vy)
  local is_moving = speed > 0.2

  if is_preacher then
    spr(self.current_sprite, x, y + hover_offset, 2, 3, self.vx < 0 and is_moving)
  else
    local sprites = (is_moving and self.bot_sprite_sets.walking or self.bot_sprite_sets.idle)[self.last_direction]
    local anim_speed = is_moving and (10 + min(speed / self.max_speed, 1) * 10) or 3
    spr(sprites[flr(time() * anim_speed) % #sprites + 1], x, y, 1, 1, self.facing_left)
  end

  reset_pal()

  -- State indicators
  local indicator = self.state == "alert" and 36 or (self.state == "attack" and 20)
  if self.subclass != "player" and indicator then
    spr(indicator, x + (is_preacher and 6 or 4), y - 8)
  else
    self.targeting:draw()
  end

  self.flash_timer = max(0, self.flash_timer - 1)
end


-- BARREL
----------
barrel = {}

function barrel.new(x, y)
  local poison = rnd() > .5
  return setmetatable({
    x = x,
    y = y,
    poison = poison,
    height = 8,
    width = 8,
    health = 1,
    exploding = false,
    explosion_time = 0,
  }, {__index=barrel})
end

function barrel:draw()
  if not self.exploding then
    spr(self.poison and 5 or 6, self.x, self.y - 8)
  end
end

function barrel:update()
  if self.health <= 0 and not self.exploding then
    self.exploding = true
    self.explosion_time = 0
  end

  if count_remaining_terminals() == 0 then
    if dist_trig(player.x - self.x, player.y - self.y) < 50 and rnd() < 0.01 then
      self.health = 0
    end
  end

  if self.exploding then
    self.explosion_time += 1

    if self.explosion_time == 1 then
      for i = 1, 20 do
        local angle, speed = rnd(), 1 + rnd(2)
        local p_vx, p_vy = cos(angle) * speed, sin(angle) * speed * 0.5
        add(particles, particle:new(
          self.x + self.width/2,
          self.y + self.height/2,
          p_vx, p_vy,
          20 + rnd(10),
          1 + rnd(2),
          self.poison and 3 or 8
        ))
      end

      for e in all(entities) do
        local dx = e.x + e.width/2 - (self.x + self.width/2)
        local dy = e.y + e.height/2 - (self.y + self.height/2)
        local normalized_dist = dist_trig(dx/64, dy/32)
        if normalized_dist < 0.5 then
          local damage = 20 * (1 - normalized_dist*2)
          e:take_damage(damage * (self.poison and 1.5 or 1))
        end
      end

      sfx(28)
    end

    mset(flr(self.x / 8), flr(self.y / 8), self.poison and 10 or 26)

    if self.explosion_time >= 15 then
      del(barrels, self)
    end
  end
end

function barrel:take_damage(amount)
  self.health = max(0, self.health - amount)
end


-- LASER DOOR
----------------
laser_door = {}

function laser_door.new(x, y, color)
  local laser_beams, color_map = {}, {}
  
  for beam in all(stringToTable("11,4|9,8|7,12")) do
    local sx, sy = x + beam[1], y + beam[2]
    local ex, ey = sx, sy + 10
    while not check_tile_flag(ex, ey) do ey += 1 end
    add(laser_beams, {start_x=sx, start_y=sy, end_x=ex, end_y=ey-1})
  end

  
  for color_data in all(stringToTable("red,8,2|green,11,3|blue,12,1")) do
    local color_name, light_shade, dark_shade = unpack(color_data)
    color_map[color_name] = {
      beam_color = light_shade,
      terminal_sequence = {7, light_shade, dark_shade, light_shade}
    }
  end

  return setmetatable({
    x = x,
    y = y,
    is_open = false,
    laser_beams = laser_beams,
    color = color or "red",
    color_map = color_map
  }, {__index=laser_door})
end

function laser_door:draw()
  spr(14, self.x, self.y, 2, 2)
  if not self.is_open then
    for i, beam in ipairs(self.laser_beams) do
      line(
        beam.start_x, 
        beam.start_y, 
        beam.end_x, 
        beam.end_y + (#self.laser_beams - i + 1) * 2, 
        self.color_map[self.color].beam_color)
    end
  end
end

function laser_door:check_collision(ex, ey, ew, eh)
  if self.is_open then return false end
  
  for beam in all(self.laser_beams) do
    if (ey + eh > beam.start_y and ey < beam.end_y) and
       (ex < beam.start_x and ex + ew > beam.start_x) then
      return true
    end
  end
  
  return false
end

-- DATA FRAGMENT
----------------
data_fragment = {collected = false}

function data_fragment.new(x, y)
  return setmetatable({
    x = x,
    y = y,
    height = 8,
    width = 8
  }, {__index=data_fragment})
end


function data_fragment:draw()
  if not self.collected then
    local sprite_list = stringToTable("50,51,52,53,53,53,53,54,55")[1]
    spr(sprite_list[flr(time() / .15) % #sprite_list + 1], self.x, self.y-4)
  end
end


-- TERMINAL
----------------
terminal = {}

function terminal.new(x, y, target_door)
  local pulse_colors = target_door and target_door.color_map[target_door.color].terminal_sequence or {7, 6, 13, 6}  -- Default pulse colors if no door

  return setmetatable({
    x = x,
    y = y,
    interactive = false,
    pulse_index = 1,
    pulse_timer = 0,
    target_door = target_door,
    pulse_colors = pulse_colors,
    completed = false
  }, {__index = terminal})
end

function terminal:update()
  printh(self.interactive)
  if self.completed then
    self.interactive = false
    return
  end

  self.interactive = true
  for e in all(entities) do
    if e.state != "idle" or dist_trig(player.x-self.x, player.y-self.y) >= 32 then
      self.interactive = false
      self.pulse_index, self.pulse_timer = 1, 0
      return
    end
  end

  self.pulse_timer = (self.pulse_timer + 1) % 6
  if self.pulse_timer == 0 then
    self.pulse_index = self.pulse_index % #self.pulse_colors + 1
  end
end

function terminal:draw()
  if self.completed then
    pal(7, 8)
  elseif self.interactive then
    pal(7, self.pulse_colors[self.pulse_index])
  end
  
  spr(39, self.x, self.y + 8)
  spr(23, self.x, self.y)
  reset_pal()
end

function create_door_terminal_pair(door_x, door_y, terminal_x, terminal_y, color)
  local new_door = laser_door.new(door_x, door_y, color)
  add(doors, new_door)
  add(terminals, terminal.new(terminal_x, terminal_y, new_door))
end

-- MINIGAME
---------------
minigame = {
  directions = {"⬅️","➡️", "⬆️", "⬇️"},
  active = false,
  current_input = {},
  time_limit = 180,
  timer = 0,
  current_terminal = nil
}

function minigame.new()
  return setmetatable({}, {__index = minigame})
end

function minigame:start(terminal)
  self.sequence = {}
  for i = 1, 5 do add(self.sequence, self.directions[flr(rnd(4)) + 1]) end

  local _ENV = self 
  active = true
  timer = time_limit
  current_input = {}
  current_terminal = terminal

end

function minigame:update()  
  self.timer -= 1
  if self.timer <= 0 then
    self:end_game(false)
    return
  end
  
  for i = 0, 3 do
    if btnp(i) then
      add(self.current_input, self.directions[i+1])
      if #self.current_input == #self.sequence then
        self:check_result()
      end
      return
    end
  end
end

function minigame:check_result()
  for i = 1, #self.sequence do
    if self.sequence[i] != self.current_input[i] then
      self:end_game(false)
      return
    end
  end
  self:end_game(true)
end

function minigame:end_game(success)
  self.active = false
  local current_terminal  = self.current_terminal

  if success then
    if current_terminal.target_door then
      current_terminal.completed = true
      current_terminal.target_door.is_open = true
    else
      current_terminal.completed = true
    end
  end
  current_terminal = nil
end

function minigame:draw()
  if not self.active or player.health <= 0 then return end
  
  local center_x, center_y = 64 + cam.x, 64 + cam.y
  rectfill(center_x - 35, center_y - 20, center_x + 35, center_y + 20, 0)
  rect(center_x - 35, center_y - 20, center_x + 35, center_y + 20, 3)
  
  -- Calculate total width of sequence
  local seq_width = #self.sequence * 12 - 4
  local seq_start_x = center_x - seq_width / 2
  
  for x in all(self.sequence) do
    print(x, seq_start_x, center_y - 10, 7)
    seq_start_x += 12
  end
  
  -- Reset seq_start_x for current input
  seq_start_x = center_x - seq_width / 2
  
  for i, dir in pairs(self.current_input) do
    local color = dir == self.sequence[i] and 11 or 8
    print(dir, seq_start_x, center_y, color)
    seq_start_x += 12
  end
  
  -- Center the timer text
  local timer_text = "time: "..flr(self.timer / 30)
  local timer_width = #timer_text * 4  -- Assuming each character is 4 pixels wide
  print(timer_text, center_x - timer_width / 2, center_y + 10, 8)
end


-- PLAYER HUD
---------------
player_hud = {
  bar_width=80,
  bar_height=5,
  cooldown_bar_height=3,
  x_offset=2,
  y_offset=2,
  text_padding=2,
  show_interact_prompt=false,
  shake_duration=0,
  alert_bar_height=4,
  credit_add_timer=0,
}

function player_hud.new()
  return setmetatable({}, {__index=player_hud})
end

function player_hud:update()
  self.show_interact_prompt = false
  for terminal in all(terminals) do
    if terminal.interactive then
      self.show_interact_prompt = true
      break
    end
  end
  self.shake_duration = max(self.shake_duration - 1, 0)
  if self.credit_add_timer > 0 then
    credits += 5
    self.credit_add_timer = max(self.credit_add_timer - 5, 0)
  end
end

function player_hud:draw()
  local cam_x, cam_y = cam.x, cam.y
  local health_percent = player.health / player.max_health
  local start_x, start_y = flr(self.x_offset + cam_x), flr(self.y_offset + cam_y)

  if self.shake_duration > 0 then
    start_x += rnd(4) - 2
    start_y += rnd(4) - 2
  end

  local health_color = health_percent > 0.6 and 11 or health_percent > 0.3 and 10 or 8
  draw_bar(start_x, start_y, 80, 5, 7, health_color, health_percent)

  local ability, cooldown_y = player.abilities[player.selected_ability], start_y + 5
  draw_bar(start_x, cooldown_y, 80, 3, 1, 12, 1 - ability.current_cooldown / ability.cooldown)

  print_shadow(flr(player.health).."/"..player.max_health, start_x + 82, start_y)
  print_shadow(ability.name.." ▶"..ability.remaining_uses.."◀", start_x, cooldown_y + 5, ability.remaining_uses == 0 and (t()*4 % 2 < 1 and 2 or 7))
  
  local credits_text = "cREDITS: "..credits
  if self.credit_add_timer > 0 then
    credits_text ..= " +"..self.credit_add_timer
  end
  print_shadow(credits_text, start_x, cooldown_y + 12)

  if self.show_interact_prompt then
    print_shadow("❎ interact", cam_x + 4, cam_y + 120)
  end
  
  local alert_x, alert_y = cam_x + self.x_offset, cam_y + 127 - self.alert_bar_height
  
  for entity in all(entities) do
    if entity.state == "alert" or entity.state == "attack" then
      local health_percent = entity.health / entity.max_health
      local bar_width = flr(entity.max_health * .4)
      draw_bar(alert_x, alert_y, bar_width, self.alert_bar_height, 7, 8, health_percent)
      print_shadow(entity.subclass, alert_x + bar_width + self.text_padding, alert_y)
      alert_y -= self.alert_bar_height + self.text_padding
    end
  end
  
  if count_remaining_terminals() == 0 then
    if ending_sequence_timer == 1000 then
      music(7)
    elseif ending_sequence_timer > 0 then
      print_shadow("EVACUATE IN: " .. flr(ending_sequence_timer), cam_x + 30, cam_y + 90)
      print_shadow("FOLLOW THE RED DOT", cam_x + 26, cam_y + 100)
      -- Spawn point indicator
      local angle = atan2(player_spawn_x - player.x, player_spawn_y - player.y)
      circfill(player.x + cos(angle) * 20, player.y + sin(angle) * 20, 1, 8)
    elseif ending_sequence_timer == 0 then
      player.health = 0
      player:on_death()
    end
    ending_sequence_timer -= 1
  end
end

function draw_bar(x, y, width, height, bg_color, fill_color, percentage)
  rectfill(x, y, x + width - 1, y + height - 1, bg_color)
  if percentage > 0 then
    rectfill(x, y, x + max(1, flr(width * percentage)) - 1, y + height - 1, fill_color)
  end
  rect(x, y, x + width - 1, y + height - 1, 0)
end

function print_shadow(text, x, y, color)
  print(text, x + 1, y + 1, 0) 
  print(text, x, y, color or 7)
end

function player_hud:add_credits(amount)
  self.credit_add_timer += amount
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

__label__
55555555555555556666665000000000000555000000000000000000000000000000000000000000000000065555555555555550000000000000000000000000
55555555555555556555555000000000000555000000000000000000000000000000000000000000000000065550000000055550000000000000000000000000
55000000000000000000000000000000000000000000000000000000000000000000000000000000000077067770557577007770000000000000000000000000
550bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb00007067070575057007070000000000000000000000000
550bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb00007067070570557057070000000000000000000000000
550bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb00007067070570557057070000000000000000000000000
55000000000000000000000000000000000000000000000000000000000000000000000000000000000077767770750577757770000000000000000000000000
55000000000000000000000000000000000000000000000000000000000000000000000000000000000000005000505550000000000000000000000000000000
550cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc00000065055555555550520000000000000000000000000
55000000000000000000000000000000000000000000000000000000000000000000000000000000000000065005555555500520000000000000000000000000
55555552222220223633362000000000000555000000000000000000000000000000000000000000000000065500555555005520000000000000000000000000
55555552222002223333332000000000000555000000000000000000000000000000000000000000000000065550000000055520000000000000000000000000
55777550222002023363332000777000000555000000000000700077007770777000700000000000000000065555555555555520000000000000000000000000
55707077727770702377720000707070707755077077700000770007007070707007700000000000000000055555555555555520000000000000000000000000
55775057007700700277000000770070707075700007000000777007007070707077700000000000000000055222222222222220000000000000000000000000
55707557007000700070000000707070707750007007000000770007007070707007700000000000000000000000000000000000000000000000000000000000
55707077707000077007700000777007707075770007000000700077707770777000700000000000022220000000000000000000000000000000000000000000
55505050000000220000002000000000000050000000000000000000000000000000000001111110222222000000000000000000000000000000000000000000
55555550200002002000020000000000000555000000000000000000000000000000000001212120122225000000000000000000000000000000000000000000
55577550022220000222200000000000000555770077707770777000000000000000000001100000111555000000000000000000000000000000000000000000
55750077007770770077707770077007000555070070707070707000000000000000000001201110111555000000000000000000000000000000000000000000
55705570707700707007000700700000000555070070707070707000000000000000000001101210111555000000000000000000000000000000000000000000
55705577007000707007005700007007000555070070707070707000000000000000000001201100011550000000000000000000000000000000000000000000
55577570755775775077755700770000000555777077707770777000000000000000000001101200000000000000000000000000000000000000000000000000
50000050500000500000005000000000000555000000000000000000000000000000000001201100000000000000000000000000000000000000000000000000
00000055000000550000005000000000000555000000000000000000000000000000000001101200000000000000000000000000000000000000000000000000
00000055000000550000005000000000000555000000000000000000000000000000000001201100000000000000000000000000000000000000000000000000
00000055000000550000005000000000000566000000000000000000000000000000000001101200000000000000000000000000000000000000000000000000
00000055000000550000005000000000000566000000000000000000000000000000000001201100000000000000000000000000000000000000000000000000
50000555500005555000055000000000005666000000000000000000000000000000000001101200000000000000000000000000000000000000000000000000
55555555555555555555555000000000005666000000000000000000000000000000000001201100000000000000000000000000000000000000000000000000
55555555555555555555555000000000555666000000000000000000000000000000000001101200000000000000000000000000000000000000000000000000
55555555555555556666665000000000555666000000000000000000000000000000000001201100000000000000000000000000000000000000000000000000
55555555555555556555555000000055555666000000000000000000000000000000000001101200000000000000000000000000000000000000000000000000
55555555555555556555552000000055555666000000000000000000000000000000000001201100000000000000000000000000000000000000000000000000
55555555555555556555552000000055555666000000000000000000000000000000000001101200000000000000000000000000000000000000000000000000
55555555555555556555552000005555555666000000000000000000000000000000000001201100000000000000000000000000000000000100000000000000
55555555555555556555552000005555555666000000000000000000000000000000000001101200000000000000000000000000000000000100000000000000
55555555555555555522222000005555555666000000000000000000000000000000000001201100000000000000000000000000000000000100000000000000
55555555555555555555555000005555555666000000000000000000000000000000000001101200000000000000000000000000000000000110000000000000
55555555555555556666665000555555555666000000000000000000000000000000000001201100000000000000000000000000000000000120000000000000
55555555555555556555555000555555555666000000000000000000000000000000000001101200000000000000000000000000000000000110000000000000
55555555555555556555552000555555555666000000000000000000000000000000000001201100000000000000000000000000000000000120000000000000
55555555555555556555552000555555555666000000000000000000000000000000000001101200000000000000000000000000000000000110120000000000
55555555555555556555552055555555555666000000000000000000000000000000000001201100000000000000000000000000000000000120110000000000
55555555555555556555552055555555555666000000000000000000000000000000000001101200000000000000000000000000000000000110120000000000
55555555555555555522222055555555555666000000000000000000000000000000000001201100000000000000000000000000000000000120110000000000
55555555555555555555555055555555555666000000000000000000000000000000000001101200000000000000000000000000000000000110120000000000
55555555555555556666665055555555555666000000000000000000000000000000000001201100000000000000000000000000000000000120110000000000
55555555555555556555555055555555555666000000000000000000000000000000000001101211111111000000000000000000000000000110121200000000
5555555555555555655555d555555555555666000000000000000000000000000000000001201111212121000000000000000000000000000120111100000000
5555555555555555655555d555555555555666000000000000000000000000000000000001100000000011000000000000000000000000000110000000000000
5555555555555555655555d555555555555666000000000000000000000000000000000001212121111021000000000000000000000000000121212100000000
5555555555555555655555d555555555555666000000000000000000000000000000000001111112121011000000000000000000000000000111111100000000
5555555555555555552222d555555555555666000000000000000000000000000000000000000000011021000000000000000000000000000000000000000000
00000000000000000000005155555555555666000000000000000000000000000000000000000000011012000000000000000000000000000000000000000000
00000000000000000000005515555555555666000000000000000000000000000000000000000000012011000000000000000000000000000000000000000000
00000000000000000000005551555555555666000000000000000000000000000000000000000000011012000000000000000000000000000000000000000000
00000000000000000000005555155555555666000000000000000000000000000000000000000000012011000000000000000000000000000000000000000000
00000000000000000000005555515555555666000000000000000000000000000000000000000000011012000000000000000000000000000000000000000000
00000000000000000000005555551555555666000000000000000000000000000000000000000000012011000000000000000000000000000000000000000000
00000000000000000000001555555155555666000000000000000000000000000000000000000000011012000000000000000000000000000000000000000000
00000000000000000000001555555515555666000000000000000000000000000000000000000000012011000000000000000000000000000000000000000000
00000000000000000000000115555551555666000000000000000000000000000000000000000000011012000000000000000000000000000000000000000000
00000000000000000000000011555555155666000000000000000000000000000000000057770000012011000000000000000000000000000000000000000000
00000000000000000000000001555555515666000000000000000000000000000000000577cc7000011012000000000000000000000000000000000000000000
00000000000000000000000001155555551666000000000000000000000000000000000777cc7000012011000000000000000000000000000000000000000000
00000000000000000000000000116666666666000000000000000000000000000000000577777000011012000000000000000000000000000000000000000000
00000000000000000000000000011666666666000000000000000000000000000000000577077000012011000000000000000000000000000000000000000000
00000000000000000000000000001166666666000000000000000000000000000000000011010000011012000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000111111000012011000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000011110000011012000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000012011000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000011012121212121212121212121212121212121200000000
00000000000000000000000000000000000000000000000000000000003000000000000000000000012011111111111111111111111111111111111100000000
00000000000000000000000000000000000000000000000000000000303000000000000000000000011000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000303030000000000000000000012121212121212121212121212121212121212100000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000011111111111111111111111111111111111111100000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030300000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030303000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
55555555555555555555555555556666666666666666660000000000000000000000000000000000000000000000000000000000000000000000000000000000
55555555555555555555555555556666666666666666660000000000000000000000000000000000000000000000000000000000000000000000000000000000
55555555555555555555555555555566666666666666660000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000055555555555516660000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000055555555555156660000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000555555551556660000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000555555515556660000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000005555155556660000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000005551555556660000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000005515555556660000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000055555556660000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000055555556660000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000555556660000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000005556660000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000005556660000000000000000000000000000000000000000000000000000000000000000000000000000000000
55555555555555555555555555555550000000000056660000000000000000000000000000000000000000000000000000000000000000000000000000000000
66666655666666556666665566666650000000000056660000000000000000000000000000000000000000000000000000000000000000000000000000000000
65555555655555556555555565555550000000000005660000000000000000000000000000000000000000000000000000000000000000000000000000000000
65555525655555256555552565555520000000000005550000000000000000000000000000000000000000000000000000000000000000000000000000000000
65555525655555256555552565555520000000000005550000000000000000000000000000000000000000000000000000000000000000000000000000000000
65555525655555256555552565555520000000000005550000000000000000000000000000000000000000000000000000000000000000000000000000000000
65555525655555256555552565555520000000000005550000000000000000000000000000000000000000000000000000000000000000000000000000000000
55222225552222255522222555222220000000000005550000000000000000000000000000000000000000000000000000000000000000000000000000000000
55555555555555555555555555555550000000000005550000000000000000000000000000000000000000000000000000000000000000000000000000000000
55555555555555555555555566666650000000000005550000000000000000000000000000000000000000000000000000000000000000000000000000000000
55555555555555555555555565555550000000000005550000000000000000000000000000000000000000000000000000000000000000000000000000000000
55555555555555555555555565555520000000000005550000000000000000000000000000000000000000000000000000000000000000000000000000000000
55555555555555555555555565555520000000000005550000000000000000000000000000000000000000000000000000000000000000000000000000000000
50222555555555555555555565555520000000000005550000000000000000000000000000000000000000000000000000000000000000000000000000000000
02222255555555555555555565555520000000000005550000000000000000000000000000000000000000000000000000000000000000000000000000000000
22222255555555555555555555222220000000000005550000000000000000000000000000000000000000000000000000000000000000000000000000000000
02222255555555555555555555555550000000000005550000000000000000000000000000000000000000000000000000000000000000000000000000000000
02220205555555555555555566666650000000000005550000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000055555555555555555565555550000000000005550000000000000000000000000000000000000000000000000000000000000000000000000000000000
70000000000005555555555565555520000000000005550000000000000000000000000000000000000000000000000000000000000000000000000000000000
07000000000005555555555565555520000000000005550000000000000000000000000000000000000000000000000000000000000000000000000000000000
00700000000005555555555565555520000000000005550000000000000000000000000000000000000000000000000000000000000000000000000000000000
07000000000005555555555565555520000000000005550000000000000000000000000000000000000000000000000000000000000000000000000000000000
70000000000005555555555555222220000000000005550000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000005555555555555555550000000000005550000000000000000000000000000000000000000000000000000000000000000000000000000000000

__gff__
0000000041000100000004040400000000000000000000000000000404000000000000000000800000000104000011010100000000000000010101010000010103030303030303030303030303000001030303030303030003030303030000010101030301010303030303010100000001000303010103200000002001050000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__map__
74b6068b01c626368810b6f6a7a78303840440b70694740640c1c185118503f603e503e6e5f60696708601178508b4050515830b65676545058501370684468963c68354d6864586050695b504040464664483068503c5881036843aa7f6f6848340f68480897c8684b7839cb006a5877a868775c6060625653506078ad184c6
8b018380f6d683d6d4e485dc06a683b384ab15671586b2880685ba88ed409080d4e6e603f6a7b0b2069485ffa28503838934886c40860303c0c0b2c08eb8d6f6d5e6e2f2e5d5f6e6830106967483b3950284ba8981908083c3847f888070516183ffc2d0d0d087b54086054003b1b2b1c185c8b08787d4d583f9e3f384408327
838006f6b1b2b2c1f6d686ba870786c7854a834bf69480a7a7b1404006958680526283ffd17017008ab5868303837e845a83acc08362d4e6e58479843f868084d88480865287598c844040849985808710841184aeb0b28380a585ffa28303d0d0d37070358a38863b03f6a787f6c6068701b6e5855f838585ffa7f606958483
d8b1c188f9d4e585f686320788370606c69475b6b6f6f789498a1885ff880585b69021b6f6a797f6062604850136836ca7a784648466d4e6e6e606968416838a8375d5e487ff8481843266448635863bc5176416f6834914646454040464841d5466044404c57070008a01b583686464445424883c3606e797a7f706957070d1
83a9748580866a866c06a5841485f4837b8605839cf60694b40505550583041570706567701770008606f6e70694856d170000831283541770a2a28b7f0083358502c47000847000007416e783de24842c707017758580866a8780967506e6830183fdd5f68301e5849b858074c60686012535060735567077701640e7062715
778479870384d483a81567156567654583ae378635b694700077a284817516f7a7a7e72583fca2831076068aea84f1f68380748394f6858c867b888084832cf6d6f6e7f7f6f640404006a57046c640f6b60606072567839156848500845487a80786aec6f640f6b783be00851c70001786e78797f7a6701785808584548d0306
a58880f6869684a085807406e7b785aad4e6830106a67034853cf7f6e78490f48a808854d6865ca74040858000d1001783f74724000034570083afd183acb688a887af06c683688780d5e6e2f2a7d4f6846e8370948406e6e5a78454e5b0c0c0f616941785f68785a283a797e783ff17700084547583c085ba86c083c58680a2
a2838470838885038680b5049101c58580d4d5e683f9e3f3e6e5854d40400694750640a783998304b1b2c1f706a47084408797857d840684ff7000c2d37070860683b2e486a8a7d484bee5838070878083a4842b177070a2a27070b405156565671583bb656765051567150505c4748440e5856b84c285728480868380f6d6a7
038481c1f606a6708640408366f7f6f6e78302c7858083ff70861683ba83bdb0f6b1c084428386f606967070c3d0d2897c83fec2848075c60684012565350607850a06b683e8f685e7a7f6878684f683c28616f7a7f6d503970385d41696704724646634666434853a57858084d4768440d6c003b1c0f6c183c2b0b2b2b2f6f4
84f584f1867c84ac84ab707034f6f7e783de40f6e783cd83068368760683d883f9d4e583de83fe856fe6838086980397e584e084d2874d66646664640084d68a80d503a70384a7e5847fc1a785f584f18a0285800000e784eaa7878506a740b7f6069586848083f7d5e48615d6a7f6f6b0c006948583d8a7f6e6e5a78433f785
d28a50000089d6842884a883a583c6b1c1b1c1a78380000000d183044625653556830c1700c3a2a2831400f6877b8681d583e8768380837384798680837fb2c106948483d8d4e5f6f68432879786fe84f585078580170084d67406f6c085a8847f875d8580c3d2000086e7e7f7a684780000848017008b2585ef069585e883f4
f683798402d6f6a7b0c1f6838016c08893855287f884c583fca2850d84807506f6b285a8a7a7b0b0838a8446c785a8839d76f7b7f6a67084ad850f000083ac83d08b809683c0b7a7a7d4e683c28440a7d5e4b0c1b783807406b2c0d6a79786d5978780c2a2d0d0d0d2865ca28384846306f6c186a8b0c1b1b1c0f6a740404006
a5841fd3177086f7e7e7258480832d83ac7000e7b18363b7e486ff40a7f606a5838087fdb0b2b2b2c0830bb183cd06947506b2c1d6f6e783d9f7e7f7e784d2837cd384d9c38409d0d0a2838c777070858340843ef6b0c185fc837f400694869f704724173457858077853c35f7f6e7f7846e8458e7f64084e8b6068501668607
8706c6947047831807851c83065785ff7070178f08707088408f3e8f0184fd83ac912cc694b50485011417441466666464445424448412c517703424646466830214830684d09602874004048a3c833e9a2c8c278468
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

