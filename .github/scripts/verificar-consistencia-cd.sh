#!/usr/bin/env bash
#
# Verifica que los tres workflows de CD sigan compartiendo las invariantes que
# SI deben ser iguales.
#
# Por que existe este script: se decidio mantener cd-frontend, cd-backend y
# cd-ml como archivos separados —se leen y se diagnostican de a uno, y es
# esperable que diverjan a medida que cada componente crezca—. La contrapartida
# de esa decision es que un arreglo se puede aplicar en dos de tres y nadie se
# entera. Ya paso: el smoke test del front detectaba el fallo y el del ml-service
# no, porque el arreglo no se propago.
#
# Esto NO exige que los tres archivos sean iguales. Solo comprueba que ninguno
# perdio una de las garantias del despliegue. Si una diferencia es deliberada,
# lo correcto es sacar la invariante de esta lista y dejar dicho por que.

set -uo pipefail

CD_FILES=(
	".github/workflows/cd-frontend.yml"
	".github/workflows/cd-backend.yml"
	".github/workflows/cd-ml.yml"
)

# patron<TAB>descripcion de la garantia que se perderia
INVARIANTES=(
	"^  esperar_ci:	el CD espera la conclusion del CI antes de desplegar"
	"needs: esperar_ci	el job de despliegue depende de esa compuerta"
	"needs.esperar_ci.result == 'skipped'	el rollback manual sigue siendo posible con la compuerta salteada"
	"^  actions: read	permiso para consultar el estado del CI"
	"cancel-in-progress: false	los despliegues se encolan en vez de cortarse a la mitad"
	"continue-on-error: true	un fallo de salud no aborta el job antes de poder revertir"
	"name: Revertir si fallo la verificacion|name: Revertir si falló la verificación	existe la reversion automatica"
	"name: Marcar el job como fallido	un despliegue revertido deja el workflow en rojo"
	"name: Determinar que version quedo en ejecucion|name: Determinar qué versión quedó en ejecución	el resumen informa lo que quedo corriendo y no lo que se intento"
	"State.Health.Status	la verificacion lee el healthcheck del contenedor"
	"tail -n \+	la limpieza descarta imagenes a partir de un limite"
	"CAPA1=	la verificacion esta dividida en capas con responsable distinto"
	"CAPA3=	existe la capa que comprueba el contrato propio del componente"
	"steps.salud.outputs.regresion == 'si'	la reversion se decide por regresion y no por el simple fallo del paso"
)

fallos=0

for f in "${CD_FILES[@]}"; do
	if [ ! -f "$f" ]; then
		echo "::error::No existe $f"
		fallos=$((fallos + 1))
		continue
	fi

	echo "· $f"
	for entrada in "${INVARIANTES[@]}"; do
		patron="${entrada%%$'\t'*}"
		descripcion="${entrada#*$'\t'}"

		if grep -qE "$patron" "$f"; then
			echo "    ok   $descripcion"
		else
			echo "::error file=$f::Falta una invariante del CD: $descripcion"
			echo "    FALTA  $descripcion"
			fallos=$((fallos + 1))
		fi
	done
done

# -------------------------------------------------------------------------
# Cuantas imagenes conserva la limpieza. La invariante es que los tres usen el
# MISMO limite, no un numero concreto: si el equipo decide conservar 10, debe
# poder hacerlo sin tocar este script — pero en los tres a la vez, porque si
# uno conserva menos que otro puede quedarse sin punto de retorno.
# -------------------------------------------------------------------------
echo "· limite de imagenes conservadas"
limites=()
for f in "${CD_FILES[@]}"; do
	[ -f "$f" ] || continue
	limite=$(grep -oE 'tail -n \+[0-9]+' "$f" | head -1 | grep -oE '[0-9]+$')
	echo "    $(basename "$f"): ${limite:-ninguno}"
	limites+=("${limite:-ninguno}")
done

distintos=$(printf '%s\n' "${limites[@]}" | sort -u | wc -l)
if [ "$distintos" -eq 1 ]; then
	echo "    ok   los tres conservan la misma cantidad"
else
	echo "::error::Los tres CD conservan cantidades distintas de imagenes: ${limites[*]}. El que conserve menos puede quedarse sin punto de retorno para revertir."
	echo "    FALTA  los tres conservan la misma cantidad"
	fallos=$((fallos + 1))
fi

# -------------------------------------------------------------------------
# Los nombres del `workflow_run` de verificacion-sistema.yml tienen que
# coincidir EXACTAMENTE con el `name:` de cada CD. GitHub los busca por texto:
# un nombre mal escrito no da error, simplemente no dispara nunca. Es un fallo
# silencioso, asi que se comprueba aca.
# -------------------------------------------------------------------------
VERIFICACION=".github/workflows/verificacion-sistema.yml"

if [ -f "$VERIFICACION" ]; then
	echo "· $VERIFICACION"
	linea_workflows=$(grep -E "^ *workflows: \[" "$VERIFICACION" || true)

	if [ -z "$linea_workflows" ]; then
		echo "::error file=$VERIFICACION::No se encontro la lista de workflows del disparador workflow_run"
		fallos=$((fallos + 1))
	else
		for f in "${CD_FILES[@]}"; do
			[ -f "$f" ] || continue
			nombre=$(grep -m1 '^name:' "$f" | sed 's/^name: *//')

			if printf '%s' "$linea_workflows" | grep -qF "$nombre"; then
				echo "    ok   se dispara tras \"$nombre\""
			else
				echo "::error file=$VERIFICACION::El workflow \"$nombre\" no figura en el disparador workflow_run: la verificacion no correra despues de ese despliegue."
				echo "    FALTA  se dispara tras \"$nombre\""
				fallos=$((fallos + 1))
			fi
		done
	fi
fi

echo
if [ "$fallos" -ne 0 ]; then
	echo "::error::$fallos invariante(s) ausente(s). Los tres CD divergieron en algo que deberia ser igual."
	echo "Si la diferencia es deliberada, quitar esa invariante de este script y explicar por que."
	exit 1
fi

echo "Los tres workflows de CD conservan todas las invariantes."
