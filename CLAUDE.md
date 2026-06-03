# CLAUDE.md

Este archivo proporciona orientación a Claude Code (claude.ai/code) cuando trabaja con código en este repositorio.

## Qué es este proyecto

`homium-audit` es una herramienta CLI en bash puro que audita sitios web desde 8 dimensiones y genera reportes profesionales. Corre como skill `/homium-audit` dentro de Claude Code.

**Flujo de uso:** `/homium-audit <URL>` → ejecuta `homium-audit.sh` → guarda dos archivos en `~/audits/`:
- `reporte-[slug]-[timestamp].md` — reporte visual para stakeholders
- `reporte-[slug]-[timestamp].json` — datos estructurados para [homium-audit-platform](https://github.com/homium-tech/audit-platform)

Ambos archivos deben contener **exactamente la misma información**. El MD es el entregable legible para humanos; el JSON es el contrato de datos con la plataforma.

## Cómo ejecutar y probar

```bash
# Ejecutar una auditoría directamente
bash homium-audit.sh https://ejemplo.com

# Probar con directorio de salida personalizado
bash homium-audit.sh https://ejemplo.com --output /tmp/test-audits

# Probar modo silencioso
bash homium-audit.sh https://ejemplo.com --quiet

# Ejecutar el instalador localmente (usa el script local, no GitHub)
bash install.sh
```

No hay suite de tests. La verificación manual se hace ejecutando el script contra una URL real e inspeccionando los archivos `.md` y `.json` generados en `~/audits/`. Para verificar el JSON: `jq '.' reporte-*.json > /dev/null && echo "válido"`.

## Restricciones de compatibilidad — no romper

El script debe correr en **bash 3.2+** (macOS por defecto), Linux bash y Windows Git Bash. Cada feature de bash usada debe ser compatible con los tres entornos.

| Patrón | Razón |
|--------|-------|
| Sin `declare -A` | bash 3 no tiene arrays asociativos |
| Sin `set -e` ni `set -o pipefail` | Muchos comandos de auditoría retornan !=0 legítimamente; el modo estricto crashearía el script |
| Sin `grep -oP` | grep BSD (macOS) no tiene flag `-P`; usar `grep -oE` o `perl -nle` |
| Sin `timeout` directo | macOS no incluye GNU `timeout`; el script usa un wrapper `_timeout` (fallback a perl) |
| `date -j -f` primero, `date -d` como fallback | Sintaxis macOS vs Linux |
| `eval` para almacenar scores (`SCORE_S_*`) | Intencional — simula arrays asociativos en bash 3 |
| Sin `eval` para acumular strings en JSON | `eval` con comillas dobles rompe silenciosamente — usar funciones directas |

## Arquitectura

### Sistema de scores

Los scores se almacenan como variables simples usando `eval`:
```bash
set_score "performance" 85   # asigna SCORE_S_performance=85
get_score "performance"      # lee SCORE_S_performance
```
Este patrón es intencional por compatibilidad con bash 3. No refactorizar a `declare -A`.

El score global es un weighted average calculado en `compute_global_score()`:
```
performance:20 seo:15 accesibilidad:15 seguridad:15 ciberseguridad:10 calidad_tecnica:10 diseno:8 ux:7
```

### Contextos por dimensión

`compute_dimension_contexts()` se llama después de `compute_global_score()` y antes de `generate_report()`. Genera variables `CTX_*` con una frase explicativa en lenguaje natural por dimensión, basada en los hallazgos reales:

```bash
CTX_PERFORMANCE   # "Por encima del promedio del sector. Sin CDN. Sin imágenes WebP/AVIF."
CTX_SEO           # "Fundamentos SEO sólidos. Todos los elementos críticos presentes."
CTX_SEGURIDAD     # "Faltan 5 headers críticos: HSTS, CSP, ..."
# ... una por cada dimensión
```

Estas variables se usan en tres lugares: tabla de scores del MD (columna Contexto), blockquote bajo el heading de cada dimensión, y objeto `context` del JSON.

### HTML_CACHE — una sola descarga

El HTML se descarga una sola vez al inicio de `main()`:
```bash
HTML_CACHE=$(fetch_url "$URL")
```
Todas las funciones `analyze_*` leen `$HTML_CACHE` con `grep` — sin requests adicionales. Los datos de performance, SEO, accesibilidad, calidad, diseño, UX, tecnología y legal se extraen todos de esta variable. No llamar `fetch_url` dentro de las funciones analyze salvo para URLs específicas (robots.txt, sitemap, rutas expuestas).

### Lighthouse — una sola ejecución, cacheada

Lighthouse corre una vez vía `run_lighthouse_once()` y cachea los resultados en `$LH_JSON_MOBILE` y `$LH_JSON_DESKTOP`. Todas las dimensiones que necesitan scores de Lighthouse llaman `lh_score "<category>"` o `lh_metric "<audit>"` que leen de ese cache. Nunca llamar `run_lighthouse_once()` de forma que dispare múltiples ejecuciones.

### Dual output: MD + JSON

El ciclo de vida al final de `main()` es:
```bash
compute_global_score
compute_dimension_contexts          # genera CTX_* variables
generate_report "$OUT_FILE"         # escribe el .md
generate_json "$JSON_FILE"          # escribe el .json
```

Ambas funciones leen las mismas variables de shell. Si se agrega un dato nuevo, debe aparecer en **ambas funciones**. El JSON usa helpers internos:
- `_je "string"` — escapa para JSON (backslashes y comillas)
- `_jb "bool"` — convierte "true"/"false" a JSON boolean
- `_jarr item1 item2` — construye array JSON de strings
- `_lhnum "audit" "device"` — extrae métrica numérica de Lighthouse

### Sprint plan en JSON — patrón _at1/_at2/_at3

El sprint plan usa tres funciones de append directo (sin `eval`) para acumular ítems:
```bash
_at1() { [[ -n "$_s1" ]] && _s1="${_s1},\"..\"" || _s1="\"..\""; }
_at2() { ... }
_at3() { ... }
```
**No usar `eval` para acumular strings** — rompe silenciosamente cuando el string contiene comillas dobles.

### Cadena de fallbacks para herramientas externas

Cada herramienta opcional tiene un fallback:
- `dig` → Google DNS API (`dns.google/resolve`)
- `whois` → RDAP API (`rdap.org`)
- `timeout` → `perl -e "alarm $t; exec @ARGV"`
- `jq` → `perl -nle` o patrones `grep`
- `lighthouse`, `axe`, `pa11y`, `htmlhint` → resueltos vía `resolve_cmd()` que intenta instalación global primero, luego `npx`

### Ciclo de vida del directorio temporal

`TMPDIR_AUDIT=$(mktemp -d)` se crea al inicio y se elimina al EXIT vía `trap`. Todos los archivos intermedios (Lighthouse JSON, salida de axe, pa11y, htmlhint, HTML crudo) van aquí. Nada persiste entre ejecuciones excepto los archivos `.md` y `.json` finales en `~/audits/`.

## Datos que genera el JSON (schema v1.0)

| Sección | Campos clave |
|---------|-------------|
| `meta` | version, url, domain, timestamp, sector, tools_available |
| `scores` | global + 8 dimensiones + email_deliverability |
| `context` | frase explicativa por dimensión (generada dinámicamente) |
| `benchmarks` | average y top-10% por sector |
| `performance` | response_ms, ttfb, size_kb, protocol, compression, cdn, resources (js/css/images/fonts/webp/lazy/srcset/third_party), lighthouse mobile+desktop con CWV |
| `seo` | title, meta_desc, h1-h3, og, schema, hreflang, robots, sitemap, word_count, last_modified, links |
| `accesibilidad` | images_alt, aria, skip_nav, forms, axe, pa11y, lighthouse |
| `seguridad` | headers (hsts/csp/xcto/xfo/rp/per/sri), https_redirect, ssl, cookies, caa, mx |
| `ciberseguridad` | server, powered_by, exposed_paths, security_txt, spf, dmarc, dkim, bimi, source_maps_exposed |
| `calidad_tecnica` | doctype, lang, charset, viewport, canonical, inline scripts/styles, deprecated_tags, mixed_content, pwa, htmlhint |
| `diseno` | viewport, css_frameworks, fonts, favicon, dark_mode, print_css, breakpoints, lighthouse |
| `ux` | nav, search, contact, cta, responsive, loading, breadcrumbs, social, chat, form_validation, lang_switch, video_present, newsletter_signup, 404/500 |
| `legal` | privacy_policy, terms, cookie_consent, gdpr, trackers |
| `tecnologia` | cms, framework, language, server, cdn, analytics, error_tracking, ab_testing, ad_scripts |
| `hosting` | ip, country, city, org, asn, abuse_contact, ipv6 |
| `dominio` | registrar, created, expires, nameservers, dnssec, whois_privacy |
| `email_deliverability` | spf, dmarc, dkim, mx, bimi, score |
| `findings` | array de hallazgos por dimensión con severity, element, value, description, recommendation |
| `priority_matrix` | ítems ordenados por impacto × esfuerzo |
| `sprint_plan` | sprint_1/2/3 con tareas priorizadas |
| `correction_guide` | cards con código para hallazgos críticos/altos |
| `perspectives` | texto por rol: ux, seo, devops, legal, cro, product |
| `narrative` | executive_summary, conclusion |
| `evolution` | deltas vs reporte anterior |

## Estructura de archivos

```
homium-audit.sh          # Script principal — toda la lógica aquí
install.sh               # Instalador cross-platform (macOS/Linux/Windows Git Bash)
commands/homium-audit.md # Skill de Claude Code instalada en ~/.claude/commands/
homium-audit.md          # Spec completa del skill (fuente de verdad para documentación)
README.md                # Documentación pública
CLAUDE.md                # Este archivo
```

**Nota:** `commands/homium-audit.md` (3 líneas, instalado por `install.sh`) y `homium-audit.md` (raíz, spec completa) tienen propósitos distintos. El instalador copia `commands/homium-audit.md` a `~/.claude/commands/`. El `homium-audit.md` de raíz es el archivo de registro del skill.

## Problemas conocidos / limitaciones intencionales

- El flag `--dimensions` está documentado en el README y los docs del skill pero no está implementado en el parser de argumentos. Usarlo causa exit 1.
- La columna Δ en la tabla de evolución del MD siempre muestra `—` — el cálculo del delta real está implementado en el JSON (`evolution.deltas`) pero no en la tabla MD.
- `ipinfo.io` (usado para geolocalización de hosting/IP) tiene un límite gratuito de 50k req/mes. En macOS, `whois` no está instalado por defecto; el fallback RDAP (`rdap.org`) puede retornar datos incompletos para algunos TLDs.
- El score de Performance puede variar ±5 pts entre ejecuciones consecutivas por variación natural de Lighthouse (especialmente Mobile).
- `TECH_WEBANALYZE` solo se llena si `webanalyze` está instalado globalmente — no tiene fallback `npx`.

## Reglas al agregar datos nuevos

1. **Siempre en ambos archivos** — si un dato va al MD, va al JSON y viceversa.
2. **Sin requests extra** — preferir extraer de `$HTML_CACHE` (grep) o de los JSON de Lighthouse ya cacheados.
3. **Inicializar con default** — toda variable nueva debe tener `${VAR:-valor_default}` en el heredoc para evitar errores por variable no asignada.
4. **JSON válido** — después de agregar campos, verificar con `jq '.' archivo.json`.
5. **Actualizar `compute_dimension_contexts()`** — si un hallazgo nuevo afecta la explicación de una dimensión, agregar la condición correspondiente.
