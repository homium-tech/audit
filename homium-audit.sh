#!/usr/bin/env bash
# =============================================================================
# homium-audit — Web Audit Tool for Claude Code
# Repo: homium-tech/audit
# Version: 1.0.0
# =============================================================================

set -euo pipefail

# ─── Colors & Symbols ────────────────────────────────────────────────────────
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'
CHECK="✓"
CROSS="✗"
ARROW="→"
WARN="⚠"

# ─── Config ───────────────────────────────────────────────────────────────────
AUDIT_DIR="${HOME}/audits"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DATE_HUMAN=$(date +"%d de %B de %Y")
TIMEOUT=30

# Resolver lighthouse: binario global o npx fallback
if command -v lighthouse &>/dev/null; then
  LH_CMD="lighthouse"
elif npx lighthouse --version &>/dev/null 2>&1; then
  LH_CMD="npx lighthouse"
else
  LH_CMD=""
fi

# Resolver herramientas opcionales via npx si no están globales
resolve_npx_tool() {
  local tool="$1" pkg="${2:-$1}"
  if command -v "$tool" &>/dev/null; then
    echo "$tool"
  elif npx --yes "$pkg" --version &>/dev/null 2>&1; then
    echo "npx $pkg"
  else
    echo ""
  fi
}

AXE_CMD=$(resolve_npx_tool "axe" "@axe-core/cli")
PA11Y_CMD=$(resolve_npx_tool "pa11y" "pa11y")
HTMLHINT_CMD=$(resolve_npx_tool "htmlhint" "htmlhint")
SSLCHECK_CMD=$(resolve_npx_tool "ssl-checker" "ssl-checker")

# ─── Usage ───────────────────────────────────────────────────────────────────
usage() {
  echo -e "${BOLD}homium-audit${RESET} — Auditoría profesional de sitios web"
  echo ""
  echo -e "  ${CYAN}Uso:${RESET} homium-audit <URL> [opciones]"
  echo ""
  echo -e "  ${CYAN}Opciones:${RESET}"
  echo -e "    --output <dir>    Directorio de salida (default: ~/audits)"
  echo -e "    --format <fmt>    Formato: md, json, html (default: md)"
  echo -e "    --dimensions <d>  Dimensiones separadas por coma"
  echo -e "                      (default: todas)"
  echo -e "    --compare <file>  Comparar con reporte anterior específico"
  echo -e "    --quiet           Solo errores críticos en stdout"
  echo -e "    --help            Muestra esta ayuda"
  echo ""
  echo -e "  ${CYAN}Dimensiones disponibles:${RESET}"
  echo -e "    performance, seo, accesibilidad, seguridad,"
  echo -e "    ciberseguridad, diseño, ux, calidad-tecnica"
  echo ""
  echo -e "  ${CYAN}Ejemplos:${RESET}"
  echo -e "    homium-audit https://example.com"
  echo -e "    homium-audit https://example.com --dimensions seo,performance"
  echo -e "    homium-audit https://example.com --output /tmp/reportes"
  exit 0
}

# ─── Argument Parsing ─────────────────────────────────────────────────────────
URL=""
OUTPUT_DIR="$AUDIT_DIR"
FORMAT="md"
DIMENSIONS="all"
COMPARE_FILE=""
QUIET=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage ;;
    --output) OUTPUT_DIR="$2"; shift 2 ;;
    --format) FORMAT="$2"; shift 2 ;;
    --dimensions) DIMENSIONS="$2"; shift 2 ;;
    --compare) COMPARE_FILE="$2"; shift 2 ;;
    --quiet) QUIET=true; shift ;;
    http*) URL="$1"; shift ;;
    *) echo -e "${RED}Opción desconocida: $1${RESET}"; exit 1 ;;
  esac
done

[[ -z "$URL" ]] && { echo -e "${RED}Error: Se requiere una URL.${RESET}"; usage; }

# ─── Helpers ──────────────────────────────────────────────────────────────────
log()  { [[ "$QUIET" == false ]] && echo -e "${DIM}[audit]${RESET} $*"; }
info() { [[ "$QUIET" == false ]] && echo -e "${BLUE}${BOLD}[•]${RESET} $*"; }
ok()   { [[ "$QUIET" == false ]] && echo -e "${GREEN}${CHECK}${RESET} $*"; }
warn() { echo -e "${YELLOW}${WARN}${RESET} $*"; }
err()  { echo -e "${RED}${CROSS}${RESET} $*" >&2; }
step() { [[ "$QUIET" == false ]] && echo -e "\n${CYAN}${BOLD}━━ $* ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"; }

# Normalize URL → domain slug for filenames
normalize_domain() {
  local url="$1"
  echo "$url" \
    | sed 's|https\?://||' \
    | sed 's|www\.||' \
    | sed 's|[/?#].*||' \
    | sed 's|[^a-zA-Z0-9]|-|g' \
    | tr '[:upper:]' '[:lower:]' \
    | sed 's|-\+|-|g' \
    | sed 's|^-\|-$||g'
}

# Progress bar
progress_bar() {
  local label="$1"
  local pct="$2"
  local width=30
  local filled=$(( pct * width / 100 ))
  local empty=$(( width - filled ))
  local bar=""
  for ((i=0; i<filled; i++)); do bar+="█"; done
  for ((i=0; i<empty; i++));  do bar+="░"; done
  echo -e "  ${label}: ${CYAN}${bar}${RESET} ${BOLD}${pct}%${RESET}"
}

# Score → color
score_color() {
  local s="$1"
  if   (( s >= 80 )); then echo -e "${GREEN}${s}${RESET}"
  elif (( s >= 60 )); then echo -e "${YELLOW}${s}${RESET}"
  else                     echo -e "${RED}${s}${RESET}"
  fi
}

# Score → emoji badge
score_badge() {
  local s="$1"
  if   (( s >= 90 )); then echo "🟢"
  elif (( s >= 70 )); then echo "🟡"
  elif (( s >= 50 )); then echo "🟠"
  else                     echo "🔴"
  fi
}

# Severity label
severity_badge() {
  case "$1" in
    critico)  echo "🔴 CRÍTICO" ;;
    alto)     echo "🟠 ALTO"    ;;
    medio)    echo "🟡 MEDIO"   ;;
    bajo)     echo "🟢 BAJO"    ;;
    *)        echo "⚪ INFO"    ;;
  esac
}

# Check tool availability
require_tool() {
  local tool="$1"
  if [[ "$tool" == "lighthouse" ]]; then
    [[ -n "$LH_CMD" ]] && return 0
    warn "Herramienta no disponible: ${BOLD}lighthouse${RESET} — análisis parcial en esta dimensión."
    return 1
  fi
  if ! command -v "$tool" &>/dev/null; then
    warn "Herramienta no disponible: ${BOLD}$tool${RESET} — análisis parcial en esta dimensión."
    return 1
  fi
  return 0
}

# Safe curl fetch
fetch_url() {
  local url="$1"
  local flags="${2:--sSL}"
  curl $flags \
    --max-time "$TIMEOUT" \
    --user-agent "Mozilla/5.0 (compatible; homium-audit/1.0)" \
    "$url" 2>/dev/null
}

# HTTP status code
http_status() {
  curl -sSLo /dev/null --max-time "$TIMEOUT" \
    -w "%{http_code}" \
    --user-agent "Mozilla/5.0 (compatible; homium-audit/1.0)" \
    "$1" 2>/dev/null || echo "000"
}

# Response time in ms
response_time_ms() {
  curl -sSLo /dev/null --max-time "$TIMEOUT" \
    -w "%{time_total}" \
    --user-agent "Mozilla/5.0 (compatible; homium-audit/1.0)" \
    "$1" 2>/dev/null | awk '{printf "%d", $1*1000}' || echo "0"
}

# TLS/SSL info con expiración
check_tls() {
  local domain="$1"
  local result
  result=$(echo | timeout "$TIMEOUT" openssl s_client -connect "${domain}:443"     -servername "$domain" 2>/dev/null </dev/null |     openssl x509 -noout -dates -subject 2>/dev/null) || true
  echo "$result"
}

# Días hasta expiración del certificado SSL
ssl_days_remaining() {
  local domain="$1"
  local expiry_date
  expiry_date=$(echo | timeout "$TIMEOUT" openssl s_client     -connect "${domain}:443" -servername "$domain" 2>/dev/null </dev/null     | openssl x509 -noout -enddate 2>/dev/null     | sed 's/notAfter=//') || { echo "-1"; return; }
  [[ -z "$expiry_date" ]] && { echo "-1"; return; }
  local expiry_epoch now_epoch
  expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null || date -jf "%b %d %T %Y %Z" "$expiry_date" +%s 2>/dev/null) || { echo "-1"; return; }
  now_epoch=$(date +%s)
  echo $(( (expiry_epoch - now_epoch) / 86400 ))
}

# ─── Dependency Check ─────────────────────────────────────────────────────────
check_dependencies() {
  step "Verificando dependencias"
  local missing=()
  local tools=(curl openssl)
  local optional=(htmlq jq node npm)

  for t in "${tools[@]}"; do
    if command -v "$t" &>/dev/null; then ok "$t"; else missing+=("$t"); err "$t (requerido)"; fi
  done
  for t in "${optional[@]}"; do
    if command -v "$t" &>/dev/null; then ok "$t"; else warn "$t (opcional — análisis reducido)"; fi
  done

  # Lighthouse via global o npx
  if [[ -n "$LH_CMD" ]]; then
    ok "lighthouse (${LH_CMD})"
  else
    warn "lighthouse (opcional — npm install -g lighthouse)"
  fi

  # Herramientas opcionales adicionales
  for pair in "axe:AXE_CMD:@axe-core/cli" "pa11y:PA11Y_CMD:pa11y" "htmlhint:HTMLHINT_CMD:htmlhint" "ssl-checker:SSLCHECK_CMD:ssl-checker"; do
    local tname="${pair%%:*}" rest="${pair#*:}" varname="${rest%%:*}" pkg="${rest##*:}"
    local cmd="${!varname}"
    if [[ -n "$cmd" ]]; then
      ok "${tname} (${cmd})"
    else
      warn "${tname} (opcional — npm i -g ${pkg})"
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    err "Faltan herramientas requeridas: ${missing[*]}"
    err "Instálalas y vuelve a intentar."
    exit 1
  fi
}

# ─── Lighthouse — ejecución única con todas las categorías ───────────────────
LH_DONE=false
LH_JSON="${TMPDIR_AUDIT}/lighthouse.json"

run_lighthouse_once() {
  [[ "$LH_DONE" == true ]] && return 0
  [[ -z "$LH_CMD" ]] && return 1
  info "Ejecutando Lighthouse (una sola pasada: performance, SEO, accesibilidad, best-practices)..."
  if $LH_CMD "$URL"     --output=json     --output-path="$LH_JSON"     --only-categories=performance,seo,accessibility,best-practices     --chrome-flags="--headless --no-sandbox --disable-gpu"     --quiet 2>/dev/null; then
    LH_DONE=true
    ok "Lighthouse completado"
    return 0
  fi
  return 1
}

lh_score() {
  local key="$1"   # performance | seo | accessibility | best-practices
  [[ "$LH_DONE" != true ]] && { echo ""; return; }
  command -v jq &>/dev/null || { echo ""; return; }
  local raw
  raw=$(jq ".categories["${key}"].score // 0" "$LH_JSON" 2>/dev/null) || { echo ""; return; }
  awk "BEGIN{printf "%d", ${raw} * 100}"
}

# ─── Data Storage (JSON tempfile) ─────────────────────────────────────────────
TMPDIR_AUDIT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_AUDIT"' EXIT

DATA_FILE="${TMPDIR_AUDIT}/audit_data.json"
cat > "$DATA_FILE" <<JSON
{
  "url": "$URL",
  "timestamp": "$TIMESTAMP",
  "date_human": "$DATE_HUMAN",
  "scores": {},
  "findings": {},
  "meta": {}
}
JSON

set_score() {
  local key="$1" val="$2"
  if command -v jq &>/dev/null; then
    local tmp
    tmp=$(jq ".scores[\"$key\"] = $val" "$DATA_FILE")
    echo "$tmp" > "$DATA_FILE"
  fi
}

get_score() {
  local key="$1"
  if command -v jq &>/dev/null; then
    jq -r ".scores[\"$key\"] // 0" "$DATA_FILE" 2>/dev/null || echo "0"
  else
    echo "0"
  fi
}

# ─── DIMENSION 1: Performance ──────────────────────────────────────────────────
analyze_performance() {
  step "Analizando Performance"
  local score=100

  # Response time
  info "Midiendo tiempo de respuesta..."
  local resp_ms
  resp_ms=$(response_time_ms "$URL")
  log "Tiempo de respuesta: ${resp_ms}ms"

  if   (( resp_ms > 3000 )); then score=$((score - 40)); PERF_RESP_SEVERITY="critico"
  elif (( resp_ms > 1500 )); then score=$((score - 25)); PERF_RESP_SEVERITY="alto"
  elif (( resp_ms > 800  )); then score=$((score - 10)); PERF_RESP_SEVERITY="medio"
  else                            PERF_RESP_SEVERITY="bajo"
  fi
  PERF_RESP_MS="$resp_ms"

  # Page weight
  info "Midiendo peso de página..."
  local page_size
  page_size=$(fetch_url "$URL" "-sSL --compressed" 2>/dev/null | wc -c) || page_size=0
  local page_kb=$(( page_size / 1024 ))
  PERF_SIZE_KB="$page_kb"
  log "Tamaño HTML: ${page_kb}KB"

  if   (( page_kb > 500 )); then score=$((score - 20)); PERF_SIZE_SEVERITY="alto"
  elif (( page_kb > 200 )); then score=$((score - 10)); PERF_SIZE_SEVERITY="medio"
  else                            PERF_SIZE_SEVERITY="bajo"
  fi

  # HTTP/2 check
  info "Verificando protocolo HTTP..."
  local protocol
  protocol=$(curl -sSLo /dev/null --max-time "$TIMEOUT" \
    -w "%{http_version}" "$URL" 2>/dev/null) || protocol="1.1"
  PERF_PROTOCOL="HTTP/$protocol"
  [[ "$protocol" != "2" && "$protocol" != "3" ]] && score=$((score - 10))

  # Gzip/Brotli
  info "Verificando compresión..."
  local encoding
  encoding=$(curl -sSLo /dev/null --max-time "$TIMEOUT" \
    -H "Accept-Encoding: gzip, deflate, br" \
    -w "%{header_json}" "$URL" 2>/dev/null \
    | grep -i "content-encoding" | head -1) || encoding=""
  PERF_COMPRESSION="${encoding:-Sin compresión}"
  [[ -z "$encoding" ]] && score=$((score - 10))

  # Lighthouse — una sola ejecución compartida
  PERF_LH_SCORE=""
  if require_tool "lighthouse" 2>/dev/null; then
    run_lighthouse_once
    PERF_LH_SCORE=$(lh_score "performance")
    [[ -n "$PERF_LH_SCORE" ]] && score=$(( (score + PERF_LH_SCORE) / 2 ))
  fi

  # Clamp score
  (( score < 0 )) && score=0
  set_score "performance" "$score"
  SCORE_PERFORMANCE="$score"
  ok "Performance score: $(score_color $score)"
}

# ─── DIMENSION 2: Calidad Técnica ─────────────────────────────────────────────
analyze_calidad_tecnica() {
  step "Analizando Calidad Técnica"
  local score=100
  local html_content
  html_content=$(fetch_url "$URL") || { warn "No se pudo descargar el HTML"; set_score "calidad_tecnica" 40; SCORE_CALIDAD_TECNICA=40; return; }

  # HTML structure checks
  local has_doctype=false has_lang=false has_charset=false has_viewport=false
  local has_title=false has_canonical=false

  echo "$html_content" | grep -qi "<!DOCTYPE html>" && has_doctype=true
  echo "$html_content" | grep -qi '<html[^>]*lang=' && has_lang=true
  echo "$html_content" | grep -qi 'charset=' && has_charset=true
  echo "$html_content" | grep -qi 'name="viewport"' && has_viewport=true
  echo "$html_content" | grep -qi '<title>' && has_title=true
  echo "$html_content" | grep -qi 'rel="canonical"' && has_canonical=true

  CT_DOCTYPE="$has_doctype"
  CT_LANG="$has_lang"
  CT_CHARSET="$has_charset"
  CT_VIEWPORT="$has_viewport"
  CT_TITLE="$has_title"
  CT_CANONICAL="$has_canonical"

  [[ "$has_doctype"   == false ]] && score=$((score - 15))
  [[ "$has_lang"      == false ]] && score=$((score - 10))
  [[ "$has_charset"   == false ]] && score=$((score - 10))
  [[ "$has_viewport"  == false ]] && score=$((score - 15))
  [[ "$has_title"     == false ]] && score=$((score - 20))
  [[ "$has_canonical" == false ]] && score=$((score - 10))

  # Inline scripts / styles (code quality smell)
  local inline_scripts inline_styles
  inline_scripts=$(echo "$html_content" | grep -c '<script>' 2>/dev/null | tr -d '[:space:]') || inline_scripts=0
  inline_styles=$(echo "$html_content" | grep -c 'style="' 2>/dev/null | tr -d '[:space:]') || inline_styles=0
  inline_scripts=${inline_scripts:-0}; inline_styles=${inline_styles:-0}
  CT_INLINE_SCRIPTS="$inline_scripts"
  CT_INLINE_STYLES="$inline_styles"
  (( inline_scripts > 5 )) && score=$((score - 10)) || true
  (( inline_styles > 10 )) && score=$((score - 5)) || true

  # htmlq analysis (if available)
  CT_BROKEN_LINKS="N/A"
  if require_tool "htmlq" 2>/dev/null; then
    local links
    links=$(echo "$html_content" | htmlq 'a[href]' --attribute href 2>/dev/null | head -20)
    CT_BROKEN_LINKS=$(echo "$links" | wc -l)
  fi

  # htmlhint — calidad y buenas prácticas HTML
  CT_HTMLHINT_ERRORS=0
  CT_HTMLHINT_WARNINGS=0
  if [[ -n "$HTMLHINT_CMD" ]]; then
    info "Ejecutando htmlhint..."
    local hint_out="${TMPDIR_AUDIT}/htmlhint.txt"
    local tmp_html="${TMPDIR_AUDIT}/page.html"
    echo "$html_content" > "$tmp_html"
    if $HTMLHINT_CMD "$tmp_html" --format json > "$hint_out" 2>/dev/null && command -v jq &>/dev/null; then
      CT_HTMLHINT_ERRORS=$(jq '[.[].messages[] | select(.type=="error")] | length' "$hint_out" 2>/dev/null || echo 0)
      CT_HTMLHINT_WARNINGS=$(jq '[.[].messages[] | select(.type=="warning")] | length' "$hint_out" 2>/dev/null || echo 0)
      CT_HTMLHINT_ERRORS=${CT_HTMLHINT_ERRORS:-0}
      CT_HTMLHINT_WARNINGS=${CT_HTMLHINT_WARNINGS:-0}
      (( CT_HTMLHINT_ERRORS > 5  )) && score=$((score - 10)) || true
      (( CT_HTMLHINT_ERRORS > 10 )) && score=$((score - 10)) || true
    fi
  fi

  (( score < 0 )) && score=0
  set_score "calidad_tecnica" "$score"
  SCORE_CALIDAD_TECNICA="$score"
  ok "Calidad técnica score: $(score_color $score)"
}

# ─── DIMENSION 3: SEO ─────────────────────────────────────────────────────────
analyze_seo() {
  step "Analizando SEO"
  local score=100
  local html_content
  html_content=$(fetch_url "$URL") || { warn "No se pudo descargar HTML"; set_score "seo" 40; SCORE_SEO=40; return; }

  # Title
  local title
  title=$(echo "$html_content" | grep -i '<title>' | sed 's/.*<title>\(.*\)<\/title>.*/\1/' | head -1 | xargs) || title=""
  SEO_TITLE="${title:-AUSENTE}"
  SEO_TITLE_LEN="${#title}"
  [[ -z "$title" ]] && score=$((score - 25)) || true
  (( ${#title} > 60 )) && score=$((score - 10)) && SEO_TITLE_NOTE="Demasiado largo (>${#title} chars)" || true
  (( ${#title} > 0 && ${#title} < 30 )) && score=$((score - 5)) && SEO_TITLE_NOTE="Demasiado corto (<${#title} chars)" || true

  # Meta description
  local meta_desc
  meta_desc=$(echo "$html_content" | grep -i 'name="description"' | \
    sed 's/.*content="\([^"]*\)".*/\1/' | head -1 | xargs) || meta_desc=""
  SEO_META_DESC="${meta_desc:-AUSENTE}"
  SEO_META_DESC_LEN="${#meta_desc}"
  [[ -z "$meta_desc" ]] && score=$((score - 20)) || true
  (( ${#meta_desc} > 160 )) && score=$((score - 5)) || true

  # H1
  local h1_count
  h1_count=$(echo "$html_content" | grep -ic '<h1' 2>/dev/null | tr -d '[:space:]') || h1_count=0
  h1_count=${h1_count:-0}
  SEO_H1_COUNT="$h1_count"
  (( h1_count == 0 )) && score=$((score - 15)) || true
  (( h1_count > 1  )) && score=$((score - 10)) || true

  # OG Tags
  local has_og=false
  echo "$html_content" | grep -qi 'property="og:' && has_og=true
  SEO_OG="$has_og"
  [[ "$has_og" == false ]] && score=$((score - 10))

  # Robots / Sitemap
  local robots_status sitemap_status
  robots_status=$(http_status "$(echo "$URL" | sed 's|/$||')/robots.txt")
  SEO_ROBOTS="$robots_status"
  [[ "$robots_status" != "200" ]] && score=$((score - 10))

  sitemap_status=$(http_status "$(echo "$URL" | sed 's|/$||')/sitemap.xml")
  SEO_SITEMAP="$sitemap_status"
  [[ "$sitemap_status" != "200" ]] && score=$((score - 10))

  # Schema.org
  local has_schema=false
  echo "$html_content" | grep -qi 'application/ld+json' && has_schema=true
  SEO_SCHEMA="$has_schema"
  [[ "$has_schema" == false ]] && score=$((score - 5))

  # Lighthouse SEO — reutiliza ejecución única
  SEO_LH_SCORE=""
  if require_tool "lighthouse" 2>/dev/null; then
    run_lighthouse_once
    SEO_LH_SCORE=$(lh_score "seo")
    [[ -n "$SEO_LH_SCORE" ]] && score=$(( (score + SEO_LH_SCORE) / 2 ))
  fi

  (( score < 0 )) && score=0
  set_score "seo" "$score"
  SCORE_SEO="$score"
  ok "SEO score: $(score_color $score)"
}

# ─── DIMENSION 4: Accesibilidad ───────────────────────────────────────────────
analyze_accesibilidad() {
  step "Analizando Accesibilidad"
  local score=100
  local html_content
  html_content=$(fetch_url "$URL") || { warn "No se pudo descargar HTML"; set_score "accesibilidad" 40; SCORE_ACCESIBILIDAD=40; return; }

  # Alt text on images
  local imgs_total imgs_no_alt
  imgs_total=$(echo "$html_content" | grep -ic '<img' 2>/dev/null | tr -d '[:space:]') || imgs_total=0
  imgs_no_alt=$(echo "$html_content" | grep -i '<img' | grep -cv 'alt=' 2>/dev/null | tr -d '[:space:]') || imgs_no_alt=0
  imgs_total=${imgs_total:-0}; imgs_no_alt=${imgs_no_alt:-0}
  ACC_IMGS_TOTAL="$imgs_total"
  ACC_IMGS_NO_ALT="$imgs_no_alt"
  local alt_penalty=$(( imgs_no_alt * 5 > 30 ? 30 : imgs_no_alt * 5 ))
  (( imgs_total > 0 && imgs_no_alt > 0 )) && score=$((score - alt_penalty)) || true

  # ARIA labels
  local has_aria=false
  echo "$html_content" | grep -qi 'aria-label\|aria-labelledby\|role=' && has_aria=true
  ACC_ARIA="$has_aria"
  [[ "$has_aria" == false ]] && score=$((score - 15))

  # Skip navigation
  local has_skip=false
  echo "$html_content" | grep -qi 'skip\|saltar' && has_skip=true
  ACC_SKIP="$has_skip"
  [[ "$has_skip" == false ]] && score=$((score - 10))

  # Form labels
  local forms_count labels_count
  forms_count=$(echo "$html_content" | grep -ic '<form' 2>/dev/null | tr -d '[:space:]') || forms_count=0
  labels_count=$(echo "$html_content" | grep -ic '<label' 2>/dev/null | tr -d '[:space:]') || labels_count=0
  forms_count=${forms_count:-0}; labels_count=${labels_count:-0}
  ACC_FORMS="$forms_count"
  ACC_LABELS="$labels_count"
  (( forms_count > 0 && labels_count < forms_count )) && score=$((score - 15)) || true

  # Lang attribute (already checked, bonus here)
  local has_lang=false
  echo "$html_content" | grep -qi '<html[^>]*lang=' && has_lang=true
  [[ "$has_lang" == false ]] && score=$((score - 10))

  # Lighthouse Accessibility — reutiliza ejecución única
  ACC_LH_SCORE=""
  if require_tool "lighthouse" 2>/dev/null; then
    run_lighthouse_once
    ACC_LH_SCORE=$(lh_score "accessibility")
    [[ -n "$ACC_LH_SCORE" ]] && score=$(( (score + ACC_LH_SCORE) / 2 ))
  fi

  # axe-core — análisis WCAG profundo
  ACC_AXE_VIOLATIONS=0
  ACC_AXE_SERIOUS=0
  if [[ -n "$AXE_CMD" ]]; then
    info "Ejecutando axe-core (WCAG)..."
    local axe_out="${TMPDIR_AUDIT}/axe.json"
    if $AXE_CMD "$URL" --save "$axe_out" --quiet 2>/dev/null && command -v jq &>/dev/null; then
      ACC_AXE_VIOLATIONS=$(jq '[.violations[].nodes[]] | length' "$axe_out" 2>/dev/null || echo 0)
      ACC_AXE_SERIOUS=$(jq '[.violations[] | select(.impact=="serious" or .impact=="critical") | .nodes[]] | length' "$axe_out" 2>/dev/null || echo 0)
      ACC_AXE_VIOLATIONS=${ACC_AXE_VIOLATIONS:-0}
      ACC_AXE_SERIOUS=${ACC_AXE_SERIOUS:-0}
      (( ACC_AXE_SERIOUS > 0 )) && score=$((score - ACC_AXE_SERIOUS * 3 > 20 ? 20 : ACC_AXE_SERIOUS * 3)) || true
    fi
  fi

  # pa11y — reporte WCAG complementario
  ACC_PA11Y_ERRORS=0
  ACC_PA11Y_WARNINGS=0
  if [[ -n "$PA11Y_CMD" ]]; then
    info "Ejecutando pa11y..."
    local pa11y_out="${TMPDIR_AUDIT}/pa11y.json"
    if $PA11Y_CMD "$URL" --reporter json > "$pa11y_out" 2>/dev/null && command -v jq &>/dev/null; then
      ACC_PA11Y_ERRORS=$(jq '[.[] | select(.type=="error")] | length' "$pa11y_out" 2>/dev/null || echo 0)
      ACC_PA11Y_WARNINGS=$(jq '[.[] | select(.type=="warning")] | length' "$pa11y_out" 2>/dev/null || echo 0)
      ACC_PA11Y_ERRORS=${ACC_PA11Y_ERRORS:-0}
      ACC_PA11Y_WARNINGS=${ACC_PA11Y_WARNINGS:-0}
      (( ACC_PA11Y_ERRORS > 0 )) && score=$((score - ACC_PA11Y_ERRORS * 2 > 15 ? 15 : ACC_PA11Y_ERRORS * 2)) || true
    fi
  fi

  (( score < 0 )) && score=0
  set_score "accesibilidad" "$score"
  SCORE_ACCESIBILIDAD="$score"
  ok "Accesibilidad score: $(score_color $score)"
}

# ─── Hosting & Domain Lookup ──────────────────────────────────────────────────
lookup_hosting_domain() {
  local domain="$1"

  # ── IP del servidor ──
  info "Resolviendo IP del servidor..."
  SEC_HOST_IP=$(dig +short A "$domain" 2>/dev/null | grep -E '^[0-9]+\.' | head -1)     || SEC_HOST_IP=$(curl -sSL --max-time 10 "https://dns.google/resolve?name=${domain}&type=A"     2>/dev/null | grep -oP '"data":"\K[0-9.]+' | head -1) || SEC_HOST_IP=""
  SEC_HOST_IP="${SEC_HOST_IP:-No resuelto}"

  # ── Geolocalización + proveedor hosting (ipinfo.io — free tier) ──
  SEC_HOST_PROVIDER="Desconocido"
  SEC_HOST_COUNTRY="Desconocido"
  SEC_HOST_CITY="Desconocido"
  SEC_HOST_ASN="Desconocido"
  SEC_HOST_ORG="Desconocido"

  if [[ "$SEC_HOST_IP" != "No resuelto" ]]; then
    info "Geolocalizando IP ${SEC_HOST_IP}..."
    local geo_json
    geo_json=$(curl -sSL --max-time 10 "https://ipinfo.io/${SEC_HOST_IP}/json" 2>/dev/null) || geo_json=""

    if [[ -n "$geo_json" ]] && command -v jq &>/dev/null; then
      SEC_HOST_COUNTRY=$(echo "$geo_json" | jq -r '.country // "Desconocido"')
      SEC_HOST_CITY=$(echo    "$geo_json" | jq -r '.city    // "Desconocido"')
      SEC_HOST_ORG=$(echo     "$geo_json" | jq -r '.org     // "Desconocido"')
      SEC_HOST_ASN=$(echo "$SEC_HOST_ORG" | grep -oP '^AS\d+' || echo "Desconocido")
      # Proveedor limpio (quitar ASN prefix)
      SEC_HOST_PROVIDER=$(echo "$SEC_HOST_ORG" | sed 's/^AS[0-9]* //')
    elif [[ -n "$geo_json" ]]; then
      # Fallback sin jq — grep básico
      SEC_HOST_COUNTRY=$(echo "$geo_json" | grep -oP '"country"\s*:\s*"\K[^"]+' | head -1 || echo "Desconocido")
      SEC_HOST_CITY=$(echo    "$geo_json" | grep -oP '"city"\s*:\s*"\K[^"]+' | head -1 || echo "Desconocido")
      SEC_HOST_ORG=$(echo     "$geo_json" | grep -oP '"org"\s*:\s*"\K[^"]+' | head -1 || echo "Desconocido")
      SEC_HOST_PROVIDER=$(echo "$SEC_HOST_ORG" | sed 's/^AS[0-9]* //')
    fi
  fi

  # ── Registrador y datos de dominio via WHOIS ──
  info "Consultando WHOIS del dominio..."
  SEC_DOM_REGISTRAR="Desconocido"
  SEC_DOM_CREATED="Desconocido"
  SEC_DOM_EXPIRES="Desconocido"
  SEC_DOM_UPDATED="Desconocido"
  SEC_DOM_NAMESERVERS="Desconocido"
  SEC_DOM_PRIVACY=false
  SEC_DOM_EXPIRY_NOTE=""
  SEC_DOM_DAYS_LEFT=-1

  local whois_raw=""
  if command -v whois &>/dev/null; then
    whois_raw=$(whois "$domain" 2>/dev/null | head -80) || whois_raw=""
  fi

  if [[ -n "$whois_raw" ]]; then
    SEC_DOM_REGISTRAR=$(echo "$whois_raw" | grep -iE "^registrar:" | head -1 | sed 's/[Rr]egistrar:\s*//' | xargs)
    SEC_DOM_CREATED=$(echo   "$whois_raw" | grep -iE "creation date|created:" | head -1 | grep -oP '\d{4}-\d{2}-\d{2}' | head -1)
    SEC_DOM_EXPIRES=$(echo   "$whois_raw" | grep -iE "expir(y|ation) date|expires:" | head -1 | grep -oP '\d{4}-\d{2}-\d{2}' | head -1)
    SEC_DOM_UPDATED=$(echo   "$whois_raw" | grep -iE "updated date|last.updated:" | head -1 | grep -oP '\d{4}-\d{2}-\d{2}' | head -1)
    SEC_DOM_NAMESERVERS=$(echo "$whois_raw" | grep -iE "^name server:" | sed 's/[Nn]ame [Ss]erver:\s*//' | xargs | tr ' ' ', ' | cut -c1-80)
    echo "$whois_raw" | grep -qi "privacy\|redacted\|protected\|proxy" && SEC_DOM_PRIVACY=true

    # Días hasta expiración del dominio
    if [[ -n "$SEC_DOM_EXPIRES" ]]; then
      local exp_epoch now_epoch
      exp_epoch=$(date -d "$SEC_DOM_EXPIRES" +%s 2>/dev/null) || exp_epoch=""
      now_epoch=$(date +%s)
      if [[ -n "$exp_epoch" ]]; then
        SEC_DOM_DAYS_LEFT=$(( (exp_epoch - now_epoch) / 86400 ))
        if   (( SEC_DOM_DAYS_LEFT <= 0   )); then SEC_DOM_EXPIRY_NOTE="🔴 EXPIRADO"
        elif (( SEC_DOM_DAYS_LEFT <= 30  )); then SEC_DOM_EXPIRY_NOTE="🔴 Expira en ${SEC_DOM_DAYS_LEFT} días — RENOVAR URGENTE"
        elif (( SEC_DOM_DAYS_LEFT <= 90  )); then SEC_DOM_EXPIRY_NOTE="🟠 Expira en ${SEC_DOM_DAYS_LEFT} días"
        elif (( SEC_DOM_DAYS_LEFT <= 180 )); then SEC_DOM_EXPIRY_NOTE="🟡 Expira en ${SEC_DOM_DAYS_LEFT} días"
        else                                      SEC_DOM_EXPIRY_NOTE="🟢 Válido por ${SEC_DOM_DAYS_LEFT} días"
        fi
      fi
    fi
    [[ -z "$SEC_DOM_REGISTRAR"   ]] && SEC_DOM_REGISTRAR="Desconocido"
    [[ -z "$SEC_DOM_CREATED"     ]] && SEC_DOM_CREATED="Desconocido"
    [[ -z "$SEC_DOM_EXPIRES"     ]] && SEC_DOM_EXPIRES="Desconocido"
    [[ -z "$SEC_DOM_NAMESERVERS" ]] && SEC_DOM_NAMESERVERS="Desconocido"
  else
    warn "whois no disponible — datos de dominio omitidos"
  fi
}

# ─── DIMENSION 5: Seguridad HTTP ──────────────────────────────────────────────
analyze_seguridad() {
  step "Analizando Seguridad"
  local score=100

  # Hosting & dominio
  local domain="${URL#*://}"
  domain="${domain%%/*}"
  lookup_hosting_domain "$domain"

  # Headers de seguridad
  local headers
  headers=$(curl -sSLI --max-time "$TIMEOUT" \
    --user-agent "Mozilla/5.0 (compatible; homium-audit/1.0)" \
    "$URL" 2>/dev/null | tr '[:upper:]' '[:lower:]') || headers=""

  SEC_HSTS=false;     echo "$headers" | grep -q "strict-transport-security" && SEC_HSTS=true
  SEC_CSP=false;      echo "$headers" | grep -q "content-security-policy"   && SEC_CSP=true
  SEC_XCTO=false;     echo "$headers" | grep -q "x-content-type-options"    && SEC_XCTO=true
  SEC_XFO=false;      echo "$headers" | grep -q "x-frame-options"           && SEC_XFO=true
  SEC_RP=false;       echo "$headers" | grep -q "referrer-policy"           && SEC_RP=true
  SEC_PER=false;      echo "$headers" | grep -q "permissions-policy"        && SEC_PER=true

  [[ "$SEC_HSTS" == false ]] && score=$((score - 20))
  [[ "$SEC_CSP"  == false ]] && score=$((score - 20))
  [[ "$SEC_XCTO" == false ]] && score=$((score - 15))
  [[ "$SEC_XFO"  == false ]] && score=$((score - 15))
  [[ "$SEC_RP"   == false ]] && score=$((score - 10))
  [[ "$SEC_PER"  == false ]] && score=$((score - 10))

  # HTTPS redirect
  local http_status_code
  http_status_code=$(http_status "http://${domain}")
  if [[ "$http_status_code" == "301" || "$http_status_code" == "302" ]]; then
    SEC_HTTPS_REDIRECT=true
  else
    SEC_HTTPS_REDIRECT=false
    score=$((score - 15))
  fi

  # TLS — expiración con openssl
  local tls_info
  tls_info=$(check_tls "$domain") || tls_info=""
  SEC_TLS_INFO="${tls_info:-No disponible}"

  info "Verificando expiración del certificado SSL..."
  local ssl_days
  ssl_days=$(ssl_days_remaining "$domain")
  SEC_SSL_DAYS="$ssl_days"
  SEC_SSL_EXPIRY_NOTE=""

  if   (( ssl_days < 0  )); then
    SEC_SSL_EXPIRY_NOTE="No se pudo verificar"
  elif (( ssl_days == 0 )); then
    SEC_SSL_EXPIRY_NOTE="🔴 EXPIRADO"
    score=$((score - 40))
  elif (( ssl_days <= 7  )); then
    SEC_SSL_EXPIRY_NOTE="🔴 Expira en ${ssl_days} días — RENOVAR URGENTE"
    score=$((score - 30))
  elif (( ssl_days <= 30 )); then
    SEC_SSL_EXPIRY_NOTE="🟠 Expira en ${ssl_days} días — programar renovación"
    score=$((score - 15))
  elif (( ssl_days <= 90 )); then
    SEC_SSL_EXPIRY_NOTE="🟡 Expira en ${ssl_days} días"
    score=$((score - 5))
  else
    SEC_SSL_EXPIRY_NOTE="🟢 Válido por ${ssl_days} días"
  fi

  # ssl-checker — validación adicional si está disponible
  SEC_SSLCHECK_RESULT=""
  if [[ -n "$SSLCHECK_CMD" ]]; then
    info "Ejecutando ssl-checker..."
    SEC_SSLCHECK_RESULT=$($SSLCHECK_CMD "$domain" 2>/dev/null | head -5) || SEC_SSLCHECK_RESULT="No disponible"
  fi

  # Cookie flags
  local cookie_header
  cookie_header=$(echo "$headers" | grep "set-cookie" || echo "")
  SEC_COOKIE_SECURE=true; echo "$cookie_header" | grep -qi "set-cookie" && \
    ! echo "$cookie_header" | grep -qi "secure" && SEC_COOKIE_SECURE=false
  SEC_COOKIE_HTTPONLY=true; echo "$cookie_header" | grep -qi "set-cookie" && \
    ! echo "$cookie_header" | grep -qi "httponly" && SEC_COOKIE_HTTPONLY=false

  [[ "$SEC_COOKIE_SECURE"   == false ]] && score=$((score - 10))
  [[ "$SEC_COOKIE_HTTPONLY" == false ]] && score=$((score - 10))

  (( score < 0 )) && score=0
  set_score "seguridad" "$score"
  SCORE_SEGURIDAD="$score"
  ok "Seguridad score: $(score_color $score)"
}

# ─── DIMENSION 6: Ciberseguridad ──────────────────────────────────────────────
analyze_ciberseguridad() {
  step "Analizando Ciberseguridad"
  local score=100
  local domain="${URL#*://}"
  domain="${domain%%/*}"

  # Server info disclosure
  local server_header
  server_header=$(curl -sSLI --max-time "$TIMEOUT" "$URL" 2>/dev/null | \
    grep -i "^server:" | head -1 | sed 's/server: //i' | xargs) || server_header=""
  CYBER_SERVER="${server_header:-Oculto (bien)}"
  local powered_by
  powered_by=$(curl -sSLI --max-time "$TIMEOUT" "$URL" 2>/dev/null | \
    grep -i "x-powered-by:" | head -1 | xargs) || powered_by=""
  CYBER_POWERED_BY="${powered_by:-Oculto (bien)}"

  [[ -n "$server_header" && "$server_header" =~ [0-9] ]] && score=$((score - 15))
  [[ -n "$powered_by" ]] && score=$((score - 10))

  # Directory listing check
  local dirs=("/admin" "/backup" "/.git" "/config" "/uploads")
  CYBER_EXPOSED_DIRS=()
  for d in "${dirs[@]}"; do
    local st
    st=$(http_status "${URL%/}${d}")
    [[ "$st" == "200" ]] && CYBER_EXPOSED_DIRS+=("$d") && score=$((score - 10))
  done
  [[ ${#CYBER_EXPOSED_DIRS[@]} -eq 0 ]] && CYBER_EXPOSED_DIRS=("Ninguno detectado")

  # Security.txt
  local sec_txt_status
  sec_txt_status=$(http_status "${URL%/}/.well-known/security.txt")
  CYBER_SEC_TXT="$sec_txt_status"
  [[ "$sec_txt_status" != "200" ]] && score=$((score - 5))

  # SPF / DMARC records (via DNS)
  CYBER_SPF="No verificable sin DNS lookup"
  CYBER_DMARC="No verificable sin DNS lookup"
  if command -v dig &>/dev/null; then
    local spf
    spf=$(dig TXT "$domain" +short 2>/dev/null | grep -i "v=spf" | head -1) || spf=""
    CYBER_SPF="${spf:-AUSENTE}"
    [[ -z "$spf" ]] && score=$((score - 10))

    local dmarc
    dmarc=$(dig TXT "_dmarc.${domain}" +short 2>/dev/null | head -1) || dmarc=""
    CYBER_DMARC="${dmarc:-AUSENTE}"
    [[ -z "$dmarc" ]] && score=$((score - 10))
  fi

  (( score < 0 )) && score=0
  set_score "ciberseguridad" "$score"
  SCORE_CIBERSEGURIDAD="$score"
  ok "Ciberseguridad score: $(score_color $score)"
}

# ─── DIMENSION 7: Diseño ──────────────────────────────────────────────────────
analyze_diseno() {
  step "Analizando Diseño"
  local score=70  # Base score (diseño requiere análisis visual real)
  local html_content
  html_content=$(fetch_url "$URL") || { set_score "diseno" 50; SCORE_DISENO=50; return; }

  # Viewport / Responsive
  local has_viewport=false
  echo "$html_content" | grep -qi 'name="viewport"' && has_viewport=true
  DIS_VIEWPORT="$has_viewport"
  [[ "$has_viewport" == false ]] && score=$((score - 20))

  # CSS Frameworks detectados
  DIS_FRAMEWORKS=()
  echo "$html_content" | grep -qi "bootstrap"   && DIS_FRAMEWORKS+=("Bootstrap")
  echo "$html_content" | grep -qi "tailwind"    && DIS_FRAMEWORKS+=("Tailwind CSS")
  echo "$html_content" | grep -qi "materialize" && DIS_FRAMEWORKS+=("Materialize")
  echo "$html_content" | grep -qi "foundation"  && DIS_FRAMEWORKS+=("Foundation")
  [[ ${#DIS_FRAMEWORKS[@]} -eq 0 ]] && DIS_FRAMEWORKS=("CSS propio o no detectado")

  # Fonts check
  DIS_FONTS=false
  echo "$html_content" | grep -qi "fonts.googleapis\|fonts.gstatic\|typekit\|font-face" && DIS_FONTS=true

  # Favicon
  DIS_FAVICON=false
  echo "$html_content" | grep -qi "rel=\"icon\"\|rel=\"shortcut icon\"" && DIS_FAVICON=true
  [[ "$DIS_FAVICON" == false ]] && score=$((score - 5))

  # Dark mode support
  DIS_DARK_MODE=false
  echo "$html_content" | grep -qi "prefers-color-scheme\|color-scheme" && DIS_DARK_MODE=true

  # Lighthouse Best Practices — reutiliza ejecución única
  DIS_LH_SCORE=""
  if require_tool "lighthouse" 2>/dev/null; then
    run_lighthouse_once
    DIS_LH_SCORE=$(lh_score "best-practices")
    [[ -n "$DIS_LH_SCORE" ]] && score=$(( (score + DIS_LH_SCORE) / 2 ))
  fi

  (( score < 0 )) && score=0
  set_score "diseno" "$score"
  SCORE_DISENO="$score"
  ok "Diseño score: $(score_color $score)"
}

# ─── DIMENSION 8: UX ──────────────────────────────────────────────────────────
analyze_ux() {
  step "Analizando Experiencia de Usuario (UX)"
  local score=70  # Base score
  local html_content
  html_content=$(fetch_url "$URL") || { set_score "ux" 50; SCORE_UX=50; return; }

  # Navigation
  local has_nav=false
  echo "$html_content" | grep -qi '<nav\|role="navigation"' && has_nav=true
  UX_NAV="$has_nav"
  [[ "$has_nav" == false ]] && score=$((score - 15))

  # Search
  local has_search=false
  echo "$html_content" | grep -qi 'type="search"\|input.*search\|buscador' && has_search=true
  UX_SEARCH="$has_search"

  # Contact info
  local has_contact=false
  echo "$html_content" | grep -qi 'contact\|contacto\|mailto:\|tel:' && has_contact=true
  UX_CONTACT="$has_contact"
  [[ "$has_contact" == false ]] && score=$((score - 10))

  # CTA (Call to action)
  local has_cta=false
  echo "$html_content" | grep -qi 'cta\|call-to-action\|btn\|button\|comprar\|registr\|sign.up\|get.started' \
    && has_cta=true
  UX_CTA="$has_cta"
  [[ "$has_cta" == false ]] && score=$((score - 15))

  # Mobile-first
  local has_media_queries=false
  echo "$html_content" | grep -qi "@media\|max-width:\|min-width:" && has_media_queries=true
  UX_RESPONSIVE="$has_media_queries"
  [[ "$has_media_queries" == false ]] && score=$((score - 20))

  # Loading indicators / UX patterns
  local has_loading=false
  echo "$html_content" | grep -qi "loading\|spinner\|skeleton" && has_loading=true
  UX_LOADING="$has_loading"

  # Error pages
  local err404
  err404=$(http_status "${URL%/}/pagina-que-no-existe-audit-test-xyz123")
  UX_404="$err404"
  [[ "$err404" != "404" ]] && score=$((score - 10))

  (( score < 0 )) && score=0
  set_score "ux" "$score"
  SCORE_UX="$score"
  ok "UX score: $(score_color $score)"
}

# ─── Legal / Privacidad ───────────────────────────────────────────────────────
analyze_legal() {
  step "Analizando Legal & Privacidad"
  local html_content
  html_content=$(fetch_url "$URL") || { return; }

  # Privacy policy
  LEGAL_PRIVACY=false
  echo "$html_content" | grep -qi "privacy\|privacidad\|política" && LEGAL_PRIVACY=true

  # Terms of service
  LEGAL_TERMS=false
  echo "$html_content" | grep -qi "terms\|condiciones\|aviso.legal" && LEGAL_TERMS=true

  # Cookie banner
  LEGAL_COOKIES=false
  echo "$html_content" | grep -qi "cookie\|gdpr\|rgpd\|consent" && LEGAL_COOKIES=true

  # GDPR compliance signals
  LEGAL_GDPR=false
  echo "$html_content" | grep -qi "gdpr\|rgpd\|reglamento.*datos\|general.data" && LEGAL_GDPR=true

  # Third-party trackers
  local trackers=()
  echo "$html_content" | grep -qi "google-analytics\|gtag\|ga.js" && trackers+=("Google Analytics")
  echo "$html_content" | grep -qi "facebook\|fbevents\|fbq(" && trackers+=("Facebook Pixel")
  echo "$html_content" | grep -qi "hotjar" && trackers+=("Hotjar")
  echo "$html_content" | grep -qi "mixpanel" && trackers+=("Mixpanel")
  echo "$html_content" | grep -qi "segment" && trackers+=("Segment")
  echo "$html_content" | grep -qi "hubspot" && trackers+=("HubSpot")
  LEGAL_TRACKERS=("${trackers[@]:-Ninguno detectado}")
}

# ─── Compute Global Score ─────────────────────────────────────────────────────
compute_global_score() {
  local weights=(
    "performance:20"
    "seo:15"
    "accesibilidad:15"
    "seguridad:15"
    "ciberseguridad:10"
    "calidad_tecnica:10"
    "diseno:8"
    "ux:7"
  )

  local total=0 weight_sum=0
  for w in "${weights[@]}"; do
    local key="${w%%:*}"
    local weight="${w##*:}"
    local s
    s=$(get_score "$key")
    total=$(( total + s * weight ))
    weight_sum=$(( weight_sum + weight ))
  done

  SCORE_GLOBAL=$(( total / weight_sum ))
}

# ─── Find Previous Report ─────────────────────────────────────────────────────
find_previous_report() {
  local slug="$1"
  if [[ -n "$COMPARE_FILE" && -f "$COMPARE_FILE" ]]; then
    PREV_REPORT="$COMPARE_FILE"
    return
  fi
  PREV_REPORT=$(ls -t "${OUTPUT_DIR}/reporte-${slug}-"*.md 2>/dev/null | head -2 | tail -1) || PREV_REPORT=""
}

# ─── Extract Score from Previous Report ───────────────────────────────────────
extract_prev_score() {
  local report="$1"
  local dimension="$2"
  grep -i "| ${dimension}" "$report" 2>/dev/null | \
    grep -oP '\d+(?=\s*/\s*100)' | head -1 || echo "N/A"
}

# ─── ASCII Bar ────────────────────────────────────────────────────────────────
ascii_bar() {
  local val="$1"
  local max="${2:-100}"
  local width="${3:-20}"
  local filled=$(( val * width / max ))
  local empty=$(( width - filled ))
  local bar=""
  for ((i=0; i<filled; i++)); do bar+="█"; done
  for ((i=0; i<empty; i++));  do bar+="░"; done
  echo "${bar}"
}

# ─── Generate Markdown Report ─────────────────────────────────────────────────
generate_report() {
  local slug="$1"
  local out_file="$2"
  local prev_report="${3:-}"

  local domain="${URL#*://}"
  domain="${domain%%/*}"

  # Global score badge
  local global_badge
  global_badge=$(score_badge "$SCORE_GLOBAL")

  cat > "$out_file" <<MDEOF
# 🔍 Auditoría Web Profesional — ${domain}

> **Generado por:** [homium-audit](https://github.com/homium-tech/audit) v1.0.0
> **Fecha:** ${DATE_HUMAN}
> **URL analizada:** ${URL}
> **Metodología:** 8 dimensiones · Análisis automatizado + roles especializados

---

## 📋 Resumen Ejecutivo

$(if (( SCORE_GLOBAL >= 80 )); then
  echo "El sitio **${domain}** presenta un estado **satisfactorio** con oportunidades de mejora identificadas en dimensiones específicas. Se recomienda priorizar las acciones críticas y de alto impacto antes del próximo ciclo de revisión."
elif (( SCORE_GLOBAL >= 60 )); then
  echo "El sitio **${domain}** presenta un estado **aceptable** con áreas de mejora importantes. Existen brechas técnicas y de experiencia que pueden impactar negativamente en conversión, posicionamiento y seguridad. Se requiere un plan de acción en el corto plazo."
else
  echo "El sitio **${domain}** presenta **deficiencias significativas** que requieren atención inmediata. Las brechas detectadas pueden tener impacto directo en negocio, reputación y cumplimiento legal."
fi)

### Score Global

| Indicador | Valor |
|-----------|-------|
| **Score Global** | ${global_badge} **${SCORE_GLOBAL} / 100** |
| **URL** | \`${URL}\` |
| **Fecha** | ${DATE_HUMAN} |
| **Dimensiones analizadas** | 8 |

\`\`\`
Performance      $(ascii_bar $SCORE_PERFORMANCE) ${SCORE_PERFORMANCE}/100
SEO              $(ascii_bar $SCORE_SEO)         ${SCORE_SEO}/100
Accesibilidad    $(ascii_bar $SCORE_ACCESIBILIDAD) ${SCORE_ACCESIBILIDAD}/100
Seguridad        $(ascii_bar $SCORE_SEGURIDAD)   ${SCORE_SEGURIDAD}/100
Ciberseguridad   $(ascii_bar $SCORE_CIBERSEGURIDAD) ${SCORE_CIBERSEGURIDAD}/100
Calidad Técnica  $(ascii_bar $SCORE_CALIDAD_TECNICA) ${SCORE_CALIDAD_TECNICA}/100
Diseño           $(ascii_bar $SCORE_DISENO)      ${SCORE_DISENO}/100
UX               $(ascii_bar $SCORE_UX)          ${SCORE_UX}/100
\`\`\`

---

## 📊 Scores por Dimensión

| Dimensión | Score | Semáforo | Interpretación |
|-----------|------:|---------|----------------|
| ⚡ Performance | **${SCORE_PERFORMANCE}/100** | $(score_badge $SCORE_PERFORMANCE) | $(if (( SCORE_PERFORMANCE >= 80 )); then echo "Óptimo"; elif (( SCORE_PERFORMANCE >= 60 )); then echo "Mejorable"; else echo "Crítico"; fi) |
| 🔍 SEO | **${SCORE_SEO}/100** | $(score_badge $SCORE_SEO) | $(if (( SCORE_SEO >= 80 )); then echo "Óptimo"; elif (( SCORE_SEO >= 60 )); then echo "Mejorable"; else echo "Crítico"; fi) |
| ♿ Accesibilidad | **${SCORE_ACCESIBILIDAD}/100** | $(score_badge $SCORE_ACCESIBILIDAD) | $(if (( SCORE_ACCESIBILIDAD >= 80 )); then echo "Óptimo"; elif (( SCORE_ACCESIBILIDAD >= 60 )); then echo "Mejorable"; else echo "Crítico"; fi) |
| 🔒 Seguridad | **${SCORE_SEGURIDAD}/100** | $(score_badge $SCORE_SEGURIDAD) | $(if (( SCORE_SEGURIDAD >= 80 )); then echo "Óptimo"; elif (( SCORE_SEGURIDAD >= 60 )); then echo "Mejorable"; else echo "Crítico"; fi) |
| 🛡️ Ciberseguridad | **${SCORE_CIBERSEGURIDAD}/100** | $(score_badge $SCORE_CIBERSEGURIDAD) | $(if (( SCORE_CIBERSEGURIDAD >= 80 )); then echo "Óptimo"; elif (( SCORE_CIBERSEGURIDAD >= 60 )); then echo "Mejorable"; else echo "Crítico"; fi) |
| ⚙️ Calidad Técnica | **${SCORE_CALIDAD_TECNICA}/100** | $(score_badge $SCORE_CALIDAD_TECNICA) | $(if (( SCORE_CALIDAD_TECNICA >= 80 )); then echo "Óptimo"; elif (( SCORE_CALIDAD_TECNICA >= 60 )); then echo "Mejorable"; else echo "Crítico"; fi) |
| 🎨 Diseño | **${SCORE_DISENO}/100** | $(score_badge $SCORE_DISENO) | $(if (( SCORE_DISENO >= 80 )); then echo "Óptimo"; elif (( SCORE_DISENO >= 60 )); then echo "Mejorable"; else echo "Crítico"; fi) |
| 👤 UX | **${SCORE_UX}/100** | $(score_badge $SCORE_UX) | $(if (( SCORE_UX >= 80 )); then echo "Óptimo"; elif (( SCORE_UX >= 60 )); then echo "Mejorable"; else echo "Crítico"; fi) |

---

## 🏆 Benchmarking (Referencia de Industria)

> *Comparación aproximada contra estándares de mercado Web 2025.*

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

### ⚡ 1. Performance

**Score: ${SCORE_PERFORMANCE}/100** $(score_badge $SCORE_PERFORMANCE)

| Hallazgo | Valor | Severidad |
|----------|-------|-----------|
| Tiempo de respuesta | ${PERF_RESP_MS}ms | $(severity_badge ${PERF_RESP_SEVERITY}) |
| Tamaño de página HTML | ${PERF_SIZE_KB}KB | $(if (( PERF_SIZE_KB > 200 )); then severity_badge "medio"; else severity_badge "bajo"; fi) |
| Protocolo HTTP | ${PERF_PROTOCOL} | $(if [[ "$PERF_PROTOCOL" == "HTTP/2" || "$PERF_PROTOCOL" == "HTTP/3" ]]; then severity_badge "bajo"; else severity_badge "medio"; fi) |
| Compresión | ${PERF_COMPRESSION} | $(echo "$PERF_COMPRESSION" | grep -qi "gzip\|br\|deflate" && severity_badge "bajo" || severity_badge "medio") |
$([ -n "${PERF_LH_SCORE:-}" ] && echo "| Lighthouse Performance | ${PERF_LH_SCORE}/100 | — |")

**💡 Recomendaciones:**
- $([ "$PERF_RESP_SEVERITY" != "bajo" ] && echo "- Optimizar servidor/CDN para reducir TTFB a <200ms" || echo "- TTFB dentro de parámetros aceptables ✓")
- $([ "$PERF_PROTOCOL" == "HTTP/1.1" ] && echo "- Migrar a HTTP/2 o HTTP/3 para multiplexación de recursos" || echo "- Protocolo HTTP actualizado ✓")
- $(echo "$PERF_COMPRESSION" | grep -qi "gzip\|br" || echo "- Activar compresión Gzip o Brotli en el servidor")
- Implementar lazy loading para imágenes y recursos no críticos
- Revisar Core Web Vitals: LCP, FID, CLS

---

### 🔍 2. SEO

**Score: ${SCORE_SEO}/100** $(score_badge $SCORE_SEO)

| Elemento | Estado | Valor |
|----------|--------|-------|
| \`<title>\` | $([ "$SEO_TITLE" == "AUSENTE" ] && echo "❌ AUSENTE" || echo "✅ Presente") | ${SEO_TITLE:0:60}... |
| Longitud título | ${SEO_TITLE_LEN} chars | $(if (( SEO_TITLE_LEN >= 30 && SEO_TITLE_LEN <= 60 )); then echo "✅ Óptima"; elif (( SEO_TITLE_LEN > 60 )); then echo "⚠️ Muy largo"; else echo "⚠️ Muy corto"; fi) |
| Meta description | $([ "$SEO_META_DESC" == "AUSENTE" ] && echo "❌ AUSENTE" || echo "✅ Presente") | ${SEO_META_DESC:0:60}... |
| H1 count | ${SEO_H1_COUNT} | $(if (( SEO_H1_COUNT == 1 )); then echo "✅ Correcto"; elif (( SEO_H1_COUNT == 0 )); then echo "❌ Falta"; else echo "⚠️ Múltiples H1"; fi) |
| Open Graph | $([ "$SEO_OG" == "true" ] && echo "✅" || echo "❌") | — |
| robots.txt | $([ "$SEO_ROBOTS" == "200" ] && echo "✅ HTTP $SEO_ROBOTS" || echo "⚠️ HTTP $SEO_ROBOTS") | — |
| sitemap.xml | $([ "$SEO_SITEMAP" == "200" ] && echo "✅ HTTP $SEO_SITEMAP" || echo "⚠️ HTTP $SEO_SITEMAP") | — |
| Schema.org | $([ "$SEO_SCHEMA" == "true" ] && echo "✅" || echo "❌") | — |
$([ -n "${SEO_LH_SCORE:-}" ] && echo "| Lighthouse SEO | ✅ ${SEO_LH_SCORE}/100 | — |")

**💡 Recomendaciones:**
- $([ "$SEO_TITLE" == "AUSENTE" ] && echo "🔴 CRÍTICO: Añadir \`<title>\` único y descriptivo (30-60 chars)" || echo "- Title tag presente ✓")
- $([ "$SEO_META_DESC" == "AUSENTE" ] && echo "🟠 ALTO: Crear meta description (120-160 chars) para cada página" || echo "- Meta description presente ✓")
- $([ "$SEO_ROBOTS" != "200" ] && echo "🟡 MEDIO: Crear archivo robots.txt en la raíz del dominio" || echo "- robots.txt encontrado ✓")
- $([ "$SEO_SITEMAP" != "200" ] && echo "🟡 MEDIO: Generar y publicar sitemap.xml + registrar en Google Search Console" || echo "- sitemap.xml encontrado ✓")
- $([ "$SEO_SCHEMA" != "true" ] && echo "🟡 MEDIO: Implementar structured data (Schema.org) para rich snippets" || echo "- Schema.org implementado ✓")
- $([ "$SEO_OG" != "true" ] && echo "🟢 BAJO: Añadir Open Graph tags para mejorar sharing en redes sociales" || echo "- Open Graph tags presentes ✓")

---

### ♿ 3. Accesibilidad

**Score: ${SCORE_ACCESIBILIDAD}/100** $(score_badge $SCORE_ACCESIBILIDAD)

| Elemento | Estado | Detalle |
|----------|--------|---------|
| Imágenes con alt | $(if (( ACC_IMGS_NO_ALT > 0 )); then echo "⚠️ Parcial"; else echo "✅ OK"; fi) | ${ACC_IMGS_TOTAL} imgs · ${ACC_IMGS_NO_ALT} sin alt |
| ARIA labels | $([ "$ACC_ARIA" == "true" ] && echo "✅" || echo "❌") | — |
| Skip navigation | $([ "$ACC_SKIP" == "true" ] && echo "✅" || echo "❌") | — |
| Formularios con labels | $(if (( ACC_FORMS > 0 && ACC_LABELS >= ACC_FORMS )); then echo "✅"; else echo "⚠️"; fi) | ${ACC_FORMS} forms · ${ACC_LABELS} labels |
$([ -n "${ACC_LH_SCORE:-}" ] && echo "| Lighthouse A11y | ✅ ${ACC_LH_SCORE}/100 | — |")
$([ -n "$AXE_CMD" ] && echo "| axe-core violations | $([ ${ACC_AXE_VIOLATIONS:-0} -eq 0 ] && echo '✅ 0' || echo "⚠️ ${ACC_AXE_VIOLATIONS}") | ${ACC_AXE_SERIOUS:-0} críticas/serias |")
$([ -n "$PA11Y_CMD" ] && echo "| pa11y errores | $([ ${ACC_PA11Y_ERRORS:-0} -eq 0 ] && echo '✅ 0' || echo "⚠️ ${ACC_PA11Y_ERRORS}") | ${ACC_PA11Y_WARNINGS:-0} warnings |")

**WCAG 2.1 Compliance estimado:** $(if (( SCORE_ACCESIBILIDAD >= 80 )); then echo "AA parcial"; elif (( SCORE_ACCESIBILIDAD >= 60 )); then echo "A parcial"; else echo "No verificado/Deficiente"; fi)

**💡 Recomendaciones:**
- $([ "$ACC_ARIA" != "true" ] && echo "🟠 ALTO: Implementar atributos ARIA en componentes interactivos" || echo "- ARIA labels presentes ✓")
- $([ "$ACC_SKIP" != "true" ] && echo "🟡 MEDIO: Añadir 'Skip to main content' link para usuarios de teclado" || echo "- Skip navigation presente ✓")
- $(( ACC_IMGS_NO_ALT > 0 )) && echo "🟠 ALTO: Añadir atributo \`alt\` descriptivo a ${ACC_IMGS_NO_ALT} imagen(es)" || echo "- Todas las imágenes tienen alt ✓"
- Realizar auditoría manual con screen reader (NVDA/JAWS)
- Verificar ratios de contraste de color (mínimo 4.5:1 para texto normal)

---

### 🔒 4. Seguridad HTTP

**Score: ${SCORE_SEGURIDAD}/100** $(score_badge $SCORE_SEGURIDAD)

#### 🌐 Infraestructura — Hosting & Dominio

| Elemento | Detalle |
|----------|---------|
| **IP del servidor** | \`${SEC_HOST_IP}\` |
| **Proveedor hosting** | ${SEC_HOST_PROVIDER} |
| **Ubicación** | ${SEC_HOST_CITY}, ${SEC_HOST_COUNTRY} |
| **ASN** | ${SEC_HOST_ASN} |
| **Registrador dominio** | ${SEC_DOM_REGISTRAR} |
| **Dominio creado** | ${SEC_DOM_CREATED:-Desconocido} |
| **Dominio expira** | ${SEC_DOM_EXPIRES:-Desconocido} — ${SEC_DOM_EXPIRY_NOTE} |
| **Última actualización** | ${SEC_DOM_UPDATED:-Desconocido} |
| **Nameservers** | \`${SEC_DOM_NAMESERVERS}\` |
| **Privacidad WHOIS** | $([ "$SEC_DOM_PRIVACY" == "true" ] && echo "✅ Activada" || echo "⚠️ Datos expuestos") |

#### 🔐 Headers de Seguridad

| Header de Seguridad | Estado | Importancia |
|--------------------|--------|-------------|
| Strict-Transport-Security (HSTS) | $([ "$SEC_HSTS" == "true" ] && echo "✅" || echo "❌ AUSENTE") | 🔴 Crítico |
| Content-Security-Policy (CSP) | $([ "$SEC_CSP" == "true" ] && echo "✅" || echo "❌ AUSENTE") | 🔴 Crítico |
| X-Content-Type-Options | $([ "$SEC_XCTO" == "true" ] && echo "✅" || echo "❌ AUSENTE") | 🟠 Alto |
| X-Frame-Options | $([ "$SEC_XFO" == "true" ] && echo "✅" || echo "❌ AUSENTE") | 🟠 Alto |
| Referrer-Policy | $([ "$SEC_RP" == "true" ] && echo "✅" || echo "❌ AUSENTE") | 🟡 Medio |
| Permissions-Policy | $([ "$SEC_PER" == "true" ] && echo "✅" || echo "❌ AUSENTE") | 🟡 Medio |
| HTTPS Redirect | $([ "$SEC_HTTPS_REDIRECT" == "true" ] && echo "✅" || echo "❌") | 🔴 Crítico |
| Cookies Secure flag | $([ "$SEC_COOKIE_SECURE" == "true" ] && echo "✅" || echo "⚠️ Falta") | 🟠 Alto |
| Cookies HttpOnly flag | $([ "$SEC_COOKIE_HTTPONLY" == "true" ] && echo "✅" || echo "⚠️ Falta") | 🟠 Alto |
| Expiración SSL | ${SEC_SSL_EXPIRY_NOTE:-No verificado} | $(if (( ${SEC_SSL_DAYS:--1} <= 0 )); then echo "🔴 Crítico"; elif (( SEC_SSL_DAYS <= 30 )); then echo "🟠 Alto"; elif (( SEC_SSL_DAYS <= 90 )); then echo "🟡 Medio"; else echo "🟢 OK"; fi) |
$([ -n "${SEC_SSLCHECK_RESULT:-}" ] && echo "| ssl-checker | \`${SEC_SSLCHECK_RESULT}\` | — |")

**💡 Recomendaciones de infraestructura:**
- $([ "$SEC_DOM_PRIVACY" != "true" ] && echo "🟡 MEDIO: Activar privacidad WHOIS en el registrador para proteger datos del titular" || echo "- Privacidad WHOIS activa ✓")
- $([ "${SEC_DOM_DAYS_LEFT:-999}" -le 90 ] && [ "${SEC_DOM_DAYS_LEFT:-999}" -gt 0 ] && echo "🟠 ALTO: Renovar dominio — expira en ${SEC_DOM_DAYS_LEFT} días" || true)
- $([ "${SEC_DOM_DAYS_LEFT:-999}" -le 0 ] && echo "🔴 CRÍTICO: El dominio ha expirado o está próximo a expirar" || true)

**💡 Recomendaciones de seguridad HTTP:**
- $([ "$SEC_HSTS" != "true" ] && echo "🔴 CRÍTICO: Implementar HSTS: \`Strict-Transport-Security: max-age=31536000; includeSubDomains\`" || echo "- HSTS configurado ✓")
- $([ "$SEC_CSP" != "true" ] && echo "🔴 CRÍTICO: Configurar Content-Security-Policy estricta para prevenir XSS" || echo "- CSP configurado ✓")
- $([ "$SEC_XCTO" != "true" ] && echo "🟠 ALTO: Añadir \`X-Content-Type-Options: nosniff\`" || echo "- X-Content-Type-Options ✓")
- $([ "$SEC_XFO" != "true" ] && echo "🟠 ALTO: Añadir \`X-Frame-Options: DENY\` para prevenir Clickjacking" || echo "- X-Frame-Options ✓")

---

### 🛡️ 5. Ciberseguridad

**Score: ${SCORE_CIBERSEGURIDAD}/100** $(score_badge $SCORE_CIBERSEGURIDAD)

| Elemento | Estado | Detalle |
|----------|--------|---------|
| Server header | $(echo "$CYBER_SERVER" | grep -qi "oculto" && echo "✅ Oculto" || echo "⚠️ Expuesto") | \`${CYBER_SERVER}\` |
| X-Powered-By | $(echo "$CYBER_POWERED_BY" | grep -qi "oculto" && echo "✅ Oculto" || echo "⚠️ Expuesto") | \`${CYBER_POWERED_BY}\` |
| Directorios expuestos | $([ "${CYBER_EXPOSED_DIRS[0]}" == "Ninguno detectado" ] && echo "✅ OK" || echo "🔴 DETECTADOS") | ${CYBER_EXPOSED_DIRS[*]} |
| security.txt | $([ "$CYBER_SEC_TXT" == "200" ] && echo "✅" || echo "⚠️ No encontrado") | HTTP ${CYBER_SEC_TXT} |
| SPF Record | $(echo "$CYBER_SPF" | grep -qi "v=spf" && echo "✅" || echo "⚠️") | \`${CYBER_SPF:0:60}\` |
| DMARC Record | $(echo "$CYBER_DMARC" | grep -qi "v=DMARC" && echo "✅" || echo "⚠️") | \`${CYBER_DMARC:0:60}\` |

**💡 Recomendaciones:**
- $(echo "$CYBER_SERVER" | grep -qiE "[0-9]|apache|nginx|iis|php" && echo "🟠 ALTO: Ocultar versión del servidor en header Server" || echo "- Server header sin versiones ✓")
- $(echo "$CYBER_POWERED_BY" | grep -qi "oculto" || echo "🟡 MEDIO: Eliminar header X-Powered-By para reducir superficie de ataque")
- $([ "$CYBER_SEC_TXT" != "200" ] && echo "🟢 BAJO: Crear \`/.well-known/security.txt\` con contacto de seguridad" || echo "- security.txt presente ✓")
- Implementar WAF (Web Application Firewall)
- Realizar pentesting periódico (OWASP Top 10)
- Configurar monitoreo de integridad de archivos

---

### ⚙️ 6. Calidad Técnica

**Score: ${SCORE_CALIDAD_TECNICA}/100** $(score_badge $SCORE_CALIDAD_TECNICA)

| Elemento | Estado | Detalle |
|----------|--------|---------|
| DOCTYPE HTML5 | $([ "$CT_DOCTYPE" == "true" ] && echo "✅" || echo "❌") | — |
| Atributo lang | $([ "$CT_LANG" == "true" ] && echo "✅" || echo "❌") | — |
| Meta charset | $([ "$CT_CHARSET" == "true" ] && echo "✅" || echo "❌") | — |
| Viewport meta | $([ "$CT_VIEWPORT" == "true" ] && echo "✅" || echo "❌") | — |
| Title tag | $([ "$CT_TITLE" == "true" ] && echo "✅" || echo "❌") | — |
| Canonical URL | $([ "$CT_CANONICAL" == "true" ] && echo "✅" || echo "❌") | — |
| Scripts inline | $(( CT_INLINE_SCRIPTS > 5 )) && echo "⚠️ Muchos" || echo "✅ OK" | ${CT_INLINE_SCRIPTS} detectados |
| Estilos inline | $(( CT_INLINE_STYLES > 10 )) && echo "⚠️ Muchos" || echo "✅ OK" | ${CT_INLINE_STYLES} detectados |
| Links analizados | — | ${CT_BROKEN_LINKS} encontrados |
$([ -n "$HTMLHINT_CMD" ] && echo "| htmlhint errores | $([ ${CT_HTMLHINT_ERRORS:-0} -eq 0 ] && echo '✅ 0' || echo "⚠️ ${CT_HTMLHINT_ERRORS}") | ${CT_HTMLHINT_WARNINGS:-0} warnings |")

**💡 Recomendaciones:**
- $([ "$CT_DOCTYPE" != "true" ] && echo "🔴 CRÍTICO: Añadir \`<!DOCTYPE html>\` al inicio del documento" || echo "- DOCTYPE correcto ✓")
- $([ "$CT_LANG" != "true" ] && echo "🟠 ALTO: Añadir atributo \`lang\` al elemento \`<html>\`" || echo "- Atributo lang presente ✓")
- $([ "$CT_CANONICAL" != "true" ] && echo "🟡 MEDIO: Implementar URLs canónicas para evitar contenido duplicado" || echo "- Canonical URL presente ✓")
- Migrar estilos y scripts inline a archivos externos
- Implementar validación HTML con W3C Validator
- Establecer proceso de code review y testing automatizado

---

### 🎨 7. Diseño

**Score: ${SCORE_DISENO}/100** $(score_badge $SCORE_DISENO)

| Elemento | Estado | Detalle |
|----------|--------|---------|
| Diseño responsive | $([ "$DIS_VIEWPORT" == "true" ] && echo "✅" || echo "❌") | — |
| Frameworks CSS | ✅ | ${DIS_FRAMEWORKS[*]} |
| Tipografía web | $([ "$DIS_FONTS" == "true" ] && echo "✅ Sí" || echo "⚠️ No detectada") | — |
| Favicon | $([ "$DIS_FAVICON" == "true" ] && echo "✅" || echo "⚠️ No encontrado") | — |
| Dark mode | $([ "$DIS_DARK_MODE" == "true" ] && echo "✅" || echo "➖ No implementado") | — |
$([ -n "${DIS_LH_SCORE:-}" ] && echo "| Lighthouse Best Practices | ✅ ${DIS_LH_SCORE}/100 | — |")

**💡 Recomendaciones:**
- $([ "$DIS_FAVICON" != "true" ] && echo "🟡 MEDIO: Añadir favicon en múltiples resoluciones (16x16, 32x32, 180x180)" || echo "- Favicon presente ✓")
- $([ "$DIS_DARK_MODE" != "true" ] && echo "🟢 BAJO: Implementar dark mode con \`prefers-color-scheme\` para mejorar UX" || echo "- Dark mode implementado ✓")
- Establecer sistema de diseño (Design System) con tokens de color, tipografía y espaciado
- Realizar pruebas de consistencia visual entre dispositivos
- Verificar contraste mínimo de color (WCAG AA: 4.5:1)
- Revisar jerarquía visual y flujo de lectura en mobile-first

---

### 👤 8. Experiencia de Usuario (UX)

**Score: ${SCORE_UX}/100** $(score_badge $SCORE_UX)

| Elemento | Estado | Detalle |
|----------|--------|---------|
| Navegación clara | $([ "$UX_NAV" == "true" ] && echo "✅" || echo "❌") | — |
| Buscador | $([ "$UX_SEARCH" == "true" ] && echo "✅" || echo "➖") | — |
| Información de contacto | $([ "$UX_CONTACT" == "true" ] && echo "✅" || echo "❌") | — |
| CTA visibles | $([ "$UX_CTA" == "true" ] && echo "✅" || echo "⚠️") | — |
| Diseño responsive | $([ "$UX_RESPONSIVE" == "true" ] && echo "✅" || echo "❌") | — |
| Loading states | $([ "$UX_LOADING" == "true" ] && echo "✅" || echo "➖") | — |
| Página 404 personalizada | $([ "$UX_404" == "404" ] && echo "✅" || echo "⚠️") | HTTP ${UX_404} |

**💡 Recomendaciones:**
- $([ "$UX_NAV" != "true" ] && echo "🟠 ALTO: Implementar navegación principal semánticamente correcta (\`<nav>\`)" || echo "- Navegación principal presente ✓")
- $([ "$UX_CTA" != "true" ] && echo "🟠 ALTO: Definir y destacar CTAs primarios en above-the-fold" || echo "- CTAs presentes ✓")
- $([ "$UX_CONTACT" != "true" ] && echo "🟡 MEDIO: Asegurar visibilidad de información de contacto en header/footer" || echo "- Contacto visible ✓")
- $([ "$UX_404" != "404" ] && echo "🟡 MEDIO: Crear página 404 personalizada con navegación y búsqueda" || echo "- 404 personalizado ✓")
- Implementar encuestas de salida (exit-intent) para capturar feedback
- Analizar mapas de calor y grabaciones de sesión (Hotjar, Clarity)
- Reducir fricción en formularios (progresivos, validación en tiempo real)

---

## 🔐 Legal & Privacidad

| Elemento | Estado | Nivel de Riesgo |
|----------|--------|-----------------|
| Política de Privacidad | $([ "$LEGAL_PRIVACY" == "true" ] && echo "✅ Detectada" || echo "❌ No detectada") | $([ "$LEGAL_PRIVACY" != "true" ] && echo "🔴 CRÍTICO (GDPR Art. 13)" || echo "✅ OK") |
| Términos de Uso | $([ "$LEGAL_TERMS" == "true" ] && echo "✅ Detectados" || echo "⚠️ No detectados") | $([ "$LEGAL_TERMS" != "true" ] && echo "🟡 MEDIO" || echo "✅ OK") |
| Banner de Cookies | $([ "$LEGAL_COOKIES" == "true" ] && echo "✅ Detectado" || echo "❌ No detectado") | $([ "$LEGAL_COOKIES" != "true" ] && echo "🟠 ALTO (ePrivacy)" || echo "✅ OK") |
| Mención GDPR/RGPD | $([ "$LEGAL_GDPR" == "true" ] && echo "✅" || echo "⚠️") | — |
| Trackers detectados | — | ${LEGAL_TRACKERS[*]} |

### ⚖️ Análisis GDPR

$(if [ "$LEGAL_PRIVACY" != "true" ] || [ "$LEGAL_COOKIES" != "true" ]; then
echo "⚠️ **Riesgo legal detectado.** El sitio puede estar incumpliendo regulaciones de privacidad aplicables:"
echo ""
[ "$LEGAL_PRIVACY" != "true" ] && echo "- **Reglamento GDPR (UE) 2016/679 Art. 13**: Obligación de informar al usuario sobre el tratamiento de datos personales."
[ "$LEGAL_COOKIES" != "true" ] && echo "- **Directiva ePrivacy**: Consentimiento explícito requerido antes de instalar cookies no esenciales."
echo ""
echo "**Multas potenciales:** Hasta 20M€ o 4% de facturación anual global."
else
echo "✅ El sitio muestra señales positivas de cumplimiento. Se recomienda auditoría legal completa para confirmar."
fi)

**Acción recomendada:** Consultar con especialista en protección de datos (DPO) para auditoría completa de cumplimiento.

---

## 🎯 Matriz de Priorización

> **Impacto** (1=Bajo → 4=Crítico) × **Esfuerzo** (1=Bajo → 4=Alto)
> Prioridad = Impacto / Esfuerzo → Hacer primero lo que tiene alto impacto y bajo esfuerzo.

| Prioridad | Acción | Impacto | Esfuerzo | Dimensión | ROI Est. |
|:---------:|--------|:-------:|:--------:|-----------|:--------:|
$([ "$SEC_HSTS" != "true" ] && echo "| 🔴 **1** | Implementar HSTS | 4 | 1 | Seguridad | Alto |")
$([ "$SEC_CSP" != "true" ] && echo "| 🔴 **2** | Configurar CSP | 4 | 2 | Seguridad | Alto |")
$([ "$SEO_TITLE" == "AUSENTE" ] && echo "| 🔴 **3** | Añadir \`<title>\` único | 4 | 1 | SEO | Muy alto |")
$([ "$SEO_META_DESC" == "AUSENTE" ] && echo "| 🟠 **4** | Crear meta descriptions | 3 | 1 | SEO | Alto |")
$([ "$SEC_XCTO" != "true" ] && echo "| 🟠 **5** | Añadir X-Content-Type-Options | 3 | 1 | Seguridad | Medio |")
$([ "$ACC_ARIA" != "true" ] && echo "| 🟠 **6** | Implementar ARIA labels | 3 | 2 | Accesibilidad | Medio |")
$([ "$SEO_SITEMAP" != "200" ] && echo "| 🟡 **7** | Generar sitemap.xml | 2 | 1 | SEO | Medio |")
$([ "$SEO_SCHEMA" != "true" ] && echo "| 🟡 **8** | Añadir Schema.org | 2 | 2 | SEO | Medio |")
$([ "$LEGAL_COOKIES" != "true" ] && echo "| 🟡 **9** | Banner de cookies GDPR | 3 | 2 | Legal | Alto |")
$([ "$DIS_FAVICON" != "true" ] && echo "| 🟢 **10** | Añadir favicon | 1 | 1 | Diseño | Bajo |")

---

## 📈 Impacto Esperado por Recomendación

| Recomendación | KPI Afectado | Mejora Estimada | Plazo |
|---------------|-------------|-----------------|-------|
| HSTS + CSP | Seguridad · Confianza usuario | +15-20 pts seguridad | < 1 semana |
| Meta tags SEO | Tráfico orgánico · CTR en SERP | +10-30% CTR | 4-8 semanas |
| Compresión Gzip/Brotli | Tiempo de carga · Core Web Vitals | -30-50% tamaño | < 1 día |
| Schema.org | Rich snippets · Visibilidad Google | +20% CTR potencial | 2-4 semanas |
| ARIA + Accesibilidad | Alcance · Compliance · SEO | +5-15 pts accesibilidad | 2-6 semanas |
| Banner cookies GDPR | Riesgo legal | Reducción riesgo legal | 1-2 semanas |
| Headers seguridad | Puntuación Mozilla Observatory | +20-40 pts | < 1 día |

---

$(if [[ -n "$prev_report" && -f "$prev_report" ]]; then
cat <<EVOLMD

## 📉 Evolución vs. Auditoría Anterior

> Comparando con: \`$(basename "$prev_report")\`

| Dimensión | Anterior | Actual | Tendencia |
|-----------|:--------:|:------:|:---------:|
| Performance | $(extract_prev_score "$prev_report" "Performance") | $SCORE_PERFORMANCE | $(prev=$(extract_prev_score "$prev_report" "Performance"); [[ "$prev" =~ ^[0-9]+$ ]] && { (( SCORE_PERFORMANCE > prev )) && echo "📈 +$((SCORE_PERFORMANCE - prev))" || (( SCORE_PERFORMANCE < prev )) && echo "📉 $((SCORE_PERFORMANCE - prev))" || echo "➡️ Sin cambio"; } || echo "—") |
| SEO | $(extract_prev_score "$prev_report" "SEO") | $SCORE_SEO | $(prev=$(extract_prev_score "$prev_report" "SEO"); [[ "$prev" =~ ^[0-9]+$ ]] && { (( SCORE_SEO > prev )) && echo "📈 +$((SCORE_SEO - prev))" || (( SCORE_SEO < prev )) && echo "📉 $((SCORE_SEO - prev))" || echo "➡️ Sin cambio"; } || echo "—") |
| Accesibilidad | $(extract_prev_score "$prev_report" "Accesibilidad") | $SCORE_ACCESIBILIDAD | — |
| Seguridad | $(extract_prev_score "$prev_report" "Seguridad") | $SCORE_SEGURIDAD | — |
| Global | $(grep "Score Global" "$prev_report" 2>/dev/null | grep -oP '\d+(?= / 100)' | head -1 || echo "N/A") | $SCORE_GLOBAL | — |

EVOLMD
fi)

---

## 🧑‍💼 Roles Especializados — Perspectivas

### 🎨 Especialista UX/UI
> El sitio $([ "$UX_NAV" == "true" ] && echo "cuenta con navegación estructurada" || echo "carece de navegación semántica clara"). $([ "$UX_CTA" == "true" ] && echo "Los CTAs son detectables." || echo "Los CTAs no están claramente definidos, lo que puede impactar la tasa de conversión.") Se recomienda realizar pruebas de usabilidad con usuarios reales y analizar el funnel de conversión con herramientas como Hotjar o Microsoft Clarity.

### 📊 Analista de Datos Web
> Con un tiempo de respuesta de **${PERF_RESP_MS}ms**, el sitio $([ "$PERF_RESP_MS" -lt 800 ] && echo "cumple con los estándares de performance." || echo "puede estar perdiendo usuarios: según Google, cada 100ms adicional reduce conversiones ~1%.") Prioridad: implementar monitoreo continuo de Core Web Vitals con alertas proactivas.

### ✍️ Redactor SEO
> La estrategia de contenidos $([ "$SEO_TITLE" != "AUSENTE" ] && echo "tiene base técnica adecuada" || echo "requiere trabajo fundamental en metadatos"). $([ "$SEO_SCHEMA" == "true" ] && echo "El uso de structured data es positivo para rich snippets." || echo "La ausencia de Schema.org limita la visibilidad en Google.") Recomiendo auditoría de palabras clave y contenido existente.

### ⚙️ DevOps / SysAdmin
> **Estado de headers de seguridad: $([ "$SCORE_SEGURIDAD" -ge 70 ] && echo "aceptable" || echo "crítico").** $([ "$SEC_HSTS" == "true" ] && echo "HSTS configurado ✓." || echo "HSTS ausente — vulnerabilidad ante ataques MITM.") Se recomienda revisar configuración de nginx/Apache e implementar pipeline de seguridad automatizado (SAST/DAST).

### 🔏 Especialista en Privacidad
> $([ "$LEGAL_PRIVACY" == "true" ] && echo "Política de privacidad detectada." || echo "⚠️ No se detectó política de privacidad — riesgo GDPR.") Trackers detectados: **${LEGAL_TRACKERS[*]}**. Asegurar consentimiento explícito previo a la activación de trackers (GDPR Art. 6, base legal de consentimiento).

### 💰 Especialista CRO
> Las oportunidades de mejora en UX y performance tienen impacto directo en conversión. $([ "$UX_CTA" == "true" ] && echo "CTAs presentes." || echo "La falta de CTAs claros es una pérdida de conversión directa.") Implementar A/B testing en páginas de alto tráfico para validar hipótesis de optimización.

### 📱 Gerente de Producto Digital
> Score global **${SCORE_GLOBAL}/100** indica $(if (( SCORE_GLOBAL >= 80 )); then echo "un producto digital en buen estado con oportunidades de excelencia."; elif (( SCORE_GLOBAL >= 60 )); then echo "un producto funcional con deuda técnica acumulada que requiere roadmap de mejora estructurado."; else echo "deuda técnica crítica que requiere sprint de emergencia y revisión de prioridades del backlog."; fi) Recomiendo OKR trimestrales con métricas de performance, seguridad y UX como indicadores clave.

---

## 📋 Próximos Pasos Recomendados

### Sprint 1 — Inmediato (< 1 semana)
- [ ] Configurar headers de seguridad críticos (HSTS, CSP, X-Content-Type-Options)
- [ ] $([ "$SEO_TITLE" == "AUSENTE" ] && echo "Añadir/corregir title tags" || echo "Revisar title tags existentes")
- [ ] Activar compresión Gzip/Brotli en servidor
- [ ] $([ "$LEGAL_COOKIES" != "true" ] && echo "Implementar banner de consentimiento de cookies" || echo "Revisar banner de cookies existente")

### Sprint 2 — Corto Plazo (1-4 semanas)
- [ ] Optimizar meta descriptions y Open Graph
- [ ] Implementar sitemap.xml y registrar en Search Console
- [ ] Añadir ARIA labels en componentes interactivos
- [ ] Configurar SPF y DMARC en DNS

### Sprint 3 — Medio Plazo (1-3 meses)
- [ ] Implementar Schema.org structured data
- [ ] Auditoría completa de accesibilidad (WCAG 2.1 AA)
- [ ] Establecer monitoreo continuo (Uptime, Core Web Vitals, alertas)
- [ ] Revisar política de privacidad con asesoría legal

---

*Reporte generado automáticamente por [homium-audit](https://github.com/homium-tech/audit) · ${DATE_HUMAN}*
*Para soporte: https://github.com/homium-tech/audit/issues*
MDEOF
}

# ─── MAIN ─────────────────────────────────────────────────────────────────────
main() {
  echo -e "\n${BOLD}${CYAN}╔══════════════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}${CYAN}║        homium-audit v1.0.0                   ║${RESET}"
  echo -e "${BOLD}${CYAN}║  Auditoría web profesional · 8 dimensiones   ║${RESET}"
  echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════╝${RESET}\n"

  info "URL: ${BOLD}${URL}${RESET}"
  info "Destino: ${BOLD}${OUTPUT_DIR}${RESET}"

  # Setup
  mkdir -p "$OUTPUT_DIR"
  check_dependencies

  # Domain slug
  SLUG=$(normalize_domain "$URL")
  OUT_FILE="${OUTPUT_DIR}/reporte-${SLUG}-${TIMESTAMP}.md"

  # Previous report
  find_previous_report "$SLUG"

  # Run all dimensions
  analyze_performance
  analyze_seo
  analyze_accesibilidad
  analyze_seguridad
  analyze_ciberseguridad
  analyze_calidad_tecnica
  analyze_diseno
  analyze_ux
  analyze_legal

  # Compute global
  compute_global_score

  # Generate report
  step "Generando reporte"
  generate_report "$SLUG" "$OUT_FILE" "${PREV_REPORT:-}"
  ok "Reporte guardado: ${BOLD}${OUT_FILE}${RESET}"

  # Summary
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
  echo -e "  ${DIM}${ARROW} Reporte completo: ${OUT_FILE}${RESET}"
  [[ -n "${PREV_REPORT:-}" ]] && echo -e "  ${DIM}${ARROW} Comparado con: ${PREV_REPORT}${RESET}"
  echo ""
}

main "$@"
