#include <p16f630.inc>

;
; -----------------------------------------------------------------------
;
;	Sega Mega Drive switchless mod
;
;   Copyright (C) 2015 by Peter Bartmann <borti4938@gmx.de>
;
;   This program is free software; you can redistribute it and/or modify
;   it under the terms of the GNU General Public License as published by
;   the Free Software Foundation; version 2 of the License only.
;
;   This program is distributed in the hope that it will be useful,
;   but WITHOUT ANY WARRANTY; without even the implied warranty of
;   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;   GNU General Public License for more details.
;
;   You should have received a copy of the GNU General Public License
;   along with this program; if not, write to the Free Software
;   Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
;
; -----------------------------------------------------------------------
;
;   pin configuration: 
;
;                         ,-----_-----.
;                     +5V |1        14| GND
;       Reset Button (in) |2  A5 A0 13| BIG Sel0 (out)
;        Reset Line (out) |3  A4 A1 12| BIG Sel1 (out)
;              /RoLC (in) |4  A3 A2 11| Language   (out)
;       (green) LED (out) |5  C5 C0 10| /Language   (out)
;         (red) LED (out) |6  C4 C1  9| Videomode  (out)
;           LED_TYPE (in) |7  C3 C2  8| /Videomode (out)
;                         `-----------'
;
; Special purposes for pins and other common notes:
;
;   Pin 2 (Reset Button)
;     The code should be able to detect the reset type by it's own without
;     any other components.
;     However, sometimes - depending on your PIC - the internal weak pull-up
;     resistor is not accurate to detect the reset type on low active consoles.
;     In that case you will see the LED cycles around the modes after
;     installation. Then you have to add an external pull-up resistor (e.g. 10k)
;     between pin 1 and 2 (SMD 0805 fits quite well between those pins
;     for DIL-14 PICs).
;
;   Pin 4 (RoLC = reset on language change)
;      low = RoLC on - pic resets console if language bit has to be changed
;     high = RoLC off
;
;   Pin 9 (Videomode)    Pin 8 (/Videomode)
;      low = 50Hz           low = 60Hz
;     high = 60Hz          high = 50Hz
;                          -> Opposite of Pin 9
;
;   Pin 11 (Language)    Pin 10 (/Language)
;      low = Japanese       low = English
;     high = English       high = Japanese
;                          -> Opposite of Pin 11
;
;   Pin 12 and Pin 13
;     A two bit counter which increases with each reset except after a reset if the
;     language flag has been previously changed.
;     MSB is pin 12 and LSB is pin 13. These two pins can be used for the MD build-in
;     game pcb.
;     
; -----------------------------------------------------------------------
;
; mode description:
;
; mode 0x00 = PAL:           50Hz, LED green
;
; mode 0x01 = NTSC:          60Hz, LED red
;
; mode 0x02 = JAP NTSC:      60Hz, LED orange
;      
; -----------------------------------------------------------------------
; Configuration bits: adapt to your setup and needs

    __CONFIG _INTRC_OSC_NOCLKOUT & _WDT_OFF & _PWRTE_OFF & _MCLRE_OFF & _CP_OFF & _CPD_OFF

; -----------------------------------------------------------------------
; macros and definitions

M_movff macro   fromReg, toReg  ; move filereg to filereg
        movfw   fromReg
        movwf   toReg
        endm

M_movpf macro   fromPORT, toReg ; move PORTx to filereg
        movfw   fromPORT
        andlw   0x3f
        movwf   toReg
        endm

M_movlf macro   literal, toReg  ; move literal to filereg
        movlw   literal
        movwf   toReg
        endm

M_beff  macro   compReg1, compReg2, branch  ; branch if two fileregs are equal
        movfw   compReg1
        xorwf	compReg2, w
        btfsc   STATUS, Z
        goto    branch
        endm

M_bepf  macro   compPORT, compReg, branch   ; brach if PORTx equals compReg (ignoring bit 6 and 7)
        movfw   compPORT
        xorwf   compReg, w
        andlw   0x3f
        btfsc   STATUS, Z
        goto    branch
        endm

M_belf  macro   literal, compReg, branch  ; branch if a literal is stored in filereg
        movlw   literal
        xorwf	compReg, w
        btfsc   STATUS, Z
        goto    branch
        endm

M_celf  macro   literal, compReg, call_func  ; call if a literal is stored in filereg
        movlw   literal
        xorwf	compReg, w
        btfsc   STATUS, Z
        call    call_func
        endm

M_delay_x10ms   macro   literal ; delay about literal x 10ms
                movlw   literal
                movwf   reg_repetition_cnt
                call    delay_x10ms
                endm

M_push_reset    macro
                banksel TRISA
                bcf     TRISA, RESET_OUT
                banksel PORTA
                bcf     PORTA, RESET_OUT
                endm

M_release_reset macro
                bsf     PORTA, RESET_OUT
                banksel TRISA
                bsf     TRISA, RESET_OUT
                banksel PORTA
                endm

M_set50 macro
        bcf PORTC, VIDMODE
        bsf PORTC, NVIDMODE
        endm

M_set60 macro
        bsf PORTC, VIDMODE
        bcf PORTC, NVIDMODE
        endm

M_setEN macro
        bsf PORTA, LANGUAGE
        bcf PORTC, NLANGUAGE
        endm

M_setJA macro
        bcf PORTA, LANGUAGE
        bsf PORTC, NLANGUAGE
        endm

M_skipnext_rst_pressed  macro
                        movfw   PORTA
                        xorwf   reg_reset_type, 0
                        andlw   (1<<RESET_BUTTON)
                        btfss   STATUS, Z
                        endm

M_skipnext_rst_notpressed   macro
                            movfw   PORTA
                            xorwf   reg_reset_type, 0
                            andlw   1<<RESET_BUTTON
                            btfsc   STATUS, Z
                            endm
; -----------------------------------------------------------------------

;port a
BIG_Sel0      EQU 0
BIG_Sel1      EQU 1
LANGUAGE      EQU 2
NRoLC         EQU 3
RESET_OUT     EQU 4
RESET_BUTTON  EQU 5

;port c
NLANGUAGE   EQU 0
VIDMODE     EQU 1
NVIDMODE    EQU 2
LED_TYPE    EQU 3
LED_RED     EQU 4
LED_GREEN   EQU 5

; registers
reg_overflow_cnt    EQU 0x20
reg_repetition_cnt  EQU 0x21
reg_current_mode    EQU 0x30
reg_previous_mode   EQU 0x31
reg_reset_cnt       EQU 0x32
reg_reset_panalty   EQU 0x33
reg_reset_type      EQU 0x40
reg_led_buffer      EQU 0x41
reg_first_boot_done EQU 0x42

; codes and bits
code_modereset      EQU 0x00
code_pal            EQU 0x00
code_ntsc           EQU 0x01
code_jap            EQU 0x02

default_mode    EQU code_ntsc

mode_overflow       EQU 0x03
bit_language        EQU 1
bit_eng_hz          EQU 0


code_led_off    EQU 0x00
code_led_green  EQU (1<<LED_GREEN)
code_led_red    EQU (1<<LED_RED)
code_led_yellow EQU code_led_green ^ code_led_red

code_led_invert EQU code_led_green ^ code_led_red

delay_10ms_t0_overflows EQU 0x14    ; prescaler T0 set to 1:2 @ 4MHz
repetitions_100ms       EQU 0x0a
repetitions_200ms       EQU 0x14
repetitions_300ms       EQU 0x1e
repetitions_mode_delay  EQU 0x4a    ; around 740ms

; -----------------------------------------------------------------------

; code memory
 org    0x0000
    clrf  STATUS  ; 00h Page 0, Bank 0
    nop           ; 01h
    nop           ; 02h
    goto  start   ; 03h begin program / Initializing

 org    0x0004  ; jump here on interrupt with GIE set (should not appear)
    return      ; return with GIE unset

 org    0x0005
idle
    M_skipnext_rst_notpressed
    goto    check_rst
    bcf     INTCON, RAIF
    sleep

check_rst
    call    delay_10ms                      ; software debounce
    call    delay_10ms                      ; software debounce
    M_skipnext_rst_pressed
    goto    idle

    M_movlf repetitions_mode_delay, reg_repetition_cnt

check_rst_loop
    call    delay_10ms
    M_skipnext_rst_pressed
    goto    doreset
    decfsz  reg_repetition_cnt, 1
    goto    check_rst_loop
    
next_mode
    incf    reg_current_mode, 1
    M_celf  mode_overflow, reg_current_mode, reset_mode

mode_delay
    call    setled
    M_movlf repetitions_mode_delay, reg_repetition_cnt

mode_delay_loop
    call    delay_10ms
    M_skipnext_rst_pressed
    goto    apply_mode
    decfsz  reg_repetition_cnt, 1
    goto    mode_delay_loop
    goto    next_mode


apply_mode
    call    save_mode
    ; other strategie than in set_initial_mode
    ; -> protection against an error in mode selection
    M_belf  code_pal, reg_current_mode, set_new_pal
    M_belf  code_ntsc, reg_current_mode, set_new_ntsc
    M_belf  code_jap, reg_current_mode, set_new_jap
    goto    set_previous_mode  ; should not appear

set_new_pal
    M_set50
    goto    apply_mode_post_check

set_new_ntsc
    M_set60
    goto    apply_mode_post_check

set_new_jap
    M_set60
    goto    apply_mode_post_check

set_previous_mode
    M_movff reg_previous_mode, reg_current_mode
    call    save_mode
    call    setled
    goto    idle

apply_mode_post_check
    ; before doing anything unset panalty of reset counter
    clrf    reg_reset_panalty
    ; strategie: look if language has been changed while changing mode
    movfw   reg_previous_mode
    xorwf   reg_current_mode, w
    andlw   (1<<bit_language)
    btfsc   STATUS, Z
    goto    idle                    ; language bit has not changed
                                    ; language bit has changed:
    bsf     reg_reset_panalty, 0    ; - set panalty flag
    btfsc   PORTA, NRoLC            ; - look if the user wants an automatic reset
                                    ;   on language change
    goto    idle
;    goto    doreset

doreset
    M_push_reset
    M_delay_x10ms   repetitions_300ms
    M_movff reg_current_mode, reg_previous_mode
    btfss   reg_reset_panalty, 0        ; language bit has been changed?
    incf    reg_reset_cnt, 1            ; only if no: increase counter
    btfsc   reg_reset_cnt, 2            ; did reset counter exceed valid interval?
    clrf    reg_reset_cnt               ; if yes: reset the 2bit counter
    clrf    reg_reset_panalty           ; unset a potential panalty
    call    save_rst_cnt
    goto    set_initial_mode            ; small trick ;)

; --------calls--------
setled
    ; same strategie as in set_initial_mode
    btfsc   reg_current_mode, bit_language
    goto    setled_yellow
    btfsc   reg_current_mode, bit_eng_hz
    goto    setled_red

setled_green
    movfw   PORTC
    andlw   0x0f
    xorlw   code_led_green
    btfsc	PORTC, LED_TYPE ; if common anode:
    xorlw   code_led_invert ; invert output
    movwf   PORTC
    return

setled_red
    movfw   PORTC
    andlw   0x0f
    xorlw   code_led_red
    btfsc	PORTC, LED_TYPE ; if common anode:
    xorlw   code_led_invert ; invert output
    movwf   PORTC
    return

setled_yellow
    movfw   PORTC
    andlw   0x0f
    xorlw   code_led_yellow
    btfsc	PORTC, LED_TYPE ; if common anode:
    xorlw   code_led_invert ; invert output
    movwf   PORTC
    return

reset_mode
    M_movlf code_modereset, reg_current_mode
    return

save_mode
    movfw   reg_current_mode
    banksel EEADR             ; save to EEPROM
    movwf   EEDAT
    clrf    EEADR             ; address 0
    bsf     EECON1, WREN
    movlw   0x55
    movwf   EECON2
    movlw   0xaa
    movwf   EECON2
    bsf     EECON1, WR
wait_save_mode_end
    btfsc   EECON1, WR
    goto    wait_save_mode_end
    bcf     EECON1, WREN
    banksel PORTA
    return

save_rst_cnt
    movfw   reg_current_mode
    banksel EEADR             ; save to EEPROM
    movwf   EEDAT
    M_movlf EEADR, 0x01       ; address
    bsf     EECON1, WREN
    movlw   0x55
    movwf   EECON2
    movlw   0xaa
    movwf   EECON2
    bsf     EECON1, WR
wait_save_rst_cnt_end
    btfsc   EECON1, WR
    goto    wait_save_rst_cnt_end
    bcf     EECON1, WREN
    banksel PORTA
    return
    


delay_10ms
    clrf    TMR0                ; start timer (operation clears prescaler of T0)
    banksel TRISA
    movfw   OPTION_REG
    andlw   0xf0
    movwf   OPTION_REG
    banksel PORTA
    M_movlf delay_10ms_t0_overflows, reg_overflow_cnt
    bsf     INTCON, T0IE        ; enable timer 0 interrupt

delay_10ms_loop_pre
    bcf     INTCON, T0IF

delay_10ms_loop
    btfss   INTCON, T0IF
    goto    delay_10ms_loop
    decfsz  reg_overflow_cnt, 1
    goto    delay_10ms_loop_pre
    bcf     INTCON, T0IE        ; disable timer 0 interrupt
    return

delay_x10ms
    call    delay_10ms
    decfsz  reg_repetition_cnt, 1
    goto    delay_x10ms
    return


; --------initialization--------
start
    clrf    PORTA
    clrf    PORTC
    M_movlf 0x07, CMCON             ; GPIO2..0 are digital I/O (not connected to comparator)
    M_movlf 0x08, INTCON            ; enable interrupts: RAIE
    banksel TRISA                   ; Bank 1
    call    3FFh                    ; Get the cal value
    movwf   OSCCAL                  ; Calibrate
    M_movlf 0x38, TRISA             ; in in in out out out
    M_movlf 0x08, TRISC             ; out out in out out out
    M_movlf (1<<RESET_BUTTON), IOCA ; IOC at reset button
    M_movlf (1<<RESET_BUTTON), WPUA ; pullups at reset button
    clrf    OPTION_REG              ; global pullup enable, prescaler T0 1:2
    banksel PORTA                   ; Bank 0


load_mode
    clrf    reg_first_boot_done
    clrf    reg_current_mode
    clrf    reg_reset_cnt
    bcf     STATUS, C           ; clear carry
    banksel EEADR               ; fetch current mode from EEPROM
    clrf    EEADR               ; address 0
    bsf     EECON1, RD
    movfw   EEDAT
;    banksel PORTA
    movwf   reg_current_mode    ; last mode saved
    movwf   reg_previous_mode   ; last mode saved to compare
;    bcf     STATUS, C           ; clear carry
;    banksel EEADR               ; fetch current mode from EEPROM
    incf    EEADR, 1            ; address 1
    bsf     EECON1, RD
    movfw   EEDAT
    andlw   0x03
;    banksel PORTA
    movwf   reg_reset_cnt
    banksel PORTA

set_BIG_Sel
    M_movff   reg_reset_cnt, PORTA   ; selects the build in game

set_initial_mode
    ; strategie: check language flag
    ;            -> if Jap, set also 60Hz
    ;            -> if Eng, check 50/60Hz at first bit
    btfsc   reg_current_mode, bit_language
    goto    set_jap
    btfsc   reg_current_mode, bit_eng_hz
    goto    set_ntsc

set_pal
    M_set50
    M_setEN
    M_movlf code_pal, reg_current_mode  ; in case a non-valid mode is stored
    goto    init_end

set_ntsc
    M_set60
    M_setEN
    M_movlf code_ntsc, reg_current_mode ; in case a non-valid mode is stored
    goto    init_end

set_jap
    M_set60
    M_setJA
    M_movlf code_jap, reg_current_mode  ; in case a non-valid mode is stored
;    goto    init_end 

init_end
    call    save_mode
    call    setled
    M_release_reset
    clrf    reg_previous_mode
    M_movff reg_current_mode, reg_previous_mode ; last mode saved to compare
    btfsc   reg_first_boot_done, 0
    goto    idle
    bsf     reg_first_boot_done, 0

detect_reset_type
    clrf    reg_reset_type
    btfss   PORTA, RESET_BUTTON             ; skip next for low-active reset
    bsf     reg_reset_type, RESET_BUTTON
    goto    idle

; -----------------------------------------------------------------------
; eeprom data
DEEPROM	CODE
	de	default_mode, 0x00

theend
    END
; ------------------------------------------------------------------------
