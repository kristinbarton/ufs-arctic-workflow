TOP_DIR=$(pwd)

SYSTEM="ursa"
COMPILER="intel"
UFS_DIR=${TOP_DIR}/ufs-weather-model
cd ${UFS_DIR}/build
make clean
cd ${UFS_DIR}

module purge
module use modulefiles
module load ufs_${SYSTEM}.${COMPILER}.lua
CMAKE_FLAGS="-DAPP=S2S -DREGIONAL_MOM6=ON -DMOVING_NEST=OFF -DCCPP_SUITES=FV3_GFS_v17_coupled_p8_ugwpv1,FV3_HAFS_v1_gfdlmp_tedmf_nonsst" ./build.sh

PREP_DIR=${TOP_DIR}/prep
cd ${PREP_DIR}
./run_prep.sh --clean --all

cd ${TOP_DIR}
mkdir ${TOP_DIR}/run

mkdir ${TOP_DIR}/run
MODEL_DIR=${TOP_DIR}/run

mkdir ${MODEL_DIR}/INPUT
mkdir ${MODEL_DIR}/OUTPUT
mkdir ${MODEL_DIR}/RESTART
mkdir ${MODEL_DIR}/history
mkdir ${MODEL_DIR}/modulefiles

ATM_RES='C185'
CASE_NAME='custom'

FIX_DIR="/scratch4/BMC/ufs-artic/Kristin.Barton/files/ufs_arctic_development/fix_files"

cp -P ${PREP_DIR}/intercom/* ${MODEL_DIR}/INPUT/.
cp -P ${PREP_DIR}/config_files/${CASE_NAME}/* ${MODEL_DIR}/.
ln -s ${MODEL_DIR}/INPUT/gfs_data.tile7.nc ${MODEL_DIR}/INPUT/gfs_data.nc
ln -s ${MODEL_DIR}/INPUT/sfc_data.tile7.nc ${MODEL_DIR}/INPUT/sfc_data.nc
ln -s ${MODEL_DIR}/INPUT/gfs_bndy.tile7.000.nc ${MODEL_DIR}/INPUT/gfs.bndy.nc
cp -P ${FIX_DIR}/datasets/${ATM_RES}/*.nc ${MODEL_DIR}/.
cp -P ${FIX_DIR}/input_grid_files/atm/${ATM_RES}/* ${MODEL_DIR}/INPUT/.
cp -P ${FIX_DIR}/input_grid_files/ocn/* ${MODEL_DIR}/INPUT/.
cp -P ${FIX_DIR}/input_grid_files/ice/* ${MODEL_DIR}/INPUT/.
cp -P ${FIX_DIR}/datasets/* ${MODEL_DIR}/.
cp -P ${UFS_DIR}/modulefiles/ufs_${SYSTEM}.${COMPILER}.lua ${MODEL_DIR}/modulefiles/modules.fv3.lua
cp -P ${UFS_DIR}/modulefiles/ufs_common.lua ${MODEL_DIR}/modulefiles/.
cp -P ${UFS_DIR}/build/ufs_model ${MODEL_DIR}/fv3.exe
