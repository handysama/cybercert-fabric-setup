#!/bin/bash

kubectl hlf channel signupdate \
    --channel "${CHANNEL_ID}" \
    -f "${ORG2_NAME}_update_in_envelope.pb" \
    --user "${ORG1_ADMIN_USER}" \
    --config networkConfig.yaml \
    --mspid "${ORG1_MSP}" \
    --output "${ORG1_NAME}-${CHANNEL_ID}-sign.pb"
