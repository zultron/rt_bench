
# Determine RT CPUs and GPU info
check_cpu() {
    # Processor model
    CPU="$(awk '/^model name/ {split($0, F, /: /); print(F[2]); exit}' \
               /proc/cpuinfo)"
    # Some hosts hang while running glmark2 and intel_gpu_top; unclear if it's
    # software or hardware, but for now, assume hardware
    INTEL_GPU_TOP_HANGS=false

    case "$CPU" in
        "Intel(R) Celeron(R) CPU  N3160  @ 1.60GHz")
            # ADLINK MXE-1501
            RT_CPUS=${RT_CPUS:-2-3}  # Shared L2 cache
            NONRT_CPUS=${NONRT_CPUS:-0-1}
            INTEL_GPU_TOP_HANGS=true
            ;;
        "Intel(R) Core(TM) i5-9400 CPU @ 2.90GHz")
            # Asus PRIME H310M-A R2.0
            RT_CPUS=${RT_CPUS:-5}  # No shared nothing!
            NONRT_CPUS=${NONRT_CPUS:-0-4}
            ;;
        "Intel(R) Core(TM) i5-8259U CPU @ 2.30GHz" | \
            "Intel(R) Core(TM) i5-8250U CPU @ 1.60GHz")
            # 8259U:  ???
            # 8250U:  YanLing/IWill YL-KBRL2
            RT_CPUS=${RT_CPUS:-3,7}  # Shared threads
            NONRT_CPUS=${NONRT_CPUS:-0-2,4-6}
            ;;
        "Intel(R) Atom(TM) Processor E3950 @ 1.60GHz")
            # ADLINK MXE-211
            RT_CPUS=${RT_CPUS:-2-3}  # Shared L2 cache
            NONRT_CPUS=${NONRT_CPUS:-0-1}
            INTEL_GPU_TOP_HANGS=true
            ;;
        *)
            echo "CPU '$CPU' unknown; please add to $BASH_SOURCE.  Exiting." >&2
            exit 1
            ;;
    esac
}
