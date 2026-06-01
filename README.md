# 🔍 homium-audit

> Herramienta de auditoría web profesional para Claude Code.
> Analiza sitios web desde **8 dimensiones**, genera reportes Markdown listos para stakeholders y detecta el stack tecnológico completo.

[![Version](https://img.shields.io/badge/versión-1.3.3-blue.svg)](https://github.com/homium-tech/audit/releases/tag/v1.3.3)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-Compatible-blueviolet)](https://claude.ai)
[![Shell: Bash](https://img.shields.io/badge/Shell-Bash-green)](https://www.gnu.org/software/bash/)

---

## ✨ ¿Qué analiza?

| Dimensión | Herramientas | Qué detecta en v1.2 |
|-----------|-------------|---------------------|
| ⚡ Performance | curl · Lighthouse | TTFB, Core Web Vitals, CDN, redirect chain, recursos JS/CSS |
| 🔍 SEO | curl · Lighthouse | Title, meta, H1-H3, OG, Twitter Cards, Schema.org, hreflang, links |
| ♿ Accesibilidad | curl · Lighthouse · axe · pa11y | Alt, ARIA, contraste, formularios, WCAG |
| 🔒 Seguridad | curl · openssl | Headers, SSL completo (TLS/cipher/SAN), HSTS max-age, CSP quality, CAA, MX |
| 🛡️ Ciberseguridad | curl · dig | SPF, DMARC, **DKIM**, **BIMI**, 10 rutas expuestas, security.txt |
| ⚙️ Calidad Técnica | curl · htmlhint | Tags deprecados, mixed content, **PWA**, Service Worker |
| 🎨 Diseño | curl · Lighthouse | Frameworks, dark mode, favicon hi-res, print stylesheet, breakpoints |
| 👤 UX | curl | Nav, CTAs, chat widget, redes sociales, breadcrumbs, validación formularios |

**Nuevo en v1.2:** Sección **Stack Tecnológico** (CMS, framework JS, lenguaje backend, CDN, analytics) y sección **Email Deliverability** con score propio.

---

## 🚀 Instalación

```bash
curl -sSL https://raw.githubusercontent.com/homium-tech/audit/main/install.sh | bash
```

El instalador detecta automáticamente el sistema operativo y configura todo.

### Actualizar a v1.2

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
performance, seo, accesibilidad, seguridad, ciberseguridad, calidad, diseno, ux
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

Cada reporte `~/audits/reporte-[dominio]-[timestamp].md` incluye:

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
├── homium-audit.sh          # Script principal (v1.3.2)
├── install.sh               # Instalador one-liner
├── commands/
│   └── homium-audit.md      # Skill /homium-audit para Claude Code
├── CLAUDE.md                # Guía para Claude Code con arquitectura y roadmap
└── README.md
```

---

## 📋 Changelog

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
