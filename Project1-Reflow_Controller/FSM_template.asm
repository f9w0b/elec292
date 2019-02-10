; non-blocking state machine template
	mov a, FSM1_state
fsm1State0:
	cjne a, #fsm1State0, fsm1State1
		; At this point we are in state 0
		; Any escape sequences (when you are done) should ljmp to "doneFSM1State0"
	doneFSM1State0:
		ljmp FSM1_done
fsm1State1:
	cjne a, #fsm1State1, fsm1State2
		; At this point we are in state 1
	doneFSM1State1:
		ljmp FSM1_done
fsm1State2:
	cjne a, #fsm1State2, FSM1_done
		; At this point we are in state 2
	doneFSM1State2:
		ljmp FSM1_done
FSM1_done:
