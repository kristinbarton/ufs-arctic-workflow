#!/bin/bash

# ================================= #
# User-Adjusted Parameters          #
# ================================= #

sacct="ufs-artic"       # Account for job submission
hours=3                 # Model forecast length (Max: 240 Hours)
res=(                   # Model resolution (C918 ~11km; C185 ~50km)
#    "C185"
    "C918"
)
dates=(                 # Format: YYYYMMDD
#    "20191028"          # Options: 20191028 | 20200227 | 20200702 | 20200709 | 20200827
    "20200227"
#    "20200702"
#    "20200709"
#    "20200827"
)
# Optional: Specify pre-compiled directory. Leave blank to run from current directory.
#ufs_dir="/scratch4/BMC/ufs-artic/Kristin.Barton/repos/kristinbarton/ufs-arctic-workflow/build/C5203a784/ufs-weather-model/"              
ufs_dir=""

base_run_dir="/scratch4/BMC/${sacct}/${USER}/stmp" # Output will go in ${BASE_RUN_DIR}/${JOB_NAME}

# ================================= #
# Other SLURM Options               #
# ================================= #

qos="batch"             # Specify QOS
time="00:90:00"         # C918 may take longer than 60m. C185 should be less than 30m
nodes=2                 # Specify nodes
ntasks=4                # Specify tasks

# ================================= #
# Execution Loop                    #
# ================================= #

echo "Starting batch submission..."
script="./workflow/submit_workflow.sh"

for d in "${dates[@]}"; do
for r in "${res[@]}"; do
    echo ">> Configuring run for date: $d | Hours: $hours | Resolution: $r | Acct: $sacct"

    # Edit this as well if desired. Output will go in ${BASE_RUN_DIR}/${JOB_NAME}
    job_name="${r}_${d}_${hours}HRS"
    echo ">> Job directory location: ${base_run_dir}/${job_name}"

    cmd=(
        "sbatch"
        "--account=$sacct"
        "--qos=$qos"
        "--time=$time"
        "--nodes=$nodes"
        "--ntasks=$nodes"
        "--job-name=Prep_${job_name}"
        "$script"
        "--date" "$d"
        "--hours" "$hours"
        "--res" "$r"
        "--run-dir" "$base_run_dir"
        "--job-name" "$job_name")

    if [[ -n "ufs_dir" ]]; then
        cmd+=("--ufs-dir" "$ufs_dir")
    fi

#    cmd+=("--step" "prep_ocn")

    # Uncomment this if you want to prep the model run WITHOUT submitting the final job
    #cmd+=("--norun")

    "${cmd[@]}"

    sleep 1
done
done
