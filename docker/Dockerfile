FROM --platform=amd64 ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y \
    subversion \
    ragel \
    curl \
    texinfo \
    g++ \
    bison \
    flex \
    cvs \
    yasm \
    automake \
    libtool \
    autoconf \
    gcc \
    cmake \
    git \
    make \
    pkg-config \
    zlib1g-dev \
    unzip \
    pax \
    nasm \
    gperf \
    autogen \
    bzip2 \
    autoconf-archive \
    p7zip-full \
    clang \
    autopoint \
    bc \
    ninja-build \
    python3-venv \
    python-is-python3 \
    python3-setuptools \
    wget \
    ed

# copy the entire git dir into the new docker container
COPY . ./ffmpeg-windows-build-helpers

WORKDIR /ffmpeg-windows-build-helpers
ENTRYPOINT [ "bash", "./docker/docker-entry.sh" ]
