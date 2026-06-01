# Debug — Lighthouse no corre en Windows

## Estado actual (v1.3.4)

Lighthouse no produce resultados en Windows con Git Bash aunque Chrome esté instalado.  
Síntoma: todas las celdas de Core Web Vitals y Lighthouse Mobile/Desktop muestran `N/A` en el reporte.

---

## Lo que ya se intentó

| Fix | Versión | Resultado |
|-----|---------|-----------|
| `resolve_cmd` dejó de pre-verificar npx | v1.3.3 | No resolvió en Windows |
| `_detect_chrome()` busca rutas Windows y pasa `--chrome-path` | v1.3.4 | Pendiente de verificar |

---

## Diagnóstico paso a paso

Correr estos comandos en **Git Bash en Windows** en orden. Cada uno valida un eslabón de la cadena.

### 1 — Verificar que node y npx existen

```bash
node --version
npm --version
npx --version
```

Si alguno falla → Node.js no está en PATH. Reiniciar Git Bash o correr el instalador de nuevo.

### 2 — Verificar que Lighthouse se puede descargar vía npx

```bash
npx --yes lighthouse --version
```

Esperar hasta 2 minutos (primera descarga). Si termina con un número de versión → OK.  
Si falla con `EACCES` o permisos → el cache de npm tiene permisos de root:

```bash
# Corregir permisos del cache npm
npm cache clean --force
# O si el directorio ~/.npm es de root:
# (correr en terminal de administrador o con sudo si tienes WSL)
```

### 3 — Verificar que Chrome se detecta correctamente

Copiar y pegar este bloque en Git Bash:

```bash
_detect_chrome() {
  [[ -f "/c/Program Files/Google/Chrome/Application/chrome.exe" ]] && \
    echo "C:/Program Files/Google/Chrome/Application/chrome.exe" && return
  [[ -f "/c/Program Files (x86)/Google/Chrome/Application/chrome.exe" ]] && \
    echo "C:/Program Files (x86)/Google/Chrome/Application/chrome.exe" && return
  [[ -f "${HOME}/AppData/Local/Google/Chrome/Application/chrome.exe" ]] && \
    echo "${HOME}/AppData/Local/Google/Chrome/Application/chrome.exe" && return
  echo "NO ENCONTRADO"
}
_detect_chrome
```

**Si dice `NO ENCONTRADO`:** Chrome no está donde se espera. Verificar la ruta real:

```bash
# Buscar chrome.exe en Program Files
find "/c/Program Files" -name "chrome.exe" 2>/dev/null | head -3
find "/c/Program Files (x86)" -name "chrome.exe" 2>/dev/null | head -3
find "${HOME}/AppData" -name "chrome.exe" 2>/dev/null | head -3
```

Anotar la ruta exacta que aparece — es la que hay que poner en `_detect_chrome()`.

### 4 — Correr Lighthouse manualmente con la ruta encontrada

Reemplazar `<RUTA_CHROME>` con lo que salió en el paso 3:

```bash
npx --yes lighthouse https://homesas.co \
  --output=json \
  --output-path=/tmp/lh-test.json \
  --only-categories=performance \
  --chrome-flags="--headless --no-sandbox --disable-gpu" \
  --chrome-path="<RUTA_CHROME>" \
  --quiet
echo "Exit code: $?"
ls -la /tmp/lh-test.json 2>/dev/null && echo "JSON generado OK" || echo "JSON NO generado"
```

**Si falla con mensaje de error:**  
Quitar `--quiet` para ver el error completo:

```bash
npx --yes lighthouse https://homesas.co \
  --output=json \
  --output-path=/tmp/lh-test.json \
  --only-categories=performance \
  --chrome-flags="--headless --no-sandbox --disable-gpu" \
  --chrome-path="<RUTA_CHROME>"
```

Anotar el error exacto.

### 5 — Probar sin --chrome-path (dejar que Lighthouse encuentre Chrome solo)

```bash
npx --yes lighthouse https://homesas.co \
  --output=json \
  --output-path=/tmp/lh-test2.json \
  --only-categories=performance \
  --chrome-flags="--headless --no-sandbox --disable-gpu"
echo "Exit code: $?"
ls -la /tmp/lh-test2.json 2>/dev/null && echo "JSON generado OK" || echo "FALLÓ"
```

Si este funciona pero el paso 4 no → el `--chrome-path` que pasamos es incorrecto (ruta mal formateada para Node.js en Windows).

### 6 — Probar sin --no-sandbox (algunos Windows lo rechazan)

```bash
npx --yes lighthouse https://homesas.co \
  --output=json \
  --output-path=/tmp/lh-test3.json \
  --only-categories=performance \
  --chrome-flags="--headless --disable-gpu"
echo "Exit code: $?"
```

---

## Errores conocidos y fixes

| Error | Causa | Fix |
|-------|-------|-----|
| `EACCES: permission denied ~/.npm` | Cache npm con permisos root (de `sudo npm` previo) | `npm cache clean --force` |
| `No usable sandbox found` | `--no-sandbox` conflicto en Windows | Quitar `--no-sandbox` de chrome-flags |
| `Chrome path not found` | `_detect_chrome()` no encuentra la ruta | Agregar la ruta correcta a `_detect_chrome()` (línea 274) |
| `Cannot find module 'lighthouse'` | npx no puede descargar | Verificar conexión y permisos de npm |
| `spawn Unknown system error -4058` | Ruta de Chrome inválida para Node.js | La ruta debe ser `C:/...` no `/c/...` |

---

## Dónde está el código relevante

Archivo: `homium-audit.sh`

| Función | Línea | Qué hace |
|---------|-------|---------|
| `resolve_cmd()` | 40 | Detecta si usar `lighthouse` global o `npx --yes lighthouse` |
| `LH_CMD=...` | 51 | Valor resultante del comando Lighthouse |
| `_detect_chrome()` | 274 | Busca Chrome en rutas de macOS / Linux / Windows |
| `_run_lh()` | 303 | Ejecuta Lighthouse pasando `--chrome-path` si se encontró |
| `run_lighthouse()` | 319 | Corre mobile + desktop, cachea resultados |

---

## Información a recolectar en Windows para el fix

Llenar esto con los resultados del diagnóstico:

```
node --version    →  
npm --version     →  
npx --version     →  
_detect_chrome()  →  
Chrome real path  →  
Paso 4 exit code  →  
Paso 4 error msg  →  
Paso 5 funciona   →  sí / no
Paso 6 funciona   →  sí / no
```

Con esos datos se puede hacer el fix correcto en `_detect_chrome()` o en los `--chrome-flags`.
