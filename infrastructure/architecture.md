# Infrastructure

> Native Windows services, scheduled tasks, and environment configuration that support the 6 memory layers.

## Services

The vector and pipeline layers run as native Windows processes:

| Service | Binary / Command | Default Port |
|---------|-----------------|-------------|
| **Qdrant** | `qdrant.exe` (from [GitHub releases](https://github.com/qdrant/qdrant/releases)) | 6333 |
| **Redis** | Native build via winget, Memurai, or Chocolatey | 6379 |
| **ARQ Worker** | `python docker\worker\main.py --run-worker` | — |

Start all services: `.\setup\start_services.ps1`
Stop all services: `.\setup\stop_services.ps1`

**Key configuration:**
- `EMBEDDING_DIMS=4096` — must match Qdrant collection schema
- `COLLECTION_NAME=knowledge_base` — target collection for all wiki ingestion
- Redis password required — set in `.env`, used by both Redis and worker
- `REDIS_HOST=127.0.0.1` and `QDRANT_HOST=localhost` — native networking

## Scheduled Tasks

Maintenance scripts are registered as Windows Task Scheduler jobs via `setup\setup_windows.ps1`:

| Job | Recommended schedule | What it does |
|-----|---------------------|--------------|
| **wiki-continuous-ingest** | Hourly (:00) | SHA-256 diff detection → embed new wiki files → Qdrant |
| **wiki-raw-ingest-monitor** | 2x/week | Read raw/ files → extract concepts/entities/comparisons → create wiki pages |
| **vault-curator-weekly** | Weekly | Phase 1 (frontmatter enrichment) + Phase 2 (semantic linking) + Phase 3 (INDEX.md) |
| **decay-scanner** | Weekly | Archive low-importance, aged AI content from Qdrant |
| **dlq-auto-report** | Every 6h | Dead letter queue monitoring and reporting |
| **maas-heartbeat** | Every 6h | Infrastructure health check |
| **holographic-memory-backup** | Weekly | Backup of workspace memory files and databases |
| **monitor-openrouter-balance** | Daily | OpenRouter credit balance check |

**Interaction between jobs:**
- `wiki-raw-ingest-monitor` creates new wiki pages → next `wiki-continuous-ingest` picks them up and sends to Qdrant
- `vault-curator-weekly` enriches ALL vault files — adds frontmatter, semantic links, and INDEX.md

## Environment Variables

### Required

| Variable | Purpose | Example |
|----------|---------|---------|
| `FABRIC_DIR` | Where Icarus writes fabric entries | `C:/Users/your-user/vault/fabric` |
| `OPENROUTER_API_KEY` | Embedding + LLM extraction | `sk-or-...` |
| `REDIS_PASSWORD` | Redis authentication | (generated) |

### Strongly recommended

| Variable | Default | Recommended | Why |
|----------|---------|-------------|-----|
| `ICARUS_EXTRACTION_MAX_TOKENS` | 1024 | **4096** | 1024 causes fabric truncation |
| `ICARUS_EXTRACTION_MODEL` | deepseek-v4-flash | same | Any OpenRouter chat model works |
| `EMBEDDING_DIMS` | varies | **4096** | Must match Qdrant collection schema |

### Optional

| Variable | Purpose |
|----------|---------|
| `ICARUS_OBSIDIAN=1` | Enable Obsidian wikilinks and daily notes |
| `OBSIDIAN_VAULT_PATH` | Vault root (if fabric is a subfolder) |
| `ICARUS_RESULT_MAX_CHARS` | Fallback truncation limit (default 500) |
| `ICARUS_TASK_MAX_CHARS` | Fallback task truncation (default 300) |
| `TOGETHER_API_KEY` | For training/eval tools |
| `OPENROUTER_FULL_API_KEY` | Alternative key for LLM extraction |
| `OPENROUTER_DS_API_KEY` | Alternative key for LLM extraction |
| `CURATOR_LOG_LEVEL` | Logging level for Vault Curator |
| `VAULT_PATH` | Path to vault root for Vault Curator |

## File locations

| Component | Path |
|-----------|------|
| Workspace memory | `$HERMES_HOME/memories/` |
| Session DB | `$HERMES_HOME/state.db` |
| Fact store DB | `$HERMES_HOME/memory_store.db` |
| Icarus plugin | `$HERMES_HOME/plugins/icarus/` |
| Fabric entries | `$FABRIC_DIR` |
| Wiki files | `$VAULT_PATH/wiki/` |
| Qdrant data | `%LOCALAPPDATA%\qdrant\storage\` |
| Scheduled tasks | Windows Task Scheduler (`MemoryOS-*`) |
| Cron scripts | Project scripts directory |

## System requirements

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| OS | Windows 10 21H2+ or 11 | x64 required |
| RAM | 8 GB | 16 GB (Qdrant + Redis + ARQ worker) |
| Disk | 20 GB | 50 GB (Qdrant vectors + wiki files) |
| Python | 3.11+ | 3.12 (tested) |
| Hermes Agent | 0.14.0+ | 0.15.2 (tested) |
| Qdrant | 1.17+ | 1.17.1 (tested) |
| Redis | Native build | winget, Memurai, or Chocolatey |
| Build Tools | Visual Studio 2022+ | C++ workload (for fastembed) |
| Scheduling | Windows Task Scheduler | Managed via PowerShell |

See [setup/install_windows.md](../setup/install_windows.md) for full installation instructions.
