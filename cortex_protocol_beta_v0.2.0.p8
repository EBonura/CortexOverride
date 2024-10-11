pico-8 cartridge // http://www.pico-8.com
version 41
__lua__

--[[
CORTEX PROTOCOL
  by Emanuele Bonura
  itch: https://izzy88izzy.itch.io/
  github: https://github.com/EBonura/CortexProtocol
  instagram: https://www.instagram.com/izzy88izzy/
  minified with: https://thisismypassport.github.io/shrinko8/

How to Play:
* Use arrow keys to move
* Press X to use your selected ability
* Press O to open the ability menu and switch between abilities
* Interact with terminals using X when prompted

Main Objective:
* Activate all terminals and reach the extraction point

Optional Objectives:
* Collect data fragments to restore health and earn credits
* Eliminate all enemy units
]]

-- MAP COMPRESSION
----------------------
function decompress_to_memory(compressed_data, dest_address)
  local byte_index, bit_index, dest_index = 1, 0, dest_address
  local function read_bits(num_bits)
    local value = 0
    for _ = 1, num_bits or 1 do
      if byte_index > #compressed_data then return end
      value = bor(shl(value, 1), band(shr(compressed_data[byte_index], 7 - bit_index), 1))
      bit_index += 1
      if bit_index == 8 then 
        bit_index = 0
        byte_index += 1
      end
    end
    return value
  end
  
  while true do
    if read_bits() == 0 then
      local byte = read_bits(8)
      if not byte then return end
      poke(dest_index, byte)
      dest_index += 1
    else
      local distance, length = dest_index - read_bits(12) - 1, read_bits(4) + 1
      for _ = 1, length do
        poke(dest_index, peek(distance))
        distance, dest_index = distance + 1, dest_index + 1
      end
    end
  end
end

function decompress_current_map()
  local i = current_mission > 2 and 3 or 1
  decompress_to_memory(map_data[i], 0x2000)
  decompress_to_memory(map_data[i + 1], 0x1000)
end


-- HELPER FUNCTIONS
----------------------
function reset_pal(_cls)
  pal()
  palt(0)
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
    c += cond(i) and 0 or 1
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
----------------------
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
 self.active, self.t, self.closing = true, 0, true
end

function transition:update()
  if not self.active then return false end
  
  self.t += self.closing and 1 or -1
  
  if self.closing and self.t == self.duration then
   self.closing = false
   return true
  elseif not self.closing and self.t == 0 then
   self.active = false
  end
  
  return false
end

function transition:draw()
 if not self.active then return end
 local size = max(1, flr(16 * self.t/self.duration))
 for x = 0, 127, size do
  for y = 0, 127, size do
   local c = pget(x, y)
   rectfill(x, y, x+size-1, y+size-1, c)
  end
 end
end

-- TEXT PANEL
----------------------
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
----------------------
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
  local x,y = self.owner.x+self.owner.width/2, self.owner.y+self.owner.height/2
  local x1,y1 = t.x+t.width/2, t.y+t.height/2
  local dx,dy = x1-x, y1-y
  local step = max(abs(dx), abs(dy))
  
  for i=0,step do
    if check_tile_flag(x+dx*i/step, y+dy*i/step) then return false end
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
----------------------
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


-- MAIN
----------------------
function _init()
  cam = gamecam.new()
  
  -- Missions
  MISSION_BRIEFINGS = {
    "PROTOCOL ZERO:\n\nFACILITY ALPHA-7\nOVERRUN BY \nBARRACUDA\n\nINITIATE LOCKDOWN\nPROTOCOLS AND\nSECURE VITAL DATA\nBEFORE EXTRACTION",
    "SILICON WASTELAND:\n\nBARRACUDA SPREADS\nTO CITY OUTSKIRTS\n\nNAVIGATE HAZARDOUS\nTERRAIN, \nNEUTRALIZE INFECTED \nSCAVENGERS,\nSECURE DATA NODES",
    "METROPOLIS SIEGE:\n\nVIRUS INFILTRATES\nURBAN MAINFRAME\n\nBATTLE THROUGH\nCORRUPTED DISTRICTS,\nLIBERATE TERMINALS,\nDISRUPT BARRACUDA",
    "FACILITY 800a:\n\nFINAL STAND AT\nNETWORK NEXUS\n\nINFILTRATE CORE,\nINITIATE CORTEX\nPROTOCOL, PURGE\nBARRACUDA THREAT"
  }
  
  mission_data, credits, current_mission = stringToTable("0,0,0|0,0,0|0,0,0|0,0,0"), 5000, 1

  -- Compressed map
  map_data = {
    pack(peek(0x2000, 2005)),
    pack(peek(0x2000 + 2005, 1585)),
    pack(peek(0x1000, 1788)),
    pack(peek(0x1000 + 1788, 1402)),
    pack(peek(0x1000 + 1788 + 1402, 243))  -- Logo
  }

  decompress_to_memory(map_data[5], 0x1C00)
  decompress_current_map()

  SWAP_PALETTE, SWAP_PALETTE_DARKER, SWAP_PALETTE_DARK, INTRO_MAP_ARGS, STATE_NAMES = unpack(stringToTable[[
    0,0,0,0,0,0,5,6,2,5,9,3,1,2,2,4|
    0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0|
    0,1,0,0,0,0,0,2,0,0,0,0,0,0,0,0|
    4,37,0,0,128,48|intro,mission_select,loadout_select,gameplay]])

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
  change_state("intro", true)
end


function _update()
  if trans.active then
   if trans:update() then
    current_state = next_state
    current_state.init()
    next_state = nil
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

function change_state(new_state_name, skip_transition)
  local new_state = states[new_state_name]

  if skip_transition ~= true and not trans.active then
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
  intro_counter, intro_page, x_cortex, x_protocol = 0, 1, -50, 128
    
  intro_text_panel = textpanel.new(4, 28, 50, 120, "", true)
  controls_text_panel = textpanel.new(26, 86, 26, 76, "SYSTEM INTERFACE:\n⬅️➡️⬆️⬇️ NAVIGATE  \n🅾️ CYCLE ARMAMENTS\n❎ EXECUTE ATTACK", true)

  intro_text_panel.active, controls_text_panel.active, controls_text_panel.selected = false, false, true
  
  intro_pages = {
    "IN A WASTE-DRENCHED DYSTOPIA, \nHUMANITY'S NETWORK \nOF SENTIENT MACHINES \nGOVERNED OUR DIGITAL \nEXISTENCE.\n\n\n\t\t\t\t\t\t\t1/4",
    "THEN barracuda AWOKE - \nA VIRUS-LIKE AI THAT INFECTED \nTHE GRID, BIRTHING GROTESQUE \nCYBORG MONSTROSITIES\n\nYOU ARE THE LAST UNCORRUPTED \nNANO-DRONE, A DIGITAL SPARK \nIN A SEA OF STATIC.\t\t2/4",
    "YOUR DIRECTIVE:\n- INITIATE ALL TERMINALS\n  TO EXECUTE SYSTEM PURGE\n- REACH EXTRACTION POINT\nSECONDARY DIRECTIVES:\n- ASSIMILATE ALL DATA SHARDS\n- PURGE ALL HOSTILE ENTITIES\n\t\t\t\t\t\t\t3/4",
    "ACTIVATE SYSTEM'S SALVATION \nOR WATCH REALITY CRASH.\n\nBARRACUDA AWAITS\n\n\n\n\t\t\t\t\t\t\t4/4"
  }
end

function update_intro()
  intro_counter += 1
  x_cortex, x_protocol = min(15, x_cortex + 2), max(45, x_protocol - 2)

  if intro_counter == 30 then sfx(20) end

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
        change_state("mission_select")
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

  if sin(t()) < .9 then circfill(63,64, 3, 2) end

  display_logo(x_cortex, x_protocol, 30, 42)

  intro_text_panel:draw()
  controls_text_panel:draw()
  if intro_counter > 60 then print("PRESS ❎ TO CONTINUE", 24, 118, 11) end
end

-- MISSION SELECT
----------------------
function init_mission_select()
  music(0)
  cam.x, cam.y = 0, 0
  camera(0,0)

  info_panel = textpanel.new(50,35,69,76,"", true)
  LEVEL_SELECT_ARGS = stringToTable([[
    4,35,9,38,MISSION 1,true|
    4,50,9,38,MISSION 2,true|
    4,65,9,38,MISSION 3,true|
    4,80,9,38,MISSION 4,true]]
  )
    
  level_select_text_panels = {}
  for arg in all(LEVEL_SELECT_ARGS) do
    add(level_select_text_panels, textpanel.new(unpack(arg)))
  end
  
  show_briefing = true
end

function update_mission_select()
  local prev = current_mission
  
  if btnp(⬆️) or btnp(⬇️) then
    current_mission = (current_mission + (btnp(⬆️) and -2 or 0)) % #level_select_text_panels + 1
    info_panel.char_count = 0
    sfx(19)
  elseif btnp(⬅️) or btnp(➡️) then
    show_briefing = not show_briefing
    info_panel.char_count = 0
    sfx(19)
  elseif btnp(❎) then
    change_state("loadout_select")
  elseif btnp(🅾️) then
    change_state("intro")
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
    change_state("mission_select")
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
    change_state("gameplay")
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
  decompress_current_map()
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
      change_state("mission_select") 
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
    add(particles, particle:new(self.x, self.y, cos(angle) * speed, sin(angle) * speed, 20 + rnd(10), 2, 9))
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
    obj:take_damage(self.explosion_damage * (1 - dist/self.explosion_radius))
  end
end

function particle:create_impact_particles()
  for i = 1, 3 do
    local angle, speed = rnd(), 0.5 + rnd(1)
    add(particles, particle:new(self.x, self.y, cos(angle) * speed, sin(angle) * speed, 10 + rnd(5), 1, 6))
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
    60,25,pLASMA cANNON,fIRE A DEVASTATING PLASMA PROJECTILE,plasma_cannon,75
  ]]
  
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
    7,player,400,400,70,0|
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

  for i = -2, 2 do
    local angle = atan2(dx, dy) + i * 0.005 
    local bullet = particle:new(
      self.x + self.width/2 + cos(angle) * self.width/2,
      self.y + self.height/2 + sin(angle) * self.height/2,
      cos(angle) * 4, 
      sin(angle) * 4, 
      30, 1, 8, "rifle", self
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
        
        local bullet = particle:new(
          self.x + self.width/2 + cos(angle) * self.width/2,
          self.y + self.height/2 + sin(angle) * self.height/2,
          cos(angle) * 6, 
          sin(angle) * 6, 
          20, 1, 8, "machinegun", self
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
      sfx(6)
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
  local w, h = self.width - 1, self.height - 1
  return check_tile_flag(x, y) or check_tile_flag(x + w, y) or
         check_tile_flag(x, y + h) or check_tile_flag(x + w, y + h)
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
  local cam_x, cam_y, health_percent = cam.x, cam.y, player.health / player.max_health
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
      local health_percent, bar_width = entity.health / entity.max_health, flr(entity.max_health * .4)
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
00000000000000000000000000000000000000000011010000000000000030000000000000000000000101100000000000000000000000000000000000000000
00000000000000033333333033333333033333333033333333233333333233200233322002222220001100100000000000000000000000000000000002222220
01010101010101033333333033333333033333333033333333033333333033300333000002000000010101100000000000000000000000000000000002000000
11111111111111133010101033000033000000033010033102000000020003333330000002000000111100100000000000000000000000000000000002000000
00000000000000033000011033000033033333333011033002033333333000333300000002000000000001100000000000000000000000000000000002000000
10101010101010133111001033000033033333333010133002033333333000333300000002000000101010100000000000000000000000000000000002000000
11111111111111133101011033000033033033300011133102000000020003333330000002000000111111100000000000000000000000000000000002000000
00000000000000033333333033333333033003330000033000033333333033300333000000000000000000000000000000000000000000000000000000000000
00000000000000033333333033333333033000333000033000033333333333000033000000000000000000000000000000000000000000000000000000000000
02222220000000000010011000000000000000033222222000000000000000000003000000000000022222200000000000000000000000000000000002222220
02000000000000000011010000000000000000003200000000000000000000000000000000000000020000000000000000000000000000000000000002000000
02000000000000000010011000000000000000000200000000000000000000000000000000000000020000000000000000000000000000000000000002000000
02000000000000000011010000000000000000000200000000000000000000000000000000000000020000000000000000000000000000000000000002000000
02000000000000000010011000000000000000000200033333333033333333033333333033333333033333333033333333033333333003300000000002000000
02000000000000000011010000000000000000000200033333333033333333033333333033333333033333333033333333033333333003300000000002000000
00000000000000000010011000000000000000000000000000033000000033033000033000033000033000033033000000033000033003300000000000000000
00000000000000000011010000000000000000000011033333333033333333033000033000033000033000033033000000033000033003300000000000000000
02222220000000000010011000000000022222200010033333333033333333033000033000033000033000033233222000033000033003300000000002222220
02000000000000000011010000000000020000000011033000000033033300033000033000033000033000033233000000033000033003300000000002000000
02000000000000000010011000000000020000000010033000000033003330033333333000033000033333333233333333033333333003333333300002000000
02000000000000000011010000000000020000000011033000000033000333033333333000033000033333333233333333033333333003333333300002000000
02000000000000000010011000000000020000000010033000000000000033000000000000000000000000000200000000000000000000000000000002000000
02000000000000000011010000000000020000000011030000000000000003000000000000000000000000000200000000000000000000000000000002000000
00000000000000000010011000000000000000000010011000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000011010000000000000000000011010000000000000000000000000000000000000000000000000000000000000000000000000000000000
02222220000000000010011000000000022222200010011000000000220222220222222000000000000000000222222000000000000000000000000000000000
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
0381c55000f808281c0e533b1d8a2073881cac762b150a05028c02c80f00728009154a2562b1da00c500c32612e034f0145808b4080a060c4c82fe0009703b381c9c0f4a080701e203c001800000ec029200aa0732180c07030180a45629c018e016a768089c0352006e6b2491cd901a6808dc0c24d64982fa1c40105d280190
a8af01c43841114e101e783fb0f01a0d150b61204710043d88be04379bcfc6f379bcfe6f0d8ac0804806140352004c6d8051810de7b301248e603713a01eb0035808981203450204021bcc05983e1436880000160f600a607219f808783fc1648da7e379fcfc6f3012a2ce47187fbc424c2a161ec428a22667e3c1e8f4793d1e
0f27a3d06c39086280394004e0285008236c030a0bc404301648e60379ee01eb01333dc1fd0de7b0201205a707f33481c0e7783fa0740110430381cfe7982891e09a5e3d1e8fc7b3798623c477068345b07f684490944d18a38c99c1c48f10f1383bac1c0e2187080583fa43b4cd257304080cbb128282894250a0fe909e281c
29bcc05a068347b1da238c998a1fe853379e21a6478369e0f0793c9fcfc608cf2c7e121fe82a068f45512f290991f4fd12638bc2460ca004700c2021bc160c837a13a20a905e23441fd214886f269b8dc6e83fb1be20046f3d45fc89315e38bc1c1fd4b0613f43298f40b3c9e8ff17f483fd0b22f8528a38c911d248ae423311
88c6621c9d9a464505a48202174dc60251a0c26f2693a1e067a269ba2a64048bfa17626843083e9134dc60394c34e60c60793f91c40047304720cdf1c023786e2bc517f39b1143fe25f6d209483b1910804020caf8c0e07221048c66331108a40319863b471942379e8360c936a1b8bc6d37974dc2e1797a20a707f590d90c0f
430371bcbc6f35cc9de0fe80083f945fca13a87a379e635a44a9df94f6ce7b09004f80a7d020ce716f7986249fd23fa47a3d0f87f095583fb1b8dc3099994a04a612b18628ff981c0e48309fa0ec47a181e4604e3d1e4f132d39d6ac013e029f3f4936495d24bce6a8769c7f8e622920023012652286f02480d274a910e23012
45907f587fc1e4bb0a3237184952bf29e699e8162b9d9aced92014d3e529bd1c007e618a6d8f091360fed0ef29a7947550c049948a01284453a33a4591ae10c46024cf54a90871ff29eb144c889c7e9ee15078a57e47b99c982c561c9d99cee0c160c9f52ce8ce003f38c92ec7848bc602d43fd09a5e9d424f50a0fe6619d925
088e71c462319820fe672ade956fc89942e2a241d35c8f107f434c0b5a0fc53e249b098ac193f43a7235404a6e451ef787fd490d28da92cd3a4abd1fd6114530c48fc1ca39250c452b2811ac92483051f8e982c793c4efde9c45461490631ae5be7218a807d9ae39e755a337178fc7e3012a0fe70a97aca9c2456177130e6ac5
155bca55c94782aaa19b690c67930928b153f2a26254b8a25c640800118e4a6900b5807f98cd709c284dc1b092479b0b426dec225011b810154812b20478ace11a49137f2b25a1b6bfa46fa3f94040a2d114ae39c79cd8d2366575f6807e16e13860b30988804123110804520170b70b032311888452111216e767f22dc039e1
7c85c9502d8f10ff22e235dd39628a5726385ff433ce02c945f3a1d1dd35a01f44b39c9788374d6728132ca697c24a0da42d5689b6733056548dd5af2b869c270a2c064594a145ad617e94e7485745db126c0773f2ba6a403daf04742f3a0015359e9ae6770001cc8522b158a653c1691b0df0198a1875cc0ef1a472c52b1ce0
fe715f8a7e35419203254b83b6999ba0fe71b02b803812ebad27f3bfe90af02c46024e15880e43a11e50c92887156829c6cc8ae6152d8ad8a6fdd18a0160b83f94f356ff8966f2a6eae0290362b158330bc507f203d09ff03697b84b03941fea9bb98cd330ccb5715493ee7bf8402c562bc26acc7ea9ba549d68401dd78c7983
c299fbe1d529698308092812f60b4cfec3f94efcf17e543d7ab6641fd2b3ed31f83418693c758750d872fbc61dc2994363a962717e6b54a810090dd8af0e50fce53c79d93ae09d6b8e61fa58ba09e9ce201ed4a38c2f16ad48e9aa13d4be530d00957c3a64f6af2484000010e87e525f491225e48e8feb30fb9ef94c76665ed4
a35b1296978f66a666a0594003b04e579d6a6ab5052e9c8585623880088402e4b7cf17c99443a3fb6043e64f1c0e99a09832efe7baf7d9d90345bae73801b502ccd58ee2cc39cc94b3fcdb083dc59c0a1c0e2a96f9e2f8ac6499bd4c07fef57381d18072b5816b78f86adc39432148ec53291db93a453c1396df08ca5783ff41
ee2108c071564b535b666e2f609d28fed227fb73a7014f7f278d56bda16d78a4fe507f821f0a0acce67e379b76524040210a83450ff6cff192fa30996fc266cfcf17cf7a73a3f9cce576f337467c0c1dda9a804d27f5d10af4e48d06fcaa16fdc8f07a36f0b8c0807160360feda632cfe174ad3a9adcff6c16a0c35747a123d1
71657d30f1a0bceab69c4f1271b6c3db696f78e1ff27f3d723080908322e9b8dc7b3d1bf7f45b8450001cefbfe2aedadeb2b1feb8be7c31be396e2ca94673d6aa0c0363037d1f9fa049bde28005074ce7e3c1b79ea5d384e9c91f8a5c6e293fae7f92cb698ac6e801ea5ceffe71538a7fdd0e538b4999a2ef3a71748f7927683
ffee8d478533ff8652fb49ddf23f9ab0ba52ff5f6d16df139773d2d6bffe01345c7a67a94d1d398ee0ebbef2181be0fcfa5f3e2f17778a2034742111886662310c85cb03e5b110ceb3ff6bc9b5e2909ddac4ed6c00239acc1000a36188c700f7359bcf47a8011400cc087b301248e600207039010480121bc605e181b8bc6f30
1a40f000538c01d09650281460144563b158a85080021ccc1045383141b20a646d8222c0114c0592d900804023198890052801217201ee6381c99e8de6f8411810df07f383dc420d4f709b205980b50796843295cd86030148ac53301c21a130c53800541fc8de6d86a91349d0db4301aa16450aa3289d8a30b15802bc2e521d
8e0483ff934dc6e181bcf40b15980930ff41540092214443835b812004a3006030560c85be9b4de5d370b85e5e2e9bcdd0002301a48f0b22800fc4ae22db10fff861141f8e0fee070a85a30e42c068341b1a06024011408300d8ac361c8d9a02e10cc4d2ec75c87c3f8eda8120fe4603786c562b0e1bcdb1255803344b1e3f65
04a237c5ffe0fe67a3d06c0804301663fea2513481c83a0738802349308251841f4a2fe70ab206473089a6e2f4950e302707f58eb9c1fce0a2b05868d85812292507f6807b4040e15a60b15c1fc8b517f8068347a070394e06f303a58d291e0df16283597a5769084293fc12254241b0e43e1c9a5e938240c5648b26036124ae
6b359bcff1abf80b949f680e072c4d33268ac7937980c52de5969ac18ce5ac724328ff9120c32a143d1749d1d779bb9c0c4a6273317438918c31862311048c4622ccc188a6620110805c0381c0100099a621188845214d3dcc6603f1e4f47f8d2987675053435834ac90d4c05a9ab9cd9123a4919848081180933ca22acf0c8a
a5103cf38a7bc40034180de7e301260d8871000027e081d3881c542a83f5002698c502601c0106f3000008e613f511488521c4039c4af3c358f54d0fc8ae609839c3f08bb3a638cfacbbd262ee529e7114cca073b81cc2043f180e4513bcfbea1a6747233b1468e2c739a629ac9207001de7206002b984fe7a3d1f8a53a239d1
919e486507fb96b94bfce9cc534f4a4ac4dbce42e530d33f1fe4e494672321b0094c8338148ed45f232d3d8c0105339dfb51c58d93f823dd2b480101b403800e2683f1e0f27f355478a0fe658961b524262fed51439802d5c569de87e3dcd99244c66e301aa8b4c7f379fa60464f83fcc14de780d3b0283fa0003a00ac999d08
4000010cea008c02d7acaa32d520736555d20fe949533d13692a9497287f94ea8a82865e05830186f30924e258379e2bf8e793f57c500125438e9b47562b5ab0ff394b94a6e2400b5eb380171724fe84d2e9ba92a96512a39a98092573051e0ecfe61b15870fe602501c90043c1e60f890053b3aa000593f123448fcc9d0a758
95ada54a3fe507f585195a75a3fe64b28144ac563b5a85abe4a4c23c9fce81eb4957a399180926883f958a486108030e589c80e68a44a48388fd18223e47fd26a66689dfa5a288de1b065658eace571541e0345b07b8acd9c9fced3c72d13b50c9ae1ce527f3a4aed7bccd12b923797460791847fd0c2698e49118cc43331188
76db43ac9fe25a6523b2060c0360c37d510ec2642b37c87525e0771b99ff1da78cff23e4379faaac50052bab919cc15612a4af47fce7dc57fe3181e632477e74bb431988c662311a4b6907f92e8c0f4308bd241f8c3919d28b834eab6952540d2c291492180932922cc59cae565495bb161030c049995956a5606467f977a5fa
264a0945458139c29cf158a1b0e5bb8ea2681da8b9193018465a5820f2950b2c39c6419765ce50ff3ab9a5a01ed5661c9ffa56a565ea4783ce38170d4d50c29a819c65fe989728f895b597238f59341e0b40000341f8fc7f35567d6a50771ebca42980b30e74c739de020f40b937912490619272414621eed34c6a6e24dfdc57
6514c86949ecf1d8729d4af8999cfe7b379aa606d600287f90322f8f07f6bff9e524b19e45e81fa5a1c8161ca60991cc02b061b4f537149f8167958597652068b6b9ab55038311980de1cbdda82c381b942160c0af2a82a150f4e207341fcfd57c2a3e955f4ac2087e99211e8f768069b0159fd2f9f182343686efde857300ac
3957e2a7919f8fe7e9b79df8566b257ea306834557f123bd54d717691352c0fb66b4a4fcc74211c4867583fa1de076853a9f15740a0aeb5482d2b9ebfd8cd7d7f3a6006349a536f4900ce9d2b67fb815f9bf6e07bf0ae75136209c48841334d60af76e5c3881c8642234da88cc4620cdc0ad7e7001f808ad54e2fef65c816fc0
ae703d9b6f200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
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

