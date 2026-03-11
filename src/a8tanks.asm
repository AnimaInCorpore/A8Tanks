; =============================================================================
; A8Tanks — Atari 800 XL tank game
; Built with jsA8E / MADS assembler.  Entry point: $2000.
; =============================================================================
;
; ATARI SCREEN CODE CHEAT-SHEET
;   Screen RAM holds "internal" codes, not ATASCII.
;   Formula:  screen_code = ATASCII - $20   (for printable chars $20..$7F)
;   Inverse-video variant: add $80 to any screen code (bits become inverted).
;
;   Common codes (decimal):
;     0  = space      10 = * 13 = -      29 = =      32 = @
;    33  = A          34 = B  ... 58 = Z
;    16  = 0          17 = 1  ... 25 = 9
;   128  = solid block (inverse space — useful as a filled tile)
;
;   STRING TERMINATOR: use $FF (255) — NOT $00, because $00 means space.
;
;   To encode a new string, subtract 32 from each ASCII value:
;     e.g. "GAME OVER" → G=39 A=33 M=45 E=37 ' '=0 O=47 V=54 E=37 R=50
;
; ATARI COLOR BYTE FORMAT
;   Bits 7-4 : hue   (0=grey, 1=gold, 2=orange, 4=pink, 7=blue,
;                     8=cyan, 9=teal, B=green, D=yellow, F=red)
;   Bits 3-1 : luminance  0=darkest … 7=brightest  (stored as lum*2)
;   Bit  0   : unused (always 0)
;
;   Useful values:  $00=black  $0E=dark grey  $1C=bright gold  $28=orange
;                   $38=peach  $86=dark blue  $94=navy  $B8=bright green
;
;   In GR.0 (ANTIC mode 2, 40×24 text):
;     COLBK  ($D01A) = background color
;     COLPF2 ($D018) = text/foreground color
;     To vary colors per scan-line, install a Display List Interrupt (DLI)
;     and poke COLPF2/COLBK inside the NMI handler.
;
; SCREEN LAYOUT 
;   Memory is linear. 
;   Antic Mode 6 (GR.1) uses 20 bytes per row.
;   Antic Mode 2 (GR.0) uses 40 bytes per row.
;
; =============================================================================

.ORG $2000

; ---------------------------------------------------------------------------
; Hardware registers
; ---------------------------------------------------------------------------
CONSOL = $D01F    ; Console keys (bits: 2=SELECT 1=OPTION 0=START); 0 = pressed
SAVMSC = $58      ; OS zero-page pointer: lo/hi address of screen RAM
SDLSTL = $0230    ; Shadow for Display List List pointer (lo/hi)

; Corrected Shadow color registers
COLOR0 = $02C4    ; Shadow for COLPF0
COLOR1 = $02C5    ; Shadow for COLPF1
COLOR2 = $02C6    ; Shadow for COLPF2
COLOR4 = $02C8    ; Shadow for COLBK

COLPF0 = $D016    ; Hardware Playfield color 0
COLPF1 = $D017    ; Hardware Playfield color 1
COLPF2 = $D018    ; Hardware Playfield color 2
COLBK  = $D01A    ; Hardware Background color

NMIEN  = $D40E    ; NMI Enable (bit 7=DLI, 6=VBLANK)
VDSLST = $0200    ; Vector for Display List Interrupt (DLI)

RTCLOK = $0014    ; OS real-time clock (low byte increments every frame)
WSYNC  = $D40A    ; Wait for horizontal sync

; ---------------------------------------------------------------------------
; Screen dimensions
; ---------------------------------------------------------------------------
SCREEN_WIDTH  = $28   ; 40 columns per row (GR.0 max width)
SCREEN_HEIGHT = $18   ; 24 rows

; ---------------------------------------------------------------------------
; Screen offsets (byte offset from screen RAM base)
; ---------------------------------------------------------------------------
TITLE_OFFSET    = $0004 ; Centered in 20-col GR.1 (Row 0)
RULE_TOP_OFFSET = $0014 ; Row 1 (first GR.0 row, starts at byte 20)
PROMPT_OFFSET   = $0158 ; Row 9 (GR.1, 340 bytes in + col 4 = 344)

; =============================================================================
; PROGRAM ENTRY
; =============================================================================

START:
  JSR INIT
  JSR SHOW_TITLE_SCREEN

GAME_LOOP:
  JSR READ_INPUT
  JSR UPDATE_GAME
  JSR DRAW_FRAME
  JMP GAME_LOOP

; ---------------------------------------------------------------------------
; INIT — set up initial game state
; ---------------------------------------------------------------------------
INIT:
  LDA #$50
  STA PLAYER_X
  LDA #$30
  STA PLAYER_Y
  LDA #$00
  STA PLAYER_DIR
  STA FRAME_COUNTER
  
  ; Patch Display List screen RAM address to match OS SAVMSC
  JSR PATCH_DL

  ; Set up Display List
  LDA #<MY_DISPLAY_LIST
  STA SDLSTL
  LDA #>MY_DISPLAY_LIST
  STA SDLSTL+1

  ; Set up DLI
  LDA #<DLI_HANDLER
  STA VDSLST
  LDA #>DLI_HANDLER
  STA VDSLST+1
  LDA #$C0              ; Enable DLI and VBLANK
  STA NMIEN
  RTS

; ---------------------------------------------------------------------------
; INIT_COLORS — set the title-screen palette (using shadow registers)
;   Shadow registers are overridden per-scanline by the DLI during the sky
;   area.  These values take effect below the DLI region (row 12 onward).
; ---------------------------------------------------------------------------
INIT_COLORS:
  LDA #$84      ; Dark blue — matches top-of-sky; colors the 24 blank lines above DLI
  STA COLOR4
  LDA #$00      ; Black background (below DLI region)
  STA COLOR2
  LDA #$0E      ; White text luminance
  STA COLOR1
  LDA #$1C      ; Gold for GR.1 title/prompt (COLOR0)
  STA COLOR0
  RTS

; ---------------------------------------------------------------------------
; DLI_HANDLER — daytime sky horizon effect
;   Fires before the title row, runs for 96 scanlines (~half the screen).
;   Per scanline:
;     COLPF0 = title text color (gold shimmer on first 8 scanlines)
;     COLPF1 = foreground/rule color (white through sky, fades below horizon)
;     COLPF2 = background color (deep blue → light blue → near-white horizon
;                                → quick fade to black below)
;   After loop, shadow registers are restored so PRESS START renders correctly.
; ---------------------------------------------------------------------------
DLI_HANDLER:
  PHA           ; Save A
  TXA
  PHA           ; Save X

  LDX #$00
DLI_LOOP:
  STA WSYNC          ; Wait for next scanline (value in A is irrelevant)
  LDA SKY_PF0,X
  STA COLPF0         ; Title text hue (only visible in Mode 6 rows)
  LDA SKY_PF1,X
  STA COLPF1         ; Foreground / rule line color
  LDA SKY_PF2,X
  STA COLPF2         ; Background color
  INX
  CPX #96
  BNE DLI_LOOP

  ; Restore color registers for the remainder of the frame
  ; (so PRESS START in Mode 6 and any GR.0 rows below render correctly)
  LDA COLOR0         ; $1C gold — used by COLPF0 for Mode 6 text
  STA COLPF0
  LDA COLOR1         ; $0E bright — foreground luminance
  STA COLPF1
  LDA COLOR2         ; $00 black — background
  STA COLPF2

  PLA           ; Restore X
  TAX
  PLA           ; Restore A
  RTI

; ---- Scanline color tables (96 entries each) --------------------------------
;  Scanline layout from DLI fire point:
;    0-7   : title row (Mode 6) — deep blue sky
;    8     : 1 blank scanline ($00 DL byte = 1 blank line)
;    9-16  : rule row — the "horizon" separator
;   17-72  : GR.0 rows 2-8 — slow luminance fade (ground below horizon)
;   73-80  : GR.0 row 9 (Mode 6) — PRESS START prompt
;   81-95  : GR.0 rows 10-11 — black
;
;  Half-screen coverage:
;    COLOR4=$84 colors the 24 OS blank scanlines above the DLI dark blue.
;    SKY_PF2 stays visible (non-zero) through entry ~73, then fades out.
;    24 (blank, dark blue) + 74 (DLI visible) ≈ 98 / 192 total scanlines.
;
;  Color scheme: natural clear-sky day
;    24 blank lines above: dark blue (COLOR4=$84, set in INIT_COLORS)
;    Top of sky (0-7)    : deep blue  ($86→$8E)
;    Mid sky  (8-16)     : lightening blue → near-white
;    Horizon (16-23)     : near-white atmospheric haze peak ($0E)
;    Below (24-73)       : very slow grey fade — ~9 scanlines per luminance step
;    Ground (74-95)      : black

; COLPF0 — title text + PRESS START text (only effective in Mode 6 rows)
;   Title is DLI entries 0-7; PRESS START is entries 73-80.
SKY_PF0:
  .BYTE $1A,$1C,$1E,$1C,$1A,$1C,$1E,$1C  ; 0-7  : title gold shimmer on blue sky
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00  ; 8-15 : not Mode 6
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00  ; 16-23: not Mode 6
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00  ; 24-31: not Mode 6
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00  ; 32-39: not Mode 6
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00  ; 40-47: not Mode 6
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00  ; 48-55: not Mode 6
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00  ; 56-63: not Mode 6
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00  ; 64-71: not Mode 6
  .BYTE $00,$1C,$1C,$1C,$1C,$1C,$1C,$1C  ; 72-79: 73-80 = PRESS START (gold)
  .BYTE $1C,$00,$00,$00,$00,$00,$00,$00  ; 80-87: entry 80 = last sl of prompt
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00  ; 88-95: black

; COLPF1 — foreground / rule line color (white in sky zone + PRESS START blink)
SKY_PF1:
  .BYTE $0E,$0E,$0E,$0E,$0E,$0E,$0E,$0E  ; 0-7  : white in title area
  .BYTE $0E,$0E,$0E,$0E,$0E,$0E,$0E,$0E  ; 8-15 : white in sky gap
  .BYTE $0E,$0E,$0E,$0E,$0E,$0E,$0E,$0E  ; 16-23: white at horizon (rule glows)
  .BYTE $0C,$0A,$08,$06,$04,$02,$00,$00  ; 24-31: below horizon, fading
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00  ; 32-39: black
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00  ; 40-47: black
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00  ; 48-55: black
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00  ; 56-63: black
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00  ; 64-71: black
  .BYTE $00,$0E,$0E,$0E,$0E,$0E,$0E,$0E  ; 72-79: 73-80 = PRESS START blink color
  .BYTE $0E,$00,$00,$00,$00,$00,$00,$00  ; 80-87: entry 80 = last sl of prompt
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00  ; 88-95: black

; COLPF2 — background (sky: deep blue → near-white horizon → very slow fade to black)
;  Below the horizon: 7 luminance steps × ~9 scanlines each = 63 scanlines of fade.
;  Reaches black near entry 73, matching the PRESS START prompt row.
SKY_PF2:
  .BYTE $86,$86,$88,$88,$8A,$8C,$8C,$8E  ; 0-7  : deep blue → medium blue (title row)
  .BYTE $8E,$8E,$7E,$7E,$7E,$0E,$0E,$0E  ; 8-15 : light blue → near-white
  .BYTE $0E,$0E,$0E,$0E,$0E,$0E,$0E,$0E  ; 16-23: near-white (horizon area peak)
  .BYTE $0E,$0E,$0C,$0C,$0C,$0C,$0C,$0C  ; 24-31: just below, starts fading
  .BYTE $0C,$0A,$0A,$0A,$0A,$0A,$0A,$0A  ; 32-39: slow fade continues
  .BYTE $0A,$08,$08,$08,$08,$08,$08,$08  ; 40-47: ~9 sl per luminance step
  .BYTE $08,$06,$06,$06,$06,$06,$06,$06  ; 48-55
  .BYTE $06,$04,$04,$04,$04,$04,$04,$04  ; 56-63
  .BYTE $04,$02,$02,$02,$02,$02,$02,$02  ; 64-71
  .BYTE $02,$02,$00,$00,$00,$00,$00,$00  ; 72-79: fades to black (PRESS START bg)
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00  ; 80-87: black
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00  ; 88-95: black

; =============================================================================
; TITLE SCREEN
; =============================================================================

SHOW_TITLE_SCREEN:
  JSR DRAW_TITLE_SCREEN

WAIT_FOR_START_RELEASE:
  JSR READ_START_KEY
  BEQ WAIT_FOR_START_RELEASE

WAIT_FOR_START_PRESS:
  LDA RTCLOK
WAIT_FRAME:
  CMP RTCLOK
  BEQ WAIT_FRAME
  JSR UPDATE_TITLE_ANIMATION
  JSR READ_START_KEY
  BNE WAIT_FOR_START_PRESS

  JSR CLEAR_SCREEN
  RTS

UPDATE_TITLE_ANIMATION:
  INC FRAME_COUNTER
  LDA FRAME_COUNTER
  AND #$1F
  BNE UPDATE_DONE

  LDY #10
BLINK_LOOP:
  LDA START_PROMPT_TEXT,Y
  EOR #$40
  STA START_PROMPT_TEXT,Y
  DEY
  BPL BLINK_LOOP

  LDA #<START_PROMPT_TEXT
  STA TEXT_SOURCE
  LDA #>START_PROMPT_TEXT
  STA TEXT_SOURCE+1
  LDA #<PROMPT_OFFSET
  STA TEXT_OFFSET
  LDA #>PROMPT_OFFSET
  STA TEXT_OFFSET+1
  JSR DRAW_TEXT_AT

UPDATE_DONE:
  RTS

READ_START_KEY:
  LDA CONSOL
  AND #$01
  RTS

DRAW_TITLE_SCREEN:
  JSR CLEAR_SCREEN
  JSR INIT_COLORS

  ; Row 0: Large title (Antic Mode 6 / GR.1)
  LDA #<TITLE_TEXT
  STA TEXT_SOURCE
  LDA #>TITLE_TEXT
  STA TEXT_SOURCE+1
  LDA #<TITLE_OFFSET
  STA TEXT_OFFSET
  LDA #>TITLE_OFFSET
  STA TEXT_OFFSET+1
  JSR DRAW_TEXT_AT

  ; Row 1: Top rule (Antic Mode 2 / GR.0)
  LDA #$80          ; $80 = solid block (inverse space). $40 is a heart!
  STA RULE_CHAR
  LDA #<RULE_TOP_OFFSET
  STA TEXT_OFFSET
  LDA #>RULE_TOP_OFFSET
  STA TEXT_OFFSET+1
  JSR DRAW_RULE

  ; Row 9: Start prompt
  LDA #<START_PROMPT_TEXT
  STA TEXT_SOURCE
  LDA #>START_PROMPT_TEXT
  STA TEXT_SOURCE+1
  LDA #<PROMPT_OFFSET
  STA TEXT_OFFSET
  LDA #>PROMPT_OFFSET
  STA TEXT_OFFSET+1
  JSR DRAW_TEXT_AT
  RTS

; ---------------------------------------------------------------------------
; DISPLAY LIST
; ---------------------------------------------------------------------------
MY_DISPLAY_LIST:
  .BYTE $70,$70,$F0     ; 24 blank lines (last 8 have DLI bit set via $F0)
  .BYTE $46             ; Row 0: Antic Mode 6 (GR.1) + LMS
  .WORD $BC00           ; Screen RAM address (patched later)
  .BYTE $00             ; 8 Blank scanlines
  .BYTE $02             ; Row 1: Antic Mode 2 (GR.0) - Top Rule
  .BYTE $02,$02,$02,$02 ; Row 2-5: GR.0
  .BYTE $02,$02,$02     ; Row 6-8: GR.0
  .BYTE $06             ; Row 9: Antic Mode 6 (GR.1) - PROMPT ROW
  .BYTE $02,$02,$02,$02 ; Row 10-13: GR.0
  .BYTE $02,$02,$02,$02 ; Row 14-17: GR.0
  .BYTE $02,$02         ; Row 18-19: GR.0
  .BYTE $41             ; JMP and Wait for VBLANK
  .WORD MY_DISPLAY_LIST

; We need to patch the LMS address in the Display List to match SAVMSC
PATCH_DL:
  LDA SAVMSC
  STA MY_DISPLAY_LIST+4
  LDA SAVMSC+1
  STA MY_DISPLAY_LIST+5
  RTS


; =============================================================================
; LOW-LEVEL DRAWING ROUTINES
; =============================================================================

; ---------------------------------------------------------------------------
; DRAW_TEXT_AT
;   Write a zero-terminated screen-code string to the screen.
;   Inputs:  TEXT_SOURCE (2 bytes) — address of string data
;            TEXT_OFFSET (2 bytes) — byte offset from start of screen RAM
;   Clobbers: A, Y
;
;   Implementation note: the addresses inside TEXT_LOAD and TEXT_STORE are
;   patched at run time (self-modifying code), which is standard practice on
;   the 6502 to avoid the overhead of indirect indexed addressing overhead.
;   The $FFFF placeholders are overwritten before the loop executes.
; ---------------------------------------------------------------------------
DRAW_TEXT_AT:
  LDA TEXT_SOURCE       ; patch source address into the LDA below
  STA TEXT_LOAD+1
  LDA TEXT_SOURCE+1
  STA TEXT_LOAD+2

  CLC
  LDA SAVMSC            ; compute destination: screen_base + offset
  ADC TEXT_OFFSET
  STA TEXT_STORE+1      ; patch destination address into the STA below
  LDA SAVMSC+1
  ADC TEXT_OFFSET+1
  STA TEXT_STORE+2

  LDY #$00
DRAW_TEXT_LOOP:
TEXT_LOAD:
  LDA $FFFF,Y           ; self-modified: reads from TEXT_SOURCE
  CMP #$FF              ; $FF = end-of-string sentinel ($00 = space, can't use BEQ)
  BEQ DRAW_TEXT_DONE
TEXT_STORE:
  STA $FFFF,Y           ; self-modified: writes to screen RAM
  INY
  BNE DRAW_TEXT_LOOP    ; Y wraps at 256 — keep strings under 255 chars

DRAW_TEXT_DONE:
  RTS

; ---------------------------------------------------------------------------
; DRAW_RULE
;   Fill one full screen row (SCREEN_WIDTH bytes) with a repeated character.
;   Inputs:  RULE_CHAR   — screen code of the fill character
;            TEXT_OFFSET — byte offset from start of screen RAM (row start)
;   Clobbers: A, Y
; ---------------------------------------------------------------------------
DRAW_RULE:
  CLC
  LDA SAVMSC
  ADC TEXT_OFFSET
  STA RULE_STORE+1      ; self-modify destination address
  LDA SAVMSC+1
  ADC TEXT_OFFSET+1
  STA RULE_STORE+2

  LDA RULE_CHAR
  LDY #$00
RULE_LOOP:
RULE_STORE:
  STA $FFFF,Y           ; self-modified: writes to screen RAM
  INY
  CPY #SCREEN_WIDTH     ; stop after 40 bytes (one full row)
  BNE RULE_LOOP
  RTS

; ---------------------------------------------------------------------------
; CLEAR_SCREEN
;   Write $00 (space) to every byte of screen RAM.
;   Walks row-by-row, advancing the self-modified pointer by SCREEN_WIDTH
;   after each row.  Handles page crossing via BCC / INC.
;   Clobbers: A, X, Y
; ---------------------------------------------------------------------------
CLEAR_SCREEN:
  LDA SAVMSC
  STA CLEAR_STORE+1
  LDA SAVMSC+1
  STA CLEAR_STORE+2

  LDX #SCREEN_HEIGHT    ; outer loop: 24 rows
CLEAR_ROW:
  LDY #$00
  LDA #$00
CLEAR_COLUMN:
CLEAR_STORE:
  STA $FFFF,Y           ; self-modified: current row base address
  INY
  CPY #SCREEN_WIDTH
  BNE CLEAR_COLUMN

  CLC
  LDA CLEAR_STORE+1     ; advance base address to next row
  ADC #SCREEN_WIDTH
  STA CLEAR_STORE+1
  BCC CLEAR_NEXT_ROW
  INC CLEAR_STORE+2     ; carry into high byte on page crossing

CLEAR_NEXT_ROW:
  DEX
  BNE CLEAR_ROW
  RTS

; =============================================================================
; GAME LOGIC STUBS
; =============================================================================

; ---------------------------------------------------------------------------
; READ_INPUT — read joystick / keyboard into game state
;   Joystick 0 port: $D300 (PORTA).  Bits 3-0: right/left/down/up (0=active).
;   Joystick 1 port: $D300 bits 7-4.
;   Fire button:     $D010 bit 2 (0=pressed).
; ---------------------------------------------------------------------------
READ_INPUT:
  ; TODO: read PORTA ($D300), decode directions, update PLAYER_DIR / movement
  RTS

; ---------------------------------------------------------------------------
; UPDATE_GAME — advance game simulation by one frame
;   Called once per frame from GAME_LOOP.
;   FRAME_COUNTER can be used for animation timing (e.g. mod 8 for blinking).
; ---------------------------------------------------------------------------
UPDATE_GAME:
  INC FRAME_COUNTER
  ; TODO: move tank, check collisions, update bullets
  RTS

; ---------------------------------------------------------------------------
; DRAW_FRAME — render current game state to screen RAM
;   Clear only dirty regions rather than the whole screen for speed.
; ---------------------------------------------------------------------------
DRAW_FRAME:
  ; TODO: draw playfield tiles, tanks, bullets using DRAW_TEXT_AT / DRAW_RULE
  RTS

; =============================================================================
; VARIABLES
; =============================================================================

PLAYER_X:
  .BYTE $50             ; pixel / tile X position of player tank

PLAYER_Y:
  .BYTE $30             ; pixel / tile Y position of player tank

PLAYER_DIR:
  .BYTE $00             ; direction: 0=up  1=right  2=down  3=left

FRAME_COUNTER:
  .BYTE $00             ; incremented every frame; wraps at 255

; Shared scratch used by DRAW_TEXT_AT and DRAW_RULE
RULE_CHAR:
  .BYTE $00             ; fill character for DRAW_RULE

TEXT_SOURCE:
  .BYTE $00,$00         ; lo, hi — pointer to string data

TEXT_OFFSET:
  .BYTE $00,$00         ; lo, hi — screen offset for current draw call

; =============================================================================
; STRING DATA  (Atari screen codes — see cheat-sheet at top of file)
; =============================================================================

; "* A8 TANKS *" — 12 chars
;  *=10 ' '=0 A=33 8=24 ' '=0 T=52 A=33 N=46 K=43 S=51 ' '=0 *=10  $FF=end
;  NOTE: $00 = space (not the terminator) — terminator is always $FF
TITLE_TEXT:
  .BYTE 10,0,33,24,0,52,33,46,43,51,0,10,$FF

; "PRESS START" — 11 chars
;  P=48 R=50 E=37 S=51 S=51 ' '=0 S=51 T=52 A=33 R=50 T=52  $FF=end
START_PROMPT_TEXT:
  .BYTE 48,50,37,51,51,0,51,52,33,50,52,$FF

.RUN START