#!/usr/bin/env bash

# This script was created based on the following script:
# https://git.nci.org.au/bom/ngm/conda-container/-/blob/ec3134fac7f0fd1fefc0a07ccdb532707f2ae222/submit.sh

# Used as `submit_pbs_job.sh job_script` to run job_script as a PBS job to NCI Gadi.

set -euo pipefail
if [[ "${CONTAINERISED_ENVS_DEBUG:-0}" == "1" ]]; then
    set -x
fi

if [ $# -ne 1 ]; then
  echo "Error: Exactly one argument (job_script) is required." >&2
  exit 1
fi

job_script="$1"

pbs_job_name="${JOB_NAME_PREFIX}_${MODULE_NAME}_${MODULE_VERSION}"

echo "Submitting PBS job '$job_script' using the following resource directives:"
echo "Name: '$pbs_job_name'"
echo "Project: '$PBS_PROJECT'"
echo "Storage: '$PBS_STORAGE'"

# Create custom logfile
export PBS_JOB_LOG_FILE="$LOGS_DIR/${pbs_job_name}.log"
touch "$PBS_JOB_LOG_FILE"
# Set a temporary logfile to send the default PBS job logs
temp_pbs_log=$(mktemp)
# Delete the custom logfile and temporary log file when the script exits.
trap "rm -vf '$PBS_JOB_LOG_FILE' '$temp_pbs_log'" EXIT

log_filename=$(basename "$PBS_JOB_LOG_FILE")
# Using ::group:: to start GitHub Actions log grouping
echo "::group::'$log_filename' log file"
qsub \
  -N $pbs_job_name \
  -P $PBS_PROJECT \
  -l storage="${PBS_STORAGE}" \
  -m n \
  -V \
  -W block=true \
  -j oe \
  -o "$temp_pbs_log" \
  "$job_script" \
  &
QID=$!

# Log STDOUT and STDERR of the PBS job log file in real-time
# stop when the QID process ends
tail -F "$PBS_JOB_LOG_FILE" --pid=$QID

# Get PBS job exit code
wait $QID
qsub_exit_code=$?

# Using ::endgroup:: to end GitHub Actions log grouping
echo "::endgroup::"

exit $qsub_exit_code