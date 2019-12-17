#!/bin/bash

# Run pc_align using a CSV of MOLA shots as a reference, then create a DEM at 24 m/px and an orthoimage at 6 m/px

# Input: text file containing list of the root directories for each stereopair
# Output will be sent to <stereopair root dir>/results/dem_align

# Dependencies:
#    NASA Ames Stereo Pipeline
#    USGS ISIS3
#    GDAL


# Function to print a usage message
print_usage (){
	echo ""
	echo "Usage: $(basename $0) -d <stereodirs.lis> -m <max-displacement> -c <number-CPU>"
	echo "<stereodirs.lis> is a file containing the name of the subdirectories to loop over, 1 per line"
	echo "<max-displacement> is the maximum displacement to pass to pc_align"
	echo "<number-CPU> is the number of physical CPU cores to be used"
	echo
	echo "-> Subdirectories containing stereopairs must all exist within the same root directory"
	echo "-> The names listed in <stereodirs.lis> will be used as the file prefix for the output"
}


# Check for sane commandline arguments
if [[ $# = 0 ]] || [[ "$1" != "-"* ]] ; then
	print_usage
	exit

# Use getopts to parse arguments/flags
elif  [[ "$1" = "-"* ]]; then
	while getopts ":d:m:c:" opt; do
		case $opt in
			d)
				if [ ! -e "$OPTARG" ]; then
	      		echo "ERROR: File $OPTARG not found"
	         	print_usage
	        		exit 1
	      		fi
	      		dirs=$OPTARG
				;;
			m)     
				# Test that the argument accompanying m is a positive integer
				if ! test "$OPTARG" -gt 0 2> /dev/null ; then
					echo "ERROR: $OPTARG not a valid argument"
					echo "The maximum displacement must be a positive integer"
					print_usage
					exit 1
				else
					maxd=$OPTARG
				fi
				;;
			c)
				# Test that the argument accompanying c is a positive integer
	      		if ! test "$OPTARG" -gt 0 2> /dev/null ; then
	        		echo "ERROR: $OPTARG not a valid argument"
	            	echo "The number of CPUs must be a positive integer"
	            	print_usage
	        		exit 1
	      		else
					cpus=$OPTARG
				fi
				;;				
		   \?)
	      	# Error to stop the script if an invalid option is passed
	      	echo "Invalid option: -$OPTARG"
	      	print_usage
	      	exit 1
	      	;;
	      :)
	      	# Error to prevent script from continuing if flag is not followed by at least 1 argument
	      	echo "ERROR: Option -$OPTARG requires an argument."
	      	print_usage
	      	exit 1
	      	;;
		esac
	done
fi 


## Release the Kraken!

echo "Start 5_asp_ctx_map_ba_pc_align2dem_sn.sh @ "$(date)
# loop through the directories listed in "stereodirs.lis" and run pc_align, point2dem, dem_geoid, etc.
for i in $( cat ${dirs} ); do
	echo Working on $i
	cd $i

	# extract the proj4 string from one of the map-projected image cubes and store it in a variable (we'll need it later for point2dem)
	proj=$(cat ${i}.proj4)
    
	# Move down into the results directory for stereopair $i
	cd ./results_map_ba

	# run pc_align and send the output to a new subdirectory called dem_align
	echo "Running pc_align..."
	pc_align --threads ${cpus} --num-iterations 2000 --max-displacement $maxd --highest-accuracy --datum D_MARS --save-inv-transformed-reference-points ${i}_map_ba-PC.tif ../${i}_pedr.csv -o dem_align/${i}_map_ba_align
    
	# move down into the directory with the pc_align output, which should be called "dem_align"
	cd ./dem_align

	# Create 24 m/px DEM, no hole filling, plus errorimage and normalized DEM for debugging
	echo "Running point2dem..."
	echo point2dem --threads ${cpus} --t_srs \"${proj}\" -r mars --nodata -32767 -s 24 --errorimage -n ${i}_map_ba_align-trans_reference.tif -o ${i}_map_ba_align_24 | sh

	# Run dem_geoid on the aligned 24 m/px DEM so that the elevation values are comparable to MOLA products
	echo "Running dem_geoid..."
	dem_geoid --threads ${cpus} ${i}_map_ba_align_24-DEM.tif -o ${i}_map_ba_align_24-DEM
    
	# Create hillshade for 24 m/px DEM
	echo "Generating hillshade with gdaldem"
	gdaldem hillshade ${i}_map_ba_align_24-DEM.tif ${i}_map_ba_align_24-hillshade.tif
    
	# Create orthoimage, no hole-filling, no DEM
	echo "Generating orthoimage..."
	echo point2dem --threads ${cpus} --t_srs \"${proj}\" -r mars --nodata -32767 -s 6  --no-dem ${i}_map_ba_align-trans_reference.tif --orthoimage ../${i}_map_ba-L.tif -o ${i}_map_ba_align_6 | sh
    
	# Move back up to the root of the stereo project   
	cd ../../../
done
echo "Finished 5_asp_ctx_map_ba_pc_align2dem_sn.sh @ "$(date)

#TODO
# add default maximum displacement, e.g. Tim's 2000 m
# Use native resolution for orthoimage
