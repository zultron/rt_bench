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
            RT_CPUS=${RT_CPUS:-2,3}  # Shared L2 cache
            GRUB_CMDLINE="isolcpus=${RT_CPUS}"
            ;;
        "Intel(R) Core(TM) i5-8259U CPU @ 2.30GHz")
            RT_CPUS=${RT_CPUS:-3,7}  # Shared threads
            GRUB_CMDLINE="isolcpus=${RT_CPUS}"
            ;;
        "Intel(R) Atom(TM) Processor E3950 @ 1.60GHz")
            RT_CPUS=${RT_CPUS:-2,3}  # Shared L2 cache
            GRUB_CMDLINE="isolcpus=${RT_CPUS}"
            ;;
        *)
            echo "CPU '$CPU' unknown; please add to $0.  Exiting." >&2
            exit 1
            ;;
    esac

    # Mount cgroups v1 hierarchy for libcgroup (libcgroup v2.0 supports cgroups
    # v2, not in Bullseye)
    GRUB_CMDLINE+=" systemd.unified_cgroup_hierarchy=false"
    GRUB_CMDLINE+=" systemd.legacy_systemd_cgroup_controller=false"

    # Motherboard information
    DMI_DATA="$(cat /sys/devices/virtual/dmi/id/modalias)"

    # Non-free firmware
    NEED_NON_FREE_FW=false

    case "$DMI_DATA" in
        *:pnMXE1500:*)
            # ADLink Tech MXE-1500 Series
            ETHERCAT_NIC=${ETHERCAT_NIC:-eno1}  # Left-hand port on rear
            ;;
        *:pnNUC8i5BEK:*)
            # Intel NUC 815BEK
            ETHERCAT_NIC=${ETHERCAT_NIC:-eno1}
            ;;
        *:pnMXE210:*)
            # ADLink Tech MXE-210 Series
            ETHERCAT_NIC=${ETHERCAT_NIC:-eno2}  # Right-hand port on front
            NEED_NON_FREE_FW=true  # i915 drivers
            ;;
        *)
            echo "DMI data '$DMI_DATA' unknown; please add to $0.  Exiting." >&2
            exit 1
            ;;
    esac
}

confirm_changes() {
    # Ask confirmation for we're about to do
    cat >&2 <<-EOF
		This script will:
		- Install some utility packages
		- Uninstall any Docker from Debian packages and install Docker CE
		  - Add your user to the 'docker' group
		- Configure kernel cmdline args '${GRUB_CMDLINE}'
		- Install the RT kernel
		- Install and configure the IgH EtherCAT Master
		  - Add your user to the 'ethercat' group
		- Disable Intel i915 graphics driver and XWindows

	EOF
    echo -n "WARNING:  Make these changes?  (y/N) " >&2
    read REALLY
    if test ! "$REALLY" = y; then
        echo "Aborting script at user request" >&2
        exit 1
    fi
}

# add_user_to_group group_name [user_name]
add_user_to_group() {
    local GROUP=$1
    local USER=${2:-$(id -un)}
    test $USER != 0 -a $USER != root || return
    ${SUDO} adduser $USER $GROUP
}

###########################
# Install script deps
###########################

install_script_deps() {
    ${APT_GET} install -y curl gnupg git
}

###########################
# Install RT kernel
# Configure isolated CPUs
###########################

install_rt_kernel() {
    ${APT_GET} install -y linux-image-rt-amd64 linux-headers-rt-amd64
    ${APT_GET} install -y cgroup-tools

    GRUB_CMDLINE_CUR="$(source /etc/default/grub &&
                           echo $GRUB_CMDLINE_LINUX_DEFAULT)"
    if test -n "${GRUB_CMDLINE}" -a "$GRUB_CMDLINE_CUR" != "$GRUB_CMDLINE"; then
        # Configure kernel cmdline args
        ${SUDO} sed -i /etc/default/grub \
            -e "s/.*\(GRUB_CMDLINE_LINUX_DEFAULT\).*/\1=\"${GRUB_CMDLINE}\"/"
        ${SUDO} update-grub
    fi
}

###########################
# Install hardware drivers
###########################

install_hw_drivers() {
    # Add contrib and non-free repos (once!)
    ${SUDO} sed -i /etc/apt/sources.list -e 's/ main$/ main contrib non-free/'
    ${APT_GET} update
    if $NEED_NON_FREE_FW; then
        # Solves e.g.
        #   W: Possible missing firmware /lib/firmware/i915/[...] for module i915
        ${APT_GET} install -y firmware-misc-nonfree
    fi
}

###########################
# Disable i915 Intel graphics
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
    # - Disable X
    ${SUDO} ln -s /usr/lib/systemd/system/multi-user.target \
        /etc/systemd/system/default.target
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
# Finish up
###########################

finalize() {
    set +x
    cat >&2 <<-EOF

		*** Install complete!
		*** You will probably have to reboot your machine
		***   in order for changes to take effect.
	EOF
    exit 0
}



###########################
# Install everything
###########################

install_everything() {
    check_cpu
    confirm_changes

    # At this point we're committed; show what we're doing
    set -x
    install_script_deps
    install_docker_ce
    install_rt_kernel
    disable_i915_graphics
    finalize
}

# Install everything if called as a script
! $CALLED_AS_SCRIPT || install_everything "$@"
