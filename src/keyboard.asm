; keyboard.asm — on-screen keyboard for shell input
;
; 6 rows x 10 keys on screen rows 12-17, one key every 2 columns.
; Select toggles the shift layer (applies to rows 0-3).
; The cursor key is drawn with an inverted tile (tile index + 95).

include "hardware.inc"

section "shellw", wram0

kb_row::        db              ; 0..5
kb_col::        db              ; 0..9
shift_on::      db

section "keyboard", rom0

; kb_char:: char of key (b = row, c = col). Preserves b, c, de.
kb_char::
	ld a, [shift_on]
	or a
	jr z, .plain
	ld a, b
	cp 4
	jr nc, .plain
	ld a, b
	add a, a            ; x2
	ld e, a
	add a, a            ; x4
	add a, a            ; x8
	add a, e            ; x10
	add a, c
	ld e, a
	ld d, 0
	ld hl, kb_shift
	add hl, de
	ld a, [hl]
	ret
.plain:
	ld a, b
	add a, a
	ld e, a
	add a, a
	add a, a
	add a, e            ; x10
	add a, c
	ld e, a
	ld d, 0
	ld hl, kb_layout
	add hl, de
	ld a, [hl]
	ret

; kb_cell_addr:: hl = &screen_buf cell of cursor key; marks row dirty.
; Preserves a, bc, de.
kb_cell_addr::
	push af
	push bc
	push de
	ld a, [kb_row]
	add KB_SCREEN_TOP
	ld l, a
	ld h, 0
	add hl, hl
	ld e, l
	ld d, h
	add hl, hl
	add hl, hl
	add hl, de          ; x10
	add hl, hl          ; x20
	ld bc, screen_buf
	add hl, bc
	; + col*2
	ld a, [kb_col]
	add a, a
	ld e, a
	ld d, 0
	add hl, de
	; mark row dirty
	push hl
	ld a, [kb_row]
	add KB_SCREEN_TOP
	ld e, a
	ld d, 0
	ld hl, dirty_rows
	add hl, de
	ld [hl], 1
	pop hl
	pop de
	pop bc
	pop af
	ret

; kb_clear_cell:: draw cursor key cell as normal char.
kb_clear_cell::
	call kb_cell_addr
	push hl
	ld a, [kb_row]
	ld b, a
	ld a, [kb_col]
	ld c, a
	call kb_char
	pop hl
	sub $20
	ld [hl], a
	ret

; kb_draw_cell:: draw cursor key cell as inverted tile.
kb_draw_cell::
	call kb_cell_addr
	push hl
	ld a, [kb_row]
	ld b, a
	ld a, [kb_col]
	ld c, a
	call kb_char
	pop hl
	sub $20
	add 95
	ld [hl], a
	ret

; kb_reset:: cursor to top-left key.
kb_reset::
	xor a
	ld [kb_row], a
	ld [kb_col], a
	ld [shift_on], a
	ret

; shell_render_kb:: draw all 6 keyboard rows.
shell_render_kb::
	ld b, 0             ; kb row
.krow:
	push bc
	ld a, b
	add KB_SCREEN_TOP
	ld c, 0
	call txt_goto
	pop bc
	ld c, 0             ; key col
.kcol:
	push bc
	call kb_char        ; a = char
	ld e, a
	ld a, b
	add KB_SCREEN_TOP   ; screen row
	sla c               ; screen col = col*2
	call txt_goto
	ld a, e
	call txt_putc
	pop bc
	inc c
	ld a, c
	cp KB_COLS
	jr c, .kcol
	inc b
	ld a, b
	cp KB_ROWS
	jr c, .krow
	call kb_draw_cell
	ld a, 1
	ld [scr_full], a    ; shift layer changes 6 rows: redraw atomically
	ret

kb_layout:
	db "1234567890"
	db "qwertyuiop"
	db "asdfghjkl-"
	db "zxcvbnm./,"
	db "&$#", "'", $22, "^~!=+"
	db "?*:;|()", $5C, "`", " "

kb_shift:
	db "!@#$%^&*()"
	db "QWERTYUIOP"
	db "ASDFGHJKL_"
	db "ZXCVBNM<>?"
