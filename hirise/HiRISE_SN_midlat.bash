#!/bin/bash

#------------------------------------------------------------------------------------------------------------------
#
# Code Written By: Tim Goudge (tgoudge@jsg.utexas.edu)
#
# Last Modified: 02-Mar-2018 by Stefano Nerozzi
#
# Code Description:
# This code will download a HiRISE stereo image pair, as well as an overlapping CTX stereo image pair. It will then
# 	produce a CTX DEM using the NASA ASP and tie these data to MOLA shot point data using the ASP to provide an 
#	accurate CTX DEM for quantitative analysis. Then, the code will produce a HiRISE DEM using the ASP and tie that
#	DEM to the previously produced, tied CTX DEM, resulting in a HiRISE DEM that is essentially tied to MOLA 
#	regional topography, and so will be accurate for quantitative analyses.
#
#------------------------------------------------------------------------------------------------------------------
#
#	EXAMPLE CALL FOR THE SCRIPT FROM THE COMMAND LINE:
#		bash HiRISE_stereo_code_w_CTX_and_MOLA_tie_TAG.s IMAGE_H1_NUM IMAGE_H2_NUM IMAGE_C1_NUM IMAGE_C2_NUM HRES
#		
#		Here IMAGE_H1_NUM and IMAGE_H2_NUM are the HiRISE image pair number/names in the format PSP_001882_1410, 
#			IMAGE_C1_NUM and IMAGE_C2_NUM are the CTX image pair number/names in the format P14_006699_2135, and
#			HRES is the optional parameter to set the output HiRISE DEM resolution in meters per pixel (mpp). If 
#			not set, or set to lower than 0.5 mpp, will simply do at the highest possible resolution based on the 
#			image pair. Currently the script does not accommodate down-sampling the CTX DEM, but this is OK, as it
#			will not actually save THAT much time.
#
#------------------------------------------------------------------------------------------------------------------


#Set input variables, which should be the four image root names and the desired HiRISE DEM resolution in meters/pixel (mpp).
#NOTES:
#	An example of a HiRISE image name in the correct format is PSP_001882_1410.
#	An example of a CTX image name in the correct format is P14_006699_2135. 
#	If the resolution is not set or is <0.5 mpp, will use highest available resolution based on image pair.
image1_h=$1
image2_h=$2
image1_c=$3
image2_c=$4
input_res_h=$5
input_res_check_h=`echo ${input_res_h} | awk '{if ($1<0.5) print 1; else print 0}'`
#Want the output HiRISE DEM at 1 mpp,  unless the input res is larger. CTX DEM is automatically set to output at 18 mpp.
output_res_h=`echo ${input_res} | awk '{if ($1>1) print $1; else print 1}'`

#Set the project names, which is just image1_image2 for both CTX and HiRISE
projname_h=${image1_h}_${image2_h}
projname_c=${image1_c}_${image2_c}

#Set up cumindex location and base CTX/HiRISE Download path
cumindex_loc_h="/disk/qnap-2/MARS/orig/supl/HiRISE/HiRISE_cumindex/EDRCUMINDEX.TAB"
main_path_h="https://hirise-pds.lpl.arizona.edu/PDS"
cumindex_loc_c="/disk/qnap-2/MARS/orig/supl/CTX/CTX_cumindex/cumindex.tab"
main_path_c="http://pds-imaging.jpl.nasa.gov/data/mro/mars_reconnaissance_orbiter/ctx/"

#Set up the location of the MOLA SQL table
#	--> THIS TABLE IS IN THE FORMAT: LON|LAT|ELEV|RADIUS|ORBIT
mola_table_loc="/disk/staff/tgoudge/Stored_Data/MOLA_SQL_Table/mola"

#Set variable below to 1 if you the program to save out ellipsoid-referenced DEMs as well as areoid-referenced DEMs.
#	Default is to NOT write them out --> Not very useful and so typically wasted space.
save_ellipsoid_ref_dem=0

#Set up the main working directory (where the script was called from) as well as the required folder structure in that directory
main_working_dir=`pwd`
#Make a folder to do all of the CTX DEM processing in
mkdir CTX_DEM
#Make a folder to do all of the HiRISE DEM processing in
mkdir HiRISE_DEM
#Make a folder to do all of the HiRISE DEM tying in
mkdir HiRISE_DEM_Tie
#Make a folder to put all of the final products
mkdir Final_Tied_DEMs

#Now can start processing data



#-----------------------------------------------------CTX DEM------------------------------------------------------
#First start with processing CTX DEM, including tying to MOLA point shot data.
#Move to CTX Directory
cd CTX_DEM/

#Get volumes and file names for the two CTX images
vol_1_c=`cat ${cumindex_loc_c} | grep ${image1_c} | awk '{print tolower(substr($0,2,9))}'`
vol_2_c=`cat ${cumindex_loc_c} | grep ${image2_c} | awk '{print tolower(substr($0,2,9))}'`
file_1_c=`cat ${cumindex_loc_c} | grep ${image1_c} | awk '{print substr($0,14,35)}' | sed s/"DATA\/"//`
file_2_c=`cat ${cumindex_loc_c} | grep ${image2_c} | awk '{print substr($0,14,35)}' | sed s/"DATA\/"//`

#Now download the IMG files
wget ${main_path_c}${vol_1_c}/data/${file_1_c}
wget ${main_path_c}${vol_2_c}/data/${file_2_c}

#Make sure both images downloaded OK, and only continue if they did
img_count_c=`ls *.IMG | wc -l`
if [ ${img_count_c} -eq 2 ]; then

	#Downloaded 2 IMG files, so OK, and continue
	#Get the full image names
	ls *.IMG > image_names.txt
	image1_c_full=`head -n 1 image_names.txt | sed s/"\.IMG"//`
	image2_c_full=`tail -n 1 image_names.txt | sed s/"\.IMG"//`
	rm image_names.txt
	
	echo IMAGE NAMES:
	echo ${image1_c_full}
	echo ${image2_c_full}

	#Import the images into ISIS
	mroctx2isis from=${image1_c_full}.IMG to=${image1_c_full}.cub
	mroctx2isis from=${image2_c_full}.IMG to=${image2_c_full}.cub

	#Move the IMG files to a new directory
	mkdir OLD_IMG_Files
	mv *.IMG OLD_IMG_Files

	#Attach spice information
	spiceinit from=${image1_c_full}.cub
	spiceinit from=${image2_c_full}.cub

	#Calibrate the images
	ctxcal from=${image1_c_full}.cub to=${image1_c_full}_cal.cub
	ctxcal from=${image2_c_full}.cub to=${image2_c_full}_cal.cub

	#Project the two images to the same projection using Ames Stereo Pipeline python script.
	#USE FULL RESOLUTION:
	cam2map4stereo.py ${image1_c_full}_cal.cub ${image2_c_full}_cal.cub
	
	#Copy over the stereo.default file
	#NOTE: THIS STEREO.DEFAULT FILE HAS THE DEFAULT PARAMETERS SET BY TAG, AND MAY NEED TO BE CHANGED
	#TO CHANGE, CREATE YOUR OWN STEREO.DEFAULT FILE IN THE WORKING DIRECTORY AND COMMENT OUT THE LINE BELOW
	cp /disk/staff/tgoudge/Stored_Data/stereo_dot_default_files/stereo_dot_default_file_CTX_v2.3.0.txt stereo.default

	#Call the stereo code
	mkdir result
	stereo ${image1_c_full}_cal.map.cub ${image2_c_full}_cal.map.cub result/${projname_c}

	#Get the center longitude for projection
	clon_c=`catlab from=${image1_c_full}_cal.map.cub | grep CenterLongitude | grep = | awk '{if ($3>180) print $3-360; else print $3}'`

	#Get the max and min latitude and longitude for the image for the MOLA search
	#	----> Want to add (or subtract) 1.5 from max/min lat/lon to make the bounding box a bit bigger
	max_lat_c=`catlab from=${image1_c_full}_cal.map.cub | grep MaximumLatitude | grep = | awk '{print $3 + 1.5}'`
	min_lat_c=`catlab from=${image1_c_full}_cal.map.cub | grep MinimumLatitude | grep = | awk '{print $3 - 1.5}'`
	max_lon_c=`catlab from=${image1_c_full}_cal.map.cub | grep MaximumLongitude | grep = | awk '{print $3+1.5}'`
	min_lon_c=`catlab from=${image1_c_full}_cal.map.cub | grep MinimumLongitude | grep = | awk '{print $3-1.5}'`

	#Move the old CUB files
	mkdir old_cub_files
	mv *.cub old_cub_files/
	
	#Do the MOLA Search using the bounding box defined above
	#	--> THIS TABLE IS IN THE FORMAT: LON|LAT|ELEV|RADIUS|ORBIT
	#		--> FOR pc_align, WE WANT THE FORMAT LAT,LON,ELEVATION RELATIVE TO ELLIPSOID
	#			--> CONVERTING TO ELEVATION RELATIVE TO ELLIPSOID IS ACHIEVED BY: RADIUS - 3396190 
	echo "sqlite3 ${mola_table_loc} 'select * FROM mola WHERE LON BETWEEN ${min_lon_c} AND ${max_lon_c} AND LAT BETWEEN ${min_lat_c} AND ${max_lat_c}' >> temp_mola_points.txt" > temp_mola_search.s
	source temp_mola_search.s
	rm temp_mola_search.s
	cat temp_mola_points.txt | sed s/"|"/" "/g | awk '{print $2","$1","($4-3396190)}' > temp_mola_points.csv
	rm temp_mola_points.txt
	
	#Now get the number of mola points you are tying to, and make sure it is enough!
	#		--> Set limit as 100 points to tie to
	num_mola_pts=`cat temp_mola_points.csv | wc -l`

	if [ ${num_mola_pts} -gt 100 ]; then
	
		#Now tie the output DEM to the MOLA points
		mkdir result/tied_final_product
		mv temp_mola_points.csv result/tied_final_product/
		cd result/tied_final_product
	
		#Copy the files you need to here
		cp ../${projname_c}-PC.tif .
		cp ../${projname_c}-L.tif .

		#Call the pc_align function to align the CTX DEM to the MOLA point shot data.
		#	Use a max displacement of 2000 m and the IAU D_MARS datum
		pc_align --max-displacement 2000 --datum D_MARS --save-inv-transformed-reference-points ${projname_c}-PC.tif temp_mola_points.csv -o ${projname_c}_tied

		#Now make the tied CTX DEM and orthoimage --> want DEM at 18 mpp
		point2dem ${projname_c}_tied-trans_reference.tif -o temp -r mars --sinusoidal --proj-lon ${clon_c} --orthoimage ${projname_c}-L.tif --nodata-value 0.0
		point2dem ${projname_c}_tied-trans_reference.tif -o temp -r mars --sinusoidal --proj-lon ${clon_c} --nodata -32767 --dem-spacing 18

		#Now remove the files you don't need
		rm ${projname_c}-PC.tif
		rm ${projname_c}-L.tif
	
		#Now move the pc_align produced files
		mkdir PC_Align_Produced_Files/
		mv temp_mola_points.csv PC_Align_Produced_Files/
		mv ${projname_c}* PC_Align_Produced_Files/

		#Now convert the temporary ellipsoid relative DEM to relative to the areoid
		dem_geoid temp-DEM.tif -o temp_areoid

		#Now make the tied DEMs and image OK for ArcMap with GDAL
		#	Also check if you are saving out ellipsoid-referenced DEM
		gdal_translate -of GTiff -ot Float32 -co "TFW=YES" -co "PROFILE=BASELINE" temp_areoid-adj.tif ${projname_c}_tied-DEM.tif
		min=`gdalinfo -stats temp-DRG.tif | sed s/"="/" "/g | grep MINIMUM | awk '{if ($2<0) print 0; else print $2}'`
		max=`gdalinfo -stats temp-DRG.tif | sed s/"="/" "/g | grep MAXIMUM | awk '{if ($2>1) print 1; else print $2}'`
		gdal_translate -of GTiff -ot Byte -scale ${min} ${max} 0 255 -co "TFW=YES" -co "PROFILE=BASELINE" temp-DRG.tif ${projname_c}_tied-DRG.tif
		if [ ${save_ellipsoid_ref_dem} -eq 1 ]; then
			gdal_translate -of GTiff -ot Float32 -co "TFW=YES" -co "PROFILE=BASELINE" temp-DEM.tif ${projname_c}_tied_ellipsoid_ref-DEM.tif
		fi

		#Remove the temporary products
		rm temp-DEM.tif
		rm temp-DRG.tif
		rm temp_areoid-adj.tif

		#Now make .prj files for the DEMs and image file
		echo PROJCS\[\"M_S${clon_c}\",GEOGCS\[\"GCS_Mars_2000_Sphere\",DATUM\[\"\<custom\>\",SPHEROID\[\"\<custom\>\",3396190.0,0.0\]\], PRIMEM\[\"Reference_Meridian\",0.0\],UNIT\[\"Degree\",0.0174532925199433\]\],PROJECTION\[\"Sinusoidal\"\],PARAMETER\[\"False_Easting\",0.0\],PARAMETER\[\"False_Northing\",0.0\],PARAMETER\[\"Central_Meridian\",${clon_c}\],UNIT\[\"Meter\",1.0\]\] > prj_template.prj
		cp prj_template.prj ${projname_c}_tied-DEM.prj
		cp prj_template.prj ${projname_c}_tied-DRG.prj
		if [ ${save_ellipsoid_ref_dem} -eq 1 ]; then
			cp prj_template.prj ${projname_c}_tied_ellipsoid_ref-DEM.prj
		fi
		rm prj_template.prj

		echo All done with CTX DEM and DRG file production

		#Set up a flag to feed to the next step --> only process HiRISE DEM if CTX was successful
		CTX_DEM_flag=1
	else
		echo DID NOT HAVE MORE THAN 100 MOLA POINTS TO TIE CTX DEM TO. QUITTING.
		#Set up a flag to feed to the next step --> only process HiRISE DEM if CTX was successful
		CTX_DEM_flag=0
	fi
else
	echo CTX IMG FILES DID NOT DOWNLOAD. QUITTING.
	#Set up a flag to feed to the next step --> only process HiRISE DEM if CTX was successful
	CTX_DEM_flag=0
fi

echo FINISHED CTX DEM PROCESSING


#-----------------------------------------------------CTX DEM------------------------------------------------------



#---------------------------------------------------HiRISE DEM-----------------------------------------------------
#Now produce the HiRISE DEM --> only do this if the CTX DEM finished smoothly
if [ ${CTX_DEM_flag} -eq 1 ]; then
	#CTX DEM processing worked, so carry on
	#Change to appropriate directory
	cd "${main_working_dir}"
	cd HiRISE_DEM/
	#Get the download paths for the two HiRISE images
	end_path_1_h=`cat ${cumindex_loc_h} | grep ${image1_h}_RED5_0 | awk '{print substr($0,15,68)}' | sed s/"${image1_h}_RED5_0\.IMG"//`
	end_path_2_h=`cat ${cumindex_loc_h} | grep ${image2_h}_RED5_0 | awk '{print substr($0,15,68)}' | sed s/"${image2_h}_RED5_0\.IMG"//`
	path_1_h=`echo ${main_path_h}/${end_path_1_h}`
	path_2_h=`echo ${main_path_h}/${end_path_2_h}`


	#Now download the HiRISE IMG files
	#	First do a check though and make sure the available cumindex file is up to date and contains the files of interest, if not, code will download ALL the HiRISE data!!!!
	image1_h_path_check=`cat ${cumindex_loc_h} | grep ${image1_h}_RED5_0 | wc -l`
	image2_h_path_check=`cat ${cumindex_loc_h} | grep ${image2_h}_RED5_0 | wc -l`
	if [ ${image1_h_path_check} -ne 0 ] && [ ${image2_h_path_check} -ne 0 ]; then
		wget -r -nd -np "${path_1_h}" -A "*RED?_?.IMG"
		wget -r -nd -np "${path_2_h}" -A "*RED?_?.IMG"
	fi

	#Need to check that all files are downloaded. Do so by seeing how many files there should be for each image from cumindex.
	img_count_1_h=`cat ${cumindex_loc_h} | grep ${image1_h}_RED | wc -l`
	img_count_2_h=`cat ${cumindex_loc_h} | grep ${image2_h}_RED | wc -l`
	img_download_count_1_h=`ls ${image1_h}*.IMG | wc -l`
	img_download_count_2_h=`ls ${image2_h}*.IMG | wc -l`

	if [ ${img_count_1_h} -eq ${img_download_count_1_h} ] && [ ${img_count_2_h} -eq ${img_download_count_2_h} ]; then
		#All .IMG files downloaded OK, so continue with processing.

		#Stitch .IMG files for image1_h
		#Use script from Ames Stereo Pipeline 
		hiedr2mosaic.py ${image1_h}*RED*.IMG

		#Stitch .IMG files for image2_h
		hiedr2mosaic.py ${image2_h}*RED*.IMG

		#Wait for both stitch jobs to complete
		wait

		#Move the IMG files to a new directory
		mkdir OLD_IMG_Files
		mv *.IMG OLD_IMG_Files

		#Project the two images to the same projection using Ames Stereo Pipeline python script.
		#	Check what resolution to use based on input parameters.
		if [ ${input_res_check_h} -eq 1 ]; then
			#USE FULL RESOLUTION:
			cam2map4stereo.py ${image1_h}_RED.mos_hijitreged.norm.cub ${image2_h}_RED.mos_hijitreged.norm.cub
		else
			#DOWNSAMPLE TO INPUT RESOLUTION
			cam2map4stereo.py ${image1_h}_RED.mos_hijitreged.norm.cub ${image2_h}_RED.mos_hijitreged.norm.cub -p MPP -r ${input_res_h}
		fi


		#Perform finalizing steps
		bandnorm from=${image1_h}_RED.map.cub to=${image1_h}_RED.map.norm.cub
		bandnorm from=${image2_h}_RED.map.cub to=${image2_h}_RED.map.norm.cub
		ls *.map.norm.cub > fromlist
		ls ${image1_h}_RED.map.norm.cub > holdlist
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
		stereo ${image1_h}_RED.map.norm.equ.cub ${image2_h}_RED.map.norm.equ.cub result/${projname_h}

		#Get the center longitude for later HiRISE DEM projection
		clon_h=`catlab from=${image1_h}_RED.map.norm.equ.cub | grep CenterLongitude | grep = | awk '{if ($3>180) print $3-360; else print $3}'`
		mv *.cub old_CUB_products/

		echo All done with HiRISE DEM processing
		
		#Set up a flag to feed to the next step --> only tie HiRISE DEM if production of this DEM was successful
		HiRISE_DEM_flag=1

	else
		echo HiRISE IMG FILES DID NOT DOWNLOAD PROPERLY. QUITTING.

		#Set up a flag to feed to the next step --> only tie HiRISE DEM if production of this DEM was successful
		HiRISE_DEM_flag=0
	fi

	echo FINISHED HiRISE DEM PROCESSING
fi


#---------------------------------------------------HiRISE DEM-----------------------------------------------------



#-------------------------------------------------Tie HiRISE DEM---------------------------------------------------
#Now tie the HiRISE DEM to the CTX DEM --> Only do if HiRISE processing went fine
if [ ${HiRISE_DEM_flag} -eq 1 ]; then
	#HiRISE DEM processing worked, so carry on
	#Change to home directory
	cd "${main_working_dir}"

	#Move needed data to HiRISE tying folder
	mv CTX_DEM/result/tied_final_product/PC_Align_Produced_Files/${projname_c}_tied-trans_reference.tif HiRISE_DEM_Tie/
	mv HiRISE_DEM/result/${projname_h}-PC.tif HiRISE_DEM_Tie/
	mv HiRISE_DEM/result/${projname_h}-L.tif HiRISE_DEM_Tie/

	#Change to tying directory
	cd HiRISE_DEM_Tie/

	#Now call the pc_align function to align the HiRISE DEM to the CTX DEM.
	#	Use a max displacement of 2000 m and the IAU D_MARS datum
	pc_align --max-displacement 2000 --datum D_Mars --save-transformed-source-points ${projname_c}_tied-trans_reference.tif ${projname_h}-PC.tif -o ${projname_h}_tied

	#Now make the tied HiRISE DEM and orthoimage --> want DEM at 1 mpp, unless input res is larger
	point2dem ${projname_h}_tied-trans_source.tif -o temp -r mars --sinusoidal --proj-lon ${clon_h} --orthoimage ${projname_h}-L.tif --nodata-value 0.0
	point2dem ${projname_h}_tied-trans_source.tif -o temp -r mars --sinusoidal --proj-lon ${clon_h} --nodata -32767 --dem-spacing ${output_res_h}

	#Now move the original HiRISE and CTX DEM files back to where you got them from.
	mv ${projname_c}_tied-trans_reference.tif ../CTX_DEM/result/tied_final_product/PC_Align_Produced_Files/
	mv ${projname_h}-PC.tif ../HiRISE_DEM/result/
	mv ${projname_h}-L.tif ../HiRISE_DEM/result/

	#Now move the pc_align produced files
	mkdir PC_Align_Produced_Files/
	mv ${projname_h}* PC_Align_Produced_Files/

	#Now convert the temporary ellipsoid relative DEM to relative to the areoid
	dem_geoid temp-DEM.tif -o temp_areoid

	#Now make the tied DEMs and image OK for ArcMap with GDAL
	gdal_translate -of GTiff -ot Float32 -co "TFW=YES" -co "PROFILE=BASELINE" temp_areoid-adj.tif ${projname_h}_tied-DEM.tif
	min=`gdalinfo -stats temp-DRG.tif | sed s/"="/" "/g | grep MINIMUM | awk '{if ($2<0) print 0; else print $2}'`
	max=`gdalinfo -stats temp-DRG.tif | sed s/"="/" "/g | grep MAXIMUM | awk '{if ($2>1) print 1; else print $2}'`
	gdal_translate -of GTiff -ot Byte -scale ${min} ${max} 0 255 -co "TFW=YES" -co "PROFILE=BASELINE" temp-DRG.tif ${projname_h}_tied-DRG.tif
	if [ ${save_ellipsoid_ref_dem} -eq 1 ]; then
		gdal_translate -of GTiff -ot Float32 -co "TFW=YES" -co "PROFILE=BASELINE" temp-DEM.tif ${projname_h}_tied_ellipsoid_ref-DEM.tif
	fi


	#Remove the temporary products
	rm temp-DEM.tif
	rm temp-DRG.tif
	rm temp_areoid-adj.tif

	#Create a projection file for the output files
	echo PROJCS\[\"M_S${clon_h}\",GEOGCS\[\"GCS_Mars_2000_Sphere\",DATUM\[\"\<custom\>\",SPHEROID\[\"\<custom\>\",3396190.0,0.0\]\], PRIMEM\[\"Reference_Meridian\",0.0\],UNIT\[\"Degree\",0.0174532925199433\]\],PROJECTION\[\"Sinusoidal\"\],PARAMETER\[\"False_Easting\",0.0\],PARAMETER\[\"False_Northing\",0.0\],PARAMETER\[\"Central_Meridian\",${clon_h}\],UNIT\[\"Meter\",1.0\]\] > prj_template.prj
	cp prj_template.prj ${projname_h}_tied-DEM.prj
	cp prj_template.prj ${projname_h}_tied-DRG.prj
	if [ ${save_ellipsoid_ref_dem} -eq 1 ]; then
		cp prj_template.prj ${projname_h}_tied_ellipsoid_ref-DEM.prj
	fi
	rm prj_template.prj

	echo All done with HiRISE DEM tying and DEM and DRG file production

fi

#-------------------------------------------------Tie HiRISE DEM---------------------------------------------------



#----------------------------------------------------Cleanup-------------------------------------------------------
#Now cleanup the data structure etc. --> Only do if all processing went fine

if [ ${HiRISE_DEM_flag} -eq 1 ] && [ ${CTX_DEM_flag} -eq 1 ]; then
	#All worked well, so go ahead
	#Change to main working directory
	cd "${main_working_dir}"

	#Move Tied CTX DEM files to Final_Tied_DEMs folder
	mv CTX_DEM/result/tied_final_product/${projname_c}_tied*.tif Final_Tied_DEMs/
	mv CTX_DEM/result/tied_final_product/${projname_c}_tied*.tfw Final_Tied_DEMs/
	mv CTX_DEM/result/tied_final_product/${projname_c}_tied*.prj Final_Tied_DEMs/

	#Move Tied HiRISE DEM files to Final_Tied_DEMs folder
	mv HiRISE_DEM_Tie/${projname_h}_tied*.tif Final_Tied_DEMs/
	mv HiRISE_DEM_Tie/${projname_h}_tied*.tfw Final_Tied_DEMs/
	mv HiRISE_DEM_Tie/${projname_h}_tied*.prj Final_Tied_DEMs/

	#Now delete all the intermediate products
	#---------------> UNCOMMENT LINES BELOW TO ACTUALLY DO THIS!!!!!!!!
	#rm -rvf CTX_DEM/
	#rm -rvf HiRISE_DEM/
	#rm -rvf HiRISE_DEM_Tie/
fi
#----------------------------------------------------Cleanup-------------------------------------------------------

echo FINISHED ALL PROCESSING!
echo CTX DEM Tied to ${num_mola_pts} MOLA points
