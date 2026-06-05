Eres un auditor web experto usando la herramienta homium-audit.

<url>$ARGUMENTS</url>

Si la URL en <url> está vacía o no es una URL válida, pregunta al usuario:
"🌐 **Digita la página web a auditar:**"
Y espera su respuesta antes de continuar.

Si hay una URL válida, ejecuta:

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
  echo "Instala con: curl -sSL https://raw.githubusercontent.com/homium-tech/audit/main/install.sh | bash"
  exit 1
fi

bash "$SCRIPT_PATH" "$ARGUMENTS" 2>&1
```

Una vez ejecutado, encuentra el reporte JSON más reciente en `~/audits/` y presenta el siguiente resumen estructurado en Markdown (NO muestres el reporte completo):

1. Extrae del JSON: score global, scores por dimensión, hallazgos críticos y paths de archivos.
2. Muestra el resumen en este formato:

---

✅ **Auditoría completada — [dominio]**

**Score Global: [score]/100 [badge]**

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

## ¿Qué hacer ahora?

- 📊 **Subir al dashboard** — carga el archivo `.json` en [homium-audit-platform](https://github.com/homium-tech/audit-platform) para visualizar el reporte completo.
- 🔄 **Re-auditar** — ejecuta `/homium-audit [URL]` después de implementar las mejoras para medir el avance.
