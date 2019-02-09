OVEN_PIN EQU ......

UpdateOven:
	jnb Oven_Switch, Ovenoff
	;Turn oven on
	setb OVEN_PIN
	sjmp UpdateOvenDone

ovenOff:
	;Turn oven off
	clr OVEN_PIN

updateOvenDone:
	ret
