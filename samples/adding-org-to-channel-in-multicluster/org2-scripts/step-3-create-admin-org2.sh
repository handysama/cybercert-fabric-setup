#!/bin/bash

set -o errexit

echo "=== Step 3 Start ==="

kubectl hlf ca register \
    --name "${ORG2_CA}" \
    --user "${ORG2_ADMIN_USER}" \
    --secret "${ORG2_ADMIN_SECRET}" \
    --type admin \
    --enroll-id enroll \
    --enroll-secret enrollpw \
    --namespace "${ORG2_NAMESPACE}" \
    --mspid "${ORG2_MSP}"

kubectl hlf ca enroll \
    --ca-name ca \
    --name "${ORG2_CA}" \
    --user "${ORG2_ADMIN_USER}" \
    --secret "${ORG2_ADMIN_SECRET}" \
    --namespace "${ORG2_NAMESPACE}" \
    --mspid "${ORG2_MSP}" \
    --output "peer-${ORG2_NAME}.yaml"

kubectl hlf inspect --output "${ORG2_NAME}.yaml" -o "${ORG2_MSP}"

kubectl hlf utils adduser \
    --userPath "peer-${ORG2_NAME}.yaml" \
    --config "${ORG2_NAME}.yaml" \
    --username "${ORG2_ADMIN_USER}" \
    --mspid "${ORG2_MSP}"

sleep 10

echo "=== Step 3 Finish ==="
