-- apps/importclick.lua
--
-- IMPORT CLICK, for the star menu. Marko's request, 11.9.2026: "when I double
-- click inside media pool i want that import dialogue open up same as in adobe
-- products." Premiere and After Effects open their Import dialog when you
-- double-click an empty spot of the project panel; Resolve does nothing there.
--
-- Ticked, a double-click on an EMPTY spot of Resolve's Media Pool opens
-- File > Import > Media... (Resolve's ⌘I). A double-click on a clip is left to
-- Resolve (it loads the clip into the viewer, as always); so is a double-click
-- on a bin, on the Media Pool's toolbar, or anywhere else.
--
-- How it knows. An event tap sees every second click of a double-click while
-- Resolve is in front (nothing is swallowed: Resolve gets the click as always).
-- WHERE it landed comes from macOS accessibility: Resolve's Media Pool is the
-- split group whose toolbar holds the Bin List checkbox, and its clip area is
-- the inner split group that is not the bin list (the one with the Add Bin
-- button). The clips themselves are not in the accessibility tree, so WHETHER
-- the spot was empty is asked of Resolve's own API a quarter of a second later:
-- a click on empty space leaves nothing selected, a double-click on a clip
-- leaves that clip selected (overlay/pages_helper.py --selected, one short
-- process, 50 ms). Nothing selected: the shortcut is pressed. The API road
-- needs Resolve > Preferences > System > General > External scripting: Local;
-- shut, the app says so once, writes it to ~/.config/resolve-assistant.log and
-- does nothing, rather than opening the dialog over a clip.
--
-- Settings, in ~/.config/importclick.json: the shortcut that means Import Media
-- in Resolve (cmd+I unless Keyboard Customization changed it), set from the
-- star's submenu. Nothing polls: the tap sleeps until a double-click.

local M = { name = "Import Click (a double-click on an empty spot of Resolve's Media Pool opens Import Media)", key = "importclick" }

local ax     = require("hs.axuielement")
local HOME   = os.getenv("HOME")
local PYTHON = HOME .. "/.pyenv/versions/3.10.14/bin/python3"
local HELPER = HOME .. "/Developer/MANTRA_STAR/overlay/pages_helper.py"
local STATE  = HOME .. "/.config/importclick.json"
local LOG    = HOME .. "/.config/resolve-assistant.log"
local BUNDLE = "com.blackmagic-design.DaVinciResolve"
local DEFAULT_KEYS = "cmd+I"
local SETTLE = 0.25              -- seconds after the double-click before Resolve is asked what is selected

local on = false
local tap
local said = false               -- the "External scripting" complaint, once per tick

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

local function log(text)
    local f = io.open(LOG, "a")
    if f then f:write(os.date("%Y-%m-%d %H:%M:%S") .. " importclick: " .. text .. "\n"); f:close() end
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

-- ---------------------------------------------------------------- where the click landed
local function desc(e) return e:attributeValue("AXDescription") or e:attributeValue("AXTitle") or "" end

local function hasChild(e, role, name)
    for _, k in ipairs(e:attributeValue("AXChildren") or {}) do
        if k:attributeValue("AXRole") == role and desc(k) == name then return true end
    end
    return false
end

-- true when the point is on the clip area of a Media Pool (any page that has one);
-- false on the bin list, the toolbar, a dialog, the timeline, anything else
local function onMediaPool(x, y)
    local ok, e = pcall(function() return ax.systemWideElement():elementAtPosition(x, y) end)
    if not ok or not e then return false end
    if e:attributeValue("AXRole") ~= "AXSplitGroup" then return false end
    if hasChild(e, "AXButton", "Add Bin") then return false end          -- the bin list
    local p = e:attributeValue("AXParent")
    return p ~= nil and hasChild(p, "AXCheckBox", "Bin List")            -- the Media Pool's toolbar
end

-- ---------------------------------------------------------------- the dialog
function M.open()
    local app = hs.application.get(BUNDLE)
    if not app then return false end
    local mods, key = parse(keys())
    if not key then return false end
    hs.eventtap.keyStroke(mods, key, 0, app)
    return true
end

local function judge(x, y)
    if not onMediaPool(x, y) then return end
    hs.task.new(PYTHON, function(code, out)
        local n = (out or ""):match("selected%s+(%S+)")
        print(string.format("importclick: double-click at %d,%d on the Media Pool, selected %s", x, y, tostring(n)))   -- Hammerspoon's console, for the record
        if n == "0" then
            M.open()
        elseif n == nil or n == "?" then
            if not said then
                said = true
                hs.alert.show("Import Click: Resolve does not answer.\nResolve > Preferences > System > General > External scripting: Local", 5)
            end
            log("cannot ask what is selected (exit " .. tostring(code) .. "): " .. ((out or ""):gsub("%s+$", "")))
        end
    end, { HELPER, "--selected" }):start()
end

-- ---------------------------------------------------------------- the tap
local function startTap()
    if tap then return end
    tap = hs.eventtap.new({ hs.eventtap.event.types.leftMouseDown }, function(ev)
        if ev:getProperty(hs.eventtap.event.properties.mouseEventClickState) ~= 2 then return false end
        local front = hs.application.frontmostApplication()
        if not front or front:bundleID() ~= BUNDLE then return false end
        local p = ev:location()
        -- the tap answers at once; the looking happens after Resolve has had the click
        M.pending = hs.timer.doAfter(SETTLE, function() judge(p.x, p.y) end)
        return false
    end)
    tap:start()
end

local function askKeys()
    local s = load()
    local button, text = hs.dialog.textPrompt("Import Click",
        "The shortcut that means File > Import > Media... in Resolve (cmd+I unless Keyboard Customization changed it).\nWords joined by plus, for example  cmd+I  or  ctrl+alt+cmd+I.",
        keys(), "Set", "Cancel")
    if button ~= "Set" then return end
    s.keys = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    save(s)
    hs.alert.show("Import Click presses " .. keys(), 2)
end

function M.running() return on end

function M.start()
    if not hs.fs.attributes(HELPER) then return false, "pages_helper.py not found" end
    if not hs.accessibilityState() then return false, "Hammerspoon needs Accessibility (System Settings > Privacy & Security)" end
    local s = load(); s.enabled = true; save(s)
    said = false
    startTap()
    on = true
    return true, "Import Click on: a double-click on an empty spot of the Media Pool opens Import Media (" .. keys() .. ")"
end

function M.stop()
    local s = load(); s.enabled = false; save(s)
    if tap then tap:stop(); tap = nil end
    on = false
    return true, "Import Click off"
end

-- ticked before: on again after a reload of Hammerspoon. The timer is kept on M: an
-- hs.timer nobody holds is collected before it fires (LESSONS.md).
if load().enabled then M.autostart = hs.timer.doAfter(1, function() M.start() end) end

function M.menu()
    if not on then return nil end
    return {
        { title = "Open Import Media now", fn = function()
            local app = hs.application.get(BUNDLE)
            if not app then hs.alert.show("Resolve is not running", 2); return end
            app:activate(); M.pending = hs.timer.doAfter(0.3, M.open)
        end },
        { title = "Set the Import Media shortcut…  (" .. keys() .. ")", fn = askKeys },
    }
end

return M
