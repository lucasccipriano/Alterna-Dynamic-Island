#!/bin/bash
# Coleta informações para investigar o comando de voz do Alterna.
cd "$(dirname "$0")"
mkdir -p diagnostico
rm -f diagnostico/*
ls -t ~/Library/Logs/DiagnosticReports/Alterna* 2>/dev/null | head -3 | while read f; do cp "$f" diagnostico/; done
log show --last 3h --style compact --predicate 'process == "Alterna" AND (subsystem CONTAINS[c] "speech" OR subsystem CONTAINS[c] "coreaudio" OR subsystem CONTAINS[c] "avfaudio" OR subsystem CONTAINS[c] "TCC" OR eventMessage CONTAINS[c] "speech" OR eventMessage CONTAINS[c] "recogni" OR eventMessage CONTAINS[c] "input")' 2>/dev/null | tail -600 > diagnostico/log-alterna.txt
log show --last 3h --style compact --predicate '(process CONTAINS[c] "speech" OR process == "corespeechd" OR process == "assistantd") AND eventMessage CONTAINS[c] "alterna"' 2>/dev/null | tail -300 > diagnostico/log-speech.txt
log show --last 3h --style compact --predicate 'process == "tccd" AND eventMessage CONTAINS[c] "alterna" AND (eventMessage CONTAINS[c] "Microphone" OR eventMessage CONTAINS[c] "SpeechRecognition" OR eventMessage CONTAINS[c] "AudioCapture" OR eventMessage CONTAINS[c] "auth_value")' 2>/dev/null | tail -200 > diagnostico/log-tcc.txt
defaults read app.alterna.Alterna 2>/dev/null | grep -iE "voice|wake" > diagnostico/ajustes.txt
system_profiler SPAudioDataType 2>/dev/null > diagnostico/audio.txt
sw_vers > diagnostico/macos.txt
echo ok > diagnostico/pronto.txt
