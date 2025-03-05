#! /bin/bash
# ^^ (not a script: only here for shellcheck's benefit)

set -e
set -o pipefail

ci_support="https://gitlab.tiker.net/inducer/ci-support/raw/main"

if [ "$(uname)" = "Darwin" ]; then
  PLATFORM=MacOSX
elif [ "$(uname)" = "Linux" ]; then
  PLATFORM=Linux
else
  PLATFORM=Windows
fi


if grep -sq 'docker\|lxc' /proc/1/cgroup; then
  CI_SUPPORT_IS_DOCKER=1
else
  CI_SUPPORT_IS_DOCKER=0
fi
if [[ $CI_SUPPORT_IS_DOCKER = 1 ]] || [[ $GITHUB_ACTIONS == "true" ]]; then
  CI_SUPPORT_IS_CONTAINER=1
else
  CI_SUPPORT_IS_CONTAINER=0
fi

if [[ $CI_SUPPORT_IS_CONTAINER = 0 ]] && [[ $CI == "true" ]]; then
  # clean up the mess that someone may have made
  rm -f "$HOME/.aksetup-defaults.py"
fi

if [ "$PY_EXE" == "" ]; then
  if [ "$py_version" == "" ]; then
    if [ "$PLATFORM" = "Windows" ]; then
      PY_EXE=python
    else
      PY_EXE=python3
    fi
  else
    PY_EXE=python${py_version}
  fi
fi

if test "$CI_SERVER_NAME" = "GitLab" && test -d ~/.local/lib; then
  echo "ERROR: $HOME/.local/lib exists. It really shouldn't. Here's what it contains:"
  find ~/.local/lib
  exit 1
fi
#

if [[ "$GITLAB_CI" = "true" ]] &&  [[ "$CI_DISPOSABLE_ENVIRONMENT" = "true" ]]; then
  # Repo ownership is adventurous in Docker-based gitlab runner, we don't care.
  git config --global --add 'safe.directory' '*'
fi


begin_output_group()
{
  if [[ $GITHUB_ACTIONS == "true" ]]; then
    echo "::group::$1"
  else
    echo "--------------------------------------------------------------"
    echo "BEGIN $1"
    echo "--------------------------------------------------------------"
  fi
}


end_output_group()
{
  if [[ $GITHUB_ACTIONS == "true" ]]; then
    echo "::endgroup::$1"
  else
    echo "--------------------------------------------------------------"
    echo "END $1"
    echo "--------------------------------------------------------------"
  fi
}


with_output_group()
{
  local groupname="$1"
  shift
  begin_output_group "$groupname"
  trap "end_output_group $groupname" RETURN
  "$@"
}


rewrite_pyopencl_test()
{
  if (cd ..; $PY_EXE -c 'import pyopencl as cl; import pyopencl.characterize as c; v = [c.get_pocl_version(p) for p in cl.get_platforms()]; v, = [i for i in v if i];  import sys; sys.exit(not v >= (4,0))'); then
    export PYOPENCL_TEST
    PYOPENCL_TEST="$(echo "${PYOPENCL_TEST}" | sed s/pthread/cpu/ )"
  fi
}


set_up_jemalloc()
{
  CONDA_JEMALLOC="$CONDA_PREFIX/lib/libjemalloc.so.2"
  if test "$CONDA_PREFIX" != "" && test -f "$CONDA_JEMALLOC"; then
    # echo "*** running with $CONDA_JEMALLOC in LD_PRELOAD"
    # CI_SUPPORT_LD_PRELOAD="$CONDA_JEMALLOC"
    echo "*** $CONDA_JEMALLOC installed, skipping because of crashes observed in January 2025"
  fi
  CI_SUPPORT_LD_PRELOAD="$LD_PRELOAD"
}


# {{{ utilities

function tomlsh {
  python3 - "$@" <<EOF
#! /usr/bin/env python3

import argparse
import sys

try:
    import tomllib
except ImportError:
    import toml as tomllib

def resolve_dotted_name(data, dotted_name):
    components = dotted_name.split(".")
    for comp in components:
        data = data.get(comp)
        if data is None:
            return data

    return data


def has_key(data, args):
    return 0 if resolve_dotted_name(data, args.dotted_name) is not None else 1


def get(data, args):
    data = resolve_dotted_name(data, args.dotted_name)
    if data:
        print(data)
    return 0


def get_list(data, args):
    for item in resolve_dotted_name(data, args.dotted_name):
        print(item)
    return 0


def main():
    parser = argparse.ArgumentParser(description="TOML wrangling for shell scripts")
    parser.add_argument("filename", default="FILE.TOML")
    subp = parser.add_subparsers()

    parser_has_key = subp.add_parser("has-key")
    parser_has_key.add_argument("dotted_name", default="DOTTED.NAME")

    parser_has_key.set_defaults(func=has_key)

    parser_get = subp.add_parser("get")
    parser_get.add_argument("dotted_name", default="DOTTED.NAME")
    parser_get.set_defaults(func=get)

    parser_get_list = subp.add_parser("get-list")
    parser_get_list .add_argument("dotted_name", default="DOTTED.NAME")
    parser_get_list .set_defaults(func=get_list)

    args = parser.parse_args()

    if not hasattr(args, "func"):
        parser.print_usage()
        sys.exit(1)

    with open(args.filename, "rb") as toml:
        data = tomllib.load(toml)

    sys.exit(args.func(data, args))


if __name__ == "__main__":
    main()
EOF
}

function with_echo()
{
  echo "+++" "$@"
  "$@"
}

function get_proj_name()
{
  if [ -n "$CI_PROJECT_NAME" ]; then
    echo "$CI_PROJECT_NAME"
  else
    basename "$GITHUB_REPOSITORY"
  fi
}

print_status_message()
{
  echo "-----------------------------------------------"
  echo "Current directory: $(pwd)"
  echo "Python executable: ${PY_EXE}"
  echo "PYOPENCL_TEST: ${PYOPENCL_TEST}"
  echo "PYTEST_ADDOPTS: ${PYTEST_ADDOPTS}"
  echo "PROJECT_INSTALL_FLAGS: ${PROJECT_INSTALL_FLAGS}"
  echo "git revision: $(git rev-parse --short HEAD)"
  echo "git status:"
  git status -s
  test -f /proc/cpuinfo && ((grep 'model name' /proc/cpuinfo | head -n 1) || true)
  echo "-----------------------------------------------"
}


cipip
{
  with_output_group "pip $*" "$PY_EXE" -m pip "$@"
}


create_and_set_up_virtualenv()
{
  with_output_group "virtualenv" create_and_set_up_virtualenv_inner
}


create_and_set_up_virtualenv_inner()
{
  ${PY_EXE} -m venv .env
  . .env/bin/activate

  # https://github.com/pypa/pip/issues/5345#issuecomment-386443351
  export XDG_CACHE_HOME=$HOME/.cache/$CI_RUNNER_ID

  RESOLVED_PY_EXE=$(which ${PY_EXE})
  case "$RESOLVED_PY_EXE" in
    $PWD/.env/*) ;;
    *)
      echo "Python executable $PY_EXE not in virtualenv"
      exit 1
      ;;
  esac


  cipip install --upgrade pip
  cipip install setuptools wheel toml
}


install_miniforge()
{
  CONDA_INSTALL_DIR="${PWD}/.conda-root"

  if [ "$PLATFORM" == "Windows" ]; then
    FORGE_INSTALLER_EXT="exe"
  else
    FORGE_INSTALLER_EXT="sh"
  fi
  # Miniforge3 comes with mamba and conda-libmamba-solver installed by default now
  FORGE_INSTALLER="Miniforge3-$PLATFORM-$(uname -m).$FORGE_INSTALLER_EXT"
  curl -L -O "https://github.com/conda-forge/miniforge/releases/latest/download/$FORGE_INSTALLER"

  rm -Rf "$CONDA_INSTALL_DIR"

  if [ "$PLATFORM" == "Windows" ]; then
    echo "start /wait \"\" ${FORGE_INSTALLER} /InstallationType=JustMe /RegisterPython=0 /S /D=$(cygpath -w "${CONDA_INSTALL_DIR}")" > install.bat
    cmd.exe //c install.bat
  else
    bash "$FORGE_INSTALLER" -b -p "$CONDA_INSTALL_DIR"
  fi
}


handle_extra_install()
{
  if test "$EXTRA_INSTALL" != ""; then
    for i in $EXTRA_INSTALL ; do
      cipip install "$i"
    done
  fi
}

pip_install_project()
{
  with_output_group "pip install project" pip_install_project_inner
}

pip_install_project_inner()
{
  begin_output_group "pip install"
  with_echo pip install hatchling

  handle_extra_install

  if test "$REQUIREMENTS_TXT" == ""; then
    REQUIREMENTS_TXT="requirements.txt"
  fi

  if test -f "$REQUIREMENTS_TXT"; then
    # Filter out any numpy requirements, install first. Otherwise some packages
    # might build against wrong version of numpy.
    # Context: https://github.com/numpy/numpy/issues/20709
    if grep -q "^numpy" "$REQUIREMENTS_TXT"; then
      echo "Installing numpy first to avoid numpy#20709."
      grep -e "^numpy" "$REQUIREMENTS_TXT" > ci-support-numpy-req.txt
      with_echo pip install -r ci-support-numpy-req.txt
    fi

    with_echo pip install -r "$REQUIREMENTS_TXT"
  fi

  if [[ "$CONDA_PREFIX" != "" ]]; then
    if test -f .conda-ci-build-configure.sh; then
      with_echo source .conda-ci-build-configure.sh
    fi
  fi

  if test -f .ci-build-configure.sh; then
    with_echo source .ci-build-configure.sh
  fi

  # Append --editable to PROJECT_INSTALL_FLAGS, if not there already and if not
  # disabled.
  if ! test -f setup.cfg || ! grep -q disable-editable-pip-install setup.cfg; then
    if ! test -f pyproject.toml || ! tomlsh pyproject.toml has-key tool.inducer-ci-support.disable-editable-pip-install; then
      if [[ ! $PROJECT_INSTALL_FLAGS =~ (^|[[:space:]]*)(--editable|-e)[[:space:]]*$ ]]; then
          PROJECT_INSTALL_FLAGS="$PROJECT_INSTALL_FLAGS --editable"
      fi
    fi
  fi

  cipip install -v $PROJECT_INSTALL_FLAGS .
}


# }}}


# {{{ cleanup

clean_up_repo_and_working_env()
{
  rm -Rf .env
  rm -Rf build
  find . -name '*.pyc' -delete

  rm -Rf env
  git clean -fdx \
    -e siteconf.py \
    -e boost-numeric-bindings \
    -e '.pylintrc.yml' \
    -e 'prepare-and-run-*.sh' \
    -e 'ci-support.sh' \
    -e 'run-*.py' \
    -e '.test-*.yml' \
    $GIT_CLEAN_EXCLUDE


  if test `find "siteconf.py" -mmin +1`; then
    echo "siteconf.py older than a minute, assumed stale, deleted"
    rm -f siteconf.py
  fi

  if [[ "$NO_SUBMODULES" = "" ]]; then
    git submodule update --init --recursive
  fi
}

# }}}


# {{{ virtualenv build

build_py_project_in_venv()
{
  print_status_message
  clean_up_repo_and_working_env
  create_and_set_up_virtualenv

  pip_install_project
}

# }}}


# {{{ miniconda build

install_conda_deps()
{
  with_output_group "conda install" install_conda_deps_inner
}

install_conda_deps_inner()
{
  print_status_message
  clean_up_repo_and_working_env
  install_miniforge

  if test "$CONDA_ENVIRONMENT" = ""; then
    if test -f ".test-conda-env-py3.yml"; then
      CONDA_ENVIRONMENT=.test-conda-env-py3.yml
    elif test -f ".test-conda-env.yml"; then
      CONDA_ENVIRONMENT=.test-conda-env.yml
    fi
  fi

  local CONDA_EXE_DIR
  if [ $PLATFORM = "Windows" ]; then
    CONDA_EXE_DIR=$CONDA_INSTALL_DIR/Scripts
  else
    CONDA_EXE_DIR=$CONDA_INSTALL_DIR/bin
  fi

  PATH="$CONDA_EXE_DIR:$PATH" with_echo conda config --set solver libmamba
  PATH="$CONDA_EXE_DIR:$PATH" with_echo conda update conda --yes --quiet
  PATH="$CONDA_EXE_DIR:$PATH" with_echo conda update --all --yes --quiet
  PATH="$CONDA_EXE_DIR:$PATH" with_echo conda env create --file "$CONDA_ENVIRONMENT" --name testing --quiet

  source "$CONDA_EXE_DIR/activate" testing

  # https://github.com/conda-forge/ocl-icd-feedstock/issues/11#issuecomment-456270634
  rm -f $CONDA_INSTALL_DIR/envs/testing/etc/OpenCL/vendors/system-*.icd
  # https://gitlab.tiker.net/inducer/pytential/issues/112
  rm -f $CONDA_INSTALL_DIR/envs/testing/etc/OpenCL/vendors/apple.icd

  # https://github.com/pypa/pip/issues/5345#issuecomment-386443351
  export XDG_CACHE_HOME=$HOME/.cache/$CI_RUNNER_ID

  # '|| true' to avoid failing if pip is already installed.
  # (need observed with boxtree 2023-03-03 -AK)
  with_echo conda install --quiet --yes pip || true

  # FIXME: workaround until we address
  # https://github.com/conda-forge/pocl-feedstock/pull/96
  if [ $PLATFORM = "MacOSX" ]; then
    if conda list | grep -q ld64; then
      with_echo conda install --yes ld64=609
    fi
  fi

  with_echo conda list

  # Placeholder until github.com/conda-forge/qt-feedstock/issues/208 is fixed
  if [ "$(uname)" = "Linux" ]; then
    with_echo rm -rf $CONDA_INSTALL_DIR/envs/testing/x86_64-conda-linux-gnu/sysroot
  fi

  local LIBRARY_PREFIX
  # If a job decides it wants to build PyOpenCL from source, e.g. this situation:
  # https://github.com/conda-forge/pyopencl-feedstock/pull/64#issuecomment-842831669
  # give it a fighting chance if running with Conda:
  if test "$CONDA_PREFIX" != ""; then
    if [ "$PLATFORM" = "Windows" ]; then
      LIBRARY_PREFIX="$CONDA_PREFIX/Library"
    else
      LIBRARY_PREFIX="$CONDA_PREFIX"
    fi
    if [[ $CI_SUPPORT_IS_CONTAINER == 1 ]]; then
      cat >> ~/.aksetup-defaults.py <<EOF
CL_INC_DIR = ["$LIBRARY_PREFIX/include"]
CL_LIB_DIR = ["$LIBRARY_PREFIX/lib"]

# This matches the default on Linux and forces the use of the conda-installed
# ICD loader on macOS.
CL_LIBNAME = ["OpenCL"]
EOF
    fi
  fi
}

build_py_project_in_conda_env()
{
  install_conda_deps
  pip_install_project
}

# }}}


# {{{ generic build

build_py_project()
{
  if test "$USE_CONDA_BUILD" == "1"; then
    build_py_project_in_conda_env
  else
    build_py_project_in_venv
  fi
}

# }}}


# {{{ test

test_py_project()
{
  rewrite_pyopencl_test

  if [[ $PYOPENCL_TEST = *nvi* ]] || [[ $PYOPENCL_TEST = *titan* ]]; then
    echo "Nvidia GPUs currently unavailable, not running tests"
    return
  fi

  cipip install pytest pytest-github-actions-annotate-failures

  # Needed for https://github.com/utgwkk/pytest-github-actions-annotate-failures
  export PYTEST_RUN_PATH=test

  # pytest-xdist fails on pypy with: ImportError: cannot import name '_psutil_linux'
  # AK, 2020-08-20
  if [[ "${PY_EXE}" == pypy* ]]; then
    CISUPPORT_PARALLEL_PYTEST=no
  else
    cipip install pytest-xdist
  fi

  AK_PROJ_NAME="$(get_proj_name)"

  # {{{ configuration for test run

  if [[ $CISUPPORT_PARALLEL_PYTEST == "" || $CISUPPORT_PARALLEL_PYTEST == "xdist" ]]; then
    # Default: parallel if Not (Gitlab and GPU CI)?
    PYTEST_PARALLEL_FLAGS=""

    # CI_RUNNER_DESCRIPTION is set by Gitlab
    if [[ $CI_RUNNER_DESCRIPTION != *-gpu ]]; then
      if [[ $CISUPPORT_PYTEST_NRUNNERS == "" ]]; then
        PYTEST_PARALLEL_FLAGS="-n 4"
      else
        PYTEST_PARALLEL_FLAGS="-n $CISUPPORT_PYTEST_NRUNNERS"
      fi
    fi

  elif [[ $CISUPPORT_PARALLEL_PYTEST == "no" ]]; then
      PYTEST_PARALLEL_FLAGS=""
  else
    echo "unrecognized scheme in CISUPPORT_PARALLEL_PYTEST"
  fi

  # It... somehow... (?) seems to cause crashes for pytential.
  # https://gitlab.tiker.net/inducer/pytential/-/issues/146
  if [[ $CISUPPORT_PYTEST_NO_DOCTEST_MODULES == "" ]]; then
    DOCTEST_MODULES_FLAG="--doctest-modules"
  else
    DOCTEST_MODULES_FLAG=""
  fi

  set_up_jemalloc

  # Core dumps? Sure, take them.
  ulimit -c unlimited || true

  if test "$PLATFORM" != "Windows"; then
    # 10 GiB should be enough for just about anyone :)
    ulimit -m "$(python -c 'print(1024*1024*10)')" || true
  fi

  # }}}

  TESTABLES=""
  if [ -d test ]; then
    cd test

    if ! [ -f .not-actually-ci-tests ]; then
      TESTABLES="$TESTABLES ."
    fi

    if [ -z "$NO_DOCTESTS" ]; then
      RST_FILES=(../doc/*.rst)

      for f in "${RST_FILES[@]}"; do
        if [ -e "$f" ]; then
          if ! grep -q no-doctest "$f"; then
            TESTABLES="$TESTABLES $f"
          fi
        fi
      done

      # macOS bash is too old for mapfile: Oh well, no doctests on mac.
      if [ "$(uname)" != "Darwin" ]; then
        mapfile -t DOCTEST_MODULES < <( git grep -l doctest -- ":(glob,top)$AK_PROJ_NAME/**/*.py" )
        TESTABLES="$TESTABLES ${DOCTEST_MODULES[*]}"
      fi
    fi
  elif [ -d $AK_PROJ_NAME/test ]; then
    TESTABLES="$AK_PROJ_NAME $TESTABLES"

    if [ -z "$NO_DOCTESTS" ]; then
      RST_FILES=(doc/*.rst)

      for f in "${RST_FILES[@]}"; do
        if [ -e "$f" ]; then
          if ! grep -q no-doctest "$f"; then
            TESTABLES="$TESTABLES $f"
          fi
        fi
      done
    fi
  fi

  ( LD_PRELOAD="$CI_SUPPORT_LD_PRELOAD" with_echo "${PY_EXE}" -m pytest \
      --durations=10 \
      --junitxml=pytest.xml \
      $DOCTEST_MODULES_FLAG \
      -rxsw -o xfail_strict=True \
      $PYTEST_FLAGS $PYTEST_PARALLEL_FLAGS $TESTABLES )
}

# }}}


# {{{ run examples

run_examples()
{
  rewrite_pyopencl_test

  if [[ $PYOPENCL_TEST = *nvi* ]] || [[ $PYOPENCL_TEST = *titan* ]]; then
    echo "Nvidia GPUs currently unavailable, not running tests"
    return
  fi

  if test "$1" == "--no-require-main"; then
    MAIN_FILTER=()
  else
    MAIN_FILTER=(-exec grep -q __main__ '{}' \;)
  fi

  if ! test -d examples; then
    echo "!!! No 'examples' directory found"
    exit 1
  else
    cd examples

    for i in $(find . -name '*.py' "${MAIN_FILTER[@]}" -print ); do
      echo "-----------------------------------------------------------------------"
      echo "RUNNING $i"
      echo "-----------------------------------------------------------------------"
      cwd=$(dirname "$i")
      example_script=$(basename "$i")

      set_up_jemalloc

      if [[ $example_script == *mpi* ]]; then
        # FIXME: This command line is OpenMPI-specific.)
        (cd "$cwd"; time \
          LD_PRELOAD="$CI_SUPPORT_LD_PRELOAD" \
          PYTHONWARNINGS=default \
          mpiexec -np ${CI_SUPPORT_MPI_RANK_COUNT:-3} --oversubscribe \
            -x LD_PRELOAD -x PYOPENCL_TEST -x PYTHONWARNINGS \
            ${PY_EXE} -m mpi4py "$example_script")
      else
        (cd "$cwd"; time \
          LD_PRELOAD="$CI_SUPPORT_LD_PRELOAD" \
          PYTHONWARNINGS=default \
          ${PY_EXE} "$example_script")
      fi
    done
  fi
}

# }}}


# {{{ docs

build_docs()
{
  if test "$CI_SUPPORT_SPHINX_VERSION_SPECIFIER" = ""; then
    # >=3.2.1 for https://github.com/sphinx-doc/sphinx/issues/8084
    # >=4.0.2 because sphinx 4 is nice :D
    CI_SUPPORT_SPHINX_VERSION_SPECIFIER=">=4.0.2"
  fi

  # Two separate installs to trick sphinx into not precisely enforcing dependencies.
  # At the time of this writing, furo says it only works with sphinx 3.x.
  # (but it seems 4.x is OK!) -AK, 2021-05-20
  cipip install furo sphinx-copybutton

  cipip install "sphinx$CI_SUPPORT_SPHINX_VERSION_SPECIFIER"

  if test "$1" = "--no-check"; then
    (cd doc; with_echo make html)
  else
    (cd doc; with_echo make html SPHINXOPTS="-W --keep-going -n")
  fi
}

maybe_upload_docs()
{
  if [[ "$(basename "$(pwd)")" != "doc" ]]; then
    cd doc
    maybe_upload_docs
    cd ..
    return
  fi

  if test -n "${DOC_UPLOAD_KEY}" && test "$CI_DEFAULT_BRANCH" && test "$CI_COMMIT_REF_NAME" = "$CI_DEFAULT_BRANCH"; then
    cat > doc_upload_ssh_config <<END
Host doc-upload
   User doc
   IdentityFile doc_upload_key
   IdentitiesOnly yes
   Hostname documen.tician.de
   Port 2222
   StrictHostKeyChecking false
END

    echo "${DOC_UPLOAD_KEY}" > doc_upload_key
    chmod 0600 doc_upload_key
    RSYNC_RSH="ssh -F doc_upload_ssh_config" ./upload-docs.sh || { rm doc_upload_key; exit 1; }
    rm doc_upload_key
  else
    echo "Not uploading docs. No DOC_UPLOAD_KEY or not on $CI_DEFAULT_BRANCH on Gitlab."
  fi
}

# }}}


# {{{ flake8

is_flake8_config_in_pyproject()
{
  grep -m 1 -Fxqs "[tool.flake8]" pyproject.toml
}

get_flake8_config_file()
{
  if is_flake8_config_in_pyproject; then
    echo "pyproject.toml"
  else
    echo "setup.cfg"
  fi
}

install_and_run_flake8()
{
  FLAKE8_PACKAGES=(flake8 pep8-naming flake8-comprehensions)

  if is_flake8_config_in_pyproject; then
    true
    FLAKE8_PACKAGES+=(flake8-pyproject)
  fi

  if grep -q quotes "$(get_flake8_config_file)"; then
    true
    FLAKE8_PACKAGES+=(flake8-quotes)
  else
    echo "-----------------------------------------------------------------"
    echo "Consider enabling quote checking for this package by configuring"
    echo "https://github.com/zheller/flake8-quotes"
    echo "in $(get_flake8_config_file). Follow this example:"
    echo "https://github.com/illinois-ceesd/mirgecom/blob/45457596cac2eeb4a0e38bf6845fe4b7c323f6f5/setup.cfg#L5-L7"
    echo "-----------------------------------------------------------------"
  fi
  if grep -q isort "$(get_flake8_config_file)"; then
    true
    FLAKE8_PACKAGES+=(flake8-isort)
  else
    echo "-----------------------------------------------------------------"
    echo "Consider enabling import order for this package by configuring"
    echo "https://github.com/gforcada/flake8-isort"
    echo "in $(get_flake8_config_file). Simply add a line"
    echo "# enable-isort"
    echo "-----------------------------------------------------------------"
  fi

  if grep -q enable-flake8-bugbear $(get_flake8_config_file); then
    FLAKE8_PACKAGES+=(flake8-bugbear)
  else
    echo "-----------------------------------------------------------------"
    echo "Consider enabling quote checking for this package by configuring"
    echo "https://github.com/PyCQA/flake8-bugbear"
    echo "in $(get_flake8_config_file). Simply add a line"
    echo "# enable-flake8-bugbear"
    echo "-----------------------------------------------------------------"
  fi

  cipip install "${FLAKE8_PACKAGES[@]}"
  ${PY_EXE} -m flake8 "$@"
}

# }}}


# {{{ pylint

run_pylint()
{
  curl -L -O "${ci_support}/run-pylint.py"

  if ! test -f .pylintrc.yml; then
    curl -o .pylintrc.yml "${ci_support}/.pylintrc-default.yml"
  fi

  cipip install pylint PyYAML pytest

  PYLINT_RUNNER_ARGS="--jobs=4 --yaml-rcfile=.pylintrc.yml"

  if test -f .pylintrc-local.yml; then
    PYLINT_RUNNER_ARGS="$PYLINT_RUNNER_ARGS --yaml-rcfile=.pylintrc-local.yml"
  fi

  $PY_EXE run-pylint.py $PYLINT_RUNNER_ARGS "$@"
}

# }}}


# {{{ benchmarks

function setup_asv
{
  cipip install asv

  if [[ ! -f ~/.asv-machine.json ]]; then
    asv machine --yes
  fi
}

function clone_asv_results_repo
{
  local PROJECT
  PROJECT="$(get_proj_name)"

  if [[ -n "$CI" ]]; then
    mkdir -p .asv
    if [[ "$CI_PROJECT_NAMESPACE" == "inducer" && -n "${BENCHMARK_DATA_DEPLOY_KEY}" ]]; then
      echo "$BENCHMARK_DATA_DEPLOY_KEY" > .deploy_key
      chmod 700 .deploy_key
      ssh-keyscan gitlab.tiker.net >> ~/.ssh/known_hosts
      chmod 644 ~/.ssh/known_hosts
      ssh-agent bash -c "ssh-add $PWD/.deploy_key; git clone git@gitlab.tiker.net:isuruf/benchmark-data"
    else
      git clone https://gitlab.tiker.net/isuruf/benchmark-data
    fi
    ln -s "$PWD/benchmark-data/$PROJECT" ".asv/results"

    if [[ "$(git branch --show-current)" != "main" ]]; then
      # Fetch the origin/main branch and setup main to track origin/main
      git fetch origin main || true
      git branch main origin/main -f
    fi
    if [[ ! -f $PWD/.asv/results/benchmarks.json ]]; then
      # this is a brand new project. Run benchmark discovery process
      asv run --bench just-discover
    fi
  fi
}

function upload_benchmark_results
{
  if [[ "$CI_PROJECT_NAMESPACE" == "inducer" ]]; then
    cd benchmark-data
    git add "$PROJECT"
    export GIT_AUTHOR_NAME="Automated Benchmark Bot"
    export GIT_AUTHOR_EMAIL="bot@gitlab.tiker.net"
    export GIT_COMMITTER_NAME=$GIT_AUTHOR_NAME
    export GIT_COMMITTER_EMAIL=$GIT_AUTHOR_EMAIL
    git commit -m "Update benchmark data for $main_commit" --allow-empty
    ssh-agent bash -c "ssh-add $PWD/../.deploy_key; git pull -r origin main"
    ssh-agent bash -c "ssh-add $PWD/../.deploy_key; git push"
    cd ..
  fi
}

function run_asv
{
  if [[ -z "$PYOPENCL_TEST" ]]; then
      echo "PYOPENCL_TEST env var not set"
      exit 1
  fi

  main_commit="$(git rev-parse main)"
  test_commit="$(git rev-parse HEAD)"

  # cf. https://github.com/pandas-dev/pandas/pull/25237
  # for reasoning on --launch-method=spawn
  asv run "$main_commit...$main_commit~" --skip-existing --verbose --show-stderr --launch-method=spawn
  asv run "$test_commit...$test_commit~" --skip-existing --verbose --show-stderr --launch-method=spawn

  output="$(asv compare "$main_commit" "$test_commit" --factor "${ASV_FACTOR:-1}" -s)"
  echo "$output"

  if [[ "$output" = *"worse"* ]]; then
    echo "Some of the benchmarks have gotten worse"
    exit 1
  fi
}

function build_asv_html
{
  setup_asv
  clone_asv_results_repo
  asv publish --html-dir doc/_build/html/benchmarks
}

function build_and_run_benchmarks
{
  setup_asv
  clone_asv_results_repo
  run_asv
  upload_benchmark_results
}

# }}}


# {{{ transfer_requirements_git_urls

function transfer_requirements_git_urls()
{
  curl -L -O "${ci_support}/transfer-requirements-git-urls"
  python3 ./transfer-requirements-git-urls "$@"
}

# }}}


# {{{ edit_requirements_txt_for_downstream_in_subdir

function edit_requirements_txt_for_downstream_in_subdir()
{
  # Assumed to be run in directory of downstream project checked out in
  # subdirectory of upstream.

  # Unshallow the upstream repo. Without that, a bunch of the commands that
  # pip (as of 21.3) uses cause copious error spew, along the lines of
  # "warning: rejected (SHA) because shallow roots are not allowed to be updated"
  # "warning: filtering not recognized by server, ignoring"
  (cd ..; if $(git rev-parse --is-shallow-repository); then git fetch --unshallow; fi)

  local PRJ_NAME
  local REQ_TXT_TO_EDIT
  local TMP_FOR_COMPARISON="zzztmp-ci-support-req.txt"

  PRJ_NAME="$(get_proj_name)"
  REQ_TXT_TO_EDIT="${1:-requirements.txt}"
  cp "$REQ_TXT_TO_EDIT" "$TMP_FOR_COMPARISON"
  sed -i "/egg=$PRJ_NAME/ c git+file://$(readlink -f ..)#egg=$PRJ_NAME" "$REQ_TXT_TO_EDIT"
  if cmp "$REQ_TXT_TO_EDIT" "$TMP_FOR_COMPARISON" > /dev/null ; then
    echo "sed did not change $REQ_TXT_TO_EDIT for downstream CI"
    exit 1
  fi
}

# }}}


# {{{ install_ispc

function install_ispc()
{
    if (curl -L "https://ci.appveyor.com/api/projects/ispc/ispc/artifacts/build%2Fispc-trunk-linux.tar.gz?job=Environment%3A%20APPVEYOR_BUILD_WORKER_IMAGE%3DUbuntu1804%2C%20LLVM_VERSION%3Dlatest" \
        | tar xfz - ) ; then
      # Appveyor downloads can fail if the daily download limit is exceeded.
      PATH="$(pwd)/ispc-trunk-linux/bin:$PATH"
    else
      curl -L https://github.com/ispc/ispc/releases/download/v1.17.0/ispc-v1.17.0-linux.tar.gz  | tar xfz -
      PATH="$(pwd)/ispc-v1.17.0-linux/bin:$PATH"
    fi

    export PATH
}

# }}}


# {{{ prepare_downstream_build

function prepare_downstream_build()
{
  # NOTE: parses https://github.com/user/repo.git@branch_name
  local proj_url="${1%%@*}"
  local proj_branch=${1#"${proj_url}@"}
  local proj_name=$(basename "$proj_url" .git)

  if [[ "$proj_name" =~ mirgecom* ]]; then
    echo "::warning::No point in testing mirgecom at the moment, see https://github.com/illinois-ceesd/mirgecom/pull/898. Test not performed."
    exit 0
  fi

  # This is here because PyOpenCL needs to record a config change so
  # CL headers are found. It git adds siteconf.py.
  if ! git diff --quiet HEAD; then
    git config --global user.email "inform@tiker.net"
    git config --global user.name "CI runner"
    git commit -a -m "Fake commit to record local changes"
  fi

  if [[ "$proj_branch" != "$proj_url" ]]; then
    git clone "$proj_url" --branch "$proj_branch"
  else
    git clone "$proj_url"
  fi

  cd "$proj_name"
  echo "*** $proj_name version: $(git rev-parse --short HEAD)"

  if test -f ../requirements.txt; then
    transfer_requirements_git_urls ../requirements.txt ./requirements.txt
  fi

  edit_requirements_txt_for_downstream_in_subdir

  # Avoid slow or complicated tests in downstream projects
  export PYTEST_ADDOPTS="-k 'not (slowtest or octave or mpi)'"

  if [[ "$proj_name" = "mirgecom" ]]; then
      # can't turn off MPI in mirgecom
      export CONDA_ENVIRONMENT=conda-env.yml

      if [[ "$GITHUB_ACTIONS" != "" ]]; then
        # Github runners don't have a lot of RAM and tend to run out.
        export CISUPPORT_PARALLEL_PYTEST=no
      fi

      echo "- mpi4py" >> "$CONDA_ENVIRONMENT"
  else
      sed -i "/mpi4py/ d" requirements.txt
  fi
}

# }}}


# {{{ test_downstream

function test_downstream()
{
  local prep_only=0

  if [[ "$1" == "--prep-only" ]]; then
    prep_only=1
    shift
  fi

  local downstream_url="$1"
  local proj_url=""
  local test_examples=0

  if [[ "$downstream_url" =~ .*_examples ]]; then
    downstream_url="${downstream_url%_examples}"
    test_examples=1
  fi

  if [[ "$downstream_url" =~ https://.* ]]; then
    proj_url="$downstream_url"
  else
    if [[ "$downstream_url" == "mirgecom" ]]; then
      proj_url="https://github.com/illinois-ceesd/$downstream_url.git"
    else
      proj_url="https://github.com/inducer/$downstream_url.git"
    fi
  fi

  prepare_downstream_build "$proj_url"
  install_conda_deps

  # Downstream CI for pytools must override pytools that's installed via conda
  # (because it comes in as a dependency of, e.g., pyopencl). Try harder to
  # get rid of it.
  pip uninstall -y "$(get_proj_name)"

  pip_install_project

  if [[ "$prep_only" == "0" ]]; then
    if [[ "$test_examples" == "0" ]]; then
      test_py_project
    else
      if [[ "$proj_url" =~ .*mirgecom.* ]]; then
        examples/run_examples.sh ./examples
      else
        run_examples
      fi
    fi
  fi
}

# }}}


# {{{ gitlab mirror

function mirror_github_to_gitlab()
{
  mkdir ~/.ssh && echo -e "Host gitlab.tiker.net\n\tStrictHostKeyChecking no\n" >> ~/.ssh/config
  eval $(ssh-agent) && echo "$GITLAB_AUTOPUSH_KEY" | ssh-add -
  git fetch --unshallow
  TGT_BRANCH="${GITHUB_REF#refs/heads/}"
  echo "pushing to $TGT_BRANCH..."
  TGT_REPO="git@gitlab.tiker.net:inducer/$(get_proj_name).git"
  git push "$TGT_REPO" "$TGT_BRANCH"
  git push "$TGT_REPO" --tags
}

# }}}


# vim: foldmethod=marker:sw=2
