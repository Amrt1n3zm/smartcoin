#!/bin/bash

# This is the dumping ground for a lot of generalized functions, and is pretty much included in all other scripts.
# I really need to organize it a bit, clean it up, and maybe even separate it out into more logical files.


if [[ -n "$HEADER_smartcoin_ops" ]]; then
        return 0
fi
HEADER_smartcoin_ops="included"
if [[ $( dirname "$0" ) == "/usr/bin" ]]; then
	CUR_LOCATION=$(dirname $(readlink -f $( dirname "$0" )/smartcoin))
else
	CUR_LOCATION="$( cd "$( dirname "$0" )" && pwd )"
fi
. $CUR_LOCATION/sql_ops.sh

# GLOBALS
Q="SELECT value FROM settings WHERE data='dev_branch';"
R=$(RunSQL "$Q")
branch=$(Field 1 "$R")
if [[ "$branch" == "stable" ]]; then
	G_BRANCH="$branch"
	G_BRANCH_ABBV="s"
elif [[ "$branch" == "experimental" ]]; then
	G_BRANCH="$branch"
	G_BRANCH_ABBV="e"
fi



# SVN STUFF
GetRevision() {
  Q="SELECT value FROM settings WHERE data='dev_branch';"
  local branch=$(RunSQL "$Q")
  echo $(svn info $CUR_LOCATION/ | grep "^Revision" | awk '{print $2}')
}

GetRepo() {
	echo `svn info $CUR_LOCATION/ | grep "^URL" | awk '{print $2}'`
}
GetLocal() {
  echo $(svn info $CUR_LOCATION/ | grep "^Revision" | awk '{print $2}')
}
GetHead() {
	local repo="$1"
	echo `svn info $repo | grep "^Revision" | awk '{print $2}'`
}
GetStableHead() {
	local repo="$1"
	echo `svn info $repo/update.ver | grep "Last Changed Rev:" | awk '{print $4}'`
}

FormatOutput() {
	local hashes="$1"
	local accepted="$2"
	local rejected="$3"
	local percentage="$4"

	Q="SELECT value FROM settings WHERE data='format';"
	local R=$(RunSQL "$Q")
	format=$(Field 1 "$R")

	format=${format//<#hashrate#>/$hashes}
	format=${format//<#accepted#>/$accepted}
	format=${format//<#rejected#>/$rejected}
	format=${format//<#rejected_percent#>/$percentage}
	echo "$format"
	
}

# GLOBAL VARIABLES
# TODO: some of these will be added to the settings database table eventually.
# TODO: The installer can prompt for values, with sane defaults already entered
export sessionName="smartcoin"
export minerSession="miner"
export REVISION=$(GetRevision)
RESTART_REQ=""



STABLE=1
EXPERIMENTAL=2

commPipe=$HOME/.smartcoin/smartcoin.cmd
statusRefresh="5"






RunningOnLinuxcoin() {
	if [[ "$HOSTNAME" == "linuxcoin" ]]; then
		echo "1"
	else
		echo "0"
	fi
}

ShowHeader() {
	echo "Smartcoin r$REVISION$G_BRANCH_ABBV" $(date "+%T")
	local cols=$(tput cols)
	#for i in $(seq $cols); do echo -n "-"; done

	echo "----------------------------------------"
}


tableIsEmpty() {
	local thisTable=$1
	local whereClause=$2

	Q="SELECT COUNT(*) FROM $thisTable $whereClause;"
	R=$(RunSQL "$Q")
	res=$(Field 1 "$R")

	if [[ "$res" == "0" ]]; then
		echo "True"
	else
		echo ""
	fi
}




GotoStatus() {
	attached=`screen -ls | grep $sessionName | grep Attached`

	if [[ "$attached" != "" ]]; then
		screen  -d -r -p 0
	else
		screen  -r $sessionName -p 0
	fi
	
}


Log() {
	local line="$1"
  local announce="$2"
  
	local dte=`date "+%D %T"`
	echo -e "$dte\t$line\n" >> $HOME/.smartcoin/smartcoin.log
   
  if [[ "$announce" == "1" ]]; then
    echo -e $line
  fi
}

RotateLogs() {
	mv $HOME/.smartcoin/smartcoin.log $HOME/.smartcoin/smartcoin.log.previous
}


DeleteTemporaryFiles() {

	if [[ -z "$thisMachine" ]]; then
		# No machine selected, update settings on all machines!
		Q="SELECT pk_machine FROM machine WHERE disabled=0;"
		R=$(RunSQL "$Q")

		for row in $R; do
			local nextMachine=$(Field 1 "$row")
			thisMachine=$thisMachine$nextMachine
			thisMachine=$thisMachine" "
		done
	fi

	local machine
	for machine in $thisMachine; do
		Q="SELECT pk_machine,name,server,username,ssh_port FROM machine WHERE pk_machine=$machine;"
		R=$(RunSQL "$Q")
		local user=$(Field 4 "$R")
		local server=$(Field 3 "$R")
		local port=$(Field 5 "$R")
		local machineInfo="$R"
		if [[ "$machine" == "1" ]]; then
			Launch $machineInfo "rm -rf /tmp/smartcoin* 2>/dev/null"
		else
			Launch $machineInfo "'rm -rf /tmp/smartcoin* 2>/dev/null'"
		fi
	done
}




SetDefaultMiner() {
	local thisMachine=$1
	local thisMiner=$2

	Q="UPDATE miner SET default_miner=0 WHERE fk_machine=$thisMachine;"
	RunSQL "$Q"

	Q="Update miner set default_miner=1 WHERE pk_miner=$thisMiner;"
	RunSQL "$Q"
}


### PROFILE RELATED FUNCTIONS ###
# TODO:  These should be in their own include file I think
GetCurrentProfile()
{
	local thisMachine=$1

	local Donate=$G_DONATION_ACTIVE

	if [[ "$Donate" ]]; then
		echo "donate"
	else
		Q="SELECT fk_profile FROM current_profile WHERE fk_machine=$MACHINE;"
		R=$(RunSQL "$Q")
		echo $(Field 1 "$R")
	fi
}
GenCurrentProfile()
{
	# Return FieldArray containing pk_profile, windowKey, pk_device, pk_miner, pk_worker, device.name, miner.launch,profile.down fields

	local thisMachine=$1
	local thisProfile=$(GetCurrentProfile "$thisMachine")
	local FieldArray
	
	local Donate=$G_DONATION_ACTIVE


	if [[ "$Donate" ]]; then
		# AutoDonate time is right, lets auto-donate!
		# Generate the FieldArray via DonateProfile
		Log "Generating Donation Profile"
		FieldArray=$(GenDonationProfile "$thisMachine")
  	elif [[ "$thisProfile" == "-4" ]]; then
    		# Generate a blank Field array for the "idle" profile
    		FieldArray=""
	elif [[ "$thisProfile" == "-3" ]]; then
		# Generate the FieldArray via Failover
		FieldArray=$(GenFailoverProfile "$thisMachine")
	elif [[ "$thisProfile" == "-2" ]]; then
		# Generous user manually chose the Donation profile!
		FieldArray=$(GenDonationProfile "$thisMachine")
		
	elif [[ "$thisProfile" == "-1" ]]; then
		# Generate the FieldArray via AutoProfile

		FieldArray=$(GenAutoProfile "$thisMachine")
	else
		# Generate the FieldArray via the database
		Q="SELECT fk_profile, 'Miner.' || pk_profile_map, fk_device, fk_miner, fk_worker, device.name, miner.launch, profile.down from profile_map LEFT JOIN device ON profile_map.fk_device=device.pk_device LEFT JOIN miner ON profile_map.fk_miner=miner.pk_miner LEFT JOIN profile ON profile_map.fk_profile=profile.pk_profile WHERE fk_profile='$thisProfile' AND device.disabled='0' ORDER BY fk_worker ASC, fk_device ASC"
        	FieldArray=$(RunSQL "$Q")
	fi
	

	echo $FieldArray	
}

GenAutoProfile()
{
	# Return FieldArray containing pk_profile, windowKey, pk_device, pk_miner, pk_worker, device.name, miner.launch,profile.down fields
	local thisMachine=$1

	local FA
	local i=0

	Q="SELECT pk_miner, launch FROM miner WHERE fk_machine=$thisMachine AND default_miner=1;"
	R=$(RunSQL "$Q")
	thisMiner=$(Field 1 "$R")
	thisLaunch=$(Field 2 "$R")

	Q="SELECT pk_worker FROM worker WHERE auto_allow=1 ORDER BY fk_pool ASC;"
	R=$(RunSQL "$Q")

	
	for thisWorker in $R; do
		Q="SELECT pk_device, name from device WHERE fk_machine='$thisMachine' AND disabled='0' AND auto_allow='1' AND type='gpu' ORDER BY device ASC;"
		R2=$(RunSQL "$Q")
		for thisDeviceRow in $R2; do
			thisDevice=$(Field 1 "$thisDeviceRow")
			thisDeviceName=$(Field 2 "$thisDeviceRow")

			let i++
		
			FA=$FA$(FieldArrayAdd "-1	Miner.$i	$thisDevice	$thisMiner	$thisWorker	$thisDeviceName	$thisLaunch	0") #force profile.down to 0, as the automatic profile is never "down"
		done
	done

	echo "$FA"
}


GenFailoverProfile()
{
	# Return FieldArray containing pk_profile, windowKey, pk_device, pk_miner, pk_worker, device.name, miner.launch fields
	local thisMachine=$1
	local FA
	local i=0
	local foundUpProfile=0

	# Return, in order, all failover profiles to the point that one not marked as "down" is found, and return them all.
	local firstActive=""
	
	# Get a list of all the profiles
	Q="SELECT pk_profile, name, down FROM profile WHERE fk_machine='$thisMachine' AND failover_order>'0' ORDER BY failover_order, pk_profile;"
	R=$(RunSQL "$Q")

	# Generate the FieldArray until we get the first profile that isn't down!
	for row in $R; do
		local thisProfile=$(Field 1 "$row")
		local isDown=$(Field 3 "$row")
		# Build the FieldArray until we get a profile that isn't down
		Q2="SELECT fk_device, fk_miner, fk_worker, device.name, profile.down, miner.launch from profile_map LEFT JOIN device ON profile_map.fk_device=device.pk_device LEFT JOIN profile ON profile_map.fk_profile=profile.pk_profile LEFT JOIN miner ON profile_map.fk_miner=miner.pk_miner WHERE fk_profile='$thisProfile' AND device.disabled='0' ORDER BY fk_worker ASC, fk_device ASC"
		R2=$(RunSQL "$Q2")
		for row2  in $R2; do
			let i++
			local thisDevice=$(Field 1 "$row2")
			local thisMiner=$(Field 2 "$row2")
			local thisWorker=$(Field 3 "$row2")
			local thisDeviceName=$(Field 4 "$row2")
			local thisDown=$(Field 5 "$row2")
			local thisLaunch=$(Field 6 "$row2")

			FA=$FA$(FieldArrayAdd "$thisProfile	Miner.$i	$thisDevice	$thisMiner	$thisWorker	$thisDeviceName	$thisLaunch	$thisDown")
		done
		if [[ "$isDown" == "0" ]]; then
			# We found the first failover profile that isn't down, lets get out of here
			foundUpProfile=1
			break
		fi
	done

	#if [[ "$foundUpProfile" == "0" ]]; then

		# None of the profiles in the failover order were up!
		# Send hashes to the donation profile until one of them comes back up!
		# Its better to have the hashes going somewhere, rather than nowhere!
		# TODO: Fully test this when I get time. DISABLE FOR NOW!
		#FA=$FA$(FieldArrayAdd $(GenDonationProfile $thisMachine "-5"))
	#fi

	echo "$FA"

}
GenDonationProfile()
{
	# Return FieldArray containing pk_profile, windowKey, pk_device, pk_miner, pk_worker, device.name, miner.launch fields
	local thisMachine=$1
	local profileNumber=$2

	if [[ -z "$profileNumber" ]]; then
		profileNumver="-2"
	fi

	local FA
	local i=0
	#local donationWorkers="-3 -2 -1"
	local donationWorkers="-1"
	
	Q="SELECT pk_miner,launch FROM miner WHERE fk_machine=$thisMachine AND default_miner=1;"
	R=$(RunSQL "$Q")
	thisMiner=$(Field 1 "$R")
	thisLaunch=$(Field 2 "$R")

	

	for thisDonationWorker in $donationWorkers; do
		Q="SELECT pk_device,name from device WHERE fk_machine='$thisMachine' AND disabled='0' ORDER BY device ASC;"
		R=$(RunSQL "$Q")
		for thisDeviceRow in $R; do
			thisDevice=$(Field 1 "$thisDeviceRow")
			thisDeviceName=$(Field 2 "$thisDeviceRow")

			let i++
		
			FA=$FA$(FieldArrayAdd "$profileNumber	Miner.$i	$thisDevice	$thisMiner	$thisDonationWorker	$thisDeviceName	$thisLaunch	0") # Force profile_down to 0, as the donation profile is never really "down"
		done
	done

	echo "$FA"
}

# alternate between donating to smartcoin and linuxcoin, if linuxcoin is installed.
# This "flag" will be xor'd with 1 every other time
lastDonation="0"
DONATION_ENTITY="0"
CycleDonations() {
	local currentDonation="$1"
	
	local onLinuxcoin

	onLinuxcoin=$(RunningOnLinuxcoin)
	
	if [[ "onLinuxcoin" == "1" ]]; then
		if [[ "$currentDonation" == "0" ]]; then
			if [[ "$lastDonation" != "0" ]]; then
				# The donation state has changed from donating to not donating.
				# Lets cycle through the list of donation entities, so that the next entity gets a dontation on the next donation cycle (everyone gets their turn)
				# Note: right now there are only 2 donation entities (0 and 1), so a simple xor will do. If more are added in the future, then I will deal with that then...				
			
				let DONATION_ENTITY=DONATION_ENTITY^1
			fi
		fi
	fi

	lastDonation=$currentDonation
}
GetWorkerInfo()
{
	# Returns a FieldArray containing user, pass, pool.server, pool.port, pool.name
	local pk_worker=$1
	local FA


	# Handle special cases, such as special donation keys
	case "$pk_worker" in
	-1)
		case "$DONATION_ENTITY" in
		0)
			# smartcoin Deepbit donation worker
			FA=$(FieldArrayAdd "1AnDpiSvcUKejhENUFuigRCZC97cir4uwn	x	mining.eligius.st	8337	Eligius (Donation to smartcoin)")
			;;
		1)
			# linuxcoin donation worker #1
			FA=$(FieldArrayAdd "zarren2@hotmail.co.uk_1	password	deepbit.net	8332	Deepbit.net (Donation to linuxcoin)")
			;;
		esac
		;;
	-2)
		case "$DONATION_ENTITY" in
		0)
			# smartcoin BTCMine donation worker
			FA=$(FieldArrayAdd "jondecker76@donate	donate	btcmine.com	8332	BTCMine (Donation to smartcoin)")
			;;
		1)
			# linuxcoin donation worker #2
			FA=$(FieldArrayAdd "zarren2@hotmail.co.uk_2	password	deepbit.net	8332	Deepbit.net (Donation to linuxcoin)")
			;;
		esac
		
		;;
	-3)
		case "$DONATION_ENTITY" in
		0)
			# BTCGuild donation worker
			FA=$(FieldArrayAdd "jondecker76_donate	donate	btcguild.com	8332	BTCGuild (Donation to smartcoin)")
			;;
		1)
			# linuxcoin donation worker #3
			FA=$(FieldArrayAdd "zarren2@hotmail.co.uk_3	password	deepbit.net	8332	Deepbit.net (Donation to linuxcoin)")
			;;
		esac
		;;
	
	*)
		# No special cases, get information from the database
		Q="SELECT user,pass,pool.server, pool.port, pool.name from worker LEFT JOIN pool ON worker.fk_pool = pool.pk_pool WHERE pk_worker=$pk_worker;"
		FA=$(RunSQL "$Q")
		;;

	esac

	echo $FA
}



GetCurrentDBProfile() {
	local thisMachine=$1

	UseDB "smartcoin.db"
	Q="SELECT fk_profile from current_profile WHERE fk_machine=$thisMachine;"
	R=$(RunSQL "$Q")
	echo $(Field 1 "$R")
}
SetCurrentProfile() {
	local thisMachine=$1
	local thisProfile=$2

	Q="DELETE FROM current_profile WHERE fk_machine=$thisMachine;"
	RunSQL "$Q"
	Q="INSERT INTO current_profile (fk_machine,fk_profile) VALUES ($thisMachine,$thisProfile);"
	RunSQL "$Q"
}

DiffTime()
{
	local startTime=$1
	local endTime=$2

	startTime=$(seq $startTime $startTime)
	endTime=$(seq $endTime $endTime)

	# Convert both to minutes
	hours=`expr $startTime / 100`
	minutes=`expr $startTime % 100`
	let hourMins=$hours*60
	let startMinutes=$hourMins+$minutes

	hours=`expr $endTime / 100`
	minutes=`expr $endTime % 100`
	let hourMins=$hours*60
	let endMinutes=$hourMins+$minutes

	echo `expr $endMinutes - $startMinutes`


}	

AddTime()
{
	local baseTime=$1
	local minutesToAdd=$2

	basetime=$(seq $baseTime $baseTime)
	local minutes=`expr $baseTime % 100` #${baseTime:2:3}
	local hours=`expr $baseTime / 100` #${baseTime:0:2}


	# Add minutes and keep between 0 and 60
	local totalMinutes=$(($minutes+$minutesToAdd))
	local carryOver=$(($totalMinutes/60))
	local correctedMinutes=$(($totalMinutes%60))
	correctedMinutes=`printf "%02d" $correctedMinutes` # pad with at least one zero if needed
	
	# Add remainder to hours
	local correctedHours=$(($hours+carryOver))
	correctedHours=$(($correctedHours%24))
	
	echo $correctedHours$correctedMinutes


}



# DonationActive returns either nothing if the donation isn't active,
# or a positive number representing the number of minutes remaining in the donation cycle
DonationActive() {
	Q="SELECT value FROM settings WHERE data='donation_start';"
	R=$(RunSQL "$Q")
	local start=$(Field 1 "$R")
	
	Q="SELECT value FROM settings WHERE data='donation_time';"
	R=$(RunSQL "$Q")
	local duration=$(Field 1 "$R")

	if [[ "$duration" == "" ]]; then
		duration="0"
	fi
	if [[ "$start" == "" ]]; then
		let startTime_hours=$RANDOM%23
		let startTime_minutes=$RANDOM%59
		startTime=$startTime_hours$startTime_minutes
		Q="UPDATE settings SET value='$startTime' WHERE data='donation_start'"
		RunSQL "$Q"
	fi

	local end=$(AddTime "$start" "$duration")
	
	local curTime=`date +%k%M`
	curTime=$(seq $curTime $curTime)


	ret=""

	if [[  "$duration" -gt "0" ]]; then
		if [[ "$start" -le "$end" ]]; then
			# Normal
			if [[ "$curTime" -ge "$start" ]]; then
				if [[ "$curTime" -lt "$end"  ]]; then
					#ret="true"
					ret=$(DiffTime $curTime $end)
				fi
			fi
		else
			 # Midnight carryover
			if [[ "$curTime" -ge "$start" ]]; then
				#ret="true"
				local minTilMid=$(DiffTime $curTime "2400")
				ret=$(AddTime $end $minTilMid)
				ret=$(seq $ret $ret)
			fi
			if [[ "$curTime" -lt "$end" ]]; then
				ret=$(DiffTime $curTime $end)
				
			fi
		fi
	fi

	CycleDonations "$ret"
	G_DONATION_ACTIVE=$ret

}

GenProfileName() {
	local thisProfile=$1

	local Donate=$G_DONATION_ACTIVE

	if [[ "$Donate" ]]; then
		echo "Donation (via AutoDonate)  - $Donate minutes remaining."
	elif [[ "$thisProfile" == "-5" ]]; then
		echo "Donation (Last resort failover)"
	elif [[ "$thisProfile" == "-4" ]]; then
		echo "Idle"
	elif [[ "$thisProfile" == "-3" ]]; then
		echo "Failover"
	elif [[ "$thisProfile" == "-2" ]]; then
		echo "Donation (Manual selection)"
	elif [[ "$thisProfile" == "-1" ]]; then
		echo "Automatic"
	else
		Q="SELECT name FROM profile WHERE pk_profile=$thisProfile;"
		R=$(RunSQL "$Q")
		echo $(Field 1 "$R")
	fi

}

GetProfileName() {
	local thisMachine=$1

	local thisProfile=$(GetCurrentProfile $thisMachine)
	echo $(GenProfileName $thisProfile)
	
}

NotImplemented()
{
	clear
	ShowHeader
	echo "This feature has not been implemented yet!"
	sleep 3
}
DisplayMenu()
{	
	local fieldArray="$1"

	for item in $fieldArray; do
	num=$(Field 2 "$item")
	listing=$(Field 3 "$item")
	echo -e  "$num) $listing"
	done


}
#var=$(GetMenuSelection "$M" "default pk")
GetMenuSelection()
{
	local fieldArray=$1
	local default=$2

	local item
	local pk
	local select_id
	local default_pk

	# We need to translate the default (which is a PK) to a selection ID
	if [[ "$default" ]]; then
		for item in $fieldArray; do
			pk=$(Field 1 "$item")
			selection_id=$(Field 2 "$item")
			if [[ "$pk" == "$default" ]]; then
				default_pk="$selection_id"
				break	
			fi
		done
	fi
	

	read -e -i "$default_pk" chosen

	for item in $fieldArray; do
		choice=$(Field 2 "$item")
		if [[ "$chosen" == "$choice" ]]; then
			echo $(Field 1 "$item")
			return 0
		fi
	done
	echo "ERROR"
}

# GetPrimaryKeySelection var "$Q" "$E" "default value"
GetPrimaryKeySelection()
{
	local _ret=$1
	local Q=$2
	local msg=$3
	local default=$4
	local fieldArray=$5	# You can pass in a pre-populated field array to add on to


	local PK	#Primary key of name (not shown in menu)
	local Name	#Name displayed in menu
	local M=""	#Menu FieldArray
	local i=0		#Index count


	if [[ "$fieldArray" ]]; then
		for thisRecord in $fieldArray; do
			
			PK=$(Field 1 "$thisRecord")
			index=$(Field 2 "$thisRecord")
			Name=$(Field 3 "$thisRecord")
			M=$M$(FieldArrayAdd "$PK	$index	$Name")
		done
		i=$index
	fi

	

	UseDB "smartcoin.db"
	R=$(RunSQL "$Q")
	for Row in $R; do
		let i++
		PK=$(Field 1 "$Row")
		Name=$(Field 2 "$Row")
		M=$M$(FieldArrayAdd "$PK	$i	$Name")
	done
	DisplayMenu "$M"
	echo "$msg"
	PK="ERROR"
	until [[ "$PK" != "ERROR" ]]; do
		PK=$(GetMenuSelection "$M" "$default")
		if [[ "$PK" == "ERROR" ]]; then
			echo "Invalid selection. Please try again."
		fi
	done
	eval $_ret="'$PK'"
}
#GetYesNoSelection var "$E" "default value"
GetYesNoSelection() {                                                                                
	resp="-1"  
	local available

	local _retyn=$1
	local msg=$2
	local default=$3
	
	if [[ "$default" == "1" ]]; then
		default="y"
	elif [[  "$default" == "0" ]]; then
		default="n"
	else
		default=""
	fi

	echo -e "$msg"                                             
	until [[ "$resp" != "-1" ]]; do                                         
		read -e -i "$default" available                                                  
		                                                        
		available=`echo $available | tr '[A-Z]' '[a-z]'`                
		if [[ "$available" == "y" ]]; then                              
			resp=1                                                
		elif [[ "$available" == "n" ]]; then                            
			resp=0                                                
		else                                                            
			echo "Invalid response!"                                
		fi                                                              
	done    
	
	eval $_retyn="'$resp'"
}
DisplayError()
{
	msg=$1
	dly=$2
	clear
	ShowHeader

	echo "ERROR! $msg"
	sleep $dly
	#test
}

AddEditDelete()
{
	# TODO: Add view option
	msg=$1
	clear
	ShowHeader

	echo "Would you like to (A)dd, (E)dit or (D)elete $msg?"
	echo "(X) to exit back to the main menu."
#test
}
GetAEDSelection()
{
	# TODO: Add view option
	read chosen
	chosen=`echo $chosen | tr '[A-Z]' '[a-z]'`
	case "$chosen" in
	a)
		echo "ADD"
		;;
	e)
		echo "EDIT"
		;;
	d)
		echo "DELETE"
		;;
  x)
    echo "EXIT"
    ;;
	*)
		echo "ERROR"
		;;	
	esac
}

# ### END UI HELPER FUNCTIONS ###

# Multi-Machine functions

# Launch a remote command over SSH on remote machines, or locally on localhost
# NOTE: To exit a persistent connection:
# ssh -i ~/.ssh/id_rsa.smartcoin -O exit -S /tmp/ssh.control user@host
# NOTE2:  If a command ends in 2>/dev/null, the command must be wrapped in single quotes or it fails!
Launch()
{
	local machineInfo=$1
	local cmd=$2
	local no_block=$3
	local ssh_flags=$4
	local machine=$(Field 1 "$machineInfo")

	local res
	local retVal

	if [[ "$machine" == "1" ]]; then
		# This is the localhost, run command normally!
		if [[ -z "$no_block" ]]; then
			res=$(eval "$cmd")
			retVal=$?
		else
			eval "$cmd"
			retVal=$?
		fi
	else
		# This is a remote machine!
		local user=$(Field 4 "$machineInfo")
		local server=$(Field 3 "$machineInfo")
		local port=$(Field 5 "$machineInfo")

		# See if the persistent connection is available
		res=$(ssh -q -p $port -i ~/.ssh/id_rsa.smartcoin -O check -S /tmp/smartcoin.ssh_connection.$machine $user@$server  2>&1 /dev/null) 

		if [[ $? -ne 0 ]]; then
			# The connection does not exist!  Lets create it!
			Log "Creating persistent ssh connection to machine $machine" 1
			Log "DEBUG: $cmd"
			
			ssh -q -n -p $port -i ~/.ssh/id_rsa.smartcoin -o BatchMode=yes -NfM -S /tmp/smartcoin.ssh_connection.$machine $user@$server
		fi
 
		if [[ -z "$no_block" ]]; then
			res=$(eval "ssh $ssh_flags -q -p $port -i ~/.ssh/id_rsa.smartcoin -o BatchMode=yes -S /tmp/smartcoin.ssh_connection.$machine $user@$server" "$cmd" | tr -d '\r')
			retVal=$?
		else
			eval "ssh $ssh_flags -q -p $port -i ~/.ssh/id_rsa.smartcoin -o BatchMode=yes -S /tmp/smartcoin.ssh_connection.$machine $user@$server" "$cmd" | tr -d '\r'
			retVal=$?
		fi
	fi
	if [[ -z "$no_block" ]]; then
		
		echo "$res"
	fi
	return $retVal
}


AutoDetect()
{
	local thisMachine=$1
	Q="SELECT pk_machine,name,server,username,ssh_port FROM machine WHERE pk_machine='$thisMachine';"
	R=$(RunSQL "$Q")
	local machineName=$(Field 2 "$R")
	local machineServer=$(Field 3 "$R")
	local machineUser=$(Field 4 "$R")
	local machinePort=$(Field 5 "$R")
	local machineInfo=$R


	clear
	ShowHeader
	echo ""
	echo "Smartcoin can attempt to auto detect installed software on this machine."
	echo "You will be prompted for the root password of this machine when needed."
	E="Do you wish to continue? (y/n)"
	GetYesNoSelection getPermission "$E"
	echo ""

	if [[ "$getPermission" == "0" ]]; then
		return
	fi
	
	Log "Running AutoDetection on machine $machineName..." 1

	
	# Run updatedb
	echo ""
	Log "Asking user if they wish to run ubdatedb."
	E="In order for smartcoin to try to reliably determine the location of installed miners and the AMD/ATI SDK for you, "
	E=$E"the linux command 'updatedb' should be run.  This can take quite a long time on machines with large filesystems."
	E=$E"Note: root password is required and you will be prompted for it."
	echo "$E"
	E="Do you want to attempt to run 'updatedb' now? (y)es or (n)o?"
	GetYesNoSelection runupdatedb "$E" "1"
	echo ""

	if [[ "$runupdatedb" == "1" ]]; then
		Log "Running 'updatedb'... Please be patient" 1
		Launch $machineInfo "sudo updatedb" "1" "-t -t"
		echo ""
	fi


	# Autodetect cards
	E="Would you like smartcoin to attempt to auto-detect installed GPUs on this machine? (y)es or (n)o?"
	GetYesNoSelection detectCards "$E" "y"

	if [[ "$detectCards" == "1" ]]; then
		echo "Detecting available local devices. Please be patient..."

		if [[ "$thisMachine" == "1" ]]; then
			D=$($CUR_LOCATION/smartcoin_devices.py)
		else
			# Copy the detection script over to the remote /tmp directory, then run it!
			$(scp -i ~/.ssh/id_rsa.smartcoin -P $machinePort $CUR_LOCATION/smartcoin_devices.py $machineUser@$machineServer:/tmp/smartcoin_devices.py)
			D=$(Launch $machineInfo "/tmp/smartcoin_devices.py")
		fi

		E=""
		D=$(Field_Prepare "$D")
		for device in $D; do
			id=$(Field 1 "$device")
			devName=$(Field 2 "$device")
			devDisable=$(Field 3 "$device")
			devType=$(Field 4 "$device")

			# TODO: deal with hard coded auto_allow?
			Q="INSERT INTO device (fk_machine,name,device,auto_allow,type,disabled) VALUES ('$thisMachine','$devName','$id','1','$devType','$devDisable');"
			RunSQL "$Q"
		done
		echo "done."
		echo ""
		echo "These are the locally installed devices that I have found: "
		echo "Name	Device #"
		echo "----	--------"

		for device in $D; do
			devID=$(Field 1 "$device")
			devName=$(Field 2 "$device")
			echo "$devName	$devID"	
		done
		echo ""
		echo "If these don't look correct, please fix them manually via the control tab under option 9) Configure Devices."
		echo ""
	fi



	# Autodetect miners
	echo "Auto detecting local installed miners..."
	E="Would you like smartcoin to attempt to auto-detect installed miners? (y)es or (n)o?"
	GetYesNoSelection detectMiners "$E" "y"
	echo ""

	if [[ "$detectMiners" == "1" ]]; then
		#detect phoenix install location
		phoenixMiner=$(Launch $machineInfo "locate phoenix.py | grep -vi svn")

		if [[ "$phoenixMiner" != "" ]]; then
			Log "Found phoenix miner installed on local system" 1
			M=""
			i=0


			for thisLocation in $phoenixMiner; do
				let i++
				M=$M$(FieldArrayAdd "$i	$i	$thisLocation")
			done
			DisplayMenu "$M"

			echo "Select the phoenix installation from the list above"
			selected="ERROR"
			until [[ "$selected" != "ERROR" ]]; do
				selected=$(GetMenuSelection "$M")
				if [[ "$selected" == "ERROR" ]]; then
					echo "Invalid selection. Please try again."
				fi
			done

			i=0
			ret=""
			for thisLocation in $phoenixMiner; do
				let i++
				ret=$thisLocation
				if [[ "$selected" == "$i" ]]; then
			  		break
				fi
			done

			thisLocation=$thisLocation
			thisLocation=${thisLocation%"phoenix.py"}
			
			Q="INSERT INTO miner (fk_machine, name,launch,path,default_miner,disabled) VALUES ('$thisMachine','phoenix','python <#path#>/phoenix.py -v -u http://<#user#>:<#pass#>@<#server#>:<#port#>/ device=<#device#> worksize=128 vectors aggression=11 bfi_int fastloop=false -k phatk','$thisLocation',0,0);"
			RunSQL "$Q"
		fi

		# Detect poclbm install location
		poclbmMiner=$(Launch $machineInfo "locate poclbm.py | grep -vi svn")
		poclbmMiner=${poclbmMiner%"poclbm.py"}
		if [[ "$poclbmMiner" != "" ]]; then
			Log "Found poclbm miner installed on local system" 1
			Q="INSERT INTO miner (fk_machine,name,launch,path,default_miner,disabled) VALUES ('$thisMachine','poclbm','python poclbm.py -d <#device#> --host http://<#server#> --port <#port#> --user <#user#> --pass <#pass#> -v -w 128 -f0','$poclbmMiner',0,0);"
			RunSQL "$Q"
		fi


		# Detect cgminer install location
		# TODO: Needs fixed, its a bit of an ugly hack for now
		cgminer=$(Launch $machineInfo "locate -r 'cgminer/cgminer$' -n1")
		cgminer=${cgminer%"cgminer"}
		if [[ "$cgminer" != "" ]]; then
			Log "Found cgminer miner installed on local system" 1
			Q="INSERT INTO miner (fk_machine,name,launch,path,default_miner,disabled) VALUES ('$thisMachine','cgminer','<#path#>cgminer -a 4way -g 2 -d <#device#> -o http://<#server#>:<#port#> -u <#user#> -p <#pass#> -I 14','$cgminer/',0,0);"
			RunSQL "$Q"
		fi

		# Set the default miner
		echo ""
		Q="SELECT pk_miner,name FROM miner WHERE fk_machine='$thisMachine' ORDER BY pk_miner ASC;"
		E="Which miner listed above do you want to be the default miner for this machine?"
		GetPrimaryKeySelection thisMiner "$Q" "$E"
		Q="UPDATE miner SET default_miner='1' WHERE pk_miner=$thisMiner;"
		RunSQL "$Q"
		Log "Default miner set to $thisMiner for this machine."
	fi

	# Set the current profile!
	# Defaults to Automatic profile until the user gets one set up
	Q="DELETE from current_profile WHERE fk_machine='$thisMachine';"	#A little paranoid, but why not...
	RunSQL "$Q"
	Q="INSERT INTO current_profile (fk_machine,fk_profile) VALUES ('$thisMachine','-1');"
	RunSQL "$Q"
	Log "Current profile set to Automatic for this machine"
	echo ""


	# AMD/ATI SDK LOCATION
	local amd_sdk_location
	E="Do you want to attempt to locate the SDK path automatically? (y)es or (n)o?"
	GetYesNoSelection autoDetectSDKLocation "$E" "y"
	echo ""

	if [[ "$autoDetectSDKLocation" == "1" ]]; then

		Log "	User chose to autodetect"
		echo "Please be patient, this may take a few minutes..."
		if [[ "$thisMachine" == "1" ]]; then
			amd_sdk_location=$($CUR_LOCATION/smartcoin_sdk_location.sh)
		else
			# Copy the detection script over to the remote /tmp directory, then run it!
			res=$(scp -i ~/.ssh/id_rsa.smartcoin -P $machinePort $CUR_LOCATION/smartcoin_sdk_location.sh $machineUser@$machineServer:/tmp/smartcoin_sdk_location.sh)
			amd_sdk_location=$(Launch $machineInfo "/tmp/smartcoin_sdk_location.sh")
		fi
		echo "Please make sure the path below is correct, and change if necessary (NOTE: There may be more than on path pre-filled in for you. Move the cursor and backspace over the path(s) that you don't want).:"
		echo ""

	else
		Log "User chose NOT to autodetect"
		echo "Enter the AMD/ATI SDK path below:"
		echo ""
	fi
	read -e -i "$amd_sdk_location" location

	Q="UPDATE settings SET value='$location' WHERE data='AMD_SDK_location' AND fk_machine='$thisMachine';"
	RunSQL "$Q"
	Log "AMD/ATI SDK location set to $location"
	echo ""

	echo ""

	Log "Autodetect routine finished."
}


#------------------------
#SETTINGS TABLE FUNCTIONS
#------------------------
# These functions will make sure that:
# A) The required settings exist in the database
# B) That there are no duplicate settings
# C) The description,information and order fields stay up to date
#
# The GeneralSettings and MachineSettings for each machine should be called each time smartcoin is started.
# Additionally, the GeneralSettings and MachineSettings for localhost should be used in the installer, and values "UPDATED" from the install script.
# Likewise, the MachineSettings should be used when a new machine is added to add their settings to the database.
EnsureSettings() {
	# TODO: Update to correct description and information fields if they differ!
	local machine=$1
	local order=$2
	local data=$3
	local description=$4
	local information=$5

	Q="SELECT COUNT(*) FROM settings WHERE data='$data' AND fk_machine='$machine';"
	R=$(RunSQL "$Q")
	entry=$(Field 1 "$R")
	if [[ "$entry" -gt "1" ]]; then
		Q="DELETE FROM settings WHERE data='$data' AND fk_machine='$machine';"
		RunSQL "$Q"
	fi
	if [[ "$entry" -ne "1" ]]; then
		Q="INSERT INTO settings (fk_machine,data,value,description,information,display_order) VALUES ('$machine','$data','','$description','$information','$order');"
		RunSQL "$Q"
	else
		# Make sure that the descrition, information and order fields are up to date
		Q="SELECT pk_settings,description,information,display_order FROM settings WHERE data='$data' AND fk_machine='$machine';"
		R=$(RunSQL "$Q")
		local pk=$(Field 1 "$R")
		local thisDescription=$(Field 2 "$R")
		local thisInformation=$(Field 3 "$R")
		local thisOrder=$(Field 4 "$R")

		if [[ "$description" != "$thisDescription" ]]; then
			Q="UPDATE settings SET description='$description' WHERE pk_settings='$pk';"
			RunSQL "$Q"
		fi
		if [[ "$information" != "$thisInformation" ]]; then
			Q="UPDATE settings SET information='$information' WHERE pk_settings='$pk';"
			RunSQL "$Q"
		fi
		if [[ "$order" != "$thisOrder" ]]; then
			Q="UPDATE settings SET display_order='$order' WHERE pk_settings='$pk';"
			RunSQL "$Q"
		fi
	fi

}


GeneralSettings() {
	local data
	local description
	local information
	
	Log "Verifying integrity of general settings..." 1

	# Development Branch
	data="dev_branch"
	description="Development branch to follow (stable/experimental)"
	information="The experimental branch gets updated more frequently, but increases your risk of running into bugs in newer features. The stable branch is updated less often, but with features that have already been tested by users in the experimental branch."
	EnsureSettings "0" "1" "$data" "$description" "$information"

	# Email Address
	data="email"
	description="Administrator email address"
	information="Though currently not used, eventually smartcoin will email you when events such as lockups, failovers, etc occur."
	EnsureSettings "0" "2" "$data" "$description" "$information"

	# Format String
	data="format"
	description="Miner output format string"
	information="Formats the output on the status screen. The special tags <#hashrate#>, <#accepted#>, <#rejected#> and <#rejected_percent#> can be used to build your own output format.\n The default format string is:\n[<#hashrate#> MHash/sec] [<#accepted#> Accepted] [<#rejected#> Rejected] [<#rejected_percent#>% Rejected]"
	EnsureSettings "0" "3" "$data" "$description" "$information"

	# Donation Minutes
	data="donation_time"
	description="Hashpower donation minutes per day"
	information="Please consider donating your hashes to the author of smartcoin for at least 30 minutes per day.  I have literally hundreds of hours of my time into making this a useful and stable platform to make running a mining operation easier, and with as little downtime as possible. A value of 0 will disable auto-donation."
	EnsureSettings "0" "4" "$data" "$description" "$information"

	# Donation start time
	# Email Address
	data="donation_start"
	description="Time to start hashpower donation each day"
	information="Please enter the time to start your auto-donations each day. The time is in 24-hour format, without a colon. For example, enter 100 for 1:00 AM, 1200 for noon, 1835 for 6:35 PM, etc."
	EnsureSettings "0" "5" "$data" "$description" "$information"
	return
}
GeneralDefaults() {
	# Set up the default general settings
	Q="UPDATE settings SET value='stable' WHERE data='dev_branch' AND fk_machine='0';"
	RunSQL "$Q"
	
	Q="UPDATE settings SET value='' WHERE data='email' AND fk_machine='0';"
	RunSQL "$Q"

	Q="UPDATE settings SET value='[<#hashrate#> MHash/sec] [<#accepted#> Accepted] [<#rejected#> Rejected] [<#rejected_percent#>% Rejected]' WHERE data='format' AND fk_machine='0';"
	RunSQL "$Q"
	
	Q="UPDATE settings SET value='0' WHERE data='donation_start' AND fk_machine='0';"
	RunSQL "$Q"

	Q="UPDATE settings SET value='200' WHERE data='donation_time' AND fk_machine='0';"
	RunSQL "$Q"
}

MachineSettings() {
	local thisMachine=$1
	local data
	local description
	local information

	if [[ -z "$thisMachine" ]]; then
		# No machine selected, update settings on all machines!
		Q="SELECT pk_machine FROM machine;"
		R=$(RunSQL "$Q")

		for row in $R; do
			local nextMachine=$(Field 1 "$row")
			thisMachine=$thisMachine$nextMachine
			thisMachine=$thisMachine" "
		done
	fi

	local machine
	for machine in $thisMachine; do
		Log "Verifying integrity of settings for machine $machine..." 1
		# AMD/ATI SDK location
		data="AMD_SDK_location"
		description="AMD/ATI SDK installation location"
		information="The AMD/ATI SDK is required by ATI GPUs to mine for bitcoins. It may be installed in many places, but it can commonly be found in ~/ and /opt."
		EnsureSettings "$machine" "1" "$data" "$description" "$information"

		# Failover Threshold
		data="failover_threshold"
		description="Failover Threshold"
		information="Measured in iterations of the status screen logic loop"
		EnsureSettings "$machine" "2" "$data" "$description" "$information"

		# Failover Rejection
		data="failover_rejection"
		description="Failover on rejection % higher than"
		information="Measured in iterations of the status screen logic loop"
		EnsureSettings "$machine" "3" "$data" "$description" "$information"	
	
		# Lockup Threshold
		data="lockup_threshold"
		description="Lockup Threshold"
		information="Measured in iterations of the status screen logic loop"
		EnsureSettings "$machine" "4" "$data" "$description" "$information"

		# Loop Delay
		data="loop_delay"
		description="Status screen loop delay"
		information="Higher values, measured in seconds, make the status screen loop run slower."
		EnsureSettings "$machine" "5" "$data" "$description" "$information"

		# Extra SSH flags
		data="ssh_flags"
		description="SSH Connection Flags"
		information="These are extra flags to pass to the internal SSH connection commands.  If smartcoin is having connection problems with this remote machine, you way want to try the -t flag, or even the -t -t flags.  Note that this has no effect on the localhost machine."
		EnsureSettings "$machine" "6" "$data" "$description" "$information"

	done
}

MachineDefaults() {
	local thisMachine="$1"


	Log "Setting default values for machine $thisMachine"
	# Fill in default values!
	Log "Populating database with default values..." 1
	Q="UPDATE settings SET value='5' WHERE data='loop_delay' AND fk_machine='$thisMachine';"
	RunSQL "$Q"

	Q="UPDATE settings SET value='50' WHERE data='lockup_threshold' AND fk_machine='$thisMachine';"
	RunSQL "$Q"

	Q="UPDATE settings SET value='10' WHERE data='failover_threshold' AND fk_machine='$thisMachine';"
	RunSQL "$Q"
	Q="UPDATE settings SET value='15' WHERE data='failover_rejection' AND fk_machine='$thisMachine';"
	RunSQL "$Q"	


}

EnsurePools() {
	# TODO: Write route which syncs pools so that I can add new ones without patching

	return
}

# Reload the miners after changing options
Reload()
{
	local thisMachine=$1
	local msg=$2

	if [[ "$thisMachine" == "0" ]]; then
		thisMachine=""
		# No machine selected, update settings on all machines!
		Q="SELECT pk_machine FROM machine WHERE disabled=0;"
		R=$(RunSQL "$Q")

		for row in $R; do
			local nextMachine=$(Field 1 "$row")
			thisMachine=$thisMachine$nextMachine
			thisMachine=$thisMachine" "
		done
	fi

	local machine
	for machine in $thisMachine; do
		echo "$msg" > /tmp/smartcoin.reload.$machine
	done
}

# LaunchInstance
# Made to replace the smartcoin_launcher.sh script, and be multi-machine aware!
LaunchInstance() {
	local thisMachineInfo=$1
	local thisDevice=$2
	local thisMiner=$3
	local thisWorker=$4
	local thisKey=$5
	local launcherLocation=$6
	local thisMachine=$(Field 1 "$thisMachineInfo")

	UseDB "smartcoin.db"

	# Get additional information on the device
	Q="SELECT name,device from device WHERE pk_device=$thisDevice;"
	R2=$(RunSQL "$Q")
	local deviceID=$(Field 2 "$R2")
	# Make a +1 offset of the device ID so that launch strings can compensate for miners which add CPU as device #0
	local deviceIDInc=$((deviceID+1))

	# Get the miner information
	Q="SELECT name, path,launch FROM miner WHERE pk_miner=$thisMiner;"
	R2=$(RunSQL "$Q")
	local minerName=$(Field 1 "$R2")
	local minerPath=$(Field 2 "$R2")
	local minerLaunch=$(Field 3 "$R2")

	R2=$(GetWorkerInfo "$thisWorker")
	workerServer=$(Field 3 "$R2")
	workerPort=$(Field 4 "$R2")
	workerUser=$(Field 1 "$R2")
	workerPass=$(Field 2 "$R2")

	#Make launch string
	minerLaunch=${minerLaunch//<#user#>/$workerUser}
	minerLaunch=${minerLaunch//<#pass#>/$workerPass}
	minerLaunch=${minerLaunch//<#server#>/$workerServer}
	minerLaunch=${minerLaunch//<#port#>/$workerPort}
	minerLaunch=${minerLaunch//<#device#>/$deviceID}
	minerLaunch=${minerLaunch//<#device+1#>/$deviceIDInc}
	minerLaunch=${minerLaunch//<#path#>/$minerPath}

	Log "Launching miner with launch string: $minerLaunch"
	# Lets fix up our $LD_LIBRARY_PATH
	Q="SELECT value FROM settings WHERE data='AMD_SDK_location' AND fk_machine='$thisMachine';"
	R=$(RunSQL "$Q")
	amd_sdk_location=$(Field 1 "$R")

	

	local cmd="screen  -d -r \"$minerSession\" -X screen -t \"$key\" \"$launcherLocation\"/smartcoin_launcher.sh \"$minerPath\" \"$minerLaunch\" \"$amd_sdk_location\""
	if [[ "$thisMachine" == "1" ]]; then
		local cmd="screen  -d -r \"$minerSession\" -X screen -t \"$key\" \"$launcherLocation\"/smartcoin_launcher.sh \"$minerPath\" \"$minerLaunch\" \"$amd_sdk_location\""
		Launch $thisMachineInfo "$cmd"
		# The line below works, and was used to build the Launch() version!
		#screen  -d -r "$minerSession" -X screen -t "$key" "$CUR_LOCATION"/smartcoin_launcher.sh "$minerPath" "$minerLaunch" "$amd_sdk_location"	
	else
		# TODO: Make a global field array at global define time so we don't have to query so often!
		#Q="SELECT name,server,username,ssh_port FROM machine WHERE pk_machine=$machine;"
		#R=$(RunSQL "$Q")
		#local user=$(Field 3 "$R")
		#local server=$(Field 2 "$R")
		#local port=$(Field 4 "$R")
		#ssh -q -t -t -p $port -i ~/.ssh/id_rsa.smartcoin -o BatchMode=yes -S /tmp/smartcoin.ssh_connection.$machine $user@$server $cmd
		Launch $thisMachineInfo "\"screen  -d -r $minerSession -X screen -t $key $launcherLocation/smartcoin_launcher.sh $minerPath '$minerLaunch' $amd_sdk_location\"" 1
	fi
}

startMiners() {
	local thisMachine=$1
	if [[ -z "$thisMachine" ]]; then
		# No machine selected, update settings on all machines!
		Q="SELECT pk_machine FROM machine WHERE disabled=0;"
		R=$(RunSQL "$Q")

		for row in $R; do
			local nextMachine=$(Field 1 "$row")
			thisMachine=$thisMachine$nextMachine
			thisMachine=$thisMachine" "
		done
	fi


	local launcherLocation
	local machine
	for machine in $thisMachine; do
		Log "Starting miners for machine $machine..."

		DeleteTemporaryFiles $machine

		Q="SELECT pk_machine,name,server,username,ssh_port FROM machine WHERE pk_machine='$machine';"
		R=$(RunSQL "$Q")
		local machineName=$(Field 2 "$R")
		local machineServer=$(Field 3 "$R")
		local machineUser=$(Field 4 "$R")
		local machinePort=$(Field 5 "$R")

		local machineInfo="$R"

		if [[ "$machine" != "1" ]]; then
			# Copy the launch script over to the remote machine's /tmp directory!
			Log "Copying remote launch script to machine $machine..." 1
			$(scp -i ~/.ssh/id_rsa.smartcoin -p -P "$machinePort" "$CUR_LOCATION"/smartcoin_launcher.sh "$machineUser"@"$machineServer":/tmp/smartcoin_launcher.sh)
	
			launcherLocation="/tmp"
		else		
			launcherLocation=$CUR_LOCATION
		fi

		local FA=$(GenCurrentProfile "$machine")

		# Lets start up the miner session with a dummy window, so that we can set options,
		# such as zombie mode	
		#if [[ "$machine" != "1" ]]; then
		#	Launch "$machine" "DISPLAY=:0 xhost +"
		#fi
		Launch "$machineInfo" "screen -c /dev/null -dmS '$minerSession' -t miner-dummy"
		
		sleep 2
		Launch "$machineInfo" "screen -r $minerSession -X zombie ko"
		Launch "$machineInfo" "screen -r $minerSession -X chdir"
		Launch "$machineInfo" "screen -r $minerSession -X hardstatus on"
		Launch "$machineInfo" "screen -r $minerSession -X hardstatus alwayslastline"
		if [[ "$machine" == "1" ]]; then
			Launch "$machineInfo" "screen -r $minerSession -X hardstatus string '%{= kG}[ %{G}%H %{g}][%= %{= kw}%?%-Lw%?%{r}(%{W}%n*%f%t%?(%u)%?%{r})%{w}%?%+Lw%?%?%= %{g}][%{B} %m/%d/%y %{W}%c %{g}]'"
		else
			Launch "$machineInfo" "\"screen -r $minerSession -X hardstatus string '%{= kG}[ %{G}%H %{g}][%= %{= kw}%?%-Lw%?%{r}(%{W}%n*%f%t%?(%u)%?%{r})%{w}%?%+Lw%?%?%= %{g}][%{B} %m/%d/%y %{W}%c %{g}]'\""
		fi

		# Start all of the miner windows
		for row in $FA; do
			local key=$(Field 2 "$row")
			local pk_device=$(Field 3 "$row")
			local pk_miner=$(Field 4 "$row")
			local pk_worker=$(Field 5 "$row")
			Log "Starting miner $key!" 1
			#local cmd="$CUR_LOCATION/smartcoin_launcher.sh $thisMachine $pk_device $pk_miner $pk_worker"
			LaunchInstance "$machineInfo" "$pk_device" "$pk_miner" "$pk_worker" "$key" "$launcherLocation"
			#Launch $machine "screen  -d -r $minerSession -X screen -t $key $cmd"
		done

		# The dummy window has served its purpose, lets get rid of it so we don't confuse the user with a blank window!
		Launch "$machineInfo" "screen -r $minerSession -p miner-dummy -X kill"
	done
}


killMiners() {
	thisMachine=$1

	if [[ -z "$thisMachine" ]]; then
		# No machine selected, update settings on all machines!
		Q="SELECT pk_machine FROM machine WHERE disabled=0;"
		R=$(RunSQL "$Q")

		for row in $R; do
			local nextMachine=$(Field 1 "$row")
			thisMachine=$thisMachine$nextMachine
			thisMachine=$thisMachine" "
		done
	fi

	local machine
	for machine in $thisMachine; do
		Q="SELECT pk_machine,name,server,username,ssh_port FROM machine WHERE pk_machine=$machine;"
		R=$(RunSQL "$Q")
		local server=$(Field 3 "$R")
		local user=$(Field 4 "$R")
		local port=$(Field 5 "$R")
		local machineInfo="$R"

		Log "Killing Miners for machine $machine...."
		Launch "$machineInfo" "screen -d -r $minerSession -X quit" 
		if [[ "$machine" != "1" ]]; then
			# TODO: Work against global/passed-in field array instead of live querying?
			Log "Closing persistent SSH connection to machine $machine"
			
			# Kill the persistent connection!
			ssh -i ~/.ssh/id_rsa.smartcoin -O exit -S /tmp/smartcoin.ssh_connection.$machine $user@$server
		fi
	done
	#sleep 2
}


# Lets fix up our $LD_LIBRARY_PATH
Q="SELECT value FROM settings WHERE data='AMD_SDK_location';"
R=$(RunSQL "$Q")
amd_sdk_location=$(Field 1 "$R")


if [[ "$amd_sdk_location" ]]; then
	export LD_LIBRARY_PATH=$amd_sdk_location:$LD_LIBRARY_PATH
fi
	


