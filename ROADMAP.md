# Roadmap — homium-audit

Lista unificada de pendientes. Consolida ROADMAP-GEO, ROADMAP-SECURITY + hallazgos del code review v1.7.1 + items de vibeauditt.

**Leyenda prioridad:** 🔴 Falso positivo activo · 🟠 Dato nuevo de alto valor · 🟡 Mejora de calidad · ⚪ Informativo  
**Leyenda platform:** ✅ Solo script — no tocar audit-platform · 🔗 Requiere cambios en audit-platform también

---

## 🐛 BUGS DETECTADOS EN AUDITORÍA REAL (aluzian.com, v1.8.0)

Encontrados al comparar el MD generado contra los datos reales del JSON. Todos en `generate_report()`.

| # | Bug | Línea aprox | Fix |
|---|-----|-------------|-----|
| B-R1 | Conclusión dice "Sin redirección HTTP→HTTPS" aunque `SEC_HTTPS_REDIRECT=true` | ~L608 narrative | Agregar condicional `[[ "$SEC_HTTPS_REDIRECT" == true ]]` antes de incluir esa frase |
| B-R2 | Conclusión menciona "X-Frame-Options" como faltante aunque está presente | ~L608 narrative | El texto de brechas de seguridad debe iterar sobre los headers realmente ausentes, no hardcodear |
| B-R3 | Conclusión dice "Sin DMARC y DKIM" aunque DKIM está presente | ~L610 narrative | Verificar `$CYBER_DKIM != "AUSENTE"` antes de incluir DKIM en la lista de brechas |
| B-R4 | Conclusión menciona "/llms.txt ausente" aunque `GEO_LLMS_TXT=true` | ~L609 narrative | Agregar condicional `[[ "$GEO_LLMS_TXT" == false ]]` en el texto GEO del narrative |
| B-R5 | Matriz de Priorización solo genera 3 filas — la Hoja de Ruta tiene 12 acciones | generate_report | Revisar si la matriz usa la misma fuente que la Hoja de Ruta o se genera por separado |

---

## 🚀 EMPEZAR AQUÍ — Solo script, sin tocar audit-platform

Todos estos se implementan **solo en `homium-audit.sh`**. El JSON sigue siendo compatible con la plataforma actual.

| # | Ítem | Por qué no toca platform | Prioridad |
|---|------|--------------------------|-----------|
| U1 | **DMARC `p=none` pasa como seguro** | Mejora score; `ciberseguridad.dmarc` string ya existe | 🔴 |
| U2 | **SPF `+all` pasa como seguro** | Mejora score; `ciberseguridad.spf` string ya existe | 🔴 |
| U3 | **HSTS `max-age` no evaluado** — `max-age=60` = verde | `SEC_HSTS_MAXAGE` ya en JSON; solo usar el valor | 🔴 |
| U4 | **Cookies: análisis global** — analytics ocultan sesión expuesta | Mismo campo `seguridad.cookies.*`, mejor detección | 🔴 |
| U5 | **GEO_SITE_TYPE: Next.js → siempre `saas`** | `geo.site_type` ya en JSON; fix en detección | 🔴 |
| U6 | **CTX_GEO contradictorio** — prefix positivo + issues negativos | `geo.context` ya en JSON; fix en texto generado | 🔴 |
| U7 | **PERF_SIZE_KB = HTML, no peso de página** | Cambiar label en MD solo; no renombrar campo JSON | 🔴 |
| A2 | **`.git/HEAD` content check** — 403 no protege archivos | Añadir `/.git/HEAD` a `exposed_paths` existente | 🟠 |
| A9 | **Score performance: heurístico mezclado con LH** | Solo cambia cálculo; `scores.performance` mismo campo | 🟠 |
| M1 | **Error pages** — stack traces en producción | Añadir a `exposed_paths` existente | 🟡 |
| M2 | **GraphQL introspection** expuesta | Añadir a `exposed_paths` existente | 🟡 |
| M6 | **Backup files ampliado** (~25 patrones) | Expande array `exposed_paths` existente | 🟡 |
| M12 | **UX/Diseño score base 70 → 100** | Solo cambia score; mismos campos | 🟡 |
| M13 | **Legal: mejorar detección** — keyword → link real | Mejora booleans existentes `legal.*` | 🟡 |
| N3 | **Endpoints API sin auth ampliado** — `/api/users`, `/api/admin`, `/graphql` | Expande `exposed_paths` existente | 🟠 |
| N4 | **Detección de vibe coding** — Lovable, Bolt, v0, Framer, Webflow + correlación de riesgos típicos | Campo nuevo en `tecnologia.generator`; sin impacto en platform hasta que lo consuma | 🟡 |

---

## 🔗 REQUIERE AUDIT-PLATFORM — Implementar en paralelo o después

Estos agregan **nuevos campos al JSON** que la plataforma necesita mostrar. Algunos pueden escribirse en el script ahora y el JSON los llevará silenciosamente hasta que la plataforma los consuma.

### Seguridad / Ciberseguridad

| # | Ítem | Campo JSON nuevo | Prioridad |
|---|------|-----------------|-----------|
| A1 | **CSP calidad real** — wildcard, nonce+unsafe bypass | `seguridad.headers.csp_wildcards`, `csp_nonce_bypass` | 🟠 |
| A3 | **TLS 1.0/1.1 activo** | `seguridad.tls_old_version` (bool) | 🟠 |
| A4 | **Cookies SameSite** — CSRF | `seguridad.cookies.samesite` | 🟠 |
| M3 | **Scripts sin SRI — ratio real** | `seguridad.sri_count`, `seguridad.sri_missing_count` | 🟡 |
| M4 | **HSTS includeSubDomains + preload** | `seguridad.headers.hsts_preload`, `hsts_subdomains` | 🟡 |
| M5 | **MTA-STS** | `ciberseguridad.mta_sts` (bool) | 🟡 |
| N1 | **CORS mal configurado** — `*` + credentials | `ciberseguridad.cors_unsafe` (bool) | 🟠 Crítico |
| N2 | **API keys en JS bundles** — Stripe, OpenAI, JWT, Supabase | `ciberseguridad.api_keys_exposed` (array de patrones) | 🟠 Crítico |
| B1 | **Cookie expiry** — sesiones que no expiran | `seguridad.cookies.session_never_expires` | ⚪ |
| B2 | **OCSP Stapling** | `seguridad.ocsp_stapling` | ⚪ |
| B3 | **COEP/COOP/CORP** — solo SaaS | `seguridad.isolation_headers.*` | ⚪ |
| B5 | **Cipher suites débiles** (RC4, 3DES) | `seguridad.weak_ciphers` | ⚪ |

### GEO v2

> ⚠️ **M9 (llms.txt quality)**: `geo.acceso.llms_txt` es boolean — la plataforma hace `llms_txt ? 'Presente' : 'Ausente'`. Cambiar a string **rompe** la plataforma. Agregar campo nuevo `llms_txt_quality` y mantener el boolean.

| # | Ítem | Campo JSON nuevo | Prioridad |
|---|------|-----------------|-----------|
| A5 | **Copilot/bingbot — 5° motor** | `geo.acceso.copilot`, `geo.engines.copilot` | 🟠 |
| A6 | **Question headings** — H2/H3 como preguntas | `geo.contenido.question_headings` (int) | 🟠 |
| A7 | **dateModified** — frescura real del contenido | `geo.confianza.fecha_modificacion` (bool) | 🟠 |
| A8 | **JSON-LD completeness** — schema con campos vacíos | `geo.confianza.org_schema_complete`, `article_schema_complete`, `faq_schema_complete` | 🟠 |
| M7 | **noai/noimageai detection** | `geo.acceso.meta_noai` (bool) | 🟡 |
| M8 | **Citation patterns** | `geo.contenido.citation_patterns` (int) | 🟡 |
| M9 | **llms.txt quality** ⚠️ | `geo.acceso.llms_txt_quality` (string, nuevo campo) | 🟡 |
| M10 | **Definition sentences** | `geo.contenido.definition_patterns` (int) | 🟡 |
| M11 | **ai-plugin.json** | `geo.acceso.ai_plugin` (bool) | 🟡 |
| B4 | **llms-full.txt** | `geo.acceso.llms_full_txt` (bool) | ⚪ |

---

## 🔬 ALTO ESFUERZO — Evaluar cuando el producto madure

| # | Ítem | Por qué esperar |
|---|------|----------------|
| E1 | **CVEs en bibliotecas JS** | Lista de CVEs a mantener; alto esfuerzo de curation |
| E2 | **Claude API integration** — narrativa de riesgo, CSP en lenguaje natural, CVE contextual | Costo por auditoría; requiere decisión de producto |
| E3 | **Unlighthouse multi-página** | Cambio arquitectural; ver nota en memoria del proyecto |

---

## Estado de versiones

| Versión | Estado | Contenido |
|---------|--------|-----------|
| v1.7.1  | ✅ Producción | Base estable |
| v1.8.0  | 🔜 Próxima | **Solo script**: U1–U7, A2, A9, M6, M12, N3 |
| v1.9.0  | Planificado | **Script + platform**: N1, N2, A1, A3–A5, A6–A8 |
| v2.0.0  | Futuro | GEO v2 completo (M7–M11) + E1–E3 |
