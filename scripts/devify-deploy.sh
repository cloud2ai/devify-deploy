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

compose() {
    export DEVIFY_DEPLOY_ROOT="${DEPLOY_ROOT}"
    export DEVIFY_RUNTIME_ROOT="${DEPLOY_ROOT}"
    export DEVIFY_ENV_FILE="${ENV_FILE}"
    export DEVIFY_NGINX_CERTS_DIR="${DEPLOY_ROOT}/data/certs/nginx"

    docker compose \
        --env-file "${ENV_FILE}" \
        --project-directory "${CORE_DIR}" \
        -p "${COMPOSE_PROJECT_NAME}" \
        -f "${CORE_DIR}/docker-compose.yml" \
        -f "${DEPLOY_ROOT}/docker-compose.yml" \
        "$@"
}

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
        "${DEPLOY_ROOT}/data/redis"
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

install_stack() {
    check_requirements
    ensure_env
    sync_devify
    prepare_directories
    ensure_nginx_certs
    compose pull
    compose up -d
    compose ps
}

upgrade_stack() {
    check_requirements
    ensure_env
    # Pull latest devify-deploy scripts and overlay configs (nginx, etc.)
    git -C "${DEPLOY_ROOT}" pull --ff-only origin main || true
    sync_devify
    prepare_directories
    ensure_nginx_certs
    compose pull
    compose up -d --remove-orphans
    compose ps
}

show_usage() {
    cat <<'USAGE'
Usage: ./scripts/devify-deploy.sh <command> [args]

Commands:
  install      Install or recreate the full stack with devify-home
  upgrade      Update devify deployment files and restart changed services
  pull         Pull images for the deployment stack
  start        Start the deployment stack
  stop         Stop the deployment stack
  restart      Restart the deployment stack
  status       Show service status
  logs         Show logs; extra args are passed to docker compose logs
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
            check_requirements
            ensure_env
            ensure_stack_files
            compose ps "$@"
            ;;
        logs)
            check_requirements
            ensure_env
            ensure_stack_files
            compose logs "$@"
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
