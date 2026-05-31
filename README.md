# 🔍 homium-audit

> Herramienta de auditoría web profesional para Claude Code.
> Analiza sitios web desde **8 dimensiones** y genera reportes Markdown listos para stakeholders.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-Compatible-blueviolet)](https://claude.ai)
[![Shell: Bash](https://img.shields.io/badge/Shell-Bash-green)](https://www.gnu.org/software/bash/)

---

## ✨ ¿Qué analiza?

| Dimensión | Herramientas | Rol |
|-----------|-------------|-----|
| ⚡ Performance | curl · Lighthouse | Analista de Datos |
| 🔍 SEO | curl · htmlq | Redactor SEO |
| ♿ Accesibilidad | curl · Lighthouse | Especialista UX/UI |
| 🔒 Seguridad HTTP | curl · openssl | DevOps / SysAdmin |
| 🛡️ Ciberseguridad | curl · dig | DevOps / SysAdmin |
| ⚙️ Calidad Técnica | curl · htmlq | Analista de Datos |
| 🎨 Diseño | curl · Lighthouse | Especialista UX/UI |
| 👤 UX | curl | Especialista CRO |

---

## 🚀 Instalación

```bash
curl -sSL https://raw.githubusercontent.com/homium-tech/audit/main/install.sh | bash
```

### Dependencias opcionales (para análisis completo)

> El script detecta automáticamente cada herramienta. Si no está instalada globalmente, intenta usarla via `npx`. Sin ellas el análisis es parcial pero funcional.
>
> Todas las herramientas operan sobre información pública del sitio auditado (URL, dominio, IP). Ninguna accede a datos privados del sistema o del usuario.

```bash
npm install -g lighthouse        # Performance · SEO · Accesibilidad · Diseño
npm install -g @axe-core/cli     # Accesibilidad WCAG profunda
npm install -g pa11y             # Accesibilidad WCAG complementaria
npm install -g htmlhint          # Calidad y buenas prácticas HTML
npm install -g ssl-checker       # Validación TLS y certificados
```

| Herramienta | Dimensión | Sin ella |
|-------------|-----------|----------|
| `lighthouse` | Performance · SEO · Accesibilidad · Diseño | Análisis reducido |
| `@axe-core/cli` | Accesibilidad | Sin reporte WCAG detallado |
| `pa11y` | Accesibilidad | Sin reporte WCAG complementario |
| `htmlhint` | Calidad técnica | Sin validación de errores HTML |
| `ssl-checker` | Seguridad | Expiración SSL verificada igualmente via `openssl` |

---

## 📖 Uso

### Desde terminal

```bash
# Auditoría completa
homium-audit https://ejemplo.com

# Solo ciertas dimensiones
homium-audit https://ejemplo.com --dimensions seo,performance,seguridad

# Directorio de salida personalizado
homium-audit https://ejemplo.com --output /tmp/reportes

# Comparar con reporte anterior
homium-audit https://ejemplo.com --compare ~/audits/reporte-ejemplo-20250101.md

# Modo silencioso
homium-audit https://ejemplo.com --quiet
```

### Desde Claude Code

```
/homium-audit https://ejemplo.com
```

---

## 📄 Estructura del Reporte

Cada reporte `~/audits/reporte-[dominio]-[timestamp].md` incluye:

1. **Resumen Ejecutivo** — Para gerentes y stakeholders no técnicos
2. **Score Global** (0-100) y **Score por Dimensión**
3. **Benchmarking** — vs. promedios de industria 2025
4. **Hallazgos por Dimensión** — Severidad: 🔴 Crítico · 🟠 Alto · 🟡 Medio · 🟢 Bajo
5. **Legal & Privacidad** — GDPR, cookies, trackers detectados
6. **Matriz de Priorización** — Impacto × Esfuerzo con ROI estimado
7. **Perspectivas por Rol** — UX, SEO, DevOps, Legal, CRO, PM
8. **Plan de Acción** — Sprints 1/2/3 con tareas concretas
9. **Evolución** *(si existe reporte anterior)* — Δ scores entre auditorías

---

## 🗂 Estructura del Proyecto

```
homium-audit/
├── homium-audit.sh          # Script principal
├── install.sh               # Instalador one-liner
├── commands/
│   └── homium-audit.md      # Comando /homium-audit para Claude Code
├── references/              # Documentación adicional
└── README.md
```

---

## 🤝 Contribuir

Issues y PRs bienvenidos en [github.com/homium-tech/audit](https://github.com/homium-tech/audit).

---

## 📝 Licencia

MIT © [Homium Tech](https://github.com/homium-tech)
