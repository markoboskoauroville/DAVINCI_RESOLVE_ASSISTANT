# DaVinci Resolve Assistant

Marko's helpers for DaVinci Resolve, the scripts that live in Resolve's own menu and the bridge the
star menu uses to reach Resolve from outside. His name for them, 9.9.2026: "I call them DaVinci
Resolve Assistant, enterprise-grade code." That means: every road has a fallback, every failure is
written down with the time, one command tells you the state of everything, and the install is one
command too.

## The pieces

    Toggle HD UHD.py        Workspace > Scripts > Utility > Toggle HD UHD. The project (and a timeline with its
                            own settings) flips between 1920x1080 and 3840x2160. The star's UHD HD Display word
                            follows (~/.config/hdbadge.json). `--read` from outside says the mode and changes nothing.
    Previous Page.py        Workspace > Scripts > Utility > Previous Page. Back to the page used before this one,
                            among every page unless the star's submenu narrowed the ring; twice and you are back. Shares
                            ~/.config/pages.json with the star's Pages app.
    Create Timeline.py      Workspace > Scripts > Utility > Create Timeline. A new timeline from the clips selected
                            in the Media Pool, named after the first clip (extension off; "name 2" if taken), nothing
                            asked. Give it a shortcut in Keyboard Customization.
    check.py                The self-check, run from a terminal: is Resolve up, does its API answer, which project,
                            resolution, page, which pages are in the bar, are the scripts installed and current,
                            which star apps are on, and the tail of the log. Exit 0 when all is well.
    install.sh              Copies the three Resolve scripts into Resolve's Scripts/Utility folder and runs check.py.

    star/                   The star's side of the assistant, mirrored here so this repository holds everything.
                            The living copies are in ~/Developer/MANTRA_STAR (its own repository); `install.sh`
                            refreshes the mirror and `check.py` says when it is behind.
      pages_helper.py       the bridge: one Python process the star's Pages app keeps while Resolve runs; tells
                            the page, opens pages, reads the page bar from UI.preset. `--selected` is its one-shot
                            road: prints how many clips the Media Pool has selected, and exits.
      importclick.lua       the star app Import Click: a double-click on an EMPTY spot of the Media Pool opens
                            File > Import > Media... (⌘I), as Premiere and After Effects do. A double-click on a
                            clip, a bin, the toolbar or anywhere else is left to Resolve.
      display.lua           the star app UHD HD Display: the word HD or UHD beside the star; a click or the
                            shortcut set in its submenu runs Toggle HD UHD.py.
      pages.lua             the star app Pages: ⌥` walks Resolve's pages like ⌘Tab (held: the row; ⇧` backwards);
                            the ring is every page unless narrowed in its submenu.
      hdbadge.lua, pagebadge.lua      the two words in the menu bar and the ⌘Tab-style row.

## The rules they keep

- **Resolve is reached two ways.** Inside Resolve a script runs with `resolve` already there. From
  outside, the same script imports Resolve's API, which needs Resolve > Preferences > System > General >
  External scripting: **Local**. When that road is shut, the star falls back to Resolve's own keys
  (⇧2..⇧8 for the pages) and says so, and the word beside the star shows the last known value.
- **Nothing dies quietly.** `pages_helper.py` waits while Resolve loads a project, reconnects when the
  API drops, and writes every failure to `~/.config/resolve-assistant.log` (rotated at 512 KB). The
  star restarts it if it ever exits while Resolve is still running.
- **Nothing polls, except the one thing that must.** Resolve's API has no event for "the page
  changed", so the helper looks twice a second while Resolve runs, and only then.
- **State is small JSON in ~/.config:** `hdbadge.json` (mode, shortcut), `pages.json` (mru, current,
  bar, ring, shortcut), `resolve-assistant.log`. Scripts inside Resolve and the star read the same files.
- **The Media Pool is found by accessibility, the empty spot by the API** (Import Click). Resolve's Qt window
  exposes the Media Pool as the split group whose toolbar holds the *Bin List* checkbox, its clip area as the
  inner split group that is not the bin list (the one with *Add Bin*). The clips themselves are not in that
  tree, so whether the spot was empty is asked of the API a quarter second after the click: nothing selected
  means empty. With External scripting shut the app says so once and opens nothing, rather than a dialog over
  a clip. One `elementAtPosition` costs a millisecond; walking Resolve's whole tree costs minutes, never do it.
- **`hs -c` piped into `head` hangs the client** (11.9.2026): probes that looked stuck were only that. Send the
  output to a file and read it.
- **Resolve's process is called `Resolve`**, not "DaVinci Resolve": look for it with
  `pgrep -f "DaVinci Resolve.app/Contents/MacOS/Resolve"`. `pgrep -x "DaVinci Resolve"` never matched, so
  the helper's first try after a launch said "gone" and the self-check never reached the API (found 9.9.2026).
- **A Hammerspoon timer nobody holds is collected before it fires.** The apps' own "on again after a reload"
  timers are kept on their module table; without that, Pages was found off while its file said enabled.
- **The page bar's choice lives in UI.preset**, a hex Qt stream with one block per screen resolution;
  see MANTRA_STAR/LESSONS.md, lesson 6, before touching that parser.

## Where it lives

GitHub: https://github.com/markoboskoauroville/DAVINCI_RESOLVE_ASSISTANT (this folder, ~/Developer/resolve-scripts).
Every change is committed and pushed. The star's side is developed in
https://github.com/markoboskoauroville/MANTRA_STAR and mirrored into `star/` by `install.sh`.

## Install and check

    ~/Developer/resolve-scripts/install.sh        copy the scripts into Resolve, then check
    python3 ~/Developer/resolve-scripts/check.py   the state of everything, in one screen

Shortcuts for the scripts inside Resolve: DaVinci Resolve > Keyboard Customization, search for the
script's name. The star's shortcuts (⌥` for pages, the UHD HD one, the key Import Click presses) are set
from the star's submenus.
