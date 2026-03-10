; A8Tanks
; Simple Atari 800 XL tank game scaffold for jsA8E automation-driven builds.

.ORG $2000

START:
  JSR INIT

GAME_LOOP:
  JSR READ_INPUT
  JSR UPDATE_GAME
  JSR DRAW_FRAME
  JMP GAME_LOOP

INIT:
  LDA #$50
  STA PLAYER_X
  LDA #$30
  STA PLAYER_Y
  LDA #$00
  STA PLAYER_DIR
  STA FRAME_COUNTER
  RTS

READ_INPUT:
  ; TODO: Read tank controls from joystick or keyboard.
  RTS

UPDATE_GAME:
  INC FRAME_COUNTER
  RTS

DRAW_FRAME:
  ; TODO: Draw the playfield and tank state.
  RTS

PLAYER_X:
  .BYTE $50

PLAYER_Y:
  .BYTE $30

PLAYER_DIR:
  .BYTE $00

FRAME_COUNTER:
  .BYTE $00

.RUN START
