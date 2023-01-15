--- Pushes fluids from smeltery to basins and tables

--[[
  ################
      REQUIRES
  ################
]]
local logging = require "logging"
logging.setWin(window.create(term.current(), 1, 1, term.getSize()))
local context = logging.createContext("MAIN", colors.black, colors.blue)

logging.setLevel(1)
if ... then
  logging.setLevel(0)
  logging.setFile("debug.txt")
end

--[[
  ###############
     CONSTANTS
  ###############
]]

local TERM = window.create(term.current(), 1, 1, term.getSize())

-- Size of Nuggets, ingots, and blocks, in millibuckets
local NUGGET = 10 -- 16 on 1.19, 10 on 1.18
local INGOT = NUGGET * 9
local BLOCK = INGOT * 9

-- Types for inputs and outputs
local FLUID_DRAIN_TYPE = "tconstruct:drain"
local FLUID_TABLE_TYPE = "tconstruct:table"
local FLUID_BASIN_TYPE = "tconstruct:basin"

-- Names of casts
local INGOT_CAST  = "tconstruct:ingot_cast"
local NUGGET_CAST = "tconstruct:nugget_cast"
local CAST_SLOT   = 1
local ITEM_SLOT   = 2 ---@TODO See if I actually need to use this.

---@type {[string]:{[integer]:blit_color}}
local FLUID_COLORS = {
  ["tconstruct:molten_iron"] = { colors.red, colors.orange },
  ["tconstruct:molten_gold"] = { colors.yellow, colors.orange },
  ["tconstruct:molten_tin"] = { colors.lightGray, colors.cyan },
  ["tconstruct:molten_lead"] = { colors.gray, colors.blue },
  ["tconstruct:molten_electrum"] = { colors.yellow, colors.red },
  ["tconstruct:molten_aluminium"] = { colors.lightGray, colors.white },
  ["tconstruct:molten_zinc"] = { colors.lime, colors.green },
  ["tconstruct:molten_brass"] = { colors.yellow, colors.brown },
  ["tconstruct:molten_invar"] = { colors.lightGray, colors.gray },
  ["tconstruct:molten_platinum"] = { colors.cyan, colors.white },
  ["tconstruct:molten_nickel"] = { colors.white, colors.white },
  ["tconstruct:molten_bronze"] = { colors.brown, colors.orange },
  ["tconstruct:molten_copper"] = { colors.orange, colors.orange },
  ["tconstruct:liquid_soul"] = { colors.brown, colors.black },
  ["thermal:redstone"] = { colors.red, colors.black },
  ["thermal:glowstone"] = { colors.yellow, colors.white },
  ["thermal:ender"] = { colors.blue, colors.black },
  ["thermal:sap"] = { colors.brown, colors.brown },
  ["thermal:syrup"] = { colors.orange, colors.orange },
  ["thermal:resin"] = { colors.brown, colors.white },
  ["thermal:tree_oil"] = { colors.orange, colors.orange },
  ["thermal:latex"] = { colors.white, colors.lightGray },
  ["thermal:crude_oil"] = { colors.gray, colors.black },
  ["thermal:heavy_oil"] = { colors.red, colors.red },
  ["thermal:light_oil"] = { colors.orange, colors.lightGray },
  ["thermal:refined_fuel"] = { colors.yellow, colors.lightGray },
}

local FLUID_LOOKUP = {
  ["tconstruct:molten_iron"] = "Molten Iron",
  ["tconstruct:molten_gold"] = "Molten Gold",
  ["tconstruct:molten_tin"] = "Molten Tin",
  ["tconstruct:molten_lead"] = "Molten Lead",
  ["tconstruct:molten_electrum"] = "Molten Electrum",
  ["tconstruct:molten_aluminium"] = "Molten Aluminium",
  ["tconstruct:molten_zinc"] = "Molten Zinc",
  ["tconstruct:molten_brass"] = "Molten Brass",
  ["tconstruct:molten_invar"] = "Molten Invar",
  ["tconstruct:molten_platinum"] = "Molten Platinum",
  ["tconstruct:molten_nickel"] = "Molten Nickel",
  ["tconstruct:molten_bronze"] = "Molten Bronze",
  ["tconstruct:molten_copper"] = "Molten Copper",
  ["tconstruct:liquid_soul"] = "Liquid Soul",
  ["thermal:redstone"] = "Destabilized Redstone",
  ["thermal:glowstone"] = "Energized Glowstone",
  ["thermal:ender"] = "Resonant Ender",
  ["thermal:sap"] = "Sap",
  ["thermal:syrup"] = "Syrup",
  ["thermal:resin"] = "Resin",
  ["thermal:tree_oil"] = "Tree Oil",
  ["thermal:latex"] = "Latex",
  ["thermal:crude_oil"] = "Crude Oil",
  ["thermal:heavy_oil"] = "Heavy Oil",
  ["thermal:light_oil"] = "Light Oil",
  ["thermal:refined_fuel"] = "Refined Fuel",
}

local BLIT_CONVERT = {
  [1] = '0',
  [2] = '1',
  [4] = '2',
  [8] = '3',
  [16] = '4',
  [32] = '5',
  [64] = '6',
  [128] = '7',
  [256] = '8',
  [512] = '9',
  [1024] = 'a',
  [2048] = 'b',
  [4096] = 'c',
  [8192] = 'd',
  [16384] = 'e',
  [32768] = 'f',
}

for k, v in pairs(FLUID_COLORS) do
  FLUID_COLORS[k] = { BLIT_CONVERT[v[1]], BLIT_CONVERT[v[2]] }
end

local EDGES = {}
do
  local function add_edge(name)
    return function(char)
      return function(inverted)
        EDGES[name] = { char = char, inverted = inverted }
      end
    end
  end

  add_edge "TOP" '\x83' (false)
  add_edge "BOT" '\x8c' (false)
  add_edge "LEFT" '\x95' (true)
  add_edge "RIGHT" '\x95' (false)
  add_edge "CORNER_TL" '\x95' (true)
  add_edge "CORNER_TR" '\x95' (false)
  add_edge "CORNER_BL" '\x8a' (false)
  add_edge "CORNER_BR" '\x85' (false)
end

--[[
  ##############
       MAIN
  ##############
]]

local process_info = {
  working = false,
  name = "",
  needed = { 0, 0, 0 }, ---@type table<integer, integer>
  done = { 0, 0, 0 } ---@type table<integer, integer>
}

--- Quick Insert Table
---@return QIT QIT The quick insert Table.
local function QIT()
  return {
    Insert = function(self, v)
      self.n = self.n + 1
      self[self.n] = v
    end,
    n = 0
  }
end

--- Check if a position is in-between another position (inclusive)
---@param x integer Test value.
---@param y integer Test value.
---@param x1 integer First position.
---@param y1 integer First position.
---@param x2 integer Second position.
---@param y2 integer Second position.
---@return boolean is_between If the position is in-between the two given positions.
local function in_between(x, y, x1, y1, x2, y2)
  return x >= x1 and x <= x2 and y >= y1 and y <= y2
end

local buttons = QIT() ---@type QIT<button>

local function check_buttons(x, y)
  for i = 1, buttons.n do
    local button = buttons[i]

    local x_left, x_right = button.center_x - (math.floor(#button.text / 2 + 0.5)) - 1,
        button.center_x + (math.floor(#button.text / 2 + 0.5))

    if button.enabled and in_between(x, y, x_left, button.center_y - 1, x_right, button.center_y + 1) then
      button.callback()
    end
  end
end

local function draw_buttons()
  for i = 1, buttons.n do
    local button = buttons[i]

    if button.displayed then
      local win = button.win

      local x_pos = button.center_x - (math.floor(#button.text / 2 + 0.5))

      for y = -1, 1 do
        win.setCursorPos(x_pos - 1, button.center_y + y)
        win.setBackgroundColor(button.enabled and button.bg_color_enable or button.bg_color_disable)
        win.write((' '):rep(#button.text + 2))

        if y == 0 then
          win.setCursorPos(x_pos, button.center_y)
          win.write(button.text)
        end
      end
    end
  end
end

--- Create a simple button.
---@param win table The window to draw the button to.
---@param text string The text to display.
---@param center_x integer The center position of the button.
---@param center_y integer The center position of the button.
---@param txt_color colour The color of the text.
---@param bg_color_enable colour The color of the background when enabled.
---@param bg_color_disable colour The color of the background when disabled.
---@param callback fun() Called when the button is pressed.
---@return button
local function simple_button(win, text, center_x, center_y, txt_color, bg_color_enable, bg_color_disable, callback)
  ---@type button
  local button = {
    win = win,
    text = text,
    center_x = center_x,
    center_y = center_y,
    txt_color = txt_color,
    bg_color_enable = bg_color_enable,
    bg_color_disable = bg_color_disable,
    callback = callback,
    enabled = true,
    displayed = true
  }

  buttons:Insert(button)

  return button
end

--- Draw a simple progress bar to a window.
---@param win table The window to draw to.
---@param x integer X position of the left of the bar.
---@param y integer Y position.
---@param w integer The width of the bar.
---@param percent number Percentage between 0-1.
---@param color colour The color of the bar.
local function progress(win, x, y, w, percent, color)
  win.setCursorPos(x, y)
  win.setBackgroundColor(color)
  win.write((' '):rep(math.floor(w * percent + 0.5)))
end

--- Ensures only one modem is connected to the system.
local function ensure_single_modem()
  local modem_found = false

  for _, side in ipairs(rs.getSides()) do
    local peripheral_type = peripheral.getType(side)
    if peripheral_type == "modem" and peripheral.call(side, "isWireless") then
      if modem_found then
        error("Multiple wired modems connected, only one can be connected directly to the computer.", 0)
      end
      modem_found = true
    end
  end
end

--- Get the amount of blocks, ingots, and nuggets of a specific fluid exist in a specified container.
---@param container table The tank object to check
---@return number blocks The amount of blocks that can be made.
---@return number ingots The amount of ingots that can be made, after taking blocks into account.
---@return number nuggets The amount of nuggets that can be made, after taking blocks and ingots into account.
local function get_fluid_as_items(container)
  -- Determine amount of each type of item will be outputted
  local fluid = container.amount
  local blocks = fluid / BLOCK
  fluid = fluid % BLOCK
  local ingots = fluid / INGOT
  fluid = fluid % INGOT
  local nuggets = fluid / NUGGET

  -- and return it
  return math.floor(blocks), math.floor(ingots), math.floor(nuggets)
end

--- Grabs all the smeltery drain names.
---@return {[integer]:string} drains A list of drains by their peripheral name.
local function get_drains()
  local periphs = peripheral.getNames()
  local drains = {}

  for i, name in ipairs(periphs) do
    if peripheral.getType(name) == FLUID_DRAIN_TYPE then
      drains[#drains + 1] = name
    end
  end

  return drains
end

--- Grabs all the smeltery caster names.
---@return {blocks:{}, ingots:{}, nuggets:{}} casters A list of casters by their peripheral name.
local function get_casters()
  local periphs = peripheral.getNames()
  local casters = { blocks = {}, ingots = {}, nuggets = {} }

  for i, name in ipairs(periphs) do
    local tp = peripheral.getType(name)
    if tp == FLUID_BASIN_TYPE then
      casters.blocks[#casters.blocks + 1] = name
    elseif tp == FLUID_TABLE_TYPE then
      local cast = peripheral.call(name, "list")[CAST_SLOT]

      if cast then
        if cast.name == NUGGET_CAST then
          casters.nuggets[#casters.nuggets + 1] = name
        elseif cast.name == INGOT_CAST then
          casters.ingots[#casters.ingots + 1] = name
        end
      end
    end
  end

  return casters
end

--- Get a list of all fluids.
---@param drains table The drains to check for fluids.
---@return table fluids The list of all fluids available.
local function get_fluids(drains)
  local fluids = {}
  local tank_count = 0

  -- get the fluids
  for _, drain in ipairs(drains) do
    for _, tank in ipairs(peripheral.call(drain, "tanks")) do
      fluids[tank.name] = true
      tank_count = tank_count + 1
    end
  end

  print(string.format("Counted %d total tanks.", tank_count))

  return fluids
end

local move_context = logging.createContext("MOVE", colors.black, colors.white)
--- Move fluids from a single drain to multiple casters.
---@param drain string The drain to move fluids from
---@param casters table The casters to move fluids to
---@param fluid_name string The name of the fluid to be sent to the casters
---@param fluid_amount integer The amount of fluid to push to each caster.
---@param count integer The amount of times to cast this item.
---@param cast_type string Used to count how many of each is complete.
local function wrap_move_fluid(drain, casters, fluid_name, fluid_amount, count, cast_type)
  return function()
    local funcs = {}

    for i = 0, count - 1 do
      funcs[i + 1] = function()
        local caster = casters[i % #casters + 1]

        local moved = 0
        move_context.debug("Start: %s -> %s (%d x %s)", drain, caster, fluid_amount, fluid_name)
        repeat
          local _moved = peripheral.call(drain, "pushFluid", caster, fluid_amount - moved, fluid_name)
          moved = moved + _moved
          sleep(0.25) -- 4 tries per second is honestly way more than enough.
        until moved >= fluid_amount
        move_context.info("Moved: %s -> %s (%d x %s)", drain, caster, fluid_amount, fluid_name)

        if cast_type == "block" then
          process_info.done[1] = process_info.done[1] + 1
        elseif cast_type == "ingot" then
          process_info.done[2] = process_info.done[2] + 1
        elseif cast_type == "nugget" then
          process_info.done[3] = process_info.done[3] + 1
        end

        os.queueEvent("redraw_smeltery")
      end
    end

    parallel.waitForAll(table.unpack(funcs, 1, #funcs))
  end
end

--- Moves fluid from drains to casters
---@param drains table The list of drains attached to the network.
---@param casters {blocks:{}, ingots:{}, nuggets:{}} The caster types connected.
---@param fluid_name string?
local function move_fluid(drains, casters, fluid_name)
  local funcs = {}

  local totals = { 0, 0, 0 }

  for _, drain in ipairs(drains) do
    local tanks = peripheral.call(drain, "tanks")

    for i, tank in ipairs(tanks) do
      if not fluid_name or (fluid_name and tank.name == fluid_name) then
        local blocks, ingots, nuggets = get_fluid_as_items(tank)
        totals[1] = totals[1] + blocks
        totals[2] = totals[2] + ingots
        totals[3] = totals[3] + nuggets

        -- move blocks
        funcs[#funcs + 1] = wrap_move_fluid(drain, casters.blocks, tank.name, BLOCK, blocks, "block")

        -- move ingots
        funcs[#funcs + 1] = wrap_move_fluid(drain, casters.ingots, tank.name, INGOT, ingots, "ingot")

        -- move nuggets
        funcs[#funcs + 1] = wrap_move_fluid(drain, casters.nuggets, tank.name, NUGGET, nuggets, "nugget")
      end
    end
  end

  process_info.needed = totals
  process_info.done = { 0, 0, 0 }

  parallel.waitForAll(table.unpack(funcs))
end

--- Draw a box with an outline. Outline is included in width/height
---@param x integer The x position of the top left corner of the box.
---@param y integer The y position of the top left corner of the box.
---@param w integer The width of the box.
---@param h integer The height of the box.
---@param label string The name of the box, displayed centered at the top.
---@param text_color blit_color The blit color used for text color.
---@param background_color blit_color The blit color used for background color.
---@param outline_color blit_color The blit color used for the outlines.
local function outlined_box(x, y, w, h, label, text_color, background_color, outline_color)
  local top_t  = string.rep(EDGES.TOP.char, w)
  local top_tc = string.rep(EDGES.TOP.inverted and background_color or outline_color, w)
  local top_bc = string.rep(EDGES.TOP.inverted and outline_color or background_color, w)

  local bot_t  = string.rep(EDGES.BOT.char, w)
  local bot_tc = string.rep(EDGES.BOT.inverted and background_color or outline_color, w)
  local bot_bc = string.rep(EDGES.BOT.inverted and outline_color or background_color, w)

  local mid_t  = EDGES.LEFT.char .. string.rep(' ', w - 2) .. EDGES.RIGHT.char
  local mid_tc = (EDGES.LEFT.inverted and background_color or outline_color) ..
      string.rep(text_color, w - 2) .. (EDGES.RIGHT.inverted and background_color or outline_color)
  local mid_bc = (EDGES.LEFT.inverted and outline_color or background_color) ..
      string.rep(background_color, w - 2) .. (EDGES.RIGHT.inverted and outline_color or background_color)

  -- Draw the main bulk
  term.setCursorPos(x, y)
  term.blit(top_t, top_tc, top_bc)
  for _y = y + 1, y + h - 2 do
    term.setCursorPos(x, _y)
    term.blit(mid_t, mid_tc, mid_bc)
  end
  term.setCursorPos(x, y + h - 1)
  term.blit(bot_t, bot_tc, bot_bc)

  -- Draw the corners (i don't care that this is slightly inefficient)
  local function draw_corner(name)
    term.blit(
      EDGES[name].char,
      EDGES[name].inverted and background_color or outline_color,
      EDGES[name].inverted and outline_color or background_color
    )
  end

  term.setCursorPos(x, y)
  draw_corner "CORNER_TL"

  term.setCursorPos(x, y + h - 1)
  draw_corner "CORNER_BL"

  term.setCursorPos(x + w - 1, y)
  draw_corner "CORNER_TR"

  term.setCursorPos(x + w - 1, y + h - 1)
  draw_corner "CORNER_BR"

  -- Write the label
  if label then
    term.setCursorPos(x + math.floor(w / 2) - 1 - math.ceil(#label / 2), y)
    term.blit(
      ' ' .. label .. ' ',
      string.rep(text_color, #label + 2),
      string.rep(background_color, #label + 2)
    )
  end

  return window.create(term.current(), x + 1, y + 1, w - 2, h - 2)
end

--- Generate a brick pattern on the current term.
local function brick_pattern()
  local w, h = term.getSize()

  local offset       = false -- if the pattern should be offset
  local brick        = "\x8f\x85"
  local brick_open   = string.sub(brick, 1, 1)
  local brick_close  = string.sub(brick, 2, 2)
  local brick_color  = string.rep('7', w)
  local brick_bcolor = string.rep('f', w)

  for y = 1, h do
    local str_text = ""

    if offset then
      str_text = brick_close .. string.rep(brick, math.floor(w / 2)) .. brick_open
    else
      str_text = string.rep(brick, math.ceil(w / 2))
    end

    if w % 2 == 1 then -- if odd width
      str_text = str_text:sub(1, -2)
    elseif w % 2 == 0 and offset then
      str_text = str_text:sub(1, -3)
    end

    term.setCursorPos(1, y)
    term.blit(str_text, brick_color, brick_bcolor)

    offset = not offset
  end
end

local working = false
local selected_fluid

--- Main thread for displaying information and getting user input
local function ui_thread()
  local ui_context = logging.createContext("UI", colors.black, colors.green)
  local mon = peripheral.find("monitor")
  if not mon then
    error("No monitor attached to system.", 0)
  end

  mon.setTextScale(0.5)
  local sx, sy = mon.getSize()
  if sx < 57 or sy < 38 then -- by default, a 3x3 0.5x monitor should be 57x38
    error("Requires a 3x3 monitor minimum.", 0)
  end

  local win = window.create(mon, 1, 1, mon.getSize())

  -- ui-local constants
  local X_TANKS = 3
  local Y_TANKS = 3
  local W_TANKS = math.ceil(sx / 3) - 3
  local H_TANKS = sy - 4
  local tanks_win

  local X_PROCESSES = math.ceil(sx / 2) - 3
  local Y_PROCESSES = Y_TANKS
  local W_PROCESSES = math.ceil(sx / 2) - 2
  local H_PROCESSES = math.ceil(sy / 3) - 2
  local processes_win

  local X_INFO = math.ceil(sx / 2) - 3
  local Y_INFO = math.ceil(sy * 1 / 3) + 3
  local W_INFO = math.ceil(sx / 2) - 2
  local H_INFO = math.ceil(sy / 3) - 5
  local info_win

  local X_CONTROLS = math.ceil(sx / 2) - 3
  local Y_CONTROLS = math.ceil(sy * 2 / 3)
  local W_CONTROLS = math.ceil(sx / 2) - 2
  local H_CONTROLS = math.ceil(sy / 3) - 2
  local controls_win

  local button_cast_all
  local button_cast_selected

  local FLUID_CHAR = '\x7f'

  -- ui-locals
  local max_fluid = 0
  local fluid_order = {} ---@type {[integer]:string}
  local fluid_heights

  local function redraw_bg()
    ui_context.debug("Redrawing background.")
    local old = term.redirect(win)

    -- set the background pattern
    brick_pattern()

    -- outline the sections
    -- tanks
    tanks_win = outlined_box(X_TANKS, Y_TANKS, W_TANKS, H_TANKS, "FLUIDS", '0', 'f', '7')

    -- current processes
    processes_win = outlined_box(X_PROCESSES, Y_PROCESSES, W_PROCESSES, H_PROCESSES, "PROCESSING", '0', 'f', '7')

    -- information
    info_win = outlined_box(X_INFO, Y_INFO, W_INFO, H_INFO, "INFO", '0', 'f', '7')

    -- controls
    controls_win = outlined_box(X_CONTROLS, Y_CONTROLS, W_CONTROLS, H_CONTROLS, "CONTROLS", '0', 'f', '7')

    buttons = QIT() ---@type QIT<button>

    local w = controls_win.getSize()

    button_cast_all = simple_button(controls_win, "Cast all", math.ceil(w / 2), 3, colours.white, colours.green,
      colors.lightGray, function() ui_context.debug("Press cast all") os.queueEvent("smeltery_cast", "all") end)

    button_cast_selected = simple_button(controls_win, "Cast selection", math.ceil(w / 2), 7, colours.white,
      colours.green,
      colors.lightGray,
      function() ui_context.debug("Press cast selected") os.queueEvent("smeltery_cast", selected_fluid) end)
    button_cast_selected.enabled = false
    selected_fluid = nil

    term.redirect(old)
  end

  --- Grab all information, return it as a large table. Runs peripheral calls in parallel, should be faster.
  ---@return {inputs:{}, outputs:{}} bundled_info The bundled information.
  local function bundle_information()
    ui_context.debug("Getting all fluid information.")
    local inputs = QIT()
    local outputs = QIT()
    local funcs = QIT()

    local drains = get_drains()
    local casters = get_casters()

    -- Deal with the drains
    for _, drain in ipairs(drains) do
      funcs:Insert(function()
        local tanks = peripheral.call(drain, "tanks")
        for _, tank in ipairs(tanks) do
          inputs:Insert(tank)
        end
      end)
    end

    -- Deal with the casters
    for caster_type, _casters in pairs(casters) do
      for _, caster in ipairs(_casters) do
        funcs:Insert(function()
          outputs:Insert {
            type = caster_type,
            tanks = peripheral.call(caster, "tanks"),
            list = peripheral.call(caster, "list")
          }
        end)
      end
    end

    -- Run all of the peripheral calls
    parallel.waitForAll(table.unpack(funcs, 1, funcs.n))

    -- Return the data
    return { inputs = inputs, outputs = outputs }
  end

  --- Sum all input tank fluids
  ---@param tanks table The tanks to sum.
  ---@return {[string]:integer} fluids The summed fluids in name:amount format.
  ---@return integer max_fluid The current max fluid
  local function sum_max_tanks(tanks)
    local fluids = {}
    local current_total = 0

    for _, tank in ipairs(tanks) do
      if not fluids[tank.name] then
        fluids[tank.name] = 0
      end

      fluids[tank.name] = fluids[tank.name] + tank.amount
      current_total = current_total + tank.amount
    end

    max_fluid = math.max(max_fluid, current_total)

    return fluids, max_fluid
  end

  --- Get the height of each fluid.
  ---@param tanks table The tanks to get the fluid info from.
  ---@param h integer The height of the window being filled.
  ---@return table fluid_heights The height of each fluid.
  local function calculate_heights(tanks, h)
    local summed_fluids, max = sum_max_tanks(tanks)

    -- collapse the fluid_order table by what fluids are in the summed_fluids table
    for i = #fluid_order, 1, -1 do
      if not summed_fluids[fluid_order[i]] then
        table.remove(fluid_order, i)
      end
    end

    -- and then add the fluids that aren't in the summed_fluids table.
    for fluid in pairs(summed_fluids) do
      local found = false
      for _, _fluid in ipairs(fluid_order) do
        if fluid == _fluid then
          found = true
          break
        end

      end
      if not found then
        table.insert(fluid_order, fluid)
      end
    end

    -- now calculate the height of every fluid (minimum 1)
    local fluid_heights = {}
    for fluid, amount in pairs(summed_fluids) do
      -- we round down here to ensure there's space for all liquids, even if there's only a little.
      fluid_heights[fluid] = math.max(math.floor((amount / max) * h), 1)
    end

    return fluid_heights
  end

  --- Get the fluid that should be at a specific height
  ---@param y integer The height to test for.
  ---@param h integer The height of the window.
  ---@return string? The fluid at the specific height, or nil if out of bounds.
  local function get_fluid_at_height(y, h)
    local upper_bound = 0

    -- for each fluid
    for i, fluid in ipairs(fluid_order) do
      -- lower bound is the previous upper bound + 1
      local lower_bound = upper_bound + 1
      -- and upper bound is the previous upper bound + the height
      upper_bound = upper_bound + fluid_heights[fluid]

      -- if y level is within bounds
      if h - y + 1 >= lower_bound and h - y + 1 <= upper_bound then
        return fluid
      end
    end
  end

  --- Display information about the fluids in tanks_win
  ---@param tanks table The tanks to display info for.
  local function fluids(tanks)
    ui_context.debug("Draw fluids to monitor.")
    tanks_win.clear()
    local w, h = tanks_win.getSize()
    fluid_heights = calculate_heights(tanks, h)
    -- for each y value
    for y = h, 1, -1 do
      local fluid = get_fluid_at_height(y, h)
      if fluid then
        -- Generate random colors to use for this fluid if none exists.
        if not FLUID_COLORS[fluid] then
          FLUID_COLORS[fluid] = { BLIT_CONVERT[2 ^ (math.random(0, 15))], BLIT_CONVERT[2 ^ (math.random(0, 15))] }
        end

        -- Actually draw.
        tanks_win.setCursorPos(1, y)
        tanks_win.blit(
          FLUID_CHAR:rep(w),
          FLUID_COLORS[fluid][1]:rep(w),
          FLUID_COLORS[fluid][2]:rep(w)
        )
      end
    end
  end

  --- Display information about the selected fluid in info_win
  ---@param tanks table The tanks to display info for.
  local function info(tanks)
    ui_context.debug("Drawing info about selected fluid.")
    info_win.setBackgroundColor(colors.black)
    info_win.clear()

    if selected_fluid then
      local selected_tank
      for _, tank in ipairs(tanks) do
        if tank.name == selected_fluid then
          selected_tank = tank
          break
        end
      end

      local w, h = info_win.getSize()

      info_win.setCursorPos(1, math.ceil(h / 2))
      info_win.blit(('\x84'):rep(w), ('7'):rep(w), ('f'):rep(w))

      local name = FLUID_LOOKUP[selected_fluid] and FLUID_LOOKUP[selected_fluid] or selected_fluid
      info_win.setCursorPos(math.ceil(w / 2 - #name / 2), math.floor(h / 4 + 0.5))
      info_win.write(name)

      if selected_tank then
        local blocks, ingots, nuggets = get_fluid_as_items(selected_tank)

        info_win.setCursorPos(math.floor(w * 0.25 - 5 / 2 - 0.5), math.floor(h * 0.75 - 0.5))
        info_win.write("Blocks")
        info_win.setCursorPos(math.floor(w * 0.25 - #tostring(blocks) / 2 - 0.5), math.floor(h * 0.75 + 1.5))
        info_win.write(blocks)

        info_win.setCursorPos(math.floor(w / 2 - 5 / 2 + 0.5), math.floor(h * 0.75 - 0.5))
        info_win.write("Ingots")
        info_win.setCursorPos(math.floor(w / 2 - #tostring(ingots) / 2 + 0.5), math.floor(h * 0.75 + 1.5))
        info_win.write(ingots)

        info_win.setCursorPos(math.floor(w * 0.8 - 7 / 2 + 0.5), math.floor(h * 0.75 - 0.5))
        info_win.write("Nuggets")
        info_win.setCursorPos(math.floor(w * 0.8 - #tostring(nuggets) / 2 + 0.5), math.floor(h * 0.75 + 1.5))
        info_win.write(nuggets)
      else
        local txt = "Failed to get fluid data."
        info_win.setCursorPos(math.ceil((w / 2 - #txt / 2)), math.floor(h * 0.75 + 0.5))
      end
    end
  end

  local function controls()
    ui_context.debug("Draw controls.")

    controls_win.setBackgroundColor(colors.black)
    controls_win.clear()

    button_cast_all.enabled = not process_info.working
    button_cast_selected.enabled = selected_fluid and not process_info.working
    draw_buttons()
  end

  local function process()
    ui_context.debug("Draw processes.")

    processes_win.setBackgroundColor(colors.black)
    processes_win.clear()

    if process_info.working then
      local w, h = processes_win.getSize()

      local name = process_info.name
      if FLUID_LOOKUP[name] then
        name = FLUID_LOOKUP[name]
      end

      processes_win.setCursorPos(math.ceil(w / 2 - #name / 2), 2)
      processes_win.write(name)

      local blocks, ingots, nuggets = table.unpack(process_info.needed, 1, 3)
      local blocks_done, ingots_done, nuggets_done = table.unpack(process_info.done, 1, 3)

      processes_win.setCursorPos(math.floor(w * 0.25 - 5 / 2 - 0.5), math.floor(h * 0.75 - 0.5))
      processes_win.write("Blocks")
      processes_win.setCursorPos(math.floor(w * 0.25 - #tostring(blocks) / 2 - 0.5), math.floor(h * 0.75 + 1.5))
      processes_win.write(blocks)
      processes_win.setCursorPos(math.floor(w * 0.25 - #tostring(blocks) / 2 - 0.5), math.floor(h * 0.75 + 2.5))
      if blocks == blocks_done then
        processes_win.setTextColor(colors.green)
      else
        processes_win.setTextColor(colors.yellow)
      end
      processes_win.write(blocks_done)

      processes_win.setTextColor(colors.white)

      processes_win.setCursorPos(math.floor(w / 2 - 5 / 2 + 0.5), math.floor(h * 0.75 - 0.5))
      processes_win.write("Ingots")
      processes_win.setCursorPos(math.floor(w / 2 - #tostring(ingots) / 2 + 0.5), math.floor(h * 0.75 + 1.5))
      processes_win.write(ingots)
      if ingots == ingots_done then
        processes_win.setTextColor(colors.green)
      else
        processes_win.setTextColor(colors.yellow)
      end
      processes_win.setCursorPos(math.floor(w / 2 - #tostring(ingots) / 2 + 0.5), math.floor(h * 0.75 + 2.5))
      processes_win.write(ingots_done)

      processes_win.setTextColor(colors.white)

      processes_win.setCursorPos(math.floor(w * 0.8 - 7 / 2 + 0.5), math.floor(h * 0.75 - 0.5))
      processes_win.write("Nuggets")
      processes_win.setCursorPos(math.floor(w * 0.8 - #tostring(nuggets) / 2 + 0.5), math.floor(h * 0.75 + 1.5))
      processes_win.write(nuggets)
      if nuggets == nuggets_done then
        processes_win.setTextColor(colors.green)
      else
        processes_win.setTextColor(colors.yellow)
      end
      processes_win.setCursorPos(math.floor(w * 0.8 - #tostring(nuggets) / 2 + 0.5), math.floor(h * 0.75 + 2.5))
      processes_win.write(nuggets_done)

      processes_win.setTextColor(colors.white)
    end
  end

  local function redraw_loop()
    local REDRAW_RATE = 1
    local bundled_info = bundle_information()
    local timer = os.startTimer(0.1)
    ui_context.info("Loaded initial information.")

    while true do
      local event, tmr
      repeat -- wait until it's time to redraw.
        event, tmr = os.pullEvent()
      until event == "redraw_smeltery" or (event == "timer" and tmr == timer)

      if event ~= "redraw_smeltery" then
        -- collect information
        bundled_info = bundle_information()
      end

      -- Draw everything
      fluids(bundled_info.inputs)
      info(bundled_info.inputs)
      controls()
      process()

      timer = os.startTimer(REDRAW_RATE)
    end
  end

  local function input_loop()
    local name = peripheral.getName(mon) ---@type string

    -- window informations
    local fluid_win_x, fluid_win_y = tanks_win.getPosition() ---@type integer, integer
    local fluid_win_w, fluid_win_h = tanks_win.getSize() ---@type integer, integer
    local fluid_win_x2, fluid_win_y2 = fluid_win_x + fluid_win_w - 1, fluid_win_h + fluid_win_h - 1

    local control_win_x, control_win_y = controls_win.getPosition() ---@type integer, integer
    local control_win_w, control_win_h = controls_win.getSize() ---@type integer, integer
    local control_win_x2, control_win_y2 = control_win_x + control_win_w - 1, control_win_y + control_win_h - 1

    while true do
      ---@type string, string, integer, integer
      local _, monitor_touched, x, y = os.pullEvent "monitor_touch"

      if monitor_touched == name then
        if in_between(x, y, fluid_win_x, fluid_win_y, fluid_win_x2, fluid_win_y2) then
          -- touched the fluid window!
          y = y - fluid_win_y + 1
          selected_fluid = get_fluid_at_height(y, fluid_win_h)
          ui_context.info("Select: %s", selected_fluid)

          if selected_fluid and not process_info.working then
            button_cast_selected.enabled = true
          else
            button_cast_selected.enabled = false
          end
          os.queueEvent "redraw_smeltery"
        elseif in_between(x, y, control_win_x, control_win_y, control_win_x2, control_win_y2) then
          -- Touched the control window!
          ui_context.debug("Control click: %d %d", x - control_win_x + 1, y - control_win_y + 1)
          check_buttons(x - control_win_x + 1, y - control_win_y + 1)
        end
      end
    end
  end

  redraw_bg()
  ui_context.debug("Begin main loops.")
  parallel.waitForAny(redraw_loop, input_loop)
end

--- Main thread for controlling movement of fluids.
local function run_thread()
  local run_context = logging.createContext("RUN", colors.black, colors.orange)
  local drains = get_drains()
  if #drains > 1 then
    local old = TERM.getTextColor()
    TERM.setTextColor(colors.yellow)
    context.warn("Multiple drains exist. Ensure there is only one drain connected, otherwise issues will occur.")
    TERM.setTextColor(old)
    sleep(7)
  end

  local casters = get_casters()

  while true do
    local _, to_cast = os.pullEvent("smeltery_cast")
    if to_cast == "all" then
      run_context.info("Push all fluids.")
      process_info.working = true
      process_info.name = "Everything"
      move_fluid(drains, casters)
      sleep(1)
      process_info.working = false
      selected_fluid = nil
    else
      run_context.info("Push fluid %s", to_cast)
      process_info.working = true
      process_info.name = to_cast
      move_fluid(drains, casters, to_cast)
      sleep(1)
      process_info.working = false
      selected_fluid = nil
    end
  end
end

-- Main logic
context.info("Starting...")
ensure_single_modem()
local ok, err = pcall(parallel.waitForAny, ui_thread, run_thread)
if ok then
  context.error("A main thread has stopped, exiting...")
  return
end
context.error(err)
