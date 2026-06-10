# Changelog

Todos los cambios notables de homium-audit se documentan aquí.

El formato sigue [Keep a Changelog](https://keepachangelog.com/es/1.0.0/).

---

## [1.7.2] — junio 2026

### Corregido
- **WebP subestimado** — el patrón solo detectaba `.webp"` literal. Ahora incluye `srcset="...webp"` y `type="image/webp"` — cubre la mayoría de sitios modernos que usan `<picture><source srcset>`.
- **Dark mode falso negativo** — `prefers-color-scheme` solo cubre CSS nativo. Agregado `data-theme=` y `class="*dark*"` para detectar la convención de Tailwind, shadcn/ui y la mayoría de sistemas de diseño desde 2022.
- **Scripts inline subcontados** — `<script>` exacto no detectaba `<script type="module">`, `<script defer>` ni `<script async>`. Ahora el patrón cubre todas las variantes inline sin `src=`.
- **Chat widget lista desactualizada** — agregados Gorgias, Help Scout, Liveblocks, tawk.to, Chaport, Olark y HubSpot chat a la detección de widgets.

---

## [1.7.1] — junio 2026

### Corregido
- **HTTP/2 siempre penalizado** — `curl -w "%{http_version}"` devuelve `"2.0"` y `"3.0"`, no `"2"` y `"3"`. La comparación exacta penalizaba −10 pts de performance a todos los sitios modernos con HTTP/2.
- **Alt text falso positivo** — `grep -cv 'alt='` detectaba `class="gallery-alt"` como si fuera atributo alt. Corregido con ` alt=` (espacio previo) para match exclusivo del atributo.
- **Skip link falso positivo** — buscar la palabra `skip` o `saltar` en cualquier parte del HTML marcaba `ACC_SKIP=true` aunque no hubiera skip navigation. Ahora busca patrones específicos: `href="#skip"`, `class="skip-link"`, `id="skip"`.
- **x.com no detectado como red social** — Twitter migró a `x.com` en 2023. Sitios que actualizaron sus links sociales no se detectaban. Agregado `x.com/[handle]` al patrón.
- **GA4 no detectado como tracker** — el patrón buscaba `ga.js` (Universal Analytics, deprecado julio 2023). GA4 se sirve vía `googletagmanager.com/gtag`. Agregado al patrón de detección.

---

## [1.7.0] — junio 2026

### Agregado
- **Flag `--upload`** — sube el JSON + screenshots a homium-audit-platform al finalizar la auditoría.
- **`~/.homium-audit.conf`** — archivo de configuración con `PLATFORM_URL`, `PLATFORM_TOKEN` y `AUTO_UPLOAD` opcional.
- **`AUTO_UPLOAD=true`** — sube automáticamente sin necesidad del flag en cada ejecución.
- Autenticación via Bearer token (`hap_xxxx`) — generado en `/tokens` de la plataforma.
- Mensajes de error claros en 401 con link directo para regenerar el token.

### Seguridad
- Parseo del config línea a línea (sin `source`) — evita ejecución de código arbitrario desde el archivo de configuración.

---

## [1.6.2-patch] — junio 2026

### Corregido — falsos positivos
- **HTTP→HTTPS redirect** — la detección ahora usa curl sin `-L` para capturar el 301 real, no el 200 final tras seguir la cadena de redirects.
- **Detección responsive** — escanea viewport meta (`width=device-width`) y el primer CSS externo enlazado. Antes solo buscaba `@media` en el HTML inline, fallando en sitios con CSS en archivos externos.
- **Hosting lookup** — fallback a `ip-api.com` cuando `ipinfo.io` devuelve error de rate-limit (4xx).
- **WHOIS registrar/nameservers/status** — fix de indentación en grep: Verisign/GoDaddy prefixa cada línea con 3 espacios que bloqueaban el match.
- **Fecha de creación de dominio** — prioriza `Creation Date:` sobre `created:` para evitar retornar `1985-01-01` (fecha de creación de ICANN).

### Mejorado — narrative en lenguaje de negocio
- `executive_summary` ahora es específico por sitio: menciona dimensión más fuerte, dimensión con mayor oportunidad y consecuencia de negocio. Incluye mención GEO si score < 60.
- `geo.context` usa formato `[nombre técnico] — [consecuencia de negocio]` en todos los issues.
- `narrative.brechas` incluye headers específicos ausentes, trackers detectados y score de email deliverability con nombre del dominio.
- `narrative.geo_insight` diferencia explícitamente GEO vs SEO.
- `evolution.deltas` ahora incluye `geo` junto a las demás dimensiones.

---

## [1.6.2] — junio 2026

### Agregado
- **Conclusión firmada** — título `## 💬 Conclusión — Homium` con apertura en lenguaje de marca.

### Cambiado
- **Skill `/homium-audit` actualizado** — reemplaza el volcado completo del MD por un resumen ejecutivo estructurado: score global, tabla 9 dimensiones, hallazgos críticos, paths de archivos.

### Eliminado
- Tabla "Diagnóstico general" de la conclusión — repetía los scores del inicio del reporte.
- Tiempos de implementación de todos los ítems del plan GEO y headers de grupo.
- Columna "Esfuerzo est." de la Hoja de Ruta.

---

## [1.6.1] — junio 2026

### Corregido
- **GEO — páginas About/Contact** — distingue tres estados: `✅ Página separada`, `⚠️ Solo sección in-page` y `❌ No existe`. Antes ambos casos marcaban `✅ Existe`, generando falsos positivos en sitios one-pager.
- Tabla de Contenido GEO sin fila vacía para tipos de sitio que no son ecommerce ni blog.

### Agregado
- **Hoja de Ruta GEO en 3 niveles** — 🔴 Urgente / 🟠 Importante / 🟡 Mediano plazo, con snippets JSON listos para copiar.
- **🗺️ Hoja de Ruta global** — tabla única numerada con hasta 21 acciones de todas las dimensiones, ordenadas por impacto × esfuerzo.
- **💬 Conclusión Ejecutiva en 5 secciones** — diagnóstico, fortalezas, brechas, análisis GEO y proyección de mejora con tabla antes/después.

---

## [1.6.0] — junio 2026

### Agregado
- **9ª dimensión: GEO (Generative Engine Optimization)** — visibilidad en ChatGPT, Gemini, Claude y Perplexity.
- Score por motor independiente (0-100): ChatGPT, Gemini, Claude, Perplexity.
- Detección de AI crawlers en `robots.txt` (GPTBot, ClaudeBot, PerplexityBot, Googlebot).
- Verificación de `llms.txt`.
- Schema para IA: FAQPage, HowTo, Speakable, Article, Product, Review, Organization.
- E-E-A-T: páginas About/Contact, autor visible, fecha de publicación visible.
- Contenido estructurado: ratio listas/tablas vs prosa, referencias autoritativas (.gov, .edu, Wikipedia).
- Auto-detección de tipo de sitio: ecommerce / blog / saas / onepager / institucional.

### Cambiado
- Score global redistribuido — GEO pesa 8%, demás pesos ajustados proporcionalmente (total = 100).
- Bloque `geo` agregado al JSON con engines / acceso / confianza / contenido.

---

## [1.5.0] — 2026

### Agregado
- **`compute_dimension_contexts()`** — genera una frase en lenguaje natural por dimensión basada en hallazgos reales. Aparece en 3 lugares: tabla de scores, blockquote por dimensión y campo `context` en JSON.
- `performance.resources`: `lazy_loading_count`, `srcset_usage`, `webp_avif_usage`, `fonts`, `third_party_domains`.
- `seo`: `word_count`, `last_modified`.
- `ciberseguridad`: `source_maps_exposed`.
- `ux`: `video_present`, `newsletter_signup`.
- `tecnologia`: `error_tracking`, `ab_testing`, `ad_scripts`.
- `hosting`: `ipv6`.

---

## [1.4.1] — 2026

### Corregido
- **`sprint_plan` vacío en JSON** — `_at()` usaba `eval` con comillas dobles sin escapar, haciendo que `sprint_1/2/3` siempre salieran como `[]`. Reemplazado por `_at1/_at2/_at3` con concatenación directa sin `eval`.
- **Priority matrix incompleta en MD** — faltaban "Forzar HTTPS redirect" y "Política de privacidad". Ahora MD y JSON tienen las mismas condiciones.
- **`analytics` vacío** — `"analytics": ["Ninguno detectado"]` corregido a `"analytics": []`.

---

## [1.4.0] — 2026

### Agregado
- **Archivo `.json`** — cada auditoría genera `reporte-[slug]-[timestamp].json` junto al `.md`.
- **Schema v1.0** — scores, benchmarks, Core Web Vitals numéricos, hallazgos con severidad y recomendación, priority matrix, sprint plan, correction guide con code snippets, perspectives por rol, narrative y evolution deltas.

---

## [1.3.4] — 2026

### Corregido
- **Detección de Chrome en Windows** — rutas Git Bash (`/c/...`) convertidas al formato `C:/...` que espera Node.js.
- **macOS y Linux** — detecta Chrome en `/Applications/Google Chrome.app`, Homebrew Chromium y rutas estándar de Linux.

### Agregado
- `install.sh` instala Chromium automáticamente si no hay navegador compatible.

---

## [1.3.3] — 2026

### Corregido
- **Lighthouse siempre corre** — `resolve_cmd` ya no pre-verifica disponibilidad del paquete npx. Usa `npx --yes <pkg>` en tiempo de ejecución.

---

## [1.3.2] — 2026

### Agregado
- **Homebrew automático** — se instala solo en macOS si no está presente.
- Instalación automática de `jq`, `dig`, `whois`, `node`, `go` y `webanalyze` según plataforma (brew / apt / dnf / yum / pacman).

---

## [1.3.1] — 2026

### Corregido
- `npm install -g` eliminado del installer — causaba falsos positivos en antivirus y fallos de permisos. Las herramientas se ejecutan vía `npx` bajo demanda.

---

## [1.3.0] — 2026

### Agregado
- Installer auto-npm — instala `lighthouse`, `axe-core`, `pa11y` y `htmlhint` si node/npm está disponible.
- Screenshots mejorados — usa `full-page-screenshot` con fallback a `final-screenshot`.
- Fecha en español — lookup table de meses compatible con bash 3.2+.

### Corregido
- `og:image` inválida descartada (valores no-URL como "website").
- Tabla seguridad — fila "HTTPS Redirect" tenía 3 columnas en tabla de 4.
- Matriz de priorización — numeración secuencial dinámica.
- Meta Pixel — patrón ampliado a `facebook.net` y `connect.facebook`.

---

## [1.2.1] — 2026

### Corregido
- **Slug de dominio** — `normalize_domain` usaba `\?` no soportado en BSD sed de macOS.
- **Benchmarking** — `case` dentro de `$()` en heredoc fallaba en bash 3; valores pre-computados antes del heredoc.
- **Sprint plan** — `printf "$s1"` interpretaba `-` como flag; corregido con `printf "%s"`.
- **`og:image`** — `sed` extraía el primer `content=` de la línea; corregido con `grep -oE`.
- **SSL en subshell** — `ssl_full_info` se ejecutaba en subshell; ahora se llama directamente.
- **SSL parsing** — issuer con apostrofe (Let's Encrypt) fallaba con `xargs`; reemplazado por perl trim. SAN usaba `\s` literal en BSD grep.
- **Broken pipe warnings** — `echo "$html" | grep -qi` generaba errores; reemplazado por herestring `<<< "$html"` en 40 líneas.
- **Word-splitting en heredoc** — comparaciones con títulos que contenían tildes o comas fallaban silenciosamente.

---

## [1.2.0] — 2026

### Agregado
- **Lighthouse dual** — Mobile + Desktop en una sola auditoría.
- **Core Web Vitals** — LCP, FCP, TBT, CLS, Speed Index por dispositivo.
- **Screenshots** — captura mobile y desktop desde Lighthouse.
- **Stack Tecnológico** — CMS, framework JS, lenguaje backend, CDN, analytics.
- **Email Deliverability** — score propio: SPF + DMARC + DKIM + MX + BIMI.
- **SSL completo** — emisor, versión TLS, cipher suite, SAN.
- **DKIM + BIMI** — completan el trío SPF + DMARC.
- **10 rutas expuestas** — `/.env`, `/wp-admin`, `/phpinfo.php`, `/swagger`, `/api-docs`.
- **Guía de corrección** — cards con código para hallazgos críticos y altos.
- **Sprint plan dinámico** — generado desde hallazgos reales.
- **`--dimensions`** — ejecutar solo las dimensiones necesarias.
- **`--sector`** — benchmarks contextuales por tipo de sitio.
- **`--threshold`** — exit 1 si score < umbral (CI/CD).
- **`--version` / `--update`** — gestión de versión desde terminal.
- **Caché HTML** — el HTML se descarga una sola vez (6x más eficiente).
- **Δ real en evolución** — diferencias calculadas con semáforo de color.

---

## [1.1.0] — 2026

### Agregado
- Auditoría en 8 dimensiones con score 0-100.
- Compatibilidad macOS / Linux / Windows Git Bash.
- Reporte Markdown con benchmarking, matriz de priorización y perspectivas por rol.
- Fallbacks automáticos para `dig`, `whois`, `timeout`.
