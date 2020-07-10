#!/bin/bash

####################################################################################################
#
# ABOUT THIS PROGRAM
#
# NAME
#	onboarding.sh -- Configure computer to Company Standards
#
# SYNOPSIS
#	sudo onboarding.sh
#	sudo onboarding.sh <mountPoint> <computerName> <currentUsername>
#
# DESCRIPTION
#	
#	This script drives the onboarding workflow, utilizing DEPNotify and pre-configured polices
#	to create a zero-touch deployment solution.
#
# USAGE
#
#	1. Upload this script into your Jamf Pro Server
#	2. Edit the "Configuration" section below
#	3. Add your own specific updates and policy calls in the section marked
#		"YOUR STUFF GOES HERE"
#	4. Call this script with a policy using the "Enrollment Complete" trigger
#
####################################################################################################
#
# HISTORY
#
#
#	Version 2.0
#	- Updated by Chad Lawson on 7/1/2020
#	- Broke blocks out into functions and stripped on non-universal work into other scripts
#
#	Version: 1.0
#
#	- Created by Chad Lawson on January 4th, 2019
#	- Based on work by 'franton' on MacAdmins Slack.
#		Posted on #depnotify on 12/31/18 @ 11:23am
#
#
#
####################################################################################################
#
# TODO
#
# LOTS more error checking is required!
#
####################################################################################################


##               ###
## Configuration ###
##               ###
LOGOFILE="/Library/Application Support/My Company/Company Logo.png"
WINDOWTITLE="My Company Provisioning"
MAINTITLE="Welcome to My Company"

function coffee {
	
	## Disable sleep for duration of run
	/usr/bin/caffeinate -d -i -m -u &
	caffeinatepid=$!	
}

function pauseJamfFramework {
	
	## Update Jamf frameworks
	/usr/local/bin/jamf manage

	## Disable Jamf Check-Ins
	jamftasks=($( find /Library/LaunchDaemons -iname "*task*" -type f -maxdepth 1 ))
	for ((i=0;i<${#jamftasks[@]};i++))
	do
		/bin/launchctl unload -w "${jamftasks[$i]}"
	done

	## Kill any check-in in progress
	jamfpid=$( ps -ax | grep "jamf policy -randomDelaySeconds" | grep -v "grep" | awk '{ print $1 }' )
	if [ "$jamfpid" != "" ];
	then
		kill -9 "$jamfpid"
	fi	
}

function waitForUser {
	
	## Check to see if we're in a user context or not. Wait if not.
	dockStatus=$( /usr/bin/pgrep -x Dock )
	while [[ "$dockStatus" == "" ]]; do
		sleep 1
		dockStatus=$( /usr/bin/pgrep -x Dock )
	done

	## Get the current user?
	currentuser=$( /usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | /usr/bin/awk -F': ' '/[[:space:]]+Name[[:space:]]:/ { if ( $2 != "loginwindow" ) { print $2 }}' )
	userid=$( /usr/bin/id -u $currentuser )	
}

function startDEPNotify {	
	
	## Create the depnotify log file
	/usr/bin/touch /var/tmp/depnotify.log
	/bin/chmod 777 /var/tmp/depnotify.log

	## Set up the initial DEP Notify window
	/bin/echo "Command: Image: ${LOGOFILE}" >> /var/tmp/depnotify.log
	/bin/echo "Command: WindowTitle: ${WINDOWTITLE}" >> /var/tmp/depnotify.log
	/bin/echo "Command: MainTitle: ${MAINTITLE}" >> /var/tmp/depnotify.log

	## Load DEP Notify
	deploc=$( /usr/bin/find /Applications -maxdepth 2 -type d -iname "*DEP*.app" )
	/bin/launchctl asuser $userid "$deploc/Contents/MacOS/DEPNotify" 2>/dev/null &
	deppid=$!	
}

function cleanUp {
	
	## Re-enable Jamf management
	for ((i=0;i<${#jamftasks[@]};i++))
	do
		/bin/launchctl load -w "${jamftasks[$i]}"
	done
	
	## Quit DEPNotify
	/bin/echo "Command: Quit" >> /var/tmp/depnotify.log
	/bin/rm -rf "$deploc" ## Deletes the DEPNotify.app

	## Delete temp files
	/bin/rm /var/tmp/depnotify.log
	/usr/bin/defaults delete menu.nomad.DEPNotify
	
	## Disable Caffeine
	/bin/kill "$caffeinatepid"	
}

function DEPNotify {
	
	local NotifyCommand=$1
	/bin/echo "$NotifyCommand" >> /var/tmp/depnotify.log
}

function jamfCommand {
	
	local jamfTrigger=$1
	
	if [[ $jamfTrigger == "recon" ]]; then
		/usr/local/bin/jamf recon
	elif [[ $jamfTrigger == "policy" ]]; then
		/usr/local/bin/jamf policy
	else 
		/usr/local/bin/jamf policy -event $jamfTrigger
	fi
}

###		###
### Main Script	###
###		###

## These next four lines execute functions above
coffee				## Uses 'caffeinate' to disable sleep and stores the PID for later
pauseJamfFramework 		## Disables recurring Jamf check-ins to prevent overlaps
waitForUser 			## Blocking loop; Waits until DEP is complete and user is logged in
startDEPNotify 			## Initial setup and execution of DEPNotify as user

###                      ###
### YOUR STUFF GOES HERE ###
###                      ###

## NOTES:
##	There are two functions to help simplify your DEPNotify commands and
##		calls to Jamf for other policies.
##
##	1. DEPNotify - Appends text to /var/tmp/depnotify.log
##		Ex. DEPNotify "Command: MainText: Message goes here"
##			DEPNotify "Status: Tell the user what we are doing..."
##
##	2. jamfCommand - Simplifies calls to the jamf binary with three options
##		'recon' 	- Submits an inventory to udpate Smart Groups, etc.
##		'policy' 	- Makes a normal policy check for new applicable policies
##		other 		- Calls jamf policy with the passed in argument as a manual trigger
##			Ex. "jamfCommand renameComputer" - executes "/usr/local/bin/jamf policy -trigger renameComputer"

## Machine Configuration
DEPNotify "Command: MainText: Configuring Machine."
DEPNotify "Status: Setting Computer Name"
jamfCommand configureComputer

## Installers required for every Mac - Runs policies with 'deploy' manual trigger
DEPNotify "Status: Starting Deployment"
DEPNotify "Command: MainText: Starting software deployment.\n\nThis process can take some time to complete."
jamfCommand deploy
sleep 3

## Add Departmental Apps - Run polices with "installDepartmentalApps" manual and scoped to departments
DEPNotify "Command: MainText: Adding Departmental Components."
DEPNotify "Status: Adding Departmental Applications. This WILL take a while."
jamfCommand recon 
sleep 1
jamfCommand installDepartmentalApps

## Send updated inventory for Smart Groups and check for any remaining scoped policies
DEPNotify "Command: MainText: Final install checks."
DEPNotify "Status: Update inventory record."
jamfCommand recon 
sleep 1
DEPNotify "Status: Final policy check."
jamfCommand policy

###         ###     
### Cleanup ###
###         ###     
cleanUp ## Quits application, deletes temporary files, and resumes normal operation
