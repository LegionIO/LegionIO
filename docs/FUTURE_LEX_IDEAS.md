# Future LEX Extension Ideas

Potential extensions to build for LegionIO.

## Core Library

- [ ] **legion-web** - Shared inbound HTTP server + route registration (core library, same level as legion-transport). LEXs register their own webhook routes; adds `http` actor type alongside subscription/polling/interval/etc.

## Infrastructure & DevOps

- [ ] **lex-consul** - HashiCorp Consul (service discovery, KV operations, health checks)
- [ ] **lex-vault** - HashiCorp Vault (secrets management, dynamic credentials, PKI)
- [ ] **lex-tfe** - Terraform Enterprise/Cloud (workspace management, run triggers, state operations)
- [ ] **lex-nomad** - HashiCorp Nomad (job scheduling, deployments, allocation management)
- [ ] **lex-github** - GitHub (repos, issues, PRs, Actions, webhooks)
- [ ] **lex-artifactory** - JFrog Artifactory (artifact management, repository operations, build info)
- [ ] **lex-jenkins** - Jenkins (job triggers, build status, pipeline management)
- [ ] **lex-gitlab** - GitLab (repos, pipelines, merge requests, registry)
- [ ] **lex-docker** - Docker API (containers, images, exec, lifecycle management)
- [ ] **lex-kubernetes** - Kubernetes API (pods, deployments, jobs, services)
- [ ] **lex-servicenow** - ServiceNow (tickets, CMDB, incident management)
- [ ] **lex-jira** - Jira (issues, transitions, comments, boards)
- [ ] **lex-confluence** - Confluence (page CRUD, space management, search)
- [ ] **lex-infoblox** - Infoblox IPAM/DNS (IP allocation, DNS record management)

## Cloud Provider Services

- [ ] **lex-sqs** - AWS SQS (queue send/receive/manage)
- [ ] **lex-sns** - AWS SNS (topic publish, subscriptions, fan-out)
- [ ] **lex-lambda** - AWS Lambda (function invocation, async triggers)
- [ ] **lex-dynamodb** - AWS DynamoDB (item CRUD, queries, scans)
- [ ] **lex-azure-blob** - Azure Blob Storage (upload, download, container management)
- [ ] **lex-gcs** - Google Cloud Storage (object CRUD, bucket management)
- [ ] **lex-pubsub** - Google Cloud Pub/Sub (publish, subscribe, topic management)

## Databases

- [ ] **lex-postgres** - PostgreSQL (queries, prepared statements, notifications)
- [ ] **lex-mongodb** - MongoDB (document CRUD, aggregation pipelines)
- [ ] **lex-sqlite** - SQLite (lightweight local read/write, good for dev mode)

## Messaging & Streaming

- [ ] **lex-kafka** - Apache Kafka (produce, consume, topic management)
- [ ] **lex-mqtt** - MQTT (publish/subscribe, IoT messaging)
- [ ] **lex-webhook** - Generic inbound/outbound webhooks (catch-all for services without a dedicated LEX; depends on legion-web)

## Monitoring & Observability

- [ ] **lex-prometheus** - Prometheus (push metrics, query PromQL)
- [ ] **lex-grafana** - Grafana API (dashboards, annotations, alerting)
- [ ] **lex-datadog** - Datadog (events, metrics, logs, monitors)
- [ ] **lex-dynatrace** - Dynatrace (events, metrics, problem notifications)
- [ ] **lex-splunk** - Splunk (HEC log ingestion, saved searches)

## AI / LLM

- [ ] **lex-bedrock** - AWS Bedrock (model invocation, knowledge bases, agents)
- [ ] **lex-azure-ai** - Azure AI Foundry (model deployments, inference, AI services)
- [ ] **lex-openai** - OpenAI / ChatGPT (completions, embeddings, assistants)
- [ ] **lex-anthropic** - Anthropic / Claude (messages API, tool use, batch processing)
- [ ] **lex-gemini** - Google Gemini (generation, embeddings, multimodal)
- [ ] **lex-xai** - xAI / Grok (completions, embeddings)

## Communication

- [ ] **lex-teams** - Microsoft Teams (messages, adaptive cards, channel management)
- [ ] **lex-discord** - Discord (bot messages, channels, reactions)
- [ ] **lex-telegram** - Telegram (bot API, messages, inline keyboards)

## Network & DNS

- [ ] **lex-dns** - DNS lookups/record validation (health checks, service verification)

## File Transfer

- [ ] **lex-sftp** - SFTP/FTP (file upload, download, directory listing)
