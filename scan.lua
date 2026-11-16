-- Loads ~/.config/hypr/hyprland.lua against a stand-in `hl` and prints every
-- bind it makes as "B\t<modmask>\t<key>\t<description>\t<command>". Hyprland
-- reports Lua binds without their command, so the config itself is the only
-- place that says what a key launches. Nothing is executed through Hyprland.

local modifiers = { SHIFT = 1, CTRL = 4, CONTROL = 4, ALT = 8, SUPER = 64 }

local function split_keys(keys)
  local modmask, key = 0, ""
  for part in string.gmatch(tostring(keys or ""), "[^+]+") do
    local value = part:gsub("^%s+", ""):gsub("%s+$", "")
    local modifier = modifiers[string.upper(value)]
    if modifier then modmask = modmask + modifier else key = value end
  end
  return modmask, key
end

local function clean(value)
  return (tostring(value or ""):gsub("[%c]", " "))
end

-- Stand-in for every Hyprland value the config reads: safe to index, call,
-- compare, do arithmetic on and loop over, so the scan reaches the last bind.
local noop
noop = setmetatable({}, {
  __index = function(_, key)
    if type(key) == "number" and key ~= 1 and key ~= 0 then return nil end
    return noop
  end,
  __call = function() return noop end,
  __len = function() return 0 end,
  __lt = function() return false end,
  __le = function() return false end,
  __unm = function() return 0 end,
  __add = function() return 0 end,
  __sub = function() return 0 end,
  __mul = function() return 0 end,
  __div = function() return 0 end,
  __mod = function() return 0 end,
  __idiv = function() return 0 end,
  __pow = function() return 0 end,
  __concat = function(left, right)
    if rawequal(left, noop) then return tostring(right) end
    return tostring(left)
  end,
  __tostring = function() return "" end,
})

local raw_ipairs = ipairs
function ipairs(list)
  if rawequal(list, noop) then return function() end, list, 0 end
  return raw_ipairs(list)
end

-- hl.dsp.exec_cmd("...") keeps its command; every other dispatcher is opaque.
-- Dispatchers nest (hl.dsp.window.close()), so the stand-in indexes forever.
local function opaque_dsp()
  return setmetatable({}, {
    __index = function() return opaque_dsp() end,
    __call = function() return { __exec = "" } end,
  })
end

local dsp = setmetatable({
  exec_cmd = function(command)
    return { __exec = type(command) == "string" and command or "" }
  end,
}, {
  __index = function() return opaque_dsp() end,
})

hl = setmetatable({
  dsp = dsp,
  bind = function(keys, dispatcher, opts)
    local modmask, key = split_keys(keys)
    if key == "" then return noop end

    local command = ""
    if type(dispatcher) == "table" and dispatcher.__exec then
      command = dispatcher.__exec
    elseif type(dispatcher) == "string" then
      command = dispatcher
    elseif o and o.bind_commands and o.bind_commands[dispatcher] then
      command = o.bind_commands[dispatcher]
    end

    local description = type(opts) == "table" and opts.description or ""
    print(table.concat({ "B", tostring(modmask), clean(key), clean(description), clean(command) }, "\t"))
    return noop
  end,
  get_config = function() return nil end,
}, {
  __index = function() return noop end,
})

local config = os.getenv("HOME") .. "/.config/hypr/hyprland.lua"
local file = io.open(config, "r")
if file then
  file:close()
  debug.sethook(function() error("instruction limit exceeded") end, "", 50000000)
  local ok, err = pcall(dofile, config)
  debug.sethook()
  if not ok then io.stderr:write("keytip: bind scan stopped early: " .. tostring(err) .. "\n") end
end
