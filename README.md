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

## Building the tools

The tools can be installed from Debian packages.

    sudo apt-get install rt-tools glmark2 rt-tests

Alternatively, build the `rt-tools` and `glmark2` from source with the
script in this project.

    ./build_tools.sh

## Running the tests

Run the tests with the script from this project.  Print basic usage:

    ./run_tests.sh -h

The script always runs the basic `cyclictest` first.  If the X display
is running (and no `-1` arg), the `cyclictest` run will be repeated
while running a series of GPU stress tests.

By default, the script writes output to the `tests` directory.  Each
run writes periodic data on CPU, GPU and memory into files within
subdirectories named `01`, `02` etc.

While the tests are running, run the following for a basic sanity
check that `cyclictest` is running as intended on isolated CPUs, and
stress tests are running on non-isolated CPUs.

    ps -Lo pid,tid,class,rtprio,ni,pri,psr,pcpu,stat,comm -C cyclictest -C glmark2 -C stress-ng

One copy of `cyclictest` should be running with one thread for each
CPU, and with elevated `RTPRIO` 90.

## Apply configurations that may affect RT

The `apply_rt_tuning_configs.sh` script can apply some configurations that
improve RT performance on some systems.  It will apply them all at
once; read the script to apply individual configurations.

    ./apply_rt_tuning_configs.sh install

Some of the configurations can be undone, but **only some**; see below
for which.

    ./apply_rt_tuning_configs.sh remove

The configurations:

- Install the Debian `PREEMPT_RT` real-time kernel package and headers
- Isolate CPUs from the kernel command line `isolatecpus=` argument
  - The host's CPU must be listed in the `check_cpu` function
  - Some CPUs do better isolated in pairs, such as when sharing L2
    cache or hyperthreading
  - The `remove` command removes CPU isolation
- Disable the i915 Intel HD Graphics driver and XWindows
  - This GPU is known to cause RT jitter during high 3D load
  - This also disables XWindows
  - The `remove` command reenables the i915 driver and XWindows
- Other things
  - Install utility packages
  - Enable legacy cgroups for `cgroup-tools`

## Running in a Docker container

The tests can be run from a Docker image for additional portability or
for comparing bare metal and containerized performance.  The
`docker/rt_bench` [rocker script][rocker] builds the image and runs a
container with access to the host GPU.

Build the container image:

    ./docker/rt_bench -b

Run the container:

    ./docker/rt_bench

[rocker]:  https://github.com/zultron/rocker

## Related links

https://www.suse.com/c/cpu-isolation-nohz_full-part-3/
https://www.kernel.org/doc/html/latest/admin-guide/kernel-parameters.html
