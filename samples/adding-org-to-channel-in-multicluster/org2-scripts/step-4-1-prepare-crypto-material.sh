#!/bin/bash

echo "=== Generating crypto material ==="

kubectl hlf org inspect --output-path crypto-config -o "${ORG2_MSP}"

echo "=== Please send 'org2.yaml', 'configtx.yaml', and all files in 'crypto-config' (keep structure) to Org1 ==="
