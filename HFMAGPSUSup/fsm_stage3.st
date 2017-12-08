program fsm("P, RAMPTABLEDIR")

/* STAGE 2: This FSM can do incremntal ramp rates, and targets when ramping up. No direction work. */




/*
**************************************************************************
fsm.st

State Machine for the Hifi Cryomagnet PSU

- Reads ramp rate table from external file and stores targets/rates in 
  two unsorted arrays: ramp_table_targets and their corresponding ramp_table_rates.
  
- The directory of the ramp file is passed to this script via the RAMPTABLEDIR 
  macro. This is sourced from the st-common.cmd IOC file.
  
- Ramp file reading skips line 0, it is reserved for column headers. 
  Subsequent file_liness have pairs of space-seperated values (target, rate)
  
- Ramping is incremental (ramps to interim points along the way) to avoid ramping too 
  quickly if there is a comms error. 
  
- the Direction PV sets the polarity of the ramp. When ramping from +ve to -ve 
  (or vice-versa), we ramp to zero, flip the polarity, and continue the ramp to
  the user's target.
  
*************************************************************************
*/

/* INITIALISER VARIABLES */

double CONSTANT_INIT = 0.028;
double LIMIT_INIT = 5.0;

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
double ramp_table_rates[64]; assign ramp_table_rates to "{P}:RAMPTABLERATES"; monitor ramp_table_rates;
double ramp_table_targets[64]; assign ramp_table_targets to "{P}:RAMPTABLETARGETS"; monitor ramp_table_targets;
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

char set_log_message[256]; assign set_log_message to "{P}:LOGMESSAGE";
int set_heater_status; assign set_heater_status to "{P}:HEATERSTATUS:SP";

/* File reading variables */
char buffer[25];
int file_lines = 0;
char *token;
char delim[2] = " ";
double sort_values[64][2];

/* Interim Ramp Rate Check Variables */

double check_difference;
int temp_target_table_index = 0;

int largest_target_index;
int smallest_target_index;

float abs_target;

int continue_ramp_after_zero_reached;
double ramp_zero_cache;
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

/* Turn on run-time debug messages */
option +d;

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
		largest_target_index = file_lines-1;
		smallest_target_index = 0;
		
		for (int x = 0; x < file_lines; x++) {
			/* Ramping up? Find next highest value */
			/* 10/10000 is 10 gauss tolerance */
			if (fabs(final_target) > fabs(current_output)) {				
				if(((fabs(current_output)+(10/10000)) < (ramp_table_targets[x]/10000)) {
					nearest_index = x;
					break;
				}			
			}		
			/* Ramping down? Find next lowest Value */
			if (fabs(final_target) < fabs(current_output)) {				
				if((fabs(current_output)-(10/10000)) > (ramp_table_targets[x]/10000)) {
					nearest_index = x;
				}
			}
		}
		/* If we have reached the last table value, and our final target is beyond that - */
		if (((fabs(final_target) > (ramp_table_targets[file_lines-1]/10000)) && ( fabs(current_output) >= (ramp_table_targets[file_lines-1]/10000)) ) ||
			( ( fabs(final_target) < (ramp_table_targets[0]/10000)) && (fabs(current_output) <= (ramp_table_targets[0]/10000))) ){
			/*printf("\n==> We're heading beyond the ranges of the ramp table!");*/
			nearest_index = 100;
		}
		return nearest_index;
	}

	
}%

foreign ssId;

ss fsm {

	state init {
  
		entry {
			printf("\nhello world!");
			set_output_mode = 0; pvPut(set_output_mode);
			printf("\n==> Reading ramp table, setting limit, constant and target\n");
			strcpy(ramp_table_directory, macValueGet("RAMPTABLEDIR"));
			pvPut(ramp_table_directory);	
			read_ramp_table_rates(); 
			pvPut(ramp_table_rates);
			pvPut(ramp_table_targets);	
			set_ramp_rate = ramp_table_rates[0]; pvPut(set_ramp_rate);
			
			if(get_limit != LIMIT_INIT) {
				printf("\nsetting limit to 5v");
				set_limit = LIMIT_INIT; pvPut(set_limit);
			}
			printf("\nget_constant: %f", get_constant);
			if(get_constant != CONSTANT_INIT) {
				printf("\nsetting constant to 0.029");
				set_constant = CONSTANT_INIT; pvPut(set_constant);
			}
			if(strcmp(get_ramp_target, "MID")!=0) {
				printf("\nsetting constant to Mid");
				set_ramp_target = TARGET_MID; pvPut(set_ramp_target);
			}
			if(strcmp(get_pause, "OFF")==0) {
				printf("\nsetting pause to on");
				set_pause = PAUSED; pvPut(set_pause);	
			}
			
			strcpy(set_log_message, " ==> I'm the initial log message!"); pvPut(set_log_message);
			printf("\nsetting log message");
		}
		
		when( fabs(get_constant-CONSTANT_INIT) < 0.01 ){	
			printf("\n==> Constant set, setting outputmode, min, max\n");

		} state init2
		
		when( delay(5) ) {
			printf("\ntrying to set values again...");
			set_constant = CONSTANT_INIT; pvPut(set_constant);
			set_pause = PAUSED; pvPut(set_pause);	
			set_ramp_target = TARGET_MID; pvPut(set_ramp_target);
			set_limit = LIMIT_INIT; pvPut(set_limit);
		}state init
		
	}  
	
	state init2 {
		entry {
			if(strcmp(get_output_mode, "AMPS")==0) {
				printf("\nsetting outputmode to TELSA");
				set_output_mode = 1; pvPut(set_output_mode);
			}
		}
		when(strcmp(get_output_mode, "TESLA")==0) {
			printf("\n==> Output mode set, setting max values");
		} state init3
		
		when( delay(5) ) {
			printf("\ntrying to set output mode again...");
			set_output_mode = 1; pvPut(set_output_mode);
		}state init2
		
	}
	
	state init3 {
		entry {
			if(get_max != 0.4) {
				set_max = 0.4; pvPut(set_max);
				printf("\nsetting max");
			}

		}
		when (fabs(get_max-0.4)<0.01) {
			printf("\n==> max sett, moving to setting mid");
		} state init4
		
		when( delay(5) ) {
			printf("\ntrying to set max again...");
			set_max = 0.4; pvPut(set_max);
			
		}state init3
		
	}
	
	state init4 {
		entry {
			if(get_mid != 0.2) {
				set_mid = 0.2; pvPut(set_mid);
				printf("\nsetting mid");
			}
		}
		
		when (fabs(get_mid-0.2)<0.01) {
			printf("\n==> mid set, moving to setting mid");
		} state idle
		
		when( delay(5) ) {
			printf("\ntrying to set mid again...");
			
			set_mid = 0.2; pvPut(set_mid);
		}state init4
	}

	state idle {


		entry {			
			printf("\n==> idle: Waiting for system to be unpaused...");
			read_ramp_table_rates(); 
			pvPut(ramp_table_rates, SYNC);
			pvPut(ramp_table_targets, SYNC);
			
		}
		
		when(strcmp(get_pause, "OFF")==0) {
			printf("\nMoving to ramping state");
			
		} state ramping_active
		
		when(write_ramp_file_trigger > 0) {
			printf("\nMoving to write_file state!");
		} state write_ramp_table_file
		
		when(read_ramp_file_trigger > 0) {
			printf("\nMoving to read_file state!");
		} state read_ramp_table_file

			
	}

	state ramping_active {
		
		entry {
			
		}	
			/*strcpy(set_log_message, "RAMP STATUS: RAMPING FROM %f TO %f AT %f A/SEC", get_output*10000, get_mid, get_rate); pvPut(set_log_message, SYNC);*/
		when(strcmp(get_pause, "ON")==0) {
			printf("\npaused!");
		} state idle
		
		when (delay(1) ) {
			
			/* Set best ramp rate and target */
			temp_target_table_index = find_nearest_ramp_rate(get_output);
			/* printf("\n table index: %d ", temp_target_table_index);	*/
			
			set_mid = (ramp_table_targets[temp_target_table_index]/10000);
			
			/* ramping down? ramp rate is the ceiling of the ramp table value (i.e. next highest value) */
			if(fabs(final_target) < fabs(get_output)) {
				/* if we're in the ranges of the ramp table */
				if(temp_target_table_index < (file_lines-1)) {
					set_ramp_rate = ramp_table_rates[temp_target_table_index+1];
					/*printf("\nramping DOWN at... %f, in table ranges", set_ramp_rate);*/
				}
				else {
					set_ramp_rate = ramp_table_rates[file_lines-1];
					/*printf("\nramping DOWN at HIGHEST TABLE VALUE... %f", set_ramp_rate);*/
				}
			}
			else {
				/* ramping up? ramp rate is matched to ramp target */
				set_ramp_rate = ramp_table_rates[temp_target_table_index];
				/*printf("\nramping UP at... %f at index: %d", set_ramp_rate, temp_target_table_index); */
			}
				
			/* If target is in-between ramp table values, target = final target. */
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
					set_ramp_rate = ramp_table_rates[0];
				}
			}	
	

			/* tesla/amp conversion */
			if(strcmp(get_output_mode, "AMPS")==0) {
				printf("\ndividing for amps conversion");
				set_mid /= get_constant;
			}
			
			printf("\ntarget: %.3f gauss\trate: %.3f a/sec\tcurrentoutput: %.3f\tfinal target: %f", set_mid*10000, set_ramp_rate, get_output*10000, final_target*10000);
			pvPut(set_ramp_rate, SYNC);
			pvPut(set_mid, SYNC);
			
		} state ramping_active
	}
	
		state write_ramp_table_file {
		entry {
			printf("\n==> Writing ramp table file to directory...");
			write_ramp_table_to_file();
			write_ramp_file_trigger = 0; pvPut(write_ramp_file_trigger, SYNC);
		}
		when (delay(1)) {
			
		} state idle		
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
			
		} state idle
	}
}

