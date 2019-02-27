#!/bin/bash

source ctx.conf

if [[ "$step" = "1" ]]; then
	sh 1_ctxedr2lev1eo.sh -p ${prod}
	step = 2
elif [[ "$step" = "2" ]]; then
	sh 2_asp_ctx_lev1eo2dem.sh -s ${config} -p ${prod}
	step = 3
elif [[ "$step" = "3" ]]; then
	sh 3_asp_ctx_step2_map2dem.sh -s ${config} -p ${prod}
	step = 4
elif [[ "$step" = "4" ]]; then
	sh 4_pedr_bin4pc_align.sh ${pedr_list}
	step = 5
elif [[ "$step" = "5" ]]; then
	sh 5_asp_ctx_map_ba_pc_align2dem_sn.sh -d ${dirs} -m ${maxd}
fi
