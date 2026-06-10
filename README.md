# 🔍 homium-audit

> Herramienta de auditoría web profesional para Claude Code.
> Analiza sitios web desde **9 dimensiones**, genera reportes Markdown listos para stakeholders y detecta el stack tecnológico completo.

[![Version](https://img.shields.io/badge/versión-1.7.0-blue.svg)](https://github.com/homium-tech/audit/releases/tag/v1.7.0)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-Compatible-blueviolet)](https://claude.ai)
[![Shell: Bash](https://img.shields.io/badge/Shell-Bash-green)](https://www.gnu.org/software/bash/)

---

## ✨ ¿Qué analiza?

| Dimensión | Herramientas | Qué detecta |
|-----------|-------------|-------------|
| ⚡ Performance | curl · Lighthouse | TTFB, Core Web Vitals, CDN, redirect chain, recursos JS/CSS |
| 🔍 SEO | curl · Lighthouse | Title, meta, H1-H3, OG, Twitter Cards, Schema.org, hreflang, links |
| 🤖 GEO | curl | Visibilidad en ChatGPT, Gemini, Claude y Perplexity. Acceso de AI crawlers, llms.txt, FAQPage/HowTo/Speakable schema, E-E-A-T, autor y fecha visibles, contenido estructurado |
| ♿ Accesibilidad | curl · Lighthouse · axe · pa11y | Alt, ARIA, contraste, formularios, WCAG |
| 🔒 Seguridad | curl · openssl | Headers, SSL completo (TLS/cipher/SAN), HSTS max-age, CSP quality, CAA, MX |
| 🛡️ Ciberseguridad | curl · dig | SPF, DMARC, DKIM, BIMI, 10 rutas expuestas, security.txt |
| ⚙️ Calidad Técnica | curl · htmlhint | Tags deprecados, mixed content, PWA, Service Worker |
| 🎨 Diseño | curl · Lighthouse | Frameworks, dark mode, favicon hi-res, print stylesheet, breakpoints |
| 👤 UX | curl | Nav, CTAs, chat widget, redes sociales, breadcrumbs, validación formularios |

Genera un reporte **JSON estructurado** junto al `.md` en cada auditoría — base para integraciones y el dashboard de [homium-audit-platform](https://github.com/homium-tech/audit-platform).

---

## 🤖 Dimensión GEO — Generative Engine Optimization

Evalúa qué tan bien posicionado está el sitio para ser **citado por motores de IA generativa**: ChatGPT, Gemini, Claude y Perplexity. Cada motor recibe su propio score independiente (0-100).

> GEO y SEO miden cosas distintas. El SEO mide si Google te *indexa*. El GEO mide si una IA te *cita* cuando alguien hace una pregunta relevante a tu negocio. Un sitio puede tener SEO 90 y GEO 30.

### Score por motor

| Motor | Señales prioritarias |
|-------|---------------------|
| ChatGPT | GPTBot permitido en robots.txt · FAQPage schema · llms.txt |
| Gemini | Googlebot permitido · FAQPage + Speakable schema · E-E-A-T completo |
| Claude | ClaudeBot/anthropic-ai permitido · llms.txt · referencias autoritativas |
| Perplexity | PerplexityBot permitido · fecha visible · contenido estructurado |

### Señales analizadas

- **Acceso de AI crawlers** — verifica si GPTBot, ClaudeBot, PerplexityBot y Googlebot están permitidos en `robots.txt`. Un bot bloqueado = invisible para ese motor.
- **llms.txt** — archivo que indica a los modelos de IA qué contenido priorizar (equivalente moderno del sitemap para IA).
- **Schema para IA** — FAQPage, HowTo, Speakable, Article, Product, Review, Organization.
- **E-E-A-T** — páginas "Quiénes somos" y "Contacto" como URLs separadas o secciones in-page. Autor visible, fecha de publicación visible.
- **Confianza del schema** — detecta si el nombre de la empresa es genérico ("Home") o si `sameAs` está vacío.
- **Contenido estructurado** — ratio de listas y tablas vs. prosa. Las IA prefieren contenido con más del 40% estructurado.
- **Referencias autoritativas** — links a .gov, .edu, Wikipedia, PubMed y fuentes reconocidas.

### Tipo de sitio — auto-detectado

Detectado desde el HTML: `ecommerce` / `blog` / `saas` / `onepager` / `institucional`. Los pesos del score varían según el tipo: e-commerce penaliza Product schema ausente, blogs penalizan Article sin autor, landing pages penalizan FAQPage ausente.

GEO pesa **8%** en el score global.

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

# Subir a homium-audit-platform al finalizar (requiere ~/.homium-audit.conf)
homium-audit https://ejemplo.com --upload

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
├── homium-audit.sh          # Script principal
├── install.sh               # Instalador one-liner
├── commands/
│   └── homium-audit.md      # Skill /homium-audit para Claude Code
├── CLAUDE.md                # Guía para Claude Code con arquitectura y decisiones técnicas
├── CHANGELOG.md             # Historial de cambios por versión
├── ROADMAP-SECURITY.md      # Mejoras de seguridad planificadas con análisis de brechas
├── ROADMAP-GEO.md           # Plan GEO v2: Copilot, answer-readiness, JSON-LD completeness
└── README.md
```

---

## 🔗 Ecosistema

Este repo es el **motor de recolección de datos**. Para el dashboard, gestión de auditorías y reportes web automáticos, ver:

**[homium-audit-platform](https://github.com/homium-tech/audit-platform)** — plataforma web que consume el JSON generado por este script.

### Integración automática con la plataforma

Con `--upload`, el CLI sube la auditoría directamente al finalizar:

```bash
# 1. Genera un API token en https://audit-platform.homium.tech/tokens
# 2. Configura ~/.homium-audit.conf:
#    PLATFORM_URL=https://audit-platform.homium.tech
#    PLATFORM_TOKEN=hap_xxxx...
# 3. Audita y sube en un solo paso:
homium-audit https://ejemplo.com --upload
```

Para subir siempre sin el flag, agrega `AUTO_UPLOAD=true` al config.
Documentación completa: [INTEGRATION.md](https://github.com/homium-tech/audit-platform/blob/main/INTEGRATION.md)

> ⚠️ **Seguridad:** `~/.homium-audit.conf` contiene tu API token en texto plano.
> **Nunca lo copies dentro de un repositorio ni lo compartas.**
> El archivo vive en tu carpeta home (`~/`) fuera de cualquier repo — ahí debe quedarse.
> Si accidentalmente lo mueves a un repo, agrégalo al `.gitignore` de inmediato y revoca el token desde [/tokens](https://audit-platform.homium.tech/tokens).

---

## 📋 Changelog

Ver historial completo en [CHANGELOG.md](CHANGELOG.md).

### Última versión — v1.7.0

- **Flag `--upload`** — sube el JSON + screenshots a homium-audit-platform al finalizar.
- **`~/.homium-audit.conf`** — configuración con `PLATFORM_URL`, `PLATFORM_TOKEN` y `AUTO_UPLOAD`.
- Parseo seguro del config (sin `source` — evita ejecución de código arbitrario).

---

## 🤝 Contribuir

Issues y PRs bienvenidos en [github.com/homium-tech/audit](https://github.com/homium-tech/audit).

---

## 📝 Licencia

MIT © [Homium Tech](https://github.com/homium-tech)
