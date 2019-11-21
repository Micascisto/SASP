#!/bin/bash

# Preprocessing script meant to be run as part of a CTX Ames Stereo Pipeline workflow.
# Uses USGS ISIS3 to transform CTX EDRs into Level 1 products with the even/odd detector correction applied (hence "lev1eo"), making them suitable for later processing in ASP.
# This can also be used as a general processor for CTX EDRs because it doesn't call any ASP routines.

# Requires GNU parallel

# INPUT NOTES: 
#  A textfile named productIDs.lis that contains the CTX product IDs to be processed.
#  The Product IDs of the stereopairs SHOULD be listed sequentially if you plan on using the file as input to later ASP script components, i.e.
#   Pair1_Left
#   Pair1_Right
#   Pair2_Left
#   Pair2_Right
#   etc.


# Just a simple function to print a usage message
print_usage (){
	echo
	echo "Usage: $(basename $0) -p <productIDs.lis> -n -w"
	echo "<productIDs.lis> is a file containing a list of the IDs of the CTX products to be processed"
	echo "Optional: -n flag will skip running spicefit"
	echo "Optional: -w sets the usage of spiceweb, in case ISIS3 kernels need to be downloaded"
	echo
	echo "-> Product IDs belonging to a stereopair must be listed sequentially"
	echo "-> The script will search for CTX EDRs in the current directory before processing with ISIS"
}


# Check for sane commandline arguments
if [[ "$#" -eq 0 ]] || [[ "$1" != "-"* ]]; then
	print_usage
	exit 0

elif [[ "$#" -gt 5 ]]; then
	echo "Error: Too Many Arguments"
	print_usage
	exit 1

# Use getopts to parse flags that may have been set
elif  [[ "$1" = "-"* ]]; then
	while getopts ":p:n:w" opt; do
		case $opt in
			p)
				prods=$OPTARG
				if [ ! -e "$prods" ]; then
					echo ${prods}" not found" >&2
					print_usage
					exit 1
				fi
				export prods=$OPTARG    
				;;
			n)
				n=1
				;;
			w)
				spiceweb="web=yes"
				echo "SPICE web service activated. The spice must flow!"
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
else
	print_usage
	exit 1
fi 


# Check that ISIS has been initialized by looking for pds2isis. If not, initialize it
if [[ $(which pds2isis) = "" ]]; then
	echo "Initializing ISIS3"
	source $ISISROOT/scripts/isis3Startup.sh
	# Quick test to make sure that initialization worked. If not, print an error and exit
	if [[ $(which pds2isis) = "" ]]; then
		echo "ERROR: Failed to initialize ISIS3" 1>&2
		exit 1
	fi
fi


# Store the ProductIDs in an indexed array
prodarr=($(cat $prods))
# Calculate the number of elements in the array and set the max index to be 1 less than this
# We will need these values to index a FOR loop in a moment
((n_elements=${#prodarr[@]}, max_index=n_elements - 1))

# Walk through the array and test that files corresponding to the ProductIDs in productIDs.lis exist
# For CTX, EDRs should have a filename <productID>.[IMG|.img], where the suffix depends on whether the product was downloaded from the PDS Imaging Node or the Geoscience Node
# In the if/then/else block below, we privilege the .IMG suffix in order to make sure we only process a given product once, even if multiple instances exist, but the choice of suffix is arbitrary
# If a product is missing or empty, throw a warning, unset that particular Product ID from the array but continue to execute the script
for ((i = 0; i <= max_index; i++)); do
	if [[ -e ${prodarr[$i]}.IMG ]]; then
		edrarr[$i]="${prodarr[$i]}.IMG"	
	elif [[ -e ${prodarr[$i]}.img ]]; then
		edrarr[$i]="${prodarr[$i]}.img"
	else
		echo "Warning: "${prodarr[$i]}" EDR not found, exiting" 1>&2
		unset -v 'prodarr[$i]'
		exit 0
	fi
done
# Force recalculation of array indices to remove gaps in case we have made the array sparse
prodarr=("${prodarr[@]}")
edrarr=("${edrarr[@]}")


## ISIS Processing
echo "Start $(basename $0) @ "$(date)

# Ingest CTX EDRs into ISIS using mroctx2isis
echo "Running mroctx2isis"
echo "${edrarr[@]}" | tr ' ' '\n' | parallel --joblog mroctx2isis.log mroctx2isis from={} to={.}.cub

# Add SPICE data using spiceinit
echo "Running spiceinit"
parallel --joblog spiceinit.log spiceinit ${spiceweb} from={}.cub ::: ${prodarr[@]} 

# Apply spicefit as appropriate based on input flag
if [[ "$n" -eq 1 ]]; then
	echo "WARNING: spicefit has been deactivated" 1>&2 
else
	#Smooth SPICE using spicefit
	echo "Running spicefit"
	parallel --joblog spicefit.log spicefit from={}.cub ::: ${prodarr[@]}  
fi

# Apply CTX photometric calibration using ctxcal
echo "Running ctxcal"
parallel --joblog ctxcal.log ctxcal from={}.cub to={}.lev1.cub ::: ${prodarr[@]}

# Apply CTX even/odd detector correction using ctxevenodd
echo "Running ctxevenodd"
parallel --joblog ctxevenodd.log ctxevenodd from={}.lev1.cub to={}.lev1eo.cub ::: ${prodarr[@]}

# Delete intermediate files
# Admittedly, using a FOR loop makes this slower than it could be but it's safer than using globs and minimizes error output clutter
echo "Final cleanup"
((n_elements=${#edrarr[@]}, max_index=n_elements - 1))
for ((i = 0; i <= max_index; i++)); do
	if [[ -e ${prodarr[$i]}.cub ]]; then
		rm ${prodarr[$i]}.cub	
	fi
	if [[ -e ${prodarr[$i]}.lev1.cub ]]; then
		rm ${prodarr[$i]}.lev1.cub	
	fi
done

# move log and IMG files into dedicated folders
mkdir -p logs
mv *.log logs/
mkdir -p orig_IMGs
mv *.IMG orig_IMGs

echo "Finished $(basename $0) @ "$(date)

# TODO
# nicer parallel stdout