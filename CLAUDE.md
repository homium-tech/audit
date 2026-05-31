# CLAUDE.md

Este archivo proporciona orientación a Claude Code (claude.ai/code) cuando trabaja con código en este repositorio.

## Qué es este proyecto

`homium-audit` es una herramienta CLI en bash puro que audita sitios web desde 8 dimensiones y genera reportes profesionales en Markdown. Corre como skill `/homium-audit` dentro de Claude Code.

**Flujo de uso:** `/homium-audit <URL>` → ejecuta `homium-audit.sh` → guarda `~/audits/reporte-[slug]-[timestamp].md` → Claude presenta el reporte → el usuario lo carga en Claude Design para generar una versión HTML con el design system de Homium.

El formato de salida es intencionalmente Markdown, no JSON. El reporte `.md` es el entregable final.

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

No hay suite de tests. La verificación manual se hace ejecutando el script contra una URL real e inspeccionando el `.md` generado en `~/audits/`.

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

### Lighthouse — una sola ejecución, cacheada

Lighthouse corre una vez vía `run_lighthouse_once()` y cachea los resultados en `$LH_JSON`. Todas las dimensiones que necesitan scores de Lighthouse llaman `lh_score "<category>"` que lee de ese cache. Nunca llamar `run_lighthouse_once()` de forma que dispare múltiples ejecuciones.

### Cadena de fallbacks para herramientas externas

Cada herramienta opcional tiene un fallback:
- `dig` → Google DNS API (`dns.google/resolve`)
- `whois` → RDAP API (`rdap.org`)
- `timeout` → `perl -e "alarm $t; exec @ARGV"`
- `jq` → `perl -nle` o patrones `grep`
- `lighthouse`, `axe`, `pa11y`, `htmlhint` → resueltos vía `resolve_cmd()` que intenta instalación global primero, luego `npx`

### Ciclo de vida del directorio temporal

`TMPDIR_AUDIT=$(mktemp -d)` se crea al inicio y se elimina al EXIT vía `trap`. Todos los archivos intermedios (Lighthouse JSON, salida de axe, pa11y, htmlhint, HTML crudo) van aquí. Nada persiste entre ejecuciones excepto el reporte `.md` final en `~/audits/`.

### Generación del reporte

`generate_report()` escribe el archivo Markdown completo en un solo heredoc `cat > "$out_file" << MDEOF`. Todas las variables deben estar asignadas antes de llamar esta función. El heredoc usa subshells `$()` inline para secciones condicionales (badges de score, líneas de recomendación).

## Estructura de archivos

```
homium-audit.sh          # Script principal — toda la lógica aquí
install.sh               # Instalador cross-platform (macOS/Linux/Windows Git Bash)
commands/homium-audit.md # Skill de Claude Code instalada en ~/.claude/commands/
homium-audit.md          # Spec completa del skill (fuente de verdad para documentación)
README.md                # Documentación pública
```

**Nota:** `commands/homium-audit.md` (3 líneas, instalado por `install.sh`) y `homium-audit.md` (raíz, spec completa) tienen propósitos distintos. El instalador copia `commands/homium-audit.md` a `~/.claude/commands/`. El `homium-audit.md` de raíz es el archivo de registro del skill.

## Problemas conocidos / limitaciones intencionales

- `_timeout` es llamada en `ssl_days_remaining()` pero la función no está definida en el script. El guard `|| { echo "-1"; return; }` evita crashes — SSL siempre retorna "No se pudo verificar" hasta que se corrija.
- El flag `--dimensions` está documentado en el README y los docs del skill pero no está implementado en el parser de argumentos. Usarlo causa exit 1.
- El HTML se descarga 6 veces separadas (una por dimensión). Ineficiencia conocida.
- La columna Δ en la tabla de evolución siempre muestra `—` — el cálculo del delta no está implementado.
- `ipinfo.io` (usado para geolocalización de hosting/IP) tiene un límite gratuito de 50k req/mes. En macOS, `whois` no está instalado por defecto; el fallback RDAP (`rdap.org`) puede retornar datos incompletos para algunos TLDs.

## Roadmap v1.2

| # | Mejora | Tipo | Viabilidad | Esfuerzo |
|---|--------|------|-----------|----------|
| 1 | Definir `_timeout` wrapper (fallback perl) — fix SSL | Bug fix | ✅ Confirmado | Mínimo |
| 2 | Implementar `--dimensions` en el parser | Bug fix | ✅ Confirmado | Medio |
| 3 | Cachear HTML (1 fetch compartido en lugar de 6) | Perf | ✅ Confirmado | Mínimo |
| 4 | Computar Δ real en tabla de evolución | Mejora reporte | ✅ Confirmado | Mínimo |
| 5 | Logo del sitio en el reporte vía `og:image` / favicon URL | Imágenes | ✅ Sin deps nuevas — URL ya está en el HTML descargado | Mínimo |
| 6 | Captura de pantalla del sitio en el reporte | Imágenes | ✅ Puppeteer/Playwright como dep opcional (igual que lighthouse) | Medio |
| 7 | SSL: datos completos (emisor, algoritmo, cipher, SAN) vía `openssl x509` | Detalle SSL | ✅ Solo requiere el fix de `_timeout` | Bajo |
| 8 | Dominio: más datos WHOIS (registrar email, status, DNSSEC) | Detalle dominio | ✅ Ya en respuesta RDAP, solo falta parsear más campos | Bajo |
| 9 | Hosting: ASN detallado, rango IP, abuse contact | Detalle hosting | ✅ `ipinfo.io` ya retorna más campos, falta extraerlos | Bajo |
| 10 | Sprint plan dinámico generado desde hallazgos reales | Mejora reporte | ✅ Confirmado | Bajo |
| 11 | DKIM check en Ciberseguridad (completa el trío SPF+DMARC+DKIM) | Feature | ✅ Mismo patrón DNS que SPF/DMARC | Mínimo |
| 12 | `--threshold <score>` para CI/CD (exit code basado en score mínimo) | Feature | ✅ Confirmado | Mínimo |
| 13 | `homium-audit --update` / `--version` | Feature | ✅ Confirmado | Bajo |
| 14 | `--sector <tipo>` para benchmarks contextuales (ecommerce/saas/blog) | Feature | ✅ Tabla de promedios por sector en el script | Medio |
| 15 | Sección Tecnología vía `webanalyze` (fingerprints Wappalyzer) — CMS, framework JS, e-commerce, CDN, analytics, servidor, lenguaje backend | Nueva sección | ✅ `webanalyze` (Go binary opcional) + fingerprinting bash propio como fallback | Medio |
| 16 | Core Web Vitals individuales (LCP, CLS, FID/INP) — ya están en `$LH_JSON`, solo falta extraerlos | Detalle Performance | ✅ Sin deps nuevas | Mínimo |
| 17 | TTFB separado + redirect chain + CDN detectado (Cloudflare, Fastly, Akamai) vía headers ya obtenidos | Detalle Performance | ✅ Sin deps nuevas — `curl -w` + headers | Mínimo |
| 18 | Recursos externos: cantidad de JS, CSS y fuentes cargadas desde HTML | Detalle Performance | ✅ Grep sobre HTML ya descargado | Mínimo |
| 19 | SEO extendido: Twitter/X Cards, jerarquía H2/H3, tipos Schema.org, hreflang, meta robots valor, conteo links internos/externos | Detalle SEO | ✅ Sin deps nuevas — grep sobre HTML | Bajo |
| 20 | Seguridad extendida: versión TLS + cipher suite, HSTS max-age real, calidad CSP (detectar unsafe-inline), SRI en scripts, Cookie SameSite, CAA record, MX record | Detalle Seguridad | ✅ Sin deps nuevas — openssl + headers + DNS API | Bajo |
| 21 | Ciberseguridad extendida: BIMI record, más rutas expuestas (`/.env`, `/wp-admin`, `/phpinfo.php`, `/swagger`), leer contacto de `security.txt` | Detalle Ciberseguridad | ✅ Sin deps nuevas — DNS API + curl | Mínimo |
| 22 | Calidad Técnica extendida: tags HTML deprecados (`<center>`, `<font>`), mixed content (HTTP en HTTPS), PWA (manifest.json + service worker) | Detalle Calidad | ✅ Sin deps nuevas — grep sobre HTML | Mínimo |
| 23 | Diseño extendido: print stylesheet, favicon alta resolución (192px/512px), conteo de breakpoints `@media` | Detalle Diseño | ✅ Sin deps nuevas — grep sobre HTML | Mínimo |
| 24 | UX extendido: chat widget (Intercom, Drift, Zendesk), redes sociales en footer, breadcrumbs, validación en formularios (`required`, `pattern`), página 500 custom | Detalle UX | ✅ Sin deps nuevas — grep sobre HTML + curl | Mínimo |
| 25 | Nueva sección Email Deliverability: SPF + DMARC + DKIM + MX + BIMI + puntuación consolidada | Nueva sección | ✅ Sin deps nuevas — DNS API (mismos patrones existentes) | Bajo |
| 26 | Fixes por hallazgo: columna "Cómo corregir" en todas las tablas + card expandida con código para hallazgos críticos y altos | Mejora reporte | ✅ Sin deps nuevas — lógica condicional en `generate_report()` | Medio |
| 27 | Sección Conclusión firmada por Homium — lenguaje de negocio, implicaciones reales por no corregir y ventajas concretas de mejorar, generada dinámicamente desde los scores reales | Mejora reporte | ✅ Sin deps nuevas — lógica condicional en `generate_report()` | Bajo |
