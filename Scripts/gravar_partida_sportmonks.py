#!/usr/bin/env python3
"""Grava as respostas brutas da Sportmonks durante uma partida.

Serve para guardar o que o fornecedor entregou minuto a minuto, de modo que a partida possa
ser reproduzida e analisada depois que a assinatura de teste for cancelada.

Uso:
    python3 Scripts/gravar_partida_sportmonks.py            # procura o Náutico ao vivo na Série B
    python3 Scripts/gravar_partida_sportmonks.py 19722782   # grava uma partida pelo id

O token é lido de Config/Secrets.xcconfig (SPORTMONKS_TOKEN). Cada consulta vira um arquivo
em Gravacoes/sportmonks-<id>/, e a gravação para sozinha quando a partida termina.
"""

import json
import re
import sys
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
BASE = "https://api.sportmonks.com/v3/football"
LIGA_SERIE_B = 651
INTERVALO_SEGUNDOS = 30

# Mais do que o app pede: comentários, escalações e estatísticas também interessam à análise.
# `lineups.details` traz os totais por jogador (faltas cometidas e sofridas, impedimentos…).
# Comparando uma gravação com a seguinte, dá para ver em que momento cada total subiu.
INCLUDES = (
    "participants;scores;periods;events;comments;state;"
    "statistics.type;lineups.details.type"
)

# FT, AET, FT_PEN, POSTPONED, CANCELLED, WO, ABANDONED, AWARDED, DELETED.
ESTADOS_ENCERRADOS = {5, 7, 8, 10, 12, 14, 15, 17, 20}


def ler_token():
    secrets = (RAIZ / "Config" / "Secrets.xcconfig").read_text(encoding="utf-8")
    achado = re.search(r"^SPORTMONKS_TOKEN\s*=\s*(\S+)", secrets, re.MULTILINE)
    if not achado:
        sys.exit("SPORTMONKS_TOKEN não está preenchido em Config/Secrets.xcconfig.")
    return achado.group(1)


def consultar(token, caminho, **parametros):
    url = f"{BASE}/{caminho}?{urllib.parse.urlencode(parametros, safe=';:')}"
    pedido = urllib.request.Request(url, headers={"Authorization": token})
    with urllib.request.urlopen(pedido, timeout=20) as resposta:
        return json.loads(resposta.read())


def sem_acento(texto):
    decomposto = unicodedata.normalize("NFD", texto.lower())
    return "".join(c for c in decomposto if unicodedata.category(c) != "Mn")


def procurar_nautico_ao_vivo(token):
    resposta = consultar(
        token,
        "livescores/inplay",
        include="participants",
        filters=f"fixtureLeagues:{LIGA_SERIE_B}",
    )
    for partida in resposta.get("data") or []:
        if "nautico" in sem_acento(partida.get("name", "")):
            return partida["id"]
    return None


def main():
    token = ler_token()

    if len(sys.argv) > 1:
        partida_id = sys.argv[1]
    else:
        partida_id = procurar_nautico_ao_vivo(token)
        if partida_id is None:
            sys.exit("Nenhuma partida do Náutico em andamento na Série B agora.")

    pasta = RAIZ / "Gravacoes" / f"sportmonks-{partida_id}"
    pasta.mkdir(parents=True, exist_ok=True)
    print(f"Gravando a partida {partida_id} em {pasta}")

    while True:
        agora = datetime.now()
        try:
            resposta = consultar(token, f"fixtures/{partida_id}", include=INCLUDES)
        except (urllib.error.URLError, TimeoutError) as erro:
            print(f"{agora:%H:%M:%S}  falha na consulta: {erro}")
            time.sleep(INTERVALO_SEGUNDOS)
            continue

        arquivo = pasta / f"{agora:%Y%m%d-%H%M%S}.json"
        arquivo.write_text(json.dumps(resposta, ensure_ascii=False, indent=2), encoding="utf-8")

        partida = resposta.get("data")
        if partida is None:
            sys.exit(f"A Sportmonks não devolveu a partida: {resposta.get('message')}")

        estado = (partida.get("state") or {}).get("name", "?")
        eventos = len(partida.get("events") or [])
        comentarios = len(partida.get("comments") or [])
        print(f"{agora:%H:%M:%S}  {estado}  {eventos} eventos  {comentarios} comentários")

        if partida.get("state_id") in ESTADOS_ENCERRADOS:
            print("Partida encerrada. Gravação concluída.")
            return

        time.sleep(INTERVALO_SEGUNDOS)


if __name__ == "__main__":
    main()
