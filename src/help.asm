; help.asm — full-screen key help.
; Opened with SELECT on the title screen, or SELECT+START in the browser.
; Any key returns to the screen you came from.

include "hardware.inc"

section "helpw", wram0

help_prev::     db              ; mode to return to

section "help", rom0

; help_row row, col, zstring
MACRO help_row
	ld a, \1
	ld c, \2
	call txt_goto
	ld hl, \3
	call txt_print_z
ENDM

help_enter::
	ld a, [mode]
	ld [help_prev], a
	call txt_clear
	xor a
	ld [scr_top], a
	ld a, SCREEN_H - 1
	ld [scr_bot], a
	ld a, $FF
	ld [invert_row], a

	help_row 0,  8, help_l0
	help_row 1,  0, help_l1
	help_row 2,  0, help_l2
	help_row 3,  0, help_l3
	help_row 4,  0, help_l4
	help_row 5,  0, help_l5
	help_row 6,  0, help_l6
	help_row 7,  0, help_l7
	help_row 8,  0, help_l8
	help_row 9,  0, help_l9
	help_row 10, 0, help_l10
	help_row 11, 0, help_l11
	help_row 12, 0, help_l12
	help_row 13, 0, help_l13
	help_row 14, 0, help_l14
	help_row 15, 0, help_l15
	help_row 16, 0, help_l16
	help_row 17, 0, help_l17

	ld a, MODE_HELP
	ld [mode], a
	ret

help_update::
	ld a, [joy_pressed]
	or a
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

help_l0:  db "KEYS", 0
help_l1:  db "BROWSER", 0
help_l2:  db " UP/DOWN  select", 0
help_l3:  db " LEFT/RIGHT page", 0
help_l4:  db " A enter B parent", 0
help_l5:  db " B+UP / B+DOWN home", 0
help_l6:  db " SELECT long list", 0
help_l7:  db " START shell", 0
help_l8:  db " SELECT+START help", 0
help_l9:  db "PAGER", 0
help_l10: db " UP/DOWN scroll", 0
help_l11: db " LEFT/RIGHT page", 0
help_l12: db " A/B/START close", 0
help_l13: db "SHELL", 0
help_l14: db " dpad move  A type", 0
help_l15: db " B delete  START run", 0
help_l16: db " SELECT shift layer", 0
help_l17: db " SELECT+START back", 0
