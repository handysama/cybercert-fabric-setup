#!/bin/bash

set -o errexit

kubectl hlf channel join \
    --name "${CHANNEL_ID}" \
    --config "${ORG2_NAME}.yaml" \
    --user "${ORG2_ADMIN_USER}" \
    --peer "${ORG2_PEER0}"

kubectl hlf channel inspect \
    --channel "${CHANNEL_ID}" \
    --config "${ORG2_NAME}.yaml" \
    --user "${ORG2_ADMIN_USER}" \
    --peer "${ORG2_PEER0}" > "${CHANNEL_ID}.json"

kubectl hlf channel addanchorpeer \
    --channel "${CHANNEL_ID}" \
    --config "${ORG2_NAME}.yaml" \
    --user "${ORG2_ADMIN_USER}" \
    --peer "${ORG2_PEER0}"
