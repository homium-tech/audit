# 🔍 homium-audit

> Herramienta de auditoría web profesional para Claude Code.
> Analiza sitios web desde **9 dimensiones**, genera reportes Markdown listos para stakeholders y detecta el stack tecnológico completo.

[![Version](https://img.shields.io/badge/versión-1.6.1-blue.svg)](https://github.com/homium-tech/audit/releases/tag/v1.6.1)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-Compatible-blueviolet)](https://claude.ai)
[![Shell: Bash](https://img.shields.io/badge/Shell-Bash-green)](https://www.gnu.org/software/bash/)

---

## ✨ ¿Qué analiza?

| Dimensión | Herramientas | Qué detecta |
|-----------|-------------|-------------|
| ⚡ Performance | curl · Lighthouse | TTFB, Core Web Vitals, CDN, redirect chain, recursos JS/CSS |
| 🔍 SEO | curl · Lighthouse | Title, meta, H1-H3, OG, Twitter Cards, Schema.org, hreflang, links |
| 🤖 **GEO** | curl | **Nuevo en v1.6** — Visibilidad en ChatGPT, Gemini, Claude y Perplexity. Acceso de AI crawlers, llms.txt, FAQPage/HowTo/Speakable schema, E-E-A-T, autor y fecha visibles, contenido estructurado |
| ♿ Accesibilidad | curl · Lighthouse · axe · pa11y | Alt, ARIA, contraste, formularios, WCAG |
| 🔒 Seguridad | curl · openssl | Headers, SSL completo (TLS/cipher/SAN), HSTS max-age, CSP quality, CAA, MX |
| 🛡️ Ciberseguridad | curl · dig | SPF, DMARC, DKIM, BIMI, 10 rutas expuestas, security.txt |
| ⚙️ Calidad Técnica | curl · htmlhint | Tags deprecados, mixed content, PWA, Service Worker |
| 🎨 Diseño | curl · Lighthouse | Frameworks, dark mode, favicon hi-res, print stylesheet, breakpoints |
| 👤 UX | curl | Nav, CTAs, chat widget, redes sociales, breadcrumbs, validación formularios |

Genera un reporte **JSON estructurado** junto al `.md` en cada auditoría — base para integraciones y el dashboard de [homium-audit-platform](https://github.com/homium-tech/audit-platform).

---

## 🚀 Instalación

```bash
curl -sSL https://raw.githubusercontent.com/homium-tech/audit/main/install.sh | bash
```

El instalador detecta automáticamente el sistema operativo y configura todo.

### Actualizar a la última versión

```bash
homium-audit --update
```

---

## 💻 Compatibilidad

| Entorno | Soporte | Notas |
|---------|:-------:|-------|
| **macOS** (bash 3+) | ✅ Completo | Requiere bash 3.2+ (incluido por defecto) |
| **Linux** | ✅ Completo | Ubuntu, Debian, Fedora, etc. |
| **Windows — Git Bash** | ✅ Completo | Requiere [Git for Windows](https://git-scm.com/download/win) |
| **Windows — WSL** | ✅ Completo | Igual que Linux |
| **Windows — CMD/PowerShell** | ❌ | No soportado (requiere bash) |

### Requisitos mínimos

| Herramienta | macOS | Linux | Git Bash |
|-------------|:-----:|:-----:|:--------:|
| `bash` | ✅ incluido | ✅ incluido | ✅ incluido |
| `curl` | ✅ incluido | ✅ incluido | ✅ incluido |
| `openssl` | ✅ incluido | ✅ incluido | ✅ incluido |
| `perl` | ✅ incluido | ✅ incluido | ✅ incluido |

> Sin `dig` o `whois` el script usa APIs públicas como fallback automático. Sin `timeout` usa `perl` como alternativa. Todo funciona sin instalación adicional.

### Dependencias opcionales (análisis completo)

> El script las detecta automáticamente — si no están instaladas globalmente, intenta `npx`.

```bash
npm install -g lighthouse        # Performance · SEO · Accesibilidad · Core Web Vitals · Screenshots
npm install -g @axe-core/cli     # Accesibilidad WCAG profunda
npm install -g pa11y             # Accesibilidad WCAG complementaria
npm install -g htmlhint          # Calidad y buenas prácticas HTML
npm install -g ssl-checker       # Validación TLS y certificados
go install github.com/rverton/webanalyze/cmd/webanalyze@latest  # Stack tecnológico (Wappalyzer)
```

| Herramienta | Dimensión | Sin ella |
|-------------|-----------|----------|
| `lighthouse` | Performance · SEO · Accesibilidad · Diseño | Sin Core Web Vitals ni screenshots |
| `@axe-core/cli` | Accesibilidad | Sin reporte WCAG detallado |
| `pa11y` | Accesibilidad | Sin reporte WCAG complementario |
| `htmlhint` | Calidad técnica | Sin validación de errores HTML |
| `ssl-checker` | Seguridad | SSL verificado igualmente via `openssl` |
| `webanalyze` | Stack Tecnológico | Fingerprinting básico por patrones HTML |

---

## 📖 Uso

### Desde terminal

```bash
# Auditoría completa
homium-audit https://ejemplo.com

# Solo ciertas dimensiones
homium-audit https://ejemplo.com --dimensions seo,performance,seguridad

# Con sector para benchmarks contextuales
homium-audit https://ejemplo.com --sector ecommerce

# Directorio de salida personalizado
homium-audit https://ejemplo.com --output /tmp/reportes

# Comparar con reporte anterior
homium-audit https://ejemplo.com --compare ~/audits/reporte-ejemplo-20250101.md

# Modo CI/CD — exit 1 si score < umbral
homium-audit https://ejemplo.com --threshold 70

# Modo silencioso
homium-audit https://ejemplo.com --quiet

# Ver versión instalada
homium-audit --version

# Actualizar a la última versión
homium-audit --update
```

### Dimensiones disponibles para `--dimensions`

```
performance, seo, geo, accesibilidad, seguridad, ciberseguridad, calidad, diseno, ux
```

### Sectores disponibles para `--sector`

| Sector | Benchmarks ajustados para |
|--------|--------------------------|
| `ecommerce` | Tiendas online — performance y UX prioritarios |
| `saas` | Aplicaciones SaaS — seguridad y accesibilidad |
| `blog` | Blogs y medios — SEO como métrica central |
| `landing` | Landing pages — conversión y velocidad |
| `portfolio` | Portfolios — diseño destacado |

### Desde Claude Code

```
/homium-audit https://ejemplo.com
```

---

## 📄 Estructura del Reporte

Cada auditoría genera dos archivos en `~/audits/`:
- `reporte-[dominio]-[timestamp].md` — reporte visual para stakeholders
- `reporte-[dominio]-[timestamp].json` — datos estructurados para integraciones

El `.md` incluye:

1. **Capturas de pantalla** *(si Lighthouse disponible)* — Mobile y desktop side-by-side
2. **Resumen Ejecutivo** — Para gerentes y stakeholders no técnicos
3. **Score Global** (0-100) y **Score por Dimensión**
4. **Benchmarking por Sector** — vs. promedios del sector seleccionado
5. **Lighthouse Mobile vs Desktop** — Tabla comparativa con Core Web Vitals (LCP, FCP, TBT, CLS)
6. **Hallazgos por Dimensión** — Severidad: 🔴 Crítico · 🟠 Alto · 🟡 Medio · 🟢 Bajo
7. **Stack Tecnológico** — CMS, framework JS, lenguaje backend, CDN, analytics detectados
8. **Email Deliverability** — Score propio: SPF + DMARC + DKIM + MX + BIMI
9. **Legal & Privacidad** — GDPR, cookies, trackers detectados
10. **Matriz de Priorización** — Impacto × Esfuerzo con ROI estimado
11. **Perspectivas por Rol** — UX, SEO, DevOps, Legal, CRO, PM
12. **Plan de Acción Dinámico** — Sprints 1/2/3 generados desde los hallazgos reales
13. **Guía de Corrección** — Cards con código listo para copiar (HSTS, CSP, SPF, DKIM, etc.)
14. **Evolución** *(si existe reporte anterior)* — Δ scores reales entre auditorías
15. **Conclusión Homium** — Análisis ejecutivo en lenguaje de negocio

---

## 🗂 Estructura del Proyecto

```
homium-audit/
├── homium-audit.sh          # Script principal (v1.6.1)
├── install.sh               # Instalador one-liner
├── commands/
│   └── homium-audit.md      # Skill /homium-audit para Claude Code
├── CLAUDE.md                # Guía para Claude Code con arquitectura y roadmap
└── README.md
```

---

## 🔗 Ecosistema

Este repo es el **motor de recolección de datos**. Para el dashboard, gestión de auditorías y reportes web automáticos, ver:

**[homium-audit-platform](https://github.com/homium-tech/audit-platform)** — plataforma web que consume el JSON generado por este script.

---

## 📋 Changelog

### v1.6.1 — GEO fixes + Hoja de Ruta + Conclusión Ejecutiva

**Fixes de exactitud en GEO:**
- La detección de páginas About y Contact ahora distingue tres estados: `✅ Página separada` (URL propia con 200), `⚠️ Solo sección in-page` (anchor `#nosotros` en la misma página) y `❌ No existe`. Antes ambos casos marcaban `✅ Existe`, lo que generaba falsos positivos en sitios tipo one-pager.
- Tabla de Contenido GEO sin fila vacía para tipos de sitio que no son ecommerce ni blog.
- Fila "Tipo de sitio" con descripción contextual (e-commerce/blog/institucional).

**Plan de mejora GEO → Hoja de Ruta GEO en 3 niveles:**
- 🔴 **Urgente** — páginas dedicadas, corrección de schema name/sameAs, bots bloqueados. Cada ítem incluye descripción contextual inteligente (detecta si hay sección in-page y explica por qué igual se necesita una URL separada).
- 🟠 **Importante** — FAQPage schema con snippet JSON listo para copiar, llms.txt con plantilla completa.
- 🟡 **Mediano plazo** — autor visible, fecha en DOM con `<time>`, Speakable schema, ratio de contenido estructurado, fuentes externas.

**Sprints eliminados → 🗺️ Hoja de Ruta global:**
- Tabla única numerada con hasta 21 acciones de todas las dimensiones.
- Ordenada por impacto × esfuerzo real: primero headers de seguridad (15-30 min cada uno), luego GEO, legal, email, performance y calidad.
- Columnas: dimensión, severidad, esfuerzo estimado y resultado esperado con números concretos.

**💬 Conclusión Ejecutiva — 5 secciones:**
1. **Diagnóstico general** — tabla de scores por dimensión con semáforo de color.
2. **Fortalezas detectadas** — dinámicas, solo muestra las dimensiones que superan umbral real.
3. **Brechas críticas** — en lenguaje de negocio: qué riesgo concreto representa cada brecha (seguridad, GEO, email, GDPR).
4. **Análisis profundo GEO** — explica en qué difiere GEO del SEO tradicional y cuál es el gap de mayor impacto.
5. **Proyección de mejora** — tabla antes/después con scores estimados post-implementación + próximo paso recomendado.

### v1.6.0 — Nueva dimensión GEO (Generative Engine Optimization)

**9ª dimensión: visibilidad en buscadores de IA generativa.**

Evalúa qué tan bien posicionado está el sitio para ser citado por ChatGPT, Gemini, Claude y Perplexity — cada uno con su propio score y diagnóstico.

**Señales analizadas:**

- **Acceso de AI crawlers** — Verifica si GPTBot, ClaudeBot, PerplexityBot y Googlebot están permitidos en `robots.txt`. Un bot bloqueado = invisible para ese motor.
- **llms.txt** — Archivo emergente que indica a los modelos de IA qué contenido priorizar (equivalente moderno del sitemap para IA).
- **Schema para IA** — FAQPage, HowTo, Speakable, Article, Product, Review, Organization. Extraídos de los datos SEO ya cacheados (costo cero de red).
- **E-E-A-T** — Páginas "Quiénes somos" y "Contacto" como URLs separadas o secciones in-page. Autor visible, fecha de publicación visible.
- **Confianza del schema** — Detecta si el nombre de la empresa es genérico ("Home") o si `sameAs` está vacío.
- **Contenido estructurado** — Ratio de listas y tablas vs. prosa. Las IA prefieren contenido > 40% estructurado.
- **Referencias autoritativas** — Links a .gov, .edu, Wikipedia, PubMed y fuentes reconocidas.

**Score por motor** (0-100 independiente por buscador):

| Motor | Señales prioritarias |
|-------|---------------------|
| ChatGPT | GPTBot permitido · FAQPage schema · llms.txt |
| Gemini | Googlebot permitido · FAQPage + Speakable · E-E-A-T completo |
| Claude | ClaudeBot permitido · llms.txt · referencias autoritativas |
| Perplexity | PerplexityBot permitido · fecha visible · contenido estructurado |

**Tipo de sitio** — Auto-detectado desde el HTML (ecommerce / blog / saas / onepager / institucional). Los pesos del score varían según el tipo: e-commerce penaliza Product schema ausente, blogs penalizan Article sin autor, etc.

**Impacto en score global:** GEO pesa 8% en el score global. Los demás pesos se redistribuyeron proporcionalmente (total = 100).

### v1.5.0 — Contextos por dimensión + datos enriquecidos

**Contextos explicativos:**
- Nueva función `compute_dimension_contexts()` — genera una frase en lenguaje natural por dimensión basada en los hallazgos reales (no texto fijo)
- Aparece en **3 lugares**: columna "Contexto" en la tabla de scores, blockquote bajo el heading de cada dimensión en los hallazgos, y campo `context` por dimensión en el JSON
- Ejemplo: Seguridad 10/100 → *"Faltan 5 headers críticos: HSTS, X-Content-Type, X-Frame-Options, Referrer-Policy, Permissions-Policy. Sin redirección HTTP→HTTPS."*

**Datos nuevos (sin costo de red — grep sobre HTML ya descargado):**
- `performance.resources`: `lazy_loading_count`, `srcset_usage`, `webp_avif_usage`, `fonts`, `third_party_domains`
- `seo`: `word_count`, `last_modified` (del header HTTP)
- `ciberseguridad`: `source_maps_exposed` — penaliza score si están expuestos
- `ux`: `video_present`, `newsletter_signup`
- `tecnologia`: `error_tracking` (Sentry/Bugsnag/Rollbar), `ab_testing` (Optimizely/VWO), `ad_scripts` (Google Ads/DoubleClick)
- `hosting`: `ipv6` — vía `dig AAAA` con fallback a DNS API

### v1.4.1 — Alinear MD y JSON
- **Fix `sprint_plan` vacío** — Bug crítico en la función `_at()`: usaba `eval` con comillas dobles sin escapar, lo que hacía que `sprint_1/2/3` siempre salieran como `[]` en el JSON. Reemplazado por tres funciones `_at1/_at2/_at3` que concatenan directamente sin `eval`
- **Priority matrix completa en MD** — El MD no incluía "Forzar HTTPS redirect" ni "Política de privacidad" en la matriz de priorización. Ahora ambos archivos tienen las mismas 11 condiciones evaluadas
- **Fix analytics vacío** — `"analytics": ["Ninguno detectado"]` se corrige a `"analytics": []` cuando no hay herramientas detectadas

### v1.4.0 — JSON output estructurado
- **Nuevo archivo `.json`** — cada auditoría genera `reporte-[slug]-[timestamp].json` junto al `.md` en `~/audits/`
- **Schema v1.0** — cubre todos los datos del reporte: scores, benchmarks, Core Web Vitals numéricos, hallazgos por dimensión con severidad y recomendación, priority matrix, sprint plan, correction guide con code snippets, perspectives por rol, narrative y evolution deltas
- **Base para Audit Platform** — el JSON es el contrato de datos entre este script y [homium-audit-platform](https://github.com/homium-tech/audit-platform)
- **Campos v2 reservados** — campos `null` para features futuros: word count, lazy loading, third-party scripts, IPv6, source maps, etc.

### v1.3.4 — Detección automática de Chrome para Lighthouse (Windows + macOS + Linux)
- **Rutas Windows soportadas** — Detecta Chrome en `C:/Program Files/Google/Chrome/...`, `Program Files (x86)` y AppData del usuario; convierte rutas Git Bash (`/c/...`) al formato `C:/...` que espera Node.js
- **macOS y Linux** — Detecta Chrome en `/Applications/Google Chrome.app`, Homebrew Chromium y rutas estándar de Linux; pasa `--chrome-path` explícitamente a Lighthouse
- **Installer instala Chromium** — `install.sh` verifica si hay algún navegador compatible; si no, instala `chromium` automáticamente (brew / apt / dnf)
- **Resuelve N/A en Lighthouse** — Core Web Vitals y screenshots aparecen correctamente en equipos sin Chrome en PATH

### v1.3.3 — Fix Lighthouse vía npx
- **Lighthouse siempre corre** — `resolve_cmd` dejó de pre-verificar la disponibilidad del paquete npx (que descargaba el binario y podía fallar/timeout); ahora simplemente comprueba si `npx` existe y usa `npx --yes <pkg>` en tiempo de ejecución
- **Sin instalación previa requerida** — Lighthouse, axe-core, pa11y y htmlhint se descargan automáticamente la primera vez que se necesitan

### v1.3.2 — Installer totalmente automático
- **Homebrew automático** — Se instala solo en macOS si no está presente
- **Todas las dependencias** — `jq`, `dig`, `whois`, `node`, `go` y `webanalyze` se instalan automáticamente según la plataforma (brew / apt / dnf / yum / pacman)
- **Sin intervención manual** — El usuario solo corre el instalador; el sistema pide contraseña una sola vez si es necesario
- **No bloquea** — Si una herramienta falla, avisa y continúa con el resto

### v1.3.1
- **Fix installer** — Eliminado `npm install -g` que causaba falsos positivos en antivirus y fallos de permisos; las herramientas (`lighthouse`, `axe-core`, `pa11y`, `htmlhint`) se ejecutan vía `npx` bajo demanda, sin instalación global

### v1.3.0
- **Installer auto-npm** — `install.sh` instala automáticamente `lighthouse`, `axe-core`, `pa11y` y `htmlhint` si node/npm está disponible; verifica si ya están instalados antes de reinstalar
- **Screenshots mejorados** — Usa `full-page-screenshot` de Lighthouse (página completa, ~1280px) con fallback automático a `final-screenshot` para compatibilidad con versiones anteriores
- **Fecha en español** — El reporte mostraba el mes en inglés ("June"); corregido con lookup table de meses en español compatible con bash 3.2+
- **og:image inválida** — Descarta valores no-URL (ej. "website") para evitar imágenes rotas en el reporte
- **Recomendaciones Performance** — Líneas de protocolo y compresión mostraban vacías cuando estaban OK; ahora muestran confirmación positiva
- **Tabla seguridad** — Fila "HTTPS Redirect" tenía 3 columnas en tabla de 4; corregida columna faltante
- **Meta Pixel** — Patrón de detección ampliado a `facebook.net` y `connect.facebook` para capturar pixel cargado desde CDN
- **Matriz de priorización** — Numeración secuencial dinámica; ya no salta números cuando ítems previos están OK

### v1.2.1 — Bugfixes
- **Slug de dominio** — `normalize_domain` usaba `\?` (no soportado en BSD sed de macOS); reemplazado por dos `sed` separados para `http://` y `https://`. El nombre del reporte ahora es `reporte-dominio-co-...` en lugar de `reporte-https-...`
- **Benchmarking** — El `case` dentro de `$()` en el heredoc fallaba en bash 3; los valores se pre-computan antes del heredoc y se insertan como variables simples
- **Sprint plan** — `printf "$s1"` interpretaba el `-` de `- [ ]` como flag; corregido con `printf "%s" | sed 's/\\n/\n/g'`
- **og:image** — El `sed` extraía el primer `content=` de la línea en lugar del de `og:image`; corregido con `grep -oE 'content="..."'` previo al sed
- **SSL en subshell** — `ssl_full_info` se ejecutaba en subshell vía `$()` y sus variables no regresaban al scope padre; ahora se llama directamente en `analyze_seguridad`
- **SSL parsing** — Issuer usaba `xargs` que fallaba con el apostrofe en "Let's Encrypt"; reemplazado por perl trim. SAN usaba `[^\s,]` donde `\s` es literal en BSD grep, causando que "homesas.co" se truncara a "home"; corregido con `[^, ]`
- **Broken pipe warnings** — `echo "$html" | grep -qi` generaba `write error: Broken pipe` cuando grep salía temprano al encontrar el primer match; reemplazado por herestring `grep -qi 'pattern' <<< "$html"` en 40 líneas (compatible bash 3.2+)
- **Word-splitting en heredoc** — Comparaciones `[ "$SEO_TITLE" == "AUSENTE" ]` dentro del heredoc fallaban cuando el título contenía caracteres especiales (tildes, em dash, comas); variables booleanas pre-computadas fuera del heredoc y operadores `!=` y `==` sin espacio corregidos (`"$VAR"!=` → `"$VAR" !=`)

### v1.2.0
- **Lighthouse dual** — Mobile + Desktop en una sola auditoría con tabla comparativa
- **Core Web Vitals** — LCP, FCP, TBT, CLS, Speed Index por dispositivo
- **Screenshots** — Captura mobile y desktop desde Lighthouse, guardadas junto al reporte
- **Stack Tecnológico** — Nueva sección: CMS, framework JS, lenguaje backend, CDN, analytics
- **Email Deliverability** — Score propio SPF + DMARC + DKIM + MX + BIMI
- **SSL completo** — Emisor, versión TLS, cipher suite, SAN (dominios cubiertos)
- **Dominio extendido** — DNSSEC, estado, abuse email del registrador
- **Hosting extendido** — Rango IP, abuse contact vía ipinfo.io
- **Seguridad extendida** — HSTS max-age real, calidad CSP (unsafe-inline), SRI, CAA, MX
- **DKIM + BIMI** — Completan el trío SPF + DMARC en Ciberseguridad
- **10 rutas expuestas** — Agrega `/.env`, `/wp-admin`, `/phpinfo.php`, `/swagger`, `/api-docs`
- **Logo del sitio** — og:image embebida en el reporte
- **Guía de corrección** — Cards con código para hallazgos críticos y altos
- **Sprint plan dinámico** — Generado desde hallazgos reales, no estático
- **Conclusión Homium** — Cierre ejecutivo en lenguaje de negocio con implicaciones reales
- **`--dimensions`** — Ejecutar solo las dimensiones necesarias
- **`--sector`** — Benchmarks contextuales por tipo de sitio
- **`--threshold`** — Integración CI/CD con exit code por score mínimo
- **`--version` / `--update`** — Gestión de versión desde terminal
- **Caché HTML** — El HTML se descarga una sola vez (6x más eficiente)
- **Δ real en evolución** — Diferencias calculadas con semáforo de color

### v1.1.0
- Auditoría en 8 dimensiones con score 0-100
- Compatibilidad macOS / Linux / Windows Git Bash
- Reporte Markdown con benchmarking, matriz de priorización y perspectivas por rol
- Fallbacks automáticos para dig, whois, timeout

---

## 🤝 Contribuir

Issues y PRs bienvenidos en [github.com/homium-tech/audit](https://github.com/homium-tech/audit).

---

## 📝 Licencia

MIT © [Homium Tech](https://github.com/homium-tech)
