FROM inducer/debian-amd64-minbase
MAINTAINER Andreas Kloeckner <inform@tiker.net>

RUN echo 'APT::Default-Release "testing";' >> /etc/apt/apt.conf

RUN apt-get update
RUN apt-get -y upgrade

# -o APT::Install-Recommends=0
RUN apt-get -y -o APT::Install-Suggests=0 install \
  python3-dev \
  build-essential \
  git \
  jq \
  curl \
  sudo

RUN useradd -G sudo -m runner
RUN apt-get clean
USER runner