# Multi-Agent Setup

How Moses (main) and AMI (support) coexist on one gateway.

## Architecture

```
One OpenClaw Gateway Process
    │
    ├── Main agent: Moses
    │   ├── Workspace: /home/openclaw/.openclaw/workspace
    │   ├── Agent dir: /home/openclaw/.openclaw/agents/main/agent
    │   ├── Sessions: /home/openclaw/.openclaw/agents/main/sessions
    │   ├── Sandbox: NO (runs on host, full access)
    │   └── Routing: default (everything without explicit binding)
    │
    └── Ami-support agent: AMI
        ├── Workspace: /home/openclaw/.openclaw/workspace-ami-support
        ├── Agent dir: /home/openclaw/.openclaw/agents/ami-support/agent
        ├── Sessions: /home/openclaw/.openclaw/agents/ami-support/sessions
        ├── Sandbox: YES (Docker-in-Docker, isolated container)
        └── Routing: explicit bindings for specific WhatsApp group IDs
```

## Routing by chat_id (deterministic, not prompt-based)

Configured in `openclaw.json` under `bindings`:

```json5
{
  bindings: [
    {
      agentId: "ami-support",
      match: {
        channel: "whatsapp",
        peer: { kind: "group", id: "120363425053244769@g.us" }  // admin group
      }
    },
    {
      agentId: "ami-support",
      match: {
        channel: "whatsapp",
        peer: { kind: "group", id: "120363405405269909@g.us" }  // support group
      }
    }
  ]
}
```

Messages from these group IDs → routed to AMI agent.
All other messages → routed to Moses (default agent).

## Isolation layers

| Layer | How it isolates |
|---|---|
| **Routing** | Binding filters by `chat_id` at the code level — AMI literally never sees messages from Moses's groups |
| **Workspace** | Separate directories — file tools resolve relative paths inside the agent's workspace |
| **Sessions** | Separate session stores — no shared chat history |
| **Auth** | Separate `auth-profiles.json` per agent — no credential sharing |
| **Sandbox** | AMI runs in isolated Docker container with only its workspace mounted |
| **Tool policy** | Denied: `elevated`, `gateway`, `sessions_spawn`, `whatsapp_login` |

## Moses can read AMI, not vice versa

- **Moses** runs unsandboxed — can read `/home/node/.openclaw/workspace-ami-support/` when needed
- **AMI** is sandboxed — can only see `/workspace` inside its container
- AMI's sandbox doesn't mount Moses's workspace → physical impossibility to read it
- Documented in Moses's `AGENTS.md` under "AMI Support Agent — Access"

## Why multi-agent instead of multi-profile

Multi-profile would mean two separate OpenClaw processes with their own gateways. More RAM, more complexity, harder to share WhatsApp account. Multi-agent with bindings gives the same isolation guarantees with less overhead.

See OpenClaw docs: `docs/concepts/multi-agent.md`
