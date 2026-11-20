-- Loads ~/.config/hypr/hyprland.lua against a stand-in `hl` and prints every
-- bind it makes as "B\t<modmask>\t<key>\t<description>\t<command>". Hyprland
-- reports Lua binds without their command, so the config itself is the only
-- place that says what a key launches. Nothing is executed through Hyprland.
--
-- The config runs in a sandbox: it can read files and environment variables,
-- but processes (os.execute, io.popen), writes (io.open for writing, os.remove,
-- os.rename) and native modules are replaced by stand-ins that do nothing, so a
-- config that does work at load time has no effect when Keytip scans it.
--
-- The last line says whether the scan reached the end of the config:
--   "E\tok"                  every bind was read
--   "E\tpartial\t<reason>"    the config stopped early; binds may be missing
-- A missing "E" line (timeout, no lua) means the same as partial.

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
local function sandbox_ipairs(list)
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

sandbox_hl = setmetatable({
  dsp = dsp,
  bind = function(keys, dispatcher, opts)
    local modmask, key = split_keys(keys)
    if key == "" then return noop end

    local command = ""
    if type(dispatcher) == "table" and dispatcher.__exec then
      command = dispatcher.__exec
    elseif type(dispatcher) == "string" then
      command = dispatcher
    elseif sandbox.o and sandbox.o.bind_commands and sandbox.o.bind_commands[dispatcher] then
      command = sandbox.o.bind_commands[dispatcher]
    end

    local description = type(opts) == "table" and opts.description or ""
    print(table.concat({ "B", tostring(modmask), clean(key), clean(description), clean(command) }, "\t"))
    return noop
  end,
  get_config = function() return nil end,
}, {
  __index = function() return noop end,
})

-- ---------------------------------------------------------------- sandbox

local function inert_file()
  local file = {}
  function file.read() return nil end
  function file.lines() return function() end end
  function file.write() return file end
  function file.close() return true end
  function file.flush() return file end
  function file.seek() return 0 end
  function file.setvbuf() return true end
  return file
end

local real_open = io.open
local real_popen = io.popen

-- Omarchy's own config asks three read-only questions through a shell: which
-- dictation backend is set, which cursor theme is set, and which *.lua files
-- a directory holds. Those exact commands run; every other command is
-- replaced by an empty result, as if the program were not installed, and
-- named on stderr.
local function popen_allowed(command)
  command = tostring(command)
  if command == "omarchy-default-dictation 2>/dev/null" then return true end
  if command == "gsettings get org.gnome.desktop.interface cursor-theme 2>/dev/null" then return true end
  local directory = command:match("^find '([^'\n]*)' %-maxdepth 1 %-type f %-name '%*%.lua' %-printf '%%f\\n' 2>/dev/null | sort$")
  return directory ~= nil
end

local function guarded_popen(command, mode)
  if popen_allowed(command) and (mode == nil or mode == "r") then return real_popen(command, "r") end
  io.stderr:write("keytip: scan skipped a shell command: " .. clean(command) .. "\n")
  return inert_file()
end
local function open_read_only(path, mode)
  mode = mode or "r"
  if not tostring(mode):match("^rb?$") then return nil, "read-only", 1 end
  return real_open(path, mode)
end

local sandbox_package = {
  loaded = {},
  preload = {},
  path = package.path,
  cpath = "",
  config = package.config,
  searchpath = package.searchpath,
}

local function pick(source, names)
  local out = {}
  for _, name in raw_ipairs(names) do out[name] = source[name] end
  return out
end

local function noop_function() return nil end

sandbox = pick(_G, {
  "assert", "collectgarbage", "error", "getmetatable", "next", "pairs", "pcall", "rawequal",
  "rawget", "rawlen", "rawset", "select", "setmetatable", "tonumber", "tostring", "type", "xpcall",
})
sandbox._G = sandbox
sandbox._VERSION = _VERSION
sandbox.string = pick(string, { "byte", "char", "find", "format", "gmatch", "gsub", "len", "lower", "match", "rep", "reverse", "sub", "upper", "pack", "packsize", "unpack" })
sandbox.table = table
sandbox.math = math
sandbox.utf8 = utf8
sandbox.coroutine = coroutine
sandbox.os = {
  getenv = os.getenv, time = os.time, date = os.date, clock = os.clock, difftime = os.difftime,
  tmpname = function() return "/dev/null" end,
  execute = noop_function, remove = noop_function, rename = noop_function, exit = noop_function,
  setlocale = noop_function,
}
sandbox.io = {
  open = open_read_only,
  lines = function(path, ...)
    local file = open_read_only(path, "r")
    if not file then error("cannot read " .. tostring(path), 2) end
    return file:lines(...)
  end,
  popen = guarded_popen,
  write = noop_function, read = noop_function, close = noop_function,
  stdout = inert_file(), stderr = inert_file(), stdin = inert_file(),
}
sandbox.print = function() end
sandbox.ipairs = sandbox_ipairs
sandbox.hl = sandbox_hl
sandbox.package = sandbox_package

local function run_chunk(path, name, ...)
  local chunk, err = loadfile(path, "t", sandbox)
  if not chunk then error(err, 0) end
  return chunk(name, path, ...)
end

sandbox.dofile = function(path) return run_chunk(path, path) end
sandbox.loadfile = function(path, _, env) return loadfile(path, "t", env or sandbox) end
sandbox.load = function(chunk, name, _, env) return load(chunk, name, "t", env or sandbox) end
sandbox.require = function(name)
  name = tostring(name)
  local loaded = sandbox_package.loaded
  if loaded[name] ~= nil then return loaded[name] end
  local preload = sandbox_package.preload[name]
  local path
  if preload then
    loaded[name] = preload(name, ":preload:")
  else
    local found, searched = package.searchpath(name, sandbox_package.path)
    if not found then error("module '" .. name .. "' not found:" .. tostring(searched), 2) end
    path = found
    local result = run_chunk(found, name)
    if result ~= nil then loaded[name] = result end
  end
  if loaded[name] == nil then loaded[name] = true end
  return loaded[name]
end
sandbox_package.loaded._G = sandbox

-- ------------------------------------------------------------------- scan

local config = os.getenv("HOME") .. "/.config/hypr/hyprland.lua"
local file = io.open(config, "r")
local outcome = "partial\tno hyprland.lua"
if file then
  file:close()
  debug.sethook(function() error("instruction limit exceeded") end, "", 50000000)
  local ok, err = pcall(run_chunk, config, config)
  debug.sethook()
  if ok then
    outcome = "ok"
  else
    outcome = "partial\t" .. clean(err)
    io.stderr:write("keytip: bind scan stopped early: " .. tostring(err) .. "\n")
  end
end
print("E\t" .. outcome)
