program fsm("P, RAMPTABLEDIR")

/*
**************************************************************************
fsm.st

State Machine for the Hifi Cryomagnet PSU

- Reads ramp rate table from external file and stores targets/rates in 
  two unsorted arrays: ramp_targets and their corresponding ramp_rates.
  
- The directory of the ramp file is passed to this script via the RAMPTABLEDIR 
  macro. This is sourced from the st-common.cmd IOC file.
  
- Ramp file reading skips line 0, it is reserved for column headers. 
  Subsequent file_lines_count have pairs of space-seperated values (target, rate)
  
- Ramping is incremental (ramps to interim points along the way) to avoid ramping too 
  quickly if there is a communications error. 
  
- the Direction PV sets the polarity of the ramp. When ramping from +ve to -ve 
  (or vice-versa), we ramp to zero, flip the polarity, and continue the ramp to
  the user's target.
  
*************************************************************************
*/

/* INITIALISER VARIABLES */

double CONSTANT_INIT = 0.028;
double LIMIT_INIT = 5.0;
double GAUSS_TOLERANCE = 5/10000;
double MAX_INIT = 0.4;
double MID_INIT = 0.2;

#include "seqPVmacros.h"
%{#include <stdlib.h>}%
%{#include <stdio.h>}%
%{#include <float.h>}%

/* Turn on run-time debug messages */
option +d;

/* PV definitions */
PV(double, get_mid, "{P}:MID", Monitor);
PV(double, get_max, "{P}:MAX", Monitor);
PV(double, get_limit, "{P}:LIMIT", Monitor);
PV(string, get_pause, "{P}:PAUSE", Monitor);
PV(double, get_output, "{P}:OUTPUT", Monitor);
PV(double, get_constant, "{P}:CONSTANT", Monitor);
PV(double, get_ramp_rate, "{P}:RAMPRATE", Monitor);
PV(string, get_direction, "{P}:DIRECTION", Monitor);
PV(string, get_ramp_target, "{P}:RAMPTARGET", Monitor);
PV(string, get_output_mode, "{P}:OUTPUTMODE", Monitor);
PV(int, read_ramp_file_trigger, "{P}:READFILE", Monitor); 
PV(string, get_heater_status, "{P}:HEATERSTATUS", Monitor);
PV(int, write_ramp_file_trigger, "{P}:WRITEFILE", Monitor); 
PV(double, final_target, "{P}:MIDFINALTARGET", Monitor);

char ramp_table_directory[256]; assign ramp_table_directory to "{P}:RAMPTABLEDIRECTORY";
char temp_log[256];
double ramp_rates[64]; assign ramp_rates to "{P}:RAMPTABLERATES"; monitor ramp_rates;
double ramp_targets[64]; assign ramp_targets to "{P}:RAMPTABLETARGETS"; monitor ramp_targets;
int system_stable; assign system_stable to "{P}:SYSTEMSTABLE";

double set_max; assign set_max to "{P}:MAX:SP";
double set_mid; assign set_mid to "{P}:MID:SP";
int set_pause; assign set_pause to "{P}:PAUSE:SP";
double set_limit; assign set_limit to "{P}:LIMIT:SP";
int set_ramp_target; assign set_ramp_target to "{P}:RAMPTARGET:SP";
int set_direction; assign set_direction to "{P}:DIRECTION:SP";
double set_constant; assign set_constant to "{P}:CONSTANT:SP";
double set_ramp_rate; assign set_ramp_rate to "{P}:RAMPRATE:SP";
int set_output_mode; assign set_output_mode to "{P}:OUTPUTMODE:SP";

char log_message[256];
char set_log_message[256]; assign set_log_message to "{P}:LOGMESSAGE";
int set_heater_status; assign set_heater_status to "{P}:HEATERSTATUS:SP";

/* File reading variables */
char buffer[25];
int file_lines_count = 0;
char *token;
char delim[2] = " ";
double sort_values[64][2];

/* Interim Ramp Rate Check Variables */

int temp_target_table_index = 0;
int largest_target_index;
int smallest_target_index;

int continue_ramp_after_zero_reached;
double final_target_cache;
double interim_ramping_tolerance;

/* direction setters */
int POSITIVE = 2;
int NEGATIVE = 1;
/* Pause setters */
int PAUSED = 1;
int UNPAUSED = 0;
/* ramp targets */
int TARGET_ZERO = 0;
int TARGET_MID = 1;
int TARGET_MAX = 2;
/* Output mode setters */
int TESLA = 1;
int AMPS = 0;

%{
	/* 
		Escaped C Code - this section contains functions called within states.
	*/
	
	static void read_ramp_rates() {	
		/* 
			Reading ramp table values from external .txt file 
			Puts file values into arrays ramp_rates and ramp_targets 		
		*/
		
		/* Empty our arrays for re-writing */
		memset(ramp_targets, -1, sizeof(ramp_rates));
		memset(ramp_rates, -1, sizeof(ramp_rates));
		memset(sort_values, -1, sizeof(sort_values));
		file_lines_count = 0;
			
		FILE *ramp_file;
		ramp_file = fopen(ramp_table_directory, "r");
		
		if (ramp_file != NULL) {
			/* Skip first line */
			fgets(buffer, 30, ramp_file);
			
			while (fgets(buffer, 30, ramp_file) != NULL) {			
				token = strtok(buffer, delim);
				ramp_targets[file_lines_count] = strtod(token, NULL);			
				token = strtok(NULL, delim);
				ramp_rates[file_lines_count] = strtod(token, NULL);
				file_lines_count++;			
			}	
		}	
		else {
			printf("\nFile Read Error");
			exit(-1);
		}
		fclose(ramp_file);	
	}

	static void write_ramp_table_to_file() {	

		/* 
			Writing ramp rate and target values to our .txt file
		*/
				
		FILE *ramp_file;
		ramp_file = fopen(ramp_table_directory, "w");
		int values_count = 0;
		for(int i = 0; i < 64; i++) {
			if (ramp_targets[i] > 0) {
				values_count++;
			}
		}	
		if (ramp_file != NULL) {

			fprintf(ramp_file, "target rate");
		
			for (int i = 0; i < values_count; i++) {
				if ((ramp_rates[i] > 0) && (ramp_targets[i] > 0)) {
					fprintf(ramp_file, "\n%f %f", ramp_targets[i], ramp_rates[i]);
				}			
			}
		}		
		else {
			printf("\nFile Read Error");
			exit(-1);	
		}	
		fclose(ramp_file);
		
		printf("\nFile write successful!");

		read_ramp_rates();	
	}

	static double amp_value(double value) {
		return value / 10000;
	}
	
	static double gauss_value(double value) {
		return value * 10000;
	}
	
	static int find_nearest_ramp_rate(double current_output) {	
		/*  
			:returns: Index value of next available ramp target/ramp rate. 
			
			Return of 100 indicates that we have gone beyond the ranges of the 
			ramp table.
		*/
		int nearest_index = 0;
		largest_target_index = file_lines_count-1;
		smallest_target_index = 0;
		
		for (int index = 0; index < file_lines_count; index++) {
			/* Ramping up? Find next highest value */
			if (fabs(final_target) > fabs(current_output)) {				
				if((fabs(current_output)+GAUSS_TOLERANCE) < amp_value(ramp_targets[index])) {
					nearest_index = index;
					break;
				}			
			}		
			/* Ramping down? Find next lowest Value */
			else {				
				if((fabs(current_output)-GAUSS_TOLERANCE) > amp_value(ramp_targets[index])) {
					nearest_index = index;
				}
			}
		}
		/* If we are outside the ranges of the ramp target table */
		if (((fabs(final_target) > amp_value(ramp_targets[file_lines_count-1])) && (fabs(current_output) >= (amp_value(ramp_targets[file_lines_count-1])))) ||
			((fabs(final_target) < amp_value(ramp_targets[0])) && (fabs(current_output) <= amp_value(ramp_targets[0])))) {
			nearest_index = 100;
		}
		return nearest_index;
	}	
}%

foreign ssId;

ss fsm {

	state initialise {
  
		entry {
			set_output_mode = AMPS; pvPut(set_output_mode);
			strcpy(ramp_table_directory, macValueGet("RAMPTABLEDIR"));
			pvPut(ramp_table_directory);	
			read_ramp_rates(); 
			pvPut(ramp_rates);
			pvPut(ramp_targets);	
			set_ramp_rate = ramp_rates[0]; pvPut(set_ramp_rate);
			strcpy(set_log_message, "==> Initialising Keithley 2700 Values"); pvPut(set_log_message);
			
			if(get_limit != LIMIT_INIT) {
				printf("\n=> Setting limit to 5v");
				set_limit = LIMIT_INIT; pvPut(set_limit);
			}
			if(get_constant != CONSTANT_INIT) {
				printf("\n=> Setting constant to %f", CONSTANT_INIT);
				set_constant = CONSTANT_INIT; pvPut(set_constant);
			}
			if(strcmp(get_ramp_target, "MID")!=0) {
				printf("\n=> Setting ramp target to MID");
				set_ramp_target = TARGET_MID; pvPut(set_ramp_target);
			}
			if(strcmp(get_pause, "OFF")==0) {
				printf("\n=> Setting pause to ON");
				set_pause = PAUSED; pvPut(set_pause);	
			}
		}
		/* Only move to next initiation state when we have confirmed that the values are set. */
		when( (fabs(get_constant-CONSTANT_INIT) < 0.01) &&
			(fabs(get_limit-LIMIT_INIT) < 0.01 ) &&
			((strcmp(get_ramp_target, "MID")==0)) &&
			(strcmp(get_pause, "ON")==0)) {	
		} state initialise_output_mode
		
		/* In the event of a failure to set values */
		when(delay(5)) {
			printf("\n\n==> ERROR: Failed to set values, trying again...");
		}state initialise
		
	}  
	
	state initialise_output_mode {
		
		entry {
			if(strcmp(get_output_mode, "AMPS")==0) {
				printf("\n=> Setting output mode to TESLA");
				set_output_mode = TESLA; pvPut(set_output_mode);
			}
		}
		
		when(strcmp(get_output_mode, "TESLA")==0) {
		} state initialise_max
		
		when( delay(5) ) {
			printf("\n\n==> ERROR: Failed to set output mode, trying again...");
			set_output_mode = 1; pvPut(set_output_mode);
		} state initialise_output_mode
		
	}
	
	state initialise_max {
		
		entry {
			if(get_max != MAX_INIT) {
				set_max = MAX_INIT; pvPut(set_max);
				printf("\n=> Setting max value to %f", MAX_INIT);
			}
		}
		
		when (fabs(get_max-MAX_INIT)<0.01) {
		} state initialise_mid
		
		when( delay(5) ) {
			printf("\n\n==> ERROR: Failed to set max value, trying again...");			
		}state initialise_max
		
	}
	
	state initialise_mid {
		
		entry {
			if(get_mid != MID_INIT) {
				set_mid = MID_INIT; pvPut(set_mid);
				printf("\n=> Setting mid value to %f", MID_INIT);
			}
		}
		
		when (fabs(get_mid-MID_INIT)<0.01) {
			printf("\n==> All system values initialised");			
			strcpy(set_log_message, "==> System Ready"); pvPut(set_log_message);
		} state idle
		
		when( delay(5) ) {
			printf("\n\n==> ERROR: Failed to set mid value, trying again...");					
		} state initialise_mid
		
	}

	state idle {

		entry {			
			read_ramp_rates(); 
			pvPut(ramp_rates, SYNC);
			pvPut(ramp_targets, SYNC);
		}
		
		when(strcmp(get_pause, "OFF")==0) {			
			/* 
				Will this ramp pass through zero? If so, store target in a cache
				variable, set target to 0, and raise a flag to continue ramping after reaching 0.
			*/
			if(((get_output < 0) && (final_target > 0)) ||
			((get_output > 0) && (final_target < 0) )) {
				final_target_cache = final_target;
				final_target = 0;
				continue_ramp_after_zero_reached = 1;				
			}
			else {
				continue_ramp_after_zero_reached = 0;
			}			
		} state ramping_active
		
		/* Listen for read/write file triggers */
		
		when(write_ramp_file_trigger > 0) {
			/* printf("\nMoving to write_file state!"); */
		} state write_ramp_table_file
		
		when(read_ramp_file_trigger > 0) {
			/*printf("\nMoving to read_file state!"); */			
		} state read_ramp_table_file	
	}

	state ramping_active {
		
		entry {
		}	
			
		when(strcmp(get_pause, "ON")==0) {
			snprintf(log_message, sizeof(log_message), "RAMP STATUS: HOLDING ON %s AT %0.3f GAUSS", get_ramp_target, gauss_value(get_output));
			strcpy(set_log_message, log_message); pvPut(set_log_message);
		} state idle
		
		/* When the output is around zero, check if we need to flip polarity and contine ramping */
		when(fabs((get_output) < GAUSS_TOLERANCE) && (continue_ramp_after_zero_reached == 1)) {
		} state flip_polarity
		
		when (delay(1))  {
			
			/* Set best ramp rate and target */
			temp_target_table_index = find_nearest_ramp_rate(get_output);						
			set_mid = amp_value(ramp_targets[temp_target_table_index]);
			
			/* Ramping down? Ramp rate is the ceiling of the ramp table value (i.e. next highest value) */
			if(fabs(final_target) < fabs(get_output)) {
				/* If we're in the ranges of the ramp table */
				if(temp_target_table_index < (file_lines_count-1)) {
					set_ramp_rate = ramp_rates[temp_target_table_index+1];
				}
				else {
					set_ramp_rate = ramp_rates[file_lines_count-1];
				}
			}
			else {
				/* Ramping up? ramp rate is matched to ramp target */
				set_ramp_rate = ramp_rates[temp_target_table_index];
			}
				
			/* If final target is in-between ramp table values, target = final target. */
			if ((set_mid > fabs(final_target)) && (final_target != 0)) {
				set_mid = final_target;
			}	

			/* If we're beyond the ranges of the ramp table, set target to be user's Final target, and 
			   rate to be the currently used rate. */
			if (temp_target_table_index > 99) {
				set_mid = final_target;
				set_ramp_rate = get_ramp_rate;
				/* Ramping down? Rate is the lowest ramp rate value. */
				if (fabs(final_target) < fabs(get_output)) {
					set_ramp_rate = ramp_rates[0];
				}
			}	
	
			/* Tesla/Amp Conversion */
			if(strcmp(get_output_mode, "AMPS")==0) {
				set_mid /= get_constant;
			}
			
			pvPut(set_ramp_rate, SYNC);
			pvPut(set_mid, SYNC);
			snprintf(log_message, sizeof(log_message), "RAMP STATUS: RAMPING FROM %0.3f TO %0.3f AT %0.3f A/SEC", gauss_value(get_output), gauss_value(set_mid), get_ramp_rate);
			strcpy(set_log_message, log_message); pvPut(set_log_message);
			
		} state ramping_active
	}
	
	state write_ramp_table_file {
		/* 
			Writes new values to our ramp table .txt file.
		*/
		entry {
			write_ramp_table_to_file();
			write_ramp_file_trigger = 0; pvPut(write_ramp_file_trigger, SYNC);
		}
		when (delay(1)) {			
		} state idle		
	}
	
	state read_ramp_table_file {
		/* 
			Reads new values from our ramp table .txt file.
		*/
		entry {
			read_ramp_rates();
			pvPut(ramp_rates, SYNC);
			pvPut(ramp_targets, SYNC);
			read_ramp_file_trigger = 0; pvPut(read_ramp_file_trigger, SYNC);
		}
		when (delay(1)) {
		} state idle
	}

	state flip_polarity {
		entry {
			continue_ramp_after_zero_reached = 0;
			final_target = final_target_cache;
			
			if(final_target < 0) {
				set_direction = NEGATIVE; pvPut(set_direction);
			}
			else {
				set_direction = POSITIVE; pvPut(set_direction);
			}
		}
		/* Confirm that direction has been set */
		when (((strcmp(get_direction, "+")==0) && (set_direction == POSITIVE)) ||
			 ((strcmp(get_direction, "-")==0) && (set_direction == NEGATIVE))) {
			set_ramp_target = TARGET_MID; pvPut(set_ramp_target);
		} state ramping_active
	}	 
	
}
