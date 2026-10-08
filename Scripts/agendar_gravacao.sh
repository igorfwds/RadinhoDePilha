#!/bin/bash
# Deixa a gravação da Sportmonks armada para começar sozinha.
#
# Espera até o horário informado, depois tenta iniciar a gravação a cada 30 segundos até a
# partida do Náutico aparecer como em andamento. Quando a partida termina, encerra.
# Mantém o Mac acordado durante todo o processo (a tela pode apagar e bloquear).
#
# Uso:
#     bash Scripts/agendar_gravacao.sh            # começa a tentar às 19:25 de hoje
#     bash Scripts/agendar_gravacao.sh 15:55      # começa a tentar às 15:55 de hoje
#
# Deixe o Mac na tomada e com a tampa aberta: fechar a tampa faz o Mac dormir mesmo assim.

set -u
set -o pipefail

INICIO="${1:-19:25}"
INTERVALO=30

# Desiste se a partida não aparecer neste tempo, para não ficar tentando a noite toda no caso
# de um adiamento.
LIMITE_DE_TENTATIVAS_SEGUNDOS=$((4 * 60 * 60))

RAIZ="$(cd "$(dirname "$0")/.." && pwd)"

# Reinicia a si mesmo sob o caffeinate, que impede o Mac de dormir enquanto o script roda.
if [ -z "${GRAVACAO_ACORDADA:-}" ]; then
    GRAVACAO_ACORDADA=1 exec caffeinate -is bash "$0" "$@"
fi

if ! [[ "$INICIO" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
    echo "Horário inválido: '$INICIO'. Use o formato HH:MM, por exemplo 19:25."
    exit 1
fi

ALVO=$(date -j -f "%Y-%m-%d %H:%M:%S" "$(date +%Y-%m-%d) $INICIO:00" +%s)

mkdir -p "$RAIZ/Gravacoes"
LOG="$RAIZ/Gravacoes/agendada-$(date +%Y%m%d-%H%M%S).log"

registrar() {
    echo "$(date '+%H:%M:%S')  $*" | tee -a "$LOG"
}

registrar "Gravação armada. Começa a tentar às $INICIO. Registro em $LOG"

# Confere o relógio a cada passo em vez de dormir de uma vez só: se o Mac cochilar no meio,
# um único sleep longo acordaria atrasado.
while [ "$(date +%s)" -lt "$ALVO" ]; do
    sleep 20
done

registrar "Horário atingido. Tentando a cada $INTERVALO segundos."

DESISTE_EM=$(( $(date +%s) + LIMITE_DE_TENTATIVAS_SEGUNDOS ))
TENTATIVA=0

cd "$RAIZ" || exit 1

while true; do
    TENTATIVA=$((TENTATIVA + 1))

    # -u: sem buffer, para cada linha aparecer na tela e no registro na hora.
    if python3 -u Scripts/gravar_partida_sportmonks.py 2>&1 | tee -a "$LOG"; then
        registrar "Gravação concluída."
        exit 0
    fi

    if [ "$(date +%s)" -ge "$DESISTE_EM" ]; then
        registrar "A partida não apareceu em 4 horas. Desistindo."
        exit 1
    fi

    registrar "Tentativa $TENTATIVA sem partida em andamento. Nova tentativa em $INTERVALO segundos."
    sleep "$INTERVALO"
done
