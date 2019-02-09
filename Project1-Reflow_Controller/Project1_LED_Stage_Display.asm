DisplayStateOnLEDs:
	; non-blocking case-switch block for displaying LEDs based on state starts here
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
			Set_Cursor(2, 1)
    		Send_Constant_String(#waitLEDs_MESSAGE)
		ljmp fsmLEDDone

	rampTosoakLEDs:
		cjne a, #1, soakLEDs
			; At this point we are in rampTosoakLEDs state
			setb STATE1_LED
			clr STATE2_LED
			clr STATE3_LED
			clr STATE4_LED
			clr STATE5_LED
			Set_Cursor(2, 1)
    		Send_Constant_String(#RAMP_TO_soakLEDs_MESSAGE)
		ljmp fsmLEDDone

	soakLEDs:
		cjne a, #2, rampToreflowLEDs
			; At this point we are in soakLEDs state
			setb STATE2_LED
			clr STATE1_LED
			clr STATE3_LED
			clr STATE4_LED
			clr STATE5_LED
			Set_Cursor(2, 1)
    		Send_Constant_String(#soakLEDs_MESSAGE)
		ljmp fsmLEDDone

	rampToreflowLEDs:
		cjne a, #3, reflowLEDs
			; At this point we are in rampToreflowLEDs state
			setb STATE3_LED
			clr STATE1_LED
			clr STATE2_LED
			clr STATE4_LED
			clr STATE5_LED
			Set_Cursor(2, 1)
    		Send_Constant_String(#RAMP_TO_reflowLEDs_MESSAGE)
		ljmp fsmLEDDone

	reflowLEDs:
		cjne a, #4, coolDownLEDs
			; At this point we are in reflowLEDs state
			setb STATE4_LED
			clr STATE1_LED
			clr STATE2_LED
			clr STATE3_LED
			clr STATE5_LED
			Set_Cursor(2, 1)
    		Send_Constant_String(#reflowLEDs_MESSAGE)
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
			Set_Cursor(2, 1)
    		Send_Constant_String(#COOL_DOWN_MESSAGE)
		sjmp fsmLEDDone

	coolToTouchLEDs:
		cjne a, #6, fsmLEDDone
			; At this point we are in coolToTouchLEDs state
			; Fix LED 5 so that it matches the others
			call LEDAlign
			; Flash all LEDs
			cpl STATE1_LED
			cpl STATE2_LED
			cpl STATE3_LED
			cpl STATE4_LED
			cpl STATE5_LED
			Wait_Milli_Seconds(#100)
			Set_Cursor(2, 1)
    		Send_Constant_String(#COOL_TO_TOUCH_MESSAGE)
		sjmp fsmLEDDone
	fsmLEDDone:
	ret

; Function for aligning LEDs for flashing in final state;
LEDAlign:
	push acc
	jnb Unaligned_LED_Flag, alignLEDsDone
	clr Unaligned_LED_Flag
	clr STATE5_LED
alignLEDsDone:
	pop acc
	ret
