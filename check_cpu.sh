
# Determine RT CPUs and GPU info:
# - $RT_CPUS:  cpuset for RT CPUs; existing value won't be clobbered
# - $NONRT_CPUS:  cpuset for non-RT CPUs; existing value won't be clobbered
# - $INTEL_GPU_HANGS:  `true` if running `cyclictest` and `glmark2` will hang
#   the system (under investigation)

check_cpu() {
    # Processor model
    CPU="$(awk '/^model name/ {split($0, F, /: /); print(F[2]); exit}' \
               /proc/cpuinfo)"
    # Some hosts hang while running glmark2 and intel_gpu_top; unclear if it's
    # software or hardware, but for now, assume hardware
    INTEL_GPU_HANGS=false

    case "$CPU" in
        "Intel(R) Celeron(R) CPU  N3160  @ 1.60GHz")
            # ADLINK MXE-1501
            RT_CPUS=${RT_CPUS:-2-3}  # Shared L2 cache
            INTEL_GPU_HANGS=true
            ;;
        "Intel(R) Core(TM) i5-9400 CPU @ 2.90GHz")
            # Asus PRIME H310M-A R2.0
            RT_CPUS=${RT_CPUS:-5}  # No shared nothing!
            ;;
        "Intel(R) Core(TM) i5-8259U CPU @ 2.30GHz" | \
            "Intel(R) Core(TM) i5-8250U CPU @ 1.60GHz")
            # 8259U:  ???
            # 8250U:  YanLing/IWill N15 YL-KBRL2
            RT_CPUS=${RT_CPUS:-6,7}  # Shared threads
            ;;
        "Intel(R) Atom(TM) Processor E3950 @ 1.60GHz")
            # ADLINK MXE-211
            RT_CPUS=${RT_CPUS:-2-3}  # Shared L2 cache
            INTEL_GPU_HANGS=true
            ;;
        *)
            test -n "$RT_CPUS" || return
            ;;
    esac
    RT_CPUS=$(hwloc-calc 2>/dev/null --intersect PU PU:${RT_CPUS//,/ PU:})
    NONRT_CPUS=$(hwloc-calc 2>/dev/null --intersect PU all ~PU:${RT_CPUS//,/ ~PU:})
    NUM_CORES=$(hwloc-calc 2>/dev/null --number-of PU PU:${RT_CPUS//,/ PU:})
}
