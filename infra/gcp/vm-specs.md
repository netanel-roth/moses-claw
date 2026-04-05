# VM Specifications

## Current deployment

| Field | Value |
|---|---|
| **VM Name** | `openclaw-gateway` |
| **Project** | `moses-claw` |
| **Zone** | `europe-west1-b` (Belgium) |
| **Machine Type** | `e2-medium` (2 vCPU, 4GB RAM, ~$25/mo) |
| **Boot Disk** | 50GB standard persistent disk |
| **OS** | Debian 12 |
| **Service Account** | `openclaw-vm@moses-claw.iam.gserviceaccount.com` |
| **Network** | Default VPC, loopback only for gateway |
| **Tags** | `openclaw`, `openclaw-iap-ssh` |

## Billing

- Linked billing account: `016DA0-A18B0D-9AF42B`
- Estimated monthly cost: ~$25 (VM) + $2 (disk) = ~$27/mo
- Budget alert: not configured (requires Billing Admin role)

## Expected resource usage

- VM: ~$25/mo
- Disk (50GB): ~$2/mo
- Network egress: minimal (mostly inbound WhatsApp/Telegram)
- Secret Manager: free tier
- Docker images: stored locally
