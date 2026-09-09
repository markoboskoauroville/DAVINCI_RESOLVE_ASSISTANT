-- apps/pages.lua
--
-- PAGES, for the star menu: ⌘Tab for DaVinci Resolve's pages. Marko, 9.9.2026:
-- "I need something which is same as Alt+Tab or Command+Tab in the Mac ...
-- It needs to jump only between spaces which user enabled ... Behavior must
-- be exactly the same as Command+Tab to remember last two tabs, so it
-- switches back and forth. Keyboard shortcut for that is Option+`."
--
-- Ticked, while Resolve is in front:
--   ⌥`          the page used before this one (tap it again and again: back and forth)
--   ⌥` held     a row of the pages opens, in the order they were last used, like ⌘Tab;
--               every ` moves the light one to the right, ⇧` one to the left; letting
--               go of ⌥ jumps to the lit page
-- The row holds EVERY page, unless the star's submenu narrows it, page by page
-- ("All pages again" widens it back). Marko, later the same day: "if I'm in the
-- middle of the work, I add new pages to the list, it doesn't register it. So
-- just make it work with all the pages, doesn't filter the pages at all. I can
-- filter them inside the settings of this app in the star menu." (Resolve
-- writes its page bar to UI.preset only when it quits, so following the bar
-- lagged a whole session. The helper still reports the bar, for the record.)
--
-- The three-letter name of the page stands beside the star (overlay/
-- pagebadge.lua): MED CUT EDT FUS COL FAI DEL PHO. A click on it lists the
-- ring; a page in the list is a jump.
--
-- Resolve is reached through overlay/pages_helper.py, one process that stays
-- up while Resolve runs (needs Resolve > Preferences > System > General >
-- External scripting: Local). It tells us the page whenever it changes, and
-- opens pages on request. Without it (external scripting off) a jump falls
-- back to Resolve's own ⇧2..⇧8 keys, and the word cannot follow the mouse.
-- Settings, the shortcut and the last-used order live in ~/.config/pages.json,
-- which "Previous Page.py" inside Resolve reads too.

local M = { name = "Pages (⌥` switches Resolve's pages like ⌘Tab; the page beside the star)", key = "pages" }

local HOME   = os.getenv("HOME")
local HERE   = HOME .. "/Developer/MANTRA_STAR/"
local BADGE  = HERE .. "overlay/pagebadge.lua"
local HELPER = HERE .. "overlay/pages_helper.py"
local PYTHON = HOME .. "/.pyenv/versions/3.10.14/bin/python3"
local STATE  = HOME .. "/.config/pages.json"
local PREFS  = HOME .. "/Library/Preferences/Blackmagic Design/DaVinci Resolve"
local APP    = "DaVinci Resolve"
local BUNDLE = "com.blackmagic-design.DaVinciResolve"

-- hs.application.get(name) answers with a dead object for a while after Resolve
-- quits (the helper was restarted every 20 s against nothing); the bundle id is exact
local function resolveRunning() return #hs.application.applicationsForBundleID(BUNDLE) > 0 end

local ORDER = { "media", "cut", "edit", "fusion", "color", "fairlight", "deliver", "photo" }
local NAME  = { media = "Media", cut = "Cut", edit = "Edit", fusion = "Fusion", color = "Color",
                fairlight = "Fairlight", deliver = "Deliver", photo = "Photo" }
local SHIFTKEY = { media = "2", cut = "3", edit = "4", fusion = "5", color = "6", fairlight = "7", deliver = "8" }
local DEFAULT_HOTKEY = "alt+`"

local on = false
local current = "none"           -- the page Resolve is on, as last heard
local mru = {}                   -- pages, most recently used first
local bar = {}                   -- the pages ticked in Resolve's page bar, from the helper
local task, buffer, retry        -- the helper
local hotkeys = {}
local appWatcher, prefWatcher

local function badge() return dofile(BADGE) end

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

local function remember()
    local s = load()
    s.mru, s.current, s.bar = mru, current, bar
    save(s)
end

-- ---------------------------------------------------------------- the ring
local function index(list)
    local t = {}
    for i, v in ipairs(list) do t[v] = i end
    return t
end

-- the pages in the ring, in Resolve's order: the submenu's choice if there is one, else every page
function M.ring()
    local s = load()
    local chosen = type(s.ring) == "table" and index(s.ring) or nil
    local ring = {}
    for _, p in ipairs(ORDER) do
        if not chosen or chosen[p] then ring[#ring + 1] = p end
    end
    return ring
end

local function touch(page)
    for i = #mru, 1, -1 do if mru[i] == page then table.remove(mru, i) end end
    table.insert(mru, 1, page)
    while #mru > #ORDER do table.remove(mru) end
    remember()
end

-- the row ⌘Tab shows: the current page first, then the others by last use, then the rest
local function candidates()
    local list, seen = {}, {}
    local inRing = index(M.ring())
    if current ~= "none" then list[1] = current; seen[current] = true end
    for _, p in ipairs(mru) do
        if inRing[p] and not seen[p] then list[#list + 1] = p; seen[p] = true end
    end
    for _, p in ipairs(M.ring()) do
        if not seen[p] then list[#list + 1] = p; seen[p] = true end
    end
    return list
end

-- ---------------------------------------------------------------- the helper
local function send(line)
    if task and task:isRunning() then task:setInput(line .. "\n"); return true end
    return false
end

local function heard(line)
    local cmd, arg = line:match("^(%S+)%s*(.*)$")
    if cmd == "page" then
        current = arg
        if arg ~= "none" then touch(arg) else remember() end
        badge().set(arg)
    elseif cmd == "pages" then
        bar = {}
        for p in arg:gmatch("[^,]+") do bar[#bar + 1] = p end
        remember()
    elseif cmd == "waiting" then                      -- Resolve is up, its API not yet: the helper keeps trying
        print("pages_helper: waiting for Resolve's API (a project loading, or External scripting not Local)")
    elseif cmd == "error" then
        hs.alert.show("Pages: " .. arg, 3)
    end
end

local function startHelper()
    if task and task:isRunning() then return end
    if retry then retry:stop(); retry = nil end
    buffer = ""
    task = hs.task.new(PYTHON, function()
        task = nil
        -- Resolve is still there but its API was not ready (a project loading, or
        -- External scripting not Local): ask again in a while, never in a hurry
        if on and resolveRunning() then retry = hs.timer.doAfter(20, startHelper) end
    end, function(_, out, err)
        if err and err ~= "" then print("pages_helper: " .. err) end
        buffer = buffer .. (out or "")
        while true do
            local line, rest = buffer:match("^([^\n]*)\n(.*)$")
            if not line then break end
            buffer = rest
            heard(line)
        end
        return true
    end, { "-u", HELPER })
    task:start()
end

local function stopHelper()
    if retry then retry:stop(); retry = nil end
    if task then
        send("quit")
        local t = task; task = nil
        hs.timer.doAfter(1, function() if t:isRunning() then t:terminate() end end)
    end
end

-- ---------------------------------------------------------------- a jump
function M.open(page)
    if not page or page == current then return end
    if not send("open " .. page) then
        -- the outside road is shut: Resolve's own page keys, ⇧2 Media … ⇧8 Deliver
        local k = SHIFTKEY[page]
        if not k then hs.alert.show("Pages: no way to reach " .. (NAME[page] or page) .. " without external scripting", 3); return end
        local app = hs.application.applicationsForBundleID(BUNDLE)[1]
        if app then app:activate() end
        hs.eventtap.keyStroke({ "shift" }, k, 0, app)
    end
    current = page
    touch(page)
    badge().set(page)
end

function M.previous()
    local c = candidates()
    if c[2] then M.open(c[2]) else hs.alert.show("Pages: only one page in the ring", 2) end
end

-- ---------------------------------------------------------------- ⌘Tab
local row, lit, tap, watch

local function commit()
    if tap then tap:stop(); tap = nil end
    if watch then watch:stop(); watch = nil end
    badge().hideHud()
    local target = row and row[lit]
    row = nil
    if target then M.open(target) end
end

local function step(dir)
    if not row then
        row = candidates()
        if #row < 2 then
            row = nil
            hs.alert.show("Pages: only " .. (NAME[current] or "one page") .. " is in the ring", 2)
            return
        end
        lit = 1
        -- letting go of ⌥ is the jump: an event tap hears it, and a small clock
        -- looks every tenth of a second in case the tap missed the moment
        tap = hs.eventtap.new({ hs.eventtap.event.types.flagsChanged }, function(e)
            if not e:getFlags().alt then commit() end
            return false
        end)
        tap:start()
        watch = hs.timer.doEvery(0.1, function()
            if not hs.eventtap.checkKeyboardModifiers().alt then commit() end
        end)
    end
    lit = ((lit - 1 + dir) % #row) + 1
    badge().hud(row, lit)
    if not hs.eventtap.checkKeyboardModifiers().alt then commit() end     -- a quick tap: already let go
end

-- ---------------------------------------------------------------- the shortcut
-- Written as words joined by plus: "alt+`", "ctrl+alt+cmd+P", "F18".
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

local function hotkeyText()
    local s = load()
    return (s.hotkey and s.hotkey ~= "") and s.hotkey or DEFAULT_HOTKEY
end

local function frontmost()
    local app = hs.application.frontmostApplication()
    return app and app:name() == APP
end

local function setHotkeys(enabled)
    for _, hk in ipairs(hotkeys) do if enabled then hk:enable() else hk:disable() end end
end

local function bind()
    for _, hk in ipairs(hotkeys) do hk:delete() end
    hotkeys = {}
    local text = hotkeyText()
    local mods, key = parse(text)
    if not key then return end
    local ok, hk = pcall(hs.hotkey.new, mods, key, function() step(1) end, nil, function() step(1) end)
    if not ok then hs.alert.show("Pages: cannot bind " .. text, 3); return end
    hotkeys[1] = hk
    local back, hasShift = {}, false
    for _, m in ipairs(mods) do back[#back + 1] = m; if m == "shift" then hasShift = true end end
    if not hasShift then
        back[#back + 1] = "shift"
        local ok2, hk2 = pcall(hs.hotkey.new, back, key, function() step(-1) end, nil, function() step(-1) end)
        if ok2 then hotkeys[2] = hk2 end
    end
    -- the shortcut lives only while Resolve is in front; the other apps keep their ⌥`
    setHotkeys(frontmost())
end

local function askShortcut()
    local button, text = hs.dialog.textPrompt("Pages",
        "The shortcut that walks Resolve's pages like ⌘Tab (with shift it walks backwards).\nWords joined by plus, for example  alt+`  or  ctrl+alt+cmd+P.",
        hotkeyText(), "Set", "Cancel")
    if button ~= "Set" then return end
    local s = load()
    s.hotkey = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if s.hotkey == "" then s.hotkey = nil end
    save(s)
    bind()
    hs.alert.show("Pages: " .. hotkeyText() .. " walks the pages", 2)
end

-- ---------------------------------------------------------------- the word's own menu
local function badgeMenu()
    local rows = {}
    for _, p in ipairs(M.ring()) do
        rows[#rows + 1] = { title = NAME[p], checked = (p == current), fn = function() M.open(p) end }
    end
    rows[#rows + 1] = { title = "-" }
    rows[#rows + 1] = { title = "Previous page  (" .. hotkeyText() .. ")", fn = M.previous }
    return rows
end

-- ---------------------------------------------------------------- Resolve comes and goes
local function appear()
    local s = load()
    mru = type(s.mru) == "table" and s.mru or {}
    bar = type(s.bar) == "table" and s.bar or {}
    badge().show(current, badgeMenu)
    startHelper()
end

local function leave()
    stopHelper()
    badge().hide()
    current = "none"
end

local function watchApps()
    if appWatcher then return end
    appWatcher = hs.application.watcher.new(function(name, ev)
        if name ~= APP then return end
        if ev == hs.application.watcher.launched then hs.timer.doAfter(10, function() if on then appear() end end)
        elseif ev == hs.application.watcher.terminated then leave()
        elseif ev == hs.application.watcher.activated then setHotkeys(true)
        elseif ev == hs.application.watcher.deactivated then setHotkeys(false)
        end
    end)
    appWatcher:start()
    -- Resolve writes its page bar choice to UI.preset; when that file changes, ask again
    prefWatcher = hs.pathwatcher.new(PREFS, function(paths)
        for _, p in ipairs(paths) do
            if p:match("UI%.preset$") then send("pages"); return end
        end
    end)
    prefWatcher:start()
end

function M.running() return on end

function M.start()
    if not hs.fs.attributes(HELPER) then return false, "pages_helper.py is missing" end
    local s = load(); s.enabled = true; save(s)
    on = true
    watchApps()
    bind()
    if resolveRunning() then appear() end
    return true, "Pages on: " .. hotkeyText() .. " walks Resolve's pages while Resolve is in front"
end

function M.stop()
    local s = load(); s.enabled = false; save(s)
    on = false
    for _, hk in ipairs(hotkeys) do hk:delete() end
    hotkeys = {}
    if appWatcher then appWatcher:stop(); appWatcher = nil end
    if prefWatcher then prefWatcher:stop(); prefWatcher = nil end
    commit()
    leave()
    return true, "Pages off"
end

-- ticked before: on again after a reload of Hammerspoon, without a hand on the star
-- The timer is kept on M: an hs.timer nobody holds is collected before it fires, and
-- Pages was found off after a reload while its file still said enabled (9.9.2026).
if load().enabled then M.autostart = hs.timer.doAfter(1, function() M.start() end) end

-- ---------------------------------------------------------------- the star's submenu
function M.menu()
    if not on then return nil end
    local s = load()
    local chosen = type(s.ring) == "table"
    local inRing = index(M.ring())
    local rows = {
        { title = "Previous page now  (" .. hotkeyText() .. ")", fn = M.previous },
        { title = "Set the keyboard shortcut…  (" .. hotkeyText() .. ")", fn = askShortcut },
        { title = "-" },
        { title = chosen and "PAGES IN THE RING (my own choice)" or "PAGES IN THE RING (all of them)", disabled = true },
    }
    for _, p in ipairs(ORDER) do
        rows[#rows + 1] = {
            title = "  " .. NAME[p] .. "  " .. badge().CODE[p],
            checked = inRing[p] and true or false,
            fn = function()
                local st = load()
                local ring = type(st.ring) == "table" and st.ring or M.ring()
                local keep = {}
                local had = false
                for _, q in ipairs(ring) do if q == p then had = true else keep[#keep + 1] = q end end
                if not had then keep[#keep + 1] = p end
                st.ring = keep
                save(st)
            end,
        }
    end
    if chosen then
        rows[#rows + 1] = { title = "All pages again", fn = function()
            local st = load(); st.ring = nil; save(st)
        end }
    end
    rows[#rows + 1] = { title = "-" }
    rows[#rows + 1] = { title = "Read the page again", fn = function()
        if not send("read") then startHelper() end
    end }
    return rows
end

return M
