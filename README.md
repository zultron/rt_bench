# Crude RT Benchmarks for Motion Controller Hardware

- Measure a system's real-time jitter with `cyclictest`.
- Simultaneously run GPU stress tests to determine effect on jitter.
- Apply and test configurations that may affect real-time performance.
- Visualize results with graphs.
- Reproduce tests on multiple machines for comparison.

Motion control applications run a hardware update loop with a high,
stable frequency to produce smooth, responsive motion.  A major,
unsolved challenge is how to find controller hardware with good
real-time characteristics to support high-performance motion control.

[A few examples][examples].

Note:  Running `cyclictest` and `glmark2` (esp. certain 3D tests) at
the same time causes hangs in most systems I've tried.  The reason is
as yet unknown.

## Building the tools

The tools can be installed from Debian packages.

    sudo apt-get install rt-tools glmark2 rt-tests

Alternatively, build the `rt-tools` and `glmark2` from source with the
script in this project.

    ./build_tools.sh

## Running the tests

Run the tests with the script from this project.  Print basic usage:

    ./run_tests.sh -h

The script always runs the basic `cyclictest` first with `stress-ng`
system stress tests.  If the `-1` arg is not supplied, the
`cyclictest` run will repeat once for each of a series of GPU stress
tests by the `glmark2` utility.

The script writes output to the directory specified by the `-o`
argument, `tests` by default.  The `tests.html` file contains the
final report with system and run information and test results for each
run.  Each run records `cyclictest` output, periodic data on CPU, GPU
& memory, and the latency histogram chart into files within
subdirectories named `01`, `02` etc.

While the tests are running, run the following for a basic sanity
check that `cyclictest` are running as intended on isolated CPUs, and
stress tests are running on non-isolated CPUs.

    ps -Lo pid,tid,class,rtprio,ni,pri,psr,pcpu,stat,comm -C cyclictest -C glmark2 -C stress-ng

One copy of `cyclictest` should be running with one thread for each
isolated CPU, and with elevated `RTPRIO` 90.  Any `glmark2` and
`stress-ng` threads should be running on non-isolated CPUs.

## Apply configurations that may affect RT

The `apply_rt_tuning_configs.sh` script can apply some configurations
that improve RT performance on some systems.  It can also remove most
of them.  See the inline help.

    ./apply_rt_tuning_configs.sh -h

The configurations:

- Install the Debian `PREEMPT_RT` real-time kernel package and headers
  - Essential for real-time performance
  - Only Debian ships `PREEMPT_RT` kernel packages
- Isolate CPU(s) from the kernel command line `isolcpus=` argument
  - Specify which CPU(s) with e.g. `-r 3,7`, or add to the `check_cpu`
    function
  - Some CPUs do better isolated in pairs, such as when sharing L2
    cache or hyperthreading
  - See [Linux kernel parameter docs][kparams]
- Set kernel `nohz_full=` for same CPU(s) as above `isolcpus=`
  - See this Suse blog ["CPU Isolation" article][nohz_full]
  - See [Linux kernel parameter docs][kparams]
- Set kernel `irqaffinity=` for CPUs *not* in `isolcpus=` cpuset
  - The kernel will try to move IRQ service threads to these CPUs
  - See [Linux kernel parameter docs][kparams]
- Disable the i915 Intel HD Graphics driver; disable XWindows
  - Intel GPUs are known to cause RT jitter during high 3D load
  - These options disable XWindows to avoid this, and blacklist the
    i915 driver as an even more drastic measure
- Other things
  - Install Docker CE (for running tests in a container)
  - Enable legacy cgroups for `cgroup-tools`; not currently used in
    these scripts

## Running in a Docker container

The tests can be run from a Docker image for additional portability or
for comparing bare metal and containerized performance.  The
`docker/rt_bench` [rocker script][rocker] builds the image and runs a
container with access to the host GPU.

Build the container image:

    ./docker/rt_bench -b

Run the container:

    ./docker/rt_bench



[examples]:  https://zultron.github.io/rt_bench/
[kparams]:  https://www.kernel.org/doc/html/latest/admin-guide/kernel-parameters.html
[nohz_full]:  https://www.suse.com/c/cpu-isolation-nohz_full-part-3/
[rocker]:  https://github.com/zultron/rocker
