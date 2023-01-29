; cwrite.asm — store/load helpers used by the SDCC-compiled C module
; (src/shcmd.c).
;
; SDCC's RGBDS asm backend miscompiles several direct array stores from
; C (it drops the array base and reuses a stale register), so every WRAM
; read/write the C module performs on the asm-owned screen state goes
; through these hand-written helpers.
;
; sdcccall(1) convention: first 16-bit argument in DE, second 8-bit
; argument in A, 8-bit return value in A.

section "cwrite", rom0

; _shc_store:: *(uint8_t*)de = a
_shc_store::
	ld	[de], a
	ret

; _shc_load:: a = *(uint8_t*)de
_shc_load::
	ld	a, [de]
	ret
