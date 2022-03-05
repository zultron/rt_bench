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
    # Not in install instructions, but fix error:
    # ModuleNotFoundError: No module named 'distutils.sysconfig'
    python3-distutils
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
OTHER_UTILS=(  # Executables used in run_tests.sh
    intel-gpu-tools  # for intel_gpu_top
    sysstat  # for mpstat
    gnuplot  # for gnuplot
    mesa-utils  # for glxinfo
    kmod  # for lsmod
    procps  # for free, pkill
    psmisc # for killall
)

set_vars() {
    test -z "$THIS_DIR" || return 0  # Don't run twice
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
    local PKG
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
        echo "Cloning git repo $GIT_URL"
        echo "  into $GIT_DIR"
        mkdir -p $GIT_DIR
        ${DO} git clone --depth 1 "$GIT_URL" $GIT_DIR
    else
        echo "Git repo $GIT_URL"
        echo "  already cloned into $GIT_DIR"
    fi
    cd $GIT_DIR
}

build_rt_tests() {
    INSTALL=${1:-false}
    set_vars
    install_build_deps "${BUILD_DEPS_RT_TESTS[@]}"
    git_clone_and_cd git://git.kernel.org/pub/scm/utils/rt-tests/rt-tests.git
    echo "Building rt-tests"
    ${DO} make
    if $INSTALL; then
        echo "Installing rt-tests"
        ${SUDO} make install prefix=/usr
    fi
}

build_glmark2() {
    INSTALL=${1:-false}
    ! $INSTALL || PREFIX=--prefix=/usr
    set_vars
    install_build_deps "${BUILD_DEPS_GLMARK2[@]}"
    git_clone_and_cd https://github.com/glmark2/glmark2.git
    echo "Building glmark2"
    ${DO} meson setup build $PREFIX \
        -Dflavors=drm-gl,drm-glesv2,wayland-gl,wayland-glesv2,x11-gl,x11-glesv2
    ${DO} ninja -C build
    if $INSTALL; then
        echo "Installing glmark2"
        ${SUDO} ninja -C build install
    fi
}

install_other_tools() {
    echo "Installing other tools"
    install_conditionally "${OTHER_UTILS[@]}"
}

if $CALLED_AS_SCRIPT; then
    test "$1" = install && INSTALL=true || INSTALL=false
    build_rt_tests $INSTALL
    build_glmark2 $INSTALL
    install_other_tools
    echo "Completed successfully"
fi
