program fsm("P, RAMPTABLEDIR")

/*
**************************************************************************
fsm.st

State Machine for the Hifi Cryomagnet PSU

- Reads ramp rate table from external file and stores targets/rates in 
  two unsorted arrays: ramp_table_targets and their corresponding ramp_table_rates.
  
- Ramp file reading skips file_lines 0, it is reserved for column headers. 
  Subsequent file_liness have pairs
  of space-seperated values.
  
- Ramping is incremental (ramps to interim points 
  along the way) to avoid ramping too quickly if there 
  is a comms error. 
  
- The directory of the ramp file is passed to this script via the RAMPTABLEDIR 
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
PV(double, set_zero, "{P}:ZERO", Monitor);
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
double ramp_table_rates[64]; assign ramp_table_rates to "{P}:RAMPTABLERATES"; monitor ramp_table_rates;
double ramp_table_targets[64]; assign ramp_table_targets to "{P}:RAMPTABLETARGETS"; monitor ramp_table_targets;
int system_stable; assign system_stable to "{P}:SYSTEMSTABLE";

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
int set_heater_status; assign set_heater_status to "{P}:HEATERSTATUS:SP";

/* File reading variables */
char buffer[25];
int file_lines = 0;
char *token;
char delim[2] = " ";
double sort_values[64][2];

/* Interim Ramp Rate Check Variables */
double difference_ramp_up;
double difference_ramp_down;
double check_difference;
int temp_target_table_index = 0;

int largest_target_index;
int smallest_target_index;

float abs_target;

int ramp_zero_trigger;
double ramp_zero_cache;

%{
	/* 
		Escaped C Code - this section contains functions called within states.
	*/
	
	static void sort_column(double arr[][2], int file_lines) {
		/* 
			Function to sort ramp file values into order by target value 
			This is so we can more easily find the next appropriate ramp target.
		*/
		int i,j,k;
		double key;
		for(i=0;i<file_lines;i++)
		{
			for(j=1;j<file_lines;j++)
			{
				key=arr[j][i];
				k=j-1;
				while(k>=0 && arr[k][i]>key)
				{
					arr[k+1][i]=arr[k][i];
					k--;
				}
				arr[k+1][i]=key;
			}
		}
	}
		
	static void read_ramp_table_rates() {	
		/* 
			Reading ramp table values from external .txt file 
			Puts file values into ramp_table_rates and ramp_table_targets 		
		*/
		/* Empty our arrays for re-writing */
		memset(ramp_table_targets, -1, sizeof(ramp_table_rates));
		memset(ramp_table_rates, -1, sizeof(ramp_table_rates));
		memset(sort_values, -1, sizeof(sort_values));
		file_lines = 0;
			
		FILE *ramp_file;
		ramp_file = fopen(ramp_table_directory, "r");
		
		if (ramp_file != NULL) {
			/* Skip first line */
			fgets(buffer, 30, ramp_file);
			
			while (fgets(buffer, 30, ramp_file) != NULL) {			
				token = strtok(buffer, delim);
				sort_values[file_lines][0] = strtod(token, NULL);			
				token = strtok(NULL, delim);
				sort_values[file_lines][1] = strtod(token, NULL);
				file_lines++;			
			}	
		}	
		else {
			printf("\nFile Read Error");
			exit(-1);
		}
		fclose(ramp_file);	
		
		/* Sort ramp file values into ascending order of target, and put into our PV values*/
		for (int i = 0; i < file_lines;i++) {
			sort_column(sort_values, file_lines);
			ramp_table_targets[i] = sort_values[i][0];
			ramp_table_rates[i] = sort_values[i][1];
		}	
	}

	static void write_ramp_table_to_file() {	
		/* 
			Writing ramp rate and target values to our .txt file
		*/
		
		printf("\n==> Writing file...");
		
		FILE *ramp_file;
		ramp_file = fopen(ramp_table_directory, "w");
		int j = 0;
		for(int i = 0; i < 64; i++) {
			if (ramp_table_targets[i] > 0) {
				j++;
			}
		}	
		
		if (ramp_file != NULL) {

			fprintf(ramp_file, "target rate");
		
			for (int i = 0; i < j; i++) {
				if ((ramp_table_rates[i] > 0) && (ramp_table_targets[i] > 0)) {
					fprintf(ramp_file, "\n%f %f", ramp_table_targets[i], ramp_table_rates[i]);
					printf("\nWriting file_lines: %f %f", ramp_table_targets[i], ramp_table_rates[i]);
				}			
			}
		}		
		else {
			printf("\nFile Read Error");
			exit(-1);	
		}	
		fclose(ramp_file);
		
		printf("\n==> File write successful!");
		/* Trigger a re-read to get values in sorted order */
		read_ramp_table_rates();	
	}

	static int find_nearest_ramp_rate(double current_output) {	
		/*  
			:returns: Index value of next available ramp target/ramp rate. 
			
			Return of 100 indicates that we have gone beyond the ranges of the 
			ramp table.
		*/

		int nearest_index = 0;
		difference_ramp_down = DBL_MAX;
		difference_ramp_up = DBL_MAX;	
		largest_target_index = file_lines-1;
		smallest_target_index = 0;
		
		for (int x = 0; x < file_lines; x++) {
			/* Ramping up? Find next highest value */
			if (fabs(final_target) > fabs(current_output)) {
				if(fabs(current_output) < (ramp_table_targets[x]/10000)) {
					nearest_index = x;
					break;
				}			
			}		
			/* Ramping down? Find next lowest Value */
			if (fabs(final_target) < fabs(current_output)) {
				if(fabs(current_output) > (ramp_table_targets[x]/10000)) {
					nearest_index = x;
				}
			}
		}
		/* If we have reached the last table value, and our final target is beyond that - */
		if (((fabs(final_target) > (ramp_table_targets[file_lines-1]/10000)) && ( fabs(current_output) >= (ramp_table_targets[file_lines-1]/10000)) ) ||
			( ( fabs(final_target) < (ramp_table_targets[0]/10000)) && (fabs(current_output) <= (ramp_table_targets[0]/10000))) ){
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
			printf("\n==> FSM initialisation: setting PV values\n");
			strcpy(ramp_table_directory, macValueGet("RAMPTABLEDIR"));
			pvPut(ramp_table_directory, SYNC);		
			set_heater_status = 0; pvPut(set_heater_status, SYNC);
			set_limit = 5.0; pvPut(set_limit, SYNC);
			set_constant = 0.00029; pvPut(set_constant, SYNC);
			set_zero = 0.000; pvPut(set_zero, SYNC);
			/* Set direction based on current +/- output */
			if (get_output < 0) {
				set_direction = 1;
			} else {
				set_direction = 2;
			}
			pvPut(set_direction, SYNC);
			
			set_max = 34.92; pvPut(set_max, SYNC);
			set_output_mode = 1; pvPut(set_output_mode, SYNC);
			set_pause = 1; pvPut(set_pause, SYNC);		
			system_stable = 1; pvPut(system_stable, SYNC);
			strcpy(set_error_message, " ==> I'm an error!"); pvPut(set_error_message, SYNC);
			strcpy(set_log_message, " ==> I'm the initial log message!"); pvPut(set_log_message, SYNC);
			write_ramp_file_trigger = 0; pvPut(write_ramp_file_trigger, SYNC);
			read_ramp_file_trigger = 0; pvPut(write_ramp_file_trigger, SYNC);					
			read_ramp_table_rates(); 
			pvPut(ramp_table_rates, SYNC);
			pvPut(ramp_table_targets, SYNC);
			set_ramp_rate = ramp_table_rates[0]; pvPut(set_ramp_rate, SYNC);
			printf("\n==> Initial variable values set\n");	
			ramp_zero_trigger = 0;
			
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
		
		} state ramp_idle	
		
		when(write_ramp_file_trigger > 0) {
			printf("\nMoving to write_file state!");
		} state write_ramp_table_file
		
		when(read_ramp_file_trigger > 0) {
			printf("\nMoving to read_file state!");
		} state read_ramp_table_file
	}

	state ramp_idle {

		entry {			
			printf("\n==> ramp_idle: Waiting for system to be unpaused...");
		}
		
		when(write_ramp_file_trigger > 0) {
			printf("\nMoving to write_file state!");
		} state write_ramp_table_file
		
		when(read_ramp_file_trigger > 0) {
			printf("\nMoving to read_file state!");
		} state read_ramp_table_file
		
		when(strcmp("ON", get_pause)==0) {
			/* Moving to Ramp Idle State */
		} state ramp_idle
		
		when(strcmp("ON", get_heater_status)==0) {
			printf("\n==> Heater turned on, moving to heater_idle");
		} state heater_idle

		/* If system is unpaused, move to ramping state */
		when(strcmp("OFF", get_pause)==0) {		
			/* If ramp will pass from + to - or - to +, flag our 'ramp to zero' trigger.
				Target becomes 0 and user's target is stored in a cache variable to be used 
				after the ramp-tp-zero is complete. */
			if (((get_output < 0) && (final_target > 0)) || ((get_output > 0) && (final_target < 0)))  {
				ramp_zero_trigger = 1;
				ramp_zero_cache = final_target;
				final_target = 0; pvPut(final_target, SYNC);
			}
			else {
				ramp_zero_trigger = 0;
			}
		} state set_ramp_values
	}

	state ramp_active {
		
		entry {
			
			read_ramp_table_rates();
			pvPut(ramp_table_rates, SYNC);
			pvPut(ramp_table_targets, SYNC);			
			system_stable = 0; pvPut(system_stable, SYNC);	
			printf("\n==> ramp_active: ramping to next target: %f", (get_mid/10000));	
		}
		
		/* When the final target is reached, pause system and move to idle state */
		when((fabs(final_target - (get_output*10000)) < 0.00001) && (ramp_zero_trigger == 0)) {
			printf("\nramp_zero_trigger: %i", ramp_zero_trigger);
			printf("\nramp_active ==> ramp_complete");
			set_pause = 1; pvPut(set_pause, SYNC);			
		} state ramp_complete
		
		/* When we've finished ramping to zero */
		when((fabs(final_target - (get_output*10000)) < 0.00001) && (ramp_zero_trigger == 1)) {
			printf("\nRamp to Zero complete, continuing to next target");
			/* Continue to previous user-set target */
			final_target = ramp_zero_cache;
			ramp_zero_trigger = 0;
		} state set_ramp_values
		
		/* When the interim target is reached, search for next target */
		when(fabs(get_output - get_mid) < 0.00001) {
			/*printf("\nramp_active ==> set_ramp_values");	*/		
		} state set_ramp_values

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
			read_ramp_table_rates();
			temp_target_table_index = find_nearest_ramp_rate(get_output);
			
			/* Set Direction based on current output and our target */
			if ((get_output >= 0) && (final_target >= 0)) {	
				set_direction = 2;
			}
			else if ((get_output <= 0) && (final_target < 0)) {
				set_direction = 1;
			}					
			
			set_mid = (ramp_table_targets[temp_target_table_index]/10000);						
			set_ramp_rate = ramp_table_rates[temp_target_table_index];
			
			/* If target is in-between ramp table values, target = final target. */
			if ((set_mid > fabs(final_target/10000)) && (final_target != 0)) {
				set_mid = fabs(final_target/10000);
			}	
			
			/* If we're beyond the ranges of the ramp table, set target to be user's Final target, and 
			   rate to be the current used rate. */
			if (temp_target_table_index > 99) {
				set_mid = (final_target/10000);
				set_ramp_rate = get_ramp_rate;
			}
			
			/* Flip values depending on what our polarity is */
			if (set_direction == 1) {
				set_mid *= -1.0;				
			}
			if (set_direction == 2) {
				set_mid = fabs(set_mid);
			}
			
			/* Set all these values */
			pvPut(set_ramp_rate, SYNC);
			pvPut(set_mid, SYNC);	
			pvPut(set_direction, SYNC);		
		}
		
		when (delay(1)) {
			printf("\n==> Set values: Current Target: %f \t Final Target: %f \t Rate: %f", get_mid*10000, final_target, get_ramp_rate);
		} state ramp_active
	}
	
	state ramp_complete {
		entry {
			printf("\n==> Ramp complete! Moving to ramp_idle");			
		}
		when (delay(2)) {
			system_stable = 1; pvPut(system_stable, SYNC);
		} state ramp_idle
	}
	
	state write_ramp_table_file {
		entry {
			printf("\n==> Writing ramp table file to directory...");
			write_ramp_table_to_file();
			write_ramp_file_trigger = 0; pvPut(write_ramp_file_trigger, SYNC);
		}
		when (delay(1)) {
			
		} state heater_idle		
	}
	
	state read_ramp_table_file {
		entry {
			printf("\n==> Reading ramp table file and setting PVs...");
			read_ramp_table_rates();
			pvPut(ramp_table_rates, SYNC);
			pvPut(ramp_table_targets, SYNC);
			read_ramp_file_trigger = 0; pvPut(read_ramp_file_trigger, SYNC);
		}
		when (delay(1)) {
			
		} state heater_idle		
	}
}

