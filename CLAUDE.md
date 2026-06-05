# CLAUDE.md

Este archivo proporciona orientación a Claude Code (claude.ai/code) cuando trabaja con código en este repositorio.

## Qué es este proyecto

`homium-audit` es una herramienta CLI en bash puro que audita sitios web desde 9 dimensiones y genera reportes profesionales. Corre como skill `/homium-audit` dentro de Claude Code.

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
performance:19 seo:14 geo:8 accesibilidad:14 seguridad:14 ciberseguridad:9 calidad_tecnica:9 diseno:7 ux:6
```

### Contextos por dimensión

`compute_dimension_contexts()` se llama después de `compute_global_score()` y antes de `generate_report()`. Genera variables `CTX_*` con una frase explicativa en lenguaje natural por dimensión, basada en los hallazgos reales:

```bash
CTX_PERFORMANCE   # "Por encima del promedio del sector. Sin CDN. Sin imágenes WebP/AVIF."
CTX_SEO           # "Fundamentos SEO sólidos. Todos los elementos críticos presentes."
CTX_GEO           # "Visibilidad parcial en IA. Sin preguntas estructuradas para IA. Sin llms.txt."
CTX_SEGURIDAD     # "Faltan 5 headers críticos: HSTS, CSP, ..."
# ... una por cada dimensión
```

Estas variables se usan en tres lugares: tabla de scores del MD (columna Contexto), blockquote bajo el heading de cada dimensión, y objeto `context` del JSON.

### HTML_CACHE — una sola descarga

El HTML se descarga una sola vez al inicio de `main()`:
```bash
HTML_CACHE=$(fetch_url "$URL")
```
Todas las funciones `analyze_*` leen `$HTML_CACHE` con `grep` — sin requests adicionales. Los datos de performance, SEO, accesibilidad, calidad, diseño, UX, GEO, tecnología y legal se extraen todos de esta variable. No llamar `fetch_url` dentro de las funciones analyze salvo para URLs específicas (robots.txt, sitemap, rutas expuestas, llms.txt).

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

### Dimensión GEO — arquitectura

`analyze_geo()` corre después de `analyze_seo()` en `main()` y es **autónoma**: no depende de `analyze_tecnologia()`. Usa greps directos en `HTML_CACHE` para todo lo que necesita.

**Requests nuevos (máximo 4):**
- `curl -s /robots.txt` — descarga el contenido completo para parsear bots AI (el status ya se tenía; ahora se guarda el body)
- `HEAD /llms.txt` — verifica existencia del archivo de prioridades para IA
- `HEAD /nosotros` o `/about` — verifica página "Quiénes somos" como URL separada
- `HEAD /contacto` o `/contact` — verifica página de contacto como URL separada

**Señales extraídas de variables ya en memoria (costo cero):**
- `SEO_SCHEMA_TYPES` — contiene todos los tipos de schema; se hace `grep` para FAQPage, HowTo, Speakable, Article, Product, Review, Organization
- `SEO_EXT_LINKS` — total de links externos (base para ratio autoritativo)
- `SEO_WORD_COUNT` — palabras en página
- `UX_SOCIAL` — links a redes sociales

**Detección de tipo de sitio** (desde `HTML_CACHE`, sin depender de `TECH_CMS`):
```
ecommerce  → Shopify/WooCommerce/PrestaShop en HTML, /cart links
blog       → Ghost, /blog /articulos /noticias en links internos
saas       → Next.js/Nuxt sin blog
onepager   → < 3 links internos a sub-páginas
institucional → default
```
El flag `--sector` tiene prioridad sobre la auto-detección.

**Variables de salida de `analyze_geo()`:**
```bash
GEO_SITE_TYPE          # ecommerce|blog|saas|onepager|institucional
GEO_BOT_CHATGPT        # true|false — GPTBot permitido en robots.txt
GEO_BOT_GEMINI         # true|false — Googlebot permitido
GEO_BOT_CLAUDE         # true|false — ClaudeBot/anthropic-ai permitido
GEO_BOT_PERPLEXITY     # true|false — PerplexityBot permitido
GEO_LLMS_TXT           # true|false
GEO_SCHEMA_FAQ         # true|false — FAQPage schema
GEO_SCHEMA_HOWTO       # true|false — HowTo schema
GEO_SCHEMA_SPEAKABLE   # true|false — Speakable schema
GEO_SCHEMA_ARTICLE     # true|false — Article/BlogPosting schema
GEO_SCHEMA_PRODUCT     # true|false — Product schema (ecommerce)
GEO_SCHEMA_REVIEW      # true|false — Review/AggregateRating schema
GEO_SCHEMA_ORG         # true|false — Organization schema presente
GEO_SCHEMA_ORG_NAME_OK # true|false — nombre no es "Home" u otro genérico
GEO_SCHEMA_SAMAS_EMPTY # true|false — sameAs está vacío
GEO_PAGE_ABOUT         # true|false — /nosotros, /about o sección in-page detectada
GEO_PAGE_ABOUT_TYPE    # "pagina"|"seccion"|"ninguna" — URL separada vs anchor in-page vs ausente
GEO_PAGE_CONTACT       # true|false — /contacto, /contact o sección in-page detectada
GEO_PAGE_CONTACT_TYPE  # "pagina"|"seccion"|"ninguna" — URL separada vs anchor in-page vs ausente
GEO_AUTHOR_VISIBLE     # true|false — byline o itemprop="author" en HTML
GEO_DATE_VISIBLE       # true|false — <time datetime=> o itemprop="datePublished"
GEO_SOCIAL_LINKS       # true|false — redes sociales visibles en HTML
GEO_STRUCTURED_PCT     # 0-100 — % contenido en listas/tablas vs palabras
GEO_LI_COUNT           # int — cantidad de <li>
GEO_TABLE_COUNT        # int — cantidad de <table>
GEO_AUTH_LINKS         # int — links a .gov, .edu, Wikipedia, etc.
GEO_AUTH_LINKS_PCT     # 0-100 — % del total de links externos
GEO_ENGINE_CHATGPT     # 0-100 — score específico para ChatGPT
GEO_ENGINE_GEMINI      # 0-100 — score específico para Gemini
GEO_ENGINE_CLAUDE      # 0-100 — score específico para Claude
GEO_ENGINE_PERPLEXITY  # 0-100 — score específico para Perplexity
SCORE_GEO              # 0-100 — score global GEO
```

**Pesos del score por tipo de sitio:**
- `ecommerce`: penaliza fuerte Product schema ausente (-15) y Review (-8)
- `blog`: penaliza fuerte Article schema ausente (-15) y FAQ (-8)
- `landing/onepager`: penaliza FAQPage (-12) y Organization (-8)
- `institucional` (default): penaliza FAQPage (-12), Organization (-8), Article (-5), Speakable (-5)

**Advertencia sobre `case` en heredoc:** usar `if/elif/fi` en lugar de `case/esac` dentro de `$()` en heredocs — bash 3.2 parsea mal los `)` de los patrones de `case` dentro de command substitutions.

**Distinción página vs sección in-page:** `GEO_PAGE_ABOUT_TYPE` y `GEO_PAGE_CONTACT_TYPE` toman uno de tres valores:
- `"pagina"` — URL separada que responde 200 (`/nosotros` o `/about`)
- `"seccion"` — anchor in-page detectado (`id="nosotros"` o `href="#nosotros"`)
- `"ninguna"` — no detectado de ninguna forma

El MD muestra `✅ Página separada` / `⚠️ Solo sección in-page` / `❌ No existe` según el tipo. El JSON guarda el valor string del tipo para que la plataforma pueda diferenciar los tres estados.

### Estructura del reporte MD — secciones finales

Las secciones al final del MD (generadas en `generate_report()`) son:

1. **🗺️ Hoja de Ruta** — tabla numerada con hasta ~21 acciones de todas las dimensiones, ordenadas por impacto × esfuerzo. Columnas: acción, dimensión, severidad, impacto esperado (sin columna de esfuerzo/tiempos — eliminada en v1.6.2).

2. **💬 Conclusión — Homium** — abre con "De acuerdo al análisis realizado por **Homium**..." y contiene 4 secciones dinámicas:
   - Fortalezas detectadas (dinámicas según scores reales — solo muestra las que superan umbral)
   - Brechas críticas en lenguaje de negocio (seguridad, GEO, email, legal)
   - Análisis profundo GEO — explica qué mide, por qué difiere del SEO, y cuál es el gap principal
   - Proyección de mejora con tabla antes/después + próximo paso recomendado

   **Eliminado en v1.6.2:** tabla "Diagnóstico general" (duplicaba la tabla de scores del inicio) y todos los tiempos de implementación del plan GEO.

### Sprint plan en JSON — patrón _at1/_at2/_at3

El sprint plan en el JSON usa tres funciones de append directo (sin `eval`) para acumular ítems:
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
| `scores` | global + 9 dimensiones + email_deliverability |
| `context` | frase explicativa por dimensión (generada dinámicamente) |
| `benchmarks` | average y top-10% por sector (incluye geo) |
| `performance` | response_ms, ttfb, size_kb, protocol, compression, cdn, resources (js/css/images/fonts/webp/lazy/srcset/third_party), lighthouse mobile+desktop con CWV |
| `seo` | title, meta_desc, h1-h3, og, schema, hreflang, robots, sitemap, word_count, last_modified, links |
| `geo` | score, site_type, context, engines (chatgpt/gemini/claude/perplexity con score+estado), acceso (bots + llms_txt), confianza (pagina_empresa, pagina_contacto, autor_visible, fecha_visible, nombre_empresa_correcto, perfiles_sociales, redes_en_sitio), contenido (preguntas_estructuradas, guias_estructuradas, fragmentos_voz, articulos_con_autor, productos_marcados, resenas_estructuradas, contenido_estructurado_pct, listas_detectadas, tablas_detectadas, palabras, links_externos, links_autoritativos, links_autoritativos_pct) |
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
- `analyze_geo()` corre antes de `analyze_tecnologia()` por diseño — no puede usar `TECH_CMS` ni `TECH_WEBANALYZE`. Usa greps directos en `HTML_CACHE` para la detección de CMS/plataforma.
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
