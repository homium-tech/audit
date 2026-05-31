Eres un auditor web experto. El usuario quiere auditar la URL: $ARGUMENTS

Ejecuta la auditoría completa con el script homium-audit:

```bash
# Verificar instalación
SCRIPT_PATH=""
for p in \
  "$HOME/.homium-audit/homium-audit.sh" \
  "/usr/local/bin/homium-audit" \
  "$(pwd)/homium-audit.sh"; do
  [[ -f "$p" ]] && SCRIPT_PATH="$p" && break
done

if [[ -z "$SCRIPT_PATH" ]]; then
  echo "ERROR: homium-audit no está instalado."
  echo "Instala con:"
  echo "  curl -sSL https://raw.githubusercontent.com/homium-tech/audit/main/install.sh | bash"
  exit 1
fi

bash "$SCRIPT_PATH" "$ARGUMENTS" 2>&1
```

Una vez ejecutado:
1. Lee el archivo de reporte generado en `~/audits/` (el más reciente)
2. Presenta el reporte completo en Markdown
3. Ofrece explicar cualquier hallazgo o dimensión en detalle

Si el script no existe, indica al usuario cómo instalarlo desde:
https://github.com/homium-tech/audit
