; Pseudocode for Project1.asm

; State “symbolic constant” definitions
0 -> WAIT
1 -> RAMP_TO_SOAK
2 -> SOAK
3 -> RAMP_TO_REFLOW
4 -> REFLOW
5 ->COOL_DOWN

; forever loop
forever:

	;...
	; Other code that gets run every forever loop
	;...
	lcall updateOven											; Reads the OVEN_SWITCH bit flag and sets output to oven accordingly
	lcall updateTemp 											; Does the SPI and calculations to get CURRENT_ACTUAL_TEMP
	lcall updateDisplay7Seg										; Updates the 7-segment display to show CURRENT_ACTUAL_TEMP
	lcall updateDisplayLCD										; Show reflow process current state, temperature(s) (current and target temperature), and running time using LCD
	lcall update_state_display									; Updates the LED board displaying the current state

	; Finite state machine cases
	case( STATE_COUNTER )

		0:  													; WAIT
			if( START_BUTTON != 0 ) {							; If start button not pressed, keep waiting
				if( SET_MODE != 0 ) {							; If we are setting something, keep waiting
					jump forever 								; Go back to beginning of forever loop
				}
				; The following code executes when START_BUTTON has been pressed and we are not setting anything
				STATE_TIME_COUNTER = 60 						; Start a counter for 60s for the safety check
				CURRENT_TARGET_TEMP = SOAK_TEMP 				; Set the target temperature as SOAK_TEMP
				OVEN_SWITCH = 1									; Ramp to next temperature as fast as possible
				STATE_COUNTER = RAMP_TO_SOAK 					; Go to next state
				lcall stateChangeBeep 							; Little beep of the speaker to indicate state change
				jump forever
			} else {
				jump forever	 								; If start button not pressed, keep forever looping
			}

		1: 														; RAMP_TO_SOAK
			if( STATE_TIME_COUNTER == 0 ) { 					; Check if our 60 second ramping timer is done
				if(CURRENT_ACTUAL_TEMP <= 50) {					; At the end of 60 seconds, if we are not at 50C yet
					OVEN_SWITCH = 0								; Oven did not heat up, turn off
					STATE_COUNTER = WAIT						; Go back to wait state
					lcall errorBeep								; Beep to indicate error
					jump forever 								; Go back to beginning
				}
			}
			if( CURRENT_ACTUAL_TEMP <= CURRENT_TARGET_TEMP ) {	; While current temp less than target temp
				dec STATE_TIME_COUNTER							; We count down state time counter
				jump forever									; Go back to beginning
			}
			; The following code is executed if we have not encountered an oven error and are done heating up to SOAK_TEMP
			STATE_TIME_COUNTER = SOAK_TIME						; Set timer for soak time
			STATE_COUNTER = SOAK								; Next state will be to SOAK
			lcall stateChangeBeep								; Beep to indicate state change
			jump forever										; Go back to beginning

		2:														; SOAK
			if( STATE_TIME_COUNTER != 0 ){
				lcall adjustTemp								; Should take current_temp and target_temp
				dec STATE_TIME_COUNTER							; Decrement state timer to keep counting soak time
				jump forever									; Go back to beginning
			}
			; The following code executes when the timer indicates we are done the soak process
			OVEN_SWITCH = 1										; Ramp to reflow temperature as fast as possible
			CURRENT_TARGET_TEMP = REFLOW_TEMP					; Make target temp = reflow temp
			STATE_COUNTER = RAMP_TO_REFLOW						; Go to next state
			lcall stateChangeBeep								; Beep to indicate state change
			jump forever										; Go back to beginning

		3: 														; RAMP TO REFLOW
			if( CURRENT_ACTUAL_TEMP != CURRENT_TARGET_TEMP ) {	; While we have not reached the reflow temp, keep going back to beginning
				jump forever									; When we have not reached reflow temp, keep heating
			}
			; The following code executes when we have reached reflow temperature
			STATE_TIME_COUNTER = REFLOW_TIME					; Set the state timer as reflow time
			STATE_COUNTER = REFLOW								; Go to next state
			lcall stateChangeBeep								; Beep to indicate state change
			jump forever										; Go back to beginning

		4:														; REFLOW
			if( STATE_TIME_COUNTER != 0 ) {							; If timer hasn't finished yet, do nothing
				dec STATE_TIME_COUNTER							; Keep decrementing state timer
				lcall adjustTemp									; Maintain temperature with PWM
				jump forever									; Go back to beginning
			}
			; The following code executes when timer indicates we are done reflow time
			OVEN_SWITCH = 0										; Cool down ASAP
			CURRENT_TARGET_TEMP = SAFE_TEMP 					; Set safe to touch temperature as target
			STATE_COUNTER = COOL_DOWN							; Go to next state
			lcall stateChangeBeep								; Indicate state change with beep
			jump forever										; GO back to beginning

		5:														; COOL_DOWN
			if( CURRENT_ACTUAL_TEMP != CURRENT_TARGET_TEMP ) {	; Wait until we are at safe to touch temperature
				jump forever									; Do nothing, go back to beginning
			}
			; The following code executes when temp has reached the safe to touch temperature
			STATE_COUNTER = COOL_TO_TOUCH						; Go to next state
			lcall stateChangeBeep								; Call 6 beeps to indicate cool to touch
			lcall stateChangeBeep
			lcall stateChangeBeep
			lcall stateChangeBeep
			lcall stateChangeBeep
			lcall stateChangeBeep
			jump forever
		6: 														; COOL_TO_TOUCH
			if( BOOT_BUTTON != 0 ) 								; If reset button pressed, bo back to WAIT state
				STATE_COUNTER = WAIT
				jump forever
			} else {											; Else keep idling
				jump forever
			}

; Function: adjustTemp; paramters CURRENT_TARGET_TEMP, CURRENT_ACTUAL_TEMP
adjustTemp:
	CURRENT_TEMP_DIFF = CURRENT_TARGET_TEMP - CURRENT_ACTUAL_TEMP	; Calculate current temperature difference
	P_ADJUST = POWER_SCALER * CURRENT_TEMP_DIFF 					; Set power as a proportional value to current temperature difference
	POWER = P_ADJUST 												; In the future: POWER = k1*P_ADJUST + k2*I_ADJUST + k3*D_ADJUST
	lcall pwmAdjust 												; Use PWM to adjust the oven; this whole subroutine is called once every second
ret

; Function: pwmAdjust; parameter: POWER
pwmAdjust:
	; Uses timer 0, 2048Hz
	; PWM_ON_VAL + PWM_OFF_VAL always add to FREQ_SCALER * 100
	PWM_ON_VAL = FREQ_SCALER * POWER							; Local variable PWM_ON_VAL
	PWM_OFF_VAL = FREQ_SCALER * ( 100 - POWER )					; Local variable PWM_OFF_VAL
	if( OVEN_SWITCH != 1 ) {									; If oven was initially OFF
		if ( PWM_OFF_Counter != 0 ) {							; While PWM_OFF_COUNTER is not 0, keep decrementing and looping
			dec PWM_OFF_Counter
		} else {
			PWM_ON_Counter = PWM_ON_Val 						; Reload value of PWM_ON_Counter
			OVEN_SWITCH = 1										; Set oven to ON
		}
		ljmp done_PWM											; We are done
	} else {													; If oven was initially ON
		if( PWM_ON_COUNTER != 0 ) {								; While PWM_ON_COUNTER is not 0, keep decrementing and looping
			dec PWM_ON_COUNTER
		} else {
			PWM_OFF_COUNTER = PWM_OFF_Val 						; Reload value of PWM_OFF_Counter
			OVEN_SWITCH = 0										; Set oven as OFF
		}
		ljmp done_PWM											; We are done
	}
	done_PWM:
ret

; Show reflow process current state, temperature(s) (current and target temperature), and running time using LCD
updateDisplayLCD:
	case(STATE_COUNTER)
		0:														; WAIT
			Set_Cursor(1,1)
			Send_Constant_String(“Oven Controller”)
			Set_Cursor(2,1)
			Send_Constant_String(“Press ‘START’ to begin”)
		1:														; RAMP TO SOAK
			Set_Cursor(1,1)
			Send_Constant_String(“SOAK->”)
			Set_Cursor(1,8)
			Display_BCD(CURRENT_TARGET_TEMP)
			Set_Cursor(1,14)
			Display_BCD(CURRENT_TIME)							; TIME ELAPSED SINCE START
			Set_Cursor(2,1)
			Send_Constant_String(“CURRENT TEMP”)
			Set_Cursor(2,12)
			Display_BCD(CURRENT_ACTUAL_TEMP)
		2: 														; SOAK
			Set_Cursor(1,1)
			Send_Constant_String(“SOAKING”)
			Set_Cursor(1,11)
			Display_BCD(STATE_TIME_COUNTER)						; TIME ELAPSED IN STATE
			Set_Cursor(1,14)
			Display_BCD(CURRENT_TIME)							; TIME ELAPSED SINCE START
			Set_Cursor(2,1)
			Send_Constant_String(“CURRENT TEMP”)
			Set_Cursor(2,12)
			Display_BCD(CURRENT_ACTUAL_TEMP)
		3:														; RAMP TO REFLOW
			Set_Cursor(1,1)
			Send_Constant_String(“REFLOW->”)
			Set_Cursor(1,8)
			Display_BCD(CURRENT_TARGET_TEMP)
			Set_Cursor(1,14)
			Display_BCD(CURRENT_TIME)							; TIME ELAPSED SINCE START
			Set_Cursor(2,1)
			Send_Constant_String(“CURRENT TEMP”)
			Set_Cursor(2,12)
			Display_BCD(CURRENT_ACTUAL_TEMP)
		4: 														; REFLOW
			Set_Cursor(1,1)
			Send_Constant_String(“REFLOWING”)
			Set_Cursor(1,11)
			Display_BCD(STATE_TIME_COUNTER)						; TIME ELAPSED IN STATE
			Set_Cursor(1,14)
			Display_BCD(CURRENT_TIME)							; TIME ELAPSED SINCE START
			Set_Cursor(2,1)
			Send_Constant_String(“CURRENT TEMP”)
			Set_Cursor(2,13)
			Display_BCD(CURRENT_ACTUAL_TEMP)
		5: 														; COOL_DOWN
			Set_Cursor(1,1)
			Send_Constant_String(“OPEN OVEN”)
			Set_Cursor(1,14)
			Display_BCD(CURRENT_TIME) 							; TIME ELAPSED SINCE START
			Set_Cursor(2,1)
			Send_Constant_String(“CURRENT TEMP”)
			Set_Cursor(2,13)
			Display_BCD(CURRENT_ACTUAL_TEMP)
		6:
			Set_Cursor(1,1)
			Send_Constant_String(“COOL TO TOUCH”)
			Set_Cursor(2,1)
			Send_Constant_String(“CURRENT TEMP”)
			Set_Cursor(2,13)
			Display_BCD(CURRENT_ACTUAL_TEMP)

; Sound indication functions:
	stateChangeBeep:
	ret
	errorBeep:
	ret
