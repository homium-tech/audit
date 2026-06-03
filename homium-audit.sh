#!/usr/bin/env bash
# =============================================================================
# homium-audit — Web Audit Tool for Claude Code
# Repo: homium-tech/audit
# Version: 1.1.0
# =============================================================================

# Sin flags estrictos: compatibilidad macOS/Linux (BSD/GNU)

# ─── Colors & Symbols ────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'
DIM='\033[2m'; RESET='\033[0m'
CHECK="✓"; CROSS="✗"; ARROW="→"; WARN="⚠"

# ─── Config ───────────────────────────────────────────────────────────────────
AUDIT_DIR="${HOME}/audits"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
_month_num=$(date +%m)
case "$_month_num" in
  01) _month_es="enero"      ;; 02) _month_es="febrero"    ;; 03) _month_es="marzo"      ;;
  04) _month_es="abril"      ;; 05) _month_es="mayo"       ;; 06) _month_es="junio"      ;;
  07) _month_es="julio"      ;; 08) _month_es="agosto"     ;; 09) _month_es="septiembre" ;;
  10) _month_es="octubre"    ;; 11) _month_es="noviembre"  ;; 12) _month_es="diciembre"  ;;
esac
DATE_HUMAN="$(date +%d) de ${_month_es} de $(date +%Y)"
TIMEOUT=30

# ─── Temp dir (declarado primero para que todo lo use) ────────────────────────
TMPDIR_AUDIT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_AUDIT"' EXIT

DATA_FILE="${TMPDIR_AUDIT}/audit_data.json"
LH_JSON_MOBILE="${TMPDIR_AUDIT}/lighthouse-mobile.json"
LH_JSON_DESKTOP="${TMPDIR_AUDIT}/lighthouse-desktop.json"
LH_DONE_MOBILE=false
LH_DONE_DESKTOP=false

# ─── Resolver herramientas opcionales ─────────────────────────────────────────
resolve_cmd() {
  local bin="$1" pkg="${2:-$1}"
  if command -v "$bin" &>/dev/null; then
    echo "$bin"
  elif command -v npx &>/dev/null; then
    echo "npx --yes $pkg"
  else
    echo ""
  fi
}

LH_CMD=$(resolve_cmd "lighthouse" "lighthouse")
AXE_CMD=$(resolve_cmd "axe" "@axe-core/cli")
PA11Y_CMD=$(resolve_cmd "pa11y" "pa11y")
HTMLHINT_CMD=$(resolve_cmd "htmlhint" "htmlhint")
SSLCHECK_CMD=$(resolve_cmd "ssl-checker" "ssl-checker")

# ─── Usage ───────────────────────────────────────────────────────────────────
SCRIPT_VERSION="1.3.4"

usage() {
  echo -e "${BOLD}homium-audit${RESET} v${SCRIPT_VERSION} — Auditoría profesional de sitios web"
  echo -e "  ${CYAN}Uso:${RESET} homium-audit <URL> [opciones]"
  echo -e "  ${CYAN}Opciones:${RESET}"
  echo -e "    --output <dir>         Directorio de salida (default: ~/audits)"
  echo -e "    --compare <file>       Comparar con reporte anterior"
  echo -e "    --dimensions <lista>   Solo analizar ciertas dimensiones (ej: seo,performance,seguridad)"
  echo -e "    --sector <tipo>        Sector del sitio: ecommerce|saas|blog|landing|portfolio"
  echo -e "    --threshold <score>    Exit 1 si score global < valor (útil en CI/CD)"
  echo -e "    --quiet                Solo errores críticos en stdout"
  echo -e "    --version              Muestra la versión instalada"
  echo -e "    --update               Actualiza homium-audit a la última versión"
  echo -e "    --help                 Muestra esta ayuda"
  echo -e ""
  echo -e "  ${CYAN}Dimensiones disponibles:${RESET} performance, seo, accesibilidad, seguridad,"
  echo -e "    ciberseguridad, calidad, diseno, ux"
  exit 0
}

# ─── Argument Parsing ─────────────────────────────────────────────────────────
URL=""; OUTPUT_DIR="$AUDIT_DIR"; COMPARE_FILE=""; QUIET=false
DIMENSIONS=""; SECTOR=""; THRESHOLD=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)       usage ;;
    --version|-v)    echo "homium-audit v${SCRIPT_VERSION}"; exit 0 ;;
    --update)
      echo -e "${CYAN}Actualizando homium-audit...${RESET}"
      INSTALL_DIR="${HOME}/.homium-audit"
      if curl -sSL "https://raw.githubusercontent.com/homium-tech/audit/main/homium-audit.sh" \
          -o "${INSTALL_DIR}/homium-audit.sh" 2>/dev/null; then
        chmod +x "${INSTALL_DIR}/homium-audit.sh"
        echo -e "${GREEN}✓ Actualizado correctamente en ${INSTALL_DIR}/homium-audit.sh${RESET}"
      else
        echo -e "${RED}✗ No se pudo actualizar. Verifica tu conexión.${RESET}" >&2; exit 1
      fi
      exit 0 ;;
    --output)        OUTPUT_DIR="$2"; shift 2 ;;
    --compare)       COMPARE_FILE="$2"; shift 2 ;;
    --dimensions)    DIMENSIONS="$2"; shift 2 ;;
    --sector)        SECTOR="$2"; shift 2 ;;
    --threshold)     THRESHOLD="$2"; shift 2 ;;
    --quiet)         QUIET=true; shift ;;
    http*)           URL="$1"; shift ;;
    *)               echo -e "${RED}Opción desconocida: $1${RESET}"; usage ;;
  esac
done

[[ -z "$URL" ]] && { echo -e "${RED}Error: Se requiere una URL.${RESET}"; usage; }

# should_run: true si la dimensión está en --dimensions (o si no hay filtro)
should_run() {
  [[ -z "$DIMENSIONS" ]] && return 0
  echo ",$DIMENSIONS," | grep -qi ",${1}," && return 0 || return 1
}

# ─── Helpers ──────────────────────────────────────────────────────────────────
log()  { [[ "$QUIET" == false ]] && echo -e "${DIM}[audit]${RESET} $*" || true; }
info() { [[ "$QUIET" == false ]] && echo -e "${BLUE}${BOLD}[•]${RESET} $*" || true; }
ok()   { [[ "$QUIET" == false ]] && echo -e "${GREEN}${CHECK}${RESET} $*" || true; }
warn() { echo -e "${YELLOW}${WARN}${RESET} $*"; }
err()  { echo -e "${RED}${CROSS}${RESET} $*" >&2; }
step() { [[ "$QUIET" == false ]] && echo -e "\n${CYAN}${BOLD}━━ $* ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}" || true; }

normalize_domain() {
  echo "$1" | sed 's|https://||' | sed 's|http://||' | sed 's|www\.||' \
    | sed 's|[/?#].*||' | sed 's|[^a-zA-Z0-9]|-|g' | tr '[:upper:]' '[:lower:]' \
    | sed 's|-\+|-|g' | sed 's|^-||' | sed 's|-$||'
}

progress_bar() {
  local label="$1" pct="$2" width=30
  local filled=$(( pct * width / 100 )) bar="" i
  for ((i=0; i<filled; i++)); do bar+="█"; done
  for ((i=filled; i<width; i++)); do bar+="░"; done
  echo -e "  ${label}: ${CYAN}${bar}${RESET} ${BOLD}${pct}%${RESET}"
}

score_color() {
  local s="${1:-0}"
  (( s >= 80 )) && echo -e "${GREEN}${s}${RESET}" && return
  (( s >= 60 )) && echo -e "${YELLOW}${s}${RESET}" && return
  echo -e "${RED}${s}${RESET}"
}

score_badge() {
  local s="${1:-0}"
  (( s >= 90 )) && echo "🟢" && return
  (( s >= 70 )) && echo "🟡" && return
  (( s >= 50 )) && echo "🟠" && return
  echo "🔴"
}

severity_badge() {
  case "${1:-}" in
    critico) echo "🔴 CRÍTICO" ;; alto)  echo "🟠 ALTO" ;;
    medio)   echo "🟡 MEDIO"  ;; bajo)  echo "🟢 BAJO" ;;
    *)       echo "⚪ INFO"   ;;
  esac
}

ascii_bar() {
  local val="${1:-0}" width="${2:-20}" filled bar="" i
  filled=$(( val * width / 100 ))
  for ((i=0; i<filled; i++)); do bar+="█"; done
  for ((i=filled; i<width; i++)); do bar+="░"; done
  echo "$bar"
}

# ─── HTTP helpers ─────────────────────────────────────────────────────────────
fetch_url() {
  curl -sSL --max-time "$TIMEOUT" \
    --user-agent "Mozilla/5.0 (compatible; homium-audit/1.1)" "$1" 2>/dev/null || echo ""
}

http_status() {
  curl -sSLo /dev/null --max-time "$TIMEOUT" \
    --user-agent "Mozilla/5.0 (compatible; homium-audit/1.1)" \
    -w "%{http_code}" "$1" 2>/dev/null || echo "000"
}

response_time_ms() {
  curl -sSLo /dev/null --max-time "$TIMEOUT" \
    --user-agent "Mozilla/5.0 (compatible; homium-audit/1.1)" \
    -w "%{time_total}" "$1" 2>/dev/null \
    | awk '{printf "%d", $1*1000}' || echo "0"
}

fetch_headers() {
  curl -sSLI --max-time "$TIMEOUT" \
    --user-agent "Mozilla/5.0 (compatible; homium-audit/1.1)" \
    "$1" 2>/dev/null | tr '[:upper:]' '[:lower:]' || echo ""
}

# ─── Timeout wrapper (GNU timeout en Linux, perl en macOS/Windows) ────────────
_timeout() {
  local t="$1"; shift
  if command -v timeout &>/dev/null; then
    timeout "$t" "$@"
  else
    perl -e "alarm $t; exec @ARGV" -- "$@"
  fi
}

# ─── TLS helpers ──────────────────────────────────────────────────────────────
ssl_full_info() {
  local domain="$1"
  local raw
  raw=$(echo "" | _timeout "$TIMEOUT" openssl s_client \
    -connect "${domain}:443" -servername "$domain" 2>/dev/null) || { return 1; }

  # Extraer campos directamente del output s_client (compatible LibreSSL + OpenSSL)
  SSL_PROTOCOL=$(echo "$raw" | grep -iE "^\s*Protocol\s*:" | awk -F: '{print $2}' | xargs 2>/dev/null || echo "")
  [[ -z "$SSL_PROTOCOL" ]] && SSL_PROTOCOL=$(echo "$raw" | grep -oE "TLSv[0-9.]+" | head -1 || echo "Desconocido")

  SSL_CIPHER=$(echo "$raw" | grep -iE "Cipher is" | grep -oE "Cipher is \S+" | sed 's/Cipher is //' | head -1 || echo "")
  [[ -z "$SSL_CIPHER" ]] && SSL_CIPHER=$(echo "$raw" | grep -iE "^\s*Cipher\s*:" | awk -F: '{print $2}' | xargs 2>/dev/null || echo "Desconocido")

  # Parsear cert con openssl x509 (solo flags compatibles con LibreSSL)
  local cert
  cert=$(echo "$raw" | openssl x509 -noout -enddate -issuer -subject 2>/dev/null) || cert=""

  SSL_EXPIRY_DATE=$(echo "$cert" | grep "notAfter" | sed 's/notAfter=//' | xargs 2>/dev/null || echo "")
  SSL_ISSUER=$(echo "$raw" | grep "^issuer=" \
    | perl -nle 'if (/O=([^,\/]+)/) { $v=$1; $v=~s/^\s+|\s+$//g; print $v }' | head -1 || echo "Desconocido")
  [[ -z "$SSL_ISSUER" ]] && SSL_ISSUER="Desconocido"
  SSL_SUBJECT=$(echo "$cert" | grep "^subject=" \
    | perl -nle 'if (/CN=([^,\/]+)/) { $v=$1; $v=~s/^\s+|\s+$//g; print $v }' | head -1 || echo "Desconocido")

  # SAN: openssl x509 -text compatible LibreSSL (usar [^, ] en lugar de [^\s,])
  local san_raw
  san_raw=$(echo "$raw" | openssl x509 -noout -text 2>/dev/null \
    | grep -A1 "Subject Alternative Name" | grep "DNS:" || echo "")
  SSL_SAN=$(echo "$san_raw" | grep -oE 'DNS:[^, ]+' | sed 's/DNS://g' | tr '\n' ' ' \
    | sed 's/^ *//;s/ *$//' || echo "")

  if [[ -n "$SSL_EXPIRY_DATE" ]]; then
    local exp_epoch now_epoch
    exp_epoch=$(date -j -f "%b %d %T %Y %Z" "$SSL_EXPIRY_DATE" +%s 2>/dev/null \
      || date -d "$SSL_EXPIRY_DATE" +%s 2>/dev/null) || exp_epoch=""
    if [[ -n "$exp_epoch" ]]; then
      now_epoch=$(date +%s)
      SSL_DAYS_LEFT=$(( (exp_epoch - now_epoch) / 86400 ))
    else
      SSL_DAYS_LEFT=-1
    fi
  else
    SSL_DAYS_LEFT=-1
  fi
}

ssl_days_remaining() {
  local domain="$1"
  ssl_full_info "$domain" 2>/dev/null || true
  echo "${SSL_DAYS_LEFT:--1}"
}

# ─── Score storage — variables simples (bash 3/4/5 compatible) ──────────────
SCORE_S_performance=0; SCORE_S_seo=0;       SCORE_S_accesibilidad=0
SCORE_S_seguridad=0;   SCORE_S_ciberseguridad=0; SCORE_S_calidad_tecnica=0
SCORE_S_diseno=0;      SCORE_S_ux=0

set_score() {
  local key="$1" val="${2:-0}"
  eval "SCORE_S_${key}=${val}"
}

get_score() {
  local key="$1"
  eval "echo "\${SCORE_S_${key}:-0}""
}

# ─── Detectar Chrome/Chromium para Lighthouse ────────────────────────────────
_detect_chrome() {
  # macOS — Chrome instalado
  [[ -f "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" ]] && \
    echo "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" && return
  # macOS — Chromium via Homebrew
  [[ -f "/opt/homebrew/bin/chromium" ]] && echo "/opt/homebrew/bin/chromium" && return
  [[ -f "/usr/local/bin/chromium"    ]] && echo "/usr/local/bin/chromium"    && return
  # Linux
  command -v google-chrome        &>/dev/null && echo "$(command -v google-chrome)"        && return
  command -v google-chrome-stable &>/dev/null && echo "$(command -v google-chrome-stable)" && return
  command -v chromium-browser     &>/dev/null && echo "$(command -v chromium-browser)"     && return
  command -v chromium             &>/dev/null && echo "$(command -v chromium)"             && return
  # Windows — Git Bash (rutas en formato Unix → convertidas a C:/... para Node.js)
  local _win_chrome=""
  if [[ -f "/c/Program Files/Google/Chrome/Application/chrome.exe" ]]; then
    _win_chrome="C:/Program Files/Google/Chrome/Application/chrome.exe"
  elif [[ -f "/c/Program Files (x86)/Google/Chrome/Application/chrome.exe" ]]; then
    _win_chrome="C:/Program Files (x86)/Google/Chrome/Application/chrome.exe"
  elif [[ -f "${HOME}/AppData/Local/Google/Chrome/Application/chrome.exe" ]]; then
    # HOME en Git Bash es /c/Users/username → convertir a C:/Users/username para Node.js
    _win_chrome=$(echo "${HOME}/AppData/Local/Google/Chrome/Application/chrome.exe" \
      | perl -pe 's|^/([a-z])/|uc($1).":/"|e' 2>/dev/null || \
        echo "${HOME}/AppData/Local/Google/Chrome/Application/chrome.exe")
  fi
  [[ -n "$_win_chrome" ]] && echo "$_win_chrome" && return
  echo ""
}

# ─── Lighthouse — mobile + desktop ───────────────────────────────────────────
_run_lh() {
  local out="$1" extra_flags="$2" chrome_path="$3"
  if [[ -n "$chrome_path" ]]; then
    $LH_CMD "$URL" --output=json --output-path="$out" \
      --only-categories=performance,seo,accessibility,best-practices \
      --chrome-flags="--headless --no-sandbox --disable-gpu" \
      --chrome-path="$chrome_path" \
      $extra_flags --quiet 2>/dev/null
  else
    $LH_CMD "$URL" --output=json --output-path="$out" \
      --only-categories=performance,seo,accessibility,best-practices \
      --chrome-flags="--headless --no-sandbox --disable-gpu" \
      $extra_flags --quiet 2>/dev/null
  fi
}

run_lighthouse() {
  [[ -z "$LH_CMD" ]] && return 1
  local chrome_path
  chrome_path=$(_detect_chrome)

  if [[ "$LH_DONE_MOBILE" != true ]]; then
    info "Ejecutando Lighthouse Mobile..."
    _run_lh "$LH_JSON_MOBILE" "" "$chrome_path" && LH_DONE_MOBILE=true || true
    [[ "$LH_DONE_MOBILE" == true ]] && ok "Lighthouse Mobile completado" || warn "Lighthouse Mobile no pudo completar"
  fi

  if [[ "$LH_DONE_DESKTOP" != true ]]; then
    info "Ejecutando Lighthouse Desktop..."
    _run_lh "$LH_JSON_DESKTOP" "--preset=desktop" "$chrome_path" && LH_DONE_DESKTOP=true || true
    [[ "$LH_DONE_DESKTOP" == true ]] && ok "Lighthouse Desktop completado" || warn "Lighthouse Desktop no pudo completar"
  fi
}

lh_score() {
  local key="$1" device="${2:-mobile}"
  local json_file
  [[ "$device" == "desktop" ]] && json_file="$LH_JSON_DESKTOP" || json_file="$LH_JSON_MOBILE"
  local done_flag
  [[ "$device" == "desktop" ]] && done_flag="$LH_DONE_DESKTOP" || done_flag="$LH_DONE_MOBILE"
  [[ "$done_flag" != true ]] && { echo ""; return; }
  [[ ! -f "$json_file" ]] && { echo ""; return; }
  command -v jq &>/dev/null || { echo ""; return; }
  local raw
  raw=$(jq ".categories[\"${key}\"].score // 0" "$json_file" 2>/dev/null) || { echo ""; return; }
  awk "BEGIN{printf \"%d\", ${raw:-0} * 100}"
}

lh_metric() {
  local audit="$1" device="${2:-mobile}"
  local json_file
  [[ "$device" == "desktop" ]] && json_file="$LH_JSON_DESKTOP" || json_file="$LH_JSON_MOBILE"
  [[ ! -f "$json_file" ]] && { echo "N/A"; return; }
  command -v jq &>/dev/null || { echo "N/A"; return; }
  jq -r ".audits[\"${audit}\"].displayValue // \"N/A\"" "$json_file" 2>/dev/null | tr -d '\n' || echo "N/A"
}

# ─── Dependency check ─────────────────────────────────────────────────────────
check_dependencies() {
  step "Verificando dependencias"
  local missing=()
  for t in curl openssl; do
    command -v "$t" &>/dev/null && ok "$t" || { missing+=("$t"); err "$t (requerido)"; }
  done
  [[ -n "$LH_CMD"       ]] && ok "lighthouse ($LH_CMD)"         || warn "lighthouse — npm i -g lighthouse"
  [[ -n "$AXE_CMD"      ]] && ok "axe-core ($AXE_CMD)"          || warn "@axe-core/cli — npm i -g @axe-core/cli"
  [[ -n "$PA11Y_CMD"    ]] && ok "pa11y ($PA11Y_CMD)"           || warn "pa11y — npm i -g pa11y"
  [[ -n "$HTMLHINT_CMD" ]] && ok "htmlhint ($HTMLHINT_CMD)"     || warn "htmlhint — npm i -g htmlhint"
  [[ -n "$SSLCHECK_CMD" ]] && ok "ssl-checker ($SSLCHECK_CMD)"  || warn "ssl-checker — npm i -g ssl-checker"
  command -v jq  &>/dev/null && ok "jq"  || warn "jq — scores compuestos deshabilitados"
  command -v dig &>/dev/null && ok "dig" || warn "dig — DNS lookup deshabilitado"
  [[ ${#missing[@]} -gt 0 ]] && { err "Faltan: ${missing[*]}"; exit 1; } || true
}

# ─── Hosting & Domain ─────────────────────────────────────────────────────────
lookup_hosting_domain() {
  local domain="$1"
  info "Resolviendo IP y hosting..."

  # Resolver IP: dig → nslookup → Google DNS API
  SEC_HOST_IP=""
  if command -v dig &>/dev/null; then
    SEC_HOST_IP=$(dig +short A "$domain" 2>/dev/null | grep -E '^[0-9]+\.' | head -1 || echo "")
  fi
  if [[ -z "$SEC_HOST_IP" ]] && command -v nslookup &>/dev/null; then
    SEC_HOST_IP=$(nslookup "$domain" 2>/dev/null | grep -A1 "Name:" | grep "Address" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "")
  fi
  if [[ -z "$SEC_HOST_IP" ]]; then
    SEC_HOST_IP=$(curl -sSL --max-time 10       "https://dns.google/resolve?name=${domain}&type=A" 2>/dev/null       | perl -nle 'print $1 if /"data":"([0-9.]+)"/' | head -1 || echo "")
  fi
  SEC_HOST_IP="${SEC_HOST_IP:-No resuelto}"

  SEC_HOST_PROVIDER="Desconocido"; SEC_HOST_COUNTRY="Desconocido"
  SEC_HOST_CITY="Desconocido"; SEC_HOST_ASN="Desconocido"; SEC_HOST_ORG="Desconocido"
  SEC_HOST_RANGE="Desconocido"; SEC_HOST_ABUSE="Desconocido"

  if [[ "$SEC_HOST_IP" != "No resuelto" ]]; then
    local geo
    geo=$(curl -sSL --max-time 10 "https://ipinfo.io/${SEC_HOST_IP}/json" 2>/dev/null) || geo=""
    if [[ -n "$geo" ]] && command -v jq &>/dev/null; then
      SEC_HOST_COUNTRY=$(echo "$geo" | jq -r '.country // "Desconocido"' 2>/dev/null || echo "Desconocido")
      SEC_HOST_CITY=$(echo    "$geo" | jq -r '.city    // "Desconocido"' 2>/dev/null || echo "Desconocido")
      SEC_HOST_ORG=$(echo     "$geo" | jq -r '.org     // "Desconocido"' 2>/dev/null || echo "Desconocido")
      SEC_HOST_RANGE=$(echo   "$geo" | jq -r '.ip      // "Desconocido"' 2>/dev/null || echo "Desconocido")
      SEC_HOST_ASN=$(echo "$SEC_HOST_ORG" | grep -oE '^AS[0-9]+' || echo "Desconocido")
      SEC_HOST_PROVIDER=$(echo "$SEC_HOST_ORG" | sed 's/^AS[0-9]* //')
      local abuse_json
      abuse_json=$(curl -sSL --max-time 8 "https://ipinfo.io/${SEC_HOST_IP}/abuse" 2>/dev/null) || abuse_json=""
      [[ -n "$abuse_json" ]] && SEC_HOST_ABUSE=$(echo "$abuse_json" | jq -r '.email // "Desconocido"' 2>/dev/null || echo "Desconocido") || true
    elif [[ -n "$geo" ]]; then
      SEC_HOST_COUNTRY=$(echo "$geo" | grep -o '"country":"[^"]*"' | cut -d'"' -f4 || echo "Desconocido")
      SEC_HOST_CITY=$(echo    "$geo" | grep -o '"city":"[^"]*"'    | cut -d'"' -f4 || echo "Desconocido")
      SEC_HOST_ORG=$(echo     "$geo" | grep -o '"org":"[^"]*"'     | cut -d'"' -f4 || echo "Desconocido")
      SEC_HOST_PROVIDER=$(echo "$SEC_HOST_ORG" | sed 's/^AS[0-9]* //')
    fi
  fi

  info "Consultando WHOIS..."
  SEC_DOM_REGISTRAR="Desconocido"; SEC_DOM_CREATED="Desconocido"
  SEC_DOM_EXPIRES="Desconocido";   SEC_DOM_UPDATED="Desconocido"
  SEC_DOM_NAMESERVERS="Desconocido"; SEC_DOM_PRIVACY=false
  SEC_DOM_EXPIRY_NOTE=""; SEC_DOM_DAYS_LEFT=-1

  # whois → RDAP API fallback (rdap.org — funciona en Git Bash/Windows)
  local w=""
  if command -v whois &>/dev/null; then
    w=$(whois "$domain" 2>/dev/null | head -80) || w=""
  fi
  if [[ -z "$w" ]]; then
    local rdap_tld="${domain##*.}"
    local rdap_json
    rdap_json=$(curl -sSL --max-time 15       "https://rdap.org/domain/${domain}" 2>/dev/null) || rdap_json=""
    if [[ -n "$rdap_json" ]]; then
      local reg_name
      reg_name=$(echo "$rdap_json" | perl -nle 'print $1 if /"fn":"([^"]+)"/' | head -1 || echo "")
      [[ -n "$reg_name" ]] && w="Registrar: ${reg_name}"
      local exp_date
      exp_date=$(echo "$rdap_json" | perl -nle 'print $1 if /"expirationDate":"([^"T]+)/' | head -1 || echo "")
      [[ -n "$exp_date" ]] && w="${w}"$'
'"Registry Expiry Date: ${exp_date}"
      local cr_date
      cr_date=$(echo "$rdap_json" | perl -nle 'print $1 if /"registrationDate":"([^"T]+)/' | head -1 || echo "")
      [[ -n "$cr_date" ]] && w="${w}"$'
'"Creation Date: ${cr_date}"
    fi
  fi
  if [[ -n "$w" ]]; then
    local w_orig="$w"
      SEC_DOM_REGISTRAR=$(echo "$w" | grep -iE "^registrar:"       | head -1 | sed 's/[Rr]egistrar:\s*//' | xargs || echo "Desconocido")
      SEC_DOM_CREATED=$(echo   "$w" | grep -iE "creation date|created:" | head -1 | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1 || echo "")
      SEC_DOM_EXPIRES=$(echo   "$w" | grep -iE "expir"             | head -1 | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1 || echo "")
      SEC_DOM_UPDATED=$(echo   "$w" | grep -iE "updated"           | head -1 | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1 || echo "")
      SEC_DOM_NAMESERVERS=$(echo "$w" | grep -iE "^name server:"   | sed 's/[Nn]ame [Ss]erver:\s*//' | tr '\n' ',' | sed 's/,$//' | xargs || echo "Desconocido")
      SEC_DOM_STATUS=$(echo "$w" | grep -iE "^domain status:" | head -3 | sed 's/[Dd]omain [Ss]tatus:\s*//' | tr '\n' '·' | sed 's/·$//' | xargs || echo "Desconocido")
      SEC_DOM_ABUSE_EMAIL=$(echo "$w" | grep -iE "registrar abuse contact email" | head -1 | sed 's/.*:\s*//' | xargs || echo "Desconocido")
      echo "$w" | grep -qiE "privacy|redacted|protected|proxy" && SEC_DOM_PRIVACY=true || true
      echo "$w" | grep -qiE "dnssec.*signed|signedDelegation" && SEC_DOM_DNSSEC=true || SEC_DOM_DNSSEC=false
      [[ -z "$SEC_DOM_REGISTRAR"   ]] && SEC_DOM_REGISTRAR="Desconocido"
      [[ -z "$SEC_DOM_CREATED"     ]] && SEC_DOM_CREATED="Desconocido"
      [[ -z "$SEC_DOM_EXPIRES"     ]] && SEC_DOM_EXPIRES="Desconocido"
      [[ -z "$SEC_DOM_NAMESERVERS" ]] && SEC_DOM_NAMESERVERS="Desconocido"
      [[ -z "$SEC_DOM_STATUS"      ]] && SEC_DOM_STATUS="Desconocido"

      if [[ "$SEC_DOM_EXPIRES" != "Desconocido" ]]; then
        local exp_epoch now_epoch
        exp_epoch=$(date -j -f "%Y-%m-%d" "$SEC_DOM_EXPIRES" +%s 2>/dev/null           || date -d "$SEC_DOM_EXPIRES" +%s 2>/dev/null) || exp_epoch=""
        now_epoch=$(date +%s)
        if [[ -n "$exp_epoch" ]]; then
          SEC_DOM_DAYS_LEFT=$(( (exp_epoch - now_epoch) / 86400 ))
          if   (( SEC_DOM_DAYS_LEFT <= 0   )); then SEC_DOM_EXPIRY_NOTE="🔴 EXPIRADO"
          elif (( SEC_DOM_DAYS_LEFT <= 30  )); then SEC_DOM_EXPIRY_NOTE="🔴 Expira en ${SEC_DOM_DAYS_LEFT} días — URGENTE"
          elif (( SEC_DOM_DAYS_LEFT <= 90  )); then SEC_DOM_EXPIRY_NOTE="🟠 Expira en ${SEC_DOM_DAYS_LEFT} días"
          elif (( SEC_DOM_DAYS_LEFT <= 180 )); then SEC_DOM_EXPIRY_NOTE="🟡 Expira en ${SEC_DOM_DAYS_LEFT} días"
          else                                      SEC_DOM_EXPIRY_NOTE="🟢 Válido por ${SEC_DOM_DAYS_LEFT} días"
          fi
        fi
      fi
  else
    warn "whois/RDAP no disponible — datos de dominio omitidos"
  fi
}

# ─── DIMENSION 1: Performance ─────────────────────────────────────────────────
analyze_performance() {
  step "Analizando Performance"
  local score=100

  info "Midiendo tiempo de respuesta..."
  PERF_RESP_MS=$(response_time_ms "$URL")
  PERF_RESP_MS=${PERF_RESP_MS:-0}
  log "Tiempo de respuesta: ${PERF_RESP_MS}ms"

  if   (( PERF_RESP_MS > 3000 )); then score=$((score-40)); PERF_RESP_SEVERITY="critico"
  elif (( PERF_RESP_MS > 1500 )); then score=$((score-25)); PERF_RESP_SEVERITY="alto"
  elif (( PERF_RESP_MS > 800  )); then score=$((score-10)); PERF_RESP_SEVERITY="medio"
  else PERF_RESP_SEVERITY="bajo"; fi

  info "Midiendo peso de página..."
  local page_size
  page_size=$(echo "$HTML_CACHE" | wc -c 2>/dev/null) || page_size=0
  PERF_SIZE_KB=$(( ${page_size:-0} / 1024 ))
  (( PERF_SIZE_KB > 500 )) && score=$((score-20)) || true
  (( PERF_SIZE_KB > 200 && PERF_SIZE_KB <= 500 )) && score=$((score-10)) || true

  info "Verificando protocolo HTTP..."
  local protocol
  protocol=$(curl -sSLo /dev/null --max-time "$TIMEOUT" -w "%{http_version}" "$URL" 2>/dev/null) || protocol="1.1"
  PERF_PROTOCOL="HTTP/${protocol:-1.1}"
  [[ "$protocol" != "2" && "$protocol" != "3" ]] && score=$((score-10)) || true

  info "Verificando compresión..."
  local enc_header
  enc_header=$(curl -sSLo /dev/null --max-time "$TIMEOUT" \
    -H "Accept-Encoding: gzip, deflate, br" \
    -D - "$URL" 2>/dev/null | grep -i "content-encoding" | head -1) || enc_header=""
  PERF_COMPRESSION="${enc_header:-Sin compresión}"
  [[ -z "$enc_header" ]] && score=$((score-10)) || true

  info "Midiendo TTFB y cadena de redirects..."
  local ttfb redirects
  ttfb=$(curl -sSLo /dev/null --max-time "$TIMEOUT" \
    --user-agent "Mozilla/5.0 (compatible; homium-audit/1.2)" \
    -w "%{time_starttransfer}" "$URL" 2>/dev/null \
    | awk '{printf "%d", $1*1000}') || ttfb=0
  PERF_TTFB_MS=${ttfb:-0}
  redirects=$(curl -sSLo /dev/null --max-time "$TIMEOUT" \
    --user-agent "Mozilla/5.0 (compatible; homium-audit/1.2)" \
    -w "%{num_redirects}" "$URL" 2>/dev/null) || redirects=0
  PERF_REDIRECTS=${redirects:-0}
  (( PERF_TTFB_MS > 600 )) && score=$((score-10)) || true
  (( PERF_REDIRECTS > 2  )) && score=$((score-5))  || true

  info "Detectando CDN..."
  local resp_headers
  resp_headers=$(fetch_headers "$URL")
  PERF_CDN="No detectado"
  echo "$resp_headers" | grep -qi "cf-ray"           && PERF_CDN="Cloudflare"   || true
  echo "$resp_headers" | grep -qi "x-amz-cf-id"      && PERF_CDN="CloudFront"   || true
  echo "$resp_headers" | grep -qi "x-served-by"      && PERF_CDN="Fastly"       || true
  echo "$resp_headers" | grep -qi "x-cache.*akamai\|x-akamai" && PERF_CDN="Akamai" || true
  echo "$resp_headers" | grep -qi "x-varnish"        && PERF_CDN="Varnish"      || true
  echo "$resp_headers" | grep -qi "x-cdn\|keycdn"    && PERF_CDN="KeyCDN"       || true

  info "Contando recursos externos..."
  PERF_JS_COUNT=$(echo "$HTML_CACHE" | grep -ic 'src="[^"]*\.js' 2>/dev/null | tr -d '[:space:]') || PERF_JS_COUNT=0
  PERF_CSS_COUNT=$(echo "$HTML_CACHE" | grep -ic 'href="[^"]*\.css' 2>/dev/null | tr -d '[:space:]') || PERF_CSS_COUNT=0
  PERF_IMG_COUNT=$(echo "$HTML_CACHE" | grep -ic '<img' 2>/dev/null | tr -d '[:space:]') || PERF_IMG_COUNT=0
  PERF_JS_COUNT=${PERF_JS_COUNT:-0}; PERF_CSS_COUNT=${PERF_CSS_COUNT:-0}; PERF_IMG_COUNT=${PERF_IMG_COUNT:-0}
  (( PERF_JS_COUNT > 20  )) && score=$((score-5)) || true
  (( PERF_CSS_COUNT > 10 )) && score=$((score-5)) || true

  run_lighthouse
  PERF_LH_MOBILE=$(lh_score "performance" "mobile")
  PERF_LH_DESKTOP=$(lh_score "performance" "desktop")
  if [[ -n "$PERF_LH_MOBILE" && -n "$PERF_LH_DESKTOP" ]]; then
    score=$(( (score + PERF_LH_MOBILE + PERF_LH_DESKTOP) / 3 ))
  elif [[ -n "$PERF_LH_MOBILE" ]]; then
    score=$(( (score + PERF_LH_MOBILE) / 2 ))
  elif [[ -n "$PERF_LH_DESKTOP" ]]; then
    score=$(( (score + PERF_LH_DESKTOP) / 2 ))
  fi

  (( score < 0 )) && score=0; (( score > 100 )) && score=100
  set_score "performance" "$score"; SCORE_PERFORMANCE=$score
  ok "Performance score: $(score_color $score)"
}

# ─── DIMENSION 2: Calidad Técnica ─────────────────────────────────────────────
analyze_calidad_tecnica() {
  step "Analizando Calidad Técnica"
  local score=100
  local html
  html="$HTML_CACHE"

  CT_DOCTYPE=false; CT_LANG=false; CT_CHARSET=false; CT_VIEWPORT=false
  CT_TITLE=false;   CT_CANONICAL=false

  grep -qi "<!DOCTYPE html>" <<< "$html"     && CT_DOCTYPE=true   || true
  grep -qi '<html[^>]*lang=' <<< \"$html\"     && CT_LANG=true      || true
  grep -qi 'charset=' <<< \"$html\"            && CT_CHARSET=true   || true
  grep -qi 'name="viewport"' <<< \"$html\"     && CT_VIEWPORT=true  || true
  grep -qi '<title>' <<< \"$html\"             && CT_TITLE=true     || true
  grep -qi 'rel="canonical"' <<< \"$html\"     && CT_CANONICAL=true || true

  [[ "$CT_DOCTYPE"   == false ]] && score=$((score-15)) || true
  [[ "$CT_LANG"      == false ]] && score=$((score-10)) || true
  [[ "$CT_CHARSET"   == false ]] && score=$((score-10)) || true
  [[ "$CT_VIEWPORT"  == false ]] && score=$((score-15)) || true
  [[ "$CT_TITLE"     == false ]] && score=$((score-20)) || true
  [[ "$CT_CANONICAL" == false ]] && score=$((score-10)) || true

  CT_INLINE_SCRIPTS=$(echo "$html" | grep -c '<script>' 2>/dev/null | tr -d '[:space:]') || CT_INLINE_SCRIPTS=0
  CT_INLINE_STYLES=$(echo  "$html" | grep -c 'style="'  2>/dev/null | tr -d '[:space:]') || CT_INLINE_STYLES=0
  CT_INLINE_SCRIPTS=${CT_INLINE_SCRIPTS:-0}; CT_INLINE_STYLES=${CT_INLINE_STYLES:-0}
  (( CT_INLINE_SCRIPTS > 5  )) && score=$((score-10)) || true
  (( CT_INLINE_STYLES  > 10 )) && score=$((score-5))  || true

  CT_DEPRECATED=$(echo "$html" | grep -icE '<(center|font|marquee|blink|frame|frameset|noframes|applet|basefont|big|strike|tt|u)\b' 2>/dev/null | tr -d '[:space:]') || CT_DEPRECATED=0
  CT_DEPRECATED=${CT_DEPRECATED:-0}
  (( CT_DEPRECATED > 0 )) && score=$((score-10)) || true

  CT_MIXED_CONTENT=false
  grep -qiE 'src="http://|href="http://' <<< \"$html\" && CT_MIXED_CONTENT=true || true
  [[ "$CT_MIXED_CONTENT" == true ]] && score=$((score-15)) || true

  CT_PWA_MANIFEST=false; grep -qi 'rel="manifest"' <<< "$html" && CT_PWA_MANIFEST=true || true
  CT_SERVICE_WORKER=false; grep -qi 'serviceWorker\|sw\.js' <<< "$html" && CT_SERVICE_WORKER=true || true

  CT_BROKEN_LINKS="N/A"
  if [[ -n "$HTMLHINT_CMD" ]]; then
    info "Ejecutando htmlhint..."
    local tmp_html="${TMPDIR_AUDIT}/page.html" hint_out="${TMPDIR_AUDIT}/htmlhint.json"
    echo "$html" > "$tmp_html"
    CT_HTMLHINT_ERRORS=0; CT_HTMLHINT_WARNINGS=0
    if $HTMLHINT_CMD "$tmp_html" --format json > "$hint_out" 2>/dev/null && command -v jq &>/dev/null; then
      CT_HTMLHINT_ERRORS=$(jq  '[.[].messages[]|select(.type=="error")]|length'   "$hint_out" 2>/dev/null || echo 0)
      CT_HTMLHINT_WARNINGS=$(jq '[.[].messages[]|select(.type=="warning")]|length' "$hint_out" 2>/dev/null || echo 0)
      CT_HTMLHINT_ERRORS=${CT_HTMLHINT_ERRORS:-0}; CT_HTMLHINT_WARNINGS=${CT_HTMLHINT_WARNINGS:-0}
      (( CT_HTMLHINT_ERRORS > 10 )) && score=$((score-20)) || (( CT_HTMLHINT_ERRORS > 5 )) && score=$((score-10)) || true
    fi
  else
    CT_HTMLHINT_ERRORS=0; CT_HTMLHINT_WARNINGS=0
  fi

  (( score < 0 )) && score=0; (( score > 100 )) && score=100
  set_score "calidad_tecnica" "$score"; SCORE_CALIDAD_TECNICA=$score
  ok "Calidad técnica score: $(score_color $score)"
}

# ─── DIMENSION 3: SEO ─────────────────────────────────────────────────────────
analyze_seo() {
  step "Analizando SEO"

  info "Extrayendo logo e imagen del sitio..."
  SITE_OG_IMAGE=$(echo "$HTML_CACHE" | grep -iE 'property="og:image"[^:-]' \
    | grep -oiE 'content="[^"]+"' | sed 's/content="\([^"]*\)"/\1/' \
    | head -1 | xargs 2>/dev/null) || SITE_OG_IMAGE=""
  [[ "$SITE_OG_IMAGE" != http* ]] && SITE_OG_IMAGE=""
  SITE_FAVICON=$(echo "$HTML_CACHE" | grep -iE 'rel="(icon|shortcut icon)"' \
    | sed 's/.*href="\([^"]*\)".*/\1/' | head -1 | xargs 2>/dev/null) || SITE_FAVICON=""
  # Normalizar favicon relativo a URL absoluta
  if [[ -n "$SITE_FAVICON" && "$SITE_FAVICON" != http* ]]; then
    local base_url="${URL%/}"
    [[ "$SITE_FAVICON" == /* ]] && SITE_FAVICON="${base_url}${SITE_FAVICON}" || SITE_FAVICON="${base_url}/${SITE_FAVICON}"
  fi
  local score=100
  local html
  html="$HTML_CACHE"

  local title
  title=$(echo "$html" | grep -i '<title>' | sed 's/.*<title>\(.*\)<\/title>.*/\1/' | head -1 | xargs 2>/dev/null) || title=""
  SEO_TITLE="${title:-AUSENTE}"; SEO_TITLE_LEN="${#title}"
  [[ -z "$title" ]]                                   && score=$((score-25)) || true
  (( ${#title} > 60 ))                                && score=$((score-10)) || true
  (( ${#title} > 0 && ${#title} < 30 ))               && score=$((score-5))  || true

  local meta_desc
  meta_desc=$(echo "$html" | grep -i 'name="description"' \
    | sed 's/.*content="\([^"]*\)".*/\1/' | head -1 | xargs 2>/dev/null) || meta_desc=""
  SEO_META_DESC="${meta_desc:-AUSENTE}"; SEO_META_DESC_LEN="${#meta_desc}"
  [[ -z "$meta_desc" ]]     && score=$((score-20)) || true
  (( ${#meta_desc} > 160 )) && score=$((score-5))  || true

  local h1_count
  h1_count=$(echo "$html" | grep -ic '<h1' 2>/dev/null | tr -d '[:space:]') || h1_count=0
  SEO_H1_COUNT=${h1_count:-0}
  (( SEO_H1_COUNT == 0 )) && score=$((score-15)) || true
  (( SEO_H1_COUNT >  1 )) && score=$((score-10)) || true

  SEO_OG=false;     grep -qi 'property="og:' <<< "$html"         && SEO_OG=true     || true
  SEO_SCHEMA=false; grep -qi 'application/ld+json' <<< "$html"   && SEO_SCHEMA=true || true
  [[ "$SEO_OG"     == false ]] && score=$((score-10)) || true
  [[ "$SEO_SCHEMA" == false ]] && score=$((score-5))  || true

  SEO_TWITTER_CARD=false; grep -qi 'name="twitter:card"' <<< "$html" && SEO_TWITTER_CARD=true || true
  SEO_HREFLANG=false;     grep -qi 'hreflang=' <<< "$html"            && SEO_HREFLANG=true    || true
  local meta_robots
  meta_robots=$(echo "$html" | grep -i 'name="robots"' | sed 's/.*content="\([^"]*\)".*/\1/' | head -1 | xargs 2>/dev/null) || meta_robots=""
  SEO_META_ROBOTS="${meta_robots:-No definido}"
  SEO_H2_COUNT=$(echo "$html" | grep -ic '<h2' 2>/dev/null | tr -d '[:space:]') || SEO_H2_COUNT=0
  SEO_H3_COUNT=$(echo "$html" | grep -ic '<h3' 2>/dev/null | tr -d '[:space:]') || SEO_H3_COUNT=0
  SEO_H2_COUNT=${SEO_H2_COUNT:-0}; SEO_H3_COUNT=${SEO_H3_COUNT:-0}
  local schema_types
  schema_types=$(echo "$html" | grep -oE '"@type"\s*:\s*"[^"]+"' | sed 's/"@type"\s*:\s*"\([^"]*\)"/\1/' | sort -u | tr '\n' ', ' | sed 's/,$//' || echo "")
  SEO_SCHEMA_TYPES="${schema_types:-N/A}"
  local int_links ext_links
  int_links=$(echo "$html" | grep -oiE 'href="/' | wc -l | tr -d '[:space:]') || int_links=0
  ext_links=$(echo "$html"  | grep -oiE 'href="http' | wc -l | tr -d '[:space:]') || ext_links=0
  SEO_INT_LINKS=${int_links:-0}; SEO_EXT_LINKS=${ext_links:-0}

  local base="${URL%/}"
  SEO_ROBOTS=$(http_status "${base}/robots.txt")
  SEO_SITEMAP=$(http_status "${base}/sitemap.xml")
  [[ "$SEO_ROBOTS"  != "200" ]] && score=$((score-10)) || true
  [[ "$SEO_SITEMAP" != "200" ]] && score=$((score-10)) || true

  run_lighthouse
  SEO_LH_MOBILE=$(lh_score "seo" "mobile")
  SEO_LH_DESKTOP=$(lh_score "seo" "desktop")
  if [[ -n "$SEO_LH_MOBILE" && -n "$SEO_LH_DESKTOP" ]]; then
    score=$(( (score + SEO_LH_MOBILE + SEO_LH_DESKTOP) / 3 ))
  elif [[ -n "$SEO_LH_MOBILE" ]]; then
    score=$(( (score + SEO_LH_MOBILE) / 2 ))
  elif [[ -n "$SEO_LH_DESKTOP" ]]; then
    score=$(( (score + SEO_LH_DESKTOP) / 2 ))
  fi

  (( score < 0 )) && score=0; (( score > 100 )) && score=100
  set_score "seo" "$score"; SCORE_SEO=$score
  ok "SEO score: $(score_color $score)"
}

# ─── DIMENSION 4: Accesibilidad ───────────────────────────────────────────────
analyze_accesibilidad() {
  step "Analizando Accesibilidad"
  local score=100
  local html
  html="$HTML_CACHE"

  local imgs_total imgs_no_alt
  imgs_total=$(echo "$html" | grep -ic '<img' 2>/dev/null | tr -d '[:space:]') || imgs_total=0
  imgs_no_alt=$(echo "$html" | grep -i '<img' | grep -cv 'alt=' 2>/dev/null | tr -d '[:space:]') || imgs_no_alt=0
  ACC_IMGS_TOTAL=${imgs_total:-0}; ACC_IMGS_NO_ALT=${imgs_no_alt:-0}
  if (( ACC_IMGS_TOTAL > 0 && ACC_IMGS_NO_ALT > 0 )); then
    local pen=$(( ACC_IMGS_NO_ALT * 5 ))
    (( pen > 30 )) && pen=30
    score=$((score - pen))
  fi

  ACC_ARIA=false;  grep -qi 'aria-label\|aria-labelledby\|role=' <<< "$html" && ACC_ARIA=true  || true
  ACC_SKIP=false;  grep -qi 'skip\|saltar' <<< "$html"                        && ACC_SKIP=true  || true
  [[ "$ACC_ARIA" == false ]] && score=$((score-15)) || true
  [[ "$ACC_SKIP" == false ]] && score=$((score-10)) || true

  local forms_count labels_count
  forms_count=$(echo  "$html" | grep -ic '<form'  2>/dev/null | tr -d '[:space:]') || forms_count=0
  labels_count=$(echo "$html" | grep -ic '<label' 2>/dev/null | tr -d '[:space:]') || labels_count=0
  ACC_FORMS=${forms_count:-0}; ACC_LABELS=${labels_count:-0}
  (( ACC_FORMS > 0 && ACC_LABELS < ACC_FORMS )) && score=$((score-15)) || true

  grep -qi '<html[^>]*lang=' <<< \"$html\" || score=$((score-10)) || true

  run_lighthouse
  ACC_LH_MOBILE=$(lh_score "accessibility" "mobile")
  ACC_LH_DESKTOP=$(lh_score "accessibility" "desktop")
  if [[ -n "$ACC_LH_MOBILE" && -n "$ACC_LH_DESKTOP" ]]; then
    score=$(( (score + ACC_LH_MOBILE + ACC_LH_DESKTOP) / 3 ))
  elif [[ -n "$ACC_LH_MOBILE" ]]; then
    score=$(( (score + ACC_LH_MOBILE) / 2 ))
  elif [[ -n "$ACC_LH_DESKTOP" ]]; then
    score=$(( (score + ACC_LH_DESKTOP) / 2 ))
  fi

  ACC_AXE_VIOLATIONS=0; ACC_AXE_SERIOUS=0
  if [[ -n "$AXE_CMD" ]]; then
    info "Ejecutando axe-core..."
    local axe_out="${TMPDIR_AUDIT}/axe.json"
    if $AXE_CMD "$URL" --save "$axe_out" --quiet 2>/dev/null && command -v jq &>/dev/null && [[ -f "$axe_out" ]]; then
      ACC_AXE_VIOLATIONS=$(jq '[.violations[].nodes[]]|length'                                                           "$axe_out" 2>/dev/null || echo 0)
      ACC_AXE_SERIOUS=$(jq    '[.violations[]|select(.impact=="serious" or .impact=="critical")|.nodes[]]|length'        "$axe_out" 2>/dev/null || echo 0)
      ACC_AXE_VIOLATIONS=${ACC_AXE_VIOLATIONS:-0}; ACC_AXE_SERIOUS=${ACC_AXE_SERIOUS:-0}
      local pen=$(( ACC_AXE_SERIOUS * 3 )); (( pen > 20 )) && pen=20
      (( ACC_AXE_SERIOUS > 0 )) && score=$((score - pen)) || true
    fi
  fi

  ACC_PA11Y_ERRORS=0; ACC_PA11Y_WARNINGS=0
  if [[ -n "$PA11Y_CMD" ]]; then
    info "Ejecutando pa11y..."
    local pa11y_out="${TMPDIR_AUDIT}/pa11y.json"
    if $PA11Y_CMD "$URL" --reporter json > "$pa11y_out" 2>/dev/null && command -v jq &>/dev/null && [[ -f "$pa11y_out" ]]; then
      ACC_PA11Y_ERRORS=$(jq   '[.[]|select(.type=="error")]  |length' "$pa11y_out" 2>/dev/null || echo 0)
      ACC_PA11Y_WARNINGS=$(jq '[.[]|select(.type=="warning")]|length' "$pa11y_out" 2>/dev/null || echo 0)
      ACC_PA11Y_ERRORS=${ACC_PA11Y_ERRORS:-0}; ACC_PA11Y_WARNINGS=${ACC_PA11Y_WARNINGS:-0}
      local pen=$(( ACC_PA11Y_ERRORS * 2 )); (( pen > 15 )) && pen=15
      (( ACC_PA11Y_ERRORS > 0 )) && score=$((score - pen)) || true
    fi
  fi

  (( score < 0 )) && score=0; (( score > 100 )) && score=100
  set_score "accesibilidad" "$score"; SCORE_ACCESIBILIDAD=$score
  ok "Accesibilidad score: $(score_color $score)"
}

# ─── DIMENSION 5: Seguridad ───────────────────────────────────────────────────
analyze_seguridad() {
  step "Analizando Seguridad"
  local score=100

  local domain="${URL#*://}"; domain="${domain%%/*}"

  # Hosting & dominio
  lookup_hosting_domain "$domain"

  # Headers
  local headers
  headers=$(fetch_headers "$URL")

  SEC_HSTS=false; echo "$headers" | grep -q "strict-transport-security" && SEC_HSTS=true || true
  SEC_CSP=false;  echo "$headers" | grep -q "content-security-policy"   && SEC_CSP=true  || true
  SEC_XCTO=false; echo "$headers" | grep -q "x-content-type-options"    && SEC_XCTO=true || true
  SEC_XFO=false;  echo "$headers" | grep -q "x-frame-options"           && SEC_XFO=true  || true
  SEC_RP=false;   echo "$headers" | grep -q "referrer-policy"           && SEC_RP=true   || true
  SEC_PER=false;  echo "$headers" | grep -q "permissions-policy"        && SEC_PER=true  || true

  # HSTS max-age value
  SEC_HSTS_MAXAGE=$(echo "$headers" | grep "strict-transport-security" \
    | grep -oE 'max-age=[0-9]+' | grep -oE '[0-9]+' | head -1 || echo "0")
  SEC_HSTS_MAXAGE=${SEC_HSTS_MAXAGE:-0}

  # CSP quality — detectar directivas inseguras
  SEC_CSP_UNSAFE=false
  echo "$headers" | grep "content-security-policy" | grep -qi "unsafe-inline\|unsafe-eval" \
    && SEC_CSP_UNSAFE=true || true

  # SRI en scripts externos
  SEC_SRI=false; echo "$HTML_CACHE" | grep -qi 'integrity="sha' && SEC_SRI=true || true

  # CAA y MX DNS records
  SEC_CAA="AUSENTE"; SEC_MX="AUSENTE"
  local caa_raw mx_raw
  caa_raw=$(if command -v dig &>/dev/null; then
    dig CAA "$domain" +short 2>/dev/null | head -1
  else
    curl -sSL --max-time 8 "https://dns.google/resolve?name=${domain}&type=CAA" 2>/dev/null \
      | perl -nle 'print $1 if /"data":"([^"]+)"/' | head -1
  fi || echo "")
  mx_raw=$(if command -v dig &>/dev/null; then
    dig MX "$domain" +short 2>/dev/null | head -1
  else
    curl -sSL --max-time 8 "https://dns.google/resolve?name=${domain}&type=MX" 2>/dev/null \
      | perl -nle 'print $1 if /"data":"([^"]+)"/' | head -1
  fi || echo "")
  [[ -n "$caa_raw" ]] && SEC_CAA="$caa_raw" || true
  [[ -n "$mx_raw"  ]] && SEC_MX="$mx_raw"   || true

  [[ "$SEC_HSTS" == false ]] && score=$((score-20)) || true
  [[ "$SEC_CSP"  == false ]] && score=$((score-20)) || true
  [[ "$SEC_XCTO" == false ]] && score=$((score-15)) || true
  [[ "$SEC_XFO"  == false ]] && score=$((score-15)) || true
  [[ "$SEC_RP"   == false ]] && score=$((score-10)) || true
  [[ "$SEC_PER"  == false ]] && score=$((score-10)) || true
  [[ "$SEC_CSP_UNSAFE" == true ]] && score=$((score-10)) || true

  local http_code
  http_code=$(http_status "http://${domain}")
  [[ "$http_code" == "301" || "$http_code" == "302" ]] && SEC_HTTPS_REDIRECT=true || SEC_HTTPS_REDIRECT=false
  [[ "$SEC_HTTPS_REDIRECT" == false ]] && score=$((score-15)) || true

  # SSL — llamar ssl_full_info directamente (no en subshell) para preservar variables
  info "Verificando SSL..."
  ssl_full_info "$domain" 2>/dev/null || true
  SEC_SSL_DAYS=${SSL_DAYS_LEFT:--1}
  if   (( SEC_SSL_DAYS < 0   )); then SEC_SSL_EXPIRY_NOTE="No se pudo verificar"
  elif (( SEC_SSL_DAYS == 0  )); then SEC_SSL_EXPIRY_NOTE="🔴 EXPIRADO";                              score=$((score-40))
  elif (( SEC_SSL_DAYS <= 7  )); then SEC_SSL_EXPIRY_NOTE="🔴 Expira en ${SEC_SSL_DAYS}d — URGENTE"; score=$((score-30))
  elif (( SEC_SSL_DAYS <= 30 )); then SEC_SSL_EXPIRY_NOTE="🟠 Expira en ${SEC_SSL_DAYS} días";        score=$((score-15))
  elif (( SEC_SSL_DAYS <= 90 )); then SEC_SSL_EXPIRY_NOTE="🟡 Expira en ${SEC_SSL_DAYS} días";        score=$((score-5))
  else                                SEC_SSL_EXPIRY_NOTE="🟢 Válido por ${SEC_SSL_DAYS} días"
  fi

  SEC_SSLCHECK_RESULT=""
  if [[ -n "$SSLCHECK_CMD" ]]; then
    info "Ejecutando ssl-checker..."
    SEC_SSLCHECK_RESULT=$($SSLCHECK_CMD "$domain" 2>/dev/null | head -3 || echo "")
  fi

  # Cookies
  local cookie_hdr
  cookie_hdr=$(echo "$headers" | grep "set-cookie" || echo "")
  SEC_COOKIE_SECURE=true; SEC_COOKIE_HTTPONLY=true
  if echo "$cookie_hdr" | grep -qi "set-cookie"; then
    echo "$cookie_hdr" | grep -qi "secure"   || SEC_COOKIE_SECURE=false
    echo "$cookie_hdr" | grep -qi "httponly" || SEC_COOKIE_HTTPONLY=false
  fi
  [[ "$SEC_COOKIE_SECURE"   == false ]] && score=$((score-10)) || true
  [[ "$SEC_COOKIE_HTTPONLY" == false ]] && score=$((score-10)) || true

  (( score < 0 )) && score=0; (( score > 100 )) && score=100
  set_score "seguridad" "$score"; SCORE_SEGURIDAD=$score
  ok "Seguridad score: $(score_color $score)"
}

# ─── DIMENSION 6: Ciberseguridad ──────────────────────────────────────────────
analyze_ciberseguridad() {
  step "Analizando Ciberseguridad"
  local score=100
  local domain="${URL#*://}"; domain="${domain%%/*}"

  local server_hdr
  server_hdr=$(fetch_headers "$URL" | grep "^server:" | head -1 | sed 's/server: //' | xargs || echo "")
  CYBER_SERVER="${server_hdr:-Oculto}"
  local powered_hdr
  powered_hdr=$(fetch_headers "$URL" | grep "x-powered-by:" | head -1 | xargs || echo "")
  CYBER_POWERED_BY="${powered_hdr:-Oculto}"

  echo "$CYBER_SERVER"    | grep -qE "[0-9]\.|apache|nginx|iis|php" && score=$((score-15)) || true
  [[ -n "$powered_hdr" ]] && score=$((score-10)) || true

  local dirs=("/admin" "/backup" "/.git" "/config" "/uploads" "/.env" "/wp-admin" "/phpinfo.php" "/swagger" "/api-docs")
  CYBER_EXPOSED_DIRS=()
  for d in "${dirs[@]}"; do
    local st; st=$(http_status "${URL%/}${d}")
    [[ "$st" == "200" ]] && CYBER_EXPOSED_DIRS+=("$d") && score=$((score-10)) || true
  done
  [[ ${#CYBER_EXPOSED_DIRS[@]} -eq 0 ]] && CYBER_EXPOSED_DIRS=("Ninguno detectado")

  local sec_txt_status sec_txt_contact
  sec_txt_status=$(http_status "${URL%/}/.well-known/security.txt")
  CYBER_SEC_TXT="$sec_txt_status"
  if [[ "$sec_txt_status" == "200" ]]; then
    sec_txt_contact=$(fetch_url "${URL%/}/.well-known/security.txt" | grep -i "^contact:" | head -1 | sed 's/Contact:\s*//' | xargs 2>/dev/null) || sec_txt_contact=""
    CYBER_SEC_TXT_CONTACT="${sec_txt_contact:-No especificado}"
  else
    score=$((score-5))
    CYBER_SEC_TXT_CONTACT="—"
  fi

  CYBER_SPF="No verificable"; CYBER_DMARC="No verificable"
  # dig → curl DNS API fallback (funciona en Git Bash/Windows)
  dns_txt_lookup() {
    local host="$1"
    if command -v dig &>/dev/null; then
      dig TXT "$host" +short 2>/dev/null | tr -d '"' || echo ""
    else
      curl -sSL --max-time 10 \
        "https://dns.google/resolve?name=${host}&type=TXT" 2>/dev/null \
        | perl -nle 'print $1 if /"data":"([^"]+)"/' || echo ""
    fi
  }
  spf_raw=$(dns_txt_lookup "$domain")
  dmarc_raw=$(dns_txt_lookup "_dmarc.${domain}")
  dkim_raw=$(dns_txt_lookup "default._domainkey.${domain}")
  bimi_raw=$(dns_txt_lookup "default._bimi.${domain}")
  CYBER_SPF=$(echo "$spf_raw"    | grep -i "v=spf"   | head -1 || echo "AUSENTE")
  CYBER_DMARC=$(echo "$dmarc_raw"| grep -i "v=DMARC" | head -1 || echo "AUSENTE")
  CYBER_DKIM=$(echo "$dkim_raw"  | grep -i "v=DKIM"  | head -1 || echo "AUSENTE")
  CYBER_BIMI=$(echo "$bimi_raw"  | grep -i "v=BIMI"  | head -1 || echo "AUSENTE")
  [[ -z "$CYBER_SPF"   ]] && CYBER_SPF="AUSENTE"
  [[ -z "$CYBER_DMARC" ]] && CYBER_DMARC="AUSENTE"
  [[ -z "$CYBER_DKIM"  ]] && CYBER_DKIM="AUSENTE"
  [[ "$CYBER_SPF"   == "AUSENTE" ]] && score=$((score-10)) || true
  [[ "$CYBER_DMARC" == "AUSENTE" ]] && score=$((score-10)) || true
  [[ "$CYBER_DKIM"  == "AUSENTE" ]] && score=$((score-5))  || true

  (( score < 0 )) && score=0; (( score > 100 )) && score=100
  set_score "ciberseguridad" "$score"; SCORE_CIBERSEGURIDAD=$score
  ok "Ciberseguridad score: $(score_color $score)"
}

# ─── DIMENSION 7: Diseño ──────────────────────────────────────────────────────
analyze_diseno() {
  step "Analizando Diseño"
  local score=70
  local html
  html="$HTML_CACHE"

  DIS_VIEWPORT=false; grep -qi 'name="viewport"' <<< "$html" && DIS_VIEWPORT=true || true
  [[ "$DIS_VIEWPORT" == false ]] && score=$((score-20)) || true

  DIS_FRAMEWORKS=()
  grep -qi "bootstrap" <<< "$html"   && DIS_FRAMEWORKS+=("Bootstrap")   || true
  grep -qi "tailwind" <<< "$html"    && DIS_FRAMEWORKS+=("Tailwind CSS") || true
  grep -qi "materialize" <<< "$html" && DIS_FRAMEWORKS+=("Materialize")  || true
  grep -qi "foundation" <<< "$html"  && DIS_FRAMEWORKS+=("Foundation")   || true
  [[ ${#DIS_FRAMEWORKS[@]} -eq 0 ]] && DIS_FRAMEWORKS=("CSS propio")

  DIS_FONTS=false;     grep -qi "fonts.googleapis\|font-face" <<< "$html"        && DIS_FONTS=true     || true
  DIS_FAVICON=false;   grep -qi 'rel="icon"\|rel="shortcut icon"' <<< "$html"    && DIS_FAVICON=true   || true
  DIS_DARK_MODE=false; grep -qi "prefers-color-scheme\|color-scheme" <<< "$html" && DIS_DARK_MODE=true || true
  [[ "$DIS_FAVICON" == false ]] && score=$((score-5)) || true

  DIS_PRINT_CSS=false;  grep -qi 'media="print"' <<< "$html"                     && DIS_PRINT_CSS=true  || true
  DIS_FAVICON_HI=false; grep -qi '192x192\|512x512\|apple-touch-icon' <<< "$html" && DIS_FAVICON_HI=true || true
  DIS_BREAKPOINTS=$(echo "$html" | grep -oiE '@media[^{]+' | wc -l | tr -d '[:space:]') || DIS_BREAKPOINTS=0
  DIS_BREAKPOINTS=${DIS_BREAKPOINTS:-0}

  run_lighthouse
  DIS_LH_MOBILE=$(lh_score "best-practices" "mobile")
  DIS_LH_DESKTOP=$(lh_score "best-practices" "desktop")
  if [[ -n "$DIS_LH_MOBILE" && -n "$DIS_LH_DESKTOP" ]]; then
    score=$(( (score + DIS_LH_MOBILE + DIS_LH_DESKTOP) / 3 ))
  elif [[ -n "$DIS_LH_MOBILE" ]]; then
    score=$(( (score + DIS_LH_MOBILE) / 2 ))
  elif [[ -n "$DIS_LH_DESKTOP" ]]; then
    score=$(( (score + DIS_LH_DESKTOP) / 2 ))
  fi

  (( score < 0 )) && score=0; (( score > 100 )) && score=100
  set_score "diseno" "$score"; SCORE_DISENO=$score
  ok "Diseño score: $(score_color $score)"
}

# ─── Tecnología: fingerprinting bash + webanalyze opcional ───────────────────
analyze_tecnologia() {
  step "Detectando stack tecnológico"
  local html="$HTML_CACHE"
  local headers
  headers=$(fetch_headers "$URL")

  TECH_CMS="Desconocido"
  grep -qi 'wp-content\|wp-includes\|<meta[^>]*generator[^>]*WordPress' <<< \"$html\" && TECH_CMS="WordPress"   || true
  grep -qi 'cdn\.shopify\.com\|Shopify\.theme' <<< \"$html\"                           && TECH_CMS="Shopify"     || true
  grep -qi 'wix\.com\|X-Wix-Published-Version' <<< \"$html\"                           && TECH_CMS="Wix"         || true
  grep -qi 'webflow\.io\|data-wf-site' <<< \"$html\"                                   && TECH_CMS="Webflow"     || true
  grep -qi 'squarespace\.com\|Squarespace' <<< \"$html\"                                && TECH_CMS="Squarespace" || true
  grep -qi 'sites\.google\.com\|<meta[^>]*generator[^>]*Drupal' <<< \"$html\"          && TECH_CMS="Drupal"      || true
  grep -qi 'ghost\.io\|content=\"Ghost' <<< \"$html\"                                  && TECH_CMS="Ghost"       || true
  grep -qi 'notion\.so\|notion-page' <<< \"$html\"                                     && TECH_CMS="Notion"      || true

  TECH_FRAMEWORK="Desconocido"
  grep -qi '__NEXT_DATA__\|/_next/' <<< \"$html\"                                       && TECH_FRAMEWORK="Next.js"  || true
  grep -qi '__nuxt\|/_nuxt/' <<< \"$html\"                                              && TECH_FRAMEWORK="Nuxt"     || true
  grep -qi 'data-reactroot\|__REACT_DEVTOOLS' <<< \"$html\"                            && TECH_FRAMEWORK="React"    || true
  grep -qi 'data-v-\|vue\.config' <<< \"$html\"                                        && TECH_FRAMEWORK="Vue"      || true
  grep -qi 'ng-version\|_nghost\|angular' <<< \"$html\"                                && TECH_FRAMEWORK="Angular"  || true
  grep -qi 'svelte\|__svelte' <<< \"$html\"                                            && TECH_FRAMEWORK="Svelte"   || true
  grep -qi 'astro\|data-astro' <<< \"$html\"                                           && TECH_FRAMEWORK="Astro"    || true
  grep -qi 'remix\.run\|__remixContext' <<< \"$html\"                                  && TECH_FRAMEWORK="Remix"    || true

  TECH_ANALYTICS=()
  grep -qi 'gtag\|google-analytics\|analytics\.js' <<< \"$html\"  && TECH_ANALYTICS+=("Google Analytics") || true
  grep -qi 'googletagmanager' <<< \"$html\"                        && TECH_ANALYTICS+=("Google Tag Manager") || true
  grep -qi 'fbevents\|fbq(\|facebook\.net\|connect\.facebook' <<< "$html" && TECH_ANALYTICS+=("Meta Pixel") || true
  grep -qi 'hotjar' <<< \"$html\"                                  && TECH_ANALYTICS+=("Hotjar") || true
  grep -qi 'mixpanel' <<< \"$html\"                                && TECH_ANALYTICS+=("Mixpanel") || true
  grep -qi 'segment\.com\|analytics\.js' <<< \"$html\"            && TECH_ANALYTICS+=("Segment") || true
  grep -qi 'plausible' <<< \"$html\"                               && TECH_ANALYTICS+=("Plausible") || true
  [[ ${#TECH_ANALYTICS[@]} -eq 0 ]] && TECH_ANALYTICS=("Ninguno detectado")

  TECH_SERVER=$(echo "$headers" | grep "^server:" | head -1 | sed 's/server: //' | xargs || echo "Oculto")
  TECH_LANGUAGE="Desconocido"
  echo "$headers" | grep -qi "x-powered-by: php"    && TECH_LANGUAGE="PHP"    || true
  echo "$headers" | grep -qi "x-powered-by: asp"    && TECH_LANGUAGE=".NET"   || true
  echo "$headers" | grep -qi "x-powered-by: express\|node" && TECH_LANGUAGE="Node.js" || true
  local phpsess; phpsess=$(echo "$headers" | grep "set-cookie" | grep -i "PHPSESSID" || echo "")
  [[ -n "$phpsess" ]] && TECH_LANGUAGE="PHP" || true

  TECH_CDN="${PERF_CDN:-No detectado}"

  # webanalyze si está disponible
  TECH_WEBANALYZE=""
  if command -v webanalyze &>/dev/null; then
    info "Ejecutando webanalyze..."
    TECH_WEBANALYZE=$(webanalyze -host "$URL" 2>/dev/null | head -20 || echo "")
    [[ -n "$TECH_WEBANALYZE" ]] && ok "webanalyze completado" || true
  fi

  ok "Stack tecnológico detectado"
}

# ─── DIMENSION 8: UX ──────────────────────────────────────────────────────────
analyze_ux() {
  step "Analizando UX"
  local score=70
  local html
  html="$HTML_CACHE"

  UX_NAV=false;       grep -qi '<nav\|role="navigation"' <<< "$html"             && UX_NAV=true       || true
  UX_SEARCH=false;    grep -qi 'type="search"\|input.*search' <<< "$html"         && UX_SEARCH=true    || true
  UX_CONTACT=false;   grep -qi 'contact\|contacto\|mailto:\|tel:' <<< "$html"    && UX_CONTACT=true   || true
  UX_CTA=false;       grep -qi 'btn\|button\|comprar\|registr\|sign' <<< "$html" && UX_CTA=true       || true
  UX_RESPONSIVE=false;grep -qi "@media\|max-width:\|min-width:" <<< "$html"      && UX_RESPONSIVE=true|| true
  UX_LOADING=false;   grep -qi "loading\|spinner\|skeleton" <<< "$html"          && UX_LOADING=true   || true

  [[ "$UX_NAV"       == false ]] && score=$((score-15)) || true
  [[ "$UX_CTA"       == false ]] && score=$((score-15)) || true
  [[ "$UX_CONTACT"   == false ]] && score=$((score-10)) || true
  [[ "$UX_RESPONSIVE" == false ]] && score=$((score-20)) || true

  UX_404=$(http_status "${URL%/}/pagina-que-no-existe-audit-xyz123")
  [[ "$UX_404" != "404" ]] && score=$((score-10)) || true

  UX_500=$(http_status "${URL%/}/error-500-audit-xyz")
  UX_BREADCRUMBS=false; grep -qi 'breadcrumb\|aria-label.*breadcrumb' <<< "$html" && UX_BREADCRUMBS=true || true
  UX_SOCIAL=false;      grep -qi 'twitter\.com\|linkedin\.com\|instagram\.com\|facebook\.com' <<< "$html" && UX_SOCIAL=true || true
  UX_CHAT=false;        grep -qi 'intercom\|drift\|zendesk\|crisp\|tidio\|freshchat' <<< "$html" && UX_CHAT=true || true
  UX_FORM_VALIDATION=false; grep -qi 'required\|pattern=\|minlength=' <<< "$html" && UX_FORM_VALIDATION=true || true
  UX_LANG_SWITCH=false; grep -qi 'lang-switch\|language-selector\|idioma\|hreflang' <<< "$html" && UX_LANG_SWITCH=true || true

  (( score < 0 )) && score=0; (( score > 100 )) && score=100
  set_score "ux" "$score"; SCORE_UX=$score
  ok "UX score: $(score_color $score)"
}

# ─── Legal & Privacidad ───────────────────────────────────────────────────────
analyze_legal() {
  step "Analizando Legal & Privacidad"
  local html
  html="$HTML_CACHE"

  LEGAL_PRIVACY=false; grep -qi "privacy\|privacidad\|política" <<< "$html"          && LEGAL_PRIVACY=true || true
  LEGAL_TERMS=false;   grep -qi "terms\|condiciones\|aviso.legal" <<< "$html"         && LEGAL_TERMS=true   || true
  LEGAL_COOKIES=false; grep -qi "cookie\|gdpr\|rgpd\|consent" <<< "$html"             && LEGAL_COOKIES=true || true
  LEGAL_GDPR=false;    grep -qi "gdpr\|rgpd\|reglamento.*datos" <<< "$html"           && LEGAL_GDPR=true    || true

  LEGAL_TRACKERS=()
  grep -qi "google-analytics\|gtag\|ga.js" <<< "$html" && LEGAL_TRACKERS+=("Google Analytics") || true
  grep -qi "facebook\|fbevents\|fbq(" <<< "$html"      && LEGAL_TRACKERS+=("Facebook Pixel")   || true
  grep -qi "hotjar" <<< "$html"                         && LEGAL_TRACKERS+=("Hotjar")           || true
  grep -qi "mixpanel" <<< "$html"                       && LEGAL_TRACKERS+=("Mixpanel")         || true
  grep -qi "segment" <<< "$html"                        && LEGAL_TRACKERS+=("Segment")          || true
  grep -qi "hubspot" <<< "$html"                        && LEGAL_TRACKERS+=("HubSpot")          || true
  [[ ${#LEGAL_TRACKERS[@]} -eq 0 ]] && LEGAL_TRACKERS=("Ninguno detectado")
}

# ─── Score global ─────────────────────────────────────────────────────────────
compute_global_score() {
  local total=0 weight_sum=0
  local keys="performance:20 seo:15 accesibilidad:15 seguridad:15 ciberseguridad:10 calidad_tecnica:10 diseno:8 ux:7"
  for pair in $keys; do
    local key="${pair%%:*}" w="${pair##*:}"
    local s; s=$(get_score "$key")
    total=$(( total + s * w ))
    weight_sum=$(( weight_sum + w ))
  done
  (( weight_sum > 0 )) && SCORE_GLOBAL=$(( total / weight_sum )) || SCORE_GLOBAL=0
}

# ─── Previous report ──────────────────────────────────────────────────────────
find_previous_report() {
  local slug="$1"
  PREV_REPORT=""
  [[ -n "$COMPARE_FILE" && -f "$COMPARE_FILE" ]] && { PREV_REPORT="$COMPARE_FILE"; return; }
  PREV_REPORT=$(ls -t "${OUTPUT_DIR}/reporte-${slug}-"*.md 2>/dev/null | sed -n '2p') || PREV_REPORT=""
}

extract_prev_score() {
  local report="$1" dimension="$2"
  grep -i "| ${dimension}" "$report" 2>/dev/null | grep -oE '[0-9]+' | head -1 || echo "N/A"
}

score_delta() {
  local prev="$1" curr="$2"
  [[ "$prev" == "N/A" || -z "$prev" ]] && { echo "—"; return; }
  local diff=$(( curr - prev ))
  if   (( diff > 0 )); then echo "+${diff} 🟢"
  elif (( diff < 0 )); then echo "${diff} 🔴"
  else echo "= 🟡"
  fi
}

# ─── Generate report ──────────────────────────────────────────────────────────
generate_report() {
  local out_file="$1" prev_report="${2:-}"
  local domain="${URL#*://}"; domain="${domain%%/*}"
  local global_badge; global_badge=$(score_badge "$SCORE_GLOBAL")

  # Pre-computar benchmarks por sector (fuera del heredoc)
  local bp bs ba bsec bcy bct bd bu tp ts ta tsec tcy tct td tu
  case "${SECTOR:-general}" in
    ecommerce) bp=72 bs=75 ba=58 bsec=55 bcy=50 bct=65 bd=70 bu=75
               tp=92 ts=92 ta=85 tsec=88 tcy=82 tct=88 td=92 tu=92 ;;
    saas)      bp=70 bs=68 ba=60 bsec=65 bcy=58 bct=70 bd=65 bu=70
               tp=92 ts=88 ta=88 tsec=92 tcy=85 tct=90 td=88 tu=90 ;;
    blog)      bp=68 bs=80 ba=55 bsec=48 bcy=42 bct=62 bd=60 bu=62
               tp=90 ts=95 ta=82 tsec=80 tcy=75 tct=85 td=85 tu=85 ;;
    landing)   bp=75 bs=70 ba=55 bsec=50 bcy=45 bct=60 bd=72 bu=78
               tp=95 ts=90 ta=82 tsec=85 tcy=80 tct=85 td=92 tu=92 ;;
    portfolio) bp=65 bs=65 ba=55 bsec=48 bcy=42 bct=62 bd=80 bu=70
               tp=90 ts=85 ta=82 tsec=80 tcy=75 tct=85 td=95 tu=90 ;;
    *)         bp=65 bs=70 ba=55 bsec=50 bcy=45 bct=60 bd=65 bu=60
               tp=90 ts=90 ta=85 tsec=90 tcy=85 tct=85 td=90 tu=88 ;;
  esac

  # Pre-computar íconos de variables con posibles caracteres especiales (evita word-splitting en [ ] dentro del heredoc)
  local ic_seo_title ic_seo_meta ic_seo_h1 ic_seo_og ic_seo_twitter ic_seo_schema ic_seo_hreflang
  local rec_seo_title rec_seo_meta rec_seo_robots rec_seo_sitemap rec_seo_schema
  [[ "$SEO_TITLE"    == "AUSENTE" ]] && ic_seo_title="❌"  || ic_seo_title="✅"
  [[ "$SEO_META_DESC" == "AUSENTE" ]] && ic_seo_meta="❌"  || ic_seo_meta="✅"
  (( ${SEO_H1_COUNT:-0} == 1 ))      && ic_seo_h1="✅"     || ic_seo_h1="⚠️"
  [[ "$SEO_OG"          == "true" ]] && ic_seo_og="✅"      || ic_seo_og="❌"
  [[ "$SEO_TWITTER_CARD" == "true" ]] && ic_seo_twitter="✅" || ic_seo_twitter="❌"
  [[ "$SEO_SCHEMA"      == "true" ]] && ic_seo_schema="✅"  || ic_seo_schema="❌"
  [[ "$SEO_HREFLANG"    == "true" ]] && ic_seo_hreflang="✅" || ic_seo_hreflang="➖"

  [[ "$SEO_TITLE"    == "AUSENTE" ]] && rec_seo_title="🔴 CRÍTICO: Añadir \`<title>\` único (30-60 chars)" || rec_seo_title="Title tag presente ✓"
  [[ "$SEO_META_DESC" == "AUSENTE" ]] && rec_seo_meta="🟠 ALTO: Crear meta description (120-160 chars)"   || rec_seo_meta="Meta description presente ✓"
  [[ "$SEO_ROBOTS"   != "200"     ]] && rec_seo_robots="🟡 MEDIO: Crear robots.txt en la raíz"            || rec_seo_robots="robots.txt encontrado ✓"
  [[ "$SEO_SITEMAP"  != "200"     ]] && rec_seo_sitemap="🟡 MEDIO: Generar sitemap.xml y registrar en Search Console" || rec_seo_sitemap="sitemap.xml encontrado ✓"
  [[ "$SEO_SCHEMA"   != "true"    ]] && rec_seo_schema="🟡 MEDIO: Implementar Schema.org para rich snippets"         || rec_seo_schema="Schema.org implementado ✓"

  cat > "$out_file" << MDEOF
# 🔍 Auditoría Web Profesional — ${domain}

> **Generado por:** [homium-audit](https://github.com/homium-tech/audit) v${SCRIPT_VERSION}
> **Fecha:** ${DATE_HUMAN}
> **URL:** ${URL}

---

## 📋 Resumen Ejecutivo

$(if (( SCORE_GLOBAL >= 80 )); then
  echo "El sitio **${domain}** presenta un estado **satisfactorio**. Se recomienda priorizar las acciones de alto impacto antes del próximo ciclo de revisión."
elif (( SCORE_GLOBAL >= 60 )); then
  echo "El sitio **${domain}** presenta un estado **aceptable** con áreas de mejora importantes. Existen brechas que pueden impactar conversión, posicionamiento y seguridad."
else
  echo "El sitio **${domain}** presenta **deficiencias significativas** que requieren atención inmediata con impacto directo en negocio, reputación y cumplimiento legal."
fi)

| Indicador | Valor |
|-----------|-------|
| **Score Global** | ${global_badge} **${SCORE_GLOBAL} / 100** |
| **URL** | \`${URL}\` |
| **Fecha** | ${DATE_HUMAN} |

\`\`\`
Performance      $(ascii_bar $SCORE_PERFORMANCE) ${SCORE_PERFORMANCE}/100
SEO              $(ascii_bar $SCORE_SEO)          ${SCORE_SEO}/100
Accesibilidad    $(ascii_bar $SCORE_ACCESIBILIDAD) ${SCORE_ACCESIBILIDAD}/100
Seguridad        $(ascii_bar $SCORE_SEGURIDAD)    ${SCORE_SEGURIDAD}/100
Ciberseguridad   $(ascii_bar $SCORE_CIBERSEGURIDAD) ${SCORE_CIBERSEGURIDAD}/100
Calidad Técnica  $(ascii_bar $SCORE_CALIDAD_TECNICA) ${SCORE_CALIDAD_TECNICA}/100
Diseño           $(ascii_bar $SCORE_DISENO)       ${SCORE_DISENO}/100
UX               $(ascii_bar $SCORE_UX)           ${SCORE_UX}/100
\`\`\`

$(if [[ -n "${SCREENSHOT_MOBILE:-}" || -n "${SCREENSHOT_DESKTOP:-}" ]]; then
echo "### 📸 Capturas de Pantalla"
echo ""
[ -n "${SCREENSHOT_MOBILE:-}"  ] && echo "**📱 Mobile**" && echo "![Mobile](${SCREENSHOT_MOBILE})" && echo ""
[ -n "${SCREENSHOT_DESKTOP:-}" ] && echo "**🖥️ Desktop**" && echo "![Desktop](${SCREENSHOT_DESKTOP})" && echo ""
echo "---"
echo ""
fi)

## 📊 Scores por Dimensión

| Dimensión | Score | Estado |
|-----------|------:|--------|
| ⚡ Performance     | **${SCORE_PERFORMANCE}/100**     | $(score_badge $SCORE_PERFORMANCE) |
| 🔍 SEO             | **${SCORE_SEO}/100**             | $(score_badge $SCORE_SEO) |
| ♿ Accesibilidad   | **${SCORE_ACCESIBILIDAD}/100**   | $(score_badge $SCORE_ACCESIBILIDAD) |
| 🔒 Seguridad       | **${SCORE_SEGURIDAD}/100**       | $(score_badge $SCORE_SEGURIDAD) |
| 🛡️ Ciberseguridad | **${SCORE_CIBERSEGURIDAD}/100**  | $(score_badge $SCORE_CIBERSEGURIDAD) |
| ⚙️ Calidad Técnica | **${SCORE_CALIDAD_TECNICA}/100** | $(score_badge $SCORE_CALIDAD_TECNICA) |
| 🎨 Diseño          | **${SCORE_DISENO}/100**          | $(score_badge $SCORE_DISENO) |
| 👤 UX              | **${SCORE_UX}/100**              | $(score_badge $SCORE_UX) |

---

## 🏆 Benchmarking $([ -n "${SECTOR:-}" ] && echo "— Sector: ${SECTOR}")

| Dimensión | Tu sitio | Promedio sector | Top 10% |
|-----------|:--------:|:--------------:|:-------:|
| Performance | ${SCORE_PERFORMANCE} | ${bp} | ${tp}+ |
| SEO | ${SCORE_SEO} | ${bs} | ${ts}+ |
| Accesibilidad | ${SCORE_ACCESIBILIDAD} | ${ba} | ${ta}+ |
| Seguridad | ${SCORE_SEGURIDAD} | ${bsec} | ${tsec}+ |
| Ciberseguridad | ${SCORE_CIBERSEGURIDAD} | ${bcy} | ${tcy}+ |
| Calidad Técnica | ${SCORE_CALIDAD_TECNICA} | ${bct} | ${tct}+ |
| Diseño | ${SCORE_DISENO} | ${bd} | ${td}+ |
| UX | ${SCORE_UX} | ${bu} | ${tu}+ |

---

$(if [[ "$LH_DONE_MOBILE" == true || "$LH_DONE_DESKTOP" == true ]]; then
cat << LHMD
## 🔦 Lighthouse — Mobile vs Desktop

| Categoría | 📱 Mobile | 🖥️ Desktop | Diferencia |
|-----------|:---------:|:----------:|:----------:|
| Performance | ${PERF_LH_MOBILE:-N/A} | ${PERF_LH_DESKTOP:-N/A} | $([ -n "${PERF_LH_MOBILE:-}" ] && [ -n "${PERF_LH_DESKTOP:-}" ] && score_delta "$PERF_LH_MOBILE" "$PERF_LH_DESKTOP" || echo "—") |
| SEO | ${SEO_LH_MOBILE:-N/A} | ${SEO_LH_DESKTOP:-N/A} | $([ -n "${SEO_LH_MOBILE:-}" ] && [ -n "${SEO_LH_DESKTOP:-}" ] && score_delta "$SEO_LH_MOBILE" "$SEO_LH_DESKTOP" || echo "—") |
| Accesibilidad | ${ACC_LH_MOBILE:-N/A} | ${ACC_LH_DESKTOP:-N/A} | $([ -n "${ACC_LH_MOBILE:-}" ] && [ -n "${ACC_LH_DESKTOP:-}" ] && score_delta "$ACC_LH_MOBILE" "$ACC_LH_DESKTOP" || echo "—") |
| Best Practices | ${DIS_LH_MOBILE:-N/A} | ${DIS_LH_DESKTOP:-N/A} | $([ -n "${DIS_LH_MOBILE:-}" ] && [ -n "${DIS_LH_DESKTOP:-}" ] && score_delta "$DIS_LH_MOBILE" "$DIS_LH_DESKTOP" || echo "—") |

> 📱 Mobile simula una conexión 4G lenta con CPU reducida. 🖥️ Desktop usa condiciones de red y hardware estándar. Una diferencia grande entre ambos indica oportunidades de optimización móvil.

---
LHMD
fi)

## 🔎 Hallazgos por Dimensión

### ⚡ 1. Performance — ${SCORE_PERFORMANCE}/100 $(score_badge $SCORE_PERFORMANCE)

| Hallazgo | Valor | Severidad |
|----------|-------|-----------|
| Tiempo de respuesta | ${PERF_RESP_MS}ms | $(severity_badge ${PERF_RESP_SEVERITY:-bajo}) |
| TTFB | ${PERF_TTFB_MS:-N/A}ms | $([ "${PERF_TTFB_MS:-0}" -gt 600 ] && echo "🟠 ALTO" || echo "🟢 BAJO") |
| Redirects | ${PERF_REDIRECTS:-0} | $([ "${PERF_REDIRECTS:-0}" -gt 2 ] && echo "🟡 MEDIO" || echo "🟢 OK") |
| CDN | ${PERF_CDN:-No detectado} | $([ "${PERF_CDN:-No detectado}" != "No detectado" ] && echo "🟢 OK" || echo "🟡 MEDIO") |
| Tamaño HTML | ${PERF_SIZE_KB}KB | $([ ${PERF_SIZE_KB:-0} -gt 200 ] && echo "🟡 MEDIO" || echo "🟢 BAJO") |
| Scripts JS | ${PERF_JS_COUNT:-0} | $([ "${PERF_JS_COUNT:-0}" -gt 20 ] && echo "🟡 MEDIO" || echo "🟢 OK") |
| Hojas CSS | ${PERF_CSS_COUNT:-0} | $([ "${PERF_CSS_COUNT:-0}" -gt 10 ] && echo "🟡 MEDIO" || echo "🟢 OK") |
| Imágenes | ${PERF_IMG_COUNT:-0} | — |
| Protocolo | ${PERF_PROTOCOL} | $(echo "$PERF_PROTOCOL" | grep -q "2\|3" && echo "🟢 OK" || echo "🟡 MEDIO") |
| Compresión | $(echo "$PERF_COMPRESSION" | grep -qi "gzip\|br\|deflate" && echo "✅ Activa" || echo "❌ Inactiva") | $(echo "$PERF_COMPRESSION" | grep -qi "gzip\|br\|deflate" && echo "🟢 OK" || echo "🟡 MEDIO") |
$([ -n "${PERF_LH_MOBILE:-}" ] && echo "| Lighthouse 📱 Mobile | ${PERF_LH_MOBILE}/100 | — |")
$([ -n "${PERF_LH_DESKTOP:-}" ] && echo "| Lighthouse 🖥️ Desktop | ${PERF_LH_DESKTOP}/100 | — |")

$(if [[ "$LH_DONE_MOBILE" == true || "$LH_DONE_DESKTOP" == true ]]; then
echo "**Core Web Vitals:**"
echo ""
echo "| Métrica | 📱 Mobile | 🖥️ Desktop |"
echo "|---------|:---------:|:----------:|"
echo "| LCP (Largest Contentful Paint) | $(lh_metric 'largest-contentful-paint' 'mobile') | $(lh_metric 'largest-contentful-paint' 'desktop') |"
echo "| FCP (First Contentful Paint) | $(lh_metric 'first-contentful-paint' 'mobile') | $(lh_metric 'first-contentful-paint' 'desktop') |"
echo "| TBT (Total Blocking Time) | $(lh_metric 'total-blocking-time' 'mobile') | $(lh_metric 'total-blocking-time' 'desktop') |"
echo "| CLS (Cumulative Layout Shift) | $(lh_metric 'cumulative-layout-shift' 'mobile') | $(lh_metric 'cumulative-layout-shift' 'desktop') |"
echo "| Speed Index | $(lh_metric 'speed-index' 'mobile') | $(lh_metric 'speed-index' 'desktop') |"
fi)

**💡 Recomendaciones:**
- $([ "${PERF_RESP_SEVERITY:-bajo}" != "bajo" ] && echo "🟠 Optimizar TTFB a <600ms (CDN, caché de servidor, optimización de base de datos)" || echo "Tiempo de respuesta óptimo ✓")
- $([ "${PERF_CDN:-No detectado}" == "No detectado" ] && echo "🟡 Implementar CDN para reducir latencia geográfica y tiempo de carga" || echo "CDN activo ✓")
- $(echo "$PERF_PROTOCOL" | grep -q "2\|3" && echo "Protocolo HTTP/2+ activo ✓" || echo "🟡 Migrar a HTTP/2 o HTTP/3 — multiplexación de requests paralelos")
- $(echo "$PERF_COMPRESSION" | grep -qi "gzip\|br\|deflate" && echo "Compresión activa ✓" || echo "🟡 Activar compresión Gzip/Brotli — reduce el tamaño de transferencia hasta un 70%")
- $([ "${PERF_JS_COUNT:-0}" -gt 20 ] && echo "🟡 Consolidar o diferir scripts JS (${PERF_JS_COUNT} detectados) — cada request adicional suma latencia" || echo "Cantidad de scripts JS aceptable ✓")

---

### 🔍 2. SEO — ${SCORE_SEO}/100 $(score_badge $SCORE_SEO)

| Elemento | Estado | Detalle |
|----------|--------|---------|
$([ -n "${SITE_OG_IMAGE:-}" ] && echo "![Vista previa](${SITE_OG_IMAGE})" || true)

| Elemento | Estado | Detalle |
|----------|--------|---------|
| \`<title>\` | ${ic_seo_title} | ${SEO_TITLE:0:60} (${SEO_TITLE_LEN} chars) |
| Meta description | ${ic_seo_meta} | ${SEO_META_DESC_LEN} chars |
| Meta robots | ℹ️ | ${SEO_META_ROBOTS} |
| H1 | ${ic_seo_h1} | ${SEO_H1_COUNT:-0} encontrados |
| H2 / H3 | ℹ️ | ${SEO_H2_COUNT:-0} H2 · ${SEO_H3_COUNT:-0} H3 |
| Open Graph | ${ic_seo_og} | — |
| Twitter/X Card | ${ic_seo_twitter} | — |
| Schema.org | ${ic_seo_schema} | ${SEO_SCHEMA_TYPES:-N/A} |
| hreflang | ${ic_seo_hreflang} | — |
| Links internos / externos | ℹ️ | ${SEO_INT_LINKS:-0} internos · ${SEO_EXT_LINKS:-0} externos |
| robots.txt | $([ "$SEO_ROBOTS" == "200" ] && echo "✅" || echo "❌") | HTTP ${SEO_ROBOTS} |
| sitemap.xml | $([ "$SEO_SITEMAP" == "200" ] && echo "✅" || echo "❌") | HTTP ${SEO_SITEMAP} |
$([ -n "${SEO_LH_MOBILE:-}" ] && echo "| Lighthouse SEO 📱 Mobile | ✅ ${SEO_LH_MOBILE}/100 | — |")
$([ -n "${SEO_LH_DESKTOP:-}" ] && echo "| Lighthouse SEO 🖥️ Desktop | ✅ ${SEO_LH_DESKTOP}/100 | — |")

**💡 Recomendaciones:**
- ${rec_seo_title}
- ${rec_seo_meta}
- ${rec_seo_robots}
- ${rec_seo_sitemap}
- ${rec_seo_schema}

---

### ♿ 3. Accesibilidad — ${SCORE_ACCESIBILIDAD}/100 $(score_badge $SCORE_ACCESIBILIDAD)

| Elemento | Estado | Detalle |
|----------|--------|---------|
| Imágenes con alt | $([ "${ACC_IMGS_NO_ALT:-0}" -eq 0 ] && echo "✅" || echo "⚠️") | ${ACC_IMGS_TOTAL:-0} imgs · ${ACC_IMGS_NO_ALT:-0} sin alt |
| ARIA labels | $([ "$ACC_ARIA" == "true" ] && echo "✅" || echo "❌") | — |
| Skip navigation | $([ "$ACC_SKIP" == "true" ] && echo "✅" || echo "❌") | — |
| Formularios/Labels | $([ "${ACC_FORMS:-0}" -eq 0 ] || [ "${ACC_LABELS:-0}" -ge "${ACC_FORMS:-0}" ] && echo "✅" || echo "⚠️") | ${ACC_FORMS:-0} forms · ${ACC_LABELS:-0} labels |
$([ -n "${ACC_LH_MOBILE:-}" ] && echo "| Lighthouse A11y 📱 Mobile | ✅ ${ACC_LH_MOBILE}/100 | — |")
$([ -n "${ACC_LH_DESKTOP:-}" ] && echo "| Lighthouse A11y 🖥️ Desktop | ✅ ${ACC_LH_DESKTOP}/100 | — |")
$([ "${ACC_AXE_VIOLATIONS:-0}" -gt 0 ] && echo "| axe-core violations | ⚠️ ${ACC_AXE_VIOLATIONS} | ${ACC_AXE_SERIOUS:-0} críticas/serias |" || echo "| axe-core | ✅ Sin violations | — |")
$([ "${ACC_PA11Y_ERRORS:-0}" -gt 0 ] && echo "| pa11y errores | ⚠️ ${ACC_PA11Y_ERRORS} | ${ACC_PA11Y_WARNINGS:-0} warnings |" || echo "| pa11y | ✅ Sin errores | — |")

**💡 Recomendaciones:**
- $([ "$ACC_ARIA" != "true" ] && echo "🟠 ALTO: Implementar atributos ARIA en componentes interactivos" || echo "ARIA labels presentes ✓")
- $([ "$ACC_SKIP" != "true" ] && echo "🟡 MEDIO: Añadir 'Skip to main content' para usuarios de teclado" || echo "Skip navigation presente ✓")
- $([ "${ACC_IMGS_NO_ALT:-0}" -gt 0 ] && echo "🟠 ALTO: Añadir alt descriptivo a ${ACC_IMGS_NO_ALT} imagen(es)" || echo "Todas las imágenes tienen alt ✓")
- Verificar ratios de contraste (mínimo 4.5:1 para texto normal — WCAG AA)

---

### 🔒 4. Seguridad — ${SCORE_SEGURIDAD}/100 $(score_badge $SCORE_SEGURIDAD)

#### 🌐 Hosting & Dominio

| Elemento | Detalle |
|----------|---------|
| **IP del servidor** | \`${SEC_HOST_IP:-Desconocida}\` |
| **Proveedor hosting** | ${SEC_HOST_PROVIDER:-Desconocido} |
| **Ubicación** | ${SEC_HOST_CITY:-?}, ${SEC_HOST_COUNTRY:-?} |
| **ASN** | ${SEC_HOST_ASN:-Desconocido} |
| **Abuse contact hosting** | ${SEC_HOST_ABUSE:-Desconocido} |
| **Registrador dominio** | ${SEC_DOM_REGISTRAR:-Desconocido} |
| **Email abuse registrador** | ${SEC_DOM_ABUSE_EMAIL:-Desconocido} |
| **Estado dominio** | ${SEC_DOM_STATUS:-Desconocido} |
| **DNSSEC** | $([ "${SEC_DOM_DNSSEC:-false}" == "true" ] && echo "✅ Activo" || echo "⚠️ No configurado") |
| **Dominio creado** | ${SEC_DOM_CREATED:-Desconocido} |
| **Dominio expira** | ${SEC_DOM_EXPIRES:-Desconocido} ${SEC_DOM_EXPIRY_NOTE:+— $SEC_DOM_EXPIRY_NOTE} |
| **Última actualización** | ${SEC_DOM_UPDATED:-Desconocido} |
| **Nameservers** | \`${SEC_DOM_NAMESERVERS:-Desconocido}\` |
| **Privacidad WHOIS** | $([ "$SEC_DOM_PRIVACY" == "true" ] && echo "✅ Activada" || echo "⚠️ Datos expuestos") |
| **CAA Record** | $([ "${SEC_CAA:-AUSENTE}" != "AUSENTE" ] && echo "✅ ${SEC_CAA:0:50}" || echo "⚠️ AUSENTE") |
| **MX Record** | $([ "${SEC_MX:-AUSENTE}" != "AUSENTE" ] && echo "✅ Configurado" || echo "⚠️ AUSENTE") |

#### 🔐 Certificado SSL

| Elemento | Estado |
|----------|--------|
| Expiración SSL | ${SEC_SSL_EXPIRY_NOTE:-No verificado} |
| Versión TLS | ${SSL_PROTOCOL:-Desconocido} |
| Cipher suite | ${SSL_CIPHER:-Desconocido} |
| Emisor | ${SSL_ISSUER:-Desconocido} |
| SAN (dominios cubiertos) | ${SSL_SAN:-N/A} |
$([ -n "${SEC_SSLCHECK_RESULT:-}" ] && echo "| ssl-checker | \`${SEC_SSLCHECK_RESULT}\` |")

#### 🛡️ Headers de Seguridad

| Header | Estado | Detalle | Importancia |
|--------|--------|---------|-------------|
| Strict-Transport-Security (HSTS) | $([ "$SEC_HSTS" == "true" ] && echo "✅" || echo "❌") | $([ "$SEC_HSTS" == "true" ] && echo "max-age=${SEC_HSTS_MAXAGE:-?}s" || echo "Ausente") | 🔴 Crítico |
| Content-Security-Policy (CSP)    | $([ "$SEC_CSP"  == "true" ] && echo "$([ "$SEC_CSP_UNSAFE" == "true" ] && echo "⚠️ Inseguro" || echo "✅")" || echo "❌") | $([ "$SEC_CSP_UNSAFE" == "true" ] && echo "unsafe-inline detectado" || echo "—") | 🔴 Crítico |
| X-Content-Type-Options           | $([ "$SEC_XCTO" == "true" ] && echo "✅" || echo "❌") | — | 🟠 Alto |
| X-Frame-Options                  | $([ "$SEC_XFO"  == "true" ] && echo "✅" || echo "❌") | — | 🟠 Alto |
| Referrer-Policy                  | $([ "$SEC_RP"   == "true" ] && echo "✅" || echo "❌") | — | 🟡 Medio |
| Permissions-Policy               | $([ "$SEC_PER"  == "true" ] && echo "✅" || echo "❌") | — | 🟡 Medio |
| Subresource Integrity (SRI)      | $([ "$SEC_SRI"  == "true" ] && echo "✅" || echo "➖") | — | 🟡 Medio |
| HTTPS Redirect                   | $([ "$SEC_HTTPS_REDIRECT" == "true" ] && echo "✅" || echo "❌") | — | 🔴 Crítico |
| Cookies Secure                   | $([ "$SEC_COOKIE_SECURE"   == "true" ] && echo "✅" || echo "⚠️") | 🟠 Alto |
| Cookies HttpOnly                 | $([ "$SEC_COOKIE_HTTPONLY" == "true" ] && echo "✅" || echo "⚠️") | 🟠 Alto |

**💡 Recomendaciones:**
- $([ "$SEC_DOM_PRIVACY" != "true" ] && echo "🟡 Activar privacidad WHOIS en el registrador" || echo "Privacidad WHOIS activa ✓")
- $([ "$SEC_HSTS" != "true" ] && echo "🔴 CRÍTICO: \`Strict-Transport-Security: max-age=31536000; includeSubDomains\`" || echo "HSTS configurado ✓")
- $([ "$SEC_CSP"  != "true" ] && echo "🔴 CRÍTICO: Configurar Content-Security-Policy para prevenir XSS" || echo "CSP configurado ✓")
- $([ "$SEC_XCTO" != "true" ] && echo "🟠 ALTO: \`X-Content-Type-Options: nosniff\`" || echo "X-Content-Type-Options ✓")
- $([ "$SEC_XFO"  != "true" ] && echo "🟠 ALTO: \`X-Frame-Options: DENY\` — previene Clickjacking" || echo "X-Frame-Options ✓")

---

### 🛡️ 5. Ciberseguridad — ${SCORE_CIBERSEGURIDAD}/100 $(score_badge $SCORE_CIBERSEGURIDAD)

| Elemento | Estado | Detalle |
|----------|--------|---------|
| Server header | $(echo "$CYBER_SERVER" | grep -qiE "^oculto$" && echo "✅ Oculto" || echo "⚠️ Expuesto") | \`${CYBER_SERVER}\` |
| X-Powered-By | $(echo "$CYBER_POWERED_BY" | grep -qiE "^oculto$" && echo "✅ Oculto" || echo "⚠️ Expuesto") | \`${CYBER_POWERED_BY}\` |
| Directorios expuestos | $([ "${CYBER_EXPOSED_DIRS[0]}" == "Ninguno detectado" ] && echo "✅ OK" || echo "🔴 DETECTADOS") | ${CYBER_EXPOSED_DIRS[*]} |
| security.txt | $([ "$CYBER_SEC_TXT" == "200" ] && echo "✅" || echo "⚠️") | Contacto: ${CYBER_SEC_TXT_CONTACT:-—} |
| SPF Record | $(echo "$CYBER_SPF" | grep -qi "v=spf" && echo "✅" || echo "⚠️ AUSENTE") | \`${CYBER_SPF:0:60}\` |
| DMARC Record | $(echo "$CYBER_DMARC" | grep -qi "v=DMARC" && echo "✅" || echo "⚠️ AUSENTE") | \`${CYBER_DMARC:0:60}\` |
| DKIM Record | $(echo "$CYBER_DKIM" | grep -qi "v=DKIM" && echo "✅" || echo "⚠️ AUSENTE") | — |
| BIMI Record | $(echo "$CYBER_BIMI" | grep -qi "v=BIMI" && echo "✅" || echo "➖ AUSENTE") | — |

**💡 Recomendaciones:**
- $(echo "$CYBER_SERVER" | grep -qiE "[0-9]\.|apache|nginx|iis|php" && echo "🟠 Ocultar versión en header Server — exponer la versión facilita ataques dirigidos" || echo "Server header sin versión ✓")
- $([ "$CYBER_SEC_TXT" != "200" ] && echo "🟢 Crear \`/.well-known/security.txt\` — permite a investigadores reportar vulnerabilidades de forma responsable" || echo "security.txt presente ✓")
- $(echo "$CYBER_DKIM" | grep -qi "v=DKIM" || echo "🟡 Configurar DKIM — junto a SPF y DMARC protege al dominio de suplantación de identidad en emails")
- Implementar WAF y realizar pentesting periódico (OWASP Top 10)

---

### ⚙️ 6. Calidad Técnica — ${SCORE_CALIDAD_TECNICA}/100 $(score_badge $SCORE_CALIDAD_TECNICA)

| Elemento | Estado |
|----------|--------|
| DOCTYPE HTML5 | $([ "$CT_DOCTYPE"   == "true" ] && echo "✅" || echo "❌") |
| Atributo lang | $([ "$CT_LANG"      == "true" ] && echo "✅" || echo "❌") |
| Meta charset  | $([ "$CT_CHARSET"   == "true" ] && echo "✅" || echo "❌") |
| Viewport meta | $([ "$CT_VIEWPORT"  == "true" ] && echo "✅" || echo "❌") |
| Title tag     | $([ "$CT_TITLE"     == "true" ] && echo "✅" || echo "❌") |
| Canonical URL | $([ "$CT_CANONICAL" == "true" ] && echo "✅" || echo "❌") |
| Scripts inline | $([ "${CT_INLINE_SCRIPTS:-0}" -le 5 ] && echo "✅" || echo "⚠️") | ${CT_INLINE_SCRIPTS:-0} |
| Estilos inline | $([ "${CT_INLINE_STYLES:-0}" -le 10 ] && echo "✅" || echo "⚠️") | ${CT_INLINE_STYLES:-0} |
| Tags deprecados | $([ "${CT_DEPRECATED:-0}" -eq 0 ] && echo "✅" || echo "⚠️") | ${CT_DEPRECATED:-0} detectados |
| Mixed content | $([ "$CT_MIXED_CONTENT" == "false" ] && echo "✅" || echo "🔴") | — |
| PWA manifest | $([ "$CT_PWA_MANIFEST" == "true" ] && echo "✅" || echo "➖") | — |
| Service Worker | $([ "$CT_SERVICE_WORKER" == "true" ] && echo "✅" || echo "➖") | — |
$([ "${CT_HTMLHINT_ERRORS:-0}" -gt 0 ] && echo "| htmlhint errores | ⚠️ ${CT_HTMLHINT_ERRORS} | ${CT_HTMLHINT_WARNINGS:-0} warnings |" || echo "| htmlhint | ✅ Sin errores | — |")

**💡 Recomendaciones:**
- $([ "$CT_DOCTYPE"   != "true" ] && echo "🔴 Añadir \`<!DOCTYPE html>\` — sin él el navegador entra en modo quirks y el renderizado es impredecible" || echo "DOCTYPE correcto ✓")
- $([ "$CT_LANG"      != "true" ] && echo "🟠 Añadir atributo \`lang\` al elemento \`<html>\` — requerido para lectores de pantalla y motores de búsqueda" || echo "Lang presente ✓")
- $([ "$CT_CANONICAL" != "true" ] && echo "🟡 Implementar URLs canónicas — sin ellas Google puede indexar versiones duplicadas y dividir el posicionamiento" || echo "Canonical presente ✓")
- $([ "$CT_MIXED_CONTENT" == "true" ] && echo "🔴 Eliminar recursos HTTP en página HTTPS — los navegadores los bloquean y esto daña la experiencia del usuario" || echo "Sin mixed content ✓")

---

### 🎨 7. Diseño — ${SCORE_DISENO}/100 $(score_badge $SCORE_DISENO)

| Elemento | Estado | Detalle |
|----------|--------|---------|
| Responsive | $([ "$DIS_VIEWPORT"   == "true" ] && echo "✅" || echo "❌") | — |
| Framework CSS | ✅ | ${DIS_FRAMEWORKS[*]} |
| Tipografía web | $([ "$DIS_FONTS"     == "true" ] && echo "✅" || echo "➖") | — |
| Favicon | $([ "$DIS_FAVICON"   == "true" ] && echo "✅" || echo "⚠️") | $([ -n "${SITE_FAVICON:-}" ] && echo "\`${SITE_FAVICON}\`" || echo "—") |
| Favicon alta resolución | $([ "$DIS_FAVICON_HI" == "true" ] && echo "✅" || echo "➖") | — |
| Dark mode | $([ "$DIS_DARK_MODE" == "true" ] && echo "✅" || echo "➖") | — |
| Print stylesheet | $([ "$DIS_PRINT_CSS" == "true" ] && echo "✅" || echo "➖") | — |
| Breakpoints \`@media\` | ℹ️ | ${DIS_BREAKPOINTS:-0} detectados |
$([ -n "${DIS_LH_MOBILE:-}" ] && echo "| Lighthouse Best Practices 📱 Mobile | ✅ ${DIS_LH_MOBILE}/100 | — |")
$([ -n "${DIS_LH_DESKTOP:-}" ] && echo "| Lighthouse Best Practices 🖥️ Desktop | ✅ ${DIS_LH_DESKTOP}/100 | — |")

---

### 👤 8. UX — ${SCORE_UX}/100 $(score_badge $SCORE_UX)

| Elemento | Estado |
|----------|--------|
| Navegación \`<nav>\` | $([ "$UX_NAV"            == "true" ] && echo "✅" || echo "❌") |
| Buscador | $([ "$UX_SEARCH"          == "true" ] && echo "✅" || echo "➖") |
| Contacto visible | $([ "$UX_CONTACT"       == "true" ] && echo "✅" || echo "❌") |
| CTAs | $([ "$UX_CTA"               == "true" ] && echo "✅" || echo "⚠️") |
| Responsive | $([ "$UX_RESPONSIVE"      == "true" ] && echo "✅" || echo "❌") |
| Loading states | $([ "$UX_LOADING"        == "true" ] && echo "✅" || echo "➖") |
| Redes sociales | $([ "$UX_SOCIAL"         == "true" ] && echo "✅" || echo "➖") |
| Breadcrumbs | $([ "$UX_BREADCRUMBS"    == "true" ] && echo "✅" || echo "➖") |
| Chat / Soporte | $([ "$UX_CHAT"           == "true" ] && echo "✅" || echo "➖") |
| Validación formularios | $([ "$UX_FORM_VALIDATION" == "true" ] && echo "✅" || echo "➖") |
| Language switcher | $([ "$UX_LANG_SWITCH"  == "true" ] && echo "✅" || echo "➖") |
| Página 404 custom | $([ "$UX_404" == "404" ] && echo "✅" || echo "⚠️") |

---

## 🧰 Stack Tecnológico

| Categoría | Detectado |
|-----------|-----------|
| CMS / Plataforma | ${TECH_CMS:-Desconocido} |
| Framework JS | ${TECH_FRAMEWORK:-Desconocido} |
| Servidor web | ${TECH_SERVER:-Oculto} |
| Lenguaje backend | ${TECH_LANGUAGE:-Desconocido} |
| CDN | ${TECH_CDN:-No detectado} |
| Analytics / Marketing | ${TECH_ANALYTICS[*]:-Ninguno detectado} |

$([ -n "${TECH_WEBANALYZE:-}" ] && echo "**Análisis extendido (webanalyze):**" && echo '```' && echo "$TECH_WEBANALYZE" && echo '```')

---

## 📧 Email Deliverability

$(
email_score=100
spf_ok=false;   echo "$CYBER_SPF"   | grep -qi "v=spf"   && spf_ok=true   || email_score=$((email_score-30))
dmarc_ok=false; echo "$CYBER_DMARC" | grep -qi "v=DMARC" && dmarc_ok=true || email_score=$((email_score-30))
dkim_ok=false;  echo "$CYBER_DKIM"  | grep -qi "v=DKIM"  && dkim_ok=true  || email_score=$((email_score-25))
mx_ok=false;    [ "${SEC_MX:-AUSENTE}" != "AUSENTE" ] && mx_ok=true        || email_score=$((email_score-10))
bimi_ok=false;  echo "$CYBER_BIMI"  | grep -qi "v=BIMI"  && bimi_ok=true  || true
(( email_score < 0 )) && email_score=0

echo "**Score de Deliverability: $(score_badge $email_score) ${email_score}/100**"
echo ""
echo "| Mecanismo | Estado | Valor |"
echo "|-----------|--------|-------|"
echo "| SPF | $([ "$spf_ok" == "true" ] && echo "✅" || echo "🔴 AUSENTE") | \`${CYBER_SPF:0:60}\` |"
echo "| DMARC | $([ "$dmarc_ok" == "true" ] && echo "✅" || echo "🔴 AUSENTE") | \`${CYBER_DMARC:0:60}\` |"
echo "| DKIM | $([ "$dkim_ok" == "true" ] && echo "✅" || echo "🟠 AUSENTE") | — |"
echo "| MX Records | $([ "$mx_ok" == "true" ] && echo "✅" || echo "🟡 AUSENTE") | \`${SEC_MX:0:50}\` |"
echo "| BIMI | $([ "$bimi_ok" == "true" ] && echo "✅ Activo" || echo "➖ No configurado") | — |"
echo ""
if [[ "$spf_ok" == "false" || "$dmarc_ok" == "false" || "$dkim_ok" == "false" ]]; then
  echo "> ⚠️ Sin los tres pilares (SPF + DMARC + DKIM), los emails del dominio pueden ser bloqueados por spam filters o suplantados por atacantes."
else
  echo "> ✅ Los tres pilares de autenticación de email están configurados. El dominio está protegido contra suplantación."
fi
)

---

## 🔐 Legal & Privacidad

| Elemento | Estado | Riesgo |
|----------|--------|--------|
| Política de Privacidad | $([ "$LEGAL_PRIVACY" == "true" ] && echo "✅" || echo "❌") | $([ "$LEGAL_PRIVACY" != "true" ] && echo "🔴 GDPR Art.13" || echo "✅ OK") |
| Términos de Uso | $([ "$LEGAL_TERMS"   == "true" ] && echo "✅" || echo "⚠️") | $([ "$LEGAL_TERMS"   != "true" ] && echo "🟡 Medio"       || echo "✅ OK") |
| Banner Cookies | $([ "$LEGAL_COOKIES" == "true" ] && echo "✅" || echo "❌") | $([ "$LEGAL_COOKIES" != "true" ] && echo "🟠 ePrivacy"    || echo "✅ OK") |
| Trackers detectados | — | ${LEGAL_TRACKERS[*]} |

$([ "$LEGAL_PRIVACY" != "true" ] || [ "$LEGAL_COOKIES" != "true" ] && echo "⚠️ **Riesgo legal detectado.** Multas GDPR: hasta 20M€ o 4% de facturación anual." || echo "✅ Señales positivas de cumplimiento. Se recomienda auditoría legal completa.")

---

## 🔧 Guía de Corrección — Hallazgos Críticos y Altos

$(
has_fixes=false

if [[ "$SEC_HSTS" != "true" ]]; then has_fixes=true; cat << 'FIXEOF'
### 🔴 HSTS ausente

**Qué pasa sin esto:** Un atacante puede interceptar la conexión inicial HTTP antes de que el navegador sea redirigido a HTTPS (ataque MITM).

**nginx:**
```nginx
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
```
**Apache:**
```apache
Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
```
**Tiempo estimado:** < 30 minutos · **Impacto:** +20 pts Seguridad

---
FIXEOF
fi

if [[ "$SEC_CSP" != "true" ]]; then has_fixes=true; cat << 'FIXEOF'
### 🔴 Content-Security-Policy ausente

**Qué pasa sin esto:** El navegador ejecuta cualquier script sin restricciones — incluyendo los inyectados por atacantes (XSS).

**Punto de partida (nginx/Apache):**
```
Content-Security-Policy: default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:;
```
> Ajustar según los dominios de recursos externos reales del sitio.

**Tiempo estimado:** 1-2 horas · **Impacto:** +20 pts Seguridad

---
FIXEOF
fi

if [[ "$SEO_TITLE" == "AUSENTE" ]]; then has_fixes=true; cat << 'FIXEOF'
### 🔴 Title tag ausente

**Qué pasa sin esto:** Google no puede identificar el tema de la página — no aparece en resultados de búsqueda con texto relevante. CTR orgánico cercano a cero.

```html
<head>
  <title>Nombre de Página | Nombre de Marca</title>
</head>
```
> Longitud óptima: 50-60 caracteres. Único por página.

**Tiempo estimado:** < 1 hora · **Impacto:** +25 pts SEO

---
FIXEOF
fi

if [[ "$CT_MIXED_CONTENT" == "true" ]]; then has_fixes=true; cat << 'FIXEOF'
### 🔴 Mixed content detectado

**Qué pasa sin esto:** Los navegadores modernos bloquean recursos HTTP en páginas HTTPS — imágenes rotas, scripts que no cargan, estilos que no aplican.

```bash
# Buscar recursos HTTP en el código fuente
grep -rn 'src="http://' ./
grep -rn 'href="http://' ./
```
> Reemplazar todas las URLs `http://` por `https://` o URLs relativas `//`.

**Tiempo estimado:** 1-4 horas · **Impacto:** +15 pts Calidad Técnica

---
FIXEOF
fi

if [[ "${ACC_IMGS_NO_ALT:-0}" -gt 0 ]]; then has_fixes=true
cat << FIXEOF
### 🟠 ${ACC_IMGS_NO_ALT} imagen(es) sin atributo alt

**Qué pasa sin esto:** Los lectores de pantalla no pueden describir las imágenes — usuarios con discapacidad visual quedan excluidos. También penaliza el SEO.

\`\`\`html
<!-- Antes -->
<img src="producto.jpg">

<!-- Después -->
<img src="producto.jpg" alt="Descripción concisa del contenido de la imagen">

<!-- Para imágenes decorativas -->
<img src="decorativo.svg" alt="" role="presentation">
\`\`\`

**Tiempo estimado:** 30-60 min · **Impacto:** +5 pts Accesibilidad por cada imagen corregida

---
FIXEOF
fi

if [[ "$CYBER_SPF" == "AUSENTE" || "$CYBER_DMARC" == "AUSENTE" || "$CYBER_DKIM" == "AUSENTE" ]]; then
has_fixes=true; cat << FIXEOF
### 🟠 Autenticación de email incompleta (SPF/DMARC/DKIM)

**Qué pasa sin esto:** Cualquier persona puede enviar emails haciéndose pasar por tu dominio — phishing, spam, daño reputacional.

\`\`\`dns
; SPF — reemplazar con tu servidor de correo real
${domain}.  TXT  "v=spf1 include:_spf.google.com ~all"

; DMARC
_dmarc.${domain}.  TXT  "v=DMARC1; p=quarantine; rua=mailto:dmarc@${domain}"

; DKIM — generado por tu proveedor de email
default._domainkey.${domain}.  TXT  "v=DKIM1; k=rsa; p=<clave_publica>"
\`\`\`

**Tiempo estimado:** 1-2 horas · **Impacto:** Protección contra suplantación de identidad

---
FIXEOF
fi

[[ "$has_fixes" == "false" ]] && echo "> ✅ No se detectaron hallazgos críticos o altos que requieran corrección urgente."
)

## 🎯 Matriz de Priorización

| Prioridad | Acción | Impacto | Esfuerzo | Dimensión |
|:---------:|--------|:-------:|:--------:|-----------|
$(
  _p=0
  [ "$SEC_HSTS"            != "true"   ] && { _p=$((_p+1)); echo "| 🔴 ${_p} | Implementar HSTS | 4 | 1 | Seguridad |"; }
  [ "$SEC_CSP"             != "true"   ] && { _p=$((_p+1)); echo "| 🔴 ${_p} | Configurar CSP | 4 | 2 | Seguridad |"; }
  [ "$SEO_TITLE"          == "AUSENTE" ] && { _p=$((_p+1)); echo "| 🔴 ${_p} | Añadir title tag | 4 | 1 | SEO |"; }
  [ "$SEC_HTTPS_REDIRECT"  != "true"   ] && { _p=$((_p+1)); echo "| 🔴 ${_p} | Forzar HTTPS redirect | 4 | 1 | Seguridad |"; }
  [ "$SEO_META_DESC"      == "AUSENTE" ] && { _p=$((_p+1)); echo "| 🟠 ${_p} | Meta descriptions | 3 | 1 | SEO |"; }
  [ "$LEGAL_COOKIES"       != "true"   ] && { _p=$((_p+1)); echo "| 🟠 ${_p} | Banner cookies GDPR | 3 | 2 | Legal |"; }
  [ "$ACC_ARIA"            != "true"   ] && { _p=$((_p+1)); echo "| 🟠 ${_p} | ARIA labels | 3 | 2 | Accesibilidad |"; }
  [ "$LEGAL_PRIVACY"       != "true"   ] && { _p=$((_p+1)); echo "| 🟠 ${_p} | Política de privacidad | 3 | 1 | Legal |"; }
  [ "$SEO_SITEMAP"         != "200"    ] && { _p=$((_p+1)); echo "| 🟡 ${_p} | Generar sitemap.xml | 2 | 1 | SEO |"; }
  [ "$SEO_SCHEMA"          != "true"   ] && { _p=$((_p+1)); echo "| 🟡 ${_p} | Schema.org | 2 | 2 | SEO |"; }
  [ "$DIS_FAVICON"         != "true"   ] && { _p=$((_p+1)); echo "| 🟢 ${_p} | Favicon | 1 | 1 | Diseño |"; }
)

---

## 📈 Impacto Esperado

| Acción | KPI | Mejora Est. | Plazo |
|--------|-----|------------|-------|
| HSTS + CSP + Headers | Seguridad | +15-20 pts | < 1 semana |
| Meta tags SEO | CTR orgánico | +10-30% | 4-8 semanas |
| Compresión Gzip/Brotli | Velocidad | -30-50% tamaño | < 1 día |
| Schema.org | Rich snippets | +20% CTR | 2-4 semanas |
| ARIA + Accesibilidad | Alcance + Compliance | +5-15 pts | 2-6 semanas |
| Banner cookies | Riesgo legal | Reducción riesgo | 1-2 semanas |

---

$(if [[ -n "$prev_report" && -f "$prev_report" ]]; then
cat << EVOLMD
## 📉 Evolución vs. Auditoría Anterior

> Comparando con: \`$(basename "$prev_report")\`

| Dimensión | Anterior | Actual | Δ |
|-----------|:--------:|:------:|:-:|
$(prev_global=$(grep "Score Global" "$prev_report" 2>/dev/null | perl -nle 'print $1 if /([0-9]+) \/ 100/' | head -1 || echo "N/A")
echo "| Global | ${prev_global} | $SCORE_GLOBAL | $(score_delta "$prev_global" "$SCORE_GLOBAL") |")
$(prev_perf=$(extract_prev_score "$prev_report" "Performance")
echo "| Performance | ${prev_perf} | $SCORE_PERFORMANCE | $(score_delta "$prev_perf" "$SCORE_PERFORMANCE") |")
$(prev_seo=$(extract_prev_score "$prev_report" "SEO")
echo "| SEO | ${prev_seo} | $SCORE_SEO | $(score_delta "$prev_seo" "$SCORE_SEO") |")
$(prev_seg=$(extract_prev_score "$prev_report" "Seguridad")
echo "| Seguridad | ${prev_seg} | $SCORE_SEGURIDAD | $(score_delta "$prev_seg" "$SCORE_SEGURIDAD") |")

EVOLMD
fi)

---

## 🧑‍💼 Perspectivas por Rol

**🎨 UX/UI:** $([ "$UX_NAV" == "true" ] && echo "Navegación estructurada presente." || echo "Falta navegación semántica.") $([ "$UX_CTA" == "true" ] && echo "CTAs detectables." || echo "CTAs no definidos — impacto directo en conversión.") Recomiendo pruebas con usuarios reales y análisis de mapas de calor.

**📊 Datos Web:** Tiempo de respuesta de **${PERF_RESP_MS}ms** $([ "${PERF_RESP_MS:-9999}" -lt 800 ] && echo "— dentro de parámetros óptimos." || echo "— puede estar afectando conversiones (cada 100ms extra = ~1% menos conversión).") Implementar monitoreo continuo de Core Web Vitals.

**✍️ SEO:** $([ "$SEO_TITLE" != "AUSENTE" ] && echo "Base técnica de metadatos adecuada." || echo "Requiere trabajo fundamental en metadatos.") $([ "$SEO_SCHEMA" == "true" ] && echo "Structured data positivo para rich snippets." || echo "Sin Schema.org — visibilidad en Google limitada.")

**⚙️ DevOps:** Headers de seguridad: **$([ $SCORE_SEGURIDAD -ge 70 ] && echo "aceptables" || echo "críticos")**. Hosting en **${SEC_HOST_PROVIDER:-desconocido}** (${SEC_HOST_COUNTRY:-?}). $([ "$SEC_HSTS" == "true" ] && echo "HSTS configurado ✓." || echo "HSTS ausente — vulnerabilidad MITM.")

**🔏 Privacidad:** $([ "$LEGAL_PRIVACY" == "true" ] && echo "Política de privacidad detectada." || echo "⚠️ Sin política de privacidad — riesgo GDPR.") Trackers: **${LEGAL_TRACKERS[*]}**. Verificar consentimiento explícito (GDPR Art. 6).

**💰 CRO:** $([ "$UX_CTA" == "true" ] && echo "CTAs presentes." || echo "Sin CTAs claros — pérdida de conversión directa.") Priorizar A/B testing en páginas de alto tráfico.

**📱 Producto Digital:** Score **${SCORE_GLOBAL}/100** — $([ $SCORE_GLOBAL -ge 80 ] && echo "producto en buen estado." || [ $SCORE_GLOBAL -ge 60 ] && echo "deuda técnica acumulada, requiere roadmap de mejora." || echo "deuda técnica crítica, sprint de emergencia recomendado.") OKRs sugeridos: performance, seguridad y UX como KPIs clave.

---

## 📋 Plan de Acción

$(
s1=""; s2=""; s3=""

# Sprint 1 — Críticos y altos de bajo esfuerzo
[ "$SEC_HSTS"    != "true"    ] && s1="${s1}- [ ] Implementar HSTS en el servidor web\n"
[ "$SEC_CSP"     != "true"    ] && s1="${s1}- [ ] Configurar Content-Security-Policy\n"
[ "$SEC_XCTO"    != "true"    ] && s1="${s1}- [ ] Añadir X-Content-Type-Options: nosniff\n"
[ "$SEC_XFO"     != "true"    ] && s1="${s1}- [ ] Añadir X-Frame-Options: DENY\n"
[ "$SEC_HTTPS_REDIRECT" != "true" ] && s1="${s1}- [ ] Forzar redirección HTTP → HTTPS\n"
echo "$PERF_COMPRESSION" | grep -qi "gzip\|br\|deflate" || s1="${s1}- [ ] Activar compresión Gzip/Brotli en el servidor\n"
[ "$SEO_TITLE"   == "AUSENTE" ] && s1="${s1}- [ ] Añadir \`<title>\` único a todas las páginas\n"
[ "$CT_DOCTYPE"  != "true"    ] && s1="${s1}- [ ] Añadir \`<!DOCTYPE html>\` al inicio del HTML\n"
[ "$CT_MIXED_CONTENT" == "true" ] && s1="${s1}- [ ] Eliminar recursos HTTP en página HTTPS\n"
[ -z "$s1" ] && s1="- [ ] Mantener los estándares actuales — sin críticos detectados\n"

# Sprint 2 — Medios de esfuerzo razonable
[ "$SEO_META_DESC" == "AUSENTE" ] && s2="${s2}- [ ] Crear meta descriptions únicas (120-160 chars)\n"
[ "$SEO_ROBOTS"  != "200"     ] && s2="${s2}- [ ] Crear robots.txt en la raíz del sitio\n"
[ "$SEO_SITEMAP" != "200"     ] && s2="${s2}- [ ] Generar sitemap.xml y registrar en Search Console\n"
[ "$ACC_ARIA"    != "true"    ] && s2="${s2}- [ ] Implementar atributos ARIA en componentes interactivos\n"
[ "${ACC_IMGS_NO_ALT:-0}" -gt 0 ] && s2="${s2}- [ ] Añadir atributo alt a ${ACC_IMGS_NO_ALT} imagen(es)\n"
[ "$CYBER_SPF"   == "AUSENTE" ] && s2="${s2}- [ ] Configurar registro SPF en DNS\n"
[ "$CYBER_DMARC" == "AUSENTE" ] && s2="${s2}- [ ] Configurar registro DMARC en DNS\n"
[ "$CYBER_DKIM"  == "AUSENTE" ] && s2="${s2}- [ ] Configurar DKIM en el servidor de correo\n"
[ "$LEGAL_COOKIES" != "true"  ] && s2="${s2}- [ ] Implementar banner de cookies GDPR\n"
[ "$LEGAL_PRIVACY" != "true"  ] && s2="${s2}- [ ] Publicar política de privacidad\n"
[ -z "$s2" ] && s2="- [ ] Revisar métricas Core Web Vitals y optimizar LCP\n"

# Sprint 3 — Mejoras estratégicas
[ "$SEO_SCHEMA"  != "true"    ] && s3="${s3}- [ ] Implementar Schema.org (structured data)\n"
[ "$CT_PWA_MANIFEST" != "true" ] && s3="${s3}- [ ] Crear manifest.json para soporte PWA\n"
[ "$DIS_DARK_MODE" != "true"  ] && s3="${s3}- [ ] Implementar soporte dark mode\n"
s3="${s3}- [ ] Auditoría WCAG 2.1 AA completa con herramienta especializada\n"
s3="${s3}- [ ] Monitoreo continuo de uptime y Core Web Vitals\n"
s3="${s3}- [ ] Revisión legal de política de privacidad por asesor\n"

echo "### Sprint 1 — Esta semana *(críticos · bajo esfuerzo)*"
printf "%s" "$s1" | sed 's/\\n/\n/g'
echo ""
echo "### Sprint 2 — Próximas 4 semanas"
printf "%s" "$s2" | sed 's/\\n/\n/g'
echo ""
echo "### Sprint 3 — Próximos 3 meses"
printf "%s" "$s3" | sed 's/\\n/\n/g'
)

---

## 💬 Conclusión

$(
# Identificar dimensiones más fuertes y más débiles
best_dim=""; best_score=0
worst_dim=""; worst_score=101
declare_scores="performance:$SCORE_PERFORMANCE seo:$SCORE_SEO accesibilidad:$SCORE_ACCESIBILIDAD seguridad:$SCORE_SEGURIDAD ciberseguridad:$SCORE_CIBERSEGURIDAD calidad_tecnica:$SCORE_CALIDAD_TECNICA diseno:$SCORE_DISENO ux:$SCORE_UX"
for pair in $declare_scores; do
  dim="${pair%%:*}"; val="${pair##*:}"
  (( val > best_score  )) && best_score=$val  && best_dim=$dim
  (( val < worst_score )) && worst_score=$val && worst_dim=$dim
done

# Estado global
if   (( SCORE_GLOBAL >= 80 )); then estado="sólido"
elif (( SCORE_GLOBAL >= 60 )); then estado="aceptable con oportunidades claras de mejora"
else                                 estado="con brechas importantes que requieren atención prioritaria"
fi

# Párrafo de apertura
echo "De acuerdo al análisis realizado por **Homium**, el sitio **${domain}** obtuvo un score global de **${SCORE_GLOBAL}/100**, lo que refleja un sitio ${estado}."
echo ""

# Lo positivo
echo "**Lo que está funcionando a favor:**"
if   (( best_score >= 80 )); then
  echo "El sitio muestra una fortaleza destacada en **${best_dim//_/ } (${best_score}/100)**$([ "$SCORE_PERFORMANCE" -ge 80 ] && echo ", con tiempos de carga que garantizan una experiencia fluida para el visitante" || echo ""). Esa base es valiosa — y es sobre ella que se construye todo lo demás."
else
  echo "Si bien ninguna dimensión alcanza el nivel óptimo, el sitio tiene elementos de base funcionales que facilitan un camino de mejora estructurado."
fi
echo ""

# Lo que requiere atención
echo "**Lo que está costando oportunidades:**"
[ "$SEC_HSTS" != "true" ] || [ "$SEC_CSP" != "true" ] && \
  echo "El sitio no cuenta con las protecciones de seguridad estándar, lo que significa que los datos de los visitantes están expuestos a riesgos evitables — algo que puede dañar la reputación de la marca de forma difícil de revertir."
[ "${ACC_IMGS_NO_ALT:-0}" -gt 0 ] || [ "$ACC_ARIA" != "true" ] && \
  echo "Una parte de los usuarios — personas con discapacidad visual o motora — no puede navegar el sitio con comodidad, lo que reduce el alcance real de la audiencia y puede representar un riesgo legal en mercados con regulaciones de accesibilidad."
[ "$LEGAL_COOKIES" != "true" ] || [ "$LEGAL_PRIVACY" != "true" ] && \
  echo "La ausencia de mecanismos de consentimiento visibles expone al negocio a sanciones significativas bajo normativa GDPR — un riesgo legal prevenible con bajo esfuerzo."
[ "$SEO_TITLE" == "AUSENTE" ] || [ "$SEO_META_DESC" == "AUSENTE" ] && \
  echo "Las páginas carecen de elementos SEO fundamentales, lo que limita directamente la visibilidad en buscadores y reduce el tráfico orgánico potencial."
echo ""

# Perspectiva de cierre
echo "**Perspectiva general:**"
if (( SCORE_GLOBAL >= 80 )); then
  echo "Con ajustes puntuales en las áreas identificadas, **${domain}** puede consolidarse como referente en su categoría. Las mejoras recomendadas son de bajo esfuerzo y alto impacto — una inversión que se traduce directamente en confianza, alcance y conversión."
elif (( SCORE_GLOBAL >= 60 )); then
  echo "Resolver las brechas prioritarias no es solo una cuestión técnica — es una decisión de negocio. Un sitio seguro genera más confianza y más conversiones. Uno accesible llega a más personas. Con las acciones del Sprint 1 implementadas, **${domain}** puede alcanzar un score de **$(( SCORE_GLOBAL + 15 ))+/100** en menos de dos semanas."
else
  echo "El camino de mejora es claro y los beneficios, tangibles. Atender las brechas críticas identificadas posicionará a **${domain}** en un estado competitivo en menos de un mes, con impacto directo en seguridad, posicionamiento y experiencia del usuario."
fi
)

---

*[homium-audit](https://github.com/homium-tech/audit) v${SCRIPT_VERSION} · ${DATE_HUMAN}*
MDEOF
}

# ─── Generate JSON ─────────────────────────────────────────────────────────────
generate_json() {
  local out_file="$1"
  local domain="${URL#*://}"; domain="${domain%%/*}"

  # Helpers
  _je() { printf '%s' "${1}" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\r' | tr '\n' ' '; }
  _jb() { [[ "${1}" == "true" ]] && printf 'true' || printf 'false'; }
  _lhnum() {
    local val; val=$(lh_metric "$1" "$2" 2>/dev/null || echo "")
    [[ -z "$val" || "$val" == "N/A" || "$val" == "—" ]] && printf 'null' && return
    printf '%s' "$val" | tr -d ',' | sed 's/ s$//' | sed 's/ ms$//' | grep -oE '[0-9]+\.?[0-9]*' | head -1 || printf 'null'
  }
  _jarr() {
    local first=true out="["
    for item in "$@"; do
      [[ "$first" == "true" ]] && first=false || out="${out},"
      out="${out}\"$(_je "$item")\""
    done
    printf '%s' "${out}]"
  }

  # Benchmarks (same logic as generate_report)
  local bp bs ba bsec bcy bct bd bu tp ts ta tsec tcy tct td tu
  case "${SECTOR:-general}" in
    ecommerce) bp=72 bs=75 ba=58 bsec=55 bcy=50 bct=65 bd=70 bu=75 tp=92 ts=92 ta=85 tsec=88 tcy=82 tct=88 td=92 tu=92 ;;
    saas)      bp=70 bs=68 ba=60 bsec=65 bcy=58 bct=70 bd=65 bu=70 tp=92 ts=88 ta=88 tsec=92 tcy=85 tct=90 td=88 tu=90 ;;
    blog)      bp=68 bs=80 ba=55 bsec=48 bcy=42 bct=62 bd=60 bu=62 tp=90 ts=95 ta=82 tsec=80 tcy=75 tct=85 td=85 tu=85 ;;
    landing)   bp=75 bs=70 ba=55 bsec=50 bcy=45 bct=60 bd=72 bu=78 tp=95 ts=90 ta=82 tsec=85 tcy=80 tct=85 td=92 tu=92 ;;
    portfolio) bp=65 bs=65 ba=55 bsec=48 bcy=42 bct=62 bd=80 bu=70 tp=90 ts=85 ta=82 tsec=80 tcy=75 tct=85 td=95 tu=90 ;;
    *)         bp=65 bs=70 ba=55 bsec=50 bcy=45 bct=60 bd=65 bu=60 tp=90 ts=90 ta=85 tsec=90 tcy=85 tct=85 td=90 tu=88 ;;
  esac

  # ISO timestamp
  local iso_ts; iso_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "$TIMESTAMP")

  # Email deliverability (re-compute)
  local email_score=100 spf_bool=false dmarc_bool=false dkim_bool=false mx_bool=false bimi_bool=false
  echo "$CYBER_SPF"   | grep -qi "v=spf"   && spf_bool=true   || email_score=$((email_score-30))
  echo "$CYBER_DMARC" | grep -qi "v=DMARC" && dmarc_bool=true || email_score=$((email_score-30))
  echo "$CYBER_DKIM"  | grep -qi "v=DKIM"  && dkim_bool=true  || email_score=$((email_score-25))
  [ "${SEC_MX:-AUSENTE}" != "AUSENTE" ] && mx_bool=true || email_score=$((email_score-10))
  echo "$CYBER_BIMI"  | grep -qi "v=BIMI"  && bimi_bool=true  || true
  (( email_score < 0 )) && email_score=0

  # Null-safe numeric fields
  local ssl_days hsts_maxage
  (( ${SEC_SSL_DAYS:--1} >= 0 )) && ssl_days="${SEC_SSL_DAYS}" || ssl_days="null"
  (( ${SEC_HSTS_MAXAGE:-0} > 0 )) && hsts_maxage="${SEC_HSTS_MAXAGE}" || hsts_maxage="null"

  # Arrays
  local json_css_frameworks json_analytics json_trackers json_san
  local json_nameservers json_schema_types json_exposed_paths json_webanalyze
  local json_ss_mobile json_ss_desktop json_dimensions_run

  json_css_frameworks=$(_jarr "${DIS_FRAMEWORKS[@]}")
  if [[ "${TECH_ANALYTICS[0]:-}" == "Ninguno detectado" || ${#TECH_ANALYTICS[@]} -eq 0 ]]; then
    json_analytics="[]"
  else
    json_analytics=$(_jarr "${TECH_ANALYTICS[@]}")
  fi
  json_trackers=$(_jarr "${LEGAL_TRACKERS[@]}")
  json_san=$(_jarr ${SSL_SAN})

  if [[ "${CYBER_EXPOSED_DIRS[0]:-Ninguno detectado}" == "Ninguno detectado" ]]; then
    json_exposed_paths="[]"
  else
    json_exposed_paths=$(_jarr "${CYBER_EXPOSED_DIRS[@]}")
  fi

  local _ns_first=true; json_nameservers="["
  while IFS= read -r _ns; do
    _ns=$(echo "$_ns" | xargs 2>/dev/null || echo "")
    [[ -z "$_ns" || "$_ns" == "Desconocido" ]] && continue
    [[ "$_ns_first" == "true" ]] && _ns_first=false || json_nameservers="${json_nameservers},"
    json_nameservers="${json_nameservers}\"$(_je "$_ns")\""
  done <<< "$(echo "${SEC_DOM_NAMESERVERS:-}" | tr ',' '\n')"
  json_nameservers="${json_nameservers}]"

  local _st_first=true; json_schema_types="["
  while IFS= read -r _st; do
    _st=$(echo "$_st" | xargs 2>/dev/null || echo "")
    [[ -z "$_st" || "$_st" == "N/A" ]] && continue
    [[ "$_st_first" == "true" ]] && _st_first=false || json_schema_types="${json_schema_types},"
    json_schema_types="${json_schema_types}\"$(_je "$_st")\""
  done <<< "$(echo "${SEO_SCHEMA_TYPES:-}" | tr ',' '\n')"
  json_schema_types="${json_schema_types}]"

  [[ -n "${TECH_WEBANALYZE:-}" ]] && json_webanalyze="\"$(_je "$TECH_WEBANALYZE")\"" || json_webanalyze="null"
  [[ -n "${SCREENSHOT_MOBILE:-}" ]]  && json_ss_mobile="\"$(_je "$(basename "$SCREENSHOT_MOBILE")")\""  || json_ss_mobile="null"
  [[ -n "${SCREENSHOT_DESKTOP:-}" ]] && json_ss_desktop="\"$(_je "$(basename "$SCREENSHOT_DESKTOP")")\"" || json_ss_desktop="null"

  if [[ -n "$DIMENSIONS" ]]; then
    local _dr_first=true; json_dimensions_run="["
    while IFS= read -r _dim; do
      _dim=$(echo "$_dim" | xargs 2>/dev/null || echo "")
      [[ -z "$_dim" ]] && continue
      [[ "$_dr_first" == "true" ]] && _dr_first=false || json_dimensions_run="${json_dimensions_run},"
      json_dimensions_run="${json_dimensions_run}\"${_dim}\""
    done <<< "$(echo "$DIMENSIONS" | tr ',' '\n')"
    json_dimensions_run="${json_dimensions_run}]"
  else
    json_dimensions_run='["performance","seo","accesibilidad","seguridad","ciberseguridad","calidad_tecnica","diseno","ux"]'
  fi

  # Findings builder
  local _fj=""
  _fa() {
    local _entry="{\"severity\":\"${1}\",\"element\":\"${2}\",\"value\":\"$(_je "${3}")\",\"description\":\"$(_je "${4}")\",\"recommendation\":\"$(_je "${5}")\"}"
    [[ -n "$_fj" ]] && _fj="${_fj}," || true
    _fj="${_fj}${_entry}"
  }

  # Performance findings
  _fj=""
  [[ "${PERF_RESP_SEVERITY:-bajo}" != "bajo" ]] && _fa "${PERF_RESP_SEVERITY}" "response_ms" "${PERF_RESP_MS}ms" "Tiempo de respuesta elevado (${PERF_RESP_MS}ms)" "Implementar CDN y optimizar caché de servidor"
  (( ${PERF_TTFB_MS:-0} > 600 )) && _fa "alto" "ttfb" "${PERF_TTFB_MS}ms" "TTFB superior a 600ms" "Optimizar backend y activar caché de servidor"
  (( ${PERF_REDIRECTS:-0} > 2 )) && _fa "medio" "redirects" "${PERF_REDIRECTS}" "Cadena de redirects excesiva" "Reducir a máximo 1-2 redirects"
  [[ "${PERF_CDN:-No detectado}" == "No detectado" ]] && _fa "medio" "cdn" "No detectado" "Sin CDN — latencia geográfica no optimizada" "Implementar Cloudflare o CloudFront"
  echo "${PERF_PROTOCOL:-}" | grep -q "2\|3" || _fa "medio" "protocol" "${PERF_PROTOCOL:-HTTP/1.1}" "Protocolo HTTP/1.1 sin multiplexación" "Migrar a HTTP/2 o HTTP/3"
  echo "${PERF_COMPRESSION:-}" | grep -qi "gzip\|br\|deflate" || _fa "medio" "compression" "Inactiva" "Sin compresión — tamaño elevado" "Activar Gzip/Brotli en el servidor"
  (( ${PERF_JS_COUNT:-0} > 20 )) && _fa "medio" "js_count" "${PERF_JS_COUNT}" "Exceso de scripts JS (${PERF_JS_COUNT})" "Consolidar y diferir scripts no críticos"
  local JSON_F_PERF="[${_fj}]"

  # SEO findings
  _fj=""
  [[ "${SEO_TITLE:-}" == "AUSENTE" ]] && _fa "critico" "title" "AUSENTE" "Title tag ausente — CTR orgánico cercano a cero" "Añadir <title> único de 50-60 chars"
  [[ "${SEO_META_DESC:-}" == "AUSENTE" ]] && _fa "critico" "meta_description" "AUSENTE" "Meta description ausente" "Crear meta description de 120-160 chars"
  (( ${SEO_H1_COUNT:-0} == 0 )) && _fa "alto" "h1" "0" "Sin H1 — falta señal principal de keyword" "Añadir un único H1 con la keyword principal"
  (( ${SEO_H1_COUNT:-0} > 1 )) && _fa "medio" "h1_multiple" "${SEO_H1_COUNT}" "Múltiples H1 — señal semántica confusa" "Reducir a un único H1 por página"
  [[ "${SEO_OG:-false}" != "true" ]] && _fa "medio" "og_tags" "false" "Sin Open Graph — preview desfavorable en redes" "Añadir og:title, og:description, og:image"
  [[ "${SEO_ROBOTS:-}" != "200" ]] && _fa "medio" "robots_txt" "${SEO_ROBOTS:-0}" "robots.txt ausente" "Crear robots.txt en la raíz del sitio"
  [[ "${SEO_SITEMAP:-}" != "200" ]] && _fa "medio" "sitemap_xml" "${SEO_SITEMAP:-0}" "sitemap.xml ausente" "Generar sitemap.xml y registrar en Search Console"
  [[ "${SEO_SCHEMA:-false}" != "true" ]] && _fa "bajo" "schema_org" "false" "Sin Schema.org — sin rich snippets en Google" "Implementar structured data según tipo de contenido"
  local JSON_F_SEO="[${_fj}]"

  # Accesibilidad findings
  _fj=""
  (( ${ACC_IMGS_NO_ALT:-0} > 0 )) && _fa "alto" "images_alt" "${ACC_IMGS_NO_ALT} sin alt" "${ACC_IMGS_NO_ALT} imágenes sin atributo alt" "Añadir alt descriptivo a cada imagen"
  [[ "${ACC_ARIA:-false}" != "true" ]] && _fa "alto" "aria" "false" "Sin atributos ARIA en componentes interactivos" "Implementar aria-label, aria-labelledby y role"
  [[ "${ACC_SKIP:-false}" != "true" ]] && _fa "medio" "skip_navigation" "false" "Sin skip navigation para usuarios de teclado" "Añadir enlace Skip to main content al inicio del body"
  (( ${ACC_FORMS:-0} > 0 )) && (( ${ACC_LABELS:-0} < ${ACC_FORMS:-0} )) && _fa "alto" "form_labels" "${ACC_LABELS:-0}/${ACC_FORMS:-0}" "Formularios sin labels suficientes" "Asociar <label> a cada campo de formulario"
  local JSON_F_ACC="[${_fj}]"

  # Seguridad findings
  _fj=""
  [[ "${SEC_HSTS:-false}" != "true" ]] && _fa "critico" "hsts" "false" "HSTS no configurado — vulnerable a MITM" "Strict-Transport-Security: max-age=31536000; includeSubDomains"
  [[ "${SEC_CSP:-false}" != "true" ]] && _fa "critico" "csp" "false" "CSP ausente — vulnerable a XSS" "Configurar CSP con directivas adecuadas"
  [[ "${SEC_CSP_UNSAFE:-false}" == "true" ]] && _fa "alto" "csp_unsafe" "unsafe-inline" "CSP con unsafe-inline — protección XSS reducida" "Eliminar unsafe-inline y usar nonces o hashes"
  [[ "${SEC_XCTO:-false}" != "true" ]] && _fa "alto" "x_content_type_options" "false" "X-Content-Type-Options ausente" "Añadir: X-Content-Type-Options: nosniff"
  [[ "${SEC_XFO:-false}" != "true" ]] && _fa "alto" "x_frame_options" "false" "X-Frame-Options ausente — vulnerable a clickjacking" "Añadir: X-Frame-Options: DENY"
  [[ "${SEC_RP:-false}" != "true" ]] && _fa "medio" "referrer_policy" "false" "Referrer-Policy ausente" "Añadir: Referrer-Policy: strict-origin-when-cross-origin"
  [[ "${SEC_PER:-false}" != "true" ]] && _fa "medio" "permissions_policy" "false" "Permissions-Policy ausente" "Configurar Permissions-Policy para limitar APIs del navegador"
  [[ "${SEC_HTTPS_REDIRECT:-false}" != "true" ]] && _fa "critico" "https_redirect" "false" "Sin redirección HTTP → HTTPS" "Configurar redirect 301 en el servidor"
  [[ "${SEC_COOKIE_SECURE:-true}" != "true" ]] && _fa "alto" "cookie_secure" "false" "Cookies sin flag Secure" "Añadir flag Secure a todas las cookies de sesión"
  [[ "${SEC_COOKIE_HTTPONLY:-true}" != "true" ]] && _fa "alto" "cookie_httponly" "false" "Cookies sin flag HttpOnly" "Añadir flag HttpOnly para prevenir acceso JS"
  local JSON_F_SEC="[${_fj}]"

  # Ciberseguridad findings
  _fj=""
  echo "${CYBER_SERVER:-}" | grep -qiE "[0-9]\.|apache|nginx|iis|php" && _fa "alto" "server_header" "$CYBER_SERVER" "Versión de servidor expuesta en header Server" "Ocultar versión en configuración del servidor"
  [[ -n "${CYBER_POWERED_BY:-}" && "${CYBER_POWERED_BY}" != "Oculto" ]] && _fa "medio" "powered_by" "$CYBER_POWERED_BY" "X-Powered-By expone tecnología del backend" "Eliminar o suprimir header X-Powered-By"
  [[ "${CYBER_EXPOSED_DIRS[0]:-Ninguno detectado}" != "Ninguno detectado" ]] && _fa "critico" "exposed_paths" "${CYBER_EXPOSED_DIRS[*]}" "Directorios sensibles accesibles públicamente" "Restringir acceso via .htaccess o configuración del servidor"
  [[ "${CYBER_SEC_TXT:-}" != "200" ]] && _fa "bajo" "security_txt" "${CYBER_SEC_TXT:-404}" "security.txt ausente" "Crear /.well-known/security.txt con contacto de seguridad"
  [[ "$CYBER_SPF"   == "AUSENTE" ]] && _fa "alto"  "spf"   "AUSENTE" "SPF ausente — dominio susceptible a spoofing" "Configurar registro SPF en DNS"
  [[ "$CYBER_DMARC" == "AUSENTE" ]] && _fa "alto"  "dmarc" "AUSENTE" "DMARC ausente" "Configurar registro DMARC en DNS"
  [[ "$CYBER_DKIM"  == "AUSENTE" ]] && _fa "medio" "dkim"  "AUSENTE" "DKIM ausente" "Configurar DKIM en el servidor de correo"
  local JSON_F_CYBER="[${_fj}]"

  # Calidad técnica findings
  _fj=""
  [[ "${CT_DOCTYPE:-false}" != "true" ]] && _fa "critico" "doctype" "false" "DOCTYPE ausente — modo quirks activo" "Añadir <!DOCTYPE html> como primera línea del HTML"
  [[ "${CT_LANG:-false}" != "true" ]] && _fa "alto" "lang_attribute" "false" "Atributo lang ausente en <html>" "Añadir lang='es' al elemento <html>"
  [[ "${CT_CANONICAL:-false}" != "true" ]] && _fa "medio" "canonical" "false" "URL canónica ausente — riesgo contenido duplicado" "Implementar <link rel='canonical'> en el <head>"
  [[ "${CT_MIXED_CONTENT:-false}" == "true" ]] && _fa "critico" "mixed_content" "true" "Mixed content — recursos HTTP en página HTTPS" "Reemplazar todas las URLs http:// por https://"
  (( ${CT_DEPRECATED:-0} > 0 )) && _fa "medio" "deprecated_tags" "${CT_DEPRECATED}" "${CT_DEPRECATED} tags HTML deprecados" "Reemplazar por equivalentes CSS modernos"
  local JSON_F_CT="[${_fj}]"

  # Diseño findings
  _fj=""
  [[ "${DIS_VIEWPORT:-false}" != "true" ]] && _fa "critico" "viewport" "false" "Meta viewport ausente — no responsive en móviles" "Añadir <meta name='viewport' content='width=device-width, initial-scale=1'>"
  [[ "${DIS_FAVICON:-false}" != "true" ]] && _fa "bajo" "favicon" "false" "Favicon ausente" "Añadir favicon.ico y variantes de alta resolución"
  local JSON_F_DIS="[${_fj}]"

  # UX findings
  _fj=""
  [[ "${UX_NAV:-false}" != "true" ]] && _fa "alto" "navigation" "false" "Sin elemento <nav> — navegación semántica ausente" "Estructurar el menú dentro de un elemento <nav>"
  [[ "${UX_CTA:-false}" != "true" ]] && _fa "alto" "cta" "false" "Sin CTAs detectables — impacto directo en conversión" "Añadir botones de llamada a la acción visibles"
  [[ "${UX_CONTACT:-false}" != "true" ]] && _fa "medio" "contact" "false" "Sin información de contacto visible" "Añadir email, teléfono o formulario en lugar visible"
  [[ "${UX_RESPONSIVE:-false}" != "true" ]] && _fa "critico" "responsive" "false" "Sin señales de diseño responsive" "Implementar media queries y diseño adaptable"
  local JSON_F_UX="[${_fj}]"

  # Legal findings
  _fj=""
  [[ "${LEGAL_PRIVACY:-false}" != "true" ]] && _fa "critico" "privacy_policy" "false" "Política de privacidad ausente — riesgo GDPR Art.13" "Publicar política de privacidad accesible desde el footer"
  [[ "${LEGAL_COOKIES:-false}" != "true" ]] && _fa "alto" "cookie_consent" "false" "Sin banner de cookies GDPR — riesgo ePrivacy" "Implementar solución de consentimiento (Cookiebot, OneTrust)"
  [[ "${LEGAL_TERMS:-false}" != "true" ]] && _fa "medio" "terms" "false" "Términos de uso ausentes" "Publicar términos y condiciones del servicio"
  local JSON_F_LEGAL="[${_fj}]"

  # Priority matrix
  local _pi=0 _pm=""
  _ap() {
    _pi=$((_pi+1))
    local _e="{\"priority\":${_pi},\"action\":\"$(_je "${1}")\",\"impact\":${2},\"effort\":${3},\"dimension\":\"${4}\"}"
    [[ -n "$_pm" ]] && _pm="${_pm}," || true; _pm="${_pm}${_e}"
  }
  [ "${SEC_HSTS:-false}"           != "true"   ] && _ap "Implementar HSTS"                4 1 "seguridad"
  [ "${SEC_CSP:-false}"            != "true"   ] && _ap "Configurar CSP"                  4 2 "seguridad"
  [ "${SEO_TITLE:-}"              == "AUSENTE" ] && _ap "Añadir title tag"                4 1 "seo"
  [ "${SEC_HTTPS_REDIRECT:-false}" != "true"   ] && _ap "Forzar HTTPS redirect"           4 1 "seguridad"
  [ "${SEO_META_DESC:-}"          == "AUSENTE" ] && _ap "Crear meta descriptions"         3 1 "seo"
  [ "${LEGAL_COOKIES:-false}"      != "true"   ] && _ap "Banner cookies GDPR"             3 2 "legal"
  [ "${ACC_ARIA:-false}"           != "true"   ] && _ap "Implementar ARIA labels"         3 2 "accesibilidad"
  [ "${LEGAL_PRIVACY:-false}"      != "true"   ] && _ap "Publicar política de privacidad" 3 1 "legal"
  [ "${SEO_SITEMAP:-}"             != "200"    ] && _ap "Generar sitemap.xml"             2 1 "seo"
  [ "${SEO_SCHEMA:-false}"         != "true"   ] && _ap "Implementar Schema.org"          2 2 "seo"
  [ "${DIS_FAVICON:-false}"        != "true"   ] && _ap "Agregar favicon"                 1 1 "diseno"
  local JSON_PRIORITY_MATRIX="[${_pm}]"

  # Sprint plan
  local _s1="" _s2="" _s3=""
  _at1() { [[ -n "$_s1" ]] && _s1="${_s1},\"$(_je "$1")\"" || _s1="\"$(_je "$1")\""; }
  _at2() { [[ -n "$_s2" ]] && _s2="${_s2},\"$(_je "$1")\"" || _s2="\"$(_je "$1")\""; }
  _at3() { [[ -n "$_s3" ]] && _s3="${_s3},\"$(_je "$1")\"" || _s3="\"$(_je "$1")\""; }
  [ "${SEC_HSTS:-false}"           != "true"   ] && _at1 "Implementar HSTS en el servidor web"
  [ "${SEC_CSP:-false}"            != "true"   ] && _at1 "Configurar Content-Security-Policy"
  [ "${SEC_XCTO:-false}"           != "true"   ] && _at1 "Añadir X-Content-Type-Options: nosniff"
  [ "${SEC_XFO:-false}"            != "true"   ] && _at1 "Añadir X-Frame-Options: DENY"
  [ "${SEC_HTTPS_REDIRECT:-false}" != "true"   ] && _at1 "Forzar redirección HTTP → HTTPS"
  echo "${PERF_COMPRESSION:-}" | grep -qi "gzip\|br\|deflate" || _at1 "Activar compresión Gzip/Brotli"
  [ "${SEO_TITLE:-}"              == "AUSENTE" ] && _at1 "Añadir <title> único a todas las páginas"
  [ "${CT_MIXED_CONTENT:-false}"  == "true"    ] && _at1 "Eliminar recursos HTTP en página HTTPS"
  [[ -z "$_s1" ]] && _at1 "Mantener estándares actuales — sin críticos detectados"
  [ "${SEO_META_DESC:-}"          == "AUSENTE" ] && _at2 "Crear meta descriptions únicas (120-160 chars)"
  [ "${SEO_ROBOTS:-}"              != "200"    ] && _at2 "Crear robots.txt en la raíz del sitio"
  [ "${SEO_SITEMAP:-}"             != "200"    ] && _at2 "Generar sitemap.xml y registrar en Search Console"
  [ "${ACC_ARIA:-false}"           != "true"   ] && _at2 "Implementar atributos ARIA en componentes interactivos"
  (( ${ACC_IMGS_NO_ALT:-0} > 0 )) && _at2 "Añadir atributo alt a ${ACC_IMGS_NO_ALT} imagen(es)"
  [ "$CYBER_SPF"   == "AUSENTE" ] && _at2 "Configurar registro SPF en DNS"
  [ "$CYBER_DMARC" == "AUSENTE" ] && _at2 "Configurar registro DMARC en DNS"
  [ "$CYBER_DKIM"  == "AUSENTE" ] && _at2 "Configurar DKIM en el servidor de correo"
  [ "${LEGAL_COOKIES:-false}"      != "true"   ] && _at2 "Implementar banner de cookies GDPR"
  [ "${LEGAL_PRIVACY:-false}"      != "true"   ] && _at2 "Publicar política de privacidad"
  [[ -z "$_s2" ]] && _at2 "Revisar métricas Core Web Vitals y optimizar LCP"
  [ "${SEO_SCHEMA:-false}"        != "true"    ] && _at3 "Implementar Schema.org (structured data)"
  [ "${CT_PWA_MANIFEST:-false}"   != "true"    ] && _at3 "Crear manifest.json para soporte PWA"
  [ "${DIS_DARK_MODE:-false}"     != "true"    ] && _at3 "Implementar soporte dark mode"
  _at3 "Auditoría WCAG 2.1 AA completa con herramienta especializada"
  _at3 "Monitoreo continuo de uptime y Core Web Vitals"
  _at3 "Revisión legal de política de privacidad por asesor"

  # Correction guide
  local _cg=""
  _acg() {
    local _e="{\"title\":\"$(_je "${1}")\",\"severity\":\"${2}\",\"problem\":\"$(_je "${3}")\",\"fixes\":${4},\"estimated_time\":\"$(_je "${5}")\",\"score_impact\":\"$(_je "${6}")\"}"
    [[ -n "$_cg" ]] && _cg="${_cg}," || true; _cg="${_cg}${_e}"
  }
  [[ "${SEC_HSTS:-false}" != "true" ]] && _acg \
    "HSTS ausente" "critico" \
    "Un atacante puede interceptar la conexión HTTP inicial antes del redirect a HTTPS (MITM)." \
    '[{"label":"nginx","code":"add_header Strict-Transport-Security \"max-age=31536000; includeSubDomains; preload\" always;"},{"label":"Apache","code":"Header always set Strict-Transport-Security \"max-age=31536000; includeSubDomains; preload\""}]' \
    "< 30 minutos" "+20 pts Seguridad"
  [[ "${SEC_CSP:-false}" != "true" ]] && _acg \
    "Content-Security-Policy ausente" "critico" \
    "El navegador ejecuta cualquier script sin restricciones, incluyendo inyecciones XSS." \
    '[{"label":"Header","code":"Content-Security-Policy: default-src '\''self'\''; script-src '\''self'\''; img-src '\''self'\'' data: https:;"}]' \
    "1-2 horas" "+20 pts Seguridad"
  [[ "${SEO_TITLE:-}" == "AUSENTE" ]] && _acg \
    "Title tag ausente" "critico" \
    "Google no puede identificar el tema de la página. CTR orgánico cercano a cero." \
    '[{"label":"HTML","code":"<head><title>Nombre de Página | Nombre de Marca</title></head>"}]' \
    "< 1 hora" "+25 pts SEO"
  [[ "${CT_MIXED_CONTENT:-false}" == "true" ]] && _acg \
    "Mixed content detectado" "critico" \
    "Los navegadores modernos bloquean recursos HTTP en páginas HTTPS." \
    '[{"label":"bash","code":"grep -rn '\''src=\"http://'\'' ./ && grep -rn '\''href=\"http://'\'' ./"}]' \
    "1-4 horas" "+15 pts Calidad Técnica"
  (( ${ACC_IMGS_NO_ALT:-0} > 0 )) && _acg \
    "${ACC_IMGS_NO_ALT} imagen(es) sin atributo alt" "alto" \
    "Usuarios con discapacidad visual quedan excluidos. Penaliza el SEO." \
    '[{"label":"HTML","code":"<img src=\"producto.jpg\" alt=\"Descripción concisa del contenido\">"}]' \
    "30-60 min" "+5 pts Accesibilidad por imagen"
  [[ "$CYBER_SPF" == "AUSENTE" || "$CYBER_DMARC" == "AUSENTE" || "$CYBER_DKIM" == "AUSENTE" ]] && _acg \
    "Autenticación de email incompleta" "alto" \
    "Cualquier persona puede enviar emails haciéndose pasar por el dominio." \
    "[{\"label\":\"SPF\",\"code\":\"${domain}.  TXT  \\\"v=spf1 include:_spf.google.com ~all\\\"\"},{\"label\":\"DMARC\",\"code\":\"_dmarc.${domain}.  TXT  \\\"v=DMARC1; p=quarantine; rua=mailto:dmarc@${domain}\\\"\"},{\"label\":\"DKIM\",\"code\":\"default._domainkey.${domain}.  TXT  \\\"v=DKIM1; k=rsa; p=clave_publica\\\"\"}]" \
    "1-2 horas" "Protección contra suplantación"
  local JSON_CORRECTION_GUIDE="[${_cg}]"

  # Perspectives
  local persp_ux persp_seo persp_devops persp_legal persp_cro persp_product
  persp_ux="$([ "${UX_NAV:-false}" == "true" ] && echo "Navegación estructurada presente." || echo "Falta navegación semántica.") $([ "${UX_CTA:-false}" == "true" ] && echo "CTAs detectables." || echo "CTAs no definidos — impacto directo en conversión.") Recomiendo pruebas con usuarios reales y mapas de calor."
  persp_seo="$([ "${SEO_TITLE:-}" != "AUSENTE" ] && echo "Base técnica de metadatos adecuada." || echo "Requiere trabajo fundamental en metadatos.") $([ "${SEO_SCHEMA:-false}" == "true" ] && echo "Structured data positivo para rich snippets." || echo "Sin Schema.org — visibilidad en Google limitada.")"
  persp_devops="Headers de seguridad: $( (( ${SCORE_SEGURIDAD:-0} >= 70 )) && echo "aceptables" || echo "críticos"). Hosting en ${SEC_HOST_PROVIDER:-desconocido} (${SEC_HOST_COUNTRY:-?}). $([ "${SEC_HSTS:-false}" == "true" ] && echo "HSTS configurado." || echo "HSTS ausente — vulnerabilidad MITM.")"
  persp_legal="$([ "${LEGAL_PRIVACY:-false}" == "true" ] && echo "Política de privacidad detectada." || echo "Sin política de privacidad — riesgo GDPR.") Trackers: ${LEGAL_TRACKERS[*]:-ninguno}. Verificar consentimiento explícito (GDPR Art. 6)."
  persp_cro="$([ "${UX_CTA:-false}" == "true" ] && echo "CTAs presentes." || echo "Sin CTAs claros — pérdida de conversión directa.") Priorizar A/B testing en páginas de alto tráfico."
  persp_product="Score ${SCORE_GLOBAL:-0}/100 — $( (( ${SCORE_GLOBAL:-0} >= 80 )) && echo "producto en buen estado." || (( ${SCORE_GLOBAL:-0} >= 60 )) && echo "deuda técnica acumulada, requiere roadmap de mejora." || echo "deuda técnica crítica, sprint de emergencia recomendado.") OKRs sugeridos: performance, seguridad y UX."

  # Narrative
  local exec_summary conclusion
  if   (( ${SCORE_GLOBAL:-0} >= 80 )); then exec_summary="El sitio ${domain} presenta un estado satisfactorio. Se recomienda priorizar las acciones de alto impacto antes del próximo ciclo de revisión."
  elif (( ${SCORE_GLOBAL:-0} >= 60 )); then exec_summary="El sitio ${domain} presenta un estado aceptable con áreas de mejora importantes. Existen brechas que pueden impactar conversión, posicionamiento y seguridad."
  else                                       exec_summary="El sitio ${domain} presenta deficiencias significativas que requieren atención inmediata con impacto directo en negocio, reputación y cumplimiento legal."
  fi
  local _bd="" _bs=0 _wd="" _ws=101
  for _pair in performance:${SCORE_PERFORMANCE:-0} seo:${SCORE_SEO:-0} accesibilidad:${SCORE_ACCESIBILIDAD:-0} seguridad:${SCORE_SEGURIDAD:-0} ciberseguridad:${SCORE_CIBERSEGURIDAD:-0} calidad_tecnica:${SCORE_CALIDAD_TECNICA:-0} diseno:${SCORE_DISENO:-0} ux:${SCORE_UX:-0}; do
    local _pd="${_pair%%:*}" _pv="${_pair##*:}"
    (( _pv > _bs )) && _bs=$_pv && _bd=$_pd
    (( _pv < _ws )) && _ws=$_pv && _wd=$_pd
  done
  if   (( ${SCORE_GLOBAL:-0} >= 80 )); then local _estado="sólido"
  elif (( ${SCORE_GLOBAL:-0} >= 60 )); then local _estado="aceptable con oportunidades claras de mejora"
  else                                       local _estado="con brechas importantes que requieren atención prioritaria"
  fi
  conclusion="De acuerdo al análisis de Homium, ${domain} obtuvo ${SCORE_GLOBAL:-0}/100 — sitio ${_estado}. Dimensión más fuerte: ${_bd//_/ } (${_bs}/100). Mayor oportunidad: ${_wd//_/ } (${_ws}/100)."

  # Evolution deltas
  local ev_prev="null" ev_g="null" ev_p="null" ev_s="null" ev_a="null"
  local ev_sec="null" ev_cy="null" ev_ct="null" ev_d="null" ev_u="null"
  if [[ -n "${PREV_REPORT:-}" && -f "$PREV_REPORT" ]]; then
    ev_prev="\"$(_je "$(basename "$PREV_REPORT")")\""
    local _pg; _pg=$(grep "Score Global" "$PREV_REPORT" 2>/dev/null | perl -nle 'print $1 if /([0-9]+) \/ 100/' | head -1 || echo "")
    [[ -n "$_pg" ]] && ev_g=$(( ${SCORE_GLOBAL:-0} - _pg )) || true
    local _pp; _pp=$(extract_prev_score "$PREV_REPORT" "Performance"); [[ "$_pp" != "N/A" && -n "$_pp" ]] && ev_p=$(( ${SCORE_PERFORMANCE:-0} - _pp )) || true
    local _ps; _ps=$(extract_prev_score "$PREV_REPORT" "SEO"); [[ "$_ps" != "N/A" && -n "$_ps" ]] && ev_s=$(( ${SCORE_SEO:-0} - _ps )) || true
    local _pa; _pa=$(extract_prev_score "$PREV_REPORT" "Accesibilidad"); [[ "$_pa" != "N/A" && -n "$_pa" ]] && ev_a=$(( ${SCORE_ACCESIBILIDAD:-0} - _pa )) || true
    local _psec; _psec=$(extract_prev_score "$PREV_REPORT" "Seguridad"); [[ "$_psec" != "N/A" && -n "$_psec" ]] && ev_sec=$(( ${SCORE_SEGURIDAD:-0} - _psec )) || true
    local _pcy; _pcy=$(extract_prev_score "$PREV_REPORT" "Ciberseguridad"); [[ "$_pcy" != "N/A" && -n "$_pcy" ]] && ev_cy=$(( ${SCORE_CIBERSEGURIDAD:-0} - _pcy )) || true
    local _pct; _pct=$(extract_prev_score "$PREV_REPORT" "Calidad"); [[ "$_pct" != "N/A" && -n "$_pct" ]] && ev_ct=$(( ${SCORE_CALIDAD_TECNICA:-0} - _pct )) || true
    local _pdis; _pdis=$(extract_prev_score "$PREV_REPORT" "Diseño"); [[ "$_pdis" != "N/A" && -n "$_pdis" ]] && ev_d=$(( ${SCORE_DISENO:-0} - _pdis )) || true
    local _pu; _pu=$(extract_prev_score "$PREV_REPORT" "UX"); [[ "$_pu" != "N/A" && -n "$_pu" ]] && ev_u=$(( ${SCORE_UX:-0} - _pu )) || true
  fi

  cat > "$out_file" << JSONEOF
{
  "meta": {
    "schema_version": "1.0",
    "tool_version": "$(_je "$SCRIPT_VERSION")",
    "url": "$(_je "$URL")",
    "domain": "$(_je "$domain")",
    "timestamp": "$(_je "$iso_ts")",
    "sector": "$(_je "${SECTOR:-general}")",
    "dimensions_run": ${json_dimensions_run},
    "tools_available": {
      "lighthouse": $(_jb "${LH_DONE_MOBILE:-false}"),
      "axe": $([[ -n "${AXE_CMD:-}" ]] && echo "true" || echo "false"),
      "pa11y": $([[ -n "${PA11Y_CMD:-}" ]] && echo "true" || echo "false"),
      "htmlhint": $([[ -n "${HTMLHINT_CMD:-}" ]] && echo "true" || echo "false"),
      "webanalyze": $(command -v webanalyze &>/dev/null && echo "true" || echo "false"),
      "ssl_checker": $([[ -n "${SSLCHECK_CMD:-}" ]] && echo "true" || echo "false")
    }
  },
  "scores": {
    "global": ${SCORE_GLOBAL:-0},
    "performance": ${SCORE_PERFORMANCE:-0},
    "seo": ${SCORE_SEO:-0},
    "accesibilidad": ${SCORE_ACCESIBILIDAD:-0},
    "seguridad": ${SCORE_SEGURIDAD:-0},
    "ciberseguridad": ${SCORE_CIBERSEGURIDAD:-0},
    "calidad_tecnica": ${SCORE_CALIDAD_TECNICA:-0},
    "diseno": ${SCORE_DISENO:-0},
    "ux": ${SCORE_UX:-0},
    "email_deliverability": ${email_score}
  },
  "benchmarks": {
    "sector": "$(_je "${SECTOR:-general}")",
    "average": { "performance": ${bp}, "seo": ${bs}, "accesibilidad": ${ba}, "seguridad": ${bsec}, "ciberseguridad": ${bcy}, "calidad_tecnica": ${bct}, "diseno": ${bd}, "ux": ${bu} },
    "top":     { "performance": ${tp}, "seo": ${ts}, "accesibilidad": ${ta}, "seguridad": ${tsec}, "ciberseguridad": ${tcy}, "calidad_tecnica": ${tct}, "diseno": ${td}, "ux": ${tu} }
  },
  "performance": {
    "response_ms": ${PERF_RESP_MS:-0},
    "ttfb_ms": ${PERF_TTFB_MS:-0},
    "size_kb": ${PERF_SIZE_KB:-0},
    "protocol": "$(_je "${PERF_PROTOCOL:-}")",
    "compression": "$(_je "${PERF_COMPRESSION:-}")",
    "redirects": ${PERF_REDIRECTS:-0},
    "cdn": "$(_je "${PERF_CDN:-No detectado}")",
    "resources": { "js": ${PERF_JS_COUNT:-0}, "css": ${PERF_CSS_COUNT:-0}, "images": ${PERF_IMG_COUNT:-0}, "fonts": null, "third_party_domains": null, "webp_avif_usage": null, "lazy_loading_count": null, "srcset_usage": null },
    "lighthouse": {
      "mobile":  { "score": ${PERF_LH_MOBILE:-null},  "lcp": $(_lhnum "largest-contentful-paint" "mobile"),  "fcp": $(_lhnum "first-contentful-paint" "mobile"),  "tbt": $(_lhnum "total-blocking-time" "mobile"),  "cls": $(_lhnum "cumulative-layout-shift" "mobile"),  "speed_index": $(_lhnum "speed-index" "mobile")  },
      "desktop": { "score": ${PERF_LH_DESKTOP:-null}, "lcp": $(_lhnum "largest-contentful-paint" "desktop"), "fcp": $(_lhnum "first-contentful-paint" "desktop"), "tbt": $(_lhnum "total-blocking-time" "desktop"), "cls": $(_lhnum "cumulative-layout-shift" "desktop"), "speed_index": $(_lhnum "speed-index" "desktop") }
    }
  },
  "seo": {
    "title": "$(_je "${SEO_TITLE:-}")",
    "title_length": ${SEO_TITLE_LEN:-0},
    "meta_description": "$(_je "${SEO_META_DESC:-}")",
    "meta_description_length": ${SEO_META_DESC_LEN:-0},
    "meta_robots": "$(_je "${SEO_META_ROBOTS:-No definido}")",
    "h1_count": ${SEO_H1_COUNT:-0}, "h2_count": ${SEO_H2_COUNT:-0}, "h3_count": ${SEO_H3_COUNT:-0},
    "og_tags": $(_jb "${SEO_OG:-false}"),
    "og_image": "$(_je "${SITE_OG_IMAGE:-}")",
    "twitter_card": $(_jb "${SEO_TWITTER_CARD:-false}"),
    "schema_org": $(_jb "${SEO_SCHEMA:-false}"),
    "schema_types": ${json_schema_types},
    "hreflang": $(_jb "${SEO_HREFLANG:-false}"),
    "robots_txt": ${SEO_ROBOTS:-0}, "sitemap_xml": ${SEO_SITEMAP:-0},
    "internal_links": ${SEO_INT_LINKS:-0}, "external_links": ${SEO_EXT_LINKS:-0},
    "favicon": "$(_je "${SITE_FAVICON:-}")",
    "word_count": null, "last_modified": null,
    "lighthouse": { "mobile": ${SEO_LH_MOBILE:-null}, "desktop": ${SEO_LH_DESKTOP:-null} }
  },
  "accesibilidad": {
    "images_total": ${ACC_IMGS_TOTAL:-0}, "images_without_alt": ${ACC_IMGS_NO_ALT:-0},
    "aria_present": $(_jb "${ACC_ARIA:-false}"), "skip_navigation": $(_jb "${ACC_SKIP:-false}"),
    "forms_count": ${ACC_FORMS:-0}, "labels_count": ${ACC_LABELS:-0},
    "lang_attribute": $(_jb "${CT_LANG:-false}"),
    "axe":   { "violations": ${ACC_AXE_VIOLATIONS:-0}, "serious": ${ACC_AXE_SERIOUS:-0} },
    "pa11y": { "errors": ${ACC_PA11Y_ERRORS:-0}, "warnings": ${ACC_PA11Y_WARNINGS:-0} },
    "lighthouse": { "mobile": ${ACC_LH_MOBILE:-null}, "desktop": ${ACC_LH_DESKTOP:-null} }
  },
  "seguridad": {
    "headers": {
      "hsts": $(_jb "${SEC_HSTS:-false}"), "hsts_max_age": ${hsts_maxage},
      "csp": $(_jb "${SEC_CSP:-false}"), "csp_unsafe_inline": $(_jb "${SEC_CSP_UNSAFE:-false}"),
      "x_content_type_options": $(_jb "${SEC_XCTO:-false}"), "x_frame_options": $(_jb "${SEC_XFO:-false}"),
      "referrer_policy": $(_jb "${SEC_RP:-false}"), "permissions_policy": $(_jb "${SEC_PER:-false}"),
      "sri": $(_jb "${SEC_SRI:-false}")
    },
    "https_redirect": $(_jb "${SEC_HTTPS_REDIRECT:-false}"),
    "ssl": {
      "days_remaining": ${ssl_days}, "expiry_note": "$(_je "${SEC_SSL_EXPIRY_NOTE:-}")",
      "issuer": "$(_je "${SSL_ISSUER:-Desconocido}")", "tls_version": "$(_je "${SSL_PROTOCOL:-Desconocido}")",
      "cipher": "$(_je "${SSL_CIPHER:-Desconocido}")", "san": ${json_san}
    },
    "cookies": { "secure": $(_jb "${SEC_COOKIE_SECURE:-false}"), "httponly": $(_jb "${SEC_COOKIE_HTTPONLY:-false}") },
    "caa_record": "$(_je "${SEC_CAA:-AUSENTE}")", "mx_record": "$(_je "${SEC_MX:-AUSENTE}")"
  },
  "ciberseguridad": {
    "server_header": "$(_je "${CYBER_SERVER:-Oculto}")", "powered_by": "$(_je "${CYBER_POWERED_BY:-Oculto}")",
    "exposed_paths": ${json_exposed_paths},
    "security_txt": ${CYBER_SEC_TXT:-0}, "security_txt_contact": "$(_je "${CYBER_SEC_TXT_CONTACT:-}")",
    "spf": "$(_je "${CYBER_SPF:-AUSENTE}")", "dmarc": "$(_je "${CYBER_DMARC:-AUSENTE}")",
    "dkim": "$(_je "${CYBER_DKIM:-AUSENTE}")", "bimi": "$(_je "${CYBER_BIMI:-AUSENTE}")",
    "source_maps_exposed": null, "dev_tools_active": null
  },
  "calidad_tecnica": {
    "doctype": $(_jb "${CT_DOCTYPE:-false}"), "lang_attribute": $(_jb "${CT_LANG:-false}"),
    "charset": $(_jb "${CT_CHARSET:-false}"), "viewport": $(_jb "${CT_VIEWPORT:-false}"),
    "title_tag": $(_jb "${CT_TITLE:-false}"), "canonical": $(_jb "${CT_CANONICAL:-false}"),
    "inline_scripts": ${CT_INLINE_SCRIPTS:-0}, "inline_styles": ${CT_INLINE_STYLES:-0},
    "deprecated_tags": ${CT_DEPRECATED:-0}, "mixed_content": $(_jb "${CT_MIXED_CONTENT:-false}"),
    "pwa_manifest": $(_jb "${CT_PWA_MANIFEST:-false}"), "service_worker": $(_jb "${CT_SERVICE_WORKER:-false}"),
    "htmlhint": { "errors": ${CT_HTMLHINT_ERRORS:-0}, "warnings": ${CT_HTMLHINT_WARNINGS:-0} }
  },
  "diseno": {
    "viewport": $(_jb "${DIS_VIEWPORT:-false}"), "css_frameworks": ${json_css_frameworks},
    "web_fonts": $(_jb "${DIS_FONTS:-false}"), "favicon": $(_jb "${DIS_FAVICON:-false}"),
    "favicon_hires": $(_jb "${DIS_FAVICON_HI:-false}"), "dark_mode": $(_jb "${DIS_DARK_MODE:-false}"),
    "print_css": $(_jb "${DIS_PRINT_CSS:-false}"), "breakpoints_count": ${DIS_BREAKPOINTS:-0},
    "lighthouse": { "mobile": ${DIS_LH_MOBILE:-null}, "desktop": ${DIS_LH_DESKTOP:-null} }
  },
  "ux": {
    "navigation": $(_jb "${UX_NAV:-false}"), "search": $(_jb "${UX_SEARCH:-false}"),
    "contact": $(_jb "${UX_CONTACT:-false}"), "cta": $(_jb "${UX_CTA:-false}"),
    "responsive": $(_jb "${UX_RESPONSIVE:-false}"), "loading_states": $(_jb "${UX_LOADING:-false}"),
    "breadcrumbs": $(_jb "${UX_BREADCRUMBS:-false}"), "social_links": $(_jb "${UX_SOCIAL:-false}"),
    "chat_widget": $(_jb "${UX_CHAT:-false}"), "form_validation": $(_jb "${UX_FORM_VALIDATION:-false}"),
    "language_switcher": $(_jb "${UX_LANG_SWITCH:-false}"),
    "page_404": ${UX_404:-0}, "page_500": ${UX_500:-0},
    "video_present": null, "newsletter_signup": null
  },
  "legal": {
    "privacy_policy": $(_jb "${LEGAL_PRIVACY:-false}"), "terms": $(_jb "${LEGAL_TERMS:-false}"),
    "cookie_consent": $(_jb "${LEGAL_COOKIES:-false}"), "gdpr_mentions": $(_jb "${LEGAL_GDPR:-false}"),
    "trackers": ${json_trackers}
  },
  "tecnologia": {
    "cms": "$(_je "${TECH_CMS:-Desconocido}")", "framework": "$(_je "${TECH_FRAMEWORK:-Desconocido}")",
    "language": "$(_je "${TECH_LANGUAGE:-Desconocido}")", "server": "$(_je "${TECH_SERVER:-Oculto}")",
    "cdn": "$(_je "${TECH_CDN:-No detectado}")", "analytics": ${json_analytics},
    "error_tracking": null, "ab_testing": null, "ad_scripts": null,
    "webanalyze_raw": ${json_webanalyze}
  },
  "email_deliverability": {
    "spf": ${spf_bool}, "dmarc": ${dmarc_bool}, "dkim": ${dkim_bool},
    "mx": ${mx_bool}, "bimi": ${bimi_bool}, "score": ${email_score}
  },
  "hosting": {
    "ip": "$(_je "${SEC_HOST_IP:-}")", "country": "$(_je "${SEC_HOST_COUNTRY:-Desconocido}")",
    "city": "$(_je "${SEC_HOST_CITY:-Desconocido}")", "org": "$(_je "${SEC_HOST_ORG:-Desconocido}")",
    "asn": "$(_je "${SEC_HOST_ASN:-Desconocido}")", "abuse_contact": "$(_je "${SEC_HOST_ABUSE:-Desconocido}")",
    "ipv6": null
  },
  "dominio": {
    "registrar": "$(_je "${SEC_DOM_REGISTRAR:-Desconocido}")",
    "created": "$(_je "${SEC_DOM_CREATED:-}")", "expires": "$(_je "${SEC_DOM_EXPIRES:-}")",
    "updated": "$(_je "${SEC_DOM_UPDATED:-}")", "nameservers": ${json_nameservers},
    "dnssec": $(_jb "${SEC_DOM_DNSSEC:-false}"), "status": "$(_je "${SEC_DOM_STATUS:-Desconocido}")",
    "whois_privacy": $(_jb "${SEC_DOM_PRIVACY:-false}"), "abuse_email": "$(_je "${SEC_DOM_ABUSE_EMAIL:-Desconocido}")"
  },
  "screenshots": { "mobile": ${json_ss_mobile}, "desktop": ${json_ss_desktop} },
  "findings": {
    "performance": ${JSON_F_PERF}, "seo": ${JSON_F_SEO}, "accesibilidad": ${JSON_F_ACC},
    "seguridad": ${JSON_F_SEC}, "ciberseguridad": ${JSON_F_CYBER}, "calidad_tecnica": ${JSON_F_CT},
    "diseno": ${JSON_F_DIS}, "ux": ${JSON_F_UX}, "legal": ${JSON_F_LEGAL}
  },
  "priority_matrix": ${JSON_PRIORITY_MATRIX},
  "expected_impact": [
    { "action": "HSTS + CSP + Headers",  "kpi": "Seguridad",            "improvement": "+15-20 pts", "timeline": "< 1 semana" },
    { "action": "Meta tags SEO",          "kpi": "CTR orgánico",         "improvement": "+10-30%",    "timeline": "4-8 semanas" },
    { "action": "Compresión Gzip/Brotli", "kpi": "Velocidad",            "improvement": "-30-50%",    "timeline": "< 1 día" },
    { "action": "Schema.org",            "kpi": "Rich snippets",         "improvement": "+20% CTR",   "timeline": "2-4 semanas" },
    { "action": "ARIA + Accesibilidad",   "kpi": "Alcance + Compliance", "improvement": "+5-15 pts",  "timeline": "2-6 semanas" },
    { "action": "Banner cookies",         "kpi": "Riesgo legal",         "improvement": "Reducción riesgo GDPR", "timeline": "1-2 semanas" }
  ],
  "sprint_plan": { "sprint_1": [${_s1}], "sprint_2": [${_s2}], "sprint_3": [${_s3}] },
  "correction_guide": ${JSON_CORRECTION_GUIDE},
  "perspectives": {
    "ux":      "$(_je "$persp_ux")",
    "seo":     "$(_je "$persp_seo")",
    "devops":  "$(_je "$persp_devops")",
    "legal":   "$(_je "$persp_legal")",
    "cro":     "$(_je "$persp_cro")",
    "product": "$(_je "$persp_product")"
  },
  "narrative": {
    "executive_summary": "$(_je "$exec_summary")",
    "conclusion": "$(_je "$conclusion")",
    "source": "script"
  },
  "evolution": {
    "previous_report": ${ev_prev},
    "deltas": {
      "global": ${ev_g}, "performance": ${ev_p}, "seo": ${ev_s}, "accesibilidad": ${ev_a},
      "seguridad": ${ev_sec}, "ciberseguridad": ${ev_cy}, "calidad_tecnica": ${ev_ct},
      "diseno": ${ev_d}, "ux": ${ev_u}
    }
  }
}
JSONEOF
}

# ─── MAIN ─────────────────────────────────────────────────────────────────────
main() {
  echo -e "\n${BOLD}${CYAN}╔══════════════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}${CYAN}║        homium-audit v${SCRIPT_VERSION}                 ║${RESET}"
  echo -e "${BOLD}${CYAN}║  Auditoría web profesional · 8 dimensiones   ║${RESET}"
  echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════╝${RESET}\n"

  info "URL: ${BOLD}${URL}${RESET}"
  info "Destino: ${BOLD}${OUTPUT_DIR}${RESET}"

  mkdir -p "$OUTPUT_DIR"
  check_dependencies

  local SLUG OUT_FILE
  SLUG=$(normalize_domain "$URL")
  OUT_FILE="${OUTPUT_DIR}/reporte-${SLUG}-${TIMESTAMP}.md"

  find_previous_report "$SLUG"

  info "Descargando página..."
  HTML_CACHE=$(fetch_url "$URL")
  ok "Página descargada ($(echo "$HTML_CACHE" | wc -c | tr -d '[:space:]') bytes)"

  [[ -n "$DIMENSIONS" ]] && info "Dimensiones: ${BOLD}${DIMENSIONS}${RESET}" || true
  [[ -n "$SECTOR"     ]] && info "Sector: ${BOLD}${SECTOR}${RESET}"         || true

  should_run "performance"    && analyze_performance    || true
  should_run "seo"            && analyze_seo            || true
  should_run "accesibilidad"  && analyze_accesibilidad  || true
  should_run "seguridad"      && analyze_seguridad      || true
  should_run "ciberseguridad" && analyze_ciberseguridad || true
  should_run "calidad"        && analyze_calidad_tecnica || true
  should_run "diseno"         && analyze_diseno         || true
  should_run "ux"             && analyze_ux             || true
  analyze_tecnologia
  analyze_legal

  # Extraer screenshots de Lighthouse si están disponibles
  SCREENSHOT_MOBILE=""; SCREENSHOT_DESKTOP=""
  if command -v jq &>/dev/null; then
    if [[ "$LH_DONE_MOBILE" == true && -f "$LH_JSON_MOBILE" ]]; then
      local ss_data
      ss_data=$(jq -r '.audits["full-page-screenshot"].details.screenshot.data // ""' "$LH_JSON_MOBILE" 2>/dev/null || echo "")
      [[ -z "$ss_data" || "$ss_data" == "null" ]] && \
        ss_data=$(jq -r '.audits["final-screenshot"].details.data // ""' "$LH_JSON_MOBILE" 2>/dev/null || echo "")
      if [[ -n "$ss_data" && "$ss_data" != "null" ]]; then
        local ss_file="${OUTPUT_DIR}/screenshot-mobile-${SLUG}-${TIMESTAMP}.webp"
        echo "$ss_data" | sed 's|^data:[^;]*;base64,||' | base64 -d > "$ss_file" 2>/dev/null \
          && SCREENSHOT_MOBILE="$ss_file" || true
        [[ -n "$SCREENSHOT_MOBILE" ]] && ok "Screenshot mobile guardado" || true
      fi
    fi
    if [[ "$LH_DONE_DESKTOP" == true && -f "$LH_JSON_DESKTOP" ]]; then
      local ss_data
      ss_data=$(jq -r '.audits["full-page-screenshot"].details.screenshot.data // ""' "$LH_JSON_DESKTOP" 2>/dev/null || echo "")
      [[ -z "$ss_data" || "$ss_data" == "null" ]] && \
        ss_data=$(jq -r '.audits["final-screenshot"].details.data // ""' "$LH_JSON_DESKTOP" 2>/dev/null || echo "")
      if [[ -n "$ss_data" && "$ss_data" != "null" ]]; then
        local ss_file="${OUTPUT_DIR}/screenshot-desktop-${SLUG}-${TIMESTAMP}.webp"
        echo "$ss_data" | sed 's|^data:[^;]*;base64,||' | base64 -d > "$ss_file" 2>/dev/null \
          && SCREENSHOT_DESKTOP="$ss_file" || true
        [[ -n "$SCREENSHOT_DESKTOP" ]] && ok "Screenshot desktop guardado" || true
      fi
    fi
  fi

  compute_global_score

  step "Generando reporte"
  generate_report "$OUT_FILE" "${PREV_REPORT:-}"
  ok "Reporte guardado: ${BOLD}${OUT_FILE}${RESET}"
  local JSON_FILE="${OUT_FILE%.md}.json"
  generate_json "$JSON_FILE"
  ok "JSON guardado: ${BOLD}${JSON_FILE}${RESET}"

  if [[ -n "${THRESHOLD:-}" ]]; then
    if (( SCORE_GLOBAL < THRESHOLD )); then
      echo -e "\n${RED}${CROSS} Score global ${SCORE_GLOBAL} < threshold ${THRESHOLD} — FALLÓ${RESET}" >&2
      exit 1
    else
      echo -e "\n${GREEN}${CHECK} Score global ${SCORE_GLOBAL} ≥ threshold ${THRESHOLD} — OK${RESET}"
    fi
  fi

  echo ""
  echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo -e "  ${BOLD}SCORE GLOBAL: $(score_color $SCORE_GLOBAL) / 100${RESET}  $(score_badge $SCORE_GLOBAL)"
  echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo ""
  progress_bar "Performance    " "$SCORE_PERFORMANCE"
  progress_bar "SEO            " "$SCORE_SEO"
  progress_bar "Accesibilidad  " "$SCORE_ACCESIBILIDAD"
  progress_bar "Seguridad      " "$SCORE_SEGURIDAD"
  progress_bar "Ciberseguridad " "$SCORE_CIBERSEGURIDAD"
  progress_bar "Calidad Técnica" "$SCORE_CALIDAD_TECNICA"
  progress_bar "Diseño         " "$SCORE_DISENO"
  progress_bar "UX             " "$SCORE_UX"
  echo ""
  echo -e "  ${DIM}${ARROW} Reporte: ${OUT_FILE}${RESET}"
  [[ -n "${PREV_REPORT:-}" ]] && echo -e "  ${DIM}${ARROW} Comparado con: ${PREV_REPORT}${RESET}"
  echo ""
}

main "$@"
