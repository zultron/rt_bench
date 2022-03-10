# `rt_bench` GH pages

## `stress-ng` only, 10 minutes

Run after `./apply_rt_tuning_configs.sh -izq`

```
DISPLAY=:0 ./run_tests.sh -d 600 -1 -o test_mxe-211_x_stress-ng "ADLINK MXE-211:  GPU, isolcpus=izq"
DISPLAY=:0 ./run_tests.sh -d 600 -1 -o test_h310m_x_stress-ng "Asus PRIME H310M-A R2.0:  GPU, isolcpus=izq"
DISPLAY=:0 ./run_tests.sh -d 600 -1 -o test_iwill_x_stress-ng "Yanling/Iwill N15 YL-KBRL2: GPU, isolcpus=izq"
```

## `glmark2` tests, 1 minute each

```
DISPLAY=:0 ./run_tests.sh -d 60 -o test_mxe-211_gpu "ADLINK MXE-211:  GPU, isolcpus=izq"
DISPLAY=:0 ./run_tests.sh -d 60 -o test_mxe-211_gpu "Asus PRIME H310M-A R2.0:  GPU, isolcpus=izq"
DISPLAY=:0 ./run_tests.sh -d 60 -o test_mxe-211_gpu "Yanling/Iwill N15 YL-KBRL2:  GPU, isolcpus=izq"
```
