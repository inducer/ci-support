#! /bin/bash

curl -L -O -k https://gitlab.tiker.net/inducer/ci-support/raw/main/ci-support.sh
source ci-support.sh

build_py_project
run_examples
