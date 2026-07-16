#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CORE_DIR="${DEPLOY_ROOT}/.devify"
ENV_FILE="${DEPLOY_ROOT}/.env"
ENV_SAMPLE="${DEPLOY_ROOT}/env.sample"

DEVIFY_REPO="${DEVIFY_REPO:-https://github.com/cloud2ai/devify.git}"
DEVIFY_REF="${DEVIFY_REF:-main}"
COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-devify}"

log() { echo -e "\033[1;36m[devify-deploy]\033[0m $*"; }
die() { echo -e "\033[1;31m[devify-deploy] ERROR:\033[0m $*" >&2; exit 1; }

# Map the git ref to the registry image tag. CI publishes semver tags without
# the leading "v" (docker/metadata-action {{version}}), so v1.1.26 -> 1.1.26;
# non-version refs (e.g. main) fall back to the "latest" image.
image_tag_for_ref() {
    if [[ "${DEVIFY_REF}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "${DEVIFY_REF#v}"
    else
        echo "latest"
    fi
}

# Compose wrapper. Layers three files (base app stack + deploy overlay +
# blue/green overlay); the blue/green file is LAST so its !override/!reset on
# nginx and the colored services win. See docker-compose.bluegreen.yml.
compose() {
    export DEVIFY_DEPLOY_ROOT="${DEPLOY_ROOT}"
    export DEVIFY_RUNTIME_ROOT="${DEPLOY_ROOT}"
    export DEVIFY_ENV_FILE="${ENV_FILE}"
    export DEVIFY_NGINX_CERTS_DIR="${DEPLOY_ROOT}/data/certs/nginx"
    export DEVIFY_IMAGE_TAG="$(image_tag_for_ref)"

    docker compose \
        --env-file "${ENV_FILE}" \
        --project-directory "${CORE_DIR}" \
        -p "${COMPOSE_PROJECT_NAME}" \
        -f "${CORE_DIR}/docker-compose.yml" \
        -f "${DEPLOY_ROOT}/docker-compose.yml" \
        -f "${CORE_DIR}/docker-compose.bluegreen.yml" \
        "$@"
}

# Blue/green helpers (current_color/other_color/wait_for_healthy/switch_traffic)
DEPLOY_PATH="${DEPLOY_ROOT}"
# shellcheck source=./lib/deploy-common.sh
source "${SCRIPT_DIR}/lib/deploy-common.sh"

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Missing required command: $1" >&2
        exit 1
    fi
}

check_requirements() {
    require_command git
    require_command docker
    docker compose version >/dev/null
}

ensure_env() {
    if [ ! -f "${ENV_FILE}" ]; then
        cp "${ENV_SAMPLE}" "${ENV_FILE}"
        echo "Created ${ENV_FILE} from env.sample."
        echo "Edit ${ENV_FILE} before production use, then rerun this command."
    fi
}

sync_devify() {
    if [ ! -d "${CORE_DIR}/.git" ]; then
        rm -rf "${CORE_DIR}"
        git clone "${DEVIFY_REPO}" "${CORE_DIR}"
    else
        git -C "${CORE_DIR}" remote set-url origin "${DEVIFY_REPO}"
    fi

    git -C "${CORE_DIR}" fetch --tags origin
    if git -C "${CORE_DIR}" rev-parse --verify --quiet "origin/${DEVIFY_REF}" >/dev/null; then
        git -C "${CORE_DIR}" checkout --force -B "${DEVIFY_REF}" "origin/${DEVIFY_REF}"
    else
        git -C "${CORE_DIR}" checkout --force "${DEVIFY_REF}"
    fi
}

prepare_directories() {
    mkdir -p \
        "${DEPLOY_ROOT}/cache" \
        "${DEPLOY_ROOT}/data/certs/haraka" \
        "${DEPLOY_ROOT}/data/certs/nginx" \
        "${DEPLOY_ROOT}/data/django/staticfiles" \
        "${DEPLOY_ROOT}/data/email_attachments" \
        "${DEPLOY_ROOT}/data/haraka/debug" \
        "${DEPLOY_ROOT}/data/haraka/email_attachments" \
        "${DEPLOY_ROOT}/data/haraka/emails" \
        "${DEPLOY_ROOT}/data/haraka/logs" \
        "${DEPLOY_ROOT}/data/logs/api" \
        "${DEPLOY_ROOT}/data/logs/mysql" \
        "${DEPLOY_ROOT}/data/logs/nginx" \
        "${DEPLOY_ROOT}/data/logs/scheduler" \
        "${DEPLOY_ROOT}/data/logs/worker" \
        "${DEPLOY_ROOT}/data/mysql/data" \
        "${DEPLOY_ROOT}/data/nginx/conf.d" \
        "${DEPLOY_ROOT}/data/redis"
}

# Populate the nginx conf.d directory that the blue/green nginx service mounts.
# The directory (not single files) is mounted so switch_traffic's atomic
# rewrite of active-upstream.conf is visible inside the container.
sync_nginx_confd() {
    local confd="${DEPLOY_ROOT}/data/nginx/conf.d"
    mkdir -p "${confd}"
    # Blue/green app config, versioned with the synced devify repo.
    cp "${CORE_DIR}/docker/nginx/bluegreen/default.conf" \
        "${confd}/default.conf"
    # aimychats.com (devify-home) config from this deploy repo.
    cp "${DEPLOY_ROOT}/docker/nginx/aimychats.com.conf" \
        "${confd}/aimychats.com.conf"
    # Runtime switch file: seed from template only if absent so an existing
    # active color is preserved across upgrades.
    if [ ! -f "${confd}/active-upstream.conf" ]; then
        cp "${CORE_DIR}/docker/nginx/bluegreen/active-upstream.conf.default" \
            "${confd}/active-upstream.conf"
    fi
}

ensure_nginx_certs() {
    if [ ! -f "${DEPLOY_ROOT}/data/certs/nginx/aimychats.com.crt" ] ||
       [ ! -f "${DEPLOY_ROOT}/data/certs/nginx/app.aimychats.com.crt" ]; then
        if [ -f "${DEPLOY_ROOT}/docker/nginx/certs/aimychats.com.crt" ] &&
           [ -f "${DEPLOY_ROOT}/docker/nginx/certs/app.aimychats.com.crt" ]; then
            cp "${DEPLOY_ROOT}"/docker/nginx/certs/* "${DEPLOY_ROOT}/data/certs/nginx/"
            echo "Migrated nginx certificates from docker/nginx/certs to data/certs/nginx."
            return
        fi
        "${SCRIPT_DIR}/generate-self-signed-certs.sh"
    fi
}

ensure_stack_files() {
    if [ ! -f "${CORE_DIR}/docker-compose.yml" ]; then
        sync_devify
        prepare_directories
    fi
}

# Blue/green deploy: bring up the idle color, health-gate it, flip nginx, then
# retire the old color. Shared by install and upgrade. Only devify-api/devify-ui
# are colored; mysql/redis/haraka/devify-home/worker/scheduler stay single.
bluegreen_deploy() {
    prepare_directories
    ensure_nginx_certs
    sync_nginx_confd
    compose pull

    # Foundational stateful services first (idempotent no-op if already up).
    compose up -d mysql redis haraka

    local current next first_install
    current="$(current_color)"
    if [ "$(docker inspect -f '{{.State.Running}}' \
            "devify-api-${current}" 2>/dev/null)" != "true" ]; then
        # No color is live yet (first blue/green deploy) — deploy the current
        # color directly; there is nothing to switch from or retire.
        next="${current}"
        first_install=1
        log "devify-api-${current} not running — first blue/green deploy to ${next}"
    else
        next="$(other_color "${current}")"
        first_install=0
        log "Active color: ${current}; deploying idle color: ${next}"
    fi

    # Run migrations against the deploy color while it serves no traffic. Single
    # shared mysql, so migrations must stay backward-compatible for the overlap.
    log "Running migrations against devify-api-${next}..."
    compose run --rm --no-deps "devify-api-${next}" \
        python manage.py migrate --noinput

    log "Starting devify-api-${next} / devify-ui-${next}..."
    compose --profile "${next}" up -d \
        "devify-api-${next}" "devify-ui-${next}"

    log "Waiting for devify-api-${next} to report healthy..."
    if ! wait_for_healthy "devify-api-${next}"; then
        compose --profile "${next}" stop \
            "devify-api-${next}" "devify-ui-${next}"
        die "devify-api-${next} never became healthy; deploy aborted, ${current} stays live"
    fi
    log "devify-api-${next} is healthy"

    # devify-home + nginx must be up before switching traffic.
    compose up -d devify-home
    compose up -d nginx

    if [ "${first_install}" = "1" ]; then
        # active-upstream.conf template already points at blue (== next here).
        echo "${next}" > "${DEPLOY_ROOT}/.active_color"
        log "First deploy: nginx serving devify-api-${next} directly"
    else
        switch_traffic "${current}" "${next}"
        echo "${next}" > "${DEPLOY_ROOT}/.active_color"
        log "Observing ${POST_SWITCH_OBSERVE_SECONDS}s before retiring ${current}..."
        sleep "${POST_SWITCH_OBSERVE_SECONDS}"
        log "Retiring devify-api-${current} / devify-ui-${current}"
        compose --profile "${current}" stop \
            "devify-api-${current}" "devify-ui-${current}" || true
        compose --profile "${current}" rm -f \
            "devify-api-${current}" "devify-ui-${current}" || true
    fi

    # One-time cleanup of legacy pre-blue/green single containers, if present.
    docker rm -f devify-api devify-ui >/dev/null 2>&1 || true

    # Non-colored app services: ordinary rolling restart. Celery graceful-drain
    # settings mean in-flight tasks finish before the old process exits.
    compose up -d devify-worker devify-scheduler
    compose ps
}

install_stack() {
    check_requirements
    ensure_env
    sync_devify
    bluegreen_deploy
}

upgrade_stack() {
    check_requirements
    ensure_env
    # Pull latest devify-deploy scripts and overlay configs (nginx, etc.)
    git -C "${DEPLOY_ROOT}" pull --ff-only origin main || true
    sync_devify
    bluegreen_deploy
}

rollback_stack() {
    check_requirements
    ensure_env
    ensure_stack_files
    sync_nginx_confd
    local active target
    active="$(current_color)"
    target="$(other_color "${active}")"
    log "Active color is ${active}; rolling back to ${target}"
    log "(no pull/build/migrate — only works if ${target}'s image is still local)"

    if ! compose --profile "${target}" up -d \
        "devify-api-${target}" "devify-ui-${target}"; then
        die "Could not start ${target}. Redeploy that version instead: DEVIFY_REF=<tag> $0 upgrade"
    fi
    log "Waiting for devify-api-${target} to report healthy..."
    if ! wait_for_healthy "devify-api-${target}"; then
        compose --profile "${target}" stop \
            "devify-api-${target}" "devify-ui-${target}"
        die "devify-api-${target} never became healthy; rollback aborted, ${active} stays live"
    fi
    switch_traffic "${active}" "${target}"
    echo "${target}" > "${DEPLOY_ROOT}/.active_color"
    log "Rolled back: active color is now ${target}. ${active} left running for inspection."
}

status_stack() {
    check_requirements
    ensure_env
    ensure_stack_files
    local color; color="$(current_color)"
    log "Active color: ${color}"
    compose ps "devify-api-${color}" "devify-ui-${color}" \
        devify-worker devify-scheduler devify-home nginx 2>/dev/null || true
    if docker exec "devify-api-${color}" \
        curl -fs http://127.0.0.1:8000/health >/dev/null 2>&1; then
        log "devify-api-${color} (active): healthy"
    else
        log "devify-api-${color} (active): NOT healthy"
    fi
}

show_usage() {
    cat <<'USAGE'
Usage: ./scripts/devify-deploy.sh <command> [args]

Commands:
  install      Install the full stack (blue/green) with devify-home
  upgrade      Blue/green deploy: health-gate the idle color, switch, retire old
  rollback     Flip traffic back to the other color (no pull/build/migrate)
  status       Show the active color, its health, and running services
  pull         Pull images for the deployment stack
  start        Start the deployment stack
  stop         Stop the deployment stack
  restart      Restart the deployment stack
  status       Show service status
  logs         Show logs; extra args are passed to docker compose logs
  manage       Run a Django management command in the devify-api container
               e.g. ./scripts/devify-deploy.sh manage migrate
               e.g. ./scripts/devify-deploy.sh manage verify_webhook
  config       Sync devify files and validate the composed deployment config

Environment:
  DEVIFY_REPO             Git repository to sync; default https://github.com/cloud2ai/devify.git
  DEVIFY_REF              Branch, tag, or commit to deploy; default main
  COMPOSE_PROJECT_NAME    Compose project name; default devify
USAGE
}

main() {
    command="${1:-}"
    if [ -n "${command}" ]; then
        shift
    fi

    case "${command}" in
        install)
            install_stack
            ;;
        upgrade)
            upgrade_stack
            ;;
        pull)
            check_requirements
            ensure_env
            sync_devify
            prepare_directories
            compose pull "$@"
            ;;
        start)
            check_requirements
            ensure_env
            ensure_stack_files
            compose up -d "$@"
            ;;
        stop)
            check_requirements
            ensure_env
            ensure_stack_files
            compose stop "$@"
            ;;
        restart)
            check_requirements
            ensure_env
            ensure_stack_files
            compose restart "$@"
            ;;
        status)
            status_stack
            ;;
        rollback)
            rollback_stack
            ;;
        logs)
            check_requirements
            ensure_env
            ensure_stack_files
            compose logs "$@"
            ;;
        manage)
            check_requirements
            ensure_env
            ensure_stack_files
            compose exec devify-api python manage.py "$@"
            ;;
        config)
            check_requirements
            ensure_env
            sync_devify
            prepare_directories
            compose config >/dev/null
            echo "Compose configuration is valid."
            ;;
        *)
            show_usage
            exit 1
            ;;
    esac
}

main "$@"
