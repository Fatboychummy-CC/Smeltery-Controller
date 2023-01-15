---@class logging
local logging = {}

---@alias colour
---| 'colours.white' # white
---| 'colours.orange' # orange
---| 'colours.magenta' # magenta
---| 'colours.lightBlue' # light blue
---| 'colours.yellow' # yellow
---| 'colours.lime' # lime
---| 'colours.pink' # pink
---| 'colours.grey' # grey
---| 'colours.lightGrey' # light grey
---| 'colours.cyan' # cyan
---| 'colours.purple' # purple
---| 'colours.blue' # blue
---| 'colours.brown' # brown
---| 'colours.green' # green
---| 'colours.red' # red
---| 'colours.black' # black

---@alias peripheral table

local file
local win
local log_level = 0

---@alias log_context {background_colour:colour, text_colour:colour, name:string}

---@enum logLevel
logging.logLevel = {
  DEBUG = 0,
  INFO = 1,
  WARN = 2,
  ERROR = 3,
  PURCHASE = 4
}
logging.logLevelNames = {}
for k, v in pairs(logging.logLevel) do logging.logLevelNames[v] = k end
logging.logLevelColours = {
  [0] = colors.gray,
  colors.white,
  colors.yellow,
  colors.red,
  colors.green
}

--- Set the window the logger logs to
---@param _win peripheral The window to log to.
function logging.setWin(_win)
  win = _win
end

--- Get the window object being used by the logger.
---@return peripheral window The window being logged to.
function logging.getWin()
  return win
end

function logging.setFile(filename)
  logging.close()
  file = fs.open(filename, 'a')
end

function logging.close()
  if file then file.close() file = nil end
end

--- Set the logging level.
---@param level logLevel
function logging.setLevel(level)
  log_level = level
end

--- Write information to the loggiing window and file.
---@param context log_context The contextual information of this log message.
---@param level logLevel The logging level, higher is "more important."
---@param s any The text to write (tostring'd if not a string).
---@param ... any If extra arguments are supplied, this will do string.format(s, ...)
local function l_write(context, level, s, ...)
  local args = table.pack(...)
  if log_level <= level then
    if win then
      local old = term.redirect(win)

      local old_bg = term.getBackgroundColor()
      local old_fg = term.getTextColor()

      write("[")
      term.setTextColor(context.text_colour)
      term.setBackgroundColor(context.background_colour)
      write(context.name)
      term.setBackgroundColor(colors.black)
      term.setTextColor(colors.white)
      write("][")
      term.setTextColor(logging.logLevelColours[level])
      write(logging.logLevelNames[level])
      term.setTextColor(colors.white)
      write("]: ")
      term.setTextColor(logging.logLevelColours[level])
      if args.n > 0 then
        write(s:format(...))
      else
        write(s)
      end

      term.setBackgroundColor(old_bg)
      term.setTextColor(old_fg)

      print()

      term.redirect(old)
    end
    if file then
      if ... then
        file.writeLine(
          ("[%s][%s]: %s"):format(context.name, logging.logLevelNames[level], s:format(...))
        )
      else
        file.writeLine(
          ("[%s][%s]: %s"):format(context.name, logging.logLevelNames[level], s)
        )
      end

      file.flush()
    end
  end
end

function logging.createContext(name, bg_color, txt_color)
  ---@type log_context
  local context = { name = name, background_colour = bg_color, text_colour = txt_color }

  ---@class logger
  local logger = {}

  function logger.debug(s, ...)
    l_write(context, 0, s, ...)
  end

  function logger.info(s, ...)
    l_write(context, 1, s, ...)
  end

  function logger.warn(s, ...)
    l_write(context, 2, s, ...)
  end

  function logger.error(s, ...)
    l_write(context, 3, s, ...)
  end

  function logger.purchase(s, ...)
    l_write(context, 4, s, ...)
  end

  return logger
end

return logging
