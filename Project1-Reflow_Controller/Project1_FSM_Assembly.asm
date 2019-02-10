;------------------------------------------------------------------------------;
;------------------------- formatting guidelines ------------------------------;
; label name: lowercaseUppercase
; Function name: UpperCaseUppercase
; Symbolic Constants: CAPS_CAPS_CAPS
; Variables: Uppercase_Uppercase
;------------------------------------------------------------------------------;
START_BUTTON equ P4.5													; arbitrary pin for start button
COOL_TO_TOUCH_TEMP EQU 50
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
