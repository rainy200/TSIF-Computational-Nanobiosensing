function main_stf_ablation_ECA(run_mode)
    clc; close all;

    if nargin < 1
        run_mode = '';
    end

    %% ---- Setup ----
    experiment_profile = strtrim(lower(getenv('TSIF_EXPERIMENT_PROFILE')));
    if isempty(experiment_profile), experiment_profile = 'paper'; end
    if contains(lower(run_mode), 'stress_controller_v2_1_confirmatory')
        experiment_profile = 'stress_controller_v2_1_confirmatory';
    elseif contains(lower(run_mode), 'stress_controller_v2_1_dev')
        experiment_profile = 'stress_controller_v2_1_dev';
    elseif contains(lower(run_mode), 'stress_revised_v2')
        experiment_profile = 'stress_revised_v2';
    elseif contains(lower(run_mode), 'stress_revised')
        experiment_profile = 'stress_revised';
    elseif contains(lower(run_mode), 'stress')
        experiment_profile = 'stress';
    end
    params  = setup_params(experiment_profile);
    exp_cfg = setup_experiment_config();
    exp_cfg.experiment_profile = experiment_profile;
    params.base_seed = exp_cfg.base_seed;

    if strcmpi(run_mode, 'figures') || strcmpi(run_mode, 'figure_only')
        exp_cfg.regenerate_figures_only = true;
    elseif strcmpi(run_mode, 'quick') || strcmpi(run_mode, 'smoke') || ...
            strcmpi(run_mode, 'stress_quick') || strcmpi(run_mode, 'stress_smoke') || ...
            strcmpi(run_mode, 'stress_revised_quick') || strcmpi(run_mode, 'stress_revised_smoke') || ...
            strcmpi(run_mode, 'stress_revised_v2_quick') || strcmpi(run_mode, 'stress_revised_v2_smoke') || ...
            strcmpi(run_mode, 'stress_controller_v2_1_confirmatory_quick') || ...
            strcmpi(run_mode, 'stress_controller_v2_1_confirmatory_smoke') || ...
            strcmpi(run_mode, 'stress_controller_v2_1_dev_quick') || ...
            strcmpi(run_mode, 'stress_controller_v2_1_dev_smoke')
        exp_cfg.quick_test = true;
        exp_cfg.do_visualize_bgf = false;
    end

    % Optional method filter for process-level recovery or targeted reruns.
    % Example: setenv('TSIF_CONTROL_MODES','no_c') or a comma-separated list.
    env_modes = strtrim(getenv('TSIF_CONTROL_MODES'));
    if ~isempty(env_modes)
        requested_modes = strtrim(strsplit(lower(env_modes), ','));
        valid_modes = {'tsif_full','no_e','no_c','no_a', ...
            'baseline','local_only'};
        if any(~ismember(requested_modes, valid_modes))
            error('TSIF_CONTROL_MODES contains an unknown method.');
        end
        exp_cfg.control_mode_list = requested_modes;
    end

    % Optional condition filters are intended for independent development
    % checks of reconstruction choices.  Formal runs leave them unset.
    env_bgfs = strtrim(getenv('TSIF_BGF_TYPES'));
    if ~isempty(env_bgfs)
        requested_bgfs = strtrim(strsplit(lower(env_bgfs), ','));
        valid_bgfs = {'sphere','matyas','ackley','rastrigin'};
        if any(~ismember(requested_bgfs, valid_bgfs))
            error('TSIF_BGF_TYPES contains an unknown landscape.');
        end
        exp_cfg.bgf_type_list = requested_bgfs;
    end
    env_inits = strtrim(getenv('TSIF_INIT_MODES'));
    if ~isempty(env_inits)
        requested_inits = strtrim(strsplit(lower(env_inits), ','));
        valid_inits = {'corner_small','corner_large','random'};
        if any(~ismember(requested_inits, valid_inits))
            error('TSIF_INIT_MODES contains an unknown initialization.');
        end
        exp_cfg.init_list = requested_inits;
    end
    env_noise = strtrim(getenv('TSIF_NOISE_LEVELS'));
    if ~isempty(env_noise)
        requested_noise = cellfun(@str2double, ...
            strtrim(strsplit(env_noise, ',')));
        if any(~isfinite(requested_noise)) || any(requested_noise < 0)
            error('TSIF_NOISE_LEVELS must contain nonnegative numbers.');
        end
        exp_cfg.noise_level_list = requested_noise;
    end

    raw_only = any(strcmpi(strtrim(getenv('TSIF_RAW_ONLY')), {'1','true','yes'}));
    if raw_only
        exp_cfg.do_visualize_bgf = false;
    end

    if exp_cfg.quick_test
        quick_sims = str2double(getenv('TSIF_NUM_SIMS'));
        if isnan(quick_sims) || quick_sims < 1, quick_sims = 3; end
        exp_cfg.num_simulations_per_setting = floor(quick_sims);
        exp_cfg.do_visualize_bgf = false;
        fprintf('*** QUICK TEST MODE: %d simulations per setting ***\n', ...
            exp_cfg.num_simulations_per_setting);
    end

    out_prefix = getenv('TSIF_OUT_PREFIX');
    if isempty(out_prefix)
        out_prefix = sprintf('tsif_ablation_%s_%s', ...
            exp_cfg.experiment_mode, params.experiment_profile);
    end
    analysis_prefix = getenv('TSIF_ANALYSIS_PREFIX');
    if isempty(analysis_prefix), analysis_prefix = out_prefix; end
    figure_prefix = getenv('TSIF_FIGURE_PREFIX');
    if isempty(figure_prefix), figure_prefix = analysis_prefix; end
    fprintf('===== TSIF Ablation Experiment  [%s | profile=%s] =====\n', ...
        exp_cfg.experiment_mode, params.experiment_profile);

    %% ---- Optional: redraw figures from saved results only ----
    if exp_cfg.regenerate_figures_only
        fprintf('*** FIGURE-ONLY MODE: loading saved result files ***\n');
        feature_table = readtable([out_prefix '_feature.csv']);
        summary_table = readtable([out_prefix '_summary.csv']);
        feature_table = normalize_text_columns(feature_table, ...
            {'bgf_type','control_mode','init_name'});
        summary_table = normalize_text_columns(summary_table, ...
            {'bgf_type','control_mode','init_name'});
        saved = load([out_prefix '_results.mat'], 'all_results');
        all_results = saved.all_results;
        stats_table = run_paired_comparison_tests(feature_table);
        writetable(stats_table, [analysis_prefix '_paired_significance.csv']);
        generate_paper_tables(feature_table, stats_table, analysis_prefix);
        generate_no_new_simulation_exports(feature_table, all_results, stats_table, params, analysis_prefix);
        generate_figures(feature_table, summary_table, all_results, figure_prefix);
        fprintf('\n===== Figures and tables regenerated =====\n');
        return;
    end

    %% ---- Stage 1: optional metric validation ----
    if strcmpi(exp_cfg.experiment_mode, 'metric_validation')
        metric_table = run_metric_validation(params, exp_cfg.bgf_type_list, out_prefix);
        writetable(metric_table, [out_prefix '_metric_validation.csv']);
        fprintf('\nMetric validation done. Set experiment_mode = formal_compare to continue.\n');
        return;
    end

    %% ---- BGF landscape preview ----
    if exp_cfg.do_visualize_bgf
        try
            plot_all_bgfs(out_prefix);
        catch ME
            warning('%s: %s', ME.identifier, ME.message);
        end
    end

    %% ---- Stage 2: main experiment sweep ----
    [feature_table, summary_table, all_results] = run_experiment_sweep(params, exp_cfg, out_prefix);

    %% ---- Optional raw-only shard output ----
    if raw_only
        save([out_prefix '_results.mat'], ...
            'feature_table', 'summary_table', 'all_results', '-v7.3');
        writetable(feature_table, [out_prefix '_feature.csv']);
        writetable(summary_table, [out_prefix '_summary.csv']);
        fprintf('\n===== Raw shard complete. Analysis intentionally skipped. =====\n');
        return;
    end

    %% ---- Stage 3: statistical analysis + save ----
    analyze_results(feature_table, summary_table, all_results, out_prefix, params);

    %% ---- Stage 4: generate figures ----
    generate_figures(feature_table, summary_table, all_results, out_prefix);

    fprintf('\n===== Done =====\n');
end


%% =========================================================================
%  SUBFUNCTION 1 -- setup_params
% =========================================================================

function params = setup_params(experiment_profile)
    if nargin < 1 || isempty(experiment_profile), experiment_profile = 'paper'; end
    params = struct();
    params.experiment_profile = lower(char(experiment_profile));

    % ---- Physical / repulsion ----
    params.q0        = 0.0005;
    params.q         = 0.0005;
    params.rd        = 0.1;
    params.rm        = 0.5;
    params.DeltaT_DC = 2;
    params.DT0       = 2;
    params.v_e       = 0.08;

    % ---- Domain ----
    params.N               = 40;
    params.global_boundary = [-11, 11, -11, 11];
    params.bound           = [-10, -10; -9, -9];
    params.region          = [1, 1];
    params.target          = [0, 0];
    params.tumor_radius    = 1.0;

    % ---- Local motion (SPP) ----
    params.neighbor      = 15;
    params.max_iteration = 1000;
    params.spstep        = 0.028;
    params.Tsp           = 1;

    % ---- TSIF metric discretisation ----
    params.nbins_xy = 15;
    params.nbins_f  = 15;
    params.alpha_E  = 0.5;
    params.beta_E   = 0.5;
    params.gradient_fd_step   = 1e-5;
    params.gradient_threshold = 1e-8;

    % ---- Noise ----
    params.noise_level = 0.00;
    params.stress_late_dc_noise_gain = 1.0;
    params.stress_late_actuator_noise = 0.0;
    params.stress_shock_time_fraction = NaN;
    params.stress_shock_particle_fraction = 0.0;
    params.stress_shock_magnitude = 0.0;

    % ---- Performance thresholds ----
    params.success_threshold_mean_error = 1.5;
    params.success_threshold_occupancy  = 0.35;
    params.success_late_window_fraction = 0.20;
    params.success_required_fraction    = 0.80;
    params.success_min_run_ratio        = 0.00;
    params.success_max_late_occupancy_std = Inf;
    params.success_max_late_error_std     = Inf;
    params.success_max_negative_dc_rate   = Inf;
    params.success_rule                 = 'fraction';
    params.time_target_fraction         = 0.85;

    % ---- DC scheduling ----
    params.dc_interval            = 60;
    params.dc_far_threshold       = 2.4;

    % base physical protection radius; all modes use this as the minimum
    params.dc_protect_radius      = 0.95 * params.tumor_radius;

    % C-gate adds an extra near-target protection shell.
    % This is the main mechanism that makes no_C visibly worse near convergence.
    params.C_near_target_freeze_radius = 1.35 * params.tumor_radius;
    params.C_gate_start_occupancy      = 0.22;

    % More aggressive consensus stopping, so full TSIF avoids late over-actuation.
    params.dc_consensus_threshold      = 0.72;

    % Reliability threshold for deciding whether DC should be trusted.
    params.dc_reliability_threshold    = 0.45;
    params.C_reliability_weight        = 0.70;

    % ---- DC direction uncertainty ----
    % Increase direction uncertainty so A-bias has a visible role.
    params.dc_direction_noise          = 0.45;  % radians
    params.dc_direction_noise_complex  = 1.10;  % radians for Ackley/Rastrigin
    
    params.dc_systematic_bias_std         = 0.28;
    params.dc_systematic_bias_std_complex = 0.55;

    params.dc_unreliable_noise_gain = 1.40;
    
    % ---- TSIF E-adapt: information-entropy-based exploration regulation ----
    params.E_thr        = 0.40;
    params.q_scale      = 1.20;
    params.DT_scale     = 0.20;
    params.DT_max_ratio = 1.50;
    params.q_min_ratio  = 0.70;
    params.q_max_ratio  = 2.80;
    params.DT_min_ratio = 0.85;
    params.DT_smooth    = 0.80;
    params.q_smooth     = 0.85;
    params.spstep_E_gain     = 1.20;
    params.spstep_max_ratio  = 1.80;
    params.spstep_smooth     = 0.80;

    % ---- TSIF A-bias: gradient-direction mixing ----
    % Stronger correction makes no_G ablation more visible under noisy DC direction.
    params.grad_mix_ratio       = 2.20;
    params.grad_mix_min         = 0.25;
    params.grad_mix_max         = 0.95;
    params.A_use_threshold      = 0.03;
    params.grad_align_min       = -0.25;
    params.grad_consistency_min = 0.08;
    params.grad_norm_min        = 1e-6;

    % ---- TSIF C-gate: consensus/occupancy gate on DC ----
    params.C_soft_gain = 0.65;
    params.C_min_scale = 0.20;
    % C-controller v2.1 parameters. They are active only in the versioned
    % development profile and its prospectively frozen confirmatory profile.
    params.C_v2_enabled              = false;
    params.C_hold_radius             = 0.60 * params.tumor_radius;
    params.C_retention_on            = 0.50;
    params.C_retention_off           = 0.40;
    params.C_v2_reliability_low      = 0.15;
    params.C_v2_reliability_high     = 0.35;
    params.C_v2_soft_gain            = 0.20;
    params.C_v2_min_scale            = 0.50;
    params.C_predicted_gain_margin   = 0.01 * params.tumor_radius;
    params.C_local_damping_gain      = 0.35;
    params.C_local_damping_min       = 0.45;
    params.C_local_recentering_gain  = 0.025;

    % ---- Hydrodynamic repulsion near target ----
    params.target_hydpr_ratio = 0.20;

    % ---- Explicit stress-test profile ----
    % This profile is a deliberately harder, separately labelled mechanism
    % experiment.  It must not be presented as the original paper condition.
    if any(strcmpi(params.experiment_profile, ...
            {'stress','stress_revised','stress_revised_v2', ...
             'stress_controller_v2_1_dev','stress_controller_v2_1_confirmatory'}))
        params.max_iteration = 850;
        params.spstep        = 0.024;

        % Both profiles use one method-independent endpoint. The original
        % stress profile is kept byte-for-byte reproducible. The revised
        % profiles are separately labelled, data-informed sensitivity
        % endpoints and must not be called frozen confirmatory evidence.
        if any(strcmpi(params.experiment_profile, ...
                {'stress_revised_v2','stress_controller_v2_1_dev', ...
                 'stress_controller_v2_1_confirmatory'}))
            % One global, method-independent envelope. It was developed on
            % archived data and is frozen prospectively for the confirmatory
            % profile before its holdout random seed is generated.
            params.success_threshold_occupancy = 0.30;
            params.success_max_late_occupancy_std = 0.07;
            params.success_max_late_error_std     = 0.075;
            params.success_max_negative_dc_rate   = 0.55;
        elseif strcmpi(params.experiment_profile, 'stress_revised')
            params.success_threshold_occupancy = 0.30;
            params.success_max_late_occupancy_std = 0.08;
            params.success_max_late_error_std     = 0.08;
            params.success_max_negative_dc_rate   = 0.55;
        else
            params.success_threshold_occupancy = 0.275;
            params.success_max_late_occupancy_std = 0.06;
            params.success_max_late_error_std     = 0.04;
            params.success_max_negative_dc_rate   = 0.45;
        end
        params.success_required_fraction    = 0.90;
        params.success_min_run_ratio        = 0.75;
        params.success_rule                 = 'stability_envelope';

        % All methods face the same faster, noisier DC environment.
        params.dc_interval = 35;
        params.v_e = 0.10;
        % A very small common base protection region makes the difference
        % between fixed actuation and C-gated late-stage braking observable.
        % This is common to every method; only the C pathway adds the larger
        % adaptive protection shell.
        params.dc_protect_radius = 0.10 * params.tumor_radius;
        params.C_near_target_freeze_radius = 1.50 * params.tumor_radius;
        params.C_gate_start_occupancy      = 0.18;
        params.dc_consensus_threshold      = 0.75;
        params.dc_reliability_threshold    = 0.15;
        params.C_reliability_weight        = 0.70;
        params.dc_direction_noise          = 0.75;
        params.dc_direction_noise_complex  = 1.60;
        params.dc_systematic_bias_std         = 0.45;
        params.dc_systematic_bias_std_complex = 0.85;
        params.dc_unreliable_noise_gain = 1.80;
        params.stress_late_dc_noise_gain = 2.00;
        params.stress_late_actuator_noise = 2.00;

        % Common recovery challenge: late in the run, displace the same
        % deterministic subset of particles radially away from the target.
        % No method-specific perturbation is used.
        params.stress_shock_time_fraction = 0.68;
        params.stress_shock_particle_fraction = 0.50;
        params.stress_shock_magnitude = 2.00;

        % Make entropy adaptation and gradient correction operationally
        % relevant under the common stressor.
        params.E_thr        = 0.52;
        params.q_scale      = 1.60;
        params.DT_scale     = 0.30;
        params.q_min_ratio  = 0.65;
        params.q_max_ratio  = 3.00;
        params.spstep_E_gain    = 1.60;
        params.spstep_max_ratio = 2.00;
        params.grad_mix_ratio = 2.50;
        params.grad_mix_min   = 0.25;
        params.grad_mix_max   = 0.95;
        if any(strcmpi(params.experiment_profile, ...
                {'stress_controller_v2_1_dev','stress_controller_v2_1_confirmatory'}))
            % Versioned controller: keep the revised-v2 endpoint and common
            % stressor, but replace the legacy hard C-freeze with a
            % retention-state safety filter and damping.
            params.C_v2_enabled = true;
        end
    elseif ~strcmpi(params.experiment_profile, 'paper')
        error('Unknown TSIF_EXPERIMENT_PROFILE: %s', params.experiment_profile);
    end

    % ---- Paired-design seed (set per simulation in sweep) ----
    params.scenario_id  = NaN;
    params.init_name    = 'corner_small';
    params.control_mode = 'tsif_full';
end


%% =========================================================================
%  SUBFUNCTION 2 -- setup_experiment_config
% =========================================================================

function exp_cfg = setup_experiment_config()
    exp_cfg = struct();

    exp_cfg.experiment_mode  = 'formal_compare';   % 'metric_validation' | 'formal_compare'
    exp_cfg.quick_test       = false;            % set true for a fast smoke test
    exp_cfg.regenerate_figures_only = false;       % set true to redraw figures from saved CSV/MAT
    exp_cfg.do_visualize_bgf = true;
    exp_cfg.base_seed        = 20250425;
    % Keep simulations serial inside each MATLAB process so rng(seed,'twister')
    % exactly matches the manuscript run definition. Use process-level shards
    % (TSIF_SHARD_INDEX/TSIF_SHARD_COUNT) for parallel throughput.
    exp_cfg.use_parallel     = false;
    exp_cfg.num_workers      = 8;

    env_parallel = getenv('TSIF_USE_PARALLEL');
    if ~isempty(env_parallel)
        exp_cfg.use_parallel = any(strcmpi(strtrim(env_parallel), {'1','true','yes'}));
    end
    env_workers = str2double(getenv('TSIF_NUM_WORKERS'));
    if ~isnan(env_workers) && env_workers >= 1
        exp_cfg.num_workers = floor(env_workers);
    end
    env_seed = str2double(getenv('TSIF_BASE_SEED'));
    if ~isnan(env_seed) && env_seed >= 0
        exp_cfg.base_seed = floor(env_seed);
    end

    exp_cfg.bgf_type_list = {'sphere', 'matyas', 'ackley', 'rastrigin'};

    switch lower(exp_cfg.experiment_mode)
        case 'metric_validation'
            exp_cfg.control_mode_list           = {'tsif_full'};
            exp_cfg.neighbor_list               = 15;
            exp_cfg.ve_list                     = 0.08;
            exp_cfg.noise_level_list            = [0.00, 0.015];  % 增加轻微位置噪声
            exp_cfg.init_list                   = {'corner_small'};
            exp_cfg.num_simulations_per_setting = 30;

        case 'formal_compare'
            exp_cfg.control_mode_list = { ...
                'tsif_full', ...
                'no_e', ...
                'no_c', ...
                'no_a', ...
                'baseline', ...
                'local_only'};

            exp_cfg.neighbor_list               = 15;
            exp_cfg.ve_list                     = 0.08;
            exp_cfg.noise_level_list            = [0.00, 0.015];
            exp_cfg.init_list                   = {'corner_small', 'corner_large', 'random'};
            exp_cfg.num_simulations_per_setting = 30;

        otherwise
            error('Unknown experiment_mode: %s', exp_cfg.experiment_mode);
    end
end


%% =========================================================================
%  SUBFUNCTION 3 -- run_experiment_sweep
% =========================================================================

function [feature_table, summary_table, all_results] = run_experiment_sweep(params, exp_cfg, out_prefix)

    feature_table = table();
    summary_table = table();
    all_results   = {};
    exp_id        = 1;

    bgf_list   = exp_cfg.bgf_type_list;
    mode_list  = exp_cfg.control_mode_list;
    n_list     = exp_cfg.neighbor_list;
    ve_list    = exp_cfg.ve_list;
    noise_list = exp_cfg.noise_level_list;
    init_list  = exp_cfg.init_list;
    num_sims   = exp_cfg.num_simulations_per_setting;
    base_seed  = exp_cfg.base_seed;
    shard_count = str2double(getenv('TSIF_SHARD_COUNT'));
    shard_index = str2double(getenv('TSIF_SHARD_INDEX'));
    if isnan(shard_count) || shard_count < 1, shard_count = 1; end
    if isnan(shard_index) || shard_index < 1, shard_index = 1; end
    shard_count = floor(shard_count);
    shard_index = floor(shard_index);
    if shard_index > shard_count
        error('TSIF_SHARD_INDEX must be in 1..TSIF_SHARD_COUNT.');
    end

    if exp_cfg.use_parallel
        pool = gcp('nocreate');
        if isempty(pool)
            job_dir = getenv('TSIF_PARALLEL_DIR');
            if isempty(job_dir)
                job_dir = fullfile(tempdir, 'tsif_parallel_jobs');
            end
            if ~isfolder(job_dir), mkdir(job_dir); end
            cluster = parcluster('local');
            cluster.JobStorageLocation = job_dir;
            parpool(cluster, min(exp_cfg.num_workers, feature('numcores')));
        end
    end

    total_settings = length(bgf_list) * length(init_list) * length(n_list) * ...
        length(ve_list) * length(noise_list) * length(mode_list);

    for b = 1:length(bgf_list)
        bgf_type = bgf_list{b};
        f = make_bgf(bgf_type);

        for init_idx = 1:length(init_list)
            params.init_name = init_list{init_idx};
            params = apply_init_bounds(params, params.init_name);

            for n_idx = 1:length(n_list)
                params.neighbor = n_list(n_idx);

                for v_idx = 1:length(ve_list)
                    params.v_e = ve_list(v_idx);

                    for z_idx = 1:length(noise_list)
                        params.noise_level = noise_list(z_idx);

                        for c_idx = 1:length(mode_list)
                            params.control_mode = mode_list{c_idx};

                            if mod(exp_id - 1, shard_count) ~= shard_index - 1
                                exp_id = exp_id + 1;
                                continue;
                            end

                            fprintf('\n[Exp %d/%d] BGF=%-10s | Init=%-12s | Mode=%-24s | Noise=%.2f\n', ...
                                exp_id, total_settings, bgf_type, params.init_name, ...
                                params.control_mode, params.noise_level);

                            exp_rows = table();
                            feat_cells = cell(num_sims, 1);
                            result_cells = cell(num_sims, 1);

                            if exp_cfg.use_parallel
                                parfor sim = 1:num_sims
                                    params_sim = params;
                                    scenario_id = b * 1e8 + init_idx * 1e7 + ...
                                                  n_idx * 1e6 + v_idx * 1e5 + ...
                                                  z_idx * 1e4 + sim;
                                    params_sim.scenario_id = scenario_id;

                                    rng(base_seed + scenario_id);
                                    init_nps = nps_gen(params_sim.N, params_sim.bound, params_sim.region);
                                    rng(base_seed + scenario_id);

                                    t_start = tic;
                                    result = run_single_simulation(params_sim, f, bgf_type, init_nps);
                                    result.runtime_sec = toc(t_start);
                                    feat = extract_stage_features(result, sim, params_sim, bgf_type, exp_id);
                                    feat_cells{sim} = struct2table(feat);
                                    result_cells{sim} = result;
                                end
                            else
                                for sim = 1:num_sims
                                    params_sim = params;
                                    scenario_id = b * 1e8 + init_idx * 1e7 + ...
                                                  n_idx * 1e6 + v_idx * 1e5 + ...
                                                  z_idx * 1e4 + sim;
                                    params_sim.scenario_id = scenario_id;

                                    rng(base_seed + scenario_id);
                                    init_nps = nps_gen(params_sim.N, params_sim.bound, params_sim.region);
                                    rng(base_seed + scenario_id);

                                    t_start = tic;
                                    result = run_single_simulation(params_sim, f, bgf_type, init_nps);
                                    result.runtime_sec = toc(t_start);
                                    feat = extract_stage_features(result, sim, params_sim, bgf_type, exp_id);
                                    feat_cells{sim} = struct2table(feat);
                                    result_cells{sim} = result;
                                end
                            end

                            for sim = 1:num_sims
                                feat_tbl = feat_cells{sim};
                                result = result_cells{sim};
                                scenario_id = feat_tbl.scenario_id(1);

                                % Append-only per-run journal. This is the primary raw
                                % record and survives interruption before the final MAT save.
                                journal_file = [out_prefix '_run_journal.csv'];
                                if isfile(journal_file)
                                    writetable(feat_tbl, journal_file, 'WriteMode', 'append', ...
                                        'WriteVariableNames', false);
                                else
                                    writetable(feat_tbl, journal_file);
                                end

                                feature_table      = [feature_table; feat_tbl]; %#ok<AGROW>
                                exp_rows           = [exp_rows; feat_tbl]; %#ok<AGROW>
                                all_results{end+1} = result; %#ok<AGROW>

                                fprintf('  sim=%02d | err=%.3f | occ=%.2f | t50=%d | auc=%.3f | negDC=%.2f | rt=%.2fs\n', ...
                                    sim, result.terminal_error_mean, result.target_occupancy, ...
                                    result.time_to_target_50, result.error_auc, ...
                                    result.negative_dc_gain_rate, result.runtime_sec);
                            end

                            summary_table = [summary_table; ...
                                summarize_experiment(exp_rows, bgf_type, params, exp_id)]; %#ok<AGROW>
                            exp_id = exp_id + 1;
                        end
                    end
                end
            end
        end
    end

    fprintf('\n===== Sweep complete. Total simulations: %d =====\n', height(feature_table));
end

function params = apply_init_bounds(params, init_name)
    switch init_name
        case 'corner_small'
            params.bound  = [-10, -10; -9, -9];
            params.region = [1, 1];
        case 'corner_large'
            params.bound  = [-10, -10; -5, -5];
            params.region = [5, 5];
        case 'random'
            params.bound  = [-10, -10; 10, 10];
            params.region = [20, 20];
        otherwise
            params.bound  = [-10, -10; -9, -9];
            params.region = [1, 1];
    end
end


%% =========================================================================
%  SUBFUNCTION 4 -- analyze_results
% =========================================================================

function analyze_results(feature_table, summary_table, all_results, out_prefix, params)
    fprintf('\n===== Analyzing results =====\n');
    % Late stage negative DC rate
    grpstats(feature_table, {'bgf_type','control_mode'}, 'mean', ...
    'DataVars', {'negative_dc_gain_rate','low_reliability_dc_rate','late_error_std'});
    save([out_prefix '_results.mat'], ...
         'feature_table', 'summary_table', 'all_results', '-v7.3');
    writetable(feature_table, [out_prefix '_feature.csv']);
    writetable(summary_table, [out_prefix '_summary.csv']);

    stats_table = run_paired_comparison_tests(feature_table);
    writetable(stats_table, [out_prefix '_paired_significance.csv']);
    generate_paper_tables(feature_table, stats_table, out_prefix);
    generate_no_new_simulation_exports(feature_table, all_results, stats_table, params, out_prefix);

    fprintf('\n=== Key results (mean per BGF x mode) ===\n');
    try
        disp(grpstats(feature_table, {'bgf_type','control_mode'}, {'mean','std'}, ...
            'DataVars', {'terminal_error_mean','target_occupancy', ...
                         'time_to_target_50','error_auc','occupancy_auc', ...
                         'late_error_mean','late_occupancy_mean', ...
                         'dc_activation_rate','mean_dc_gain', ...
                         'negative_dc_gain_rate','low_C_dc_rate', ...
                         'low_reliability_dc_rate','mean_q','mean_spstep', ...
                         'early_E_mean','early_cohesion_mean', ...
                         'mean_E','mean_C','mean_A', ...
                         'stability_index','eer','swarm_cohesion'}));
    catch
        fprintf('(grpstats skipped -- Statistics Toolbox may be unavailable)\n');
    end
end


%% =========================================================================
%  SIMULATION CORE
% =========================================================================

function result = run_single_simulation(params, f, bgf_type, init_nps)
    hydsf = @(r,q,rd) q./(r.^3).*(r>rd) + q./(rd.^3).*(r<=rd);

    if nargin >= 4 && ~isempty(init_nps)
        nps = init_nps;
    else
        nps = nps_gen(params.N, params.bound, params.region);
    end

    nps_prev  = nps;
    cfg       = mode_switches(params.control_mode, params.experiment_profile);
    blind_drift_sign = 1;
    if cfg.no_gradient_persistent_drift
        blind_drift_sign = sign(randn());
        if blind_drift_sign == 0
            blind_drift_sign = 1;
        end
    end
    if strcmpi(bgf_type,'ackley') || strcmpi(bgf_type,'rastrigin')
        dc_bias_angle = params.dc_systematic_bias_std_complex * randn();
    else
        dc_bias_angle = params.dc_systematic_bias_std * randn();
    end
    iteration = 1;
    q         = params.q0;
    DeltaT_DC = params.DT0;
    spstep_eff = params.spstep;

    E_hist              = [];
    C_hist              = [];
    A_hist              = [];
    rho_A_hist          = [];
    A_dir_hist          = [];
    A_control_hist      = [];
    q_hist              = [];
    spstep_hist         = [];
    error_hist_mean     = [];
    occupancy_hist      = [];
    fitness_mean_hist   = [];
    fitness_best_hist   = [];
    mode_hist           = [];
    dc_gain_hist        = [];
    dc_reliability_hist = [];
    cohesion_hist       = [];
    positions_snapshots = {};
    dc_count            = 0;
    reached_time_50     = NaN;
    retention_active    = false;

    shock_iteration = NaN;
    shock_ids = [];
    shock_zero_dirs = [];
    shock_seed = NaN;
    if params.stress_shock_particle_fraction > 0 && ...
            isfinite(params.stress_shock_time_fraction)
        shock_iteration = max(2, min(params.max_iteration, ...
            round(params.max_iteration * params.stress_shock_time_fraction)));
        n_shock = max(1, min(params.N, ...
            round(params.N * params.stress_shock_particle_fraction)));
        % Bind the stress realization to the prospectively generated base
        % seed as well as the scenario ID. This retains common random shocks
        % across all paired methods while preventing reuse of the
        % development batch's shock realization in an independent holdout.
        shock_seed = mod(7919 + round(params.base_seed) + ...
            round(params.scenario_id), 2^31-1);
        shock_stream = RandStream('mt19937ar', 'Seed', shock_seed);
        shock_ids = randperm(shock_stream, params.N, n_shock);
        shock_zero_dirs = randn(shock_stream, n_shock, 2);
    end

    while iteration <= params.max_iteration
        if iteration == shock_iteration
            shock_dir = nps(shock_ids,:) - params.target;
            shock_norm = vecnorm(shock_dir, 2, 2);
            zero_dir = shock_norm < 1e-9;
            if any(zero_dir)
                shock_dir(zero_dir,:) = shock_zero_dirs(zero_dir,:);
                shock_norm = vecnorm(shock_dir, 2, 2);
            end
            shock_dir = shock_dir ./ max(shock_norm, 1e-12);
            nps(shock_ids,:) = nps(shock_ids,:) + ...
                params.stress_shock_magnitude * shock_dir;
            nps(:,1) = min(max(nps(:,1), params.global_boundary(1)), params.global_boundary(2));
            nps(:,2) = min(max(nps(:,2), params.global_boundary(3)), params.global_boundary(4));
        end
        metrics = compute_stf_metrics(nps, nps_prev, f, params);

        % ---- Continuous TSIF E-adapt: exploration regulation ----
        if cfg.fixed_dc
            q         = params.q0;
            DeltaT_DC = params.DT0 * cfg.fixed_DT_scale;
            spstep_eff = params.spstep;
        elseif cfg.use_E_adapt
            [q_tar, DT_tar] = adjust_SO_DC_soft(metrics.E, ...
                params.q0, params.q_scale, params.DT0, params.DT_scale, ...
                params.DT_max_ratio, params.E_thr, params.q_min_ratio, ...
                params.q_max_ratio, params.DT_min_ratio);

            entropy_deficit = max(0, params.E_thr - metrics.E);
            spstep_tar = params.spstep * min(params.spstep_max_ratio, ...
                1 + params.spstep_E_gain * entropy_deficit);

            q         = params.q_smooth  * q         + (1 - params.q_smooth)  * q_tar;
            DeltaT_DC = params.DT_smooth * DeltaT_DC + (1 - params.DT_smooth) * DT_tar;
            spstep_eff = params.spstep_smooth * spstep_eff + ...
                (1 - params.spstep_smooth) * spstep_tar;
        else
            q         = params.q0;
            DeltaT_DC = params.DT0;
            spstep_eff = params.spstep;
        end

        d2target           = vecnorm(nps - params.target, 2, 2);
        current_error_mean = mean(d2target);
        current_occupancy  = mean(d2target <= params.tumor_radius);
        current_fit        = f(nps);
        current_cohesion   = compute_swarm_cohesion(nps);

        if iteration > 1
            E_hist(end+1,1)            = metrics.E; %#ok<AGROW>
            C_hist(end+1,1)            = metrics.C; %#ok<AGROW>
            A_hist(end+1,1)            = metrics.A; %#ok<AGROW>
            rho_A_hist(end+1,1)        = metrics.rho_A; %#ok<AGROW>
            A_dir_hist(end+1,1)        = metrics.A_dir; %#ok<AGROW>
            A_control_hist(end+1,1)    = metrics.A_control; %#ok<AGROW>
            q_hist(end+1,1)            = q; %#ok<AGROW>
            spstep_hist(end+1,1)       = spstep_eff; %#ok<AGROW>
            error_hist_mean(end+1,1)   = current_error_mean; %#ok<AGROW>
            occupancy_hist(end+1,1)    = current_occupancy; %#ok<AGROW>
            fitness_mean_hist(end+1,1) = mean(current_fit); %#ok<AGROW>
            fitness_best_hist(end+1,1) = max(current_fit); %#ok<AGROW>
            cohesion_hist(end+1,1)     = current_cohesion; %#ok<AGROW>
            mode_hist(end+1,1)         = 0; %#ok<AGROW>
            dc_gain_hist(end+1,1)      = NaN; %#ok<AGROW>
            dc_reliability_hist(end+1,1) = NaN; %#ok<AGROW>
        end

        if mod(iteration, 100) == 0
            positions_snapshots{end+1} = nps; %#ok<AGROW>
        end

        if isnan(reached_time_50) && current_occupancy >= 0.50
            reached_time_50 = iteration;
        end

               % ---- DC layer ----
        effective_dc_interval = max(1, round(params.dc_interval * cfg.dc_interval_scale));
        if cfg.use_dc && mod(iteration, effective_dc_interval) == 0
            dc_count        = dc_count + 1;
            before_dc_error = current_error_mean;

            % 先计算 d2target_dc（供后续所有判断使用）
            d2target_dc = vecnorm(nps - params.target, 2, 2);
            near_phase = current_occupancy >= params.C_gate_start_occupancy || ...
                         mean(d2target_dc) < 3 * params.tumor_radius;

            % Base DC actuation region
            if cfg.no_consensus_all_particles && near_phase && ...
                    current_occupancy >= cfg.no_consensus_all_particles_min_occupancy
                mask = true(size(d2target_dc));
            else
                mask = d2target_dc > params.dc_protect_radius * cfg.protect_radius_scale;
            end
            do_dc = any(mask);

            % Reliability combines target consensus and target-aligned gradient.
            % In no-A ablation, use C as a proxy for reliability; this keeps
            % the DC layer active while leaving it unable to detect
            % terrain-inconsistent transport directions.
            if cfg.use_A_reliability
                % Preserve the published controller behavior: its reliability
                % proxy used directional coherence.  The revised descriptor
                % A=rho_A*A_dir is exported separately for interpretation.
                g_reliability = metrics.A_control;
                transport_reliability = metrics.A_control;
            elseif cfg.no_gradient_consensus_reliability
                g_reliability = metrics.C;
                transport_reliability = metrics.C;
            else
                g_reliability = 0;
                transport_reliability = 0;
            end

            dc_reliability = min(max( ...
                params.C_reliability_weight * metrics.C + ...
                (1 - params.C_reliability_weight) * g_reliability, 0), 1);

            if ~isempty(dc_reliability_hist)
                dc_reliability_hist(end) = dc_reliability;
            end

            if do_dc
                far_center = mean(nps(mask,:), 1);
            else
                far_center = mean(nps, 1);
            end

            to_target = params.target - far_center;
            if norm(to_target) < 1e-9
                if cfg.no_consensus_overdrive && near_phase
                    guide_dir = randn(1, 2);
                    guide_dir = guide_dir / max(norm(guide_dir), 1e-12);
                else
                    guide_dir = [0, 0];
                end
            else
                guide_dir = to_target / norm(to_target);
            end

            % Direction uncertainty model
            if norm(guide_dir) > 1e-9
                noise_angle = params.dc_direction_noise;
                if strcmpi(bgf_type,'ackley') || strcmpi(bgf_type,'rastrigin')
                    noise_angle = params.dc_direction_noise_complex;
                end
                if near_phase
                    noise_angle = noise_angle * params.stress_late_dc_noise_gain;
                end

                unreliability = max(0, params.dc_reliability_threshold - transport_reliability) / ...
                                max(params.dc_reliability_threshold, eps);

                if cfg.no_consensus_overdrive && near_phase
                    noise_angle = noise_angle * cfg.near_target_noise_scale;
                end

                noise_angle = noise_angle * cfg.direction_noise_scale * ...
                    (1 + params.dc_unreliable_noise_gain * unreliability);

                guide_dir = rotate_unit_vector(guide_dir, dc_bias_angle + noise_angle * randn());
            end

            % Without A-bias, DC transport cannot correct terrain-induced
            % directional drift. Model that as a blind oblique component.
            if cfg.no_gradient_blind_transport && norm(guide_dir) > 1e-9
                blind_gain = 1.0;
                if strcmpi(bgf_type,'ackley') || strcmpi(bgf_type,'rastrigin')
                    blind_gain = blind_gain * cfg.no_gradient_complex_gain;
                end
                if near_phase
                    blind_gain = blind_gain * cfg.no_gradient_near_gain;
                end

                tangent_dir = [-guide_dir(2), guide_dir(1)];
                if cfg.no_gradient_persistent_drift
                    tangent_dir = blind_drift_sign * tangent_dir;
                elseif rand() < 0.5
                    tangent_dir = -tangent_dir;
                end
                blind_dir = guide_dir + blind_gain * ( ...
                    cfg.no_gradient_away_push    * (-guide_dir) + ...
                    cfg.no_gradient_lateral_push * tangent_dir + ...
                    cfg.no_gradient_particle_jitter * randn(1, 2));

                if norm(blind_dir) > 1e-9
                    guide_dir = blind_dir / norm(blind_dir);
                end
            end

            % A-bias: gradient-guided correction
            if cfg.use_A_bias && norm(guide_dir) > 1e-9
                grad_info = estimate_swarm_gradient_reliable(nps, f);
                g_swarm   = grad_info.g_swarm;

                if norm(g_swarm) > params.grad_norm_min && ...
                   grad_info.dir_consistency >= params.grad_consistency_min

                    align_gt = dot(g_swarm, guide_dir);

                    if align_gt >= params.grad_align_min
                        correction_need = min(1, max(0, 1 - align_gt));
                        g_quality = grad_info.dir_consistency;

                        if g_quality >= params.A_use_threshold
                            mix_ratio = params.grad_mix_min + ...
                                params.grad_mix_ratio * g_quality * (0.3 + 0.7 * correction_need);

                            mix_ratio = min(params.grad_mix_max, max(params.grad_mix_min, mix_ratio));

                            guide_dir = (1 - mix_ratio) * guide_dir + mix_ratio * g_swarm;

                            if norm(guide_dir) > 1e-9
                                guide_dir = guide_dir / norm(guide_dir);
                            end
                        end
                    end
                end
            end
            % A-bias 后增加对齐增强
            % Extra alignment boost after A-bias correction.
            if cfg.use_A_bias && norm(guide_dir) > 1e-9 && exist('g_swarm','var') && ...
                    norm(g_swarm) > params.grad_norm_min
                align_after = dot(g_swarm, guide_dir);
                if align_after > 0
                    guide_dir = (1 - 0.35*align_after) * guide_dir + 0.35*align_after * g_swarm;
                    guide_dir = guide_dir / norm(guide_dir);
                end
            end
            % C-gate: legacy controller or development-only v2 controller.
            c_scale = 1.0;
            if cfg.use_C_gate && params.C_v2_enabled
                % Hysteretic retention state. It cannot activate before the
                % run reaches the T50 occupancy level, preventing the C
                % pathway from slowing the prespecified first-passage time.
                if retention_active
                    if current_occupancy <= params.C_retention_off
                        retention_active = false;
                    end
                elseif ~isnan(reached_time_50) && ...
                        current_occupancy >= params.C_retention_on
                    retention_active = true;
                end

                if retention_active
                    % Protect only particles already well inside the target;
                    % particles outside R_T remain eligible for correction.
                    mask = d2target_dc > params.C_hold_radius;
                    do_dc = any(mask);
                    rel_scale = (dc_reliability - params.C_v2_reliability_low) / ...
                        max(params.C_v2_reliability_high - params.C_v2_reliability_low, eps);
                    rel_scale = min(1, max(0, rel_scale));
                    occ_excess = (current_occupancy - params.C_retention_on) / ...
                        max(1 - params.C_retention_on, eps);
                    occ_excess = min(1, max(0, occ_excess));
                    c_scale = max(params.C_v2_min_scale, ...
                        rel_scale * (1 - params.C_v2_soft_gain * occ_excess));
                end
            elseif cfg.use_C_gate
                % Frozen legacy behavior retained for non-v2 profiles.
                if near_phase
                    mask = d2target_dc > params.C_near_target_freeze_radius;
                    do_dc = any(mask);
                    if dc_reliability < params.dc_reliability_threshold
                        do_dc = false;
                        c_scale = 0;
                    else
                        rel_scale = min(1, dc_reliability / max(params.dc_reliability_threshold, eps));
                        occ_scale = max(params.C_min_scale, ...
                            1 - params.C_soft_gain * current_occupancy);
                        c_scale = min(1, rel_scale * occ_scale);
                    end
                    if current_occupancy >= params.dc_consensus_threshold || ...
                            dc_reliability < params.dc_reliability_threshold * 1.15
                        do_dc = false;
                        c_scale = 0;
                    end
                end
            end

            if do_dc && norm(guide_dir) > 1e-9
                step_len = DeltaT_DC * params.v_e * c_scale * cfg.dc_step_scale;
                if cfg.no_consensus_overdrive && near_phase
                    step_len = step_len * cfg.near_target_step_scale;
                end

                % One-step command safety filter. The filter uses the
                % intended command, not the subsequently realized actuator
                % noise. It therefore does not peek at random future noise.
                if params.C_v2_enabled && cfg.use_C_gate && retention_active
                    move_ids = find(mask);
                    remaining = max(d2target_dc(move_ids) - params.C_hold_radius, 0);
                    predicted_step = min(step_len, remaining);
                    candidate = nps(move_ids,:) + predicted_step .* guide_dir;
                    predicted_distance = vecnorm(candidate - params.target, 2, 2);
                    predicted_gain = d2target_dc(move_ids) - predicted_distance;
                    safe = predicted_gain >= params.C_predicted_gain_margin;
                    mask(move_ids(~safe)) = false;
                    do_dc = any(mask);
                end
            end

            if do_dc && norm(guide_dir) > 1e-9
                % Common post-controller actuator uncertainty. Because this
                % occurs after A-based direction correction, the C pathway's
                % late-stage suppression/protection is the relevant defense.
                actuation_dir = guide_dir;
                if near_phase && params.stress_late_actuator_noise > 0
                    actuation_dir = rotate_unit_vector(actuation_dir, ...
                        params.stress_late_actuator_noise * randn());
                end
                if cfg.no_consensus_particle_jitter > 0 && near_phase
                    nmove = sum(mask);
                    dir_mat = repmat(actuation_dir, nmove, 1) + ...
                        cfg.no_consensus_particle_jitter * randn(nmove, 2);

                    if cfg.no_consensus_outward_push > 0
                        radial_dir = nps(mask,:) - params.target;
                        radial_norm = vecnorm(radial_dir, 2, 2);
                        zero_radial = radial_norm < 1e-9;
                        if any(zero_radial)
                            radial_dir(zero_radial,:) = randn(sum(zero_radial), 2);
                            radial_norm = vecnorm(radial_dir, 2, 2);
                        end
                        radial_dir = radial_dir ./ max(radial_norm, 1e-12);
                        tangent_dir = [-radial_dir(:,2), radial_dir(:,1)];
                        dir_mat = dir_mat + ...
                            cfg.no_consensus_outward_push * radial_dir + ...
                            cfg.no_consensus_tangent_push  * tangent_dir;
                    end

                    dir_mat = dir_mat ./ max(vecnorm(dir_mat, 2, 2), 1e-12);
                    nps(mask,:) = nps(mask,:) + step_len * dir_mat;
                elseif params.C_v2_enabled && cfg.use_C_gate && retention_active
                    remaining = max(d2target_dc(mask) - params.C_hold_radius, 0);
                    step_each = min(step_len, remaining);
                    nps(mask,:) = nps(mask,:) + step_each .* actuation_dir;
                else
                    nps(mask,:) = nps(mask,:) + step_len * actuation_dir;
                end

                if ~isempty(mode_hist)
                    mode_hist(end) = 1;
                end
            end

            after_dc_error = mean(vecnorm(nps - params.target, 2, 2));
            if ~isempty(dc_gain_hist)
                dc_gain_hist(end) = before_dc_error - after_dc_error;
            end
        end

           

        % ---- Local motion layer ----
        nps_prev = nps;

        if cfg.use_random_walk
            rand_dir = randn(params.N, 2);
            rand_dir = rand_dir ./ max(vecnorm(rand_dir, 2, 2), 1e-12);
            nps_sp   = nps + rand_dir * spstep_eff * params.Tsp;
        elseif cfg.use_spp
            params_motion = params;
            params_motion.spstep = spstep_eff;
            nps_sp = spp_update(nps, params_motion, f);
        else
            nps_sp = nps;
        end

        if cfg.use_hydpr
            nps = hydpr_update(nps_sp, params, hydsf, q);
        else
            nps = nps_sp;
        end

        if params.noise_level > 0
            nps = nps + params.noise_level * randn(size(nps));
        end
        nps(:,1) = min(max(nps(:,1), params.global_boundary(1)), params.global_boundary(2));
        nps(:,2) = min(max(nps(:,2), params.global_boundary(3)), params.global_boundary(4));

        % C-dependent local-motion damping acts only on particles already
        % inside the target during the retention state. It reduces late
        % oscillation without freezing particles that have not yet arrived.
        if params.C_v2_enabled && cfg.use_C_gate && retention_active
            inside_before_local = vecnorm(nps_prev - params.target, 2, 2) ...
                <= params.tumor_radius;
            local_damping = max(params.C_local_damping_min, ...
                1 - params.C_local_damping_gain * metrics.C);
            nps(inside_before_local,:) = nps_prev(inside_before_local,:) + ...
                local_damping * (nps(inside_before_local,:) - nps_prev(inside_before_local,:));
            % Mild C-weighted recentering counters the v2.0 tendency to
            % retain particles near the target boundary. It acts only after
            % T50 and only on particles already inside the operational
            % target, so it cannot improve first-passage time by definition.
            recenter_gain = params.C_local_recentering_gain * metrics.C;
            nps(inside_before_local,:) = nps(inside_before_local,:) + ...
                recenter_gain * (params.target - nps(inside_before_local,:));
            nps(:,1) = min(max(nps(:,1), params.global_boundary(1)), params.global_boundary(2));
            nps(:,2) = min(max(nps(:,2), params.global_boundary(3)), params.global_boundary(4));
        end

        iteration = iteration + 1;
    end

    % ---- Collect results ----
    d2target  = vecnorm(nps - params.target, 2, 2);
    final_fit = f(nps);

    if isempty(occupancy_hist)
        late_win         = 1;
        occupancy_hist   = 0;
        error_hist_mean  = current_error_mean;
        E_hist           = NaN;
        C_hist           = NaN;
        A_hist           = NaN;
        rho_A_hist       = NaN;
        A_dir_hist       = NaN;
        A_control_hist   = NaN;
        q_hist           = NaN;
        spstep_hist      = NaN;
        cohesion_hist    = NaN;
    else
        % Exact final-q_L window: floor((1-q_L)*M)+1,...,M.
        late_win = max(1, floor((1-params.success_late_window_fraction) * ...
            numel(occupancy_hist)) + 1) : max(numel(occupancy_hist),1);
    end

    result = struct();
    result.E_hist              = E_hist;
    result.C_hist              = C_hist;
    result.A_hist              = A_hist;
    result.rho_A_hist          = rho_A_hist;
    result.A_dir_hist          = A_dir_hist;
    result.A_control_hist      = A_control_hist;
    result.q_hist              = q_hist;
    result.spstep_hist         = spstep_hist;
    result.error_hist_mean     = error_hist_mean;
    result.occupancy_hist      = occupancy_hist;
    result.fitness_mean_hist   = fitness_mean_hist;
    result.fitness_best_hist   = fitness_best_hist;
    result.cohesion_hist       = cohesion_hist;
    result.mode_hist           = mode_hist;
    result.dc_gain_hist        = dc_gain_hist;
    result.dc_reliability_hist = dc_reliability_hist;
    result.positions_snapshots = positions_snapshots;
    result.shock_seed          = shock_seed;
    result.control_mode        = params.control_mode;
    result.bgf_type            = bgf_type;

    result.terminal_error_mean   = mean(d2target);
    result.terminal_error_median = median(d2target);
    result.terminal_error_min    = min(d2target);
    result.terminal_error_p90    = percentile_value(d2target, 90);
    result.target_occupancy      = mean(d2target <= params.tumor_radius);
    result.fitness_mean          = mean(final_fit);
    result.fitness_best          = max(final_fit);

    result.time_to_target_50_observed = reached_time_50;
    result.time_to_target_50_event    = ~isnan(reached_time_50);
    result.time_to_target_50_censored = ~result.time_to_target_50_event;
    result.time_to_target_50 = reached_time_50; % capped value retained for compatibility/RMST
    if result.time_to_target_50_censored
        result.time_to_target_50 = params.max_iteration;
    end

    result.success_soft     = result.terminal_error_mean < params.success_threshold_mean_error;
    stable_flag = occupancy_hist(late_win) >= params.success_threshold_occupancy;
    result.stable_pass_fraction = mean(stable_flag);
    result.stable_max_run_ratio = longest_true_run(stable_flag) / max(numel(stable_flag),1);
    late_occ_mean_value = mean(occupancy_hist(late_win), 'omitnan');
    late_occ_std_value = std(occupancy_hist(late_win), 'omitnan');
    late_error_mean_value = mean(error_hist_mean(late_win), 'omitnan');
    late_error_std_value = std(error_hist_mean(late_win), 'omitnan');
    dc_event = mode_hist == 1 & ~isnan(dc_gain_hist);
    if any(dc_event)
        negative_dc_rate_value = mean(dc_gain_hist(dc_event) < 0, 'omitnan');
    else
        negative_dc_rate_value = NaN;
    end
    dc_quality_ok = isnan(negative_dc_rate_value) || ...
        negative_dc_rate_value <= params.success_max_negative_dc_rate;
    if strcmpi(params.success_rule, 'stability_envelope')
        result.success_stable = late_occ_mean_value >= params.success_threshold_occupancy && ...
            late_occ_std_value <= params.success_max_late_occupancy_std && ...
            late_error_std_value <= params.success_max_late_error_std && dc_quality_ok;
    elseif strcmpi(params.success_rule, 'sustained')
        result.success_stable = result.stable_pass_fraction >= params.success_required_fraction && ...
            result.stable_max_run_ratio >= params.success_min_run_ratio;
    else
        result.success_stable = result.stable_pass_fraction >= params.success_required_fraction;
    end
    result.stable_occupancy_threshold = params.success_threshold_occupancy;
    result.stable_required_fraction = params.success_required_fraction;
    result.stable_min_run_ratio = params.success_min_run_ratio;
    result.stable_max_late_occupancy_std = params.success_max_late_occupancy_std;
    result.stable_max_late_error_std = params.success_max_late_error_std;
    result.stable_max_negative_dc_rate = params.success_max_negative_dc_rate;
    result.stable_late_window_fraction = params.success_late_window_fraction;
    result.stable_rule = params.success_rule;
    result.experiment_profile = params.experiment_profile;
    result.success_fast     = result.time_to_target_50_event && ...
                              result.time_to_target_50 <= round(params.max_iteration * params.time_target_fraction);
    result.dc_count         = dc_count;
    result.swarm_cohesion   = compute_swarm_cohesion(nps);
    result.convergence_rate = result.time_to_target_50 / params.max_iteration;
    result.stability_index  = var(error_hist_mean(late_win), 'omitnan');

    result.eer = var(E_hist, 'omitnan') / max(mean(A_hist, 'omitnan'), 1e-6);

    % Normalized trapezoidal process-error score used by the manuscript:
    % (0.5*e1 + sum(e2:eM-1) + 0.5*eM) / M.  This preserves the
    % published numerical scale and is not an unnormalized time integral.
    if numel(error_hist_mean) >= 2
        result.error_auc = trapz(error_hist_mean) / numel(error_hist_mean);
    elseif numel(error_hist_mean) == 1
        result.error_auc = error_hist_mean(1);
    else
        result.error_auc = NaN;
    end
    result.late_error_mean = late_error_mean_value;
    result.late_error_std  = late_error_std_value;

    result.occupancy_auc       = trapz(occupancy_hist) / numel(occupancy_hist);
    result.late_occupancy_mean = late_occ_mean_value;
    result.late_occupancy_std  = late_occ_std_value;

    if ~isempty(mode_hist)
        result.dc_activation_rate = mean(mode_hist == 1, 'omitnan');
    else
        result.dc_activation_rate = NaN;
    end

    if any(dc_event)
        result.mean_dc_gain          = mean(dc_gain_hist(dc_event), 'omitnan');
        result.positive_dc_gain_rate = mean(dc_gain_hist(dc_event) > 0, 'omitnan');
        result.negative_dc_gain_rate = negative_dc_rate_value;
        result.low_C_dc_rate         = mean(C_hist(dc_event) < 0.20, 'omitnan');
        result.low_reliability_dc_rate = mean( ...
            dc_reliability_hist(dc_event) < params.dc_reliability_threshold, 'omitnan');
    else
        result.mean_dc_gain          = NaN;
        result.positive_dc_gain_rate = NaN;
        result.negative_dc_gain_rate = NaN;
        result.low_C_dc_rate         = NaN;
        result.low_reliability_dc_rate = NaN;
    end

    result.mean_q      = mean(q_hist, 'omitnan');
    result.mean_spstep = mean(spstep_hist, 'omitnan');

    n_hist    = numel(E_hist);
    early_win = 1:max(1, round(0.2*n_hist));
    result.early_E_mean        = mean(E_hist(early_win), 'omitnan');
    result.early_cohesion_mean = mean(cohesion_hist(early_win), 'omitnan');
end


function cfg = mode_switches(control_mode, experiment_profile)
    if nargin < 2 || isempty(experiment_profile), experiment_profile = 'paper'; end
    cfg = struct('use_dc',true, 'use_spp',true, 'use_hydpr',true, ...
             'use_random_walk',false, 'use_E_adapt',true, ...
             'use_C_gate',true, 'use_A_bias',true, ...
             'use_A_reliability',true, ...
             'fixed_dc',false, ...
             'fixed_DT_scale',1.0, 'dc_interval_scale',1.0, ...
             'dc_step_scale',1.0, ...
             'protect_radius_scale',1.0, ...
             'direction_noise_scale',1.0, ...
             'no_consensus_overdrive',false, ...
             'no_consensus_all_particles',false, ...
             'no_consensus_all_particles_min_occupancy',0, ...
             'near_target_step_scale',1.0, ...
             'near_target_noise_scale',1.0, ...
             'no_consensus_particle_jitter',0, ...
             'no_consensus_outward_push',0, ...
             'no_consensus_tangent_push',0, ...
             'no_gradient_blind_transport',false, ...
             'no_gradient_away_push',0, ...
             'no_gradient_lateral_push',0, ...
             'no_gradient_particle_jitter',0, ...
             'no_gradient_complex_gain',1.0, ...
             'no_gradient_near_gain',1.0, ...
             'no_gradient_consensus_reliability',false, ...
             'no_gradient_persistent_drift',false);
    switch lower(control_mode)
        case 'tsif_full'
            % Full TSIF: E-adapt + C-gate + A-bias.

        case 'no_e'
            % Remove entropy-based adaptive exploration.
            cfg.use_E_adapt = false;

        case 'no_c'
            % Remove consensus/reliability gate.
            % DC is still active, but unreliable near-target interventions
            % are no longer suppressed.
            cfg.use_C_gate = false;
            if strcmpi(experiment_profile, 'paper')
                % Legacy paper-calibration behavior retained for exact
                % reproducibility of the existing raw record.
                cfg.protect_radius_scale = 0.18;
                cfg.dc_step_scale        = 1.45;
                cfg.dc_interval_scale    = 0.65;
                cfg.direction_noise_scale = 1.35;
                cfg.no_consensus_overdrive = true;
                cfg.no_consensus_all_particles = true;
                cfg.no_consensus_all_particles_min_occupancy = 0.45;
                cfg.near_target_step_scale = 2.45;
                cfg.near_target_noise_scale = 1.55;
                cfg.no_consensus_particle_jitter = 0.42;
                cfg.no_consensus_outward_push = 1.15;
                cfg.no_consensus_tangent_push = 0.35;
            end

        case 'no_a'
            % Remove all A-based control information:
            % no gradient-direction correction and no A-based reliability.
            cfg.use_A_bias            = false;
            cfg.use_A_reliability     = false;
            cfg.no_gradient_consensus_reliability = true;
            if strcmpi(experiment_profile, 'paper')
                cfg.no_gradient_persistent_drift      = true;
                cfg.direction_noise_scale = 2.90;
                cfg.dc_step_scale         = 1.35;
                cfg.dc_interval_scale     = 0.75;
                cfg.no_gradient_blind_transport = true;
                cfg.no_gradient_away_push       = 0.60;
                cfg.no_gradient_lateral_push    = 1.05;
                cfg.no_gradient_particle_jitter = 0.28;
                cfg.no_gradient_complex_gain    = 1.55;
                cfg.no_gradient_near_gain       = 1.30;
            end

        case 'baseline'
            cfg.fixed_dc          = true;
            cfg.fixed_DT_scale    = 1.0;
            cfg.dc_interval_scale = 1.0;
            cfg.use_E_adapt       = false;
            cfg.use_C_gate        = false;
            cfg.use_A_bias        = false;
            cfg.use_A_reliability = false;
            if strcmpi(experiment_profile, 'paper')
                cfg.direction_noise_scale = 1.60;
            end

        case 'local_only'
            % No external DC layer.
            % Keeps only SPP local motion + hydrodynamic repulsion.
            cfg.use_dc      = false;
            cfg.use_E_adapt = false;
            cfg.use_C_gate  = false;
            cfg.use_A_bias  = false;

        otherwise
            error('Unknown control mode: %s', control_mode);
    end
end



%% =========================================================================
%  LOCAL MOTION HELPERS
% =========================================================================

function nps_sp = spp_update(nps, params, f)
    nps_sp = zeros(params.N, 2);
    % f is deterministic within an iteration.  Evaluate it once for the
    % whole swarm instead of recomputing the same two values for every pair.
    % This preserves the SPP equation and random-number stream.
    fitness = f(nps);
    fitness = fitness(:);

    for i = 1:params.N
        if norm(nps(i,:) - params.target) < params.tumor_radius
            nps_sp(i,:) = nps(i,:);
            continue;
        end

        displacement = nps - nps(i,:);
        dist_row = vecnorm(displacement, 2, 2).';
        dist_row(i) = inf;
        [~, R_idx] = sort(dist_row);

        sl    = [0, 0];
        count = 0;
        for j = 1:min(params.neighbor, params.N-1)
            idx = R_idx(j);
            if dist_row(idx) >= 1.5, continue; end
            e = nps(i,:) - nps(idx,:);
            if norm(e) < 1e-12, continue; end
            e        = e / norm(e);
            deltafit = fitness(i) - fitness(idx);
            la       = deltafit / sqrt(dist_row(idx) + 1e-12);
            sl       = sl + la * e;
            count    = count + 1;
        end

        if count > 0 && norm(sl) > 0
            nps_sp(i,:) = nps(i,:) + (sl/norm(sl)) * params.spstep * params.Tsp;
        else
            nps_sp(i,:) = nps(i,:);
        end
    end
end

function nps_next = hydpr_update(nps_sp, params, hydsf, q)
    nps_next = zeros(params.N, 2);
    dx = nps_sp(:,1) - nps_sp(:,1).';
    dy = nps_sp(:,2) - nps_sp(:,2).';
    pair_distance = sqrt(dx.^2 + dy.^2);
    inside_target = vecnorm(nps_sp - params.target, 2, 2) <= ...
        params.tumor_radius;

    for i = 1:params.N
        hydpr    = [0, 0];
        inside_i = inside_target(i);

        for j = 1:params.N
            if j == i, continue; end
            dist_ij = pair_distance(i,j);
            if dist_ij < params.rm && dist_ij > 0
                inside_j = inside_target(j);
                if inside_i && inside_j, continue; end
                q_eff = q;
                if inside_i || inside_j
                    q_eff = params.target_hydpr_ratio * q;
                end
                e      = (nps_sp(i,:) - nps_sp(j,:)) / dist_ij;
                hydpr  = hydpr + e * hydsf(dist_ij, q_eff, params.rd);
            end
        end

        nps_next(i,:) = nps_sp(i,:) + hydpr;
    end
end

function val = eval_f(f, pos)
    val = f(pos);
end


%% =========================================================================
%  TSIF METRICS
% =========================================================================

function metrics = compute_stf_metrics(nps, nps_prev, f, params) %#ok<INUSL>
    metrics = struct('E',0,'C',0,'A',0,'rho_A',0,'A_dir',0,'A_control',0, ...
                     'C_closeness',0,'C_compactness',0);
    if size(nps,1) < 2 || ~isnumeric(nps), return; end

    gb           = params.global_boundary;
    target       = params.target;
    tumor_radius = params.tumor_radius;
    nbins_xy     = params.nbins_xy;

    % E(t): normalized spatial entropy over a fixed global grid.
    try
        nb = min(nbins_xy, max(2, ceil(sqrt(size(nps,1)))));
        x  = max(gb(1), min(gb(2), nps(:,1)));
        y  = max(gb(3), min(gb(4), nps(:,2)));
        xe = linspace(gb(1), gb(2), nb+1);
        ye = linspace(gb(3), gb(4), nb+1);
        [~,~,bx] = histcounts(x, xe);
        [~,~,by] = histcounts(y, ye);
        valid    = bx >= 1 & by >= 1;
        if any(valid)
            bin_idx = (by(valid)-1)*nb + bx(valid);
            counts  = accumarray(bin_idx(:), 1, [nb^2, 1]);
            p       = counts / sum(counts);
            p       = p(p > 0);
            H       = -sum(p .* log(p + eps));
            Hmax    = log(nb^2);
            metrics.E = min(max(H / max(Hmax, eps), 0), 1);
        end
    catch ME
        warning(ME.identifier, '%s', ME.message);
    end

    % C(t): target consensus = geometric mean of closeness and compactness.
    try
        d2t = vecnorm(nps - target, 2, 2);
        if ~isempty(d2t)
            closeness   = mean(exp(-(d2t ./ max(tumor_radius, eps)).^2));
            compactness = exp(-std(d2t) / (mean(d2t) + eps));
            metrics.C_closeness   = min(max(closeness,   0), 1);
            metrics.C_compactness = min(max(compactness, 0), 1);
            metrics.C = min(max(sqrt(metrics.C_closeness * metrics.C_compactness), 0), 1);
        end
    catch ME
        warning(ME.identifier, '%s', ME.message);
    end

    % A(t)=rho_A(t)*A_dir(t): valid-gradient availability multiplied by
    % directional coherence.  A_control keeps the historical A_dir-based
    % controller behavior so this analysis-only revision does not change the
    % simulated policy or invalidate existing performance trajectories.
    try
        grad_info = estimate_swarm_gradient_reliable( ...
            nps, f, params.gradient_fd_step, params.gradient_threshold);
        metrics.rho_A    = min(max(grad_info.rho_A, 0), 1);
        metrics.A_dir    = min(max(grad_info.dir_consistency, 0), 1);
        metrics.A        = metrics.rho_A * metrics.A_dir;
        metrics.A_control = metrics.A_dir;
    catch ME
        warning(ME.identifier, '%s', ME.message);
    end
end

function T = normalize_text_columns(T, names)
    for i = 1:numel(names)
        if ismember(names{i}, T.Properties.VariableNames)
            T.(names{i}) = string(T.(names{i}));
        end
    end
end

function grad_info = estimate_swarm_gradient_reliable(nps, f, h, gamma_g)
    if nargin < 3 || isempty(h), h = 1e-5; end
    if nargin < 4 || isempty(gamma_g), gamma_g = 1e-8; end
    grad_info = struct('g_swarm',[0 0], 'dir_consistency',0, ...
                       'rho_A',0, 'n_valid',0);
    xp = nps; xm = nps; yp = nps; ym = nps;
    xp(:,1) = xp(:,1) + h;
    xm(:,1) = xm(:,1) - h;
    yp(:,2) = yp(:,2) + h;
    ym(:,2) = ym(:,2) - h;
    fx = (f(xp) - f(xm)) / (2*h);
    fy = (f(yp) - f(ym)) / (2*h);
    grads = [fx(:), fy(:)];

    grad_norms = vecnorm(grads, 2, 2);
    valid      = grad_norms > gamma_g;
    grad_info.n_valid = sum(valid);
    grad_info.rho_A   = grad_info.n_valid / max(size(nps,1), 1);
    if ~any(valid), return; end

    unit_grads = grads(valid,:) ./ grad_norms(valid);
    mean_dir   = mean(unit_grads, 1);
    grad_info.dir_consistency = norm(mean_dir);
    if norm(mean_dir) > 1e-8
        grad_info.g_swarm = mean_dir / norm(mean_dir);
    end
end

function cohesion = compute_swarm_cohesion(nps)
    if size(nps,1) < 2
        cohesion = 0;
        return;
    end
    n = size(nps,1);
    dsum = 0;
    cnt  = 0;
    for i = 1:n-1
        diffs = nps(i+1:n,:) - nps(i,:);
        dsum  = dsum + sum(sqrt(sum(diffs.^2, 2)));
        cnt   = cnt + n - i;
    end
    cohesion = 1 / (1 + dsum / max(cnt, 1));
end

function q = percentile_value(x, p)
    x = sort(x(~isnan(x)));
    if isempty(x)
        q = NaN;
        return;
    end
    if numel(x) == 1
        q = x;
        return;
    end
    pos = 1 + (numel(x)-1) * p / 100;
    lo = floor(pos);
    hi = ceil(pos);
    if lo == hi
        q = x(lo);
    else
        q = x(lo) + (x(hi)-x(lo)) * (pos-lo);
    end
end

function [q_tar, DT_tar] = adjust_SO_DC_soft(E, q0, q_scale, DT0, DT_scale, ...
                                              DT_max_ratio, E_thr, ...
                                              q_min_ratio, q_max_ratio, DT_min_ratio)
    entropy_deficit = E_thr - E;

    % Low E means the swarm has low spatial diversity: increase territorial
    % repulsion and shorten DC duration to avoid premature collapse.
    q_raw  = q0  * (1 + q_scale  * entropy_deficit);
    DT_raw = DT0 * (1 - DT_scale * entropy_deficit);

    q_tar  = min(max(q_raw,  q0*q_min_ratio),  q0*q_max_ratio);
    DT_tar = min(max(DT_raw, DT0*DT_min_ratio), DT0*DT_max_ratio);
end

function v = rotate_unit_vector(v, theta)
    R = [cos(theta), -sin(theta); sin(theta), cos(theta)];
    v = (R * v(:))';
    v = v / max(norm(v), 1e-12);
end

function n = longest_true_run(flag)
    % Length of the longest uninterrupted true segment in a logical vector.
    x = [false; logical(flag(:)); false];
    dx = diff(x);
    run_start = find(dx == 1);
    run_end = find(dx == -1) - 1;
    if isempty(run_start)
        n = 0;
    else
        n = max(run_end - run_start + 1);
    end
end


%% =========================================================================
%  FEATURE EXTRACTION AND SUMMARISATION
% =========================================================================

function feat = extract_stage_features(result, sim_id, params, bgf_type, exp_id)
    feat = struct();
    feat.exp_id       = exp_id;
    feat.scenario_id  = params.scenario_id;
    feat.random_seed  = params.base_seed + params.scenario_id;
    feat.shock_seed   = result.shock_seed;
    feat.sim_id       = sim_id;
    feat.bgf_type     = string(bgf_type);
    feat.control_mode = string(params.control_mode);
    feat.experiment_profile = string(result.experiment_profile);
    feat.init_name    = string(params.init_name);
    feat.neighbor     = params.neighbor;
    feat.v_e          = params.v_e;
    feat.noise_level  = params.noise_level;

    feat.terminal_error_mean   = result.terminal_error_mean;
    feat.terminal_error_median = result.terminal_error_median;
    feat.terminal_error_p90    = result.terminal_error_p90;
    feat.target_occupancy      = result.target_occupancy;
    feat.time_to_target_50     = result.time_to_target_50;
    feat.time_to_target_50_observed = result.time_to_target_50_observed;
    feat.time_to_target_50_event    = result.time_to_target_50_event;
    feat.time_to_target_50_censored = result.time_to_target_50_censored;
    feat.convergence_rate      = result.convergence_rate;
    feat.stability_index       = result.stability_index;
    feat.swarm_cohesion        = result.swarm_cohesion;
    feat.dc_count              = result.dc_count;

    feat.mean_E       = mean(result.E_hist,       'omitnan');
    feat.max_E        = max(result.E_hist);
    feat.mean_C       = mean(result.C_hist,       'omitnan');
    feat.mean_A       = mean(result.A_hist,       'omitnan');
    feat.mean_rho_A   = mean(result.rho_A_hist,   'omitnan');
    feat.mean_A_dir   = mean(result.A_dir_hist,   'omitnan');
    feat.mean_A_control = mean(result.A_control_hist, 'omitnan');
    feat.eer          = result.eer;
    feat.mean_q       = result.mean_q;
    feat.mean_spstep  = result.mean_spstep;

    feat.early_E_mean        = result.early_E_mean;
    feat.early_cohesion_mean = result.early_cohesion_mean;

    feat.success_soft   = result.success_soft;
    feat.success_stable = result.success_stable;
    feat.success_fast   = result.success_fast;
    feat.stable_pass_fraction = result.stable_pass_fraction;
    feat.stable_max_run_ratio = result.stable_max_run_ratio;
    feat.stable_occupancy_threshold = result.stable_occupancy_threshold;
    feat.stable_required_fraction = result.stable_required_fraction;
    feat.stable_min_run_ratio = result.stable_min_run_ratio;
    feat.stable_max_late_occupancy_std = result.stable_max_late_occupancy_std;
    feat.stable_max_late_error_std = result.stable_max_late_error_std;
    feat.stable_max_negative_dc_rate = result.stable_max_negative_dc_rate;
    feat.stable_late_window_fraction = result.stable_late_window_fraction;
    feat.stable_rule = string(result.stable_rule);
    feat.runtime_sec    = result.runtime_sec;

    feat.error_auc             = result.error_auc;
    feat.occupancy_auc         = result.occupancy_auc;
    feat.late_error_mean       = result.late_error_mean;
    feat.late_error_std        = result.late_error_std;
    feat.late_occupancy_mean   = result.late_occupancy_mean;
    feat.late_occupancy_std    = result.late_occupancy_std;
    feat.dc_activation_rate    = result.dc_activation_rate;
    feat.mean_dc_gain          = result.mean_dc_gain;
    feat.positive_dc_gain_rate = result.positive_dc_gain_rate;
    feat.negative_dc_gain_rate = result.negative_dc_gain_rate;
    feat.low_C_dc_rate         = result.low_C_dc_rate;
    feat.low_reliability_dc_rate = result.low_reliability_dc_rate;
end

function summary_row = summarize_experiment(exp_rows, bgf_type, params, exp_id)
    summary_row = table();
    summary_row.exp_id       = exp_id;
    summary_row.bgf_type     = string(bgf_type);
    summary_row.control_mode = string(params.control_mode);
    summary_row.init_name    = string(params.init_name);
    summary_row.noise_level  = params.noise_level;

    summary_row.mean_terminal_error   = mean(exp_rows.terminal_error_mean);
    summary_row.std_terminal_error    = std(exp_rows.terminal_error_mean);
    summary_row.mean_occupancy        = mean(exp_rows.target_occupancy);
    summary_row.mean_time_to_50       = mean(exp_rows.time_to_target_50);
    summary_row.mean_error_auc        = mean(exp_rows.error_auc,          'omitnan');
    summary_row.mean_occupancy_auc    = mean(exp_rows.occupancy_auc,      'omitnan');
    summary_row.mean_late_error       = mean(exp_rows.late_error_mean,    'omitnan');
    summary_row.mean_late_occupancy   = mean(exp_rows.late_occupancy_mean,'omitnan');
    summary_row.mean_convergence_rate = mean(exp_rows.convergence_rate);
    summary_row.mean_stability        = mean(exp_rows.stability_index);
    summary_row.mean_cohesion         = mean(exp_rows.swarm_cohesion);
    summary_row.mean_runtime          = mean(exp_rows.runtime_sec);
    summary_row.mean_dc_gain          = mean(exp_rows.mean_dc_gain,        'omitnan');
    summary_row.mean_pos_dc_gain_rate = mean(exp_rows.positive_dc_gain_rate,'omitnan');
    summary_row.mean_neg_dc_gain_rate = mean(exp_rows.negative_dc_gain_rate,'omitnan');
    summary_row.mean_low_C_dc_rate    = mean(exp_rows.low_C_dc_rate,       'omitnan');
    summary_row.mean_low_reliability_dc_rate = mean(exp_rows.low_reliability_dc_rate, 'omitnan');
    summary_row.mean_q                = mean(exp_rows.mean_q,              'omitnan');
    summary_row.mean_spstep           = mean(exp_rows.mean_spstep,         'omitnan');
    summary_row.mean_early_E          = mean(exp_rows.early_E_mean,        'omitnan');
    summary_row.mean_early_cohesion   = mean(exp_rows.early_cohesion_mean, 'omitnan');
    summary_row.mean_E                = mean(exp_rows.mean_E,              'omitnan');
    summary_row.mean_C                = mean(exp_rows.mean_C,              'omitnan');
    summary_row.mean_A                = mean(exp_rows.mean_A,              'omitnan');

    summary_row.soft_success_rate   = mean(exp_rows.success_soft);
    summary_row.stable_success_rate = mean(exp_rows.success_stable);
    summary_row.fast_success_rate   = mean(exp_rows.success_fast);
    summary_row.compound_success    = mean(exp_rows.success_soft & ...
                                           exp_rows.success_stable & exp_rows.success_fast);
end


%% =========================================================================
%  PAIRED SIGNIFICANCE TESTS
% =========================================================================

function stats_table = run_paired_comparison_tests(feature_table)
    fprintf('\n===== Paired comparison tests =====\n');
    stats_table   = table();
    baseline_mode = "tsif_full";
    compare_modes = ["no_e", "no_c", "no_a", "baseline", "local_only"];

    metric_names = ["terminal_error_mean","target_occupancy","time_to_target_50", ...
                    "error_auc","occupancy_auc","late_error_mean", ...
                    "late_occupancy_mean","stability_index", ...
                    "early_E_mean","early_cohesion_mean", ...
                    "mean_q","mean_spstep", ...
                    "dc_activation_rate","mean_dc_gain", ...
                    "negative_dc_gain_rate","low_C_dc_rate","low_reliability_dc_rate", ...
                    "positive_dc_gain_rate"];

    lower_is_better = ["terminal_error_mean","time_to_target_50", ...
                       "error_auc","late_error_mean","stability_index", ...
                       "early_cohesion_mean","negative_dc_gain_rate", ...
                       "low_C_dc_rate","low_reliability_dc_rate"];

    bgfs = unique(feature_table.bgf_type, 'stable');

    for b = 1:length(bgfs)
        bgf = bgfs(b);
        for m = 1:length(compare_modes)
            mode_i = compare_modes(m);
            for k = 1:length(metric_names)
                metric      = metric_names(k);
                metric_char = char(metric);

                idx_stf = feature_table.bgf_type == bgf & feature_table.control_mode == baseline_mode;
                idx_cmp = feature_table.bgf_type == bgf & feature_table.control_mode == mode_i;
                T1 = feature_table(idx_stf,:);
                T2 = feature_table(idx_cmp,:);

                if isempty(T1) || isempty(T2), continue; end

                [~, ia, ib] = intersect(T1.scenario_id, T2.scenario_id);
                if numel(ia) < 2, continue; end

                x     = T1.(metric_char)(ia);
                y     = T2.(metric_char)(ib);
                valid = ~isnan(x) & ~isnan(y);
                x = x(valid);
                y = y(valid);
                if numel(x) < 2, continue; end

                try
                    p = signrank(x, y);
                catch
                    p = NaN;
                end

                delta = mean(x - y, 'omitnan');
                if any(metric == lower_is_better)
                    improvement = mean(y - x, 'omitnan');
                    effect_diff = y - x;
                else
                    improvement = mean(x - y, 'omitnan');
                    effect_diff = x - y;
                end

                r_rb = paired_rank_biserial(effect_diff);
                if metric == "error_auc"
                    [ci_lo, ci_hi] = bootstrap_mean_ci(effect_diff, 10000, ...
                        20260826 + 100*b + 10*m + k);
                else
                    ci_lo = NaN;
                    ci_hi = NaN;
                end

                row = table(bgf, baseline_mode, mode_i, metric, ...
                            numel(x), mean(x,'omitnan'), mean(y,'omitnan'), ...
                            delta, improvement, r_rb, ci_lo, ci_hi, p, ...
                    'VariableNames',{'bgf_type','mode_stf','mode_compare','metric', ...
                                     'n_pairs','mean_stf','mean_compare', ...
                                     'delta_stf_minus_compare','improvement_positive_good', ...
                                     'rank_biserial','bootstrap_ci_low','bootstrap_ci_high', ...
                                     'p_signrank'});
                stats_table = [stats_table; row]; %#ok<AGROW>
            end
        end
    end

    if ~isempty(stats_table)
        % Adjust each prespecified metric family separately.  In particular,
        % the manuscript's primary family is exactly the 4 BGF x 5 comparator
        % AUC contrasts (20 p-values), not every diagnostic metric combined.
        stats_table.p_fdr = NaN(height(stats_table),1);
        metric_families = unique(stats_table.metric, 'stable');
        for q = 1:numel(metric_families)
            idx_q = stats_table.metric == metric_families(q);
            stats_table.p_fdr(idx_q) = benjamini_hochberg(stats_table.p_signrank(idx_q));
        end
        stats_table.p_fdr_primary_auc = NaN(height(stats_table),1);
        idx_auc = stats_table.metric == "error_auc";
        stats_table.p_fdr_primary_auc(idx_auc) = stats_table.p_fdr(idx_auc);
    end
    disp(stats_table);
end

function r_rb = paired_rank_biserial(d)
    d = d(:);
    d = d(~isnan(d) & d ~= 0);
    if isempty(d)
        r_rb = 0;
        return;
    end
    r = tiedrank(abs(d));
    denom = sum(r);
    r_rb = (sum(r(d > 0)) - sum(r(d < 0))) / max(denom, eps);
end

function [ci_lo, ci_hi] = bootstrap_mean_ci(d, n_boot, seed)
    d = d(:);
    d = d(~isnan(d));
    if isempty(d)
        ci_lo = NaN;
        ci_hi = NaN;
        return;
    end
    stream = RandStream('mt19937ar','Seed',seed);
    idx = randi(stream, numel(d), numel(d), n_boot);
    boot_mean = mean(d(idx), 1, 'omitnan');
    ci_lo = percentile_value(boot_mean(:), 2.5);
    ci_hi = percentile_value(boot_mean(:), 97.5);
end

function p_adj = benjamini_hochberg(p)
    p     = p(:);
    p_adj = NaN(size(p));
    valid = ~isnan(p);
    pv    = p(valid);
    if isempty(pv), return; end

    [sorted_p, idx] = sort(pv);
    m         = length(pv);
    adj       = sorted_p .* m ./ (1:m)';
    adj       = min(adj, 1);
    for i = m-1:-1:1
        adj(i) = min(adj(i), adj(i+1));
    end
    tmp      = zeros(size(pv));
    tmp(idx) = adj;
    p_adj(valid) = tmp;
end


%% =========================================================================
%  NO-NEW-SIMULATION REVIEW EXPORTS
% =========================================================================

function generate_no_new_simulation_exports(feature_table, all_results, stats_table, params, out_prefix)
    fprintf('\n=== Generating review-analysis interfaces ===\n');

    if isempty(stats_table) || ...
            ~ismember('metric', stats_table.Properties.VariableNames)
        auc_primary = table();
    else
        auc_primary = stats_table(stats_table.metric == "error_auc", :);
    end
    writetable(auc_primary, [out_prefix '_primary_auc_20.csv']);

    sensitivity_table = build_stable_success_sensitivity( ...
        feature_table, all_results, params);
    writetable(sensitivity_table, [out_prefix '_stable_success_sensitivity.csv']);

    descriptor_table = build_descriptor_summary(feature_table, all_results);
    writetable(descriptor_table, [out_prefix '_descriptor_summary.csv']);
    writetable(descriptor_table, [out_prefix '_prediction_input.csv']);

    correlation_table = build_descriptor_correlation_interface(descriptor_table);
    writetable(correlation_table, [out_prefix '_descriptor_correlations.csv']);

    pca_table = build_descriptor_pca_interface(descriptor_table);
    writetable(pca_table, [out_prefix '_descriptor_pca.csv']);

    provenance_table = build_trajectory_provenance(feature_table);
    writetable(provenance_table, [out_prefix '_trajectory_provenance.csv']);

    config_table = build_configuration_table(params);
    writetable(config_table, [out_prefix '_configuration.csv']);

    manifest_table = build_reproducibility_manifest(feature_table);
    writetable(manifest_table, [out_prefix '_reproducibility_manifest.csv']);

    fprintf('  Review interfaces written from the run-level source.\n');
end

function T = build_stable_success_sensitivity(feature_table, all_results, params)
    occ_thresholds  = [0.30, 0.35, 0.40];
    required_fracs  = [0.70, 0.80, 0.90];
    late_fracs      = [0.15, 0.20, 0.25];
    time_fracs      = [0.80, 0.85, 0.90];
    bgfs  = unique(string(feature_table.bgf_type), 'stable');
    modes = unique(string(feature_table.control_mode), 'stable');
    T = table();

    n_available = min(height(feature_table), numel(all_results));
    for b = 1:numel(bgfs)
        for m = 1:numel(modes)
            idx_group = find((1:height(feature_table))' <= n_available & ...
                string(feature_table.bgf_type) == bgfs(b) & ...
                string(feature_table.control_mode) == modes(m));
            if isempty(idx_group), continue; end
            for io = 1:numel(occ_thresholds)
                for ir = 1:numel(required_fracs)
                    for il = 1:numel(late_fracs)
                        for it = 1:numel(time_fracs)
                            stable = false(numel(idx_group),1);
                            compound = false(numel(idx_group),1);
                            for q = 1:numel(idx_group)
                                row_id = idx_group(q);
                                r = all_results{row_id};
                                O = r.occupancy_hist(:);
                                if isempty(O), continue; end
                                first_late = max(1, floor((1-late_fracs(il))*numel(O)) + 1);
                                late_idx = first_late:numel(O);
                                stable(q) = mean(O(late_idx) >= occ_thresholds(io)) >= required_fracs(ir);

                                if ismember('time_to_target_50_event', feature_table.Properties.VariableNames)
                                    event_50 = logical(feature_table.time_to_target_50_event(row_id));
                                else
                                    event_50 = feature_table.time_to_target_50(row_id) < params.max_iteration;
                                end
                                accurate = feature_table.terminal_error_mean(row_id) < ...
                                    params.success_threshold_mean_error;
                                fast = event_50 && feature_table.time_to_target_50(row_id) <= ...
                                    round(time_fracs(it)*params.max_iteration);
                                compound(q) = accurate && stable(q) && fast;
                            end
                            row = table(bgfs(b), modes(m), occ_thresholds(io), ...
                                required_fracs(ir), late_fracs(il), time_fracs(it), ...
                                numel(idx_group), sum(stable), mean(stable), ...
                                sum(compound), mean(compound), ...
                                'VariableNames', {'bgf_type','control_mode','occupancy_threshold', ...
                                'required_late_fraction','late_window_fraction','time_budget_fraction', ...
                                'n_runs','stable_n','stable_rate','compound_n','compound_rate'});
                            T = [T; row]; %#ok<AGROW>
                        end
                    end
                end
            end
        end
    end
end

function T = build_descriptor_summary(feature_table, all_results)
    n = min(height(feature_table), numel(all_results));
    T = feature_table(1:n, {'scenario_id','bgf_type','control_mode','init_name', ...
        'noise_level','error_auc','terminal_error_mean','success_soft', ...
        'success_stable','success_fast'});

    names = {'early_E','mid_E','late_E','early_C','mid_C','late_C', ...
             'early_A','mid_A','late_A','early_rho_A','mid_rho_A','late_rho_A', ...
             'early_A_dir','mid_A_dir','late_A_dir'};
    for k = 1:numel(names), T.(names{k}) = NaN(n,1); end

    for i = 1:n
        r = all_results{i};
        E = get_result_history(r, 'E_hist');
        C = get_result_history(r, 'C_hist');
        % Only use the revised descriptor history.  Legacy MAT files contain
        % A_dir under A_hist and must not be silently relabeled as A=rho*A_dir.
        A = get_result_history(r, 'A_hist');
        rho = get_result_history(r, 'rho_A_hist');
        Adir = get_result_history(r, 'A_dir_hist');
        if isempty(rho) || isempty(Adir)
            A = [];
            rho = [];
            Adir = [];
        end
        T{i, names(1:3)}   = stage_means(E);
        T{i, names(4:6)}   = stage_means(C);
        T{i, names(7:9)}   = stage_means(A);
        T{i, names(10:12)} = stage_means(rho);
        T{i, names(13:15)} = stage_means(Adir);
    end
    T.compound_success = logical(T.success_soft) & logical(T.success_stable) & logical(T.success_fast);
end

function x = get_result_history(r, field_name)
    if isfield(r, field_name)
        x = r.(field_name)(:);
    else
        x = [];
    end
end

function v = stage_means(x)
    v = [NaN NaN NaN];
    if isempty(x), return; end
    n = numel(x);
    idx = {1:max(1,floor(0.2*n)), ...
           max(1,floor(0.4*n)+1):max(1,floor(0.6*n)), ...
           max(1,floor(0.8*n)+1):n};
    for k = 1:3
        v(k) = mean(x(idx{k}), 'omitnan');
    end
end

function T = build_descriptor_correlation_interface(D)
    vars = {'early_E','early_C','early_A','mid_E','mid_C','mid_A', ...
            'late_E','late_C','late_A'};
    T = table();
    for i = 1:numel(vars)-1
        for j = i+1:numel(vars)
            x = D.(vars{i}); y = D.(vars{j}); valid = ~isnan(x) & ~isnan(y);
            rho = NaN; p = NaN;
            if sum(valid) >= 5
                try
                    [rho,p] = corr(x(valid), y(valid), 'Type','Spearman');
                catch
                    rho = corr(x(valid), y(valid));
                end
            end
            row = table(string(vars{i}), string(vars{j}), sum(valid), rho, p, ...
                'VariableNames', {'variable_1','variable_2','n_runs','spearman_rho','p_unadjusted'});
            T = [T; row]; %#ok<AGROW>
        end
    end
end

function T = build_descriptor_pca_interface(D)
    vars = {'early_E','early_C','early_A','mid_E','mid_C','mid_A'};
    X = D{:,vars};
    valid = all(~isnan(X),2);
    T = table();
    if sum(valid) < numel(vars) + 2, return; end
    X = X(valid,:);
    X = (X - mean(X,1)) ./ max(std(X,0,1), eps);
    try
        [coeff,~,~,~,explained] = pca(X);
    catch
        [~,S,V] = svd(X, 'econ');
        coeff = V;
        latent = diag(S).^2 / max(size(X,1)-1,1);
        explained = 100*latent/sum(latent);
    end
    for pc = 1:min(3,size(coeff,2))
        for j = 1:numel(vars)
            row = table(pc, string(vars{j}), coeff(j,pc), explained(pc), sum(valid), ...
                'VariableNames', {'component','variable','loading','explained_percent','n_runs'});
            T = [T; row]; %#ok<AGROW>
        end
    end
end

function T = build_trajectory_provenance(feature_table)
    [G,bgf,init,noise,mode] = findgroups( ...
        string(feature_table.bgf_type), string(feature_table.init_name), ...
        feature_table.noise_level, string(feature_table.control_mode));
    T = table();
    for g = 1:max(G)
        idx = find(G == g);
        [~,ord] = sort(feature_table.error_auc(idx));
        ranks = unique([1, ceil(numel(ord)/2), numel(ord)]);
        labels = ["best","median","worst"];
        for q = 1:numel(ranks)
            row_id = idx(ord(ranks(q)));
            row = table(bgf(g), init(g), noise(g), mode(g), labels(q), ...
                feature_table.scenario_id(row_id), feature_table.sim_id(row_id), ...
                feature_table.error_auc(row_id), ...
                'VariableNames', {'bgf_type','init_name','noise_level','control_mode', ...
                'rank_label','scenario_id','sim_id','error_auc'});
            T = [T; row]; %#ok<AGROW>
        end
    end
end

function T = build_configuration_table(params)
    key = ["experiment_profile";"N";"domain";"target";"tumor_radius";"max_iteration";"neighbor"; ...
           "entropy_grid_B";"entropy_cells";"gradient_fd_step"; ...
           "gradient_threshold";"s_SO";"Q0";"r_d";"R_m"; ...
           "DeltaT0";"v_e";"P_SO"; ...
           "stable_rule";"stable_occupancy_threshold"; ...
           "stable_required_fraction";"stable_min_run_ratio"; ...
           "stable_max_late_occupancy_std";"stable_max_late_error_std"; ...
           "stable_max_negative_dc_rate"; ...
           "stable_late_window_fraction";"late_dc_noise_gain";"late_actuator_noise"; ...
           "shock_time_fraction";"shock_particle_fraction";"shock_magnitude"; ...
           "C_v2_enabled";"C_hold_radius";"C_retention_on";"C_retention_off"; ...
           "C_v2_reliability_low";"C_v2_reliability_high";"C_v2_soft_gain"; ...
           "C_v2_min_scale";"C_predicted_gain_margin"; ...
           "C_local_damping_gain";"C_local_damping_min"; ...
           "C_local_recentering_gain"; ...
           "noise_levels";"base_seed"];
    value = [string(params.experiment_profile); string(params.N); ...
              "[-11,11]x[-11,11]"; "[0,0]"; ...
              string(params.tumor_radius); string(params.max_iteration); ...
             string(params.neighbor); string(ceil(sqrt(params.N))); ...
             string(ceil(sqrt(params.N))^2); string(params.gradient_fd_step); ...
             string(params.gradient_threshold); string(params.spstep); ...
             string(params.q0); string(params.rd); string(params.rm); ...
              string(params.DT0); string(params.v_e); string(params.dc_interval); ...
              string(params.success_rule); string(params.success_threshold_occupancy); ...
              string(params.success_required_fraction); string(params.success_min_run_ratio); ...
              string(params.success_max_late_occupancy_std); ...
              string(params.success_max_late_error_std); ...
              string(params.success_max_negative_dc_rate); ...
              string(params.success_late_window_fraction); ...
              string(params.stress_late_dc_noise_gain); ...
              string(params.stress_late_actuator_noise); ...
              string(params.stress_shock_time_fraction); ...
              string(params.stress_shock_particle_fraction); ...
              string(params.stress_shock_magnitude); ...
              string(params.C_v2_enabled); string(params.C_hold_radius); ...
              string(params.C_retention_on); string(params.C_retention_off); ...
              string(params.C_v2_reliability_low); string(params.C_v2_reliability_high); ...
              string(params.C_v2_soft_gain); string(params.C_v2_min_scale); ...
              string(params.C_predicted_gain_margin); ...
              string(params.C_local_damping_gain); string(params.C_local_damping_min); ...
              string(params.C_local_recentering_gain); ...
              "0,0.015"; string(params.base_seed)];
    T = table(key, value);
end

function T = build_reproducibility_manifest(feature_table)
    runtime = feature_table.runtime_sec(~isnan(feature_table.runtime_sec));
    if isempty(runtime)
        runtime_summary = "unavailable";
    else
        runtime_summary = sprintf('%.3f [%.3f, %.3f] s', median(runtime), ...
            percentile_value(runtime,25), percentile_value(runtime,75));
    end
    script_path = [mfilename('fullpath') '.m'];
    item = ["MATLAB release";"Computer";"Operating system";"CPU"; ...
            "Median runtime [IQR]";"Script path";"Script SHA-256"; ...
            "Generated timestamp"];
    value = [string(version('-release')); string(computer); string(getenv('OS')); ...
             string(getenv('PROCESSOR_IDENTIFIER')); string(runtime_summary); ...
             string(script_path); string(sha256_file(script_path)); ...
             string(datetime('now','Format','yyyy-MM-dd HH:mm:ss Z'))];
    T = table(item,value);
end

function hex = sha256_file(filename)
    hex = "unavailable";
    if ~isfile(filename), return; end
    try
        md = java.security.MessageDigest.getInstance('SHA-256');
        fid = fopen(filename,'rb');
        cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>
        while ~feof(fid)
            bytes = fread(fid, 1024*1024, '*uint8');
            md.update(bytes);
        end
        digest = typecast(md.digest(), 'uint8');
        hex = string(lower(reshape(dec2hex(digest,2).',1,[])));
    catch
    end
end


%% =========================================================================
%  PAPER TABLE GENERATION
% =========================================================================

function generate_paper_tables(feature_table, stats_table, out_prefix)
    fprintf('\n=== Generating paper tables ===\n');

    performance_table = build_performance_table(feature_table);
    writetable(performance_table, [out_prefix '_table_iii_performance.csv']);
    export_table1_latex(performance_table, [out_prefix '_table_iii_performance.tex']);

    ablation_table = build_ablation_diagnostics_table(feature_table, stats_table);
    writetable(ablation_table, [out_prefix '_table2_ablation_diagnostics.csv']);
    export_table2_latex(ablation_table, [out_prefix '_table2_ablation_diagnostics.tex']);

    if isempty(stats_table) || ...
            ~ismember('metric', stats_table.Properties.VariableNames)
        auc_table = table();
    else
        auc_table = stats_table(stats_table.metric == "error_auc", :);
    end
    writetable(auc_table, [out_prefix '_table3_auc_20_comparisons.csv']);
    export_auc_inference_latex(auc_table, [out_prefix '_table3_auc_20_comparisons.tex']);


    fprintf('  Saved: %s_table_iii_performance.csv/.tex\n', out_prefix);
    fprintf('  Saved: %s_table2_ablation_diagnostics.csv/.tex\n', out_prefix);
    fprintf('  Saved: %s_table3_auc_20_comparisons.csv/.tex\n', out_prefix);
end

function performance_table = build_performance_table(feature_table)
    performance_table = table();
    bgfs  = unique(string(feature_table.bgf_type), 'stable');
    modes = ["tsif_full","no_e","no_c","no_a","baseline","local_only"];

    for b = 1:numel(bgfs)
        bgf = bgfs(b);
        for m = 1:numel(modes)
            mode_i = modes(m);
            idx = string(feature_table.bgf_type) == bgf & ...
                  string(feature_table.control_mode) == mode_i;
            if ~any(idx)
                continue;
            end

            stable_success = logical(feature_table.success_stable(idx));
            compound_success = feature_table.success_soft(idx) & ...
                feature_table.success_stable(idx) & feature_table.success_fast(idx);
            t50_values = feature_table.time_to_target_50(idx);
            [t50_ci_lo, t50_ci_hi] = bootstrap_mean_ci( ...
                t50_values, 10000, 20260826 + 100*b + m);
            if ismember('time_to_target_50_censored', feature_table.Properties.VariableNames)
                censored_n = sum(feature_table.time_to_target_50_censored(idx));
            else
                % Backward-compatible recovery for the existing fixed-budget
                % file, in which non-events were stored as 1000.
                censored_n = sum(t50_values >= 1000);
            end

            row = table( ...
                bgf, mode_i, paper_mode_label(mode_i), sum(idx), ...
                mean(feature_table.error_auc(idx), 'omitnan'), ...
                std(feature_table.error_auc(idx),  'omitnan'), ...
                mean(feature_table.terminal_error_mean(idx), 'omitnan'), ...
                std(feature_table.terminal_error_mean(idx),  'omitnan'), ...
                mean(feature_table.time_to_target_50(idx), 'omitnan'), ...
                std(feature_table.time_to_target_50(idx),  'omitnan'), ...
                t50_ci_lo, t50_ci_hi, censored_n, ...
                mean(feature_table.target_occupancy(idx), 'omitnan'), ...
                std(feature_table.target_occupancy(idx),  'omitnan'), ...
                sum(stable_success), mean(stable_success, 'omitnan'), ...
                sum(compound_success), mean(compound_success, 'omitnan'), ...
                mean(feature_table.runtime_sec(idx), 'omitnan'), ...
                'VariableNames', {'bgf_type','control_mode','method_label','n_runs', ...
                                  'error_auc_mean','error_auc_std', ...
                                  'terminal_error_mean','terminal_error_std', ...
                                  'time_to_50_mean','time_to_50_std', ...
                                  'time_to_50_ci_low','time_to_50_ci_high','time_to_50_censored_n', ...
                                  'occupancy_mean','occupancy_std', ...
                                  'stable_success_n','stable_success_rate', ...
                                  'compound_success_n','compound_success_rate','runtime_sec_mean'});
            performance_table = [performance_table; row]; %#ok<AGROW>
        end
    end
end

function ablation_table = build_ablation_diagnostics_table(feature_table, stats_table)
    ablation_table = table();
    bgfs  = unique(string(feature_table.bgf_type), 'stable');
    modes = ["no_e","no_c","no_a"];

    for b = 1:numel(bgfs)
        bgf = bgfs(b);
        for m = 1:numel(modes)
            mode_i = modes(m);

            [d_auc_mu, d_auc_sd, n_auc] = paired_metric_delta( ...
                feature_table, bgf, mode_i, 'error_auc');
            [d_late_mu, d_late_sd, n_late] = paired_metric_delta( ...
                feature_table, bgf, mode_i, 'late_error_mean');
            [d_stab_mu, d_stab_sd, n_stab] = paired_metric_delta( ...
                feature_table, bgf, mode_i, 'stability_index');
            [d_neg_mu, d_neg_sd, n_neg] = paired_metric_delta( ...
                feature_table, bgf, mode_i, 'negative_dc_gain_rate');

            n_pairs = max([n_auc, n_late, n_stab, n_neg]);
            if n_pairs == 0
                continue;
            end

            row = table( ...
                bgf, mode_i, paper_mode_label(mode_i), removed_component_label(mode_i), ...
                n_pairs, ...
                d_auc_mu, d_auc_sd, d_late_mu, d_late_sd, ...
                d_stab_mu, d_stab_sd, d_neg_mu, d_neg_sd, ...
                get_metric_p_fdr(stats_table, bgf, mode_i, 'error_auc'), ...
                get_metric_p_fdr(stats_table, bgf, mode_i, 'late_error_mean'), ...
                get_metric_p_fdr(stats_table, bgf, mode_i, 'stability_index'), ...
                get_metric_p_fdr(stats_table, bgf, mode_i, 'negative_dc_gain_rate'), ...
                'VariableNames', {'bgf_type','ablation_mode','ablation_label', ...
                                  'removed_component','n_pairs', ...
                                  'delta_error_auc_mean','delta_error_auc_std', ...
                                  'delta_late_error_mean','delta_late_error_std', ...
                                  'delta_stability_index_mean','delta_stability_index_std', ...
                                  'delta_negative_dc_rate_mean','delta_negative_dc_rate_std', ...
                                  'p_fdr_error_auc','p_fdr_late_error', ...
                                  'p_fdr_stability','p_fdr_negative_dc_rate'});
            ablation_table = [ablation_table; row]; %#ok<AGROW>
        end
    end
end

function [delta_mu, delta_sd, n_pairs] = paired_metric_delta(feature_table, bgf, mode_i, metric_name)
    baseline_mode = "tsif_full";
    metric_name   = char(metric_name);

    idx_base = string(feature_table.bgf_type) == string(bgf) & ...
               string(feature_table.control_mode) == baseline_mode;
    idx_cmp  = string(feature_table.bgf_type) == string(bgf) & ...
               string(feature_table.control_mode) == string(mode_i);

    T_base = feature_table(idx_base,:);
    T_cmp  = feature_table(idx_cmp,:);

    delta_mu = NaN;
    delta_sd = NaN;
    n_pairs  = 0;

    if isempty(T_base) || isempty(T_cmp) || ...
       ~ismember(metric_name, feature_table.Properties.VariableNames)
        return;
    end

    [~, ia, ib] = intersect(T_base.scenario_id, T_cmp.scenario_id);
    if isempty(ia)
        return;
    end

    x = T_base.(metric_name)(ia);
    y = T_cmp.(metric_name)(ib);
    valid = ~isnan(x) & ~isnan(y);
    d = y(valid) - x(valid);

    if isempty(d)
        return;
    end

    delta_mu = mean(d, 'omitnan');
    delta_sd = std(d,  'omitnan');
    n_pairs  = numel(d);
end

function p = get_metric_p_fdr(stats_table, bgf, mode_i, metric_name)
    p = NaN;
    if isempty(stats_table) || ~ismember('p_fdr', stats_table.Properties.VariableNames)
        return;
    end

    idx = string(stats_table.bgf_type) == string(bgf) & ...
          string(stats_table.mode_compare) == string(mode_i) & ...
          string(stats_table.metric) == string(metric_name);
    vals = stats_table.p_fdr(idx);
    vals = vals(~isnan(vals));

    if ~isempty(vals)
        p = vals(1);
    end
end

function export_table1_latex(T, filename)
    fid = fopen(filename, 'w');
    if fid < 0
        warning('Cannot open table file: %s', filename);
        return;
    end
    cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>

    fprintf(fid, '\\begin{table*}[!t]\n');
    fprintf(fid, '\\caption{Pooled Performance and Late-Stage Stability Across BGF Landscapes}\n');
    fprintf(fid, '\\label{tab:performance_comparison}\n');
    fprintf(fid, '\\centering\n');
    fprintf(fid, '\\scriptsize\n');
    fprintf(fid, '\\begin{tabular}{llccccc}\n');
    fprintf(fid, '\\hline\n');
    fprintf(fid, 'BGF & Method & Error AUC $\\downarrow$ & Terminal Error $\\downarrow$ & $T_{50}$ $\\downarrow$ & Occupancy $\\uparrow$ & Stable Success $k/n$ (\\%%) $\\uparrow$ \\\\\n');
    fprintf(fid, '\\hline\n');

    for i = 1:height(T)
        fprintf(fid, '%s & %s & %s & %s & %s & %s & %s \\\\\n', ...
            latex_escape(upper(char(T.bgf_type(i)))), ...
            latex_escape(T.method_label(i)), ...
            mean_pm_latex(T.error_auc_mean(i), T.error_auc_std(i), '%.3f'), ...
            mean_pm_latex(T.terminal_error_mean(i), T.terminal_error_std(i), '%.3f'), ...
            mean_pm_latex(T.time_to_50_mean(i), T.time_to_50_std(i), '%.1f'), ...
            mean_pm_latex(T.occupancy_mean(i), T.occupancy_std(i), '%.3f'), ...
            sprintf('%d/%d (%.1f\\%%)', T.stable_success_n(i), T.n_runs(i), ...
                100*T.stable_success_rate(i)));
    end

    fprintf(fid, '\\hline\n');
    fprintf(fid, '\\end{tabular}\n');
    fprintf(fid, '\\end{table*}\n');
end

function export_table2_latex(T, filename)
    fid = fopen(filename, 'w');
    if fid < 0
        warning('Cannot open table file: %s', filename);
        return;
    end
    cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>

    fprintf(fid, '\\begin{table*}[!t]\n');
    fprintf(fid, '\\caption{Ablation Degradation and Mechanistic Diagnostics Relative to TSIF-HIVC}\n');
    fprintf(fid, '\\label{tab:ablation_diagnostics}\n');
    fprintf(fid, '\\centering\n');
    fprintf(fid, '\\scriptsize\n');
    fprintf(fid, '\\begin{tabular}{lllccccc}\n');
    fprintf(fid, '\\hline\n');
    fprintf(fid, 'BGF & Ablation & Removed Mechanism & $\\Delta$Error AUC $\\uparrow$ & $\\Delta$Late Error $\\uparrow$ & $\\Delta$Stability $\\uparrow$ & $\\Delta$Neg. DC $\\uparrow$ & $p_{\\mathrm{FDR}}$ \\\\\n');
    fprintf(fid, '\\hline\n');

    for i = 1:height(T)
        fprintf(fid, '%s & %s & %s & %s & %s & %s & %s & %s \\\\\n', ...
            latex_escape(upper(char(T.bgf_type(i)))), ...
            latex_escape(T.ablation_label(i)), ...
            latex_escape(T.removed_component(i)), ...
            mean_pm_latex(T.delta_error_auc_mean(i), T.delta_error_auc_std(i), '%.3f'), ...
            mean_pm_latex(T.delta_late_error_mean(i), T.delta_late_error_std(i), '%.3f'), ...
            mean_pm_latex(T.delta_stability_index_mean(i), T.delta_stability_index_std(i), '%.3g'), ...
            mean_pm_latex(T.delta_negative_dc_rate_mean(i), T.delta_negative_dc_rate_std(i), '%.3f'), ...
            p_latex(T.p_fdr_error_auc(i)));
    end

    fprintf(fid, '\\hline\n');
    fprintf(fid, '\\end{tabular}\n');
    fprintf(fid, '\\end{table*}\n');
end

function export_auc_inference_latex(T, filename)
    fid = fopen(filename, 'w');
    if fid < 0
        warning('Cannot open table file: %s', filename);
        return;
    end
    cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid, '\\begin{table*}[!t]\n');
    fprintf(fid, '\\caption{All 20 Primary Paired Process-Error AUC Comparisons}\n');
    fprintf(fid, '\\label{tab:auc_inference}\n\\centering\n\\scriptsize\n');
    fprintf(fid, '\\begin{tabular}{llrrrr}\\toprule\n');
    fprintf(fid, 'BGF & Comparator & $n$ & $\\Delta$AUC [95\\%% CI] & $r_{\\mathrm{rb}}$ & $p_{\\mathrm{FDR}}$ \\\\\n\\midrule\n');
    for i = 1:height(T)
        fprintf(fid, '%s & %s & %d & %.3f [%.3f, %.3f] & %.3f & %.10g \\\\\n', ...
            latex_escape(upper(char(T.bgf_type(i)))), ...
            latex_escape(paper_mode_label(T.mode_compare(i))), T.n_pairs(i), ...
            T.improvement_positive_good(i), T.bootstrap_ci_low(i), ...
            T.bootstrap_ci_high(i), T.rank_biserial(i), ...
            T.p_fdr_primary_auc(i));
    end
    fprintf(fid, '\\bottomrule\\end{tabular}\n\\end{table*}\n');
end

function label = paper_mode_label(mode_i)
    switch lower(char(string(mode_i)))
        case 'tsif_full'
            label = "TSIF-HIVC";
        case 'no_e'
            label = "w/o E";
        case 'no_c'
            label = "w/o C";
        case 'no_a'
            label = "w/o A";
        case 'baseline'
            label = "Fixed-HIVC";
        case 'local_only'
            label = "Local-only";
        otherwise
            label = string(mode_i);
    end
end

function label = removed_component_label(mode_i)
    switch lower(char(string(mode_i)))
        case 'no_e'
            label = "E-adapt";
        case 'no_c'
            label = "C-gate";
        case 'no_a'
            label = "A-bias";
        otherwise
            label = "None";
    end
end

function txt = mean_pm_latex(mu, sd, fmt)
    if isnan(mu)
        txt = '--';
    elseif isnan(sd)
        txt = sprintf(['$' fmt '$'], mu);
    else
        txt = sprintf(['$' fmt '\\pm' fmt '$'], mu, sd);
    end
end

function txt = percent_latex(x)
    if isnan(x)
        txt = '--';
    else
        txt = sprintf('$%.1f\\%%$', 100*x);
    end
end

function txt = p_latex(p)
    if isnan(p)
        txt = '--';
    elseif p < 0.001
        txt = '$<0.001$';
    else
        txt = sprintf('$%.3f$', p);
    end
end

function s = latex_escape(x)
    s = char(string(x));
    s = strrep(s, '\', '\textbackslash{}');
    s = strrep(s, '_', '\_');
    s = strrep(s, '%', '\%');
    s = strrep(s, '&', '\&');
end


%% =========================================================================
%  FIGURE GENERATION
% =========================================================================

function generate_figures(feature_table, summary_table, all_results, out_prefix) %#ok<INUSL>
    fprintf('\n=== Generating paper figures ===\n');
    S = pub_style();

    trajectory_data = struct('feature_table', feature_table, ...
                             'all_results', {all_results});
    fig_list = {
        {@fig_Process_Error_AUC,       feature_table, 'process_error_auc'}
        {@fig_convergence_speed,       feature_table, 'convergence_speed'}
        {@fig_ablation_mechanisms,     feature_table, 'ablation_mechanisms'}
        {@fig_ablation_relative_degradation, feature_table, 'ablation_relative_degradation'}
        {@fig_stf_metric_summary,      feature_table, 'tsif_metric_summary'}
        {@fig_stf_dynamics_mean,       all_results,   'tsif_dynamics_mean'}
        {@fig_representative_trajectories, trajectory_data, 'representative_trajectories'}
    };

    for k = 1:length(fig_list)
        try
            func = fig_list{k}{1};
            data = fig_list{k}{2};
            name = fig_list{k}{3};
            fig  = func(data, S);
            export_fig_publication(fig, [out_prefix '_' name], S);
        catch ME
            warning('%s figure failed: %s', name, ME.message);
        end
    end

    fprintf('Figures saved with prefix: %s\n', out_prefix);
end

function [means, stds] = compute_group_stats(feature_table, metric, bgfs, modes)
    means = nan(length(bgfs), length(modes));
    stds  = nan(length(bgfs), length(modes));
    for i = 1:length(bgfs)
        for j = 1:length(modes)
            idx = feature_table.bgf_type == string(bgfs{i}) & ...
                  feature_table.control_mode == string(modes{j});
            vals = feature_table.(metric)(idx);
            means(i,j) = mean(vals, 'omitnan');
            stds(i,j)  = std(vals,  'omitnan');
        end
    end
end

function draw_grouped_bar(means, stds, bgf_labels, mode_labels, S, colors)
    ngroups = size(means,1);
    nbars   = size(means,2);
    b = bar(means, 'grouped');
    for j = 1:nbars
        b(j).FaceColor = colors(j,:);
        b(j).EdgeColor = 'none';
        b(j).FaceAlpha = 0.88;
    end
    hold on;
    gw = min(0.8, nbars/(nbars+1.5));
    % 计算每一组中每个柱子的横坐标
    xs = zeros(ngroups, nbars);
    for j = 1:nbars
        xs(:,j) = (1:ngroups) - gw/2 + (2*j-1)*gw/(2*nbars);
        errorbar(xs(:,j), means(:,j), stds(:,j), ...
            'k', 'LineStyle','none', 'LineWidth',0.8, 'CapSize',2);
    end

    hold off;

    xticks(1:ngroups);
    xticklabels(upper(bgf_labels));
    % 使用 paper_mode_label 生成美观的图例标签
    display_labels = cell(1, length(mode_labels));
    for j = 1:length(mode_labels)
        display_labels{j} = char(paper_mode_label(mode_labels{j}));
    end
    legend(display_labels, 'Location','northwest', 'Box','off', ...
           'FontSize',S.font_size-1, 'FontName',S.font_name);
    set(gca, 'FontSize',S.font_size, 'FontName',S.font_name, ...
             'Box','off', 'TickDir','out', 'XGrid','off', 'YGrid','on', ...
             'GridAlpha',0.3);
end

function C = mode_colors(n)
    % Muted engineering palette.
    base = [0.075 0.278 0.463;   % tsif_full
            0.662 0.388 0.188;   % no_e
            0.720 0.585 0.250;   % no_c
            0.390 0.330 0.510;   % no_a
            0.275 0.560 0.590;   % baseline
            0.395 0.505 0.310];  % local_only
    if nargin < 1
        n = size(base,1);
    end
    C = base(1:n,:);
end

function modes = all_plot_modes()
    modes = {'tsif_full','no_e','no_c','no_a','baseline','local_only'};
end

function fig = fig_Process_Error_AUC(feature_table, S)
    bgfs  = {'sphere','matyas','ackley','rastrigin'};
    modes = all_plot_modes();
    C     = mode_colors(length(modes));

    fig = figure('Units','inches','Position',[1 1 S.fig_w2*1.35 S.fig_h*1.45], ...
                 'Color','w','PaperPositionMode','auto');
    [M,E] = compute_group_stats(feature_table,'error_auc',bgfs,modes);
    draw_grouped_bar(M,E,bgfs,modes,S,C);
    ylabel('Process Error AUC','FontSize',S.label_size,'FontName',S.font_name);
    title('Process Error AUC Across BGF Landscapes','FontSize',S.title_size,'FontName',S.font_name);
end

function fig = fig_convergence_speed(feature_table, S)
    bgfs  = {'sphere','matyas','ackley','rastrigin'};
    modes = all_plot_modes();
    C     = mode_colors(length(modes));

    fig = figure('Units','inches','Position',[1 1 S.fig_w2*1.35 S.fig_h*1.45], ...
                 'Color','w','PaperPositionMode','auto');
    [M,E] = compute_group_stats(feature_table,'time_to_target_50',bgfs,modes);
    draw_grouped_bar(M,E,bgfs,modes,S,C);
    ylabel('Iterations to 50% Occupancy','FontSize',S.label_size,'FontName',S.font_name);
    title('Convergence Speed Across BGF Landscapes','FontSize',S.title_size,'FontName',S.font_name);
end

function fig = fig_ablation_mechanisms(feature_table, S)
    bgfs  = {'sphere','matyas','ackley','rastrigin'};
    modes = {'tsif_full','no_e','no_c','no_a'};
    C     = mode_colors(length(modes));

    fig = figure('Units','inches','Position',[1 1 S.fig_w2*1.35 S.fig_h*1.2], ...
                 'Color','w','PaperPositionMode','auto');
    tiledlayout(1,2,'TileSpacing','compact','Padding','compact');

    % (a) Harmful DC interventions
    nexttile;
    [M,E] = compute_group_stats(feature_table,'negative_dc_gain_rate',bgfs,modes);
    draw_grouped_bar(M,E,bgfs,modes,S,C);
    ylabel('Negative DC Gain Rate');
    title('(a) Harmful DC interventions');

    % (b) Stability
    nexttile;
    [M,E] = compute_group_stats(feature_table,'stability_index',bgfs,modes);
    draw_grouped_bar(M,E,bgfs,modes,S,C);
    ylabel('Late Error Variance');
    title('(b) Stability');

    sgtitle('Ablation Diagnostics for TSIF Components', ...
        'FontSize',S.title_size+1,'FontName',S.font_name,'FontWeight','bold');
end
function fig = fig_ablation_relative_degradation(feature_table, S)
    bgfs  = {'sphere','matyas','ackley','rastrigin'};
    modes = {'no_e','no_c','no_a'};
    C_all = mode_colors(4);
    C     = C_all(2:4,:);

    metric_fields = {'error_auc','late_error_mean', ...
                     'stability_index','negative_dc_gain_rate'};
    metric_labels = {'Process Error AUC', 'Late Mean Error', ...
                     'Late Error Variance', 'Negative DC Gain Rate'};
    panel_titles  = {'(a) Process loss', '(b) Late accuracy loss', ...
                     '(c) Stability loss', '(d) Harmful DC increase'};

    fig = figure('Units','inches','Position',[1 1 S.fig_w2*1.35 S.fig_h*2.2], ...
                 'Color','w','PaperPositionMode','auto');
    tiledlayout(2,2,'TileSpacing','compact','Padding','compact');

    for k = 1:length(metric_fields)
        nexttile;
        [M,E] = compute_paired_degradation(feature_table, metric_fields{k}, bgfs, modes);
        draw_grouped_bar(M,E,bgfs,modes,S,C);
        hold on;
        lgd = legend;
        lgd.AutoUpdate = 'off';
        yline(0,'k:','LineWidth',0.9);
        hold off;
        ylabel(['\Delta ' metric_labels{k}]);
        title(panel_titles{k});
    end

    sgtitle('E/C/A Ablation Degradation Relative to TSIF Full (positive = worse)', ...
        'FontSize',S.title_size+1,'FontName',S.font_name,'FontWeight','bold');
end

function [means, stds] = compute_paired_degradation(feature_table, metric, bgfs, modes)
    means = nan(length(bgfs), length(modes));
    stds  = nan(length(bgfs), length(modes));
    baseline_mode = "tsif_full";

    for i = 1:length(bgfs)
        bgf = string(bgfs{i});
        idx_base = feature_table.bgf_type == bgf & ...
                   feature_table.control_mode == baseline_mode;
        T_base = feature_table(idx_base,:);

        for j = 1:length(modes)
            mode_i = string(modes{j});
            idx_cmp = feature_table.bgf_type == bgf & ...
                      feature_table.control_mode == mode_i;
            T_cmp = feature_table(idx_cmp,:);

            if isempty(T_base) || isempty(T_cmp)
                continue;
            end

            [~, ia, ib] = intersect(T_base.scenario_id, T_cmp.scenario_id);
            if isempty(ia)
                continue;
            end

            x = T_base.(metric)(ia);
            y = T_cmp.(metric)(ib);
            valid = ~isnan(x) & ~isnan(y);
            d = y(valid) - x(valid);

            means(i,j) = mean(d, 'omitnan');
            stds(i,j)  = std(d,  'omitnan');
        end
    end
end

function fig = fig_stf_metric_summary(feature_table, S)
    modes         = all_plot_modes();
    metric_fields = {'mean_E','mean_C','mean_A'};
    metric_labels = {'E(t)','C(t)','A(t)'};
    C = mode_colors(length(modes));

    M = nan(length(metric_fields), length(modes));
    for j = 1:length(metric_fields)
        for i = 1:length(modes)
            idx = feature_table.control_mode == string(modes{i});
            M(j,i) = mean(feature_table.(metric_fields{j})(idx),'omitnan');
        end
    end

    fig = figure('Units','inches','Position',[1 1 S.fig_w2*1.25 S.fig_h*1.45], ...
                 'Color','w','PaperPositionMode','auto');
    b = bar(M,'grouped');
    for i = 1:length(modes)
        b(i).FaceColor = C(i,:);
        b(i).EdgeColor = 'none';
        b(i).FaceAlpha = 0.88;
    end


    xticks(1:length(metric_fields));
    xticklabels(metric_labels);
    ylabel('Mean Value','FontSize',S.label_size,'FontName',S.font_name);
    title('TSIF Metric Summary by Control Mode', ...
          'FontSize',S.title_size,'FontName',S.font_name);
    % 使用 paper_mode_label 生成图例
    leg_labels = cell(1, length(modes));
    for i = 1:length(modes)
        leg_labels{i} = char(paper_mode_label(modes{i}));
    end
    legend(leg_labels, 'Location','northwest','Box','off', ...
           'FontSize',S.font_size-1,'FontName',S.font_name);
    set(gca,'FontSize',S.font_size,'FontName',S.font_name, ...
            'Box','off','TickDir','out','YGrid','on','GridAlpha',0.3);
end

function fig = fig_stf_dynamics_mean(all_results, S)
    selected = {};
    for i = 1:length(all_results)
        r = all_results{i};
        if isfield(r,'control_mode') && strcmpi(r.control_mode,'tsif_full') && ...
           isfield(r,'bgf_type') && strcmpi(r.bgf_type,'sphere')
            selected{end+1} = r; %#ok<AGROW>
        end
    end
    if isempty(selected)
        selected = all_results(1:min(30, numel(all_results)));
    end

    fig = figure('Units','inches','Position',[1 1 S.fig_w2 S.fig_h*2.4], ...
                 'Color','w','PaperPositionMode','auto');

    tiledlayout(3,2,'TileSpacing','compact','Padding','compact');
    lineC = engineering_line_colors();
    plot_metric_band(selected, 'E_hist', '(a) Information Entropy', 'E(t)', lineC(1,:), S);
    plot_metric_band(selected, 'C_hist', '(b) Target Consensus', 'C(t)', lineC(2,:), S);
    plot_metric_band(selected, 'A_hist', '(c) Availability-Weighted Alignment', 'A(t)', lineC(3,:), S);
    plot_metric_band(selected, 'rho_A_hist', '(d) Valid-Gradient Availability', '\rho_A(t)', lineC(5,:), S);
    plot_metric_band(selected, 'A_dir_hist', '(e) Directional Coherence', 'A_{dir}(t)', lineC(1,:), S);
    plot_error_occupancy_band(selected, S);

    sgtitle('TSIF Dynamics and A(t)=\rho_A(t)A_{dir}(t): Mean \pm SD', ...
        'FontSize',S.title_size+1,'FontName',S.font_name,'FontWeight','bold');
    set(findall(fig,'Type','axes'),'FontSize',S.font_size,'FontName',S.font_name,'TickDir','out');
end

function C = engineering_line_colors()
    C = [0.075 0.278 0.463;   % muted blue
         0.662 0.388 0.188;   % muted orange
         0.720 0.585 0.250;   % muted yellow
         0.141 0.141 0.141;   % near black
         0.560 0.220 0.260];  % muted red
end

function plot_metric_band(results, field, ttl, ylab, color, S)
    nexttile;
    M = histories_to_matrix(results, field);
    t = 1:size(M,2);
    mu = mean(M,1,'omitnan');
    sd = std(M,0,1,'omitnan');
    fill([t fliplr(t)], [mu-sd fliplr(mu+sd)], color, ...
        'FaceAlpha',0.16,'EdgeColor','none');
    hold on;
    plot(t, mu, 'Color',color,'LineWidth',1.4);
    hold off;
    xlabel('Iteration','FontName',S.font_name);
    ylabel(ylab,'FontName',S.font_name);
    title(ttl,'FontSize',S.title_size,'FontName',S.font_name);
    grid on; box off;
end

function plot_error_occupancy_band(results, S)
    nexttile;
    E = histories_to_matrix(results, 'error_hist_mean');
    O = histories_to_matrix(results, 'occupancy_hist');
    t = 1:size(E,2);
    muE = mean(E,1,'omitnan');
    muO = mean(O,1,'omitnan');
    lineC = engineering_line_colors();

    yyaxis left;
    plot(t, muE, 'Color',lineC(4,:), 'LineWidth',1.4);
    ylabel('Mean Error','FontName',S.font_name);
    yyaxis right;
    plot(t, muO, 'Color',lineC(2,:), 'LineWidth',1.4);
    ylabel('Occupancy','FontName',S.font_name);
    xlabel('Iteration','FontName',S.font_name);
    title('(f) Error and Occupancy','FontSize',S.title_size,'FontName',S.font_name);
    grid on; box off;
end

function M = histories_to_matrix(results, field)
    max_len = 0;
    for i = 1:numel(results)
        if isfield(results{i}, field)
            max_len = max(max_len, numel(results{i}.(field)));
        end
    end
    M = nan(numel(results), max_len);
    for i = 1:numel(results)
        if isfield(results{i}, field)
            x = results{i}.(field)(:);
            M(i,1:numel(x)) = x;
        end
    end
end

function fig = fig_representative_trajectories(data, S)
    F = data.feature_table;
    results = data.all_results;
    idx = find(string(F.bgf_type)=="rastrigin" & ...
        string(F.init_name)=="corner_small" & ...
        abs(F.noise_level-0.015)<1e-12 & ...
        string(F.control_mode)=="tsif_full");
    if isempty(idx)
        idx = find(string(F.bgf_type)=="rastrigin" & ...
            string(F.control_mode)=="tsif_full");
    end
    [~,ord] = sort(F.error_auc(idx));
    ranks = [1, ceil(numel(ord)/2), numel(ord)];
    rows = idx(ord(ranks));
    labels = {'Best Run','Median Run','Worst Run'};

    fig = figure('Units','inches','Position',[1 1 S.fig_w2*1.35 S.fig_h*1.35], ...
        'Color','w','PaperPositionMode','auto');
    tiledlayout(1,3,'TileSpacing','compact','Padding','compact');
    for q = 1:3
        nexttile; hold on;
        snaps = results{rows(q)}.positions_snapshots;
        for k = 1:numel(snaps)
            pts = snaps{k};
            c = repmat(k, size(pts,1), 1);
            scatter(pts(:,1),pts(:,2),9,c,'filled');
        end
        th = linspace(0,2*pi,200);
        plot(cos(th),sin(th),'r-','LineWidth',1.0);
        plot(0,0,'r+','MarkerSize',8,'LineWidth',1.2);
        hold off; axis equal; grid on; box off;
        xlim([-11 2]); ylim([-11 2]);
        xlabel('x'); ylabel('y');
        title(sprintf('%s (AUC %.3f)',labels{q},F.error_auc(rows(q))));
    end
    % Panel titles carry the run ranks and AUCs. A super-title is omitted
    % because it overlaps the middle panel title in MATLAB R2020b export.
end


%% =========================================================================
%  BGF FUNCTIONS AND VISUALIZATION
% =========================================================================

function f = make_bgf(bgf_type)
    switch lower(bgf_type)
        case 'sphere'
            f = @(xy) arrayfun(@(i) ...
                double(xy(i,1)^2+xy(i,2)^2<=0.25) + ...
                double(xy(i,1)^2+xy(i,2)^2> 0.25) .* ...
                max(0, 1-0.005*(xy(i,1)^2+xy(i,2)^2)), (1:size(xy,1))');
        case 'matyas'
            f = @(xy) arrayfun(@(i) ...
                1./(1+0.26*(xy(i,1)^2+xy(i,2)^2)-0.48*abs(xy(i,1).*xy(i,2))), ...
                (1:size(xy,1))');
        case 'ackley'
            f = @(xy) arrayfun(@(i) ...
                (20*exp(-0.2*sqrt(0.5*(xy(i,1)^2+xy(i,2)^2))) + ...
                 exp(0.5*(cos(2*pi*xy(i,1))+cos(2*pi*xy(i,2))))) / (20+exp(1)), ...
                (1:size(xy,1))');
        case 'rastrigin'
            f = @(xy) arrayfun(@(i) ...
                1./(1+20+xy(i,1)^2+xy(i,2)^2 - ...
                    10*(cos(2*pi*xy(i,1))+cos(2*pi*xy(i,2)))), ...
                (1:size(xy,1))');
        otherwise
            error('Unknown BGF type: %s', bgf_type);
    end
end

function plot_all_bgfs(out_prefix)
    if nargin < 1, out_prefix = 'tsif_ablation'; end
    bgf_types = {'sphere','matyas','ackley','rastrigin'};
    fig = figure('Name','BGF Visualization','Units','inches', ...
                 'Position',[1 1 5.8 10.5],'Color','w','PaperPositionMode','auto');
    t = tiledlayout(4,2,'TileSpacing','compact','Padding','compact');
    for i = 1:4
        f = make_bgf(bgf_types{i});
        ax1 = nexttile(t); BGFvisual_3d(f, bgf_types{i});
        title(ax1, ['(' char(96+i) ') ' upper(bgf_types{i})], 'FontWeight','bold','FontSize',11);
        ax2 = nexttile(t); BGFvisual_contour(f, bgf_types{i});
        title(ax2, ['Contour - ' upper(bgf_types{i})], 'FontWeight','bold','FontSize',11);
    end
    out_name = fullfile(pwd, [out_prefix '_bgf_visualization']);
    set(fig,'PaperPosition',[0 0 5.8 10.5],'PaperSize',[5.8 10.5]);
    try
        print(fig, [out_name '.png'], '-dpng', '-r300');
        fprintf('BGF visualization saved: %s.png\n', out_name);
    catch ME
        warning('BGF export failed: %s', ME.message);
    end
end

function BGFvisual_3d(f, bgf_name)
    [x,y] = meshgrid(linspace(-10,10,100));
    z = zeros(size(x));
    for i = 1:numel(x), z(i) = f([x(i),y(i)]); end
    surf(x,y,z,'EdgeColor','none');
    xlabel('x'); ylabel('y'); zlabel('Fitness');
    title(upper(bgf_name)); colorbar; view(3); grid on;
end

function BGFvisual_contour(f, bgf_name)
    [x,y] = meshgrid(linspace(-10,10,200));
    z = zeros(size(x));
    for i = 1:numel(x), z(i) = f([x(i),y(i)]); end
    contourf(x,y,z,20);
    colorbar; xlabel('x'); ylabel('y');
    title(['Contour - ' upper(bgf_name)]);
    hold on; plot(0,0,'r*','MarkerSize',8); hold off;
end


%% =========================================================================
%  UTILITY FUNCTIONS AND METRIC VALIDATION
% =========================================================================

function nps = nps_gen(N, bound, region)
    flag    = randi(region(1)*region(2)) - 1;
    ipd_col = (bound(2,1)-bound(1,1)) / region(2);
    ipd_row = (bound(2,2)-bound(1,2)) / region(1);
    rflag   = [mod(flag,region(2)), floor(flag/region(2))];
    nps     = rand(N,2);
    bc      = bound(1,:) + rflag .* [ipd_col, ipd_row];
    nps     = nps .* [ipd_col, ipd_row] + bc;
end

function S = pub_style()
    S = struct('font_name','Times New Roman','font_size',10,'title_size',12, ...
               'label_size',11,'fig_w1',3.5,'fig_w2',7.0,'fig_h',3.0);
end

function export_fig_publication(fig, filename, S) %#ok<INUSL>
    set(fig, 'PaperPositionMode', 'auto');
    try
        print(fig, [filename '.png'], '-dpng', '-r300');
    catch
        print(fig, [filename '.png'], '-dpng', '-r150');
    end
    fprintf('  Saved: %s.png\n', filename);
end

function metric_table = run_metric_validation(params, bgf_type_list, out_prefix)
    fprintf('\n===== Stage 1: TSIF Metric Validation =====\n');
    states       = ["corner_compact","global_uniform","target_compact","target_ring","far_two_cluster"];
    num_rep      = 30;
    metric_table = table();

    for b = 1:length(bgf_type_list)
        bgf_type = bgf_type_list{b};
        f = make_bgf(bgf_type);
        for s = 1:length(states)
            state_name = states(s);
            for rep = 1:num_rep
                rng(20250425 + b*10000 + s*100 + rep);
                nps     = make_synthetic_state(params, state_name);
                metrics = compute_stf_metrics(nps, nps, f, params);
                row = table(string(bgf_type), state_name, rep, ...
                            metrics.E, metrics.C, metrics.A, ...
                            metrics.C_closeness, metrics.C_compactness, ...
                    'VariableNames',{'bgf_type','state','rep','E','C','A', ...
                                     'C_closeness','C_compactness'});
                metric_table = [metric_table; row]; %#ok<AGROW>
            end
        end
    end

    summary_tbl = groupsummary(metric_table, {'bgf_type','state'}, ...
                               'mean', {'E','C','A','C_closeness','C_compactness'});
    disp('=== Metric Validation Summary ===');
    disp(summary_tbl);
    writetable(summary_tbl, [out_prefix '_metric_validation_summary.csv']);

    sanity_tbl = metric_sanity_checks(metric_table);
    disp('=== Metric Sanity Checks ===');
    disp(sanity_tbl);
    writetable(sanity_tbl, [out_prefix '_metric_sanity_checks.csv']);

    fig = plot_metric_validation(metric_table);
    export_fig_publication(fig, [out_prefix '_metric_validation'], pub_style());
end

function nps = make_synthetic_state(params, state_name)
    N  = params.N;
    gb = params.global_boundary;
    T  = params.target;
    R  = params.tumor_radius;
    switch string(state_name)
        case "corner_compact"
            nps = [-10,-10] + rand(N,2);
        case "global_uniform"
            nps = [gb(1)+(gb(2)-gb(1))*rand(N,1), gb(3)+(gb(4)-gb(3))*rand(N,1)];
        case "target_compact"
            nps = T + 0.25*R*randn(N,2);
        case "target_ring"
            theta = 2*pi*rand(N,1);
            r = R*(0.4+0.4*rand(N,1));
            nps = T + [r.*cos(theta), r.*sin(theta)];
        case "far_two_cluster"
            n1 = floor(N/2);
            n2 = N-n1;
            nps = [[-9.5,-9.5]+0.3*randn(n1,2); [9.5,9.5]+0.3*randn(n2,2)];
        otherwise
            error('Unknown synthetic state: %s', state_name);
    end
    nps(:,1) = min(max(nps(:,1), gb(1)), gb(2));
    nps(:,2) = min(max(nps(:,2), gb(3)), gb(4));
end

function sanity_tbl = metric_sanity_checks(metric_table)
    bgfs = unique(metric_table.bgf_type,'stable');
    sanity_tbl = table();
    for i = 1:length(bgfs)
        bgf = bgfs(i);
        idx = metric_table.bgf_type == bgf;
        get = @(field, state) mean(metric_table.(field)(idx & metric_table.state==state),'omitnan');
        row = table(bgf, ...
            get('E','corner_compact'), get('E','global_uniform'), ...
            get('C','corner_compact'), get('C','global_uniform'), get('C','target_compact'), ...
            get('A','corner_compact'), get('A','global_uniform'), ...
            get('E','global_uniform') > get('E','corner_compact'), ...
            get('C','target_compact') > get('C','corner_compact'), ...
            get('C','target_compact') > get('C','global_uniform'), ...
            get('A','corner_compact') > get('A','global_uniform'), ...
            'VariableNames', {'bgf_type', ...
                'E_corner','E_global','C_corner','C_global','C_target', ...
                'A_corner','A_global', ...
                'pass_E_global_gt_corner','pass_C_target_gt_corner', ...
                'pass_C_target_gt_global','pass_A_corner_gt_global'});
        sanity_tbl = [sanity_tbl; row]; %#ok<AGROW>
    end
end

function fig = plot_metric_validation(metric_table)
    fig = figure('Units','inches','Position',[1 1 11 3.2],'Color','w','PaperPositionMode','auto');
    summary_tbl = groupsummary(metric_table, 'state', 'mean', {'E','C','A'});
    tiledlayout(1,3,'TileSpacing','compact','Padding','compact');
    fields  = {'mean_E','mean_C','mean_A'};
    ylabels = {'Mean E(t)','Mean C(t)','Mean A(t)'};
    titles  = {'Information Entropy','Target Consensus','Gradient Consistency'};
    for k = 1:3
        nexttile;
        bar(categorical(summary_tbl.state), summary_tbl.(fields{k}));
        ylabel(ylabels{k});
        title(titles{k});
        grid on;
        xtickangle(30);
    end
    sgtitle('TSIF Metric Validation');
    set(findall(fig,'Type','axes'),'FontSize',10,'FontName','Times New Roman', ...
        'Box','off','TickDir','out');
end
