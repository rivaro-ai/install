#!/bin/bash
set -e

# ============================================================
# Rivaro for Developers - One-Line Installer
# ============================================================
# Usage:
#   curl -fsSL https://get.rivaro.ai | bash
#
# What this does:
#   1. Checks for Docker + Docker Compose
#   2. Downloads the developer docker-compose.yaml
#   3. Runs docker compose up -d
#   4. Waits for the backend to be healthy
#   5. Runs a test detection
#   6. Opens the dashboard
#
# Options (via environment variables):
#   RIVARO_DEV_DIR     Install directory (default: ~/.rivaro/developer)
#   RIVARO_BACKEND_MODE image (default) or obfuscated
#   RIVARO_BACKEND_JAR_URL URL used when backend mode is obfuscated
#   OPENAI_API_KEY     Pre-configure your OpenAI key (optional)
#   ANTHROPIC_API_KEY  Pre-configure your Anthropic key (optional)
# ============================================================

RIVARO_DEV_DIR="${RIVARO_DEV_DIR:-$HOME/.rivaro/developer}"
RIVARO_BACKEND_MODE="${RIVARO_BACKEND_MODE:-image}"
RIVARO_BACKEND_JAR_URL="${RIVARO_BACKEND_JAR_URL:-https://github.com/rivaro-ai/ai-compliance/releases/latest/download/rivaro-backend.jar}"
GITHUB_RAW="https://raw.githubusercontent.com/rivaro-ai/developer/main"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC}  $1"; }
ok()    { echo -e "${GREEN}  ✓${NC}  $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
fail()  { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

echo ""
echo -e "${BOLD}Rivaro for Developers${NC}"
echo -e "${DIM}Runtime governance for AI agents${NC}"
echo ""

if [ "$RIVARO_BACKEND_MODE" != "image" ] && [ "$RIVARO_BACKEND_MODE" != "obfuscated" ]; then
    fail "Invalid RIVARO_BACKEND_MODE=${RIVARO_BACKEND_MODE}. Use 'image' or 'obfuscated'."
fi

# ── Prerequisites ────────────────────────────────────────────

if ! command -v docker &> /dev/null; then
    fail "Docker is required. Install it at https://docs.docker.com/get-docker/"
fi
ok "Docker"

if ! docker compose version &> /dev/null; then
    fail "Docker Compose is required. Install it at https://docs.docker.com/compose/install/"
fi
ok "Docker Compose"

if ! docker info &> /dev/null 2>&1; then
    fail "Docker daemon is not running. Start Docker and try again."
fi
ok "Docker is running"

echo ""

# ── Download ─────────────────────────────────────────────────

mkdir -p "$RIVARO_DEV_DIR"

info "Downloading to ${RIVARO_DEV_DIR}"

if ! curl -fsSL "${GITHUB_RAW}/docker-compose.yaml" -o "${RIVARO_DEV_DIR}/docker-compose.yaml"; then
    fail "Failed to download docker-compose.yaml. Check your internet connection."
fi
ok "docker-compose.yaml"

COMPOSE_FILES=(-f docker-compose.yaml)
if [ "$RIVARO_BACKEND_MODE" = "obfuscated" ]; then
    info "Downloading obfuscated backend JAR"
    if ! curl -fsSL "${RIVARO_BACKEND_JAR_URL}" -o "${RIVARO_DEV_DIR}/rivaro-backend.jar"; then
        fail "Failed to download obfuscated backend JAR from ${RIVARO_BACKEND_JAR_URL}"
    fi

    if command -v jar >/dev/null 2>&1; then
        if ! jar tf "${RIVARO_DEV_DIR}/rivaro-backend.jar" >/dev/null 2>&1; then
            fail "Downloaded JAR is invalid (jar tf check failed)."
        fi
    elif command -v unzip >/dev/null 2>&1; then
        if ! unzip -tq "${RIVARO_DEV_DIR}/rivaro-backend.jar" >/dev/null 2>&1; then
            fail "Downloaded JAR is invalid (unzip -t check failed)."
        fi
    else
        warn "Skipping JAR integrity check (install 'jar' or 'unzip' for verification)."
    fi

    cat > "${RIVARO_DEV_DIR}/docker-compose.obfuscated.yaml" <<'EOF'
services:
  backend:
    image: eclipse-temurin:17-jre
    container_name: rivaro-dev-backend
    working_dir: /app
    command: ["java", "-jar", "/app/rivaro-backend.jar"]
    volumes:
      - ./rivaro-backend.jar:/app/rivaro-backend.jar:ro
    depends_on:
      mysql:
        condition: service_healthy
      rabbitmq:
        condition: service_healthy
      redis:
        condition: service_healthy

  frontend:
    depends_on:
      backend:
        condition: service_started
EOF
    COMPOSE_FILES+=(-f docker-compose.obfuscated.yaml)
    ok "rivaro-backend.jar (obfuscated)"
fi

# ── Write .env if provider keys are set ──────────────────────

ENV_FILE="${RIVARO_DEV_DIR}/.env"
if [ -n "$OPENAI_API_KEY" ] || [ -n "$ANTHROPIC_API_KEY" ]; then
    {
        [ -n "$OPENAI_API_KEY" ] && echo "OPENAI_API_KEY=${OPENAI_API_KEY}"
        [ -n "$ANTHROPIC_API_KEY" ] && echo "ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}"
    } > "$ENV_FILE"
    ok "Provider keys saved to .env"
fi

echo ""

# ── Start services ───────────────────────────────────────────

info "Starting Rivaro (this takes ~60 seconds on first run)..."
echo ""

cd "$RIVARO_DEV_DIR"
docker compose "${COMPOSE_FILES[@]}" pull --quiet 2>/dev/null || true
docker compose "${COMPOSE_FILES[@]}" up -d

echo ""
info "Waiting for backend to be ready..."

MAX_WAIT=180
WAITED=0
while [ $WAITED -lt $MAX_WAIT ]; do
    if curl -sf http://localhost:8080/actuator/health > /dev/null 2>&1; then
        break
    fi
    sleep 3
    WAITED=$((WAITED + 3))
    if [ $((WAITED % 15)) -eq 0 ]; then
        echo -e "  ${DIM}Still starting... (${WAITED}s)${NC}"
    fi
done

if [ $WAITED -ge $MAX_WAIT ]; then
    warn "Backend is still starting. Check logs with: docker compose -f ${RIVARO_DEV_DIR}/docker-compose.yaml logs backend"
    echo ""
    echo -e "  Once it's ready, open: ${BOLD}http://localhost:3000${NC}"
    exit 0
fi

echo ""
echo -e "  ${GREEN}✔${NC}  Rivaro running on ${BOLD}localhost:8080${NC}"
echo -e "  ${GREEN}✔${NC}  Intercepting AI requests"
echo ""

# ── Test detection ───────────────────────────────────────────

echo -e "  → Running test detection..."
echo ""

SCAN_OK=false
for attempt in 1 2 3; do
    SCAN_RESULT=$(curl -sf -X POST http://localhost:8080/api/local/demo-scan \
        -H "Content-Type: application/json" \
        -d '{"content": "Process customer John Smith, SSN 123-45-6789, email john@example.com"}' 2>/dev/null)
    if [ $? -eq 0 ] && echo "$SCAN_RESULT" | grep -q '"detection_count":[1-9]'; then
        SCAN_OK=true
        break
    fi
    sleep 2
done

if $SCAN_OK; then
    echo -e "    ${RED}→ Detected: Sensitive data (SSN, email address)${NC}"
    echo -e "    ${YELLOW}→ Action: REDACTED${NC}"
    echo ""
    echo -e "  ${GREEN}${BOLD}✔ Your first AI risk was prevented${NC}"
else
    echo -e "    ${DIM}Detection test skipped — backend still warming up.${NC}"
    echo -e "    ${DIM}Try: curl -X POST http://localhost:8080/api/local/demo-scan -H 'Content-Type: application/json' -d '{\"content\":\"SSN 123-45-6789\"}'${NC}"
fi

echo ""
echo -e "  Dashboard:  ${BOLD}http://localhost:3000${NC}"
echo -e "  Proxy:      ${BOLD}http://localhost:8080${NC}"
echo ""
echo -e "  ${BOLD}Next:${NC} Point your agent's base_url to ${BOLD}http://localhost:8080/v1${NC}"
echo -e "  ${DIM}Docs: https://docs.rivaro.ai/developer-quickstart${NC}"
echo ""
echo -e "  ${DIM}Manage:${NC}"
if [ "$RIVARO_BACKEND_MODE" = "obfuscated" ]; then
    echo -e "    ${DIM}cd ${RIVARO_DEV_DIR} && docker compose -f docker-compose.yaml -f docker-compose.obfuscated.yaml logs -f${NC}"
    echo -e "    ${DIM}cd ${RIVARO_DEV_DIR} && docker compose -f docker-compose.yaml -f docker-compose.obfuscated.yaml down${NC}"
    echo -e "    ${DIM}cd ${RIVARO_DEV_DIR} && docker compose -f docker-compose.yaml -f docker-compose.obfuscated.yaml down -v${NC}"
else
    echo -e "    ${DIM}cd ${RIVARO_DEV_DIR} && docker compose logs -f   # stream logs${NC}"
    echo -e "    ${DIM}cd ${RIVARO_DEV_DIR} && docker compose down      # stop${NC}"
    echo -e "    ${DIM}cd ${RIVARO_DEV_DIR} && docker compose down -v   # reset all data${NC}"
fi
echo ""

# Open the dashboard (best-effort)
if command -v open &> /dev/null; then
    open "http://localhost:3000" 2>/dev/null || true
elif command -v xdg-open &> /dev/null; then
    xdg-open "http://localhost:3000" 2>/dev/null || true
fi
