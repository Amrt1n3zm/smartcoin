#!/bin/bash
#clear
#echo "Starting..."

minerPath="$1"
minerLaunch="$2"
exportPath="$3"

echo "Exporting: $exportPath"
echo "LAUNCH: $minerLaunch"


# Make sure phoenix install location can be found
case "$minerLaunch" in
*phoenix.py*)
	# Phoenix requires its path be in $LD_LIBRARY_PATH to launch from script
	if [[ "$LD_LIBRARY_PATH" != *$minerPath* ]]; then
		# It has not yet been added. Add the phoenixPath to LD_LIBRARY_PATH
		export LD_LIBRARY_PATH=$minerPath:$LD_LIBRARY_PATH
	fi
	;;
esac

# Make sure that the AMD/ATI SDK location can be found
if [[ "$LD_LIBRARY_PATH" != *$exportPath* ]]; then
	export LD_LIBRARY_PATH=$exportPath:$LD_LIBRARY_PATH
fi

# Note: do not quote these!
cd $minerPath && $minerLaunch

