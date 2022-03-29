#!/bin/bash
# smartcoin_control.sh
# This script handles all of the user configurable options and menu system of smartcoin.
# Only one instance of this control script runs on the local machine, it uses and stores database information
# which lets smartcoin interact with multiple machines.
# This script only handles database interaction, and doesn't launch or kill any other processes directly.


if [[ $( dirname "$0" ) == "/usr/bin" ]]; then
	CUR_LOCATION=$(dirname $(readlink -f $( dirname "$0" )/smartcoin))
else
	CUR_LOCATION="$( cd "$( dirname "$0" )" && pwd )"
fi
. $CUR_LOCATION/smartcoin_ops.sh




# Update system
Do_Update()
{
  
  clear
  ShowHeader
  echo "Getting svn information. Please be patient..."
  local svn_rev=$(GetRevision)
  local svn_repo=$(GetRepo)
  local svn_exp=$(GetHead "$svn_repo")
  local svn_stb=$(GetStableHead "$svn_repo")
  E="Your current version is r$svn_rev$G_BRANCH_ABBV.\n"
  E=$E"The current experimental version is r$svn_exp""e\n"
  E=$E"The current stable version is r$svn_stb""s\n"
  E=$E"Are you sure that you wish to perform an update?"
	GetYesNoSelection doInstall "$E"

  if [[ "$doInstall" == "0" ]]; then
    return
  fi
  # First, lets update only the update script!
  echo ""
  echo "Bring update script up to current..."
  svn update $CUR_LOCATION/smartcoin_update.sh >/dev/null 2>&1

  echo ""
  
  Q="SELECT value FROM settings WHERE data='dev_branch';"
  R=$(RunSQL "$Q")
  local branch=$(Field 1 "$R")
  
  
  if [[ "$branch" == "stable" ]]; then
     $CUR_LOCATION/smartcoin_update.sh
  elif [[ "$branch" == "experimental" ]]; then
    $CUR_LOCATION/smartcoin_update.sh 1
  else
    echo ""
    echo "Error! Specified branch must be either \"experimental\" or \"stable\"."
    sleep 5    
  fi
  
  # Lets update the master revision variable
  export REVISION=$(GetRevision)

}

# Failover Order Menu
Do_SetFailoverOrder()
{
	local thisMachine
	clear
	ShowHeader

	echo "CHANGE FAILOVER ORDER"
	echo "---------------------"
	Q="SELECT COUNT(*) FROM profile;"
	R=$(RunSQL "$Q")
	local count=$(Field 1 "$R")
	if [[ "$count" -le "1" ]]; then
		E="You need at least 2 manual profiles set up to use the failover system. "
		E=$E"Please set up some profiles, then come back here to set a specific failover order."
		echo "$E"
		sleep 5
		return
	fi
	

	local thisProfile
	local usedProfiles=""
	local i=0


	Q="SELECT pk_machine, name from machine;"
	E="Please select the machine from the list above that you wish to edit Failover order on"
	GetPrimaryKeySelection thisMachine "$Q" "$E"
	echo ""

	echo "Current failover order:"
	echo "-----------------------"
	Q="SELECT pk_profile, name FROM profile WHERE fk_machine='$thisMachine' AND failover_order>'0' ORDER BY failover_order;"
	R=$(RunSQL "$Q")
	for row in $R; do
		local thisProfile=$(Field 1 "$row")
		local thisProfileName=$(Field 2 "$row")

		echo "$thisProfile) $thisProfileName"
	done
	if [[ -z "$R" ]]; then
		echo "<<<Failover order not yet set!>>>"
	fi
	echo "-----------------------"
	echo ""
	echo "The current profile failover order is listed above."
	echo ""

	E="Do you want to change the failover order, (y)es or (n)o?"
	GetYesNoSelection changeOrder "$E"
	echo ""

	if [[ "$changeOrder" == "1"  ]]; then
		
		# Mark all profiles to not be included into the failover system
		Q="UPDATE profile SET failover_order='-1' WHERE fk_machine='$thisMachine';"
		RunSQL "$Q"

		Q="SELECT pk_profile, name FROM profile WHERE fk_machine='$thisMachine' ORDER BY pk_profile;"
		R=$(RunSQL "$Q")
		for row in $R; do
			local thisProfile=$(Field 1 "$row")
			local thisProfileName=$(Field 2 "$row")

			echo "$thisProfile) $thisProfileName"
		done
		echo ""
		echo "Enter a comma-separated list of the ID numbers above to define the failover order. I.e. 1,5,2,3"
		echo "Note: leave out ID numbers to exclude them from the failover system"
		read profileOrder
		
		echo "Updating the Failover order..."
		# Filter out spaces
		profileOrder=${profileOrder//" "/""}

		# then convert to a list that can be iterated with for
		profileOrder=${profileOrder//","/" "}

		for thisProfile in $profileOrder; do
			let i++
			Q="UPDATE profile SET failover_order='$i' WHERE pk_profile='$thisProfile';"
			RunSQL "$Q"
		done

		echo "done."
		sleep 1
	fi

}

# Profile Menu
Do_ChangeProfile() {
	local autoEntry

	clear
	ShowHeader

	# Add the flags for the dynamically generated profiles
	autoEntry=$(FieldArrayAdd "-2	1	Donation")
	autoEntry=$autoEntry$(FieldArrayAdd "-1	2	Automatic")
	autoEntry=$autoEntry$(FieldArrayAdd "-3	3	Failover")
	autoEntry=$autoEntry$(FieldArrayAdd "-4	4	Idle")

	# Display menu
	Q="SELECT pk_machine,name from machine"
	E="Select the machine from the list above that you wish to change the profile on"
	GetPrimaryKeySelection thisMachine "$Q" "$E"

	Q="SELECT pk_profile, name FROM profile where fk_machine=$thisMachine AND pk_profile>0 ORDER BY pk_profile ASC;"
	E="Select the profile from the list above that you wish to switch to"
	GetPrimaryKeySelection thisProfile "$Q" "$E" "" "$autoEntry"
	
	SetCurrentProfile "$thisMachine" "$thisProfile"
	
	# Lets see if we can automatically go to the status screen
	Q="SELECT name FROM machine WHERE pk_machine=$thisMachine;"
	R=$(RunSQL "$Q")
	machineName=$(Field 1 "$R")

	screen -r $sessionName -X screen -p 1

}
Do_Settings() {
	local autoEntry
	local thisMachine

	clear
	ShowHeader
	echo "EDIT SETTINGS"
	echo "-------------"
	echo ""
	Q=""
	E="Which settings would you like to edit?"
	autoEntry=$(FieldArrayAdd "1	1	General Settings")
	autoEntry=$autoEntry$(FieldArrayAdd "2	2	Machine Settings")
	GetPrimaryKeySelection settingsType "$Q" "$E" "" "$autoEntry"
	echo ""

	if [[ "$settingsType" == "2" ]]; then
		Q="SELECT pk_machine,name from machine"
		E="Select the machine from the list above that you wish to edit settings on"
		GetPrimaryKeySelection thisMachine "$Q" "$E"
	else
		thisMachine=0
	fi
	echo ""


	clear
	ShowHeader
	if [[ "$thisMachine" == "0" ]]; then
		echo "EDIT GENERAL SETTINGS"
		echo "---------------------"
	else
		echo "EDIT MACHINE #$thisMachine SETTINGS"
		echo "----------------------"
	fi
	Q="SELECT pk_settings, description FROM settings WHERE fk_machine='$thisMachine' AND description !='' ORDER BY display_order;"
	E="Select the setting from the list above that you wish to edit"
	GetPrimaryKeySelection thisSetting "$Q" "$E"
	echo " "

	clear
	ShowHeader
	echo "EDIT SETTING"
	echo "------------"
	echo ""
	Q="SELECT information FROM settings WHERE pk_settings='$thisSetting';"
	R=$(RunSQL "$Q")
	local information=$(Field 1 "$R")
	echo "Here is some general information about this setting:"
	echo "--------------------"
	echo -ne "$information\n"
	echo "--------------------"
	echo ""
	Q="SELECT value, description FROM settings WHERE pk_settings=$thisSetting;"
	R=$(RunSQL "$Q")
	settingValue=$(Field 1 "$R")
	settingDescription=$(Field 2 "$R")
	
	echo "New $settingDescription"
	read -e -i "$settingValue" newSetting



	echo "Updating Setting..."
	Q="UPDATE settings SET value='$newSetting' WHERE pk_settings=$thisSetting;"
	RunSQL "$Q"
	sleep 1
	echo "done."

	

	Reload $thisMachine "Settings have been changed. Reloading miners."


	
}
# Configure Machines Menu
Do_Machines() {
	clear                                                                   
        ShowHeader                                                              
        #Add/Edit/Delete?                                                       
        AddEditDelete "machines"                                                  
        action=$(GetAEDSelection)                                               
                                                                                
        case "$action" in                                                       
        ADD)                                                                    
                Add_Machines                                                      
                ;;                                                              
        DELETE)                                                                 
                Delete_Machines                                                   
                ;;                                                              
                                                                                
        EDIT)                                                                   
                Edit_Machines                                                     
                ;;                                                              
        EXIT)                                                                   
                return                                                          
                ;;                                                              
        *)                                                                      
                DisplayError "Invalid selection!" "5"                           
                ;;               
	esac

}
GenKeysAndCopy() {
	local machinePort=$1
	local machineUser=$2
	local machineServer=$3


	# Step 1: Generate the keys if needed!
	if [[ ! -f ~/.ssh/id_rsa.smartcoin ]]; then
		Log "SSH keys have not been generated yet" 1
		echo "Generating..."
		ssh-keygen -q -N "" -f ~/.ssh/id_rsa.smartcoin -C "Smartcoin RSA key"
		echo "Done."
	fi

	# If we can copy the key over to the remote machine, then success!
	#ssh $machineUser@$machineServer -p $machinePort uname -r 2> /dev/null
	ssh-copy-id -i ~/.ssh/id_rsa.smartcoin.pub "-q -p $machinePort $machineUser@$machineServer"
	return $?
}

Add_Machines() {
	clear
	ShowHeader
	echo "ADDING MACHINE"
	echo "--------------"
	echo ""
	echo "Give this machine a nickname"
	read machineName
	echo ""
	echo "Enter this machines server address"
	read machineServer
	echo ""
	echo "Enter this machines server port"
	read -e -i "22" machinePort
	echo ""
	echo "Enter the username to use with this machine"
	read machineUser
	echo ""

	# Now its time to determine whether or not the remote machine is online.
	# We can only add it to teh database if it is online - as we have to generate some RSA keys!
	echo "In order to continue, we need to attempt to connect to this remote machine."
	echo "If we can successfully connect, we will generate RSA keys for secure communication."
	echo "Press any key to attempt to connect to the remote machine. You will need to enter the password for the remote machine when prompted!"
	read
	echo

	GenKeysAndCopy "$machinePort" "$machineUser" "$machineServer"
	  
	if [[ $? -ne 0 ]]; then
		echo "Aborting!"
		echo "We were unable to connect to the remote server. This most likely means that the server is either offline, or information was entered incorrectly."
		echo "Please try again, and make sure that the server is online, and that information entered is correct."
		echo "(Any key to continue)"
		read
	else
		
		echo "Connection successful!"
		echo ""
		E="Would you like to disable this machine? (y)es or (n)o?"
		GetYesNoSelection machineDisabled "$E" "n"
		echo ""
      
		# Add the machine to the database!
		echo "Updating Machines..."
		Q="INSERT INTO machine (name,server,ssh_port,username,disabled) VALUES ('$machineName','$machineServer','$machinePort','$machineUser','$machineDisabled');"
		RunSQL "$Q"
		sleep 1
		echo "done."

		# TODO: Auto-detection on remote machine!
		Q="SELECT pk_machine FROM machine ORDER BY pk_machine DESC LIMIT 1;"
		R=$(RunSQL "$Q")
		local insertedMachine=$(Field 1 "$R")

		MachineSettings "$insertedMachine"
		MachineDefaults "$insertedMachine"
		AutoDetect "$insertedMachine"
	fi


	return
}

Edit_Machines() {
	# TODO: Use this function as a model for local variable scope and return values. Need to someday clean up all other functions to be as tidy.
	local connectionInformationChanged

	clear
	ShowHeader
	echo "EDITING MACHINE"
	echo "---------------"
	echo ""

	local thisMachine
	Q="SELECT pk_machine,name FROM machine WHERE pk_machine<>'1';"
	E="Select the machine from the list above that you wish to edit"
	GetPrimaryKeySelection thisMachine "$Q" "$E"
	echo ""

	Q="SELECT name,username,server,ssh_port,disabled FROM machine WHERE pk_machine='$thisMachine'";
	R=$(RunSQL "$Q")
	local cname=$(Field 1 "$R")
	local cusername=$(Field 2 "$R")
	local cserver=$(Field 3 "$R")
	local cssh_port=$(Field 4 "$R")
	local cdisabled=$(Field 5 "$R")

	local machineName
	echo "Enter a nickname for this machine:"
	read -e -i "$cname" machineName
	echo ""

	local machineUsername
	echo "Enter the username for this machine:"
	read -e -i "$cusername" machineUsername
	echo ""
	if [[ "$machineUsername" != "$cusername" ]]; then
		connectionInformationChanged="1"
	fi


	local machineServer
	echo "Enter the server host address for this machine:"
	read -e -i "$cserver" machineServer
	echo ""
	if [[ "$machineServer" != "$cserver" ]]; then
		connectionInformationChanged="1"
	fi

	local machinePort
	echo "Enter the ssh port for this machine:"
	read -e -i "$cssh_port" machinePort
	echo ""

	local machineDisabled
	E="Would you like to disable this machine?"
	GetYesNoSelection machineDisabled "$E" "$cdisabled"
	echo ""


	if [[ "$connectionInformationChanged" == "1" ]]; then
		Log "Connection information has changed. Trying to establish a new connection." 1
		GenKeysAndCopy "$machinePort" "$machineUsername" "$machineServer"
		if [[ $? -ne 0 ]]; then
			echo ""
			Log "New connection was not successful." 1
			echo "Please try again and make sure you have entered the correct connection information."
			echo "Changes will not be written to the database."
			echo "(Any key to continue)"
			read
			return 1
		else
			Log "New connection successful!" 1
		fi
	fi
	echo ""

	echo "Updating machine..."
	Q="UPDATE machine SET name='$machineName', username='$machineUsername', server='$machineServer', ssh_port='$machinePort', disabled='$machineDisabled' WHERE pk_machine='$thisMachine';"
	RunSQL "$Q"
	echo "done."
	sleep 1
	Reload $thisMachine "Machines have changed. Reloading miners."
	return 0
}

Delete_Machines() {
	clear
	ShowHeader
	echo "SELECT MACHINE TO DELETE"

	Q="SELECT COUNT(*) FROM machine;"
	R=$(RunSQL "$Q")
	local numMachines=$(Field 1 "$R")

	if [[ "$numMachines" -le "1" ]]; then
		echo "You have no extra machines to delete, and you cannot delete the localhost machine."
		echo "Press any key to return to the control screen."
		read
		return
	fi
	Q="SELECT pk_machine,name FROM machine WHERE pk_machine<>'1';"
	E="Select the machine from the list above that you wish to delete"
	GetPrimaryKeySelection thisMachine "$Q" "$E"


	echo "Deleting Machine..."
	local tables="settings current_profile miner device macro_map profile"
	local thisTable

	for thisTable in $tables; do
		Q="DELETE FROM $thisTable WHERE fk_machine='$thisMachine';"
		RunSQL "$Q"
	done
	

	# Delete the actual machine entry
	Q="DELETE FROM machine WHERE pk_machine='$thisMachine';"
	RunSQL "$Q"	

	echo "done."
	sleep 1
}

# Configure Miners Menu
Do_Miners() {
	clear
	ShowHeader
	#Add/Edit/Delete?
	AddEditDelete "miners"
	action=$(GetAEDSelection)
		
	case "$action" in
	ADD)
		Add_Miners
		;;
	DELETE)
		Delete_Miners
		;;

	EDIT)
		Edit_Miners
		;;
  	EXIT)
    		return
    		;;
	*)
		DisplayError "Invalid selection!" "5"
		;;	

	esac

	

	
}
Add_Miners()
{
	#table:miner fields:pk_miner, name, launch, path
	clear
	ShowHeader
	echo "ADDING MINER"
	echo "------------"
	Q="SELECT pk_machine, name from machine;"
	E="Please select the machine from the list above that is hosting this miner"
	GetPrimaryKeySelection thisMachine "$Q" "$E"
	echo "Give this miner a nickname"
	read minerName
	echo "Enter the miner's path (i.e. /home/you/miner/)"
	read minerPath
	echo "Enter the miner's launch string"
	echo "Note:use special strings <#user#>, <#path#>, <#server#>"
	echo "<#port#>, and <#device#>"
	echo "i.e.  phoenix.py -v -u http://<#user#>:<#pass#>@<#server#>:<#port#>/ -k phatk device=<#device#> worksize=256 vectors aggression=11 bfi_int fastloop=false"
	read minerLaunch
	E="Do you want this to be the the default miner for this machine?"
	GetYesNoSelection defaultMiner "$E"

	echo "Adding Miner..."
	Q="INSERT INTO miner (name,launch,path,fk_machine) VALUES ('$minerName','$minerLaunch','$minerPath','$thisMachine');"
	RunSQL "$Q"


	Q="SELECT pk_miner FROM miner ORDER BY pk_miner DESC LIMIT 1;"
	R=$(RunSQL "$Q")
	insertedID=$(Field 1 "$R")


	if [[ "$defaultMiner" = "1" ]]; then
		SetDefaultMiner "$thisMachine" "$insertedID"
	fi

	echo "done."
	Reload $thisMachine "Miners have been changed. Reloading miners."
	sleep 1

}
Edit_Miners()
{
	clear
	ShowHeader
	echo "SELECT MINER TO EDIT"
	Q="SELECT pk_machine,name FROM machine;"
	E="Select the machine the miner resides on"
	GetPrimaryKeySelection thisMachine "$Q" "$E"


	empty=$(tableIsEmpty "miner" "WHERE fk_machine=$thisMachine")
	if [[ "$empty" ]]; then
		echo ""
		echo "There are no miners to edit."
		sleep 3
		return
	fi

	Q="SELECT pk_miner, name FROM miner WHERE fk_machine=$thisMachine;"
	E="Select the miner you wish to edit"
	GetPrimaryKeySelection thisMiner "$Q" "$E"

	Q="SELECT name, launch, path, fk_machine, default_miner FROM miner WHERE pk_miner=$thisMiner;"
	R=$(RunSQL "$Q")
	cname=$(Field 1 "$R")
	claunch=$(Field 2 "$R")
	cpath=$(Field 3 "$R")
	cmachine=$(Field 4 "$R")
	cdefault=$(Field 5 "$R")

	if [[ "$cdefault" == "1" ]]; then
		cdefault="y"
	else
		cdefault="n"
	fi

	clear
	ShowHeader
	echo "EDITING MINER"
	echo "------------"

	Q="SELECT pk_machine, name from machine;"                               
	E="Please select the machine from the list above that is hosting this
 miner"                          
	GetPrimaryKeySelection thisMachine "$Q" "$E" "$cmachine"
	echo "Please give this miner a nickname"
	read -e -i "$cname" minerName
	
	echo "Enter the miner's path (i.e. /home/you/miner/)"
	read -e -i "$cpath" minerPath

	echo "Enter the miner's launch string"
	echo "Note:use special strings <#user#>, <#path#>, <#server#>"
	echo "<#port#>, and <#device#>"
	read -e -i "$claunch" minerLaunch

	E="Do you want this to be the the default miner for this machine?"
	GetYesNoSelection defaultMiner "$E" "$cdefault"


	echo "Updating Miner..."

	Q="UPDATE miner SET name='$minerName', launch='$minerLaunch', path='$minerPath', fk_machine=$thisMachine WHERE pk_miner=$thisMiner"
	RunSQL "$Q"

	if [[ "$defaultMiner" = "1" ]]; then
		SetDefaultMiner "$thisMachine" "$thisMiner"
	fi
	
	echo "done."
	sleep 1
	Reload $thisMachine "Miners have been changed. Reloading miners."
}
Delete_Miners()
{
	#TODO: deal with situation where we delete the default miner - a new one needs set!
	clear
	ShowHeader
	echo "SELECT MINER TO DELETE"

	Q="SELECT pk_machine,name FROM machine;"
	E="Select the machine from the list above that the miner resides on"
	GetPrimaryKeySelection thisMachine "$Q" "$E"


	empty=$(tableIsEmpty "miner" "WHERE fk_machine=$thisMachine")
	if [[ "$empty" ]]; then
		echo ""
		echo "There are no miners to delete."
		sleep 3
		return
	fi

	
	Q="SELECT pk_miner,name FROM miner WHERE fk_machine=$thisMachine;"
	E="Please select the miner from the list above to delete"
	GetPrimaryKeySelection thisMiner "$Q" "$E"

	echo "Deleting Miner..."
	Q="DELETE FROM profile_map WHERE fk_miner=$thisMiner;"
	RunSQL "$Q"

	Q="DELETE FROM miner WHERE pk_miner=$thisMiner"
	RunSQL "$Q"
	echo "done."
	sleep 1
	Reload $thisMachine "Miners have been changed. Reloading miners."
}


# Configure Pools Menu
Do_Pools() {
clear                                                                   
        ShowHeader                                                              
        #Add/Edit/Delete?                                                       
        AddEditDelete "pools"                                                 
        action=$(GetAEDSelection)                                               
                                                                                
        case "$action" in                                                       
        ADD)                                                                    
                Add_Pool                                                     
                ;;                                                              
        DELETE)                                                                 
                Delete_Pool                                                  
                ;;                                                              
                                                                                
        EDIT)                                                                   
                Edit_Pool                                                    
                ;;  
        EXIT)
                return
                ;;                
        *)                                                                      
                DisplayError "Invalid selection!" "5"                           
                ;;                                                              
                                                                                
        esac     
	# Reload all miners
	Reload "0" "Pool information has been changed. Reloading miners." 
}
Add_Pool() 
{
	clear
	ShowHeader
	echo "ADDING POOL"
	echo "-----------"

	echo "Give this pool a nickname"
	read poolName
	echo ""

	echo "Enter the main server address for this pool"
	read  poolServer
	echo ""

	echo "Enter an optional alternate server address for this pool"
	read poolAlternate
	echo ""
        
	echo "Enter the port number to connect to this pool"
	read poolPort
	echo ""
	
	echo "Enter a disconnection timeout for this pool"
	read poolTimeout
	echo ""
  
  # TODO: auto_allow and disabled aren't used yet (if ever?)
  #       fix hard coding once a decision is made

        Q="INSERT INTO pool (name,server,alternate_server,port,timeout,auto_allow,disabled) VALUES ('$poolName','$poolServer','$poolAlternate','$poolPort','$poolTimeout',1,0);"
        RunSQL "$Q"
	echo "done."
	sleep 1
}
Edit_Pool()
{
	clear
	ShowHeader

	empty=$(tableIsEmpty "pool")
	if [[ "$empty" ]]; then
		echo ""
		echo "There are no pools to edit."
		sleep 3
		return
	fi

	echo "SELECT POOL TO EDIT"
	Q="SELECT pk_pool, name FROM pool;"
	E="Please select the pool from the list above to edit"
	GetPrimaryKeySelection thisPool "$Q" "$E"
        
	Q="SELECT name,server,alternate_server,port,timeout  FROM pool WHERE pk_pool=$thisPool;"
	R=$(RunSQL "$Q")
	cname=$(Field 1 "$R")
	cserver=$(Field 2 "$R")
	calternate=$(Field 3 "$R")
	cport=$(Field 4 "$R")
	ctimeout=$(Field 5 "$R")


	clear
	ShowHeader
	echo "EDITING POOL"
	echo "------------"

	echo "Give this pool a nickname"
	read -e -i "$cname" poolName
	echo ""

	echo "Enter the main server address for this pool"
	read -e -i "$cserver" poolServer
	echo ""

	echo "Enter an optional alternate server address for this pool"
	read -e -i "$calternate" poolAlternate
	echo ""
        
	echo "Enter the port number to connect to this pool"
	read -e -i "$cport" poolPort
	echo ""
	
	echo "Enter a disconnection timeout for this pool"
	read -e -i "$ctimeout" poolTimeout
	echo ""

        echo "Updating Pool..."

        Q="UPDATE pool SET name='$poolName', server='$poolServer', alternate_server='$poolAlternate', port='$poolPort', timeout='$poolTimeout' WHERE pk_pool=$thisPool"
        RunSQL "$Q"
	echo "done."
	sleep 1

}
Delete_Pool()
{
	clear
	ShowHeader

	empty=$(tableIsEmpty "pool")
	if [[ "$empty" ]]; then
		echo ""
		echo "There are no pools to delete."
		sleep 3
		return
	fi

	echo "SELECT POOL TO DELETE"
	Q="SELECT pk_pool,name from pool;"
	E="Please select the pool from the list above to delete"
	GetPrimaryKeySelection thisPool "$Q" "$E"

	echo "Deleting pool..."

	
	# Get a list of the workers that reference the pool...
	Q="SELECT * FROM worker WHERE fk_pool=$thisPool;"
	R=$(RunSQL "$Q")
	for row in $R; do
		thisWorker=$(Field 1 "$row")
	
		# We have to delete all workers that refer to this pool!
		# And delete the profile_map entries that refer to those workers
		Q="DELETE FROM profile_map WHERE fk_worker=$thisWorker;"
		RunSQL "$Q"
	done

	Q="DELETE FROM worker WHERE fk_pool=$thisPool;"
	RunSQL "$Q"
	# And finally, delete the pool!
	Q="DELETE FROM pool WHERE pk_pool=$thisPool;"
	RunSQL "$Q"
	echo "done."
	sleep 1

}



# Configure Workers Menu
Do_Workers() {
        clear
        ShowHeader
        #Add/Edit/Delete?
        AddEditDelete "workers"
        action=$(GetAEDSelection)
                
        case "$action" in
        ADD)
                Add_Workers
                ;;
        DELETE)
                Delete_Workers
                ;;

        EDIT)
                Edit_Workers
                ;;
        EXIT)
                return
                ;;
        *)
                DisplayError "Invalid selection!" "5"
                ;;      

        esac

	# Reload all miners
	Reload 0 "Worker information has been changed. Reloading miners."
        
}

Add_Workers()
{
        #table:miner fields:pk_miner, name, launch, path
	clear
        ShowHeader
        echo "ADDING WORKER"
        echo "-------------"
	Q="SELECT pk_pool, name FROM pool;"
	E="What pool listed above is this worker associated with?"
	GetPrimaryKeySelection thisPool "$Q" "$E"
	echo " "

        echo "Give this worker a nickname"
        read -e -i "default" workerName
	echo " "
	

        echo "Enter the username for this worker"
        read userName
	echo " "

        echo "Enter the password for this worker"
        read password
	echo " "

	E="Would you like this worker to be available to the automatic profile? (y)es or (n)o?"
	GetYesNoSelection workerAllow "$E" 1

	echo "Adding Worker..."
        Q="INSERT INTO worker (fk_pool, name, user, pass, auto_allow, disabled) VALUES ('$thisPool','$workerName','$userName','$password','$workerAllow','0');"
        R=$(RunSQL "$Q")
	echo "done."
	sleep 1

}


Edit_Workers()
{
	clear
	ShowHeader

	empty=$(tableIsEmpty "worker")
	if [[ "$empty" ]]; then
		echo ""
		echo "There are no workers to edit."
		sleep 3
		return
	fi

	echo "SELECT WORKER TO EDIT"
	Q="SELECT pk_worker, pool.name || '.' || worker.name as fullName FROM worker LEFT JOIN pool ON worker.fk_pool = pool.pk_pool;"
	E="Please select the worker from the list above to edit"
	GetPrimaryKeySelection EditPK "$Q" "$E"

	Q="SELECT fk_pool,name,user,pass,auto_allow FROM worker WHERE pk_worker=$EditPK;"
	R=$(RunSQL "$Q")
	cpool=$(Field 1 "$R")
	cname=$(Field 2 "$R")
	cuser=$(Field 3 "$R")
	cpass=$(Field 4 "$R")
	callow=$(Field 5 "$R")


	clear
	ShowHeader
	echo "EDITING WORKER"
	echo "------------"
	Q="SELECT pk_pool,name FROM pool;"
	E="Which pool does this worker belong to?"
	GetPrimaryKeySelection workerPool "$Q" "$E" "$cpool"
	echo ""

	echo "Give this worker a nickname"
	read -e -i "$cname" workerName
	echo ""

	echo "Enter the user name for this worker"
	read -e -i "$cuser" workerUser
	echo ""

	echo "Enter the password for this worker"
	read -e -i "$cpass" workerPass
	echo ""


	E="Do you want to allow this worker to be added to the automatic profile?"
	GetYesNoSelection workerAllow "$E" "$callow"

	echo "Updating Worker..."

	Q="UPDATE worker SET fk_pool='$workerPool', name='$workerName', user='$workerUser', pass='$workerPass', auto_allow='$workerAllow' WHERE pk_worker=$EditPK"
	RunSQL "$Q"
	echo "done"
	sleep 1

}



Delete_Workers()
{
	clear
	ShowHeader

	empty=$(tableIsEmpty "worker")
	if [[ "$empty" ]]; then
		echo ""
		echo "There are no workers to delete."
		sleep 3
		return
	fi

	echo "SELECT WORKER TO DELETE"
	Q="SELECT pk_worker, pool.name || '.' || worker.name AS fullName FROM worker LEFT JOIN pool ON worker.fk_pool = pool.pk_pool;"
	E="Please select the worker from the list above to delete"
	GetPrimaryKeySelection thisWorker "$Q" "$E"
	

	echo "Deleting Worker..."
	Q="DELETE FROM worker WHERE pk_worker=$thisWorker;"
	RunSQL "$Q"
	# We also have to delete the profile_map entries that refer to this worker!
	Q="DELETE FROM profile_map WHERE fk_worker=$thisWorker;"
	RunSQL "$Q"
	echo "done."
	sleep 1
}


# Configure Profiles Menu
Do_Profile() {
	clear
	ShowHeader
	#Add/Edit/Delete?
	AddEditDelete "profiles"
	action=$(GetAEDSelection)
              
	case "$action" in
	ADD)
		Add_Profile
		;;
	DELETE)
		Delete_Profile
		Reload "Profile information has been changed. Reloading miners."
		;;
	EDIT)
		Edit_Profile
		Reload "Profile information has been changed. Reloading miners."
		;;
  EXIT)
    return
    ;;
	*)
		DisplayError "Invalid selection!" "5"
		;;      

	esac       
}

Add_Profile()
{
	# Add A Profile
	Q="SELECT pk_machine,name from machine"
	E="Select the machine you wish to add a profile on"
	GetPrimaryKeySelection thisMachine "$Q" "$E"

	echo "Enter a name for this profile"
	read profileName
	echo ""

	# Make sure we set the failover order to -1 so that new profiles aren't automatically included into the failover order!
	Q="INSERT INTO profile (name,fk_machine,failover_order) VALUES ('$profileName','$thisMachine','-1');"
	R=$(RunSQL "$Q")
		
	Q="SELECT pk_profile FROM profile ORDER BY pk_profile DESC LIMIT 1;"
	R=$(RunSQL "$Q")
	profileID=$(Field 1 "$R")

	# Get the default miner
	Q="SELECT pk_miner, default_miner FROM miner WHERE fk_machine=$thisMachine ORDER BY pk_miner;"
	R=$(RunSQL "$Q")
	selectIndex=0
	for thisRecord in $R; do
		let selectIndex++
		minerDefault=$(Field 2 "$R")
		if [[ "$minerDefalut" == "1" ]]; then
			break
		fi
	done

	
	
	instance=0	
	profileProgress=""
	addedInstances=""
	finished=""
	until [[ "$finished" == "1" ]]; do
		let instance++
		clear
		ShowHeader
		profileProgress="Profile: $profileName (adding miner instance #$instance)\n"
		#profileProgress="$profileProgress--------------------------------------------------------------------------------\n"



		echo -e "$profileProgress"
		echo -e "$addedInstances"

		Q="Select pk_miner, name from miner WHERE fk_machine=$thisMachine ORDER BY pk_miner;"
		E="Please select the miner from the list above to use with this instance"
		GetPrimaryKeySelection thisMiner "$Q" "$E" "$selectIndex"
		echo ""

		Q="SELECT pk_worker, pool.name || '.' || worker.name AS fullName FROM worker LEFT JOIN pool ON worker.fk_pool = pool.pk_pool;"
		E="Please select the pool worker from the list above to use with this instance"
		GetPrimaryKeySelection thisWorker "$Q" "$E"
		echo ""
	
	
		Q="SELECT pk_device, name FROM device WHERE fk_machine=$thisMachine ORDER BY device;"
		E="Please select the device from the list above to use with this instance"
		GetPrimaryKeySelection thisDevice "$Q" "$E"

		
		Q="INSERT INTO profile_map (fk_device,fk_miner,fk_worker,fk_profile) VALUES ($thisDevice,$thisMiner,$thisWorker,$profileID);"
		R=$(RunSQL "$Q")

		clear
		ShowHeader
		Q="SELECT device.name, pool.name || '.' || worker.name AS fullName, miner.name FROM profile_map LEFT JOIN miner ON profile_map.fk_miner = miner.pk_miner LEFT JOIN device on profile_map.fk_device = device.pk_device LEFT JOIN worker on profile_map.fk_worker = worker.pk_worker LEFT JOIN pool ON worker.fk_pool=pool.pk_pool  WHERE fk_profile = $profileID ORDER BY pk_profile_map ASC;
"
		R=$(RunSQL "$Q")
		addedInstances=""
		for row in $R; do
			addedDevice=$(Field 1 "$row")
			addedWorker=$(Field 2 "$row")
			addedMiner=$(Field 3 "$row")
			addedInstances="$addedInstances $addedMiner - $addedDevice - $addedWorker\n"
		done
		addedInstances="$addedInstances\n"
		echo -e "$profileProgress"
		echo -e "$addedInstances"
		echo ""
		E="Your current progress on this profile is listed above."
		E="$E Would you like to continue adding instances to this profile? (y)es or (n)o?"
		GetYesNoSelection resp "$E"

		if [[ "$resp" == "0" ]]; then
			finished="1"
		fi
	done	
	clear
	ShowHeader
	echo " Your profile is now finished. You can activate it at any time now in the profiles menu."
	sleep 5
}

Edit_Profile()
{

	
	clear
	ShowHeader
	echo "SELECT PROFILE TO EDIT"

	Q="SELECT pk_machine,name from machine"
	E="Select the machine you wish to edit the profile on"
	GetPrimaryKeySelection thisMachine "$Q" "$E"

	echo ""
	Q="SELECT pk_profile, name FROM profile WHERE fk_machine=$thisMachine;"
	E="Please select the profile from the list above to edit"
	GetPrimaryKeySelection thisProfile "$Q" "$E"
	echo ""
	
	Q="SELECT name FROM profile WHERE pk_profile='$thisProfile';"
	R=$(RunSQL "$Q")
	local profileName=$(Field 1 "$R")

	local exitEditProfile=""
	while [[ "$exitEditProfile" == "" ]]; do
		clear
		ShowHeader
		echo "EDITING PROFILE: '$profileName'"
		Q="SELECT pk_profile_map, device.name || ' - ' || pool.name || '.' || worker.name || ' - ' || miner.name AS fullName FROM profile_map LEFT JOIN miner ON profile_map.fk_miner = miner.pk_miner LEFT JOIN device on profile_map.fk_device = device.pk_device LEFT JOIN worker on profile_map.fk_worker = worker.pk_worker LEFT JOIN pool ON worker.fk_pool=pool.pk_pool  WHERE fk_profile = '$thisProfile' ORDER BY device.name ASC, pool.name ASC, worker.name ASC, miner.name ASC, pk_profile_map ASC;"
		R=$(RunSQL "$Q")

		i=0
		for row in $R; do
			let i++
			pkProfileMap=$(Field 1 "$row")
			instance=$(Field 2 "$row")
			echo "$i) $instance‌"
		done
	
		echo ""
		echo "The instances of this profile are listed above."
		echo "Would you like to (A)dd, (E)dit or (D)elete profile instances?"
		echo "(X) to exit back to the main menu if you are finished editing this profile."
		action=$(GetAEDSelection)
                echo ""

		case "$action" in
		ADD)
			clear
			ShowHeader
			echo "ADD PROFILE INSTANCE"
			echo ""
			Q="Select pk_miner, name from miner WHERE fk_machine=$thisMachine ORDER BY pk_miner;"
			E="Please select the miner from the list above to use with this instance"
			GetPrimaryKeySelection thisMiner "$Q" "$E"
			echo ""

			Q="SELECT pk_worker, pool.name || '.' || worker.name AS fullName FROM worker LEFT JOIN pool ON worker.fk_pool = pool.pk_pool;"
			E="Please select the pool worker from the list above to use with this instance"
			GetPrimaryKeySelection thisWorker "$Q" "$E"
			echo ""
	
	
			Q="SELECT pk_device, name FROM device WHERE fk_machine=$thisMachine ORDER BY device;"
			E="Please select the device from the list above to use with this instance"
			GetPrimaryKeySelection thisDevice "$Q" "$E"

			echo "Inserting new instance..."
			Q="INSERT INTO profile_map (fk_device,fk_miner,fk_worker,fk_profile) VALUES ($thisDevice,$thisMiner,$thisWorker,$thisProfile);"
			RunSQL "$Q"
			echo "done."
			sleep 2
			;;
		DELETE)
			clear
			ShowHeader
			echo "DELETE PROFILE INSTANCE"
			echo ""
			E="Which instance above do you want to delete?"
			GetPrimaryKeySelection deletePK "$Q" "$E"
			echo "Deleting instance..."
			Q="DELETE FROM profile_map WHERE pk_profile_map='$deletePK';"
			RunSQL "$Q"
			echo "done."
			sleep 2

			;;
		EDIT)
			clear
			ShowHeader
			echo "EDIT PROFILE INSTANCE"
			echo ""
			E="Which instance above do you want to edit?"
			GetPrimaryKeySelection editPK "$Q" "$E"
			echo ""

			Q="SELECT fk_miner, fk_worker, fk_device FROM profile_map WHERE pk_profile_map='$editPK';"
			R=$(RunSQL "$Q")
			cminer=$(Field 1 "$R")
			cworker=$(Field 2 "$R")
			cdevice=$(Field 3 "$R")

			Q="Select pk_miner, name from miner WHERE fk_machine=$thisMachine ORDER BY pk_miner;"
			E="Please select the miner from the list above to use with this instance"
			GetPrimaryKeySelection thisMiner "$Q" "$E" "$cminer"
			echo ""

			Q="SELECT pk_worker, pool.name || '.' || worker.name AS fullName FROM worker LEFT JOIN pool ON worker.fk_pool = pool.pk_pool;"
			E="Please select the pool worker from the list above to use with this instance"
			GetPrimaryKeySelection thisWorker "$Q" "$E" "$cworker"
			echo ""
	
	
			Q="SELECT pk_device, name FROM device WHERE fk_machine=$thisMachine ORDER BY device;"
			E="Please select the device from the list above to use with this instance"
			GetPrimaryKeySelection thisDevice "$Q" "$E" "$cdevice"


			echo "Updating instance..."
			Q="UPDATE profile_map SET fk_miner='$thisMiner', fk_worker='$thisWorker', fk_device='$thisDevice' WHERE pk_profile_map='$editPK';"
			RunSQL "$Q"
			echo "done."
			sleep 2

			;;
  		EXIT)
    			exitEditProfile="1"
			;;
		*)
			DisplayError "Invalid selection!" "5"
			;;      
		esac 
		
	done


	
}

Delete_Profile()
{
	clear
	ShowHeader
	echo "SELECT PROFILE TO DELETE"
	Q="SELECT pk_machine,name from machine"
	E="Select the machine you wish to delete the profile from"
	GetPrimaryKeySelection thisMachine "$Q" "$E"
	
	empty=$(tableIsEmpty "profile" "WHERE fk_machine=$thisMachine")
	if [[ "$empty" ]]; then
		echo ""
		echo "There are no profiles to delete."
		sleep 3
		return
	fi

	Q="SELECT pk_profile, name FROM profile WHERE fk_machine=$thisMachine;"
	E="Please select the profile from the list above to delete"
	GetPrimaryKeySelection thisProfile "$Q" "$E"

	echo "Deleting profile..."
	# Get a list of the profile_map entries that reference the profile...
	Q="DELETE FROM profile_map WHERE fk_profile=$thisProfile;"

	# And finally, delete the profile!
	Q="DELETE FROM profile WHERE pk_profile=$thisProfile;"
	RunSQL "$Q"
	echo "done."
	sleep 1

}


Do_Devices() {
	clear
	ShowHeader
	#Add/Edit/Delete?
	AddEditDelete "devices"
	action=$(GetAEDSelection)
                
	case "$action" in
	ADD)
		Add_Device
		;;
	DELETE)
		Delete_Device
		;;
	EDIT)
		Edit_Device
		;;
  	EXIT)
    		return
    		;;
	*)
		DisplayError "Invalid selection!" "5"
		;;      
	esac     


}
Add_Device() 
{
	clear
	ShowHeader
	echo "ADDING DEVICE"
	echo "-------------"

	Q="SELECT pk_machine,name from machine"
	E="Select the machine you wish to add the device on"
	GetPrimaryKeySelection thisMachine "$Q" "$E"

	echo "Give this device a nickname"
	read deviceName
	echo ""

	echo "Enter the device type: ('gpu' or 'cpu')"
	read -e -i "gpu" deviceType
	echo ""

	echo "Enter the OpenCL device number (if applicable)"
	read  deviceDevice
	echo ""

	E="Would you like this device to be available to the automatic profile? (y)es or (n)o?"
	GetYesNoSelection deviceAllow "$E"


	E="Do you want to disable this device?"
	GetYesNoSelection deviceDisabled "$E"
	
	

	
        echo "Adding Device..."
        Q="INSERT INTO device (name,device,disabled,fk_machine,auto_allow,type) VALUES ('$deviceName','$deviceDevice','$deviceDisabled','$thisMachine','$deviceAllow','$deviceType');"
        RunSQL "$Q"
	#screen -r $sessionName -X wall "Device Added!" #TODO: Get This working!!!
	echo "done."
	sleep 1
	Reload $thisMachine "Device information has been changed. Reloading miners."
}
Edit_Device() 
{
	clear
	ShowHeader
	Q="SELECT pk_machine, name from machine;"                               
	E="Please select the machine from the list above that is hosting this device"                          
	GetPrimaryKeySelection thisMachine "$Q" "$E"

	empty=$(tableIsEmpty "device" "WHERE fk_machine=$thisMachine")
	if [[ "$empty" ]]; then
		echo ""
		echo "There are no devices to edit."
		sleep 3
		return
	fi


	Q="SELECT pk_device, name FROM device WHERE fk_machine=$thisMachine;"
	E="Please select the device from the list above to edit"
	GetPrimaryKeySelection EditPK "$Q" "$E"
        
	Q="SELECT name,device,auto_allow,disabled,type FROM device WHERE pk_device=$EditPK;"
	R=$(RunSQL "$Q")
	cname=$(Field 1 "$R")
	cdevice=$(Field 2 "$R")
	callow=$(Field 3 "$R")
	cdisabled=$(Field 4 "$R")
	ctype=$(Field 5 "$R")

	cmachine=$thisMachine

	clear
	ShowHeader
	echo "EDITING DEVICE"
	echo "--------------"

	Q="SELECT pk_machine,name from machine"
	E="Select the machine for this device"
	GetPrimaryKeySelection thisMachine "$Q" "$E" "$cmachine"

	echo "Give this device a nickname"
	read -e -i "$cname" deviceName
	echo ""

	echo "Enter the device type: ('gpu' or 'cpu')"
	read -e -i "$ctype" deviceType
	echo ""

	echo "Enter the OpenCL device number (if applicable)"
	read  -e -i "$cdevice" deviceDevice
	echo ""

	
	E="Would you like this device to be available to the automatic profile? (y)es or (n)o?"
	GetYesNoSelection deviceAllow "$E" "$callow"

	E="Do you want to disable this device?"
	GetYesNoSelection deviceDisabled "$E" "$cdisabled"

        echo "Updating Device..."

        Q="UPDATE device SET name='$deviceName', device='$deviceDevice', fk_machine='$thisMachine', disabled='$deviceDisabled', auto_allow='$deviceAllow', type='$deviceType' WHERE pk_device='$EditPK'"
        RunSQL "$Q"
	echo done
	sleep 1
	Reload "Device information has been changed. Reloading miners."
}
Delete_Device()
{
	clear
	ShowHeader
	echo "SELECT DEVICE TO DELETE"
	Q="SELECT pk_machine, name from machine;"                               
	E="Please select the machine from the list above that is hosting this device"                          
	GetPrimaryKeySelection thisMachine "$Q" "$E"

	empty=$(tableIsEmpty "device" "WHERE fk_machine=$thisMachine")
	if [[ "$empty" ]]; then
		echo ""
		echo "There are no devices to delete."
		sleep 3
		return
	fi


	Q="SELECT pk_device, name FROM device WHERE fk_machine=$thisMachine;"
	E="Please select the device from the list above to delete"
	GetPrimaryKeySelection thisDevice "$Q" "$E"

	echo "Deleting device..."


	# Delete entries from the profile profile_map that use this device!
	Q="DELETE from profile_map where fk_device=$thisDevice;"
	RunSQL "$Q"

	# And finally, delete the device!
	Q="DELETE FROM device WHERE pk_device=$thisDevice;"
	RunSQL "$Q"
	echo "done."
	sleep 1
	Reload "Device information has been changed. Reloading miners."
}

Do_Macro() {
	clear
	ShowHeader
	#Add/Edit/Delete?
	AddEditDelete "macros"
	action=$(GetAEDSelection)
                
	case "$action" in
	ADD)
		Add_Macro
		;;
	DELETE)
		Delete_Macro
		;;
	EDIT)
		Edit_Macro
		;;
  	EXIT)
    		return
    		;;
	*)
		DisplayError "Invalid selection!" "5"
		;;      
	esac     


}

Add_Macro() {
	clear
	ShowHeader
	echo "ADDING MACRO"
	echo "------------"
	echo ""

	local macroName
	echo "Please enter a name for this macro"
	read macroName
	echo ""

	# Insert the new record
	Q="INSERT INTO macro (name) VALUES ('$macroName');"
	RunSQL "$Q"
	# get the PK of the new record
	Q="SELECT pk_macro FROM macro ORDER BY pk_macro DESC LIMIT 1;"
	R=$(RunSQL "$Q")
	local insertedId=$(Field 1 "$R")


	local exitLoop=""
	while [[ "$exitLoop" == "" ]]; do
		clear
		ShowHeader
		echo "ADDING MACRO"
		echo "------------"
		echo ""
		echo "Macro \"$macroName\" current progress:"
		echo "Machine			Profile"
		echo "----------------------------------------"
		Q="SELECT COUNT(*) FROM macro_map WHERE fk_macro='$insertedId';"
		R=$(RunSQL "$Q")
		local numEntries=$(Field 1 "$R")
	
		if [[ "$numEntries" -lt "1" ]]; then
			echo "<<<NO MACRO ENTRIES>>>"
		else
			Q="SELECT machine.name, fk_profile from macro_map LEFT JOIN machine ON macro_map.fk_machine = machine.pk_machine WHERE macro_map.fk_macro='$insertedId';"
			R=$(RunSQL "$Q")
			for row in $R; do
				local machineName=$(Field 1 "$row")
				local profileId=$(Field 2 "$row")
				local profileName=$(GenProfileName $profileId)
				echo "$machineName		$profileName"
			done
		fi
			echo ""
		echo "----------------------------------------"
		echo ""

		E="Your current progress on this macro is listed above."
		E="$E Would you like to add to this macro? (y)es or (n)o?"
		GetYesNoSelection resp "$E"
		echo ""
		if [[ "$resp" == "0" ]]; then
			break
		fi

		Q="SELECT pk_machine, name from machine;"                               
		E="Please select a machine from the list above for this macro to change the profile on"                          
		GetPrimaryKeySelection thisMachine "$Q" "$E"
		echo ""

		# TODO: Make an external function for building full profile autoentry list?
		# Add the flags for the dynamically generated profiles
		local autoEntry=$(FieldArrayAdd "-2	1	Donation")
		autoEntry=$autoEntry$(FieldArrayAdd "-1	2	Automatic")
		autoEntry=$autoEntry$(FieldArrayAdd "-3	3	Failover")
		autoEntry=$autoEntry$(FieldArrayAdd "-4	4	Idle")

		# Display menu
		Q="SELECT pk_profile, name FROM profile where fk_machine=$thisMachine AND pk_profile>0 ORDER BY pk_profile ASC;"
		E="Select the profile from the list above that you wish to switch to"
		GetPrimaryKeySelection thisProfile "$Q" "$E" "" "$autoEntry"
		echo ""

		echo "Updating macro..."
		Q="INSERT INTO macro_map (fk_macro, fk_machine, fk_profile) VALUES ('$insertedId','$thisMachine','$thisProfile');"
		RunSQL "$Q"
		echo "done"
		sleep1

	done

	return 0

}


Edit_Macro() {
	clear
	ShowHeader
	echo "EDIT MACRO"
	echo "-----------"
	echo ""
	echo "Not yet implemented."
	sleep 3
	return 0
}

Delete_Macro() {
	clear
	ShowHeader
	echo "DELETE MACRO"
	echo "------------"
	echo ""

	Q="SELECT COUNT(*) FROM macro;"
	R=$(RunSQL "$Q")
	local numMacros=$(Field 1 "$R")
	if [[ "$numMacros" -lt "1" ]]; then
		echo "There are no macros to delete!"
		echo "(Press any key to continue)"
		read
		return 1
	fi

	local thisMacro
	Q="SELECT pk_macro,name FROM macro;"
	E="Select the macro from the list above that you wish to delete:"
	GetPrimaryKeySelection thisMacro "$Q" "$E"
	echo ""

	echo "Deleting macro..."
	# Delete macro_map entries, followed by the macro entry
	Q="DELETE FROM macro_map WHERE fk_macro='$thisMacro';"
	RunSQL "$Q"
	Q="DELETE FROM macro WHERE pk_macro='$thisMacro';"
	RunSQL "$Q"
	echo "Done."
	sleep 1
	return 0
}

Execute_Macro() {
	clear
	ShowHeader
	echo "EXECUTE MACRO"
	echo "-------------"
	echo ""

	Q="SELECT COUNT(*) FROM macro;"
	R=$(RunSQL "$Q")
	local numMacros=$(Field 1 "$R")
	if [[ "$numMacros" -lt "1" ]]; then
		echo "There are no macros to execute!"
		echo "(Press any key to continue)"
		read
		return 1
	fi

	local thisMacro
	Q="SELECT pk_macro,name FROM macro;"
	E="Select the macro from the list above that you wish to execute:"
	GetPrimaryKeySelection thisMacro "$Q" "$E"
	echo ""

	echo "Executing macro..."
	# Lets populate the current machine profiles from the macro information!
	Q="SELECT fk_machine,fk_profile FROM macro_map WHERE fk_macro='$thisMacro';"
	R=$(RunSQL "$Q")
	for row in $R; do
		local thisMachine=$(Field 1 "$row")
		local thisProfile=$(Field 2 "$row")
		Q="DELETE from current_profile WHERE fk_machine='$thisMachine';"
		RunSQL "$Q"
		Q="INSERT INTO current_profile (fk_machine,fk_profile) VALUES ('$thisMachine','$thisProfile');"
		RunSQL "$Q"
	done
	echo "Done."
	sleep 1

	return 0
}

while true
do
	clear
	ShowHeader
	echo "1) Reboot Computer"
	echo "2) Kill smartcoin (exit)"
	echo "3) Disconnect from smartcoin (leave running)"
	echo "4) Edit Settings"
	echo "5) Select Profile"
	echo "6) Configure Miners"
	echo "7) Configure Workers"
	echo "8) Configure Profiles"
	echo "9) Configure Devices"
	echo "10) Configure Pools"
	echo "11) Update Smartcoin"
	echo "12) Set Failover Order"
	echo "13) Configure Machines"
	echo "14) Configure Macros"
	echo "15) Execute Macro"


	read selection

	case "$selection" in
		1)
			echo "Are you sure you want to reboot? (y)es or (n)o?"
			resp=""
			until [[ "$resp" != "" ]]; do
				read available
			        
				available=`echo $available | tr '[A-Z]' '[a-z]'`
				if [[ "$available" == "y" ]]; then
					resp="1"
				elif [[ "$available" == "n" ]]; then
					resp="0"
				else
					echo "Invalid response!"
		
	
				fi
			done	
			if [[ "$resp" == "1" ]]; then
				Log "Reboot option selected" 1
				echo "Going down for a reboot."
				sudo reboot
			fi
			;;
		2)
			Log "Exit option selected"
			# Kill the miners
			# TODO: Kill ALL miners, not just localhost!
			killMiners 1
			# Commit suicide
			screen -d -r $sessionName -X quit
			;;
			
		3)
			Log "Disconnect option selected"
			screen -d $sessionName
			;;

		4)
			Log "Settings option selected"
			Do_Settings
			;;
		5)
			Log "Change Profile option selected"
			Do_ChangeProfile
			;;
		6)	
			Log "Configure Miners option selected"
			Do_Miners
			;;
		7)
			Log "Configure Workers option selected"
			Do_Workers
			;;

		8)
			Log "Configure Profiles option selected"
			Do_Profile
			;;
	
		9)
			Log "Configure Devices option selected"
			Do_Devices
			;;

		10)
			Log "Configure Pools option selected"
			Do_Pools
			;;
		11)
			Log "Update option selected"
      			Do_Update
      			;;
		12)
			Log "Set Failover Order option selected"
			Do_SetFailoverOrder
			;;
		13)
			Log "Configure Machines option selected"
			Do_Machines
			;;
		14)
			Log "Configure Macros option selected"
			Do_Macro
			;;
		15)
			Log "Execute Macro option selected"
			Execute_Macro
			;;
		*)

			;;
	esac
done






