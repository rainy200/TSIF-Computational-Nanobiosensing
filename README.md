# TSIF for Computational Nanobiosensing

MATLAB implementation and reproducibility code for the Triadic Swarm Intelligence Framework (TSIF), including its evaluation in hybrid in vivo computing (HIVC) and autonomous in vivo computing (AIVC) settings.

The repository accompanies the manuscript:

> **Triadic Swarm Intelligence Framework: Toward an Interpretable Process-Level State Descriptor for Computational Nanobiosensing**  


## Repository contents

| File | Purpose |
|---|---|
| `code/main_stif_ablation_ECA.m` | Main TSIF-HIVC factorial experiment, component ablations, paired inference, tables, and figures. |
| `code/main_tsif_aivc_revised.m` | Target-free TSIF-AIVC experiment using a common P-AIVC local layer; includes TSIF-AIVC, `w/o E`, `w/o C`, `w/o A`, Fixed-AIVC, and published P-AIVC comparisons. |

Both files are self-contained MATLAB functions with their helper functions included at the end of the same file.

## Requirements

- MATLAB R2020b or later
- Statistics and Machine Learning Toolbox for `signrank` and PCA-based supplementary analyses
- Parallel Computing Toolbox is optional; the default definitions support serial execution and process-level sharding

No external MATLAB data file is required by these final implementations.

## Quick checks

From the repository root:

```matlab
addpath('code');

% TSIF-HIVC reduced check
main_stif_ablation_ECA('quick');

% TSIF-AIVC branch and output check
main_tsif_aivc_revised('smoke');
```

The quick modes are intended to verify execution and output structure. Their results should not be used as manuscript evidence.

## Formal TSIF-HIVC experiment

```matlab
addpath('code');
main_stif_ablation_ECA('formal');
```

The default base seed is `20250425`. Each scenario reuses its initialization and stochastic realization across all compared methods, enabling matched comparisons. Environment-variable overrides in this program are intended for explicit sensitivity or sharded runs and should be recorded when used.

## Formal TSIF-AIVC experiment

```matlab
addpath('code');
main_tsif_aivc_revised('formal');
```

The formal design contains:

- four BGF landscapes: Sphere, Matyas, Ackley, and Rastrigin;
- three initialization regimes;
- two position-noise levels;
- six methods;
- 30 matched seeds per setting;
- 4,320 runs in total.

The formal base seed is locked at `20261217`. For scenario `s`, the program uses `mod(20261217 + s, 2^31 - 1)`. All six methods within a scenario receive the same initial positions and pre-generated stochastic arrays. A conflicting `AIVC_BASE_SEED` environment value causes the formal run to stop instead of silently changing the seed.

The six AIVC-family methods are:

1. **TSIF-AIVC**: complete dynamic target-free TSIF feedback;
2. **w/o E**: entropy pathway disabled;
3. **w/o C**: consensus pathway disabled;
4. **w/o A**: alignment pathway disabled;
5. **Fixed-AIVC**: non-adaptive frozen TSIF gains;
6. **P-AIVC** (`local_only` internally): article-based local autonomous controller without the added TSIF feedback layer.

The true target position is used only by the common evaluation layer. It is not supplied to the TSIF-AIVC or P-AIVC control paths.

## Outputs

Each formal program writes run-level records, pooled and factorial summaries, statistical comparisons, configuration tables, MATLAB result files, and publication figures. The AIVC program writes its default formal outputs to `autonomous_results/`.

Process-error AUC is a lower-is-better metric. Manuscript statements should be based on a completed formal run and the generated paired inference tables, rather than on smoke or parameter-development runs.

## Experimental Data

The experimental data are available in the
[data release](https://github.com/rainy200/TSIF-Computational-Nanobiosensing/releases/tag/data-v1.0).

Download the two ZIP files under **Assets**.


## Reproducibility notes

- Method comparisons use matched scenarios and random streams.
- Single-path ablations change only their named TSIF switch.
- Fixed-AIVC and P-AIVC retain their defined non-adaptive and published-local roles.
- Configuration and method-switch tables are exported with the results.
- Public result archives should record the commit identifier and preserve the generated configuration files.

## Citation

Please cite the accompanying manuscript. A machine-readable citation template is provided in `CITATION.cff`; publication metadata can be updated after acceptance.

## License

This code is released under the MIT License. See `LICENSE`.
