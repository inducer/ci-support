echo "-----------------------------------------------"
echo "Current directory: $(pwd)"
echo "Python executable: ${PY_EXE}"
echo "PYOPENCL_TEST: ${PYOPENCL_TEST}"
echo "-----------------------------------------------"

# {{{ clean up

rm -Rf .env
rm -Rf build
find . -name '*.pyc' -delete

rm -Rf env
git clean -fdx -e siteconf.py -e boost-numeric-bindings

if test `find "siteconf.py" -mmin +1`; then
  echo "siteconf.py older than a minute, assumed stale, deleted"
  rm -f siteconf.py
fi


# }}}

if [[ "$NO_SUBMODULES" = "" ]]; then
  git submodule update --init --recursive
fi

# {{{ virtualenv

VENV_VERSION="virtualenv-15.1.0"
rm -Rf "$VENV_VERSION"
curl -k https://pypi.python.org/packages/source/v/virtualenv/$VENV_VERSION.tar.gz | tar xfz -

VIRTUALENV="${PY_EXE} -m venv"
${VIRTUALENV} -h > /dev/null || VIRTUALENV="$VENV_VERSION/virtualenv.py --no-setuptools -p ${PY_EXE}"

if [ -d ".env" ]; then
  echo "**> virtualenv exists"
else
  echo "**> creating virtualenv"
  ${VIRTUALENV} .env
fi

. .env/bin/activate

# }}}

# {{{ setuptools

#curl -k https://bitbucket.org/pypa/setuptools/raw/bootstrap-py24/ez_setup.py | python -
#curl -k https://ssl.tiker.net/software/ez_setup.py | python -
#curl -k https://bootstrap.pypa.io/ez_setup.py | python -

# SETUPTOOLS_VERSION="setuptools-33.1.1"
# curl -k -O https://pypi.python.org/packages/dc/8c/7c9869454bdc53e72fb87ace63eac39336879eef6f2bf96e946edbf03e90/$SETUPTOOLS_VERSION.zip
# unzip $SETUPTOOLS_VERSION
# (cd $SETUPTOOLS_VERSION; $PY_EXE setup.py install)

# }}}

if [[ "${PY_EXE}" == python3.[56789] ]]; then
  $PY_EXE -m ensurepip
else
  #curl -k https://gitlab.tiker.net/inducer/pip/raw/7.0.3/contrib/get-pip.py | python -
  curl -k https://bootstrap.pypa.io/get-pip.py | python -
fi

# Not sure why the hell pip ends up there, but in Py3.3, it sometimes does.
export PATH=`pwd`/.env/local/bin:$PATH

PIP="${PY_EXE} $(which pip)"

$PIP install setuptools

if test "$EXTRA_INSTALL" != ""; then
  for i in $EXTRA_INSTALL ; do
    if [ "$i" = "numpy" ] && [[ "${PY_EXE}" == pypy* ]]; then
      $PIP install git+https://bitbucket.org/pypy/numpy.git
    elif [ "$i" = "numpy" ] && [[ "${PY_EXE}" == python2.6* ]]; then
      $PIP install 'numpy==1.10.4'
    else
      $PIP install $i
    fi
  done
fi

if test "$REQUIREMENTS_TXT" == ""; then
  REQUIREMENTS_TXT="requirements.txt"
fi

if test -f $REQUIREMENTS_TXT; then
  $PIP install -r $REQUIREMENTS_TXT
fi

$PIP install .