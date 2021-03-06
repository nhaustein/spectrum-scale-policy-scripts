## Description

Spectrum Scale Information Lifecycle Management policies can be configured to automatically migrate files from one file system pool to another if a pre-defined occupation limit of a pool is met. For example in an environment with two file system pools (e.g. system and silver) files can be placed in pool `system` and if pool `system` reaches an occupation of 80% then files can be migrated to pool `silver`. This migration policy however takes the entire file system occupation into account and not the occupation of a particular fileset.

To take the occupation of a fileset into account, the standard ILM policies are not effective. However it is possible to migrate files pertaining to a particular fileset if the fileset soft quota limit is met. Migrating files pertaining to a particular fileset from one file system pool to another only makes sense if the files for a particular fileset are placed in a particular pool. For example, all files for a fileset name fset1 can be placed in pool `system`. 

This project provides a description of the methodology along with some sample code and policies to accomplish this.


### Methodology

To migrate files pertaining to a particular fileset of a Spectrum Scale file system when the fileset has reached the pre-defined soft quota limit the following components are required:

1.	An EXTERNAL LIST policy [quota-listpol.txt](quota-listpol.txt) that identifies files according to quota limits using the clause `THRESHOLD (resourceclass)` in the EXTERNAL LIST rule and the clause THRESHOLD(%high, %low) in the LIST rule. The parameter `resourceclass` in the EXTERNAL LIST rule can be `FILESET_QUOTAS` for hard quota limits or `FILESET_QUOTA_SOFT` for soft quota limits. Files are identified if the quota occupation in the fileset is above the THRESHOLD defined in the LIST rule. The LIST policy identifies files located in pool `system` that brings the occupation in the fileset down to a low threshold. The LIST policy stores the list of identified files in a pre-defined location. This list of files is used as input for the MIGRATION policy. 

2.	A MIGRATE policy [quota-migpol.txt](quota-migpol.txt) takes the list of files generated by the EXTERNAL LIST policy, evaluates these against the migration rule and migrates selected files from pool `system` to pool `ltfs` that is managed by IBM Spectrum Archive Enterprise Edition. 

3.	A callback script [callback-quota.sh](callback-quota.sh) that is invoked when the Spectrum Scale event `softQuotaExceeded` is raised for a fileset. This callback script runs the EXTERNAL LIST policy of step 1 to identify files according to the quota limits and invokes the migration policy of step 2 with the files being identified. Thus, the callback script is invoked when the event `softQuotaExceeded` is triggered and coordinates the LIST and MIGRATE policy runs. 

4.	Last but not least, the Spectrum Scale callback is defined that receives the event `softQuotaExceeded` and runs the callback script `callback-quota.sh`passing on certain parameters including the file system and fileset name that triggered this even Quota callback. 
 
 
* Note: *
The event `softQuotaExceeded` is triggered on the file system manager. Any node with a manager role in the cluster can become file system manager. Therefore all components explained above have to be installed on all nodes with manager role. 


The next sections explain how to install and configure these components.


## Preparation

Setup the placement policy for the filesets placing all files stored in this fileset directory to a particular pool. The following placement policy example places all files stored in fileset `test` in the pool `system`. All other files are placed in pool `data`:

		/* fileset placement rule */ 
		RULE 'placefset' SET POOL 'system' FOR FILESET ('test') 
		/* default placement rule */ 
		RULE 'default' SET POOL 'data'


Configure quota for the filesets that should be migrated when the quota limit is reached. 


Copy the `callback-quota.sh` script and the two policy files (`quota-listpol.txt` and `quota-migpol.txt`) into the same directory on all nodes in your cluster that have manager role. Since all nodes in a cluster have access to the common Spectrum Scale file systems you can copy these files into a directory of the Spectrum Scale file system. 


Adjust configurable parameters in the `callback-quota.sh` script:


| Parameter | Description |
| ----------|-------------|
| workDir | define the working directory where output files of the policy runs are stored. It may also be used to define the path names of the policy files. This directory must exist.  |
| logDir | define the directory where the log files are stored. This directory must exist.  |
| logF | define the file name of the log file. The log file is stored under directory specified by `logDir` and is continuously appended. Configure log rotation for this file when required. | 
| outfile | define the path and file name prefix of the file list created by the EXTERNAL LIST policy. |
| listPol | define the path and file name of the policy file including the EXTERNAL LIST policy [quota-listpol.txt](quota-listpol.txt) | 
| migPol | define the path and file name of the policy file including the MIGRATE policy [quota-migpol.txt](quota-migpol.txt) | 
| migPolOpts | define options for the `mmapplypolicy` command running the migration. When migrating to Spectrum Archive these should include the EE node names (`-N`), the number of threads (`-m`), the bucket size (`-B`), etc. |
| eePool | define the pool name for the tape pool when migrating to Spectrum Archive EE. The tape pool name given here in the syntax `pool@library` substitutes the parameter `EEPOOL`in the migrate policy [quota-migpol.txt](quota-migpol.txt). When not migrating to Spectrum Archive EE then leave this parameter blank and adjust the migrate policy. |



Adjust the policy file [quota-listpol.txt](quota-listpol.txt) according to your needs.


Adjust the policy file [quota-migpol.txt](quota-migpol.txt) according to your needs


Create the Spectrum Scale callback:

     # mmaddcallback SOFTQUOTA-MIGRATION --command /path/callback-quota.sh --event softQuotaExceeded --parms "%eventName %fsName %filesetName"

The callback is invoked when the event `softQuotaExceeded` is triggered for the file system on the file system manager. The callback launches the script `/path/callback-quota.sh` (the path must be spelled out and it must be identical for all manager nodes). The callback passes the following parameters to the callback script:
	`eventName` 	is the event `softQuotaExceeded`
	`fsName`  		file system name where the event was triggerd for
	`fsetname` 		fileset name where the event was triggered for. If the event was triggered for the entire file system then the fileset name is `root`. 


Test if the callback script is effective. For example by temporarily reducing the soft quota limit and storing some files in the fileset. Monitor the GPFS logs on the active file system manager for the file system to see that the event `softQuotaExceeded` is triggered and that the callback script `callback-quota.sh` is launched and files are migrated. 


## Processing

The `callback-quota.sh` script performs the following steps: 
- check if preconfigured parameters are correct
- check if parameters passed by the callback are correct
- run the EXTERNAL LIST policy and create list of selected files based on quota consumption
- run the MIGRATE policy using the file list produced by the EXTERNAL LIST policy


## Output

The `callback-quota.sh` writes STDIN and STDERR to the log file defined by parameter `$logF`

Return codes:

  0: Good
  
  1: Error


## Notes

- The callback is configured cluster wide for all nodes.
- The callback script along with the policy files must be installed on all manager nodes because the event is triggered on the file system manager only. 
- The event "softQuotaExceeded" is only triggered once per fileset when the condition is met. It expects the space consumption to decrease under the quota limits. If this is the case and after a while the quota limit is reached again then this event is triggered again. Otherwise, if the space consumption does not decrease then the event might not be triggered again. Therefore it is important to make sure that the callback script works 100 % and that it alerts the admin if not. 
- In order to retrigger the event the softquota limits can be increased or files can be move out and back in again. Some delay between moving files out of the files and in should be planned (5 - 10 min).  
- Consider placing the temporary file generated by mmapplypolicy in a directory with sufficient space. Use the parameter -s with the mmapplypolicy command for this. 

