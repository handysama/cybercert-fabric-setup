#!/bin/bash

# Output channel update config
kubectl hlf channel addorg \
    --name "${CHANNEL_ID}" \
    --config networkConfig.yaml \
    --user "${ORG1_ADMIN_USER}" \
    --peer "${ORG1_PEER0}" \
    --msp-id "${ORG2_MSP}" \
    --org-config configtx.yaml \
    --dry-run > "${ORG2_NAME}.json"
