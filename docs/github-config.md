# ⚙️ Gobernanza de Git, Protección de Ramas y CI/CD – EnergiAI

Este documento registra la arquitectura de ramas, las **reglas de protección de ramas activas en GitHub** y la configuración del pipeline de **Integración Continua (CI)** del repositorio **G9-LATAM-TEAM-09**.

---

## 🔀 1. Arquitectura de Ramas (GitFlow Simplificado)

El repositorio sigue un modelo de desarrollo colaborativo estructurado en tres niveles:

| Rama | Propósito | Reglas de Acceso |
|------|-----------|------------------|
| `main` | Rama de Producción y entregables estables probados. | **Protegida**. Solo recibe merges vía Pull Request aprobados desde `develop`. |
| `develop` | Rama principal de integración y desarrollo activo. | **Protegida**. Recibe merges vía Pull Request desde ramas `feature/*`. |
| `feature/*` | Ramas individuales para nuevas características, correcciones o documentación. | Libres para los desarrolladores. Nacen de `develop` y se integran mediante PR. |

---

## 🛡️ 2. Reglas de Protección de Ramas (Configuradas mediante GitHub Rulesets)

En la sección **Settings > Rules > Rulesets** del repositorio en GitHub, se encuentra activo el Ruleset oficial del proyecto:

### 🟢 Ruleset: `Proteger Main` (Estado: Active)
- **Ramas Objetivo (*Target Branches*)**: Aplica a **`main`** y **`develop`**.
- **Reglas Configuradas**:
  - ✅ **Require a pull request before merging**: Exige que todos los cambios se envíen mediante Pull Request (Requiere mínimo **1 aprobación** de revisión).
  - ✅ **Restrict deletions**: Impide la eliminación de las ramas objetivo.
  - ✅ **Block force pushes**: Impide reescribir el historial de las ramas objetivo.
  - ✅ **Bypass List**: Vacía (ningún usuario puede saltarse las reglas de integración).
  - ❌ **Require status checks to pass before merging**: **no está configurada.** Es una decisión deliberada del equipo: el CI informa, no bloquea el merge.

> ⚠️ **Consecuencia de esa decisión, y por qué importa saberla.** Un Pull Request se puede mergear con el CI en rojo; la única barrera real es la aprobación humana. Por eso el CI tiene que ser **confiable** —un check en verde que no significa nada es peor que no tenerlo— y por eso la verificación de despliegue del CD pasa a ser la última línea de defensa automática. Si algún día se decide activarla, hay que hacerlo junto con el filtrado por job del CI: un job salteado a nivel de workflow deja el Pull Request pendiente para siempre.

---

## 🔐 3. Protecciones de GitHub disponibles y **no activadas**

Estas tres protecciones **no viven en el código**: se activan desde **Settings > Code security** del repositorio y no dejan rastro en ningún archivo versionado. Se documentan acá justamente por eso — para que su estado sea visible y su activación una decisión registrada del equipo, no algo que alguien prende un día sin avisar.

**Estado al 11/08/2026: las tres desactivadas.** El repositorio es público, así que las tres son gratuitas.

| Protección | Qué hace | Costo / riesgo de activarla |
|---|---|---|
| **Secret scanning** | Escanea el repositorio buscando formatos conocidos de credenciales (claves de nube, tokens, claves privadas) y genera una alerta si encuentra alguna. | Ninguno. Solo notifica. |
| **Push protection** | **Bloquea el push** que contiene una credencial, antes de que entre al historial. | Puede rechazar un push por un falso positivo. Se puede saltear justificando el motivo, y la justificación queda registrada. |
| **Dependabot alerts** | Avisa cuando una dependencia declarada tiene una vulnerabilidad conocida. | Ninguno. Solo notifica. |

**Tres precisiones antes de activarlas:**

1. **`Dependabot alerts` no es `Dependabot version updates`.** El primero solo avisa; el segundo abre Pull Requests automáticos de actualización. Se recomienda activar únicamente el primero: las actualizaciones automáticas llenarían el repositorio de PRs en plena hackathon.
2. **`Push protection` no borra el pasado.** Solo frena pushes nuevos. Si ya hubiera una credencial en el historial, activarla no la saca: habría que rotarla y reescribir el historial. **Verificado el 11/08: el historial está limpio** — las únicas coincidencias son marcadores de ejemplo (`<token>`, líneas comentadas) en documentación y archivos `.env.example`. Los `.env` reales están en `.gitignore` y viven solo en la VM.
3. **La más valiosa de las tres, para este proyecto, es `Push protection`.** El `OCI_PAR_URL` lleva el token embebido en la propia URL y da acceso al Object Storage. Si alguien lo commitea por accidente en un repositorio público, rotarlo después no borra el commit — y el token queda expuesto en el historial de forma permanente.

**Cómo activarlas** (requiere permiso de administrador): *Settings > Code security > Secret protection*, y *Settings > Code security > Dependabot alerts*.

---

## 🚀 4. Integración Continua (CI Workflow)

El repositorio cuenta con un pipeline de **GitHub Actions** automatizado definido en [`.github/workflows/ci.yml`](../.github/workflows/ci.yml).

### Disparadores (*Triggers*)
- Se ejecuta automáticamente ante cada **Push** o **Pull Request** hacia las ramas `main` y `develop`.
- **Sin filtro `paths` a nivel de workflow, a propósito**: los CD esperan la conclusión del CI para su commit, así que el run tiene que existir siempre. El filtrado se hace **por job**.

### Trabajos (*Jobs*)
1. **`cambios`**: compara contra la base y determina qué áreas tocó el cambio. Ante cualquier duda asume que cambió todo.
2. **`workflows-ci`**: valida los workflows con `actionlint` (que incluye `shellcheck` sobre cada `run:`) y verifica que los tres CD conserven sus invariantes. Corre siempre.
3. **`backend-ci` (Spring Boot & Java 17)**: JDK 17 Temurin con caché de Maven; ejecuta `./mvnw -B verify` (compilación, tests y empaquetado).
4. **`data-science-ci` (FastAPI)**: instala dependencias, valida la consistencia del esquema de la API contra el modelo, ejecuta `pytest`, construye la imagen y la arranca para comprobar que responde servida.
5. **`frontend-ci` (Vite + React)**: `npm ci`, verificación de tipos, construcción de la imagen y arranque del contenedor para comprobar que sirve la aplicación y que el *fallback* del router funciona.
6. **`docker-ci`**: ejecuta `docker compose config` para validar sintaxis, variables y contextos, y construye la imagen del backend — la única que ningún otro job construye.

### Despliegue continuo

Los tres workflows de CD y el de verificación del sistema están documentados en detalle en [`docs/cicd/`](./cicd/README.md): las tres capas de verificación, la política de reversión, cómo leer un CD en rojo y el paso manual tras publicar un modelo nuevo.

---

## ⚖️ 5. Licencia del Proyecto

El proyecto está licenciado bajo la **Licencia MIT**.
- **Archivo de Licencia**: [`LICENSE`](../LICENSE) en la raíz del repositorio.
- **Declaración en Maven**: Etiqueta `<licenses>` configurada en [`pom.xml`](../backend/analisis-energetico-api/pom.xml).

---

## 🔄 6. Protocolo de Sincronización entre `develop` y `main`

Para mantener la consistencia y sincronización entre `develop` y `main` respetando la protección activa:

1. Finalizada la iteración/semana, se verifica que todos los PRs de `feature/*` estén integrados en `develop` y con la suite de CI aprobada.
2. Se abre un **Pull Request en GitHub**: `base: main` ⬅️ `compare: develop`.
3. El responsable revisa los cambios y verifica el paso del pipeline de CI.
4. Se autoriza el merge (*Create a merge commit* o *Rebase and merge*).
5. Ambas ramas quedan alineadas y en estado verde.
