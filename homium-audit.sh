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
DATE_HUMAN=$(date +"%d de %B de %Y")
TIMEOUT=30

# ─── Temp dir (declarado primero para que todo lo use) ────────────────────────
TMPDIR_AUDIT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_AUDIT"' EXIT

DATA_FILE="${TMPDIR_AUDIT}/audit_data.json"
LH_JSON="${TMPDIR_AUDIT}/lighthouse.json"
LH_DONE=false

# ─── Resolver herramientas opcionales ─────────────────────────────────────────
resolve_cmd() {
  local bin="$1" pkg="${2:-$1}"
  if command -v "$bin" &>/dev/null; then
    echo "$bin"
  elif command -v npx &>/dev/null && npx "$pkg" --version &>/dev/null 2>&1; then
    echo "npx $pkg"
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
usage() {
  echo -e "${BOLD}homium-audit${RESET} — Auditoría profesional de sitios web"
  echo -e "  ${CYAN}Uso:${RESET} homium-audit <URL> [opciones]"
  echo -e "  ${CYAN}Opciones:${RESET}"
  echo -e "    --output <dir>    Directorio de salida (default: ~/audits)"
  echo -e "    --compare <file>  Comparar con reporte anterior"
  echo -e "    --quiet           Solo errores críticos en stdout"
  echo -e "    --help            Muestra esta ayuda"
  exit 0
}

# ─── Argument Parsing ─────────────────────────────────────────────────────────
URL=""; OUTPUT_DIR="$AUDIT_DIR"; COMPARE_FILE=""; QUIET=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)    usage ;;
    --output)     OUTPUT_DIR="$2"; shift 2 ;;
    --compare)    COMPARE_FILE="$2"; shift 2 ;;
    --quiet)      QUIET=true; shift ;;
    http*)        URL="$1"; shift ;;
    *)            echo -e "${RED}Opción desconocida: $1${RESET}"; exit 1 ;;
  esac
done

[[ -z "$URL" ]] && { echo -e "${RED}Error: Se requiere una URL.${RESET}"; usage; }

# ─── Helpers ──────────────────────────────────────────────────────────────────
log()  { [[ "$QUIET" == false ]] && echo -e "${DIM}[audit]${RESET} $*" || true; }
info() { [[ "$QUIET" == false ]] && echo -e "${BLUE}${BOLD}[•]${RESET} $*" || true; }
ok()   { [[ "$QUIET" == false ]] && echo -e "${GREEN}${CHECK}${RESET} $*" || true; }
warn() { echo -e "${YELLOW}${WARN}${RESET} $*"; }
err()  { echo -e "${RED}${CROSS}${RESET} $*" >&2; }
step() { [[ "$QUIET" == false ]] && echo -e "\n${CYAN}${BOLD}━━ $* ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}" || true; }

normalize_domain() {
  echo "$1" | sed 's|https\?://||' | sed 's|www\.||' | sed 's|[/?#].*||' \
    | sed 's|[^a-zA-Z0-9]|-|g' | tr '[:upper:]' '[:lower:]' \
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

# ─── TLS helpers ──────────────────────────────────────────────────────────────
ssl_days_remaining() {
  local domain="$1"
  local expiry_date
  expiry_date=$(echo | _timeout "$TIMEOUT" openssl s_client \
    -connect "${domain}:443" -servername "$domain" 2>/dev/null </dev/null \
    | openssl x509 -noout -enddate 2>/dev/null \
    | sed 's/notAfter=//') || { echo "-1"; return; }
  [[ -z "$expiry_date" ]] && { echo "-1"; return; }
  local exp_epoch now_epoch
  exp_epoch=$(date -j -f "%b %d %T %Y %Z" "$expiry_date" +%s 2>/dev/null \
    || date -d "$expiry_date" +%s 2>/dev/null) || { echo "-1"; return; }
  now_epoch=$(date +%s)
  echo $(( (exp_epoch - now_epoch) / 86400 ))
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

# ─── Lighthouse — una sola ejecución ─────────────────────────────────────────
run_lighthouse_once() {
  [[ "$LH_DONE" == true ]] && return 0
  [[ -z "$LH_CMD" ]] && return 1
  info "Ejecutando Lighthouse (una pasada: performance, seo, accessibility, best-practices)..."
  $LH_CMD "$URL" \
    --output=json \
    --output-path="$LH_JSON" \
    --only-categories=performance,seo,accessibility,best-practices \
    --chrome-flags="--headless --no-sandbox --disable-gpu" \
    --quiet 2>/dev/null && LH_DONE=true || true
  [[ "$LH_DONE" == true ]] && ok "Lighthouse completado" || warn "Lighthouse no pudo completar el análisis"
}

lh_score() {
  local key="$1"
  [[ "$LH_DONE" != true ]] && { echo ""; return; }
  command -v jq &>/dev/null || { echo ""; return; }
  local raw
  raw=$(jq ".categories[\"${key}\"].score // 0" "$LH_JSON" 2>/dev/null) || { echo ""; return; }
  awk "BEGIN{printf \"%d\", ${raw:-0} * 100}"
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

  if [[ "$SEC_HOST_IP" != "No resuelto" ]]; then
    local geo
    geo=$(curl -sSL --max-time 10 "https://ipinfo.io/${SEC_HOST_IP}/json" 2>/dev/null) || geo=""
    if [[ -n "$geo" ]] && command -v jq &>/dev/null; then
      SEC_HOST_COUNTRY=$(echo "$geo" | jq -r '.country // "Desconocido"' 2>/dev/null || echo "Desconocido")
      SEC_HOST_CITY=$(echo    "$geo" | jq -r '.city    // "Desconocido"' 2>/dev/null || echo "Desconocido")
      SEC_HOST_ORG=$(echo     "$geo" | jq -r '.org     // "Desconocido"' 2>/dev/null || echo "Desconocido")
      SEC_HOST_ASN=$(echo "$SEC_HOST_ORG" | grep -oE '^AS[0-9]+' || echo "Desconocido")
      SEC_HOST_PROVIDER=$(echo "$SEC_HOST_ORG" | sed 's/^AS[0-9]* //')
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
      echo "$w" | grep -qiE "privacy|redacted|protected|proxy" && SEC_DOM_PRIVACY=true || true
      [[ -z "$SEC_DOM_REGISTRAR"   ]] && SEC_DOM_REGISTRAR="Desconocido"
      [[ -z "$SEC_DOM_CREATED"     ]] && SEC_DOM_CREATED="Desconocido"
      [[ -z "$SEC_DOM_EXPIRES"     ]] && SEC_DOM_EXPIRES="Desconocido"
      [[ -z "$SEC_DOM_NAMESERVERS" ]] && SEC_DOM_NAMESERVERS="Desconocido"

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
  page_size=$(fetch_url "$URL" | wc -c 2>/dev/null) || page_size=0
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

  run_lighthouse_once
  PERF_LH_SCORE=$(lh_score "performance")
  [[ -n "$PERF_LH_SCORE" ]] && score=$(( (score + PERF_LH_SCORE) / 2 )) || true

  (( score < 0 )) && score=0; (( score > 100 )) && score=100
  set_score "performance" "$score"; SCORE_PERFORMANCE=$score
  ok "Performance score: $(score_color $score)"
}

# ─── DIMENSION 2: Calidad Técnica ─────────────────────────────────────────────
analyze_calidad_tecnica() {
  step "Analizando Calidad Técnica"
  local score=100
  local html
  html=$(fetch_url "$URL")

  CT_DOCTYPE=false; CT_LANG=false; CT_CHARSET=false; CT_VIEWPORT=false
  CT_TITLE=false;   CT_CANONICAL=false

  echo "$html" | grep -qi "<!DOCTYPE html>"     && CT_DOCTYPE=true   || true
  echo "$html" | grep -qi '<html[^>]*lang='     && CT_LANG=true      || true
  echo "$html" | grep -qi 'charset='            && CT_CHARSET=true   || true
  echo "$html" | grep -qi 'name="viewport"'     && CT_VIEWPORT=true  || true
  echo "$html" | grep -qi '<title>'             && CT_TITLE=true     || true
  echo "$html" | grep -qi 'rel="canonical"'     && CT_CANONICAL=true || true

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
  local score=100
  local html
  html=$(fetch_url "$URL")

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

  SEO_OG=false;     echo "$html" | grep -qi 'property="og:'         && SEO_OG=true     || true
  SEO_SCHEMA=false; echo "$html" | grep -qi 'application/ld+json'   && SEO_SCHEMA=true || true
  [[ "$SEO_OG"     == false ]] && score=$((score-10)) || true
  [[ "$SEO_SCHEMA" == false ]] && score=$((score-5))  || true

  local base="${URL%/}"
  SEO_ROBOTS=$(http_status "${base}/robots.txt")
  SEO_SITEMAP=$(http_status "${base}/sitemap.xml")
  [[ "$SEO_ROBOTS"  != "200" ]] && score=$((score-10)) || true
  [[ "$SEO_SITEMAP" != "200" ]] && score=$((score-10)) || true

  run_lighthouse_once
  SEO_LH_SCORE=$(lh_score "seo")
  [[ -n "$SEO_LH_SCORE" ]] && score=$(( (score + SEO_LH_SCORE) / 2 )) || true

  (( score < 0 )) && score=0; (( score > 100 )) && score=100
  set_score "seo" "$score"; SCORE_SEO=$score
  ok "SEO score: $(score_color $score)"
}

# ─── DIMENSION 4: Accesibilidad ───────────────────────────────────────────────
analyze_accesibilidad() {
  step "Analizando Accesibilidad"
  local score=100
  local html
  html=$(fetch_url "$URL")

  local imgs_total imgs_no_alt
  imgs_total=$(echo "$html" | grep -ic '<img' 2>/dev/null | tr -d '[:space:]') || imgs_total=0
  imgs_no_alt=$(echo "$html" | grep -i '<img' | grep -cv 'alt=' 2>/dev/null | tr -d '[:space:]') || imgs_no_alt=0
  ACC_IMGS_TOTAL=${imgs_total:-0}; ACC_IMGS_NO_ALT=${imgs_no_alt:-0}
  if (( ACC_IMGS_TOTAL > 0 && ACC_IMGS_NO_ALT > 0 )); then
    local pen=$(( ACC_IMGS_NO_ALT * 5 ))
    (( pen > 30 )) && pen=30
    score=$((score - pen))
  fi

  ACC_ARIA=false;  echo "$html" | grep -qi 'aria-label\|aria-labelledby\|role=' && ACC_ARIA=true  || true
  ACC_SKIP=false;  echo "$html" | grep -qi 'skip\|saltar'                        && ACC_SKIP=true  || true
  [[ "$ACC_ARIA" == false ]] && score=$((score-15)) || true
  [[ "$ACC_SKIP" == false ]] && score=$((score-10)) || true

  local forms_count labels_count
  forms_count=$(echo  "$html" | grep -ic '<form'  2>/dev/null | tr -d '[:space:]') || forms_count=0
  labels_count=$(echo "$html" | grep -ic '<label' 2>/dev/null | tr -d '[:space:]') || labels_count=0
  ACC_FORMS=${forms_count:-0}; ACC_LABELS=${labels_count:-0}
  (( ACC_FORMS > 0 && ACC_LABELS < ACC_FORMS )) && score=$((score-15)) || true

  echo "$html" | grep -qi '<html[^>]*lang=' || score=$((score-10)) || true

  run_lighthouse_once
  ACC_LH_SCORE=$(lh_score "accessibility")
  [[ -n "$ACC_LH_SCORE" ]] && score=$(( (score + ACC_LH_SCORE) / 2 )) || true

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

  [[ "$SEC_HSTS" == false ]] && score=$((score-20)) || true
  [[ "$SEC_CSP"  == false ]] && score=$((score-20)) || true
  [[ "$SEC_XCTO" == false ]] && score=$((score-15)) || true
  [[ "$SEC_XFO"  == false ]] && score=$((score-15)) || true
  [[ "$SEC_RP"   == false ]] && score=$((score-10)) || true
  [[ "$SEC_PER"  == false ]] && score=$((score-10)) || true

  local http_code
  http_code=$(http_status "http://${domain}")
  [[ "$http_code" == "301" || "$http_code" == "302" ]] && SEC_HTTPS_REDIRECT=true || SEC_HTTPS_REDIRECT=false
  [[ "$SEC_HTTPS_REDIRECT" == false ]] && score=$((score-15)) || true

  # SSL expiry
  info "Verificando expiración SSL..."
  local ssl_days
  ssl_days=$(ssl_days_remaining "$domain")
  SEC_SSL_DAYS=${ssl_days:--1}
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

  local dirs=("/admin" "/backup" "/.git" "/config" "/uploads")
  CYBER_EXPOSED_DIRS=()
  for d in "${dirs[@]}"; do
    local st; st=$(http_status "${URL%/}${d}")
    [[ "$st" == "200" ]] && CYBER_EXPOSED_DIRS+=("$d") && score=$((score-10)) || true
  done
  [[ ${#CYBER_EXPOSED_DIRS[@]} -eq 0 ]] && CYBER_EXPOSED_DIRS=("Ninguno detectado")

  local sec_txt; sec_txt=$(http_status "${URL%/}/.well-known/security.txt")
  CYBER_SEC_TXT="$sec_txt"
  [[ "$sec_txt" != "200" ]] && score=$((score-5)) || true

  CYBER_SPF="No verificable"; CYBER_DMARC="No verificable"
  # dig → curl DNS API fallback (funciona en Git Bash/Windows)
  dns_txt_lookup() {
    local host="$1"
    if command -v dig &>/dev/null; then
      dig TXT "$host" +short 2>/dev/null | tr -d '"' || echo ""
    else
      curl -sSL --max-time 10         "https://dns.google/resolve?name=${host}&type=TXT" 2>/dev/null         | perl -nle 'print $1 if /"data":"([^"]+)"/' || echo ""
    fi
  }
  spf_raw=$(dns_txt_lookup "$domain")
  dmarc_raw=$(dns_txt_lookup "_dmarc.${domain}")
  CYBER_SPF=$(echo "$spf_raw"   | grep -i "v=spf"  | head -1 || echo "AUSENTE")
  CYBER_DMARC=$(echo "$dmarc_raw" | grep -i "v=DMARC" | head -1 || echo "AUSENTE")
  [[ -z "$CYBER_SPF"   ]] && CYBER_SPF="AUSENTE"
  [[ -z "$CYBER_DMARC" ]] && CYBER_DMARC="AUSENTE"
  [[ "$CYBER_SPF"   == "AUSENTE" ]] && score=$((score-10)) || true
  [[ "$CYBER_DMARC" == "AUSENTE" ]] && score=$((score-10)) || true

  (( score < 0 )) && score=0; (( score > 100 )) && score=100
  set_score "ciberseguridad" "$score"; SCORE_CIBERSEGURIDAD=$score
  ok "Ciberseguridad score: $(score_color $score)"
}

# ─── DIMENSION 7: Diseño ──────────────────────────────────────────────────────
analyze_diseno() {
  step "Analizando Diseño"
  local score=70
  local html
  html=$(fetch_url "$URL")

  DIS_VIEWPORT=false; echo "$html" | grep -qi 'name="viewport"' && DIS_VIEWPORT=true || true
  [[ "$DIS_VIEWPORT" == false ]] && score=$((score-20)) || true

  DIS_FRAMEWORKS=()
  echo "$html" | grep -qi "bootstrap"   && DIS_FRAMEWORKS+=("Bootstrap")   || true
  echo "$html" | grep -qi "tailwind"    && DIS_FRAMEWORKS+=("Tailwind CSS") || true
  echo "$html" | grep -qi "materialize" && DIS_FRAMEWORKS+=("Materialize")  || true
  echo "$html" | grep -qi "foundation"  && DIS_FRAMEWORKS+=("Foundation")   || true
  [[ ${#DIS_FRAMEWORKS[@]} -eq 0 ]] && DIS_FRAMEWORKS=("CSS propio")

  DIS_FONTS=false;     echo "$html" | grep -qi "fonts.googleapis\|font-face"        && DIS_FONTS=true     || true
  DIS_FAVICON=false;   echo "$html" | grep -qi 'rel="icon"\|rel="shortcut icon"'    && DIS_FAVICON=true   || true
  DIS_DARK_MODE=false; echo "$html" | grep -qi "prefers-color-scheme\|color-scheme" && DIS_DARK_MODE=true || true
  [[ "$DIS_FAVICON" == false ]] && score=$((score-5)) || true

  run_lighthouse_once
  DIS_LH_SCORE=$(lh_score "best-practices")
  [[ -n "$DIS_LH_SCORE" ]] && score=$(( (score + DIS_LH_SCORE) / 2 )) || true

  (( score < 0 )) && score=0; (( score > 100 )) && score=100
  set_score "diseno" "$score"; SCORE_DISENO=$score
  ok "Diseño score: $(score_color $score)"
}

# ─── DIMENSION 8: UX ──────────────────────────────────────────────────────────
analyze_ux() {
  step "Analizando UX"
  local score=70
  local html
  html=$(fetch_url "$URL")

  UX_NAV=false;       echo "$html" | grep -qi '<nav\|role="navigation"'             && UX_NAV=true       || true
  UX_SEARCH=false;    echo "$html" | grep -qi 'type="search"\|input.*search'         && UX_SEARCH=true    || true
  UX_CONTACT=false;   echo "$html" | grep -qi 'contact\|contacto\|mailto:\|tel:'    && UX_CONTACT=true   || true
  UX_CTA=false;       echo "$html" | grep -qi 'btn\|button\|comprar\|registr\|sign' && UX_CTA=true       || true
  UX_RESPONSIVE=false;echo "$html" | grep -qi "@media\|max-width:\|min-width:"      && UX_RESPONSIVE=true|| true
  UX_LOADING=false;   echo "$html" | grep -qi "loading\|spinner\|skeleton"          && UX_LOADING=true   || true

  [[ "$UX_NAV"       == false ]] && score=$((score-15)) || true
  [[ "$UX_CTA"       == false ]] && score=$((score-15)) || true
  [[ "$UX_CONTACT"   == false ]] && score=$((score-10)) || true
  [[ "$UX_RESPONSIVE" == false ]] && score=$((score-20)) || true

  UX_404=$(http_status "${URL%/}/pagina-que-no-existe-audit-xyz123")
  [[ "$UX_404" != "404" ]] && score=$((score-10)) || true

  (( score < 0 )) && score=0; (( score > 100 )) && score=100
  set_score "ux" "$score"; SCORE_UX=$score
  ok "UX score: $(score_color $score)"
}

# ─── Legal & Privacidad ───────────────────────────────────────────────────────
analyze_legal() {
  step "Analizando Legal & Privacidad"
  local html
  html=$(fetch_url "$URL")

  LEGAL_PRIVACY=false; echo "$html" | grep -qi "privacy\|privacidad\|política"          && LEGAL_PRIVACY=true || true
  LEGAL_TERMS=false;   echo "$html" | grep -qi "terms\|condiciones\|aviso.legal"         && LEGAL_TERMS=true   || true
  LEGAL_COOKIES=false; echo "$html" | grep -qi "cookie\|gdpr\|rgpd\|consent"             && LEGAL_COOKIES=true || true
  LEGAL_GDPR=false;    echo "$html" | grep -qi "gdpr\|rgpd\|reglamento.*datos"           && LEGAL_GDPR=true    || true

  LEGAL_TRACKERS=()
  echo "$html" | grep -qi "google-analytics\|gtag\|ga.js" && LEGAL_TRACKERS+=("Google Analytics") || true
  echo "$html" | grep -qi "facebook\|fbevents\|fbq("      && LEGAL_TRACKERS+=("Facebook Pixel")   || true
  echo "$html" | grep -qi "hotjar"                         && LEGAL_TRACKERS+=("Hotjar")           || true
  echo "$html" | grep -qi "mixpanel"                       && LEGAL_TRACKERS+=("Mixpanel")         || true
  echo "$html" | grep -qi "segment"                        && LEGAL_TRACKERS+=("Segment")          || true
  echo "$html" | grep -qi "hubspot"                        && LEGAL_TRACKERS+=("HubSpot")          || true
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

# ─── Generate report ──────────────────────────────────────────────────────────
generate_report() {
  local out_file="$1" prev_report="${2:-}"
  local domain="${URL#*://}"; domain="${domain%%/*}"
  local global_badge; global_badge=$(score_badge "$SCORE_GLOBAL")

  cat > "$out_file" << MDEOF
# 🔍 Auditoría Web Profesional — ${domain}

> **Generado por:** [homium-audit](https://github.com/homium-tech/audit) v1.1.0
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

---

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

## 🏆 Benchmarking

| Dimensión | Tu sitio | Promedio sector | Top 10% |
|-----------|:--------:|:--------------:|:-------:|
| Performance | ${SCORE_PERFORMANCE} | 65 | 90+ |
| SEO | ${SCORE_SEO} | 70 | 90+ |
| Accesibilidad | ${SCORE_ACCESIBILIDAD} | 55 | 85+ |
| Seguridad | ${SCORE_SEGURIDAD} | 50 | 90+ |
| Ciberseguridad | ${SCORE_CIBERSEGURIDAD} | 45 | 85+ |
| Calidad Técnica | ${SCORE_CALIDAD_TECNICA} | 60 | 85+ |
| Diseño | ${SCORE_DISENO} | 65 | 90+ |
| UX | ${SCORE_UX} | 60 | 88+ |

---

## 🔎 Hallazgos por Dimensión

### ⚡ 1. Performance — ${SCORE_PERFORMANCE}/100 $(score_badge $SCORE_PERFORMANCE)

| Hallazgo | Valor | Severidad |
|----------|-------|-----------|
| Tiempo de respuesta | ${PERF_RESP_MS}ms | $(severity_badge ${PERF_RESP_SEVERITY:-bajo}) |
| Tamaño HTML | ${PERF_SIZE_KB}KB | $([ ${PERF_SIZE_KB:-0} -gt 200 ] && echo "🟡 MEDIO" || echo "🟢 BAJO") |
| Protocolo | ${PERF_PROTOCOL} | $(echo "$PERF_PROTOCOL" | grep -q "2\|3" && echo "🟢 OK" || echo "🟡 MEDIO") |
| Compresión | $(echo "$PERF_COMPRESSION" | grep -qi "gzip\|br\|deflate" && echo "✅ Activa" || echo "❌ Inactiva") | $(echo "$PERF_COMPRESSION" | grep -qi "gzip\|br\|deflate" && echo "🟢 OK" || echo "🟡 MEDIO") |
$([ -n "${PERF_LH_SCORE:-}" ] && echo "| Lighthouse | ${PERF_LH_SCORE}/100 | — |")

**💡 Recomendaciones:**
- $([ "${PERF_RESP_SEVERITY:-bajo}" != "bajo" ] && echo "🟠 Optimizar TTFB a <200ms (CDN, caché, servidor)" || echo "Tiempo de respuesta óptimo ✓")
- $(echo "$PERF_PROTOCOL" | grep -q "2\|3" || echo "🟡 Migrar a HTTP/2 o HTTP/3")
- $(echo "$PERF_COMPRESSION" | grep -qi "gzip\|br\|deflate" || echo "🟡 Activar compresión Gzip/Brotli en el servidor")
- Implementar lazy loading para imágenes y revisar Core Web Vitals (LCP, FID, CLS)

---

### 🔍 2. SEO — ${SCORE_SEO}/100 $(score_badge $SCORE_SEO)

| Elemento | Estado | Detalle |
|----------|--------|---------|
| \`<title>\` | $([ "$SEO_TITLE" == "AUSENTE" ] && echo "❌" || echo "✅") | ${SEO_TITLE:0:60} (${SEO_TITLE_LEN} chars) |
| Meta description | $([ "$SEO_META_DESC" == "AUSENTE" ] && echo "❌" || echo "✅") | ${SEO_META_DESC_LEN} chars |
| H1 | $([ "${SEO_H1_COUNT:-0}" -eq 1 ] && echo "✅" || echo "⚠️") | ${SEO_H1_COUNT:-0} encontrados |
| Open Graph | $([ "$SEO_OG" == "true" ] && echo "✅" || echo "❌") | — |
| robots.txt | $([ "$SEO_ROBOTS" == "200" ] && echo "✅" || echo "❌") | HTTP ${SEO_ROBOTS} |
| sitemap.xml | $([ "$SEO_SITEMAP" == "200" ] && echo "✅" || echo "❌") | HTTP ${SEO_SITEMAP} |
| Schema.org | $([ "$SEO_SCHEMA" == "true" ] && echo "✅" || echo "❌") | — |
$([ -n "${SEO_LH_SCORE:-}" ] && echo "| Lighthouse SEO | ✅ ${SEO_LH_SCORE}/100 | — |")

**💡 Recomendaciones:**
- $([ "$SEO_TITLE"    == "AUSENTE" ] && echo "🔴 CRÍTICO: Añadir \`<title>\` único (30-60 chars)"           || echo "Title tag presente ✓")
- $([ "$SEO_META_DESC"== "AUSENTE" ] && echo "🟠 ALTO: Crear meta description (120-160 chars)"             || echo "Meta description presente ✓")
- $([ "$SEO_ROBOTS"   != "200"    ] && echo "🟡 MEDIO: Crear robots.txt en la raíz"                       || echo "robots.txt encontrado ✓")
- $([ "$SEO_SITEMAP"  != "200"    ] && echo "🟡 MEDIO: Generar sitemap.xml y registrar en Search Console" || echo "sitemap.xml encontrado ✓")
- $([ "$SEO_SCHEMA"   != "true"   ] && echo "🟡 MEDIO: Implementar Schema.org para rich snippets"         || echo "Schema.org implementado ✓")

---

### ♿ 3. Accesibilidad — ${SCORE_ACCESIBILIDAD}/100 $(score_badge $SCORE_ACCESIBILIDAD)

| Elemento | Estado | Detalle |
|----------|--------|---------|
| Imágenes con alt | $([ "${ACC_IMGS_NO_ALT:-0}" -eq 0 ] && echo "✅" || echo "⚠️") | ${ACC_IMGS_TOTAL:-0} imgs · ${ACC_IMGS_NO_ALT:-0} sin alt |
| ARIA labels | $([ "$ACC_ARIA" == "true" ] && echo "✅" || echo "❌") | — |
| Skip navigation | $([ "$ACC_SKIP" == "true" ] && echo "✅" || echo "❌") | — |
| Formularios/Labels | $([ "${ACC_FORMS:-0}" -eq 0 ] || [ "${ACC_LABELS:-0}" -ge "${ACC_FORMS:-0}" ] && echo "✅" || echo "⚠️") | ${ACC_FORMS:-0} forms · ${ACC_LABELS:-0} labels |
$([ -n "${ACC_LH_SCORE:-}" ] && echo "| Lighthouse A11y | ✅ ${ACC_LH_SCORE}/100 | — |")
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
| **Registrador dominio** | ${SEC_DOM_REGISTRAR:-Desconocido} |
| **Dominio creado** | ${SEC_DOM_CREATED:-Desconocido} |
| **Dominio expira** | ${SEC_DOM_EXPIRES:-Desconocido} ${SEC_DOM_EXPIRY_NOTE:+— $SEC_DOM_EXPIRY_NOTE} |
| **Última actualización** | ${SEC_DOM_UPDATED:-Desconocido} |
| **Nameservers** | \`${SEC_DOM_NAMESERVERS:-Desconocido}\` |
| **Privacidad WHOIS** | $([ "$SEC_DOM_PRIVACY" == "true" ] && echo "✅ Activada" || echo "⚠️ Datos expuestos") |

#### 🔐 Certificado SSL

| Elemento | Estado |
|----------|--------|
| Expiración SSL | ${SEC_SSL_EXPIRY_NOTE:-No verificado} |
$([ -n "${SEC_SSLCHECK_RESULT:-}" ] && echo "| ssl-checker | \`${SEC_SSLCHECK_RESULT}\` |")

#### 🛡️ Headers de Seguridad

| Header | Estado | Importancia |
|--------|--------|-------------|
| Strict-Transport-Security (HSTS) | $([ "$SEC_HSTS" == "true" ] && echo "✅" || echo "❌") | 🔴 Crítico |
| Content-Security-Policy (CSP)    | $([ "$SEC_CSP"  == "true" ] && echo "✅" || echo "❌") | 🔴 Crítico |
| X-Content-Type-Options           | $([ "$SEC_XCTO" == "true" ] && echo "✅" || echo "❌") | 🟠 Alto |
| X-Frame-Options                  | $([ "$SEC_XFO"  == "true" ] && echo "✅" || echo "❌") | 🟠 Alto |
| Referrer-Policy                  | $([ "$SEC_RP"   == "true" ] && echo "✅" || echo "❌") | 🟡 Medio |
| Permissions-Policy               | $([ "$SEC_PER"  == "true" ] && echo "✅" || echo "❌") | 🟡 Medio |
| HTTPS Redirect                   | $([ "$SEC_HTTPS_REDIRECT" == "true" ] && echo "✅" || echo "❌") | 🔴 Crítico |
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
| security.txt | $([ "$CYBER_SEC_TXT" == "200" ] && echo "✅" || echo "⚠️") | HTTP ${CYBER_SEC_TXT} |
| SPF Record | $(echo "$CYBER_SPF" | grep -qi "v=spf" && echo "✅" || echo "⚠️") | \`${CYBER_SPF:0:60}\` |
| DMARC Record | $(echo "$CYBER_DMARC" | grep -qi "v=DMARC" && echo "✅" || echo "⚠️") | \`${CYBER_DMARC:0:60}\` |

**💡 Recomendaciones:**
- $(echo "$CYBER_SERVER" | grep -qiE "[0-9]\.|apache|nginx|iis|php" && echo "🟠 Ocultar versión en header Server" || echo "Server header sin versión ✓")
- $([ "$CYBER_SEC_TXT" != "200" ] && echo "🟢 Crear \`/.well-known/security.txt\` con contacto de seguridad" || echo "security.txt presente ✓")
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
$([ "${CT_HTMLHINT_ERRORS:-0}" -gt 0 ] && echo "| htmlhint errores | ⚠️ ${CT_HTMLHINT_ERRORS} | ${CT_HTMLHINT_WARNINGS:-0} warnings |" || echo "| htmlhint | ✅ Sin errores | — |")

**💡 Recomendaciones:**
- $([ "$CT_DOCTYPE"   != "true" ] && echo "🔴 Añadir \`<!DOCTYPE html>\`" || echo "DOCTYPE correcto ✓")
- $([ "$CT_LANG"      != "true" ] && echo "🟠 Añadir atributo \`lang\` al elemento \`<html>\`" || echo "Lang presente ✓")
- $([ "$CT_CANONICAL" != "true" ] && echo "🟡 Implementar URLs canónicas para evitar contenido duplicado" || echo "Canonical presente ✓")

---

### 🎨 7. Diseño — ${SCORE_DISENO}/100 $(score_badge $SCORE_DISENO)

| Elemento | Estado | Detalle |
|----------|--------|---------|
| Responsive | $([ "$DIS_VIEWPORT"   == "true" ] && echo "✅" || echo "❌") | — |
| Framework CSS | ✅ | ${DIS_FRAMEWORKS[*]} |
| Tipografía web | $([ "$DIS_FONTS"     == "true" ] && echo "✅" || echo "➖") | — |
| Favicon | $([ "$DIS_FAVICON"   == "true" ] && echo "✅" || echo "⚠️") | — |
| Dark mode | $([ "$DIS_DARK_MODE" == "true" ] && echo "✅" || echo "➖") | — |
$([ -n "${DIS_LH_SCORE:-}" ] && echo "| Lighthouse Best Practices | ✅ ${DIS_LH_SCORE}/100 | — |")

---

### 👤 8. UX — ${SCORE_UX}/100 $(score_badge $SCORE_UX)

| Elemento | Estado |
|----------|--------|
| Navegación \`<nav>\` | $([ "$UX_NAV"        == "true" ] && echo "✅" || echo "❌") |
| Buscador | $([ "$UX_SEARCH"    == "true" ] && echo "✅" || echo "➖") |
| Contacto visible | $([ "$UX_CONTACT"  == "true" ] && echo "✅" || echo "❌") |
| CTAs | $([ "$UX_CTA"       == "true" ] && echo "✅" || echo "⚠️") |
| Responsive | $([ "$UX_RESPONSIVE"== "true" ] && echo "✅" || echo "❌") |
| Loading states | $([ "$UX_LOADING"  == "true" ] && echo "✅" || echo "➖") |
| Página 404 custom | $([ "$UX_404" == "404" ] && echo "✅" || echo "⚠️") |

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

## 🎯 Matriz de Priorización

| Prioridad | Acción | Impacto | Esfuerzo | Dimensión |
|:---------:|--------|:-------:|:--------:|-----------|
$([ "$SEC_HSTS"    != "true"   ] && echo "| 🔴 1 | Implementar HSTS | 4 | 1 | Seguridad |")
$([ "$SEC_CSP"     != "true"   ] && echo "| 🔴 2 | Configurar CSP | 4 | 2 | Seguridad |")
$([ "$SEO_TITLE"   == "AUSENTE"] && echo "| 🔴 3 | Añadir title tag | 4 | 1 | SEO |")
$([ "$SEO_META_DESC"=="AUSENTE"] && echo "| 🟠 4 | Meta descriptions | 3 | 1 | SEO |")
$([ "$LEGAL_COOKIES"!= "true"  ] && echo "| 🟠 5 | Banner cookies GDPR | 3 | 2 | Legal |")
$([ "$ACC_ARIA"    != "true"   ] && echo "| 🟠 6 | ARIA labels | 3 | 2 | Accesibilidad |")
$([ "$SEO_SITEMAP" != "200"    ] && echo "| 🟡 7 | Generar sitemap.xml | 2 | 1 | SEO |")
$([ "$SEO_SCHEMA"  != "true"   ] && echo "| 🟡 8 | Schema.org | 2 | 2 | SEO |")
$([ "$DIS_FAVICON" != "true"   ] && echo "| 🟢 9 | Favicon | 1 | 1 | Diseño |")

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
| Global | $(grep "Score Global" "$prev_report" 2>/dev/null | perl -nle 'print $1 if /([0-9]+) \/ 100/' | head -1 || echo "N/A") | $SCORE_GLOBAL | — |
| Performance | $(extract_prev_score "$prev_report" "Performance") | $SCORE_PERFORMANCE | — |
| SEO | $(extract_prev_score "$prev_report" "SEO") | $SCORE_SEO | — |
| Seguridad | $(extract_prev_score "$prev_report" "Seguridad") | $SCORE_SEGURIDAD | — |

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

### Sprint 1 — Esta semana
- [ ] Configurar headers HSTS, CSP, X-Content-Type-Options
- [ ] $([ "$SEO_TITLE" == "AUSENTE" ] && echo "Añadir title tags únicos" || echo "Revisar title tags")
- [ ] Activar compresión Gzip/Brotli
- [ ] $([ "$LEGAL_COOKIES" != "true" ] && echo "Implementar banner de cookies GDPR" || echo "Revisar banner de cookies")

### Sprint 2 — Próximas 4 semanas
- [ ] Optimizar meta descriptions y Open Graph
- [ ] Sitemap.xml + Google Search Console
- [ ] ARIA labels en componentes interactivos
- [ ] SPF y DMARC en DNS

### Sprint 3 — Próximos 3 meses
- [ ] Schema.org structured data
- [ ] Auditoría WCAG 2.1 AA completa
- [ ] Monitoreo continuo (uptime + Core Web Vitals)
- [ ] Revisión legal de política de privacidad

---

*[homium-audit](https://github.com/homium-tech/audit) v1.1.0 · ${DATE_HUMAN}*
MDEOF
}

# ─── MAIN ─────────────────────────────────────────────────────────────────────
main() {
  echo -e "\n${BOLD}${CYAN}╔══════════════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}${CYAN}║        homium-audit v1.1.0                   ║${RESET}"
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

  analyze_performance
  analyze_seo
  analyze_accesibilidad
  analyze_seguridad
  analyze_ciberseguridad
  analyze_calidad_tecnica
  analyze_diseno
  analyze_ux
  analyze_legal

  compute_global_score

  step "Generando reporte"
  generate_report "$OUT_FILE" "${PREV_REPORT:-}"
  ok "Reporte guardado: ${BOLD}${OUT_FILE}${RESET}"

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
