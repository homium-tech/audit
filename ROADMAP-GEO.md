# Roadmap GEO v2 — homium-audit

Mejoras identificadas para la dimensión `geo`. El análisis actual es **access-centric**: se enfoca en si los bots pueden llegar al contenido. La v2 agrega un cuarto pilar — **answer-readiness** — que mide si el contenido está en el formato que un LLM necesita para citarlo directamente.

---

## Los cuatro pilares de GEO v2

| Pilar | Estado actual | Estado v2 |
|-------|--------------|-----------|
| **Acceso** | 4 bots + llms.txt | + Copilot/bingbot + noai detection + llms-full.txt |
| **Confianza** | About/Contact/autor/fecha/org schema | + dateModified vs datePublished + JSON-LD completeness |
| **Respuesta** | li count + table count + auth links | + question headings + citation patterns + definition sentences |
| **Integración** | — | + ai-plugin.json + llms.txt quality score |

---

## Pilar 1 — Acceso

### 1.1 Bing/Copilot — el 5° motor

**Estado actual — problema:**
Se verifican GPTBot, ClaudeBot, PerplexityBot y Googlebot. `bingbot` no se verifica. Microsoft Copilot usa Bing para grounding y está integrado en Windows, Edge y Office 365 — es el 5° motor de AI generativa con mayor base de usuarios instalada. Un sitio que bloquea `bingbot` es invisible para Copilot.

**Con la mejora:**
- Verificar `User-agent: bingbot` en robots.txt con el mismo patrón que los otros bots.
- Nuevo score por motor: `GEO_ENGINE_COPILOT` (0-100).
- Señales prioritarias para Copilot: bingbot permitido + structured content + dateModified reciente.
- Variable `GEO_BOT_COPILOT` (true/false).

**Señales clave para Copilot:** bingbot acceso · contenido estructurado · dateModified reciente · Organization schema.

---

### 1.2 Detección de `noai` / `noimageai`

**Estado actual — problema:**
No se detecta. Algunos sitios agregan `<meta name="robots" content="noai, noimageai">` para bloquear el uso de su contenido en entrenamiento de modelos. Es el equivalente inverso de llms.txt: declara explícitamente que el sitio no quiere ser usado por IA. Si está presente, todos los scores por motor deberían penalizarse.

**Con la mejora:**
- Grep en `$HTML_CACHE`: `<meta[^>]*name="robots"[^>]*content="[^"]*noai`.
- Variable `GEO_META_NOAI` (true/false).
- Si `true`: hallazgo alto y penalización del score global GEO.
- Reportar qué directivas tiene: `noai`, `noimageai`, o ambas.

**Impacto:** Señal de intención explícita — si el sitio no quiere ser citado por IA, el score de GEO debe reflejarlo. Hoy podría salir con GEO 70 aunque tenga esta directiva activa.

---

### 1.3 llms-full.txt

**Estado actual — problema:**
Solo se verifica `llms.txt`. La convención emergente incluye también `llms-full.txt` — una versión más detallada con el contenido completo del sitio en formato optimizado para LLMs. Algunos frameworks (Astro, Docusaurus, VitePress) lo generan automáticamente.

**Con la mejora:**
- HEAD a `/llms-full.txt`.
- Variable `GEO_LLMS_FULL_TXT` (true/false).
- Señal positiva adicional en el score de Claude y Perplexity (priorizan contenido denso y estructurado).

---

### 1.4 llms.txt — calidad del contenido, no solo existencia

**Estado actual — problema:**
Solo se hace HEAD para verificar si existe (status 200). Un `llms.txt` vacío o de dos líneas es marginalmente mejor que nada. Lo que hace efectivo un `llms.txt` es tener estructura: nombre del sitio (`# Nombre`), descripción (`> Descripción`), y al menos una sección con páginas clave enlazadas (`- [Página](URL): descripción`).

**Con la mejora:**
- Descargar el contenido (GET, igual que robots.txt ya descargado).
- Verificar presencia de `#` (nombre), `>` (descripción) y al menos una entrada `- [`.
- Variable `GEO_LLMS_TXT_QUALITY`: `"completo"` / `"parcial"` / `"vacio"`.
- Score diferenciado: presente y completo = 0 pts perdidos, presente pero vacío = −3 pts, ausente = −5 pts.

---

## Pilar 2 — Confianza

### 2.1 dateModified — frescura real del contenido

**Estado actual — problema:**
Se detecta si hay una fecha visible en el DOM (`<time datetime=>` o `itemprop="datePublished"`), pero no se distingue entre fecha de publicación y fecha de modificación. Para LLMs, especialmente Perplexity y Gemini, lo que importa es cuándo fue actualizado por última vez, no cuándo se publicó. Un artículo de 2019 actualizado en 2025 es más citable que uno publicado y nunca tocado.

**Con la mejora:**
- Grep `itemprop="dateModified"` y `"dateModified"` en JSON-LD como señal separada.
- Usar `SEO_LAST_MODIFIED` (HTTP header ya capturado) como fallback.
- Variable `GEO_DATE_MODIFIED` (true/false).
- Si solo hay `datePublished` pero no `dateModified`: hallazgo informativo.
- Penalización adicional en score de Perplexity si no hay `dateModified`.

---

### 2.2 JSON-LD completeness — calidad del schema, no solo presencia

**Estado actual — problema:**
Se detecta si existe `FAQPage`, `Organization`, `Article`, etc., pero no si están bien formados. Un schema con campos vacíos (`"name": ""`, `"sameAs": []`, `"author": ""`) es casi peor que no tenerlo — puede confundir al modelo con datos incorrectos o incompletos. Hoy un sitio con `Organization` vacío recibe el mismo puntaje que uno con Organization completo.

**Con la mejora:**

Para `Organization`:
- Verificar presencia de `"url"`, `"logo"`, `"contactPoint"` con valor no vacío.
- `GEO_SCHEMA_ORG_COMPLETE` (true/false).

Para `Article` / `BlogPosting`:
- Verificar `"headline"`, `"author"`, `"datePublished"` con valores reales.
- `GEO_SCHEMA_ARTICLE_COMPLETE` (true/false).

Para `FAQPage`:
- Verificar que tenga al menos una `Question` con `acceptedAnswer` no vacía.
- `GEO_SCHEMA_FAQ_COMPLETE` (true/false).

**Penalización:** schema presente pero incompleto = −3 pts (hoy no penaliza).

---

### 2.3 ai-plugin.json — optimización explícita para ChatGPT

**Estado actual — problema:**
No se detecta. `/.well-known/ai-plugin.json` es el manifest para GPT Actions / plugins de ChatGPT. Si existe, el sitio está explícitamente optimizado para integración con el ecosistema OpenAI — una señal de intención muy fuerte que hoy no aparece en el reporte.

**Con la mejora:**
- HEAD a `/.well-known/ai-plugin.json`.
- Variable `GEO_AI_PLUGIN` (true/false).
- Señal positiva en score de ChatGPT (+10 pts) y hallazgo de nivel "Bien" en el reporte.

---

## Pilar 3 — Answer-readiness (el gap más grande)

Un LLM genera respuestas buscando pasajes que ya estén en "formato de respuesta". Los sitios que estructuran contenido como Q&A, definiciones o afirmaciones con fuente son citados más frecuentemente. Todo lo siguiente es grep sobre `$HTML_CACHE` — costo de red cero.

### 3.1 Question headings — H2/H3 como preguntas

**Estado actual — problema:**
No se mide. Un H2 o H3 phrased como pregunta (`¿Qué es X?`, `¿Cómo funciona Y?`) le indica al modelo exactamente qué pregunta responde ese bloque de contenido. Es el patrón de contenido más directamente citable — el heading es la query, el párrafo siguiente es la respuesta.

**Con la mejora:**
```bash
GEO_QUESTION_HEADINGS=$(grep -oiE '<h[23][^>]*>[[:space:]]*(¿|Qué |Cómo |Por qué|Cuál |Cuándo |What |How |Why )' <<< "$html" | wc -l | tr -d ' ')
```
- Variable `GEO_QUESTION_HEADINGS` (int — número de headings con formato pregunta).
- 0 headings: penalización en score de ChatGPT y Perplexity.
- ≥ 3 headings: señal positiva, +5 pts en score de Perplexity.

**Impacto:** Diferencia blogs con contenido educativo bien estructurado de los que solo listan servicios. Costo: una línea de grep.

---

### 3.2 Citation patterns — contenido con atribución

**Estado actual — problema:**
Se cuentan links autoritativos (.gov, .edu, Wikipedia) pero no se verifica si el texto del contenido tiene patrones de citación. Frases como "según", "de acuerdo a", "fuente:", "publicado por", "basado en datos de" indican que el contenido hace afirmaciones con respaldo — exactamente lo que Claude y Perplexity priorizan para minimizar alucinaciones.

**Con la mejora:**
```bash
GEO_CITATION_PATTERNS=$(grep -oiE 'según |de acuerdo (a|con)|fuente:|publicado por|basado en|according to|published by|source:' <<< "$html" | wc -l | tr -d ' ')
```
- Variable `GEO_CITATION_PATTERNS` (int).
- 0 patrones en contenido de más de 500 palabras: hallazgo informativo.
- ≥ 3 patrones: señal positiva en score de Claude y Perplexity.

---

### 3.3 Definition sentences — contenido definitorio

**Estado actual — problema:**
No se mide. Las frases definitionales ("X es Y", "X se define como Y", "X refers to Y") son las más citadas por LLMs en respuestas a queries de tipo "¿qué es X?". Gemini y Perplexity especialmente favorecen páginas con definiciones claras en los primeros párrafos.

**Con la mejora:**
```bash
GEO_DEFINITION_PATTERNS=$(grep -oiE '[A-ZÁÉÍÓÚ][^.]{3,40} (es |son |se define|se refiere|refers to|is a |are )' <<< "$html" | wc -l | tr -d ' ')
```
- Variable `GEO_DEFINITION_PATTERNS` (int).
- Señal positiva si `GEO_DEFINITION_PATTERNS` > 0 para sitios institucionales y SaaS.

---

## Score por motor — v2

| Motor | Señales actuales | Señales nuevas v2 |
|-------|-----------------|-------------------|
| ChatGPT | GPTBot + FAQ + llms.txt + about/contact | + ai-plugin.json + question headings + JSON-LD completeness |
| Gemini / AI Overview | Googlebot + FAQ + Speakable + E-E-A-T | + dateModified reciente + definition sentences + JSON-LD completeness |
| Claude | ClaudeBot + llms.txt + auth links + author | + citation patterns + JSON-LD completeness + llms-full.txt |
| Perplexity | PerplexityBot + fecha + structured + auth links + FAQ | + dateModified + question headings + citation patterns |
| **Copilot** *(nuevo)* | — | bingbot + structured content + dateModified + Organization schema |

---

## Variables nuevas de salida

```bash
# Pilar 1 — Acceso
GEO_BOT_COPILOT          # true|false — bingbot permitido en robots.txt
GEO_META_NOAI            # true|false — meta noai/noimageai detectado
GEO_LLMS_FULL_TXT        # true|false — /llms-full.txt presente
GEO_LLMS_TXT_QUALITY     # "completo"|"parcial"|"vacio" — calidad del contenido de llms.txt
GEO_AI_PLUGIN            # true|false — /.well-known/ai-plugin.json presente

# Pilar 2 — Confianza
GEO_DATE_MODIFIED        # true|false — dateModified en schema o HTTP header
GEO_SCHEMA_ORG_COMPLETE  # true|false — Organization con url+logo+contactPoint
GEO_SCHEMA_ARTICLE_COMPLETE # true|false — Article con headline+author+datePublished
GEO_SCHEMA_FAQ_COMPLETE  # true|false — FAQPage con al menos una Question+acceptedAnswer

# Pilar 3 — Answer-readiness
GEO_QUESTION_HEADINGS    # int — H2/H3 con formato de pregunta
GEO_CITATION_PATTERNS    # int — frases con atribución/fuente detectadas
GEO_DEFINITION_PATTERNS  # int — frases definitionales detectadas

# Motor nuevo
GEO_ENGINE_COPILOT       # 0-100 — score específico para Bing/Copilot
```

---

## Priorización

| # | Ítem | Esfuerzo | Impacto | Requests nuevos |
|---|------|----------|---------|-----------------|
| 1 | Copilot/bingbot (1.1) | Bajo | Alto | 0 — ya descargamos robots.txt |
| 2 | Question headings (3.1) | Bajo | Alto | 0 — grep en HTML_CACHE |
| 3 | dateModified (2.1) | Bajo | Alto | 0 — grep en HTML_CACHE + SEO_LAST_MODIFIED |
| 4 | noai detection (1.2) | Bajo | Medio | 0 — grep en HTML_CACHE |
| 5 | Citation patterns (3.2) | Bajo | Medio | 0 — grep en HTML_CACHE |
| 6 | llms.txt quality (1.4) | Bajo | Medio | 0 — ya descargamos robots.txt, mismo patrón |
| 7 | JSON-LD completeness (2.2) | Medio | Alto | 0 — grep en HTML_CACHE |
| 8 | Definition sentences (3.3) | Bajo | Medio | 0 — grep en HTML_CACHE |
| 9 | ai-plugin.json (2.3) | Bajo | Medio | 1 HEAD request |
| 10 | llms-full.txt (1.3) | Bajo | Bajo | 1 HEAD request |

Los ítems 1–6 tienen costo de red cero (todo grep sobre variables ya en memoria) y cubren los dos gaps más críticos: el 5° motor (Copilot) y el pilar de answer-readiness.
