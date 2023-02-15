#!/bin/bash

kubectl hlf channel update \
    --channel "${CHANNEL_ID}" \
    -f "${ORG2_NAME}_update_in_envelope.pb" \
    --config networkConfig.yaml \
    --user "${ORG1_ADMIN_USER}" \
    --mspid "${ORG1_MSP}" \
    -s "${ORG1_NAME}-${CHANNEL_ID}-sign.pb" \
    -s "${ORG2_NAME}-${CHANNEL_ID}-sign.pb"
