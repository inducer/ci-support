#! /bin/bash

curl -L -O https://tiker.net/ci-support-v0
source ci-support-v0

build_py_project_in_conda_env
setup_asv
clone_asv_results_repo
run_asv
upload_benchmark_results
