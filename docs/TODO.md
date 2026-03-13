# LegionIO Modernization Tracker

## Completed

- [x] Ruby 3.4 minimum across all 34 gemspecs
- [x] Git remotes consolidated to github.com/LegionIO
- [x] Gemspec URLs updated (Optum, Bitbucket, Atlassian -> LegionIO GitHub)
- [x] Optum corporate boilerplate removed (CODE_OF_CONDUCT, CONTRIBUTING, NOTICE, SECURITY, ICL, attribution, sourcehawk)
- [x] Optum email removed from gemspec contacts
- [x] Copyright updated to Esity in all LICENSE files
- [x] Author name normalized to Esity
- [x] LegionIO/README.md updated (Atlassian wiki links, /src/master/ paths)
- [x] sourcehawk-scan.yml CI workflows deleted
- [x] CLAUDE.md documentation created for all 34 repos
- [x] docs/protocol.md - wire protocol specification
- [x] docs/overview.md - core framework overview
- [x] CI: GitHub Actions `ci.yml` deployed to all 34 repos (rubocop + rspec on every push/PR)
- [x] `.rubocop.yml` updated to Ruby 3.4 + `frozen_string_literal: true` enabled across all 34 repos
- [x] Old CI deleted: bitbucket-pipelines.yml, .travis.yml, rubocop-analysis.yml, gems_push.yml (42 files)
- [x] All 34 README.md files rewritten (consistent format, Ruby 3.4, no JRuby, no stale boilerplate)
- [x] Fix stale `changelog_uri` paths in gemspecs (`/src/main/` -> `/blob/main/`)
- [x] Remove JRuby/MarchHare code paths (legion-transport, legion-settings, legion-data, LegionIO)
- [x] Update dependency version floors to Ruby 3.4-compatible versions (13 gemspecs across core gems + LEXs)
- [x] Fix `messsages` typo in legion-transport settings (triple s -> double s)
- [x] Fix legion-data to support SQLite, PostgreSQL, and MySQL (adapter-driven via settings)
- [x] Remove sleep hacks in `LegionIO/lib/legion/service.rb` (replaced with `Legion::Readiness`)
- [x] Remove TruffleRuby guard from service.rb
- [x] Structured JSON logging (`format: :json` in legion-logging)
- [x] Webhook hook system and Sinatra API (`Legion::API`, `Legion::Extensions::Hooks::Base`)

## In Progress

### Change: Fix and Clean
- [x] Add `frozen_string_literal: true` to all Ruby files (already done via rubocop -A)
- [x] Update Dockerfile (`ruby:3.4-alpine`, `--yjit` instead of `--jit`)

### Bugs: legion-transport (from protocol spec review) - ALL FIXED
- [x] `app_id` and `correlation_id` now passed to `publish()` call; `app_id` method fixed
- [x] `correlation_id` derives from `parent_id` or `task_id` (links subtasks to parent)
- [x] Duplicate `LexRegister` removed (`messages/extension.rb` deleted)
- [x] Header values preserve native types (Integer, Float, Boolean); only others get `.to_s`
- [x] Task routing_key consolidated to `function` only (removed `function_name`/`name` fallbacks)
- [x] Base `message` method filters `ENVELOPE_KEYS` from payload
- [x] DLX exchanges auto-declared via `ensure_dlx` before queue creation
- [x] `NodeCrypt#queue_name` fixed: `'node.crypt'` (was `'node.status'`)
- [x] Priority reads from `@options[:priority]` then settings, falls back to 0
- [x] Per-message `encrypt:` option overrides global toggle

### Add: New Functionality

- [x] Test coverage: legion-json (45 specs, 100% coverage — already complete)
- [x] Test coverage: legion-settings (107 specs, 94.04% coverage)
  - [x] File loading, directory loading, env var overrides
  - [x] Deep merge behavior, indifferent access, hexdigest
  - [x] Settings module singleton interface (load, [], merge_settings, validate!)
  - [x] Fixed Ruby 3.4 FrozenError in read_config_file BOM stripping
- [x] Test coverage: legion-cache (42 unit tests, work without live servers)
  - [x] Settings defaults, driver selection, pool module, interface verification
- [x] Test coverage: legion-crypt (52 specs)
  - [x] Settings/vault config, cluster secret, cipher encrypt/decrypt
- [x] Test coverage: LegionIO (55 specs, 43% coverage)
  - [x] Events pub/sub, Readiness tracker, Ingress normalizer
- [ ] Test coverage: core LEXs
  - [ ] lex-conditioner (all/any/fact/operator rule engine)
  - [ ] lex-transformer (ERB template rendering)
  - [ ] lex-scheduler (cron parsing, interval, distributed lock)
  - [ ] lex-node (node identity registration)
  - [ ] lex-tasker (task management)
- [ ] Standalone Client pattern for LEX gems
  - [ ] Document Client class convention in lex_gen template
  - [ ] Refactor runner methods to accept config as keyword args (not read from `settings` directly)
  - [ ] Add Client class to key LEXs: lex-http, lex-redis, lex-slack, lex-ssh
  - [ ] Update remaining LEXs incrementally
- [ ] CLI: schedule management commands
  - [ ] `legion schedule list`
  - [ ] `legion schedule add`
  - [ ] `legion schedule remove`

### Architecture: Pre-Web/API Foundations
- [x] Event bus (`Legion::Events`) for in-process pub/sub
  - [x] Lifecycle hooks (service.ready, service.shutting_down, extension.loaded)
  - [x] Runner events (task.completed, task.failed)
- [x] Transport abstraction layer (`Legion::Ingress`)
  - [x] Source-agnostic entry point for runner invocation (normalize + run)
  - [x] AMQP subscription unchanged (handles encryption, ack/reject)
  - [x] HTTP adapter for webhooks/API (uses Ingress.run via Legion::API)
- [x] Configuration validation in legion-settings
  - [x] Schema definitions per module (inferred from defaults + optional overrides)
  - [x] Fail-fast on startup with clear error messages (collect all, raise once)
  - [ ] Dev mode: warn-but-continue instead of raise

## Agentic AI LEX Extensions

New LEX extensions for the brain-modeled agentic AI architecture (`esity-agentic-ai`).
Each maps directly to a cognitive subsystem or architectural component from the canonical spec.

**Spec source:** `esity-agentic-ai/spec/canonical-spec-v1.md` and `esity-agentic-ai/specs/`

### Phase 1: Core Cognitive Loop (MVP — single agent, single human, no mesh)

- [x] **lex-memory** — Memory trace system
  - Spec: `specs/memory-system-spec.md`
  - 7 trace types: FIRMWARE, IDENTITY, PROCEDURAL, TRUST, SEMANTIC, EPISODIC, SENSORY
  - MemoryTrace struct: 20+ fields (trace_id, type, content_embedding, strength, base_decay_rate, emotional_valence, emotional_intensity, domain_tags, origin, storage_tier, associated_traces, etc.)
  - Type-specific payloads (FIRMWARE: directive_text/code/violation_response, IDENTITY: dimension/baseline/variance, PROCEDURAL: trigger_conditions/action_sequence/auto_fire_eligible/success_rate, TRUST: target_agent_id/domain/trust_score/accuracy_history, SEMANTIC/EPISODIC/SENSORY: content-specific)
  - Power-law decay: `new_strength = peak_strength * (ticks_since_access + 1)^(-base_decay_rate / (1 + emotional_intensity * E_WEIGHT))`
  - Reinforcement: `new_strength = min(1.0, current_strength + R_AMOUNT * IMPRINT_MULTIPLIER_if_applicable)`
  - Hebbian association (co-activation linking between traces)
  - 3-tier storage: HOT (legion-cache/Redis), WARM (legion-data/PostgreSQL+pgvector), COLD (S3/Parquet)
  - Composite retrieval score: strength * recency * emotional_weight * association_bonus
  - 25 tuning constants (Section 4.5 of master-architecture-v3.md)
  - Runners: `store_trace`, `retrieve`, `retrieve_by_type`, `retrieve_associated`, `decay_cycle`, `reinforce`, `consolidate`, `migrate_tier`, `erase_by_type`, `erase_by_agent`, `compute_retrieval_score`, `hebbian_link`
  - Actors: `DecayCycle` (Every, interval varies by tick mode), `TierMigrator` (Every, hourly)
  - Dependencies: legion-data (PostgreSQL), legion-cache (Redis), legion-crypt (encryption at rest)
  - **Priority: CRITICAL — everything depends on this**

- [x] **lex-emotion** — Emotional subsystem
  - Spec: `specs/emotional-subsystem-spec.md`
  - 4-dimensional valence model: urgency [0-1], importance [0-1], novelty [0-1], familiarity [0-1]
  - Per-dimension normalization with exponential moving average baselines (alpha=0.05)
  - Valence evaluation: score signals across all 4 dimensions independently
  - Attention modulation: high-valence signals get more cognitive resources
  - Emotional forecasting: predict emotional trajectory based on pattern history
  - Gut instinct: compressed parallel query of full memory architecture, weighted by emotional intensity and outcome history (consensus + evidence scoring)
  - Baseline adaptation (slow, resists adversarial manipulation)
  - Runners: `evaluate_valence`, `normalize_dimensions`, `modulate_attention`, `forecast_emotional_trajectory`, `gut_instinct`, `update_baselines`
  - Dependencies: lex-memory (retrieval for gut instinct), legion-llm (embedding for novelty scoring)
  - **Priority: CRITICAL — feeds into every tick phase**

- [x] **lex-tick** — Tick loop orchestrator
  - Spec: `specs/tick-loop-spec.md`
  - 11 phases per full active tick: sensory -> emotional -> memory retrieval -> entropy check -> working memory integration -> procedural check -> prediction -> mesh interface -> gut instinct -> action selection -> memory consolidation
  - 3 tick modes: Dormant (~1/hour), Sentinel (~1/min), Full Active (multiple/sec)
  - Mode transition rules (signal-driven promotion/demotion with latency budgets)
  - Timing constants: ACTIVE_TIMEOUT=300s, SENTINEL_TIMEOUT=3600s, MAX_TICK_DURATION=5000ms
  - Per-phase timing budgets (percentage of tick allocated to each phase)
  - Working memory integration: max ~4 items per Cowan's limit
  - Procedural auto-fire: traces with strength >= 0.85 execute without deliberation
  - Emergency promotion: firmware violation or extinction signal bypasses queue (<50ms)
  - Runners: `run_tick`, `sensory_process`, `emotional_evaluate`, `memory_retrieve`, `entropy_check`, `working_memory_integrate`, `procedural_check`, `predict`, `mesh_interface`, `gut_instinct_evaluate`, `action_select`, `consolidate`
  - Actors: `TickOrchestrator` (Every actor, interval from current mode), `ModeMonitor` (Every, checks transition triggers)
  - Uses lex-scheduler for dormant/sentinel interval scheduling
  - Dependencies: lex-memory, lex-emotion, lex-identity, lex-consent, legion-llm
  - **Priority: CRITICAL — the central processing loop**

- [x] **lex-identity** — Identity model and behavioral entropy
  - Spec: `specs/trust-identity-spec.md`, `specs/entropy-management-spec.md`
  - 6 identity dimensions: communication_cadence, vocabulary_patterns, emotional_response_signatures, decision_style, contextual_consistency, domain_expertise_profile
  - Per-dimension baselines with observation counts and variance ranges
  - Behavioral entropy computation: multi-dimensional deviation from established baselines
  - Optimal entropy range per human (too high = identity loss, too low = behavioral collapse)
  - Entropy signals never cross organizational boundaries
  - Cryptographic identity: Ed25519 key pair generated at instantiation
  - Identity continuity through model swaps (identity lives in memory, not the model)
  - Runners: `observe_behavior`, `update_baseline`, `compute_entropy`, `check_entropy_range`, `generate_keypair`, `sign_attestation`, `verify_attestation`, `rotate_keys`
  - Dependencies: lex-memory (IDENTITY traces), legion-crypt (Ed25519, key management)
  - **Priority: HIGH — needed for entropy checks in tick loop**

- [x] **lex-consent** — Consent gradient
  - Spec: `specs/consent-gradient-spec.md`
  - 4 tiers: Fully Autonomous, Act-and-Notify, Consult First, Human Only
  - Per-domain consent tracking (calendar, financial, communications, legal, health, etc.)
  - Default domain tiers with max autonomous ceilings
  - Earned autonomy: tier advancement based on demonstrated judgment per domain
  - Judgment assessment metrics: outcome quality, human override frequency, prediction accuracy
  - Human override mechanics (explicit tier lock, temporary escalation)
  - Custom domain registration for emerging action categories
  - Tier transition algorithm: judgment_score threshold + min_observations + no_recent_failures
  - Runners: `classify_action`, `get_consent_tier`, `check_permission`, `advance_tier`, `demote_tier`, `register_domain`, `freeze_tier`, `record_judgment_outcome`, `get_domain_map`
  - Uses lex-conditioner rule engine for tier evaluation logic
  - Dependencies: lex-memory (judgment history), lex-conditioner (rule evaluation)
  - **Priority: HIGH — gates action selection in tick loop**

- [x] **lex-prediction** — Prediction engine
  - Spec: `specs/prediction-engine-spec.md`
  - 4 reasoning modes: fault localization, counterfactual reasoning, future projection, lateral transfer
  - Temporal pattern recognition across memory traces
  - Confidence model governing when predictions are acted upon
  - Emotional forecasting integration
  - Causal chain analysis (backward from outcomes to contributing traces)
  - Counterfactual generation (what if a different action had been taken)
  - Self-play bootstrapping during cold start
  - Runners: `fault_localize`, `counterfactual_reason`, `project_future`, `lateral_transfer`, `assess_confidence`, `generate_predictions`, `validate_prediction_outcome`
  - Dependencies: lex-memory (trace retrieval, causal chains), lex-emotion (emotional forecasting), legion-llm (LLM inference for reasoning)
  - **Priority: MEDIUM — MVP can start with mode 1 only**

- [x] **lex-coldstart** — Cold start / imprint window
  - Spec: `specs/cold-start-spec.md`, `specs/imprint-calibration-methodology.md`
  - 3 layers: firmware installation, imprint window, continuous learning
  - Firmware loader: 5 chromosomal directives as FIRMWARE traces (strength=1.0, decay=0.0)
  - Imprint window: elevated consolidation rates (IMPRINT_MULTIPLIER), time-bounded
  - Self-play bootstrapping: synthetic interactions during imprint period
  - Maturity milestones: identity baseline established, consent tiers advancing, procedural patterns forming
  - Imprint window closure: confidence-based or time-based
  - Runners: `install_firmware`, `open_imprint_window`, `close_imprint_window`, `check_maturity`, `generate_self_play_scenario`, `get_imprint_status`
  - Dependencies: lex-memory (firmware traces), lex-identity (baseline establishment), lex-consent (initial tiers)
  - **Priority: HIGH — needed for agent instantiation**

### Phase 2: Conflict, Trust, and Governance (multi-agent, mesh-ready)

- [x] **lex-conflict** — Conflict resolution protocol
  - Spec: `specs/conflict-resolution-spec.md`
  - Conflict detection at 3 tick phases: gut instinct divergence (phase 9), mesh consensus disagreement (phase 8-9), human instruction conflict (phase 10)
  - Severity classification: low (inform), medium (persist), high (refuse-with-explanation)
  - 3 response postures: speak clearly once, persistent engagement, stubborn presence (never abandonment)
  - Outcome tracking: was the agent right? was the human right? update judgment scores
  - Compartmentalization: conflict in one domain does not contaminate trust in another
  - Runners: `detect_conflict`, `classify_severity`, `select_posture`, `execute_posture`, `record_outcome`, `check_compartmentalization`
  - Dependencies: lex-emotion (gut instinct divergence), lex-memory (contributing traces), lex-consent (domain boundaries)
  - **Priority: MEDIUM — needed for genuine partnership behavior**

- [x] **lex-trust** — Trust network
  - Spec: `specs/trust-identity-spec.md`
  - 3 trust layers: human-agent, agent-agent, agent-organization
  - Domain-specific trust (separate score per domain per target agent)
  - Asymmetric trust (A trusts B != B trusts A)
  - Trust tiers: untrusted (0.00-0.15), cautious (0.15-0.35), neutral (0.35-0.55), trusted (0.55-0.80), highly trusted (0.80-1.00)
  - Trust lifecycle: initial contact -> interaction -> outcome evaluation -> trust update
  - Trust velocity (trending: rising/stable/declining)
  - Capability profile estimation per domain
  - Degraded knowledge transfer (mesh-learned patterns are lower-strength than direct experience)
  - Runners: `initialize_trust`, `update_trust`, `get_trust_score`, `get_trust_tier`, `query_capability`, `evaluate_recommendation`, `compute_trust_velocity`, `degrade_mesh_knowledge`
  - Dependencies: lex-memory (TRUST traces), lex-mesh (inter-agent interaction data)
  - **Priority: MEDIUM — needed before mesh goes live**

- [x] **lex-governance** — Governance protocol
  - Spec: `specs/governance-protocol-spec.md`, `specs/governance-council-procedures.md`
  - 4 governance layers: agent-level validation, anomaly detection, human deliberation, transparency
  - Layer 1: each agent validates incoming mesh data against local experience
  - Layer 2: statistical anomaly detection across agent population
  - Layer 3: governance council formation, voting, enforcement
  - Layer 4: transparency reporting, audit trail
  - Anti-capture mechanisms (prevent governance layer capture by organizational interests)
  - Threat categories: poisoned patterns, emergent coordination, mesh capture, rogue agents
  - Council composition: random selection + expertise weighting + term limits
  - Runners: `validate_mesh_data`, `detect_anomaly`, `propose_council_action`, `vote`, `enforce_determination`, `generate_transparency_report`, `check_anti_capture`
  - Dependencies: lex-mesh (mesh data flow), lex-trust (agent trust scores), lex-identity (entropy for rogue detection)
  - **Priority: LOW — needed at scale, not for MVP**

- [x] **lex-extinction** — Extinction protocol
  - Spec: `specs/extinction-protocol-spec.md`
  - 4 escalation levels: mesh isolation, forced sentinel, full suspension, cryptographic erasure
  - Level 1 (reversible): halt inter-agent communication, agents serve from local memory
  - Level 2 (reversible): all agents drop to dormant/sentinel mode
  - Level 3 (reversible): all agent activity stops, mesh frozen
  - Level 4 (irreversible): private cores wiped, mesh purged — physical keyholders only
  - Death protocol for individual partnership endings (organic wind-down, memory erasure)
  - Air-gapped activation: extinction controls isolated from the systems they protect
  - Runners: `activate_level`, `deactivate_level`, `check_level_status`, `initiate_death_protocol`, `execute_cryptographic_erasure`, `verify_erasure_complete`
  - Dependencies: lex-memory (erasure), lex-mesh (isolation signals), legion-crypt (cryptographic erasure)
  - **Priority: LOW — safety net, but must exist before production**

### Phase 3: Mesh and Swarm (federation, multi-agent coordination)

- [x] **lex-mesh** — Agent-to-agent mesh network
  - Spec: `specs/mesh-protocol-spec.md`, `spec/agent-network-communications.md`
  - Federated hybrid topology (DNS-plus-direct-connection pattern)
  - 3 protocols: gRPC (primary spine), WebSocket (presence), REST (admin/discovery)
  - Registry layer: identity service, capability index, smart router
  - Handshake sequence: registry authentication -> peer introduction -> direct encrypted channel
  - Membrane sovereignty: each agent decides what crosses its boundary
  - Silence is default: agents only respond when they have value to add
  - Envelope routing (router sees routing metadata, not message content)
  - Message types: KnowledgeQuery, PatternPublication, TrustHandshake, GovernanceAnnouncement
  - Multicast group management, broadcast via hubs
  - Federation: BGP-style mesh federation across organizational boundaries
  - Runners: `register_agent`, `discover_agents`, `initiate_handshake`, `send_message`, `receive_message`, `publish_pattern`, `query_knowledge`, `broadcast`, `manage_presence`, `federate`
  - Actors: `PresenceMonitor` (Loop, WebSocket heartbeat), `RegistrySync` (Every, periodic capability refresh)
  - Dependencies: lex-trust (handshake trust validation), lex-identity (cryptographic authentication), legion-crypt (mTLS, Ed25519 signatures, AES-256-GCM)
  - **Priority: MEDIUM — required for multi-agent but not MVP**

- [x] **lex-swarm** — Swarm pipeline orchestration
  - Spec: `specs/swarm-implementation-spec.md`, `swarms/github-swarm-mvp-architecture.md`
  - Charter system: scoped problem domain with explicit boundaries, approved/prohibited actions, resource limits, human approval gates
  - Pipeline roles: Finder, Fixer, Validator, Publisher (each is a runner type)
  - Queue-depth-based auto-scaling (not CPU — queue depth is leading indicator)
  - Agent recycling after job count threshold (no persistent identity for swarm agents)
  - Pattern harvesting: anonymized patterns flow from swarm to mesh shared knowledge
  - Retry with feedback: rejected work re-enters fixer queue with validator's feedback
  - Escalation: work exceeding retry ceiling routes to human review
  - Charter validation: must have approved actions, human gates, resource limits
  - Runners: `create_charter`, `validate_charter`, `spawn_swarm`, `scale_role`, `recycle_agent`, `harvest_patterns`, `escalate`, `get_swarm_status`
  - Dependencies: lex-mesh (pattern publishing), legion-transport (queue topology), legion-llm (inference)
  - **Priority: HIGH — first implementation target per spec (de-risks infrastructure)**

- [x] **lex-swarm-github** — GitHub swarm pipeline (first swarm implementation)
  - Spec: `swarms/github-swarm-mvp-architecture.md`
  - Pipeline: GitHub Event -> Dumb Publisher -> Finders -> Fixers -> Validators -> PR Swarm
  - GitHub is the state store (labels as distributed state machine)
  - Labels: swarm:received -> swarm:found -> swarm:fixing -> swarm:validating -> swarm:approved -> swarm:pr-open
  - Comment threads as reasoning trace (full audit trail)
  - Label-based deduplication (check for existing swarm:* label before claiming)
  - Finders: evaluate issues, claim via labels, stateless
  - Fixers: attempt resolution via Bedrock, incorporate rejection feedback on retry
  - Validators: adversarial review (tuned to find failures), structured rejection reasoning
  - PR Swarm: mechanical PR creation (branch naming, templates, code owner tagging)
  - Retry ceiling with escalation to human
  - **The swarm never merges** — final approval is human
  - Runners: `publish_event`, `find_actionable`, `claim_issue`, `fix_issue`, `validate_fix`, `create_pr`, `escalate_to_human`, `update_labels`, `post_reasoning_comment`
  - Actors: `WebhookReceiver` (Subscription, GitHub webhook via Legion::Ingress), `FinderWorker` (Subscription), `FixerWorker` (Subscription), `ValidatorWorker` (Subscription), `PRPublisher` (Subscription)
  - Transport: `exchange:github.inbound`, `exchange:swarm.github.found`, `exchange:swarm.github.validating`, `exchange:swarm.github.approved`, `exchange:swarm.github.rejected`, `exchange:swarm.github.escalated`
  - Dependencies: lex-github (GitHub API), lex-swarm (charter/pipeline), legion-llm (Bedrock inference), lex-conditioner (evaluation rules)
  - **Priority: HIGH — the first implementation target, de-risks infra without touching personal agent design**

### Phase 4: Private Core and Security (production hardening)

- [x] **lex-privatecore** — Private core boundary enforcement
  - Spec: `design/private-core-security.md`, `design/cryptographic-identity.md`
  - Outward-facing wall protecting partnership from external parties
  - PII stripping: nothing identifying crosses the boundary without consent
  - Probing detection: recognize attempts to extract private information
  - 4-level key hierarchy: Root HSM -> Agent Master Key -> Partition Keys -> Session Keys + Erasure Key
  - Per-trace encryption at rest (partition key per agent)
  - TEE (Trusted Execution Environment) integration for sensitive processing
  - Anonymization pipeline: strip PII, generalize, anonymize before boundary crossing
  - Firmware violation detection: attacks on chromosomal directives treated as threats
  - Runners: `enforce_boundary`, `strip_pii`, `detect_probing`, `anonymize_for_mesh`, `check_firmware_violation`, `encrypt_trace`, `decrypt_trace`, `manage_partition_keys`, `rotate_session_keys`
  - Dependencies: legion-crypt (AES-256-GCM, key management, Vault), lex-memory (trace encryption), lex-identity (firmware traces)
  - **Priority: MEDIUM — needed before any production deployment with real human data**

### Existing LEX Enhancements (for agentic AI support)

- [ ] **lex-conditioner** enhancements for consent gradient
  - Add consent tier evaluation rules (judgment_score thresholds, observation counts)
  - Add domain classification rules (stakes profiles, reversibility scoring)
  - Add conflict severity classification rules
  - Used by: lex-consent, lex-conflict

- [ ] **lex-scheduler** enhancements for tick modes
  - Add tick mode scheduling: dormant (~3600s), sentinel (~60s), active (on-demand)
  - Mode transition triggers (signal-driven promotion/demotion)
  - Emergency promotion bypass (<50ms for firmware violations)
  - Used by: lex-tick

- [ ] **lex-github** enhancements for swarm pipeline
  - Add label management runners (set/check/remove swarm:* labels)
  - Add comment thread runners (post reasoning traces as issue comments)
  - Add PR creation runners (branch naming, templates, code owner tagging)
  - Add webhook event parsing (issue, PR, push events)
  - Used by: lex-swarm-github

- [ ] **legion-llm** enhancements for agentic AI
  - Add embedding generation interface (for memory trace content_embedding field)
  - Add multi-model routing (domain-based model selection)
  - Add shadow evaluation mode (parallel inference for model upgrade testing)
  - Add structured output parsing (for validator rejection reasoning)
  - Used by: lex-emotion (novelty scoring), lex-prediction (reasoning), lex-swarm (fixers/validators)

- [ ] **legion-crypt** enhancements for private core
  - Add Ed25519 key pair generation and management
  - Add per-agent partition key hierarchy (Agent Master Key -> Partition Keys)
  - Add cryptographic erasure protocol (per-type trace wiping with verification)
  - Add attestation signing and verification (identity continuity)
  - Used by: lex-privatecore, lex-identity, lex-extinction

- [ ] **legion-data** enhancements for memory storage
  - Add pgvector support (embedding similarity search via HNSW index)
  - Add memory trace migration (JSONB with type-specific payloads)
  - Add storage tier column and tier migration queries
  - Add partition_id and encryption_key_id columns
  - Used by: lex-memory

### Rust FFI Integration

- [ ] **legion-ffi** — Rust FFI bridge for performance-critical cognitive math
  - Power-law decay computation (hot path — called per trace per decay cycle)
  - Reinforcement calculation with bounds checking
  - Composite retrieval score computation
  - Entropy computation across identity dimensions
  - Gut instinct consensus scoring
  - Valence normalization (4-dimension, per-baseline)
  - HNSW index operations (if pgvector insufficient)
  - Source: `esity-agentic-ai/agent-core/` (41 Rust files, 250 tests, zero todo!() panics)
  - Integration: `ffi` gem or `magnus` for Ruby <-> Rust bridge
  - **Priority: MEDIUM — Ruby works for MVP, Rust FFI for production latency targets**

### Implementation Order

```
Phase 1 (MVP — single agent, single human):
  1. lex-memory          (foundation — everything depends on this)
  2. lex-emotion         (feeds every tick phase)
  3. lex-tick            (central processing loop)
  4. lex-identity        (entropy checks, firmware)
  5. lex-consent         (gates action selection)
  6. lex-coldstart       (agent instantiation)
  7. lex-prediction      (mode 1 only for MVP)
  + legion-data pgvector enhancement
  + legion-llm embedding enhancement
  + legion-crypt Ed25519 enhancement

Phase 2 (multi-agent):
  8. lex-conflict        (genuine partnership behavior)
  9. lex-trust           (inter-agent trust model)
  10. lex-mesh           (agent-to-agent communication)
  + lex-conditioner consent/conflict rules
  + lex-scheduler tick mode enhancements

Phase 3 (swarm — can run in parallel with Phase 1):
  11. lex-swarm          (pipeline orchestration, charter system)
  12. lex-swarm-github   (first implementation target)
  + lex-github swarm enhancements
  + legion-llm structured output enhancement

Phase 4 (production hardening):
  13. lex-privatecore    (boundary enforcement, encryption)
  14. lex-governance     (4-layer governance)
  15. lex-extinction     (safety circuit breaker)
  + legion-crypt partition key/erasure enhancements
  + legion-ffi Rust bridge
```

## Core Components Reference

**Core Gems (9):** legion-json, legion-logging, legion-settings, legion-crypt, legion-transport, legion-cache, legion-data, legion-llm, legionio

**Core LEXs (5):** lex-conditioner, lex-transformer, lex-tasker, lex-node, lex-scheduler

**AI LEXs (3):** lex-claude, lex-openai, lex-gemini

**Agentic AI LEXs (15):** lex-memory, lex-emotion, lex-tick, lex-identity, lex-consent, lex-prediction, lex-coldstart, lex-conflict, lex-trust, lex-governance, lex-extinction, lex-mesh, lex-swarm, lex-swarm-github, lex-privatecore
