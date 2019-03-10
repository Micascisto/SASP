#!/bin/bash

# Script to mapproject the Level 1eo images of a stereopair onto the low-res DEM created in the previous step. Then run the map-projected images through parallel_stereo.
# The purpose of this is to combine the benefits of bundle_adjust with those of proving ASP with map-projected images. This 2-step approach is meant to help remove some of the
#  spurious jagged edges that can appear on steep slopes in DEMs made from un-projected images.
# This script is capable of processing many stereopairs in a single run and uses GNU parallel to improve the efficiency of the processing and reduce total wall time.  


# Dependencies:
#   NASA Ames Stereo Pipeline
#   USGS ISIS3
#   GDAL
#   GNU parallel
# Optional dependency:
#   Dan's GDAL Scripts https://github.com/gina-alaska/dans-gdal-scripts
#    (used to generate footprint shapefile based on initial DEM)


# Just a simple function to print a usage message
print_usage (){
echo
echo "Usage: $(basename $0) -s <stereo.default> -p <productIDs.lis> -c <number-CPU>"
echo "<stereo.default> is the name and absolute path to the stereo.default file to be used by parallel_stereo"
echo "<productIDs.lis> is a file containing a list of the IDs of the CTX products to be processed"
echo "<number-CPU> is the number of physical CPU cores to be used"
echo
echo "-> These scripts are optimized to use Normalized Cross Correlation at this stage, make sure to set it up in stereo.default"
echo "-> Product IDs belonging to a stereopair must be listed sequentially."
# echo "-> The script will search for CTX Level 1eo products in the current directory before processing with ASP."
}

### Check for sane commandline arguments
if [[ $# = 0 ]] || [[ "$1" != "-"* ]]; then
    print_usage
    exit 0

# Else use getopts to parse flags that may have been set
elif  [[ "$1" = "-"* ]]; then
    while getopts ":p:s:c:" opt; do
        case $opt in
            p)
                prods=$OPTARG
                if [ ! -e "$OPTARG" ]; then
                    echo "$OPTARG not found" >&2
                    print_usage
                    exit 1
                fi
                ;;
            s)
                config=$OPTARG
                if [ ! -e "$OPTARG" ]; then
                    echo "$OPTARG not found" >&2
                    print_usage
                    exit 1
                fi
                export config=$OPTARG
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
                echo "Invalid option: -$OPTARG" >&2
                exit 1
                ;;
            :)
                # Error to prevent script from continuing if flag is not followed by at least 1 argument
                echo "Option -$OPTARG requires an argument." >&2
                exit 1
                ;;
        esac
   done
fi

# If we've made it this far, commandline args look sane and specified files exist
# Check that ISIS has been initialized by looking for pds2isis, if not, initialize it
if [[ $(which pds2isis) = "" ]]; then
    echo "Initializing ISIS3"
    source $ISISROOT/scripts/isis3Startup.sh
    # Quick test to make sure that initialization worked
    # If not, print an error and exit
    if [[ $(which pds2isis) = "" ]]; then
        echo "ERROR: Failed to initialize ISIS3" 1>&2
        exit 1
    fi
fi


##   Start the big bad FOR loop to mapproject the bundle_adjust'd images onto the corresponding low-res DEM and pass to parallel_stereo
echo "Start $(basename $0) @ "$(date)
for i in $( cat stereodirs.lis ); do
    cd $i

    # Store the complete path to the DEM we will use as the basis of the map projection step in a variable called $refdem
    refdem=${PWD}/results_ba/dem/${i}_ba_100_fill50-DEM.tif

    # If the specified DEM does not exist or does not have nonzero size, throw an error and immediately continue to the next iteration of the FOR loop.
    if [ ! -s "$refdem" ]; then
        echo "The specified DEM does not exist or has zero size"
        echo $refdem
        cd ../
        continue
    fi

    # Store the names of the Level1 EO cubes in variables
    Lcam=$(awk '{print($1".lev1eo.cub")}' stereopair.lis)
    Rcam=$(awk '{print($2".lev1eo.cub")}' stereopair.lis)

    # Mapproject the CTX images against a specific DTM using the adjusted camera information
    # TODO: use actual image resolutions instead of 6 m
    echo "Projecting "$Lcam" against "$refdem
    awk -v refdem=$refdem -v L=$Lcam '{print("mapproject -t isis "refdem" "L" "$1".ba.map.tif --mpp 6 --bundle-adjust-prefix adjust/ba")}' stereopair.lis | sh
    echo "Projecting "$Rcam" against "$refdem
    awk -v refdem=$refdem -v R=$Rcam '{print("mapproject -t isis "refdem" "R" "$2".ba.map.tif --mpp 6 --bundle-adjust-prefix adjust/ba")}' stereopair.lis | sh

    # Store the names of the map-projected cubes in variables
    Lmap=$(awk '{print($1".ba.map.tif")}' stereopair.lis)
    Rmap=$(awk '{print($2".ba.map.tif")}' stereopair.lis)

    # This was once broken into stages, but I believe it complicates things and doesn't work so well. For instance, step 4 was run with 8 threads on a 4 core machine.
    parallel_stereo -t isis --processes ${cpus} --threads-multiprocess 1 --threads-singleprocess 4 $Lmap $Rmap $Lcam $Rcam -s ${config} results_map_ba/${i}_map_ba --bundle-adjust-prefix adjust/ba $refdem
    
    
    # Extract the projection info from previosuly generated file
    proj4=$(cat ${i}.proj4)
    
    # cd into the results directory for stereopair $i
    cd results_map_ba/
    # Run point2dem with orthoimage and intersection error image outputs. No hole filling.
    # TODO: extract the worst resolution out of the stereopair (caminfo??) and do x3 to calculate output DEM resolution
    echo "Running point2dem..."
    echo point2dem --threads 16 --t_srs \"${proj4}\" -r mars --nodata -32767 -s 18 -n --errorimage ${i}_map_ba-PC.tif --orthoimage ${i}_map_ba-L.tif -o dem/${i}_map_ba | sh

    # Generate hillshade (useful for getting feel for textural quality of the DEM)
    echo "Running gdaldem hillshade"
    gdaldem hillshade ./dem/${i}_map_ba-DEM.tif ./dem/${i}_map_ba-hillshade.tif

    ## OPTIONAL ##
    # # Create a shapefile containing the footprint of the valid data area of the DEM 
    # # This requires the `gdal_trace_outline` tool from the "Dan's GDAL Scripts" collection
    # # If you don't have this tool installed and don't comment out the next line, the script will throw an error but will continue to execute
    # gdal_trace_outline dem/${i}_ba-DEM.tif -ndv -32767 -erosion -out-cs en -ogr-out dem/${i}_ba_footprint.shp

    cd ../../
done

echo "Finished $(basename $0) @ "$(date)

# TODO
# Experiment with aligning low-res DEM with MOLA, see if it yields better results.
# cleaner work folder, leave only files that are absolutely necessary
# test and possibly optimize multithreading with Intel hyperthreading
