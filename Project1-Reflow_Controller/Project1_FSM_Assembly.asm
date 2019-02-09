;------------------------------------------------------------------------------;
;------------------------- formatting guidelines ------------------------------;
; label name: lowercaseUppercase
; Function name: UpperCaseUppercase
; Symbolic Constants: CAPSCAPSCAPS
; Variables: Uppercase_Uppercase
; Global Variables(except x,y,z): CAPS_CAPS_CAPS
;------------------------------------------------------------------------------;
START_BUTTON equ P4.5													; arbitrary pin for start button

; ARM Translation for FSM
forever:

	; non-blocking state machine for KEY1 starts here
	mov a, STATE_COUNTER
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
					mov STATE_TIMER, #60								; Start a counter for 60s for the safety check
					mov Current_Target_Temp+0, Soak_Temp+0				; Set the target temperature as Soak_Temp
					mov Current_Target_Temp+1, Soak_Temp+1
					mov Power, #100										; Ramp to next temperature as fast as possible
					mov STATE_COUNTER, #RAMP_TO_SOAK 					; Go to next state
					lcall stateChangeBeep 								; Little beep of the speaker to indicate state change
			doneWaitState:
				ljmp fsm1Done
	rampToSoak:
		cjne a, #RAMP_TO_SOAK, soak
			; At this point we are in rampToSoak state
			mov x+0, Current_Actual_Temp+0
			mov x+1, Current_Actual_Temp+1
			mov x+2, #0
			mov x+3, #0
			mov y, #Current_Target_Temp
			lcall x_lt_y
			jb mb, notAtSoak										; if Current_Actual_Temp<Current_Target_Temp don't move to SOAK
				mov State_Timer, #SOAK_TIME							; set timer to length of soak period
				mov STATE_COUNTER, #SOAK							; set state to SOAK
				ljmp fsm1Done										; finish with current state and move on to forever to begin SOAK
			notAtSoakTemp:
			cjne STATE_TIMER, #0, decCounter							; if our safety timer isn't zero we continue to count down
				mov x, #Current_Actual_Temp
				mov y, #50
				lcall x_lteq_y
				jb mb, errorTemp										; if Current_Actual_Temp<=50 and our safety timer was zero
				errorTemp:												; shut down and return to wait state after error
					mov Power, #0
					mov STATE_COUNTER, #WAIT
					lcall errorBeep
					ljmp fsm1Done
	soak:
		cjne a, #SOAK, rampToReflow
			; At this point we are in soak state
			cjne State_Timer, #0, decCounter							; if our safety timer isn't zero we continue to count down

		sjmp fsm1Done
	rampToReflow:
		cjne a, #RAMP_TO_REFLOW, reflow
			; At this point we are in rampToReflow state
		sjmp fsm1Done
	reflow:
		cjne a, #REFLOW, coolDown
			; At this point we are in reflow state
		sjmp fsm1Done
	coolDown:
		cjne a, #COOL_DOWN, coolToTouch
			; At this point we are in coolDown state
		sjmp fsm1Done
	coolToTouch:
		cjne a, #COOL_TO_TOUCH, fsm1Done
			; At this point we are in coolToTouch state
		sjmp fsm1Done
	fsm1Done:

jmp forever

//
;0:
	jb START_BUTTON, checkSettings
		jmp forever											; if start button not pressed, keep waiting
	checkSettings:
		cjne SET_MODE, #0, forever							; if we are setting something, keep waiting
			; The following code executes when START_BUTTON has been pressed and we are not setting anything
			mov a, #60
			mov State_Timer, a							; Start a counter for 60s for the safety check
			mov a, Soak_Temp
			mov Current_Target_Temp, a							; Set the target temperature as Soak_Temp
			mov a, 100
			mov Power, a										; Ramp to next temperature as fast as possible
			mov a, RAMP_TO_SOAK
			mov STATE_COUNTER, a 								; Go to next state
			lcall stateChangeBeep 								; Little beep of the speaker to indicate state change
			jmp forever
;1:
	cjne State_Timer, #0, decCounter
		;jb x_lteq_y(Current_Actual_Temp, #50), errorTemp
		mov x, Current_Actual_Temp
		mov y, #50
		x_lteq_y
		jb mb, errorTemp
			mov a, SOAK_TIME
			mov State_Timer, a
			mov a, SOAK
			mov STATE_COUNTER, a
			jmp forever
		errorTemp:
			mov a, #0
			mov Power, a
			mov a, WAIT
			mov STATE_COUNTER, a
			lcall errorBeep
			jmp forever
	decCounter:
