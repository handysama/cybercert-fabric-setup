#!/bin/bash

echo "=== Signing channel update ==="

kubectl hlf channel signupdate \
    --channel "${CHANNEL_ID}" \
    -f "${ORG2_NAME}_update_in_envelope.pb" \
    --user "${ORG2_ADMIN_USER}" \
    --config "${ORG2_NAME}.yaml" \
    --mspid "${ORG2_MSP}" \
    --output "${ORG2_NAME}-${CHANNEL_ID}-sign.pb"

echo "=== Please send 'org2-ecertplatform-sign.pb' to Org1 ==="
