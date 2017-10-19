program fsm("P, RAMPTABLEDIR")

/*
**************************************************************************
fsm.st

State Machine for the Hifi Cryomagnet PSU

- Reads ramp rate table from external file and stores targets/rates in 
  two unsorted arrays: ramp_table_targets and their corresponding ramp_table_rates.
  
- Ramp file reading skips line 0, it is reserved for column headers. 
  Subsequent lines have pairs
  of space-seperated values.
  
- Ramping is incremental (ramps to interim points 
  along the way) to avoid ramping too quickly if there 
  is a comms error. 
  
- The directory of the ramp file is passed to this script via RAMPTABLEDIR 
  macro. This is sourced from the st-common.cmd IOC file.

  
*************************************************************************
*/

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

PV(int, write_ramp_file_trigger, "{P}:WRITEFILE", Monitor); 
/*
PV(double, ramp_table_rates[64], "{P}:RAMPTABLERATES", Monitor);
PV(double, ramp_table_targets[64],"{P}:RAMPTABLETARGETS", Monitor);
*/

PV(double, set_zero, "{P}:ZERO", Monitor);
PV(double, set_final_target, "{P}:MIDFINALTARGET", Monitor);


double ramp_table_rates[64]; assign ramp_table_rates to "{P}:RAMPTABLERATES"; monitor ramp_table_rates;
double ramp_table_targets[64]; assign ramp_table_targets to "{P}:RAMPTABLETARGETS"; monitor ramp_table_targets;

int system_stable; assign system_stable to "{P}:SYSTEMSTABLE";
char ramp_table_directory[256]; assign ramp_table_directory to "{P}:RAMPTABLEDIRECTORY";


double set_max; assign set_max to "{P}:MAX:SP";
double set_mid; assign set_mid to "{P}:MID:SP";
int set_pause; assign set_pause to "{P}:PAUSE:SP";
double set_limit; assign set_limit to "{P}:LIMIT:SP";
int set_target; assign set_target to "{P}:RAMPTARGET:SP";
int set_direction; assign set_direction to "{P}:DIRECTION:SP";
double set_constant; assign set_constant to "{P}:CONSTANT:SP";
double set_ramp_rate; assign set_ramp_rate to "{P}:RAMPRATE:SP";
int set_output_mode; assign set_output_mode to "{P}:OUTPUTMODE:SP";
char set_error_message[256]; assign set_error_message to "{P}:ERRORMESSAGE";
char set_log_message[256]; assign set_log_message to "{P}:LOGMESSAGE";

/* File reading variables */
char buffer[25];
int line = 0;
char *token;
char delim[2] = " ";

/* Ramp Rate Check Variables */
double difference_ramp_up;
double difference_ramp_down;
double check_difference;
int temp_target_table_index = 0;

double final_target;
int largest_target_index;
int smallest_target_index;

float abs_target;
int j;
int i;


%{
	
static void read_ramp_table_rates() {	


	/* Reading ramp table values from external txt file */
	/* Puts file values into ramp_table_rates and ramp_table_targets */
	
	/* empty our arrays to start re-write */
	memset(ramp_table_targets, -1, sizeof(ramp_table_rates));
	memset(ramp_table_rates, -1, sizeof(ramp_table_rates));
	line = 0;
	
	FILE *ramp_file;
	ramp_file = fopen(ramp_table_directory, "r");
	
	if (ramp_file != NULL) {
		/* Skip first line */
		fgets(buffer, 25, ramp_file);
		
		while (fgets(buffer, 25, ramp_file) != NULL) {			
			token = strtok(buffer, delim);
			ramp_table_targets[line] = strtod(token, NULL);			
			token = strtok(NULL, delim);
			ramp_table_rates[line] = strtod(token, NULL);			
			line++;			
		}	
	}	
	else {
		printf("\nFile Read Error");
		exit(-1);
	}
	fclose(ramp_file);	
	/* Print ramp table values */
	/*
	for (int i = 0; i < line; i++) {
		printf("\nTarget:\t %f \t Rate:\t %f", ramp_table_targets[i], ramp_table_rates[i]);
	}
	*/
		
}

static void write_ramp_table_to_file() {
	
	printf("\n==>Writing file...");
	
	FILE *ramp_file;
	ramp_file = fopen(ramp_table_directory, "w");
	
	for(i = 0; i < 64; i++) {
		if (ramp_table_targets[i] > 0) {
			j++;
		}
	}
	
	if (ramp_file != NULL) {
		/* Skip first line 
		char headers[25] = "targets rates";
		fprintf(ramp_file, "%s", headers);
		*/
		fprintf(ramp_file, "target rate");
	
		for (int i = 0; i < j; i++) {
			if ((ramp_table_rates[i] > 0) && (ramp_table_targets[i] > 0)) {
				fprintf(ramp_file, "\n%f %f", ramp_table_targets[i], ramp_table_rates[i]);
				printf("\nWriting line: %f %f", ramp_table_targets[i], ramp_table_rates[i]);
			}			
		}
	}
		
	else {
		printf("\nFile Read Error");
		exit(-1);	
	}
	
	fclose(ramp_file);
	
	printf("\n==>File write successful!");
	
}

static int find_nearest_ramp_rate(double current_output) {
	
	/*  :returns: Index value of next available ramp target/ramp rate. */

	int nearest_index = 0;
	difference_ramp_down = DBL_MAX;
	difference_ramp_up = DBL_MAX;	
	largest_target_index = 0;
	smallest_target_index = 0;
		
	for (int x = 0; x < line; x++) {
		/* Find largest target in ramp table */
		if (ramp_table_targets[x] > ramp_table_targets[largest_target_index]) {
			largest_target_index = x;
		}
		/* Find smallest target in ramp table */
		if (ramp_table_targets[x] < ramp_table_targets[smallest_target_index]) {
			smallest_target_index = x;
		}
		
		/* Ramping up? Find nearest higher value */
		if (fabs(get_final_target) > current_output) {			
			if (ramp_table_targets[x] > current_output) {
				check_difference = ramp_table_targets[x] - fabs(current_output);
				if (check_difference < difference_ramp_up) {
					difference_ramp_up = check_difference;
					nearest_index = x;
				}
			}
		}
		/* Ramping down? Find nearest lower value */
		else {
			if (ramp_table_targets[x] < fabs(current_output)) {
				check_difference = fabs(current_output) - ramp_table_targets[x];
				if (check_difference < difference_ramp_down) {
					difference_ramp_down = check_difference;
					nearest_index = x;
				}
			}
		}
	}
	/* If we have reached the last table value, and our final target is beyond that - */
	if (((get_final_target > ramp_table_targets[largest_target_index]) && (current_output >= ramp_table_targets[largest_target_index])) ||
     	((get_final_target < ramp_table_targets[smallest_target_index]) && (current_output <= ramp_table_targets[smallest_target_index]))) {
		printf("\n==> We're heading beyond the ranges of the ramp table!");
		nearest_index = 100;
	}
	return nearest_index;
}

}%

foreign ssId;

ss fsm {

	state init {
  
		entry {
			/* Set initial PV variables */
			
			/* Get ramp table file directory and assign to PV for OPI access*/
			
			
			strcpy(ramp_table_directory, macValueGet("RAMPTABLEDIR"));
			pvPut(ramp_table_directory, SYNC);
			
			printf("\n==> Ramp table location: ");
			printf(ramp_table_directory);
			printf("\n==> init: Setting initial variable values\n");	
			
			set_limit = 5.0; pvPut(set_limit, SYNC);
			set_constant = 0.00029; pvPut(set_constant, SYNC);
			set_zero = 0.000; pvPut(set_zero, SYNC);
			set_ramp_rate = 0.2; pvPut(set_ramp_rate, SYNC);
			set_max = 34.92; pvPut(set_max, SYNC);
			set_output_mode = 0; pvPut(set_output_mode, SYNC);
			set_pause = 1; pvPut(set_pause, SYNC);		
			system_stable = 1; pvPut(system_stable, SYNC);
			strcpy(set_error_message, " ==> I'm an error!"); pvPut(set_error_message, SYNC);
			strcpy(set_log_message, " ==> I'm the initial log message!"); pvPut(set_log_message, SYNC);
			write_ramp_file_trigger = -5; pvPut(write_ramp_file_trigger, SYNC);
			/*printf("\n==> ramp_trigger: %d", get_ramp_file_trigger); */
		
			read_ramp_table_rates(); 
			pvPut(ramp_table_rates, SYNC);
			pvPut(ramp_table_targets, SYNC);
			
			
			
			/* Get the Current Direction (GS), read and parse the response, noting it in a global, also note the Direction in a local variable*/	    
		}
		
		when(delay(1)) {	

		} state heater_idle
	}  

	state heater_idle {
		
		entry {			
			printf("\n==> heater_idle: Waiting for heater to be switched off\n");
		}
		
		when(strcmp("OFF", get_heater_status)==0) {
		/*	printf("\nheater_idle ==> ramp_idle\n");  */  
		} state ramp_idle	
	}

	state ramp_idle {

		entry {			
			printf("\n==> ramp_idle: Waiting for system to be unpaused...");
		}
		

		
		when(write_ramp_file_trigger > 0) {
			printf("\nMoving to write_file state!");
		} state write_ramp_table_file
		
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
		
		when(strcmp("ON", get_heater_status)==0) {
			printf("\n==> Heater turned on, moving to heater_idle");
		} state heater_idle

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
			
			read_ramp_table_rates();
			pvPut(ramp_table_rates, SYNC);
			pvPut(ramp_table_targets, SYNC);
			system_stable = 0; pvPut(system_stable, SYNC);
			
			printf("\n==> ramp_active: ramping to next target: %f", get_mid);			
				
		}
		
		/* When the final target is reached, pause system and move to idle state */
		when(fabs(get_final_target - get_output) < 0.00001) {
			printf("\nramp_active ==> ramp_complete");
			set_pause = 1; pvPut(set_pause, SYNC);			
		} state ramp_complete
		
		/* When the interim target is reached, search for next target */
		when(fabs(get_output - get_mid) < 0.00001) {
			printf("\nramp_active ==> set_ramp_values");			
		} state set_ramp_values
		
		/* If ramp has to move through 0, ramp to zero first */
		
		/* Do we have to do this?
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

		/* If pause is on, stop ramping */
		when(strcmp("ON", get_pause)==0) {			
			printf("\n==> Ramping paused! pause on\n");
		} state ramp_idle
		/* If heater is on, stop ramping */
		when(strcmp("ON", get_heater_status)==0) {
			printf("\n==> Ramping aborted, heater turned on");
			set_pause = 1; pvPut(set_pause, SYNC);
		} state heater_idle
	} 
	
	state set_ramp_values {
		entry {
			printf("\n\n==> Attemping to read ramp values...");
			read_ramp_table_rates();
			temp_target_table_index = find_nearest_ramp_rate(get_output);
		
			if (get_output <= 0) {
				printf("\n==> Setting direction to NEGATIVE");
				set_direction = 0;
			}
			else { 
				printf("\n==> Setting direction to POSITIVE");
				set_direction = 1;
			}
			pvPut(set_direction, SYNC);
			printf("\nDirection:");
			printf(get_direction);
			
			
			
			/* Values are found based on abs value of target (check this) */
			
			/* If we're ramping up */
			if (get_final_target > get_output) {
				/* If target is smaller than final target, set mid/rate to next value in table */
				if (ramp_table_targets[temp_target_table_index] <= fabs(get_final_target)) {
					set_mid = ramp_table_targets[temp_target_table_index];						
					set_ramp_rate = ramp_table_rates[temp_target_table_index];
				}
				/* If target is larger than the final target, set mid to be final_target */
				else if (ramp_table_targets[temp_target_table_index] > fabs(get_final_target)) {
					set_mid = get_final_target;
					set_ramp_rate = get_ramp_rate;
				}			
			}
			else {
			/* If ramping down */	
				if (ramp_table_targets[temp_target_table_index] >= fabs(get_final_target)) {
					set_mid = ramp_table_targets[temp_target_table_index];
					set_ramp_rate = ramp_table_rates[temp_target_table_index];	
				}
				/* If target is larger than the final target, set mid to be final_target */
				else if (ramp_table_targets[temp_target_table_index] < fabs(get_final_target)) {
					set_mid = get_final_target;
					set_ramp_rate = get_ramp_rate;
				}
			}				
			
			/* If we're beyond the ranges of the ramp table, set target to be user's Final target, and 
			   rate to be the currently used rate. */
			if (temp_target_table_index > 99) {
				set_mid = get_final_target;
				set_ramp_rate = get_ramp_rate;
			}

			/* If direction is negative, make target negative */
			printf("\nCurrent direction:");
			printf(get_direction);
			if (strcmp("-", get_direction) == 0) {
				printf("\n==> Neg ramping, *-1 ");
				set_mid *= -1.0;
			}
			/* Finally, set these PV values */
			pvPut(set_ramp_rate, SYNC);
			pvPut(set_mid, SYNC);
			printf("\n==> Set values: Current Target: %f \t Final Target: %f \t Rate: %f", get_mid, get_final_target, get_ramp_rate);			
		}
		
		when (delay(2)) {
	
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
			printf("\n\n==> Ramp complete! Moving to ramp_idle");			
		}
		when (delay(2)) {
			system_stable = 1; pvPut(system_stable, SYNC);
		} state ramp_idle
	}
	
	state write_ramp_table_file {
		entry {
			printf("\n==>Writing ramp table file to directory...");

			write_ramp_table_to_file();
			write_ramp_file_trigger = 0; pvPut(write_ramp_file_trigger, SYNC);
		}
		when (delay(1)) {
			
		} state ramp_idle 
		
	}
}

