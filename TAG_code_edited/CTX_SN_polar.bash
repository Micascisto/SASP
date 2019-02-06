#!/bin/bash

#------------------------------------------------------------------------------------------------------------------
#
# Code Written By: Tim Goudge (tgoudge@jsg.utexas.edu)
# Modified by Stefano Nerozzi (stefano.nerozzi@utexas.edu
#
# Last Modified: 1/Jun/2017
#
# Code Description:
# This code will download a CTX stereo image pair and produce a DEM using these images with the NASA ASP, then it 
#	will tie these data to MOLA shot point data using the ASP to provide an accurate DEM for quantitative 
#	analysis.
#
#------------------------------------------------------------------------------------------------------------------
#
#	EXAMPLE CALL FOR THE SCRIPT FROM THE COMMAND LINE:
#		bash CTX_stereo_code_w_MOLA_tie_TAG.s IMAGE_1_NUM IMAGE_2_NUM RES
#		
#		Here IMAGE_1_NUM and IMAGE_2_NUM are the CTX image number/names in the format P14_006699_2135, and RES
#			is the optional parameter to set the output DEM resolution in meters per pixel (mpp). If not set, or
#			set to lower than 6 mpp, will simply do at the highest possible resolution based on the image pair.
#
#------------------------------------------------------------------------------------------------------------------


#Set input variables, which should be the two image root names and the desired DEM resolution in meters/pixel (mpp). 
image_root1=`echo $1`
image_root2=`echo $2`
input_res=$3
if [ -z "${input_res}" ]; then
    echo "missing resolution"
    exit
fi
input_res_check=`echo ${input_res} | awk '{if ($1<6) print 1; else print 0}'`
#Want the output DEM at	18 mpp,	unless the input res is	larger
#output_res=`echo ${input_res} | awk '{if ($1>18) print $1; else print 18}'`
output_res=`echo "${input_res}*3" | bc`

echo "input res: ${input_res}"
echo "output res: ${output_res}"

#Set up the location of the MOLA SQL table
#	--> THIS TABLE IS IN THE FORMAT: LON|LAT|ELEV|RADIUS|ORBIT
mola_table_loc=/disk/qnap-2/MARS/orig/supl/MOLA/MOLA_SQL_Table/mola

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
wget ${main_path}${vol_1}/data/${file_1}
wget ${main_path}${vol_2}/data/${file_2}

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
	mroctx2isis from=${image1}.IMG to=${image1}.cub
	mroctx2isis from=${image2}.IMG to=${image2}.cub

	#Move the IMG files to a new directory
	mkdir old_img_files
	mv *.IMG old_img_files

	#Attach spice information
	spiceinit from=${image1}.cub
	spiceinit from=${image2}.cub

	#Calibrate the images
	ctxcal from=${image1}.cub to=${image1}_cal.cub
	ctxcal from=${image2}.cub to=${image2}_cal.cub

	#Project the two images to the same projection using Ames Stereo Pipeline python script.
		#Check what resolution to use based on input parameters.
	if [ ${input_res_check} -eq 1 ]; then
		#USE FULL RESOLUTION:
		cam2map4stereo.py ${image1}_cal.cub ${image2}_cal.cub --map=mars_polar_stereo.map
	else
		#DOWNSAMPLE TO INPUT RESOLUTION
		cam2map4stereo.py ${image1}_cal.cub ${image2}_cal.cub -p MPP -r ${input_res} --map=mars_polar_stereo.map
	fi

    #cam2map from=${image1}_cal.cub map=Korolev_LAEA.map to=${image1}_cal.map.cub
    #cam2map from=${image2}_cal.cub map=${image1}_cal.map.cub to=${image2}_cal.map.cub

	#Call the stereo code
	mkdir result
	stereo ${image1}_cal.map.cub ${image2}_cal.map.cub result/${projname}

	#Get the center longitude for projection
	clon=`catlab from=${image1}_cal.map.cub | grep CenterLongitude | grep = | awk '{if ($3>180) print $3-360; else print $3}'`

	#Get the max and min latitude and longitude for the image for the MOLA search
	#	----> Want to add (or subtract) 1.5 from max/min lat/lon to make the bounding box a bit bigger
	max_lat=`catlab from=${image1}_cal.map.cub | grep MaximumLatitude | grep = | awk '{print $3 + 1.5}'`
	min_lat=`catlab from=${image1}_cal.map.cub | grep MinimumLatitude | grep = | awk '{print $3 - 1.5}'`
	max_lon=`catlab from=${image1}_cal.map.cub | grep MaximumLongitude | grep = | awk '{print $3+1.5}'`
	min_lon=`catlab from=${image1}_cal.map.cub | grep MinimumLongitude | grep = | awk '{print $3-1.5}'`

	#Move the old CUB files
	mkdir old_cub_files
	mv *.cub old_cub_files/
	
	#Do the MOLA Search using the bounding box defined above
	#	--> THIS TABLE IS IN THE FORMAT: LON|LAT|ELEV|RADIUS|ORBIT
	#		--> FOR pc_align, WE WANT THE FORMAT LAT,LON,ELEVATION RELATIVE TO ELLIPSOID
	#			--> CONVERTING TO ELEVATION RELATIVE TO ELLIPSOID IS ACHIEVED BY: RADIUS - 3396190 
	echo "sqlite3 ${mola_table_loc} 'select * FROM mola WHERE LON BETWEEN ${min_lon} AND ${max_lon} AND LAT BETWEEN ${min_lat} AND ${max_lat}' >> temp_mola_points.txt" > temp_mola_search.s
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
		cp ../${projname}-PC.tif .
		cp ../${projname}-L.tif .

		#Call the pc_align function to align the CTX DEM to the MOLA point shot data.
		#	Use a max displacement of 2000 m and the IAU D_MARS datum
		pc_align --max-displacement 2000 --datum D_MARS --save-inv-transformed-reference-points ${projname}-PC.tif temp_mola_points.csv -o ${projname}_tied

		#Now make the tied DEM and orthoimage --> want DEM at 18 mpp, unless input res is larger
		#point2dem ${projname}_tied-trans_reference.tif -o temp -r mars --stereographic --proj-lon 0.0 --proj-lat 90.0 --orthoimage ${projname}-L.tif --nodata-value 0.0
		#point2dem ${projname}_tied-trans_reference.tif -o temp -r mars --stereographic --proj-lon 0.0 --proj-lat 90.0 --nodata -32767 --dem-spacing ${output_res}
        point2dem ${projname}_tied-trans_reference.tif -o temp -r mars --orthoimage ${projname}-L.tif --nodata-value 0.0
        point2dem ${projname}_tied-trans_reference.tif -o temp -r mars --nodata -32767 --dem-spacing ${output_res}

		#Now remove the files you don't need
		rm ${projname}-PC.tif
		rm ${projname}-L.tif
	
		#Now move the pc_align produced files
		mkdir PC_Align_Produced_Files/
		mv temp_mola_points.csv PC_Align_Produced_Files/
		mv ${projname}* PC_Align_Produced_Files/

		#Now convert the temporary ellipsoid relative DEM to relative to the areoid
		dem_geoid temp-DEM.tif -o temp_areoid

		#Now make the tied DEMs and image OK for ArcMap with GDAL
		gdal_translate -of GTiff -ot Float32 -co "TFW=YES" -co "PROFILE=BASELINE" temp-DEM.tif ${projname}_tied_ellipsoid_ref-DEM.tif
		gdal_translate -of GTiff -ot Float32 -co "TFW=YES" -co "PROFILE=BASELINE" temp_areoid-adj.tif ${projname}_tied-DEM.tif
		min=`gdalinfo -stats temp-DRG.tif | sed s/"="/" "/g | grep MINIMUM | awk '{if ($2<0) print 0; else print $2}'`
		max=`gdalinfo -stats temp-DRG.tif | sed s/"="/" "/g | grep MAXIMUM | awk '{if ($2>1) print 1; else print $2}'`
		gdal_translate -of GTiff -ot Byte -scale ${min} ${max} 0 255 -co "TFW=YES" -co "PROFILE=BASELINE" temp-DRG.tif ${projname}_tied-DRG.tif

		#Remove the temporary products
		rm temp-DEM.tif
		rm temp-DRG.tif
		rm temp_areoid-adj.tif

		#Now make .prj files for the DEMs and image file
		#echo PROJCS\[\"M_S${clon}\",GEOGCS\[\"GCS_Mars_2000_Sphere\",DATUM\[\"\<custom\>\",SPHEROID\[\"\<custom\>\",3396190.0,0.0\]\], PRIMEM\[\"Reference_Meridian\",0.0\],UNIT\[\"Degree\",0.0174532925199433\]\],PROJECTION\[\"Sinusoidal\"\],PARAMETER\[\"False_Easting\",0.0\],PARAMETER\[\"False_Northing\",0.0\],PARAMETER\[\"Central_Meridian\",${clon}\],UNIT\[\"Meter\",1.0\]\] > prj_template.prj
		#cp prj_template.prj ${projname}_tied-DEM.prj
		#cp prj_template.prj ${projname}_tied-DRG.prj
		#cp prj_template.prj ${projname}_tied_ellipsoid_ref-DEM.prj
		#rm prj_template.prj

		echo All done with DEM and DRG file production
	else
		echo DID NOT HAVE MORE THAN 100 MOLA POINTS TO TIE TO. QUITTING.
	fi
else
	echo IMG FILES DID NOT DOWNLOAD. QUITTING.
fi

#Now do some final cleanup from main working directory
cd "${main_working_dir}"

#Make a directory for the final ArcMap products
mkdir Final_Tied_DEMs

#Move the final products to that folder
mv result/tied_final_product/${projname}_tied-D??.??? Final_Tied_DEMs/

#Now delete all the intermediate products
rm -rf result/
rm -rf old_img_files/
rm -rf old_cub_files/

echo Tied to ${num_mola_pts} MOLA points
echo FINISHED
