program fsm("P")

#include "seqPVmacros.h"

/* Turn on run-time debug messages */
option +d;

/* PV definitions */
PV(float, test, "{P}:LIMIT:SP", Monitor);


foreign ssId;

ss fsm
{
  state unknown
  {
    when()
	{
	  printf("this wsdfsdfsdforks!");
	  test = -10;
	  pvPut(test);
	  
	} state unknown
  }
}


