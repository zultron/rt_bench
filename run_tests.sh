#!/bin/bash -e

INVOCATION=( "${@}" ); INVOCATION=( "${INVOCATION[@]/#/\"}" );
INVOCATION=( "\"$0\"" "${INVOCATION[@]/%/\"}" );
THIS_DIR=$(readlink -f $(dirname $0))
DATA_DIR=$THIS_DIR/tests
lsmod | grep -q '^i915 ' && HAVE_I915=true || HAVE_I915=false
CGNAME=/rt
glxinfo >&/dev/null && \
    GPU_ACCEL="$(glxinfo | sed -n 's/^\( *Accelerated: \)// p')" || GPU_ACCEL=no
CPU="$(awk '/^model name/ {split($0, F, /: /); print(F[2]); exit}' \
    /proc/cpuinfo)"

# Determine RT CPUs and GPU info
source $(dirname $BASH_SOURCE)/check_cpu.sh

if test -z "$IN_DOCKER"; then
    # Find glmark2 (glmark2-es2?)
    GLMARK2=$THIS_DIR/build/glmark2/build/src/glmark2
    if test -x $GLMARK2; then
        GLMARK2_ARGS="--data-path $THIS_DIR/build/glmark2/data"
    else
        GLMARK2=glmark2
    fi
    # Find cyclictest
    CYCLICTEST=$THIS_DIR/build/rt-tests/cyclictest
    test -x $CYCLICTEST || CYCLICTEST=cyclictest
    # Find intel_gpu_top
    INTEL_GPU_TOP=$THIS_DIR/build/igt-gpu-tools/build/tools/intel_gpu_top
    test -x $INTEL_GPU_TOP || INTEL_GPU_TOP=intel_gpu_top
else
    GLMARK2=glmark2
    CYCLICTEST=cyclictest
    INTEL_GPU_TOP=intel_gpu_top
fi

NEEDED_UTILS=(
    $GLMARK2
    $CYCLICTEST
    $INTEL_GPU_TOP
    mpstat
    gnuplot
    glxinfo
    lsmod
    free pkill
    killall
    sudo
)

cleanup() {
    test -z "$G_PID" || pkill -P $G_PID || true
    test -z "$G_TOP_PID" || sudo pkill -P $G_TOP_PID || true
    test -z "$C_TOP_PID" || pkill -P $C_TOP_PID || true
    test -z "$MEM_TOP_PID" || pkill -P $MEM_TOP_PID || true
    pkill -P $$ || true
    exit
}

check_utils() {
    for UTIL in "${NEEDED_UTILS[@]}"; do
        if ! which $UTIL >&/dev/null; then
            echo "Failed to find executable '$UTIL'" >&2
            exit 1
        fi
    done
}

setup_cgroup() {
    if ! $CREATE_CPUSET; then
        echo "Not setting up isolcpus cpuset cgroup" 1>&2
        return
    fi
    echo "Setting up cgroup cpuset:$CGNAME with CPUs $RT_CPUS" 1>&2
    test -n "$RT_CPUS" || \
        usage "Option -r set, but no kernel command line 'isolcpus='"
    if test "$(lscgroup cpuset:$CGNAME)" != ""; then
        echo "    cgroup cpuset:$CGNAME already exists" 1>&2
    else
        echo "    Creating cgroup cpuset:$CGNAME" 1>&2
        sudo cgcreate -g cpuset:$CGNAME
    fi
    CPUSET=$(cgget -nvr cpuset.cpus $CGNAME)
    if test -n "$(cgget -nvr cpuset.cpus $CGNAME)"; then
        echo "    cgroup cpuset:$CGNAME already contains CPUs $CPUSET" 1>&2
        return
    fi
    echo "    Adding CPUs $RT_CPUS to cgroup cpuset:$CGNAME" 1>&2
    sudo cgset -r cpuset.cpus=$RT_CPUS $CGNAME
    CPUSET=$(cgget -nvr cpuset.cpus $CGNAME)
    if test -n "$CPUSET"; then
        echo "    Success:  cgroup cpuset:$CGNAME CPUs $CPUSET" 1>&2
    else
        echo "Failed to create cgroup cpuset:$CGNAME with CPUs $RT_CPUS" 1>&2
        exit 1
    fi
}

test_cases() {
    if test -z "$DISPLAY" && ! $RUN_ONE; then
        usage "DISPLAY unset; unable to run GPU stress tests"
    fi
    if test "$GPU_ACCEL" = no && ! $RUN_ONE; then
        usage "No GPU acceleration; unable to run GPU stress tests"
    fi
    if $RUN_ONE; then
        echo no-gpu-stress
        return
    fi
    cat <<-EOF
		no-gpu-stress
		build:use-vbo=false
		build:use-vbo=true
		texture:texture-filter=nearest
		texture:texture-filter=linear
		texture:texture-filter=mipmap
		shading:shading=gouraud
		shading:shading=blinn-phong-inf
		shading:shading=phong
		shading:shading=cel
		bump:bump-render=high-poly
		bump:bump-render=normals
		bump:bump-render=height
		effect2d:kernel=0,1,0;1,-4,1;0,1,0;
		effect2d:kernel=1,1,1,1,1;1,1,1,1,1;1,1,1,1,1;
		pulsar:light=false:quads=5:texture=false
		desktop:blur-radius=5:effect=blur:passes=1:separable=true:windows=4
		desktop:effect=shadow:windows=4
		buffer:columns=200:interleave=false:update-dispersion=0.9:update-fraction=0.5:update-method=map
		buffer:columns=200:interleave=false:update-dispersion=0.9:update-fraction=0.5:update-method=subdata
		buffer:columns=200:interleave=true:update-dispersion=0.9:update-fraction=0.5:update-method=map
		ideas:speed=duration
		jellyfish
		terrain
		shadow
		refract
		conditionals:fragment-steps=0:vertex-steps=0
		conditionals:fragment-steps=5:vertex-steps=0
		conditionals:fragment-steps=0:vertex-steps=5
		function:fragment-complexity=low:fragment-steps=5
		function:fragment-complexity=medium:fragment-steps=5
		loop:fragment-loop=false:fragment-steps=5:vertex-steps=5
		loop:fragment-steps=5:fragment-uniform=false:vertex-steps=5
		loop:fragment-steps=5:fragment-uniform=true:vertex-steps=5
		EOF
}

html_header() {
    local RT_CPUS_HTML GPU_ACCEL_HTML
    test -z "$RT_CPUS" || RT_CPUS_HTML="<li>isolcpus=$RT_CPUS</li>"
    $RUN_ONE || GPU_ACCEL_HTML="<li>GPU acceleration:  $GPU_ACCEL</li>"
    cat <<-EOF
		<html>
		  <head>
		    <title>$1</title>
		  </head>
		  <body>
		    <h1>Latency tests:  $DESCRIPTION</h1>
		    <ul>
		      <li>Date:  $(date -R)</li>
		      <li>Invocation:  ${INVOCATION[@]}</li>
		      <li>cyclictest version:  $($CYCLICTEST --help | head -1)</li>
		      <li>Test duration:  $DURATION seconds</li>
		      <li>Kernel commandline:  $(cat /proc/cmdline)</li>
		      <li>Create 'cpuset:$CGNAME' cgroup:  $CREATE_CPUSET</li>
		      <li>CPU:  $CPU</li>
		      <li>Number of CPUs:  $NUM_CORES</li>
		      <li>DMI info:  $(cat /sys/devices/virtual/dmi/id/modalias)</li>
		      $RT_CPUS_HTML
		      $GPU_ACCEL_HTML
		    </ul>
		EOF
}

html_test_header() {
    local IX="$1"
    local TITLE="$2"
    local CT_ARGS="$3"
    local GLMARK2_ARGS="$4"
    test -z "$GLMARK2_ARGS" || GLM_HTML="<li>glmark2 command:  glmark2 $GLMARK2_ARGS</li>"
    cat <<-EOF

		    <h2>Test #${IX}:  ${TITLE}</h2>
		    <ul>
		      <li>Command:  cyclictest $CT_ARGS</li>
		      $GLM_HTML
		EOF
}

html_test_plot() {
	echo "    </ul>"
	echo "    <img src=\"$1\"/>"
}

html_footer() {
    cat <<-EOF

		  </body>
		</html>
		EOF
}

mk_hist() {
    local TEST_DIR=$1; shift
    local PLOT_DATA=$1; shift
    local PLOT_FILE=$1; shift
    local HTML_FILE=$1; shift
    local TITLE="$*"
    local i=0
    local PLOTCMD=$TEST_DIR/plotcmd.gv

    # Plot header
    cat >$PLOTCMD <<-EOF
		set terminal png
		set output "$PLOT_FILE"
		set multiplot layout $NUM_CORES, 1 title "Latency histogram:  $TITLE" font ",14"
		unset xtics
		numcpus = $NUM_CORES
		top_border = (1 - 0.1)
		bot_border = 0.05
		inter_border = 0.02
		graph_height = (top_border - bot_border - inter_border * (numcpus - 1)) / numcpus
		graph_dist = (top_border - bot_border) / numcpus
		EOF

    for CPU in ${RT_CPUS//,/ }; do
        i=$((i+1))
        # Clean up data
        local CPU_PLOT_DATA=$TEST_DIR/histogram$i
        grep -v -e "^#" -e "^$" $PLOT_DATA | tr " " "\t" | cut -f1,$((i+1)) \
            >$CPU_PLOT_DATA
        local MAX=$(awk "/Max Latencies/ {print \$$((i+3))}" $PLOT_DATA)

        cat >>$PLOTCMD <<-EOF
			graphnum = $i
			set tmargin at screen (top_border - (graphnum-1) * graph_dist)
			set bmargin at screen (top_border - (graphnum-1) * graph_dist - graph_height)
			set xrange [0:400]
			set logscale y
			set ytics font ",8"
			set yrange [0.8:*]
			set ylabel " "
			EOF
        # Add Y label to 2nd last plot
        test $i != $(($NUM_CORES - 1)) || cat >>$PLOTCMD <<-EOF
			set ylabel "Number of latency samples"
			EOF
        # Add X label to last plot
        test $i != $NUM_CORES || cat >>$PLOTCMD <<-EOF
			set xlabel "Latency (us)"
			set xtics nomirror
			EOF
        cat >>$PLOTCMD <<-EOF
			plot "$CPU_PLOT_DATA" using 1:2 title "CPU$CPU: max $MAX" with histeps
			#
			EOF
    done

    # - Plot footer
    cat >>$PLOTCMD <<-EOF
		unset multiplot
		EOF

    # Execute plot command
    cat $PLOTCMD | gnuplot -persist
    html_test_plot $(realpath --relative-to=$DATA_DIR  $PLOT_FILE) >> $HTML_FILE
}

test_sequential() {
    if test -z "$RT_CPUS"; then
        echo "CPU '$CPU' unknown; please add to $BASH_SOURCE.  Exiting." >&2
        exit 1
    fi
    test ! -e $DATA_DIR || usage "Output directory exists; move or specify new one"
    mkdir -p $DATA_DIR
    ! $INTEL_GPU_HANGS || echo "Not running intel_gpu_top" 1>&2  # FIXME
    local HTML_FILE=$DATA_DIR/tests.html
    local i=0
    html_header "Latency tests:  $(date -R)" > $HTML_FILE
    for CASE in $(test_cases); do
        i=$((++i))
        local IX=$(printf "%02d" $i)
        local TEST_DIR=$DATA_DIR/$IX; mkdir -p $TEST_DIR
        local PLOT_FILE="$TEST_DIR/plot-${IX}.png"
        local TITLE="glmark2 $CASE"
        test "$CASE" != no-gpu-stress || TITLE="No GPU stress"
        local DATA_FILE=$TEST_DIR/cyclictest_out.txt
        local GPU_TOP=$TEST_DIR/gpu_top_out.txt
        local CPU_TOP=$TEST_DIR/cpu_top_out.txt
        local MEM_TOP=$TEST_DIR/mem_top_out.txt
        local GLMARK2_OUT=$TEST_DIR/glmark2_out.txt
        local CT_ARGS="-D$DURATION -m -p90 -i200 -h400 -q"
        CT_ARGS+=" -t $NUM_CORES -a${RT_CPUS}"
        local GLMARK2_TEST_ARGS="${GLMARK2_ARGS} -b $CASE:duration=$DURATION"
        test $CASE != no-gpu-stress || GLMARK2_TEST_ARGS=""

        # Print info to console & HTML file
        echo
        echo "****************"
        echo "Test #$i:  $TITLE"
        echo "Command:  $CYCLICTEST $CT_ARGS"
        echo "Output:  $DATA_FILE"
        test -z "$GLMARK2_TEST_ARGS" || echo "glmark2 command:  $GLMARK2 $GLMARK2_TEST_ARGS"
        html_test_header $IX "$TITLE" "$CT_ARGS" "$GLMARK2_TEST_ARGS" >> $HTML_FILE

        # Run glmark2, if applicable
        if test $CASE != no-gpu-stress; then
            ${GLMARK2} ${GLMARK2_TEST_ARGS} > $GLMARK2_OUT & G_PID=$!
        fi

        # Run Intel GPU top, if applicable
        ! $HAVE_I915 && $INTEL_GPU_HANGS \
            || { sudo $INTEL_GPU_TOP -o - > $GPU_TOP & G_TOP_PID=$!; }

        # Record processor & memory stats during run
        mpstat -P ALL 1 $DURATION > $CPU_TOP & C_TOP_PID=$!
        free -s 1 -c $DURATION > $MEM_TOP & MEM_TOP_PID=$!

        # Run cyclictest
        time sudo $CYCLICTEST $CT_ARGS >$DATA_FILE
        echo "  cyclictest done"

        # Shut down background processes
        ! $HAVE_I915 || sudo killall intel_gpu_top || true
        wait

        # Generate chart
        echo "  generating chart"
        mk_hist $TEST_DIR $DATA_FILE $PLOT_FILE $HTML_FILE "$TITLE"
    done
    html_footer >> $HTML_FILE
}

usage() {
    cat 1>&2 <<-EOF
		Usage:  $0 [arg ...] [Description]
		  -d SECS:  Duration of test in seconds (default 20)
		  -o PATH:  Location of output dir (default $DATA_DIR)
		  -c:       Create cgroup cpuset:$CGNAME on CPUs in /proc/cmdline isolcpus= argument
		  -1:       Run only one test without glmark2 GPU loading
		  -h:       This usage message
		EOF
    if test -z "$1"; then
        exit 0
    else
        echo "$1" 1>&2
        exit 1
    fi
}

DURATION=20
CREATE_CPUSET=false
RUN_ONE=false
while getopts :d:o:c1h ARG; do
    case $ARG in
        d) DURATION=$OPTARG ;;
        o) DATA_DIR=$OPTARG ;;
        c) CREATE_CPUSET=true ;;
        1) RUN_ONE=true ;;
        h) usage ;;
        *) usage "Unknown option '-$ARG'" ;;
    esac
done
shift $(($OPTIND - 1))
DESCRIPTION="$*"

# setup_cgroup
check_utils
check_cpu
trap cleanup EXIT ERR INT
test_sequential
