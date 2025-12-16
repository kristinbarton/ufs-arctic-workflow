export CASE_NAME='2020-07-04_240HR'
SYSTEM="ursa"
COMPILER="intelllvm"
ATM_RES='C185'
FIX_DIR="/scratch4/BMC/ufs-artic/Kristin.Barton/files/ufs_arctic_development/fix_files"
RUN_DIR="/scratch4/BMC/ufs-artic/Kristin.Barton/stmp/test_runs"

TOP_DIR=$(pwd)
UFS_DIR=${TOP_DIR}/ufs-weather-model
cd ${UFS_DIR}/build
make clean
cd ${UFS_DIR}

module purge
module use modulefiles
module load ufs_${SYSTEM}.${COMPILER}.lua
CMAKE_FLAGS="-DAPP=S2S -DREGIONAL_MOM6=ON -DMOVING_NEST=OFF -DCCPP_SUITES=FV3_GFS_v17_coupled_p8_ugwpv1" ./build.sh

PREP_DIR=${TOP_DIR}/prep
cd ${PREP_DIR}
./run_prep.sh --clean --all
cd ${TOP_DIR}

base=${RUN_DIR}/${CASE_NAME}
count=1
MODEL_DIR=${base}
while [ -e "$MODEL_DIR" ]; do
    MODEL_DIR="${base}_${count}"
    ((count++))
done

mkdir ${MODEL_DIR}
mkdir ${MODEL_DIR}/INPUT
mkdir ${MODEL_DIR}/OUTPUT
mkdir ${MODEL_DIR}/RESTART
mkdir ${MODEL_DIR}/history
mkdir ${MODEL_DIR}/modulefiles

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

echo "Model run directory built in ${MODEL_DIR}"
