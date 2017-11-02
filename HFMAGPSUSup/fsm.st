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
PV(double, get_limit, "{P}:LIMIT", Monitor);
PV(string, get_pause, "{P}:PAUSE", Monitor);
PV(double, get_output, "{P}:OUTPUT", Monitor);
PV(double, get_constant, "{P}:CONSTANT", Monitor);
PV(string, get_direction, "{P}:DIRECTION", Monitor);
PV(double, get_ramp_rate, "{P}:RAMPRATE", Monitor);
PV(string, get_ramp_target, "{P}:RAMPTARGET", Monitor);
PV(string, get_output_mode, "{P}:OUTPUTMODE", Monitor);
PV(string, get_heater_status, "{P}:HEATERSTATUS", Monitor);
PV(double, get_final_target, "{P}:MIDFINALTARGET", Monitor);
PV(int, write_ramp_file_trigger, "{P}:WRITEFILE", Monitor); 
PV(int, read_ramp_file_trigger, "{P}:READFILE", Monitor); 

PV(double, set_zero, "{P}:ZERO", Monitor);
PV(double, set_final_target, "{P}:MIDFINALTARGET", Monitor);
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

double final_target;
int largest_target_index;
int smallest_target_index;

float abs_target;
int j;
int i;

int ramp_zero_trigger;
double ramp_zero_cache;

double output_display; assign output_display to "{P}:OUTPUTDISPLAY";

%{
	
	
static void sort_column(double arr[][2], int file_lines) {
	/* Function to sort ramp file values into order by Target */
	int i,j, k;
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

	/* Reading ramp table values from external .txt file */
	/* Puts file values into ramp_table_rates and ramp_table_targets */
	/* printf("\n==> Reading ramp table file..."); */
	/* Empty our arrays to start re-write */
	memset(ramp_table_targets, -1, sizeof(ramp_table_rates));
	memset(ramp_table_rates, -1, sizeof(ramp_table_rates));
	memset(sort_values, -1, sizeof(sort_values));
	file_lines = 0;
	
	FILE *ramp_file;
	ramp_file = fopen(ramp_table_directory, "r");
	/* printf("\n==> File opened "); */
	
	if (ramp_file != NULL) {
		/* Skip first line */
		fgets(buffer, 30, ramp_file);
		
		while (fgets(buffer, 30, ramp_file) != NULL) {			
			token = strtok(buffer, delim);
			sort_values[file_lines][0] = strtod(token, NULL);
			/* ramp_table_targets[file_lines] = strtod(token, NULL); */			
			token = strtok(NULL, delim);
			sort_values[file_lines][1] = strtod(token, NULL);
			/* ramp_table_rates[file_lines] = strtod(token, NULL); */			
			file_lines++;			
		}	
	}	
	else {
		printf("\nFile Read Error");
		exit(-1);
	}
	fclose(ramp_file);	
	/* printf("\n==> File read complete!"); */
	
	/* Sort ramp file values into ascending order of target, and put into our PV values*/
	for (i = 0; i < file_lines;i++) {
		sort_column(sort_values, file_lines);
		ramp_table_targets[i] = sort_values[i][0];
		ramp_table_rates[i] = sort_values[i][1];
	}	
}


static void write_ramp_table_to_file() {
	
	printf("\n==> Writing file...");
	
	FILE *ramp_file;
	ramp_file = fopen(ramp_table_directory, "w");
	
	for(i = 0; i < 64; i++) {
		if (ramp_table_targets[i] > 0) {
			j++;
		}
	}	
	
	if (ramp_file != NULL) {
		/* Skip first file_lines 
		char headers[25] = "targets rates";
		fprintf(ramp_file, "%s", headers);
		*/
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
	
	/*  :returns: Index value of next available ramp target/ramp rate. */

	int nearest_index = 0;
	difference_ramp_down = DBL_MAX;
	difference_ramp_up = DBL_MAX;	
	largest_target_index = file_lines-1;
	smallest_target_index = 0;
	
	for (int x = 0; x < file_lines; x++) {
		/* Ramping up? Find next highest value */
		if (fabs(get_final_target) > fabs(current_output)) {
			if(fabs(current_output) < (ramp_table_targets[x]/10000)) {
				nearest_index = x;
				break;
			}			
		}		
		/* Ramping down? Find next lowest Value */
		if (fabs(get_final_target) < fabs(current_output)) {
			if(fabs(current_output) > (ramp_table_targets[x]/10000)) {
				nearest_index = x;
			}
		}
	}
	/* If we have reached the last table value, and our final target is beyond that - */
	if (((fabs(get_final_target) > (ramp_table_targets[file_lines-1]/10000)) && ( fabs(current_output) >= (ramp_table_targets[file_lines-1]/10000)) ) ||
     	( ( fabs(get_final_target) < (ramp_table_targets[0]/10000)) && (fabs(current_output) <= (ramp_table_targets[0]/10000))) ){
		printf("\n==> We're heading beyond the ranges of the ramp table!");
		nearest_index = 100;
	}
	return nearest_index;
}

static double convert_units(double val) {
	/* Return the value of a variable based on whether the user has selected Amps or Gauss. */
	if (val == 0) {
			return 0;
		}
	else if (strcmp(get_output_mode, "GAUSS")==0) {
			return val * 10000 * get_constant;
		}
	else {
		return val;
	}
}
}%

foreign ssId;

ss fsm {

	state init {
  
		entry {
			/* Set initial PV variables */			
			printf("\n==> init: Setting initial variable values\n");
			strcpy(ramp_table_directory, macValueGet("RAMPTABLEDIR"));
			pvPut(ramp_table_directory, SYNC);		
			
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
			/*printf("\nramp_idle ==> set_ramp_values");*/	
			/* If ramp will pass from + to - or - to + */
			if (((get_output < 0) && (get_final_target > 0)) || ((get_output > 0) && (get_final_target < 0)))  {
				printf("\nPASSING THROUGH ZERO!");
				ramp_zero_trigger = 1;
				ramp_zero_cache = get_final_target;
				get_final_target = 0; pvPut(get_final_target, SYNC);
			}
			else {
				ramp_zero_trigger = 0;
			}
			/*printf("\nsetting ramp_zero_trigger to: %i", ramp_zero_trigger);*/
			/* printf("\n==> final target = %f", get_final_target); */
		  
		  /* removed code: getting target value. Instead we send 
		  set_target = 1;
		  pvPut(set_target);
		  printf("\n==> Target: %s", get_ramp_target);
		  
		  /*
		  If Units are Gauss, Global B Target X (value to use) = (final target / 10000) / T/A Sweep
		If Units are AMPS, Global B Target X (value to use) = final target

		  
		  */
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
		when((fabs(get_final_target - (get_output*10000)) < 0.00001) && (ramp_zero_trigger == 0)) {
			printf("\nramp_zero_trigger: %i", ramp_zero_trigger);
			printf("\nramp_active ==> ramp_complete");
			set_pause = 1; pvPut(set_pause, SYNC);			
		} state ramp_complete
		
		/* When we've finished ramping to zero */
		when((fabs(get_final_target - (get_output*10000)) < 0.00001) && (ramp_zero_trigger == 1)) {
			printf("\nRamp to Zero complete, continuing to next target");
			/* Continue to previous user-set target */
			get_final_target = ramp_zero_cache;
			ramp_zero_trigger = 0;
		} state set_ramp_values
		
		/* When the interim target is reached, search for next target */
		when(fabs(get_output - get_mid) < 0.00001) {
			/*printf("\nramp_active ==> set_ramp_values");	*/		
		} state set_ramp_values

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
			read_ramp_table_rates();
			temp_target_table_index = find_nearest_ramp_rate(get_output);
			
			/* Set Direction based on current output and our target */
			if ((get_output >= 0) && (get_final_target >= 0)) {	
				set_direction = 2;
			}
			else if ((get_output <= 0) && (get_final_target < 0)) {
				set_direction = 1;
			}						
			pvPut(set_direction, SYNC);			
			
			set_mid = (ramp_table_targets[temp_target_table_index]/10000);						
			set_ramp_rate = ramp_table_rates[temp_target_table_index];
			
			if ((set_mid > fabs(get_final_target)) && (get_final_target != 0)) {
				printf("\nMiddly-table value");
				set_mid = fabs(get_final_target/10000);
			}
			
			pvPut(set_direction, SYNC);
			printf("\nDirection:");
			printf(get_direction);
			/* If we're beyond the ranges of the ramp table, set target to be user's Final target, and 
			   rate to be the currently used rate. */
			if (temp_target_table_index > 99) {
				set_mid = (get_final_target/10000);
				set_ramp_rate = get_ramp_rate;
			}
			
			if (set_direction == 1) {
				set_mid *= -1.0;				
			}
			if (set_direction == 2) {
				set_mid = fabs(set_mid);
			}
			
			pvPut(set_ramp_rate, SYNC);
			pvPut(set_mid, SYNC);						
		}
		
		when (delay(1)) {
			/*printf("\nAFTER: set_target = %f \tget_target =  %f", set_mid, get_mid);*/
			printf("\n==> Set values: Current Target: %f \t Final Target: %f \t Rate: %f", get_mid, get_final_target, get_ramp_rate);
	
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

