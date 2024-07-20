; help.asm — scrollable full-screen key help.
; Opened with SELECT on the title screen, or SELECT+START in the browser.
; UP/DOWN scroll one line, LEFT/RIGHT page, A/B/START return.

include "hardware.inc"

def HELP_VIEW_ROWS equ SCREEN_H - 1  ; bottom row is the footer

section "helpw", wram0

help_prev::     db              ; mode to return to
help_top::      db              ; first visible help line

section "help", rom0

help_lines:
	dw help_l00, help_l01, help_l02, help_l03
	dw help_l04, help_l05, help_l06, help_l07
	dw help_l08, help_l09, help_l10, help_l11
	dw help_l12, help_l13, help_l14, help_l15
	dw help_l16, help_l17, help_l18, help_l19
	dw help_l20, help_l21, help_l22, help_l23
	dw help_l24, help_l25, help_l26, help_l27
	dw help_l28, help_l29, help_l30, help_l31
	dw help_l32, help_l33, help_l34, help_l35
	dw help_l36
help_lines_end:
def HELP_COUNT equ (help_lines_end - help_lines) / 2

help_enter::
	ld a, [mode]
	ld [help_prev], a
	xor a
	ld [help_top], a
	; fallthrough

; help_render:: draw the current page plus the footer.
help_render::
	call txt_clear
	xor a
	ld [scr_top], a
	ld a, SCREEN_H - 1
	ld [scr_bot], a
	ld a, $FF
	ld [invert_row], a
	; hl = help_lines + help_top * 2
	ld a, [help_top]
	ld hl, help_lines
	or a
	jr z, .render
.skip:
	inc hl
	inc hl
	dec a
	jr nz, .skip
.render:
	ld c, 0             ; c = screen row
.row:
	ld a, c
	cp HELP_VIEW_ROWS
	jr nc, .footer
	ld a, [hl+]         ; line pointer low
	ld e, a
	ld a, [hl+]         ; line pointer high
	ld d, a
	or e
	jr z, .footer       ; defensive: end of table
	push hl
	push bc
	ld a, c
	ld c, 0
	call txt_goto
	ld h, d
	ld l, e
	call txt_print_z
	pop bc
	pop hl
	inc c
	jr .row
.footer:
	ld a, SCREEN_H - 1
	ld c, 0
	call txt_goto
	ld hl, help_footer
	call txt_print_z
	ld a, MODE_HELP
	ld [mode], a
	ret

help_update::
	ld a, [joy_pressed]
	and J_UP
	jr z, .down
	ld a, [help_top]
	or a
	ret z
	dec a
	ld [help_top], a
	jp help_render
.down:
	ld a, [joy_pressed]
	and J_DOWN
	jr z, .left
	ld a, [help_top]
	cp HELP_COUNT - HELP_VIEW_ROWS
	ret nc
	inc a
	ld [help_top], a
	jp help_render
.left:
	ld a, [joy_pressed]
	and J_LEFT
	jr z, .right
	ld a, [help_top]
	sub HELP_VIEW_ROWS
	jr nc, .left_ok
	xor a
.left_ok:
	ld [help_top], a
	jp help_render
.right:
	ld a, [joy_pressed]
	and J_RIGHT
	jr z, .close
	ld a, [help_top]
	add HELP_VIEW_ROWS
	cp HELP_COUNT - HELP_VIEW_ROWS
	jr c, .right_ok
	ld a, HELP_COUNT - HELP_VIEW_ROWS
.right_ok:
	ld [help_top], a
	jp help_render
.close:
	ld a, [joy_pressed]
	and J_A | J_B | J_START
	ret z
	ld a, [help_prev]
	cp MODE_TITLE
	jr z, .to_title
	ld a, MODE_BROWSER
	ld [mode], a
	jp browser_render
.to_title:
	ld a, MODE_TITLE
	ld [mode], a
	jp title_enter

help_l00: db "      GB-UNIX KEYS", 0
help_l01: db "TITLE", 0
help_l02: db " START/A login", 0
help_l03: db " SELECT help", 0
help_l04: db "BROWSER", 0
help_l05: db " UP/DOWN  select", 0
help_l06: db " LEFT/RIGHT page", 0
help_l07: db " A enter  B parent", 0
help_l08: db " B+UP/DN root/home", 0
help_l09: db " SELECT long list", 0
help_l10: db " START shell", 0
help_l11: db " SELECT+START help", 0
help_l12: db "PAGER", 0
help_l13: db " UP/DOWN scroll", 0
help_l14: db " LEFT/RIGHT page", 0
help_l15: db " A/B/START close", 0
help_l16: db "SHELL", 0
help_l17: db " D-PAD pick  A type", 0
help_l18: db " B delete  START run", 0
help_l19: db " SELECT shift layer", 0
help_l20: db " SEL+UP/DN history", 0
help_l21: db " SEL+START browser", 0
help_l22: db " exit logs out", 0
help_l23: db "GBEDIT", 0
help_l24: db " D-PAD pick  A type", 0
help_l25: db " A insert  B delete", 0
help_l26: db " B+D-PAD move text", 0
help_l27: db " B+A insert newline", 0
help_l28: db " SELECT shift layer", 0
help_l29: db " START save and quit", 0
help_l30: db " SEL+START discard", 0
help_l31: db "TOP", 0
help_l32: db " A/B/START shell", 0
help_l33: db "HELP", 0
help_l34: db " UP/DOWN scroll", 0
help_l35: db " LEFT/RIGHT page", 0
help_l36: db " A/B/START close", 0
help_footer: db "UP/DN scroll A back", 0
