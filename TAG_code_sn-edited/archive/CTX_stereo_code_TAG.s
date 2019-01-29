#!/bin/bash

#------------------------------------------------------------------------------------------------------------------
#
# Code Written By: Tim Goudge (tgoudge@jsg.utexas.edu)
#
# Last Modified: 9/29/2015
#
# Code Description:
# This code will download a CTX stereo image pair and produce a DEM using these images with the NASA ASP. These 
#	data will not be tied to MOLA regional topography, and so will only be useful for qualitative analyses.
#
#------------------------------------------------------------------------------------------------------------------
#
#	EXAMPLE CALL FOR THE SCRIPT FROM THE COMMAND LINE:
#		bash CTX_stereo_code_TAG.s IMAGE_1_NUM IMAGE_2_NUM RES
#		
#		Here IMAGE_1_NUM and IMAGE_2_NUM are the CTX image number/names in the format P14_006699_2135, and RES
#			is the optional parameter to set the output DEM resolution in meters per pixel (mpp). If not set, or
#			set to lower than 6 mpp, will simply do at the highest possible resolution based on the image pair.
#
#------------------------------------------------------------------------------------------------------------------


#Set input variables, which should be the two image root names and the desired DEM resolution in meters/pixel (mpp).
#NOTES:
#	An example of a CTX image name in the correct format is P14_006699_2135. 
#	If the resolution is not set or is <6 mpp, will use highest available resolution based on image pair.
image_root1=`echo $1`
image_root2=`echo $2`
input_res=$3
input_res_check=`echo ${input_res} | awk '{if ($1<6) print 1; else print 0}'`
#Want the output DEM at 18 mpp, unless the input res is larger
output_res=`echo ${input_res} | awk '{if ($1>18) print $1; else print 18}'`

#Set up cumindex location and base CTX Download path
cumindex_loc=`echo /disk/qnap-2/MARS/orig/supl/CTX/CTX_cumindex/cumindex.tab`
main_path=`echo http://pds-imaging.jpl.nasa.gov/data/mro/mars_reconnaissance_orbiter/ctx/`

#Set up the main working directory (where the script was called from) as well as the required folder structure in that directory
main_working_dir=`pwd`

#Get volumes and file names for the two images
vol_1=`cat ${cumindex_loc} | grep ${image_root1} | awk '{print tolower(substr($0,2,9))}'`
vol_2=`cat ${cumindex_loc} | grep ${image_root2} | awk '{print tolower(substr($0,2,9))}'`
file_1=`cat ${cumindex_loc} | grep ${image_root1} | awk '{print substr($0,14,35)}' | sed s/"DATA\/"//`
file_2=`cat ${cumindex_loc} | grep ${image_root2} | awk '{print substr($0,14,35)}' | sed s/"DATA\/"//`

#Now download the IMG files
wget ${main_path}${vol_1}/data/${file_1} &
wget ${main_path}${vol_2}/data/${file_2}
wait

#Now set up the proj name, which is just image_root1_image_root2
projname=`echo ${image_root1}_${image_root2}`

#Make sure both images downloaded OK, and only continue if they did
img_count=`ls *.IMG | wc -l`
if [ ${img_count} -eq 2 ]; then

	#Downloaded 2 IMG files, so OK, and continue
	#Get the full image names
	ls *.IMG > image_names.txt
	image1=`head -n 1 image_names.txt | sed s/"\.IMG"//`
	root1=`head -n 1 image_names.txt | awk '{print substr($0,1,15)}'`
	image2=`tail -n 1 image_names.txt | sed s/"\.IMG"//`
	root2=`tail -n 1 image_names.txt | awk '{print substr($0,1,15)}'`
	rm image_names.txt
	
	echo IMAGE NAMES:
	echo ${image1}
	echo ${image2}

	#Import the images into ISIS
	mroctx2isis from=${image1}.IMG to=${image1}.cub &
	mroctx2isis from=${image2}.IMG to=${image2}.cub
	wait

	#Move the IMG files to a new directory
	mkdir OLD_IMG_Files
	mv *.IMG OLD_IMG_Files

	#Attach spice information
	spiceinit from=${image1}.cub &
	spiceinit from=${image2}.cub
	wait

	#Calibrate the images
	ctxcal from=${image1}.cub to=${image1}_cal.cub &
	ctxcal from=${image2}.cub to=${image2}_cal.cub
	wait

	#Project the two images to the same projection using Ames Stereo Pipeline python script.
	#	Check what resolution to use based on input parameters.
	if [ ${input_res_check} -eq 1 ]; then
		#USE FULL RESOLUTION:
		cam2map4stereo.py ${image1}_cal.cub ${image2}_cal.cub
	else
		#DOWNSAMPLE TO INPUT RESOLUTION
		cam2map4stereo.py ${image1}_cal.cub ${image2}_cal.cub -p MPP -r ${input_res}
	fi

	#Copy over the stereo.default file
	#NOTE: THIS STEREO.DEFAULT FILE HAS THE DEFAULT PARAMETERS SET BY TAG, AND MAY NEED TO BE CHANGED
	#TO CHANGE, CREATE YOUR OWN STEREO.DEFAULT FILE IN THE WORKING DIRECTORY AND COMMENT OUT THE LINE BELOW
	cp /disk/qnap-2/MARS/code/modl/TAG_code/stereo_dot_default_files/stereo_dot_default_file_CTX_v2.3.0.txt stereo.default

	#Call the stereo code
	mkdir result
	stereo ${image1}_cal.map.cub ${image2}_cal.map.cub result/${projname}

	#Get the center longitude for projection
	clon=`catlab from=${image1}_cal.map.cub | grep CenterLongitude | grep = | awk '{if ($3>180) print $3-360; else print $3}'`

	#Move the old CUB files
	mkdir old_cub_files
	mv *.cub old_cub_files/

	#Create the DEM and an orthorectified image to project onto it --> want DEM at 18 mpp, unless input res is larger
	cd result/
	mkdir final_product
	point2dem ${projname}-PC.tif -o final_product/temp -r mars --sinusoidal --proj-lon ${clon} --orthoimage ${projname}-L.tif --nodata-value 0.0
	point2dem ${projname}-PC.tif -o final_product/temp -r mars --sinusoidal --proj-lon ${clon} --dem-spacing ${output_res}

	#Now convert the temporary ellipsoid relative DEM to relative to the areoid
	cd final_product/
	dem_geoid temp-DEM.tif -o temp_areoid

	#Now make the tied DEMs and image OK for ArcMap with GDAL
	gdal_translate -of GTiff -ot Float32 -co "TFW=YES" -co "PROFILE=BASELINE" temp-DEM.tif ${projname}_ellipsoid_ref-DEM.tif
	gdal_translate -of GTiff -ot Float32 -co "TFW=YES" -co "PROFILE=BASELINE" temp_areoid-adj.tif ${projname}-DEM.tif
	min=`gdalinfo -stats temp-DRG.tif | sed s/"="/" "/g | grep MINIMUM | awk '{if ($2<0) print 0; else print $2}'`
	max=`gdalinfo -stats temp-DRG.tif | sed s/"="/" "/g | grep MAXIMUM | awk '{if ($2>1) print 1; else print $2}'`
	gdal_translate -of GTiff -ot Byte -scale ${min} ${max} 0 255 -co "TFW=YES" -co "PROFILE=BASELINE" temp-DRG.tif ${projname}-DRG.tif

	#Remove the temporary products
	rm temp-DEM.tif
	rm temp-DRG.tif
	rm temp_areoid-adj.tif

	#Create a projection file for the output files
	echo PROJCS\[\"M_S${clon}\",GEOGCS\[\"GCS_Mars_2000_Sphere\",DATUM\[\"\<custom\>\",SPHEROID\[\"\<custom\>\",3396190.0,0.0\]\], PRIMEM\[\"Reference_Meridian\",0.0\],UNIT\[\"Degree\",0.0174532925199433\]\],PROJECTION\[\"Sinusoidal\"\],PARAMETER\[\"False_Easting\",0.0\],PARAMETER\[\"False_Northing\",0.0\],PARAMETER\[\"Central_Meridian\",${clon}\],UNIT\[\"Meter\",1.0\]\] > prj_template.prj
	cp prj_template.prj ${projname}-DEM.prj
	cp prj_template.prj ${projname}_ellipsoid_ref-DEM.prj
	cp prj_template.prj ${projname}-DRG.prj
	rm prj_template.prj
	
else
	echo IMG FILES DID NOT DOWNLOAD. QUITTING.
fi


#Now do some final cleanup from main working directory
cd "${main_working_dir}"

#Make a directory for the final ArcMap products
mkdir Final_DEMs

#Move the final products to that folder
mv result/final_product/${projname}-D??.??? Final_DEMs/

#Now delete all the intermediate products
#---------------> UNCOMMENT LINES BELOW TO ACTUALLY DO THIS!!!!!!!!
#rm -rvf result/
#rm -rvf OLD_IMG_Files/
#rm -rvf old_CUB_products/

echo FINISHED

echo FINISHED

