#!/usr/bin/env bash
# =============================================================================
# aws-scanner-tool  —  Linux / Mac
# =============================================================================
# Interactive tool to scan multiple AWS accounts in parallel Docker containers.
# Each account gets its own container. Results saved to ./aws-scan-results/
#
# Requirements: Docker must be installed and running.
# Usage:  bash tool.sh
# =============================================================================

set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
IMAGE_NAME="aws-scanner"
RESULTS_DIR="$(pwd)/aws-scan-results"
CONTAINER_PREFIX="aws-scan"
SCAN_SESSION_ID="$(date +%Y%m%d_%H%M%S)"

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

# ── Active containers tracking ────────────────────────────────────────────────
declare -a ACTIVE_CONTAINERS=()

# ── Cleanup on Ctrl+C ─────────────────────────────────────────────────────────
cleanup() {
    echo ""
    echo -e "${YELLOW}  *** Interrupted — stopping all running containers... ***${RESET}"
    for cname in "${ACTIVE_CONTAINERS[@]:-}"; do
        if docker ps -q --filter "name=${cname}" | grep -q .; then
            echo -e "  Stopping container: ${cname}"
            docker stop "${cname}" >/dev/null 2>&1 || true
            docker rm   "${cname}" >/dev/null 2>&1 || true
            echo -e "  ${GREEN}Deleted: ${cname}${RESET}"
        fi
    done
    echo ""
    echo -e "  ${CYAN}Partial results (if any) are in: ${RESULTS_DIR}/${RESET}"
    ask_again_or_exit
}
trap cleanup INT TERM

# ── Helpers ───────────────────────────────────────────────────────────────────
banner() {
    clear
    echo -e "${BOLD}${BLUE}"
    echo "  ╔══════════════════════════════════════════════════════╗"
    echo "  ║          AWS Multi-Account Resource Scanner          ║"
    echo "  ║   Scans ALL resources across ALL regions per account ║"
    echo "  ╚══════════════════════════════════════════════════════╝"
    echo -e "${RESET}"
    echo -e "  ${CYAN}Results folder: ${RESULTS_DIR}${RESET}"
    echo ""
}

confirm_docker() {
    if ! command -v docker &>/dev/null; then
        echo -e "${RED}  ERROR: Docker is not installed or not in PATH.${RESET}"
        echo "  Install Docker: https://docs.docker.com/get-docker/"
        exit 1
    fi
    if ! docker info &>/dev/null; then
        echo -e "${RED}  ERROR: Docker daemon is not running.${RESET}"
        echo "  Start Docker Desktop or run:  sudo systemctl start docker"
        exit 1
    fi
    echo -e "  ${GREEN}✓ Docker is running${RESET}"
}

build_image() {
    echo ""
    echo -e "  ${BOLD}Building scanner Docker image...${RESET}"
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    docker build -t "${IMAGE_NAME}" "${SCRIPT_DIR}" -f "${SCRIPT_DIR}/Dockerfile" \
        --quiet && echo -e "  ${GREEN}✓ Image built: ${IMAGE_NAME}${RESET}"
}

get_credentials() {
    local scan_num="$1"
    echo ""
    echo -e "  ${BOLD}${CYAN}── Credentials for Scan ${scan_num} ──────────────────────────${RESET}"
    echo -e "  ${YELLOW}(Enter AWS credentials for account ${scan_num})${RESET}"
    echo ""

    read -rp "    AWS Access Key ID      : " AWS_ACCESS_KEY_ID
    while [[ -z "${AWS_ACCESS_KEY_ID}" ]]; do
        echo -e "    ${RED}Cannot be empty.${RESET}"
        read -rp "    AWS Access Key ID      : " AWS_ACCESS_KEY_ID
    done

    read -rsp "    AWS Secret Access Key  : " AWS_SECRET_ACCESS_KEY
    echo ""
    while [[ -z "${AWS_SECRET_ACCESS_KEY}" ]]; do
        echo -e "    ${RED}Cannot be empty.${RESET}"
        read -rsp "    AWS Secret Access Key  : " AWS_SECRET_ACCESS_KEY
        echo ""
    done

    read -rsp "    AWS Session Token      : " AWS_SESSION_TOKEN
    echo ""
    echo -e "    ${CYAN}(Press Enter to skip if not using temporary credentials)${RESET}"

    read -rp "    Default Region         : " AWS_DEFAULT_REGION
    AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"

    export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_DEFAULT_REGION
}

run_container() {
    local scan_num="$1"
    local cname="${CONTAINER_PREFIX}-${SCAN_SESSION_ID}-${scan_num}"
    ACTIVE_CONTAINERS+=("${cname}")

    local account_label="scan${scan_num}"
    local out_dir="${RESULTS_DIR}/${account_label}_$(date +%Y%m%d)"
    mkdir -p "${out_dir}"

    echo ""
    echo -e "  ${GREEN}Starting container for Scan ${scan_num}: ${cname}${RESET}"
    echo -e "  Results will appear in: ${out_dir}"

    # Build docker run args
    local docker_args=(
        --name   "${cname}"
        --rm                              # auto-delete when done
        -v       "${out_dir}:/scanner"    # output goes to host
        -e       "AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}"
        -e       "AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}"
        -e       "AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION}"
    )

    if [[ -n "${AWS_SESSION_TOKEN:-}" ]]; then
        docker_args+=(-e "AWS_SESSION_TOKEN=${AWS_SESSION_TOKEN}")
    fi

    docker_args+=("${IMAGE_NAME}")

    # Run in background — logs go to file
    local log_file="${out_dir}/scan.log"
    docker run "${docker_args[@]}" >"${log_file}" 2>&1 &
    local docker_pid=$!

    echo -e "  ${CYAN}Container started (PID ${docker_pid}) — log: ${log_file}${RESET}"
    echo "${cname}:${docker_pid}:${out_dir}" >> "${RESULTS_DIR}/.running_${SCAN_SESSION_ID}"
}

wait_for_all_containers() {
    echo ""
    echo -e "  ${BOLD}${YELLOW}All containers started. Waiting for scans to complete...${RESET}"
    echo -e "  ${CYAN}(Ctrl+C to interrupt — containers will be stopped and partial results saved)${RESET}"
    echo ""

    local all_done=false
    while ! $all_done; do
        all_done=true
        local running_count=0
        for cname in "${ACTIVE_CONTAINERS[@]:-}"; do
            if docker ps -q --filter "name=${cname}" | grep -q .; then
                all_done=false
                running_count=$((running_count + 1))
            fi
        done
        if ! $all_done; then
            printf "\r  ${CYAN}Running containers: ${running_count}  ($(date +%H:%M:%S))${RESET}    "
            sleep 5
        fi
    done

    echo ""
    echo ""
    echo -e "  ${GREEN}${BOLD}All scans completed!${RESET}"
}

show_results_summary() {
    echo ""
    echo -e "  ${BOLD}${GREEN}══ Results Summary ══════════════════════════════════${RESET}"
    local count=0
    while IFS= read -r -d '' f; do
        echo -e "  ${GREEN}✓${RESET} ${f}"
        count=$((count + 1))
    done < <(find "${RESULTS_DIR}" -name "aws_inventory_*.xlsx" -print0 2>/dev/null)

    if [[ $count -eq 0 ]]; then
        echo -e "  ${YELLOW}No Excel files found yet — check scan logs for errors.${RESET}"
    else
        echo ""
        echo -e "  ${CYAN}Total reports: ${count}${RESET}"
    fi
    echo -e "  ${BOLD}Results folder: ${RESULTS_DIR}${RESET}"
    echo ""
}

ask_again_or_exit() {
    echo ""
    echo -e "  ${BOLD}Do you want to run more scans?${RESET}"
    echo -e "  [Y] Yes — scan more accounts"
    echo -e "  [N] No  — exit the tool"
    echo ""
    read -rp "  Your choice [Y/N]: " choice
    choice="${choice^^}"
    if [[ "${choice}" == "Y" ]]; then
        ACTIVE_CONTAINERS=()
        SCAN_SESSION_ID="$(date +%Y%m%d_%H%M%S)"
        run_scans
    else
        echo ""
        echo -e "  ${GREEN}Thank you for using AWS Scanner Tool. Goodbye!${RESET}"
        echo ""
        exit 0
    fi
}

run_scans() {
    echo ""
    echo -e "  ${BOLD}How many AWS accounts do you want to scan?${RESET}"
    echo -e "  ${CYAN}(Each account runs in its own Docker container in parallel)${RESET}"
    echo ""
    read -rp "  Number of scans: " num_scans

    if ! [[ "${num_scans}" =~ ^[0-9]+$ ]] || [[ "${num_scans}" -lt 1 ]]; then
        echo -e "  ${RED}Please enter a valid number (1 or more).${RESET}"
        run_scans
        return
    fi

    echo ""
    echo -e "  ${YELLOW}You will now enter AWS credentials for ${num_scans} account(s).${RESET}"
    echo -e "  ${YELLOW}Each account will be scanned in a separate container simultaneously.${RESET}"
    echo ""

    # Collect all credentials first, then launch all containers
    declare -A CRED_STORE
    for i in $(seq 1 "${num_scans}"); do
        get_credentials "${i}"
        CRED_STORE["${i},ACCESS_KEY"]="${AWS_ACCESS_KEY_ID}"
        CRED_STORE["${i},SECRET_KEY"]="${AWS_SECRET_ACCESS_KEY}"
        CRED_STORE["${i},SESSION"]="${AWS_SESSION_TOKEN:-}"
        CRED_STORE["${i},REGION"]="${AWS_DEFAULT_REGION}"
    done

    echo ""
    echo -e "  ${BOLD}${GREEN}Launching ${num_scans} container(s)...${RESET}"

    for i in $(seq 1 "${num_scans}"); do
        AWS_ACCESS_KEY_ID="${CRED_STORE[${i},ACCESS_KEY]}"
        AWS_SECRET_ACCESS_KEY="${CRED_STORE[${i},SECRET_KEY]}"
        AWS_SESSION_TOKEN="${CRED_STORE[${i},SESSION]}"
        AWS_DEFAULT_REGION="${CRED_STORE[${i},REGION]}"
        run_container "${i}"
        sleep 1  # slight stagger to avoid rate limits
    done

    wait_for_all_containers
    show_results_summary
    ask_again_or_exit
}

# ── MAIN ──────────────────────────────────────────────────────────────────────
main() {
    banner
    confirm_docker
    mkdir -p "${RESULTS_DIR}"

    echo ""
    echo -e "  ${BOLD}Checking / building Docker image...${RESET}"
    build_image

    run_scans
}

main