FROM debian:testing-slim
MAINTAINER Andreas Kloeckner <inform@tiker.net>

RUN echo 'APT::Default-Release "testing";' >> /etc/apt/apt.conf

RUN apt-get update
RUN apt-get -y upgrade

# -o APT::Install-Recommends=0
RUN apt-get -y -o APT::Install-Suggests=0 install \
  python3-dev python3-venv \
  libblas-dev liblapack-dev libopenblas-dev \
  build-essential \
  git \
  jq \
  curl \
  sudo \
  libtool automake autoconf gettext \
  gfortran \
  libhwloc-dev \
  locales-all \
  rsync

RUN useradd -G sudo -m runner
RUN apt-get clean

RUN echo "runner ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/allow-runner-sudo
RUN echo 'APT::Get::Assume-Yes "1";' > /etc/apt/apt.conf.d/75assume-yes

USER runner
