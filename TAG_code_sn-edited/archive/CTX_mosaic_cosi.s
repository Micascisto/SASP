#------------------------------------------------------------------------------------------------------------------
#
# Code Written By: Tim Goudge (tgoudge@jsg.utexas.edu)
#
# Last Modified: 9/29/2015
#
# Code Description:
# This code will take a list of CTX images, download them, then process and mosaic them into a single file, then
#	project them into a local sinusoidal projection that is based on the reference image center longitude, 
#	and output them to a ArcMap-ready .tif format.
#
#------------------------------------------------------------------------------------------------------------------
#
#	EXAMPLE CALL FOR THE SCRIPT FROM THE COMMAND LINE:
#		bash CTX_mosaic_cosi.s TEXT_FILE_NAME.txt
#		
#		Here TEXT_FILE_NAME.txt should be a text file in the same directory that the script is called from, which
#			has a list of CTX image names/numbers (one per line) in the format P14_006699_2135.
#
#------------------------------------------------------------------------------------------------------------------

#Read in the input variable, which should be a list of CTX image names in the format such as: P14_006699_2135, and
#	get the number of files to download.
in_list=`cat $1`
in_list_count=`cat $1 | wc -l`

#Set up cumindex location and base CTX Download path
cumindexdir=/disk/qnap-2/MARS/orig/supl/CTX/CTX_cumindex
main_download_path=`echo http://pds-imaging.jpl.nasa.gov/data/mro/mars_reconnaissance_orbiter/ctx/`

echo --------------------------------------------
echo Downloading data
echo --------------------------------------------

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

#Only want to do the mosaicking if all the files were downloaded, so check.
if [ ${in_list_count} -eq ${downloaded_count} ]; then
	#Downloaded same number of files as in list, so continue with mosaicking.

	#First need to move the image list .txt (and any other .txt files) to a different folder so they don't screw up later processing
	mkdir OLD_TXT
	mv *.txt OLD_TXT

	echo --------------------------------------------
	echo Starting mosaic prep
	echo --------------------------------------------

	for i in *.IMG
	do
		#Get image rootname
		rootname=`echo $i | sed s/".IMG"//`
	
		#Convert to ISIS, add spice and calibrate
		echo --------------------------------------------
		echo Converting to ISIS
		echo --------------------------------------------
		mroctx2isis from=${rootname}.IMG to=${rootname}.cub

		echo --------------------------------------------
		echo Attaching spice information
		echo --------------------------------------------
		spiceinit from=${rootname}.cub

		echo --------------------------------------------
		echo Calibrating image ${rootname}
		echo --------------------------------------------
		ctxcal from=${rootname}.cub to=${rootname}_cal_no_cosi.cub
       	 	cosi from=${rootname}_cal_no_cosi.cub to=${rootname}_cal.cub
	
		echo --------------------------------------------
		echo Finding projection information for image ${rootname}
		echo --------------------------------------------
		#Find clon of image
		clon_360=`cat ${cumindexdir}/cumindex.tab | grep ${rootname} | awk '{print substr($0,194,6)}'`
		clon=`echo ${clon_360} | awk '{if ($1>180) print 360-$1; else print 0-$1}'`

		#Find pixel resolution in m/pixel
		pixres=`cat ${cumindexdir}/cumindex.tab | grep ${rootname} | awk '{print substr($0,157,8)}'`

		#Output to a .txt file that contains the filename, clon and pixres
		echo ${rootname} ${clon} ${pixres} > ${rootname}.txt

	done

	echo --------------------------------------------
	echo Mosaic prep finished
	echo --------------------------------------------

	echo --------------------------------------------
	echo Starting main mosaic loop
	echo --------------------------------------------

	#Find image with the lowest resolution
	echo --------------------------------------------
	echo Finding image with the lowest resolution
	echo --------------------------------------------
	pixres="0.0"
	clon="0.0"
	hold_name="null"

	for k in *.txt
	do
		#Get the resolution, rootname and clon from the file
		pixres_temp=`cat $k | awk '{print $3}'`
		rootname=`cat $k | awk '{print $1}'`
		clon_temp=`cat $k | awk '{print $2}'`

		echo ${pixres} ${pixres_temp} ${hold_name} ${rootname} ${clon} ${clon_temp} > temp.txt
		
		pixres=`cat temp.txt | awk '{if ($2 > $1) print $2; else print $1}'`
		hold_name=`cat temp.txt | awk '{if ($2 > $1) print $4; else print $3}'`
		clon=`cat temp.txt | awk '{if ($2 > $1) print $6; else print $5}'`
		rm temp.txt	
	done

	#Now move the .txt files
	mv *.txt OLD_TXT

	echo --------------------------------------------
	echo Minimum pixel resolution = ${pixres} 
	echo From image ${hold_name}
	echo With center longitude ${clon}
	echo --------------------------------------------

	#Create main map template
	echo --------------------------------------------
	echo Creating map template
	echo --------------------------------------------
	maptemplate map=${hold_name}_mos.map targopt=user targetname=MARS lattype=planetocentric londir=positiveeast londom=180 clon=${clon}

	#Project all images
	for l in *_cal.cub
	do

		#Get rootname
		rootname=`echo $l | sed s/"_cal.cub"//`
	
		echo --------------------------------------------
		echo Projecting image cube ${rootname}
		echo --------------------------------------------

		#Project image
		cam2map from=${rootname}_cal.cub map=${hold_name}_mos.map pixres=mpp resolution=${pixres} to=${rootname}_sinu_map.cub

	done

	#Get list of projected images
	ls *_sinu_map.cub > summary_list.txt
	echo ${hold_name}_sinu_map.cub > hold_list.txt

	#Equalize images
	echo --------------------------------------------
	echo Equalizing Images
	echo --------------------------------------------
	equalizer fromlist= summary_list.txt holdlist=hold_list.txt

	#Get list of equalized images and mosaic them.
	ls *.equ.cub > mos_list.txt
	echo --------------------------------------------
	echo Mosaicking Images
	echo --------------------------------------------
	noseam fromlist=mos_list.txt to=${hold_name}_base_mosaic_unstr.cub HNS=501 HNL=501 LNS=501 LNL=501

	#Perform a gaussian stretch on the mosaic
	echo --------------------------------------------
	echo Performing gaussian stretch
	echo --------------------------------------------
	gaussstretch from=${hold_name}_base_mosaic_unstr.cub to=${hold_name}_base_mosaic.cub

	#Get max and min values from histogram
	echo --------------------------------------------
	echo Getting moasic max and min values for stretching
	echo --------------------------------------------
	rootmin=`gdalinfo -stats ${hold_name}_base_mosaic.cub | sed s/"="/" "/g | grep MINIMUM | awk '{if ($2<0) print 0; else print $2}'`
	rootmax=`gdalinfo -stats ${hold_name}_base_mosaic.cub | sed s/"="/" "/g | grep MAXIMUM | awk '{if ($2>1) print 1; else print $2}'`

	#Convert to Tiff
	echo --------------------------------------------
	echo Converting to GeoTiff
	echo --------------------------------------------
	gdal_translate -of GTiff -ot Byte -scale ${rootmin} ${rootmax} 0 255 -co "TFW=YES" -co "PROFILE=BASELINE" ${hold_name}_base_mosaic.cub ${hold_name}_base_mosaic.tif

	#Generate a .prj file for ArcGIS
	echo --------------------------------------------
	echo Generating ArcMap projection file
	echo --------------------------------------------
	echo PROJCS\[\"M_S${clon}\",GEOGCS\[\"GCS_Mars_2000_Sphere\",DATUM\[\"\<custom\>\",SPHEROID\[\"\<custom\>\",3396190.0,0.0\]\], PRIMEM\[\"Reference_Meridian\",0.0\],UNIT\[\"Degree\",0.0174532925199433\]\],PROJECTION\[\"Sinusoidal\"\],PARAMETER\[\"False_Easting\",0.0\],PARAMETER\[\"False_Northing\",0.0\],PARAMETER\[\"Central_Meridian\",${clon}\],UNIT\[\"Meter\",1.0\]\] > ${hold_name}_base_mosaic.prj

	echo --------------------------------------------
	echo Removing temporary files
	echo --------------------------------------------
	rm *.txt
	rm *.cub
	rm *.map
	rm *.aux.xml

	echo --------------------------------------------
	echo Mosaic processing finished
	echo --------------------------------------------

	echo --------------------------------------------
	echo Moving .IMG files
	echo --------------------------------------------

	mkdir OLD_IMG
	mv *.IMG OLD_IMG
	mkdir OLD
	mv OLD_TXT OLD/
	mv OLD_IMG OLD/

	echo --------------------------------------------
	echo Mosaicking Complete!
	echo --------------------------------------------

else

	#Did NOT download same number of files as in list, so abort mosaicking.
	echo DOWNLOADED ONLY ${downloaded_count} FILES OF ${in_list_count} IN LIST. QUITTING.

fi

echo FINISHED
