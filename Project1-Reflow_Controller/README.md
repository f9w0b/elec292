###### This is a repository for Project 1 - Reflow Oven Controller for ELEC 291/292.

# Reminders when coding:
*Format:*
	- Symbolic Constants, Buttons/Pins: CAPS_CAPS_CAPS
	- Global Variables (other than x, y, bcd for math32): Uppercase_Uppercase
	- Labels (for jumping): lowercaseUppercase
	- Function names: UpperCaseUppercase
	"ISR" and "LED" can be capitalized regardless of guidelines
**Please use hard tabs (tab characters) instead of spaces, makes cleaning up formatting much easier**

*Code:*
	- When using math32.inc, and using registers "x" and "y", make sure to move as follows:
    mov x+0, variable+0		; Move low bits of "variable" into "x"
    mov x+1, variable+1		; Move higher bits of "variable" into "x"
    mov x+2, #0				; Clear
    mov x+3, #0				; Clear (these help make sure no residue)
	
