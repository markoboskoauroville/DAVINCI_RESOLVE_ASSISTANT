-- apps/display.lua
--
-- UHD HD DISPLAY, for the star menu. Marko's request, 8.9.2026: "I need the
-- star menu item now. Call it UHD HD Display. When I activate it, it reads my
-- resolution state and it follows. If I'm changing it with the other script,
-- then it toggles." And: "let this display text be a toggle, and we are
-- working through Hammerspoon. I just toggle from the top of my menu. And add
-- a setting for this app so I can define a keyboard shortcut."
--
-- Ticked, the word HD or UHD stands in the menu bar beside the star (the
-- plain system font, no box: overlay/hdbadge.lua). A click on the word
-- switches the project between HD and UHD; so does the shortcut, which is set
-- from the star's submenu ("Set the keyboard shortcut…", for example
-- ctrl+alt+cmd+U) and kept in ~/.config/hdbadge.json. Both run Resolve's own
-- script "Toggle HD UHD.py" from outside, which needs Resolve > Preferences >
-- System > General > External scripting: Local. The word reads the project
-- ONCE when ticked (the same script with --read) and after that only follows
-- the switches, from here or from Resolve's menu; nothing polls. Unticked,
-- the word goes.

local M = { name = "UHD HD Display (the resolution beside the star; click or shortcut switches)", key = "display" }

local HOME   = os.getenv("HOME")
local LUA    = HOME .. "/Developer/MANTRA_STAR/overlay/hdbadge.lua"
local PYTHON = HOME .. "/.pyenv/versions/3.10.14/bin/python3"
local SCRIPT = HOME .. "/Library/Application Support/Blackmagic Design/DaVinci Resolve/Fusion/Scripts/Utility/Toggle HD UHD.py"
local STATE  = HOME .. "/.config/hdbadge.json"
local BUNDLE = "com.blackmagic-design.DaVinciResolve"
local function resolveRunning() return #hs.application.applicationsForBundleID(BUNDLE) > 0 end   -- exact; get(name) lies after a quit

local on = false
local hotkey

local function badge() return dofile(LUA) end

-- ---------------------------------------------------------------- the settings file
local function load()
    local f = io.open(STATE)
    if not f then return {} end
    local ok, j = pcall(hs.json.decode, f:read("a")); f:close()
    return (ok and type(j) == "table") and j or {}
end

local function save(t)
    hs.fs.mkdir(HOME .. "/.config")
    local f = io.open(STATE, "w")
    if f then f:write(hs.json.encode(t)); f:close() end
end

-- ---------------------------------------------------------------- the shortcut
-- Written as words joined by plus: "ctrl+alt+cmd+U", "cmd+shift+R", "F19".
local function parse(text)
    local mods, key = {}, nil
    for part in (text or ""):gmatch("[^%+%s]+") do
        local p = part:lower()
        if p == "ctrl" or p == "control" then mods[#mods + 1] = "ctrl"
        elseif p == "alt" or p == "option" or p == "opt" then mods[#mods + 1] = "alt"
        elseif p == "cmd" or p == "command" then mods[#mods + 1] = "cmd"
        elseif p == "shift" then mods[#mods + 1] = "shift"
        else key = part end
    end
    return mods, key
end

local function bind()
    if hotkey then hotkey:delete(); hotkey = nil end
    local s = load()
    if not s.hotkey or s.hotkey == "" then return end
    local mods, key = parse(s.hotkey)
    if not key then return end
    local ok, hk = pcall(hs.hotkey.bind, mods, key, function() badge().click() end)
    if ok then hotkey = hk else hs.alert.show("UHD HD Display: cannot bind " .. s.hotkey, 3) end
end

local function askShortcut()
    local s = load()
    local button, text = hs.dialog.textPrompt("UHD HD Display", "The keyboard shortcut that switches HD and UHD in Resolve.\nWords joined by plus, for example  ctrl+alt+cmd+U  or  F19.\nLeave it empty for no shortcut.",
                                              s.hotkey or "ctrl+alt+cmd+U", "Set", "Cancel")
    if button ~= "Set" then return end
    s.hotkey = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    save(s)
    bind()
    hs.alert.show(s.hotkey ~= "" and ("UHD HD Display: " .. s.hotkey .. " switches") or "UHD HD Display: no shortcut", 2)
end

-- ---------------------------------------------------------------- the word
function M.read()
    if not resolveRunning() then badge().set("?"); return end
    hs.task.new(PYTHON, function(code, out)
        local line = (out or ""):match("([^\n]+)%s*$") or ""
        if code == 0 and (line == "HD" or line == "UHD") then badge().set(line)
        else badge().set(load().mode or "?") end          -- the outside road is shut: the last known
    end, { SCRIPT, "--read" }):start()
end

-- ---------------------------------------------------------------- Resolve comes and goes
-- Marko: "if DaVinci is run, it can start displaying." Ticked once, the app
-- stays on (remembered in the settings file, so a Hammerspoon reload keeps
-- it): the word appears when Resolve is running and goes when Resolve quits,
-- on launch and quit events, never a poll.
local watcher

local function appear()
    badge().show(load().mode or "?")
    M.read()
end

local function watch()
    if watcher then return end
    watcher = hs.application.watcher.new(function(name, ev)
        if name ~= "DaVinci Resolve" then return end
        if ev == hs.application.watcher.launched then hs.timer.doAfter(10, appear)   -- the project needs a moment
        elseif ev == hs.application.watcher.terminated then badge().hide() end
    end)
    watcher:start()
end

function M.running() return on end

function M.start()
    if not hs.fs.attributes(SCRIPT) then return false, "Toggle HD UHD.py not found in Resolve's scripts" end
    local s = load(); s.enabled = true; save(s)
    watch()
    bind()
    if resolveRunning() then appear() end
    on = true
    return true, "UHD HD Display on: the word shows whenever Resolve runs" ..
        ((s.hotkey and s.hotkey ~= "") and ("; " .. s.hotkey .. " switches") or "")
end

function M.stop()
    local s = load(); s.enabled = false; save(s)
    if hotkey then hotkey:delete(); hotkey = nil end
    if watcher then watcher:stop(); watcher = nil end
    badge().hide()
    on = false
    return true, "UHD HD Display off"
end

-- ticked before: on again after a reload of Hammerspoon, without a hand on the star
-- The timer is kept on M: an hs.timer nobody holds is collected before it fires, and
-- Pages was found off after a reload while its file still said enabled (9.9.2026).
if load().enabled then M.autostart = hs.timer.doAfter(1, function() M.start() end) end

function M.menu()
    if not on then return nil end
    local s = load()
    return {
        { title = "Switch HD / UHD now", fn = function() badge().click() end },
        { title = "Set the keyboard shortcut…  (" .. ((s.hotkey and s.hotkey ~= "") and s.hotkey or "none") .. ")", fn = askShortcut },
        { title = "Read the resolution again", fn = M.read },
    }
end

return M
