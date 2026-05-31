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

Una vez ejecutado, lee el reporte `.md` más reciente en `~/audits/` y preséntalo completo en Markdown.

Al finalizar, muestra este mensaje exacto:

---

## 🎨 ¿Quieres visualizar este reporte para tu cliente?

1. Crea un nuevo proyecto en [Claude Design](https://claude.ai/design)
2. Carga el archivo `~/audits/reporte-[dominio]-[fecha].md` generado
3. Agrega tu design system como contexto del proyecto
4. Luego pide a Claude:

> **"Con base en el reporte cargado y el design system de Homium, pregunta que estilo de diseño quiero, por ejemplo: "claro o oscuro", Haz las preguntas necesarias para entender el contexto del cliente y sus necesidades de presentación. Finalmente genera un reporte HTML interactivo responsive para presentar al cliente que incluya:**
> - **Gráfica radar con los 8 scores**
> - **Barras de progreso animadas por dimensión**
> - **Menú de navegación lateral por sección**
> - **Cards por hallazgo con badge de severidad (crítico/alto/medio/bajo)**
> - **Matriz de priorización impacto × esfuerzo como cuadrante visual**
> - **Sección de evolución con comparativa si existe reporte anterior**
> - **Responsive mobile y desktop**
> - **Destaca en una tabla información de servidor, ssl, fechas de adquisición, fechas de expiración, etc.**
> - **Crea un botón para descargar una versión descargable en Pdf del informe.**
> - **Aplica los colores, tipografía y componentes del design system de Homium."**


