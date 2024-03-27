; main.asm — gb-unix entry point, boot, title screen, main loop

include "hardware.inc"

def BGP_DEFAULT  equ $E4         ; 3-bit grayscale palette

section "vars", wram0

mode::          db              ; MODE_BROWSER / MODE_SHELL / MODE_PAGER
upt_frames::    db              ; 0..59
upt_secs::      ds 2            ; seconds since boot (u16)
boot_flags::    db              ; bit0: save was fresh
scr_full::      db              ; 1 = next VBlank does an atomic full redraw

section "header", rom0[$100]
	nop
	jp boot_start
	ds $150 - @         ; logo + header space (rgbfix writes the logo here)

section "code0", rom0[$150]

boot_start::
	di
	ld sp, $DF00
	; LCD off
	xor a
	ldh [rLCDC], a
	ld a, BGP_DEFAULT
	ldh [rBGP], a
	; font + blank tilemap
	call load_font
	call txt_init
	; sound: power on the APU for the splash jingle
	call music_init
	; battery-backed filesystem
	call sram_init
	ld [boot_flags], a
	; filesystem state
	xor a
	ld [cwd_depth], a
	; LCD on: BG on, tiles $8000, map $9800
	ld a, LCDC_ON | LCDC_TILE8000 | LCDC_BG_ON
	ldh [rLCDC], a
	call title_enter
	jp main_loop

; ---- title screen -----------------------------------------------------

title_enter::
	; txt_clear fills the buffer with spaces, marks every row dirty and sets
	; scr_full, so leaving the shell/help does one atomic full-screen redraw
	; and no shell text survives the switch back to the splash.
	call txt_clear
	xor a
	ld [scr_top], a
	ld a, SCREEN_H - 1
	ld [scr_bot], a
	; splash art: point buffer rows 1-3 at the logo tiles
	ld hl, logo_map
	ld de, screen_buf + SCREEN_W
	ld bc, LOGO_ROWS * SCREEN_W
	call mem_copy
	ld a, 6
	ld c, 1
	call txt_goto
	ld hl, title_sub
	call txt_print_z
	ld a, 8
	ld c, 0
	call txt_goto
	ld hl, title_frame
	call txt_print_z
	ld a, 9
	ld c, 0
	call txt_goto
	ld hl, title_hint1
	call txt_print_z
	ld a, 10
	ld c, 0
	call txt_goto
	ld hl, title_hint2
	call txt_print_z
	ld a, 11
	ld c, 0
	call txt_goto
	ld hl, title_hint3
	call txt_print_z
	ld a, 12
	ld c, 0
	call txt_goto
	ld hl, title_frame
	call txt_print_z
	; mount status from boot_flags bit0
	ld a, 14
	ld c, 2
	call txt_goto
	ld a, [boot_flags]
	bit 0, a
	ld hl, title_loadfs
	jr z, .p
	ld hl, title_newfs
.p:
	call txt_print_z
	ld a, 16
	ld c, 0
	call txt_goto
	ld hl, title_login
	call txt_print_z
	ld a, MODE_TITLE
	ld [mode], a
	ld a, $FF
	ld [invert_row], a
	call music_play       ; splash jingle starts here
	ret

title_update::
	call music_update     ; splash jingle only on this screen
	ld a, [joy_pressed]
	and J_SELECT
	jr z, .no_help
	call music_stop       ; leaving the splash: silence
	jp help_enter
.no_help:
	ld a, [joy_pressed]
	and J_START | J_A
	ret z
	; log in: boot the shell environment, then the browser
	call music_stop       ; leaving the splash: silence
	ld a, MODE_BROWSER
	ld [mode], a
	jp browser_enter

; ---- main loop --------------------------------------------------------

main_loop::
	call wait_vblank
	call input_update
	; uptime clock
	ld a, [upt_frames]
	inc a
	ld [upt_frames], a
	cp 60
	jr c, .clocked
	xor a
	ld [upt_frames], a
	ld a, [upt_secs]
	inc a
	ld [upt_secs], a
	jr nz, .clocked
	ld a, [upt_secs+1]
	inc a
	ld [upt_secs+1], a
.clocked:
	; mode dispatch
	ld a, [mode]
	cp MODE_BROWSER
	jr z, .browser
	cp MODE_SHELL
	jr z, .shell
	cp MODE_PAGER
	jr z, .pager
	cp MODE_TITLE
	jr z, .title
	cp MODE_HELP
	jr z, .help
	cp MODE_EDITOR
	jr z, .editor
	jr main_loop
.browser:
	call browser_update
	jr main_loop
.shell:
	call shell_update
	jr main_loop
.pager:
	call pager_update
	jr main_loop
.title:
	call title_update
	jr main_loop
.help:
	call help_update
	jr main_loop
.editor:
	call editor_update
	jr main_loop

; wait_vblank:: busy-wait for VBlank; blit dirty rows; wait for frame end.
wait_vblank::
	ldh a, [rLY]
	cp 144
	jr c, wait_vblank    ; wait until VBlank starts
	ld a, [scr_full]
	and a
	jr z, .partial
	xor a
	ld [scr_full], a
	call blit_full       ; screen switch: redraw everything, no tearing
	jr .wd
.partial:
	call blit            ; ~2000 cycles worst case, fits in VBlank
.wd:
	ldh a, [rLY]
	cp 144
	jr nc, .wd           ; wait until VBlank ends
	ret

title_sub:     db "a tiny unix for GB", 0
title_frame:   db "+------------------+", 0
title_hint1:   db "|   START login    |", 0
title_hint2:   db "|then START = gbsh |", 0
title_hint3:   db "|   SELECT help    |", 0
title_newfs:   db "fs: save created", 0
title_loadfs:  db "fs: save loaded", 0
title_login:   db "press START to login", 0
