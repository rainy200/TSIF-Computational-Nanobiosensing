function main_tsif_aivc_revised(run_mode)
%MAIN_TSIF_AIVC_REVISED Target-free TSIF-on-AIVC comparison.
% Compares TSIF-AIVC, w/o E, w/o C, w/o A, Fixed-AIVC, and article-based P-AIVC.
% Control uses positions, neighbor relations, and one local BGF sample per agent;
% the true target is used only by the common evaluation layer.
%
% Modes: smoke (24 runs), quick (432), formal (4320), merge, and figures.
% Formal runs lock the base seed at 20261217.

    if nargin < 1 || isempty(run_mode), run_mode = 'formal'; end
    run_mode = lower(strtrim(char(run_mode)));
    close all;

    P = setup_parameters();
    D = setup_design(run_mode);
    [P,D] = apply_environment_overrides(P,D);
    ensure_folder(D.output_dir);

    if strcmp(run_mode,'merge')
        [feature_table, all_results, P_run, D_run] = merge_shards(D);
        D_run.output_dir = D.output_dir;
        D_run.output_prefix = D.output_prefix;
        D_run.bootstrap_samples = D.bootstrap_samples;
        D_run.shard_count = 1;
        D_run.shard_index = 1;
        D_run.raw_only = false;
        finish_analysis(feature_table, all_results, P_run, D_run);
        return;
    elseif strcmp(run_mode,'figures')
        feature_file = getenv('AIVC_FEATURE_FILE');
        if isempty(feature_file)
            feature_file = fullfile(D.output_dir,[D.output_prefix '_feature.csv']);
        end
        feature_table = readtable(feature_file);
        feature_table = normalize_text_columns(feature_table);
        stats_table = run_auc_comparisons(feature_table,D.bootstrap_samples,D.base_seed);
        generate_figures(feature_table,stats_table,D);
        fprintf('Autonomous AIVC figures regenerated from %s\n',feature_file);
        return;
    end

    export_method_switch_table(D);
    export_configuration(P,D);
    [feature_table, all_results] = run_sweep(P,D);
    audit_design(feature_table,D,P);

    raw_mat = fullfile(D.output_dir,[D.output_prefix '_results.mat']);
    raw_csv = fullfile(D.output_dir,[D.output_prefix '_feature.csv']);
    save(raw_mat,'feature_table','all_results','P','D','-v7.3');
    writetable(feature_table,raw_csv);

    if D.shard_count > 1 || D.raw_only
        fprintf('Raw shard complete: %d runs. Analysis deferred until merge.\n',height(feature_table));
        return;
    end
    finish_analysis(feature_table,all_results,P,D);
end

function P = setup_parameters()
    P = struct();

    P.N = 40;
    P.boundary = [-11 11 -11 11];
    P.target = [0 0];
    P.target_radius = 1.0;
    P.max_iteration = 850;

    % Map article-reported lengths for a 0.5-mm target to the common R_T=1 coordinates.
    P.paivc_length_scale = P.target_radius/0.5;
    P.paivc_neighbor_count = 20;
    P.paivc_migration_step = 0.04*P.paivc_length_scale;
    P.paivc_path_loss_index = 0.50;       % missing in article; author-code value
    P.paivc_reference_distance = 1.00*P.paivc_length_scale;
    P.paivc_sensing_mu = 0;
    P.paivc_sensing_sigma = 0.02;
    P.paivc_stop_radius = P.target_radius;
    P.paivc_flocking_radius = 2.00*P.paivc_length_scale;
    P.paivc_adsorption_step = 0.02*P.paivc_length_scale;
    P.paivc_adsorption_lambda = 1.00/P.paivc_length_scale;
    P.paivc_territorial_radius = 1.00*P.paivc_length_scale;
    P.paivc_min_force_radius = 0.05*P.paivc_length_scale;
    P.paivc_viscosity = 0.04;
    P.paivc_Q0 = 1.34;
    P.paivc_entropy0 = 44.31;
    P.paivc_Q_noise_mu = 0;
    P.paivc_Q_noise_sigma = 0.02;
    P.paivc_entropy_bins = 50;            % L omitted in article
    P.paivc_sampling_T0 = 1.0;            % T0 omitted in article
    P.paivc_repulsion_step_cap = 2*P.paivc_migration_step;

    % Target-free TSIF uses attainable-range entropy, local compactness and BGF rank,
    % and neighborhood directional coherence without additional BGF queries.
    P.entropy_bins_per_axis = ceil(sqrt(P.N));
    P.vector_valid_threshold = 1e-12;
    P.progress_ema_alpha = 0.08;
    P.progress_tolerance = 2.5e-4;

    % E schedules native BGF-directed migration magnitude without changing its
    % direction or number of BGF queries.
    P.E_low = 0.18;
    P.E_high = 0.55;
    P.E_gain = 0.60;
    P.E_gain_min = 1.00;
    P.E_gain_max = 1.48;

    % C gates social displacement and validates stopping through local and
    % temporally confirmed evidence.
    P.C_gain = 0.88;
    P.C_rank_threshold = 0.35;
    P.C_progress_floor = 0.35;
    P.C_fitness_threshold = 0.70;
    P.C_migration_brake = 0.58;
    P.C_hold_rank_threshold = 0.70;
    P.C_hold_compactness_threshold = 0.20;
    P.C_hold_confirmations = 2;
    P.C_rescue_elite_rank = 0.75;
    P.C_rescue_fitness_threshold = 0.97;
    P.C_rescue_gain = 1.00;

    % A blends each cooperative direction with its neighborhood mean using a
    % one-sided, norm-preserving correction.
    P.A_activation = 0.40;
    P.A_gain = 0.58;
    P.A_max_blend = 0.45;
    P.A_speed_gain = 0.65;

    % Target-free hold rule based on the article's noisy local-fitness threshold.
    P.paivc_hold_fitness_threshold = 0.995;

    % Fixed-AIVC multipliers are pooled full-method averages from an independent
    % 72-scenario development design (seed 17320508), frozen before formal testing.
    P.fixed_E_scale = 1.036827816643871;
    P.fixed_C_strength = 0.093505308269833;
    P.fixed_A_blend = 0.150764873190314;

    % Exploratory secondary endpoint; thresholds were not independently preregistered.
    P.success_terminal_error = 1.5;
    P.success_occupancy = 0.35;
    P.success_late_fraction = 0.20;
    P.success_required_fraction = 0.80;
    P.success_t50_fraction = 0.85;
end

function D = setup_design(run_mode)
    D = struct();
    D.run_mode = run_mode;
    D.seed_locked = strcmp(run_mode,'formal');
    D.methods = {'tsif_aivc','aivc_no_e','aivc_no_c','aivc_no_a', ...
                 'fixed_aivc','local_only'};
    D.bgfs = {'sphere','matyas','ackley','rastrigin'};
    D.inits = {'corner_small','corner_large','random'};
    D.position_noise_levels = [0 0.015];
    D.num_seeds = 30;
    D.base_seed = 20261217;               % untouched final holdout seed
    D.bootstrap_samples = 2000;
    D.shard_count = 1;
    D.shard_index = 1;
    D.raw_only = false;
    D.output_dir = fullfile(pwd,'autonomous_results');
    D.output_prefix = 'tsif_aivc_separate_formal_seed20261217';

    switch run_mode
        case 'smoke'
            D.inits = {'corner_small'};
            D.position_noise_levels = 0;
            D.num_seeds = 1;
            D.bootstrap_samples = 200;
            D.base_seed = 91001;
            D.output_dir = fullfile(pwd,'diagnostic','autonomous_smoke');
            D.output_prefix = 'tsif_aivc_autonomous_smoke';
        case 'quick'
            D.num_seeds = 3;
            D.bootstrap_samples = 500;
            D.base_seed = 31415927;
            D.output_dir = fullfile(pwd,'diagnostic','autonomous_quick');
            D.output_prefix = 'tsif_aivc_autonomous_quick';
        case {'formal','merge','figures'}
        otherwise
            error('Unknown run_mode: %s',run_mode);
    end
end

function [P,D] = apply_environment_overrides(P,D)
    D.num_seeds = env_number('AIVC_NUM_SEEDS',D.num_seeds,1,Inf,true);
    requested_seed = env_number('AIVC_BASE_SEED',D.base_seed,0,2^31-1,true);
    if D.seed_locked && requested_seed~=D.base_seed
        error(['Formal seed is locked at %d. Remove AIVC_BASE_SEED or set ' ...
            'it to the same value.'],D.base_seed);
    end
    D.base_seed = requested_seed;
    D.bootstrap_samples = env_number('AIVC_BOOTSTRAP_SAMPLES',D.bootstrap_samples,100,Inf,true);
    D.shard_count = env_number('AIVC_SHARD_COUNT',D.shard_count,1,Inf,true);
    D.shard_index = env_number('AIVC_SHARD_INDEX',D.shard_index,1,D.shard_count,true);
    P.max_iteration = env_number('AIVC_MAX_ITERATION',P.max_iteration,10,Inf,true);
    P.progress_ema_alpha = env_number('AIVC_PROGRESS_ALPHA',P.progress_ema_alpha,0.001,1,false);
    P.progress_tolerance = env_number('AIVC_PROGRESS_TOL',P.progress_tolerance,1e-8,0.1,false);
    P.E_low = env_number('AIVC_E_LOW',P.E_low,0,1,false);
    P.E_high = env_number('AIVC_E_HIGH',P.E_high,0,1,false);
    P.E_gain = env_number('AIVC_E_GAIN',P.E_gain,0,10,false);
    P.C_gain = env_number('AIVC_C_GAIN',P.C_gain,0,1,false);
    P.C_rank_threshold = env_number('AIVC_C_RANK_THRESHOLD',P.C_rank_threshold,0,0.999,false);
    P.C_progress_floor = env_number('AIVC_C_PROGRESS_FLOOR',P.C_progress_floor,0,1,false);
    P.C_fitness_threshold = env_number('AIVC_C_FITNESS_THRESHOLD',P.C_fitness_threshold,0,0.999,false);
    P.C_migration_brake = env_number('AIVC_C_MIGRATION_BRAKE',P.C_migration_brake,0,1,false);
    P.C_hold_rank_threshold = env_number('AIVC_C_HOLD_RANK',P.C_hold_rank_threshold,0,1,false);
    P.C_hold_compactness_threshold = env_number('AIVC_C_HOLD_COMPACTNESS',P.C_hold_compactness_threshold,0,1,false);
    P.C_hold_confirmations = env_number('AIVC_C_HOLD_CONFIRMATIONS',P.C_hold_confirmations,1,20,true);
    P.C_rescue_elite_rank = env_number('AIVC_C_RESCUE_ELITE_RANK',P.C_rescue_elite_rank,0,0.999,false);
    P.C_rescue_fitness_threshold = env_number('AIVC_C_RESCUE_FITNESS',P.C_rescue_fitness_threshold,0,1,false);
    P.C_rescue_gain = env_number('AIVC_C_RESCUE_GAIN',P.C_rescue_gain,0,1,false);
    P.A_activation = env_number('AIVC_A_ACTIVATION',P.A_activation,0,0.999,false);
    P.A_gain = env_number('AIVC_A_GAIN',P.A_gain,0,1,false);
    P.A_max_blend = env_number('AIVC_A_MAX_BLEND',P.A_max_blend,0,1,false);
    P.A_speed_gain = env_number('AIVC_A_SPEED_GAIN',P.A_speed_gain,0,2,false);
    if P.E_low>=P.E_high, error('AIVC_E_LOW must be smaller than AIVC_E_HIGH.'); end

    txt = strtrim(getenv('AIVC_BGF_TYPES'));
    if ~isempty(txt), D.bgfs = parse_list(txt,{'sphere','matyas','ackley','rastrigin'}); end
    txt = strtrim(getenv('AIVC_INIT_MODES'));
    if ~isempty(txt), D.inits = parse_list(txt,{'corner_small','corner_large','random'}); end
    txt = strtrim(getenv('AIVC_METHODS'));
        if ~isempty(txt), D.methods = parse_list(txt,{'tsif_aivc','aivc_no_e','aivc_no_c', ...
            'aivc_no_a','fixed_aivc','local_only'}); end
    txt = strtrim(getenv('AIVC_POSITION_NOISE'));
    if ~isempty(txt)
        vals = str2double(strtrim(strsplit(txt,',')));
        if any(~isfinite(vals)) || any(vals<0), error('Invalid AIVC_POSITION_NOISE.'); end
        D.position_noise_levels = vals;
    end

    txt = strtrim(getenv('AIVC_OUT_DIR'));
    if ~isempty(txt), D.output_dir = txt; end
    txt = strtrim(getenv('AIVC_OUT_PREFIX'));
    if ~isempty(txt), D.output_prefix = txt; end
    D.raw_only = any(strcmpi(strtrim(getenv('AIVC_RAW_ONLY')),{'1','true','yes'}));
end

function value = env_number(name,default_value,min_value,max_value,as_integer)
    txt = strtrim(getenv(name));
    if isempty(txt), value = default_value; return; end
    value = str2double(txt);
    if ~isfinite(value) || value<min_value || value>max_value
        error('%s is outside the allowed range.',name);
    end
    if as_integer, value = floor(value); end
end

function values = parse_list(txt,allowed)
    values = strtrim(strsplit(lower(txt),','));
    if any(~ismember(values,allowed)), error('Unknown list item in: %s',txt); end
end

function ensure_folder(folder)
    if ~isfolder(folder), mkdir(folder); end
end

function [feature_table,all_results] = run_sweep(P,D)
    scenario_total = numel(D.bgfs)*numel(D.inits)*numel(D.position_noise_levels)*D.num_seeds;
    row_cells = cell(scenario_total*numel(D.methods),1);
    result_cells = cell(scenario_total*numel(D.methods),1);
    row_cursor = 0;
    scenario_cursor = 0;

    journal_file = fullfile(D.output_dir,[D.output_prefix '_run_journal.csv']);
    if isfile(journal_file), delete(journal_file); end

    fprintf('TSIF-AIVC comparison: %d scenarios x %d methods\n',scenario_total,numel(D.methods));
    for b = 1:numel(D.bgfs)
        bgf_name = D.bgfs{b};
        f = make_bgf(bgf_name);
        for ii = 1:numel(D.inits)
            init_name = D.inits{ii};
            for z = 1:numel(D.position_noise_levels)
                pos_noise = D.position_noise_levels(z);
                for seed_index = 1:D.num_seeds
                    scenario_cursor = scenario_cursor+1;
                    if mod(scenario_cursor-1,D.shard_count) ~= D.shard_index-1
                        continue;
                    end
                    scenario_id = b*10000000 + ii*100000 + z*1000 + seed_index;
                    random_seed = mod(D.base_seed+scenario_id,2^31-1);
                    [initial_positions,common] = make_common_randomness(P,random_seed,init_name);

                    fprintf('[%d/%d] %s | %s | noise %.3f | seed %02d\n', ...
                        scenario_cursor,scenario_total,bgf_name,init_name,pos_noise,seed_index);
                    for m = 1:numel(D.methods)
                        mode = D.methods{m};
                        cfg = mode_spec(mode);
                        t0 = tic;
                        result = run_trial(P,f,bgf_name,initial_positions,common,pos_noise,cfg);
                        runtime_sec = toc(t0);
                        row = result_to_row(result,P,D,bgf_name,init_name,pos_noise, ...
                            seed_index,scenario_id,random_seed,mode,cfg,runtime_sec, ...
                            initial_positions,common);
                        row_cursor = row_cursor+1;
                        row_cells{row_cursor} = struct2table(row);
                        result.method = mode;
                        result.bgf_type = bgf_name;
                        result.init_name = init_name;
                        result.position_noise = pos_noise;
                        result.seed_index = seed_index;
                        result.scenario_id = scenario_id;
                        result_cells{row_cursor} = result;
                        fprintf('  %-17s AUC %.3f | occ %.3f | T50 %d%s | %.2fs\n', ...
                            mode,result.error_auc,result.target_occupancy, ...
                            result.time_to_50,ternary(result.time_to_50_event,'','c'),runtime_sec);
                    end

                    block = vertcat(row_cells{row_cursor-numel(D.methods)+1:row_cursor});
                    if isfile(journal_file)
                        writetable(block,journal_file,'WriteMode','append','WriteVariableNames',false);
                    else
                        writetable(block,journal_file);
                    end
                end
            end
        end
    end
    row_cells = row_cells(1:row_cursor);
    result_cells = result_cells(1:row_cursor);
    feature_table = vertcat(row_cells{:});
    all_results = result_cells;
end

function cfg = mode_spec(mode)
    cfg = struct('mode',mode,'use_paivc_local',true, ...
        'use_E',true,'use_C',true,'use_A',true, ...
        'native_entropy_adaptation',true,'fixed_tsif_gains',false, ...
        'external_baseline',false,'method_role','internal_full');
    switch mode
        case 'tsif_aivc'
        case 'aivc_no_e'
            cfg.use_E = false; cfg.method_role = 'single_path_ablation';
        case 'aivc_no_c'
            cfg.use_C = false; cfg.method_role = 'single_path_ablation';
        case 'aivc_no_a'
            cfg.use_A = false; cfg.method_role = 'single_path_ablation';
        case 'fixed_aivc'
            cfg.use_E = false; cfg.use_C = false; cfg.use_A = false;
            cfg.fixed_tsif_gains = true;
            cfg.method_role = 'fixed_gain_internal_control';
        case 'local_only'
            cfg.use_E = false; cfg.use_C = false; cfg.use_A = false;
            cfg.external_baseline = true;
            cfg.method_role = 'article_based_paivc_local_only';
        otherwise
            error('Unknown AIVC mode: %s',mode);
    end
end

function [initial_positions,R] = make_common_randomness(P,seed,init_name)
    stream = RandStream('mt19937ar','Seed',seed);
    switch init_name
        case 'corner_small'
            lo = [-10 -10]; hi = [-9 -9];
        case 'corner_large'
            lo = [-10 -10]; hi = [-5 -5];
        case 'random'
            lo = [-10 -10]; hi = [10 10];
        otherwise
            error('Unknown initialization: %s',init_name);
    end
    initial_positions = rand(stream,P.N,2).*(hi-lo)+lo;
    R.sensing_z = randn(stream,P.N,P.max_iteration);
    R.q_z = randn(stream,P.max_iteration,1);
    R.position_z = randn(stream,P.N,2,P.max_iteration);
    R.checksum = sum(R.sensing_z(:))+sum(R.q_z(:))+ ...
        sum(R.position_z(:));
end

function result = run_trial(P,f,bgf_name,initial_positions,R,position_noise,cfg)
    nps = initial_positions;
    state = initialize_paivc_state(P,bgf_name);
    Pctrl = make_control_parameters(P);
    assert(~isfield(Pctrl,'target'), ...
        'Target leakage: autonomous control parameters contain target.');
    M = P.max_iteration+1;
    error_hist = nan(M,1); occupancy_hist = nan(M,1);
    E_hist = nan(M,1); C_hist = nan(M,1); A_hist = nan(M,1);
    rho_hist = nan(M,1); Adir_hist = nan(M,1);
    Alocal_hist = nan(M,1); direction_reliability_hist = nan(M,1);
    progress_gate_hist = nan(M,1);
    E_gain_hist = ones(M,1); C_gain_hist = zeros(M,1);
    A_gain_hist = zeros(M,1); paivc_entropy_hist = nan(M,1);
    positions_initial = initial_positions;

    for sample = 1:M
        d = vecnorm(nps-P.target,2,2);
        error_hist(sample) = mean(d);
        occupancy_hist(sample) = mean(d<=P.target_radius);
        if sample==M
            if sample>1
                E_hist(sample)=E_hist(sample-1); C_hist(sample)=C_hist(sample-1);
                A_hist(sample)=A_hist(sample-1); rho_hist(sample)=rho_hist(sample-1);
                Adir_hist(sample)=Adir_hist(sample-1);
                Alocal_hist(sample)=Alocal_hist(sample-1);
                direction_reliability_hist(sample)=direction_reliability_hist(sample-1);
                progress_gate_hist(sample)=progress_gate_hist(sample-1);
                E_gain_hist(sample)=E_gain_hist(sample-1);
                C_gain_hist(sample)=C_gain_hist(sample-1);
                A_gain_hist(sample)=A_gain_hist(sample-1);
                paivc_entropy_hist(sample)=paivc_entropy_hist(sample-1);
            end
            break;
        end
        iteration = sample;
        sensing_noise = P.paivc_sensing_mu+P.paivc_sensing_sigma*R.sensing_z(:,iteration);
        q_noise = P.paivc_Q_noise_mu+P.paivc_Q_noise_sigma*R.q_z(iteration);
        [nps,state,Dg] = autonomous_paivc_step(nps,Pctrl,f,state,iteration, ...
            sensing_noise,q_noise,cfg);
        E_hist(sample)=Dg.E; C_hist(sample)=Dg.C_auto;
        A_hist(sample)=Dg.A_auto; rho_hist(sample)=Dg.rho_A;
        Adir_hist(sample)=Dg.A_dir;
        Alocal_hist(sample)=Dg.A_local;
        direction_reliability_hist(sample)=Dg.direction_reliability;
        progress_gate_hist(sample)=Dg.progress_gate;
        E_gain_hist(sample)=Dg.g_E; C_gain_hist(sample)=Dg.mean_g_C;
        A_gain_hist(sample)=Dg.g_A; paivc_entropy_hist(sample)=state.entropy;

        if position_noise>0
            % Article-based P-AIVC holds an agent after it reaches the fitness threshold;
            % position perturbations therefore apply only to agents not yet held.
            perturbation=position_noise*R.position_z(:,:,iteration);
            perturbation(state.held,:)=0;
            nps = nps+perturbation;
        end
        nps(:,1) = clamp(nps(:,1),P.boundary(1),P.boundary(2));
        nps(:,2) = clamp(nps(:,2),P.boundary(3),P.boundary(4));
    end

    positions_final = nps;
    result = compute_endpoints(error_hist,occupancy_hist,E_hist,C_hist,A_hist, ...
        rho_hist,Adir_hist,Alocal_hist,direction_reliability_hist, ...
        progress_gate_hist,E_gain_hist,C_gain_hist,A_gain_hist, ...
        paivc_entropy_hist,P);
    result.positions_initial = positions_initial;
    result.positions_final = positions_final;
    % Match the HIVC analysis window: recorded states correspond to
    % iterations 2,...,T after updates 1,...,T-1.
    process_idx=2:P.max_iteration;
    result.error_hist = error_hist(process_idx);
    result.occupancy_hist = occupancy_hist(process_idx);
    result.E_hist = E_hist(process_idx);
    result.C_hist = C_hist(process_idx);
    result.A_hist = A_hist(process_idx);
    result.rho_A_hist = rho_hist(process_idx);
    result.A_dir_hist = Adir_hist(process_idx);
    result.A_local_hist = Alocal_hist(process_idx);
    result.direction_reliability_hist = direction_reliability_hist(process_idx);
    result.progress_gate_hist = progress_gate_hist(process_idx);
    result.control_bgf_evals = P.N*P.max_iteration;
    result.offline_metric_bgf_evals = 0;
    result.paivc_behavior = state.behavior;
    result.paivc_final_Q = state.Q;
end

function Pctrl = make_control_parameters(P)
    % Remove evaluation-only quantities so control cannot query the true target.
    Pctrl=P;
    remove={'target','target_radius','success_terminal_error', ...
        'success_occupancy','success_late_fraction', ...
        'success_required_fraction','success_t50_fraction'};
    remove=remove(isfield(Pctrl,remove));
    Pctrl=rmfield(Pctrl,remove);
end

function state = initialize_paivc_state(P,bgf_name)
    if any(strcmpi(bgf_name,{'sphere','matyas'})), behavior='flocking';
    else, behavior='territorial'; end
    state = struct('behavior',behavior,'Q',P.paivc_Q0,'entropy',NaN, ...
        'Tsi',P.paivc_sampling_T0,'next_update',1, ...
        'held',false(P.N,1),'hold_streak',zeros(P.N,1),'fitness_ema',NaN);
end

function [nps_next,state,Dg] = autonomous_paivc_step(nps,P,f,state,iteration, ...
        sensing_noise,q_noise,cfg)
    % Target-free P-AIVC update with optional TSIF gains, using only positions,
    % neighbors, and the existing noisy BGF sample.
    assert(~isfield(P,'target'),'Autonomous controller received true target.');
    N = size(nps,1);
    nps_next = nps;
    fitness = f(nps); fitness = fitness(:)+sensing_noise(:);

    % Target-free stagnation gate from the existing noisy BGF samples; no
    % candidate-position or finite-difference query is introduced.
    mean_fitness=mean(clamp(fitness,0,1));
    if ~isfinite(state.fitness_ema)
        state.fitness_ema=mean_fitness;
        Dg.progress_gate=0;
    else
        previous_ema=state.fitness_ema;
        state.fitness_ema=(1-P.progress_ema_alpha)*previous_ema+ ...
            P.progress_ema_alpha*mean_fitness;
        progress=state.fitness_ema-previous_ema;
        Dg.progress_gate=clamp(1-progress/max(P.progress_tolerance,eps),0,1);
    end

    if cfg.native_entropy_adaptation && ...
            strcmpi(state.behavior,'territorial') && iteration>=state.next_update
        state.entropy = paivc_information_entropy(fitness,P.paivc_entropy_bins);
        state.Q = max(0,P.paivc_Q0*exp(-state.entropy/max(P.paivc_entropy0,eps))+q_noise);
        state.Tsi = P.paivc_sampling_T0*exp(state.entropy/max(P.paivc_entropy0,eps));
        state.next_update = iteration+max(1,round(state.Tsi));
    end
    if strcmpi(state.behavior,'flocking')
        perception_radius = P.paivc_flocking_radius;
    else
        perception_radius = P.paivc_territorial_radius;
    end

    cooperation_all=zeros(N,2); social_all=zeros(N,2);
    neighbor_sets=cell(N,1);
    local_C=zeros(N,1);
    relative_evidence=fractional_rank01(fitness);
    candidate_hold=fitness>=P.paivc_hold_fitness_threshold;
    for i = 1:N
        displacement = nps-nps(i,:);                  % i -> neighbor
        distances = vecnorm(displacement,2,2);
        distances(i) = inf;
        [~,order] = sort(distances);
        order = order(1:min(P.paivc_neighbor_count,N-1));
        order = order(distances(order)<=perception_radius);
        neighbor_sets{i}=order(:);
        if isempty(order)
            local_C(i)=0;
            continue;
        end

        cooperation = [0 0]; attraction = [0 0]; repulsion = [0 0];
        for jj = 1:numel(order)
            j = order(jj); dij = distances(j);
            if dij<1e-12, continue; end
            unit_to = displacement(j,:)/dij;
            path_gain = (dij/max(P.paivc_reference_distance,eps))^P.paivc_path_loss_index;
            cooperation = cooperation+((fitness(j)-fitness(i))/max(path_gain,eps))*unit_to;
            if strcmpi(state.behavior,'flocking')
                w = exp(-1/max(P.paivc_adsorption_lambda*dij,eps));
                attraction = attraction+w*unit_to;
            else
                Rm = P.paivc_min_force_radius;
                c = state.Q/(8*pi*P.paivc_viscosity);
                force = c*(max(dij-Rm,0)/max(dij,eps)^3+ ...
                    max(Rm-dij,0)/max(Rm,eps)^3);
                threshold = P.paivc_Q0/(8*pi*P.paivc_viscosity)* ...
                    max(perception_radius-Rm,0)/max(perception_radius,eps)^3;
                force_max = P.paivc_Q0/(8*pi*P.paivc_viscosity*max(Rm,eps)^2);
                excess = max(force-threshold,0)/max(force_max-threshold,eps);
                repulsion = repulsion-excess*unit_to;
            end
        end
        if norm(cooperation)>1e-12, cooperation=cooperation/norm(cooperation); end
        cooperation_all(i,:)=cooperation;
        if strcmpi(state.behavior,'flocking')
            social_all(i,:)=P.paivc_adsorption_step*attraction;
        else
            repulsion_delta = P.paivc_repulsion_step_cap*repulsion;
            if norm(repulsion_delta)>P.paivc_repulsion_step_cap
                repulsion_delta=repulsion_delta/norm(repulsion_delta)*P.paivc_repulsion_step_cap;
            end
            social_all(i,:)=repulsion_delta;
        end
        mean_neighbor_distance=mean(distances(order));
        compactness=exp(-(mean_neighbor_distance/max(perception_radius,eps))^2);
        local_C(i)=sqrt(clamp(compactness,0,1)*relative_evidence(i));
    end

    % P-AIVC accepts one high local measurement; TSIF-C additionally requires
    % local support and temporal confirmation.
    if cfg.use_C
        supported_hold=candidate_hold & ...
            relative_evidence>=P.C_hold_rank_threshold & ...
            local_C>=P.C_hold_compactness_threshold;
        state.hold_streak(supported_hold)=state.hold_streak(supported_hold)+1;
        state.hold_streak(~supported_hold)=0;
        state.held=state.held | state.hold_streak>=P.C_hold_confirmations;
    else
        state.held=state.held | candidate_hold;
    end
    hold_local=state.held;

    % E scales the native BGF-directed step using finite-swarm-normalized entropy.
    % Its nonnegative cruise and stagnation-escape terms never reverse or suppress
    % the native migration direction.
    Dg.E=spatial_entropy(nps,P);
    if cfg.use_E
        low_drive=max(P.E_low-Dg.E,0)/max(P.E_low,eps)*Dg.progress_gate;
        spread_drive=clamp((Dg.E-P.E_low)/max(P.E_high-P.E_low,eps),0,1);
        Dg.g_E=clamp(exp(P.E_gain*(0.55*spread_drive+low_drive)), ...
            P.E_gain_min,P.E_gain_max);
    elseif cfg.fixed_tsif_gains
        Dg.g_E=P.fixed_E_scale;
    else
        Dg.g_E=1;
    end

    % C uses local compactness and relative BGF rank to reduce non-directed social
    % displacement for compact, high-evidence agents without reducing migration.
    Dg.C_auto=mean(local_C);
    if cfg.use_C
        rank_gate=clamp((relative_evidence-P.C_rank_threshold)/ ...
            max(1-P.C_rank_threshold,eps),0,1);
        evidence_gate=clamp((fitness-P.C_fitness_threshold)/ ...
            max(1-P.C_fitness_threshold,eps),0,1);
        progress_weight=P.C_progress_floor+ ...
            (1-P.C_progress_floor)*Dg.progress_gate;
        C_strength=clamp(P.C_gain*local_C.*rank_gate.*evidence_gate.* ...
            progress_weight,0,1);
    elseif cfg.fixed_tsif_gains
        C_strength=P.fixed_C_strength*ones(N,1);
    else
        C_strength=zeros(N,1);
    end
    Dg.mean_g_C=mean(C_strength);

    % A_auto retains global cancellation, while control uses neighborhood coherence
    % to avoid coupling opposing regions in multimodal fields.
    c_norm=vecnorm(cooperation_all,2,2);
    valid=c_norm>P.vector_valid_threshold;
    Dg.rho_A=mean(valid); Dg.A_dir=0; Dg.A_auto=0;
    unit_all=zeros(N,2);
    if any(valid)
        unit_all(valid,:)=cooperation_all(valid,:)./c_norm(valid);
        Dg.A_dir=norm(mean(unit_all(valid,:),1));
        Dg.A_auto=Dg.rho_A*Dg.A_dir;
    end
    cooperation_control=cooperation_all;
    local_alignment=zeros(N,1); A_blend=zeros(N,1);
    applied_reliability=zeros(N,1); reliability_valid=false(N,1);
    for i=1:N
        if ~valid(i), continue; end
        members=neighbor_sets{i};
        members=members(valid(members));
        members=unique([i;members(:)]);
        local_resultant=mean(unit_all(members,:),1);
        local_alignment(i)=norm(local_resultant);
        if local_alignment(i)<=P.vector_valid_threshold, continue; end
        local_direction=local_resultant/local_alignment(i);
        if cfg.use_A
            activation=max(local_alignment(i)-P.A_activation,0)/ ...
                max(1-P.A_activation,eps);
            A_blend(i)=min(P.A_max_blend,P.A_gain*activation);
        elseif cfg.fixed_tsif_gains
            A_blend(i)=P.fixed_A_blend;
        end
        blended=(1-A_blend(i))*unit_all(i,:)+A_blend(i)*local_direction;
        if norm(blended)>P.vector_valid_threshold
            cooperation_control(i,:)=blended/norm(blended);
        else
            cooperation_control(i,:)=unit_all(i,:);
        end
        applied_reliability(i)=dot(cooperation_control(i,:),local_direction);
        reliability_valid(i)=true;
    end
    if any(reliability_valid)
        Dg.A_local=mean(local_alignment(reliability_valid));
        Dg.direction_reliability=mean(applied_reliability(reliability_valid));
        Dg.g_A=mean(A_blend(reliability_valid));
    else
        Dg.A_local=0; Dg.direction_reliability=0; Dg.g_A=0;
    end

    % During stagnation, low-evidence agents blend toward the centroid of the
    % best locally measured agents, preventing isolation without target coordinates.
    if cfg.use_C
        elite=relative_evidence>=P.C_rescue_elite_rank;
        if any(elite) && max(fitness(elite))>=P.C_rescue_fitness_threshold
            evidence_centroid=mean(nps(elite,:),1);
            for i=1:N
                if hold_local(i), continue; end
                rescue_vector=evidence_centroid-nps(i,:);
                rescue_norm=norm(rescue_vector);
                if rescue_norm<=P.vector_valid_threshold, continue; end
                rescue_direction=rescue_vector/rescue_norm;
                rescue_weight=P.C_rescue_gain*Dg.progress_gate* ...
                    (1-relative_evidence(i));
                if c_norm(i)<=P.vector_valid_threshold
                    rescue_weight=max(rescue_weight,0.85*Dg.progress_gate);
                end
                rescue_weight=clamp(rescue_weight,0,0.95);
                blended=(1-rescue_weight)*cooperation_control(i,:)+ ...
                    rescue_weight*rescue_direction;
                if norm(blended)>P.vector_valid_threshold
                    cooperation_control(i,:)=blended/norm(blended);
                end
            end
        end
    end

    % A increases speed only with reliable neighborhood direction; Fixed-AIVC
    % uses the corresponding frozen scalar.
    A_speed_scale=ones(N,1);
    if cfg.use_A
        A_speed_scale=1+P.A_speed_gain*A_blend.*local_alignment;
    elseif cfg.fixed_tsif_gains
        A_speed_scale=(1+P.A_speed_gain*P.fixed_A_blend)*ones(N,1);
    end

    % C brakes compact, high-evidence agents to reduce near-optimum overshoot.
    C_migration_scale=1-P.C_migration_brake*C_strength;

    for i=1:N
        if hold_local(i), continue; end
        cooperative_delta=Dg.g_E*A_speed_scale(i)*C_migration_scale(i)* ...
            P.paivc_migration_step* ...
            cooperation_control(i,:);
        social_delta=(1-C_strength(i))*social_all(i,:);
        if norm(cooperation_control(i,:))>P.vector_valid_threshold
            opposing=min(dot(social_delta,cooperation_control(i,:)),0);
            social_delta=social_delta- ...
                C_strength(i)*opposing*cooperation_control(i,:);
        end
        nps_next(i,:)=nps(i,:)+cooperative_delta+social_delta;
    end
end

function entropy_value = paivc_information_entropy(fitness,num_bins)
    values = clamp(fitness(:),0,1);
    counts = histcounts(values,linspace(0,1,num_bins+1));
    p = counts/max(sum(counts),1); p = p(p>0);
    entropy_value = -sum(p.*log(p));
end

function ranks = fractional_rank01(values)
    % Deterministic empirical ranks use shared midranks, so a flat field gives
    % neutral evidence without requiring a toolbox.
    values=values(:); n=numel(values); ranks=zeros(n,1);
    if n<=1, ranks(:)=0.5; return; end
    [sorted_values,order]=sort(values);
    first=1;
    while first<=n
        last=first;
        while last<n && sorted_values(last+1)==sorted_values(first)
            last=last+1;
        end
        midrank=0.5*((first-1)+(last-1))/(n-1);
        ranks(order(first:last))=midrank;
        first=last+1;
    end
end

function E = spatial_entropy(nps,P)
    B = P.entropy_bins_per_axis;
    x = clamp(nps(:,1),P.boundary(1),P.boundary(2));
    y = clamp(nps(:,2),P.boundary(3),P.boundary(4));
    xe = linspace(P.boundary(1),P.boundary(2),B+1);
    ye = linspace(P.boundary(3),P.boundary(4),B+1);
    [~,~,bx] = histcounts(x,xe); [~,~,by] = histcounts(y,ye);
    valid = bx>=1 & by>=1;
    if any(valid)
        idx = (by(valid)-1)*B+bx(valid);
        counts = accumarray(idx(:),1,[B^2 1]);
        p = counts/sum(counts); p=p(p>0);
        % Normalize by the finite-swarm attainable maximum when N<B^2.
        E = -sum(p.*log(p))/log(min(P.N,B^2));
    else
        E = 0;
    end
    E=clamp(E,0,1);
end

function result = compute_endpoints(error_hist,occupancy_hist,E,C,A,rho,Adir, ...
        Alocal,direction_reliability,progress_gate,E_gain,C_gain,A_gain, ...
        paivc_entropy,P)
    process_idx=2:P.max_iteration;
    process_error=error_hist(process_idx);
    process_occupancy=occupancy_hist(process_idx);
    process_E=E(process_idx); process_C=C(process_idx); process_A=A(process_idx);
    process_rho=rho(process_idx); process_Adir=Adir(process_idx);
    process_Alocal=Alocal(process_idx);
    process_direction_reliability=direction_reliability(process_idx);
    process_progress_gate=progress_gate(process_idx);
    result.error_auc = trapz(process_error)/numel(process_error);
    result.occupancy_auc = trapz(process_occupancy)/numel(process_occupancy);
    result.terminal_error_mean = error_hist(end);
    result.target_occupancy = occupancy_hist(end);
    first = find(process_occupancy>=0.5,1,'first');
    if isempty(first)
        result.time_to_50=P.max_iteration; result.time_to_50_event=false;
    else
        result.time_to_50=first+1; result.time_to_50_event=true;
    end
    late_start=floor((1-P.success_late_fraction)*numel(process_error))+1;
    late=late_start:numel(process_error);
    result.late_error_mean=mean(process_error(late));
    result.late_error_std=std(process_error(late));
    result.late_occupancy_mean=mean(process_occupancy(late));
    result.late_occupancy_std=std(process_occupancy(late));
    result.mean_E=mean(process_E); result.mean_C=mean(process_C); result.mean_A=mean(process_A);
    result.mean_rho_A=mean(process_rho); result.mean_A_dir=mean(process_Adir);
    result.mean_A_local=mean(process_Alocal);
    result.mean_direction_reliability=mean(process_direction_reliability);
    result.late_direction_reliability=mean(process_direction_reliability(late));
    result.mean_progress_gate=mean(process_progress_gate);
    result.mean_E_gain=mean(E_gain(1:end-1));
    result.mean_C_gain=mean(C_gain(1:end-1));
    result.mean_A_gain=mean(A_gain(1:end-1));
    result.mean_paivc_entropy=mean(paivc_entropy(isfinite(paivc_entropy)));
    if isempty(paivc_entropy(isfinite(paivc_entropy)))
        result.mean_paivc_entropy=NaN;
    end
    gate_terminal=result.terminal_error_mean<P.success_terminal_error;
    gate_occupancy=result.late_occupancy_mean>=P.success_occupancy;
    gate_sustained=mean(process_occupancy(late)>=P.success_occupancy)>=P.success_required_fraction;
    gate_t50=result.time_to_50_event && result.time_to_50<=P.success_t50_fraction*P.max_iteration;
    result.gate_terminal=gate_terminal; result.gate_occupancy=gate_occupancy;
    result.gate_sustained=gate_sustained; result.gate_t50=gate_t50;
    result.stable_success=gate_terminal&&gate_occupancy&&gate_sustained&&gate_t50;
end

function row = result_to_row(R,P,D,bgf,init_name,pos_noise,seed_index, ...
        scenario_id,random_seed,mode,cfg,runtime_sec,initial_positions,common)
    row = struct();
    row.architecture="AIVC"; row.bgf_type=string(bgf); row.control_mode=string(mode);
    row.method_label=string(paper_mode_label(mode)); row.method_role=string(cfg.method_role);
    row.external_baseline=cfg.external_baseline;
    row.use_TSIF_E=cfg.use_E; row.use_TSIF_C=cfg.use_C; row.use_TSIF_A=cfg.use_A;
    row.native_paivc_entropy_adaptation=cfg.native_entropy_adaptation;
    row.fixed_tsif_gains=cfg.fixed_tsif_gains;
    row.use_external_dc=false;
    row.external_target_vector_access=false;
    row.global_swarm_statistic_access=cfg.use_E||cfg.use_A|| ...
        cfg.native_entropy_adaptation;
    row.finite_difference_gradient_access=false;
    row.local_BGF_hold_rule=true;
    row.init_name=string(init_name); row.position_noise=pos_noise;
    row.seed_index=seed_index; row.scenario_id=scenario_id; row.random_seed=random_seed;
    row.base_seed=D.base_seed; row.N=P.N; row.max_iteration=P.max_iteration;
    row.initial_checksum=sum(initial_positions(:)); row.common_noise_checksum=common.checksum;
    row.error_auc=R.error_auc; row.occupancy_auc=R.occupancy_auc;
    row.terminal_error_mean=R.terminal_error_mean; row.target_occupancy=R.target_occupancy;
    row.time_to_50=R.time_to_50; row.time_to_50_event=R.time_to_50_event;
    row.time_to_50_censored=~R.time_to_50_event;
    row.late_error_mean=R.late_error_mean; row.late_error_std=R.late_error_std;
    row.late_occupancy_mean=R.late_occupancy_mean; row.late_occupancy_std=R.late_occupancy_std;
    row.mean_E=R.mean_E; row.mean_C=R.mean_C; row.mean_A=R.mean_A;
    row.mean_rho_A=R.mean_rho_A; row.mean_A_dir=R.mean_A_dir;
    row.mean_A_local=R.mean_A_local;
    row.mean_direction_reliability=R.mean_direction_reliability;
    row.late_direction_reliability=R.late_direction_reliability;
    row.mean_progress_gate=R.mean_progress_gate;
    row.mean_E_gain=R.mean_E_gain; row.mean_C_gain=R.mean_C_gain;
    row.mean_A_gain=R.mean_A_gain; row.mean_paivc_entropy=R.mean_paivc_entropy;
    row.gate_terminal=R.gate_terminal; row.gate_occupancy=R.gate_occupancy;
    row.gate_sustained=R.gate_sustained; row.gate_t50=R.gate_t50;
    row.stable_success=R.stable_success;
    row.control_bgf_evals=R.control_bgf_evals;
    row.offline_metric_bgf_evals=R.offline_metric_bgf_evals;
    row.paivc_behavior=string(R.paivc_behavior); row.paivc_final_Q=R.paivc_final_Q;
    row.runtime_sec=runtime_sec;
end

function y = clamp(x,lo,hi)
    y=min(max(x,lo),hi);
end

function out = ternary(cond,a,b)
    if cond, out=a; else, out=b; end
end

function f = make_bgf(name)
    switch lower(name)
        case 'sphere'
            f=@(xy) double(sum(xy.^2,2)<=0.25)+double(sum(xy.^2,2)>0.25).* ...
                max(0,1-0.005*sum(xy.^2,2));
        case 'matyas'
            f=@(xy) 1./(1+0.26*sum(xy.^2,2)-0.48*abs(xy(:,1).*xy(:,2)));
        case 'ackley'
            f=@(xy) (20*exp(-0.2*sqrt(0.5*sum(xy.^2,2)))+ ...
                exp(0.5*(cos(2*pi*xy(:,1))+cos(2*pi*xy(:,2)))))/(20+exp(1));
        case 'rastrigin'
            f=@(xy) 1./(1+20+sum(xy.^2,2)- ...
                10*(cos(2*pi*xy(:,1))+cos(2*pi*xy(:,2))));
        otherwise
            error('Unknown BGF: %s',name);
    end
end

function finish_analysis(feature_table,all_results,P,D)
    feature_table = normalize_text_columns(feature_table);
    export_method_switch_table(D);
    export_configuration(P,D);
    audit = audit_design(feature_table,D,P);
    summary_table = build_performance_summary(feature_table,D);
    factorial_table = build_factorial_summary(feature_table,D);
    stats_table = run_auc_comparisons(feature_table,D.bootstrap_samples,D.base_seed);

    writetable(feature_table,fullfile(D.output_dir,[D.output_prefix '_feature.csv']));
    writetable(summary_table,fullfile(D.output_dir,[D.output_prefix '_performance.csv']));
    writetable(factorial_table,fullfile(D.output_dir,[D.output_prefix '_factorial_144.csv']));
    writetable(stats_table,fullfile(D.output_dir,[D.output_prefix '_auc_20_comparisons.csv']));
    writetable(audit,fullfile(D.output_dir,[D.output_prefix '_design_audit.csv']));
    save(fullfile(D.output_dir,[D.output_prefix '_results.mat']), ...
        'feature_table','summary_table','factorial_table','stats_table','audit', ...
        'all_results','P','D','-v7.3');
    export_latex_tables(summary_table,stats_table,D);
    generate_figures(feature_table,stats_table,D);

    fprintf('\n=== TSIF-AIVC main AUC results ===\n');
    show = stats_table(:,{'bgf_type','comparator_label','n_pairs', ...
        'mean_auc_full','mean_auc_comparator','relative_improvement_pct', ...
        'ci_relative_low','ci_relative_high','p_fdr_all20'});
    disp(show);
    fprintf('Outputs saved under %s\n',D.output_dir);
end

function T = normalize_text_columns(T)
    names = {'architecture','bgf_type','control_mode','method_label', ...
        'method_role','init_name','paivc_behavior'};
    for k=1:numel(names)
        if ismember(names{k},T.Properties.VariableNames)
            T.(names{k})=string(T.(names{k}));
        end
    end
end

function audit = audit_design(F,D,P)
    F=normalize_text_columns(F);
    scenarios=unique(F.scenario_id);
    expected_modes=string(D.methods(:));
    complete=true; initial_matched=true; noise_matched=true; unique_rows=true;
    query_matched=true;
    for k=1:numel(scenarios)
        X=F(F.scenario_id==scenarios(k),:);
        complete=complete && height(X)==numel(expected_modes) && ...
            isempty(setxor(unique(X.control_mode),expected_modes));
        initial_matched=initial_matched && range(double(X.initial_checksum))<1e-10;
        noise_matched=noise_matched && range(double(X.common_noise_checksum))<1e-8;
        unique_rows=unique_rows && numel(unique(X.control_mode))==height(X);
        query_matched=query_matched && range(double(X.control_bgf_evals))==0;
    end
    config_matched=all(F.base_seed==D.base_seed) && all(F.N==P.N) && ...
        all(F.max_iteration==P.max_iteration) && ...
        all(F.random_seed==mod(D.base_seed+F.scenario_id,2^31-1));
    target_free=all(~F.use_external_dc) && all(~F.external_target_vector_access) && ...
        all(~F.finite_difference_gradient_access);
    if ~(complete&&initial_matched&&noise_matched&&unique_rows&&config_matched&& ...
            query_matched&&target_free)
        error('AIVC design audit failed: incomplete or unmatched scenario block.');
    end
    expected_scenarios=numel(D.bgfs)*numel(D.inits)* ...
        numel(D.position_noise_levels)*D.num_seeds;
    factor_complete=true;
    if D.shard_count==1
        factor_complete=numel(scenarios)==expected_scenarios && ...
            isempty(setxor(unique(F.bgf_type),string(D.bgfs(:)))) && ...
            isempty(setxor(unique(F.init_name),string(D.inits(:)))) && ...
            isempty(setxor(unique(F.position_noise),D.position_noise_levels(:)));
        if ~factor_complete
            error('AIVC design audit failed: factorial cells or scenarios are missing.');
        end
    end
    if isfield(D,'source_shard_parameters_verified')
        shard_parameters_verified=D.source_shard_parameters_verified;
    else
        shard_parameters_verified=D.shard_count==1;
    end
    audit=table(numel(scenarios),expected_scenarios,height(F),numel(expected_modes),complete, ...
        factor_complete, ...
        initial_matched,noise_matched,query_matched,target_free,config_matched, ...
        shard_parameters_verified,unique_rows, ...
        'VariableNames',{'n_scenarios','expected_scenarios','n_runs','methods_per_scenario', ...
        'complete_method_blocks','complete_factorial_when_unsharded','matched_initial_positions', ...
        'matched_exogenous_noise','matched_control_BGF_query_count', ...
        'no_external_DC_target_or_finite_difference_access','matched_frozen_configuration', ...
        'source_shard_parameter_structs_verified', ...
        'unique_scenario_method_rows'});
end

function export_method_switch_table(D)
    rows=cell(numel(D.methods),1);
    for k=1:numel(D.methods)
        c=mode_spec(D.methods{k});
        rows{k}=table(string(c.mode),string(paper_mode_label(c.mode)), ...
            c.use_paivc_local,c.native_entropy_adaptation,c.use_E,c.use_C,c.use_A, ...
            c.fixed_tsif_gains,c.external_baseline,false,false,false, ...
            c.use_E||c.use_A||c.native_entropy_adaptation,string(c.method_role), ...
            'VariableNames',{'control_mode','method_label','P_AIVC_core', ...
            'native_EntAS_adaptation','dynamic_TSIF_E','dynamic_TSIF_C', ...
            'dynamic_TSIF_A','fixed_TSIF_gains','external_baseline', ...
            'external_DC','external_target_vector_access', ...
            'finite_difference_gradient_access','global_swarm_statistic_access', ...
            'method_role'});
    end
    T=vertcat(rows{:});

    % Verify that each ablation changes exactly its named TSIF switch.
    full=mode_spec('tsif_aivc');
    assert_clean_ablation(full,mode_spec('aivc_no_e'),'use_E');
    assert_clean_ablation(full,mode_spec('aivc_no_c'),'use_C');
    assert_clean_ablation(full,mode_spec('aivc_no_a'),'use_A');
    writetable(T,fullfile(D.output_dir,[D.output_prefix '_method_switches.csv']));
end

function assert_clean_ablation(full,ablated,changed_field)
    fields={'use_paivc_local','native_entropy_adaptation','use_E','use_C','use_A', ...
        'fixed_tsif_gains'};
    for k=1:numel(fields)
        name=fields{k};
        if strcmp(name,changed_field)
            assert(full.(name) && ~ablated.(name),'Named ablation switch did not turn off.');
        else
            assert(isequal(full.(name),ablated.(name)), ...
                'Ablation changes more than the named TSIF pathway.');
        end
    end
end

function export_configuration(P,D)
    names={ ...
        'experiment_revision','design_base_seed','formal_seed_locked', ...
        'population_N','domain_x_min','domain_x_max', ...
        'target_radius','max_iteration','P_AIVC_K','P_AIVC_gamma', ...
        'P_AIVC_path_loss','P_AIVC_dref','P_AIVC_sigma', ...
        'P_AIVC_flocking_Rf','P_AIVC_adsorption_step','P_AIVC_adsorption_lambda', ...
        'P_AIVC_territorial_Rf','P_AIVC_Rm','P_AIVC_repulsion_step_cap', ...
        'P_AIVC_viscosity','P_AIVC_Q0','P_AIVC_Ent0','P_AIVC_Q_noise_sigma', ...
        'P_AIVC_entropy_bins_reconstructed','P_AIVC_T0_reconstructed', ...
        'P_AIVC_local_hold_fitness','P_AIVC_persistent_hold', ...
        'P_AIVC_landscape_class_prespecified','fixed_E_scale','fixed_C_strength', ...
        'fixed_A_blend','fixed_gain_development_seed','TSIF_grid_B', ...
        'TSIF_entropy_attainable_normalization','TSIF_vector_valid_threshold', ...
        'TSIF_progress_ema_alpha','TSIF_progress_tolerance','TSIF_E_low', ...
        'TSIF_E_high','TSIF_E_gain','TSIF_E_gain_min','TSIF_E_gain_max', ...
        'TSIF_C_gain','TSIF_C_rank_threshold', ...
        'TSIF_C_progress_floor','TSIF_C_fitness_threshold', ...
        'TSIF_C_migration_brake','TSIF_C_hold_rank_threshold', ...
        'TSIF_C_hold_compactness_threshold','TSIF_C_hold_confirmations', ...
        'TSIF_C_rescue_elite_rank','TSIF_C_rescue_fitness_threshold', ...
        'TSIF_C_rescue_gain', ...
        'TSIF_A_activation','TSIF_A_gain', ...
        'TSIF_A_max_blend','TSIF_A_speed_gain','success_terminal_error', ...
        'success_occupancy','success_late_fraction','success_required_fraction', ...
        'success_T50_fraction','position_noise_min','position_noise_max'};
    values=[2026091104 D.base_seed double(D.seed_locked) ...
        P.N P.boundary(1) P.boundary(2) P.target_radius ...
        P.max_iteration P.paivc_neighbor_count P.paivc_migration_step ...
        P.paivc_path_loss_index P.paivc_reference_distance P.paivc_sensing_sigma ...
        P.paivc_flocking_radius P.paivc_adsorption_step P.paivc_adsorption_lambda ...
        P.paivc_territorial_radius P.paivc_min_force_radius P.paivc_repulsion_step_cap ...
        P.paivc_viscosity P.paivc_Q0 P.paivc_entropy0 P.paivc_Q_noise_sigma P.paivc_entropy_bins ...
        P.paivc_sampling_T0 P.paivc_hold_fitness_threshold 1 1 P.fixed_E_scale ...
        P.fixed_C_strength P.fixed_A_blend 17320508 ...
        P.entropy_bins_per_axis 1 P.vector_valid_threshold ...
        P.progress_ema_alpha P.progress_tolerance P.E_low P.E_high P.E_gain ...
        P.E_gain_min P.E_gain_max P.C_gain P.C_rank_threshold ...
        P.C_progress_floor P.C_fitness_threshold P.C_migration_brake ...
        P.C_hold_rank_threshold P.C_hold_compactness_threshold P.C_hold_confirmations ...
        P.C_rescue_elite_rank P.C_rescue_fitness_threshold P.C_rescue_gain P.A_activation ...
        P.A_gain P.A_max_blend P.A_speed_gain ...
        P.success_terminal_error P.success_occupancy ...
        P.success_late_fraction P.success_required_fraction P.success_t50_fraction ...
        min(D.position_noise_levels) max(D.position_noise_levels)];
    source=repmat("frozen experiment definition",numel(names),1);
    article_names={'P_AIVC_K','P_AIVC_gamma','P_AIVC_sigma', ...
        'P_AIVC_flocking_Rf','P_AIVC_territorial_Rf','P_AIVC_Rm', ...
        'P_AIVC_viscosity','P_AIVC_Q0','P_AIVC_Ent0','P_AIVC_Q_noise_sigma'};
    for k=1:numel(names)
        if ismember(names{k},article_names), source(k)="reported then length-scaled from Ref. [35]"; end
        if contains(names{k},'reconstructed') || any(strcmp(names{k},{ ...
                'P_AIVC_path_loss','P_AIVC_dref','P_AIVC_adsorption_step', ...
                'P_AIVC_adsorption_lambda','P_AIVC_repulsion_step_cap'}))
            source(k)="article-based reconstruction; value omitted in Ref. [35]";
        end
    end
    T=table(string(names(:)),values(:),source,'VariableNames',{'parameter','value','provenance'});
    writetable(T,fullfile(D.output_dir,[D.output_prefix '_configuration.csv']));
end

function S = build_performance_summary(F,D)
    F=normalize_text_columns(F);
    rows=cell(numel(D.bgfs)*numel(D.methods),1); q=0;
    for b=1:numel(D.bgfs)
        for m=1:numel(D.methods)
            X=F(F.bgf_type==string(D.bgfs{b}) & F.control_mode==string(D.methods{m}),:);
            if isempty(X), continue; end
            q=q+1;
            rows{q}=table(string(D.bgfs{b}),string(D.methods{m}), ...
                string(paper_mode_label(D.methods{m})),height(X), ...
                mean(X.error_auc),std(X.error_auc), ...
                mean(X.terminal_error_mean),std(X.terminal_error_mean), ...
                mean(X.target_occupancy),std(X.target_occupancy), ...
                mean(X.late_error_std),std(X.late_error_std), ...
                mean(X.mean_direction_reliability),std(X.mean_direction_reliability), ...
                sum(X.time_to_50_event),sum(X.time_to_50_censored), ...
                mean(X.time_to_50),sum(X.stable_success),mean(X.stable_success), ...
                mean(X.runtime_sec), ...
                'VariableNames',{'bgf_type','control_mode','method_label','n_runs', ...
                'error_auc_mean','error_auc_sd','terminal_error_mean', ...
                'terminal_error_sd','occupancy_mean','occupancy_sd', ...
                'late_error_std_mean','late_error_std_sd', ...
                'direction_reliability_mean','direction_reliability_sd', ...
                't50_event_n','t50_censored_n','t50_rmst_to_horizon', ...
                'stable_success_n','stable_success_rate','runtime_sec_mean'});
        end
    end
    S=vertcat(rows{1:q});
end

function S = build_factorial_summary(F,D)
    % Complete 4 x 6 x 3 x 2 design; formal cells contain 30 runs.
    F=normalize_text_columns(F);
    rows=cell(numel(D.bgfs)*numel(D.methods)*numel(D.inits)* ...
        numel(D.position_noise_levels),1); q=0;
    for b=1:numel(D.bgfs)
        for m=1:numel(D.methods)
            for ii=1:numel(D.inits)
                for z=1:numel(D.position_noise_levels)
                    X=F(F.bgf_type==string(D.bgfs{b}) & ...
                        F.control_mode==string(D.methods{m}) & ...
                        F.init_name==string(D.inits{ii}) & ...
                        F.position_noise==D.position_noise_levels(z),:);
                    if isempty(X), continue; end
                    q=q+1;
                    rows{q}=table(string(D.bgfs{b}),string(D.methods{m}), ...
                        string(paper_mode_label(D.methods{m})),string(D.inits{ii}), ...
                        D.position_noise_levels(z),height(X), ...
                        mean(X.error_auc),std(X.error_auc), ...
                        mean(X.terminal_error_mean),std(X.terminal_error_mean), ...
                        mean(X.target_occupancy),std(X.target_occupancy), ...
                        sum(X.time_to_50_event),sum(X.time_to_50_censored), ...
                        mean(X.time_to_50),sum(X.stable_success),mean(X.stable_success), ...
                        'VariableNames',{'bgf_type','control_mode','method_label', ...
                        'init_name','position_noise','n_runs','error_auc_mean', ...
                        'error_auc_sd','terminal_error_mean','terminal_error_sd', ...
                        'occupancy_mean','occupancy_sd','t50_event_n','t50_censored_n', ...
                        't50_rmst_to_horizon','stable_success_n','stable_success_rate'});
                end
            end
        end
    end
    S=vertcat(rows{1:q});
end

function Stats = run_auc_comparisons(F,n_boot,base_seed)
    F=normalize_text_columns(F);
    bgfs=unique(F.bgf_type,'stable');
    comparators=["aivc_no_e","aivc_no_c","aivc_no_a","fixed_aivc","local_only"];
    rows=cell(numel(bgfs)*numel(comparators),1); q=0;
    for b=1:numel(bgfs)
        full=F(F.bgf_type==bgfs(b) & F.control_mode=="tsif_aivc",:);
        full=sortrows(full,'scenario_id');
        for m=1:numel(comparators)
            cmp=F(F.bgf_type==bgfs(b) & F.control_mode==comparators(m),:);
            cmp=sortrows(cmp,'scenario_id');
            [ids,ia,ib]=intersect(full.scenario_id,cmp.scenario_id,'stable');
            x=full.error_auc(ia); y=cmp.error_auc(ib); d=y-x;
            strata=full.init_name(ia)+"|"+string(full.position_noise(ia));
            [dlo,dhi,rlo,rhi,rblo,rbhi]=bootstrap_paired(d,x,y,strata,n_boot, ...
                base_seed+1000*b+10*m);
            rel=100*(mean(y)-mean(x))/mean(y);
            p=paired_wilcoxon(x,y);
            rb=paired_rank_biserial(d);
            if comparators(m)=="local_only", family="external_4";
            else, family="internal_16"; end
            q=q+1;
            rows{q}=table(bgfs(b),comparators(m),string(paper_mode_label(comparators(m))), ...
                family,numel(ids),mean(x),std(x),mean(y),std(y),mean(d),dlo,dhi, ...
                rel,rlo,rhi,rb,rblo,rbhi,p, ...
                'VariableNames',{'bgf_type','comparator','comparator_label','test_family', ...
                'n_pairs','mean_auc_full','sd_auc_full','mean_auc_comparator', ...
                'sd_auc_comparator','paired_difference','ci_difference_low', ...
                'ci_difference_high','relative_improvement_pct','ci_relative_low', ...
                'ci_relative_high','rank_biserial','ci_rank_biserial_low', ...
                'ci_rank_biserial_high','p_raw'});
        end
    end
    Stats=vertcat(rows{1:q});
    Stats.p_fdr_all20=benjamini_hochberg(Stats.p_raw);
    Stats.p_fdr_family=nan(height(Stats),1);
    fams=unique(Stats.test_family);
    for k=1:numel(fams)
        idx=Stats.test_family==fams(k);
        Stats.p_fdr_family(idx)=benjamini_hochberg(Stats.p_raw(idx));
    end
end

function p = paired_wilcoxon(x,y)
    d=y-x; d=d(isfinite(d));
    if isempty(d) || all(abs(d)<eps), p=1; return; end
    if exist('signrank','file')==2
        try
            p=signrank(x,y,'method','approximate');
        catch
            p=signrank(x,y);
        end
    else
        % Two-sided sign-test fallback when Statistics Toolbox is absent.
        n=sum(d~=0); k=min(sum(d>0),sum(d<0));
        p=min(1,2*sum(arrayfun(@(j)nchoosek(n,j),0:k))/2^n);
    end
end

function r = paired_rank_biserial(d)
    d=d(isfinite(d) & abs(d)>eps);
    if isempty(d), r=0; return; end
    if exist('tiedrank','file')==2, ranks=tiedrank(abs(d));
    else, [~,ord]=sort(abs(d)); ranks=zeros(size(d)); ranks(ord)=1:numel(d); end
    r=sum(sign(d).*ranks)/sum(ranks);
end

function [dlo,dhi,rlo,rhi,rblo,rbhi] = bootstrap_paired(d,x,y,stratum_id,B,seed)
    stream=RandStream('mt19937ar','Seed',mod(seed,2^31-1));
    strata=unique(stratum_id(:),'stable');
    delta=nan(B,1); rel=nan(B,1); rb=nan(B,1);
    for b=1:B
        idx=[];
        for j=1:numel(strata)
            members=find(stratum_id==strata(j));
            draw=members(randi(stream,numel(members),[numel(members) 1]));
            idx=[idx;draw]; %#ok<AGROW>
        end
        delta(b)=mean(d(idx));
        rel(b)=100*(mean(y(idx))-mean(x(idx)))/mean(y(idx));
        rb(b)=paired_rank_biserial(d(idx));
    end
    dlo=percentile_value(delta,2.5); dhi=percentile_value(delta,97.5);
    rlo=percentile_value(rel,2.5); rhi=percentile_value(rel,97.5);
    rblo=percentile_value(rb,2.5); rbhi=percentile_value(rb,97.5);
end

function p_adj = benjamini_hochberg(p)
    p=p(:); m=numel(p); [sp,ord]=sort(p); adj=sp.*m./(1:m)';
    for k=m-1:-1:1, adj(k)=min(adj(k),adj(k+1)); end
    adj=min(adj,1); p_adj=nan(m,1); p_adj(ord)=adj;
end

function q = percentile_value(x,pct)
    x=sort(x(isfinite(x)));
    if isempty(x), q=NaN; return; end
    if numel(x)==1, q=x; return; end
    pos=1+(numel(x)-1)*pct/100; lo=floor(pos); hi=ceil(pos);
    if lo==hi, q=x(lo); else, q=x(lo)+(x(hi)-x(lo))*(pos-lo); end
end

function generate_figures(F,Stats,D)
    F=normalize_text_columns(F); Stats=normalize_stats_text(Stats);
    bgfs=string(D.bgfs); modes=string(D.methods);
    labels=cellfun(@paper_plot_label,D.methods,'UniformOutput',false);
    S=paper_figure_style();
    colors=paper_mode_colors(numel(modes));

    means=nan(numel(bgfs),numel(modes)); sds=means; occ=means;
    for b=1:numel(bgfs)
        for m=1:numel(modes)
            X=F(F.bgf_type==bgfs(b)&F.control_mode==modes(m),:);
            means(b,m)=mean(X.error_auc); sds(b,m)=std(X.error_auc);
            occ(b,m)=mean(X.target_occupancy);
        end
    end
    fig=paper_figure(S);
    draw_paper_grouped_bar(means,sds,cellstr(bgfs),labels,colors,S);
    ylabel('Process Error AUC','FontSize',S.label_size,'FontName',S.font_name);
    title('Process Error AUC Across BGF Landscapes', ...
        'FontSize',S.title_size,'FontName',S.font_name,'FontWeight','normal');
    export_figure(fig,fullfile(D.output_dir,[D.output_prefix '_auc_absolute'])); close(fig);

    all_comps=["aivc_no_e","aivc_no_c","aivc_no_a","fixed_aivc","local_only"];
    comps=all_comps(ismember(all_comps,modes));
    rel=nan(numel(bgfs),numel(comps)); low=rel; high=rel;
    for b=1:numel(bgfs)
        for m=1:numel(comps)
            X=Stats(Stats.bgf_type==bgfs(b)&Stats.comparator==comps(m),:);
            rel(b,m)=X.relative_improvement_pct;
            low(b,m)=X.ci_relative_low; high(b,m)=X.ci_relative_high;
        end
    end
    fig=paper_figure(S);
    short_labels=cellfun(@paper_plot_label,cellstr(comps),'UniformOutput',false);
    plot_low=floor(min(low(:))-0.5); plot_high=ceil(max(high(:))+0.5);
    for b=1:numel(bgfs)
        subplot(2,2,b); hold on;
        for m=1:numel(comps)
            color_idx=find(modes==comps(m),1);
            errorbar(m,rel(b,m),rel(b,m)-low(b,m),high(b,m)-rel(b,m), ...
                'o','Color',colors(color_idx,:),'MarkerFaceColor',colors(color_idx,:), ...
                'MarkerEdgeColor','k','LineWidth',S.error_line_width, ...
                'CapSize',S.cap_size,'MarkerSize',4.5);
        end
        yline(0,':','Color',[0.35 0.35 0.35],'LineWidth',0.8);
        set(gca,'XTick',1:numel(comps),'XTickLabel',short_labels, ...
            'FontName',S.font_name,'FontSize',S.panel_font_size, ...
            'Box','off','TickDir','out','XGrid','off','YGrid','on', ...
            'GridColor',S.grid_color,'GridAlpha',S.grid_alpha);
        xtickangle(18);
        ylim([plot_low plot_high]);
        panel_title=char(bgfs(b)); panel_title(1)=upper(panel_title(1));
        title(panel_title,'FontSize',S.font_size,'FontName',S.font_name, ...
            'FontWeight','normal');
        ylabel('I_{AUC} (%)','FontSize',S.panel_font_size,'FontName',S.font_name);
    end
    export_figure(fig,fullfile(D.output_dir,[D.output_prefix '_auc_relative_improvement'])); close(fig);

    fig=paper_figure(S);
    draw_paper_grouped_bar(100*occ,[],cellstr(bgfs),labels,colors,S);
    ylabel('Terminal Target Occupancy (%)', ...
        'FontSize',S.label_size,'FontName',S.font_name);
    title('Terminal Occupancy Across BGF Landscapes', ...
        'FontSize',S.title_size,'FontName',S.font_name,'FontWeight','normal');
    ylim([0 100]);
    export_figure(fig,fullfile(D.output_dir,[D.output_prefix '_terminal_occupancy'])); close(fig);
end

function S=paper_figure_style()
    S=struct('font_name','Times New Roman','font_size',9, ...
        'panel_font_size',8,'title_size',11,'label_size',10, ...
        'fig_width',7.0,'fig_height',3.5,'bar_width',0.72, ...
        'face_alpha',0.88,'error_line_width',0.8,'cap_size',2, ...
        'grid_color',[0.78 0.78 0.78],'grid_alpha',0.55);
end

function C=paper_mode_colors(n)
    % Muted engineering palette in the same method order as the HIVC plots.
    base=[0.075 0.278 0.463; ... % TSIF-AIVC
          0.662 0.388 0.188; ... % w/o E
          0.720 0.585 0.250; ... % w/o C
          0.390 0.330 0.510; ... % w/o A
          0.275 0.560 0.590; ... % Fixed-AIVC
          0.395 0.505 0.310];    % P-AIVC / Local-only
    C=base(1:n,:);
end

function fig=paper_figure(S)
    fig=figure('Color','w','Units','inches', ...
        'Position',[1 1 S.fig_width S.fig_height], ...
        'PaperPositionMode','auto','Renderer','painters');
end

function draw_paper_grouped_bar(means,stds,bgf_labels,mode_labels,colors,S)
    nbars=size(means,2);
    hb=bar(means,'grouped','BarWidth',S.bar_width);
    hold on;
    for j=1:nbars
        hb(j).FaceColor=colors(j,:);
        hb(j).EdgeColor='none';
        hb(j).FaceAlpha=S.face_alpha;
        if ~isempty(stds)
            x=hb(j).XData+hb(j).XOffset;
            x=x(:);
            errorbar(x,means(:,j),stds(:,j),'Color',[0.30 0.30 0.30], ...
                'LineStyle','none','LineWidth',S.error_line_width, ...
                'CapSize',S.cap_size);
        end
    end
    hold off;
    upper_labels=cellfun(@upper,bgf_labels,'UniformOutput',false);
    set(gca,'XTick',1:numel(bgf_labels),'XTickLabel',upper_labels, ...
        'FontName',S.font_name,'FontSize',S.font_size, ...
        'Box','off','TickDir','out','XGrid','off','YGrid','on', ...
        'GridColor',S.grid_color,'GridAlpha',S.grid_alpha,'Layer','top');
    legend(mode_labels,'Location','northwest','NumColumns',1,'Box','off', ...
        'FontName',S.font_name,'FontSize',S.font_size-1);
end

function S=normalize_stats_text(S)
    names={'bgf_type','comparator','comparator_label','test_family'};
    for k=1:numel(names)
        if ismember(names{k},S.Properties.VariableNames), S.(names{k})=string(S.(names{k})); end
    end
end

function export_figure(fig,path_no_ext)
    set(fig,'PaperPositionMode','auto','InvertHardcopy','off');
    print(fig,[path_no_ext '.png'],'-dpng','-r300');
    savefig(fig,[path_no_ext '.fig']);
end

function labels=title_case(labels)
    for k=1:numel(labels)
        s=labels{k}; labels{k}=[upper(s(1)) s(2:end)];
    end
end

function label = paper_mode_label(mode)
    mode=char(mode);
    switch mode
        case 'tsif_aivc', label='TSIF-AIVC';
        case 'aivc_no_e', label='w/o TSIF-E';
        case 'aivc_no_c', label='w/o TSIF-C';
        case 'aivc_no_a', label='w/o TSIF-A';
        case 'fixed_aivc', label='Fixed-AIVC (frozen gains)';
        case 'local_only', label='P-AIVC (Local-only)';
        otherwise, label=mode;
    end
end

function label = paper_plot_label(mode)
    % Plotting labels are shortened; exported tables retain full method names.
    mode=char(mode);
    switch mode
        case 'tsif_aivc', label='TSIF-AIVC';
        case 'aivc_no_e', label='w/o E';
        case 'aivc_no_c', label='w/o C';
        case 'aivc_no_a', label='w/o A';
        case 'fixed_aivc', label='Fixed-AIVC';
        case 'local_only', label='P-AIVC';
        otherwise, label=mode;
    end
end

function export_latex_tables(S,Stats,D)
    f= fopen(fullfile(D.output_dir,[D.output_prefix '_performance.tex']),'w');
    fprintf(f,'%% Generated automatically by main_tsif_aivc_revised.m\n');
    fprintf(f,'\\begin{tabular}{llrrrr}\n\\toprule\n');
    fprintf(f,'BGF & Method & $n$ & AUC & Occupancy & Stable success \\\\\n\\midrule\n');
    for k=1:height(S)
        fprintf(f,'%s & %s & %d & %.3f $\\pm$ %.3f & %.1f\\%% & %d/%d \\\\\n', ...
            char(S.bgf_type(k)),latex_escape(char(S.method_label(k))),S.n_runs(k), ...
            S.error_auc_mean(k),S.error_auc_sd(k),100*S.occupancy_mean(k), ...
            S.stable_success_n(k),S.n_runs(k));
    end
    fprintf(f,'\\bottomrule\n\\end{tabular}\n'); fclose(f);

    f=fopen(fullfile(D.output_dir,[D.output_prefix '_auc_20_comparisons.tex']),'w');
    fprintf(f,'%% Positive relative improvement favors TSIF-AIVC; negative favors the named comparator.\n');
    fprintf(f,'\\begin{tabular}{llrrrr}\n\\toprule\n');
    fprintf(f,'BGF & Comparator & $n$ & Relative improvement & $r_{rb}$ & $p_{FDR,20}$ \\\\\n\\midrule\n');
    for k=1:height(Stats)
        fprintf(f,'%s & %s & %d & %.2f\\%% [%.2f, %.2f] & %.3f & %.4g \\\\\n', ...
            char(Stats.bgf_type(k)),latex_escape(char(Stats.comparator_label(k))), ...
            Stats.n_pairs(k),Stats.relative_improvement_pct(k), ...
            Stats.ci_relative_low(k),Stats.ci_relative_high(k), ...
            Stats.rank_biserial(k),Stats.p_fdr_all20(k));
    end
    fprintf(f,'\\bottomrule\n\\end{tabular}\n'); fclose(f);
end

function s=latex_escape(s)
    s=strrep(s,'_','\\_'); s=strrep(s,'&','\\&'); s=strrep(s,'%','\\%');
end

function [F,all_results,P_run,D_run] = merge_shards(D)
    merge_dir=strtrim(getenv('AIVC_MERGE_DIR'));
    if isempty(merge_dir), merge_dir=D.output_dir; end
    files=dir(fullfile(merge_dir,'**','*_feature.csv'));
    if isempty(files), error('No shard feature CSV files found under %s',merge_dir); end
    tables=cell(numel(files),1); all_results={};
    P_run=[]; D_run=[];
    for k=1:numel(files)
        path=fullfile(files(k).folder,files(k).name);
        tables{k}=normalize_text_columns(readtable(path));
        mat_path=strrep(path,'_feature.csv','_results.mat');
        if ~isfile(mat_path), error('Missing shard MAT for %s',path); end
        X=load(mat_path,'all_results','P','D');
        if ~all(isfield(X,{'all_results','P','D'}))
            error('Shard MAT lacks all_results/P/D: %s',mat_path);
        end
        if isempty(P_run)
            P_run=X.P; D_run=X.D;
        else
            if ~isequaln(orderfields(P_run),orderfields(X.P))
                error('Algorithm parameters differ across shards: %s',mat_path);
            end
            if ~isequaln(orderfields(strip_shard_runtime_fields(D_run)), ...
                    orderfields(strip_shard_runtime_fields(X.D)))
                error('Factorial design differs across shards: %s',mat_path);
            end
        end
        all_results=[all_results; X.all_results(:)]; %#ok<AGROW>
    end
    F=vertcat(tables{:});
    feature_keys=strcat(string(F.scenario_id),"|",F.control_mode);
    if numel(unique(feature_keys))~=numel(feature_keys)
        error(['Duplicate scenario/method rows were found while merging. ' ...
            'Use a clean shard directory rather than silently choosing one copy.']);
    end
    F=sortrows(F,{'scenario_id','control_mode'});

    % Keep trajectories aligned with de-duplicated feature rows to preserve
    % provenance.
    if ~isempty(all_results)
        result_keys=strings(numel(all_results),1);
        for k=1:numel(all_results)
            result_keys(k)=string(all_results{k}.scenario_id)+"|"+ ...
                string(all_results{k}.method);
        end
        [unique_result_keys,result_keep]=unique(result_keys,'stable');
        if numel(unique_result_keys)~=numel(result_keys)
            error('Duplicate trajectory keys were found while merging shards.');
        end
        unique_results=all_results(result_keep);
        ordered_keys=strcat(string(F.scenario_id),"|",F.control_mode);
        [found,where]=ismember(ordered_keys,unique_result_keys);
        if ~all(found)
            error('Merged feature rows do not all have matching trajectory records.');
        end
        all_results=unique_results(where);
        if numel(all_results)~=height(F)
            error('Merged trajectory/feature row counts disagree.');
        end
    end
    D_run.source_shard_parameters_verified=true;
    fprintf('Merged %d shard files into %d unique run rows.\n',numel(files),height(F));
end

function Dclean=strip_shard_runtime_fields(Din)
    Dclean=Din;
    names={'output_dir','output_prefix','shard_index'};
    names=names(isfield(Dclean,names));
    if ~isempty(names), Dclean=rmfield(Dclean,names); end
end
