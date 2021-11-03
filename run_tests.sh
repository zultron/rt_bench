#!/bin/bash -ex

# GLMARK2="glmark2"
GLMARK2="glmark2-es2"

function test_cases() {
    cat <<-EOF
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

cleanup() {
    pkill -P $G_PID || true
    pkill -P $$ || true
}
trap cleanup EXIT

test_sequential() {
    i=1
    for CASE in $(test_cases); do
        echo $i $CASE
        ${GLMARK2} -b $CASE:duration=25.0 & G_PID=$!
        OUTPUT=$(printf "tests/plot-${GLMARK2}-%02d.png" $i)
        time ./mklatencyplot.bash $OUTPUT $GLMARK2 "$CASE"
        echo "  cyclictest done"
        kill $G_PID
        wait
        i=$((i+1))
    done
}

test_parallel() {
    TESTS=""
    for CASE in $(test_cases); do
        TESTS+="$GLMARK2 -b '$CASE:duration=25.0' & "
    done
    bash -c "$TESTS" & G_PID=$!
    OUTPUT="tests/plot-${GLMARK2}-parallel.png"
    CMD="cd $PWD; time ./mklatencyplot.bash $OUTPUT $GLMARK2 all_parallel"
    docker exec -i ros-devel bash -c "$CMD"
    echo "  cyclictest done"
    kill $G_PID
    wait
}

# test_sequential
test_parallel


# [build] use-vbo=false: FPS: 3024 FrameTime: 0.331 ms
# [build] use-vbo=true: FPS: 3393 FrameTime: 0.295 ms
# [texture] texture-filter=nearest: FPS: 3050 FrameTime: 0.328 ms
# [texture] texture-filter=linear: FPS: 3050 FrameTime: 0.328 ms
# [texture] texture-filter=mipmap: FPS: 3003 FrameTime: 0.333 ms
# [shading] shading=gouraud: FPS: 2826 FrameTime: 0.354 ms
# [shading] shading=blinn-phong-inf: FPS: 2852 FrameTime: 0.351 ms
# [shading] shading=phong: FPS: 2655 FrameTime: 0.377 ms
# [shading] shading=cel: FPS: 2592 FrameTime: 0.386 ms
# [bump] bump-render=high-poly: FPS: 1478 FrameTime: 0.677 ms
# [bump] bump-render=normals: FPS: 3247 FrameTime: 0.308 ms
# [bump] bump-render=height: FPS: 3198 FrameTime: 0.313 ms
# [effect2d] kernel=0,1,0;1,-4,1;0,1,0;: FPS: 1821 FrameTime: 0.549 ms
# [effect2d] kernel=1,1,1,1,1;1,1,1,1,1;1,1,1,1,1;: FPS: 1041 FrameTime: 0.961 ms
# [pulsar] light=false:quads=5:texture=false: FPS: 2894 FrameTime: 0.346 ms
# [desktop] blur-radius=5:effect=blur:passes=1:separable=true:windows=4: FPS: 874 FrameTime: 1.144 ms
# [desktop] effect=shadow:windows=4: FPS: 1426 FrameTime: 0.701 ms
# [buffer] columns=200:interleave=false:update-dispersion=0.9:update-fraction=0.5:update-method=map: FPS: 306 FrameTime: 3.268 ms
# [buffer] columns=200:interleave=false:update-dispersion=0.9:update-fraction=0.5:update-method=subdata: FPS: 292 FrameTime: 3.425 ms
# [buffer] columns=200:interleave=true:update-dispersion=0.9:update-fraction=0.5:update-method=map: FPS: 544 FrameTime: 1.838 ms
# [ideas] speed=duration: FPS: 1966 FrameTime: 0.509 ms
# [jellyfish] <default>: FPS: 1963 FrameTime: 0.509 ms
# [terrain] <default>: FPS: 154 FrameTime: 6.494 ms
# [shadow] <default>: FPS: 1491 FrameTime: 0.671 ms
# [refract] <default>: FPS: 284 FrameTime: 3.521 ms
# [conditionals] fragment-steps=0:vertex-steps=0: FPS: 2315 FrameTime: 0.432 ms
# [conditionals] fragment-steps=5:vertex-steps=0: FPS: 2334 FrameTime: 0.428 ms
# [conditionals] fragment-steps=0:vertex-steps=5: FPS: 2290 FrameTime: 0.437 ms
# [function] fragment-complexity=low:fragment-steps=5: FPS: 2341 FrameTime: 0.427 ms
# [function] fragment-complexity=medium:fragment-steps=5: FPS: 2367 FrameTime: 0.422 ms
# [loop] fragment-loop=false:fragment-steps=5:vertex-steps=5: FPS: 2309 FrameTime: 0.433 ms
# [loop] fragment-steps=5:fragment-uniform=false:vertex-steps=5: FPS: 2316 FrameTime: 0.432 ms
# [loop] fragment-steps=5:fragment-uniform=true:vertex-steps=5: FPS: 2342 FrameTime: 0.427 ms
