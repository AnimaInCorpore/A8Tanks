; =============================================================================
; A8Tanks — Atari 800 XL tank game
; Built with jsA8E / MADS assembler.  Entry point: $2000.
; =============================================================================
;
; ATARI SCREEN CODE CHEAT-SHEET
;   Screen RAM holds "internal" codes, not ATASCII.
;   Formula:  screen_code = ATASCII - $20   (for printable chars $20..$7F)
;   Inverse-video variant: add $40 to any screen code (bits become inverted).
;
;   Common codes (decimal):
;     0  = space      10 = *      13 = -      29 = =      32 = @
;    33  = A          34 = B  ... 58 = Z
;    16  = 0          17 = 1  ... 25 = 9
;    64  = solid block (inverse space — useful as a filled tile)
;
;   STRING TERMINATOR: use $FF (255) — NOT $00, because $00 means space.
;
;   To encode a new string, subtract 32 from each ASCII value:
;     e.g. "GAME OVER" → G=39 A=33 M=45 E=37 ' '=0 O=47 V=54 E=37 R=50
;
; ATARI COLOR BYTE FORMAT
;   Bits 7-4 : hue   (0=grey, 1=gold, 2=orange, 4=pink, 7=blue,
;                      8=cyan, 9=teal, B=green, D=yellow, F=red)
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
; SCREEN LAYOUT  (40 cols × 24 rows, all offsets = row*40 + col)
;
;   row  0 ············································  (blank)
;   row  1 ············································
;   row  2 ············································
;   row  3 ············································
;   row  4 ············································
;   row  5 ========================================      RULE_TOP   $00C8
;   row  6 ············································  (blank)
;   row  7          * A8 TANKS *                         TITLE      $0126  col 14
;   row  8 ············································  (blank)
;   row  9 ========================================      RULE_BOT   $0168
;   row 10 ············································  (blank)
;   row 11 ············································
;   row 12 ············································
;   row 13 ············································
;   row 14               PRESS START                     PROMPT     $023E  col 14
;   row 15 ············································
;   …
;   row 23 ············································
;
;   To reposition text: change the *_OFFSET constants and update the
;   centering column accordingly (col = (40 - text_length) / 2).
;
; =============================================================================

.ORG $2000

; ---------------------------------------------------------------------------
; Hardware registers
; ---------------------------------------------------------------------------
CONSOL = $D01F    ; Console keys (bits: 2=SELECT 1=OPTION 0=START); 0 = pressed
SAVMSC = $58      ; OS zero-page pointer: lo/hi address of screen RAM

COLPF2 = $D018    ; Playfield color 2 — text foreground in GR.0
COLBK  = $D01A    ; Background color

; ---------------------------------------------------------------------------
; Screen dimensions
; ---------------------------------------------------------------------------
SCREEN_WIDTH  = $28   ; 40 columns per row
SCREEN_HEIGHT = $18   ; 24 rows

; ---------------------------------------------------------------------------
; Screen offsets for each drawn element (row * 40 + col)
; Adjust these to move elements without touching the draw code.
; ---------------------------------------------------------------------------
RULE_TOP_OFFSET      = $00C8   ; row  5, col  0  — top horizontal rule
TITLE_SCREEN_OFFSET  = $0126   ; row  7, col 14  — title string (12 chars)
RULE_BOT_OFFSET      = $0168   ; row  9, col  0  — bottom horizontal rule
PROMPT_SCREEN_OFFSET = $023E   ; row 14, col 14  — "PRESS START" (11 chars)

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
; INIT — set up initial game state (called once at boot)
; ---------------------------------------------------------------------------
INIT:
  LDA #$50
  STA PLAYER_X          ; start position X
  LDA #$30
  STA PLAYER_Y          ; start position Y
  LDA #$00
  STA PLAYER_DIR        ; 0=up  1=right  2=down  3=left
  STA FRAME_COUNTER
  RTS

; ---------------------------------------------------------------------------
; INIT_COLORS — set the title-screen palette
;   Tweak COLBK / COLPF2 here to change the color scheme.
;   The values follow the Atari color byte format described at the top.
; ---------------------------------------------------------------------------
INIT_COLORS:
  LDA #$00      ; $00 = black background
  STA COLBK
  LDA #$1C      ; $1C = bright yellow/gold text  (hue 1, lum 6)
  STA COLPF2    ; try $28 for orange, $38 for peach, $B8 for green, $94 for blue
  RTS

; =============================================================================
; TITLE SCREEN
; =============================================================================

; ---------------------------------------------------------------------------
; SHOW_TITLE_SCREEN — draw title then wait for START press
; ---------------------------------------------------------------------------
SHOW_TITLE_SCREEN:
  JSR DRAW_TITLE_SCREEN

WAIT_FOR_START_RELEASE:
  JSR READ_START_KEY
  BEQ WAIT_FOR_START_RELEASE    ; spin while START is already held

WAIT_FOR_START_PRESS:
  JSR READ_START_KEY
  BNE WAIT_FOR_START_PRESS      ; spin until START goes low (pressed)

  JSR CLEAR_SCREEN              ; wipe screen before gameplay begins
  RTS

; ---------------------------------------------------------------------------
; READ_START_KEY — returns Z=1 (BEQ branches) when START is pressed
;   CONSOL bit 0: 1=released, 0=pressed.  AND #$01 isolates that bit.
; ---------------------------------------------------------------------------
READ_START_KEY:
  LDA CONSOL
  AND #$01      ; isolate START bit  (0 = pressed → Z flag set)
  RTS

; ---------------------------------------------------------------------------
; DRAW_TITLE_SCREEN — compose the full title screen
;   To add more lines, call DRAW_TEXT_AT with a new TEXT_SOURCE / TEXT_OFFSET.
;   To add a blinking effect on PRESS START, toggle inverse video on the
;   string bytes every N frames using FRAME_COUNTER (add $40 to each byte
;   to invert, subtract $40 to restore).
; ---------------------------------------------------------------------------
DRAW_TITLE_SCREEN:
  JSR CLEAR_SCREEN
  JSR INIT_COLORS

  ; Row 5: top rule  ========================================
  LDA #$1D          ; '=' = screen code 29 ($3D - $20)
  STA RULE_CHAR     ; swap to $0D for '---', $40 for solid blocks
  LDA #<RULE_TOP_OFFSET
  STA TEXT_OFFSET
  LDA #>RULE_TOP_OFFSET
  STA TEXT_OFFSET+1
  JSR DRAW_RULE

  ; Row 7: title string  "* A8 TANKS *"
  LDA #<TITLE_TEXT
  STA TEXT_SOURCE
  LDA #>TITLE_TEXT
  STA TEXT_SOURCE+1
  LDA #<TITLE_SCREEN_OFFSET
  STA TEXT_OFFSET
  LDA #>TITLE_SCREEN_OFFSET
  STA TEXT_OFFSET+1
  JSR DRAW_TEXT_AT

  ; Row 9: bottom rule  ========================================
  LDA #$1D
  STA RULE_CHAR
  LDA #<RULE_BOT_OFFSET
  STA TEXT_OFFSET
  LDA #>RULE_BOT_OFFSET
  STA TEXT_OFFSET+1
  JSR DRAW_RULE

  ; Row 14: start prompt  "PRESS START"
  LDA #<START_PROMPT_TEXT
  STA TEXT_SOURCE
  LDA #>START_PROMPT_TEXT
  STA TEXT_SOURCE+1
  LDA #<PROMPT_SCREEN_OFFSET
  STA TEXT_OFFSET
  LDA #>PROMPT_SCREEN_OFFSET
  STA TEXT_OFFSET+1
  JSR DRAW_TEXT_AT
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

; "* A8 TANKS *" — 12 chars, placed at col 14 → (40 - 12) / 2 = 14
;  *=10 ' '=0 A=33 8=24 ' '=0 T=52 A=33 N=46 K=43 S=51 ' '=0 *=10  $FF=end
;  NOTE: $00 = space (not the terminator) — terminator is always $FF
TITLE_TEXT:
  .BYTE 10,0,33,24,0,52,33,46,43,51,0,10,$FF

; "PRESS START" — 11 chars, placed at col 14 → (40 - 11) / 2 = 14  (rounded)
;  P=48 R=50 E=37 S=51 S=51 ' '=0 S=51 T=52 A=33 R=50 T=52  $FF=end
START_PROMPT_TEXT:
  .BYTE 48,50,37,51,51,0,51,52,33,50,52,$FF

.RUN START
