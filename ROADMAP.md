# Roadmap — homium-audit

**Leyenda prioridad:** 🔴 Urgente · 🟠 Alto valor · 🟡 Mejora de calidad · ⚪ Informativo  
**Leyenda platform:** ✅ Solo script · 🔗 Script + audit-platform

---

## ✅ COMPLETADO

| Versión | Ítem |
|---------|------|
| v1.8.0 | U1–U7: 7 falsos positivos (DMARC policy, SPF +all, HSTS max-age, cookies por sesión, GEO site type, CTX_GEO, PERF label) |
| v1.8.0 | A2: .git/HEAD content check · A9: Performance score LH 60%+heurístico 40% |
| v1.8.0 | M1+M2: Error pages + GraphQL introspection · M6: Backup files ×25 |
| v1.8.0 | M12: UX/Diseño score base 100 · M13: Legal link real · N3: Endpoints API ampliados |
| v1.8.0 | N4: Vibe coding detection (Webflow, Framer, Lovable, Bolt, Astro) |
| v1.8.1 | B-R1–B-R5: Bugs narrative (brechas dinámicas, GEO/email sin contradicciones, matriz completa) |
| v1.9.0 | N1: CORS unsafe · N2: API keys en JS bundles |
| v1.9.0 | A1: CSP calidad (wildcard/nonce-bypass) · A3: TLS 1.0/1.1 · A4: SameSite cookies |
| v1.9.0 | A5: Copilot/bingbot 5° motor · A6: Question headings · A7: dateModified · A8: JSON-LD completeness |
| v1.9.0 | Platform: DMARC/SPF policy, GraphQL, error disclosure, CORS, API keys, Copilot engine, vibe coding |
| v1.10.0 | GEO v2 restante — M7–M11: noai, citation patterns, llms.txt quality, definition sentences, ai-plugin.json |
| v1.11.0 | Seguridad media — M3–M5: SRI ratio real, HSTS includeSubDomains+preload, MTA-STS |
| v2.0.0 | Screenshots de alta calidad (Chrome headless) · instalador Linux reforzado (NodeSource, guardia anti-sudo, rc file) |

---

## 🔜 PENDIENTES

### ⚪ Baja — Informativo

| # | Ítem | Campo JSON |
|---|------|-----------|
| B1 | Cookie expiry — sesiones que no expiran | `seguridad.cookies.session_never_expires` |
| B2 | OCSP Stapling | `seguridad.ocsp_stapling` |
| B3 | COEP/COOP/CORP — solo sector saas | `seguridad.isolation_headers.*` |
| B4 | llms-full.txt | `geo.acceso.llms_full_txt` |
| B5 | Cipher suites débiles (RC4, 3DES) | `seguridad.weak_ciphers` |

---

## 🔗 PLATFORM — Mejoras de UX en audit-platform

| # | Ítem | Descripción | Estado |
|---|------|-------------|--------|
| P1 | **Página de error** | Página 404/500 con diseño Homium en lugar de JSON crudo | ✅ Hecho |
| P2 | **Claridad de datos — badge de impacto** | Badge `Riesgo activo` (un solo color fijo) en cada fila del DETAIL con flag `crit`/`warn`. Se probó también un esquema de 3 badges (Riesgo activo/Oportunidad/Informativo) pero se descartó — "Oportunidad" repetido en casi todas las filas `ok` generaba ruido visual sin aportar. El resto de filas mantiene el punto de color de siempre. | ✅ Hecho (2026-07-14) |
| P3 | **Claridad de datos — separar accionables vs contexto** | Cada card del DETAIL separa "Requiere atención" (flags crit/warn, siempre visible) de "Datos de contexto" (`<details>` colapsado). Si no hay riesgos, muestra `✓ Sin hallazgos que requieran atención`. | ✅ Hecho (2026-07-14) |
| P4 | **Claridad de datos — consecuencia en lenguaje de negocio** | Debajo de cada fila de riesgo, una línea en lenguaje de negocio (ej. "Sin HSTS — un visitante en WiFi pública puede ser interceptado sin saberlo"). Mapa `DT_CONSEQUENCE` en `report.js`, ~60 hallazgos cubiertos (más de los ~20 estimados). | ✅ Hecho (2026-07-14) |

---

## 🔬 ALTO ESFUERZO — Evaluar cuando el producto madure

| # | Ítem | Por qué esperar |
|---|------|----------------|
| E1 | **CVEs en bibliotecas JS** | Lista a mantener; alto esfuerzo de curation |
| E2 | **Claude API integration** — narrativa de riesgo, CSP en lenguaje natural, CVE contextual | Costo por auditoría; requiere decisión de producto |
| E3 | **Unlighthouse multi-página** — schema consistency cross-page | Cambio arquitectural |

---

## Estado de versiones

| Versión | Estado | Contenido |
|---------|--------|-----------|
| v1.8.1 | ✅ Producción | 16 fixes solo script + bugs narrative |
| v1.9.0 | ✅ Producción | CORS, API keys, CSP/TLS/SameSite, GEO v2 (Copilot, dateModified, question headings, JSON-LD) |
| v1.10.0 | ✅ Producción | GEO v2 restante: M7–M11 (noai, citation patterns, llms.txt quality, definition sentences, ai-plugin) |
| v1.11.0 | ✅ Producción | Seguridad media: M3–M5 (SRI ratio, HSTS flags, MTA-STS) |
| v2.0.0 | ✅ Producción | Screenshots de alta calidad + instalador Linux reforzado (NodeSource, guardia anti-sudo) |
| v3.0.0 | Futuro | E1–E3 alto esfuerzo (ver sección anterior) |
