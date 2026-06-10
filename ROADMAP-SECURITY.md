# Roadmap de Seguridad — homium-audit

Mejoras identificadas para las dimensiones `seguridad` y `ciberseguridad`. Cada ítem documenta el estado actual (lo que se detecta hoy y por qué es insuficiente) y el valor que aporta implementarlo.

---

## Grupo 1 — Calidad de headers, no solo presencia

### 1.1 CSP — análisis de efectividad real

**Estado actual — problema:**
El script detecta si el header `Content-Security-Policy` existe y si contiene `unsafe-inline` o `unsafe-eval`. Nada más. Un sitio con `Content-Security-Policy: default-src *` recibe puntos positivos aunque esa política sea equivalente a no tener nada — permite cargar recursos de cualquier origen. Un sitio con `script-src 'nonce-abc123' 'unsafe-inline'` también pasa porque el script no sabe que `unsafe-inline` anula el nonce por completo.

**Con la mejora:**
- Detectar `default-src *` o `script-src *` como política inútil (peor que ausente — da falsa seguridad).
- Detectar `unsafe-inline` junto a `nonce-` (se anulan mutuamente — el nonce pierde efecto).
- Detectar `data:` en `img-src` o `script-src` (vector de XSS).
- Detectar ausencia de `frame-ancestors` (equivalente a no tener X-Frame-Options).
- Score diferenciado: CSP presente pero inefectiva = −10 pts, CSP ausente = −20 pts.

**Impacto:** Distingue sitios que tienen seguridad real de los que tienen una ilusión de seguridad. Hoy ambos salen igual.

---

### 1.2 HSTS — max-age mínimo y directivas de preload

**Estado actual — problema:**
El script detecta si HSTS existe y extrae el `max-age`, pero no lo evalúa. Un `max-age=60` (60 segundos) recibe el mismo puntaje que `max-age=31536000` (1 año). 60 segundos le da a un atacante MITM una ventana de ataque en cada nueva conexión — prácticamente inútil.

**Con la mejora:**
- `max-age < 86400` (1 día): flag como insuficiente, −15 pts.
- `max-age < 31536000` (1 año): advertencia, no entra a listas de preload HSTS.
- Ausencia de `includeSubDomains`: los subdominios siguen siendo vulnerables a downgrade.
- Ausencia de `preload`: el sitio no puede registrarse en el HSTS preload list del browser.
- Severidad diferenciada en el reporte: HSTS presente pero inefectivo ≠ HSTS correcto.

**Impacto:** Un cliente con `max-age=60` hoy sale con check verde en HSTS. Con esta mejora sale con advertencia naranja y una explicación de por qué 60 segundos no protege a sus usuarios en redes WiFi públicas.

---

### 1.3 Headers de aislamiento de origen (COEP / COOP / CORP)

**Estado actual — problema:**
No se detectan. Son los tres headers que mitigan ataques Spectre/Meltdown en browser y habilitan `SharedArrayBuffer` de forma segura. Ausentes en la mayoría de sitios, pero críticos en cualquier SaaS o app con datos sensibles.

**Con la mejora:**
- Detectar `Cross-Origin-Embedder-Policy`, `Cross-Origin-Opener-Policy`, `Cross-Origin-Resource-Policy`.
- No penalizar en score (son headers avanzados, su ausencia es normal en sitios institucionales).
- Mostrar como hallazgo informativo para SaaS o apps con login: "tu app es vulnerable a ataques de canal lateral entre pestañas del browser".
- Penalizar solo en sector `saas` con −5 pts cada uno.

**Impacto:** Diferenciación real entre auditorías de sitios estáticos y SaaS — un dato que hoy el reporte no distingue.

---

## Grupo 2 — Cookies con granularidad real

### 2.1 Análisis por cookie, no global

**Estado actual — problema:**
El script verifica si *alguna* cookie tiene `Secure` y *alguna* tiene `HttpOnly`. En la práctica esto siempre pasa: las cookies de analytics (que no importan) tienen esos flags; la cookie de sesión (que sí importa) puede no tenerlos. El resultado es un falso positivo — el check pasa aunque la cookie crítica esté expuesta.

**Con la mejora:**
- Parsear cada `Set-Cookie` header por separado.
- Identificar cookies de sesión por nombre (`PHPSESSID`, `session`, `auth`, `token`, `jwt`, `_session`, `connect.sid`).
- Reportar qué cookies específicas no tienen `Secure`, `HttpOnly` o `SameSite`.
- Severidad alta si la cookie de sesión carece de cualquiera de los tres flags.

**Impacto:** Elimina el falso positivo más frecuente en auditorías de cookies. Hoy casi todos los sitios pasan este check aunque tengan la sesión expuesta.

---

### 2.2 SameSite — protección CSRF

**Estado actual — problema:**
No se detecta. `SameSite` es la defensa primaria contra CSRF (Cross-Site Request Forgery) desde 2020. Sin `SameSite=Strict` o `SameSite=Lax`, cualquier sitio malicioso puede hacer requests autenticados en nombre del usuario con solo embeber una imagen o formulario. Es especialmente crítico en sitios con formularios de compra, transferencia o cambio de datos.

**Con la mejora:**
- Detectar ausencia de `SameSite` en cookies de sesión: hallazgo de severidad alta.
- Detectar `SameSite=None` sin `Secure`: inválido en browsers modernos y una brecha.
- Distinguir `Lax` (protección básica) de `Strict` (protección completa).

**Impacto:** CSRF es el vector más subestimado en sitios con formularios. Hoy no aparece en el reporte.

---

### 2.3 Cookie expiry — gestión de sesión

**Estado actual — problema:**
No se analiza. Cookies de sesión con `Expires` en fecha lejana (años) son sesiones que nunca expiran — si el token es robado, el atacante tiene acceso indefinido.

**Con la mejora:**
- Flag si una cookie de sesión tiene `Expires` > 30 días en el futuro.
- Hallazgo informativo: "la sesión del usuario nunca expira — un token robado da acceso indefinido".

**Impacto:** Pequeño de implementar, alto de comunicar — es el tipo de dato que un cliente de e-commerce entiende inmediatamente.

---

## Grupo 3 — TLS/SSL en profundidad

### 3.1 Versión TLS activa

**Estado actual — problema:**
Solo se verifica la vigencia del certificado. No se verifica qué versiones de TLS acepta el servidor. TLS 1.0 y TLS 1.1 están oficialmente deprecadas (RFC 8996, marzo 2021) y tienen vulnerabilidades conocidas (POODLE, BEAST). Muchos servidores mal configurados aún las aceptan por compatibilidad con clientes antiguos.

**Con la mejora:**
- Usar `openssl s_client -tls1` y `openssl s_client -tls1_1` para detectar si el servidor los acepta.
- Fallback: si openssl no está disponible, marcar como "no verificable" — no penalizar.
- TLS 1.0 activo: hallazgo crítico, −20 pts.
- TLS 1.1 activo: hallazgo alto, −10 pts.
- Solo TLS 1.2+: correcto.

**Impacto:** Un servidor con TLS 1.0 activo hoy sale con SSL verde (el cert es válido). Con esta mejora sale con hallazgo crítico y la razón concreta.

---

### 3.2 Cipher suites débiles

**Estado actual — problema:**
No se verifica. RC4, 3DES (SWEET32) y cipher suites de exportación (EXPORT) son vulnerables y están deprecados. Pueden seguir activos en servidores con configuración antigua.

**Con la mejora:**
- `openssl s_client -cipher RC4` / `3DES`: flag si el servidor los acepta.
- Hallazgo alto con explicación del ataque específico (SWEET32 para 3DES).
- Solo si openssl está disponible — sin penalizar si no lo está.

**Impacto:** Complementa el análisis TLS — versión correcta pero cipher suite débil es un gap real que hoy no se detecta.

---

### 3.3 OCSP Stapling

**Estado actual — problema:**
No se verifica. Sin OCSP Stapling, el browser del usuario hace una request separada a la CA para verificar si el certificado fue revocado. Esa request expone qué sitio está visitando el usuario (privacidad) y agrega latencia. Además, si la CA está caída, el browser puede mostrar un error o simplemente no verificar (soft-fail).

**Con la mejora:**
- `openssl s_client -status` para verificar si el servidor incluye la respuesta OCSP en el handshake.
- Hallazgo informativo (no penaliza score) pero visible en el reporte.

**Impacto:** Dato de alta calidad técnica que diferencia el reporte para audiencias devops/sysadmin.

---

## Grupo 4 — Email: calidad de políticas, no solo presencia

### 4.1 DMARC policy real

**Estado actual — problema:**
El script detecta si el registro DMARC existe, pero no evalúa su política. `v=DMARC1; p=none` es un registro válido que solo *reporta* — no bloquea ni pone en cuarentena ningún email fraudulento. Hoy un sitio con `p=none` recibe el mismo puntaje que uno con `p=reject`. Es el error de auditoría de email más frecuente.

**Con la mejora:**
- `p=none`: hallazgo medio — "DMARC en modo observación, el dominio puede ser suplantado para phishing".
- `p=quarantine`: correcto pero no óptimo.
- `p=reject`: óptimo.
- Penalización diferenciada: ausente = −10 pts, `p=none` = −7 pts, `p=quarantine` = −3 pts, `p=reject` = 0 pts.

**Impacto:** Hoy muchos dominios tienen DMARC pero con `p=none` — siguen siendo suplantables para phishing. El reporte los trata como seguros. Es un falso positivo con consecuencias reales para los clientes.

---

### 4.2 SPF `+all` — política que permite todo

**Estado actual — problema:**
El script detecta si SPF existe, pero no si tiene `+all` al final. Un SPF que termina en `+all` significa "cualquier servidor del mundo puede enviar emails como este dominio" — es exactamente lo opuesto a lo que SPF debe hacer. Técnicamente tiene SPF; funcionalmente no tiene ninguna protección.

**Con la mejora:**
- Detectar `+all` en el registro SPF: hallazgo crítico, −15 pts.
- Detectar `?all` (neutral): hallazgo medio, −5 pts.
- Solo `~all` (softfail) o `-all` (hardfail) son aceptables.

**Impacto:** Un dominio con `v=spf1 +all` hoy sale con check verde en SPF. Es una brecha crítica de suplantación de identidad que el reporte actual no detecta.

---

### 4.3 MTA-STS — forzar TLS en tránsito de email

**Estado actual — problema:**
No se verifica. MTA-STS es el protocolo que instruye a los servidores de email entrante a usar STARTTLS obligatorio al comunicarse con el dominio. Sin él, un atacante con acceso a la red puede hacer downgrade del email a texto plano (STARTTLS stripping) e interceptarlo en tránsito.

**Con la mejora:**
- Verificar `https://mta-sts.{domain}/.well-known/mta-sts.txt` (un HTTP HEAD es suficiente).
- Hallazgo informativo para dominios con MX configurado: "el correo entrante puede ser interceptado en tránsito".
- Penalización leve: −5 pts si hay MX y no hay MTA-STS.

**Impacto:** Dato de seguridad de email que prácticamente ninguna herramienta de auditoría web detecta — diferenciador de calidad del reporte.

---

## Grupo 5 — Información expuesta con mayor precisión

### 5.1 `.git` — verificar el archivo, no solo el directorio

**Estado actual — problema:**
El script hace HTTP a `/.git` y verifica si devuelve 200. Muchos servidores configuran el directorio como 403 (forbidden) pero dejan los archivos individuales accesibles. `.git/HEAD` es el primer archivo que verifican las herramientas de extracción de repositorios — si responde con `ref: refs/heads/main`, el repositorio completo es extraíble.

**Con la mejora:**
- Verificar `/.git/HEAD` con fetch del contenido, no solo status code.
- Si responde con `ref: refs/heads/` o `HEAD`: hallazgo crítico — el código fuente es público.
- Verificar también `/.git/config` (expone URLs de remote, nombres de usuario).

**Impacto:** Cambia de "directorio listable" a "código fuente expuesto" — un hallazgo mucho más grave y específico.

---

### 5.2 Archivos de backup y configuración olvidados

**Estado actual — problema:**
Se verifican 10 rutas fijas. No se verifican patrones de backup que son muy comunes: archivos generados por editores (`wp-config.php~`, `index.php.bak`), exports de base de datos (`database.sql`, `backup.sql.gz`), archives del proyecto (`site.zip`, `public.tar.gz`), y archivos de configuración de frameworks (`database.yml`, `.env.production`, `.env.local`).

**Con la mejora:**
- Ampliar la lista de rutas verificadas a ~25 patrones de backup comunes.
- Incluir variantes del nombre de dominio: `{domain}.zip`, `{domain}.sql`.
- Prioridad alta para archivos que contienen credenciales (`.env.*`, `database.yml`, `wp-config.php.bak`).

**Impacto:** Aumenta la superficie de detección. Los backups olvidados son uno de los vectores de breach más frecuentes en sitios WordPress y PHP.

---

### 5.3 Error pages — information disclosure

**Estado actual — problema:**
No se analiza. Muchos frameworks exponen stack traces, rutas absolutas del sistema, versiones de dependencias y nombres de variables en sus páginas de error. Esta información es valiosa para un atacante en la fase de reconocimiento.

**Con la mejora:**
- Hacer una request a una ruta aleatoria inexistente (`/{uuid}`) y analizar la respuesta.
- Detectar: stack traces (`at Function.`, `Traceback (most recent call last)`), rutas absolutas (`/var/www/`, `/home/`), versiones de framework en el body.
- Hallazgo alto si se detecta información técnica en el error.

**Impacto:** Identifica sitios en modo debug en producción — un error de configuración frecuente con alto valor informativo para el atacante.

---

### 5.4 GraphQL introspection expuesta

**Estado actual — problema:**
Se verifica `/swagger` y `/api-docs` por status 200. No se verifica GraphQL. Si un sitio tiene GraphQL con introspection habilitada en producción, cualquier persona puede consultar el schema completo de la API: todos los tipos, campos, queries y mutations. Es el equivalente a publicar la documentación privada de la API.

**Con la mejora:**
- Request POST a `/graphql` con `{"query":"{__schema{types{name}}}"}`.
- Si la respuesta incluye `__schema` con contenido: hallazgo alto.
- Verificar también rutas alternativas: `/api/graphql`, `/v1/graphql`.

**Impacto:** Brecha que afecta específicamente a apps modernas (Next.js, SaaS) — el tipo de sitio que más usa la herramienta.

---

## Grupo 6 — Supply chain JavaScript

### 6.1 Scripts externos sin SRI

**Estado actual — problema:**
El script detecta si *hay algún* atributo `integrity="sha..."` en el HTML. No cuenta cuántos scripts externos *no lo tienen*. Un sitio con 8 scripts de terceros y SRI en uno de ellos sale igual que un sitio con SRI en todos. Los scripts de terceros sin SRI son el vector principal de supply chain attacks web (Magecart, Polyfill.io incident 2024).

**Con la mejora:**
- Contar scripts externos (`src` con dominio distinto al del sitio).
- Contar cuántos tienen `integrity` vs cuántos no.
- Mostrar lista de dominios de scripts sin SRI: Google, Cloudflare, CDNs de terceros.
- Penalización proporcional: más del 50% sin SRI = −10 pts.

**Impacto:** Después del incidente de Polyfill.io (junio 2024, 100k+ sitios comprometidos), este es un dato de alta relevancia para clientes con e-commerce.

---

### 6.2 Bibliotecas JavaScript con CVEs conocidos

**Estado actual — problema:**
No se verifica. El script detecta qué frameworks usa el sitio (Bootstrap, jQuery, etc.) pero no si las versiones detectadas tienen vulnerabilidades conocidas. jQuery 1.x tiene XSS documentados; Bootstrap < 4.6.2 tiene XSS; lodash < 4.17.21 tiene prototype pollution.

**Con la mejora:**
- Extraer versiones de las URLs de scripts: `jquery-3.4.1.min.js`, `bootstrap@4.5.2`.
- Cruzar contra una lista estática embebida en el script (sin API externa) de bibliotecas/versiones vulnerables.
- Hallazgo alto si hay versión con CVE crítico o alto conocido.
- Lista inicial: jQuery < 3.5.0, Bootstrap < 4.6.2, Lodash < 4.17.21, moment.js (deprecated), Angular < 1.8.3.

**Impacto:** Sin dependencia de API externa — cero latencia, cero costo. Una lista estática de 20 entradas cubre el 80% de los casos reales.

---

## Grupo 7 — Integración con Claude API

Estos ítems no son detecciones nuevas sino un layer de interpretación sobre los datos ya recolectados. Requieren una llamada a la API de Claude al final del análisis.

### 7.1 Análisis de CSP con lenguaje natural

**Estado actual — problema:**
La interpretación de un CSP complejo requiere conocimiento especializado. Un header como `script-src 'self' 'unsafe-inline' https://cdn.example.com; object-src 'none'` tiene implicaciones que no son obvias ni para desarrolladores experimentados.

**Con la mejora:**
- Enviar el CSP completo a Claude con el contexto del tipo de sitio.
- Claude devuelve: (a) qué está permitido en lenguaje claro, (b) qué directivas son problemáticas y por qué, (c) una versión mejorada del header.
- El resultado enriquece el bloque CSP del reporte con una explicación de una línea y el header corregido como snippet.

---

### 7.2 Correlación CVE contextual por stack

**Estado actual — problema:**
Detectar "WordPress 6.1 + WooCommerce" no dice nada por sí solo. El valor está en saber si esa combinación específica tiene vulnerabilidades conocidas y si son explotables desde afuera.

**Con la mejora:**
- Enviar el stack detectado (CMS, versión, plugins identificados) a Claude.
- Claude devuelve CVEs relevantes con severidad CVSS, vector de ataque y si son explotables sin autenticación.
- Aparece como bloque "Vulnerabilidades conocidas del stack" en el reporte.

---

### 7.3 Narrativa de riesgo de negocio por hallazgo crítico

**Estado actual — problema:**
Los hallazgos críticos hoy dicen "HSTS ausente" con una recomendación técnica. No dicen qué le pasa concretamente a un usuario del sitio si no se corrige.

**Con la mejora:**
- Para cada hallazgo crítico, Claude genera una consecuencia en lenguaje de negocio: "Sin HSTS, un usuario que se conecta desde una red WiFi pública puede ser redirigido a una versión falsa de tu sitio y sus credenciales ser capturadas — sin que el browser muestre ninguna advertencia."
- Aparece como campo `business_impact` en el JSON y en el reporte bajo cada hallazgo crítico.

---

## Priorización

| # | Ítem | Esfuerzo | Impacto | Falsos positivos que corrige |
|---|------|----------|---------|------------------------------|
| 1 | DMARC policy real (4.1) | Bajo | Alto | Sí — `p=none` pasa hoy |
| 2 | SPF `+all` (4.2) | Bajo | Alto | Sí — `+all` pasa hoy |
| 3 | Cookies SameSite + por cookie (2.1, 2.2) | Medio | Alto | Sí — analytics ocultan sesión insegura |
| 4 | CSP calidad (1.1) | Medio | Alto | Sí — `default-src *` pasa hoy |
| 5 | HSTS max-age (1.2) | Bajo | Medio | Sí — `max-age=60` pasa hoy |
| 6 | `.git/HEAD` (5.1) | Bajo | Alto | No — mejora precisión |
| 7 | Scripts sin SRI (6.1) | Medio | Medio | No — dato nuevo |
| 8 | TLS version (3.1) | Medio | Alto | No — dato nuevo |
| 9 | Error pages (5.3) | Bajo | Medio | No — dato nuevo |
| 10 | GraphQL introspection (5.4) | Bajo | Medio | No — dato nuevo |
| 11 | Claude API — DMARC/CVE/narrativa (7.x) | Alto | Alto | No — capa de interpretación |
| 12 | Cipher suites (3.2) | Medio | Medio | No — dato nuevo |
| 13 | HSTS preload/includeSubDomains (1.2) | Bajo | Medio | No — dato nuevo |
| 14 | MTA-STS (4.3) | Bajo | Medio | No — dato nuevo |
| 15 | CVEs en bibliotecas JS (6.2) | Alto | Alto | No — dato nuevo |
| 16 | COEP/COOP/CORP (1.3) | Bajo | Medio | No — solo SaaS |
| 17 | OCSP Stapling (3.3) | Bajo | Bajo | No — informativo |
| 18 | Backup files (5.2) | Bajo | Medio | No — amplía superficie |
| 19 | Cookie expiry (2.3) | Bajo | Bajo | No — informativo |

Los ítems 1–5 son los de mayor ROI: esfuerzo bajo-medio, corrigen falsos positivos activos y cubren los vectores de ataque más frecuentes en los sitios que audita Homium.
