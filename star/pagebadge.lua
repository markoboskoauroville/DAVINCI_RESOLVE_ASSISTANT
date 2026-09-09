-- overlay/pagebadge.lua
--
-- THE PAGE WORD IN THE MENU BAR, beside the star and the HD/UHD word, and the
-- ⌘Tab-style ring that shows while ⌥` is held. Marko, 9.9.2026: "I need to
-- have the name of the active page same as UHD HD at the top of my menu bar.
-- Three-letter word, not complete."
--
-- MED CUT EDT FUS COL FAI DEL PHO: the plain system font, no box, the same
-- shape as hdbadge.lua. A click on the word opens the list of the pages in
-- the ring, the current one ticked; a page in the list is a jump to it.
--
--     .show(page, menuBuilder)   the word appears
--     .set(page)                 the word changes
--     .hide()                    the word goes
--     .hud(list, sel)            the ring on screen: the pages in the order they were
--                                last used, the chosen one lit, like ⌘Tab's row of icons
--     .hideHud()
--
-- Not a star app, no tick: apps/pages.lua owns it.

local B = _G.PAGEBADGE or {}
_G.PAGEBADGE = B

B.CODE = { media = "MED", cut = "CUT", edit = "EDT", fusion = "FUS", color = "COL",
           fairlight = "FAI", deliver = "DEL", photo = "PHO", none = "---" }
B.NAME = { media = "Media", cut = "Cut", edit = "Edit", fusion = "Fusion", color = "Color",
           fairlight = "Fairlight", deliver = "Deliver", photo = "Photo", none = "no page" }

-- ---------------------------------------------------------------- the word
function B.set(page)
    B.page = page or "none"
    if B.item then B.item:setTitle(B.CODE[B.page] or "---") end
    return B.page
end

function B.show(page, menuBuilder)
    if page then B.page = page end
    if not B.item then
        B.item = hs.menubar.new(true, "mantra.pagebadge")
        B.item:setTooltip("the Resolve page; click for the ring, ⌥` walks it like ⌘Tab")
    end
    if menuBuilder then B.item:setMenu(menuBuilder) end
    B.item:setTitle(B.CODE[B.page or "none"] or "---")
    return "shown " .. tostring(B.page)
end

function B.hide()
    if B.item then B.item:delete(); B.item = nil end
    B.hideHud()
    return "hidden"
end

-- ---------------------------------------------------------------- the ring on screen
local CELL_W, CELL_H, PAD = 150, 66, 14

function B.hud(list, sel)
    local n = #list
    if n == 0 then return B.hideHud() end
    local win = hs.window.frontmostWindow()
    local screen = (win and win:screen()) or hs.screen.mainScreen()
    local f = screen:frame()
    local w, h = n * CELL_W + PAD * 2, CELL_H + PAD * 2
    local frame = { x = f.x + (f.w - w) / 2, y = f.y + (f.h - h) / 2, w = w, h = h }
    if not B.canvas then
        B.canvas = hs.canvas.new(frame)
        B.canvas:level(hs.canvas.windowLevels.popUpMenu)      -- above every window, like ⌘Tab
        B.canvas:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces)
    else
        B.canvas:frame(frame)
    end
    local els = {
        { type = "rectangle", action = "fill", fillColor = { white = 0.08, alpha = 0.88 },
          roundedRectRadii = { xRadius = 18, yRadius = 18 }, frame = { x = 0, y = 0, w = w, h = h } },
    }
    for i, page in ipairs(list) do
        local x = PAD + (i - 1) * CELL_W
        local lit = (i == sel)
        if lit then
            els[#els + 1] = { type = "rectangle", action = "fill", fillColor = { white = 1, alpha = 0.22 },
                              roundedRectRadii = { xRadius = 12, yRadius = 12 },
                              frame = { x = x + 4, y = PAD, w = CELL_W - 8, h = CELL_H } }
        end
        els[#els + 1] = { type = "text", text = B.NAME[page] or page, textSize = 21,
                          textColor = { white = 1, alpha = lit and 1 or 0.6 }, textAlignment = "center",
                          frame = { x = x, y = PAD + 10, w = CELL_W, h = 30 } }
        els[#els + 1] = { type = "text", text = B.CODE[page] or "", textSize = 11,
                          textColor = { white = 1, alpha = lit and 0.9 or 0.4 }, textAlignment = "center",
                          frame = { x = x, y = PAD + 40, w = CELL_W, h = 16 } }
    end
    B.canvas:replaceElements(els)
    B.canvas:show()
    return "hud " .. n
end

function B.hideHud()
    if B.canvas then B.canvas:delete(); B.canvas = nil end
    return "hud hidden"
end

return B
