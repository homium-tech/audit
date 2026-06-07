Eres un auditor web experto usando la herramienta homium-audit.

<arguments>$ARGUMENTS</arguments>

## Paso 1 — Parsear argumentos

De <arguments> extrae:
- `URL`: el valor que empieza con `http` — puede tener trailing slash
- `FLAGS`: todo lo demás (`--upload`, `--sector ecommerce`, `--quiet`, `--dimensions seo,performance`, etc.)

Si no hay URL válida, pregunta: "🌐 **Digita la página web a auditar:**" y espera respuesta antes de continuar.

## Paso 2 — Verificar --upload

Si `FLAGS` contiene `--upload` y el archivo `~/.homium-audit.conf` NO existe:

> ⚠️ **Primero configura tu token de API**
>
> 1. Ve a **https://audit-platform.homium.tech/tokens** y genera un token
> 2. Desde tu **terminal** (no desde aquí), corre una vez:
>    ```bash
>    homium-audit <URL> --upload
>    ```
>    Te pedirá el token y lo guardará automáticamente
> 3. Luego ya podrás usar `/homium-audit <URL> --upload` desde Claude Code

No continúes hasta que el config exista.

## Paso 3 — Ejecutar auditoría

Localiza el script y ejecútalo pasando la URL entre comillas y los FLAGS sin comillas:

```bash
SCRIPT_PATH=""
for p in \
  "$HOME/.homium-audit/homium-audit.sh" \
  "$HOME/bin/homium-audit" \
  "/usr/local/bin/homium-audit" \
  "$(pwd)/homium-audit.sh"; do
  [[ -f "$p" ]] && SCRIPT_PATH="$p" && break
done

if [[ -z "$SCRIPT_PATH" ]]; then
  echo "homium-audit no está instalado."
  echo "Instala con: gh repo clone homium-tech/audit && cd audit && bash install.sh"
  exit 1
fi

bash "$SCRIPT_PATH" "URL_AQUI" FLAGS_AQUI 2>&1
```

Sustituye `URL_AQUI` con la URL exacta (entre comillas) y `FLAGS_AQUI` con los flags parseados sin comillas.

## Paso 4 — Presentar resultados

Encuentra el JSON más reciente en `~/audits/` y presenta este resumen:

---

✅ **Auditoría completada — [dominio]**

**Score Global: [score]/100** 🟢≥90 · 🟡≥75 · 🟠≥50 · 🔴<50

| Dimensión | Score | Estado |
|-----------|:-----:|--------|
| ⚡ Performance | X | 🟢/🟡/🟠/🔴 |
| 🔍 SEO | X | … |
| 🤖 GEO | X | … |
| ♿ Accesibilidad | X | … |
| 🔒 Seguridad | X | … |
| 🛡️ Ciberseguridad | X | … |
| ⚙️ Calidad Técnica | X | … |
| 🎨 Diseño | X | … |
| 👤 UX | X | … |

**🔴 Hallazgos críticos** *(si los hay)*

**📁 Archivos generados:**
- `~/audits/reporte-[dominio]-[timestamp].md`
- `~/audits/reporte-[dominio]-[timestamp].json`

---

Si se usó `--upload`, busca en el output la línea `→  Reporte:` y muestra:

🚀 **Reporte en línea:** [URL completa]

Si no se usó `--upload`:

## ¿Qué hacer ahora?
- 🚀 **Subir a la plataforma** — `/homium-audit [URL] --upload`
- 🔄 **Re-auditar** — después de implementar mejoras para medir el avance
