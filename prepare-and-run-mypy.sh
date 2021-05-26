#! /bin/bash

set -e

if [[ $1 == python* ]]; then
  PY_EXE="$1"
  shift
fi

if [ "$py_version" == "" ]; then
  py_version=3
fi

if [ "$PY_EXE" == "" ]; then
  PY_EXE=python${py_version}
fi


VERSIONS="$@"
if test "$VERSIONS" = ""; then
  VERSIONS="mypy typed-ast"
fi

echo "-----------------------------------------------"
echo "Current directory: $(pwd)"
echo "Python executable: ${PY_EXE}"
echo "-----------------------------------------------"

# {{{ clean up

rm -Rf .env
rm -Rf build
find . -name '*.pyc' -delete

rm -Rf env
git clean -fdx -e siteconf.py -e boost-numeric-bindings -e local_settings.py

if test `find "siteconf.py" -mmin +1`; then
  echo "siteconf.py older than a minute, assumed stale, deleted"
  rm -f siteconf.py
fi

# }}}

git submodule update --init --recursive

# {{{ virtualenv

${PY_EXE} -m venv .env
. .env/bin/activate

${PY_EXE} -m ensurepip

# }}}

if test "$EXTRA_INSTALL" != ""; then
  for i in $EXTRA_INSTALL ; do
    $PY_EXE -m pip install "$i"
  done
fi

if test "$REQUIREMENTS_TXT" == ""; then
  REQUIREMENTS_TXT="requirements.txt"
fi

# https://github.com/pypa/pip/issues/5345#issuecomment-386443351
export XDG_CACHE_HOME=$HOME/.cache/$CI_RUNNER_ID

if test -f $REQUIREMENTS_TXT; then
  $PY_EXE -m pip install -r $REQUIREMENTS_TXT
fi

$PY_EXE -m pip install $VERSIONS

curl -L -O -k https://gitlab.tiker.net/inducer/ci-support/raw/main/ci-support.sh
source ci-support.sh

build_py_project

./run-mypy.sh
