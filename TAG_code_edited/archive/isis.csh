#!/bin/csh

setenv ISISROOT /disk/qnap-2/MARS/syst/ext/linux/apps/isis3/isis
source $ISISROOT/scripts/isis3Startup.csh
setenv LD_LIBRARY_PATH /disk/qnap-2/MARS/syst/ext/linux/apps/isis3/isis/3rdParty/lib:$LD_LIBRARY_PATH
setenv PATH "/disk/qnap-2/MARS/syst/ext/linux/apps/isis3/StereoPipeline-2.4.1-2014-07-15-x86_64-Linux-GLIBC-2.5/bin:${PATH}"
