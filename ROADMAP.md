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

---

## 🔜 PENDIENTES

### 🟠 Alta — GEO v2 restante (solo script, bajo esfuerzo, 0 requests)

| # | Ítem | Campo JSON | Plataforma |
|---|------|-----------|-----------|
| M7 | **noai/noimageai detection** — `<meta name="robots" content="noai">` bloquea IA | `geo.acceso.meta_noai` | 🔗 |
| M8 | **Citation patterns** — "según", "fuente:", "according to" en contenido | `geo.contenido.citation_patterns` | 🔗 |
| M9 | **llms.txt quality** — calidad real del contenido (completo/parcial/vacío) ⚠️ campo nuevo, no cambiar tipo boolean | `geo.acceso.llms_txt_quality` | 🔗 |
| M10 | **Definition sentences** — "X es Y", "X se define como" | `geo.contenido.definition_patterns` | 🔗 |
| M11 | **ai-plugin.json** — `/.well-known/ai-plugin.json` → +10pts ChatGPT | `geo.acceso.ai_plugin` | 🔗 |

### 🟡 Media — Seguridad complementaria

| # | Ítem | Campo JSON | Plataforma |
|---|------|-----------|-----------|
| M3 | **Scripts sin SRI — ratio real** — hoy es solo boolean | `seguridad.sri_count`, `sri_missing_count` | 🔗 |
| M4 | **HSTS includeSubDomains + preload** | `seguridad.headers.hsts_preload`, `hsts_subdomains` | 🔗 |
| M5 | **MTA-STS** — TLS forzado en email entrante | `ciberseguridad.mta_sts` | 🔗 |

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

| # | Ítem | Descripción |
|---|------|-------------|
| P1 | **Página de error** | Cuando un token no existe o la auditoría falla al cargar, mostrar página de error con diseño consistente en lugar del JSON crudo `{"error":"Auditoría no encontrada"}` |

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
| v1.10.0 | 🔜 Próxima | GEO v2 restante: M7–M11 (noai, citation patterns, llms.txt quality, definition sentences, ai-plugin) |
| v1.11.0 | Planificado | Seguridad media: M3–M5 (SRI ratio, HSTS flags, MTA-STS) |
| v2.0.0 | Futuro | E1–E3 alto esfuerzo |
