#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[deploy-home] %s\n' "$1"
}

require_env() {
  local var_name="$1"
  if [ -z "${!var_name:-}" ]; then
    printf '[deploy-home] Variable requise absente: %s\n' "$var_name" >&2
    exit 1
  fi
}

DEBUG_ENABLED=0
debug() {
  if [ "$DEBUG_ENABLED" -eq 1 ]; then
    printf '[deploy-home][debug] %s\n' "$1"
  fi
}

# Variables d'environnement avec valeurs par défaut pour un lancement workflow_dispatch.
: "${SSH_PORT:=22}"
: "${DEPLOY_REF:=main}"
: "${DEPLOY_ENVIRONMENT:=home}"
: "${DEPLOY_DEBUG:=0}"
: "${GITHUB_TOKEN:=}"

require_env "SSH_HOST"
require_env "SSH_USER"
require_env "SSH_PRIVATE_KEY"
require_env "GITHUB_REPOSITORY"
require_env "SSH_PORT"
require_env "DEPLOY_REF"
require_env "DEPLOY_ENVIRONMENT"
require_env "DEPLOY_DEBUG"

case "$DEPLOY_DEBUG" in
  1 | true)
    DEBUG_ENABLED=1
    ;;
  0 | false)
    DEBUG_ENABLED=0
    ;;
  *)
    log "Valeur DEPLOY_DEBUG invalide: '${DEPLOY_DEBUG}' (attendu: 0, 1, true, false)."
    exit 1
    ;;
esac

REPO_SLUG="${GITHUB_REPOSITORY}"
REPO_TOKEN="${GITHUB_TOKEN}"

if [ "$DEPLOY_ENVIRONMENT" != "home" ]; then
  log "Environnement '${DEPLOY_ENVIRONMENT}' non reconnu pour ce script (attendu: home)."
  exit 1
fi

log "Déploiement de ${REPO_SLUG}@${DEPLOY_REF} vers ${SSH_USER}@${SSH_HOST}:${SSH_PORT}."
debug "Mode debug activé."
debug "Contexte: environnement=${DEPLOY_ENVIRONMENT}, ref=${DEPLOY_REF}, hôte=${SSH_HOST}, port=${SSH_PORT}."

ssh_key_file="$(mktemp)"
cleanup() {
  rm -f "$ssh_key_file"
}
trap cleanup EXIT

umask 077
printf '%s\n' "$SSH_PRIVATE_KEY" >"$ssh_key_file"
chmod 600 "$ssh_key_file"

ssh_opts=(
  -i "$ssh_key_file"
  -p "$SSH_PORT"
  -o BatchMode=yes
  -o StrictHostKeyChecking=accept-new
  -o ConnectTimeout=10
)
debug "Options SSH actives: BatchMode=yes, StrictHostKeyChecking=accept-new, ConnectTimeout=10."

ssh "${ssh_opts[@]}" "${SSH_USER}@${SSH_HOST}" \
  bash -se -- "$DEPLOY_REF" "$REPO_SLUG" "$REPO_TOKEN" "$DEBUG_ENABLED" <<'REMOTE_SCRIPT'
set -euo pipefail

log() {
  printf '[remote] %s\n' "$1"
}

DEPLOY_DEBUG_MODE="${4:-0}"
debug() {
  if [ "$DEPLOY_DEBUG_MODE" -eq 1 ]; then
    printf '[remote][debug] %s\n' "$1"
  fi
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    log "Commande requise introuvable sur la machine cible: ${cmd}"
    exit 1
  fi
}

extract_json_bool() {
  local payload="$1"
  local key="$2"

  printf '%s' "$payload" |
    sed -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\\(true\\|false\\).*/\\1/p" |
    head -n 1
}

extract_json_number() {
  local payload="$1"
  local key="$2"

  printf '%s' "$payload" |
    sed -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\\([0-9][0-9]*\\).*/\\1/p" |
    head -n 1
}

extract_json_string() {
  local payload="$1"
  local key="$2"

  printf '%s' "$payload" |
    sed -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" |
    head -n 1
}

extract_global_health_status() {
  local payload="$1"

  printf '%s' "$payload" |
    sed -n 's/.*"status"[[:space:]]*:[[:space:]]*"\([^"]*\)"[[:space:]]*,"valhalla".*/\1/p' |
    head -n 1
}

extract_valhalla_health_status() {
  local payload="$1"

  printf '%s' "$payload" |
    sed -n 's/.*"valhalla"[[:space:]]*:[[:space:]]*{[^}]*"status"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' |
    head -n 1
}

dump_runtime_diagnostics() {
  log "Etat des conteneurs suivis:"
  for container_name in "${CONTAINER_NAMES[@]}"; do
    docker ps -a --filter "name=^/${container_name}$" || true
  done

  log "Etat compose:"
  "${compose_cmd[@]}" -p "$COMPOSE_PROJECT" -f "$COMPOSE_FILE_PATH" ps || true

  for container_name in "${CONTAINER_NAMES[@]}"; do
    log "Derniers logs du conteneur ${container_name}:"
    docker logs --tail 120 "$container_name" || true
  done
}

DEPLOY_REF="$1"
REPO_SLUG="$2"
REPO_TOKEN="${3:-}"
REPO_URL="https://github.com/${REPO_SLUG}.git"

# Paramètres centralisés du déploiement home.
APP_DIR="/home/arnaud/apps/bikevoyager"
COMPOSE_FILE="deploy/home.compose.yml"
FRONT_URL_HEALTHCHECK="http://127.0.0.1:5081"
API_HEALTH_URL="http://127.0.0.1:5080/api/v1/health"
VALHALLA_WAIT_SECONDS=1200
VALHALLA_POLL_SECONDS=10
CONTAINER_NAMES=("bikevoyager-front" "bikevoyager-api" "bikevoyager-valhalla" "bikevoyager-valhalla-bootstrap")

APP_PARENT_DIR="$(dirname "$APP_DIR")"
COMPOSE_FILE_PATH="${APP_DIR}/${COMPOSE_FILE}"
COMPOSE_PROJECT="bikevoyager-home"
HOME_ENV_RELATIVE_PATH="deploy/home.env"
HOME_ENV_EXAMPLE_RELATIVE_PATH="deploy/home.env.example"
HOME_ENV_PATH="${APP_DIR}/${HOME_ENV_RELATIVE_PATH}"
HOME_ENV_EXAMPLE_PATH="${APP_DIR}/${HOME_ENV_EXAMPLE_RELATIVE_PATH}"

git_with_auth() {
  if [ -n "$REPO_TOKEN" ]; then
    local auth_header
    auth_header="$(printf 'x-access-token:%s' "$REPO_TOKEN" | base64 | tr -d '\n')"
    git -c "http.extraheader=AUTHORIZATION: basic ${auth_header}" "$@"
    return
  fi

  git "$@"
}

require_cmd git
require_cmd docker
require_cmd curl

compose_cmd=()
if docker compose version >/dev/null 2>&1; then
  compose_cmd=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  compose_cmd=(docker-compose)
else
  log "docker compose est introuvable (ni plugin Docker, ni binaire docker-compose)."
  exit 1
fi

log "Préparation du dossier ${APP_DIR}"
debug "Config remote: compose=${COMPOSE_FILE}, api_health=${API_HEALTH_URL}, conteneurs=${CONTAINER_NAMES[*]}."
mkdir -p "$APP_PARENT_DIR"

if [ ! -d "$APP_DIR/.git" ]; then
  log "Repository absent, clonage initial."
  if ! git_with_auth clone "$REPO_URL" "$APP_DIR"; then
    log "Clonage impossible. Si le repo est privé, vérifier que GITHUB_TOKEN est transmis."
    exit 1
  fi
fi

cd "$APP_DIR"
git remote set-url origin "$REPO_URL"

log "Mise à jour Git et résolution de la référence ${DEPLOY_REF}"
git_with_auth fetch --prune --tags origin

# Même stratégie que Tetrigular: SHA -> tag -> branche.
if [[ "$DEPLOY_REF" =~ ^[0-9a-f]{7,40}$ ]]; then
  log "Référence détectée comme SHA, checkout détaché."
  git checkout --detach "$DEPLOY_REF"
elif git rev-parse -q --verify "refs/tags/${DEPLOY_REF}" >/dev/null; then
  log "Référence détectée comme tag, checkout détaché."
  git checkout --detach "refs/tags/${DEPLOY_REF}"
else
  log "Référence détectée comme branche, alignement sur origin/${DEPLOY_REF}."
  git checkout -B "$DEPLOY_REF" "origin/${DEPLOY_REF}"
  git reset --hard "origin/${DEPLOY_REF}"
fi

deployed_commit="$(git rev-parse --short HEAD)"
deployed_date_utc="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
deployed_host="$(hostname -f 2>/dev/null || hostname 2>/dev/null || echo "unknown-host")"
log "Commit déployé: ${deployed_commit}"
log "Contexte déploiement: host=${deployed_host}, date_utc=${deployed_date_utc}, ref=${DEPLOY_REF}"
debug "Commit complet: $(git rev-parse HEAD)"

if [ ! -f "$COMPOSE_FILE_PATH" ]; then
  log "Fichier compose introuvable: ${COMPOSE_FILE_PATH}"
  exit 1
fi

if [ ! -f "$HOME_ENV_EXAMPLE_PATH" ]; then
  log "Fichier exemple introuvable: ${HOME_ENV_EXAMPLE_PATH}"
  exit 1
fi

if [ ! -f "$HOME_ENV_PATH" ]; then
  cp "$HOME_ENV_EXAMPLE_PATH" "$HOME_ENV_PATH"
  log "Fichier deploy/home.env créé (à personnaliser avec les identifiants Brevo)"
fi

chmod 600 "$HOME_ENV_PATH"

log "Build et démarrage de la stack home via docker compose"
"${compose_cmd[@]}" -p "$COMPOSE_PROJECT" -f "$COMPOSE_FILE_PATH" up -d --build --remove-orphans

log "Attente de santé API/Valhalla via ${API_HEALTH_URL} (timeout: ${VALHALLA_WAIT_SECONDS}s)"
valhalla_attempts=$((VALHALLA_WAIT_SECONDS / VALHALLA_POLL_SECONDS))
if [ "$valhalla_attempts" -lt 1 ]; then
  valhalla_attempts=1
fi

valhalla_ready="false"
api_health_payload=""
health_http_status=""
health_payload_file="$(mktemp)"
cleanup_health_payload() {
  rm -f "$health_payload_file"
}
trap cleanup_health_payload EXIT

for ((attempt=1; attempt<=valhalla_attempts; attempt+=1)); do
  health_http_status="$(curl -sS -o "$health_payload_file" -w '%{http_code}' --connect-timeout 3 --max-time 8 "$API_HEALTH_URL" || true)"

  if [ "$health_http_status" = "200" ]; then
    api_health_payload="$(cat "$health_payload_file")"
    compact_payload="$(printf '%s' "$api_health_payload" | tr -d '\n')"
    global_health_status="$(extract_global_health_status "$compact_payload")"
    valhalla_health_status="$(extract_valhalla_health_status "$compact_payload")"

    if [ "$global_health_status" = "OK" ] && [ "$valhalla_health_status" = "UP" ]; then
      valhalla_ready="true"
      log "Health API OK et Valhalla UP (tentative ${attempt}/${valhalla_attempts})."
      break
    fi

    build_state="$(extract_json_string "$compact_payload" "state")"
    build_phase="$(extract_json_string "$compact_payload" "phase")"
    build_progress="$(extract_json_number "$compact_payload" "progressPct")"
    build_message="$(extract_json_string "$compact_payload" "message")"
    reason_value="$(extract_json_string "$compact_payload" "reason")"

    if [ "$valhalla_health_status" = "BUILDING" ]; then
      log "Valhalla BUILDING (tentative ${attempt}/${valhalla_attempts}, phase=${build_phase:-initialisation}, progression=${build_progress:-0}%, message=${build_message:-n/a})."
    elif [ "$valhalla_health_status" = "DOWN" ]; then
      log "Valhalla DOWN (tentative ${attempt}/${valhalla_attempts}, reason=${reason_value:-n/a}, message=${build_message:-n/a})."
    elif [ "$build_state" = "failed" ]; then
      log "Valhalla en echec (tentative ${attempt}/${valhalla_attempts}, message=${build_message:-n/a}, reason=${reason_value:-n/a})."
    else
      log "Health API DEGRADE (tentative ${attempt}/${valhalla_attempts}, global=${global_health_status:-n/a}, valhalla=${valhalla_health_status:-unknown})."
    fi
  else
    log "Health API indisponible (tentative ${attempt}/${valhalla_attempts}, code=${health_http_status:-n/a})."
  fi

  sleep "$VALHALLA_POLL_SECONDS"
done

if [ "$valhalla_ready" != "true" ]; then
  log "Health API / Valhalla non prêts après ${VALHALLA_WAIT_SECONDS}s."
  if [ -n "$api_health_payload" ]; then
    log "Dernier payload health: $api_health_payload"
  fi
  dump_runtime_diagnostics
  exit 1
fi

log "Vérification finale frontend via ${FRONT_URL_HEALTHCHECK}"
front_http_status="$(curl -sS -o /dev/null -I -w '%{http_code}' --connect-timeout 2 --max-time 5 "$FRONT_URL_HEALTHCHECK" || true)"
if [ "$front_http_status" != "200" ]; then
  log "Frontend indisponible après readiness API (code=${front_http_status:-n/a})."
  dump_runtime_diagnostics
  exit 1
fi

log "Déploiement terminé avec succès (API health + frontend OK)"
REMOTE_SCRIPT

log "Script terminé."
