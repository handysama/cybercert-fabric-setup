#!/bin/bash

set -o errexit

# Output (shared) network configuration of Org1 and Org2
kubectl hlf inspect --output networkConfig.yaml -o "${ORG1_MSP}" -o "${ORG1_ORD_MSP}"

# Backup original config
cp networkConfig.yaml networkConfig.bak.yaml

yq --yaml-output -s '.[0] * {"organizations":{"'${ORG1_ORD_MSP}'":{"users": .[1].organizations.'${ORG1_ORD_MSP}'.users }}}' \
    networkConfig.yaml ordservice.yaml > networkConfig-out1.yaml

yq --yaml-output -s '.[0] * {"organizations":{"'${ORG1_MSP}'":{"users": .[1].organizations.'${ORG1_MSP}'.users }}}' \
    networkConfig-out1.yaml "${ORG1_NAME}.yaml" > networkConfig-out2.yaml

yq --yaml-output -s '.[0] * {"organizations":{"'${ORG2_MSP}'":{"users": .[1].organizations.'${ORG2_MSP}'.users, "cryptoPath": .[1].organizations.'${ORG2_MSP}'.cryptoPath }}}' \
    networkConfig-out2.yaml "${ORG2_NAME}.yaml" > networkConfig-out3.yaml

# Override network config
mv networkConfig-out3.yaml networkConfig.yaml
