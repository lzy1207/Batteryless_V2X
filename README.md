# Batteryless V2X PHY Simulation

MATLAB-based physical-layer simulation framework for batteryless vehicular communications using controlled amplitude overlay.

This project investigates how a low-rate passive payload can be embedded into an existing MIMO-OFDM host transmission without requiring an additional channel access attempt. The simulator evaluates the coexistence between the conventional host link and the batteryless passive overlay link.

The repository mainly supports physical-layer packet error rate evaluation under different attenuation depths, passive embedding bit rates, modulation and coding schemes, and channel conditions.

---

## 1. Project Overview

Batteryless roadside devices, passive sensors, and lightweight vehicular terminals require a low-power downlink for receiving control messages, configuration information, acknowledgements, and sensing instructions.

Instead of transmitting a separate packet, the proposed approach embeds passive data into an existing host waveform by introducing controlled amplitude attenuation. The host receiver continues to decode the original MIMO-OFDM packet, while the passive receiver extracts the additional information using low-complexity envelope detection.

The system therefore contains two receiver branches:

1. A coherent MIMO-OFDM receiver for the host packet.
2. A low-complexity envelope detector for the passive overlay packet.

The passive transmission reuses the airtime and spectrum already occupied by the host packet.

---

## 2. Physical-Layer Principle

### 2.1 Host transmission

The host communication link uses a packet-based MIMO-OFDM transmission.

The transmitter performs conventional operations such as:

* payload generation;
* channel coding;
* modulation;
* spatial-stream mapping;
* precoding;
* OFDM waveform generation.

At the receiver, the host packet is processed through:

* channel estimation;
* noise estimation;
* MIMO equalization;
* spatial combining;
* demodulation;
* channel decoding;
* packet-error detection.

The host-link reliability is evaluated by its packet error rate under different SNR, MCS, attenuation, and passive-rate settings.

### 2.2 Passive data embedding

The passive payload is inserted after the host waveform has been generated.

Two amplitude states are used to represent the passive bits:

* one state leaves the host waveform unchanged;
* the other state applies a controlled attenuation.

The attenuation depth determines the difference between the two amplitude states.

A larger attenuation depth generally makes the passive states easier to distinguish. However, stronger attenuation also creates a larger disturbance to the host waveform and may increase the host packet error rate.

The attenuation depth must therefore be selected by considering both host-link reliability and passive-link reliability.

### 2.3 Manchester coding

The passive information is Manchester encoded before being embedded into the host waveform.

Manchester coding is used as a line code rather than as a forward-error-correction code. Each passive information bit is represented by two complementary amplitude intervals. This creates an amplitude transition within each bit period and helps the passive receiver distinguish the two possible bit values.

The relevant processing modules include:

* `glazeManchesterEncode.m`
* `glazeBuildPacket.m`
* `glazeEmbed.m`
* `glazeDecode.m`

### 2.4 Passive envelope detection

The passive receiver does not perform full coherent MIMO-OFDM demodulation.

Instead, it uses the received signal envelope to detect the amplitude changes introduced by the overlay. The receiver compares the envelope levels in different portions of a Manchester-coded bit interval and decides the corresponding passive bit.

This design is suitable for low-complexity and low-power receivers because it avoids operations such as full carrier synchronization, FFT processing, coherent channel estimation, and high-resolution analog-to-digital conversion.

---

## 3. Vehicle-to-UAV Channel Model

The corresponding paper considers a low-altitude vehicular network in which ground vehicles communicate with UAVs.

The main channel assumptions are:

* ground vehicles use uniform linear antenna arrays;
* UAVs use uniform planar antenna arrays;
* each vehicle-to-UAV link follows a block-fading model;
* the channel remains approximately constant within one channel block;
* different channel blocks can have independent channel realizations;
* large-scale attenuation depends on the three-dimensional vehicle-to-UAV distance;
* small-scale fading can be represented by a Nakagami fading model;
* the channel includes transmit and receive array responses determined by the relative vehicle-UAV geometry.

The current MATLAB simulation mainly uses WLAN Toolbox MIMO-OFDM processing functions to generate packet-level PHY performance. These results provide the PER mappings required by the higher-layer cross-layer model.

---

## 4. Host-Link Reliability

The host receiver experiences both wireless channel impairment and overlay-induced distortion.

The host packet error rate depends on:

* baseline SNR;
* attenuation depth;
* passive embedding bit rate;
* selected host MCS;
* packet length;
* number of spatial streams;
* transmit and receive antenna configuration;
* channel estimation accuracy;
* equalization and combining method.

The simulator evaluates the effective host-link performance after applying the passive overlay.

A valid overlay configuration should preserve the host packet error rate below the required reliability threshold.

---

## 5. Passive-Link Reliability

The passive receiver distinguishes the two amplitude states from the received signal envelope.

The passive-link reliability depends on:

* attenuation depth;
* passive embedding bit rate;
* host-signal strength;
* sampling rate;
* number of envelope samples per passive bit;
* envelope-detector noise;
* filtering distortion;
* comparator noise;
* passive packet length;
* host MCS and packet duration.

A larger attenuation depth generally improves passive detection because it increases the amplitude difference between the two passive states.

A higher passive bit rate reduces the number of available samples per bit. This makes passive detection more difficult, particularly under weak-channel conditions.

The passive packet error rate is obtained after Manchester decoding and packet-level error checking.

---

## 6. Packet-Level Embedding Feasibility

The passive packet must fit inside the data portion of the host packet.

The available host-packet duration is affected by:

* host payload length;
* host MCS;
* number of spatial streams;
* OFDM symbol duration;
* guard interval;
* PHY and MAC overhead.

The required passive duration is affected by:

* passive preamble length;
* passive payload length;
* Manchester coding overhead;
* passive embedding bit rate.

A parameter configuration is infeasible when the complete passive packet cannot be accommodated within the available host-packet duration.

In the simulator, an infeasible configuration should be:

* marked as failed;
* excluded from parameter selection;
* assigned a high passive packet error rate; or
* removed using an action mask in a later reinforcement-learning implementation.

---

## 7. PHY-Layer Performance Metrics

The main physical-layer outputs are:

* host packet error rate;
* passive packet error rate;
* host decoding success probability;
* passive decoding success probability;
* effective host SINR;
* passive detection quality;
* host packet duration;
* passive embedding duration;
* packet-fit feasibility;
* host goodput;
* passive goodput;
* combined PHY-layer goodput.

The PHY simulator is primarily responsible for generating the mapping between:

* channel condition;
* attenuation depth;
* passive bit rate;
* host MCS;
* host packet error rate;
* passive packet error rate.

These mappings can later be used by optimization, MAC-layer analysis, or reinforcement-learning algorithms.

---

## 8. Main Simulation Experiments

### 8.1 Attenuation-depth comparison

This experiment studies the influence of attenuation depth on both links.

Typical configuration:

* host transmission fixed at MCS 0;
* passive embedding bit rate fixed at 20 kbps;
* attenuation depth varied over several candidate values;
* SNR swept over a predefined range.

Expected observations:

* small attenuation introduces limited disturbance to the host packet;
* small attenuation produces weak passive amplitude separation;
* increasing attenuation improves passive decoding;
* excessive attenuation can increase the host packet error rate.

Representative script:

```matlab
run_per_compare_multidelta_MIMO_STS2
```

### 8.2 Host-MCS comparison

This experiment studies the coexistence performance under different host MCS values.

Typical configuration:

* attenuation depth fixed at 3 dB;
* passive embedding bit rate fixed at 20 kbps;
* host MCS varied.

Expected observations:

* MCS 0 provides the strongest host-link robustness;
* higher MCS values provide higher nominal host rates;
* higher MCS values are more sensitive to channel noise and overlay distortion;
* higher MCS values shorten the host packet duration;
* a shorter host packet may not provide sufficient time for the complete passive packet;
* passive PER may remain high when the embedding-duration constraint is violated.

Representative scripts:

```matlab
run_per_compare_MCS
```

```matlab
compare_MCS
```

```matlab
compare_MCS2
```

### 8.3 Passive-bit-rate comparison

This experiment evaluates different passive embedding bit rates.

Typical configuration:

* host transmission fixed at MCS 0;
* attenuation depth fixed at 3 dB;
* passive embedding bit rate varied.

Expected observations:

* increasing the passive bit rate shortens each passive bit interval;
* a higher passive bit rate may reduce the time during which attenuation affects the host waveform;
* a higher passive bit rate provides fewer envelope samples for each passive bit;
* insufficient samples increase passive decoding errors;
* a very low passive bit rate requires a long embedding duration;
* a very low passive bit rate may violate the packet-fit constraint.

Representative script:

```matlab
run_per_compare_multiRb_MIMO_STS2
```

---

## 9. Repository Structure

### Core PHY simulation

* `box0Simulation.m`
  Main packet-level host and passive-link simulation function.

* `fullPHY.m`
  Full physical-layer simulation workflow.

* `MIMO_STS2.m`
  MIMO space-time-stream simulation configuration.

* `MIMO_test1.m`
  MIMO test scenario.

* `SIMO_test.m`
  SIMO baseline scenario.

* `getBox0SimParams.m`
  Construction of simulation parameters.

* `calculateSINR.m`
  SINR calculation utility.

* `extractPERfromSINR.m`
  PER extraction or PER mapping utility.

### Passive overlay modules

* `glazeBuildPacket.m`
  Builds the passive packet.

* `glazeManchesterEncode.m`
  Performs Manchester coding.

* `glazeEmbed.m`
  Embeds the passive waveform into the host waveform.

* `glazeDecode.m`
  Performs passive envelope-based decoding.

* `glazelog.m`
  Logs or visualizes passive-link results.

### MIMO receiver processing

* `getPrecodingMatrix.m`
* `heChannelToChannelEstimate.m`
* `heLTFChannelEstimate.m`
* `heNoiseEstimate.m`
* `heEqualizeCombine.m`
* `helperPerfectChannelEstimate.m`
* `helperSymbolEqualize.m`
* `heSUCalculateSteeringMatrix.m`
* `heUserBeamformingFeedback.m`
* `tgaxLinkPerformanceModel.m`
* `tgaxMMSEFilter.m`

These files provide operations such as precoding, channel estimation, noise estimation, MMSE filtering, equalization, combining, and link-performance evaluation.

### Experiment scripts

* `run_per_compare_multidelta_MIMO_STS2.m`
* `run_per_compare_multiRb_MIMO_STS2.m`
* `run_per_compare_MCS.m`
* `run_per_and_power_compare.m`
* `run_per_and_success_compare_multidelta_*.m`
* `compare2w.m`
* `compare_packet1000.m`
* `demo_plot_wifi_vs_glaze_waveform.m`
* `PERlog.m`
* `plotPERvsSNR.m`
* `plotPERvsEffectiveSNR.m`

### Dataset generation

* `generate_dataset_5cols.m`
  Generates PHY-layer simulation data for later optimization or learning.

---

## 10. Software Requirements

A recent MATLAB version compatible with the required WLAN Toolbox functions is recommended.

The project may require:

* MATLAB;
* WLAN Toolbox;
* Communications Toolbox;
* Signal Processing Toolbox;
* Parallel Computing Toolbox for parallel Monte Carlo simulations.

Run the following MATLAB command to inspect the installed products:

```matlab
ver
```

---

## 11. Quick Start

Clone the repository:

```bash
git clone https://github.com/lzy1207/Batteryless_V2X.git
```

Open MATLAB and enter the repository directory:

```matlab
cd('path_to_repository/Batteryless_V2X');
addpath(genpath(pwd));
```

Run the attenuation-depth comparison:

```matlab
run_per_compare_multidelta_MIMO_STS2
```

Run the MCS comparison:

```matlab
run_per_compare_MCS
```

Run the passive-bit-rate comparison:

```matlab
run_per_compare_multiRb_MIMO_STS2
```

Generate a PHY-layer dataset:

```matlab
generate_dataset_5cols
```

Before running an experiment, inspect the configuration section of the selected script and verify:

* SNR range;
* number of simulated packets;
* random seed;
* host MCS;
* attenuation-depth candidates;
* passive-rate candidates;
* host payload length;
* passive payload length;
* number of transmit antennas;
* number of receive antennas;
* number of spatial streams;
* output directory.

---

## 12. Reproducibility

For reproducible simulations, set the MATLAB random seed before running the experiment:

```matlab
rng(1, 'twister');
```

For every simulated parameter combination, it is recommended to record:

* SNR;
* attenuation depth;
* passive embedding bit rate;
* host MCS;
* host payload length;
* passive payload length;
* number of transmitted packets;
* host packet-error count;
* passive packet-error count;
* host PER;
* passive PER;
* packet-fit status;
* average effective host SINR;
* average passive detection quality.

A sufficiently large number of packet trials should be used when evaluating low packet error rates.

---

## 13. Expected Outputs

Depending on the selected experiment, the repository can generate:

* host PER versus SNR;
* passive PER versus SNR;
* comparison among different attenuation depths;
* comparison among different host MCS values;
* comparison among different passive embedding bit rates;
* host and passive waveform plots;
* received-power comparisons;
* packet-decoding success probabilities;
* MATLAB figure files;
* MATLAB data files;
* CSV datasets for optimization and reinforcement learning.

The central tradeoff is that stronger passive embedding improves passive detection but can also increase host-link distortion.

Therefore, attenuation depth, passive bit rate, and host MCS should be selected jointly.

---

## 14. Relationship to the Cross-Layer Framework

The complete research framework contains the following components:

1. Vehicle-to-UAV channel generation.
2. Host MIMO-OFDM waveform generation.
3. Passive overlay embedding and decoding.
4. Host and passive PER evaluation.
5. IEEE 802.11p contention analysis.
6. Cross-layer throughput calculation.
7. Model-driven parameter optimization.
8. Subchannel-conditioned multi-agent reinforcement learning.

This repository currently focuses primarily on:

* physical-layer waveform simulation;
* host-link PER evaluation;
* passive-link PER evaluation;
* PHY dataset generation.

The generated PHY data can be supplied to the MAC-layer model, optimization framework, or reinforcement-learning environment.

---

## 15. Current Limitations

The current implementation has several limitations:

* the host waveform is implemented using MATLAB WLAN Toolbox functions;
* the simulator mainly provides link-level rather than complete network-level evaluation;
* the passive receiver is represented by a software envelope-detection model;
* the passive hardware front-end has not yet been fully validated through RF measurements;
* some experiment scripts contain scenario-specific parameter settings;
* sufficiently large Monte Carlo trials are required for accurate low-PER evaluation;
* the complete heterogeneous DCF model is not included in every script;
* the reinforcement-learning implementation is not part of this PHY-only repository;
* some scripts may still contain local absolute file paths;
* output paths should be converted to relative paths before running the code on another computer.

---

## 16. Citation

When using this repository, please cite the corresponding work:

```bibtex
@article{cao2026batterylessv2x,
  title   = {Cross-Layer Throughput in DSRC-Based Passive Low-Altitude Vehicular Networks: Performance Analysis and Model-Data Co-Driven Optimization},
  author  = {Cao, Liu and Liu, Zhaoyu and Zhang, Lyutianyang and Hu, Ye},
  year    = {2026},
  note    = {Manuscript}
}
```

The venue, DOI, volume, issue, and page numbers should be updated after publication.

---

## 17. License and Third-Party Code

This repository does not currently provide a blanket open-source license for every file.

Some helper functions may originate from or be adapted from MathWorks examples. Their original copyright statements and licensing notices must be retained.

Before redistributing or commercially using the repository:

1. inspect the header of every helper function;
2. identify third-party source code;
3. preserve all original copyright notices;
4. verify the applicable redistribution conditions;
5. apply a project license only to code for which the authors own the necessary rights.

---

## 18. Contact

For questions about the physical-layer simulator, passive overlay model, PER evaluation, or dataset generation, please open an issue in this GitHub repository.
