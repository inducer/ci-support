#! /bin/bash

set -e

PY_EXE=python3.5

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
    $PY_EXE -m pip install $i
  done
fi

if test "$REQUIREMENTS_TXT" == ""; then
  REQUIREMENTS_TXT="requirements.txt"
fi

if test -f $REQUIREMENTS_TXT; then
  $PY_EXE -m pip install -r $REQUIREMENTS_TXT
fi

$PY_EXE -m pip install mypy

./run-mypy.sh