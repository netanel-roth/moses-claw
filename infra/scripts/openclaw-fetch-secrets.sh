

#!/usr/bin/env bash
# Fetches secrets from GCP Secret Manager and writes them to .env
# Called by systemd service before docker-compose starts

set -e

PROJECT="moses-claw"
ENV_FILE="/home/openclaw/openclaw/.env.secrets"

TOKEN=$(curl -s -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token" | python3 -c "import sys,json;print(json.load(sys.stdin)['access_token'])")

fetch() {
  local NAME=$1
  curl -s -H "Authorization: Bearer $TOKEN" \
    "https://secretmanager.googleapis.com/v1/projects/$PROJECT/secrets/$NAME/versions/latest:access" \
    | python3 -c "import sys,json,base64;d=json.load(sys.stdin);print(base64.b64decode(d['payload']['data']).decode(),end='')"
}

mkdir -p "$(dirname "$ENV_FILE")"
{
  echo "GROQ_API_KEY=$(fetch GROQ_API_KEY)"
  echo "GEMINI_API_KEY=$(fetch GEMINI_API_KEY)"
  echo "GOG_KEYRING_PASSWORD=$(fetch GOG_KEYRING_PASSWORD)"
  echo "OPENCLAW_GATEWAY_TOKEN=$(fetch OPENCLAW_GATEWAY_TOKEN)"
} > "$ENV_FILE"

chmod 600 "$ENV_FILE"
chown openclaw:openclaw "$ENV_FILE"
echo "Secrets written to $ENV_FILE"
