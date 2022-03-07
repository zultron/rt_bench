#!/bin/bash -e

THIS_DIR=$(readlink -f $(dirname $0))
HIST_TMP_DIR=$THIS_DIR/tests/tmp
lsmod | grep -q '^i915 ' && HAVE_I915=true || HAVE_I915=false
RT_CPUS="$(sed -n '/isolcpus=/ s/^.*isolcpus=\([0-9,-]\+\).*$/\1/ p' /proc/cmdline)"
CGNAME=/rt

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
else
    GLMARK2=glmark2
    CYCLICTEST=cyclictest
fi

NEEDED_UTILS=(
    $GLMARK2
    $CYCLICTEST
    intel_gpu_top
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
    test -z "$G_TOP_PID" || pkill -P $G_TOP_PID || true
    test -z "$C_TOP_PID" || pkill -P $C_TOP_PID || true
    test -z "$MEM_TOP_PID" || pkill -P $MEM_TOP_PID || true
    pkill -P $$ || true
    sudo chown -R $USER $HIST_TMP_DIR || true
    exit
}
trap cleanup EXIT ERR INT

function check_utils() {
    for UTIL in "${NEEDED_UTILS[@]}"; do
        if ! which $UTIL >&/dev/null; then
            echo "Failed to find executable '$UTIL'" >&2
            exit 1
        fi
    done
}

function setup_cgroup() {
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

function test_cases() {
    if test -z "$DISPLAY"; then
        echo "Note:  DISPLAY unset; not running GPU stress tests" >&2
        echo no-gpu-stress
        return
    fi
    GPU_ACCEL="$(glxinfo | sed -n 's/^\( *Accelerated: \)// p')"
    if test "$GPU_ACCEL" = no; then
        echo "Note:  DISPLAY=${DISPLAY} not accelerated; not running GPU stress tests" >&2
        echo no-gpu-stress
        return
    fi
    if $EXTERNAL_LOAD; then
        echo external-load
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

run_cyclictest() {
    local DATA_DIR=$1
    local DATA_FILE=$DATA_DIR/cyclictest_out.txt
    local GPU_TOP=$DATA_DIR/gpu_top_out.txt
    local CPU_TOP=$DATA_DIR/cpu_top_out.txt
    local MEM_TOP=$DATA_DIR/mem_top_out.txt
    NUM_CYCLES=100000  # OSADL:  100000000
    ! $HAVE_I915 || { sudo intel_gpu_top -lo $GPU_TOP & G_TOP_PID=$!; }
    mpstat -P ALL 1 25 > $CPU_TOP & C_TOP_PID=$!
    free -s 1 -c 25 > $MEM_TOP & MEM_TOP_PID=$!
    sudo $CYCLICTEST -l$NUM_CYCLES -m -Sp90 -i200 -h400 -q >$DATA_FILE
    kill $C_TOP_PID || true
    kill $MEM_TOP_PID || true
    $HAVE_I915 && sudo killall intel_gpu_top || true
    $HAVE_I915 && sudo chown $USER $GPU_TOP || true
}


html_header() {
    cat <<-EOF
		<html>
		  <head>
		    <title>$1</title>
		  </head>
		  <body>

		    <h1>$1</h1>
		EOF
}

html_plot() {
    cat <<-EOF

		    <h2>$1</h2>
		    <img src="$(basename $2)"/>
		EOF

}

html_footer() {
    cat <<-EOF

		  </body>
		</html>
		EOF
}

mk_hist() {
    local PLOT_DATA=$1; shift
    local PLOT_FILE=$1; shift
    local HTML_FILE=$1; shift
    local TITLE="$*"
    local CORES=$(nproc)
    local i
    local DATA_DIR=$(dirname $PLOT_DATA)
    local PLOTCMD=$DATA_DIR/plotcmd

    # Plot header
    cat >$PLOTCMD <<-EOF
		set terminal png
		set output "$PLOT_FILE"
		set multiplot layout $CORES, 1 title "Latency histogram:  $TITLE" font ",14"
		unset xtics
		EOF

    for i in `seq 1 $CORES`; do
        # Clean up data
        local CPU_PLOT_DATA=$DATA_DIR/histogram$i
        grep -v -e "^#" -e "^$" $PLOT_DATA | tr " " "\t" | cut -f1,$((i+1)) \
            >$CPU_PLOT_DATA
        local MAX=$(awk "/Max Latencies/ {print \$$((i+3))}" $PLOT_DATA)

        cat >>$PLOTCMD <<-EOF
			set tmargin at screen (1 - (0.1 + ($i-1) * 0.2))
			set bmargin at screen (1 - (0.08 + $i * 0.2))
			set xrange [0:400]
			set logscale y
			set ytics font ",8"
			set yrange [0.8:*]
			set ylabel " "
			EOF
        # Add Y label to 2nd last plot
        test $i != $(($CORES - 1)) || cat >>$PLOTCMD <<-EOF
			set ylabel "Number of latency samples"
			EOF
        # Add X label to last plot
        test $i != $CORES || cat >>$PLOTCMD <<-EOF
			set xlabel "Latency (us)"
			set xtics nomirror
			EOF
        cat >>$PLOTCMD <<-EOF
			plot "$CPU_PLOT_DATA" using 1:2 title "CPU$((i-1)): max $MAX" with histeps
			#
			EOF
    done

    # - Plot footer
    cat >>$PLOTCMD <<-EOF
		unset multiplot
		EOF

    # Execute plot command
    cat $PLOTCMD | gnuplot -persist
    html_plot "$TITLE" $PLOT_FILE >> $HTML_FILE
}

test_sequential() {
    check_utils

    local i=1
    PLOT_DIR=tests; mkdir -p $PLOT_DIR
    HTML_FILE=$PLOT_DIR/tests.html
    html_header "Latency tests:  $(date -R)" > $HTML_FILE
    for CASE in $(test_cases); do
        local IX=$(printf "%02d" $i)
        local DATA_DIR=$HIST_TMP_DIR/$IX; mkdir -p $DATA_DIR
        local PLOT_FILE="$PLOT_DIR/plot-${IX}.png"
        local TITLE="glmark2 $CASE"
        echo $i $TITLE
        rm -rf $DATA_DIR; mkdir -p $DATA_DIR
        G_PID=
        if test $CASE != no-gpu-stress -a $CASE != external-load; then
            ${GLMARK2} ${GLMARK2_ARGS} -b $CASE:duration=25.0 & G_PID=$!
        fi
        time run_cyclictest $DATA_DIR
        echo "  cyclictest done"
        if test $CASE != no-gpu-stress -a $CASE != external-load; then
            kill $G_PID
            wait
        fi
        mk_hist $DATA_DIR/cyclictest_out.txt $PLOT_FILE $HTML_FILE $TITLE
        i=$((i+1))
    done
    html_footer >> $HTML_FILE
}

usage() {
    cat 1>&2 <<-EOF
		Usage:  $0 [arg ...]
		  -c:  Create cgroup cpuset:$CGNAME on CPUs in /proc/cmdline isolcpus= argument
		  -x:  External GPU load; run one test without glmark2 GPU loading
		  -h:  This usage message
		EOF
    if test -z "$1"; then
        exit 0
    else
        echo "$1" 1>&2
        exit 1
    fi
}

CREATE_CPUSET=false
EXTERNAL_LOAD=false
while getopts :cxh ARG; do
    case $ARG in
        c) CREATE_CPUSET=true ;;
        x) EXTERNAL_LOAD=true ;;
        h) usage ;;
        *) usage "Unknown option '-$ARG'" ;;
    esac
done
shift $(($OPTIND - 1))

setup_cgroup
test_sequential
