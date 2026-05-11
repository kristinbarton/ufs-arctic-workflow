#!/bin/sh
# ==============================================================================
# Atmosphere Prep Script (run_atm_prep.sh)
# Description: Generates surface initial conditions and atmosphere 
#              initial/lateral boundary conditions using chgres_cube
# ==============================================================================

set -eo pipefail

# ================================= #
# Logging & Validation              #
# ================================= #

log_info()  { echo -e "(info) $1"; }
log_warn()  { echo -e "(Warn) $1"; }
log_error() { echo -e "[ERROR] $1" >&2; }
error_exit() { log_error "$1"; exit 1; }

[[ -z "$CHGRES_EXEC" ]] && error_exit "CHGRES_EXEC is not set."
[[ -z "$CDATE" ]] && error_exit "CDATE is not set."
[[ -z "$ATM_RUN_DIR" ]] && error_exit "ATM_RUN_DIR is not set."

log_info "-> Using chgres_cube at: $CHGRES_EXEC"

module use "${UFS_UTILS_DIR}/modulefiles"
module load "build.${SYSTEM}.intelllvm.lua" || error_exit "Failed to load chgres module."

# ================================= #
# Global Variables & Date Setup     #
# ================================= #


cycle_year="${CDATE:0:4}"
cycle_mon="${CDATE:4:2}"
cycle_day="${CDATE:6:2}"
cycle_hour="${CDATE:8:2}"
cycle_hour="${cycle_hour:-00}"

# Shared namelist values
regional="${ATM_REGIONAL}"
halo_bndy="${ATM_HALO_BNDY}"
halo_blend="${ATM_HALO_BLEND}"

mosaic_file_target_grid="${FIX_DIR}/mesh_files/${ATM_DST_GRID}/${ATM_DST_GRID}_mosaic.nc"
fix_dir_target_grid="${FIX_DIR}/mesh_files/${ATM_DST_GRID}/sfc"
orog_dir_target_grid="${FIX_DIR}/mesh_files/${ATM_DST_GRID}"
orog_files_target_grid="${ATM_RES}_oro_data.tile${ATM_TILE}.halo${ATM_HALO_BNDY}.nc"
vcoord_file_target_grid="${FIX_DIR}/mesh_files/${ATM_DST_GRID}/global_hyblev.l${ATM_LEVS}.txt"

sotyp_from_climo=.true.
vgtyp_from_climo=.true.
vgfrc_from_climo=.true.
minmax_vgfrc_from_climo=.true.
tg3_from_soil=.true.
lai_from_climo=.true.
external_model="GFS"
nsoill_out=4
thomp_mp_climo_file="NULL"
wam_cold_start=.false.

# ================================= #
# Function Definitions              #
# ================================= #

generate_namelist() {
    cat > ./fort.41 <<EOF
&config
 mosaic_file_target_grid="${mosaic_file_target_grid:-NULL}"
 fix_dir_target_grid="${fix_dir_target_grid:-NULL}"
 orog_dir_target_grid="${orog_dir_target_grid:-NULL}"
 orog_files_target_grid="${orog_files_target_grid:-NULL}"
 vcoord_file_target_grid="${vcoord_file_target_grid:-NULL}"
 mosaic_file_input_grid="${mosaic_file_input_grid:-NULL}"
 orog_dir_input_grid="${orog_dir_input_grid:-NULL}"
 orog_files_input_grid="${orog_files_input_grid:-NULL}"
 data_dir_input_grid="${data_dir_input_grid:-NULL}"
 atm_files_input_grid="${atm_files_input_grid:-NULL}"
 atm_core_files_input_grid="${atm_core_files_input_grid:-NULL}"
 atm_tracer_files_input_grid="${atm_tracer_files_input_grid:-NULL}"
 sfc_files_input_grid="${sfc_files_input_grid:-NULL}"
 nst_files_input_grid="${nst_files_input_grid:-NULL}"
 grib2_file_input_grid="${grib2_file_input_grid:-NULL}"
 geogrid_file_input_grid="${geogrid_file_input_grid:-NULL}"
 varmap_file="${varmap_file:-NULL}"
 wam_parm_file="${wam_parm_file:-NULL}"
 cycle_year=${cycle_year}
 cycle_mon=${cycle_mon}
 cycle_day=${cycle_day}
 cycle_hour=${cycle_hour}
 convert_atm=${convert_atm}
 convert_sfc=${convert_sfc}
 convert_nst=${convert_nst}
 input_type="${input_type}"
 tracers=${tracers}
 tracers_input=${tracers_input}
 regional=${regional}
 halo_bndy=${halo_bndy}
 halo_blend=${halo_blend}
 sotyp_from_climo=${sotyp_from_climo}
 vgtyp_from_climo=${vgtyp_from_climo}
 vgfrc_from_climo=${vgfrc_from_climo}
 minmax_vgfrc_from_climo=${minmax_vgfrc_from_climo}
 tg3_from_soil=${tg3_from_soil}
 lai_from_climo=${lai_from_climo}
 external_model="${external_model}"
 nsoill_out=${nsoill_out}
 thomp_mp_climo_file="${thomp_mp_climo_file:-NULL}"
 wam_cold_start=${wam_cold_start}
/
EOF
}

run_chgres() {
    local log_file="$1"
    ${SRUN_n2} --time=30:00 "${CHGRES_EXEC}" 2>&1 | tee "${log_file}" > /dev/null

    if [ ${PIPESTATUS[0]} -ne 0 ]; then
        error_exit "chgres_cube failed! Check ${log_file} for details."
    fi

}

# ================================= #
# Generating SFC Files              #
# ================================= #

sfc_out="${ATM_RUN_DIR}/intercom/sfc_data.tile${ATM_TILE}.nc"
if [ -s "$sfc_out" ]; then
    log_info "-> Surface IC file already exists. Skipping."
else
    log_info "-> Generating surface IC files..."
    if [ "$SFC_IC_TYPE" = "restart_files" ]; then
        convert_atm=.false.
        convert_sfc=.true.
        convert_nst=.true.
        mosaic_file_input_grid="${FIX_DIR}/mesh_files/${ATM_SRC_GRID}/${ATM_SRC_GRID}_mosaic.nc"
        orog_dir_input_grid="${FIX_DIR}/mesh_files/${ATM_SRC_GRID}"
        orog_files_input_grid=${ATM_SRC_GRID}'_oro_data.tile1.nc","'${ATM_SRC_GRID}'_oro_data.tile2.nc","'${ATM_SRC_GRID}'_oro_data.tile3.nc","'${ATM_SRC_GRID}'_oro_data.tile4.nc","'${ATM_SRC_GRID}'_oro_data.tile5.nc","'${ATM_SRC_GRID}'_oro_data.tile6.nc'
        data_dir_input_grid="${ATM_INPUT_DIR}/ics"
        atm_core_files_input_grid='fv_core.res.tile1.nc","fv_core.res.tile2.nc","fv_core.res.tile3.nc","fv_core.res.tile4.nc","fv_core.res.tile5.nc","fv_core.res.tile6.nc","fv_core.res.nc'
        atm_tracer_files_input_grid='fv_tracer.res.tile1.nc","fv_tracer.res.tile2.nc","fv_tracer.res.tile3.nc","fv_tracer.res.tile4.nc","fv_tracer.res.tile5.nc","fv_tracer.res.tile6.nc'
        sfc_files_input_grid='sfc_data.tile1.nc","sfc_data.tile2.nc","sfc_data.tile3.nc","sfc_data.tile4.nc","sfc_data.tile5.nc","sfc_data.tile6.nc'
        input_type="restart"
        tracers='"sphum","liq_wat","o3mr","ice_wat","rainwat","snowwat","graupel"'
        tracers_input='"sphum","liq_wat","o3mr","ice_wat","rainwat","snowwat","graupel"'
    else
        error_exit "Unknown or unsupported SFC input type: ${SFC_IC_TYPE}"
    fi

    generate_namelist
    run_chgres "./chgres_cube_sfc.log"
    mv "${ATM_RUN_DIR}/out.sfc.tile${ATM_TILE}.nc" "$sfc_out"
fi

# ================================= #
# Generating ATM Files              #
# ================================= #


atm_out="${ATM_RUN_DIR}/intercom/gfs_data.tile${ATM_TILE}.nc"
if [ -s "$atm_out" ]; then
    log_info "-> Atmosphere IC files already exist. Skipping."
else
    log_info "-> Generating atmosphere IC files..."
    if [ "$ATM_IC_TYPE" = "restart_files" ]; then
        convert_atm=.true.
        convert_sfc=.false.
        convert_nst=.false.
        mosaic_file_input_grid="${FIX_DIR}/mesh_files/${ATM_SRC_GRID}/${ATM_SRC_GRID}_mosaic.nc"
        orog_dir_input_grid="${FIX_DIR}/mesh_files/${ATM_SRC_GRID}"
        orog_files_input_grid=${ATM_SRC_GRID}'_oro_data.tile1.nc","'${ATM_SRC_GRID}'_oro_data.tile2.nc","'${ATM_SRC_GRID}'_oro_data.tile3.nc","'${ATM_SRC_GRID}'_oro_data.tile4.nc","'${ATM_SRC_GRID}'_oro_data.tile5.nc","'${ATM_SRC_GRID}'_oro_data.tile6.nc'
        data_dir_input_grid="${ATM_INPUT_DIR}/ics"
        atm_core_files_input_grid='fv_core.res.tile1.nc","fv_core.res.tile2.nc","fv_core.res.tile3.nc","fv_core.res.tile4.nc","fv_core.res.tile5.nc","fv_core.res.tile6.nc","fv_core.res.nc'
        atm_tracer_files_input_grid='fv_tracer.res.tile1.nc","fv_tracer.res.tile2.nc","fv_tracer.res.tile3.nc","fv_tracer.res.tile4.nc","fv_tracer.res.tile5.nc","fv_tracer.res.tile6.nc'
        sfc_files_input_grid='sfc_data.tile1.nc","sfc_data.tile2.nc","sfc_data.tile3.nc","sfc_data.tile4.nc","sfc_data.tile5.nc","sfc_data.tile6.nc'
        input_type="restart"
        tracers='"sphum","liq_wat","o3mr","ice_wat","rainwat","snowwat","graupel"'
        tracers_input='"sphum","liq_wat","o3mr","ice_wat","rainwat","snowwat","graupel"'
    
    elif [ "$ATM_IC_TYPE" = "grib_files" ]; then
        convert_atm=.true.
        convert_sfc=.false.
        convert_nst=.false.
        mosaic_file_input_grid="NULL"
        orog_dir_input_grid="NULL"
        orog_files_input_grid="NULL"
        data_dir_input_grid="${ATM_INPUT_DIR}/fcst/atmos/combined"
        atm_core_files_input_grid="NULL"
        atm_tracer_files_input_grid="NULL"
        input_type="grib2"
        tracers='"sphum","liq_wat","o3mr","ice_wat","rainwat","snowwat","graupel"'
        tracers_input='"spfh","clwmr","o3mr","ice_wat","rainwat","snowwat","graupel"'
        grib2_file_input_grid="gefs.t00z.pgrb2_combined.0p25.f003"
        atm_file_input_grid="gefs.t00z.pgrb2_combined.0p25.f003"
        sfc_file_input_grid="gefs.t00z.pgrb2_combined.0p25.f003"
        varmap_file="${UFS_UTILS_DIR}/parm/varmap_tables/GFSphys_var_map.txt"
    
    else
        error_exit "Unknown or unsupported ATM input type: ${ATM_IC_TYPE}"
    fi

    generate_namelist
    run_chgres "./chgres_cube_atm.log"
    
    mv "${ATM_RUN_DIR}/gfs_ctrl.nc" "${ATM_RUN_DIR}/intercom/gfs_ctrl.nc"
    mv "${ATM_RUN_DIR}/gfs.bndy.nc" "${ATM_RUN_DIR}/intercom/gfs_bndy.tile${ATM_TILE}.000.nc"
    mv "${ATM_RUN_DIR}/out.atm.tile${ATM_TILE}.nc" "$atm_out"
fi

# ================================= #
# Generating LBC Files              #
# ================================= #

log_info "-> Generating atmosphere LBC files..."

fhr_b=${ATM_LBC_INT}
fhr_e=${NHRS}
fhr_i=${ATM_LBC_INT}
fhr=${fhr_b}

if [ "$ATM_LBC_TYPE" = "grib_files" ]; then
    convert_atm=.true.
    convert_sfc=.false.
    convert_nst=.false.
    mosaic_file_input_grid="NULL"
    orog_dir_input_grid="NULL"
    orog_files_input_grid="NULL"
    data_dir_input_grid="${ATM_INPUT_DIR}/fcst/atmos/combined"
    atm_files_input_grid="NULL"
    atm_core_files_input_grid="NULL"
    atm_tracer_files_input_grid="NULL"
    sfc_files_input_grid="NULL"
    convert_nst=.true.
    input_type="grib2"
    tracers="sphum","liq_wat","o3mr","ice_wat","rainwat","snowwat","graupel"
    tracers_input="spfh","clmr","o3mr","icmr","rwmr","snmr","grle"
    varmap_file="${UFS_UTILS_DIR}/parm/varmap_tables/GFSphys_var_map.txt"
else
    error_exit "Unknown or unsupported LBC input type: ${ATM_LBC_TYPE}"
fi

while [ "$fhr" -le "$fhr_e" ]; do
    fhr_str=$(printf "%03d" "$fhr")
    lbc_out="${ATM_RUN_DIR}/intercom/gfs_bndy.tile${ATM_TILE}.${fhr_str}.nc"

    if [ -s "$lbc_out" ]; then
        log_info "-> Atmosphere LBC file for forecast hour ${fhr_str} already exists. Skipping."
    else
        log_info "-> Processing LBC at forecast hour ${fhr_str}"
    
        grib2_file_input_grid="gefs.t${cycle_hour}z.pgrb2_combined.0p25.f${fhr_str}"
        
        generate_namelist
        run_chgres "./chgres_cube_lbc_${fhr_str}.log"
    
        mv "${ATM_RUN_DIR}/gfs.bndy.nc" "$lbc_out"
    
    fi
    fhr=$(($fhr + $fhr_i))
done

log_info "-> Atmosphere prep complete."
exit 0
