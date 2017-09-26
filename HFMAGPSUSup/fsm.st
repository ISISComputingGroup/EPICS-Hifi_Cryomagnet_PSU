program fsm("P")

#include "seqPVmacros.h"

/* Turn on run-time debug messages */
option +d;

/* PV definitions */
PV(double, get_limit, "{P}:LIMIT", Monitor);
PV(double, get_contant, "{P}:CONSTANT", Monitor);
PV(double, get_zero, "{P}:ZERO", Monitor);
PV(string, get_ramp_target, "{P}:RAMPTARGET", Monitor);
PV(double, get_mid, "{P}:MID", Monitor);
PV(double, get_max, "{P}:MAX", Monitor);
PV(string, get_pause, "{P}:PAUSE", Monitor);
PV(double, get_ramp_rate, "{P}:RAMPRATE", Monitor);
PV(string, get_output_mode, "{P}:OUTPUTMODE", Monitor);
PV(string, get_heater_status, "{P}:HEATERSTATUS", Monitor);

PV(string, set_error, "{P}:ERRORMESSAGE", Monitor);
PV(double, set_zero, "{P}:ZERO", Monitor);

double set_limit; assign set_limit to "{P}:LIMIT:SP";
double set_constant; assign set_constant to "{P}:CONSTANT:SP";
int set_pause; assign set_pause to "{P}:PAUSE:SP";
double set_ramp_rate; assign set_ramp_rate to "{P}:RAMPRATE:SP";
double set_max; assign set_max to "{P}:MAX:SP";
double set_mid; assign set_mid to "{P}:MID:SP";
int set_output_mode; assign set_output_mode to "{P}:OUTPUTMODE:SP";
int set_target; assign set_target to "{P}:RAMPTARGET:SP";

float abs_target; /* absolute value of set target */

foreign ssId;

ss fsm {

  state init {
  
    /* Declare initial globals */
	entry {
	  printf("==> init: Setting initial variable values\n");
	  set_limit = 5.0; pvPut(set_limit);
	  set_constant = 0.00029; pvPut(set_constant);
	  set_zero = 0.000; pvPut(set_zero);
	  set_ramp_rate = 0.2; pvPut(set_ramp_rate);
	  set_max = 34.92; pvPut(set_max);
	  set_output_mode = 0; pvPut(set_output_mode);
	  set_pause = 1; pvPut(set_pause);
	  /* strcpy(): set new string value */
	  strcpy(set_error, "==> I'm an error!"); pvPut(set_error);
	
	  /* Get the Current Direction (GS), read and parse the response, noting it in a global, also note the Direction in a local variable*/	    
	}
	
    when(delay(2.5)) {	
	  printf("==> Moving to idle state...\n");
	} state heater_idle
  }  
  
  
  state heater_idle {
  
	entry {
	  printf("==> heater_idle: Waiting for heater to be switched off\n");
	}
	
	when(strcmp("OFF", get_heater_status)==0) {
	  printf("\n==> Moving to ramp check!\n");    
	} state ramp_idle
	
	/* probably dont need this loop? 
	when(strcmp("ON", get_heater_status)==0) {
	  
	} state heater_idle
    */	
  }
  
  
  state ramp_idle {
  
	entry {
	  printf("==> ramp_idle: Waiting for system to be unpaused...");
	}
	
	when(strcmp("ON", get_pause)==0) {
	  /* things to do when paused - monitor other variables? */
	  /*
	  
	  => Sweep Target limits set to +/- the absolute value of the max current if units are in Amps, 
	  if units are Gauss they are set to +/- the absolute value to the max current x 10000 x T/A Sweep

	  => Set Vout to the value in the global status

       =>If the Units are Amps set the output to the Output (A) value in the global status, 
	   if it is Gauss set it to Output (T) in the global status x 10000
	  */
	} state ramp_idle
	
    /* If system is unpaused, move to ramping state */
    when(strcmp("OFF", get_pause)==0) {
	  printf("\n==> Moving to ramp active state!\n");	
	  
	  /* set final target value to users target selection */
	  printf(get_ramp_target);
	  if (strcmp("ZERO", get_ramp_target)==0) {
		printf("\n==> zero target! setting mid...");
	    set_mid = get_zero;
	  }
	  else if (strcmp("MAX", get_ramp_target)==0) {
	    set_mid = get_max;
	  }
	  else {
	    set_mid = get_mid;
	  }
	  pvPut(set_mid);
	  printf("\n==> Mid val to set: %f", set_mid);
	  printf("\n==> Actual Mid Value: %f", get_mid);
	  
	  set_target = 1;
	  pvPut(set_target);
	  printf("\n==> Target: %s", get_ramp_target);
	  
	  /*
	  If Units are Gauss, Global B Target X (value to use) = (final target / 10000) / T/A Sweep
If Units are Tesla (AMPS?), Global B Target X (value to use) = final target

	  
	  */
	} state ramp_active	
  }
  
  state ramp_active {
  
	entry {
	  printf("\n==> ramp_active: Monitoring ramp... ");
	}
	
	when(strcmp("OFF", get_pause)==0) {
	/* whilst still ramping, do these things... */
	   /*
	  abs_target = abs(get_mid);
	  if (abs_target == 0)
	    set_target = 0;
		pvPut(set_target);
	If the Absolute of the value to use is 0:
	Send R0, read and parse the response, noting it in a global
Otherwise:
	Send S% [MID] value to use, read and parse the response, noting it in a global
If the Output at the start of the process * value to use < 0:
	Send R0, read and parse the response, noting it in a global
	Loop until At Target is TRUE:
		Send RS (ramp status), read and parse the response, noting it in a global
		Send GO (get output), read and parse the response, noting it in a global
If there are entries in the passed in ramp rate table (the local one on Shim X), make ramp table defined? True
IF there are entries in the passed in ramp rate table (the local one on Shim X), find the closest ramp rate, 
called closest ramp for clarity (used up to Gauss is less than the absolute value of output(A) from status returned 
from get output x the global T/A Sweep x 10000, first entry in table as table should be in used up to order – not enforced anywhere) 
and if the absolute of the Ramp Rate from the status returned during Get Output – closest ramp >= 0.0001, set the Ramp Rate (SR) to the
 closest ramp and write the status to the global status.
	If value to use < 0, send D-, otherwise send D+
	
Otherwise (Output at the start of the process * value to use > 0):
	If Output at the start = 0:
		If value to use < 0, send D-, otherwise send D+
	If value to set != 0, send R% (mid)
	Loop until At Target is TRUE:
		Send RS, read and parse the response, noting it in a global
		Send GO, read and parse the response, noting it in a global
If there are entries in the passed in ramp rate table (the local one on Shim X), make ramp table defined? True
IF there are entries in the passed in ramp rate table (the local one on Shim X), find the closest ramp rate, 
called closest ramp for clarity (used up to Gauss is less than the absolute value of output(A) from status returned
 from get output x the global T/A Sweep x 10000, first entry in table as table should be in used up to order – not enforced anywhere)
 and if the absolute of the Ramp Rate from the status returned during Get Output – closest ramp >= 0.0001, set the Ramp Rate (SR) to the 
 closest ramp and write the status to the global status.
	*/
	} state ramp_active
	
	/* If heater is turned on, abort ramp */
    when(strcmp("ON", get_heater_status)==0) {
	  set_pause = 1;
	  pvPut(set_pause);
	  printf("\n==> HEATER TURNED ON, ABORTING RAMP!\n");
	} state heater_idle

	/* if pause is on, stop ramping */
	when(strcmp("ON", get_pause)==0) {
	printf("==> Ramping paused!\n");
	} state ramp_idle
  }  
}
