---
name: homium-audit
description: >
  Analiza sitios web desde 8 dimensiones (performance, SEO, accesibilidad,
  seguridad, ciberseguridad, calidad técnica, diseño y UX) y genera un
  reporte profesional en Markdown guardado en ~/audits/.
  
  Úsalo cuando el usuario escriba /homium-audit, pida una "auditoría web",
  quiera analizar un sitio, evaluar performance/SEO/seguridad de una URL,
  o generar un reporte técnico de sitio web. También activa si mencionan
  Lighthouse, análisis web, web audit, o evaluar sitio.
argument-hint: "<URL>"
---

# /homium-audit — Auditoría Web Profesional

Analiza sitios web con **8 dimensiones especializadas** y genera reportes profesionales en Markdown.

## Cómo usar este comando

Cuando el usuario ejecute `/homium-audit <URL>`, debes:

1. **Localizar el script** en `~/.homium-audit/homium-audit.sh` o en la ruta de instalación
2. **Ejecutar la auditoría** con bash
3. **Mostrar el progreso** al usuario mientras corre
4. **Abrir y presentar** el reporte generado

---

## Flujo de Ejecución

### Paso 1 — Verificar instalación

```bash
# Buscar el script instalado
SCRIPT_PATH=""
for p in \
  "$HOME/.homium-audit/homium-audit.sh" \
  "/usr/local/bin/homium-audit" \
  "$(pwd)/homium-audit.sh"; do
  [[ -f "$p" ]] && SCRIPT_PATH="$p" && break
done

if [[ -z "$SCRIPT_PATH" ]]; then
  echo "homium-audit no está instalado."
  echo "Instala con:"
  echo "  curl -sSL https://raw.githubusercontent.com/homium-tech/audit/main/install.sh | bash"
fi
```

### Paso 2 — Ejecutar auditoría

```bash
bash "$SCRIPT_PATH" "<URL_DEL_USUARIO>" 2>&1
```

### Paso 3 — Leer y presentar el reporte

```bash
# El reporte se guarda en ~/audits/reporte-<slug>-<timestamp>.md
ls -t ~/audits/reporte-*.md | head -1
```

Lee el archivo generado y preséntalo al usuario con formato Markdown.

---

## Dimensiones que analiza

| # | Dimensión | Herramientas | Rol especializado |
|---|-----------|-------------|-------------------|
| 1 | ⚡ Performance | curl, Lighthouse | Analista de Datos Web |
| 2 | 🔍 SEO | curl, htmlq | Redactor SEO |
| 3 | ♿ Accesibilidad | curl, Lighthouse | Especialista UX/UI |
| 4 | 🔒 Seguridad HTTP | curl, openssl | DevOps / SysAdmin |
| 5 | 🛡️ Ciberseguridad | curl, dig | DevOps / SysAdmin |
| 6 | ⚙️ Calidad Técnica | curl, htmlq | Analista de Datos Web |
| 7 | 🎨 Diseño | curl, Lighthouse | Especialista UX/UI |
| 8 | 👤 UX | curl | Especialista CRO |

---

## Opciones soportadas

```
/homium-audit <URL>                         # Auditoría completa
/homium-audit <URL> --dimensions seo,perf   # Solo dimensiones específicas
/homium-audit <URL> --output /ruta/         # Cambiar directorio de salida
/homium-audit <URL> --compare <reporte.md>  # Comparar con reporte previo
/homium-audit <URL> --quiet                 # Solo salida mínima
```

---

## Estructura del reporte generado

El reporte en `~/audits/reporte-<dominio>-<timestamp>.md` incluye:

1. **Resumen Ejecutivo** — Lenguaje gerencial, contexto del estado actual
2. **Score Global** — Weighted average de las 8 dimensiones
3. **Scores por Dimensión** — Tabla con semáforos 🟢🟡🟠🔴
4. **Benchmarking** — vs. promedios de industria 2025
5. **Hallazgos por Dimensión** — Tablas con severidad por item
6. **Sección Legal & Privacidad** — GDPR, cookies, trackers detectados
7. **Matriz de Priorización** — Impacto × Esfuerzo con ROI estimado
8. **Impacto Esperado** — KPIs afectados y % de mejora estimado
9. **Perspectivas por Rol** — UX, SEO, DevOps, Legal, CRO, PM
10. **Próximos Pasos** — Sprint 1/2/3 con acciones concretas
11. **Evolución** *(si existe reporte anterior)* — Comparativa de scores

---

## Comportamiento al ejecutar

Al recibir `/homium-audit https://sitio.com`:

1. Informa al usuario que iniciará la auditoría (puede tomar 1-3 minutos)
2. Ejecuta el script y muestra los logs de progreso
3. Una vez terminado, lee el archivo `.md` generado
4. Presenta el reporte completo en el chat con formato Markdown
5. Ofrece explicar cualquier hallazgo o prioridad en detalle

### Mensaje de inicio sugerido:
> "Iniciando auditoría de `https://sitio.com`... Esto puede tomar entre 1 y 3 minutos dependiendo del sitio y las herramientas disponibles. Analizaré 8 dimensiones: performance, SEO, accesibilidad, seguridad, ciberseguridad, calidad técnica, diseño y UX."

---

## Instalación de dependencias opcionales

Para análisis completo con Lighthouse:
```bash
# Node.js requerido
npm install -g lighthouse

# htmlq (parser HTML)
cargo install htmlq  # o: brew install htmlq

# dig (DNS)
# Linux: sudo apt install dnsutils
# Mac: incluido en bind-tools
```

---

## Si el script no existe (instalación in-situ)

Si el usuario no tiene homium-audit instalado, descárgalo:

```bash
curl -sSL \
  https://raw.githubusercontent.com/homium-tech/audit/main/install.sh \
  | bash
```

O crea el script directamente desde el archivo en el repositorio.
