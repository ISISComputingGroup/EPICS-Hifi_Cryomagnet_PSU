program fsm("P")

#include "seqPVmacros.h"
%{#include <stdlib.h>}%
%{#include <stdio.h>}%

/* Turn on run-time debug messages */
option +d;

/* PV definitions */

PV(double, get_mid, "{P}:MID", Monitor);
PV(double, get_max, "{P}:MAX", Monitor);
PV(double, get_zero, "{P}:ZERO", Monitor);
PV(double, get_limit, "{P}:LIMIT", Monitor);
PV(string, get_pause, "{P}:PAUSE", Monitor);
PV(double, get_output, "{P}:OUTPUT", Monitor);
PV(double, get_contant, "{P}:CONSTANT", Monitor);
PV(string, get_direction, "{P}:DIRECTION", Monitor);
PV(double, get_ramp_rate, "{P}:RAMPRATE", Monitor);
PV(string, get_ramp_target, "{P}:RAMPTARGET", Monitor);
PV(string, get_output_mode, "{P}:OUTPUTMODE", Monitor);
PV(string, get_heater_status, "{P}:HEATERSTATUS", Monitor);
PV(double, get_final_target, "{P}:MIDFINALTARGET", Monitor);

PV(double, set_zero, "{P}:ZERO", Monitor);
PV(string, set_error, "{P}:ERRORMESSAGE", Monitor);
PV(double, set_final_target, "{P}:MIDFINALTARGET", Monitor);

/* set these three to the lower type of PV assignment, not PV() */

double set_max; assign set_max to "{P}:MAX:SP";
double set_mid; assign set_mid to "{P}:MID:SP";

int set_pause; assign set_pause to "{P}:PAUSE:SP";
double set_limit; assign set_limit to "{P}:LIMIT:SP";
int set_target; assign set_target to "{P}:RAMPTARGET:SP";
int set_direction; assign set_direction to "{P}:DIRECTION:SP";
double set_constant; assign set_constant to "{P}:CONSTANT:SP";
double set_ramp_rate; assign set_ramp_rate to "{P}:RAMPRATE:SP";
int set_output_mode; assign set_output_mode to "{P}:OUTPUTMODE:SP";

/* File reading variables */
char buffer[25];
int line = 0;

char *token;
char delim[2] = " ";
int temp_target_table_index = 0;

/* Ramp Rate Check Variables */
double difference;
double check_difference;

double final_target;
int largest_target_index;

double ramp_rates[64];
double ramp_targets[64];


float abs_target;

/* Reading ramp table values from external txt file */
%{
	
static int read_ramp_rates() {	
	printf("\nI survived the read_ramp_rate function call");
	FILE *ramp_file;
	ramp_file = fopen("C:\\Instrument\\Settings\\config\\common\\ramps\\cryomag_ramp_table.txt", "r");
	printf("\nI survived the file being opened");
	if (ramp_file != NULL) {
		/* skip first line */
		fgets(buffer, 25, ramp_file);
		printf("\nI survived skipping the first file line");
		while (fgets(buffer, 25, ramp_file) != NULL) {
			token = strtok(buffer, delim);
			ramp_targets[line] = strtod(token, NULL);
			token = strtok(NULL, delim);
			ramp_rates[line] = strtod(token, NULL);
			line++;
		}
	}
	else {
		printf("\nFile Read Error");
		exit(-1);
	}
	fclose(ramp_file);
	printf("\n==> Ramp Table File read complete ^_^");
	
	/* Print ramp rate table values 
	for (int i = 0; i < line; i++) {
		printf("\nTarget:\t %f \t Rate:\t %f", ramp_targets[i], ramp_rates[i]);
	}
	*/
}

static int find_nearest_ramp_rate(double current_output) {

	difference = 50000;
	int nearest_index = 0;
	largest_target_index = 0;
	for (int x = 0; x < line; x++) {
		if (ramp_targets[x] > ramp_targets[largest_target_index]) {
			largest_target_index = x;
		}
		if (ramp_targets[x] > current_output) {
			check_difference = ramp_targets[x] - current_output;
			if (check_difference < difference) {
				difference = check_difference;				
				nearest_index = x;
			}
		}
	}
	if (get_final_target > ramp_targets[largest_target_index]) {
		nearest_index = -1;
	}
	printf("\n");
	printf("\n==> Current output: %f \t next output target: %f \t index: %d", current_output, ramp_targets[nearest_index], nearest_index);
	printf("\n");
	return nearest_index;
}

}%

foreign ssId;

ss fsm {

	state init {
  
		entry {
			/* Set initial PV variables */
			printf("\n==> init: Setting initial variable values\n");
			set_limit = 5.0; pvPut(set_limit, SYNC);
			set_constant = 0.00029; pvPut(set_constant, SYNC);
			set_zero = 0.000; pvPut(set_zero, SYNC);
			set_ramp_rate = 0.2; pvPut(set_ramp_rate, SYNC);
			set_max = 34.92; pvPut(set_max, SYNC);
			set_output_mode = 0; pvPut(set_output_mode, SYNC);
			set_pause = 1; pvPut(set_pause, SYNC);			
			/* strcpy(): because C */
			strcpy(set_error, "==> I'm an error!"); pvPut(set_error, SYNC);
			

			/* Get the Current Direction (GS), read and parse the response, noting it in a global, also note the Direction in a local variable*/	    
		}

		when(delay(1)) {	
			printf("\n==> Moving to idle state...");
		} state heater_idle
	}  


	state heater_idle {

		entry {
			printf("\n==> heater_idle: Waiting for heater to be switched off\n");
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
			
			printf("\n==> ramp_idle: Waiting for system to be unpaused...");
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
			
			printf("\n==> Moving to ramp active state!  \nfinal_target: %f  get_mid: %f in ramp_idle state\n", final_target, get_mid);	
			printf("\n==> final target = %f", get_final_target);
		  
		  /* removed code: getting target value. Instead we send 
		  set_target = 1;
		  pvPut(set_target);
		  printf("\n==> Target: %s", get_ramp_target);
		  
		  /*
		  If Units are Gauss, Global B Target X (value to use) = (final target / 10000) / T/A Sweep
		If Units are Tesla (AMPS?), Global B Target X (value to use) = final target

		  
		  */
		} state set_ramp_values
	}

	state ramp_active {

		entry {
			
			printf("\n==> ramp_active: Ramping to next target: %f", get_mid);
			
			/* Change value of Direction depending on +/-ve of target */
	
			if(get_mid < 0) {
				set_direction = 0; pvPut(set_direction, SYNC);
			}
			else if(get_mid > 0) {
				set_direction = 2; pvPut(set_direction, SYNC);
			}
			
		}
		
		/* when ramp is complete, pause system and move to idle state */
		when(fabs(get_final_target - get_output) < 0.00001) {
			printf("\nAll done! moving to ramp_idle, final_target: %f ", get_final_target);
			set_pause = 1;
			pvPut(set_pause, SYNC);
		} state ramp_complete
		
		
		
		when(fabs(get_output - get_mid) < 0.00001) {
			printf("\n get_output: %f \t ramp_targets[index]: %f \t get_mid: %f", get_output, ramp_targets[temp_target_table_index], get_mid);
			printf("\nfabs: %f",fabs(get_output - get_mid));
			printf("\n==> Hit target! Looking for next target...");			
		} state set_ramp_values
		/*
		when(abs(get_output-get_mid)<0.0001) {
			printf("\nget_output: %f \t\t final_target: %f", get_output, final_target);
			printf("\n==> Reached next target");
			
		} state ramp_active
		*/
		/* If ramp has to move through 0, ramp to zero first */
		/*
		when((get_output < 0 && get_mid > 0) || (get_output > 0 && get_mid < 0)) {
			printf("\n==> Moving to ramp_to_zero state");
			set_target = 0;
			pvPut(set_target);			
			
		} state ramp_to_zero
		*/
		
	
			
				
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


		/* if pause is on, stop ramping */
		when(strcmp("ON", get_pause)==0) {			
			printf("\n==> Ramping paused! pause on\n");
		} state ramp_idle
	} 
	
	state set_ramp_values {
		entry {
			read_ramp_rates();
			printf("\n==> Ramping overall to: %f", get_final_target);
			temp_target_table_index = find_nearest_ramp_rate(get_output);
			if (temp_target_table_index != -1) {
				if (ramp_targets[temp_target_table_index] < get_final_target) {
					set_mid = ramp_targets[temp_target_table_index];					
				}
				else {
					set_mid = get_final_target;
				}
				set_ramp_rate = ramp_rates[temp_target_table_index];
			}
			else {
				set_mid = get_final_target;
				set_ramp_rate = get_ramp_rate;
			}
			pvPut(set_mid, SYNC);
			pvPut(set_ramp_rate, SYNC);
					
			printf("\n==> Setting ramp vals, post set: Target: %f \t Rate: %f", get_mid, get_ramp_rate);
			
		}
		
		
		
		when (delay(2)) {
			printf("\n==> Moving from set_ramp_values to ramp_active");
		} state ramp_active
	}

	state ramp_to_zero {
		entry {
			printf("\n==> Ramping to Zero...");
		}
		
		when (get_output == 0) {
			set_target = 1; /* set target back to MID to continue ramping */
			pvPut(set_target);
		} state ramp_active
	} 
	
	state ramp_complete {
		entry {
			printf("\n==> Finished Ramping! Moving to ramp_idle \n");			
		}
		when (delay(2)) {
			
		} state ramp_idle
	}
}
