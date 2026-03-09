	org $BFF0
	db "NES", $1A
	db $1
	db $1
	db %00000000
	db %00000000
	db 0
	db 0,0,0,0,0,0,0


; labels/variables
button_array equ $00 			; Storage of buttons being pressed.
player_x equ $01 				; x-position of player sprite
player_y equ $02 				; y-position of player sprite
player_inner_x equ $03			; x-position within one tile
player_inner_y equ $04			; y-position within one tile
player_abs_x equ $05
player_abs_y equ $06
dx equ $07 						; delta x (movement)
dy equ $08 						; delta y (movement)

clock_cycle equ $09 			; These two labels are for delaying/slowing down
clock_cycle_end equ $0A			; movement


nmi_flags equ $F0 				; keeping track of whether waiting/ready (1 yes, 0 no):
								; -----LVN (L-Logic, V-video, N-NMI)

collision_flags equ $F1 		; Flags for collisions: ULRD???? (up, left, right, down, last four for damage :D )
start_collision_low equ $F2		; Storage for LSB for collision logic (player_abs_y - 1)
start_collision_high equ $F3 	; MSB for collision logic (player_abs_y - 1)


;; REGISTERS ;;
z3 equ $FD
z2 equ $FE
z equ $FF 						; "z" register (for those times when x and y aren't enough abc's)


; nmi/irq/reset


nmi:
	pha
		php
			txa
			pha
			tya
			pha

	; 1) check nmi was completed
	lda nmi_flags
	and #1 			; check bit 1, did nmi finish?
	bne finish_nmi  ; if it didn't, get to the end pls

	; we're in an NMI, turn the bit on:
	lda nmi_flags
	ora #1
	sta nmi_flags

	jsr check_bg_collision_in_nmi

	; 2) for now I'm not sure we need to 
	; use gfx flag - we're only updating sprites?

gfx_update:
	lda #$02
	sta $4014
	lda nmi_flags
	and #%11111101 			;We're turning bit 1 off ("2")
	sta nmi_flags
	

finish_nmi:
	inc clock_cycle
	cmp clock_cycle_end
	bne continue_after_cycle_check
	lda #0
	sta clock_cycle
continue_after_cycle_check:
	;TODO: theoretically other stuff would happen here...

	lda nmi_flags
	and #$FE  		; turn off bit 1 - we've now "completed" previous NMI
	sta nmi_flags

			pla
			tay
			pla
			tax
		plp
	pla
	rti

; Subroutine for checking collisions against BG
check_bg_collision_in_nmi:
	
	;;; TODO NUXT: The ONLY thing in NMI should be to check the values of the 8-blocks
	;;; and to store that in a flag then use that flag OUTSIDE Of NMI (game loop) to 
	;;; check collision (minimizes NMI code!!!)

	; 4 Cases:
	; 1) player_inner_x and player_inner_y are both non-zero:
	; For both to be non-zero, the sprite is currently "occupying"
	; all adjacent tiles, so collisions are not possible
	; 2) Only player_inner_x is non-zero:
	; In this case we need only check UD collisions (four tiles in 
	; total, since sprite is "in-between tiles" horizontally)
	; 3) Only player_inner_y is non-zero:
	; Similar to 2), but checking LR collisions (four tiles total)
	; 4) player_inner_x and player_inner_y are both zero:
	; The four collisions we check are exactly one tile each
	; direction (ULDR)
check_bg_collision_upper:
	jsr check_bg_collision_update_2006_lda_2007
	lda #%10000000
	;;; TODO NUXT: also, don't forget the "skip because of innerx/y" logic (not currently here)
	jsr check_bg_collision_chk_flag


check_bg_collision_upper_inner_x:
	lda #1
	sta z3
	jsr check_bg_collision_add_to_find_next_spot
	
	lda player_inner_x
	beq check_bg_collision_left
	lda #%10000000
	jsr check_bg_collision_chk_flag


check_bg_collision_left:

	lda #30
	sta z3
	jsr check_bg_collision_add_to_find_next_spot
	lda #%01000000
	jsr check_bg_collision_chk_flag

check_bg_collision_right:
	lda #2
	sta z3
	jsr check_bg_collision_add_to_find_next_spot
	lda #%00100000
	jsr check_bg_collision_chk_flag

check_bg_collision_left_inner_y:
	lda #30
	sta z3
	jsr check_bg_collision_add_to_find_next_spot
	lda player_inner_y
	beq check_bg_collision_down
	lda #%01000000
	jsr check_bg_collision_chk_flag

check_bg_collision_down:
	lda #1
	sta z3
	jsr check_bg_collision_add_to_find_next_spot
	lda #%00010000
	jsr check_bg_collision_chk_flag

check_bg_collision_down_inner_x:
	lda #1
	sta z3
	jsr check_bg_collision_add_to_find_next_spot
	lda player_inner_x
	beq check_bg_collision_right_inner_y
	lda #%00010000
	jsr check_bg_collision_chk_flag

check_bg_collision_right_inner_y:
	lda #0
	sta z3
	jsr check_bg_collision_add_to_find_next_spot
	lda player_inner_y
	beq done_check_bg_collision
	lda #%00010000
	jsr check_bg_collision_chk_flag

done_check_bg_collision:
	lda #0
	sta $2005
	lda #255
	sta $2005
	lda #$88
	sta $2000

	rts

check_bg_collision_update_2006_lda_2007:
	;TODO NUXT: why does $2006 cause this???
	lda start_collision_low
	sta $2006
	stx start_collision_high
	stx $2006

	; TODO (later): modify for scrolling logic

	lda $2007    					; Checking BG at that spot
	tax
	rts

check_bg_collision_chk_flag:
	cpx #1
	bne finished_check_bg_collision_chk_flag
	ora collision_flags
	sta collision_flags
finished_check_bg_collision_chk_flag:
	lda #0
	sta start_collision_low
	sta start_collision_high
	rts

check_bg_collision_add_to_find_next_spot:
    lda start_collision_low
    clc
    adc z3
    sta start_collision_low
    lda start_collision_high
    adc #0
    sta start_collision_high
    rts


irq:
	rti

reset:
	cld
	sei

	ldx #$FF
	txs
	
	inx
	sta $2000
	sta $2001
	sta $4010
	sta $4015
	
	lda #40
	sta $4017 			; Disable frame interrupt (APU frame counter)

wait_vblank:
	bit $2002
	bpl wait_vblank

	
	; x is already 0
clear_ram:
	lda #0
	sta $0000,x
	sta $0100,x
	sta $0300,x
	sta $0400,x
	sta $0500,x
	sta $0600,x
	sta $0700,x

	lda #255
	sta $0200,x  		; Put all the sprites offscreen

	inx
	bne clear_ram


	;; set collision address to $2000 (00 already set in start_collision_low)
	lda #$20
	sta start_collision_high



	;; DISPLAY CODE: this is where the code starts to initialize
	;; (place) the sprites used to track the position of the player's
	;; sprite. 

	lda #0
	sta $02D2
	sta $02DA
	sta $02D6
	sta $02DE
	sta $02E2
	sta $02EA
	sta $02E6
	sta $02EE
	sta $02F2
	sta $02FA
	sta $02F6
	sta $02FE

	; set y-value on screen for debug to 40 (inner)
	lda #40 
	sta $02E0	; high-digit (inner x)
	sta $02E4	; low-digit
	sta $02E8	; high-digit (inner y)
	sta $02EC	; low-digit
	
	; set y-value on screen for debug to 48 (x/y)
	lda #48
	sta $02F0	; high-digit (x)
	sta $02F4
	sta $02F8	; high-digit (y)
	sta $02FC

	; set y-value on screen for abs val debug to 56 (abs x/y)
	lda #56	
	sta $02D0
	sta $02D4
	sta $02D8
	sta $02DC

	; highx lowx highy lowy
	lda #$60
	sta $02D3
	sta $02E3
	sta $02F3
	lda #$68
	sta $02D7
	sta $02E7
	sta $02F7
	lda #$70
	sta $02DB
	sta $02EB
	sta $02FB
	lda #$78
	sta $02DF
	sta $02EF
	sta $02FF
	;; END DISPLAY CODE

wait_vblank_2:
	bit $2002
	bpl wait_vblank_2

load_palete:
	lda $2002
	lda #$3F
	sta $2006
	lda #$00
	sta $2006
	ldx #0
palette_loop:
	lda palette_table,x
	sta $2007
	inx
	cpx #$20
	bne palette_loop

load_map:
	lda $2002
	lda #$20
	sta $2006
	lda #$00
	sta $2006

	; NOTE: This loop breaks if the second table
	; value is zero, i.e. there are "zero" tiles
	; of the first tile!
	; SECOND NOTE: Using two entries of 255 ($FF) 
	; to indicate the end of table data, so we 
	; know when to kill the loop.
	
	ldx #1
	lda map_data_table_one,x
	tay
	dex
map_load_loop:
	lda map_data_table_one,x
inner_map_loop:
	sta $2007 			; write one tile
	dey					; decrease y-count cause we've done one...
	cpy #0
	bne inner_map_loop
	inx
	inx
	inx
	lda map_data_table_one,x ; load value two-higher
	tay
	cpy #255			; last two values assumed to be 255,255
	beq done_map_loop	; so if we hit that, we're done
	dex					; at any rate, y is loaded properly...
	jmp map_load_loop	; so let's start the loop over again
done_map_loop:
	lda #0
	sta $2005			; reset the scrolling
	lda #255
	sta $2005

	; TODO:
	; store magic numbers for player
	; position for proof of concept
	lda #0
	sta player_inner_x
	sta player_inner_y
	sta clock_cycle
	lda #10
	sta clock_cycle_end

	lda #80  		;not lda #80, that's 80/8 = 10
	sta player_x
	lda #16			;not #16, that's 16/8 = 2
	sta player_y
	lda #10
	sta player_abs_x
	lda #2
	sta player_abs_y

	;; SPRITE LOGIC - BEGIN ;;
	ldx #0
load_sprite:
	lda sprite_data,x
	sta $0200,x
	inx
	cpx #44
	bne load_sprite

	lda #$02
	sta $4014


	lda #$1E 		;; PPUMASK 0001 1110 - rgb and monochrome untouched
	sta $2001		;; sprite and bkgd on, don't hide sprite/bg clip
	lda #$88 		;; PPUCTRL 10001000 - Nmi on, (unused/extpins), sprites8x8, bg$0000, 
	sta $2000 		;; spr$1000, inc+1, AA=$2000 (namespace start)


main_loop:

check_ctrl_start:
	lda #1
	sta $4016
	lda #0
	sta $4016
	ldx #8
read_ctrl_loop:
	pha
	lda $4016
	and #%00000011
	cmp #1
	pla
	ror
	dex
	bne read_ctrl_loop
	sta button_array

	lda clock_cycle  			; check that clock_cycle is appropriate (for now we're assuming
	;bne main_loop_end 			; 0 means "you can update x/y positions")
	lda nmi_flags				; Now we check that we're not already waiting for a gfx update...
	and #2  
	bne main_loop_end   		; go to end of loop if bit 1 is turned on....

	jsr check_collision
	jsr check_controller
	jsr update_xy

main_loop_end:
	jmp main_loop

check_collision:
	;TODO: still not sure whether to use this or EOR the DONKY
	;lda collision_flags
	;and #%00001111				; turn off collisions to start check
	;sta collision_flags


	; Start by finding where we are on BG nametable
	lda player_abs_y
	sec
	sbc #1
	tax

	ldy #0
	lda #0
	sta z3
	clc
bg_collision_find_y:
	adc #32
	sta z3
	bcc bg_collision_find_y_dex
	iny 							; Store number of carries in y
	clc
bg_collision_find_y_dex:
	dex
	bne bg_collision_find_y

	; Now add 1 more than the x offset (zero-indexing):
	inc player_abs_x
	clc
	lda z3
	adc player_abs_x
	sta z3
	dec player_abs_x

	lda z3
	sta start_collision_low  		; LSB for nametable

	tya
	clc
	adc #$20 						; MSB for nametable
	sta start_collision_high

	rts


check_controller:
	
check_right:
	lda button_array
	and #%10000000
	beq checkleft
	; logic for moving right
	moveright:
		; dx = 1
		lda #1
		sta dx
checkleft:
	lda button_array
	and #%01000000 
	beq checkup
	; logic for moving left
	moveleft:
		; dx = -1
		lda #255
		sta dx
checkup:
	lda button_array
	and #%00010000 
	beq checkdown
	moveup:
		; dy = -1
		lda #255
		sta dy
checkdown:
	lda button_array
	and #%00100000 
	beq move_now
	movedown:
		; dy = 1
		lda #1
		sta dy
move_now:		
	rts

;; BEFORE WE DO ANY UPDATE_XY, just do the following:
;; Check if there's a collision using player_abs_x or player_abs_y
;; if there is, just zero out dx and/or dy, then movement won't happen anyways
;; NOTE: this would still "trigger" update_xy (i.e. the code will still run)
;; so this is probably wasted cycles (we might want a quick dx/dy check and just skip update_xy if necessary)

update_xy:
	; x coordinate relative to one screen
	; (zero-indexed) 32x30
	
	lda player_x
	clc
	adc dx
	sta player_x

	lda player_inner_x
	clc
	adc dx
	sta player_inner_x

	;; check if adjacent direction is wall;
	;; if it is, we don't move!
	cmp #1
	beq check_wall_right
	
	; check if > 7 (new abs_x)
	cmp #8
	beq change_abs_x

	cmp #255
	;; check if adjacent direction is wall;
	;; if it is, we don't move!
	beq check_wall_left
	jmp done_inner_x

check_wall_left:
	lda collision_flags
	and #%01000000
	beq change_abs_x
	inc player_x
	inc player_inner_x
	inc dx
	jmp done_inner_x

check_wall_right:
	lda collision_flags
	and #%00100000
	beq done_inner_x
	dec player_x
	dec player_inner_x
	dec dx 
	jmp done_inner_x
change_abs_x:
	; player_inner_x is -1 or 8, reset it by doing lsr 5 times:
	;  8 = 00001000 => 00000100 => 00000010 => 00000001 => 00000000 => 00000000
	; -1 = 11111111 => 01111111 => 00111111 => 00011111 => 00001111 => 00000111
	lsr player_inner_x
	lsr player_inner_x
	lsr player_inner_x
	lsr player_inner_x
	lsr player_inner_x

	lda player_abs_x
	clc
	adc dx
	sta player_abs_x
done_inner_x:
	; check y now
start_y:

	lda player_y
	clc
	adc dy
	sta player_y

	lda player_inner_y
	clc
	adc dy
	sta player_inner_y
	
	; check if > 7 (new abs_y)
	cmp #1
	;; check if adjacent direction is wall;
	;; if it is, we don't move!
	beq check_wall_down

	cmp #8
	beq change_abs_y

	cmp #255
	;; check if adjacent direction is wall;
	;; if it is, we don't move!
	beq check_wall_up
	jmp done_inner_y

check_wall_up:
	lda collision_flags
	and #%10000000
	beq change_abs_y
	inc player_y
	inc player_inner_y
	inc dy
	jmp done_inner_y

check_wall_down:
	lda collision_flags
	and #%00010000
	beq done_inner_y
	dec player_y
	dec player_inner_y
	dec dy 
	jmp done_inner_y
	
change_abs_y:
	; player_inner_y is -1 or 8, reset it by doing lsr 5 times:
	;  8 = 00001000 => 00000100 => 00000010 => 00000001 => 00000000 => 00000000
	; -1 = 11111111 => 01111111 => 00111111 => 00011111 => 00001111 => 00000111
	lsr player_inner_y
	lsr player_inner_y
	lsr player_inner_y
	lsr player_inner_y
	lsr player_inner_y

	lda player_abs_y
	clc
	adc dy
	sta player_abs_y
done_inner_y:
update_tiles:

	;; TO DO DEL PLACEHOLDERS
	; e7 e6 e5 e4 (inner x low) e3 e2 e1 e0 (inner x high)
	; ef ee ed ec (inner y low) eb ea e9 e8 (inner y high)
	; f7 f6 f5 f4 (abs x low)  f3 f2 f1 f0 (abs x high)
	; ff fe fd fc (abs y low)  fb fa f9 f8 (abs y high)
	;; MORE WASTEFUL CODE THAT SHOULD GO SOMEWHER EELSE
	;; BUT I JUST WANT PRROOF OF CONCEPT DEL LATER
	;; inner_x tile number: $02E5 (high)	

	lda #0
	sta z
	lda player_abs_x
	ldy #$D1
	jsr extracting_tens
	lda player_abs_y
	ldy #$D9
	jsr extracting_tens

	;lda player_inner_x
	;lda dx 			; test dx if you want :)
	;lda clock_cycle
	lda collision_flags
	ldy #$E1
	jsr extracting_tens
	
	
	
	lda player_x
	ldy #$F1
	jsr extracting_tens
	lda player_y
	ldy #$F9
	jsr extracting_tens
	
	

	;; TODO: is this right???
	lda nmi_flags
	ora #%00000010  	; turn on update gfx flag
	sta nmi_flags

	lda player_x
	sta $0203
	lda player_y
	sta $0200

	lda #0
	sta dx
	sta dy

	rts

extracting_tens:
	sta z

	ldx #0  			; Use this to keep track of tens column
begin_ten_extraction:

	lda z
	and #$F0

	;; loop:
	;; - is it less than 10? then just take the number and that's your right digit; exit loop
	beq store_high_digit
	;; - is it more than 10? then just subtract 10, add that to your left digit, and repeat loop
	lda z
	sec
	sbc #$10

	; x is where we keep track of "tens" (hexes?) column:
	sta z
	inx
	jmp begin_ten_extraction

store_high_digit:
	; store the new tens digit before moving to the units digit
	txa
	sta $0200,y
	
store_low_digit:

	ldx #0
loop_low_digit:
	lda z
store_value:
	iny
	iny
	iny
	iny
	sta $0200,y
	lda #0
	sta z
	rts

palette_table:
	db $0F, $18, $16, $32
	db $0F, $18, $16, $32
	db $0F, $18, $16, $32
	db $0F, $18, $16, $32
	db $0F, $11, $12, $11
	db $0F, $11, $14, $15
	db $0F, $16, $17, $19
	db $0F, $19, $1A, $1B

; Formatting for map tables:
; a,b, c,d, ... where a,c are tile #s, b,d are quantity

map_data_table_one:
	; let's build a simple map so we can see if it works
	db 1,33, 0,30, 1,2, 0,15, 1,5, 0,10, 1,2, 0,30 
	db 1,10, 0,8, 1,19, 0,15, 1,1, 0,10, 1,3, 0,30
	db 1,30, 0,2, 1,2, 0,5, 1,5, 0,5, 1,5, 0,5, 1,4, 0,1, 1,5
    db 0,10, 1,7, 0,10, 1,2
    db 0,30, 1,2, 0,30, 1,2, 0,30, 1,2, 0,30, 1,2, 0,30, 1,2
    db 0,30, 1,2, 0,30, 1,2, 0,30, 1,2, 0,30, 1,2, 0,30, 1,2
    db 0,30, 1,2, 0,30, 1,2, 0,30, 1,2, 0,30, 1,2, 0,30, 1,2
    db 0,30, 1,2, 0,30, 1,2, 0,30, 1,2, 0,30, 1,33

	db 255,255, 2,32, 3,32, 4,32
	db 20,32, 21,32, 22,32, 23,32, 24,32
	db 25,32, 26,32, 27,32, 28,32, 29,32
	db 255,255

map_data_table_two:
	; let's build a simple map so we can see if it works
	db 10,32, 11,32, 12,32, 13,32, 14,32
	db 15,32, 16,32, 17,32, 18,32, 19,32
	db 20,32, 21,32, 22,32, 23,32, 24,32
	db 25,32, 26,32, 27,32, 28,32, 29,32
	db 1,32, 0,32, 0,32, 0,32, 2,32
	db 1,32, 0,32, 0,32, 0,32, 2,32

sprite_data:
	db 16, $10, $01, 80

	db $36, $0, $03, $40 			
	db $46, $1, $03, $40 			
	db $56, $2, $03, $40 			
	db $66, $3, $03, $40 			

	db $76, $4, $03, $40 			
	db $86, $5, $03, $40 			
	db $96, $6, $03, $40 			
	db $A6, $7, $03, $40 			

	db $B6, $8, $03, $40 			
	db $C6, $9, $03, $40 			

	org $FFFA
	dw nmi
	dw reset
	dw irq

chr_rom_start:

bg_start:

	; OICURMT
    db 0,0,0,0,0,0,0,0
    db 0,0,0,0,0,0,0,0

    ; test block - tile 1
    db %11111111
    db %10000001
    db %10000001
    db %10000001
    db %10000001
    db %10000001
    db %10000001
    db %11111111
    db $FF, $FF, $FF, $FF, $FF, $FF, $FF, $00
    ;db $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
    ;db $00, $FF, $FF, $FF, $FF, $FF, $FF, $00

    db %00000000    
    db %01100000 ; A
    db %10010000
    db %10010000
    db %11110000
    db %10010000 ; A5
    db %10010000
    db %10010000
    db 0,0,0,0,0,0,0,0

    db %00000000 ; B
    db %11100000 
    db %10010000
    db %10010000
    db %11100000 ; B5
    db %10010000
    db %10010000
    db %11100000
    db 0,0,0,0,0,0,0,0

    db %11110000 ; C
    db %10000000 ; 
    db %10000000 ; 
    db %10000000 ; 
    db %10000000 ; 
    db %10000000 ; 
    db %10000000 ; 
    db %11110000 ; 
    db 0,0,0,0,0,0,0,0



    db %00000000
    db %11100000 ; D 
    db %10010000
    db %10010000
    db %10100000
    db %11000000
    db %00000000
    db %00000000
    db 0,0,0,0,0,0,0,0

    db %00000000
    db %01110000 ; E
    db %01000000
    db %01000000
    db %01110000
    db %01000000
    db %01000000
    db %01110000
    db 0,0,0,0,0,0,0,0

    db %00000000
    db %01110000 ; F (moved top row of 1s over one)
    db %01000000
    db %01000000
    db %01110000
    db %01000000
    db %01000000
    db %00000000
    db 0,0,0,0,0,0,0,0


    db %00000000 ; G
    db %00011110
    db %00100000
    db %01000000
    db %01000000
    db %11000110
    db %01000010
    db %00111100
    db 0,0,0,0,0,0,0,0

    ;letter_h
    db %10000001
    db %10000001
    db %10000001 ; H
    db %11111111
    db %10000001
    db %10000001
    db %10000001
    db %00000000
    db $00,$00,$00,$00,$00,$00,$00,$00

    db %00000000 ; I
    db %00111100
    db %00001000
    db %00001000
    db %00001000
    db %00001000
    db %00001000
    db %00111100
    db 0,0,0,0,0,0,0,0
    

    db %00010000 ; J
    db %00010000
    db %00010000
    db %00010000
    db %00010000
    db %00010000
    db %1001000
    db %00110000
    db 0,0,0,0,0,0,0,0

    db %00000000
    db %01000100 ; K
    db %01001000
    db %01010000
    db %01100000
    db %01010000
    db %01001000
    db %00000000
    db 0,0,0,0,0,0,0,0

    db %10000000 ; L
    db %10000000
    db %10000000
    db %10000000
    db %10000000
    db %10000000
    db %10000000
    db %11111110
    db 0,0,0,0,0,0,0,0


    db%10000001 ; M
    db%10100101
    db%10100101
    db%10011001
    db%10011001
    db%10000001
    db%10000001
    db%10000001
    db%00000000
    db%00000000
    db%00000000
    db%00000000
    db%00000000
    db%00000000
    db%00000000
    db%00000000

    db%10000001 ; N
    db%10100001
    db%10110001
    db%10011001
    db%10001101
    db%10000111
    db%10000011
    db%10000001
    db%00000000
    db%00000000
    db%00000000
    db%00000000
    db%00000000
    db%00000000
    db%00000000
    db%00000000

    db %01111110
    db %10000010 ; O
    db %10000010
    db %10000010
    db %10000010
    db %10000010
    db %10000010
    db %01111110
    db 0,0,0,0,0,0,0,0


    db%11110000 ; P
    db%10011000
    db%10011000
    db%10011000
    db%11110000
    db%10000000
    db%10000000
    db%10000000
    db%00000000
    db%00000000
    db%00000000
    db%00000000
    db%00000000
    db%00000000
    db%00000000
    db%00000000

    db %00111100 ;Q
    db %01111110
    db %01100110
    db %01100110
    db %01100110
    db %01100110
    db %01111111
    db %00111101
    db 0, 0, 0, 0, 0, 0, 0, 0
       
       
    db %01111000 ;R
    db %01111100
    db %01100110
    db %01100110
    db %01111000
    db %01101100
    db %01100110
    db %01100110
    db 0, 0, 0, 0, 0, 0, 0, 0
       
       
    db %00111100 ;S
    db %01111110
    db %01100000
    db %00111100
    db %00001100
    db %01100110
    db %01111110
    db %00111100
    db 0, 0, 0, 0, 0, 0, 0, 0



    
    db %00000000 ; T
    db %01111110
    db %00001000
    db %00001000
    db %00001000
    db %00001000
    db %00001000
    db %00001000

    db %00000000
    db %00000000
    db %00000000
    db %00000000
    db %00000000
    db %00000000
    db %00000000
    db %00000000
    ; ... and so on for the rest of the alphabet   
   
    db %01100110 ;U
    db %01100110
    db %01100110
    db %01100110
    db %01100110
    db %01100110
    db %01111110
    db %00111100
    db 0, 0, 0, 0, 0, 0, 0, 0
       

    db %01100110 ;V
    db %01100110
    db %01100110
    db %01100110
    db %01100110
    db %01100110
    db %01111110
    db %00001100
    db 0, 0, 0, 0, 0, 0, 0, 0
       

    db %01100110 ;W
    db %01100110
    db %01100110
    db %01100110
    db %01100110
    db %01100110
    db %01111110
    db %01100110
    db 0, 0, 0, 0, 0, 0, 0, 0


    db %11000011 ; Letter X
    db %11000011
    db %00110011
    db %00001100
    db %00001100
    db %00110011
    db %11000011
    db %11000011
    db $00,$00,$00,$00,$00,$00,$00,$00


    db %11000011 ; Letter Y
    db %11000011
    db %00110011
    db %00001100
    db %00001100
    db %00001100
    db %00001100
    db %00001100
    db $00,$00,$00,$00,$00,$00,$00,$00

    db %11111111 ; Letter Z
    db %00001100
    db %00011000
    db %00110000
    db %01100000
    db %11000000
    db %11000000
    db %11111111
    db $00,$00,$00,$00,$00,$00,$00,$00

	
	; PROBABLY SOME OR ALL BOSSES GO IN BACKGROUND!!!
	; BACKGROUND:

	; Grass
	; Colors: #FFFFFF, #85BC2F, #366D00, #55C753, #FFFFFF, #730A37, #710F07, #5A1A00, #FFFFFF, #0B3400, #003C00, #003D10, #FFFFFF, #000000, #000000, #000000
	; Tile 1
	; Palette 1: #FFFFFF, #85BC2F, #366D00, #55C753
	db %11111111
	db %11111111
	db %11111111
	db %11111111
	db %11111111
	db %11111111
	db %11111111
	db %11111111

	db %01111111
	db %01111011
	db %11111011
	db %11111111
	db %11111111
	db %11101111
	db %11101110
	db %11111110

	; Brick
	; Colors: #FFFFFF, #002D69, #5A1A00, #FF8B7F, #FFFFFF, #730A37, #710F07, #5A1A00, #FFFFFF, #0B3400, #003C00, #003D10, #FFFFFF, #000000, #000000, #000000
	; Tile 1
	; Palette 1: #FFFFFF, #002D69, #5A1A00, #FF8B7F
	db %10001000
	db %10001000
	db %10001000
	db %11111111
	db %00100010
	db %00100010
	db %00100010
	db %11111111
	db %11111111
	db %11111111
	db %11111111
	db %11111111
	db %11111111
	db %11111111
	db %11111111
	db %11111111


	; NONSENSE TILE - testing only
	db %11111111
	db %11011011
	db %11111111
	db %11111111
	db %10111101
	db %11011011
	db %11100111
	db %11111111
	db %11111111
	db %11111111
	db %11111111
	db %11111111
	db %11111111
	db %11111111
	db %11111111
	db %11111111

	

	db %00000000	; #0: Blank SHOULD BE ZERO BUT TESTIN GRASS
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	db 0,0,0,0,0,0,0,0


bg_end:

	ds 4096 - (bg_end - bg_start)	; Ensure correct size of background tiles (4096 bytes)


sprite_start:

	; TEST TILE ZERO - solid block after digits (tile "A")
	

	; 0
	db %11111111
	db %10000001
	db %10111101
	db %10111101
	db %10111101
	db %10111101
	db %10000001
	db %11111111
	db 0,0,0,0,0,0,0,0 ; bitplane 2

	; 1
	db %11111111
	db %11100111
	db %11100111
	db %11100111
	db %11100111
	db %11100111
	db %11100111
	db %11111111
	db 0,0,0,0,0,0,0,0 ; bitplane 2

	; 2
	db %11111111
	db %11100111
	db %10000011
	db %00110011
	db %11001111
	db %10111111
	db %10000111
	db %11111111
	db 0,0,0,0,0,0,0,0 ; bitplane 2

	; 3
	db %11111111
	db %11100111
	db %10000011
	db %11111011
	db %11000111
	db %11111011
	db %10000111
	db %11111111
	db 0,0,0,0,0,0,0,0 ; bitplane 2

	; 4
	db %11111111
	db %11100111
	db %11000111
	db %10100111
	db %00000111
	db %11100111
	db %11100111
	db %11111111
	db 0,0,0,0,0,0,0,0 ; bitplane 2

	; 5
	db %11111111
	db %00000001
	db %00111111
	db %00000111
	db %11111011
	db %11111011
	db %10000111
	db %11111111
	db 0,0,0,0,0,0,0,0 ; bitplane 2

	; 6
	db %11011111
	db %10111111
	db %01111111
	db %00000111
	db %01111011
	db %01111011
	db %10000111
	db %11111111
	db 0,0,0,0,0,0,0,0 ; bitplane 2

	; 7
	db %11111111
	db %10000001
	db %11111101
	db %11111011
	db %11110111
	db %11101111
	db %11011111
	db %11111111
	db 0,0,0,0,0,0,0,0 ; bitplane 2

	; 8
	db %10000111
	db %01111011
	db %01111011
	db %10000111
	db %10000111
	db %01111011
	db %10000111
	db %11111111
	db 0,0,0,0,0,0,0,0 ; bitplane 2

	; 9
	db %10000111
	db %01111011
	db %01111011
	db %10000011
	db %11110111
	db %11101111
	db %10111111
	db %11111111
	db 0,0,0,0,0,0,0,0 ; bitplane 2

	db %00000000    
    db %01100000 ; A
    db %10010000
    db %10010000
    db %11110000
    db %10010000 ; A5
    db %10010000
    db %10010000
    db 0,0,0,0,0,0,0,0

    db %00000000 ; B
    db %11100000 
    db %10010000
    db %10010000
    db %11100000 ; B5
    db %10010000
    db %10010000
    db %11100000
    db 0,0,0,0,0,0,0,0

    db %11110000 ; C
    db %10000000 ; 
    db %10000000 ; 
    db %10000000 ; 
    db %10000000 ; 
    db %10000000 ; 
    db %10000000 ; 
    db %11110000 ; 
    db 0,0,0,0,0,0,0,0



    db %00000000
    db %11100000 ; D 
    db %10010000
    db %10010000
    db %10100000
    db %11000000
    db %00000000
    db %00000000
    db 0,0,0,0,0,0,0,0

    db %00000000
    db %01110000 ; E
    db %01000000
    db %01000000
    db %01110000
    db %01000000
    db %01000000
    db %01110000
    db 0,0,0,0,0,0,0,0

    db %00000000
    db %01110000 ; F (moved top row of 1s over one)
    db %01000000
    db %01000000
    db %01110000
    db %01000000
    db %01000000
    db %00000000
    db 0,0,0,0,0,0,0,0

	; test block (solid square)
	db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
	db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
	
	; Carnivorous Plant
	; Colors: #FFFFFF, #000000, #55C753, #00793D, #FFFFFF, #C890FF, #F8D5B4, #656565, #FFFFFF, #AEE8D0, #AFE5EA, #B6B6B6, #FFFFFF, #FF83C0, #EF9A49, #730A37
	; Tile 1
	; Palette 1: #FFFFFF, #000000, #55C753, #00793D
	db %00000000
	db %00000011
	db %00000100
	db %00001001
	db %00001101
	db %00001000
	db %00000110
	db %01100011

	db %00000000   ;bp2
	db %00000000
	db %00000011
	db %00000111
	db %00000111
	db %00000111
	db %00000011
	db %00000000

	; Tile 2
	; Palette 1: #FFFFFF, #000000, #55C753, #00793D
	db %10110000
	db %11011000
	db %11011111
	db %01101110
	db %00111110
	db %00000101
	db %00001110
	db %00010100
	db %01000000
	db %01100000
	db %01110000
	db %00111101
	db %00000001
	db %00000010
	db %00000100
	db %00001000
	
	; Tile 3
	; Palette 1: #FFFFFF, #000000, #55C753, #00793D
	db %00010100
	db %00111000
	db %00111000
	db %00111000
	db %00101000
	db %00010100
	db %00011100
	db %00001010
	db %00001000
	db %00010000
	db %00010000
	db %00010000
	db %00010000
	db %00001000
	db %00001000
	db %00000100
	; Tile 4
	; Palette 1: #FFFFFF, #000000, #55C753, #00793D
	db %00011110
	db %00011001
	db %00111111
	db %01011011
	db %01110011
	db %01000001
	db %00000000
	db %00000000
	db %00000100
	db %00001110
	db %00001011
	db %00110001
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	; Tile 5
	; Palette 1: #FFFFFF, #000000, #55C753, #00793D
	db %11111000
	db %10010110
	db %11000101
	db %10111111
	db %01000000
	db %01000111
	db %10111001
	db %10110110
	db %00000000
	db %11111000
	db %11111110
	db %11000000
	db %10000000
	db %10000000
	db %11000110
	db %11111000
	; Tile 6
	; Palette 1: #FFFFFF, #000000, #55C753, #00793D
	db %11111000
	db %10100011
	db %01111101
	db %10110011
	db %11001110
	db %11111100
	db %00000000
	db %00000000
	db %00000000
	db %01000000
	db %10000010
	db %01111100
	db %01111000
	db %00000000
	db %00000000
	db %00000000
	; Tile 7
	; Palette 1: #FFFFFF, #000000, #55C753, #00793D
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	; Tile 8
	; Palette 1: #FFFFFF, #000000, #55C753, #00793D
	db %00000000
	db %00000000
	db %10000000
	db %01000000
	db %01100000
	db %11100000
	db %00100000
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	db %10000000
	db %11000000
	db %00000000
	db %00000000
	db %00000000


	; carnivorous plant animation 2 and 4
	; Layout: 4x2
	; Tile 9 (Column 1, Row 1)
	; Palette 1: #FFFFFF, #55C753, #00793D, #000000  	CORRECT -> #FFFFFF, #000000, #55C753, #00793D
	; NES Colors: $20, $2A, $1B, $0F
	db %00000000
	db %00000011
	db %00000100
	db %00001001
	db %00001010
	db %00001000
	db %00000110
	db %00000011
	
	db %00000000
	db %00000000
	db %00000011
	db %00000111
	db %00000101
	db %00000111
	db %00000011
	db %00000000


	; Tile 10 (Column 1, Row 2) (OLD TILE 3 NEW TILE 2??)
	; Palette 1: #FFFFFF, #55C753, #00793D, #000000 DUN!!!!!!!!!!!!!
	; NES Colors: $20, $2A, $1B, $0F
	db %01110000
	db %01101000
	db %01100000
	db %00111001
	db %00001111
	db %00000001
	db %00000001
	db %00000010
	
	db %00000000
	db %00110000
	db %00111000
	db %00001110
	db %00000000
	db %00000000
	db %00000000
	db %00000001

	; Tile 11 (Column 1, Row 3) (OLD TILE 5 NEW TILE 3??)
	; Palette 1: #FFFFFF, #55C753, #00793D, #000000   CORRECT -> #FFFFFF-DUN, #000000-, #55C753-, #00793D-DUN!!!!!!!!!!!!!!
	; NES Colors: $20, $2A, $1B, $0F
	db %00000010
	db %00000010
	db %00000010
	db %00000010
	db %00000001
	db %00000001
	db %00000001
	db %00000000
	
	db %00000001
	db %00000001
	db %00000001
	db %00000001
	db %00000000
	db %00000000
	db %00000000
	db %00000000

	; Tile 12 (Column 1, Row 4)
	; Palette 1: #FFFFFF, #55C753, #00793D, #000000 CORRECT -> #FFFFFF, #000000, #55C753, #00793D DUN!!!
	; NES Colors: $20, $2A, $1B, $0F
	db %00000000
	db %00000011
	db %00000100
	db %00000111
	db %00000100
	db %00000000
	db %00000000
	db %00000000
	
	db %00000000
	db %00000000
	db %00000011
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	db %00000000

	; Tile 13 (Column 2, Row 1)
	; Palette 1: #FFFFFF, #55C753, #00793D, #000000
	; NES Colors: $20, $2A, $1B, $0F   CORRECT -> #FFFFFF-DUN, #000000-DUN, #55C753-DUN, #00793D     DUN!!!!
	db %11111000
	db %10010110
	db %11000101
	db %10111111
	db %01000000
	db %01000111
	db %10111001
	db %10000110
	
	db %00000000
	db %11111000
	db %11111110
	db %11000000
	db %10000000
	db %11000000
	db %11000110
	db %11111000

	; Tile 14 (Column 2, Row 2)
	; Palette 1: #FFFFFF, #55C753, #00793D, #000000  	CORRECT -> #FFFFFF, #000000, #55C753, #00793D DUN!
	; NES Colors: $20, $2A, $1B, $0F
	db %11111000
	db %11100011
	db %11011111
	db %11110011
	db %11101110
	db %01110000
	db %11000000
	db %10000000
	
	db %10000000
	db %10100000
	db %01000010
	db %01101110
	db %01010000
	db %11000000
	db %10000000
	db %10000000
	
	; Tile 15 (Column 2, Row 3)
	; Palette 1: #FFFFFF, #55C753, #00793D, #000000  CORRECT -> #FFFFFF, #000000, #55C753, #00793D DUN!!
	; NES Colors: $20, $2A, $1B, $0F
	db %10000000
	db %10000000
	db %10000000
	db %10000000
	db %01000000
	db %11000000
	db %11000000
	db %10100000
	
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	db %10000000
	db %10000000
	db %10000000
	db %01000000
	
	; Tile 16 (Column 2, Row 4)
	; Palette 1: #FFFFFF, #55C753, #00793D, #000000  CORRECT -> #FFFFFF, #000000, #55C753, #00793D DUN!
	; NES Colors: $20, $2A, $1B, $0F
	
	db %11100000
	db %10011000
	db %11101100
	db %00010100
	db %00000100
	db %00000000
	db %00000000
	db %00000000

	db %01000000
	db %11100000
	db %00011000
	db %00001000
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	
	; carnivorous plant animation 3
	; Layout: 4x2
	; Tile 17 (Column 1, Row 1)
	; Palette 1: #FFFFFF, #55C753, #00793D, #000000
	; NES Colors: $20, $2A, $1B, $0F
	db %00000000
	db %00000011
	db %00000111
	db %00001110
	db %00001010
	db %00001111
	db %00000101
	db %00000011
	db %00000000
	db %00000011
	db %00000100
	db %00001001
	db %00001101
	db %00001000
	db %00000110
	db %00000011
	; Tile 18 (Column 2, Row 1)
	; Palette 1: #FFFFFF, #55C753, #00793D, #000000
	; NES Colors: $20, $2A, $1B, $0F
	db %11111000
	db %01101110
	db %00111011
	db %01111111
	db %11000000
	db %11000111
	db %01111111
	db %01001110
	db %11111000
	db %10010110
	db %11000101
	db %10111111
	db %01000000
	db %01000111
	db %10111001
	db %10110110
	; Tile 19 (Column 1, Row 2)
	; Palette 1: #FFFFFF, #55C753, #00793D, #000000
	; NES Colors: $20, $2A, $1B, $0F
	db %01110000
	db %01011000
	db %01011111
	db %00110111
	db %00001111
	db %00000001
	db %00000001
	db %00000000
	db %01110000
	db %01101000
	db %01100111
	db %00111001
	db %00001111
	db %00000001
	db %00000001
	db %00000000
	; Tile 20 (Column 2, Row 2)
	; Palette 1: #FFFFFF, #55C753, #00793D, #000000
	; NES Colors: $20, $2A, $1B, $0F
	db %11111000
	db %11100011
	db %11011101
	db %11110011
	db %11101110
	db %01110000
	db %11000000
	db %11100000
	db %11111000
	db %10100011
	db %01011111
	db %01101101
	db %01011110
	db %11110000
	db %01000000
	db %10100000
	; Tile 21 (Column 1, Row 3)
	; Palette 1: #FFFFFF, #55C753, #00793D, #000000
	; NES Colors: $20, $2A, $1B, $0F
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	; Tile 22 (Column 2, Row 3)
	; Palette 1: #FFFFFF, #55C753, #00793D, #000000
	; NES Colors: $20, $2A, $1B, $0F
	db %11100000
	db %10100000
	db %10100000
	db %01010000
	db %01110000
	db %01110000
	db %01010000
	db %01110000
	db %10100000
	db %11100000
	db %11100000
	db %01110000
	db %01010000
	db %01010000
	db %01110000
	db %01010000
	; Tile 23 (Column 1, Row 4)
	; Palette 1: #FFFFFF, #55C753, #00793D, #000000
	; NES Colors: $20, $2A, $1B, $0F
	db %00000000
	db %00000000
	db %00000000
	db %00000001
	db %00000011
	db %00000011
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	db %00000001
	db %00000010
	db %00000011
	db %00000000
	db %00000000
	; Tile 24 (Column 2, Row 4)
	; Palette 1: #FFFFFF, #55C753, #00793D, #000000
	; NES Colors: $20, $2A, $1B, $0F
	db %00101000
	db %00111000
	db %11001100
	db %01110010
	db %11101101
	db %00000111
	db %00000001
	db %00000000
	db %00111000
	db %00101000
	db %11110100
	db %10111110
	db %11101011
	db %00000111
	db %00000001
	db %00000000


	; Tile 25
	; Palette 1: #FFFFFF, #000000, #7841CC, #656565
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	db %00000011
	db %00000110
	db %00000110

	db %00000000
	db %00000000
	db %00000000
	db %00000000
	db %00000011
	db %00000100
	db %00001001
	db %00001001
	; Tile 26
	; Palette 1: #FFFFFF, #000000, #7841CC, #656565
	db %00000111
	db %00000011
	db %00000000
	db %00001010
	db %00110001
	db %00100010
	db %00100010
	db %00000000
	db %00001000
	db %00000100
	db %00011011
	db %00111111
	db %01001111
	db %01010111
	db %01010111
	db %01100111
	; Tile 27
	; Palette 1: #FFFFFF, #000000, #7841CC, #656565
	db %00000011
	db %00000010
	db %00000100
	db %00000000
	db %00000110
	db %00000000
	db %00000000
	db %00000000
	db %00000111
	db %00000111
	db %00001110
	db %00001110
	db %00001111
	db %00001111
	db %00000000
	db %00000000
	; Tile 28
	; Palette 1: #FFFFFF, #000000, #7841CC, #656565
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	; Tile 29
	; Palette 2: #600B62, #730A37, #710F07, #5A1A00
	db %00000000
	db %00000000
	db %00000010
	db %00000010
	db %00000010
	db %10000010
	db %11000010
	db %01000010
	db %00000100
	db %00000110
	db %00000111
	db %00000111
	db %10000111
	db %01000111
	db %00100111
	db %10100111
	; Tile 30
	; Palette 2: #600B62, #730A37, #710F07, #5A1A00
	db %11000010
	db %00000010
	db %00000000
	db %10000000
	db %00000000
	db %10000000
	db %10000000
	db %00000000
	db %00100111
	db %11100111
	db %10000010
	db %11111110
	db %11111110
	db %11000010
	db %11000111
	db %11000000
	; Tile 31
	; Palette 2: #600B62, #730A37, #710F07, #5A1A00
	db %10000000
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	db %11000000
	db %11000000
	db %11100000
	db %11100000
	db %01110000
	db %01110000
	db %00000000
	db %00000000
	; Tile 32
	; Palette 2: #600B62, #730A37, #710F07, #5A1A00
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	db %00000000

	; (Numbers in brackets denote tile #s)
	; tile 33
	db %00000000
	db %00000000
	db %00011100	; "MAN" (0) CUT ONE OFF LEGS K
	db %00111110
	db %00111110
	db %00111110
	db %00111110
	db %00011100
	
	
	db %00000000
	db %00000000
	db %00011100	; "MAN" bp2
	db %00100010
	db %00101010
	db %00100010
	db %00101110
	db %00011100
	
	; tile 34
	db %00111110	; "MAN pt.2" (1)
	db %00111110
	db %00111110
	db %00111110
	db %00111110
	db %00111110
	db %00111110
	db %00100010

	db %01111110	; "MAN pt.2" bp2
	db %11111111
	db %11111111
	db %11111111
	db %11111111
	db %11111111
	db %11111111
	db %11111111
	; tile 35
	db %11101011	; "MAN pt.3" (2)
	db %11101011
	db %00101010
	db %00101010
	db %00111110
	db %00111000
	db %00111100
	db %00111100

	db %00111110	; "MAN pt.3" bp2
	db %00111110
	db %00111110
	db %00111110
	db %00111110
	db %00111110
	db %00111111
	db %00111111
	; tile 36
	db %00000000
	db %01100000
	db %11111100	; "WOMAN" (3) CUT ONE OFF LEGS K
	db %10111110
	db %00111110
	db %00111110
	db %00111110
	db %00011100
	
	
	db %00000000
	db %01100000
	db %11111100	; "WOMAN" bp2
	db %10100010
	db %00101010
	db %00100010
	db %00101110
	db %00011100
	
	; tile 37
	db %00111110	; "WOMAN pt.2" (4)
	db %00111110
	db %00111110
	db %00111110
	db %00111110
	db %00111110
	db %00111110
	db %00100010
	
	db %01111110	; "WOMAN pt.2" bp2
	db %11111111
	db %11111111
	db %11111111
	db %11111111
	db %11111111
	db %11111111
	db %11111111

	; tile 38
	db %11101011	; "WOMAN pt.3" (5)
	db %11101011
	db %00101010
	db %00101010
	db %00111110
	db %00111000
	db %00111100
	db %00111100
	
	db %00111110	; "WOMAN pt.3" bp2
	db %00111110
	db %00111110
	db %00111110
	db %00111110
	db %00111110
	db %00111111
	db %00111111

	; tile 39
	db %00000000
	db %00011100	; "SKELETON HEAD" (6)
	db %00101110
	db %00101110
	db %00010010
	db %00011100
	db %00010000
	db %11100000
	
	db %00000000
	db %00011100
	db %00110010
	db %00111010	; "SKELETON" bp2
	db %00011110
	db %00011100
	db %11010010
	db %11111101

	; tile 40	
	db %10111100	; "Skeleton mid body" (7)
	db %10000000
	db %10010000
	db %10010001	
	db %11000100
	db %10111000
	db %11100000
	db %11100000
	
	db %10111101	; "bitplane2"
	db %10111101
	db %10011101
	db %10010001
	db %11000100
	db %10111000
	db %11100000
	db %11100000

	; tile 41
	db %00100100	; "Skeleton lower body" (8)
	db %00100100
	db %00100100
	db %00100100
	db %00100100
	db %00100100
	db %00100111
	db %00011000
	; tile 42
	db %00100100	; "Skeleton lower bp2"
	db %00100100
	db %00100100
	db %00100100
	db %00100100
	db %00100100
	db %00100111
	db %00011000

	db %00000000	; "Skelly sword" (9)
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	; tile 43
	db %00001000	; "Skelly sword bp2"
	db %00001000
	db %00001000
	db %00001000
	db %00001000
	db %00001000
	db %00001000
	db %00001000

	db %00000000	; "Sword hilt" (A)
	db %00000000
	db %00000000
	db %00000000	
	db %00000000	
	db %00011100	
	db %00000000	
	db %11110000
	; tile 44
	db %00000000	; "hilt bp2"
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	db %00000000
	db %00011000
	db %11111000	

	; Alphabet (A0Z)
    db %00011000 ; A
    db %00100100
    db %00100100
    db %00111100
    db %00100100 ; A5
    db %00100100
    db %00100100
    db %00000000
    db 255,255,255,255,255,255,255,255

    db %00000000 ; B
    db %01110000 
    db %01001000
    db %01001000
    db %01110000 ; B5
    db %01001000
    db %01001000
    db %01110000
    db 255,255,255,255,255,255,255,255

    db %11110000 ; C
    db %10000000 ; 
    db %10000000 ; 
    db %10000000 ; 
    db %10000000 ; 
    db %10000000 ; 
    db %10000000 ; 
    db %11110000 ; 
    db 255,255,255,255,255,255,255,255



    db %00000000
    db %11100000 ; D 
    db %10010000
    db %10010000
    db %10100000
    db %11000000
    db %00000000
    db %00000000
    db 255,255,255,255,255,255,255,255

    db %00000000
    db %01110000 ; E
    db %01000000
    db %01000000
    db %01110000
    db %01000000
    db %01000000
    db %01110000
    db 255,255,255,255,255,255,255,255

    db %00000000
    db %01110000 ; F (moved top row of 1s over one)
    db %01000000
    db %01000000
    db %01110000
    db %01000000
    db %01000000
    db %00000000
    db 255,255,255,255,255,255,255,255


    db %00000000 ; G
    db %00011110
    db %00100000
    db %01000000
    db %01000000
    db %11000110
    db %01000010
    db %00111100
    db 255,255,255,255,255,255,255,255

    ;letter_h
    db %10000001
    db %10000001
    db %10000001 ; H
    db %11111111
    db %10000001
    db %10000001
    db %10000001
    db %00000000
    db $00,$00,$00,$00,$00,$00,$00,$00

    db %00000000 ; I
    db %00111100
    db %00001000
    db %00001000
    db %00001000
    db %00001000
    db %00001000
    db %00111100
    db 0,0,0,0,0,0,0,0
    

    db %00010000 ; J
    db %00010000
    db %00010000
    db %00010000
    db %00010000
    db %00010000
    db %1001000
    db %00110000
    db 0,0,0,0,0,0,0,0

    db %00000000
    db %01000100 ; K
    db %01001000
    db %01010000
    db %01100000
    db %01010000
    db %01001000
    db %00000000
    db 0,0,0,0,0,0,0,0

    db %10000000 ; L
    db %10000000
    db %10000000
    db %10000000
    db %10000000
    db %10000000
    db %10000000
    db %11111110
    db 0,0,0,0,0,0,0,0


    db%10000001 ; M
    db%10100101
    db%10100101
    db%10011001
    db%10011001
    db%10000001
    db%10000001
    db%10000001
    db%00000000
    db%00000000
    db%00000000
    db%00000000
    db%00000000
    db%00000000
    db%00000000
    db%00000000

    db%10000001 ; N
    db%10100001
    db%10110001
    db%10011001
    db%10001101
    db%10000111
    db%10000011
    db%10000001
    db%00000000
    db%00000000
    db%00000000
    db%00000000
    db%00000000
    db%00000000
    db%00000000
    db%00000000

    db %01111110
    db %10000010 ; O
    db %10000010
    db %10000010
    db %10000010
    db %10000010
    db %10000010
    db %01111110
    db 0,0,0,0,0,0,0,0


    db%11110000 ; P
    db%10011000
    db%10011000
    db%10011000
    db%11110000
    db%10000000
    db%10000000
    db%10000000
    db%00000000
    db%00000000
    db%00000000
    db%00000000
    db%00000000
    db%00000000
    db%00000000
    db%00000000

    db %00111100 ;Q
    db %01111110
    db %01100110
    db %01100110
    db %01100110
    db %01100110
    db %01111111
    db %00111101
    db 0, 0, 0, 0, 0, 0, 0, 0
       
       
    db %01111000 ;R
    db %01111100
    db %01100110
    db %01100110
    db %01111000
    db %01101100
    db %01100110
    db %01100110
    db 0, 0, 0, 0, 0, 0, 0, 0
       
       
    db %00111100 ;S
    db %01111110
    db %01100000
    db %00111100
    db %00001100
    db %01100110
    db %01111110
    db %00111100
    db 0, 0, 0, 0, 0, 0, 0, 0



    
    db %00000000 ; T
    db %01111110
    db %00001000
    db %00001000
    db %00001000
    db %00001000
    db %00001000
    db %00001000

    db %00000000
    db %00000000
    db %00000000
    db %00000000
    db %00000000
    db %00000000
    db %00000000
    db %00000000
    ; ... and so on for the rest of the alphabet   
   
    db %01100110 ;U
    db %01100110
    db %01100110
    db %01100110
    db %01100110
    db %01100110
    db %01111110
    db %00111100
    db 0, 0, 0, 0, 0, 0, 0, 0
       

    db %01100110 ;V
    db %01100110
    db %01100110
    db %01100110
    db %01100110
    db %01100110
    db %01111110
    db %00001100
    db 0, 0, 0, 0, 0, 0, 0, 0
       

    db %01100110 ;W
    db %01100110
    db %01100110
    db %01100110
    db %01100110
    db %01100110
    db %01111110
    db %01100110
    db 0, 0, 0, 0, 0, 0, 0, 0


    db %11000011 ; Letter X
    db %11000011
    db %00110011
    db %00001100
    db %00001100
    db %00110011
    db %11000011
    db %11000011
    db $00,$00,$00,$00,$00,$00,$00,$00


    db %11000011 ; Letter Y
    db %11000011
    db %00110011
    db %00001100
    db %00001100
    db %00001100
    db %00001100
    db %00001100
    db $00,$00,$00,$00,$00,$00,$00,$00

    db %11111111 ; Letter Z
    db %00001100
    db %00011000
    db %00110000
    db %01100000
    db %11000000
    db %11000000
    db %11111111
    db $00,$00,$00,$00,$00,$00,$00,$00


sprite_end:
	ds 4096 - (sprite_end - sprite_start)	; Ensure correct size of sprite tiles (4096 bytes)

	
	