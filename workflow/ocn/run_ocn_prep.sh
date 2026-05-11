#!/bin/sh
# ==============================================================================
# Ocean Prep Script (run_init.sh)
# Description: Prepares inputs for MOM6 Arctic grid, including initial
#              conditions (IC), lateral boundary conditions (OBC), and forcing.
# ==============================================================================

set -eo pipefail

# ================================= #
# Logging & Validation              #
# ================================= #

log_info()  { echo -e "(info) $1"; }
log_warn()  { echo -e "(Warn) $1"; }
log_error() { echo -e "[ERROR] $1" >&2; }
error_exit() { log_error "$1"; exit 1; }

# Fail-fast validation
required_vars=(
    "CDATE" "OCN_IC_TYPE" "NLN" "SRUN_n1" "OCN_RUN_DIR" 
    "OCN_SCRIPT_DIR" "OCN_DST_GRID_DIR" "OCN_SRC_GRID_DIR"
)
for var in "${required_vars[@]}"; do
    [[ -z "${!var}" ]] && error_exit "Required variable '$var' is not set."
done

# ================================= #
# Date Parsing & Setup              #
# ================================= #

ymd="${CDATE:0:8}"
hour="00"

if [ "${hour}" == "00" ]; then
  type=${type:-n}
else
  type=${type:-f}
fi

mkdir -p "${OCN_RUN_DIR}/intercom/"
mkdir -p "${OCN_RUN_DIR}/inputs/"

# Retrive the regridding weights and ocean grid files
mkdir -p "${OCN_RUN_DIR}/inputs/"
${NLN} "${OCN_DST_GRID_DIR}"/* "${OCN_RUN_DIR}/inputs/."
${NLN} "${OCN_SRC_GRID_DIR}"/* "${OCN_RUN_DIR}/inputs/."
${NLN} "${OCN_SCRIPT_DIR}"/* "${OCN_RUN_DIR}/inputs/."

if [ "$OCN_IC_TYPE" == 'gefs' ]; then
    export wgt_file_base=${OCN_WGT_FILE_BASE}
    ic_filename="${OCN_RUN_DIR}/inputs/Ct.${OCN_SRC_GRID}_SCRIP_masked.nc"
    bc_filename="${OCN_RUN_DIR}/inputs/Ct.${OCN_SRC_GRID}_SCRIP.nc"
    method="neareststod"
    ${NLN} "${OCN_INPUT_DIR}"/*.nc "${OCN_RUN_DIR}/inputs/."
elif [[ "$OCN_IC_TYPE" == 'rtofs' ]]; then
    wgt_file_base='rtofs2arctic'
    ic_filename="${OCN_RUN_DIR}/inputs/rtofs_global_ssh_ic.nc"
    bc_filename="${OCN_RUN_DIR}/inputs/rtofs_global_ssh_ic.nc"
    method="neareststod"
fi

# ================================= #
# Functions Definitions             #
# ================================= #

link_rtofs_archive() {
    local hr="$1"
    local prefix="${COMIN_RTOFS}/rtofs.${ymd}/rtofs_glo.t00z.${type}${hr}.archv"

    for ext in a b; do
        if [[ -e "${prefix}.${ext}" ]]; then
            ${NLN} "${prefix}.${ext}" "archv_in.${ext}"
        elif [[ -e "${prefix}.${ext}.tgz" ]]; then
            tar -xpvzf "${prefix}.${ext}.tgz"
            ${NLN} "rtofs_glo.t00z.${type}${hr}.archv.${ext}" "archv_in.${ext}"
        else
            error_exit "RTOFS archive missing: ${prefix}.${ext} (or .tgz equivalent)"
        fi
    done
}

generate_weight() {
    local src="$1"
    local dst="$2"
    local wgt="$3"

    if [[ ! -e "$wgt" ]]; then
        log_info "-> Weight file does not exist: ${wgt}. Generating with ESMF..."
        ${SRUN_n1} ESMF_RegridWeightGen -s "$src" -d "$dst" -w "$wgt" -m "$method" \
            --dst_loc center --netCDF4 --dst_regional --ignore_degenerate > /dev/null || error_exit "ESMF failed on ${wgt}"
    fi
}

# ================================= #
# Initial Conditions (IC) Setup     #
# ================================= #

input_dir="${OCN_RUN_DIR}/inputs"
output_dir="${OCN_RUN_DIR}/intercom"
out_file_path="${output_dir}/${OCN_IC_FILE}"
tmp_file_path="${out_file_path}.tmp"
dst_vrt_file_path="${input_dir}/${OCN_DST_VRT_FILE}"
h_wgt="${input_dir}/${wgt_file_base}_h.nc"

if [ -s "$out_file_path" ]; then
    log_info "-> Ocean IC file already exists and is complete. Skipping."
else

    log_info "-> Generating Ocean IC files..."
    cd "${OCN_RUN_DIR}/inputs/"
    
    if [[ "$OCN_IC_TYPE" == 'rtofs' ]]; then
        export CDF038="rtofs_global_ssh_ic.nc"
        export CDF034="rtofs_global_ts_ic.nc"
        export CDF033="rtofs_global_uv_ic.nc"
    
        # Link global RTOFS depth and grid files
        ${NLN} "${FIX_HAFS}/fix_mom6/fix_gofs/depth_GLBb0.08_09m11ob.a" regional.depth.a
        ${NLN} "${FIX_HAFS}/fix_mom6/fix_gofs/depth_GLBb0.08_09m11ob.b" regional.depth.b
        ${NLN} "${FIX_HAFS}/fix_hycom/rtofs_glo.navy_0.08.regional.grid.a" regional.grid.a
        ${NLN} "${FIX_HAFS}/fix_hycom/rtofs_glo.navy_0.08.regional.grid.b" regional.grid.b
    
        link_rtofs_archive "$hour"
    
        # Run HYCOM-tools executables
        log_info "-> Preparing rtofs inputs with HYCOM archv2ncdf utilities .."
        ${SRUN_n1} "${EXEChafs}/hafs_hycom_utils_archv2ncdf3z.x" < ./rtofs_global_3d_ic.in 2>&1 | tee archv2ncdf3z_3d_ic.log > /dev/null
        ${SRUN_n1} "${EXEChafs}/hafs_hycom_utils_archv2ncdf2d.x" < ./rtofs_global_ssh_ic.in 2>&1 | tee archv2ncdf2d_ssh_ic.log > /dev/null
    
        unlink archv_in.a
        unlink archv_in.b
    fi
    
    # Generate Subgrids
    if [[ ! -e "ocean_subgrid_v.nc" ]] && [[ ! -e "ocean_subgrid_u.nc" ]]; then
        log_info "-> U/V subgrid files do not exist. Creating them..."
        "${OCN_SCRIPT_DIR}/utils/make_subgrids.py" --lat y --lon x --fin ocean_hgrid.nc --out ocean_subgrid
    fi
    
    # Generate Center, U, and V Weights
    generate_weight "${ic_filename}" "ocean_mask.nc"      "${wgt_file_base}_h.nc"
    generate_weight "${ic_filename}" "ocean_subgrid_v.nc" "${wgt_file_base}_v.nc"
    generate_weight "${ic_filename}" "ocean_subgrid_u.nc" "${wgt_file_base}_u.nc"
    
    rm -f "$tmp_file_path"

    ${SRUN_n1} python "${OCN_SCRIPT_DIR}/run_ocn_prep.py" \
        --var_name "${OCN_U_VAR}" "${OCN_V_VAR}" \
        --src_file "${input_dir}/${OCN_U_SRC}" "${input_dir}/${OCN_V_SRC}" \
        --src_ang_name "${OCN_SRC_ANG_VAR}" \
        --src_ang_file "${input_dir}/${OCN_SRC_ANG_FILE}" \
        --src_ang_supergrid "${OCN_SRC_ANG_CONVERT}" \
        --dst_ang_name "${OCN_DST_ANG_VAR}" \
        --dst_ang_file "${input_dir}/${OCN_DST_ANG_FILE}" \
        --dst_ang_supergrid "${OCN_DST_ANG_CONVERT}" \
        --wgt_file "${input_dir}/${wgt_file_base}_u.nc" "${input_dir}/${wgt_file_base}_v.nc" \
        --vrt_file "${dst_vrt_file_path}" \
        --out_file "${tmp_file_path}" \
        --dz_name "${OCN_DST_VRT_VAR}" \
        --time_name "${OCN_TIME_VAR}" || error_exit "U-V Vector remapping failed."
    
    # Define scalars in a delimited array: "DisplayName:VariableName:SourceFile"
    scalars=(
        "Temperature:${OCN_TMP_VAR}:${OCN_TMP_SRC}"
        "Salinity:${OCN_SAL_VAR}:${OCN_SAL_SRC}"
        "Thickness:${OCN_THK_VAR}:${OCN_THK_SRC}"
        "SSH:${OCN_SSH_VAR}:${OCN_SSH_SRC}"
    )
    
    for item in "${scalars[@]}"; do
        desc="${item%%:*}"
        rest="${item#*:}"
        var_name="${rest%%:*}"
        src_file="${rest#*:}"
    
        ${SRUN_n1} python "${OCN_SCRIPT_DIR}/run_ocn_prep.py" \
            --var_name "${var_name}" \
            --src_file "${input_dir}/${src_file}" \
            --wgt_file "${h_wgt}" \
            --vrt_file "${dst_vrt_file_path}" \
            --out_file "${tmp_file_path}" \
            --dz_name "${OCN_DST_VRT_VAR}" \
            --time_name "${OCN_TIME_VAR}" || error_exit "${desc} remapping failed."
    done

    ${SRUN_n1} python "${OCN_SCRIPT_DIR}/utils/add_eta.py" \
        --file_name "${tmp_file_path}" \
        --thickness_variable "${OCN_THK_VAR}" \
        --time_dim "${OCN_TIME_VAR}" || error_exit "Failed to add ETA variable."

    mv "${tmp_file_path}" "${out_file_path}"
fi

# ================================= #
# Lateral Boundaries (OBC) Setup    #
# ================================= #

log_info "-> Generating Ocean OBC files..."
cd "${OCN_RUN_DIR}/inputs/"

if [[ "$OCN_IC_TYPE" == 'rtofs' ]]; then
    export CDF038="rtofs.${type}${hour}_global_ssh_obc.nc"
    export CDF034="rtofs.${type}${hour}_global_ts_obc.nc"
    export CDF033="rtofs.${type}${hour}_global_uv_obc.nc"

    link_rtofs_archive "$hour"

    log_info "-> Running HYCOM archv2ncdf utilities (OBC)..."
    ${SRUN_n1} "${EXEC_HAFS}/hafs_hycom_utils_archv2ncdf2d.x" < ./rtofs_global_ssh_obc.in 2>&1 | tee archv2ncdf2d_ssh_obc.log > /dev/null
    ${SRUN_n1} "${EXEC_HAFS}/hafs_hycom_utils_archv2ncdf3z.x" < ./rtofs_global_3d_obc.in 2>&1 | tee archv2ncdf3z_3d_obc.log > /dev/null

    unlink archv_in.a
    unlink archv_in.b
elif [[ "$OCN_IC_TYPE" != 'gefs' ]]; then
    error_exit "OCN source grid type invalid: ${OCN_IC_TYPE}"
fi

time_var_out="${OCN_TIME_VARNAME_OUT:-$OCN_TIME_VAR}"

obc_scalars=(
    "Temperature:${OCN_TMP_VAR}:${OCN_TMP_SRC}"
    "Salinity:${OCN_SAL_VAR}:${OCN_SAL_SRC}"
    "SSH:${OCN_SSH_VAR}:${OCN_SSH_SRC}"
)

for i in 001 002 003 004; do
    
    wgt_file="${wgt_file_base}_${i}.nc"
    wgt_path="${input_dir}/${wgt_file}"
    obc_out_path="${output_dir}/${OCN_OUT_FILE_BASE}${i}${OCN_FILE_TAIL}"
    obc_tmp_path="${obc_out_path}.tmp"
    ang_file="${input_dir}/${OCN_ANG_FILE_BASE}${i}${OCN_FILE_TAIL}"
    hgrid_path="${input_dir}/ocean_hgrid_${i}.nc"

    if [ -s "$obc_out_path" ]; then
        log_info "-> OBC Boundary ${i} already exits. Skipping."
        continue
    fi

    log_info "-> Processing OBC Boundary ${i}"

    rm -f "$obc_tmp_path"
    
    generate_weight "${bc_filename}" "ocean_hgrid_${i}.nc" "${wgt_file}"

    # --- 1. Remap U-V Vectors ---
    ${SRUN_n1} python "${OCN_SCRIPT_DIR}/run_ocn_prep.py" \
        --var_name "${OCN_U_VAR}" "${OCN_V_VAR}" \
        --src_file "${input_dir}/${OCN_U_SRC}" "${input_dir}/${OCN_V_SRC}" \
        --src_ang_name "${OCN_SRC_ANG_VAR}" \
        --src_ang_file "${input_dir}/${OCN_SRC_ANG_FILE}" \
        --src_ang_supergrid "${OCN_SRC_ANG_CONVERT}" \
        --dst_ang_name "${OCN_DST_ANG_VAR}" \
        --dst_ang_file "${ang_file}" \
        --dst_ang_supergrid "${OCN_DST_ANG_CONVERT}" \
        --wgt_file "${wgt_path}" \
        --vrt_file "${dst_vrt_file_path}" \
        --out_file "${obc_tmp_path}" \
        --dz_name "${OCN_DST_VRT_VAR}" \
        --time_name "${OCN_TIME_VAR}" \
        --time_name_out "${time_var_out}" || error_exit "OBC Boundary ${i} U-V remapping failed."

    # --- 2. Remap Scalars ---
    for item in "${obc_scalars[@]}"; do
        desc="${item%%:*}"
        rest="${item#*:}"
        var_name="${rest%%:*}"
        src_file="${rest#*:}"

        ${SRUN_n1} python "${OCN_SCRIPT_DIR}/run_ocn_prep.py" \
            --var_name "${var_name}" \
            --src_file "${input_dir}/${src_file}" \
            --wgt_file "${wgt_path}" \
            --vrt_file "${dst_vrt_file_path}" \
            --out_file "${obc_tmp_path}" \
            --dz_name "${OCN_DST_VRT_VAR}" \
            --time_name "${OCN_TIME_VAR}" \
            --time_name_out "${time_var_out}" || error_exit "OBC Boundary ${i} ${desc} remapping failed."
    done

    # --- 3. Format NetCDF Files (NCO) ---
    
    # Rename dimensions and variables
    ncrename -O \
        -d "${OCN_DST_VRT_VAR},nz_segment_${i}" \
        -d "yh,ny_segment_${i}" \
        -d "xh,nx_segment_${i}" \
        -v "${OCN_SSH_VAR},ssh_segment_${i}" \
        -v "${OCN_TMP_VAR},temp_segment_${i}" \
        -v "${OCN_SAL_VAR},salinity_segment_${i}" \
        -v "${OCN_U_VAR},u_segment_${i}" \
        -v "${OCN_V_VAR},v_segment_${i}" "${obc_tmp_path}"

    # Generate dz arrays via ncap2
    ncap2 -O -s "dz_u_segment_${i}[${time_var_out},nz_segment_${i},ny_segment_${i},nx_segment_${i}]=${OCN_DST_VRT_VAR}(:)" "${obc_tmp_path}" "${obc_tmp_path}"
    ncap2 -O -s "dz_v_segment_${i}[${time_var_out},nz_segment_${i},ny_segment_${i},nx_segment_${i}]=${OCN_DST_VRT_VAR}(:)" "${obc_tmp_path}" "${obc_tmp_path}"
    ncap2 -O -s "dz_ssh_segment_${i}[${time_var_out},nz_segment_${i},ny_segment_${i},nx_segment_${i}]=${OCN_DST_VRT_VAR}(:)" "${obc_tmp_path}" "${obc_tmp_path}"
    ncap2 -O -s "dz_salinity_segment_${i}[${time_var_out},nz_segment_${i},ny_segment_${i},nx_segment_${i}]=${OCN_DST_VRT_VAR}(:)" "${obc_tmp_path}" "${obc_tmp_path}"
    ncap2 -O -s "dz_temp_segment_${i}[${time_var_out},nz_segment_${i},ny_segment_${i},nx_segment_${i}]=${OCN_DST_VRT_VAR}(:)" "${obc_tmp_path}" "${obc_tmp_path}"

    # Remove the original vertical coordinate variable
    ncks -O -x -v "${OCN_DST_VRT_VAR}" "${obc_tmp_path}" "${obc_tmp_path}" > /dev/null 2>&1

    # Extract Lat/Lon from HGRID and append to OBC output safely
    rm -f tmp.nc
    if [[ "$i" == "001" ]] || [[ "$i" == "002" ]]; then
        ncap2 -A -v -s "lon_segment_${i}[nxp]=x(0,:)" "${hgrid_path}" tmp.nc
        ncap2 -A -v -s "lat_segment_${i}[nxp]=y(0,:)" "${hgrid_path}" tmp.nc
        ncrename -d "nxp,nx_segment_${i}" tmp.nc
    elif [[ "$i" == "003" ]] || [[ "$i" == "004" ]]; then
        ncap2 -A -v -s "lon_segment_${i}[nyp]=x(:,0)" "${hgrid_path}" tmp.nc
        ncap2 -A -v -s "lat_segment_${i}[nyp]=y(:,0)" "${hgrid_path}" tmp.nc
        ncrename -d "nyp,ny_segment_${i}" tmp.nc
    fi

    ncap2 -A -v -s "lon_segment_${i}=lon_segment_${i}" tmp.nc "${obc_tmp_path}"
    ncap2 -A -v -s "lat_segment_${i}=lat_segment_${i}" tmp.nc "${obc_tmp_path}"
    rm -f tmp.nc

    mv "${obc_tmp_path}" "${obc_out_path}"
done

log_info "-> Ocean Prep complete."
exit 0
