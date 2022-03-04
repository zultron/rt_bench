#!/bin/bash -e

# Called as script, or sourced?
if test $0 = $BASH_SOURCE; then
    CALLED_AS_SCRIPT=true
    # Abort on any error
    set -e
else
    # This script can be sourced & individual functions used
    CALLED_AS_SCRIPT=false
fi

BUILD_DEPS=(
    build-essential
    git
)
BUILD_DEPS_RT_TESTS=(
    libnuma-dev
)
BUILD_DEPS_GLMARK2=(
    libdrm-dev
    libgbm-dev
    libgl1-mesa-dev
    libgles2-mesa-dev
    libjpeg-dev
    libpng-dev
    libudev-dev
    libwayland-dev
    libxcb1-dev
    meson
    pkg-config
    python3
    wayland-protocols
)

set_vars() {
    test "$DEBUG" = true || DEBUG=false
    $DEBUG && DO=echo || DO=
    test $(id -u) = 0 && SUDO="$DO" || SUDO="$DO sudo -H"
    APT_GET="${SUDO} apt-get"
    export DEBIAN_FRONTEND=noninteractive
    THIS_DIR="$(readlink -f $(dirname $BASH_SOURCE))"
    BUILD_DIR=${THIS_DIR}/build
}

test_installed() {
    local PKG=$1
    dpkg-query -W $PKG >&/dev/null || return 1
    local STAT=$(dpkg-query -W --showformat '${db:Status-Status}\n' $PKG 2>/dev/null)
    test $STAT = installed && return 0 || return 1
}

install_conditionally() {
    local $PKG
    for PKG in "${@}"; do
        if test_installed $PKG; then
            echo "Install $PKG:  already installed" 1>&2
        else
            echo "Installling $PKG" 1>&2
            ${APT_GET} install -y $PKG
        fi
    done
}

install_build_deps() {
    install_conditionally "${BUILD_DEPS[@]}" "${@}"
}

git_clone_and_cd() {
    GIT_URL="$1"
    GIT_DIR="${BUILD_DIR}/$(basename $1 .git)"
    if test ! -e $GIT_DIR/.git; then
        mkdir -p $GIT_DIR
        ${DO} git clone --depth 1 "$GIT_URL" $GIT_DIR
    fi
    cd $GIT_DIR
}

build_rt_tests() {
    set_vars
    install_build_deps "${BUILD_DEPS_RT_TESTS[@]}"
    git_clone_and_cd git://git.kernel.org/pub/scm/utils/rt-tests/rt-tests.git
    make
}

build_glmark2() {
    set_vars
    install_build_deps "${BUILD_DEPS_GLMARK2[@]}"
    git_clone_and_cd https://github.com/glmark2/glmark2.git
    meson setup build \
        -Dflavors=drm-gl,drm-glesv2,wayland-gl,wayland-glesv2,x11-gl,x11-glesv2
        # [-Ddata-path=DATA_PATH --prefix=PREFIX]
    ninja -C build
}


if $CALLED_AS_SCRIPT; then
    # while getopts :dt:i:N-bT:m:P:pBHlvn:L:E:GIchD ARG; do
    # build_rt_tests
    build_glmark2
fi
