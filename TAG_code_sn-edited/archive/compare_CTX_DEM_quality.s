#!/bin/bash

#------------------------------------------------------------------------------------------------------------------
#
# Code Written By: Tim Goudge (tgoudge@jsg.utexas.edu)
#
# Last Modified: 10/23/2015
#
# Code Description:
# This code will take a list of CTX stereo image pairs and then output the Ls, incidence and phase angle for each
#	image in the pair, so one can judge which is likely to produce the best quality DEM.
#
#------------------------------------------------------------------------------------------------------------------
#
#	EXAMPLE CALL FOR THE SCRIPT FROM THE COMMAND LINE:
#		bash compare_CTX_DEM_quality.s TEXT_FILE_NAME.txt
#		
#		Here TEXT_FILE_NAME.txt should be a text file in the same directory that the script is called from, which
#			has a list of CTX image names/numbers (two per line, i.e., one stereo pair per line) in the format 
#			P14_006699_2135_P14_006699_2136.
#
#------------------------------------------------------------------------------------------------------------------

#Read in the input variable, which should be a list of CTX image pair names in the format such as: P14_006699_2135_P14_006699_2136
in_list=`cat $1`

#Set up cumindex location
cumindexdir=/disk/qnap-2/MARS/orig/supl/CTX/CTX_cumindex

#Now loop through list of image pairs
for j in ${in_list}
do
	#Get the seperate image names
	image1=`echo ${j} | sed s/"_"/" "/g | awk '{print $1"_"$2"_"$3}'`
	image2=`echo ${j} | sed s/"_"/" "/g | awk '{print $4"_"$5"_"$6}'`
	
	#Get the Ls, incidence and phase angles for each image, as well as the difference in these quantities
	Ls1=`cat ${cumindexdir}/cumindex.tab | grep ${image1} | awk '{print tolower(substr($0,437,6))}'`
	i1=`cat ${cumindexdir}/cumindex.tab | grep ${image1} | awk '{print tolower(substr($0,180,6))}'`
	g1=`cat ${cumindexdir}/cumindex.tab | grep ${image1} | awk '{print tolower(substr($0,187,6))}'`

	Ls2=`cat ${cumindexdir}/cumindex.tab | grep ${image2} | awk '{print tolower(substr($0,437,6))}'`
	i2=`cat ${cumindexdir}/cumindex.tab | grep ${image2} | awk '{print tolower(substr($0,180,6))}'`
	g2=`cat ${cumindexdir}/cumindex.tab | grep ${image2} | awk '{print tolower(substr($0,187,6))}'`

	Lsdiff=`echo ${Ls1} ${Ls2} | awk '{print $1-$2}'`
	idiff=`echo ${i1} ${i2} | awk '{print $1-$2}'`
	gdiff=`echo ${g1} ${g2} | awk '{print $1-$2}'`

	#Now print everything out
	echo ---------------------------------------------------------
	echo For image pair ${j}
	echo Image 1, ${image1}, Ls = ${Ls1}, incidence angle = ${i1}, phase angle = ${g1}
	echo Image 2, ${image2}, Ls = ${Ls2}, incidence angle = ${i2}, phase angle = ${g2}
	echo Difference for pair, Ls = ${Lsdiff}, incidence angle = ${idiff}, phase angle = ${gdiff}
	echo ---------------------------------------------------------

done

echo ---------------------------------------------------------
echo FINISHED
