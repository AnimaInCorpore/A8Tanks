; =============================================================================
; A8Tanks - artillery duel for the Atari 800 XL, written in 100% assembly.
;
; Two tanks, one hill, wind.  Set angle and power, fire, and blow the other
; tank away (or let the CPU do it).  First to three wins takes the match.
;
;   Joystick left/right : barrel angle       Joystick up/down : shot power
;   Fire button         : shoot              SELECT : 1/2 players (title)
;   START / fire        : begin match (title)
;
; The program never calls the OS: it switches the OS ROM (and BASIC) off,
; installs its own NMI vector and drives ANTIC/GTIA/POKEY/PIA directly.
;
; Generated blocks (do not edit by hand):
;   TITLE SCREEN  node tools/generate_start_screen.js
;   FONT, TABLES, GAME DISPLAY LIST  node tools/generate_assets.js
; =============================================================================

; ---- hardware ---------------------------------------------------------------
HPOSP0 = $D000
SIZEP0 = $D008
SIZEP3 = $D00B
TRIG0  = $D010
TRIG1  = $D011
COLPM0 = $D012
COLPM1 = $D013
COLPM2 = $D014
COLPM3 = $D015
COLPF0 = $D016
COLPF1 = $D017
COLPF2 = $D018
COLBK  = $D01A
PRIOR  = $D01B
GRACTL = $D01D
CONSOL = $D01F

AUDF1  = $D200
AUDC1  = $D201
AUDCTL = $D208
IRQEN  = $D20E
SKCTL  = $D20F

PORTA  = $D300
PORTB  = $D301
PACTL  = $D302
PBCTL  = $D303

DMACTL = $D400
CHACTL = $D401
DLISTL = $D402
DLISTH = $D403
PMBASE = $D407
CHBASE = $D409
WSYNC  = $D40A
NMIEN  = $D40E
NMIST  = $D40F
NMIRES = $D40F

; ---- memory map ---------------------------------------------------------------
; $2000-$5FFF  code, tables, variables
; $6000-$7F9F  game bitmap (ANTIC E, 40 bytes/line, 200 lines in two 4K-safe halves)
; $8000-$AB7F  title screen (display list, bitmap, per-line palettes)
; $B000-$B7FF  player/missile RAM (2K, single line)      $B800 character set
SCREEN_A = $6000
SCREEN_B = $7000
SCREEN_END = $8000
PM_BASE_HI = $B0
PM_P0    = $B400
PM_P2    = $B600
PM_P3    = $B700

PLAY_ROWS = 200
PM_Y0    = 32               ; player RAM index of bitmap line 0
HPOS0    = 48               ; horizontal position of bitmap column 0

; ---- game constants -------------------------------------------------------------
GRAVITY  = 13               ; 8.8 fixed point pixels/frame^2
BARREL_MAX = 9
TANK_H   = 6
KILL_DIST = 11
WIN_SCORE = 3

; ---- zero page --------------------------------------------------------------
FRAME    = $80              ; incremented by every VBI
GMODE    = $81              ; 0 = title, 1 = game (selects VBI/DLI behaviour)
DLIIDX   = $82
DMASH    = $83              ; DMACTL value copied every VBI (0 blanks the screen)
DLIVEC   = $84              ; +1
RSEED    = $86              ; +1
PTR      = $88              ; +1
PTR2     = $8A              ; +1
T0       = $8C
T1       = $8D
T2       = $8E
T3       = $8F
T4       = $90
T5       = $91
T6       = $92
RESL     = $93
RESH     = $94
PX       = $95
PY       = $96
RCLO     = $97
RCHI     = $98
WINDL    = $99
WINDH    = $9A
WIND     = $9B
TURN     = $9C
NPLAYERS = $9D
ROUNDNO  = $9E
SXL      = $9F
SXH      = $A0
SYL      = $A1
SYH      = $A2
VXL      = $A3
VXH      = $A4
VYL      = $A5
VYH      = $A6
STEPN    = $A7
IMPX     = $A8
IMPY     = $A9
SHOOTER  = $AA
BCX      = $AB
BSY      = $AC
BNEG     = $AD
BMODE    = $AE
BT       = $AF
BPX0     = $B0
BPY0     = $B1
BAXL     = $B2
BAXH     = $B3
BAYL     = $B4
BAYH     = $B5
BK       = $B6
CX       = $B7
CXEND    = $B8
INP      = $B9
MOVECNT  = $BA
HELDN    = $BB
SFXTIME  = $BC
SFXFRQ   = $BD
SFXSLIDE = $BE
SFXCTL   = $BF
SFXSHIFT = $C0
SHYOLD   = $C1
FBI      = $C2
FBX      = $C3
FBY      = $C4
AI_S     = $C5
AI_T     = $C6
AI_TX    = $C7
AI_DIR   = $C8
AI_LO    = $C9
AI_HI    = $CA
AI_IT    = $CB
AI_BEST  = $CC
AI_BA    = $CD
AI_BP    = $CE
AI_C     = $CF
AI_JIT   = $D0
SIMCNT   = $D1
TITLE_SEL = $D2
DIEDMASK = $D3
EXI      = $D4

; ---- variables (uninitialised RAM) ------------------------------------------------
.ORG $5000
HEIGHT:   .DS 160           ; ground surface line per column (200 = no ground)
CPTS:     .DS 12
ROWLO:    .DS PLAY_ROWS
ROWHI:    .DS PLAY_ROWS
TX:       .DS 2             ; tank centre column
TG:       .DS 2             ; ground line under the tank
ANG:      .DS 2             ; barrel angle, 0..180 degrees
POW:      .DS 2
ALIVE:    .DS 2
SCORE:    .DS 2

.ORG $5400
TEXTBUF:  .DS 120           ; HUD rows 0/1 (80 bytes), title prompt (40 bytes)
HUD_ROW0 = TEXTBUF
HUD_ROW1 = TEXTBUF+40
TITLE_TEXT = TEXTBUF+80

; =============================================================================
; Start-up
; =============================================================================
.ORG $2000

START:
  SEI
  CLD
  LDX #$FF
  TXS
  LDA #$00
  STA NMIEN
  STA IRQEN
  STA DMACTL
  STA GRACTL

  ; PIA: joystick ports are inputs, PORTB bits are outputs
  LDA #$38
  STA PACTL
  STA PBCTL
  LDA #$00
  STA PORTA
  LDA #$FF
  STA PORTB
  LDA #$3C
  STA PACTL
  STA PBCTL
  LDA #$FE                 ; OS ROM off, BASIC off, self test off
  STA PORTB

  ; the OS ROM is gone, so vectors live in RAM now
  LDA #<NMI
  STA $FFFA
  LDA #>NMI
  STA $FFFB
  LDA #<START
  STA $FFFC
  LDA #>START
  STA $FFFD
  LDA #<IRQ
  STA $FFFE
  LDA #>IRQ
  STA $FFFF

  LDA #$00
  STA AUDCTL
  LDA #$03
  STA SKCTL

  LDA #PM_BASE_HI
  STA PMBASE
  LDA #>CHARSET
  STA CHBASE
  LDA #$02
  STA CHACTL
  LDA #$01
  STA PRIOR

  LDA #$A5
  STA RSEED
  LDA #$5A
  STA RSEED+1
  LDA #1
  STA NPLAYERS
  LDA #0
  STA GMODE
  STA DMASH
  STA SFXTIME
  STA FRAME
  JSR BUILD_TABLES

  LDA #$C0                 ; DLI + VBI
  STA NMIEN

  JMP MAIN

IRQ:
  RTI

; =============================================================================
; Interrupts
; =============================================================================
NMI:
  BIT NMIST
  BPL VBI
  JMP (DLIVEC)

VBI:
  PHA
  TXA
  PHA
  TYA
  PHA
  STA NMIRES
  INC FRAME
  LDA DMASH
  STA DMACTL
  LDA GMODE
  BNE VBI_GAME

  LDA #<TITLE_DISPLAY_LIST
  STA DLISTL
  LDA #>TITLE_DISPLAY_LIST
  STA DLISTH
  LDA #<TITLE_DLI
  STA DLIVEC
  LDA #>TITLE_DLI
  STA DLIVEC+1
  LDA #TITLE_COLBK0
  STA COLBK
  LDA #TITLE_PF0_0
  STA COLPF0
  LDA #TITLE_PF1_0
  STA COLPF1
  LDA #TITLE_PF2_0
  STA COLPF2
  JMP VBI_SOUND

VBI_GAME:
  LDA #<GAME_DL
  STA DLISTL
  LDA #>GAME_DL
  STA DLISTH
  LDA #<GAME_DLI
  STA DLIVEC
  LDA #>GAME_DLI
  STA DLIVEC+1
  LDA #0
  STA DLIIDX
  LDA #HUD_BG              ; HUD text: hue from COLPF2, luminance from COLPF1
  STA COLPF2
  STA COLBK
  LDA #$0E
  STA COLPF1

VBI_SOUND:
  LDA SFXTIME
  BEQ VS_OFF
  DEC SFXTIME
  LDA SFXTIME
  LDX SFXSHIFT
  BEQ VS_VOL
VS_SHIFT:
  LSR A
  DEX
  BNE VS_SHIFT
VS_VOL:
  CMP #16
  BCC VS_SET
  LDA #15
VS_SET:
  ORA SFXCTL
  STA AUDC1
  LDA SFXFRQ
  STA AUDF1
  CLC
  ADC SFXSLIDE
  STA SFXFRQ
  JMP VS_DONE
VS_OFF:
  LDA #0
  STA AUDC1
VS_DONE:
  PLA
  TAY
  PLA
  TAX
  PLA
  RTI

; Title: every scanline of the bitmap gets its own palette.
TITLE_DLI:
  PHA
  TXA
  PHA
  LDX #0
TD_LOOP:
  STA WSYNC
  LDA TITLE_COLBK,X
  STA COLBK
  LDA TITLE_PF0,X
  STA COLPF0
  LDA TITLE_PF1,X
  STA COLPF1
  LDA TITLE_PF2,X
  STA COLPF2
  INX
  CPX #TITLE_ROWS
  BNE TD_LOOP
  STA WSYNC                ; text row: white on black
  LDA #$00
  STA COLBK
  STA COLPF2
  LDA #$0E
  STA COLPF1
  PLA
  TAX
  PLA
  RTI

; Game: first DLI (end of the HUD) switches to the playfield palette, later
; DLIs step the sky/ground gradient down the screen.
GAME_DLI:
  PHA
  TXA
  PHA
  LDX DLIIDX
  LDA SKY_COLORS,X
  STA WSYNC
  STA COLBK
  LDA GROUND_COLORS,X
  STA COLPF0
  INC DLIIDX
  CPX #0
  BNE GD_END
  LDA #PAL_BARREL
  STA COLPF1
  LDA #PAL_GRASS
  STA COLPF2
GD_END:
  PLA
  TAX
  PLA
  RTI

; =============================================================================
; Main flow
; =============================================================================
MAIN:
  JSR TITLE
  LDA #0
  STA SCORE
  STA SCORE+1
  STA ROUNDNO
  LDA #45
  STA ANG
  LDA #135
  STA ANG+1
  LDA #60
  STA POW
  STA POW+1

MATCH_LOOP:
  JSR NEW_ROUND
  JSR PLAY_ROUND
  JSR ROUND_END
  BNE MAIN
  INC ROUNDNO
  JMP MATCH_LOOP

; Wait for the next vertical blank.
WAIT_FRAME:
  LDA FRAME
WF1:
  CMP FRAME
  BEQ WF1
  RTS

; Wait X frames.
WAIT_FRAMES:
  JSR WAIT_FRAME
  DEX
  BNE WAIT_FRAMES
  RTS

; =============================================================================
; Title screen
; =============================================================================
TITLE:
  LDA #0
  STA GMODE
  STA GRACTL
  STA SFXTIME
  LDA #$22
  STA DMASH
  LDA #0
  STA TITLE_SEL
  JSR DRAW_TITLE_TEXT

  ; let go of START/fire before accepting a new one
TT_REL:
  JSR WAIT_FRAME
  JSR START_PRESSED
  BNE TT_REL

TT_LOOP:
  JSR WAIT_FRAME
  LDA CONSOL
  AND #$02
  BNE TT_NOSEL
  LDA TITLE_SEL            ; SELECT toggles once per press
  BNE TT_START
  LDA #1
  STA TITLE_SEL
  LDA NPLAYERS
  EOR #3                   ; 1 <-> 2
  STA NPLAYERS
  JSR DRAW_TITLE_TEXT
  LDA #SFX_TICK
  JSR PLAY_SFX
  JMP TT_START
TT_NOSEL:
  LDA #0
  STA TITLE_SEL
TT_START:
  JSR START_PRESSED
  BEQ TT_LOOP

  LDA FRAME                ; stir the random seed with the time spent here
  EOR RSEED
  STA RSEED
  LDA FRAME
  ASL A
  EOR RSEED+1
  ORA #$01
  STA RSEED+1
  RTS

; Z clear when START or a fire button is down.
START_PRESSED:
  LDA CONSOL
  AND #$01
  BEQ SP_YES
  LDA TRIG0
  AND TRIG1
  AND #$01
  BEQ SP_YES
  LDA #0
  RTS
SP_YES:
  LDA #1
  RTS

DRAW_TITLE_TEXT:
  LDX #39
DT_CLR:
  LDA #$20
  STA TITLE_TEXT,X
  DEX
  BPL DT_CLR
  LDA NPLAYERS
  CMP #1
  BNE DT_2P
  LDA #<MSG_1P
  LDY #>MSG_1P
  JMP DT_PUT
DT_2P:
  LDA #<MSG_2P
  LDY #>MSG_2P
DT_PUT:
  LDX #80+1
  JSR PUTS
  LDA #<MSG_SELECT
  LDY #>MSG_SELECT
  LDX #80+18
  JSR PUTS
  LDA #<MSG_START
  LDY #>MSG_START
  LDX #80+32
  JSR PUTS
  RTS

; =============================================================================
; Text helpers (TEXTBUF is the destination, X = offset)
; =============================================================================
PUTS:                       ; A/Y = zero terminated string
  STA PTR2
  STY PTR2+1
  LDY #0
PS1:
  LDA (PTR2),Y
  BEQ PS2
  STA TEXTBUF,X
  INX
  INY
  BNE PS1
PS2:
  RTS

PUTNUM3:                    ; A = 0..255 as three digits
  STA T0
  LDY #$30
PN1:
  LDA T0
  CMP #100
  BCC PN2
  SEC
  SBC #100
  STA T0
  INY
  BNE PN1
PN2:
  TYA
  STA TEXTBUF,X
  INX
  LDY #$30
PN3:
  LDA T0
  CMP #10
  BCC PN4
  SEC
  SBC #10
  STA T0
  INY
  BNE PN3
PN4:
  TYA
  STA TEXTBUF,X
  INX
  LDA T0
  CLC
  ADC #$30
  STA TEXTBUF,X
  RTS

; =============================================================================
; Random numbers (16-bit Galois LFSR, 8 steps per call)
; =============================================================================
RND:
  STX T6
  LDX #8
RND1:
  ASL RSEED
  ROL RSEED+1
  BCC RND2
  LDA RSEED
  EOR #$2D
  STA RSEED
RND2:
  DEX
  BNE RND1
  LDX T6
  LDA RSEED
  EOR RSEED+1
  RTS

; A = random number 0..(A-1), A >= 1
RND_RANGE:
  STA T5
  SEC
  SBC #1
  STA T4                   ; smear n-1 into a bit mask
  LSR A
  ORA T4
  STA T4
  LSR A
  LSR A
  ORA T4
  STA T4
  LSR A
  LSR A
  LSR A
  LSR A
  ORA T4
  STA T4
RR1:
  JSR RND
  AND T4
  CMP T5
  BCS RR1
  RTS

; =============================================================================
; Bitmap primitives (mode E: 4 pixels/byte, colours 0..3)
;   0 = sky (COLBK)  1 = dirt (COLPF0)  2 = barrel (COLPF1)  3 = grass (COLPF2)
; =============================================================================
COL_SKY    = 0              ; pixel values
COL_DIRT   = 1
PAL_BARREL = $00            ; COLPF1/COLPF2 palette values (see GAME_DLI)
PAL_GRASS  = $C6
HUD_BG     = $72

BUILD_TABLES:
  LDA #<SCREEN_A
  STA PTR
  LDA #>SCREEN_A
  STA PTR+1
  LDX #0
BT1:
  CPX #100
  BNE BT2
  LDA #<SCREEN_B
  STA PTR
  LDA #>SCREEN_B
  STA PTR+1
BT2:
  LDA PTR
  STA ROWLO,X
  LDA PTR+1
  STA ROWHI,X
  CLC
  LDA PTR
  ADC #40
  STA PTR
  BCC BT3
  INC PTR+1
BT3:
  INX
  CPX #PLAY_ROWS
  BNE BT1
  RTS

CLEAR_SCREEN:
  LDA #<SCREEN_A
  STA PTR
  LDA #>SCREEN_A
  STA PTR+1
  LDA #0
  TAY
CS1:
  STA (PTR),Y
  INY
  BNE CS1
  INC PTR+1
  LDX PTR+1
  CPX #>SCREEN_END
  BNE CS1
  RTS

; Colour of the pixel at PX,PY according to the height map -> A (0..3)
BGCOLOR:
  LDX PX
  LDA PY
  SEC
  SBC HEIGHT,X
  BCC BG_SKY
  CMP #2
  BCC BG_GRASS
  LDA #COL_DIRT
  RTS
BG_GRASS:
  LDA #3
  RTS
BG_SKY:
  LDA #COL_SKY
  RTS

; Plot colour A at PX,PY
PLOT:
  STA T2
  LDX PY
  LDA ROWLO,X
  STA PTR
  LDA ROWHI,X
  STA PTR+1
  LDA PX
  LSR A
  LSR A
  TAY
  LDA PX
  AND #3
  TAX
  LDA POSMASK,X
  STA T0
  EOR #$FF
  AND (PTR),Y
  STA T1
  LDX T2
  LDA COLPAT,X
  AND T0
  ORA T1
  STA (PTR),Y
  RTS

POSMASK:
  .BYTE $C0,$30,$0C,$03
COLPAT:
  .BYTE $00,$55,$AA,$FF

; Redraw column PX for lines RCLO..RCHI-1 from the height map
REDRAW_COLUMN:
  LDA PX
  LSR A
  LSR A
  STA T2                   ; byte offset in the line
  LDA PX
  AND #3
  TAX
  LDA POSMASK,X
  STA T3
  EOR #$FF
  STA T4
  LDX PX
  LDA HEIGHT,X
  STA T5
  LDX RCLO
RC1:
  CPX RCHI
  BCS RC_DONE
  TXA
  SEC
  SBC T5
  BCC RC_SKY
  CMP #2
  BCC RC_GRASS
  LDA #$55
  JMP RC_PUT
RC_GRASS:
  LDA #$FF
  JMP RC_PUT
RC_SKY:
  LDA #$00
RC_PUT:
  AND T3
  STA T6
  LDA ROWLO,X
  STA PTR
  LDA ROWHI,X
  STA PTR+1
  LDY T2
  LDA (PTR),Y
  AND T4
  ORA T6
  STA (PTR),Y
  INX
  JMP RC1
RC_DONE:
  RTS

DRAW_TERRAIN:
  LDA #0
  STA CX
DTR1:
  LDX CX
  STX PX
  LDA HEIGHT,X
  STA RCLO
  LDA #PLAY_ROWS
  STA RCHI
  JSR REDRAW_COLUMN
  INC CX
  LDA CX
  CMP #160
  BNE DTR1
  RTS

; =============================================================================
; Terrain generation
; =============================================================================
GEN_TERRAIN:
  ; random walk of 11 control points, one every 16 columns
  LDA #140
  STA T0
  LDX #0
GT1:
  STX T1
  LDA #64
  JSR RND_RANGE
  SEC
  SBC #32
  CLC
  ADC T0
  CMP #100
  BCS GT1A
  LDA #100
GT1A:
  CMP #181
  BCC GT1B
  LDA #180
GT1B:
  STA T0
  LDX T1
  STA CPTS,X
  INX
  CPX #11
  BNE GT1

  ; linear interpolation between control points (8.8 fixed point)
  LDA #0
  STA CX                   ; segment
  STA CXEND                ; column
GT2:
  LDX CX
  LDA CPTS+1,X
  SEC
  SBC CPTS,X               ; signed delta
  STA T0
  LDA #0
  BIT T0
  BPL GT3
  LDA #$FF
GT3:
  STA T1                   ; sign extension
  LDX #4                   ; step = delta * 16
GT4:
  ASL T0
  ROL T1
  DEX
  BNE GT4
  LDA #0
  STA T2                   ; accumulator low
  LDX CX
  LDA CPTS,X
  STA T3                   ; accumulator high
  LDY #16
GT5:
  LDX CXEND
  LDA T3
  STA HEIGHT,X
  INC CXEND
  CLC
  LDA T2
  ADC T0
  STA T2
  LDA T3
  ADC T1
  STA T3
  DEY
  BNE GT5
  INC CX
  LDA CX
  CMP #10
  BNE GT2

  ; two smoothing passes
  LDA #2
  STA T4
GT6:
  LDA HEIGHT
  STA T0                   ; previous (unsmoothed) height
  LDX #1
GT7:
  LDA HEIGHT,X
  STA T1
  LDA T0
  CLC
  ADC HEIGHT+1,X
  ROR A
  CLC
  ADC HEIGHT,X
  ROR A
  STA HEIGHT,X
  LDA T1
  STA T0
  INX
  CPX #159
  BNE GT7
  DEC T4
  BNE GT6
  RTS

; =============================================================================
; New round: terrain, tanks, wind, screen
; =============================================================================
NEW_ROUND:
  LDA #0
  STA DMASH                ; blank while drawing
  STA GRACTL
  LDA #1
  STA GMODE
  JSR WAIT_FRAME
  JSR WAIT_FRAME

  JSR CLEAR_SCREEN
  LDX #0
  LDA #0
NR_PM:
  STA PM_P0,X
  STA PM_P0+$100,X
  STA PM_P0+$200,X
  STA PM_P0+$300,X
  INX
  BNE NR_PM
  STA SHYOLD

  JSR GEN_TERRAIN
  LDA #32
  JSR RND_RANGE
  CLC
  ADC #12
  STA TX
  LDA #32
  JSR RND_RANGE
  CLC
  ADC #116
  STA TX+1

  LDA #8
  JSR RND_RANGE
  TAX
  LDA WIND_TAB,X
  STA WIND
  JSR SET_WIND

  LDA #1
  STA ALIVE
  STA ALIVE+1
  LDA ROUNDNO
  AND #1
  STA TURN
  LDA #6
  STA AI_JIT

  JSR DRAW_TERRAIN
  LDX #0
  JSR PLACE_TANK
  LDX #1
  JSR PLACE_TANK

  ; sprite set-up
  LDA #0
  LDX #7
NR_HP:
  STA HPOSP0,X
  DEX
  BPL NR_HP
  STA SIZEP0
  STA SIZEP0+1
  STA SIZEP0+2
  LDA #1
  STA SIZEP3
  LDA #$02                 ; players only
  STA GRACTL
  LDA #$0F
  STA COLPM2
  LDX #0
  JSR DRAW_TANK
  LDX #1
  JSR DRAW_TANK
  LDX #0
  LDA #1
  JSR BARREL
  LDX #1
  LDA #1
  JSR BARREL

  JSR UPDATE_HUD
  LDA #$3A                 ; DL, players, single line, normal width
  STA DMASH
  LDX #20
  JSR WAIT_FRAMES
  RTS

WIND_TAB:
  .BYTE $FB,$FD,$FE,$00,$00,$02,$03,$05

SET_WIND:                   ; WINDL/WINDH from the signed WIND
  LDA WIND
  STA WINDL
  LDA #0
  BIT WIND
  BPL SW1
  LDA #$FF
SW1:
  STA WINDH
  RTS

; Flatten the 8 columns under tank X to the height at its centre
PLACE_TANK:
  STX BT
  LDA TX,X
  TAY
  LDA HEIGHT,Y
  STA TG,X
  STA T0                   ; new level
  TYA
  SEC
  SBC #4
  STA CX
  LDA #8
  STA CXEND
PT1:
  LDX CX
  LDA HEIGHT,X
  CMP T0
  BEQ PT2
  BCC PT_LOWER
  STA RCHI                 ; ground was lower: raise it to the new level
  LDA T0
  STA RCLO
  JMP PT_GO
PT_LOWER:
  STA RCLO                 ; ground was higher: cut it down
  LDA T0
  STA RCHI
PT_GO:
  LDA T0
  STA HEIGHT,X
  STX PX
  JSR REDRAW_COLUMN
PT2:
  INC CX
  DEC CXEND
  BNE PT1
  LDX BT
  RTS

; =============================================================================
; Tanks (players 0/1 in player RAM) and barrels (bitmap)
; =============================================================================
DRAW_TANK:                  ; X = tank
  STX BT
  TXA
  CLC
  ADC #>PM_P0
  STA PTR+1
  LDA #0
  STA PTR
  TAY
DTK1:
  STA (PTR),Y
  INY
  BNE DTK1
  LDX BT
  LDA TG,X
  CLC
  ADC #PM_Y0-TANK_H
  TAY
  LDA #0
  STA T0
  LDA ALIVE,X
  BNE DTK2
  LDA #TANK_H
  STA T0
DTK2:
  LDA T0
  CLC
  ADC #TANK_H
  STA T1
DTK3:
  LDX T0
  LDA TANK_SHAPES,X
  STA (PTR),Y
  INY
  INC T0
  LDA T0
  CMP T1
  BNE DTK3
  LDX BT
  LDA TX,X
  CLC
  ADC #HPOS0-4
  STA HPOSP0,X
  LDA TANK_COLORS,X
  LDY ALIVE,X
  BNE DTK4
  LDA #$04
DTK4:
  STA COLPM0,X
  RTS

TANK_SHAPES:
  .BYTE $18,$3C,$FF,$FF,$DB,$7E     ; tank
  .BYTE $00,$00,$24,$7E,$FF,$FF     ; wreck
TANK_COLORS:
  .BYTE $CA,$3A

; Barrel direction from the angle of tank X: BCX/BSY = 255*cos/sin, BNEG for > 90
BARREL_VEC:
  LDA ANG,X
  LDY #0
  STY BNEG
  CMP #91
  BCC BV1
  STA T0
  LDA #180
  SEC
  SBC T0
  LDY #$FF
  STY BNEG
BV1:
  TAY
  LDA COS_TABLE,Y
  STA BCX
  STY T0
  LDA #90
  SEC
  SBC T0
  TAY
  LDA COS_TABLE,Y
  STA BSY
  RTS

; Draw (A=1) or erase (A=0) the barrel of tank X
BARREL:
  STA BMODE
  STX BT
  JSR BARREL_VEC
  LDX BT
  LDA TX,X
  STA BPX0
  LDA TG,X
  SEC
  SBC #5
  STA BPY0
  LDA #0
  STA BAXL
  STA BAXH
  STA BAYL
  STA BAYH
  STA BK
BL1:
  INC BK
  CLC
  LDA BAXL
  ADC BCX
  STA BAXL
  BCC BL2
  INC BAXH
BL2:
  CLC
  LDA BAYL
  ADC BSY
  STA BAYL
  BCC BL3
  INC BAYH
BL3:
  LDA BK
  CMP #3
  BCC BL_NEXT
  LDA BNEG
  BEQ BL4
  LDA BPX0
  SEC
  SBC BAXH
  JMP BL5
BL4:
  LDA BPX0
  CLC
  ADC BAXH
BL5:
  STA PX
  LDA BPY0
  SEC
  SBC BAYH
  STA PY
  LDA BMODE
  BEQ BL_ERASE
  LDA #2
  JSR PLOT
  JMP BL_NEXT
BL_ERASE:
  JSR BGCOLOR
  JSR PLOT
BL_NEXT:
  LDA BK
  CMP #BARREL_MAX
  BNE BL1
  LDX BT
  RTS

; =============================================================================
; HUD
; =============================================================================
UPDATE_HUD:
  LDX #79
UH_CLR:
  LDA #$20
  STA TEXTBUF,X
  DEX
  BPL UH_CLR
  LDA #<MSG_P1
  LDY #>MSG_P1
  LDX #1
  JSR PUTS
  LDA #<MSG_P2
  LDY #>MSG_P2
  LDX #35
  JSR PUTS
  LDA SCORE
  CLC
  ADC #$30
  STA HUD_ROW0+4
  LDA SCORE+1
  CLC
  ADC #$30
  STA HUD_ROW0+38
  LDA #<MSG_WIND
  LDY #>MSG_WIND
  LDX #15
  JSR PUTS
  LDA WIND
  BNE UH_W1
  LDA #$30                 ; calm
  STA HUD_ROW0+21
  JMP UH_W4
UH_W1:
  BMI UH_WNEG
  LDY WIND
  LDA #$3E                 ; '>' per wind step
  JMP UH_WFILL
UH_WNEG:
  LDA #0
  SEC
  SBC WIND
  TAY
  LDA #$3C                 ; '<'
UH_WFILL:
  LDX #0
UH_WL:
  STA HUD_ROW0+21,X
  INX
  DEY
  BNE UH_WL
UH_W4:
  ; row 1: angle / power of the tank whose turn it is
  LDA #<MSG_ANGLE
  LDY #>MSG_ANGLE
  LDX #40+1
  JSR PUTS
  LDA #<MSG_POWER
  LDY #>MSG_POWER
  LDX #40+14
  JSR PUTS
  LDX TURN
  LDA ANG,X
  LDX #40+7
  JSR PUTNUM3
  LDX TURN
  LDA POW,X
  LDX #40+20
  JSR PUTNUM3
  ; highlight the active player
  LDA TURN
  BNE UH_H1
  LDX #1
  JMP UH_H2
UH_H1:
  LDX #35
UH_H2:
  LDY #4
UH_H3:
  LDA TEXTBUF,X
  ORA #$80
  STA TEXTBUF,X
  INX
  DEY
  BNE UH_H3
  RTS

; Put message A/Y in the message field (columns 26..39) of HUD row 1
HUD_MESSAGE:
  PHA
  TYA
  PHA
  LDA #$20
  LDX #26
HM1:
  STA HUD_ROW1,X
  INX
  CPX #40
  BNE HM1
  PLA
  TAY
  PLA
  LDX #40+26
  JMP PUTS

; =============================================================================
; Sound effects (POKEY channel 1, stepped from the VBI)
; =============================================================================
SFX_TICK = 0
SFX_FIRE = 1
SFX_BOOM = 2
SFX_WIN  = 3

PLAY_SFX:                   ; A = effect
  ASL A
  ASL A
  ASL A
  TAX
  LDA SFX_TABLE,X
  STA SFXFRQ
  LDA SFX_TABLE+1,X
  STA SFXSLIDE
  LDA SFX_TABLE+2,X
  STA SFXCTL
  LDA SFX_TABLE+3,X
  STA SFXSHIFT
  LDA SFX_TABLE+4,X
  STA SFXTIME
  RTS

; freq, slide, control, volume shift, frames, pad
SFX_TABLE:
  .BYTE 60,0,$A0,0,6,0,0,0
  .BYTE 30,4,$A0,1,24,0,0,0
  .BYTE 24,3,$80,2,50,0,0,0
  .BYTE 40,254,$A0,2,40,0,0,0

; =============================================================================
; Input
; =============================================================================
; bit0 up, bit1 down, bit2 left, bit3 right, bit4 fire (1 = active), either stick
READ_INPUT:
  LDA PORTA
  STA T0
  LSR A
  LSR A
  LSR A
  LSR A
  AND T0
  EOR #$0F
  AND #$0F
  STA T0
  LDA TRIG0
  AND TRIG1
  AND #$01
  BNE RI1
  LDA T0
  ORA #$10
  RTS
RI1:
  LDA T0
  RTS

; =============================================================================
; A turn
; =============================================================================
PLAY_ROUND:
PR_TURN:
  JSR UPDATE_HUD
  LDA NPLAYERS
  CMP #1
  BNE PR_HUMAN
  LDA TURN
  BEQ PR_HUMAN
  LDA #<MSG_CPU
  LDY #>MSG_CPU
  JSR HUD_MESSAGE
  JSR CPU_AIM
  JMP PR_FIRE
PR_HUMAN:
  LDA #<MSG_AIM
  LDY #>MSG_AIM
  JSR HUD_MESSAGE
  JSR HUMAN_AIM
PR_FIRE:
  LDA #<MSG_FIRE
  LDY #>MSG_FIRE
  JSR HUD_MESSAGE
  JSR FIRE_SHELL
  BNE PR_HIT
  LDA #<MSG_MISS
  LDY #>MSG_MISS
  JSR HUD_MESSAGE
  LDX #30
  JSR WAIT_FRAMES
  JMP PR_NEXT
PR_HIT:
  JSR EXPLODE
  LDA ALIVE
  AND ALIVE+1
  BEQ PR_OVER
PR_NEXT:
  LDA TURN
  EOR #1
  STA TURN
  ; the wind drifts a little between shots
  LDA #4
  JSR RND_RANGE
  TAX
  LDA WIND
  CLC
  ADC WIND_DRIFT,X
  CMP #6
  BNE PR_W1
  LDA #5
PR_W1:
  CMP #$FA
  BNE PR_W2
  LDA #$FB
PR_W2:
  STA WIND
  JSR SET_WIND
  JMP PR_TURN
PR_OVER:
  RTS

WIND_DRIFT:
  .BYTE $FF,$00,$00,$01

; ---- human aiming ---------------------------------------------------------
HUMAN_AIM:
HA_REL:
  JSR WAIT_FRAME
  JSR READ_INPUT
  AND #$10
  BNE HA_REL
  LDA #0
  STA MOVECNT
  STA HELDN
HA_LOOP:
  JSR WAIT_FRAME
  JSR READ_INPUT
  STA INP
  AND #$10
  BEQ HA_NOFIRE
  RTS
HA_NOFIRE:
  LDA INP
  AND #$0F
  BNE HA_MOVE
  LDA #0
  STA MOVECNT
  STA HELDN
  JMP HA_LOOP
HA_MOVE:
  LDA MOVECNT
  BEQ HA_ACT
  DEC MOVECNT
  JMP HA_LOOP
HA_ACT:
  LDA HELDN
  BNE HA_RPT
  LDA #12                  ; first repeat comes after a short delay
  BNE HA_SET
HA_RPT:
  LDA #2
  LDY HELDN
  CPY #8
  BCC HA_SET
  LDA #0                   ; held for a while: every frame
HA_SET:
  STA MOVECNT
  LDA HELDN
  CMP #200
  BCS HA_APPLY
  INC HELDN
HA_APPLY:
  LDX TURN
  LDA #0
  JSR BARREL               ; erase old barrel
  LDX TURN
  LDA INP
  LSR A
  BCC HA_NUP
  LDY POW,X
  CPY #100
  BCS HA_NUP
  INC POW,X
HA_NUP:
  LSR A
  BCC HA_NDN
  LDY POW,X
  CPY #6
  BCC HA_NDN
  DEC POW,X
HA_NDN:
  LSR A
  BCC HA_NLT
  LDY ANG,X
  CPY #180
  BCS HA_NLT
  INC ANG,X
HA_NLT:
  LSR A
  BCC HA_NRT
  LDY ANG,X
  BEQ HA_NRT
  DEC ANG,X
HA_NRT:
  LDA #1
  JSR BARREL
  JSR UPDATE_HUD
  LDA #<MSG_AIM
  LDY #>MSG_AIM
  JSR HUD_MESSAGE
  LDA SFXTIME
  BEQ HA_CLICK
  JMP HA_LOOP
HA_CLICK:
  LDA #SFX_TICK
  JSR PLAY_SFX
  JMP HA_LOOP

; ---- CPU aiming: binary-search the power for a few angles by simulation ------
AI_ANGLES:
  .BYTE 30,45,60,75,150,135,120,105

CPU_AIM:
  LDX #40
  JSR WAIT_FRAMES
  LDA TURN
  STA AI_S
  EOR #1
  STA AI_T
  TAY
  LDA TX,Y
  STA AI_TX
  LDX AI_S
  LDA #0
  STA AI_DIR               ; 0: target lies to the right
  LDA AI_TX
  CMP TX,X
  BCS CA_DIR
  LDA #4
  STA AI_DIR
CA_DIR:
  LDA #255
  STA AI_BEST
  LDA #0
  STA AI_C
CA_ANGLE:
  LDA AI_DIR
  CLC
  ADC AI_C
  TAY
  LDA AI_ANGLES,Y
  LDX AI_S
  STA ANG,X
  LDA #5
  STA AI_LO
  LDA #100
  STA AI_HI
  LDA #7
  STA AI_IT
CA_BS:
  LDA AI_LO
  CLC
  ADC AI_HI
  LSR A
  LDX AI_S
  STA POW,X
  JSR SIMULATE
  CMP AI_TX
  BEQ CA_EXACT
  BCS CA_LANDGT
  ; landed short of the target
  LDA AI_DIR
  BNE CA_TOOFAR            ; shooting left: short of it means too much power
  JMP CA_MORE
CA_LANDGT:
  LDA AI_DIR
  BNE CA_MORE              ; shooting left: beyond the target means more power
  ; shooting right: beyond the target means less power
CA_TOOFAR:
  LDX AI_S
  LDA POW,X
  STA AI_HI
  JMP CA_NEXT
CA_MORE:
  LDX AI_S
  LDA POW,X
  STA AI_LO
  JMP CA_NEXT
CA_EXACT:
  LDX AI_S
  LDA POW,X
  STA AI_LO
  STA AI_HI
CA_NEXT:
  DEC AI_IT
  BNE CA_BS
  LDX AI_S
  LDA AI_LO
  STA POW,X
  JSR SIMULATE
  SEC
  SBC AI_TX
  BCS CA_ABS
  EOR #$FF
  CLC
  ADC #1
CA_ABS:
  CMP AI_BEST
  BCS CA_KEEP
  STA AI_BEST
  LDX AI_S
  LDA ANG,X
  STA AI_BA
  LDA POW,X
  STA AI_BP
CA_KEEP:
  INC AI_C
  LDA AI_C
  CMP #4
  BEQ CA_DONE_ANG
  JMP CA_ANGLE
CA_DONE_ANG:

  ; human-like inaccuracy that shrinks with every shot
  LDA AI_JIT
  ASL A
  CLC
  ADC #1
  JSR RND_RANGE
  SEC
  SBC AI_JIT
  CLC
  ADC AI_BP
  CMP #101
  BCC CA_P1
  CMP #$C0
  BCS CA_PLOW              ; wrapped below zero
  LDA #100
  JMP CA_P2
CA_PLOW:
  LDA #6
CA_P1:
  CMP #6
  BCS CA_P2
  LDA #6
CA_P2:
  STA AI_BP
  LDA AI_JIT
  LSR A
  ASL A
  CLC
  ADC #1
  JSR RND_RANGE
  STA T0
  LDA AI_JIT
  LSR A
  STA T1
  LDA AI_BA
  CLC
  ADC T0
  SEC
  SBC T1
  STA AI_BA
  LDA AI_JIT
  CMP #3
  BCC CA_J
  DEC AI_JIT
CA_J:
  ; turn the barrel to the chosen angle, then wait a moment
CA_ROT:
  JSR WAIT_FRAME
  LDX AI_S
  LDA ANG,X
  CMP AI_BA
  BNE CA_STEP
  LDA POW,X
  CMP AI_BP
  BEQ CA_DONE
CA_STEP:
  LDA #0
  JSR BARREL
  LDX AI_S
  LDA ANG,X
  CMP AI_BA
  BEQ CA_PW
  BCC CA_UP
  DEC ANG,X
  JMP CA_PW
CA_UP:
  INC ANG,X
CA_PW:
  LDA POW,X
  CMP AI_BP
  BEQ CA_DRAW
  BCC CA_PUP
  DEC POW,X
  JMP CA_DRAW
CA_PUP:
  INC POW,X
CA_DRAW:
  LDA #1
  JSR BARREL
  JSR UPDATE_HUD
  LDA #<MSG_CPU
  LDY #>MSG_CPU
  JSR HUD_MESSAGE
  JMP CA_ROT
CA_DONE:
  LDX #30
  JSR WAIT_FRAMES
  RTS

; Fly a shot from tank TURN without drawing: A = landing column
SIMULATE:
  LDX TURN
  JSR SETUP_SHOT
  LDA #250
  STA SIMCNT
SIM1:
  JSR STEP_SHELL
  BNE SIM2
  DEC SIMCNT
  BNE SIM1
  LDA SXH
  RTS
SIM2:
  CMP #2
  BEQ SIM3
  LDA IMPX
  RTS
SIM3:
  LDA SXH
  BPL SIM4
  LDA #0                   ; left the screen on the left
  RTS
SIM4:
  CMP #160
  BCC SIM5
  LDA #200                 ; left the screen on the right
SIM5:
  RTS

; =============================================================================
; Ballistics
; =============================================================================
; unsigned T0 * T1 -> RESH:RESL
MUL8:
  LDA #0
  LDX #8
ML1:
  LSR T1
  BCC ML2
  CLC
  ADC T0
ML2:
  ROR A
  ROR RESL
  DEX
  BNE ML1
  STA RESH
  RTS

; Velocity and muzzle position for a shot from tank X
SETUP_SHOT:
  STX SHOOTER
  JSR BARREL_VEC
  LDX SHOOTER
  LDA POW,X
  STA T0
  LDA BCX
  STA T1
  JSR MUL8
  LDX #5
SS1:
  LSR RESH
  ROR RESL
  DEX
  BNE SS1
  LDA RESL
  STA VXL
  LDA RESH
  STA VXH
  LDA BNEG
  BEQ SS2
  SEC
  LDA #0
  SBC VXL
  STA VXL
  LDA #0
  SBC VXH
  STA VXH
SS2:
  LDX SHOOTER
  LDA POW,X
  STA T0
  LDA BSY
  STA T1
  JSR MUL8
  LDX #5
SS3:
  LSR RESH
  ROR RESL
  DEX
  BNE SS3
  SEC                      ; up is negative y
  LDA #0
  SBC RESL
  STA VYL
  LDA #0
  SBC RESH
  STA VYH

  ; muzzle: pivot + direction * (BARREL_MAX+1)
  LDA #BARREL_MAX+1
  STA T0
  LDA BCX
  STA T1
  JSR MUL8
  LDX SHOOTER
  LDA BNEG
  BEQ SS4
  LDA TX,X
  SEC
  SBC RESH
  JMP SS5
SS4:
  LDA TX,X
  CLC
  ADC RESH
SS5:
  STA SXH
  LDA #$80
  STA SXL
  LDA #BARREL_MAX+1
  STA T0
  LDA BSY
  STA T1
  JSR MUL8
  LDX SHOOTER
  LDA TG,X
  SEC
  SBC #5
  SEC
  SBC RESH
  STA SYH
  LDA #$80
  STA SYL
  LDA #0
  STA STEPN
  RTS

; One frame of flight.  A = 0 flying, 1 impact at IMPX/IMPY, 2 left the field
STEP_SHELL:
  CLC
  LDA SXL
  ADC VXL
  STA SXL
  LDA SXH
  ADC VXH
  STA SXH
  CLC
  LDA SYL
  ADC VYL
  STA SYL
  LDA SYH
  ADC VYH
  STA SYH
  CLC
  LDA VYL
  ADC #GRAVITY
  STA VYL
  LDA VYH
  ADC #0
  STA VYH
  INC STEPN
  LDA STEPN
  AND #3
  BNE SS_NOWIND
  CLC
  LDA VXL
  ADC WINDL
  STA VXL
  LDA VXH
  ADC WINDH
  STA VXH
SS_NOWIND:
  LDA SXH
  CMP #160
  BCS SS_OUT
  LDA SYH
  CMP #$E0
  BCS SS_FLY               ; -32..-1: above the top of the field
  CMP #PLAY_ROWS
  BCS SS_OUT               ; below the bottom
  LDX SXH
  CMP HEIGHT,X
  BCS SS_HIT
  LDX #1                   ; tank bodies
SS_TK:
  LDA ALIVE,X
  BEQ SS_TKN
  LDA SXH
  SEC
  SBC TX,X
  CLC
  ADC #4
  CMP #8
  BCS SS_TKN
  LDA SYH
  SEC
  SBC TG,X
  CLC
  ADC #TANK_H
  CMP #TANK_H
  BCC SS_HIT
SS_TKN:
  DEX
  BPL SS_TK
SS_FLY:
  LDA #0
  RTS
SS_HIT:
  LDA SXH
  STA IMPX
  LDA SYH
  STA IMPY
  LDA #1
  RTS
SS_OUT:
  LDA #2
  RTS

; Fire from tank TURN and follow the shell.  A = 1 on impact, 0 if it left
FIRE_SHELL:
  LDX TURN
  JSR SETUP_SHOT
  LDA #SFX_FIRE
  JSR PLAY_SFX
  LDA #0
  STA SHYOLD
FS1:
  JSR WAIT_FRAME
  JSR STEP_SHELL
  BNE FS_END
  JSR DRAW_SHELL
  JMP FS1
FS_END:
  PHA
  JSR HIDE_SHELL
  PLA
  CMP #1
  BEQ FS_HIT
  LDA #0
  RTS
FS_HIT:
  LDA #1
  RTS

; Two-pixel shell in player 2
DRAW_SHELL:
  LDY SHYOLD
  BEQ DS1
  LDA #0
  STA PM_P2,Y
  STA PM_P2+1,Y
DS1:
  LDA SYH
  CMP #PLAY_ROWS-2         ; also hides a shell above the field (wrapped y)
  BCS DS_HIDE
  CLC
  ADC #PM_Y0
  TAY
  STY SHYOLD
  LDA #$C0
  STA PM_P2,Y
  STA PM_P2+1,Y
  LDA SXH
  CLC
  ADC #HPOS0
  STA HPOSP0+2
  RTS
DS_HIDE:
  LDA #0
  STA SHYOLD
  RTS

HIDE_SHELL:
  JSR DS_HIDE
  LDX #0
  TXA
HS1:
  STA PM_P2,X
  INX
  BNE HS1
  RTS

; =============================================================================
; Impact
; =============================================================================
EXPLODE:
  LDA #SFX_BOOM
  JSR PLAY_SFX
  JSR CARVE
  LDA IMPX
  STA FBX
  LDA IMPY
  STA FBY
  JSR FIREBALL

  ; who is inside the blast?
  LDA #0
  STA DIEDMASK
  LDX #1
EX_K:
  LDA ALIVE,X
  BEQ EX_KN
  LDA TX,X
  SEC
  SBC IMPX
  BCS EX_K1
  EOR #$FF
  ADC #1
EX_K1:
  STA T0                   ; |dx|
  LDA TG,X
  SEC
  SBC #3
  SEC
  SBC IMPY
  BCS EX_K2
  EOR #$FF
  ADC #1
EX_K2:
  STA T1                   ; |dy|
  CMP T0
  BCC EX_K3                ; T1 < T0: max = T0, min = T1
  LDA T0                   ; swap so T0 = max
  LDY T1
  STY T0
  STA T1
EX_K3:
  LDA T1
  LSR A
  CLC
  ADC T0
  CMP #KILL_DIST+1
  BCS EX_KN
  LDA #0
  STA ALIVE,X
  LDA DIEDMASK
  ORA BITS,X
  STA DIEDMASK
EX_KN:
  DEX
  BPL EX_K

  LDA DIEDMASK
  BEQ EX_SETTLE
  LDA #SFX_BOOM
  JSR PLAY_SFX
  LDX #0
EX_D:
  LDA ALIVE,X
  BNE EX_DN
  LDA TX,X
  STA FBX
  LDA TG,X
  SEC
  SBC #3
  STA FBY
  STX EXI
  JSR FIREBALL
  LDX EXI
EX_DN:
  INX
  CPX #2
  BNE EX_D

EX_SETTLE:
  ; terrain moved: put the surviving tanks back on the ground
  LDX #0
EX_S:
  STX EXI
  LDA ALIVE,X
  BEQ EX_SD
  LDA #0
  JSR BARREL
  LDX EXI
  JSR PLACE_TANK
  LDA #1
  JSR BARREL
  JMP EX_SW
EX_SD:
  LDA #0
  JSR BARREL               ; wreck: no barrel
EX_SW:
  LDX EXI
  JSR DRAW_TANK
  LDX EXI
  INX
  CPX #2
  BNE EX_S
  LDX #15
  JSR WAIT_FRAMES
  RTS

BITS:
  .BYTE 1,2

; Dig the crater at IMPX/IMPY out of the height map and the bitmap
CARVE:
  LDA IMPX
  SEC
  SBC #CRATER_RADIUS
  BCS CV1
  LDA #0
CV1:
  STA CX
  LDA IMPX
  CLC
  ADC #CRATER_RADIUS
  CMP #160
  BCC CV2
  LDA #159
CV2:
  STA CXEND
CV_LOOP:
  LDA CX
  CMP IMPX
  BCS CV3
  LDA IMPX
  SEC
  SBC CX
  JMP CV4
CV3:
  LDA CX
  SEC
  SBC IMPX
CV4:
  TAX
  LDA CRATER_CHORD,X
  STA T6                   ; half height at this column
  LDA IMPY
  SEC
  SBC T6
  BCS CV5
  LDA #0
CV5:
  STA T4                   ; top of the circle
  LDA IMPY
  CLC
  ADC T6
  CLC
  ADC #1
  CMP #PLAY_ROWS
  BCC CV6
  LDA #PLAY_ROWS
CV6:
  STA T5                   ; first line below the circle
  LDX CX
  LDA HEIGHT,X
  CMP T4
  BCC CV_NEXT              ; ground starts below... circle is buried: leave it
  LDA T5
  CMP HEIGHT,X
  BEQ CV_NEXT
  BCC CV_NEXT
  LDY HEIGHT,X
  STY RCLO
  STA HEIGHT,X
  STA RCHI
  STX PX
  JSR REDRAW_COLUMN
CV_NEXT:
  INC CX
  LDA CX
  CMP CXEND
  BEQ CV_LOOP
  BCC CV_LOOP
  RTS

; Expanding, colour cycling fireball in player 3 at FBX/FBY
FIREBALL:
  LDA #0
  STA FBI
FB1:
  JSR WAIT_FRAME
  LDX #0
  LDA #0
FB2:
  STA PM_P3,X
  INX
  BNE FB2
  LDX FBI
  LDA FB_COLORS,X
  STA COLPM3
  LDA FB_SHAPE,X
  STA T0                   ; offset of the shape in FB_SHAPES
  LDA FBY
  CLC
  ADC #PM_Y0-5
  TAY
  LDA #10
  STA T3
FB3:
  LDX T0
  LDA FB_SHAPES,X
  STA PM_P3,Y
  INC T0
  INY
  DEC T3
  BNE FB3
  LDA FBX
  CLC
  ADC #HPOS0-8
  STA HPOSP0+3
  INC FBI
  LDA FBI
  CMP #14
  BNE FB1
  LDX #0
  TXA
FB4:
  STA PM_P3,X
  INX
  BNE FB4
  STA HPOSP0+3
  RTS

FB_SHAPE:
  .BYTE 32,32,16,0,0,0,0,0,16,16,32,32,32,32
FB_COLORS:
  .BYTE $0F,$1F,$1E,$2E,$2C,$3C,$3A,$38,$36,$34,$44,$42,$40,$00
FB_SHAPES:
  .BYTE $18,$7E,$FF,$FF,$FF,$FF,$FF,$FF,$7E,$18,0,0,0,0,0,0   ; 0  large
  .BYTE $00,$18,$3C,$7E,$7E,$7E,$7E,$3C,$18,$00,0,0,0,0,0,0   ; 16 medium
  .BYTE $00,$00,$00,$18,$3C,$3C,$18,$00,$00,$00,0,0,0,0,0,0   ; 32 small

; =============================================================================
; End of round / match
; =============================================================================
; Z set when the match goes on, clear when it is over
ROUND_END:
  LDA ALIVE
  CMP ALIVE+1
  BEQ RE_DRAW
  BCC RE_P2                ; tank 0 dead
  INC SCORE
  LDA #<MSG_P1SCORES
  LDY #>MSG_P1SCORES
  JMP RE_SHOW
RE_P2:
  INC SCORE+1
  LDA #<MSG_P2SCORES
  LDY #>MSG_P2SCORES
  JMP RE_SHOW
RE_DRAW:
  LDA #<MSG_DRAW
  LDY #>MSG_DRAW
RE_SHOW:
  PHA
  TYA
  PHA
  JSR UPDATE_HUD
  PLA
  TAY
  PLA
  JSR HUD_MESSAGE
  LDX #90
  JSR WAIT_FRAMES

  LDA SCORE
  CMP #WIN_SCORE
  BCS RE_WIN1
  LDA SCORE+1
  CMP #WIN_SCORE
  BCS RE_WIN2
  LDA #0
  RTS
RE_WIN1:
  LDA #<MSG_P1WINS
  LDY #>MSG_P1WINS
  JMP RE_END
RE_WIN2:
  LDA #<MSG_P2WINS
  LDY #>MSG_P2WINS
RE_END:
  JSR HUD_MESSAGE
  LDA #SFX_WIN
  JSR PLAY_SFX
  LDX #60
  JSR WAIT_FRAMES
RE_WAIT:
  JSR WAIT_FRAME
  JSR START_PRESSED
  BEQ RE_WAIT
  LDA #1
  RTS

; =============================================================================
; Text
; =============================================================================
MSG_1P:     .TEXT "1 PLAYER VS CPU"
            .BYTE 0
MSG_2P:     .TEXT "2 PLAYERS"
            .BYTE 0
MSG_SELECT: .TEXT "SELECT=MODE"
            .BYTE 0
MSG_START:  .TEXT "START=GO"
            .BYTE 0
MSG_P1:     .TEXT "P1:"
            .BYTE 0
MSG_P2:     .TEXT "P2:"
            .BYTE 0
MSG_WIND:   .TEXT "WIND"
            .BYTE 0
MSG_ANGLE:  .TEXT "ANGLE"
            .BYTE 0
MSG_POWER:  .TEXT "POWER"
            .BYTE 0
MSG_AIM:    .TEXT "YOUR SHOT"
            .BYTE 0
MSG_CPU:    .TEXT "CPU AIMING"
            .BYTE 0
MSG_FIRE:   .TEXT "FIRE!"
            .BYTE 0
MSG_MISS:   .TEXT "MISSED"
            .BYTE 0
MSG_DRAW:   .TEXT "DRAW!"
            .BYTE 0
MSG_P1SCORES: .TEXT "P1 SCORES!"
            .BYTE 0
MSG_P2SCORES: .TEXT "P2 SCORES!"
            .BYTE 0
MSG_P1WINS: .TEXT "P1 WINS!"
            .BYTE 0
MSG_P2WINS: .TEXT "P2 WINS!"
            .BYTE 0

; Sky and ground palette per 16-line band (see GAME_DLI)
SKY_COLORS:
  .BYTE $80,$82,$84,$86,$88,$8A,$8C,$9C,$9E,$2E,$2C,$2A,$E0
GROUND_COLORS:
  .BYTE $E6,$E6,$E6,$E6,$E6,$E4,$E4,$E4,$E2,$E2,$E2,$E0,$E0

; >>> GENERATED TABLES (node tools/generate_assets.js)
CRATER_RADIUS = 9
COS_TABLE:                       ; 255*cos(0..90 degrees)
  .BYTE $FF,$FF,$FF,$FF,$FE,$FE,$FE,$FD
  .BYTE $FD,$FC,$FB,$FA,$F9,$F8,$F7,$F6
  .BYTE $F5,$F4,$F3,$F1,$F0,$EE,$EC,$EB
  .BYTE $E9,$E7,$E5,$E3,$E1,$DF,$DD,$DB
  .BYTE $D8,$D6,$D3,$D1,$CE,$CC,$C9,$C6
  .BYTE $C3,$C0,$BE,$BA,$B7,$B4,$B1,$AE
  .BYTE $AB,$A7,$A4,$A0,$9D,$99,$96,$92
  .BYTE $8F,$8B,$87,$83,$80,$7C,$78,$74
  .BYTE $70,$6C,$68,$64,$60,$5B,$57,$53
  .BYTE $4F,$4B,$46,$42,$3E,$39,$35,$31
  .BYTE $2C,$28,$23,$1F,$1B,$16,$12,$0D
  .BYTE $09,$04,$00
CRATER_CHORD:                    ; half height of the crater per column offset
  .BYTE $09,$09,$09,$08,$08,$07,$07,$06,$04,$00
; <<< GENERATED TABLES
; >>> GENERATED GAME DISPLAY LIST (node tools/generate_assets.js)
; ANTIC display lists must not cross a 1K boundary
.ORG $4C00
GAME_DL:
  .BYTE $70
  .BYTE $42
  .WORD HUD_ROW0
  .BYTE $82
  .BYTE $4E
  .WORD SCREEN_A
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $8E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $8E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $8E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $8E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $8E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $8E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $4E
  .WORD SCREEN_B
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $8E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $8E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $8E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $8E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $8E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $8E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $0E
  .BYTE $41
  .WORD GAME_DL
; <<< GENERATED GAME DISPLAY LIST
; >>> GENERATED FONT (node tools/generate_assets.js)
CHARSET = $B800
.ORG $B900
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00   ; space
  .BYTE $10,$10,$10,$10,$10,$00,$10,$00   ; !
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00   ; "
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00   ; #
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00   ; $
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00   ; %
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00   ; &
  .BYTE $10,$10,$00,$00,$00,$00,$00,$00   ; '
  .BYTE $08,$10,$20,$20,$20,$10,$08,$00   ; (
  .BYTE $20,$10,$08,$08,$08,$10,$20,$00   ; )
  .BYTE $10,$54,$38,$54,$10,$00,$00,$00   ; *
  .BYTE $00,$10,$10,$7C,$10,$10,$00,$00   ; +
  .BYTE $00,$00,$00,$00,$30,$10,$20,$00   ; ,
  .BYTE $00,$00,$00,$7C,$00,$00,$00,$00   ; -
  .BYTE $00,$00,$00,$00,$00,$30,$30,$00   ; .
  .BYTE $04,$04,$08,$10,$20,$40,$40,$00   ; /
  .BYTE $38,$44,$4C,$54,$64,$44,$38,$00   ; 0
  .BYTE $10,$30,$10,$10,$10,$10,$38,$00   ; 1
  .BYTE $38,$44,$04,$08,$10,$20,$7C,$00   ; 2
  .BYTE $78,$04,$04,$38,$04,$04,$78,$00   ; 3
  .BYTE $08,$18,$28,$48,$7C,$08,$08,$00   ; 4
  .BYTE $7C,$40,$78,$04,$04,$44,$38,$00   ; 5
  .BYTE $38,$40,$40,$78,$44,$44,$38,$00   ; 6
  .BYTE $7C,$04,$08,$10,$20,$20,$20,$00   ; 7
  .BYTE $38,$44,$44,$38,$44,$44,$38,$00   ; 8
  .BYTE $38,$44,$44,$3C,$04,$04,$38,$00   ; 9
  .BYTE $00,$30,$30,$00,$30,$30,$00,$00   ; :
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00   ; ;
  .BYTE $08,$10,$20,$40,$20,$10,$08,$00   ; <
  .BYTE $00,$00,$7C,$00,$7C,$00,$00,$00   ; =
  .BYTE $20,$10,$08,$04,$08,$10,$20,$00   ; >
  .BYTE $38,$44,$04,$08,$10,$00,$10,$00   ; ?
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00   ; @
  .BYTE $38,$44,$44,$7C,$44,$44,$44,$00   ; A
  .BYTE $78,$44,$44,$78,$44,$44,$78,$00   ; B
  .BYTE $38,$44,$40,$40,$40,$44,$38,$00   ; C
  .BYTE $78,$44,$44,$44,$44,$44,$78,$00   ; D
  .BYTE $7C,$40,$40,$78,$40,$40,$7C,$00   ; E
  .BYTE $7C,$40,$40,$78,$40,$40,$40,$00   ; F
  .BYTE $38,$44,$40,$5C,$44,$44,$38,$00   ; G
  .BYTE $44,$44,$44,$7C,$44,$44,$44,$00   ; H
  .BYTE $38,$10,$10,$10,$10,$10,$38,$00   ; I
  .BYTE $1C,$08,$08,$08,$08,$48,$30,$00   ; J
  .BYTE $44,$48,$50,$60,$50,$48,$44,$00   ; K
  .BYTE $40,$40,$40,$40,$40,$40,$7C,$00   ; L
  .BYTE $44,$6C,$54,$54,$44,$44,$44,$00   ; M
  .BYTE $44,$64,$64,$54,$4C,$4C,$44,$00   ; N
  .BYTE $38,$44,$44,$44,$44,$44,$38,$00   ; O
  .BYTE $78,$44,$44,$78,$40,$40,$40,$00   ; P
  .BYTE $38,$44,$44,$44,$54,$48,$34,$00   ; Q
  .BYTE $78,$44,$44,$78,$50,$48,$44,$00   ; R
  .BYTE $3C,$40,$40,$38,$04,$04,$78,$00   ; S
  .BYTE $7C,$10,$10,$10,$10,$10,$10,$00   ; T
  .BYTE $44,$44,$44,$44,$44,$44,$38,$00   ; U
  .BYTE $44,$44,$44,$44,$44,$28,$10,$00   ; V
  .BYTE $44,$44,$44,$54,$54,$6C,$44,$00   ; W
  .BYTE $44,$44,$28,$10,$28,$44,$44,$00   ; X
  .BYTE $44,$44,$28,$10,$10,$10,$10,$00   ; Y
  .BYTE $7C,$04,$08,$10,$20,$40,$7C,$00   ; Z
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00   ; [
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00   ; \
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00   ; ]
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00   ; ^
  .BYTE $00,$00,$00,$00,$00,$00,$7C,$00   ; _
; <<< GENERATED FONT
; >>> GENERATED TITLE SCREEN (node tools/generate_start_screen.js)
TITLE_ROWS = $D0
TITLE_COLBK0 = $00
TITLE_PF0_0 = $10
TITLE_PF1_0 = $20
TITLE_PF2_0 = $30

.ORG $8000

TITLE_DISPLAY_LIST:
  .BYTE $F0              ; 8 blank scanlines, DLI sets bitmap palettes
  .BYTE $4E
  .WORD TITLE_BITMAP+$0000
  .BYTE $4E
  .WORD TITLE_BITMAP+$0028
  .BYTE $4E
  .WORD TITLE_BITMAP+$0050
  .BYTE $4E
  .WORD TITLE_BITMAP+$0078
  .BYTE $4E
  .WORD TITLE_BITMAP+$00A0
  .BYTE $4E
  .WORD TITLE_BITMAP+$00C8
  .BYTE $4E
  .WORD TITLE_BITMAP+$00F0
  .BYTE $4E
  .WORD TITLE_BITMAP+$0118
  .BYTE $4E
  .WORD TITLE_BITMAP+$0140
  .BYTE $4E
  .WORD TITLE_BITMAP+$0168
  .BYTE $4E
  .WORD TITLE_BITMAP+$0190
  .BYTE $4E
  .WORD TITLE_BITMAP+$01B8
  .BYTE $4E
  .WORD TITLE_BITMAP+$01E0
  .BYTE $4E
  .WORD TITLE_BITMAP+$0208
  .BYTE $4E
  .WORD TITLE_BITMAP+$0230
  .BYTE $4E
  .WORD TITLE_BITMAP+$0258
  .BYTE $4E
  .WORD TITLE_BITMAP+$0280
  .BYTE $4E
  .WORD TITLE_BITMAP+$02A8
  .BYTE $4E
  .WORD TITLE_BITMAP+$02D0
  .BYTE $4E
  .WORD TITLE_BITMAP+$02F8
  .BYTE $4E
  .WORD TITLE_BITMAP+$0320
  .BYTE $4E
  .WORD TITLE_BITMAP+$0348
  .BYTE $4E
  .WORD TITLE_BITMAP+$0370
  .BYTE $4E
  .WORD TITLE_BITMAP+$0398
  .BYTE $4E
  .WORD TITLE_BITMAP+$03C0
  .BYTE $4E
  .WORD TITLE_BITMAP+$03E8
  .BYTE $4E
  .WORD TITLE_BITMAP+$0410
  .BYTE $4E
  .WORD TITLE_BITMAP+$0438
  .BYTE $4E
  .WORD TITLE_BITMAP+$0460
  .BYTE $4E
  .WORD TITLE_BITMAP+$0488
  .BYTE $4E
  .WORD TITLE_BITMAP+$04B0
  .BYTE $4E
  .WORD TITLE_BITMAP+$04D8
  .BYTE $4E
  .WORD TITLE_BITMAP+$0500
  .BYTE $4E
  .WORD TITLE_BITMAP+$0528
  .BYTE $4E
  .WORD TITLE_BITMAP+$0550
  .BYTE $4E
  .WORD TITLE_BITMAP+$0578
  .BYTE $4E
  .WORD TITLE_BITMAP+$05A0
  .BYTE $4E
  .WORD TITLE_BITMAP+$05C8
  .BYTE $4E
  .WORD TITLE_BITMAP+$05F0
  .BYTE $4E
  .WORD TITLE_BITMAP+$0618
  .BYTE $4E
  .WORD TITLE_BITMAP+$0640
  .BYTE $4E
  .WORD TITLE_BITMAP+$0668
  .BYTE $4E
  .WORD TITLE_BITMAP+$0690
  .BYTE $4E
  .WORD TITLE_BITMAP+$06B8
  .BYTE $4E
  .WORD TITLE_BITMAP+$06E0
  .BYTE $4E
  .WORD TITLE_BITMAP+$0708
  .BYTE $4E
  .WORD TITLE_BITMAP+$0730
  .BYTE $4E
  .WORD TITLE_BITMAP+$0758
  .BYTE $4E
  .WORD TITLE_BITMAP+$0780
  .BYTE $4E
  .WORD TITLE_BITMAP+$07A8
  .BYTE $4E
  .WORD TITLE_BITMAP+$07D0
  .BYTE $4E
  .WORD TITLE_BITMAP+$07F8
  .BYTE $4E
  .WORD TITLE_BITMAP+$0820
  .BYTE $4E
  .WORD TITLE_BITMAP+$0848
  .BYTE $4E
  .WORD TITLE_BITMAP+$0870
  .BYTE $4E
  .WORD TITLE_BITMAP+$0898
  .BYTE $4E
  .WORD TITLE_BITMAP+$08C0
  .BYTE $4E
  .WORD TITLE_BITMAP+$08E8
  .BYTE $4E
  .WORD TITLE_BITMAP+$0910
  .BYTE $4E
  .WORD TITLE_BITMAP+$0938
  .BYTE $4E
  .WORD TITLE_BITMAP+$0960
  .BYTE $4E
  .WORD TITLE_BITMAP+$0988
  .BYTE $4E
  .WORD TITLE_BITMAP+$09B0
  .BYTE $4E
  .WORD TITLE_BITMAP+$09D8
  .BYTE $4E
  .WORD TITLE_BITMAP+$0A00
  .BYTE $4E
  .WORD TITLE_BITMAP+$0A28
  .BYTE $4E
  .WORD TITLE_BITMAP+$0A50
  .BYTE $4E
  .WORD TITLE_BITMAP+$0A78
  .BYTE $4E
  .WORD TITLE_BITMAP+$0AA0
  .BYTE $4E
  .WORD TITLE_BITMAP+$0AC8
  .BYTE $4E
  .WORD TITLE_BITMAP+$0AF0
  .BYTE $4E
  .WORD TITLE_BITMAP+$0B18
  .BYTE $4E
  .WORD TITLE_BITMAP+$0B40
  .BYTE $4E
  .WORD TITLE_BITMAP+$0B68
  .BYTE $4E
  .WORD TITLE_BITMAP+$0B90
  .BYTE $4E
  .WORD TITLE_BITMAP+$0BB8
  .BYTE $4E
  .WORD TITLE_BITMAP+$0BE0
  .BYTE $4E
  .WORD TITLE_BITMAP+$0C08
  .BYTE $4E
  .WORD TITLE_BITMAP+$0C30
  .BYTE $4E
  .WORD TITLE_BITMAP+$0C58
  .BYTE $4E
  .WORD TITLE_BITMAP+$0C80
  .BYTE $4E
  .WORD TITLE_BITMAP+$0CA8
  .BYTE $4E
  .WORD TITLE_BITMAP+$0CD0
  .BYTE $4E
  .WORD TITLE_BITMAP+$0CF8
  .BYTE $4E
  .WORD TITLE_BITMAP+$0D20
  .BYTE $4E
  .WORD TITLE_BITMAP+$0D48
  .BYTE $4E
  .WORD TITLE_BITMAP+$0D70
  .BYTE $4E
  .WORD TITLE_BITMAP+$0D98
  .BYTE $4E
  .WORD TITLE_BITMAP+$0DC0
  .BYTE $4E
  .WORD TITLE_BITMAP+$0DE8
  .BYTE $4E
  .WORD TITLE_BITMAP+$0E10
  .BYTE $4E
  .WORD TITLE_BITMAP+$0E38
  .BYTE $4E
  .WORD TITLE_BITMAP+$0E60
  .BYTE $4E
  .WORD TITLE_BITMAP+$0E88
  .BYTE $4E
  .WORD TITLE_BITMAP+$0EB0
  .BYTE $4E
  .WORD TITLE_BITMAP+$0ED8
  .BYTE $4E
  .WORD TITLE_BITMAP+$0F00
  .BYTE $4E
  .WORD TITLE_BITMAP+$0F28
  .BYTE $4E
  .WORD TITLE_BITMAP+$0F50
  .BYTE $4E
  .WORD TITLE_BITMAP+$0F78
  .BYTE $4E
  .WORD TITLE_BITMAP+$0FA0
  .BYTE $4E
  .WORD TITLE_BITMAP+$0FC8
  .BYTE $4E
  .WORD TITLE_BITMAP+$0FF0
  .BYTE $4E
  .WORD TITLE_BITMAP+$1018
  .BYTE $4E
  .WORD TITLE_BITMAP+$1040
  .BYTE $4E
  .WORD TITLE_BITMAP+$1068
  .BYTE $4E
  .WORD TITLE_BITMAP+$1090
  .BYTE $4E
  .WORD TITLE_BITMAP+$10B8
  .BYTE $4E
  .WORD TITLE_BITMAP+$10E0
  .BYTE $4E
  .WORD TITLE_BITMAP+$1108
  .BYTE $4E
  .WORD TITLE_BITMAP+$1130
  .BYTE $4E
  .WORD TITLE_BITMAP+$1158
  .BYTE $4E
  .WORD TITLE_BITMAP+$1180
  .BYTE $4E
  .WORD TITLE_BITMAP+$11A8
  .BYTE $4E
  .WORD TITLE_BITMAP+$11D0
  .BYTE $4E
  .WORD TITLE_BITMAP+$11F8
  .BYTE $4E
  .WORD TITLE_BITMAP+$1220
  .BYTE $4E
  .WORD TITLE_BITMAP+$1248
  .BYTE $4E
  .WORD TITLE_BITMAP+$1270
  .BYTE $4E
  .WORD TITLE_BITMAP+$1298
  .BYTE $4E
  .WORD TITLE_BITMAP+$12C0
  .BYTE $4E
  .WORD TITLE_BITMAP+$12E8
  .BYTE $4E
  .WORD TITLE_BITMAP+$1310
  .BYTE $4E
  .WORD TITLE_BITMAP+$1338
  .BYTE $4E
  .WORD TITLE_BITMAP+$1360
  .BYTE $4E
  .WORD TITLE_BITMAP+$1388
  .BYTE $4E
  .WORD TITLE_BITMAP+$13B0
  .BYTE $4E
  .WORD TITLE_BITMAP+$13D8
  .BYTE $4E
  .WORD TITLE_BITMAP+$1400
  .BYTE $4E
  .WORD TITLE_BITMAP+$1428
  .BYTE $4E
  .WORD TITLE_BITMAP+$1450
  .BYTE $4E
  .WORD TITLE_BITMAP+$1478
  .BYTE $4E
  .WORD TITLE_BITMAP+$14A0
  .BYTE $4E
  .WORD TITLE_BITMAP+$14C8
  .BYTE $4E
  .WORD TITLE_BITMAP+$14F0
  .BYTE $4E
  .WORD TITLE_BITMAP+$1518
  .BYTE $4E
  .WORD TITLE_BITMAP+$1540
  .BYTE $4E
  .WORD TITLE_BITMAP+$1568
  .BYTE $4E
  .WORD TITLE_BITMAP+$1590
  .BYTE $4E
  .WORD TITLE_BITMAP+$15B8
  .BYTE $4E
  .WORD TITLE_BITMAP+$15E0
  .BYTE $4E
  .WORD TITLE_BITMAP+$1608
  .BYTE $4E
  .WORD TITLE_BITMAP+$1630
  .BYTE $4E
  .WORD TITLE_BITMAP+$1658
  .BYTE $4E
  .WORD TITLE_BITMAP+$1680
  .BYTE $4E
  .WORD TITLE_BITMAP+$16A8
  .BYTE $4E
  .WORD TITLE_BITMAP+$16D0
  .BYTE $4E
  .WORD TITLE_BITMAP+$16F8
  .BYTE $4E
  .WORD TITLE_BITMAP+$1720
  .BYTE $4E
  .WORD TITLE_BITMAP+$1748
  .BYTE $4E
  .WORD TITLE_BITMAP+$1770
  .BYTE $4E
  .WORD TITLE_BITMAP+$1798
  .BYTE $4E
  .WORD TITLE_BITMAP+$17C0
  .BYTE $4E
  .WORD TITLE_BITMAP+$17E8
  .BYTE $4E
  .WORD TITLE_BITMAP+$1810
  .BYTE $4E
  .WORD TITLE_BITMAP+$1838
  .BYTE $4E
  .WORD TITLE_BITMAP+$1860
  .BYTE $4E
  .WORD TITLE_BITMAP+$1888
  .BYTE $4E
  .WORD TITLE_BITMAP+$18B0
  .BYTE $4E
  .WORD TITLE_BITMAP+$18D8
  .BYTE $4E
  .WORD TITLE_BITMAP+$1900
  .BYTE $4E
  .WORD TITLE_BITMAP+$1928
  .BYTE $4E
  .WORD TITLE_BITMAP+$1950
  .BYTE $4E
  .WORD TITLE_BITMAP+$1978
  .BYTE $4E
  .WORD TITLE_BITMAP+$19A0
  .BYTE $4E
  .WORD TITLE_BITMAP+$19C8
  .BYTE $4E
  .WORD TITLE_BITMAP+$19F0
  .BYTE $4E
  .WORD TITLE_BITMAP+$1A18
  .BYTE $4E
  .WORD TITLE_BITMAP+$1A40
  .BYTE $4E
  .WORD TITLE_BITMAP+$1A68
  .BYTE $4E
  .WORD TITLE_BITMAP+$1A90
  .BYTE $4E
  .WORD TITLE_BITMAP+$1AB8
  .BYTE $4E
  .WORD TITLE_BITMAP+$1AE0
  .BYTE $4E
  .WORD TITLE_BITMAP+$1B08
  .BYTE $4E
  .WORD TITLE_BITMAP+$1B30
  .BYTE $4E
  .WORD TITLE_BITMAP+$1B58
  .BYTE $4E
  .WORD TITLE_BITMAP+$1B80
  .BYTE $4E
  .WORD TITLE_BITMAP+$1BA8
  .BYTE $4E
  .WORD TITLE_BITMAP+$1BD0
  .BYTE $4E
  .WORD TITLE_BITMAP+$1BF8
  .BYTE $4E
  .WORD TITLE_BITMAP+$1C20
  .BYTE $4E
  .WORD TITLE_BITMAP+$1C48
  .BYTE $4E
  .WORD TITLE_BITMAP+$1C70
  .BYTE $4E
  .WORD TITLE_BITMAP+$1C98
  .BYTE $4E
  .WORD TITLE_BITMAP+$1CC0
  .BYTE $4E
  .WORD TITLE_BITMAP+$1CE8
  .BYTE $4E
  .WORD TITLE_BITMAP+$1D10
  .BYTE $4E
  .WORD TITLE_BITMAP+$1D38
  .BYTE $4E
  .WORD TITLE_BITMAP+$1D60
  .BYTE $4E
  .WORD TITLE_BITMAP+$1D88
  .BYTE $4E
  .WORD TITLE_BITMAP+$1DB0
  .BYTE $4E
  .WORD TITLE_BITMAP+$1DD8
  .BYTE $4E
  .WORD TITLE_BITMAP+$1E00
  .BYTE $4E
  .WORD TITLE_BITMAP+$1E28
  .BYTE $4E
  .WORD TITLE_BITMAP+$1E50
  .BYTE $4E
  .WORD TITLE_BITMAP+$1E78
  .BYTE $4E
  .WORD TITLE_BITMAP+$1EA0
  .BYTE $4E
  .WORD TITLE_BITMAP+$1EC8
  .BYTE $4E
  .WORD TITLE_BITMAP+$1EF0
  .BYTE $4E
  .WORD TITLE_BITMAP+$1F18
  .BYTE $4E
  .WORD TITLE_BITMAP+$1F40
  .BYTE $4E
  .WORD TITLE_BITMAP+$1F68
  .BYTE $4E
  .WORD TITLE_BITMAP+$1F90
  .BYTE $4E
  .WORD TITLE_BITMAP+$1FB8
  .BYTE $4E
  .WORD TITLE_BITMAP+$1FE0
  .BYTE $4E
  .WORD TITLE_BITMAP+$2008
  .BYTE $4E
  .WORD TITLE_BITMAP+$2030
  .BYTE $4E
  .WORD TITLE_BITMAP+$2058
  .BYTE $42              ; mode 2 text row for the mode select prompt
  .WORD TITLE_TEXT
  .BYTE $41
  .WORD TITLE_DISPLAY_LIST

.ORG $8400

TITLE_BITMAP:
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$0A,$AA,$AA,$AA,$AA,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$56,$AA,$AA,$AA,$A8,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $55,$55,$55,$55,$55,$55,$AA,$AA,$AA,$FF,$FF,$F0,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$03,$FF,$FF,$AA,$AA,$AA,$95,$55,$55,$55,$55,$55
  .BYTE $AA,$AA,$FF,$FF,$55,$55,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$55,$55,$7F,$FF,$AA,$AA
  .BYTE $A8,$00,$01,$55,$55,$50,$54,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$05,$55,$55,$00,$00,$AA
  .BYTE $80,$10,$15,$55,$55,$55,$55,$55,$41,$41,$40,$00,$00,$40,$00,$00,$00,$00,$00,$55,$15,$40,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$15,$55,$55,$55,$55,$55,$00,$02
  .BYTE $85,$55,$55,$00,$04,$55,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$14,$00,$05,$55,$55,$56
  .BYTE $85,$55,$51,$54,$01,$50,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$40,$00,$00,$00,$00,$00,$40,$14,$00,$01,$55,$55,$52
  .BYTE $85,$54,$51,$40,$15,$00,$00,$00,$01,$00,$00,$00,$00,$40,$00,$00,$00,$00,$01,$00,$01,$40,$00,$14,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$54,$15,$55,$55,$52
  .BYTE $95,$55,$44,$01,$55,$00,$04,$00,$14,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$40,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$14,$01,$05,$15,$52
  .BYTE $95,$54,$05,$15,$00,$00,$00,$04,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$15,$52
  .BYTE $40,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01
  .BYTE $55,$40,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$11
  .BYTE $55,$04,$04,$40,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$51
  .BYTE $45,$00,$00,$04,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$00,$00,$51
  .BYTE $45,$40,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$40,$00,$11
  .BYTE $40,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$11
  .BYTE $40,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$11
  .BYTE $40,$01,$00,$04,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01
  .BYTE $44,$55,$40,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$51
  .BYTE $44,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$51,$55,$54,$50,$01,$15,$55,$00,$15,$54,$04,$40,$00,$00,$00,$01,$00,$00,$00,$00,$00,$00,$00,$00,$51
  .BYTE $40,$14,$00,$00,$00,$00,$00,$00,$00,$01,$54,$14,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$55,$45,$55,$01,$55,$00,$00,$00,$00,$00,$00,$00,$00,$01
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $C0,$00,$C0,$00,$00,$00,$00,$3C,$00,$0E,$AA,$AA,$00,$00,$02,$55,$55,$55,$56,$02,$55,$55,$C0,$95,$57,$36,$AA,$AA,$AA,$CA,$FF,$C0,$FC,$00,$00,$00,$00,$00,$00,$03
  .BYTE $00,$00,$00,$00,$00,$0D,$55,$57,$00,$0D,$55,$55,$C0,$00,$03,$6A,$AA,$AA,$A9,$0D,$AA,$AA,$40,$6A,$A7,$36,$99,$55,$55,$C5,$55,$40,$D5,$55,$70,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$0E,$AA,$AB,$00,$0E,$55,$56,$C0,$00,$03,$55,$55,$55,$57,$0E,$55,$55,$80,$D5,$5B,$39,$55,$F5,$56,$C9,$55,$80,$EA,$AA,$B0,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$0D,$55,$57,$00,$0D,$95,$59,$C0,$00,$03,$6A,$AA,$AA,$A7,$0D,$AA,$A9,$F0,$DA,$A7,$06,$A9,$F6,$AB,$0D,$56,$C3,$D5,$55,$70,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$2B,$55,$5E,$80,$2B,$55,$57,$A0,$00,$02,$D5,$55,$55,$5E,$AB,$55,$55,$E0,$B5,$5E,$2D,$57,$AD,$56,$8B,$57,$A2,$B5,$55,$E8,$00,$00,$00,$00,$00
  .BYTE $55,$55,$55,$55,$55,$6C,$00,$03,$95,$6C,$00,$00,$E5,$55,$56,$C0,$00,$00,$0E,$AC,$00,$00,$E9,$B0,$0E,$5C,$03,$AC,$02,$AB,$03,$AA,$C0,$00,$39,$55,$55,$55,$55,$55
  .BYTE $55,$55,$55,$55,$55,$AC,$00,$03,$A5,$AC,$00,$00,$E9,$55,$56,$C0,$00,$00,$0E,$AC,$00,$00,$39,$B0,$0E,$A8,$03,$AC,$0E,$AB,$03,$AA,$C0,$00,$3A,$55,$55,$55,$55,$55
  .BYTE $55,$55,$55,$55,$57,$80,$00,$00,$AF,$80,$00,$00,$2B,$55,$57,$80,$00,$00,$02,$A0,$00,$00,$0A,$80,$02,$F8,$00,$A0,$02,$A8,$00,$A8,$00,$00,$02,$D5,$55,$55,$55,$55
  .BYTE $55,$55,$55,$55,$56,$80,$00,$00,$EA,$80,$00,$00,$3A,$55,$56,$C0,$00,$00,$0E,$B0,$00,$00,$0E,$B0,$03,$AC,$03,$AC,$03,$AC,$03,$AC,$00,$00,$0E,$95,$55,$55,$55,$55
  .BYTE $55,$55,$55,$55,$57,$80,$00,$00,$2F,$80,$00,$00,$0B,$55,$57,$80,$00,$00,$0B,$80,$00,$00,$0B,$E0,$02,$F8,$02,$F8,$02,$F8,$02,$F8,$00,$00,$02,$D5,$55,$55,$55,$55
  .BYTE $55,$55,$55,$55,$57,$80,$2A,$00,$2F,$80,$2A,$80,$0B,$55,$57,$AA,$A0,$2A,$AB,$C0,$0A,$A0,$0B,$E0,$02,$F8,$02,$F8,$03,$F8,$0B,$F8,$00,$A8,$02,$D5,$55,$55,$55,$55
  .BYTE $55,$55,$55,$55,$56,$00,$3F,$C0,$3A,$C0,$3F,$F0,$0E,$55,$56,$AA,$B0,$0E,$AA,$C0,$3A,$B0,$0E,$B0,$00,$AC,$03,$AC,$02,$B0,$0E,$AC,$03,$FC,$03,$A5,$55,$55,$55,$55
  .BYTE $55,$55,$55,$55,$56,$00,$EA,$C0,$3A,$C0,$3A,$B0,$0E,$55,$55,$AA,$B0,$0A,$AA,$C0,$3A,$B0,$0E,$B0,$00,$EC,$03,$AC,$03,$B0,$0E,$AC,$03,$AB,$03,$A5,$55,$55,$55,$55
  .BYTE $55,$55,$55,$55,$56,$00,$EA,$80,$3A,$C0,$3A,$B0,$0E,$55,$55,$6A,$B0,$0A,$AA,$C0,$3A,$B0,$0E,$B0,$00,$EC,$03,$AC,$02,$B0,$0E,$AC,$02,$AB,$03,$A5,$55,$55,$55,$55
  .BYTE $55,$55,$55,$55,$56,$00,$EA,$C0,$3A,$C0,$3A,$B0,$0E,$55,$55,$6A,$B0,$0A,$AA,$C0,$3A,$B0,$0E,$B0,$00,$EC,$03,$AC,$03,$B0,$3A,$AC,$02,$A8,$03,$A5,$55,$55,$55,$55
  .BYTE $55,$55,$55,$55,$56,$00,$EA,$C0,$3A,$C0,$3A,$B0,$0E,$55,$55,$6A,$B0,$0A,$AA,$C0,$3A,$B0,$0E,$B0,$00,$3C,$03,$AC,$03,$C0,$3A,$AC,$02,$AB,$03,$A5,$55,$55,$55,$55
  .BYTE $00,$00,$00,$00,$02,$55,$EA,$D5,$7A,$D5,$7A,$B5,$5E,$80,$00,$00,$B5,$5A,$02,$D5,$7A,$A5,$5E,$B5,$55,$7D,$57,$AD,$57,$D5,$7A,$AD,$56,$AB,$FF,$A0,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$02,$55,$BC,$95,$6F,$95,$6C,$E5,$5B,$00,$00,$00,$D5,$5B,$00,$95,$6F,$25,$5B,$E5,$55,$69,$56,$F9,$56,$95,$7F,$39,$57,$CE,$AA,$F0,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$02,$55,$E8,$D5,$7A,$D5,$7A,$B5,$5E,$00,$00,$00,$B5,$5A,$00,$D5,$7A,$35,$5E,$B5,$55,$7D,$57,$AD,$57,$55,$EA,$2D,$56,$8A,$AA,$A0,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$02,$55,$E8,$D5,$7A,$D5,$7A,$B5,$5E,$00,$00,$00,$B5,$5A,$00,$D5,$7A,$35,$5E,$B5,$55,$5D,$57,$AD,$57,$55,$EA,$2D,$56,$AA,$AA,$A0,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$02,$55,$E8,$D5,$7A,$D5,$7F,$D5,$7A,$00,$00,$00,$B5,$5A,$00,$D5,$7A,$25,$5E,$B5,$55,$5D,$57,$AD,$57,$57,$A8,$2D,$57,$FF,$EA,$A0,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$02,$55,$E8,$95,$7A,$B5,$5F,$D5,$FA,$00,$00,$00,$B5,$5A,$00,$95,$7A,$A5,$5E,$B5,$55,$5D,$57,$AD,$55,$57,$A8,$2D,$57,$FF,$EA,$A0,$00,$00,$00,$00
  .BYTE $55,$55,$55,$55,$56,$00,$EA,$C0,$3A,$B0,$00,$00,$EA,$55,$55,$55,$B0,$0A,$55,$C0,$3A,$A0,$0E,$B0,$00,$00,$03,$AC,$00,$03,$A9,$6C,$00,$00,$39,$55,$55,$55,$55,$55
  .BYTE $55,$55,$55,$55,$56,$00,$EA,$C0,$3A,$AC,$00,$03,$EA,$55,$55,$55,$B0,$0A,$55,$C0,$3A,$B0,$0E,$B0,$00,$00,$03,$AC,$00,$03,$A9,$6B,$00,$00,$3A,$55,$55,$55,$55,$55
  .BYTE $00,$00,$00,$00,$03,$55,$AA,$95,$6F,$F9,$55,$56,$BF,$00,$00,$00,$E5,$5F,$00,$95,$6A,$A5,$5B,$E5,$59,$55,$56,$F9,$55,$56,$F0,$0E,$55,$55,$5B,$00,$00,$00,$00,$00
  .BYTE $55,$55,$55,$55,$5E,$00,$00,$00,$0A,$A0,$00,$00,$2B,$55,$55,$55,$80,$0A,$57,$80,$00,$00,$02,$80,$00,$00,$00,$A0,$00,$00,$A5,$5A,$00,$00,$02,$D5,$55,$55,$55,$55
  .BYTE $55,$55,$55,$55,$5E,$00,$00,$00,$0A,$80,$00,$00,$0B,$55,$55,$57,$80,$0A,$D7,$80,$00,$00,$02,$80,$00,$00,$00,$A0,$00,$00,$A5,$5E,$80,$00,$02,$B5,$55,$55,$55,$55
  .BYTE $55,$55,$55,$55,$5E,$00,$00,$00,$0A,$80,$00,$00,$0B,$55,$55,$57,$80,$0A,$D7,$80,$00,$00,$02,$80,$08,$00,$00,$A0,$00,$00,$25,$56,$80,$00,$00,$B5,$55,$55,$55,$55
  .BYTE $55,$55,$55,$55,$5E,$00,$00,$00,$0A,$00,$00,$00,$0B,$55,$55,$55,$80,$0A,$57,$80,$00,$00,$02,$80,$08,$00,$00,$A0,$00,$00,$2D,$57,$80,$00,$00,$B5,$55,$55,$55,$55
  .BYTE $55,$55,$55,$55,$56,$00,$00,$00,$3A,$C0,$3A,$B0,$0E,$55,$55,$55,$B0,$0A,$55,$C0,$00,$00,$0E,$B0,$0E,$00,$03,$AC,$03,$C0,$E9,$55,$AF,$FC,$00,$A5,$55,$55,$55,$55
  .BYTE $55,$55,$55,$55,$57,$00,$00,$00,$3A,$C0,$3A,$B0,$0E,$55,$55,$55,$80,$0A,$55,$C0,$00,$00,$0E,$B0,$0E,$00,$03,$AC,$03,$C0,$39,$55,$6A,$AB,$00,$A5,$55,$55,$55,$55
  .BYTE $55,$55,$55,$55,$57,$00,$00,$00,$3A,$C0,$3A,$B0,$0E,$55,$55,$55,$80,$0A,$55,$C0,$00,$00,$0E,$B0,$0E,$C0,$03,$AC,$03,$C0,$39,$6A,$AA,$AB,$00,$A5,$55,$55,$55,$55
  .BYTE $00,$00,$00,$00,$02,$55,$FF,$D5,$7A,$D5,$6A,$B5,$5E,$00,$00,$00,$B5,$5A,$00,$95,$7F,$F5,$5E,$B5,$5E,$D5,$57,$AD,$57,$B5,$78,$2A,$AA,$AB,$55,$A0,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$02,$55,$AA,$95,$6F,$95,$6F,$E5,$5B,$00,$00,$00,$E5,$5F,$00,$95,$6F,$E5,$5B,$E5,$5B,$95,$56,$F9,$56,$D5,$6F,$3A,$AA,$FE,$55,$F0,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$03,$55,$EA,$D5,$7A,$D5,$78,$B5,$5E,$00,$00,$00,$95,$5A,$00,$D5,$7A,$B5,$5E,$B5,$5E,$B5,$57,$AD,$57,$B5,$5E,$2D,$57,$AB,$55,$A0,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$03,$55,$EA,$D5,$7A,$D5,$78,$B5,$5E,$00,$00,$00,$95,$5A,$00,$D5,$7A,$B5,$5E,$B5,$5E,$B5,$57,$AD,$57,$B5,$5E,$2D,$57,$8B,$55,$E0,$00,$00,$00,$00
  .BYTE $55,$55,$55,$55,$57,$00,$EA,$C0,$3A,$00,$3A,$B0,$0E,$55,$55,$55,$80,$0A,$55,$C0,$3A,$B0,$0E,$B0,$0E,$B0,$00,$AC,$03,$B0,$0E,$AC,$03,$9B,$00,$E5,$55,$55,$55,$55
  .BYTE $55,$55,$55,$55,$57,$00,$EA,$C0,$3A,$00,$3A,$B0,$0E,$55,$55,$55,$80,$0A,$55,$C0,$3A,$B0,$0E,$B0,$0E,$B0,$00,$AC,$03,$AC,$03,$AC,$03,$AB,$00,$E5,$55,$55,$55,$55
  .BYTE $55,$55,$55,$55,$57,$00,$EA,$C0,$3A,$00,$3F,$C0,$0E,$55,$55,$55,$80,$0A,$55,$C0,$0A,$70,$02,$B0,$0E,$A0,$00,$AC,$03,$AC,$03,$AC,$03,$A8,$00,$E5,$55,$55,$55,$55
  .BYTE $00,$00,$00,$00,$02,$55,$BC,$95,$6F,$95,$6A,$95,$5B,$00,$00,$00,$E5,$5F,$00,$95,$6F,$25,$5B,$E5,$5B,$F9,$56,$F9,$56,$F9,$56,$F9,$56,$A9,$55,$B0,$00,$00,$00,$00
  .BYTE $55,$55,$55,$55,$57,$00,$EA,$C0,$3A,$C0,$00,$00,$0E,$55,$55,$55,$B0,$0A,$55,$C0,$3A,$60,$0E,$B0,$0E,$AC,$03,$AC,$03,$A8,$03,$AC,$00,$FC,$00,$A5,$55,$55,$55,$55
  .BYTE $55,$55,$55,$55,$5B,$00,$EA,$C0,$3A,$C0,$00,$00,$3A,$55,$55,$55,$80,$0A,$56,$C0,$3A,$70,$0E,$B0,$0E,$A8,$03,$AC,$03,$AB,$00,$EC,$00,$00,$00,$E5,$55,$55,$55,$55
  .BYTE $55,$55,$55,$55,$57,$00,$EA,$C0,$3A,$F0,$00,$00,$3A,$55,$55,$55,$80,$0A,$55,$C0,$3A,$70,$0E,$B0,$0E,$58,$03,$AC,$03,$AB,$00,$EB,$00,$00,$03,$A5,$55,$55,$55,$55
  .BYTE $00,$00,$00,$00,$03,$55,$EA,$D5,$7A,$B5,$55,$55,$EA,$00,$00,$00,$95,$5A,$00,$D5,$7A,$35,$5E,$B5,$5E,$09,$57,$AD,$57,$8B,$55,$EB,$55,$55,$5F,$A0,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$03,$55,$EA,$D5,$7A,$BD,$55,$55,$EA,$00,$00,$00,$95,$5A,$00,$D5,$7A,$35,$5E,$B5,$5E,$09,$57,$AD,$57,$8B,$55,$EA,$D5,$55,$5E,$A0,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$03,$55,$EA,$D5,$7A,$2D,$55,$57,$EA,$00,$00,$00,$95,$5A,$00,$D5,$7A,$35,$5E,$B5,$5E,$0D,$55,$AD,$57,$8B,$55,$EA,$D5,$55,$5E,$A0,$00,$00,$00,$00
  .BYTE $55,$55,$55,$55,$5B,$00,$2A,$C0,$0A,$6C,$00,$00,$AA,$55,$55,$55,$80,$0E,$55,$C0,$0A,$70,$02,$80,$0E,$5C,$00,$A0,$03,$9B,$00,$EA,$C0,$00,$0A,$A5,$55,$55,$55,$55
  .BYTE $55,$55,$55,$55,$5C,$00,$2F,$00,$0B,$78,$00,$00,$A9,$55,$55,$55,$80,$0A,$57,$80,$0B,$E0,$02,$80,$02,$D8,$00,$A0,$00,$BC,$00,$2F,$80,$00,$0A,$B5,$55,$55,$55,$55
  .BYTE $55,$55,$55,$55,$5E,$AA,$8F,$2A,$A3,$50,$00,$00,$0D,$55,$55,$55,$00,$00,$57,$00,$03,$C0,$00,$00,$00,$D0,$00,$00,$00,$3C,$AA,$8D,$2A,$AA,$A0,$15,$55,$55,$55,$55
  .BYTE $55,$55,$55,$55,$5E,$00,$0B,$80,$02,$58,$00,$00,$0D,$55,$55,$55,$E0,$00,$D5,$C0,$02,$78,$00,$20,$00,$9E,$00,$08,$00,$2E,$00,$09,$80,$00,$00,$D5,$55,$55,$55,$55
  .BYTE $D5,$55,$55,$55,$55,$80,$09,$40,$02,$5C,$00,$00,$25,$55,$55,$55,$60,$00,$DD,$60,$02,$58,$00,$30,$00,$96,$00,$0C,$00,$27,$00,$09,$C0,$00,$02,$55,$55,$55,$55,$55
  .BYTE $00,$00,$00,$00,$00,$55,$58,$15,$56,$02,$55,$55,$70,$00,$00,$00,$35,$55,$C0,$25,$56,$09,$55,$75,$55,$82,$55,$51,$55,$63,$55,$58,$35,$55,$57,$00,$00,$00,$00,$00
  .BYTE $30,$00,$00,$00,$00,$AA,$A4,$2A,$A9,$03,$95,$55,$40,$00,$00,$00,$35,$55,$C0,$35,$57,$0D,$55,$75,$55,$C3,$55,$5D,$AA,$B3,$AA,$AC,$CA,$AA,$AB,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$15,$45,$40,$00,$00,$00,$04,$00,$00,$00,$00,$01,$55,$01,$54,$00,$40,$00,$05,$40,$54,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $55,$55,$55,$55,$55,$55,$45,$50,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$55,$55,$51,$55,$55,$55,$55,$55
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$15,$55,$55,$55,$55,$56,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$A9,$55,$55,$55,$40,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $AA,$A5,$55,$55,$55,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$11,$55,$55,$55,$AA,$AA
  .BYTE $AA,$AA,$AA,$AA,$95,$55,$55,$55,$55,$55,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$15,$55,$55,$55,$55,$5A,$AA,$AA,$AA,$AA
  .BYTE $55,$55,$55,$55,$55,$55,$5A,$AA,$AA,$AA,$AA,$AA,$AA,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$AA,$AA,$AA,$AA,$AA,$AA,$95,$55,$55,$55,$55,$55,$55
  .BYTE $45,$55,$55,$55,$55,$55,$55,$55,$55,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$55,$55,$55,$55,$55,$55,$54,$00,$00
  .BYTE $55,$50,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$55,$55
  .BYTE $55,$55,$55,$55,$5A,$AA,$AA,$A8,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$02,$AA,$AA,$AA,$55,$55,$55,$55,$55
  .BYTE $55,$55,$55,$55,$55,$AA,$A8,$00,$0A,$00,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$2A,$00,$00,$00,$00,$00,$00,$0A,$AA,$A8,$AA,$AA,$A9,$55,$55,$55,$55,$55
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $55,$55,$55,$55,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$05,$55,$55,$55
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$06,$15,$55,$55,$41,$55,$01,$55,$55,$55,$51,$40,$04,$00,$05,$15,$10,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$25,$00,$00,$00,$25,$55,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $55,$55,$55,$55,$00,$00,$15,$00,$00,$00,$00,$00,$01,$AA,$40,$00,$00,$2A,$AA,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$40,$00,$40,$55,$55,$55,$55,$55
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$02,$55,$80,$00,$00,$15,$55,$40,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$02,$69,$80,$00,$00,$95,$55,$60,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$02,$55,$80,$00,$00,$B5,$55,$60,$A8,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$02,$55,$80,$00,$00,$95,$55,$60,$56,$00,$00,$00,$00,$00,$00,$00,$00,$20,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$70,$C0,$00,$0A,$D5,$55,$55,$7F,$AA,$00,$00,$00,$00,$00,$00,$02,$D4,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$0A,$C0,$02,$AD,$55,$55,$55,$75,$57,$A0,$00,$00,$00,$02,$AA,$AD,$57,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$40,$21,$5F,$FD,$55,$55,$57,$FF,$4A,$AA,$8A,$AA,$A9,$55,$5F,$FD,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$40,$3A,$A5,$69,$55,$55,$55,$55,$9F,$FF,$D7,$FF,$FE,$AA,$A9,$69,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$40,$19,$55,$65,$55,$55,$55,$55,$9E,$AA,$AA,$AA,$A9,$55,$59,$69,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$10,$05,$55,$65,$55,$55,$55,$55,$99,$65,$59,$55,$55,$56,$FF,$EE,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$F0,$3A,$AA,$A5,$55,$55,$55,$55,$A9,$65,$59,$55,$5A,$AA,$3C,$63,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$A0,$25,$55,$55,$55,$55,$55,$55,$55,$56,$65,$55,$54,$A8,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$F0,$39,$55,$A9,$55,$55,$55,$56,$A9,$6A,$A9,$55,$50,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$0C,$C9,$55,$A5,$55,$55,$55,$56,$9A,$AA,$A7,$FF,$F0,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$1C,$C9,$55,$A9,$55,$55,$55,$5A,$AA,$AF,$FC,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$20,$25,$55,$55,$55,$55,$55,$55,$58,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$B0,$35,$55,$55,$55,$55,$55,$55,$5A,$A8,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$10,$0E,$AB,$A5,$55,$55,$55,$65,$91,$54,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$2C,$3A,$A9,$56,$AA,$55,$55,$55,$69,$55,$EC,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$E0,$0F,$FE,$56,$AA,$55,$55,$55,$56,$AA,$5B,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $55,$55,$54,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$24,$00,$02,$FF,$FF,$EA,$AA,$AA,$AA,$AA,$AD,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$55,$55,$55,$55
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$13,$F6,$AA,$A5,$55,$55,$55,$55,$55,$55,$59,$01,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$0A,$95,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$5D,$70,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$0A,$AA,$A5,$55,$55,$55,$55,$55,$55,$55,$55,$5A,$A5,$90,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$1A,$95,$55,$55,$55,$55,$55,$55,$55,$55,$55,$56,$56,$90,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$E5,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$56,$AA,$AB,$C0,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$E5,$55,$55,$AA,$A5,$55,$55,$55,$55,$55,$AA,$AA,$95,$56,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$25,$6E,$FE,$AA,$A5,$55,$5A,$AA,$AA,$AA,$55,$55,$55,$55,$90,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $01,$01,$14,$50,$55,$55,$11,$40,$11,$15,$04,$15,$47,$EA,$AA,$AA,$FF,$EA,$AA,$AA,$AA,$AA,$AA,$FA,$AA,$AA,$AB,$E0,$55,$41,$50,$44,$54,$41,$01,$10,$00,$00,$10,$04
  .BYTE $14,$00,$15,$44,$00,$00,$01,$04,$04,$45,$55,$50,$46,$BB,$FF,$FA,$AA,$AA,$AA,$BF,$FF,$FF,$FF,$EA,$AA,$AA,$AA,$FC,$15,$45,$45,$01,$50,$05,$00,$11,$55,$44,$00,$04
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$02,$AA,$AA,$AA,$AA,$BF,$FF,$FF,$FF,$D5,$55,$55,$55,$55,$55,$BC,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$59,$55,$5F,$FF,$F5,$55,$55,$55,$6A,$AA,$AA,$AA,$A9,$56,$BC,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$02,$D6,$AA,$AA,$7F,$F5,$55,$55,$55,$55,$55,$55,$55,$56,$A9,$7A,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$02,$6A,$AA,$AD,$55,$55,$55,$55,$55,$55,$55,$55,$B5,$5A,$AA,$58,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$02,$A9,$55,$55,$55,$55,$55,$55,$55,$69,$55,$56,$25,$5A,$E6,$98,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$03,$95,$55,$55,$55,$55,$57,$55,$55,$69,$55,$57,$25,$71,$E6,$90,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$0B,$95,$55,$55,$55,$55,$58,$95,$55,$82,$55,$56,$35,$63,$FC,$D8,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$3A,$55,$55,$55,$A5,$55,$5C,$95,$55,$7E,$55,$55,$25,$6B,$F2,$98,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$29,$55,$55,$55,$35,$55,$58,$95,$55,$6D,$55,$55,$55,$76,$3D,$98,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$F9,$55,$55,$56,$35,$55,$58,$95,$55,$55,$55,$55,$55,$76,$0D,$98,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$E9,$6A,$95,$56,$35,$55,$56,$55,$55,$55,$55,$55,$55,$7B,$0E,$D8,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$9D,$7A,$95,$55,$B5,$55,$55,$55,$55,$55,$55,$55,$55,$7A,$EE,$DC,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$0D,$AA,$B5,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$61,$B7,$90,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$09,$B7,$A5,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$59,$66,$D0,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$09,$AF,$69,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$5A,$BE,$60,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$05,$90,$A9,$55,$55,$55,$55,$55,$55,$55,$55,$55,$57,$56,$09,$40,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$05,$AF,$B9,$55,$55,$55,$55,$55,$55,$55,$55,$69,$5B,$95,$A5,$40,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$05,$FF,$A9,$55,$55,$55,$55,$55,$5A,$96,$F5,$B2,$6F,$D6,$55,$C0,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$0F,$BA,$FD,$55,$55,$55,$F5,$6B,$58,$96,$0D,$8A,$72,$38,$57,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$09,$FF,$E5,$55,$5F,$D7,$25,$EB,$7A,$96,$AD,$AA,$7A,$BB,$5C,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $14,$15,$54,$50,$00,$00,$00,$05,$15,$00,$00,$05,$46,$FB,$9A,$B6,$AC,$EB,$5E,$D5,$B5,$69,$5E,$D7,$B5,$6A,$A4,$40,$00,$05,$54,$14,$00,$00,$15,$40,$01,$41,$55,$54
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$02,$BD,$FE,$D5,$B5,$69,$56,$55,$B5,$69,$5E,$55,$B5,$6A,$90,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$02,$E5,$62,$95,$E5,$6D,$5B,$55,$E5,$6D,$5B,$55,$F4,$BF,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$03,$55,$82,$8F,$63,$27,$CD,$CF,$63,$E7,$09,$82,$5A,$96,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$95,$82,$8F,$63,$24,$F9,$83,$5C,$96,$F5,$69,$55,$58,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$35,$5D,$EA,$5A,$97,$25,$6B,$57,$55,$55,$55,$55,$5C,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $AA,$AA,$A8,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$09,$55,$C2,$58,$97,$B5,$7D,$55,$55,$55,$55,$55,$E0,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$0A,$AA,$AA
  .BYTE $AA,$AA,$AA,$80,$00,$00,$00,$00,$15,$55,$55,$55,$55,$56,$FF,$C2,$FE,$BF,$FF,$FF,$FF,$FF,$FA,$AA,$AA,$15,$55,$55,$55,$55,$54,$00,$00,$00,$00,$00,$08,$AA,$AA,$AA
  .BYTE $00,$00,$00,$00,$00,$05,$55,$55,$55,$55,$55,$50,$05,$54,$7A,$AA,$AA,$AA,$AA,$AA,$FF,$FF,$F0,$00,$00,$14,$00,$05,$55,$55,$55,$50,$55,$55,$45,$55,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$05,$55,$55,$55,$55,$55,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$AA,$AA,$45,$41,$54,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $55,$55,$55,$54,$00,$00,$44,$50,$40,$00,$00,$82,$28,$A0,$00,$FF,$FF,$8A,$00,$02,$82,$2A,$A0,$82,$AA,$8A,$80,$82,$84,$11,$00,$10,$50,$50,$45,$54,$55,$55,$55,$55
  .BYTE $10,$41,$41,$14,$00,$05,$40,$01,$44,$05,$51,$10,$00,$05,$55,$54,$55,$40,$11,$40,$04,$40,$04,$14,$04,$00,$11,$54,$00,$00,$15,$00,$51,$40,$40,$04,$11,$01,$44,$00
  .BYTE $40,$15,$10,$40,$00,$14,$44,$10,$41,$14,$55,$44,$10,$55,$54,$11,$05,$50,$05,$50,$41,$14,$11,$04,$55,$40,$04,$51,$04,$00,$05,$10,$40,$40,$00,$00,$00,$01,$00,$01
  .BYTE $55,$00,$55,$55,$11,$00,$44,$40,$45,$04,$40,$45,$11,$01,$00,$41,$00,$00,$00,$00,$50,$00,$10,$00,$00,$05,$50,$00,$04,$14,$40,$14,$40,$00,$45,$04,$51,$05,$55,$55
  .BYTE $10,$51,$45,$01,$40,$00,$00,$00,$00,$40,$11,$10,$44,$14,$51,$04,$51,$55,$11,$55,$04,$45,$44,$51,$54,$10,$01,$15,$50,$00,$00,$40,$00,$00,$00,$00,$11,$01,$04,$40
  .BYTE $14,$05,$45,$55,$55,$55,$11,$05,$10,$41,$00,$11,$44,$10,$01,$14,$40,$00,$11,$00,$04,$41,$04,$10,$00,$15,$41,$00,$11,$45,$00,$05,$11,$05,$15,$55,$55,$55,$54,$14
  .BYTE $05,$50,$10,$00,$00,$00,$11,$10,$00,$51,$04,$00,$00,$10,$00,$00,$54,$10,$04,$45,$01,$00,$00,$15,$00,$00,$00,$04,$51,$00,$00,$45,$10,$00,$00,$00,$00,$00,$01,$40
  .BYTE $14,$40,$45,$10,$51,$00,$04,$45,$00,$51,$10,$10,$44,$54,$45,$04,$51,$45,$51,$45,$14,$45,$44,$55,$55,$11,$01,$15,$51,$04,$04,$14,$40,$04,$50,$04,$11,$01,$04,$50
  .BYTE $05,$00,$00,$40,$14,$40,$44,$40,$01,$04,$40,$44,$11,$40,$14,$51,$14,$11,$54,$11,$51,$14,$51,$04,$15,$45,$00,$41,$04,$50,$40,$15,$44,$00,$44,$00,$54,$00,$00,$41
  .BYTE $15,$40,$00,$40,$04,$00,$11,$01,$04,$55,$04,$10,$55,$54,$55,$55,$55,$51,$54,$11,$55,$10,$14,$15,$55,$54,$00,$14,$51,$55,$00,$45,$00,$01,$00,$41,$44,$00,$00,$00
  .BYTE $41,$11,$10,$00,$05,$55,$01,$55,$55,$04,$00,$44,$00,$00,$04,$51,$00,$10,$05,$10,$41,$14,$11,$04,$50,$45,$14,$41,$04,$00,$55,$54,$05,$55,$05,$44,$45,$55,$55,$41
  .BYTE $15,$55,$44,$00,$45,$54,$11,$55,$14,$41,$05,$11,$44,$14,$01,$10,$00,$44,$00,$01,$00,$41,$04,$10,$00,$10,$45,$14,$51,$01,$55,$55,$11,$55,$55,$50,$40,$00,$55,$54
  .BYTE $40,$11,$10,$01,$44,$55,$55,$05,$50,$51,$14,$45,$14,$45,$54,$41,$55,$11,$45,$50,$40,$11,$51,$45,$00,$04,$10,$10,$04,$55,$00,$41,$05,$55,$00,$50,$44,$54,$00,$00
  .BYTE $00,$00,$40,$45,$41,$55,$51,$45,$50,$01,$05,$00,$44,$10,$00,$04,$50,$04,$11,$00,$04,$41,$04,$10,$00,$10,$40,$04,$51,$05,$10,$05,$11,$55,$55,$51,$10,$00,$00,$00
  .BYTE $AA,$AA,$AA,$00,$00,$00,$00,$11,$05,$04,$01,$44,$10,$14,$00,$01,$54,$40,$11,$01,$05,$05,$05,$14,$54,$45,$54,$41,$55,$54,$45,$04,$44,$00,$00,$00,$8A,$AA,$AA,$AA
  .BYTE $55,$55,$55,$55,$55,$AA,$AA,$AA,$AA,$AA,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$0A,$AA,$AA,$9A,$A9,$55,$55,$55,$55,$55,$55
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$04,$00,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$44,$00,$55,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$15,$55,$55,$55,$55,$55,$54,$55,$55,$55,$54,$01,$40,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$00,$00,$00,$51,$00,$05,$00,$00,$00,$00,$54,$45,$40,$01,$14,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$04,$15,$00,$04,$40,$00,$00,$01,$55,$05,$54,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$15,$55,$41,$55,$55,$41,$45,$41,$55,$41,$55,$45,$01,$41,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$40,$00,$00,$00,$00,$15,$50,$55,$55,$55,$54,$55,$55,$55,$51,$55,$55,$55,$55,$01,$55,$40,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$45,$55,$55,$55,$50,$15,$55,$55,$55,$55,$54,$00,$50,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$55,$55,$55,$55,$54,$15,$55,$54,$55,$55,$55,$45,$55,$55,$50,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$55,$55,$55,$55,$55,$15,$45,$55,$54,$55,$55,$05,$55,$54,$50,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$52,$90,$29,$28,$4A,$15,$54,$A1,$80,$52,$42,$84,$08,$50,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$95,$A5,$69,$54,$D6,$35,$80,$02,$5C,$55,$8D,$05,$71,$56,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$D9,$B6,$6D,$A8,$96,$25,$80,$02,$58,$96,$C5,$C5,$92,$58,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$92,$64,$99,$C3,$79,$DB,$7F,$CD,$87,$14,$26,$46,$18,$90,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$9B,$64,$D9,$A2,$60,$1C,$00,$01,$C0,$34,$1C,$77,$98,$D0,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$0C,$D5,$B5,$6D,$58,$96,$25,$8C,$32,$58,$24,$1B,$75,$60,$93,$C0,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$9A,$25,$41,$A0,$29,$0A,$40,$00,$A4,$24,$15,$65,$60,$90,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$23,$19,$82,$3C,$76,$10,$80,$01,$09,$DB,$25,$99,$90,$60,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$DC,$34,$61,$A8,$65,$1A,$40,$01,$64,$24,$1C,$77,$90,$90,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$14,$74,$19,$E6,$A8,$EB,$3A,$C5,$53,$AC,$38,$6D,$9B,$64,$F1,$50,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$00,$01,$00,$40,$15,$54,$01,$40,$41,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$10,$14,$11,$54,$10,$00,$05,$50,$51,$40,$54,$04,$10,$50,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00

.ORG $A800

TITLE_COLBK:
  .BYTE $00,$00,$00,$84,$85,$84,$85,$85
  .BYTE $85,$85,$85,$85,$85,$85,$85,$85
  .BYTE $85,$85,$85,$85,$85,$85,$85,$85
  .BYTE $85,$85,$85,$84,$85,$EB,$EB,$1A
  .BYTE $EB,$EB,$EB,$EB,$EB,$EB,$EB,$EB
  .BYTE $85,$84,$84,$84,$84,$84,$EB,$EB
  .BYTE $84,$1A,$1A,$1A,$1A,$EB,$EB,$EB
  .BYTE $84,$84,$84,$84,$EB,$EB,$1A,$84
  .BYTE $EB,$EB,$EB,$84,$84,$84,$28,$27
  .BYTE $01,$00,$00,$85,$85,$85,$85,$85
  .BYTE $85,$85,$85,$84,$84,$09,$06,$08
  .BYTE $08,$06,$1A,$19,$19,$19,$19,$19
  .BYTE $19,$19,$19,$1A,$1B,$19,$1B,$1A
  .BYTE $19,$EB,$EB,$EB,$EB,$EB,$EB,$EB
  .BYTE $EB,$EB,$EB,$EB,$EB,$EB,$EB,$EB
  .BYTE $EB,$EB,$EB,$1A,$19,$19,$19,$18
  .BYTE $18,$18,$18,$18,$19,$18,$18,$18
  .BYTE $18,$E8,$06,$06,$06,$06,$06,$06
  .BYTE $07,$06,$06,$07,$06,$07,$07,$06
  .BYTE $07,$07,$07,$07,$06,$06,$07,$06
  .BYTE $04,$04,$04,$04,$05,$E4,$E4,$E5
  .BYTE $E4,$E5,$E4,$E4,$E4,$E4,$E5,$E5
  .BYTE $E4,$E4,$E4,$E4,$E2,$E2,$E2,$E2
  .BYTE $E2,$E2,$E2,$E2,$E2,$E2,$E2,$E2
  .BYTE $E2,$E2,$E2,$E2,$E2,$E2,$E2,$E2
  .BYTE $E2,$E2,$E2,$E2,$E2,$E2,$E2,$E2
TITLE_PF0:
  .BYTE $10,$10,$90,$00,$83,$85,$84,$84
  .BYTE $84,$84,$84,$84,$83,$84,$84,$84
  .BYTE $84,$84,$84,$84,$84,$84,$84,$00
  .BYTE $02,$01,$27,$27,$1A,$84,$85,$85
  .BYTE $85,$85,$85,$85,$84,$85,$85,$85
  .BYTE $EB,$EB,$EB,$EB,$EB,$EB,$84,$85
  .BYTE $EB,$85,$85,$85,$85,$85,$84,$84
  .BYTE $EB,$EB,$EB,$EB,$84,$84,$84,$EB
  .BYTE $84,$85,$84,$EB,$EB,$1B,$85,$85
  .BYTE $85,$85,$85,$00,$92,$00,$84,$00
  .BYTE $00,$00,$00,$85,$06,$08,$07,$06
  .BYTE $09,$07,$07,$1A,$00,$00,$00,$00
  .BYTE $00,$00,$00,$19,$1A,$E0,$1A,$05
  .BYTE $03,$02,$04,$01,$03,$05,$05,$05
  .BYTE $06,$06,$04,$06,$05,$05,$05,$05
  .BYTE $05,$03,$02,$19,$05,$04,$05,$05
  .BYTE $05,$05,$05,$E9,$18,$00,$01,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$06,$05,$05,$00,$00,$00,$00
  .BYTE $05,$03,$00,$03,$E4,$E5,$E5,$E4
  .BYTE $E5,$E4,$E5,$E5,$E5,$E5,$E4,$E4
  .BYTE $E5,$E5,$E5,$E2,$E3,$00,$E3,$E3
  .BYTE $E3,$E3,$E3,$E3,$E3,$E3,$E3,$0A
  .BYTE $0D,$0C,$0D,$0D,$0D,$07,$0C,$E3
  .BYTE $E3,$E3,$00,$00,$00,$00,$00,$00
TITLE_PF1:
  .BYTE $20,$20,$01,$90,$01,$91,$82,$82
  .BYTE $83,$83,$83,$83,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$10
  .BYTE $91,$11,$11,$29,$02,$01,$02,$11
  .BYTE $01,$26,$28,$10,$01,$01,$01,$01
  .BYTE $02,$25,$01,$01,$01,$02,$01,$E0
  .BYTE $27,$10,$11,$11,$11,$10,$01,$01
  .BYTE $10,$27,$01,$01,$01,$01,$01,$27
  .BYTE $02,$02,$01,$01,$01,$01,$01,$01
  .BYTE $11,$90,$90,$90,$90,$10,$00,$10
  .BYTE $10,$10,$10,$00,$07,$07,$08,$07
  .BYTE $00,$00,$08,$29,$10,$10,$10,$10
  .BYTE $10,$10,$10,$00,$E6,$18,$04,$18
  .BYTE $E8,$EA,$E9,$EC,$EC,$EC,$02,$01
  .BYTE $02,$02,$E8,$03,$02,$03,$E8,$EC
  .BYTE $02,$E5,$05,$06,$E0,$1A,$03,$02
  .BYTE $00,$01,$02,$03,$01,$01,$00,$05
  .BYTE $03,$03,$05,$03,$03,$04,$03,$02
  .BYTE $05,$02,$04,$03,$03,$04,$02,$05
  .BYTE $05,$01,$01,$03,$02,$03,$05,$05
  .BYTE $03,$00,$20,$00,$04,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$E3,$E3,$00,$10,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$E1,$E4
  .BYTE $0A,$06,$04,$08,$06,$0D,$09,$0B
  .BYTE $00,$00,$10,$10,$10,$10,$10,$10
TITLE_PF2:
  .BYTE $30,$30,$10,$92,$90,$00,$00,$00
  .BYTE $00,$00,$00,$00,$10,$10,$10,$10
  .BYTE $10,$10,$10,$10,$10,$10,$10,$20
  .BYTE $84,$92,$90,$02,$27,$27,$28,$91
  .BYTE $26,$01,$10,$27,$27,$27,$27,$27
  .BYTE $27,$01,$27,$27,$27,$28,$27,$27
  .BYTE $01,$91,$83,$82,$91,$26,$26,$26
  .BYTE $27,$01,$26,$26,$25,$25,$25,$01
  .BYTE $27,$26,$26,$26,$26,$25,$24,$91
  .BYTE $91,$83,$84,$82,$84,$20,$10,$20
  .BYTE $20,$20,$20,$10,$00,$00,$00,$00
  .BYTE $10,$10,$00,$00,$20,$20,$20,$20
  .BYTE $20,$20,$20,$10,$00,$00,$00,$30
  .BYTE $00,$00,$30,$E5,$E6,$03,$E8,$00
  .BYTE $00,$EA,$30,$EA,$EC,$EC,$30,$E8
  .BYTE $00,$EA,$EC,$01,$1A,$15,$00,$20
  .BYTE $E8,$E8,$00,$05,$05,$05,$05,$10
  .BYTE $10,$10,$03,$05,$05,$05,$05,$05
  .BYTE $04,$05,$03,$05,$10,$05,$05,$02
  .BYTE $03,$04,$03,$00,$05,$05,$03,$02
  .BYTE $00,$01,$30,$10,$03,$10,$10,$10
  .BYTE $10,$10,$10,$10,$10,$10,$10,$10
  .BYTE $10,$10,$00,$00,$10,$20,$10,$10
  .BYTE $10,$10,$10,$10,$10,$10,$00,$06
  .BYTE $05,$E3,$07,$E3,$00,$E1,$05,$06
  .BYTE $10,$10,$20,$20,$20,$20,$20,$20
; <<< GENERATED TITLE SCREEN


.RUN START
