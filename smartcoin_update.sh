#!/bin/bash
# SmartCoin update system

if [[ $( dirname "$0" ) == "/usr/bin" ]]; then
	CUR_LOCATION=$(dirname $(readlink -f $( dirname "$0" )/smartcoin))
else
	CUR_LOCATION="$( cd "$( dirname "$0" )" && pwd )"
fi

# Make sure that any new functions are available too!
#echo "Bring helper functions up to current..."
#svn update $CUR_LOCATION/smartcoin_ops.sh >/dev/null 2>&1

#echo ""

. $CUR_LOCATION/smartcoin_ops.sh
experimental_update=$1

if [[ "$RESTART_REQ" ]]; then
	Log "Previous update changes have not yet been applied." 1
	echo "You must restart smartcoin before you attempt another update."
	sleep 5
	exit
fi



Log "Preparing to do an Update..." 1
Log "Getting current revision..."
svn_rev_start=$(GetLocal)
Log "Getting repo information..."
svn_current_repo=$(GetRepo)
Log "Getting the current experimental revision number..."
svn_rev_end=$(GetHead "$svn_current_repo")
Log "Getting the current stable revision number..."
svn_stable_rev_end=$(GetStableHead "$svn_current_repo")
Log "Checking stable update flag..."
safe_update=`svn diff -r $svn_rev_start:$svn_rev_end $CUR_LOCATION/update.ver`

if [[ -z "$experimental_update" ]]; then
	svn_rev_end=$svn_stable_rev_end
fi


# Make a list of "breakpoints"
# Breakpoints are revision numbers where the smartcoin software must be restarted before applying any more updates or patches.
# This way, users that are badly out of date will have to update several times to get to current, and the smartcoin software
# will be sure to be in the correct state to accept further updates and patches.
BP="300 "	# The database moves in this update
BP=$BP"365 "	# Stable/experimental branch stuff goes live
BP=$BP"607 "	# Settings table schema update


bp_message=""
# Determine where the new svn_rev_end should be
for thisBP in $BP; do
	if [[ "$thisBP" -gt "$svn_rev_start" ]]; then
		if [[ "$thisBP" -lt "$svn_rev_end" ]]; then
			svn_rev_end="$thisBP"
			export RESTART_REQ="1"
			bp_message="partial"
			Log "Partial update detected." 1
			echo "A partial update has been detected.  This means that you must run the partial update, restart smartcoin, then run an update again in order to bring your copy fully up to date."
			echo ""
			break		
		fi	
	fi
done



if [[ "$svn_rev_start" == "$svn_rev_end" ]]; then
	Log "You are already at the current revision r$svn_rev_start!" 1
else
	if [[ "$experimental_update" ]]; then
		#Do an experimental update!
		Log "Preparing $bp_message experimental update from r$svn_rev_start to r$svn_rev_end" 1
		svn update -r $svn_rev_end $CUR_LOCATION/
	else
    		if [[ "$safe_update" ]]; then
     			Log "Preparing $bp_message safe update from r$svn_rev_start to r$svn_rev_end" 1
     			svn update -r $svn_rev_end $CUR_LOCATION/
   		 else
      			Log "There are new experimental updates, but they aren't proven safe yet." 1
			echo "Not updating."
			echo "(press any key to continue)"
			read 
			exit
    		fi
	fi 




 
	#make sure that we backup the database before playing around with it!
	cp $HOME/.smartcoin/smartcoin.db $HOME/.smartcoin/smartcoin.db.backup

	echo ""
	Log "Applying post update patches..." 1
	# We don't want to apply patches against the start revision, as it would have already been done the previous time... So make sure we increment it!
	patchStart=$svn_rev_start
	let patchStart++
	patchEnd=$svn_rev_end
  
	for ((i=$patchStart; i<=$patchEnd; i++)); do
		case $i in
		300)
			# Update schema going into r300
			Log "Applying r$i patch..." 1
			Log "Setting up ~/.smartcoin and copying over database"
			mkdir -p $HOME/.smartcoin && cp $CUR_LOCATION/smartcoin.db $HOME/.smartcoin/smartcoin.db
			rm $CUR_LOCATION/smartcoin.db	#No reason to have it here. It will be updated to current on the next update.
       
			Log "Setting the dev_branch setting variable"
		        # Set up by default for stable updates!
		        Q="DELETE FROM settings WHERE data='dev_branch';"
		        RunSQL "$Q"
		        Q="INSERT INTO settings (data,value,description) VALUES ('dev_branch','stable','Development branch to follow (stable/experimental)');"
		        RunSQL "$Q"
             		;;
           
		351)            
                	Log "Applying r$i patch..." 1
			Log "Altering the profile table for the new Failover system"
			Q="ALTER TABLE profile ADD down bool NOT NULL DEFAULT(0);"
			RunSQL "$Q"
			Q="ALTER TABLE profile ADD failover_order int NOT NULL DEFAULT(0);"
			RunSQL "$Q"
			Q="ALTER TABLE profile ADD failover_count int NOT NULL DFAULT(0);"
			RunSQL "$Q"
			;;

		365)
			Log "Applying r$i patch..." 1
			Q="DELETE FROM settings WHERE data='dev_branch';"
			RunSQL "$Q"
			Q="INSERT INTO settings (data,value,description) VALUES ('dev_branch','stable','Development branch to follow (stable/experimental)');"
			RunSQL "$Q"
			
			;;
		384)
			Log "Applying r$i patch..." 1
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

			;;
		387)
			Log "Applying r$i patch..." 1
			echo ""
			echo "Please enter an administration email address where you would like to receive notifications. (You can leave this blank if you do not wish to receive notifications)"
			read emailAddress
			Q="INSERT INTO settings (data,value,description) VALUES ('email','$emailAddress','Administrator email address');"
			RunSQL "$Q"
			echo ""
			echo "Email setting updated."
			echo ""
			;;
		458)
			Log "Applying r$i patch..." 1
			echo ""
			Log "Creating format setting..." 1
			Q="INSERT INTO settings (data,value,description) VALUES ('format','[<#hashrate#> MHash/sec] [<#accepted#> Accepted] [<#rejected#> Rejected] [<#rejected_percent#>% Rejected]','Miner output format string');"
			RunSQL "$Q"
			;;
		490)
			Log "Applying r$i patch..." 1                           
                        echo "" 		
			# Set up threshold default values                                               
			Q="INSERT INTO settings (data,value,description) VALUES ('failover_threshold','10','Failover Threshold');"                                                      
			RunSQL "$Q"                                                                     
                                                                                
			Q="INSERT INTO settings (data,value,description) VALUES ('failover_rejection','10','Failover on rejection % higher than');"                                     
			RunSQL "$Q"                                                                     
                                                                                			
			Q="INSERT INTO settings (data,value,description) VALUES ('lockup_threshold','50','Lockup Threshold');"                                                          
			RunSQL "$Q"    
			;;
		502)
			Log "Applying r$i patch..." 1                           
                        echo "" 	
			# Set up loop delay for statu screens
			Q="INSERT INTO settings (data,value,description) VALUES ('loop_delay','0','Status screen loop delay (higher value runs slower)');"                                                      
			RunSQL "$Q" 
			;;
		607)
			Log "Applying r$i patch..." 1                           
                        echo "" 

			echo "Updating settings table schema..."
			# Update the schema
			Q="ALTER TABLE settings ADD COLUMN information varchar(255);"
			RunSQL "$Q"

			Q="ALTER TABLE settings ADD COLUMN fk_machine integer"
			RunSQL "$Q"

			Q="ALTER TABLE settings ADD COLUMN display_order integer;"
			RunSQL "$Q"
			echo ""


			# Patch the existing entries
			echo "Patching existing entries..."
			# General Entries
			Q="UPDATE settings SET fk_machine='0' WHERE data='dev_branch' OR data='email' OR data='format' OR data='donation_time' OR data='donation_start';"
			RunSQL "$Q"
			# Machine Entries
			Q="UPDATE settings SET fk_machine='1' WHERE data='AMD_SDK_location' OR data='failover_threshold' OR data='failover_rejection' OR data='lockup_threshold' OR data='loop_delay';"
			RunSQL "$Q"
			# Remove defunct phoenix_location settings
			Q="DELETE FROM settings WHERE data='phoenix_location';"
			RunSQL "$Q"
			echo "done."
			export RESTART_REQ="1"
			;;
    		*)	

        		Log "No patches to apply to r$i"

        		;;
     		esac
	done
fi
export REVISION=$(GetRevision)
Log "Update task complete." 1

echo ""
echo "Update is now complete!"
if [[ "$RESTART_REQ" == "1" ]]; then
	echo "You should now restart smartcoin for the latest changes to take effect!"
fi

echo "Please hit any key to continue."
read blah

