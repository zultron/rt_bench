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

Run the tests with the script from this project.

    ./run_tests.sh

## Apply configurations that may affect RT

The `apply_rt_tuning_configs.sh` script can apply some configurations that
improve RT performance on some systems.  It will apply them all at
once; read the script to apply individual configurations.

    ./apply_rt_tuning_configs.sh

The configurations:

- Install the Debian `PREEMPT_RT` real-time kernel package and headers
- Isolate CPUs from the kernel command line `isolatecpus=` argument
  - The host's CPU must be listed in the `check_cpu` function
  - Some CPUs do better isolated in pairs, such as when sharing L2
    cache or hyperthreading
- Disable the i915 Intel HD Graphics driver
  - This GPU is known to cause RT jitter during high 3D load
