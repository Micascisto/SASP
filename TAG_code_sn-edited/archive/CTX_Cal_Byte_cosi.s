#!/bin/bash

#------------------------------------------------------------------------------------------------------------------
#
# Code Written By: Tim Goudge (tgoudge@jsg.utexas.edu)
#
# Last Modified: 9/29/2015
#
# Code Description:
# This code will take a list of CTX images, download them, then process and project them (to a local sinusoidal
#	projection that is based on the image center longitude), and output them to a ArcMap-ready .tif format.
#
#------------------------------------------------------------------------------------------------------------------
#
#	EXAMPLE CALL FOR THE SCRIPT FROM THE COMMAND LINE:
#		bash CTX_Cal_Byte_cosi.s TEXT_FILE_NAME.txt
#		
#		Here TEXT_FILE_NAME.txt should be a text file in the same directory that the script is called from, which
#			has a list of CTX image names/numbers (one per line) in the format P14_006699_2135.
#
#------------------------------------------------------------------------------------------------------------------
# ISIS and ASP startup, specific to Mars Hierarchy
# Added by Eric I Petersen, Nov 30, 2015

export PATH="/disk/qnap-2/MARS/syst/ext/linux/apps/isis3/StereoPipeline-2.4.1-2014-07-15-x86_64-Linux-GLIBC-2.5/bin:${PATH}"
export ISISROOT="disk/qnap-2/MARS/syst/ext/linux/apps/isis3/isis"
source $ISISROOT/scripts/isis3startup.sh
export LD_LIBRARY_PATH="/disk/qnap-2/MARS/syst/ext/linux/apps/isis3/isis/3rdParty/lib:${LD_LIBRARY_PATH}"

#------------------------------------------------------------------------------------------------------------------

#Read in the input variable, which should be a list of CTX image names in the format such as: P14_006699_2135, and
#	get the number of files to download.
in_list=`cat $1`
in_list_count=`cat $1 | wc -l`

#Set up cumindex location and base CTX Download path
cumindexdir=/disk/qnap-2/MARS/orig/supl/CTX/CTX_cumindex
main_download_path=`echo http://pds-imaging.jpl.nasa.gov/data/mro/mars_reconnaissance_orbiter/ctx/`

#Now loop through and download all the images
for j in ${in_list}
do
	#Get volume and file name for the image
	temp_vol=`cat ${cumindexdir}/cumindex.tab | grep ${j} | awk '{print tolower(substr($0,2,9))}'`
	temp_file=`cat ${cumindexdir}/cumindex.tab | grep ${j} | awk '{print substr($0,14,35)}' | sed s/"DATA\/"//`

	#Now download the IMG files
	wget ${main_download_path}${temp_vol}/data/${temp_file}
done

#Now check how many .IMG files were successfully downloaded.
downloaded_count=`ls *.IMG | wc -l`

for i in *.IMG
do
	#Get rootname
	rootname=`echo $i | sed s/".IMG"//`
	
	#Convert to ISIS, add spice, calibrate, and do cos(i) correction
	mroctx2isis from=${rootname}.IMG to=${rootname}.cub
	spiceinit from=${rootname}.cub
	ctxcal from=${rootname}.cub to=${rootname}_cal_no_cosi.cub
	cosi from=${rootname}_cal_no_cosi.cub to=${rootname}_cal.cub
	

	#Find lon of orbit
	clon_360=`cat ${cumindexdir}/cumindex.tab | grep ${rootname} | awk '{print substr($0,194,6)}'`
	clon=`echo ${clon_360} | awk '{if ($1>180) print 360-$1; else print 0-$1}'`

	#Create map template
	maptemplate map=${rootname}.map targopt=user targetname=MARS lattype=planetocentric londir=positiveeast londom=180 clon=${clon}

	#Project image
	cam2map from=${rootname}_cal.cub map=${rootname}.map to=${rootname}_sinu_map.cub

	#Get max and min values from histogram
	rootmin=`gdalinfo -stats ${rootname}_sinu_map.cub | sed s/"="/" "/g | grep MINIMUM | awk '{if ($2<0) print 0; else print $2}'`
	rootmax=`gdalinfo -stats ${rootname}_sinu_map.cub | sed s/"="/" "/g | grep MAXIMUM | awk '{if ($2>1) print 1; else print $2}'`

	#Convert to Tiff
	gdal_translate -of GTiff -ot Byte -scale ${rootmin} ${rootmax} 0 255 -co "TFW=YES" -co "PROFILE=BASELINE" ${rootname}_sinu_map.cub ${rootname}.tif
	

	#Generate a .prj file for ArcGIS
	echo PROJCS\[\"M_S${clon}\",GEOGCS\[\"GCS_Mars_2000_Sphere\",DATUM\[\"\<custom\>\",SPHEROID\[\"\<custom\>\",3396190.0,0.0\]\], PRIMEM\[\"Reference_Meridian\",0.0\],UNIT\[\"Degree\",0.0174532925199433\]\],PROJECTION\[\"Sinusoidal\"\],PARAMETER\[\"False_Easting\",0.0\],PARAMETER\[\"False_Northing\",0.0\],PARAMETER\[\"Central_Meridian\",${clon}\],UNIT\[\"Meter\",1.0\]\] > ${rootname}.prj


	rm *.txt
	rm *.cub
	rm *.map
	rm *.aux.xml

done

echo Downloaded and processed ${downloaded_count} of ${in_list_count} images in input list.
echo FINISHED
