#!/bin/bash
# Duplo clique: exporta símbolos, cursores, papel de parede e geometria do notch para tools/video-assets.
cd "$(dirname "$0")"
swift export-assets.swift video-assets > export.log 2>&1
echo "EXIT: $?" >> export.log
tail -n 3 export.log
