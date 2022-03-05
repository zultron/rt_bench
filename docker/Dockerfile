# Dockerfile snippet for rt_bench

# Tweak apt & ccache configuration
RUN \
    # Silence some Apt warnings; don't install recommended pkgs
    echo 'APT::Install-Recommends "0";\nAPT::Install-Suggests "0";' > \
        /etc/apt/apt.conf.d/01norecommend \
    && echo 'APT::Get::Assume-Yes "true";' > \
        /etc/apt/apt.conf.d/02assumeyes \
    # Keep APT package cache
    && echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' \
        > /etc/apt/apt.conf.d/03keep-cache \
    && echo 'APT::Clean-Installed "false";' \
        > /etc/apt/apt.conf.d/04clean-installed-off \
    && rm -f /etc/apt/apt.conf.d/docker-clean

# Install basic build tools
RUN --mount=type=cache,target=/var/cache/apt \
    apt-get update \
    && apt-get install -y \
        ccache \
        build-essential \
        git \
        ca-certificates \
    # Add missing ccache symlinks
    && test -f /usr/lib/ccache/c++ || ln -s ../../bin/ccache /usr/lib/ccache/c++ \
    && test -f /usr/lib/ccache/cc || ln -s ../../bin/ccache /usr/lib/ccache/cc

# Build and install tools
WORKDIR /root/rt_bench
COPY build_tools.sh /root/rt_bench/
# - Install APT package deps & tools
RUN --mount=type=cache,target=/var/cache/apt \
    source ./build_tools.sh \
    && apt-get update \
    && apt-get install \
        "${OTHER_UTILS[@]}" \
        "${BUILD_DEPS_RT_TESTS[@]}" \
        "${BUILD_DEPS_GLMARK2[@]}"
# - rt-tests
RUN --mount=type=cache,target=/ccache/ \
    source ./build_tools.sh \
    && CCACHE_DIR=/ccache PATH=/usr/lib/ccache:/usr/sbin:/usr/bin:/sbin:/bin \
        build_rt_tests true
# - glmark2
RUN --mount=type=cache,target=/ccache/ \
    source ./build_tools.sh \
    && CCACHE_DIR=/ccache PATH=/usr/lib/ccache:/usr/sbin:/usr/bin:/sbin:/bin \
        build_glmark2 true

# Add string to shell prompt to help identify Docker container shells
RUN echo "rt_bench" > /etc/debian_chroot

COPY run_tests.sh /usr/bin/

ENV IN_DOCKER=1
