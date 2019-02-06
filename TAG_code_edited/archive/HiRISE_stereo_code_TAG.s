#!/bin/bash

#------------------------------------------------------------------------------------------------------------------
#
# Code Written By: Tim Goudge (tgoudge@jsg.utexas.edu)
#
# Last Modified: 7/20/2017
#
# Code Description:
# This code will download a HiRISE stereo image pair and produce a DEM using these images with the NASA ASP. These 
#	data will not be tied to MOLA regional topography, and so will only be useful for qualitative analyses.
#
#------------------------------------------------------------------------------------------------------------------
#
#	EXAMPLE CALL FOR THE SCRIPT FROM THE COMMAND LINE:
#		bash HiRISE_stereo_code_TAG.s IMAGE_1_NUM IMAGE_2_NUM RES
#		
#		Here IMAGE_1_NUM and IMAGE_2_NUM are the HiRISE image number/names in the format PSP_001882_1410, and RES
#			is the optional parameter to set the output DEM resolution in meters per pixel (mpp). If not set, or
#			set to lower than 0.5 mpp, will simply do at the highest possible resolution based on the image pair.
#
#------------------------------------------------------------------------------------------------------------------


#Set input variables, which should be the two image root names and the desired DEM resolution in meters/pixel (mpp).
#NOTES:
#	An example of a HiRISE image name in the correct format is PSP_001882_1410.
#	If the resolution is not set or is <0.5 mpp, will use highest available resolution based on image pair.
image1=$1
image2=$2
input_res=$3
input_res_check=`echo ${input_res} | awk '{if ($1<0.5) print 1; else print 0}'`
#Want the output DEM at	1 mpp,	unless the input res is	larger
output_res=`echo ${input_res} | awk '{if ($1>1) print $1; else print 1}'`

#Set the project name, which is just image1_image2
projname=${image1}_${image2}

#Set up cumindex location and base HiRISE Download path
cumindex_loc=`echo /disk/staff/tgoudge/Stored_Data/HiRISE_cumindex/EDRCUMINDEX.TAB`
main_path=`echo https://hirise-pds.lpl.arizona.edu/PDS`

#Set up the main working directory (where the script was called from) as well as the required folder structure in that directory
main_working_dir=`pwd`

#Get the download paths for the two images
end_path_1=`cat ${cumindex_loc} | grep ${image1}_RED5_0 | awk '{print substr($0,15,68)}' | sed s/"${image1}_RED5_0\.IMG"//`
end_path_2=`cat ${cumindex_loc} | grep ${image2}_RED5_0 | awk '{print substr($0,15,68)}' | sed s/"${image2}_RED5_0\.IMG"//`
path_1=`echo ${main_path}/${end_path_1}`
path_2=`echo ${main_path}/${end_path_2}`

#Now download the IMG files
#	First do a check though and make sure the available cumindex file is up to date and contains the files of interest, if not, code will download ALL the HiRISE data!!!!
image1_path_check=`cat ${cumindex_loc} | grep ${image1}_RED5_0 | wc -l`
image2_path_check=`cat ${cumindex_loc} | grep ${image2}_RED5_0 | wc -l`
if [ ${image1_path_check} -ne 0 ] && [ ${image2_path_check} -ne 0 ]; then
	wget -r -nd -np "${path_1}" -A "*RED?_?.IMG" &
	wget -r -nd -np "${path_2}" -A "*RED?_?.IMG"
	wait
fi

#Need to check that all files are downloaded. Do so by seeing how many files there should be for each image from cumindex.
img_count_1=`cat ${cumindex_loc} | grep ${image1}_RED | wc -l`
img_count_2=`cat ${cumindex_loc} | grep ${image2}_RED | wc -l`
img_download_count_1=`ls ${image1}*.IMG | wc -l`
img_download_count_2=`ls ${image2}*.IMG | wc -l`

if [ ${img_count_1} -eq ${img_download_count_1} ] && [ ${img_count_2} -eq ${img_download_count_2} ]; then
	#All .IMG files downloaded OK, so continue with processing.

	#Stitch .IMG files for image1
	#Use script from Ames Stereo Pipeline 
	hiedr2mosaic.py ${image1}*RED*.IMG &

	#Stitch .IMG files for image2
	hiedr2mosaic.py ${image2}*RED*.IMG

	#Wait for both stitch jobs to complete
	wait

	#Move the IMG files to a new directory
	mkdir OLD_IMG_Files
	mv *.IMG OLD_IMG_Files

	#Project the two images to the same projection using Ames Stereo Pipeline python script.
	#	Check what resolution to use based on input parameters.
	if [ ${input_res_check} -eq 1 ]; then
		#USE FULL RESOLUTION:
		cam2map4stereo.py ${image1}_RED.mos_hijitreged.norm.cub ${image2}_RED.mos_hijitreged.norm.cub
	else
		#DOWNSAMPLE TO INPUT RESOLUTION
		cam2map4stereo.py ${image1}_RED.mos_hijitreged.norm.cub ${image2}_RED.mos_hijitreged.norm.cub -p MPP -r ${input_res}
	fi
	
	#Perform finalizing steps
	bandnorm from=${image1}_RED.map.cub to=${image1}_RED.map.norm.cub
	bandnorm from=${image2}_RED.map.cub to=${image2}_RED.map.norm.cub
	ls *.map.norm.cub > fromlist
	ls ${image1}_RED.map.norm.cub > holdlist
	equalizer fromlist=fromlist holdlist=holdlist

	#Move old .cub files to a new directory
	mkdir old_CUB_products
	mv -v *.map.cub old_CUB_products/
	mv -v *.mos_hijitreged.norm.cub old_CUB_products/
	mv -v *.norm.cub old_CUB_products/
	mv -v *list old_CUB_products/

	#Get the stereo.default file
	#NOTE: THIS STEREO.DEFAULT FILE HAS THE DEFAULT PARAMETERS SET BY TAG, AND MAY NEED TO BE CHANGED
	#TO CHANGE, CREATE YOUR OWN STEREO.DEFAULT FILE IN THE WORKING DIRECTORY AND COMMENT OUT THE LINE BELOW
	cp /disk/staff/tgoudge/Stored_Data/stereo_dot_default_files/stereo_dot_default_file_v2.2.0.txt stereo.default

	#Call the stereo code
	mkdir result
	stereo ${image1}_RED.map.norm.equ.cub ${image2}_RED.map.norm.equ.cub result/${projname}

	#Get the center longitude for projection
	clon=`catlab from=${image1}_RED.map.norm.equ.cub | grep CenterLongitude | grep = | awk '{if ($3>180) print $3-360; else print $3}'`
	mv *.cub old_CUB_products/

	#Create the DEM and an orthorectified image to project onto it --> want DEM at 1 mpp, unless input res is larger
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
	echo IMG FILES DID NOT DOWNLOAD PROPERLY. QUITTING.
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
