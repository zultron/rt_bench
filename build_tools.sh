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
BUILD_DEPS_IGT_GPU_TOOLS=(
    # https://gitlab.freedesktop.org/drm/igt-gpu-tools/-/blob/d6f93088/Dockerfile.build-debian
    libunwind-dev
    libgsl-dev
    libasound2-dev
    libxmlrpc-core-c3-dev
    libjson-c-dev
    libcurl4-openssl-dev
    python3-docutils  # python-docutils, in above link
    valgrind
    peg
    libdrm-intel1
    # meson complains run-time deps missing
    libpciaccess-dev
    libkmod-dev
    libprocps-dev
    cmake
    libdw-dev
    libpixman-1-dev
    libcairo2-dev
    # More meson deps
    flex
    bison
)
BUILD_DEPS_STRESS_NG=(
    libaio-dev
    libapparmor-dev
    libattr1-dev
    libbsd-dev
    libcap-dev
    libgcrypt20-dev
    libipsec-mb-dev
    libjudy-dev
    libkeyutils-dev
    libsctp-dev
    libatomic1
    zlib1g-dev
    libkmod-dev
    libxxhash-dev
)
OTHER_UTILS=(  # Executables used in run_tests.sh
    intel-gpu-tools  # for intel_gpu_top
    sysstat  # for mpstat
    gnuplot  # for gnuplot
    mesa-utils  # for glxinfo
    kmod  # for lsmod
    procps  # for free, pkill
    psmisc  # for killall
    cgroup-tools  # for cgcreate, cgset, etc.
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
    test $STAT = installed || return 1
    return 0
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

build_igt_gpu_tools() {
    INSTALL=${1:-false}
    ! $INSTALL || PREFIX=--prefix=/usr
    set_vars
    install_build_deps "${BUILD_DEPS_IGT_GPU_TOOLS[@]}"
    git_clone_and_cd https://gitlab.freedesktop.org/drm/igt-gpu-tools.git
    echo "Building igt-gpu-tools"
    ${DO} meson build $PREFIX
    ${DO} ninja -C build
    if $INSTALL; then
        echo "Installing igt-gpu-tools"
        ${SUDO} ninja -C build install
    fi
}

build_stress_ng() {
    INSTALL=${1:-false}
    ! $INSTALL || PREFIX=--prefix=/usr
    set_vars
    install_build_deps "${BUILD_DEPS_STRESS_NG[@]}"
    git_clone_and_cd https://github.com/ColinIanKing/stress-ng.git
    echo "Building stress-ng"
    ${DO} make
    if $INSTALL; then
        echo "Installing stress-ng"
        ${SUDO} make install
    fi
}

install_other_tools() {
    echo "Installing other tools"
    install_conditionally "${OTHER_UTILS[@]}"
    # Install hwloc-nox if hwloc isn't installed already
    test_installed hwloc || install_conditionally hwloc-nox
}

if $CALLED_AS_SCRIPT; then
    test "$1" = install && INSTALL=true || INSTALL=false
    build_rt_tests $INSTALL
    build_glmark2 $INSTALL
    build_igt_gpu_tools $INSTALL
    build_stress_ng $INSTALL
    install_other_tools
    echo "Completed successfully"
fi
