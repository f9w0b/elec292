; Project 1 main file
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
	WAIT 				EQU 0 									; WAIT state is expressed with State_Counter = 0
	RAMP_TO_SOAK 		EQU 1 									; RAMP_TO_SOAK state is expressed with State_Counter = 1
	SOAK 				EQU 2 									; SOAK state is expressed with State_Counter = 2
	RAMP_TO_REFLOW 		EQU 3 									; RAMP_TO_REFLOW state is expressed with State_Counter = 3
	REFLOW 				EQU 4 									; REFLOW state is expressed with State_Counter = 4
	COOL_DOWN 			EQU 5 									; COOL_DOWN state is expressed with State_Counter = 5
	COOL_TO_TOUCH 		EQU 6 									; COOL_TO_TOUCH state is expressed with State_Counter = 6

; Pins
	START_BUTTON		EQU P4.5								; Start button, arbitrary pin
	SPEAKER				EQU P2.3								; Pin connected to speaker
	OVEN_PIN			EQU P2.2								; Pin connected to oven

	STATE1_LED			EQU P1.0								; State indication LEDs
	STATE2_LED			EQU P1.1
	STATE3_LED			EQU P1.2
	STATE4_LED			EQU P1.3
	STATE5_LED			EQU P1.4

; Other Symbolic constants
	COOL_TO_TOUCH_TEMP	EQU 50									; Temperature defined as cool to touch, used to trigger 5 -> 6 state transition

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
	ljmp Timer0ISR 	; Jump to Timer0ISR

; External interrupt 1 vector (not used in this code)
org 0x0013
	reti

; Timer/Counter 1 overflow interrupt vector
org 0x001B
	ljmp Timer1ISR 	; Jump to Timer1ISR

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
Soak_Temp:				ds 2		; default 150 (bcd)
Soak_Time:				ds 1		; default 90 (binary)
Reflow_Temp:			ds 2		; default 217 (bcd)
Reflow_Time:			ds 1		; default 50 (binary)
Power:					ds 1		; Indicates power to set oven to

; Reflow control / state machine variables
State_Counter:			ds 1 		; Current state number
State_Timer:			ds 1 		; Counter for how much time has been spent in state (binary!!! for djnz)

; Global variables for feedback
Current_Target_Temp:	ds 2		; required temp of current state
Current_Actual_Temp:	ds 2		; temp readout of thermocouple
Current_Temp_Diff:		ds 2		; target temp - actual temp
P_Adjust: 				ds 2		; Proportional factor adjustment
;I_Adjust: 				ds 1 		; Integral factor adjustment
;D_Adjust: 				ds 1 		; Derivative factor adjustment
;Pid_Total_Adjust: 		ds 1 		; Total weighted PID adjustment

; Variables for setting parameters
Dial_Val: 				ds 2		; for adjusting parameters
Set_Mode: 				ds 1		; 0:operation, else dial = (1:Soak_Temp, 2:Soak_Time, 3:Reflow_Temp, 4:Reflow_Time)

; Time Counters
Count_1Ms:     			ds 2 		; Used to determine when second has passed (referred to with Count_1Ms+0 and Count_1Ms+1)
Second_Counter:			ds 1 		; Counter for runtime seconds
Minute_Counter:			ds 1 		; Counter for runtime minutes

; Variables for math32.inc
x: 						ds 4 		; For math32
y: 						ds 4 		; For math32
bcd: 					ds 5 		; For 10 digit BCD for math32

; Single-bit variables
; In the 8051 we have variables that are 1-bit in size.  We can use the setb, clr, jb, and jnb
; instructions with these variables.  This is how you define a 1-bit variable:
bseg
Seconds_Flag: 		dbit 1		; Set to one in the ISR every time 100 ms had passed

Oven_Switch:		dbit 1		; For indicating the current ON/OFF status of oven

mf: 				dbit 1		; For math32

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
Timer0Init:
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
Timer0ISR:
	;clr TF0  ; According to the data sheet this is done for us already.
	;cpl LED_OUT 								; Invert LED output to generate square wave
	reti

;---------------------------------;
; Routine to initialize the ISR   ;
; for timer 2                     ;
;---------------------------------;
Timer1Init:
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
Timer1ISR:
	clr TF1  									; Timer 2 doesn't clear TF2 automatically. Do it in ISR
	cpl P3.6 									; To check the interrupt rate with oscilloscope. It must be precisely a 1 ms pulse.

	; The two registers used in the ISR must be saved in the stack
	push acc
	push psw

	; Increment the 16-bit one mili second counter
	inc Count_1Ms+0    							; Increment the low 8-bits first
	mov a, Count_1Ms+0 							; If the low 8-bits overflow, then increment high 8-bits
	jnz incDone
	inc Count_1Ms+1

incDone:
	; Check if 1 second has passed
	mov a, Count_1Ms+0
	cjne a, #low(1000), Timer2_ISR_done 		; Warning: this instruction changes the carry flag!
	mov a, Count_1Ms+1
	cjne a, #high(1000), Timer2_ISR_done

	; 1000 milliseconds have passed.  Set a flag so the main program knows
	setb Seconds_Flag 							; Let the main program know half second had passed
	; Reset to zero the milli-seconds counter, it is a 16-bit variable
	clr a
	mov Count_1Ms+0, a
	mov Count_1Ms+1, a

	; We are done ISR for timer 2
	pop psw
	pop acc
	reti

;---------------------------------;
; Configure serial port and baud  ;
; rate; serial port operations    ;
;---------------------------------;
; Configure the serial port and baud rate
InitializeSerialPort:
    ; Initialize serial port and baud rate using timer 2
	mov RCAP2H, #high(TIMER_2_RELOAD) 	; Set reload values so that Timer 2 matches baud rate
	mov RCAP2L, #low(TIMER_2_RELOAD) 	; Set reload values so that Timer 2 matches baud rate
	mov T2CON, #0x34 					; #00110100B
	mov SCON, #0x52 					; Serial port in mode 1, ren, txrdy, rxempty
	ret

putChar:
	jbc	TI,putChar_L1
	sjmp putChar
putChar_L1:
	mov	SBUF,a
	ret

getChar:
	jbc	RI,getChar_L1
	sjmp getChar
getChar_L1:
	mov	a,SBUF
	ret

SendString:
    clr a
    movc a, @a+dptr
    jz sendStringL1
    lcall putChar
    inc dptr
    sjmp SendString
sendStringL1:
	ret

; Send a 4-digit BCD number stored in [R3,R2] to the serial port
SendNumber:
	mov a, R3
	swap a
	anl a, #0x0f
	orl a, #'0'
	lcall putChar
	mov a, #'.'
	lcall putChar
	mov a, R3
	anl a, #0x0f
	orl a, #'0'
	lcall putChar
	mov a, R2
	swap a
	anl a, #0x0f
	orl a, #'0'
	lcall putChar
	mov a, R2
	anl a, #0x0f
	orl a, #'0'
	lcall putChar
	mov a, #'\r' 		;****
	lcall putChar 		;****
	mov a, #'\n' 		;****
	lcall putChar 		;****
	ret

;---------------------------------;
; Code for initializing LEDs      ;
;---------------------------------;
InitializeLEDs:
    ; Turn off LEDs on DE1SoC
	mov	LEDRA,#0x00
	mov	LEDRB,#0x00
	; Turn of state indication LEDs
	clr STATE1_LED
	clr STATE2_LED
	clr STATE3_LED
	clr STATE4_LED
	clr STATE5_LED
	ret

;---------------------------------;
; ADC configuration and operation ;
;---------------------------------;

InitializeADC:
	; Initialize SPI pins connected to LTC2308
	clr	MY_MOSI
	clr	MY_SCLK
	setb CE_ADC
	ret

LTC2308TogglePins:
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
LTC2308RW:
    clr a
	clr	CE_ADC ; Enable ADC

    ; Send 'S/D', get bit 11
    setb c ; S/D=1 for single ended conversion
    lcall LTC2308TogglePins
    mov acc.3, c
    ; Send channel bit 0, get bit 10
    mov c, b.2 ; O/S odd channel select
    lcall LTC2308TogglePins
    mov acc.2, c
    ; Send channel bit 1, get bit 9
    mov c, b.0 ; S1
    lcall LTC2308TogglePins
    mov acc.1, c
    ; Send channel bit 2, get bit 8
    mov c, b.1 ; S0
    lcall LTC2308TogglePins
    mov acc.0, c
    mov R1, a

    ; Now receive the lest significant eight bits
    clr a
    ; Send 'UNI', get bit 7
    setb c ; UNI=1 for unipolar output mode
    lcall LTC2308TogglePins
    mov acc.7, c
    ; Send 'SLP', get bit 6
    clr c ; SLP=0 for NAP mode
    lcall LTC2308TogglePins
    mov acc.6, c
    ; Send '0', get bit 5
    clr c
    lcall LTC2308TogglePins
    mov acc.5, c
    ; Send '0', get bit 4
    clr c
    lcall LTC2308TogglePins
    mov acc.4, c
    ; Send '0', get bit 3
    clr c
    lcall LTC2308TogglePins
    mov acc.3, c
    ; Send '0', get bit 2
    clr c
    lcall LTC2308TogglePins
    mov acc.2, c
    ; Send '0', get bit 1
    clr c
    lcall LTC2308TogglePins
    mov acc.1, c
    ; Send '0', get bit 0
    clr c
    lcall LTC2308TogglePins
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
DisplayBCDSeg7:
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
    lcall Timer0Init								; Initialize Timer 0
    lcall Timer1Init								; Initialize Timer 1
    setb EA 										; Allow global interrupts
    lcall InitializeLEDs 							; Initialize LEDs to be all off
    lcall InitializeADC							; Initialize SPI
    lcall ELCD_4BIT 								; Initialize LCD to 4 bit mode
    lcall InitializeSerialPort					; Initialize serial port
    ; Set up variable initial values

	; Dseg variables

	    ; Reflow paramter variables
	    mov Soak_Temp, #150 							; Default soak temperature (150C)
	    mov Soak_Time, #90 								; Default soak time duration (90s)
	    mov Reflow_Temp, #217 							; Default reflow temperature (217C)
	    mov Reflow_Time, #50 							; Default reflow time duration (50s)

	    ; Reflow control / state machine variables
	    mov State_Counter, #0 							; Initialize state to WAIT state
	    mov State_Timer, #0 						; Initialize time counter (for measuring how much time we are in each state) to 0

	    ; Global Variables for feedback
	    mov Current_Target_Temp, #0 					; Initialize target temperature to 0 (for debugging purposes)
	    mov Current_Actual_Temp, #0 					; Initialize current temperature to 0 (for debugging purposes)
	    mov Current_Temp_Diff, #0 						; Initialize temperature difference between current and target to 0
	    mov P_Adjust, #0 								; Initialize the proportional adjustment variable to 0
	    ;mov I_Adjust, #0 								; Initialize the integral adjustment variable to 0
	    ;mov D_Adjust, #0 								; Initialize the derivative adjustment variable to 0

	    ; Variables for setting parameters
	    mov Dial_Val, #0 								; Initialize the dial reading (from ADC) to 0
	    mov Set_Mode, #0 								; Initialize the "state counter" for setting paramters to "not setting"

	    ; Timekeeping variables
	    mov Count_1Ms, #0 								; Set Count_1Ms initial value as 0
	    mov Count_1Ms+1, #0
	    mov Second_Counter, #0 							; Initialize Second_Counter as 0
	    mov Minute_Counter, #0 							; Initialize HOUR_COUNTER as 0

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
	    setb Seconds_Flag 								; Initialize Seconds_Flag to 1 so that we update display right away
	    clr mf 											; Clear the comparison flag
	; After initialization the program stays in this 'forever' loop
forever:

;---------------------------------;
; Toggle button controls          ;
;---------------------------------;
	jb BOOT_BUTTON, bootButtonNotPressed  		; if the 'BOOT' button is not pressed skip
	Wait_Milli_Seconds(#50)							; Debounce delay.  This macro is also in 'LCD_4bit.inc'
	jb BOOT_BUTTON, bootButtonNotPressed  		; if the 'BOOT' button is not pressed skip
	jnb BOOT_BUTTON, $								; Wait for button release.  The '$' means: jump to same instruction.
	; A valid press of the 'BOOT' button has been detected, reset the BCD counter.
	; But first stop timer 2 and reset the milli-seconds counter, to resync everything.
	clr TR2                 						; Stop timer 2
	clr a 											; Clear a
	mov Count_1Ms+0, a 								; Set Count_1Ms+0 = #0
	mov Count_1Ms+1, a 								; Set Count_1Ms+1 = #0
	setb TR2                						; Re-start timer 2
	ljmp updateDisplay             				; Go to update display
bootButtonNotPressed:
	jnb Seconds_Flag, forever						; If button not pressed and it is not yet a new "second", go back to beginning of forever loop
updateDisplay:
	clr Seconds_Flag 								; We clear this flag in the main loop, but it is set in the ISR for timer 2
	cpl LEDRA.0										; Indicate cycles

	;------------------------------------------------- FSM Peripheral Function Calls

	lcall UpdateOven								; Function for updating oven control based on Oven_Switch flag
	lcall ReadTempAndDial							; Function for reading ADC inputs (LM335, k-type junction, and dial)
	lcall SettingParams								; Function for setting reflow parameters and storing them in EEPROM
	lcall UpdateDisplay7Seg							; Function for updating 7Seg display with current temperature
	lcall UpdateDisplayLCD							; Function for updating LCD display with information
	lcall DisplayStateOnLEDs						; Function for displaying current stage progress on LEDs

	;------------------------------------------------- FSM

		; non-blocking state machine for KEY1 starts here
		mov a, State_Counter
		wait:
			cjne a, #WAIT, rampToSoak
				; At this point we are in wait state state
				jb START_BUTTON, doneWaitState								; Poll for initial press
				Wait_Milli_Seconds(#50)										; Debounce delay
				jb START_BUTTON, doneWaitState								; Check for bounce
				jnb START_BUTTON, $											; Stay here until button release
					; At this point, we have detected a valid press of the start button
					cjne SET_MODE, #0, doneWaitState						; if we are setting something, keep waiting
						; The following code executes when START_BUTTON has been pressed and we are not setting anything
						mov State_Timer, #60								; Start a counter for 60s for the safety check
						mov Current_Target_Temp+0, Soak_Temp+0				; Set the target temperature as Soak_Temp
						mov Current_Target_Temp+1, Soak_Temp+1
						setb Oven_Switch									; Ramp to next temperature as fast as possible
						mov State_Counter, #RAMP_TO_SOAK 					; Go to next state
						lcall stateChangeBeep 								; Little beep of the speaker to indicate state change
				doneWaitState:
					ljmp fsm1Done
		rampToSoak:
			cjne a, #RAMP_TO_SOAK, soak
				; At this point we are in rampToSoak state
				mov x+0, Current_Actual_Temp+0								; Move Current_Actual_Temp to x
				mov x+1, Current_Actual_Temp+1
				mov x+2, #0
				mov x+3, #0
				mov y+0, Current_Target_Temp+0								; Move Current_Target_Temp to y
				mov y+1, Current_Target_Temp+1
				mov y+2, #0
				mov y+3, #0
				lcall x_lt_y												; Compare x and y, mf = 1 if x < y
				jb mf, notAtSoakTemp										; If Current_Actual_Temp < Current_Target_Temp don't move to SOAK
					; At this point, the oven temperature has reached soak temperature
					mov State_Timer, Soak_Time								; Set timer to length of soak period
					mov State_Counter, #SOAK								; Set state to SOAK
					lcall stateChangeBeep 									; Little beep of the speaker to indicate state change
					ljmp doneRampToSoakState								; Finish with current state and move on to forever to begin SOAK
				notAtSoakTemp:
					; At this point, the oven temperature has not reached soak temperature yet
					jb Safety_Check_Flag, doneRampToSoakState				; If we have passed the safety check already, no need to keep checking
					djnz State_Timer, doneRampToSoakState					; If our safety timer isn't zero we continue to count down
						; At this point, the safety counter has run out, we are at 60 seconds and check if oven has reached 50C
						mov x+0, Current_Actual_Temp+0						; Move Current_Actual_Temp to x
						mov x+1, Current_Actual_Temp+1
						mov x+2, #0
						mov x+3, #0
						mov y+0, #low(50)									; Move 50 to y
						mov y+1, #high(50)
						mov y+2, #0
						mov y+3, #0
						lcall x_lteq_y										; mf = 1 is x <= y
						jnb mf, safetyCheckPassed							; If we have reached 50C in 60s, check is complete
							; At this point, we have encountered an error with the oven (temp < 50C @ 60s)
							clr Oven_Switch									; Turn off oven
							mov State_Counter, #WAIT						; Go back to wait state
							lcall errorBeep									; Beep to indicate error
							ljmp doneRampToSoakState
						safetyCheckPassed:
							; At this point, we have passed the safety check, we should set the flag to indicate we are done
							setb Safety_Check_Flag							; Indicate we have passed safety check
				doneRampToSoakState:
					ljmp fsm1Done											; We are finished with the current state
		soak:
			cjne a, #SOAK, rampToReflow
				; At this point we are in soak state
				djnz State_Timer, maintainSoakTemp							; If our safety timer isn't zero we continue to count down
					; At this point, we State_Timer has reached 0 so we need to move to the next state
					mov Current_Target_Temp+0, Reflow_Temp+0				; Set the target temperature as Soak_Temp
					mov Current_Target_Temp+1, Reflow_Temp+1
					setb Oven_Switch										; Ramp to next temperature as fast as possible
					mov State_Counter, #RAMP_TO_REFLOW 						; Go to next state
					lcall stateChangeBeep 									; Little beep of the speaker to indicate state change
					ljmp doneSoakState										; Finished with current state, move on to forever to begin RAMP_TO_REFLOW
				maintainSoakTemp:
					; At this point we have not finished soaking yet, so maintain the temperature
					lcall AdjustTemp										; Call AdjustTemp function to maintain constant temperature
				doneSoakState:
					ljmp fsm1Done
		rampToReflow:
			cjne a, #RAMP_TO_REFLOW, reflow
				; At this point we are in rampToReflow state
				mov x+0, Current_Actual_Temp+0								; Move Current_Actual_Temp to x
				mov x+1, Current_Actual_Temp+1
				mov x+2, #0
				mov x+3, #0
				mov y+0, Current_Target_Temp+0								; Move Current_Target_Temp to y
				mov y+1, Current_Target_Temp+1
				mov y+2, #0
				mov y+3, #0
				lcall x_lt_y												; Compare x and y, mf = 1 if x < y
				jb mf, doneRampToReflowState									; If Current_Actual_Temp < Current_Target_Temp do nothing
					; At this point, the oven temperature has reached reflow temperature
					mov State_Timer, Reflow_Time							; Set timer to length of reflow period
					mov State_Counter, #REFLOW								; Set state to REFLOW
					lcall stateChangeBeep 									; Little beep of the speaker to indicate state change
					ljmp doneRampToReflowState								; Finish with current state and move on to forever to begin REFLOW
				doneRampToReflowState:
					sjmp fsm1Done
		reflow:
			cjne a, #REFLOW, coolDown
				; At this point we are in reflow state
				djnz State_Timer, maintainReflowTemp						; If our safety timer isn't zero we continue to count down
					; At this point, we State_Timer has reached 0 so we need to move to the next state
					mov Current_Target_Temp+0, #low(COOL_TO_TOUCH_TEMP)		; Set the target temperature as COOL_TO_TOUCH_TEMP
					mov Current_Target_Temp+1, #high(COOL_TO_TOUCH_TEMP)
					clr Oven_Switch											; Cool down as fast as possible
					mov State_Counter, #COOL_DOWN 							; Go to next state
					lcall stateChangeBeep 									; Little beep of the speaker to indicate state change
					ljmp doneReflowState									; Finished with current state, move on to forever to begin COOL_DOWN
				maintainReflowTemp:
					; At this point we are not done reflowing yet, so we maintain the temperature
					lcall AdjustTemp										; Call AdjustTemp function to maintain constant temperature
				doneReflowState:
					ljmp fsm1Done
		coolDown:
			cjne a, #COOL_DOWN, coolToTouch
				; At this point we are in coolDown state
				mov x+0, Current_Actual_Temp+0								; Move Current_Actual_Temp to x
				mov x+1, Current_Actual_Temp+1
				mov x+2, #0
				mov x+3, #0
				mov y+0, Current_Target_Temp+0								; Move Current_Target_Temp to y
				mov y+1, Current_Target_Temp+1
				mov y+2, #0
				mov y+3, #0
				lcall x_gt_y												; Compare x and y, mf = 1 if x > y
				jb mf, doneRampToReflowState									; If Current_Actual_Temp > Current_Target_Temp do nothing
					; At this point, the oven temperature has reached reflow temperature
					mov State_Counter, #COOL_TO_TOUCH						; Set state to COOL_TO_TOUCH
					lcall stateChangeBeep 									; Little beep of the speaker to indicate state change
					ljmp doneCoolDownState									; Finish with current state and move on to forever to begin COOL_TO_TOUCH
				doneCoolDownState:
					ljmp fsm1Done
		coolToTouch:
			cjne a, #COOL_TO_TOUCH, fsm1Done
				; At this point we are in coolToTouch state
				lcall stateChangeBeep										; Call beep 6 times
				Wait_Milli_Seconds(#250)
				lcall stateChangeBeep
				Wait_Milli_Seconds(#250)
				lcall stateChangeBeep
				Wait_Milli_Seconds(#250)
				lcall stateChangeBeep
				Wait_Milli_Seconds(#250)
				lcall stateChangeBeep
				Wait_Milli_Seconds(#250)
				lcall stateChangeBeep
				mov State_Counter, #WAIT									; Go back to the wait state
			ljmp fsm1Done
		fsm1Done:

	jmp forever

;------------------------------------------- FSM Peripheral Functions




END
