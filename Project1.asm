;Write/compile/run an assembly program for the AT89LP51RC2 microcontroller system with
;LCD for an alarm clock. The alarm clock must display hours (12 hour mode with AM/PM
;indication), minutes, seconds, and day of the week (Sunday to Monday) using the LCD. The
;clock’s current time (hours, minutes, seconds, and day of the week), must be settable using
;pushbuttons. The clock must have at least two settable alarms: one for Monday to Friday, and
;one for Saturday and Sunday. When an alarm is trigger, a speaker should produce an alarm
;sound. Use the mini speaker available in the microcontroller system parts kit for this purpose.
;Don’t forget to add extra functionality and/or features for bonus marks!
$NOLIST
$MODDE1SOC
$LIST

; There is a couple of typos in MODLP51 in the definition of the timer 0/1 reload
; special function registers (SFRs), so:

TIMER0_RELOAD_L DATA 0xf2
TIMER1_RELOAD_L DATA 0xf3
TIMER0_RELOAD_H DATA 0xf4
TIMER1_RELOAD_H DATA 0xf5

;---------------------------------;
; Symbolic Constants 		      ;
;---------------------------------;

; Timer and serial control
	CLK           		EQU 33333333 							; Microcontroller system crystal frequency in Hz
	BAUD 	 	  		EQU 115200								; BAUD rate
	TIMER_2_RELOAD 	  	EQU (65536-(CLK/(32*BAUD))) 			; We will use timer 2 to control serial port
	TIMER0_RATE   		EQU 4096     							; 2048Hz squarewave (peak amplitude of CEM-1203 speaker)
	TIMER0_RELOAD 		EQU ((65536-(CLK/TIMER0_RATE)))			; Let assembly do the calculation of timer reload value
	TIMER1_RATE   		EQU 1000       							; 1000Hz, for a timer tick of 1ms
	TIMER1_RELOAD 		EQU ((65536-(CLK/TIMER1_RATE)))			; Let assembly do the calculation of timer reload value

; Buttons
	; KEY.0 is for resetting 8051 soft processor
	BOOT_BUTTON 		EQU KEY.1 								; Set KEY.1 as BOOT_BUTTON

; SPI Pins
	CE_ADC 		 		bit 0xF8								; Chip select for ADC (Write only bit)
	MY_MOSI 	 		bit 0xF9								; SPI Master Output Slave Input (Write only bit)
	MY_MISO 	 		bit 0xFA								; SPI Master Input Slave Output (Read only bit)
	MY_SCLK 	 		bit 0xFB								; SPI Clock (Write only bit)

; Software FSM state names
	WAIT 				EQU 0 									; WAIT state is expressed with STATE_COUNTER = 0
	RAMP_TO_SOAK 		EQU 1 									; RAMP_TO_SOAK state is expressed with STATE_COUNTER = 1
	SOAK 				EQU 2 									; SOAK state is expressed with STATE_COUNTER = 2
	RAMP_TO_REFLOW 		EQU 3 									; RAMP_TO_REFLOW state is expressed with STATE_COUNTER = 3
	REFLOW 				EQU 4 									; REFLOW state is expressed with STATE_COUNTER = 4
	COOL_DOWN 			EQU 5 									; COOL_DOWN state is expressed with STATE_COUNTER = 5
	COOL_TO_TOUCH 		EQU 6 									; COOL_TO_TOUCH state is expressed with STATE_COUNTER = 6

;---------------------------------;
; ISR Vectors 				      ;
;---------------------------------;

; Reset vector
org 0x0000
    ljmp main

; External interrupt 0 vector (not used in this code)
org 0x0003
	reti

; Timer/Counter 0 overflow interrupt vector
org 0x000B
	ljmp Timer0_ISR 	; Jump to Timer0_ISR

; External interrupt 1 vector (not used in this code)
org 0x0013
	reti

; Timer/Counter 1 overflow interrupt vector
org 0x001B
	ljmp Timer1_ISR 	; Jump to Timer1_ISR

; Serial port receive/transmit interrupt vector (not used in this code)
org 0x0023 
	reti
	
; Timer/Counter 2 overflow interrupt vector
org 0x002B
 	reti	
;---------------------------------;
; Variables 				      ;
;---------------------------------;

; Multi-bit variables
; In the 8051 we can define direct access variables starting at location 0x30 up to location 0x7F
dseg at 0x30

; Reflow paramter variables
SOAK_TEMP:				ds 1		; default 150
SOAK_TIME:				ds 1		; default 90
REFLOW_TEMP:			ds 1		; default 217
REFLOW_TIME:				ds 1		; default 50

; Reflow control / state machine variables
STATE_COUNTER:			ds 1 		; Current state number
STATE_TIME_COUNTER:		ds 1 		; Counter for how much time has been spent in state

; Global variables for feedback
CURRENT_TARGET_TEMP:	ds 1		; required temp of current state
CURRENT_ACTUAL_TEMP:	ds 1		; temp readout of thermocouple
CURRENT_TEMP_DIFF:		ds 1		; target temp - actual temp
P_ADJUST: 				ds 1		; 50 if TEMP_DIFF > tempThresh, 0 else
;I_ADJUST: 				ds 1 		; Integral factor adjustment
;D_ADJUST: 				ds 1 		; Derivative factor adjustment
;PID_TOTAL_ADJUST: 		ds 1 		; Total weighted PID adjustment

; Variables for setting parameters
DIAL_VAL: 				ds 1		; for adjusting parameters
SET_MODE: 				ds 1		; 0:operation, else dial = (1:soak_temp, 2:soak_time, 3:reflow_temp, 4:reflow_time)	

; Time Counters
Count1ms:     			ds 2 		; Used to determine when second has passed (referred to with Count1ms+0 and Count1ms+1)
SECOND_COUNTER:			ds 1 		; Counter for runtime seconds
MINUTE_COUNTER:			ds 1 		; Counter for runtime minutes

; Variables for math32.inc
x: 						ds 4 		; For math32
y: 						ds 4 		; For math32
bcd: 					ds 5 		; For 10 digit BCD for math32

; Single-bit variables
; In the 8051 we have variables that are 1-bit in size.  We can use the setb, clr, jb, and jnb
; instructions with these variables.  This is how you define a 1-bit variable:
bseg
seconds_flag: 		dbit 1 		; Set to one in the ISR every time 100 ms had passed

mf: 				dbit 1 		; For math32

$NOLIST
$include(math32.inc) 								; Library of 32-bit math operations
$include(LCD_4bit_DE1SoC.inc) 						; A library of LCD related functions and utility macros

$LIST

;---------------------------------;
; LCD Setup 					  ;
;---------------------------------;

cseg
; These 'equ' must match the wiring between the microcontroller and the LCD!
ELCD_RS equ P0.4
ELCD_RW equ P0.5
ELCD_E  equ P0.6
ELCD_D4 equ P0.0
ELCD_D5 equ P0.1
ELCD_D6 equ P0.2
ELCD_D7 equ P0.3

;                 	    1234567890123456    <- This helps determine the location of the counter
Reading_Message: 	db 'Reading temps...', 0 		; Set message to display when reading
Setting_Message: 	db 'Setting temps...', 0 		; Set message to display when setting temperature
Memory_Mode: 		db      'Memory mode', 0 		; Set message to display when recording to memory
Serial_Mode: 		db      'Serial mode', 0 		; Set message to display wehn sending to serial

;---------------------------------;
; Routine to initialize the ISR   ;
; for timer 0                     ;
;---------------------------------;
Timer0_Init:
	mov a, TMOD 								; Copy TMOD to accumulator
	anl a, #0xf0 								; Clear the bits for timer 0
	orl a, #0x01 								; Configure timer 0 as 16-timer
	mov TMOD, a 								; Update TMOD
	mov TH0, #high(TIMER0_RELOAD) 				; Timer start value high bits = timer reload high bits
	mov TL0, #low(TIMER0_RELOAD) 				; Timer start value low bits = timer reload low bits
	; Set autoreload value
	mov TIMER0_RELOAD_H, #high(TIMER0_RELOAD) 	; Set reload high bits
	mov TIMER0_RELOAD_L, #low(TIMER0_RELOAD) 	; Set reload low bits
	; Enable the timer and interrupts
    setb ET0  									; Enable timer 0 interrupt
    clr TR0  									; We don't want to start TIMER0 until we want the alarm
	ret

;---------------------------------;
; ISR for timer 0.  Set to execute;
; every 1/4096Hz to generate a    ;
; 2048 Hz square wave at pin P3.7 ;
;---------------------------------;
Timer0_ISR:
	;clr TF0  ; According to the data sheet this is done for us already.
	;cpl LED_OUT 								; Invert LED output to generate square wave
	reti

;---------------------------------;
; Routine to initialize the ISR   ;
; for timer 2                     ;
;---------------------------------;
Timer1_Init:
	mov a, TMOD 								; Copy TMOD to accumulator
	anl a, #0x0f 								; Clear the bits for timer 1
	orl a, #0x10 								; Configure timer 1 as 16-timer
	mov TMOD, a 								; Update TMOD
	mov TH1, #high(TIMER0_RELOAD) 				; Timer start value high bits = timer reload high bits
	mov TL1, #low(TIMER0_RELOAD) 				; Timer start value low bits = timer reload low bits
	; Set autoreload value
	mov TIMER1_RELOAD_H, #high(TIMER1_RELOAD) 	; Set reload high bits
	mov TIMER1_RELOAD_L, #low(TIMER1_RELOAD) 	; Set reload low bits
	; Enable the timer and interrupts
	setb ET1  									; Enable timer 0 interrupt
	ret

;---------------------------------;
; ISR for timer 2                 ;
;---------------------------------;
Timer1_ISR:
	clr TF1  									; Timer 2 doesn't clear TF2 automatically. Do it in ISR
	cpl P3.6 									; To check the interrupt rate with oscilloscope. It must be precisely a 1 ms pulse.
	
	; The two registers used in the ISR must be saved in the stack
	push acc
	push psw
	
	; Increment the 16-bit one mili second counter
	inc Count1ms+0    							; Increment the low 8-bits first
	mov a, Count1ms+0 							; If the low 8-bits overflow, then increment high 8-bits
	jnz Inc_Done
	inc Count1ms+1

Inc_Done:
	; Check if 1 second has passed
	mov a, Count1ms+0
	cjne a, #low(1000), Timer2_ISR_done 		; Warning: this instruction changes the carry flag!
	mov a, Count1ms+1
	cjne a, #high(1000), Timer2_ISR_done
	
	; 1000 milliseconds have passed.  Set a flag so the main program knows
	setb seconds_flag 							; Let the main program know half second had passed
	; Reset to zero the milli-seconds counter, it is a 16-bit variable
	clr a
	mov Count1ms+0, a
	mov Count1ms+1, a
	
	; We are done ISR for timer 2
Timer2_ISR_done:
	pop psw
	pop acc
	reti

;---------------------------------;
; Configure serial port and baud  ;
; rate; serial port operations    ;
;---------------------------------;
; Configure the serial port and baud rate
Initialize_Serial_Port:
    ; Initialize serial port and baud rate using timer 2
	mov RCAP2H, #high(TIMER_2_RELOAD) 	; Set reload values so that Timer 2 matches baud rate
	mov RCAP2L, #low(TIMER_2_RELOAD) 	; Set reload values so that Timer 2 matches baud rate
	mov T2CON, #0x34 					; #00110100B
	mov SCON, #0x52 					; Serial port in mode 1, ren, txrdy, rxempty
	ret

putchar:
	jbc	TI,putchar_L1
	sjmp putchar
putchar_L1:
	mov	SBUF,a
	ret
	
getchar:
	jbc	RI,getchar_L1
	sjmp getchar
getchar_L1:
	mov	a,SBUF
	ret

SendString:
    clr a
    movc a, @a+dptr
    jz SendString_L1
    lcall putchar
    inc dptr
    sjmp SendString  
SendString_L1:
	ret

; Send a 4-digit BCD number stored in [R3,R2] to the serial port	
SendNumber:
	mov a, R3
	swap a
	anl a, #0x0f
	orl a, #'0'
	lcall putchar
	mov a, #'.'
	lcall putchar
	mov a, R3
	anl a, #0x0f
	orl a, #'0'
	lcall putchar
	mov a, R2
	swap a
	anl a, #0x0f
	orl a, #'0'
	lcall putchar
	mov a, R2
	anl a, #0x0f
	orl a, #'0'
	lcall putchar
	mov a, #'\r' 		;****
	lcall putchar 		;****
	mov a, #'\n' 		;****
	lcall putchar 		;****
	ret

;---------------------------------;
; Code for initializing LEDs      ;
;---------------------------------;
Initialize_LEDs:
    ; Turn off LEDs
	mov	LEDRA,#0x00
	mov	LEDRB,#0x00
	ret

;---------------------------------;
; ADC configuration and operation ;
;---------------------------------;
	
Initialize_ADC:
	; Initialize SPI pins connected to LTC2308
	clr	MY_MOSI
	clr	MY_SCLK
	setb CE_ADC
	ret

LTC2308_Toggle_Pins:
    mov MY_MOSI, c
    setb MY_SCLK
    mov c, MY_MISO
    clr MY_SCLK
    ret

; Bit-bang communication with LTC2308.  Check Figure 8 in datasheet (page 18):
; https://www.analog.com/media/en/technical-documentation/data-sheets/2308fc.pdf
; The VREF for this 12-bit ADC is 4.096V
; Warning: we are reading the previously converted channel! If you want to read the
; channel 'now' call this function twice.
;
; Channel to read passed in register 'b'.  Result in R1 (bits 11 downto 8) and R0 (bits 7 downto 0).
; Notice the weird order of the channel select bits!
LTC2308_RW:
    clr a 
	clr	CE_ADC ; Enable ADC

    ; Send 'S/D', get bit 11
    setb c ; S/D=1 for single ended conversion
    lcall LTC2308_Toggle_Pins
    mov acc.3, c
    ; Send channel bit 0, get bit 10
    mov c, b.2 ; O/S odd channel select
    lcall LTC2308_Toggle_Pins
    mov acc.2, c 
    ; Send channel bit 1, get bit 9
    mov c, b.0 ; S1
    lcall LTC2308_Toggle_Pins
    mov acc.1, c
    ; Send channel bit 2, get bit 8
    mov c, b.1 ; S0
    lcall LTC2308_Toggle_Pins
    mov acc.0, c
    mov R1, a
    
    ; Now receive the lest significant eight bits
    clr a 
    ; Send 'UNI', get bit 7
    setb c ; UNI=1 for unipolar output mode
    lcall LTC2308_Toggle_Pins
    mov acc.7, c
    ; Send 'SLP', get bit 6
    clr c ; SLP=0 for NAP mode
    lcall LTC2308_Toggle_Pins
    mov acc.6, c
    ; Send '0', get bit 5
    clr c
    lcall LTC2308_Toggle_Pins
    mov acc.5, c
    ; Send '0', get bit 4
    clr c
    lcall LTC2308_Toggle_Pins
    mov acc.4, c
    ; Send '0', get bit 3
    clr c
    lcall LTC2308_Toggle_Pins
    mov acc.3, c
    ; Send '0', get bit 2
    clr c
    lcall LTC2308_Toggle_Pins
    mov acc.2, c
    ; Send '0', get bit 1
    clr c
    lcall LTC2308_Toggle_Pins
    mov acc.1, c
    ; Send '0', get bit 0
    clr c
    lcall LTC2308_Toggle_Pins
    mov acc.0, c
    mov R0, a

	setb CE_ADC ; Disable ADC

	ret

;---------------------------------;
; 7-seg display operation         ;
;---------------------------------;

; Look-up table for the 7-seg displays. (Segments are turn on with zero) 
T_7seg:
    DB 40H, 79H, 24H, 30H, 19H, 12H, 02H, 78H, 00H, 10H

; Display the 4-digit bcd stored in [R3,R2] using the 7-segment displays
Display_BCD_SEG7:
	mov dptr, #T_7seg
	; Display the channel in HEX5
	mov a, b
	anl a, #0x0f
	movc a, @a+dptr
	mov HEX5, a
	
	; Display [R3,R2] in HEX3, HEX2, HEX1, HEX0
	mov a, R3
	swap a
	anl a, #0x0f
	movc a, @a+dptr
	mov HEX3, a
	
	mov a, R3
	anl a, #0x0f
	movc a, @a+dptr
	mov HEX2, a
	
	mov a, R2
	swap a
	anl a, #0x0f
	movc a, @a+dptr
	mov HEX1, a
	
	mov a, R2
	anl a, #0x0f
	movc a, @a+dptr
	mov HEX0, a
	
	ret


	
;---------------------------------;
; Main program. Includes hardware ;
; initialization and 'forever'    ;
; loop.                           ;
;---------------------------------;
main:
	; Initialization
    mov SP, #0x7F 									; Initialize stack
    lcall Timer0_Init								; Initialize Timer 0
    lcall Timer1_Init								; Initialize Timer 1
    setb EA 										; Allow global interrupts
    lcall Initialize_LEDs 							; Initialize LEDs to be all off
    lcall Initialize_ADC							; Initialize SPI
    lcall ELCD_4BIT 								; Initialize LCD to 4 bit mode
    lcall Initialize_Serial_Port					; Initialize serial port
    ; Set up variable initial values
	
	; Dseg variables

	    ; Reflow paramter variables
	    mov SOAK_TEMP, #150 							; Default soak temperature (150C)
	    mov SOAK_TIME, #90 								; Default soak time duration (90s)
	    mov REFLOW_TEMP, #217 							; Default reflow temperature (217C)
	    mov REFLOW_TIME, #50 							; Default reflow time duration (50s)

	    ; Reflow control / state machine variables
	    mov STATE_COUNTER, #0 							; Initialize state to WAIT state
	    mov STATE_TIME_COUNTER, #0 						; Initialize time counter (for measuring how much time we are in each state) to 0

	    ; Global Variables for feedback
	    mov CURRENT_TARGET_TEMP, #0 					; Initialize target temperature to 0 (for debugging purposes)
	    mov CURRENT_ACTUAL_TEMP, #0 					; Initialize current temperature to 0 (for debugging purposes)
	    mov CURRENT_TEMP_DIFF, #0 						; Initialize temperature difference between current and target to 0
	    mov P_ADJUST, #0 								; Initialize the proportional adjustment variable to 0
	    ;mov I_ADJUST, #0 								; Initialize the integral adjustment variable to 0
	    ;mov D_ADJUST, #0 								; Initialize the derivative adjustment variable to 0
	    
	    ; Variables for setting parameters
	    mov DIAL_VAL, #0 								; Initialize the dial reading (from ADC) to 0
	    mov SET_MODE, #0 								; Initialize the "state counter" for setting paramters to "not setting"

	    ; Timekeeping variables
	    mov Count1ms, #0 								; Set Count1ms initial value as 0
	    mov Count1ms+1, #0
	    mov SECOND_COUNTER, #0 							; Initialize SECOND_COUNTER as 0
	    mov MINUTE_COUNTER, #0 							; Initialize HOUR_COUNTER as 0

	    ; Math variables
	    mov x+0, #0 									; Set x initial value as 0
	    mov x+1, #0
	    mov x+2, #0
	    mov x+3, #0
	    mov y+0, #0 									; Set y initial value as 0
	    mov y+1, #0
	    mov y+2, #0
	    mov y+3, #0
	    mov bcd+0, #0 									; Set bcd initial value as 0
	    mov bcd+1, #0
	    mov bcd+2, #0
	    mov bcd+3, #0
	    mov bcd+4, #0
    
    ; Bseg variables
	    setb seconds_flag 								; Initialize seconds_flag to 1 so that we update display right away
	    clr mf 											; Clear the comparison flag
	; After initialization the program stays in this 'forever' loop
forever:

;---------------------------------;
; Toggle button controls          ;
;---------------------------------;
	jb BOOT_BUTTON, BOOT_BUTTON_Not_Pressed  		; if the 'BOOT' button is not pressed skip
	Wait_Milli_Seconds(#50)							; Debounce delay.  This macro is also in 'LCD_4bit.inc'
	jb BOOT_BUTTON, BOOT_BUTTON_Not_Pressed  		; if the 'BOOT' button is not pressed skip
	jnb BOOT_BUTTON, $								; Wait for button release.  The '$' means: jump to same instruction.
	; A valid press of the 'BOOT' button has been detected, reset the BCD counter.
	; But first stop timer 2 and reset the milli-seconds counter, to resync everything.
	clr TR2                 						; Stop timer 2
	clr a 											; Clear a
	mov Count1ms+0, a 								; Set Count1ms+0 = #0
	mov Count1ms+1, a 								; Set Count1ms+1 = #0
	setb TR2                						; Re-start timer 2
	ljmp UPDATE_DISPLAY             				; Go to update display
BOOT_BUTTON_Not_Pressed:
	jnb seconds_flag, forever						; If button not pressed and it is not yet a new "second", go back to beginning of forever loop
UPDATE_DISPLAY:
		
	clr seconds_flag 								; We clear this flag in the main loop, but it is set in the ISR for timer 2
	cpl LEDRA.0 


END