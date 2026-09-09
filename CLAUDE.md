# DaVinci Resolve Assistant, for the session that works here

Read README.md first. Every helper keeps the same shape: a Resolve script runs inside Resolve with
`resolve` already there and from outside through the API (External scripting: Local), asks nothing,
falls back when a road is shut, and writes failures to `~/.config/resolve-assistant.log`. A new
script gets a line in README.md, its name in `check.py`'s SCRIPTS and in `install.sh`, and is
installed with `./install.sh`, which ends with the self-check.

**The registry.** Marko, 9.9.2026: "any apps we are creating, any code, you need to list it there
... so I keep track of what we are doing." Every script added or changed here updates the
"resolve-scripts, the DaVinci Resolve Assistant" entry in `~/Downloads/API/PROJECTS.md` in the same turn,
with the date. The other files in that folder hold keys: never read them out.

**Git.** Every change is committed here and pushed to
https://github.com/markoboskoauroville/DAVINCI_RESOLVE_ASSISTANT (remote `origin`, branch `master`).

**The star's side.** `star/` mirrors pages_helper.py, the two badges and the two apps from
~/Developer/MANTRA_STAR, where they are developed and committed (its own repository, pushed too).
Edit them there, then `./install.sh` refreshes the mirror; `check.py` flags a mirror that is behind.
