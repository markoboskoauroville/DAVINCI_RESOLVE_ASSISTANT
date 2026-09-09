-- overlay/hdbadge.lua
--
-- THE HD/UHD WORD IN THE MENU BAR, beside the star. Marko, 8.9.2026: "I don't
-- like this box. Simply, next to the star menu, add the letters HD or UHD
-- when this is active." Resolve's scripts tell it what to show:
--
--     hs -c 'return dofile(os.getenv("HOME").."/Developer/MANTRA_STAR/overlay/hdbadge.lua").show("UHD")'
--     hs -c '... .set("HD")'        the word changes (Toggle HD UHD does this after a switch)
--     hs -c '... .hide()'           the word goes; .toggle(mode) shows or hides
--
-- The word is a plain menu bar item in the system font, so it looks like every
-- other menu bar text. It is there while the badge is active and goes away by
-- itself when Resolve quits (an application watcher, an event, never a poll).
-- A click on the word runs Toggle HD UHD.py from outside, which needs
-- Resolve > Preferences > System > General > External scripting: Local; the
-- menu inside Resolve and its shortcut do the same without that setting.
-- Not a star app, no tick: it exists only while a Resolve script asked for it.

local B = _G.HDBADGE or {}
_G.HDBADGE = B

local HOME = os.getenv("HOME")
local APP = "DaVinci Resolve"
local PYTHON = HOME .. "/.pyenv/versions/3.10.14/bin/python3"
local SCRIPT = HOME .. "/Library/Application Support/Blackmagic Design/DaVinci Resolve/Fusion/Scripts/Utility/Toggle HD UHD.py"

local function toggleResolution()
    hs.task.new(PYTHON, function(code, out, err)
        local line = ((out or "") .. (err or "")):match("([^\n]+)%s*$") or ""
        if code ~= 0 then
            hs.alert.show("Resolve: " .. (line ~= "" and line or "the script failed") ..
                          "\n(use Workspace > Scripts > Toggle HD UHD, or set External scripting to Local)", 4)
        end
    end, { SCRIPT }):start()
end

local function watch()
    if B.watcher then return end
    B.watcher = hs.application.watcher.new(function(name, ev)
        if name == APP and ev == hs.application.watcher.terminated then B.hide() end
    end)
    B.watcher:start()
end

B.click = toggleResolution                                -- the star app's shortcut and menu use it too

function B.set(mode)
    B.mode = mode or "?"
    if B.item then B.item:setTitle(B.mode) end
    return B.mode
end

function B.show(mode)
    if mode then B.mode = mode end
    if not B.item then
        B.item = hs.menubar.new(true, "mantra.hdbadge")
        B.item:setClickCallback(toggleResolution)
        B.item:setTooltip("the Resolve project resolution; click to switch HD / UHD")
    end
    B.item:setTitle(B.mode or "?")
    watch()
    return "shown " .. tostring(B.mode)
end

function B.hide()
    if B.item then B.item:delete(); B.item = nil end
    if B.watcher then B.watcher:stop(); B.watcher = nil end
    return "hidden"
end

function B.toggle(mode)
    if B.item then return B.hide() end
    return B.show(mode)
end

return B
