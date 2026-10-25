#!/bin/bash
# Duplo clique: compila, instala e abre o Alterna. O resultado fica em build.log.
cd "$(dirname "$0")"
echo "Compilando o Alterna… (o resultado vai para build.log)"
bash build.sh > build.log 2>&1
STATUS=$?
echo "EXIT: $STATUS" >> build.log
tail -n 5 build.log
