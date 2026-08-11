# 🔄 CI/CD — Cómo funciona y cómo leerlo

## 📌 Resumen

El repositorio tiene **cinco workflows**: uno de integración continua, tres de
despliegue —uno por componente— y uno de verificación del sistema completo.

| Workflow | Cuándo corre | Qué garantiza |
|---|---|---|
| `ci.yml` | Push y Pull Request a `main` y `develop` | El código compila, los tests pasan y los workflows son válidos |
| `cd-frontend.yml` · `cd-backend.yml` · `cd-ml.yml` | Push a `main` o `develop` que toque **ese** componente | Ese componente quedó desplegado y funcionando |
| `verificacion-sistema.yml` | Cada 30 min, tras cualquier despliegue, y a mano | El sistema completo funciona de punta a punta |

---

## 🧭 El principio que ordena todo: cada quien responde por lo suyo

**Cada CD verifica únicamente el contrato del componente que despliega.** No
verifica que el sistema entero funcione, y es a propósito.

Si el CD del backend exigiera un análisis completo, un backend perfectamente
sano quedaría bloqueado porque falta el modelo del ml-service. Eso atribuiría el
fallo al equipo equivocado, rompería la independencia entre componentes y
dispararía una reversión que no arregla nada.

La verificación cruzada existe, pero vive en `verificacion-sistema.yml`, que
**no controla el despliegue de nadie**.

---

## 🩺 Las tres capas de verificación

Cada CD verifica en tres capas. La distinción importa porque **cada capa implica
un responsable distinto**.

| Capa | Qué prueba | Si falla |
|---|---|---|
| **1 · Contenedor** | Arrancó y su `HEALTHCHECK` no lo marcó `unhealthy` | Regresión → **revierte** |
| **2 · Proceso** | Responde por el puerto publicado | Regresión → **revierte** |
| **3 · Contrato** | Hace aquello para lo que existe | Depende del componente |

Se comprueban **las dos cosas** —el `HEALTHCHECK` que declara el contenedor y una
petición real contra el puerto— porque fallan por motivos distintos: un
contenedor puede declararse sano y no ser alcanzable desde afuera, y al revés.

**Qué es la capa 3 en cada componente:**

- **Front-end** — `/version.json` informa **exactamente el SHA que se acaba de
  desplegar**. Ver la sección siguiente.
- **Backend** — un payload con rangos inválidos devuelve 400 con `detalles[]`.
  Ese camino se rechaza en Bean Validation **antes** de llamar al ml-service, así
  que verifica el contrato completo del backend sin depender de nadie.
- **ml-service** — una predicción real devuelve 200. Hace falta pedir una
  predicción de verdad porque `/health` devuelve un literal fijo que no mira el
  modelo.

### `/version.json`: por qué el front no se verifica raspando el HTML

El contenedor del front sirve un archivo con su propia identidad:

```json
{"servicio":"frontend","version":"<SHA del commit>"}
```

Se genera **en el build de la imagen** a partir del argumento `VERSION`, que el
CD rellena con el SHA que está desplegando. Como el valor viaja dentro de la
imagen, en un rollback —donde la imagen se reutiliza sin reconstruir— describe
correctamente la versión restaurada.

**Por qué no alcanza con mirar el HTML.** Se evaluaron dos alternativas y las dos
fallan en lo mismo:

| Alternativa | Por qué se descartó |
|---|---|
| Buscar el patrón del bundle (`/assets/index-*.js`) | Ata la verificación a Vite. Daría por roto el despliegue de cualquier versión anterior — el prototipo estático, por ejemplo — que está perfectamente sana. |
| Buscar el `<title>` de la aplicación | Ata la verificación a un texto visible al usuario, que puede cambiar por motivos de redacción y romper el despliegue sin que nada esté mal. |

**Y el problema de fondo lo tienen las dos: dan verde si el contenedor anterior
sigue en pie y responde** — que es justamente el fallo que un despliegue tiene
que detectar. Ninguna de las dos distingue «la versión nueva está sirviendo» de
«sigue sirviendo la vieja».

Comparar la versión informada contra el SHA publicado responde la pregunta
correcta: *¿está sirviendo esto?*

> El backend y el ml-service no tienen todavía un equivalente. Para el backend,
> el lugar natural sería `/actuator/info` con la información de build; para el
> ml-service, sumar la versión del modelo a su respuesta de salud. Va como
> propuesta a cada equipo.

### Por qué el ml-service no revierte cuando falla su capa 3

El modelo **no viaja en la imagen**: se descarga de Object Storage al arrancar.
Verificado el 11/08 sobre las cuatro imágenes presentes en la VM: ninguna lo
contiene.

Entonces, si el servicio no puede predecir, revertir aterriza en una versión
igual de rota, ensucia qué versión está desplegada y no arregla nada. El job
queda **en rojo igual** —esa es la señal que corresponde— pero sin reversión.

---

## 🚦 Cómo leer un CD en rojo

El resumen del run trae las tres capas por separado. Se lee de arriba hacia
abajo y la **primera** que falla dice de quién es el problema:

| Falla | Significa | Quién lo resuelve |
|---|---|---|
| Capa 1 | El contenedor no levanta o se marca `unhealthy` | Quien hizo el último cambio del componente |
| Capa 2 | Levanta pero no responde | Ídem — suele ser un fallo de arranque; ver los logs del paso |
| Capa 3 del front o del backend | El componente arrancó pero no cumple su contrato | Ídem |
| **Capa 3 del ml-service** | **Casi siempre: falta el modelo en Object Storage** | Data Science / quien publica el modelo |

> ⚠️ **Un CD permanentemente rojo deja de mirarse.** Por eso las capas se
> reportan separadas: hay que poder distinguir «falla la capa 3 del ml-service,
> bloqueo externo conocido» de «falla la capa 1, esto es nuevo y es nuestro».

---

## 📦 Publicar un modelo nuevo: **hace falta reiniciar el ml-service**

**Este es el paso que se olvida.**

`ensure_artifacts()` se ejecuta **únicamente en el arranque** del ml-service, y
la inferencia lee el modelo del disco local. Publicar el modelo en Object Storage
**no surte efecto por sí solo**: el servicio en ejecución no vuelve a mirar el
bucket, y como el modelo no está en el repositorio, publicarlo tampoco dispara
ningún CD.

Sin este paso, el síntoma es engañoso: el modelo está publicado, todo «parece»
bien y el sistema sigue devolviendo 503 — que se lee como que la publicación
falló.

**Después de publicar un modelo:**

1. Ir a **Actions → `CD Data Science / ML (FastAPI)` → Run workflow**.
2. Elegir el ambiente y dejar el campo `tag` vacío.
3. El despliegue reinicia el contenedor, `ensure_artifacts()` descarga el modelo
   y la capa 3 pasa a verde.

> 💡 El arreglo de fondo sería que el ml-service reintente traer el modelo en vez
> de resolverlo una sola vez al arrancar, y que `/health` refleje si hay modelo
> disponible. Está propuesto a Data Science; mientras tanto, el paso manual.

---

## ⛔ Por qué el CD espera al CI

El CD y el CI se disparan con el mismo evento `push`. Sin una compuerta arrancan
en paralelo y un commit con los tests en rojo se despliega igual, porque el
deploy no espera el veredicto. Cada CD tiene un job `esperar_ci` que consulta la
conclusión del CI para ese commit antes de desplegar.

**No se usa `on: workflow_run`** —que sería lo aparentemente natural— porque ese
disparador ignora el filtro `paths` (todos los componentes se desplegarían ante
cualquier cambio), resuelve `github.ref` y `github.sha` contra la rama por
defecto en lugar del commit que lo originó, y solo ejecuta la versión del archivo
que está en la rama por defecto.

**La compuerta se saltea en `workflow_dispatch`**: en un rollback se despliega un
SHA que ya estuvo en ejecución, y volver a exigirle el CI impediría revertir justo
cuando más se necesita.

> ⚠️ **Acoplamiento a no romper.** La compuerta espera a que exista un run del CI
> para el commit. Por eso `ci.yml` **no** filtra por `paths` a nivel de workflow:
> filtra por job. Si alguien mueve ese filtro al disparador, habrá cambios que
> disparen un CD sin disparar el CI, y la compuerta esperará quince minutos a algo
> que nunca va a ocurrir.

---

## 🔁 Rollback

La versión desplegada es el tag de la imagen, y el tag es el **SHA del commit**.
Volver atrás no reconstruye nada: relevanta una imagen que ya existe en la VM, o
sea exactamente el mismo binario que ya corrió.

- **Automático** — si fallan las capas 1 o 2, el propio job restaura la versión
  anterior.
- **Manual** — Actions → el CD correspondiente → *Run workflow* → indicar el SHA
  en el campo `tag`.

La limpieza conserva las **5 imágenes más recientes** por componente y nunca
borra una que tenga un contenedor asociado, aunque esté detenido: eso protege el
punto de retorno del otro ambiente.

---

## 🧪 Verificación del sistema y disponibilidad

`verificacion-sistema.yml` corre cada 30 minutos, después de cualquier
despliegue y a mano, **contra los dos ambientes**. Comprueba tres cosas en orden
—el front-end se sirve, la API responde, el análisis completo funciona— y el
resumen dice dónde se corta la cadena.

**Su criterio para el front es más laxo que el del CD, a propósito.** Este
workflow no sabe qué versión *debería* estar corriendo: exigir una concreta
daría por caído un ambiente que sirve una versión anterior perfectamente sana.
El CD sí lo sabe —acaba de publicarla— y por eso es él quien compara contra el
SHA esperado. Acá la versión se **informa**, y ese dato hace evidente de un
vistazo que un ambiente quedó atrás respecto del otro.

**Termina en rojo cuando algo falla**, a propósito: el correo de GitHub ante un
workflow programado fallido es el único canal de aviso que hoy existe. Los
dominios estuvieron devolviendo 502 desde el 27/07 hasta el 09/08 y nadie se
enteró, porque nada los miraba.

> ⚠️ El cron de GitHub puede retrasarse varios minutos y se desactiva solo si el
> repositorio queda 60 días sin actividad. Sirve para enterarse el mismo día, no
> para medir un SLA.

### La marca de las peticiones sintéticas

La verificación envía la cabecera `X-EnergiAI-Sonda` para que el backend pueda
distinguir sus peticiones de un análisis real y no registrarlas ni contarlas en
los datos agregados. Hoy no hay persistencia, así que es preventivo — pero
conviene resolverlo antes de que haya datos que ensuciar.

**Dos restricciones de diseño, no negociables:**

1. **Tiene que ser un secreto compartido, no una cabecera booleana.** Un
   `X-Sonda: true` lo manda cualquiera desde internet y obtiene el mismo trato.
   El valor vive en los *secrets* del repositorio y en el `.env` de la VM, y el
   backend debe compararlo con comparación de tiempo constante y no registrarlo
   nunca en sus logs.
2. **Solo puede controlar persistencia y telemetría.** Nunca autorización, nunca
   límites de uso, nunca validación. Si algún día decidiera el límite de
   consultas (PA-07), dejaría de ser una marca y pasaría a ser una llave para
   saltear restricciones: el daño de que se filtre subiría de «se contaron mal
   unos análisis» a «alguien evade el límite».

---

## 🧱 Por qué los tres CD son archivos separados

Comparten cerca del 90 % del contenido y aun así **no** se unificaron en un
*reusable workflow*. La decisión fue deliberada: separados se leen, diagnostican
y modifican de a uno, y es esperable que diverjan a medida que cada componente
crezca — el backend ya necesita más tiempo de arranque que el front, y el ML
tiene una política de reversión distinta.

**La contrapartida está cubierta**: `.github/scripts/verificar-consistencia-cd.sh`
comprueba que los tres conserven las garantías que sí deben ser iguales, y corre
en el CI. No exige que sean idénticos; detecta que ninguno haya perdido una
garantía. Ya pasó una vez: el smoke test del front detectaba el fallo y el del
ml-service no, porque el arreglo no se propagó.

Si una diferencia es deliberada, lo correcto es quitar esa invariante del script
y dejar dicho por qué.

---

## 📄 Configuración fuera del código

Las reglas de protección de ramas y las protecciones de seguridad del repositorio
**no viven en ningún archivo versionado**. Su estado y su justificación están en
[`docs/github-config.md`](../github-config.md).
