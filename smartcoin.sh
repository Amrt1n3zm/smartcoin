#!/bin/bash
#SMART (Simple Miner Administration for Remote Terminals)
if [[ $( dirname "$0" ) == "/usr/bin" ]]; then
	CUR_LOCATION=$(dirname $(readlink -f $( dirname "$0" )/smartcoin))
else
	CUR_LOCATION="$( cd "$( dirname "$0" )" && pwd )"
fi
. $CUR_LOCATION/smartcoin_ops.sh

# Start the backend service
#$HOME/smartcoin/smartcoin_backend.sh &

# Parse command line options
for arg in $*; do
  case $arg in
  --delay=*)  
    ARG_DELAY=`echo $arg | sed 's/[-a-zA-Z0-9]*=//'`
    ;;
  --machine=*)
    ARG_MACHINE=`echo $arg | sed 's/[0-9]*=//'`
    ;;
  --kill)
    ARG_KILL="1"
    ;;
  --silent)
    ARG_SILENT="1"
    ;;
  --restart)
    ARG_RESTART="1"
    ;;
  --reload)
    ARG_RELOAD="1"
    ;;
  esac
done

# Process command line arguments
if [[ "$ARG_DELAY" ]]; then
  sleep "$ARG_DELAY"
fi
if [[ "$ARG_RELOAD" ]]; then
  if [[ -z "$ARG_MACHINE" ]]; then
    ARG_MACHINE=0
  fi
  Reload $ARG_MACHINE "Smartcoin was told to reload remotely from the commandline."
  exit
fi
if [[ "$ARG_RESTART" ]]; then
  echo "Not yet supported!"
  exit
fi
if [[ "$ARG_KILL" ]]; then
  killMiners
  screen -d -r $sessionName -X quit 2> /dev/null
  exit
fi


echo "Starting SmartCoin at location: $CUR_LOCATION..."

running=`screen -ls 2> /dev/null | grep $sessionName`

echo "Running check"

if [[ "$running" ]]; then
	attached=`screen -ls | grep -i attached`
	echo "Re-attaching to smartcoin..."
	if [[ "$attached" != "" ]]; then
		screen -x $sessionName -p status
	else
		screen -r $sessionName -p status
	fi
	
	exit
fi
RotateLogs
Log "******************* NEW SMARTCOIN SESSION STARTED *******************" 
Log "Starting main smartcoin screen session..." 1

host=$(RunningOnLinuxcoin)
if [[ "$host" == "1" ]]; then
	Log "It has been detected that you are running on the LinuxCoin distro.  50% of your AutoDonations will go to the LinuxCoin author."
fi

# Reset the failover information in the database
Q="UPDATE profile SET failover_count='0', down='0';"
RunSQL "$Q"

# Let the user have their own custom initialization script if they want
if [[ -f "$CUR_LOCATION/init.sh" ]]; then
	Log "User initialization script found. Running initialization script." 1
	$CUR_LOCATION/init.sh
fi

DeleteTemporaryFiles

# Do settings integrity check!
GeneralSettings
MachineSettings

screen -d -m -S $sessionName -t control "$CUR_LOCATION/smartcoin_control.sh"
screen -r $sessionName -X zombie ko
screen -r $sessionName -X chdir
screen -r $sessionName -X hardstatus on
screen -r $sessionName -X hardstatus alwayslastline
screen -r $sessionName -X hardstatus string '%{= kG}[ %{G}%H %{g}][%= %{= kw}%?%-Lw%?%{r}(%{W}%n*%f%t%?(%u)%?%{r})%{w}%?%+Lw%?%?%= %{g}][%{B} %m/%d/%y %{W}%c %{g}]'

Log "Creating tab for each machine..." 1
# Create a new window for each machine
Q="SELECT pk_machine, name FROM machine WHERE disabled=0;"
R=$(RunSQL "$Q")
for row in $R; do
	pk_machine=$(Field 1 "$row")
	machineName=$(Field 2 "$row")
	Log "	$machineName"
	screen -r $sessionName -X screen -t $machineName "$CUR_LOCATION/smartcoin_status.sh" "$pk_machine"
	screen -r $sessionName -p $machineName -X wrap off
done

Log "Creating a logtail tab..." 1
screen -r $sessionName -X screen -t Log tail -f ~/.smartcoin/smartcoin.log


if [[ "$ARG_SILENT" ]]; then
  Log "SmartCoin started in the backround." 1
else
	 clear
	GotoStatus
fi



