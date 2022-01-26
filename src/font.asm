; font.asm — expand 1bpp fontdata to 2bpp tiles in VRAM
; Tile n = ASCII charcode n + $20 (tile 0 = space).
; Two copies: normal tiles 0-94 at $8000, inverted tiles 95-189 at $85F0.
; The inverted copy is used for cursor/selection highlight.

include "hardware.inc"

def INVERT_BYTES equ 95 * 16 ; bytes: $85F0

section "font", rom0

; load_font:: upload normal + inverted copies of the font to VRAM.
; LCD must be off. Clobbers af, bc, de, hl.
load_font::
	ld hl, fontdata
	ld de, $8000          ; normal tiles
	ld bc, $8000 + INVERT_BYTES ; inverted tiles
	ld a, 95              ; tile count
.tile:
	push af
	REPT 8
	ld a, [hl+]
	ld [de], a            ; low byte
	inc de
	ld [de], a            ; high byte
	inc de
	cpl
	ld [bc], a            ; inverted low byte
	inc bc
	ld [bc], a            ; inverted high byte
	inc bc
	ENDR
	pop af
	dec a
	jr nz, .tile
	; splash logo tiles at LOGO_TILE_BASE (1bpp expanded like the font)
	ld hl, logotiles
	ld de, $8000 + LOGO_TILE_BASE * 16
	ld b, LOGO_TILES
.logo:
	REPT 8
	ld a, [hl+]
	ld [de], a
	inc de
	ld [de], a
	inc de
	ENDR
	dec b
	jr nz, .logo
	ret
