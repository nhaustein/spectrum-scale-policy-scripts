#! /bin/ksh
################################################################################
# The MIT License (MIT)                                                        #
#                                                                              #
# Copyright (c) 2019 Nils Haustein                             				   #
#                                                                              #
# Permission is hereby granted, free of charge, to any person obtaining a copy #
# of this software and associated documentation files (the "Software"), to deal#
# in the Software without restriction, including without limitation the rights #
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell    #
# copies of the Software, and to permit persons to whom the Software is        #
# furnished to do so, subject to the following conditions:                     #
#                                                                              #
# The above copyright notice and this permission notice shall be included in   #
# all copies or substantial portions of the Software.                          #
#                                                                              #
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR   #
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,     #
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE  #
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER       #
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,#
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE#
# SOFTWARE.                                                                    #
################################################################################
#
# Program: receiver
#
# Description: 
# Interface script for LIST policy invoked by mmapplypolicy 
# Prints files identified by policy to output file
#
# Prerequisite:
# EXTERNAL list policy that identifies files that are not immutable.
#
# Input:
# invoked by mmapplypolicy with the following parameters:
# $1 operation (list, test)
# $2 file system name or name of filelist
# $3 optional parameter defined in LIST policy under OPTS
#
# Output:
# Prints file names identified by policy to $OUTPUTFILE
# Write runtime information and debugging messages to log file $LOGFILE
#
# Example Policy:
# /* define macros */
# define( exclude_list, (PATH_NAME LIKE '%/.SpaceMan/%' OR PATH_NAME LIKE '%/.snapshots/%' OR NAME LIKE '%mmbackup%' ))
# define( immutable, MISC_ATTRIBUTES LIKE '%X%')
# RULE EXTERNAL LIST 'setmp3' EXEC '/root/silo/receiver.sh' OPTS 'TEST'
# RULE 'mp3' LIST 'setmp3' FOR FILESET ('native') WHERE NOT (exclude_list) and NOT (immutable) and (NAME LIKE '%.mp3')
#
# Invokation:
# mmapplypolicy fsname -P policyfile
#
# Change History
# 10/09/12 first implementation based GAD startbackup
# 12/20/15 implementation for immutability, some streamlining of existing code
# 12/21/15 create the general receiver
# 06/26/20 Add name of the program to the output messages.

#global variables for this script
#----------------------------------
# define paths for log files and output files
MYPATH="./receiver"
# logfile used for system_log function
LOGFILE=$MYPATH/"receiver.log"
# outfile is used to print file names to
OUTPUTFILE=$MYPATH/"receiver.out"
# sets the log level for the system log, everything below that number is logged
LOGLEVEL=1
# set the default option for the file list processing in case $3 is not given
DEFOPTS=""


## Append to the system log
## Usage: system_log <log_level> <log_message>
system_log () {
  SEV=$1

  case $SEV in
    [0-9]) ;;
    *)    SEV=1;;
  esac
    
  LINE=$2
  if [ $LOGLEVEL -ge $SEV ] ; then
    if [[ -z "$LINE" ]]; then
	  echo -e "RECEIVER INTERNAL WARNING: Improper value given to system_log function ($@)" >> $LOGFILE
	else
      echo -e "RECEIVER: $LINE" >> $LOGFILE
	fi
  fi
}

## Print a message to the stdout
## Usage: user_log <log_message>
user_log () {
    echo -e "RECEIVER $@"
}


## Get current date and time
## Usage: get_cur_date_time 
get_cur_date_time(){
  echo "$(date +"%Y-%b-%d %H:%M:%S")"
}

#++++++++++++++++++++++++++ MAIN ++++++++++++++++++++++++++++++++++++++
user_log "$(get_cur_date_time) receiver.sh invoked by policy engine"

# check the path for logging
if [[ ! -d $MYPATH ]] then
  mkdir -p $MYPATH
  rc=$?
  if (( rc > 0 )) then
    system_log "ERROR: failed to create directory $MYPATH, check permissions"
    user_log "ERROR: failed to create directory $MYPATH, check permissions"
	exit 1
  fi
fi

system_log 1 "========================================================================="
system_log 1 "$(get_cur_date_time) receiver invoked with arguments: $*"

## Parse Arguments & execute
#$1 is the policy operation (list, migrate, etc) 
op=$1
#$2 is the policy file name
polFile=$2
#$3 is the option given in the EXTERNAL LIST rule with OPTS '..' should be retention time here  
option=$3
    
## this is required, as the script may be called multiple times during
## the same backup (if there are too many files to process).

case $op in 
  TEST ) 
       user_log "INFO: TEST option received for directory $polFile."
	   system_log 1 "INFO: TEST option received for $polFile"
	   if [[ ! -z "$polFile" ]] then
	     if [[ -d "$polFile" ]] then
		   user_log "INFO: TEST directory $polFile exists."
		   system_log 1 "INFO: Directory $polFile exists."
		 else
		   user_log "WARNING: TEST directory $polFile does not exists."
		   system_log 1 "WARNING: Directory $polFile does not exist."
		 fi
	   fi
	   
	   # delete the $OUTPUTFILE if it exists in order to get a clean start
	   if [[ -a $OUTPUTFILE ]] then
	     rm -f $OUTPUTFILE
	   fi
	   ;;
  LIST )
       user_log "INFO: LIST option received, starting receiver task"
	   system_log 1 "INFO: LIST option received with file name $polFile and options $option"
        
       #set option to default if not set
       if [[ -z $option ]] then 
	      option=$DEFOPTS
	   fi
	   
	   # process the files
	   itemNum=0
       numEntries=$(wc -l $polFile | awk '{print $1}')
	   system_log 1 "INFO: Start processing $numEntries files, outputfile=$OUTPUTFILE"
	   user_log "INFO: Start processing $numEntries files, outputfile=$OUTPUTFILE"
	   cat $polFile | while read line 
	   do
		 # use set to get file name, does tolerate blanks
		 set $line
		 shift 4
		 fName="$*"
		 
		 # perhaps check if file exists
		 echo "$fName" >> $OUTPUTFILE
		 ((itemNum=itemNum+1))
	   done
	   system_log 1 "INFO: Processed $itemNum out of $numEntries files"
	   user_log "INFO: Processed $itemNum out of $numEntries files"
       ;;
  REDO )
       user_log "INFO: REDO option received, doing nothing"
	   system_log 1 "INFO: REDO option received with file name $polFile and options $option"
       ;;
  * )
       user_log "WARNING: Unknown option $op received, doing nothing"
	   system_log 1 "WARNUNG: UNKNOWN option ($op) received with file name $polFile and options $option"
       ;;
esac

user_log "$(get_cur_date_time) receiver ended"
system_log 1 "$(get_cur_date_time) receiver ended"

# exit 0 if things are OK
exit 0