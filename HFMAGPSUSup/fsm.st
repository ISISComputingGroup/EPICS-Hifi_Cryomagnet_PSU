program fsm("P")

#include "seqPVmacros.h"
%{#include <stdlib.h>}%
%{#include <stdio.h>}%
%{#include <float.h>}%


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
double difference_ramp_up;
double difference_ramp_down;
double check_difference;

double final_target;
int largest_target_index;
int smallest_target_index;

double ramp_rates[64];
double ramp_targets[64];



float abs_target;

/* Reading ramp table values from external txt file */
%{
	
static int read_ramp_rates() {	

	/* Ramp table values are read from the text file and stored in two unsorted arrays: 
		ramp_targets and their corresponding ramp_rates.
		
		(this would probably be less convoluted if it were a sorted hash map)
	*/
	FILE *ramp_file;
	ramp_file = fopen("C:\\Instrument\\Settings\\config\\common\\ramps\\cryomag_ramp_table.txt", "r");
	
	if (ramp_file != NULL) {
		/* skip first line */
		fgets(buffer, 25, ramp_file);
		
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
	/* Print ramp rate table values 
	for (int i = 0; i < line; i++) {
		printf("\nTarget:\t %f \t Rate:\t %f", ramp_targets[i], ramp_rates[i]);
	}
	*/	
}

static int find_nearest_ramp_rate(double current_output) {
	/* Are we ramping up or down? */
	/* ramping up */

	difference_ramp_down = DBL_MAX;
	difference_ramp_up = DBL_MAX;
	int nearest_index = 0;
	largest_target_index = 0;
	smallest_target_index = 0;
	for (int x = 0; x < line; x++) {
		/* find largest value in array */
		if (ramp_targets[x] > ramp_targets[largest_target_index]) {
			largest_target_index = x;
		}
		/* find smallest value */
		if (ramp_targets[x] < ramp_targets[smallest_target_index]) {
			smallest_target_index = x;
		}
		
		/* ramping up? Find nearest higher value */
		if (get_final_target > current_output) {
			
			if (ramp_targets[x] > current_output) {
				check_difference = ramp_targets[x] - current_output;
				if (check_difference < difference_ramp_up) {
					difference_ramp_up = check_difference;
					printf("\ndifference_ramp_up: %f new target: %f", difference_ramp_up, ramp_targets[x]);					
					nearest_index = x;
				}
			}
		}
		/* ramping down? Find nearest lower value */
		else {
			if (ramp_targets[x] < current_output) {
				check_difference = current_output - ramp_targets[x];
				if (check_difference < difference_ramp_down) {
					difference_ramp_down = check_difference;
					printf("\ndifference_ramp_down: %f new target: %f", difference_ramp_down, ramp_targets[x]);
					nearest_index = x;
				}
			}
		}
	}
	/* If we have reached the last table value, and our final target is beyond that - */
	if ((get_final_target > ramp_targets[largest_target_index]) && (current_output >= ramp_targets[largest_target_index])) {
		printf("\n==> We're heading beyond the ranges of the ramp table!");
		nearest_index = 100;
	}
	if ((get_final_target < ramp_targets[smallest_target_index]) && (current_output <= ramp_targets[smallest_target_index])) {
		printf("\n==> Heading under the ramp table!");
		nearest_index = 100;
	}
	printf("\n");		
	printf("\n==> Current output: %f \t index: %d", current_output, nearest_index);
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
			printf("\nheater_idle ==> ramp_idle\n");    
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
			
			printf("\nramp_idle ==> set_ramp_values");	
			/* printf("\n==> final target = %f", get_final_target); */
		  
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
			printf("\nramp_active ==> ramp_complete");
			set_pause = 1;
			pvPut(set_pause, SYNC);
		} state ramp_complete
		
		
		
		when(fabs(get_output - get_mid) < 0.00001) {
			printf("\n get_output: %f \t ramp_targets[index]: %f \t get_mid: %f", get_output, ramp_targets[temp_target_table_index], get_mid);
			printf("\nramp_active ==> set_ramp_values");			
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
			printf("\n==> Attemping to read ramp values...");
			read_ramp_rates();
			temp_target_table_index = find_nearest_ramp_rate(get_output);
			
			
			/* If we're ramping up */
			if (get_final_target > get_output) {
				/* if target is smaller than final target, set mid/rate to next value in table */
				if (ramp_targets[temp_target_table_index] <= get_final_target) {
					printf("\n==> Setting target to next table value");
					set_mid = ramp_targets[temp_target_table_index];
					pvPut(set_mid, SYNC);
					set_ramp_rate = ramp_rates[temp_target_table_index];	
					pvPut(set_ramp_rate, SYNC);			
					printf("\nRamp up: Set mid to: %f \t Mid actual value: %f", set_mid, get_mid);				
				}
				/* if target is larger than the final target, set mid to be final_target */
				else if (ramp_targets[temp_target_table_index] > get_final_target) {
					printf("\n==> Setting target to FINAL TARGET");
					set_mid = get_final_target;
					pvPut(set_mid, SYNC);
					set_ramp_rate = get_ramp_rate;
					pvPut(set_ramp_rate, SYNC);				
				}			
				else {
					printf("\nNone of these things fired!");
				}	
			}
			else {
			/* if ramping down */	
				if (ramp_targets[temp_target_table_index] >= get_final_target) {
					printf("\n==> Setting target to lower table value");
					set_mid = ramp_targets[temp_target_table_index];
					pvPut(set_mid, SYNC);
					set_ramp_rate = ramp_rates[temp_target_table_index];	
					pvPut(set_ramp_rate, SYNC);			
					printf("\nRamp down: Set mid to: %f \t Mid actual value: %f", set_mid, get_mid);				
				}
				/* if target is larger than the final target, set mid to be final_target */
				else if (ramp_targets[temp_target_table_index] < get_final_target) {
					printf("\n==> Setting target to FINAL TARGET - lower boundary");
					set_mid = get_final_target;
					pvPut(set_mid, SYNC);
					set_ramp_rate = get_ramp_rate;
					pvPut(set_ramp_rate, SYNC);				
				}			
			
			}
			
			if (temp_target_table_index > 99) {
				printf("nearest_index = 100");
				set_mid = get_final_target;
				pvPut(set_mid, SYNC);
				set_ramp_rate = get_ramp_rate;
				pvPut(set_ramp_rate, SYNC);
				printf("\nSet mid to: %f \t Mid actual value: %f", set_mid, get_mid);
			}			
			
					
			printf("\n==> Set vals: Current Target: %f \t Final Target: %f Rate: %f", get_mid, get_final_target, get_ramp_rate);
			
		}
		
		
		
		when (delay(2)) {
			printf("\nset_ramp_values ==> ramp_active");
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
			printf("\nramp_complete ==> ramp_idle\n");			
		}
		when (delay(2)) {
			
		} state ramp_idle
	}
}
