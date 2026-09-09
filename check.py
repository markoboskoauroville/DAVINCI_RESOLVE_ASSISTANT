#!/usr/bin/env python3
"""
check.py, the DaVinci Resolve Assistant's self-check. One screen that says the
state of everything: Resolve, its API, the project, the scripts, the star's
apps, the log. Exit code 0 when all is well, 1 when something needs a hand.

    python3 ~/Developer/resolve-scripts/check.py
"""

import filecmp
import json
import os
import subprocess
import sys
import time

HOME = os.path.expanduser('~')
HERE = os.path.dirname(os.path.abspath(__file__))
UTILITY = HOME + '/Library/Application Support/Blackmagic Design/DaVinci Resolve/Fusion/Scripts/Utility'
SCRIPTS = ['Toggle HD UHD.py', 'Previous Page.py', 'Create Timeline.py']
HELPER = HOME + '/Developer/MANTRA_STAR/overlay/pages_helper.py'
LOG = HOME + '/.config/resolve-assistant.log'
PREF = HOME + '/Library/Preferences/Blackmagic Design/DaVinci Resolve/UI.preset'
VERSION = HOME + '/Library/Preferences/Blackmagic Design/DaVinci Resolve/.version'

OK, BAD, INFO = '  ok   ', '  FIX  ', '       '
trouble = []


def line(mark, text):
    print(mark + text)
    if mark == BAD:
        trouble.append(text)


def running():
    try:
        return subprocess.run(['pgrep', '-x', 'DaVinci Resolve'], capture_output=True, timeout=3).returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


def load_json(path):
    try:
        with open(path) as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return {}


def main():
    print('DaVinci Resolve Assistant, ' + time.strftime('%d.%m.%Y %H:%M'))
    print()

    # ---- Resolve itself
    try:
        with open(VERSION) as fh:
            ver = [l.split('=', 1)[1].strip() for l in fh if l.startswith('Resolve.Version')][0]
    except (OSError, IndexError):
        ver = '?'
    up = running()
    line(OK if up else INFO, 'Resolve %s is %s' % (ver, 'running' if up else 'not running'))

    # ---- the API
    r = None
    if up:
        sys.path.append(HERE)
        sys.path.append(os.path.dirname(HELPER))
        try:
            import pages_helper                                   # noqa: E402
            r = pages_helper.get_resolve()
        except Exception as e:                                    # noqa: BLE001
            line(BAD, 'pages_helper.py cannot be imported: %s' % e)
        if r:
            line(OK, 'the API answers (External scripting is Local)')
            pm = r.GetProjectManager()
            project = pm.GetCurrentProject() if pm else None
            if project:
                w = project.GetSetting('timelineResolutionWidth')
                h = project.GetSetting('timelineResolutionHeight')
                mode = 'UHD' if str(w) == '3840' else 'HD' if str(w) == '1920' else 'other'
                line(OK, 'project "%s", %s x %s (%s)' % (project.GetName(), w, h, mode))
                tl = project.GetCurrentTimeline()
                line(INFO, 'timeline: %s' % (tl.GetName() if tl else 'none'))
            else:
                line(INFO, 'no project is open (the Project Manager?)')
            line(OK, 'page: %s' % (r.GetCurrentPage() or 'none'))
        else:
            line(BAD, 'the API does not answer: Resolve > Preferences > System > General > External scripting: Local'
                      ' (or a project is still loading)')
    else:
        line(INFO, 'API not checked (Resolve is not running)')

    # ---- the page bar
    if os.path.exists(PREF):
        try:
            sys.path.append(os.path.dirname(HELPER))
            import pages_helper                                   # noqa: E402
            ring = pages_helper.enabled_pages()
            age = time.time() - os.path.getmtime(PREF)
            line(OK, 'pages in the bar: %s   (UI.preset written %s ago)' % (', '.join(ring), pretty(age)))
        except Exception as e:                                    # noqa: BLE001
            line(BAD, 'UI.preset cannot be read: %s' % e)
    else:
        line(BAD, 'UI.preset is missing; every page will be in the ring')

    # ---- the scripts inside Resolve
    for name in SCRIPTS:
        src, dst = os.path.join(HERE, name), os.path.join(UTILITY, name)
        if not os.path.exists(dst):
            line(BAD, '%s is not installed in Resolve (run install.sh)' % name)
        elif not filecmp.cmp(src, dst, shallow=False):
            line(BAD, '%s in Resolve differs from this folder (run install.sh)' % name)
        else:
            line(OK, '%s installed and current' % name)
    line(OK if os.path.exists(HELPER) else BAD, 'pages_helper.py %s' % ('present' if os.path.exists(HELPER) else 'MISSING at ' + HELPER))

    # ---- the star's apps and their state
    hd = load_json(HOME + '/.config/hdbadge.json')
    pg = load_json(HOME + '/.config/pages.json')
    line(INFO, 'UHD HD Display: %s, mode %s, shortcut %s' % ('on' if hd.get('enabled') else 'off', hd.get('mode', '?'), hd.get('hotkey') or 'none'))
    line(INFO, 'Pages: %s, shortcut %s, last used %s%s' % (
        'on' if pg.get('enabled') else 'off', pg.get('hotkey') or 'alt+`',
        ' > '.join(pg.get('mru', [])[:4]) or 'nothing yet',
        (', own ring: ' + ', '.join(pg['ring'])) if isinstance(pg.get('ring'), list) else ''))
    try:
        out = subprocess.run(['pgrep', '-f', 'pages_helper.py'], capture_output=True, text=True, timeout=3).stdout.split()
        line(INFO, 'pages_helper processes: %d' % len(out))
    except (OSError, subprocess.TimeoutExpired):
        pass

    # ---- the log
    print()
    if os.path.exists(LOG):
        with open(LOG) as fh:
            tail = fh.readlines()[-5:]
        print('  log, last lines (%s):' % LOG)
        for l in tail:
            print('    ' + l.rstrip())
    else:
        print('  no log yet (%s)' % LOG)

    print()
    if trouble:
        print('%d thing(s) to fix.' % len(trouble))
        return 1
    print('All well.')
    return 0


def pretty(seconds):
    if seconds < 90:
        return '%d s' % seconds
    if seconds < 5400:
        return '%d min' % (seconds / 60)
    if seconds < 172800:
        return '%.1f h' % (seconds / 3600)
    return '%d days' % (seconds / 86400)


if __name__ == '__main__':
    sys.exit(main())
