-- apps/importbutton.lua
--
-- IMPORT BUTTON, for the star menu. Marko, 11.9.2026, after the double-click
-- version (Import Click) failed under his hand: "create my fourth mouse button.
-- X mouse button one to press Command-I inside Davinci Resolve, that's import
-- shortcut."
--
-- Ticked, mouse button 4 (X1, the thumb button; macOS numbers it 3, after
-- left 0, right 1, middle 2) pressed while DaVinci Resolve is in front is
-- ⌘I, File > Import > Media... Resolve never sees the button itself: the press
-- and its release are swallowed, only the keystroke arrives. In every other
-- app the button is left alone. Nothing polls: an event tap sleeps until a
-- button that is not left or right is pressed.
--
-- Settings, in ~/.config/importbutton.json, set from the star's submenu:
--   button   which button (default 4). "Learn the button…" waits five seconds
--            for a press and keeps whatever number the mouse reports, so a
--            mouse whose thumb button is 5 or 6 works without a manual.
--   keys     what it presses (default cmd+I, unless Keyboard Customization
--            moved Import Media).

local M = { name = "Import Button (mouse button 4 in Resolve is ⌘I, Import Media)", key = "importbutton" }

local HOME   = os.getenv("HOME")
local STATE  = HOME .. "/.config/importbutton.json"
local BUNDLE = "com.blackmagic-design.DaVinciResolve"
local DEFAULT_BUTTON = 4          -- the fourth button as a person counts it: X1, the thumb
local DEFAULT_KEYS = "cmd+I"

local types = hs.eventtap.event.types
local props = hs.eventtap.event.properties

local on = false
local tap

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

local function button()
    local b = tonumber(load().button)
    return (b and b >= 3) and math.floor(b) or DEFAULT_BUTTON
end

local function keys()
    local s = load()
    return (s.keys and s.keys ~= "") and s.keys or DEFAULT_KEYS
end

-- Written as words joined by plus: "cmd+I", "ctrl+alt+cmd+I", "F19".
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
    return mods, key and key:lower() or nil
end

-- ---------------------------------------------------------------- the press
function M.press()
    local app = hs.application.get(BUNDLE)
    if not app then return false end
    local mods, key = parse(keys())
    if not key then return false end
    hs.eventtap.keyStroke(mods, key, 0, app)
    return true
end

local function inResolve()
    local front = hs.application.frontmostApplication()
    return front ~= nil and front:bundleID() == BUNDLE
end

-- ---------------------------------------------------------------- the tap
-- macOS counts buttons from 0: the fourth button as a person counts it is number 3.
local function startTap()
    if tap then return end
    tap = hs.eventtap.new({ types.otherMouseDown, types.otherMouseUp }, function(ev)
        if ev:getProperty(props.mouseEventButtonNumber) ~= button() - 1 then return false end
        if not inResolve() then return false end
        if ev:getType() == types.otherMouseDown then
            M.pending = hs.timer.doAfter(0, M.press)          -- after the tap has answered, not inside it
        end
        return true                                           -- swallowed: Resolve gets the key, not the button
    end)
    tap:start()
end

-- ---------------------------------------------------------------- the settings
local function learn()
    hs.alert.show("Import Button: press the mouse button you want, within five seconds", 5)
    local heard = false
    M.learning = hs.eventtap.new({ types.otherMouseDown }, function(ev)
        if heard then return true end
        heard = true
        local n = ev:getProperty(props.mouseEventButtonNumber) + 1
        local s = load(); s.button = n; save(s)
        hs.alert.closeAll()
        hs.alert.show("Import Button: mouse button " .. n .. " is Import Media in Resolve", 3)
        M.learnStop = hs.timer.doAfter(0, function() if M.learning then M.learning:stop(); M.learning = nil end end)
        return true
    end)
    M.learning:start()
    M.learnTimeout = hs.timer.doAfter(5, function()
        if M.learning then M.learning:stop(); M.learning = nil end
        if not heard then hs.alert.show("Import Button: no button heard; still button " .. button(), 2) end
    end)
end

local function askKeys()
    local s = load()
    local pressed, text = hs.dialog.textPrompt("Import Button",
        "What the button presses in Resolve (cmd+I is File > Import > Media... unless Keyboard Customization changed it).\nWords joined by plus, for example  cmd+I  or  ctrl+alt+cmd+I.",
        keys(), "Set", "Cancel")
    if pressed ~= "Set" then return end
    s.keys = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    save(s)
    hs.alert.show("Import Button presses " .. keys(), 2)
end

function M.running() return on end

function M.start()
    if not hs.accessibilityState() then return false, "Hammerspoon needs Accessibility (System Settings > Privacy & Security)" end
    local s = load(); s.enabled = true; save(s)
    startTap()
    on = true
    return true, "Import Button on: mouse button " .. button() .. " in Resolve presses " .. keys()
end

function M.stop()
    local s = load(); s.enabled = false; save(s)
    if tap then tap:stop(); tap = nil end
    if M.learning then M.learning:stop(); M.learning = nil end
    on = false
    return true, "Import Button off"
end

-- ticked before: on again after a reload of Hammerspoon. The timer is kept on M: an
-- hs.timer nobody holds is collected before it fires (LESSONS.md).
if load().enabled then M.autostart = hs.timer.doAfter(1, function() M.start() end) end

function M.menu()
    if not on then return nil end
    return {
        { title = "Press it now (Import Media in Resolve)", fn = function()
            local app = hs.application.get(BUNDLE)
            if not app then hs.alert.show("Resolve is not running", 2); return end
            app:activate(); M.pending = hs.timer.doAfter(0.3, M.press)
        end },
        { title = "Learn the button…  (now mouse button " .. button() .. ")", fn = learn },
        { title = "Set the key it presses…  (" .. keys() .. ")", fn = askKeys },
    }
end

return M
