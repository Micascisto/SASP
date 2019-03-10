# Stefano's version of USGS ASP Scripts #

I modified USGS ASP Scripts and added some of my own to produce CTX, HiRISE, and HRSC (work in progress) DEMs from stereo pairs.

I would like to thank USGS for providing this amazing toolset for free to the community.

These scripts are currently under development, and by no means stable and guaranteed to work on every machine. If you encounter any issues, feel free to report them, I always appreciate.

## Major edits to the original USGS scripts and settings ##

- CTX: Removed code inherent to high-performance computing environments using the SLURM job manager. This can be added back with a few lines of code, but I don't need it and prefer to keep the code cleaner for easier testing and debugging.
- CTX: Removed cam2map4stereo.py and substitude with ISIS caminfo to produce a Transverse Mercator projection with reference longitude equal to the central latitude of the left image. This projection solves distorion issues associated with the default Sinusoidal projection at high latitudes.
- CTX: Step 1 now can be run with the optional flag -w. This tells spiceinit to download SPICE kernels using the USGS ISIS Web service. This avoids the need to download all the kernels when installing ISIS, thus saving 10s GB of disk space and time. Also, this eliminates the need to keep the kernels up to date.
- CTX: Moved creation of low resolution DEM from the beginning of step 3 to the end of step 2. There are two reasons for this: (1) It seemed logical to me to generate the DEM right after running parallel_stereo instead of a completely separate script, (2) one can check the result of parallel_stereo with SGM right away after running step 2.
- CTX: Step 2 is meant to run with Semi-Global Matching settings. So, I renamed the step 2 script to reflect this crucial detail, and wrote a new setting file 'ctx_SGM_step2.stereo'. I recommend taking a look at these settings, because mine are not necessarily ideal for your particular situation.
- CTX: All the scripts that take advantage of multiprocessing now read in the number of cpu cores as an argument. You can find info on your CPUs with 'cat /proc/cpuinfo'. This way, multithreading settings are not hardcoded anymore and don't need to be edited.
- CTX: All scripts now keep the wroking folder cleaner by either better organizing files or deleting unnecessary files. This is usually done at the end of each script, so you can easily disable it.

## Dependencies ##
- USGS ISIS3 <http://isis.astrogeology.usgs.gov/> (Read above regarding SPICE kernels)
- NASA Ames Stereo Pipeline <https://ti.arc.nasa.gov/tech/asr/intelligent-robotics/ngt/stereo/>
- GDAL <http://www.gdal.org/>
- GNU Parallel <https://www.gnu.org/software/parallel/>
- pedr2tab <http://pds-geosciences.wustl.edu/missions/mgs/molasoftware.html#PEDR2TAB>
-- There is a USGS-modified version that works on most modern flavors of Linux, and Mac OS X <https://github.com/USGS-Astrogeology/socet_set/blob/master/SS4HiRISE/Software/ISIS3_MACHINE/SOURCE_CODE/pedr2tab.PCLINUX.f>. I put copy of this code and the compiled executable in the pedr2tab folder.

## Supported Platforms ##
This version of USGS ASP Scripts has been tested only on Linux Ubuntu.

## Basic Usage ##
Scripts for processing CTX, HiRISE, and HRSC data are organized into their own subdirectories.  The order in which individual scripts should be run is listed below. To make things easier, I put a sequence number in front of each script. Please see comments in the individual scripts for detailed usage information.  Running any of the scripts without arguments will print a usage message.

### CTX ###
0. Download .IMG EDR files. My favorite way to do this is via JMARS>Web Browse.
1. 1_ctxedr2lev1eo.sh
2. 2_asp_ctx_lev1eo2sgm_dem.sh
3. 3_asp_ctx_step2_map2dem.sh
4. 4_pedr_bin4_pc_align.sh
   (Optional: Estimate max displacement between initial CTX DTM and MOLA PEDR using your favorite GIS software)
5. 5_asp_ctx_map_ba_pc_align2dem.sh

### HiRISE ###
1. asp_hirise_prep.sh
2. asp_hirise_map2dem.sh
3. (Estimate max displacement between initial HiRISE DTM and reference DTM, such as CTX, using your favorite GIS)
4. asp_hirise_pc_align2dem.sh

## Referencing this Workflow ##
Please give all credits to the USGS Team by citing one or both of the following LPSC abstracts in any publications that make use of this work or derivatives thereof:
1. Mayer, D.P. and Kite, E.S., "An Integrated Workflow for Producing Digital Terrain Models of Mars from CTX and HiRISE Stereo Data Using the NASA Ames Stereo Pipeline," (2016) LPSC XLVII, Abstr. #1241. <https://www.hou.usra.edu/meetings/lpsc2016/pdf/1241.pdf>
E-poster: <https://www.lpi.usra.edu/meetings/lpsc2016/eposter/1241.pdf>
2. Mayer, D. P., "An Improved Workflow for Producing Digital Terrain Models of Mars from CTX Stereo Data Using the NASA Ames Stereo Pipeline," (2018) LPSC XLIX, Abstr. #1604. <https://www.hou.usra.edu/meetings/lpsc2018/pdf/1604.pdf>
E-poster: <https://www.hou.usra.edu/meetings/lpsc2018/eposter/1604.pdf>

The Ames Stereo Pipeline itself should be cited according to guidelines outlined in the official ASP documentation: <https://ti.arc.nasa.gov/tech/asr/groups/intelligent-robotics/ngt/stereo/>
