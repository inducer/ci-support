#! /bin/bash

echo "-----------------------------------------------"
echo "Current directory: $(pwd)"
echo "Conda environment file: ${CONDA_ENVIRONMENT}"
echo "PYOPENCL_TEST: ${PYOPENCL_TEST}"
echo "-----------------------------------------------"

if [ "$(uname)" = "Darwin" ]; then
  PLATFORM=MacOSX
else
  PLATFORM=Linux
fi

# {{{ download and install

MINICONDA_VERSION=3
MINICONDA_INSTALL_DIR=.miniconda${MINICONDA_VERSION}

MINICONDA_INSTALL_SH=Miniconda${MINICONDA_VERSION}-latest-${PLATFORM}-x86_64.sh
curl -O "https://repo.continuum.io/miniconda/$MINICONDA_INSTALL_SH"

rm -Rf "$MINICONDA_INSTALL_DIR"

bash "$MINICONDA_INSTALL_SH" -b -p "$MINICONDA_INSTALL_DIR"

# }}}

# {{{ set up testing environment

PATH="$MINICONDA_INSTALL_DIR/bin:$PATH" conda env create --quiet --file "$CONDA_ENVIRONMENT" --name testing

source "$MINICONDA_INSTALL_DIR/bin/activate" testing

conda install --quiet --yes pytest

# }}}

PY_EXE=python

${PY_EXE} setup.py install

TESTABLES=""
if [ -d test ]; then
  cd test

  if ! [ -f .not-actually-ci-tests ]; then
    TESTABLES="$TESTABLES ."
  fi

  if [ -z "$NO_DOCTESTS" ]; then
    vRST_SHS=(../doc/*.rst)

    if [ -e "${RST_SHS[0]}" ]; then
      TESTABLES="$TESTABLES ${RST_FILES[*]}"
    fi
  fi

  if ! test -z "$TESTABLES"; then
    if test -f /tmp/enable-amd-compute; then
      . /tmp/enable-amd-compute
    fi

    echo "TESTABLES: $TESTABLES"
    ulimit -c unlimited

    # Need to set both _TEST and _CTX because doctests do not use _TEST.
    ${PY_EXE} -m pytest -rw --tb=native  -rxs $TESTABLES

    # Avoid https://github.com/pytest-dev/pytest/issues/754:
    # add --tb=native

    # Avoid https://github.com/pytest-dev/pytest/issues/785:
    # omit --junitxml=pytest.xml
  fi
fi