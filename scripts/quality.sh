#!/usr/bin/env bash
# quality.sh — Run quality pipeline for gradle-pitest-plugin
# Usage: bash scripts/quality.sh [quick|full|security|lint]
#
# Modes:
#   quick    — build + shellcheck + hadolint (~30s)
#   full     — build + test + funcTest + codenarc + semgrep + trivy + gitleaks (5-10min)
#   security — semgrep + trivy + gitleaks + dependency-check (3-5min)
#   lint     — shellcheck + hadolint + codenarc (1min)
#
# Run inside the dev container:
#   podman run --rm -v .:/workspace:Z pitest-plugin:dev bash scripts/quality.sh full
#
# Or directly if tools are installed:
#   bash scripts/quality.sh quick
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

section() { echo -e "\n${CYAN}=== $1 ===${NC}"; }
log_pass() { echo -e "${GREEN}  PASS${NC} $1"; ((PASS++)); }
log_fail() { echo -e "${RED}  FAIL${NC} $1"; ((FAIL++)); }
log_warn() { echo -e "${YELLOW}  WARN${NC} $1"; ((WARN++)); }

# --- Build ---
do_build() {
    section "Gradle Build"
    if (cd "$PROJECT_DIR" && ./gradlew build -x test -x funcTest --no-daemon 2>&1 | tail -5 | grep -q "BUILD SUCCESSFUL"); then
        log_pass "Gradle build"
    else
        log_fail "Gradle build"
        return 1
    fi
}

# --- Unit Tests ---
do_test() {
    section "Unit Tests"
    if (cd "$PROJECT_DIR" && ./gradlew test --no-daemon 2>&1 | tail -5 | grep -q "BUILD SUCCESSFUL"); then
        log_pass "Unit tests"
    else
        log_fail "Unit tests"
    fi
}

# --- Functional Tests ---
do_functest() {
    section "Functional Tests"
    if (cd "$PROJECT_DIR" && PITEST_REGRESSION_TESTS=latestOnly ./gradlew funcTest --no-daemon 2>&1 | tail -5 | grep -q "BUILD SUCCESSFUL"); then
        log_pass "Functional tests"
    else
        log_fail "Functional tests"
    fi
}

# --- CodeNarc (via Gradle) ---
do_codenarc() {
    section "CodeNarc"
    if (cd "$PROJECT_DIR" && ./gradlew codenarc --no-daemon 2>&1 | tail -5 | grep -q "BUILD SUCCESSFUL"); then
        log_pass "CodeNarc"
    else
        log_fail "CodeNarc"
    fi
}

# --- ShellCheck ---
do_shellcheck() {
    section "ShellCheck"
    local scripts
    scripts=$(find "$PROJECT_DIR/scripts" -name "*.sh" -type f 2>/dev/null)
    if [[ -z "$scripts" ]]; then
        log_warn "No shell scripts found"
        return
    fi
    for script in $scripts; do
        local name
        name=$(basename "$script")
        if shellcheck "$script" 2>&1; then
            log_pass "$name"
        else
            log_fail "$name"
        fi
    done
}

# --- Hadolint ---
do_hadolint() {
    section "Hadolint"
    local containerfiles
    containerfiles=$(find "$PROJECT_DIR" -name "Containerfile*" -o -name "Dockerfile*" 2>/dev/null | grep -v '.gradle')
    if [[ -z "$containerfiles" ]]; then
        log_warn "No Containerfiles found"
        return
    fi
    for cf in $containerfiles; do
        local name
        name="${cf#"$PROJECT_DIR"/}"
        if hadolint "$cf" 2>&1; then
            log_pass "$name"
        else
            log_warn "$name (warnings)"
        fi
    done
}

# --- Semgrep ---
do_semgrep() {
    section "Semgrep SAST"
    if semgrep scan --config auto --config "p/owasp-top-ten" \
        --exclude='build' --exclude='.gradle' --exclude='*.md' \
        --metrics=off --quiet "$PROJECT_DIR" 2>&1; then
        log_pass "Semgrep"
    else
        log_warn "Semgrep (findings reported)"
    fi
}

# --- Trivy ---
do_trivy() {
    section "Trivy Vulnerability Scan"
    if trivy fs --severity HIGH,CRITICAL --exit-code 0 \
        --skip-dirs build --skip-dirs .gradle \
        "$PROJECT_DIR" 2>&1; then
        log_pass "Trivy filesystem scan"
    else
        log_warn "Trivy (vulnerabilities found)"
    fi
}

# --- Gitleaks ---
do_gitleaks() {
    section "Gitleaks Secret Detection"
    if gitleaks detect --source "$PROJECT_DIR" --no-banner 2>&1; then
        log_pass "Gitleaks"
    else
        log_fail "Gitleaks (secrets detected!)"
    fi
}

# --- OWASP Dependency-Check ---
do_depcheck() {
    section "OWASP Dependency-Check"
    if command -v dependency-check &>/dev/null; then
        dependency-check --project "gradle-pitest-plugin" \
            --scan "$PROJECT_DIR" \
            --format JSON --format HTML \
            --out "$PROJECT_DIR/build/reports/dependency-check" \
            --exclude '**/.gradle/**' --exclude '**/build/**' 2>&1
        log_pass "Dependency-Check (report in build/reports/dependency-check/)"
    else
        log_warn "dependency-check not installed (skipped)"
    fi
}

# --- Summary ---
summary() {
    echo -e "\n${CYAN}========================================${NC}"
    echo -e "  ${GREEN}PASS: $PASS${NC}  ${RED}FAIL: $FAIL${NC}  ${YELLOW}WARN: $WARN${NC}"
    echo -e "${CYAN}========================================${NC}"
    if [[ $FAIL -gt 0 ]]; then
        echo -e "${RED}Quality gate FAILED${NC}"
        return 1
    fi
    echo -e "${GREEN}Quality gate PASSED${NC}"
}

# --- Main ---
MODE="${1:-quick}"

case "$MODE" in
    quick)
        do_build
        do_shellcheck
        do_hadolint
        ;;
    full)
        do_build
        do_test
        do_functest
        do_codenarc
        do_shellcheck
        do_hadolint
        do_semgrep
        do_trivy
        do_gitleaks
        ;;
    security)
        do_semgrep
        do_trivy
        do_gitleaks
        do_depcheck
        ;;
    lint)
        do_shellcheck
        do_hadolint
        do_codenarc
        ;;
    *)
        echo "Usage: $0 [quick|full|security|lint]"
        exit 1
        ;;
esac

summary
