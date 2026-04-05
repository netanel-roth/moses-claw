# Known Issues & Workarounds

## Voice notes in groups aren't auto-transcribed

**Symptom:** User sends a WhatsApp voice note in a group, then @mentions Moses asking to transcribe. Moses says he can't access the audio file.

**Cause:** `requireMention: true` is set globally on WhatsApp groups. The voice note message itself has no mention, so it's filtered out before reaching Moses. Only the @mention text message arrives — with no audio attached.

**Workaround:**
- Send voice note with @Moses in the caption (in same message)
- Or reply to Moses's message with the voice note
- Or use DMs for voice transcription (no mention required)

**Tradeoff:** Security (mention required) vs convenience (auto-transcription). We chose security.

---

## Groq/Gemini/Keyring secrets can't use SecretRef

**Symptom:** These secrets must live in `.env.secrets` as env vars, not as `{source: exec, provider: gcp, id: ...}` SecretRefs.

**Cause:** OpenClaw's `SecretRef` system only supports specific fields (documented in `docs/reference/secretref-credential-surface.md`). The groq plugin, google/gemini embeddings, and keyring password don't have SecretRef-aware code paths.

**Workaround:** Fetch from GCP Secret Manager at boot via `openclaw-fetch-secrets.sh` → write to `.env.secrets` (chmod 600, owned by openclaw) → docker-compose loads as container env vars.

**Gap:** An agent with `exec` tool can theoretically dump env vars via `printenv`. Moses (unsandboxed) is vulnerable. AMI (sandboxed) is not — its sandbox container has its own minimal env.

---

## Sandbox needs Docker-in-Docker

**Symptom:** AMI agent's sandbox requires Docker, but the gateway runs inside Docker itself.

**Fix:** Mount `/var/run/docker.sock` into the gateway container, install Docker CLI inside the gateway container (added to Dockerfile). The gateway uses the host's Docker daemon to create sandbox containers as siblings (not children) of itself.

**Tradeoff:** Anyone with gateway container access has Docker daemon access → full host control. We accept this because the gateway container is our trust boundary.

---

## Sandbox workspace path translation

**Symptom:** The AMI agent's workspace wasn't visible inside its sandbox container.

**Cause:** Docker-in-Docker path translation. Gateway knows the workspace as `/home/node/.openclaw/workspace-ami-support` (container path), but when it asks Docker to bind-mount into the sandbox, Docker resolves the path on the **host**, not inside the gateway container.

**Fix:** The AMI agent's `workspace` config is set to the **host path** (`/home/openclaw/.openclaw/workspace-ami-support`). The gateway container mounts that host path explicitly via docker-compose so both paths work for it internally.

---

## GROQ plugin needs env var template in config

**Symptom:** After migrating secrets, Groq transcription stopped working — "no API key for Groq".

**Cause:** OpenClaw reads `env.GROQ_API_KEY` from the config file (`openclaw.json`), not from `process.env.GROQ_API_KEY` directly. When we removed the entire `env` block from config, the plugin lost its reference.

**Fix:** Put `env.GROQ_API_KEY = "${GROQ_API_KEY}"` in config — OpenClaw substitutes from process env at load time. The key still only exists in Secret Manager → container env, never on disk.

---

## Gateway auth token mismatch between CLI and gateway

**Symptom:** After moving `OPENCLAW_GATEWAY_TOKEN` to env var, the CLI inside the container couldn't authenticate to the gateway — "token mismatch".

**Fix:** Added `gateway.auth.token` as a SecretRef in `openclaw.json`. Both the gateway itself and the CLI now read from the SecretRef registry at startup. No env dependency.

---

## Docker-compose warnings about undefined variables

**Symptom:** Warnings like `The "OPENCLAW_GATEWAY_TOKEN" variable is not set. Defaulting to a blank string.`

**Cause:** Docker-compose substitutes `${OPENCLAW_GATEWAY_TOKEN}` in the `environment:` section from the host shell's env, not from `env_file:` entries. The env_file is only injected at container runtime.

**Fix:** Removed the explicit `- OPENCLAW_GATEWAY_TOKEN=${OPENCLAW_GATEWAY_TOKEN}` lines from compose. The env_file loads the values directly without needing substitution.

---

## gcloud CLI caches stale OAuth tokens

**Symptom:** After updating VM service account scopes, `gcloud secrets access` still fails with old scope errors.

**Cause:** gcloud caches the metadata-server token and doesn't always refresh on scope changes.

**Fix:** Our `openclaw-secret-resolver` uses `curl` directly to the metadata server + Secret Manager REST API, bypassing gcloud's token cache.
