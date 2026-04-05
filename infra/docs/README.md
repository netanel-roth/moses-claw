# Moses Claw Infrastructure

Custom VM configuration and scripts for the Moses Claw OpenClaw deployment.

## What's in this folder

```
infra/
├── scripts/           # Custom scripts installed on the VM
├── config/            # VM config files (Dockerfile, docker-compose, openclaw.json)
├── cron/              # Cron job definitions
├── gcp/               # GCP resources documentation
└── docs/              # How-to guides and architecture notes
```

## Related repositories

| Repo | Purpose |
|---|---|
| `mosesclaw-gcp` (this repo) | Deploy scripts + infra customizations |
| `netanel-roth/moses_claw_workspace` | Moses agent workspace (memory, skills, instructions) |
| `netanel-roth/ami_support_workspace` | AMI agent workspace (sandboxed) |

## Architecture overview

```
┌──────────────────────────────────────────────────────────────┐
│                       GCP moses-claw                          │
│                                                                │
│  ┌──────────────┐     ┌────────────────────────────────────┐ │
│  │ Secret       │     │  VM: openclaw-gateway              │ │
│  │ Manager      │────▶│  (e2-medium, europe-west1-b)       │ │
│  │              │     │                                     │ │
│  │ - GROQ_API   │     │  ┌──────────────────────────────┐ │ │
│  │ - GEMINI     │     │  │   Docker: openclaw-gateway   │ │ │
│  │ - TAVILY     │     │  │                               │ │ │
│  │ - TELEGRAM   │     │  │   ┌─────────┐ ┌─────────┐   │ │ │
│  │ - GATEWAY    │     │  │   │  Moses  │ │   AMI   │   │ │ │
│  │ - KEYRING    │     │  │   │ (main)  │ │ (sandbox)│  │ │ │
│  └──────────────┘     │  │   └─────────┘ └─────────┘   │ │ │
│                        │  │       │           │         │ │ │
│                        │  │       └─────┬─────┘         │ │ │
│                        │  │             │               │ │ │
│                        │  │       ┌─────▼─────┐         │ │ │
│                        │  │       │ WhatsApp  │         │ │ │
│                        │  │       │ Telegram  │         │ │ │
│                        │  │       └───────────┘         │ │ │
│                        │  └──────────────────────────────┘ │ │
│                        └────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────┘
                              ▲
                              │ IAP SSH tunnel only
                              │
                    ┌─────────┴─────────┐
                    │  Your Mac (local) │
                    └───────────────────┘
```

## What's tracked here vs elsewhere

**Tracked in this repo:**
- Deploy scripts (deploy.sh, destroy.sh, connect.sh, etc.)
- VM customizations (Dockerfile changes, compose mounts)
- Secret resolver scripts
- Cron jobs
- Documentation

**Tracked in workspace repos:**
- Agent personalities (SOUL.md, AGENTS.md)
- Agent memory (logs, learned facts)
- Agent skills (KB, self-improving)

**Not tracked anywhere (lives only in GCP):**
- Secret values (in Secret Manager)
- VM instance (can be recreated via deploy.sh)
- IAM bindings (must be re-created manually if project is recreated)

## Quick links

- [Setup from scratch](setup-from-scratch.md) — rebuild if VM dies
- [Secrets migration](secrets-migration.md) — how the secret system works
- [Multi-agent setup](multi-agent-setup.md) — Moses + AMI isolation
- [Known issues](known-issues.md) — quirks and workarounds
- [Secrets catalog](../gcp/secrets-catalog.md) — what's in Secret Manager
- [IAM bindings](../gcp/iam-bindings.md) — service account permissions
- [VM specs](../gcp/vm-specs.md) — machine type, zone, disk
