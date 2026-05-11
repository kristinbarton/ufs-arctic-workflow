#!/bin/bash
#SBATCH --job-name=ufs_compile
#SBATCH --qos=batch
#SBATCH --time=30:00
#SBATCH --nodes=2
#SBATCH --ntasks=2
#SBATCH --output=slurm_compile_%j.log

# ============================================================= #
# USAGE:
# sbatch --account=<your_account> compile_ufs.sh [OPTIONS]
#
# OPTIONS:
#  -s|--system SYS      Target system (ursa, hera). Default: ursa
#  -c|--compiler COMP   Target compiler (gnu, intel, intelllvm). Default: intelllvm
#  --ufs-dir DIR        Optional UFS Directory to compile instead of submodule
# ============================================================= #

set -eo pipefail

log_info() { echo -e "(info) $1"; }
log_warn() { echo -e "(Warn) $1"; }
log_error() { echo -e "[ERROR] $1"; }
error_exit() { log_error "$1"; exit 1; }

system="ursa"
compiler="intelllvm"
ufs_dir=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --system) system="$2"; shift 2 ;;
        --compiler) compiler="$2"; shift 2 ;;
        --ufs-dir) ufs_dir="$2"; shift 2 ;;
        -h|--help)
            grep "^#" "$0" | grep -v "^#SBATCH" | grep -v "^#!" # Prints USAGE block above
            exit 0
            ;;
        *) echo "Error: Unknown option '$1'. Use -h for help." >&2; exit 1 ;;
    esac
done

if [[ -n "$SLURM_SUBMIT_DIR" ]]; then 
    export TOP_DIR="$SLURM_SUBMIT_DIR"
else
    export TOP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
fi

export ufs_dir="${ufs_dir:-${TOP_DIR}/ufs-weather-model}"

log_info "Starting UFS Compilation process for System: $system | Compiler: $compiler"
log_info "Compiling in UFS directory: $ufs_dir"

[ -d "$ufs_dir" ] || error_exit "UFS Model directory not found: $ufs_dir Did you run git submodule update --init --recursive?"

# Compile
(
    cd "${ufs_dir}"
    module use modulefiles || error_exit "Failed to find modulefiles."
    module load "ufs_${system}.${compiler}.lua" || error_exit "Failed to load UFS module."
    
    if [ -d "build" ]; then
        log_warn "Existing build directory found. Cleaning..."
        (cd build && make clean)
    fi

    log_info "Running CMake and build scripts..."
    export CMAKE_FLAGS="-DDEBUG=OFF -DAPP=S2S -DREGIONAL_MOM6=ON -DMOVING_NEST=OFF -DCCPP_SUITES=FV3_GFS_v17_coupled_p8_ugwpv1"
    ./build.sh

    # Generate Provenance Metadata
    log_info "Generating build metadata..."
    meta_file="${ufs_dir}/build/build_metadata.txt"
    echo "========================================" > "$meta_file"
    echo "UFS Build" >> "$meta_file"
    echo "Build Date: $(date)" >> "$meta_file"
    echo "System: ${system}" >> "$meta_file"
    echo "Compiler: ${compiler}" >> "$meta_file"
    echo "CMake Flags: ${CMAKE_FLAGS}" >> "$meta_file"
    
    if [ -d "${ufs_dir}/.git" ]; then
        echo "Git Branch: $(git -C "${ufs_dir}" rev-parse --abbrev-ref HEAD)" >> "$meta_file"
        echo "Git Hash: $(git -C "${ufs_dir}" rev-parse HEAD)" >> "$meta_file"
    fi
    echo "========================================" >> "$meta_file"
)

log_info "Compilation complete. Executable is ready at: ${ufs_dir}/build/ufs_model"

