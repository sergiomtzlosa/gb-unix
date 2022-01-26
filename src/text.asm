; text.asm — text engine: 20x18 screen buffer, printing, scrolling, VRAM blit
;
; The screen buffer holds TILE INDICES (charcode - $20), so the blit is a
; plain copy. Blit only copies rows marked dirty (up to BLIT_BUDGET rows per
; frame) so VRAM writes always fit inside VBlank. Cursor highlight works by
; copying the highlight row from the inverted font copy (+INVERT_BASE).

include "hardware.inc"

section "textw", wram0
screen_buf::    ds SCREEN_W * SCREEN_H
dirty_rows::    ds SCREEN_H     ; nonzero = row needs re-blit
cur_col::       db
cur_row::       db
scr_top::       db              ; scroll region (shell uses 0..TERM_BOT)
scr_bot::       db
invert_row::    db              ; row to draw highlighted, $FF = none

section "text", rom0

; ---- helpers ----------------------------------------------------------

; txt_row_addr:: hl = &screen_buf[a * 20]. Preserves a, bc, de.
txt_row_addr::
	push bc
	push de
	ld l, a
	ld h, 0
	add hl, hl
	ld e, l
	ld d, h
	add hl, hl
	add hl, hl
	add hl, de          ; x8 + x2 = x10
	add hl, hl          ; x20
	ld bc, screen_buf
	add hl, bc
	pop de
	pop bc
	ret

; mem_fill_a:: fill bc bytes at hl with a. Clobbers af, bc, de, hl.
mem_fill_a::
	ld e, a             ; keep fill value out of the loop's clobbers
.loop:
	ld a, e
	ld [hl], a
	inc hl
	dec bc
	ld a, b
	or c
	jr nz, .loop
	ret

; mem_copy:: copy bc bytes hl -> de. Clobbers a, bc, hl. bc = 0 copies nothing.
mem_copy::
	ld a, b
	or c
	ret z
.loop:
	ld a, [hl+]
	ld [de], a
	inc de
	dec bc
	ld a, b
	or c
	jr nz, .loop
	ret

; ---- init -------------------------------------------------------------

txt_init::
	xor a
	ld [cur_col], a
	ld [cur_row], a
	ld [scr_top], a
	ld a, SCREEN_H - 1
	ld [scr_bot], a
	ld a, $FF
	ld [invert_row], a
	; whole buffer to space (tile 0), all rows dirty
	ld hl, screen_buf
	ld bc, SCREEN_W * SCREEN_H
	xor a
	call mem_fill_a
	ld hl, dirty_rows
	ld bc, SCREEN_H
	ld a, 1
	call mem_fill_a
	; clear full BG tilemap so off-screen area is blank too
	ld hl, $9800
	ld bc, 32 * 32
	xor a
	call mem_fill_a
	ret

; ---- printing ---------------------------------------------------------

; txt_goto:: a = row, c = col. Clobbers a.
txt_goto::
	ld [cur_row], a
	ld a, c
	ld [cur_col], a
	ret

; txt_putc:: print char a at cursor; wraps; scrolls within region.
; Preserves hl, bc, de. Clobbers af.
txt_putc::
	push hl
	push bc
	cp $0A
	jr z, .nl
	cp $20
	jr nc, .range
	ld a, '.'           ; map control bytes to '.'
	jr .have
.range:
	cp $7F
	jr c, .have
	ld a, '.'
.have:
	ld c, a
	; resolve a pending wrap from the previous full line first
	ld a, [cur_col]
	cp SCREEN_W
	jr c, .nowrap
	push bc
	call txt_newline
	pop bc
.nowrap:
	push de
	ld a, [cur_row]
	call txt_row_addr
	ld a, [cur_col]
	ld e, a
	ld d, 0
	add hl, de
	ld a, c
	sub $20             ; charcode -> tile index
	ld [hl], a
	; mark row dirty
	push hl
	ld a, [cur_row]
	ld e, a
	ld d, 0
	ld hl, dirty_rows
	add hl, de
	ld [hl], 1
	pop hl
	pop de
	; advance (col 20 = pending wrap; the next char or newline resolves it)
	ld a, [cur_col]
	inc a
	ld [cur_col], a
	pop bc
	pop hl
	ret
.nl:
	pop bc
	pop hl
	jp txt_newline

; txt_newline:: CR/LF; scrolls region when passing scr_bot.
txt_newline::
	xor a
	ld [cur_col], a
	ld a, [cur_row]
	inc a
	ld hl, scr_bot
	cp [hl]
	jr c, .store        ; still inside region
	jr z, .store        ; row scr_bot itself is valid: no scroll
	call txt_scroll
	ld a, [scr_bot]
.store:
	ld [cur_row], a
	ret

; txt_scroll:: scroll region up one line.
txt_scroll::
	push af
	push bc
	push de
	push hl
	ld a, [scr_top]
	inc a
	ld c, a             ; src row
.row_loop:
	ld a, [scr_bot]
	cp c
	jr c, .done
	push bc
	ld a, c
	call txt_row_addr   ; hl = &row c (source)
	push hl
	ld bc, -SCREEN_W
	add hl, bc          ; hl = &row c-1 (dest)
	ld e, l
	ld d, h
	pop hl              ; hl = source, de = dest
	ld bc, SCREEN_W
	call mem_copy       ; copy row c -> row c-1 (scroll up)
	pop bc
	inc c
	jr .row_loop
.done:
	ld a, [scr_bot]
	call txt_row_addr
	ld bc, SCREEN_W
	xor a
	call mem_fill_a
	; dirty: whole region
	ld a, [scr_top]
	ld c, a
.mdirty:
	ld a, [scr_bot]
	cp c
	jr c, .end
	push bc
	ld e, c
	ld d, 0
	ld hl, dirty_rows
	add hl, de
	ld [hl], 1
	pop bc
	inc c
	jr .mdirty
.end:
	pop hl
	pop de
	pop bc
	pop af
	ret

; txt_print_z:: print NUL-terminated string at hl.
txt_print_z::
	ld a, [hl+]
	or a
	ret z
	push hl             ; protect string ptr (txt_putc may wrap->newline)
	call txt_putc
	pop hl
	jr txt_print_z

; txt_print_len:: print bc chars from hl.
txt_print_len::
	ld a, [hl+]
	push hl             ; protect string ptr (txt_putc may wrap->newline)
	call txt_putc
	pop hl
	dec bc
	ld a, b
	or c
	jr nz, txt_print_len
	ret

; div_hl_c:: hl /= c (c > 0). out: hl = quotient, a = remainder.
div_hl_c::
	push bc            ; preserve caller's b (used as digit count by callers)
	ld b, 16
	xor a               ; remainder
.loop:
	add hl, hl          ; shift MSB into carry
	rla                 ; remainder = remainder*2 | carry
	cp c
	jr c, .next
	sub c
	inc hl              ; set quotient bit
.next:
	dec b
	jr nz, .loop
	pop bc
	ret

; txt_print_u16:: print hl as decimal (no leading zeros) at cursor.
txt_print_u16::
	ld b, 0             ; digit count
.loop:
	ld c, 10
	call div_hl_c
	push af             ; remainder digit
	inc b
	ld a, h
	or l
	jr nz, .loop
.print:
	pop af
	add '0'
	call txt_putc
	dec b
	jr nz, .print
	ret

; strlen_hl:: b = length of zstr at hl.
strlen_hl::
	ld b, 0
.loop:
	ld a, [hl+]
	or a
	ret z
	inc b
	jr .loop

; txt_clear_row:: fill row a with spaces and mark it dirty. Preserves a, bc.
txt_clear_row::
	push de
	call txt_row_addr
	ld c, a             ; save row
	ld b, SCREEN_W
	xor a
.loop:
	ld [hl+], a
	dec b
	jr nz, .loop
	pop de
	; mark dirty
	ld e, c
	ld d, 0
	ld hl, dirty_rows
	add hl, de
	ld [hl], 1
	ret

; txt_clear:: fill whole screen buffer with spaces; cursor to scr_top.
txt_clear::
	ld hl, screen_buf
	ld bc, SCREEN_W * SCREEN_H
	ld a, ' '
	sub $20
	call mem_fill_a
	ld hl, dirty_rows
	ld bc, SCREEN_H
	ld a, 1
	call mem_fill_a
	xor a
	ld [cur_col], a
	ld a, [scr_top]
	ld [cur_row], a
	ld a, 1
	ld [scr_full], a     ; full redraw: switch screens in one piece
	ret

; ---- blit -------------------------------------------------------------

; blit:: copy dirty rows from screen_buf to $9800 (call during VBlank).
; Highlight row comes from the inverted font copy. Clobbers af, bc, de, hl.
blit::
	ld b, BLIT_BUDGET   ; b = rows still affordable this frame
blit_rows::
	xor a
	ld c, a             ; c = row index
	ld de, dirty_rows   ; de = &dirty_rows[c]
.row_loop:
	ld a, c
	cp SCREEN_H
	jp nc, .done
	ld h, d
	ld l, e             ; hl = &dirty_rows[c]
	inc de              ; advance dirty pointer for next row
	ld a, [hl]
	or a
	jp z, .next         ; row clean
	ld a, b
	or a
	jp z, .done         ; out of budget: leave flag set for next frame
	dec b
	xor a
	ld [hl], a          ; clear dirty flag
	push de             ; keep &dirty_rows[c+1] (de is reused as dest)
	; dest = $9800 + c*32
	push bc
	ld a, c
	ld l, a
	ld h, 0
	REPT 5
	add hl, hl          ; x32
	ENDR
	ld de, $9800
	add hl, de
	pop bc
	push hl
	pop de              ; de = dest tilemap row
	; source row
	ld a, c
	call txt_row_addr   ; hl = src (20 bytes)
	; highlight?
	push bc
	ld a, [invert_row]
	ld b, a
	ld a, c
	cp b
	pop bc
	jr z, .hlrow
	REPT 20
	ld a, [hl+]
	ld [de], a
	inc de
	ENDR
	jr .next_row
.hlrow:
	REPT 20
	ld a, [hl+]
	add INVERT_BASE
	ld [de], a
	inc de
	ENDR
.next_row:
	pop de              ; restore dirty-rows pointer
.next:
	inc c
	jp .row_loop
.done:
	ret

; blit_full:: redraw every dirty row with the LCD off, then switch the LCD
; back on. Used when scr_full is set (full-screen or multi-row redraws) so
; the new screen appears in one piece instead of wiping in over the old one.
blit_full::
	ldh a, [rLCDC]
	res 7, a
	ldh [rLCDC], a
	ld b, SCREEN_H
	call blit_rows
	ldh a, [rLCDC]
	set 7, a
	ldh [rLCDC], a
	ret
