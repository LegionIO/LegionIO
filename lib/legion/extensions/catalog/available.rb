# frozen_string_literal: true

module Legion
  module Extensions
    module Catalog
      module Available
        EXTENSIONS = [
          # core
          { name: 'lex-acp', category: 'core', description: 'Agent communication protocol' },
          { name: 'lex-audit',        category: 'core',     description: 'Audit logging and trail' },
          { name: 'lex-codegen',      category: 'core',     description: 'Code generation pipeline' },
          { name: 'lex-conditioner',  category: 'core',     description: 'Task chain conditioning' },
          { name: 'lex-detect',       category: 'core',     description: 'Environment detection and recommendations' },
          { name: 'lex-exec',         category: 'core',     description: 'Shell command execution' },
          { name: 'lex-health',       category: 'core',     description: 'Health monitoring and metrics' },
          { name: 'lex-lex',          category: 'core',     description: 'Extension management' },
          { name: 'lex-llm-gateway',  category: 'core',     description: 'Legacy LLM gateway compatibility' },
          { name: 'lex-llm-ledger',   category: 'core',     description: 'LLM cost and usage ledger' },
          { name: 'lex-log',          category: 'core',     description: 'Log shipping and aggregation' },
          { name: 'lex-metering',     category: 'core',     description: 'Resource metering and accounting' },
          { name: 'lex-node',         category: 'core',     description: 'Node identity and registration' },
          { name: 'lex-ping',         category: 'core',     description: 'Connectivity checks' },
          { name: 'lex-react',        category: 'core',     description: 'Event-driven reaction engine' },
          { name: 'lex-scheduler',    category: 'core',     description: 'Cron and interval scheduling' },
          { name: 'lex-synapse',      category: 'core',     description: 'Agent-to-agent relationships' },
          { name: 'lex-tasker',       category: 'core',     description: 'Task management and lifecycle' },
          { name: 'lex-telemetry',    category: 'core',     description: 'OpenTelemetry tracing integration' },
          { name: 'lex-transformer',  category: 'core',     description: 'Task chain transformation' },
          { name: 'lex-webhook',      category: 'core',     description: 'Inbound webhook receiver' },
          # ai
          { name: 'lex-azure-ai',     category: 'ai',       description: 'Azure OpenAI provider integration' },
          { name: 'lex-bedrock',      category: 'ai',       description: 'AWS Bedrock LLM provider integration' },
          { name: 'lex-claude',       category: 'ai',       description: 'Anthropic Claude provider integration' },
          { name: 'lex-foundry',      category: 'ai',       description: 'Azure AI Foundry provider integration' },
          { name: 'lex-gemini',       category: 'ai',       description: 'Google Gemini provider integration' },
          { name: 'lex-ollama',       category: 'ai',       description: 'Ollama local LLM provider integration' },
          { name: 'lex-openai',       category: 'ai',       description: 'OpenAI provider integration' },
          { name: 'lex-xai',          category: 'ai',       description: 'xAI Grok provider integration' },
          { name: 'lex-llm',          category: 'ai',       description: 'Common LLM provider base and routing metadata' },
          { name: 'lex-llm-anthropic', category: 'ai',      description: 'Anthropic LLM provider integration' },
          { name: 'lex-llm-azure-foundry', category: 'ai',  description: 'Azure AI Foundry hosted LLM provider integration' },
          { name: 'lex-llm-bedrock',  category: 'ai',       description: 'AWS Bedrock hosted LLM provider integration' },
          { name: 'lex-llm-gemini',   category: 'ai',       description: 'Google Gemini LLM provider integration' },
          { name: 'lex-llm-mlx',      category: 'ai',       description: 'Apple MLX local LLM provider integration' },
          { name: 'lex-llm-ollama',   category: 'ai',       description: 'Ollama LLM provider integration' },
          { name: 'lex-llm-openai',   category: 'ai',       description: 'OpenAI LLM provider integration' },
          { name: 'lex-llm-vertex',   category: 'ai',       description: 'Google Vertex AI hosted LLM provider integration' },
          { name: 'lex-llm-vllm',     category: 'ai',       description: 'vLLM OpenAI-compatible provider integration' },
          # agentic
          { name: 'lex-agentic-affect',       category: 'agentic', description: 'Affective state modeling' },
          { name: 'lex-agentic-attention',    category: 'agentic', description: 'Attentional focus and salience' },
          { name: 'lex-agentic-defense',      category: 'agentic', description: 'Defensive behavior and threat response' },
          { name: 'lex-agentic-executive',    category: 'agentic', description: 'Executive function and planning' },
          { name: 'lex-agentic-homeostasis',  category: 'agentic', description: 'Internal state regulation' },
          { name: 'lex-agentic-imagination',  category: 'agentic', description: 'Generative imagination and hypothesis' },
          { name: 'lex-agentic-inference',    category: 'agentic', description: 'Probabilistic inference engine' },
          { name: 'lex-agentic-integration',  category: 'agentic', description: 'Cross-domain knowledge integration' },
          { name: 'lex-agentic-language',     category: 'agentic', description: 'Natural language understanding' },
          { name: 'lex-agentic-learning',     category: 'agentic', description: 'Online learning and adaptation' },
          { name: 'lex-agentic-memory',       category: 'agentic', description: 'Long-term memory and recall' },
          { name: 'lex-agentic-self',         category: 'agentic', description: 'Self-model and identity' },
          { name: 'lex-agentic-social',       category: 'agentic', description: 'Social cognition and theory of mind' },
          { name: 'lex-adapter',              category: 'agentic', description: 'Protocol and format adaptation' },
          { name: 'lex-apollo',               category: 'agentic', description: 'Shared knowledge store client' },
          { name: 'lex-autofix',              category: 'agentic', description: 'Autonomous code fix pipeline' },
          { name: 'lex-coldstart',            category: 'agentic', description: 'Bootstrap knowledge ingestion' },
          { name: 'lex-cost-scanner',         category: 'agentic', description: 'Cloud cost scanning and analysis' },
          { name: 'lex-dataset',              category: 'agentic', description: 'Dataset management and versioning' },
          { name: 'lex-eval',                 category: 'agentic', description: 'LLM evaluation framework' },
          { name: 'lex-extinction',           category: 'agentic', description: 'Worker lifecycle termination' },
          { name: 'lex-factory',              category: 'agentic', description: 'Spec-to-code generation pipeline' },
          { name: 'lex-finops',               category: 'agentic', description: 'FinOps cost optimization' },
          { name: 'lex-governance',           category: 'agentic', description: 'Policy and compliance governance' },
          { name: 'lex-knowledge',            category: 'agentic', description: 'Corpus ingestion and knowledge query' },
          { name: 'lex-mesh',                 category: 'agentic', description: 'Agent mesh and preference exchange' },
          { name: 'lex-mind-growth',          category: 'agentic', description: 'Autonomous cognitive expansion' },
          { name: 'lex-onboard',              category: 'agentic', description: 'New agent onboarding workflow' },
          { name: 'lex-pilot-infra-monitor',  category: 'agentic', description: 'Infrastructure monitoring pilot' },
          { name: 'lex-pilot-knowledge-assist', category: 'agentic', description: 'Knowledge assist pilot worker' },
          { name: 'lex-privatecore',          category: 'agentic', description: 'Private execution enclave' },
          { name: 'lex-prompt',               category: 'agentic', description: 'Prompt management and versioning' },
          { name: 'lex-swarm',                category: 'agentic', description: 'Multi-agent swarm orchestration' },
          { name: 'lex-swarm-github',         category: 'agentic', description: 'GitHub code review swarm' },
          { name: 'lex-tick',                 category: 'agentic', description: 'Gaia tick cycle driver' },
          # identity
          { name: 'lex-identity-approle',    category: 'identity', description: 'Vault AppRole identity provider' },
          { name: 'lex-identity-aws',        category: 'identity', description: 'AWS IAM identity provider' },
          { name: 'lex-identity-entra',      category: 'identity', description: 'Microsoft Entra identity provider' },
          { name: 'lex-identity-github',     category: 'identity', description: 'GitHub App identity provider' },
          { name: 'lex-identity-kerberos',   category: 'identity', description: 'Kerberos identity provider' },
          { name: 'lex-identity-kubernetes', category: 'identity', description: 'Kubernetes service account identity provider' },
          { name: 'lex-identity-ldap',       category: 'identity', description: 'LDAP identity provider' },
          { name: 'lex-identity-system',     category: 'identity', description: 'System identity provider' },
          # service integrations
          { name: 'lex-consul',          category: 'service', description: 'HashiCorp Consul service mesh integration' },
          { name: 'lex-github',          category: 'service', description: 'GitHub API integration' },
          { name: 'lex-http',            category: 'service', description: 'Generic HTTP client runner' },
          { name: 'lex-kerberos',        category: 'service', description: 'Kerberos authentication integration' },
          { name: 'lex-microsoft_teams', category: 'service', description: 'Microsoft Teams messaging integration' },
          { name: 'lex-nomad',           category: 'service', description: 'HashiCorp Nomad job integration' },
          { name: 'lex-redis',           category: 'service', description: 'Redis integration' },
          { name: 'lex-s3',              category: 'service', description: 'AWS S3 object storage integration' },
          { name: 'lex-tfe',             category: 'service', description: 'Terraform Enterprise integration' },
          { name: 'lex-uais',            category: 'service', description: 'UHG AI Services integration' },
          { name: 'lex-vault',           category: 'service', description: 'HashiCorp Vault secrets integration' },
          # other integrations
          { name: 'lex-aha',                  category: 'other', description: 'Aha! roadmap integration' },
          { name: 'lex-chef',                 category: 'other', description: 'Chef infrastructure automation' },
          { name: 'lex-cloudflare',           category: 'other', description: 'Cloudflare DNS and CDN integration' },
          { name: 'lex-discord',              category: 'other', description: 'Discord messaging integration' },
          { name: 'lex-dns',                  category: 'other', description: 'DNS query and management' },
          { name: 'lex-docker',               category: 'other', description: 'Docker container integration' },
          { name: 'lex-dynatrace',            category: 'other', description: 'Dynatrace APM integration' },
          { name: 'lex-elastic_app_search',   category: 'other', description: 'Elastic App Search integration' },
          { name: 'lex-elasticsearch',        category: 'other', description: 'Elasticsearch integration' },
          { name: 'lex-gitlab',               category: 'other', description: 'GitLab integration' },
          { name: 'lex-google-calendar',      category: 'other', description: 'Google Calendar integration' },
          { name: 'lex-grafana',              category: 'other', description: 'Grafana dashboard integration' },
          { name: 'lex-home-assistant',       category: 'other', description: 'Home Assistant smart home integration' },
          { name: 'lex-influxdb',             category: 'other', description: 'InfluxDB time series integration' },
          { name: 'lex-infoblox',             category: 'other', description: 'Infoblox IPAM/DNS integration' },
          { name: 'lex-jenkins',              category: 'other', description: 'Jenkins CI/CD integration' },
          { name: 'lex-jfrog',                category: 'other', description: 'JFrog Artifactory integration' },
          { name: 'lex-jira',                 category: 'other', description: 'Jira issue tracking integration' },
          { name: 'lex-kafka',                category: 'other', description: 'Apache Kafka messaging integration' },
          { name: 'lex-kubernetes',           category: 'other', description: 'Kubernetes cluster integration' },
          { name: 'lex-lambda',               category: 'other', description: 'AWS Lambda function integration' },
          { name: 'lex-memcached',            category: 'other', description: 'Memcached cache integration' },
          { name: 'lex-mongodb',              category: 'other', description: 'MongoDB integration' },
          { name: 'lex-mqtt',                 category: 'other', description: 'MQTT IoT messaging integration' },
          { name: 'lex-openweathermap',       category: 'other', description: 'OpenWeatherMap weather integration' },
          { name: 'lex-pagerduty',            category: 'other', description: 'PagerDuty alerting integration' },
          { name: 'lex-pihole',               category: 'other', description: 'Pi-hole DNS filtering integration' },
          { name: 'lex-postgres',             category: 'other', description: 'PostgreSQL database integration' },
          { name: 'lex-prometheus',           category: 'other', description: 'Prometheus metrics integration' },
          { name: 'lex-pushbullet',           category: 'other', description: 'Pushbullet notification integration' },
          { name: 'lex-pushover',             category: 'other', description: 'Pushover notification integration' },
          { name: 'lex-sftp',                 category: 'other', description: 'SFTP file transfer integration' },
          { name: 'lex-slack',                category: 'other', description: 'Slack messaging integration' },
          { name: 'lex-sleepiq',              category: 'other', description: 'SleepIQ bed sensor integration' },
          { name: 'lex-smtp',                 category: 'other', description: 'SMTP email integration' },
          { name: 'lex-sonos',                category: 'other', description: 'Sonos audio integration' },
          { name: 'lex-sqs',                  category: 'other', description: 'AWS SQS queue integration' },
          { name: 'lex-ssh',                  category: 'other', description: 'SSH remote execution integration' },
          { name: 'lex-telegram',             category: 'other', description: 'Telegram messaging integration' },
          { name: 'lex-todoist',              category: 'other', description: 'Todoist task management integration' },
          { name: 'lex-twilio',               category: 'other', description: 'Twilio SMS/voice integration' },
          { name: 'lex-wled',                 category: 'other', description: 'WLED LED controller integration' }
        ].each(&:freeze).freeze

        class << self
          def all
            EXTENSIONS.map(&:dup)
          end

          def by_category(category)
            EXTENSIONS.select { |e| e[:category] == category }.map(&:dup)
          end

          def find(name)
            entry = EXTENSIONS.find { |e| e[:name] == name }
            entry&.dup
          end
        end
      end
    end
  end
end
