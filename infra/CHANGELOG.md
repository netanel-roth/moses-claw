# Changelog

All notable changes to the Moses Claw infrastructure.

## [Unreleased]

### Added
- `infra/` folder in `mosesclaw-gcp` repo — captures all VM customizations
- GCP Secret Manager integration — 6 secrets migrated from plaintext
- Secret resolver script (`openclaw-secret-resolver`) — exec-based SecretRef provider
- Boot-time secret fetcher (`openclaw-fetch-secrets.sh`) — populates `.env.secrets` from GCP
- Multi-agent setup — Moses (main) + AMI (sandboxed support agent)
- AMI agent sandbox with Docker-in-Docker via mounted Docker socket
- Custom sandbox image with Node.js baked in (for `kb.js`)
- Dockerfile changes: Docker CLI binary added to gateway image
- Docker compose: mounts for AMI workspace host path, Docker socket, resolver script
- OpenAI Codex OAuth authentication (no Anthropic subscription anymore)
- Cron jobs for git auto-sync on both workspaces (push + pull every minute)
- Clear-sandbox-on-pull cron for AMI (reloads agent after config changes)
- Global `requireMention: true` on WhatsApp and Telegram groups
- Deploy keys for both workspace repos (separate, per-repo access)

### Changed
- Default model: `openai-codex/gpt-5.4` (was `anthropic/claude-opus-4-6`)
- Fallback chain removed (single model only)
- AMI tool policy: denies `elevated`, `gateway`, `sessions_spawn`, `whatsapp_login`
- Telegram bot token → SecretRef
- Tavily API key → SecretRef
- Gateway auth token → SecretRef
- Plaintext `.env` file cleaned — no more secrets in it

### Removed
- Anthropic API key from config (we're on OpenAI Codex only)
- Legacy `memory-ami/` paths from AMI workspace (moved to `skills/ami-kb/`)
- Duplicate AMI files from Moses workspace (`ami-support-profile/`, `memory/ami/`, `memory/groups/ami-support/`)

### Security
- Moses can read AMI workspace (read-only, when asked)
- AMI cannot read Moses workspace (sandbox isolation)
- All secrets centralized in GCP Secret Manager
- `.env.secrets` file: chmod 600, owned by `openclaw` user
- Deploy keys restricted to Contents read/write on single repo each
