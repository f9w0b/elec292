; ARM Translation for FSM
forever:

	; non-blocking state machine for KEY1 starts here
		mov a, STATE_COUNTER
	wait:
		cjne a, #0, rampToSoak
			; At this point we are in wait state state
		sjmp fsm1Done
	rampToSoak:
		cjne a, #1, soak
			; At this point we are in rampToSoak state
		sjmp fsm1Done
	soak:
		cjne a, #2, rampToReflow
			; At this point we are in soak state
		sjmp fsm1Done
	rampToReflow:
		cjne a, #3, reflow
			; At this point we are in rampToReflow state
		sjmp fsm1Done
	reflow:
		cjne a, #4, coolDown
			; At this point we are in reflow state
		sjmp fsm1Done
	coolDown:
		cjne a, #5, coolToTouch
			; At this point we are in coolDown state
		sjmp fsm1Done
	coolToTouch:
		cjne a, #6, fsm1Done
			; At this point we are in coolToTouch state
		sjmp fsm1Done
	fsm1Done:

jmp forever

//
;0:
	cjne START_BUTTON, #0, checkSettings
		jmp forever											; if start button not pressed, keep waiting
	checkSettings:
		cjne SET_MODE, #0, forever							; if we are setting something, keep waiting
			; The following code executes when START_BUTTON has been pressed and we are not setting anything
			mov a, #60
			mov STATE_TIME_COUNTER, a							; Start a counter for 60s for the safety check
			mov a, SOAK_TEMP
			mov CURRENT_TARGET_TEMP, a							; Set the target temperature as SOAK_TEMP
			mov a, 100
			mov POWER, a										; Ramp to next temperature as fast as possible
			mov a, RAMP_TO_SOAK
			mov STATE_COUNTER, a 								; Go to next state
			lcall stateChangeBeep 								; Little beep of the speaker to indicate state change
			jmp forever
;1:
	cjne STATE_TIME_COUNTER, #0, decCounter
		jb x_lteq_y(CURRENT_ACTUAL_TEMP, #50), errorTemp
			mov a, SOAK_TIME
			mov STATE_TIME_COUNTER, a
			mov a, SOAK
			mov STATE_COUNTER, a
			jmp forever
		errorTemp:
			mov a, #0
			mov POWER, a
			mov a, WAIT
			mov STATE_COUNTER, a
			lcall errorBeep
			jmp forever
	decCounter:
