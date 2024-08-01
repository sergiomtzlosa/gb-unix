#!/usr/bin/env python3
"""Generate src/fsdata.asm — the pristine (read-only) Unix tree in ROM.

Emits a 96-entry inode table (20 bytes/node: type, name[11], parent,
child, sibling, attrs, data ptr u16, size u16) matching src/fs.asm and
src/sram.asm, plus file content blobs. sram.asm copies this table into
battery-backed SRAM on first boot.
"""
import sys

NODE_COUNT = 96
T_FILE, T_DIR = 1, 2

# tree: (name, kind, content, [children])
F = lambda name, content="": (name, T_FILE, content, [])
D = lambda name, children=(): (name, T_DIR, "", list(children))

MOTD = """Welcome to gb-unix 1.0
(sm83)

Game Boy UNIX.
All processes are the
main loop.

Type `help` in gbsh for
a list of commands.
"""

README = """=== gb-unix ===

You are in a file
browser on a Game Boy.

CONTROLS
--------
UP/DOWN: move cursor
LEFT/RIGHT: page
A: open / enter
B: go up (cd ..)
START: open shell
SELECT: long listing

In the shell, use the
on-screen keyboard:
A: type  B: backspace
START: run command
SELECT: shift layer

Try: cat /etc/motd

Files you create are
kept in cartridge SRAM
and survive a reboot.
"""

TODO = """TODO
----
[x] boot the kernel
[x] mount / (sram)
[-] write gbsh
[ ] port doom to sm83
[ ] fix the carry flag
[ ] get a link cable
"""

IDEAS = """IDEAS
-----
* pipes: cat | cat
* a tiny C compiler
* swap: the GB printer
  as /dev/lp0
* uptime: 59.7275 fps
* rickroll in tiles
"""

PASSWD = """root:x:0:0:root:/:/bin/sh
user:x:1000:1000:
Player One:/home/user:
/bin/sh
"""

CPUINFO = """processor  : 0
vendor     : Nintendo
cpu family : SM83
model      : DMG-01
clock      : 4.194304 MHz
bogomips   : 0.42
flags      : swap halfcarry
"""

MEMINFO = """MemTotal:    8192 kB
MemFree:       42 kB
VRAM:          16 kB
WRAM:           8 kB
CartridgeRAM:   8 kB
SwapTotal:      0 kB
"""

VERSION = """gb-unix version 1.0.0
(sm83) #1 GB
"""

BIN_LS = """ls - list files.

run in gbsh:
  ls
  ls -l /bin

gbsh built-in.
"""

BIN_CAT = """cat - print files.

run in gbsh:
  cat /etc/motd
  cat a.txt

gbsh built-in.
"""

BIN_SH = """sh - the gbsh shell.

you are already
inside it. the "$"
prompt is gbsh.

gbsh built-in.
"""

BIN_UNAME = """uname - system name.

run in gbsh:
  uname

prints GB-UNIX 1.0.

gbsh built-in.
"""

BIN_GBEDIT = """gbedit - text editor

run in gbsh:
  gbedit note.txt

A: type  B: delete
B+A: newline
B+dpad: text cursor
START: save and quit
SELECT: shift layer
SELECT+START: quit

creates the file if
it does not exist.
"""

BIN_HELP = """help - list cmds.

run in gbsh:
  help

gbsh built-in.
"""

BIN_CD = """cd - change dir.

run in gbsh:
  cd /etc
  cd ..
  cd

gbsh built-in.
"""

BIN_PWD = """pwd - print cwd.

run in gbsh:
  pwd

prints /home/user
when you are there.

gbsh built-in.
"""

BIN_ECHO = """echo - print text.

run in gbsh:
  echo hello
  echo x > file

gbsh built-in.
"""

BIN_MKDIR = """mkdir - make dir.

run in gbsh:
  mkdir work

gbsh built-in.
"""

BIN_RMDIR = """rmdir - drop dir.

run in gbsh:
  rmdir work

gbsh built-in.
"""

BIN_RM = """rm - remove file.

run in gbsh:
  rm work/a

gbsh built-in.
"""

BIN_TOUCH = """touch - new file.

run in gbsh:
  touch a.txt

gbsh built-in.
"""

BIN_CLEAR = """clear - wipe screen.

run in gbsh:
  clear

gbsh built-in.
"""

BIN_WHOAMI = """whoami - user name.

run in gbsh:
  whoami

prints user.

gbsh built-in.
"""

BIN_UPTIME = """uptime - boot time.

run in gbsh:
  uptime

gbsh built-in.
"""

BIN_TOP = """top - system monitor

run in gbsh:
  top

shows uptime, the
main loop task,
inodes, SRAM heap.

A/B/START: back.
"""

BIN_EXIT = """exit - leave gbsh.

run in gbsh:
  exit

returns to the splash screen; also Select+Start.

gbsh built-in.
"""

DEV_TTY0 = "this is tty0. hello!\n"

MAN_LS = """LS(1)  User Commands

NAME
  ls - list directory
  contents

SYNOPSIS
  ls [-l] [path]

DESCRIPTION
  Lists files in a
  directory. -l shows
  permissions.

BUGS
  No colors. Game Boys
  are green enough.

GB-UNIX 1.0    2026
"""

MESSAGES = """Nov 12 06:59:59 gb
kernel: SM83 boot ok
Nov 12 07:00:00 gb
kernel: mount / (sram)
Nov 12 07:00:00 gb
init: starting gbsh
"""

TREE = D("/", [
    D("bin", [
        F("cat", BIN_CAT),
        F("cd", BIN_CD),
        F("clear", BIN_CLEAR),
        F("echo", BIN_ECHO),
        F("exit", BIN_EXIT),
        F("gbedit", BIN_GBEDIT),
        F("help", BIN_HELP),
        F("ls", BIN_LS),
        F("mkdir", BIN_MKDIR),
        F("pwd", BIN_PWD),
        F("rm", BIN_RM),
        F("rmdir", BIN_RMDIR),
        F("sh", BIN_SH),
        F("touch", BIN_TOUCH),
        F("top", BIN_TOP),
        F("uname", BIN_UNAME),
        F("uptime", BIN_UPTIME),
        F("whoami", BIN_WHOAMI),
    ]),
    D("dev", [
        F("null", ""),
        F("random", bytes([0xDE, 0xAD, 0xBE, 0xEF, 0x13, 0x37, 0x42,
                           0x24, 0x7F, 0x00, 0x5A, 0xA5, 0xC3, 0x3C])),
        F("tty0", DEV_TTY0),
    ]),
    D("etc", [
        F("motd", MOTD),
        F("hostname", "gameboy\n"),
        F("passwd", PASSWD),
    ]),
    D("home", [
        D("user", [
            F("readme.txt", README),
            F("todo.txt", TODO),
            F(".secret", "you found the dotfile!\n"),
            D("notes", [F("ideas.txt", IDEAS)]),
        ]),
    ]),
    D("proc", [
        F("cpuinfo", CPUINFO),
        F("meminfo", MEMINFO),
        F("version", VERSION),
    ]),
    D("tmp", []),
    D("usr", [
        D("share", [
            D("man", [
                D("man1", [F("ls.1", MAN_LS)]),
            ]),
        ]),
    ]),
    D("var", [
        D("log", [F("messages", MESSAGES)]),
    ]),
])


def sanitize(s):
    return "".join(c if c.isalnum() else "_" for c in s)


def main():
    nodes = []   # (name, kind, parent, child, sibling, content_path)
    blobs = []   # (label, content_bytes)

    def walk(node, parent, path):
        name, kind, content, children = node
        idx = len(nodes)
        nodes.append([name, kind, parent, -1, -1, path])
        prev = -1
        for c in children:
            cidx = walk(c, idx, path + "/" + c[0] if path != "/" else "/" + c[0])
            if prev == -1:
                nodes[idx][3] = cidx
            else:
                nodes[prev][4] = cidx
            prev = cidx
        if kind == T_FILE:
            label = "blob_" + "_".join(sanitize(p) for p in
                                       (path.split("/")[1:] or ["root"]))
            data = content if isinstance(content, bytes) else \
                content.encode("latin-1")
            blobs.append((label, data))
            nodes[idx].append(label)
        else:
            nodes[idx].append(None)
        return idx

    walk(TREE, 0xFF, "/")

    if len(nodes) > NODE_COUNT:
        print("ERROR: tree needs %d nodes > %d" % (len(nodes), NODE_COUNT))
        sys.exit(1)
    for n in nodes:
        if len(n[0]) > 10:
            print("ERROR: name too long: %r" % n[0])
            sys.exit(1)

    out = [
        '; GENERATED by tools/genfs.py - do not edit by hand.',
        '; Pristine read-only filesystem tree + content blobs.',
        '',
        'section "fsnodes", rom0',
        '',
        'fs_rom_nodes::',
    ]

    def emit_node(name, kind, parent, child, sibling, label):
        nb = name.encode("latin-1")
        pad = 11 - len(nb)
        rows = ['    db %d, %s%s, %d, %d, %d, $00' % (
            kind,
            '"%s"' % name if all(32 <= b < 127 for b in nb) else
            ", ".join("$%02X" % b for b in nb),
            ", $00" * pad, parent, child, sibling)]
        if label:
            blob = dict(blobs)[label]
            rows.append('    dw %s, %s_end - %s' % (label, label, label))
        else:
            rows.append('    dw $0000, $0000')
        return rows

    for i, n in enumerate(nodes):
        name, kind, parent, child, sibling, path, label = (
            n[0], n[1], n[2], n[3], n[4], n[5], n[6])
        out.append('    ; %d: %s' % (i, path))
        out += emit_node(name, kind, parent, child, sibling, label)

    if len(nodes) < NODE_COUNT:
        out.append('    ; free inodes')
        out.append('    ds %d * %d, $00' % (NODE_COUNT - len(nodes), 20))

    out += ['', 'section "fsblobs", romx, bank[1]', '']
    for label, content in blobs:
        out.append('%s::' % label)
        if content:
            for i in range(0, len(content), 16):
                chunk = content[i:i+16]
                out.append('    db ' + ', '.join('$%02X' % b for b in chunk))
        out.append('%s_end::' % label)
        out.append('')

    # index constants for reference/debugging
    with open('src/fsdata.asm', 'w') as f:
        f.write('\n'.join(out) + '\n')
    print("fsdata.asm: %d nodes, %d blobs" % (len(nodes), len(blobs)))


if __name__ == '__main__':
    main()
