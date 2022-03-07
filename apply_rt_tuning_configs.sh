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

###########################
# Common variables
###########################

OS_VENDOR=$(. /etc/os-release && echo $ID)  # debian, ubuntu, linuxmint
OS_CODENAME=$(. /etc/os-release && echo $VERSION_CODENAME)  # bullseye, focal, ulyssa

test "$DEBUG" = true || DEBUG=false
$DEBUG && DO=echo || DO=
test $(id -u) = 0 && SUDO="$DO" || SUDO="$DO sudo -H"
APT_GET="${SUDO} env DEBIAN_FRONTEND=noninteractive apt-get"

###########################
# Misc. utility functions
###########################

# Determine RT CPUs and GPU info
check_cpu() {
    # Processor model
    CPU="$(awk '/^model name/ {split($0, F, /: /); print(F[2]); exit}' \
               /proc/cpuinfo)"

    case "$CPU" in
        "Intel(R) Celeron(R) CPU  N3160  @ 1.60GHz")
            RT_CPUS=${RT_CPUS:-2-3}  # Shared L2 cache
            NONRT_CPUS=${NONRT_CPUS:-0-1}
            ;;
        "Intel(R) Core(TM) i5-8259U CPU @ 2.30GHz")
            RT_CPUS=${RT_CPUS:-3,7}  # Shared threads
            NONRT_CPUS=${NONRT_CPUS:-0-2,4-6}
            ;;
        "Intel(R) Atom(TM) Processor E3950 @ 1.60GHz")
            RT_CPUS=${RT_CPUS:-2-3}  # Shared L2 cache
            NONRT_CPUS=${NONRT_CPUS:-0-1}
            ;;
        *)
            echo "CPU '$CPU' unknown; please add to $BASH_SOURCE.  Exiting." >&2
            exit 1
            ;;
    esac
}

confirm_changes() {
    # Ask confirmation for we're about to do
    {
        echo "This script will:"
        test -z "${INSTALL_DEPS[*]}" || echo "- Install packages:  ${INSTALL_DEPS[*]}"
        ! ${INSTALL_DOCKER:-false} || cat >&2 <<-EOF
			- Uninstall any Docker from Debian packages and install Docker CE
			  - Add your user to the 'docker' group
			EOF
        ! ${INSTALL_RT_KERNEL:-false} || echo "- Install the PREEMPT_RT kernel + header packages"
        ! ${CONFIG_ISOLCPUS:-false} || echo "- Add isolcpus=${RT_CPUS} to kernel cmdline"
        ! ${RM_CONFIG_ISOLCPUS:-false} || echo "- Remove isolcpus=${RT_CPUS} from kernel cmdline"
        ! ${CONFIG_NOHZ_FULL:-false} || echo "- Add nohz_full=${RT_CPUS} to kernel cmdline"
        ! ${RM_CONFIG_NOHZ_FULL:-false} || echo "- Remove nohz_full=${RT_CPUS} from kernel cmdline"
        ! ${CONFIG_IRQAFFINITY:-false} || echo "- Add irqaffinity=${NONRT_CPUS} to kernel cmdline"
        ! ${RM_CONFIG_IRQAFFINITY:-false} || echo "- Remove irqaffinity=${NONRT_CPUS} from kernel cmdline"
        ! ${INSTALL_CGROUPS:-false} || echo "- Mount legacy cgroups at boot & install cgroup-tools"
        ! ${REMOVE_CGROUPS:-false} || echo "- Do not mount legacy cgroups at boot"
        ! ${DISABLE_GPU:-false} || echo "- Disable i915 graphics kernel module"
        ! ${ENABLE_GPU:-false} || echo "- Reenable i915 graphics kernel module"
        ! ${DISABLE_X:-false} || echo "- Disable X windows"
        ! ${ENABLE_X:-false} || echo "- Reenable X windows"
        echo -n "WARNING:  Make these changes?  (y/N) "
    } >&2
    read REALLY
    if test ! "$REALLY" = y; then
        echo "Aborting script at user request" >&2
        exit 1
    fi
}

usage() {
    cat 1>&2 <<-EOF
		Usage:  $BASH_SOURCE [arg ...]
		  -d:  Install Docker CE
		  -k:  Install PREEMPT_RT kernel + header packages
		  -i:  Configure 'isolcpus=' kernel command line option
		  -I:  Remove 'isolcpus=' kernel command line option
		  -z:  Configure 'nohz_full=' kernel command line option
		  -Z:  Remove 'nohz_full=' kernel command line option
		  -q:  Configure 'irqaffinity=' kernel command line option
		  -Q:  Remove 'irqaffinity=' kernel command line option
		  -c:  Mount legacy cgroups at boot & install cgroup-tools
		  -C:  Do not mount legacy cgroups at boot
		  -g:  Disable i915 Intel graphics kernel module
		  -G:  Reenable i915 Intel graphics kernel module
		  -x:  Disable X windows
		  -X:  Reenable X windows
		  -h:  Print this help message
          $*
		EOF
    test -n "$*" && exit 0 || exit 1
}

# add_user_to_group group_name [user_name]
add_user_to_group() {
    local GROUP=$1
    local USER=${2:-$(id -un)}
    test $USER != 0 -a $USER != root || return
    ${SUDO} adduser $USER $GROUP
}

###########################
# Docker CE
###########################

# https://docs.docker.com/install/linux/docker-ce/ubuntu/
# https://docs.docker.com/install/linux/docker-ce/debian/

install_docker_ce() {
    # Remove other Docker packages and add repo
    DOCKER_CE_STATUS="$(dpkg-query -Wf='${db:Status-Status}' docker-ce
                            2>/dev/null || true)"
    if test "$DOCKER_CE_STATUS" != installed; then
        # Remove old packages
        ${APT_GET} remove -y \
            docker docker-engine docker.io || true
        # Add official Docker GPG key
        ${APT_GET} install -y curl gnupg
        curl -fsSL https://download.docker.com/linux/${OS_VENDOR}/gpg |
            ${SUDO} apt-key add -

        echo "deb [arch=amd64] https://download.docker.com/linux/${OS_VENDOR} \
            ${OS_CODENAME} stable" |
            ${SUDO} tee /etc/apt/sources.list.d/docker.list
        ${APT_GET} update
    fi

    # Install or update docker-ce package
    ${APT_GET} install -y docker-ce

    # docker user group
    add_user_to_group docker
}

###########################
# Install RT kernel
# Configure isolated CPUs
###########################

install_rt_kernel() {
    ${APT_GET} install -y linux-image-rt-amd64 linux-headers-rt-amd64
}

config_kernel_cmdline() {
    VAL="$1"
    REGEX="${2:-$1}"
    echo "Adding kernel cmdline arg '$VAL'" 1>&2
    GRUB_CMDLINE="$(source /etc/default/grub &&
                        echo $GRUB_CMDLINE_LINUX_DEFAULT)"
    GRUB_CMDLINE_TEST="$(echo $GRUB_CMDLINE | sed 's/$REGEX//')"
    if test "$GRUB_CMDLINE" != "$GRUB_CMDLINE_TEST"; then
        echo "Warning:  grub command line matches '$REGEX'; doing nothing" 1>&2
        return
    fi
    GRUB_CMDLINE+=" $VAL"
    ${SUDO} sed -i /etc/default/grub \
        -e "s/.*\(GRUB_CMDLINE_LINUX_DEFAULT\).*/\1=\"${GRUB_CMDLINE}\"/"
    UPDATE_GRUB=true
}

unconfig_kernel_cmdline() {
    ARG="$1"
    GLOB="${2:-$VAL}"
    echo "Removing kernel cmdline arg '$ARG'" 1>&2
    GRUB_CMDLINE_CUR="$(source /etc/default/grub &&
                           echo $GRUB_CMDLINE_LINUX_DEFAULT)"
    shopt -s extglob  # Enable extended glob matching
    GRUB_CMDLINE="${GRUB_CMDLINE_CUR/${GLOB}/}"

    if test "$GRUB_CMDLINE_CUR" = "$GRUB_CMDLINE"; then
        echo "Warning:  No change to kernel command line" 1>&2
    else
        # Configure kernel cmdline args
        ${SUDO} sed -i /etc/default/grub \
            -e "s/.*\(GRUB_CMDLINE_LINUX_DEFAULT\).*/\1=\"${GRUB_CMDLINE}\"/"
        UPDATE_GRUB=true
    fi
}

config_isolcpus() {
    config_kernel_cmdline isolcpus=$RT_CPUS isolcpus=
}

remove_isolcpus() {
    unconfig_kernel_cmdline isolcpus "isolcpus=+([-0-9, ])"
}

config_nohz_full() {
    config_kernel_cmdline nohz_full=$RT_CPUS nohz_full=
}

remove_nohz_full() {
    unconfig_kernel_cmdline nohz_full "nohz_full=+([-0-9, ])"
}

config_irqaffinity() {
    config_kernel_cmdline irqaffinity=$NONRT_CPUS irqaffinity=
}

remove_irqaffinity() {
    unconfig_kernel_cmdline irqaffinity "irqaffinity=+([-0-9, ])"
}

install_cgroups() {
    # Install tools
    ${SUDO} apt-get install -y cgroup-tools
    # Mount cgroups v1 hierarchy for libcgroup (libcgroup v2.0 supports cgroups
    # v2, not in Bullseye)
    config_kernel_cmdline systemd.unified_cgroup_hierarchy=false \
        systemd.unified_cgroup_hierarchy
    config_kernel_cmdline systemd.legacy_systemd_cgroup_controller=false \
        systemd.legacy_systemd_cgroup_controller
}

remove_cgroups() {
    unconfig_kernel_cmdline systemd.unified_cgroup_hierarchy \
        systemd.unified_cgroup_hierarchy=false
    unconfig_kernel_cmdline systemd.legacy_systemd_cgroup_controller \
        systemd.legacy_systemd_cgroup_controller=false
}


###########################
# Disable graphics
###########################

disable_i915_graphics() {
    # The i915 graphics driver and Intel HD Graphics are known killers of RT
    # during heavy 3D load; disable the driver completely
    ${SUDO} tee /etc/modprobe.d/blacklist-i915.conf <<-EOF
		# Disable i915 graphics, RT performance killer
		blacklist i915
		# Other drivers may drag the i915 in from deps; prevent that
		install i915 /usr/bin/false
	EOF
    ${SUDO} update-initramfs -u
}

reenable_i915_graphics() {
    ${SUDO} rm -f /etc/modprobe.d/blacklist-i915.conf
    ${SUDO} update-initramfs -u
}

disable_x() {
    ${SUDO} ln -s /usr/lib/systemd/system/multi-user.target \
        /etc/systemd/system/default.target
}

reenable_x() {
    ${SUDO} rm -f /etc/systemd/system/default.target
}


###########################
# Finish up
###########################

finalize() {
    # Run update-grub, if needed
    ! $UPDATE_GRUB || ${SUDO} update-grub

    set +x
    cat >&2 <<-EOF

		*** Install complete!
		*** You will probably have to reboot your machine
		***   in order for changes to take effect.
	EOF
    exit 0
}



###########################
# Execute command line args
###########################

if $CALLED_AS_SCRIPT; then
    while getopts :dkiIzZqQcCgGxXh ARG; do
        case $ARG in
            d) INSTALL_DOCKER=true ;;
            k) INSTALL_RT_KERNEL=true; APT_GET_UPDATE=true ;;
            i) CONFIG_ISOLCPUS=true; CHECK_CPU=true ;;
            I) RM_CONFIG_ISOLCPUS=true ;;
            z) CONFIG_NOHZ_FULL=true; CHECK_CPU=true ;;
            Z) RM_CONFIG_NOHZ_FULL=true ;;
            q) CONFIG_IRQAFFINITY=true; CHECK_CPU=true ;;
            Q) RM_CONFIG_IRQAFFINITY=true ;;
            c) INSTALL_CGROUPS=true; APT_GET_UPDATE=true ;;
            C) REMOVE_CGROUPS=true ;;
            g) DISABLE_GPU=true ;;
            G) ENABLE_GPU=true ;;
            x) DISABLE_X=true ;;
            X) ENABLE_X=true ;;
            h) usage ;;
            *) usage "Unknown option '-$ARG'" ;;
        esac
    done
    shift $(($OPTIND - 1))

    ! ${CHECK_CPU:-false} || check_cpu
    confirm_changes
    UPDATE_GRUB=false
    ! ${APT_GET_UPDATE:-false} || ${APT_GET} update
    ! ${INSTALL_DOCKER:-false} || install_docker_ce
    ! ${INSTALL_RT_KERNEL:-false} || install_rt_kernel
    ! ${CONFIG_ISOLCPUS:-false} || config_isolcpus
    ! ${RM_CONFIG_ISOLCPUS:-false} || remove_isolcpus
    ! ${CONFIG_NOHZ_FULL:-false} || config_nohz_full
    ! ${RM_CONFIG_NOHZ_FULL:-false} || remove_nohz_full
    ! ${CONFIG_IRQAFFINITY:-false} || config_irqaffinity
    ! ${RM_CONFIG_IRQAFFINITY:-false} || remove_irqaffinity
    ! ${INSTALL_CGROUPS:-false} || install_cgroups
    ! ${RM_INSTALL_CGROUPS:-false} || remove_cgroups
    ! ${DISABLE_GPU:-false} || disable_i915_graphics
    ! ${ENABLE_GPU:-false} || reenable_i915_graphics
    ! ${DISABLE_X:-false} || disable_x
    ! ${ENABLE_X:-false} || reenable_x
    finalize
fi
