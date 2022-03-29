#!/bin/bash

if [[ $( dirname "$0" ) == "/usr/bin" ]]; then
	CUR_LOCATION=$(dirname $(readlink -f $( dirname "$0" )/smartcoin))
else
	CUR_LOCATION="$( cd "$( dirname "$0" )" && pwd )"
fi



#INSTALL_LOCATION=$1

if [[ "$INSTALL_LOCATION" == "" ]]; then
	INSTALL_LOCATION="$CUR_LOCATION"
fi


CheckIfAlreadyInstalled() {
	if [[ -f "$HOME/.smartcoin/smartcoin.db" ]]; then
		echo "The installer has already been run before.  You cannot run it again."
		echo "Perhaps you should do a full reinstall, and try again."
		exit
	fi	
}


#################
# BEGIN INSTALLER
#################


clear
CheckIfAlreadyInstalled
# Move the database
mkdir -p $HOME/.smartcoin && cp $CUR_LOCATION/smartcoin.db $HOME/.smartcoin/smartcoin.db
. $CUR_LOCATION/smartcoin_ops.sh
Log "==========Beginning Installation============"
Log "Database created in $HOME/.smartcoin/smartcoin.db"

# Ask for user permission
Log "Asking user for permission to install"
echo "SmartCoin requires root permissions to install dependencies, create SymLinks and set up the database."
echo "You will be prompted for  your password when needed."
echo "Do you wish to continue? (y/n)"
read getPermission
echo ""

getPermission=`echo $getPermission | tr '[A-Z]' '[a-z]'`
if  [[ "$getPermission" != "y"  ]]; then
	echo "Exiting  SmartCoin installer."
	Log "	Permission Denied."
	exit
fi
Log "	Permission Granted."

echo ""

# Create  SymLink
echo ""
Log "Creating symlink..." 1
sudo ln -s $INSTALL_LOCATION/smartcoin.sh /usr/bin/smartcoin 2> /dev/null
echo "done."
echo ""

# Install dependencies
Log  "Installing dependencies" 1
echo "Please be patient..."
sudo apt-get install -f  -y bc sqlite3 openssh-server 2> /dev/null
echo "done."
echo ""


# SQL DB calls start now, make sure we set the database
UseDB "smartcoin.db"

# Set up the local machine
Log "Setting up local machine in database..." 1
Q="INSERT INTO machine (name,server,ssh_port,username,auto_allow,disabled) VALUES ('localhost','127.0.0.1',22,'$USER',1,0);"
RunSQL "$Q"
echo "done."


# Populate the database with default pools
Log "Populating database with pool information...."
Q="INSERT INTO pool (name,server,alternate_server,port,timeout,auto_allow,disabled) VALUES ('DeepBit','deepbit.net',NULL,8332,60,1,0);"
R=$(RunSQL "$Q")
Q="INSERT INTO pool (name,server,alternate_server,port,timeout,auto_allow,disabled) VALUES ('Bitcoin.cz (slush)','mining.bitcoin.cz',NULL,8332,60,1,0);"
R=$(RunSQL "$Q")
Q="INSERT INTO pool (name,server,alternate_server,port,timeout,auto_allow,disabled) VALUES ('BTCGuild','btcguild.com',NULL,8332,60,1,0);"
R=$(RunSQL "$Q")
Q="INSERT INTO pool (name,server,alternate_server,port,timeout,auto_allow,disabled) VALUES ('BTCMine','btcmine.com',NULL,8332,60,1,0);"
R=$(RunSQL "$Q")
Q="INSERT INTO pool (name,server,alternate_server,port,timeout,auto_allow,disabled) VALUES ('Bitcoins.lc','bitcoins.lc',NULL,8080,60,1,0);"
R=$(RunSQL "$Q")
Q="INSERT INTO pool (name,server,alternate_server,port,timeout,auto_allow,disabled) VALUES ('SwePool','swepool.net',NULL,8337,60,1,0);"
R=$(RunSQL "$Q")
Q="INSERT INTO pool (name,server,alternate_server,port,timeout,auto_allow,disabled) VALUES ('Continuum','continuumpool.com',NULL,8332,60,1,0);"
R=$(RunSQL "$Q")
Q="INSERT INTO pool (name,server,alternate_server,port,timeout,auto_allow,disabled) VALUES ('MineCo','mineco.in',NULL,3000,60,1,0);"
R=$(RunSQL "$Q")
Q="INSERT INTO pool (name,server,alternate_server,port,timeout,auto_allow,disabled) VALUES ('Eligius','mining.eligius.st',NULL,8337,60,1,0);"
R=$(RunSQL "$Q")
Q="INSERT INTO pool (name,server,alternate_server,port,timeout,auto_allow,disabled) VALUES ('CoinMiner','173.0.52.116',NULL,8347,60,1,0);"
R=$(RunSQL "$Q")
Q="INSERT INTO pool (name,server,alternate_server,port,timeout,auto_allow,disabled) VALUES ('ZABitcoin','mine.zabitcoin.co.za',NULL,8332,60,1,0);"
R=$(RunSQL "$Q")
Q="INSERT INTO pool (name,server,alternate_server,port,timeout,auto_allow,disabled) VALUES ('BitClockers','pool.bitclockers.com',NULL,8332,60,1,0);"
R=$(RunSQL "$Q")
Q="INSERT INTO pool (name,server,alternate_server,port,timeout,auto_allow,disabled) VALUES ('MtRed','mtred.com',NULL,8337,60,1,0);"
R=$(RunSQL "$Q")
Q="INSERT INTO pool (name,server,alternate_server,port,timeout,auto_allow,disabled) VALUES ('SimpleCoin','simplecoin.us',NULL,8337,60,1,0);"
R=$(RunSQL "$Q")
Q="INSERT INTO pool (name,server,alternate_server,port,timeout,auto_allow,disabled) VALUES ('Ozco','ozco.in',NULL,8332,60,1,0);"
R=$(RunSQL "$Q")
Q="INSERT INTO pool (name,server,alternate_server,port,timeout,auto_allow,disabled) VALUES ('EclipseMC','us.eclipsemc.com',NULL,8332,60,1,0);"
R=$(RunSQL "$Q")
Q="INSERT INTO pool (name,server,alternate_server,port,timeout,auto_allow,disabled) VALUES ('BitP','pool.bitp.it',NULL,8334,60,1,0);"
R=$(RunSQL "$Q")
Q="INSERT INTO pool (name,server,alternate_server,port,timeout,auto_allow,disabled) VALUES ('BitcoinPool','bitcoinpool.com',NULL,8334,60,1,0);"
R=$(RunSQL "$Q")
Q="INSERT INTO pool (name,server,alternate_server,port,timeout,auto_allow,disabled) VALUES ('EcoCoin','ecocoin.org',NULL,8332,60,1,0);"
R=$(RunSQL "$Q")
Q="INSERT INTO pool (name,server,alternate_server,port,timeout,auto_allow,disabled) VALUES ('BitLottoPool','bitcoinpool.com',NULL,8337,60,1,0);"
R=$(RunSQL "$Q")
Q="INSERT INTO pool (name,server,alternate_server,port,timeout,auto_allow,disabled) VALUES ('X8S','pit.x8s.de',NULL,8337,60,1,0);"                              
R=$(RunSQL "$Q")
Q="INSERT INTO pool (name,server,alternate_server,port,timeout,auto_allow,disabled) VALUES ('Ars Technica','arsbitcoin.com',NULL,8344,60,1,0);"    
R=$(RunSQL "$Q")
Q="INSERT INTO pool (name,server,alternate_server,port,timeout,auto_allow,disabled) VALUES ('TripleMining','eu.triplemining.com',NULL,8344,60,1,0);"    
R=$(RunSQL "$Q")
Q="INSERT INTO pool (name,server,alternate_server,port,timeout,auto_allow,disabled) VALUES ('Mainframe','mining.mainframe.nl',NULL,8343,60,1,0);"    
R=$(RunSQL "$Q")
Q="INSERT INTO pool (name,server,alternate_server,port,timeout,auto_allow,disabled) VALUES ('Bitcoin Monkey','bitcoinmonkey.com',NULL,8332,60,1,0);"    
R=$(RunSQL "$Q")
Q="INSERT INTO pool (name,server,alternate_server,port,timeout,auto_allow,disabled) VALUES ('Best Bitcoin','pool.bestbitcoinminingpool.com',NULL,8332,60,1,0);"    
R=$(RunSQL "$Q")
Q="INSERT INTO pool (name,server,alternate_server,port,timeout,auto_allow,disabled) VALUES ('Eclipse MC','us.eclipsemc.com',NULL,8337,60,1,0);"    
R=$(RunSQL "$Q")

# Create the Machine Settings needed in the database, then fill them in with defaults
MachineSettings 1
MachineDefaults 1

# Create the General settings needed in the database, then fill them in with defaults
GeneralSettings
GeneralDefaults

# Run the autodetect routine
AutoDetect 1


# Administrator email
echo ""
echo "Please enter an administration email address where you would like to receive notifications. (You can leave this blank if you do not wish to receive notifications)"
read emailAddress
Q="UPDATE settings SET value='$emailAddress' WHERE data='email' AND fk_machine='0';"
RunSQL "$Q"

# ----------------
# Ask for donation
# ----------------
clear
host=$(RunningOnLinuxcoin)
if [[ "$host" == "1" ]]; then
	donationAddendum="\nNOTE: It has been detected that you are running the LinuxCoin distro. 50% of your AutoDonations will go to the author of LinuxCoin!"
fi

donation="Please consider donating a small portion of your hashing power to the author of SmartCoin.  A lot of work has gone in to"
donation="$donation making this a good stable platform that will make maintaining your miners much easier, more stable"
donation="$donation and with greater up-time. By donating a small portion"
donation="$donation of your hashing power, you will help to ensure that smartcoin users get support, bugs get fixed and features added."
donation="$donation Donating just 30 minutes a day of your hashing power is only a mall percentage, and will go a long way to show the author of SmartCoin"
donation="$donation your support and appreciation.  You can always turn this setting off in the menu once you feel you've given back a fair amount."
donation="$donation $donationiAddendum"
donation="$donation \n\n\n"
donation="$donation I pledge the following minutes per day of my hashing power to the author of smartcoin:"
echo -e $donation
read -e -i "30" myDonation

if [[ "$myDonation" == "" ]]; then
	myDonation=0
fi

Q="UPDATE settings SET value='$myDonation' WHERE data='donation_time' and fk_machine='0';"
RunSQL "$Q"
let startTime_hours=$RANDOM%23
let startTime_minutes=$RANDOM%59
startTime_minutes=`printf "%02d" $startTime_minutes` # pad with a zero if needed!
startTime=$startTime_hours$startTime_minutes
Q="UPDATE settings SET value='$startTime' WHERE data='donation_start' and fk_machine='0';"
RunSQL "$Q"
if [[ "$myDonation" -gt "0"  ]]; then
	echo ""
	echo ""
	echo "Thank you for your decision to donate! Your donated hashes will start daily at $startTime_hours:$startTime_minutes for $myDonation minutes."
	echo "You can turn this off at any time from the control screen, and even specify your own start time if you want to."
fi	
echo ""
echo ""


# ---------
# Finished!
# ---------
# Tell the user what to do
echo "Installation is now complete.  You can now start SmartCoin at any time by typing the command 'smartcoin' at the terminal."
echo "You will need to go to the control page to set up some workers!"

