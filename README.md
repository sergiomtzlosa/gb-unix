# gb-unix —  Unix filesystem-like for Game Boy

![gb-unix](preview.png)

A playable Game Boy ROM that boots into a tiny Unix-like environment: a file
browser over a fake root filesystem (`/`, `/bin`, `/etc`, `/home/user`, ...)
plus a mini shell (`gbsh`) where you type real commands on an on-screen
keyboard. Files you create survive power-off via battery-backed SRAM —
exactly like a game save.

Written in **RGBDS assembly**, with the `gbsh` shell's `pwd`/`echo` output
path implemented in C (compiled with [SDCC](https://sdcc.sourceforge.net/)
to RGBDS-syntax assembly and assembled with `rgbasm`). The ROM is 32 KB,
MBC1 with 8 KB battery-backed RAM (cart type `0x03`).

## Controls

| Key | Browser mode | Shell mode | File pager |
|---|---|---|---|
| **D-Pad Up/Down** | Move cursor in listing | Move on on-screen keyboard | Scroll 1 line |
| **D-Pad Left/Right** | Page up/down | Move on keyboard (wraps) | Page up/down |
| **A** | Enter dir / open file | Type character | Close |
| **B** | `cd ..` (parent dir) | Backspace | Close |
| **B + Up** | Jump to `/` | — | — |
| **B + Down** | Jump to `/home/user` | — | — |
| **Start** | Enter shell (`gbsh`) | Execute command | Close |
| **Select** | Toggle long listing (`drwxr-xr-x`) | Toggle shift layer (caps/symbols) | — |
| **Select + Start** | Key help | Leave shell (back to browser) | — |

On the title screen, **Start** or **A** logs in and **Select** opens the key
help. A tiny pixel-art Tux + `GB-UNIX` logo tops the splash.

## The screens

1. **Title** — boot screen with the Tux + `GB-UNIX` splash; Start/A logs in,
   Select opens the key help.
2. **Browser** — an `ls`-style listing of the current directory with a cursor.
   The header shows the cwd path, the footer shows the selected item's info
   (`name`, item count for dirs, `sizeB ro/rw` for files). Select toggles the
   long listing: `drwxr-xr-x bin`.
3. **File pager** — full-screen text view of a file's contents, scrollable
   with Up/Down, paged with Left/Right, closed with A/B/Start.
4. **Shell** — a scrolling 20×11 terminal with a path prompt (`/$`, `/etc$`,
   `/home/user$`; deep paths fall back to their basename), an input line, and
   a 6×10 QWERTY-ish on-screen keyboard (lowercase letters, digits, symbols
   via the shift layer).
5. **Key help** — a full-screen table of every control, opened with Select on
   the title screen or Select+Start in the browser; any key returns.

## Shell commands

`gbsh` implements these commands:

| Command | Description |
|---|---|
| `help` | List the commands and the shell's key bindings |
| `ls [-l] [PATH]` | List a directory (or print a file's name); `-l` shows the long form `drwxr-xr-x dir` / `-rw-r--r-- 48B file` |
| `cd [PATH]` | Change directory; `cd` with no argument goes to `/home/user` |
| `pwd` | Print the current directory path (`/ (root)` at the root) |
| `cat FILE...` | Print one or more files to the terminal |
| `echo [TEXT...]` | Print text; `echo TEXT > FILE` writes the text into a file |
| `mkdir DIR` | Create a directory |
| `rmdir DIR` | Remove an empty directory |
| `rm FILE` | Remove a file |
| `touch FILE` | Create an empty file (no-op if it already exists) |
| `clear` | Clear the terminal |
| `whoami` | Print the current user |
| `uname` | Print the system name |
| `uptime` | Print time since boot (minutes and seconds) |
| `motd` | Print the message of the day (`/etc/motd`) |
| `exit` | Leave the shell and return to the browser (same as Select+Start) |

Notes:

- Command names are case-insensitive, so `PWD` and `pwd` both work (handy when
  the on-screen keyboard's shift layer is on); paths stay case-sensitive.
- `mkdir`, `touch`, `rm`, `rmdir` and `echo >` print what they did
  (`created w`, `removed w/n`, `wrote w/n`), so a silent screen always
  means a problem, never a missed keystroke.
- The system tree shipped in ROM is immutable: `rm /etc/motd`,
  `rmdir /tmp` or `echo x > /etc/hostname` fail with
  `error: operation not permitted`. Files and directories you create are
  yours to change.
- `echo hello > file` writes `hello\n` into `file` (output redirection).
- `cat` reads both the read-only system files (from ROM) and files you created
  (from SRAM); several files can be given, and directories or missing files
  print an error.
- Every built-in has a file in `/bin` (`cat`, `cd`, `clear`, `echo`, `exit`,
  `help`, `ls`, `mkdir`, `pwd`, `rm`, `rmdir`, `sh`, `touch`, `uname`,
  `uptime`, `whoami`) holding a short man-page-style note — `cat /bin/pwd`
  explains `pwd` and how to run it. They are documentation, not separate
  programs (gbsh is a built-in shell), but you can still run them by path:
  `/bin/pwd`, `bin/echo hi` and `./pwd` all invoke the built-in named after
  the last path component, so the files in `/bin` are not just decoration.
- Paths may be absolute (`/etc/motd`) or relative (`motd`, `../etc/motd`).
  `.` and `..` components are handled.
- Unknown commands report `not found: <name>`; a one-key typo of a known
  command adds `did you mean: <name>` (e.g. `ped` → `pwd`). Failed operations
  print `error: <reason>` (no such file, file exists, no space left, name too
  long, not a directory, operation not permitted, ...).

## Filesystem design

- **ROM banks** hold the *pristine* system tree as a compact descriptor:
  a node table (name/type/parent/child/sibling, 20 bytes per inode) plus
  read-only file contents (motd, `/proc/cpuinfo`, man page, readme, a stub
  binary per shell built-in, ...).
  On first boot the descriptor is copied into SRAM.
- **SRAM (8 KB, MBC1+RAM+BATTERY)** holds the *live* state:
  - `GBUX` magic + format version header; on mismatch the tree is
    re-initialized from the ROM descriptor (fresh format).
  - Node table copy (96 inodes) + a bump-allocator heap for user file
    contents.
  - `mkdir`/`touch`/`rm`/`rmdir`/`echo x > f` mutate SRAM nodes; `cat` reads
    ROM or SRAM depending on where the file lives.
- Emulators persist the SRAM automatically:
  - **PyBoy** writes it as `gb-unix.gb.ram` next to the ROM.
  - **mGBA / SameBoy / BGB / real hardware** use `gb-unix.sav`.
  Delete that file to reset the filesystem to its pristine state.

## Building

Requires [RGBDS](https://rgbds.gbdev.io/) (`rgbasm`, `rgblink`, `rgbfix`)
and [SDCC](https://sdcc.sourceforge.net/) (`sdcc`) for the C module.

```sh
make            # builds gb-unix.gb
make clean      # remove build artifacts
```

The C sources (`src/*.c`) are compiled by SDCC to RGBDS-syntax assembly
(`--asm=rgbds --no-peep`) and assembled with `rgbasm`; C artifacts land in
`build/`. `tools/rgbds/` contains a prebuilt RGBDS used by the Makefile;
adjust `AS`/`CC`/`LD`/`FIX` in the Makefile if yours are on `$PATH`.

## Running

Open `gb-unix.gb` in any Game Boy emulator (mGBA, SameBoy, PyBoy, BGB, ...)
or flash it to hardware. Try:

1. START → browser. Move around the root tree, SELECT for the long listing.
2. A on a directory to enter it, B to go back up, A on a file to page it.
3. START → shell. Type `help` on the keyboard, START to run.
4. `mkdir demo` / `touch note` / `echo hi > note` — then power-cycle the
   emulator: your files are still there.

## Project layout

```
gb-unix/
├── Makefile            — sdcc (C) + rgbasm → rgblink → rgbfix, outputs gb-unix.gb
├── README.md
├── build/              — build artifacts (objects, generated asm)
├── tools/              — prebuilt RGBDS + genfont/genlogo/genfs generators
└── src/
    ├── main.asm        — entry point, cart header, boot, title splash, main loop
    ├── hardware.inc    — hardware register equates
    ├── font.asm        — custom 8×8 font incl. lowercase
    ├── text.asm        — print/scroll/cursor text engine (20×18 char grid)
    ├── help.asm        — full-screen key help
    ├── input.asm       — polled joypad with edge detection
    ├── fs.asm          — path resolve, tree walk, ls/cat/mkdir/rm logic
    ├── sram.asm        — SRAM enable, init/format, inode alloc, content heap
    ├── browser.asm     — browser UI
    ├── pager.asm       — file viewer
    ├── shell.asm       — tokenizer, command table, executors, tty
    ├── shcmd.c         — C: pwd/echo output (SDCC → RGBDS asm, see cwrite.asm)
    ├── cwrite.asm      — asm store/load helpers used by shcmd.c
    ├── keyboard.asm    — on-screen keyboard grid
    ├── fsdata.asm      — the filesystem content itself (motd, man pages, ...)
    └── logodata.asm    — generated splash logo tiles (tools/genlogo.py)
```

## Limitations

- 96 inodes total, 30-char command lines, 11-char file names (like classic
  Unix!), ~2 KB of user file content.
- File pager shows ASCII text; binary files render their bytes as text.
- The clock is frame-accurate only while the console is on (uptime resets on
  boot — no RTC).

## Status

Complete: boot/title, browser (short + long listing), pager, shell with
on-screen keyboard, full command set, SRAM persistence of
`mkdir`/`touch`/`rm`/`rmdir`/redirection across power cycles.
