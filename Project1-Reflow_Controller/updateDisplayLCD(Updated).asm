;not working, still in editing process ; this code works together with Warren and gabriel's thermocouple
updateDisplayLCD:
	push acc
	push psw
	push R0
	push R1
	lcall hex2bcd16	;display sensor value onto bcd
	mov a, State_Counter

waitDisplay:
	cjne a, #WAIT, rampToSoakDisplay
	Set_Cursor(1,1)
	Send_Constant_String("Oven Controller")
	Set_Cursor(2,1)
	Send_Constant_String("Press 'START'")
	ljmp updateDisplayLCDDone

rampToSoakDisplay: ;denote TC stands for thercouple temperature; oven temperature
	cjne a, #RAMP_TO_SOAK, soakDisplay
	Set_Cursor(1,1)
	Send_Constant_String("SOAK->")
	Set_Cursor(2,1)
	Send_Constant_String("TC:")
	Set_Cursor(2,4)
	Display_BCD(Current_Actual_Temp)
	Set_Cursor(1,12)
	Display_BCD(Minutes_Counter)
	Set_Cursor(1,14)
	Send_Constant_String(":")
	Set_Cursor(1,15)
	Display_BCD(Seconds_Counter)
	Set_Cursor(2,12)
	Send_Constant_String("RM:")
	Set_Cursor(2,15)
	Display_BCD(sensor)
	ljmp updateDisplayLCDDone

soakDisplay:
	cjne a, #SOAK, rampToReflowDisplay
	Set_Cursor(1,1)
	Send_Constant_String("SOAKING")
	Set_Cursor(2,1)
	Send_Constant_String("TC:")
	Set_Cursor(2,4)
	Display_BCD(Current_Actual_Temp)
	Set_Cursor(1,12)
	Display_BCD(Minutes_Counter)
	Set_Cursor(1,14)
	Send_Constant_String(":")
	Set_Cursor(1,15)
	Display_BCD(Seconds_Counter)
	Set_Cursor(2,12)
	Send_Constant_String("RM:")
	Set_Cursor(2,15)
	Display_BCD(sensor)
	ljmp updateDisplayLCDDone

rampToReflowDisplay:
	cjne a, #RAMP_TO_REFLOW, reflowDisplay
	Set_Cursor(1,1)
	Send_Constant_String("REFLOW->")
	Set_Cursor(2,1)
	Send_Constant_String("TC:")
	Set_Cursor(2,4)
	Display_BCD(Current_Actual_Temp)
	Set_Cursor(1,12)
	Display_BCD(Minutes_Counter)
	Set_Cursor(1,14)
	Send_Constant_String(":")
	Set_Cursor(1,15)
	Display_BCD(Seconds_Counter)
	Set_Cursor(2,12)
	Send_Constant_String("RM:")
	Set_Cursor(2,15)
	Display_BCD(sensor)
	ljmp updateDisplayLCDDone

reflowDisplay:
	cjne a, #REFLOW, coolDownDisplay
	Set_Cursor(1,1)
	Send_Constant_String("REFLOWING")
	Set_Cursor(2,1)
	Send_Constant_String("TC:")
	Set_Cursor(2,4)
	Display_BCD(Current_Actual_Temp)
	Set_Cursor(1,12)
	Display_BCD(Minutes_Counter)
	Set_Cursor(1,14)
	Send_Constant_String(":")
	Set_Cursor(1,15)
	Display_BCD(Seconds_Counter)
	Set_Cursor(2,12)
	Send_Constant_String("RM:")
	Set_Cursor(2,15)
	Display_BCD(sensor)
	ljmp updateDisplayLCDDone

coolDownDisplay:
	cjne a, #COOL_DOWN, coolToTouchDisplay
	Set_Cursor(1,1)
	Send_Constant_String("OPEN OVEN")
	Set_Cursor(2,1)
	Send_Constant_String("TC:")
	Set_Cursor(2,4)
	Display_BCD(Current_Actual_Temp)
	Set_Cursor(1,12)
	Display_BCD(Minutes_Counter)
	Set_Cursor(1,14)
	Send_Constant_String(":")
	Set_Cursor(1,15)
	Display_BCD(Seconds_Counter)
	Set_Cursor(2,12)
	Send_Constant_String("RM:")
	Set_Cursor(2,15)
	Display_BCD(sensor)
	ljmp updateDisplayLCDDone

coolToTouchDisplay:
	cjne a, #COOL_TO_TOUCH, updateDisplayLCDDone
	Set_Cursor(1,1)
	Send_Constant_String("COOL TO TOUCH")
	Set_Cursor(2,1)
	Send_Constant_String("TC:")
	Set_Cursor(2,4)
	Display_BCD(Current_Actual_Temp)
	Set_Cursor(1,12)
	Display_BCD(Minutes_Counter)
	Set_Cursor(1,14)
	Send_Constant_String(":")
	Set_Cursor(1,15)
	Display_BCD(Seconds_Counter)
	Set_Cursor(2,12)
	Send_Constant_String("RM:")
	Set_Cursor(2,15)
	Display_BCD(sensor)

updateDisplayLCDDone:
	pop R1
	pop R0
	pop psw
	pop acc
	
	ret
