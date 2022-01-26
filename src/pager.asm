; pager.asm — file viewer mode (full-screen text, scrollable)

include "hardware.inc"

section "pagerw", wram0

pg_node::       db
pg_top::        db              ; first visible line
pg_row::        db              ; screen row while rendering

section "pager", rom0

; pager_open:: view file a. a = node index.
pager_open::
	ld [pg_node], a
	xor a
	ld [pg_top], a
	ld a, MODE_PAGER
	ld [mode], a
	jp pager_render

pager_close::
	ld a, MODE_BROWSER
	ld [mode], a
	jp browser_render

; pager_render:: redraw the pager screen.
pager_render::
	call txt_clear
	; header: name [topline]
	xor a
	ld c, 0
	call txt_goto
	ld a, [pg_node]
	call fs_node_addr
	inc hl              ; name field (zstr, 11 bytes max)
	ld d, h
	ld e, l
	ld b, 0
	ld c, 11
.len:
	ld a, [hl+]
	or a
	jr z, .got
	inc b
	dec c
	jr nz, .len
.got:
	ld a, b
	or a
	jr z, .name_done
	ld h, d
	ld l, e
	ld c, b
	ld b, 0
	call txt_print_len
.name_done:
	ld a, ' '
	call txt_putc
	ld a, '['
	call txt_putc
	ld a, [pg_top]
	ld l, a
	ld h, 0
	call txt_print_u16
	ld a, ']'
	call txt_putc
	; body: rows 1-17
	ld a, [pg_node]
	call fs_read_open
	; skip pg_top lines
	ld a, [pg_top]
	ld b, a
.seek:
	ld a, b
	or a
	jr z, .body
	push bc
	call fread_next
	pop bc
	dec b
	jr .seek
.body:
	ld a, 1
	ld [pg_row], a
.line:
	ld a, [pg_row]
	cp 17               ; rows 1-16 only: a full line at row 17 would wrap+scroll
	jr nc, .done
	ld c, 0
	call txt_goto
	ld d, SCREEN_W      ; chars left on this line
.char:
	call fread_next
	jr nc, .done
	cp $0A
	jr z, .next_line
	cp $20
	jr c, .char         ; skip control chars
	push af
	ld a, d
	or a
	jr z, .skip         ; line longer than 20 cols: truncate
	dec d
	pop af
	call txt_putc
	jr .char
.skip:
	pop af
	jr .char
.next_line:
	ld a, [pg_row]
	inc a
	ld [pg_row], a
	jr .line
.done:
	ld a, $FF
	ld [invert_row], a
	ret

; pager_update:: handle input.
pager_update::
	ld a, [joy_pressed]
	ld a, [joy_pressed]
	and J_UP
	jp nz, .up
	ld a, [joy_pressed]
	and J_DOWN
	jp nz, .down
	ld a, [joy_pressed]
	and J_LEFT
	jp nz, .left
	ld a, [joy_pressed]
	and J_RIGHT
	jp nz, .right
	ld a, [joy_pressed]
	and J_A | J_B | J_START
	jp nz, pager_close
	ret
.up:
	ld a, [pg_top]
	or a
	ret z
	dec a
	ld [pg_top], a
	jp pager_render
.down:
	ld a, [pg_top]
	inc a
	ld [pg_top], a
	jp pager_render
.left:
	ld a, [pg_top]
	sub 8
	jr nc, .l_ok
	xor a
.l_ok:
	ld [pg_top], a
	jp pager_render
.right:
	ld a, [pg_top]
	add 8
	ld [pg_top], a
	jp pager_render
