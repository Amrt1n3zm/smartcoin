#!/bin/bash
if [[ $( dirname "$0" ) == "/usr/bin" ]]; then
	CUR_LOCATION=$(dirname $(readlink -f $( dirname "$0" )/smartcoin))
else
	CUR_LOCATION="$( cd "$( dirname "$0" )" && pwd )"
fi
. $CUR_LOCATION/smartcoin_ops.sh


# Monitoring functions perform the following:
# 1) Load in /tmp/smartcoin-$key via grep looking for specific strings
# 2) work with $hashes, $rejected and $accepted global variables
# 3) Create an $output variable with the line to output
# 4) Hashing  units are handled internally as MHash.  Conversion must be done on the fly for other bases


# PHOENIX monitoring
Monitor_phoenix()
{
	local machineInfo=$1

	oldCmd=$(Launch $machineInfo "grep 'hash' '/tmp/smartcoin-$key' 2> /dev/null | tail -n 1")
	Launch $machineInfo "screen -d -r $minerSession -p $key -X hardcopy '/tmp/smartcoin-$key'"
	cmd=$(Launch $machineInfo "grep 'hash' '/tmp/smartcoin-$key' 2> /dev/null | tail -n 1")

	#failure=$(Launch $machineInfo "grep \"=== Command\" \"/tmp/smartcoin-$key\" | tail -n 1")
	
	if [[ "$cmd" == *Ghash* ]]; then
		hashUnits="Ghash"
	elif [[ "$cmd" == *Mhash* ]]; then
		hashUnits="Mhash"
	elif [[ "$cmd" == *khash* ]]; then
		hashUnits="khash"

	fi  

	


	if [ "$cmd" ]; then
		hashes=`echo $cmd | sed -e 's/[^0-9. ]*//g' -e  's/ \+/ /g' | cut -d' ' -f1`
		accepted=`echo $cmd | sed -e 's/[^0-9. ]*//g' -e  's/ \+/ /g' | cut -d' ' -f2`
		rejected=`echo $cmd | sed -e 's/[^0-9. ]*//g' -e  's/ \+/ /g' | cut -d' ' -f3`
	fi

	# Convert into MHash if needed
	case $hashUnits in
	Ghash)
		hashes=`echo "scale=2; $hashes*1000" | bc -l 2> /dev/null`
		;;
	Mhash)
		# We are already scaled to MHash, do nothing!
		hashes=$hashes
		;;
	khash)
		hashes=`echo "scale=2; $hashes/1000" | bc -l 2> /dev/null`
		;;
	esac
	
	local percentRejected=`echo "scale=3;a=($rejected*100) ; b=$accepted; c=a/b; print c" | bc -l 2> /dev/null`
	if [ -z "$percentRejected" ]; then
		percentRejected="0.00"
	fi

	output=$(FormatOutput $hashes $accepted $rejected $percentRejected)

	if [[ -n "$failure" ]]; then
			output="\e[00;31m<<<FAIL>>\e[00m"
			let profileFailed++
			skipLockupCheck="1"
	
	elif [[ -z "$cmd" ]]; then
		output="\e[00;31m<<<IDLE>>>\e[00m"	
	else
		if [[ "$hashes" == "0" ]]; then
			# Is it safe to say the profile is down?
			output="\e[00;31m<<<DOWN>>>\e[00m"
			let profileFailed++
			skipLockupCheck="1"
		fi
	fi

}

Monitor_poclbm()
{
	local machineInfo=$1

	oldCmd=$(Launch $machineInfo "grep 'MH/s' '/tmp/smartcoin-$key' 2> /dev/null | tail -n 1")
	Launch $machineInfo "screen -d -r $minerSession -p $key -X hardcopy '/tmp/smartcoin-$key'"
	cmd=$(Launch $machineInfo "grep 'MH/s' '/tmp/smartcoin-$key' 2> /dev/null | tail -n 1")

	#failure=$(Launch $machineInfo "grep '=== Command' '/tmp/smartcoin-$key' | tail -n 1")
	
	if [ "$cmd" ]; then
		hashes=`echo $cmd |cut -d' ' -f2 | sed -e 's/[^0-9. ]*//g' -e  's/ \+/ /g'`
		local rej_acc=`echo $cmd | cut -d' ' -f7`
		accepted=`echo $rej_acc | cut -d'/' -f2`
		rejected=`echo $rej_acc | cut -d'/' -f1`
	fi

	local percentRejected=`echo "scale=3;a=($rejected*100) ; b=$accepted; c=a/b; print c" | bc -l 2> /dev/null`
	if [ -z "$percentRejected" ]; then
		percentRejected="0.00"
	fi

	output=$(FormatOutput $hashes $accepted $rejected $percentRejected)

	if [[ -n "$failure" ]]; then
			output="\e[00;31m<<<FAIL>>\e[00m"
			let profileFailed++
			skipLockupCheck="1"
	
	elif [[ -z "$cmd" ]]; then
		output="\e[00;31m<<<IDLE>>>\e[00m"	
	else
		if [[ "$hashes" == "0" ]]; then
			# Is it safe to say the profile is down?
			output="\e[00;31m<<<DOWN>>>\e[00m"
			let profileFailed++
			skipLockupCheck="1"
		fi
	fi
}

Monitor_cgminer()
{
	local machineInfo=$1

	oldCmd=$(Launch $machineInfo "grep '(5s)' '/tmp/smartcoin-$key' 2> /dev/null | tail -n 1")
	Launch $machineInfo "screen -d -r $minerSession -p $key -X hardcopy '/tmp/smartcoin-$key'"
	cmd=$(Launch $machineInfo "grep '(5s)' '/tmp/smartcoin-$key' 2> /dev/null | tail -n 1")

	#failure=$(Launch $machineInfo "grep '=== Command' '/tmp/smartcoin-$key' | tail -n 1")

	if [[ "$cmd" == *Gh/s* ]]; then
		hashUnits="Ghash"
	elif [[ "$cmd" == *Mh/s* ]]; then
		hashUnits="Mhash"
	elif [[ "$cmd" == *kh/s* ]]; then
		hashUnits="khash"
	fi  

	if [ "$cmd" ]; then
		hashes=`echo $cmd | sed -e 's/[^0-9. ]*//g' -e  's/ \+/ /g' | cut -d' ' -f2`
		accepted=`echo $cmd | sed -e 's/[^0-9. ]*//g' -e  's/ \+/ /g' | cut -d' ' -f4`
		rejected=`echo $cmd | sed -e 's/[^0-9. ]*//g' -e  's/ \+/ /g' | cut -d' ' -f5`
	fi

	# Convert into MHash if needed
	case $hashUnits in
	Ghash)
		hashes=`echo "scale=2; $hashes*1000" | bc -l 2> /dev/null`
		;;
	Mhash)
		# We are already scaled to MHash, do nothing!
		hashes=$hashes
		;;
	khash)
		hashes=`echo "scale=2; $hashes/1000" | bc -l 2> /dev/null`
		;;
	esac

	local percentRejected=`echo "scale=3;a=($rejected*100) ; b=$accepted; c=a/b; print c" | bc -l 2> /dev/null`
	if [ -z "$percentRejected" ]; then
		percentRejected="0.00"
	fi

	output=$(FormatOutput $hashes $accepted $rejected $percentRejected)

	if [[ -n "$failure" ]]; then
			output="\e[00;31m<<<FAIL>>\e[00m"
			let profileFailed++
			skipLockupCheck="1"
	
	elif [[ -z "$cmd" ]]; then
		output="\e[00;31m<<<IDLE>>>\e[00m"	
	else
		if [[ "$hashes" == "0" ]]; then
			# Is it safe to say the profile is down?
			output="\e[00;31m<<<DOWN>>>\e[00m"
			let profileFailed++
			skipLockupCheck="1"
		fi
	fi
}
