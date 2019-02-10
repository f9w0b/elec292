updateDisplayLCD:
	mov a, State_Counter

waitDisplay:
	cjne a, #WAIT, rampToSoakDisplay
	Set_Cursor(1,1)
	Send_Constant_String("Oven Controller")
	Set_Cursor(2,1)
	Send_Constant_String("Press 'START'")
	ljmp updateDisplayLCDDone

rampToSoakDisplay:
	cjne a, #RAMP_TO_SOAK, soakDisplay
	Set_Cursor(1,1)
	Send_Constant_String("SOAK->")
	Set_Cursor(2,1)
	Send_Constant_String("Temp:")
	Set_Cursor(2,6)
	Display_BCD(Current_Actual_Temp)
	Set_Cursor(2,10)
	Send_Constant_String("Time:")
	Set_Cursor(2,15)
	Display_BCD(CURRENT_TIME)
	ljmp updateDisplayLCDDone

soakDisplay:
	cjne a, #SOAK, rampToReflowDisplay
	Set_Cursor(1,1)
	Send_Constant_String("SOAKING")
	Set_Cursor(2,1)
	Send_Constant_String("Temp:")
	Set_Cursor(2,6)
	Display_BCD(Current_Actual_Temp)
	Set_Cursor(2,10)
	Send_Constant_String("Time:")
	Set_Cursor(2,15)
	Display_BCD(CURRENT_TIME)
	ljmp updateDisplayLCDDone

rampToReflowDisplay:
	cjne a, #RAMP_TO_REFLOW, reflowDisplay
	Set_Cursor(1,1)
	Send_Constant_String("REFLOW->")
	Set_Cursor(2,1)
	Send_Constant_String("Temp:")
	Set_Cursor(2,6)
	Display_BCD(Current_Actual_Temp)
	Set_Cursor(2,10)
	Send_Constant_String("Time:")
	Set_Cursor(2,15)
	Display_BCD(CURRENT_TIME)
	ljmp updateDisplayLCDDone

reflowDisplay:
	cjne a, #REFLOW, coolDownDisplay
	Set_Cursor(1,1)
	Send_Constant_String("REFLOWING")
	Set_Cursor(2,1)
	Send_Constant_String("Temp:")
	Set_Cursor(2,6)
	Display_BCD(Current_Actual_Temp)
	Set_Cursor(2,10)
	Send_Constant_String("Time:")
	Set_Cursor(2,15)
	Display_BCD(CURRENT_TIME)
	ljmp updateDisplayLCDDone

coolDownDisplay:
	cjne a, #COOL_DOWN, coolToTouchDisplay
	Set_Cursor(1,1)
	Send_Constant_String("OPEN OVEN")
	Set_Cursor(2,1)
	Send_Constant_String("Temp:")
	Set_Cursor(2,6)
	Display_BCD(Current_Actual_Temp)
	Set_Cursor(2,10)
	Send_Constant_String("Time:")
	Set_Cursor(2,15)
	Display_BCD(CURRENT_TIME)
	ljmp updateDisplayLCDDone

coolToTouchDisplay:
	cjne a, #COOL_TO_TOUCH, updateDisplayLCDDone
	Set_Cursor(1,1)
	Send_Constant_String("COOL TO TOUCH")
	Set_Cursor(2,1)
	Send_Constant_String("Temp:")
	Set_Cursor(2,6)
	Display_BCD(Current_Actual_Temp)
	Set_Cursor(2,10)
	Send_Constant_String("Time:")
	Set_Cursor(2,15)
	Display_BCD(CURRENT_TIME)

updateDisplayLCDDone:
	ret
