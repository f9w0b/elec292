; Subroutine for displaying current state on LED board;
$NOLIST
$MODLP52
$LIST

TIMER0_RELOAD_L DATA 0xf2
TIMER1_RELOAD_L DATA 0xf3
TIMER0_RELOAD_H DATA 0xf4
TIMER1_RELOAD_H DATA 0xf5

CLK           EQU 22118400 ; Microcontroller system crystal frequency in Hz
TIMER0_RATE   EQU 4096     ; 2048Hz squarewave (peak amplitude of CEM-1203 speaker)
TIMER0_RELOAD EQU ((65536-(CLK/TIMER0_RATE)))
TIMER2_RATE   EQU 1000     ; 1000Hz, for a timer tick of 1ms
TIMER2_RELOAD EQU ((65536-(CLK/TIMER2_RATE)))

; !!! These need to be transfered to project1.asm!~~
; These ’EQU’ must match the wiring between the microcontroller and ADC
STATE1_LED      EQU P2.0
STATE2_LED      EQU P2.1
STATE3_LED      EQU P2.2
STATE4_LED      EQU P2.3
STATE5_LED      EQU P2.5
START_BUTTON    EQU p0.0

FREQ EQU 22118400
BAUD EQU 115200
T1LOAD EQU 256-(FREQ/(16*BAUD))


; Reset vector
org 0x0000
    ljmp MainProgram

; External interrupt 0 vector (not used in this code)
org 0x0003
	reti

; Timer/Counter 0 overflow interrupt vector
org 0x000B
	ljmp Timer0_ISR

; External interrupt 1 vector (not used in this code)
org 0x0013
	reti

; Timer/Counter 1 overflow interrupt vector (not used in this code)
org 0x001B
	reti

; Serial port receive/transmit interrupt vector (not used in this code)
org 0x0023
	reti

; Timer/Counter 2 overflow interrupt vector
org 0x002B
	ljmp Timer2_ISR

dseg at 0X30
STATE_COUNTER:           ds 1
BCD_counter_seconds:     ds 1


bseg
mf: dbit 1
seconds_flag: dbit 1
Unaligned_LED_Flag:    dbit 1 				; Add this to project 1.asm !!!

cseg
; These 'equ' must match the wiring between the microcontroller and the LCD!
LCD_RS equ P1.1
LCD_RW equ P1.2
LCD_E  equ P1.3
LCD_D4 equ P3.2
LCD_D5 equ P3.3
LCD_D6 equ P3.4
LCD_D7 equ P3.5
$NOLIST
$include(LCD_4bit.inc) ; A library of LCD related functions and utility macros
$include(math32.inc)
$LIST

;                                1234567890123456
waitLEDs_MESSAGE:                db '   TEMP: xx C   ', 0
RAMP_TO_soakLEDs_MESSAGE:        db '   TEMP: xx F   ', 0
soakLEDs_MESSAGE:                db 'WARNING TOO HOT!', 0
RAMP_TO_reflowLEDs_MESSAGE:      db '                ', 0
reflowLEDs_MESSAGE:              db '                ', 0
COOL_DOWN_MESSAGE:           db '                ', 0
COOL_TO_TOUCH_MESSAGE:       db '                ', 0
;---------------------------------;
; Routine to initialize the ISR   ;
; for timer 0                     ;
;---------------------------------;
Timer0_Init:
	mov a, TMOD
	anl a, #0xf0 ; Clear the bits for timer 0
	orl a, #0x01 ; Configure timer 0 as 16-timer
	mov TMOD, a
	mov TH0, #high(TIMER0_RELOAD)
	mov TL0, #low(TIMER0_RELOAD)
	; Set autoreload value
	mov TIMER0_RELOAD_H, #high(TIMER0_RELOAD)
	mov TIMER0_RELOAD_L, #low(TIMER0_RELOAD)
	; Enable the timer and interrupts
    ;setb ET0  ; Enable timer 0 interrupt
    setb TR0  ; Start timer 0
	ret


;---------------------------------;
; ISR for timer 0.  Set to execute;
; every 1/4096Hz to generate a    ;
; 2048 Hz square wave at pin P3.7 ;
;---------------------------------;
Timer0_ISR:
	;clr TF0  ; According to the data sheet this is done for us already.
	cpl SOUND_OUT ; Connect speaker to P3.7!
	reti

;---------------------------------;
; Routine to initialize the ISR   ;
; for timer 2                     ;
;---------------------------------;
Timer2_Init:
	mov T2CON, #0 ; Stop timer/counter.  Autoreload mode.
	mov TH2, #high(TIMER2_RELOAD)
	mov TL2, #low(TIMER2_RELOAD)
	; Set the reload value
	mov RCAP2H, #high(TIMER2_RELOAD)
	mov RCAP2L, #low(TIMER2_RELOAD)
	; Init One millisecond interrupt counter.  It is a 16-bit variable made with two 8-bit parts
	clr a
	mov Count1ms+0, a
	mov Count1ms+1, a
	; Enable the timer and interrupts
    setb ET2  ; Enable timer 2 interrupt
    setb TR2  ; Enable timer 2
	ret

;---------------------------------;
; ISR for timer 2                 ;
;---------------------------------;
Timer2_ISR:
	clr TF2  ; Timer 2 doesn't clear TF2 automatically. Do it in ISR
	cpl P3.6 ; To check the interrupt rate with oscilloscope. It must be precisely a 1 ms pulse.

	; The two registers used in the ISR must be saved in the stack
	push acc
	push psw

	; Increment the 16-bit one mili second counter
	inc Count1ms+0    ; Increment the low 8-bits first
	mov a, Count1ms+0 ; If the low 8-bits overflow, then increment high 8-bits
	jnz Inc_Done
	inc Count1ms+1

Inc_Done:
	; Check if half second has passed
	mov a, Count1ms+0
	cjne a, #low(1000), Timer2_ISR_done ; Warning: this instruction changes the carry flag!
	mov a, Count1ms+1
	cjne a, #high(1000), Timer2_ISR_done

	; 500 milliseconds have passed.  Set a flag so the main program knows
	setb seconds_flag ; Let the main program know a second had passed
	cpl TR0 ; Enable/disable timer/counter 0. This line creates a beep-silence-beep-silence sound.
	; Reset to zero the milli-seconds counter, it is a 16-bit variable
	clr a
	mov Count1ms+0, a
	mov Count1ms+1, a
	; Increment the BCD counter
	mov a, BCD_counter_seconds
	add a, #0x01
	da a ; Decimal adjust instruction.  Check datasheet for more details!
	mov BCD_counter_seconds, a
	mov a, #0x15
	cjne a, BCD_counter_seconds, Timer2_ISR_done
	mov a, STATE_COUNTER
	add a, #0x1
	da a
	mov STATE_COUNTER, a

Timer2_ISR_done:
	pop psw
	pop acc
	reti



MainProgram:
    MOV SP, #7FH ; Set the stack pointer to the begining of idata
    ;mov PMOD, #0 ; Configure all ports in bidirectional mode

    lcall Timer0_Init
    setb EA   ; Enable Global interrupts
    lcall LCD_4BIT
   ; Set_Cursor(1, 1)
    ;Send_Constant_String(#CELCIUS_Message)


forever:
jb START_reflowLEDs, checkSTATE  	; if the 'START_reflowLEDs' button is not pressed skip
wait_Milli_Seconds(#50)			; Debounce delay.  This macro is also in 'LCD_4bit.inc'          FOR TESTING
jb START_reflowLEDs, checkSTATE  	; if the 'START_reflowLEDs' button is not pressed skip
jnb START_reflowLEDs, $
lcall Timer2_Init

checkSTATE:
	; non-blocking state machine for KEY1 starts here
		mov a, STATE_COUNTER

	waitLEDs:
		cjne a, #0, rampTosoakLEDs
			; At this point we are in waitLEDs state state
			; Turn all LEDs OFF
			clr STATE1_LED
			clr STATE2_LED
			clr STATE3_LED
			clr STATE4_LED
			clr STATE5_LED
		sjmp fsmLEDDone

	rampTosoakLEDs:
		cjne a, #1, soakLEDs
			; At this point we are in rampTosoakLEDs state
			setb STATE1_LED
			clr STATE2_LED
			clr STATE3_LED
			clr STATE4_LED
			clr STATE5_LED
		sjmp fsmLEDDone

	soakLEDs:
		cjne a, #2, rampToreflowLEDs
			; At this point we are in soakLEDs state
			setb STATE2_LED
			clr STATE1_LED
			clr STATE3_LED
			clr STATE4_LED
			clr STATE5_LED
		sjmp fsmLEDDone

	rampToreflowLEDs:
		cjne a, #3, reflowLEDs
			; At this point we are in rampToreflowLEDs state
			setb STATE3_LED
			clr STATE1_LED
			clr STATE2_LED
			clr STATE4_LED
			clr STATE5_LED
		sjmp fsmLEDDone

	reflowLEDs:
		cjne a, #4, coolDownLEDs
			; At this point we are in reflowLEDs state
			setb STATE4_LED
			clr STATE1_LED
			clr STATE2_LED
			clr STATE3_LED
			clr STATE5_LED
		sjmp fsmLEDDone

	coolDownLEDs:
		cjne a, #5, coolToTouchLEDs
			; At this point we are in coolDownLEDs state
			setb STATE5_LED
			clr STATE1_LED
			clr STATE2_LED
			clr STATE3_LED
			clr STATE4_LED
			setb Unaligned_LED_Flag
		sjmp fsmLEDDone

	coolToTouchLEDs:
		cjne a, #6, fsm1Done
			; At this point we are in coolToTouchLEDs state
			call LEDAlign
			; Flash all LEDs
			cpl STATE1_LED
			cpl STATE2_LED
			cpl STATE3_LED
			cpl STATE4_LED
			cpl STATE5_LED
		sjmp fsmLEDDone
	fsmLEDDone:

jmp forever

; Function for aligning LEDs for flashing in final state;
LEDAlign:
	push acc
	jnb Unaligned_LED_Flag, alignLEDsDone
	clr Unaligned_LED_Flag
	clr STATE5_LED
alignLEDsDone:
	pop acc
	ret

END
