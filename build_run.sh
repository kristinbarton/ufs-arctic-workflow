# ================================= #
# User-adjusted parameters          #
# ================================= #

set -e -o pipefail

# Current available dates are:
# 2019/10/28, 2020/02/27, 2020/07/02, 2020/07/09, 2020/08/27
export CDATE=20191028 #YYYYMMDD
export NHRS=3 # Max run length is 240 Hours
export SACCT="ufs-artic"
export SYSTEM="ursa"
export COMPILER="intelllvm"
export RUN_DIR="/scratch4/BMC/ufs-artic/Kristin.Barton/stmp/test_runs/test_build_run_script" 

# ================================= #
# Below does not need to be changed #
# ================================= #

ATM_RES='C185'
FIX_DIR="/scratch4/BMC/ufs-artic/Kristin.Barton/files/ufs_arctic_development/fix_files"
TOP_DIR=$(pwd)

# Compile model
UFS_DIR=${TOP_DIR}/ufs-weather-model
compile() {
    if [ ! -f "${UFS_DIR}/build/ufs_model" ]; then
        echo "Compiling UFS"
        cd ${UFS_DIR}/build
        make clean
        cd ${UFS_DIR}
        module use modulefiles
        module load ufs_${SYSTEM}.${COMPILER}.lua
        CMAKE_FLAGS="-DDEBUG=ON -DAPP=S2S -DREGIONAL_MOM6=ON -DMOVING_NEST=OFF -DCCPP_SUITES=FV3_GFS_v17_coupled_p8_ugwpv1" ./build.sh
        echo "Compilation Complete"
    else
        echo "Skipping compile; UFS executable exists: ${UFS_DIR}/build/ufs_model"
    fi
}

# Run initial condition prep
PREP_DIR=${TOP_DIR}/prep
prep() {
    echo "Running input file prep script"
    cd ${PREP_DIR}
    ./run_prep.sh --clean --all
    cd ${TOP_DIR}
    echo "Input File Generation Complete"
}

# Make a new run directory
setup() {
    YEAR=${CDATE:0:4}
    MONTH=${CDATE:4:2}
    DAY=${CDATE:6:2}
    base="${RUN_DIR}/${YEAR}-${MONTH}-${DAY}_${NHRS}HRS"
    count=1
    MODEL_DIR=${base}
    while [ -e "$MODEL_DIR" ]; do
        MODEL_DIR="${base}_${count}"
        ((count++))
    done
   
    if [ -e ${TOP_DIR}/run ]; then
        unlink ${TOP_DIR}/run
    fi
    ln -s ${MODEL_DIR} ${TOP_DIR}/run
    
    # Populate run directories
    mkdir -p ${MODEL_DIR}
    mkdir -p ${MODEL_DIR}/INPUT
    mkdir -p ${MODEL_DIR}/OUTPUT
    mkdir -p ${MODEL_DIR}/RESTART
    mkdir -p ${MODEL_DIR}/history
    mkdir -p ${MODEL_DIR}/modulefiles
    
    # Populate INPUT directory
    cp -P ${PREP_DIR}/intercom/* ${MODEL_DIR}/INPUT/.
    ln -s gfs_data.tile7.nc ${MODEL_DIR}/INPUT/gfs_data.nc
    ln -s sfc_data.tile7.nc ${MODEL_DIR}/INPUT/sfc_data.nc
    ln -s gfs_bndy.tile7.000.nc ${MODEL_DIR}/INPUT/gfs.bndy.nc
    cp -P ${FIX_DIR}/datasets/${ATM_RES}/*.nc ${MODEL_DIR}/.
    cp -P ${FIX_DIR}/input_grid_files/atm/${ATM_RES}/* ${MODEL_DIR}/INPUT/.
    cp -P ${FIX_DIR}/input_grid_files/ocn/* ${MODEL_DIR}/INPUT/.
    cp -P ${FIX_DIR}/input_grid_files/ice/* ${MODEL_DIR}/INPUT/.
    cp -P ${FIX_DIR}/datasets/run_dir/* ${MODEL_DIR}/.
    cp -P ${UFS_DIR}/modulefiles/ufs_${SYSTEM}.${COMPILER}.lua ${MODEL_DIR}/modulefiles/modules.fv3.lua
    cp -P ${UFS_DIR}/modulefiles/ufs_common.lua ${MODEL_DIR}/modulefiles/.
    cp -P ${UFS_DIR}/build/ufs_model ${MODEL_DIR}/fv3.exe
    
    # Add fixed config files
    cp -P ${PREP_DIR}/config_files/templates/data_table ${MODEL_DIR}/.
    cp -P ${PREP_DIR}/config_files/templates/diag_table ${MODEL_DIR}/.
    cp -P ${PREP_DIR}/config_files/templates/fd_ufs.yaml ${MODEL_DIR}/.
    cp -P ${PREP_DIR}/config_files/templates/field_table ${MODEL_DIR}/.
    cp -P ${PREP_DIR}/config_files/templates/module-setup.sh ${MODEL_DIR}/.
    cp -P ${PREP_DIR}/config_files/templates/noahmptable.tbl ${MODEL_DIR}/.
    cp -P ${PREP_DIR}/config_files/templates/ufs.configure ${MODEL_DIR}/.
    cp -P ${PREP_DIR}/config_files/templates/input.nml ${MODEL_DIR}/.
    cp -P ${PREP_DIR}/config_files/templates/MOM_input ${MODEL_DIR}/.
    
    # Adjust config templates for specific case
    awk -v y="$YEAR" -v m="$MONTH" -v d="$DAY" '
      {
        gsub(/YEAR/, y)
        gsub(/MONTH/,   m)
        gsub(/DAY/,   d)
        print
      }
    ' ${PREP_DIR}/config_files/templates/ice_in > ${MODEL_DIR}/ice_in 
    
    awk -v y="$YEAR" -v m="$MONTH" -v d="$DAY" '
      {
        gsub(/YEAR/, y)
        gsub(/MONTH/,   m)
        gsub(/DAY/,   d)
        print
      }
    ' ${PREP_DIR}/config_files/templates/diag_table > ${MODEL_DIR}/diag_table
    
    awk -v y="$YEAR" -v m="$MONTH" -v d="$DAY" -v h="$NHRS" '
      {
        gsub(/YEAR/, y)
        gsub(/MONTH/,   m)
        gsub(/DAY/,   d)
        gsub(/NHRS/,   h)
        print
      }
    ' ${PREP_DIR}/config_files/templates/model_configure > ${MODEL_DIR}/model_configure
    
    awk -v y="$YEAR" -v m="$MONTH" -v d="$DAY" -v h="$NHRS" -v a="$SACCT" '
      {
        gsub(/YEAR/, y)
        gsub(/MONTH/,   m)
        gsub(/DAY/,   d)
        gsub(/NHRS/,   h)
        gsub(/SACCT/,   a)
        print
      }
    ' ${PREP_DIR}/config_files/templates/job_card > ${MODEL_DIR}/job_card
    
    cd ${PREP_DIR}
    ./clean.sh
    echo " ===== "
    echo ""
    echo "Model run directory built in ${MODEL_DIR}"
}

run_model() {
    echo "Submitting model run"
    cd ${TOP_DIR}/run
    sbatch job_card
}

help() {
    echo "Usage: $0 [--norun]"
    exit 1
}

# Run logic
submit_job=true
while [ $# -gt 0 ]; do
    case "$1" in
        --norun)
            submit_job=false
            ;;
        *)
            echo "Unknown option: $1"
            help
            ;;
    esac
    shift
done

compile
echo ""
prep
echo ""
setup
echo ""
if [[ "$submit_job" == true ]]; then
    run_model
fi
