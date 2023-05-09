; music.asm — splash-screen chiptune: pulse melody + bass + noise hat.
;
; Frame-driven step sequencer: one step every MUSIC_STEP frames (~112 BPM
; eighths at 60 fps), one byte per step per channel:
;   0    = rest
;   1..N = note index into freq_table
;   $FF  = end of song (loop back to the start)
; The music plays only on the splash screen: music_play on title_enter,
; music_update once per frame from title_update, music_stop when leaving.

include "hardware.inc"

def MUSIC_STEP    equ 8            ; frames per step (~112 BPM eighths)

section "musicw", wram0

mus_tick::        db               ; frames into the current step
mus_ptr1::        db               ; offset into song_mel
mus_ptr2::        db               ; offset into song_bass
mus_ptr4::        db               ; offset into song_hat
mus_on::          db               ; 0 = sequencer silent

section "music", rom0

; music_init:: power on the APU and route the channels. Call once at boot;
; the first note trigger happens well after the 8192-cycle power-on delay.
music_init::
	ld a, $80
	ldh [rNR52], a        ; sound power on
	xor a
	ldh [rNR10], a
	ldh [rNR11], a
	ldh [rNR12], a
	ldh [rNR21], a
	ldh [rNR22], a
	ldh [rNR41], a
	ldh [rNR42], a
	ldh [rNR43], a
	ld a, $77
	ldh [rNR50], a        ; both terminals, max volume
	ld a, $BB
	ldh [rNR51], a        ; ch1/ch2/ch4 to both terminals
	ret

; music_play:: start the splash song from the beginning.
music_play::
	xor a
	ld [mus_tick], a
	ld [mus_ptr1], a
	ld [mus_ptr2], a
	ld [mus_ptr4], a
	ld a, 1
	ld [mus_on], a
	ret

; music_stop:: silence every channel and halt the sequencer.
music_stop::
	xor a
	ld [mus_on], a
	ldh [rNR12], a        ; ch1 envelope 0 = silent
	ldh [rNR22], a        ; ch2
	ldh [rNR42], a        ; ch4
	ret

; music_update:: advance the sequencer; call once per frame on the splash.
music_update::
	ld a, [mus_on]
	or a
	ret z
	ld a, [mus_tick]
	inc a
	ld [mus_tick], a
	cp MUSIC_STEP
	ret c                 ; not a step boundary yet
	xor a
	ld [mus_tick], a
	call mu_ch1
	call mu_ch2
	call mu_ch4
	ret

; ---- per-step channel updates -----------------------------------------

; ch1: pulse melody, duty 50%, pluck envelope.
mu_ch1:
	ld hl, song_mel
	ld a, [mus_ptr1]
	ld e, a
	ld d, 0
	add hl, de
	ld a, [hl]
	cp $FF
	jr nz, .have          ; end of song: wrap to the start
	xor a
	ld [mus_ptr1], a
	ld e, a
	ld d, 0
	ld hl, song_mel
	add hl, de
	ld a, [hl]
.have:
	ld b, a               ; b = note byte
	ld a, [mus_ptr1]
	inc a
	ld [mus_ptr1], a      ; next step
	ld a, b
	or a
	ret z                 ; rest: leave ch1 silent
	ld e, a
	ld d, 0
	ld hl, freq_table
	add hl, de
	add hl, de            ; 2 bytes per note (lo, hi)
	ld a, [hl+]
	ld c, a
	ld a, [hl]
	ld b, a               ; bc = frequency
	ld a, $80
	ldh [rNR11], a        ; duty 50%, no length
	ld a, $B2
	ldh [rNR12], a        ; volume 11, decay, step 2 (pluck)
	ld a, c
	ldh [rNR13], a
	ld a, b
	or $80
	ldh [rNR14], a        ; trigger
	ret

; ch2: pulse bass, duty 25%, softer envelope.
mu_ch2:
	ld hl, song_bass
	ld a, [mus_ptr2]
	ld e, a
	ld d, 0
	add hl, de
	ld a, [hl]
	cp $FF
	jr nz, .have
	xor a
	ld [mus_ptr2], a
	ld e, a
	ld d, 0
	ld hl, song_bass
	add hl, de
	ld a, [hl]
.have:
	ld b, a
	ld a, [mus_ptr2]
	inc a
	ld [mus_ptr2], a
	ld a, b
	or a
	ret z
	ld e, a
	ld d, 0
	ld hl, freq_table
	add hl, de
	add hl, de
	ld a, [hl+]
	ld c, a
	ld a, [hl]
	ld b, a
	ld a, $40
	ldh [rNR21], a        ; duty 25%
	ld a, $83
	ldh [rNR22], a        ; volume 8, decay, step 3
	ld a, c
	ldh [rNR23], a
	ld a, b
	or $80
	ldh [rNR24], a        ; trigger
	ret

; ch4: noise hat, short decay. 0 = keep silent (envelope already decayed).
mu_ch4:
	ld hl, song_hat
	ld a, [mus_ptr4]
	ld e, a
	ld d, 0
	add hl, de
	ld a, [hl]
	cp $FF
	jr nz, .have
	xor a
	ld [mus_ptr4], a
	ld e, a
	ld d, 0
	ld hl, song_hat
	add hl, de
	ld a, [hl]
.have:
	ld b, a
	ld a, [mus_ptr4]
	inc a
	ld [mus_ptr4], a
	ld a, b
	or a
	ret z
	ld a, $41
	ldh [rNR42], a        ; volume 4, decay, step 1 (tick)
	ld a, $30
	ldh [rNR43], a        ; ~4 kHz hiss
	ld a, $80
	ldh [rNR44], a        ; trigger
	ret

; ---- song data ---------------------------------------------------------

; frequency table: code N -> freq_table[N*2] = NR13 lo, [N*2+1] = NR14 hi.
; code 0 is unused (rests are handled before the lookup).
freq_table:
	db $16, $04           ; 1  C3  1046
	db $84, $04           ; 2  D3  1156
	db $E5, $04           ; 3  E3  1253
	db $11, $05           ; 4  F3  1297
	db $63, $05           ; 5  G3  1379
	db $AC, $05           ; 6  A3  1452
	db $ED, $05           ; 7  B3  1517
	db $0B, $06           ; 8  C4  1547
	db $42, $06           ; 9  D4  1602
	db $72, $06           ; 10 E4  1650
	db $89, $06           ; 11 F4  1673
	db $B2, $06           ; 12 G4  1714
	db $D6, $06           ; 13 A4  1750
	db $F7, $06           ; 14 B4  1783
	db $06, $07           ; 15 C5  1798
	db $21, $07           ; 16 D5  1825
	db $39, $07           ; 17 E5  1849
	db $44, $07           ; 18 F5  1860
	db $59, $07           ; 19 G5  1881
	db $6B, $07           ; 20 A5  1899
	db $7B, $07           ; 21 B5  1915
	db $83, $07           ; 22 C6  1923

; melody: 4 bars of 8 eighth-notes, C / Am / F / G arpeggios.
song_mel:
	db 17, 19, 22, 19, 17, 19, 22, 19    ; E5 G5 C6 G5 ...   (C)
	db 15, 17, 20, 17, 15, 17, 20, 17    ; C5 E5 A5 E5 ...   (Am)
	db 13, 15, 18, 15, 13, 15, 18, 15    ; A4 C5 F5 C5 ...   (F)
	db 14, 16, 19, 16, 14, 16, 19, 16    ; B4 D5 G5 D5 ...   (G)
	db $FF                               ; loop

; bass: root notes on the beat (quarter notes = every other step).
song_bass:
	db 1, 0, 5, 0, 1, 0, 5, 0            ; C3 . G3 . ...     (C)
	db 6, 0, 3, 0, 6, 0, 3, 0            ; A3 . E3 . ...     (Am)
	db 4, 0, 1, 0, 4, 0, 1, 0            ; F3 . C3 . ...     (F)
	db 5, 0, 2, 0, 5, 0, 2, 0            ; G3 . D3 . ...     (G)
	db $FF                               ; loop

; hat: tick on the off-beats (steps 3 and 7 of each bar).
song_hat:
	db 0, 0, 1, 0, 0, 0, 1, 0
	db 0, 0, 1, 0, 0, 0, 1, 0
	db 0, 0, 1, 0, 0, 0, 1, 0
	db 0, 0, 1, 0, 0, 0, 1, 0
	db $FF                               ; loop
