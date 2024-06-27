FROM debian:testing-slim
MAINTAINER Andreas Kloeckner <inform@tiker.net>

RUN echo 'APT::Default-Release "testing";' >> /etc/apt/apt.conf

RUN apt-get update
RUN apt-get -y upgrade

# gcc-10 for https://github.com/inducer/loopy/issues/686

# -o APT::Install-Recommends=0
RUN apt-get -y -o APT::Install-Suggests=0 install \
  python-is-python3 python3-dev python3-venv python3-pip \
  libblas-dev liblapack-dev libopenblas-dev \
  build-essential \
  gcc-10 \
  git \
  jq \
  curl \
  sudo \
  libtool automake autoconf gettext \
  gfortran \
  libhwloc-dev \
  locales-all \
  rsync \
  libgl1

RUN useradd -G sudo -m runner
RUN apt-get clean

RUN echo "runner ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/allow-runner-sudo
RUN echo 'APT::Get::Assume-Yes "1";' > /etc/apt/apt.conf.d/75assume-yes

USER runner
