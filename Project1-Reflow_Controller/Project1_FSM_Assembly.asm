;------------------------------------------------------------------------------;
;------------------------- formatting guidelines ------------------------------;
; label name: lowercaseUppercase
; Function name: UpperCaseUppercase
; Symbolic Constants: CAPS_CAPS_CAPS
; Variables: Uppercase_Uppercase
;------------------------------------------------------------------------------;
START_BUTTON equ P4.5													; arbitrary pin for start button
bseg:
Safety_Check_Flag	dbit 1

; ARM Translation for FSM
forever:

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
					mov Power, #100										; Ramp to next temperature as fast as possible
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
						mov Power, #0									; Turn off oven
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
				mov Power, #100											; Ramp to next temperature as fast as possible
				mov State_Counter, #RAMP_TO_REFLOW 						; Go to next state
				lcall stateChangeBeep 									; Little beep of the speaker to indicate state change
				ljmp doneSoakState										; Finished with current state, move on to forever to begin RAMP_TO_REFLOW
			maintainSoakTemp:
				lcall AdjustTemp										; Call AdjustTemp function to maintain constant temperature
			doneSoakState:
				ljmp fsm1Done
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
			mov State_Counter, a 								; Go to next state
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
			mov State_Counter, a
			jmp forever
		errorTemp:
			mov a, #0
			mov Power, a
			mov a, WAIT
			mov State_Counter, a
			lcall errorBeep
			jmp forever
	decCounter:
