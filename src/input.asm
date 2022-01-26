; input.asm — joypad polling with edge detection

include "hardware.inc"

section "inputw", wram0

joy_held::      db              ; bitmask: A B Sel Start R L U D (bit0..7)
joy_pressed::   db              ; newly pressed this frame
joy_released::  db              ; newly released this frame

section "input", rom0

; input_update:: poll joypad; refresh joy_held / joy_pressed.
; Called once per frame. Clobbers af, bc.
input_update::
	; read action buttons (A B Select Start) -> low nibble
	; P1 bit4=0 selects direction, bit5=0 selects action: $10 -> action
	ld a, $10
	ldh [rP1], a
	ldh a, [rP1]
	ldh a, [rP1]
	ldh a, [rP1]
	cpl
	and $0F
	ld c, a
	; read dpad -> high nibble ($20 -> direction)
	ld a, $20
	ldh [rP1], a
	ldh a, [rP1]
	ldh a, [rP1]
	ldh a, [rP1]
	cpl
	and $0F
	swap a
	or c
	ld c, a             ; c = held
	ld hl, joy_held
	ld b, [hl]          ; b = previous held
	ld [hl], c
	; pressed = held & ~previous
	ld a, b
	cpl
	and c
	ld [joy_pressed], a
	; released = previous & ~held
	ld a, c
	cpl
	and b
	ld [joy_released], a
	ret
