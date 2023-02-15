#!/bin/bash

set -o errexit

echo "=== Step 2 Start ==="

kubectl hlf ca register \
    --name "${ORG1_ORD_CA}" \
    --user "${ORG2_ADMIN_USER}" \
    --secret "${ORG2_ADMIN_SECRET}" \
    --type admin \
    --enroll-id enroll \
    --enroll-secret enrollpw \
    --namespace "${ORG1_NAMESPACE}" \
    --mspid "${ORG1_ORD_MSP}"

kubectl hlf ca enroll \
    --name "${ORG1_ORD_CA}" \
    --user "${ORG2_ADMIN_USER}" \
    --secret "${ORG2_ADMIN_SECRET}" \
    --namespace "${ORG1_NAMESPACE}" \
    --mspid "${ORG1_ORD_MSP}" \
    --ca-name ca \
    --output admin-ordservice.yaml

kubectl hlf utils adduser \
    --userPath admin-ordservice.yaml \
    --config ordservice.yaml \
    --username "${ORG2_ADMIN_USER}" \
    --mspid "${ORG1_ORD_MSP}"

sleep 10

kubectl hlf ca enroll \
    --name "${ORG1_ORD_CA}" \
    --user "${ORG2_ADMIN_USER}" \
    --secret "${ORG2_ADMIN_SECRET}" \
    --namespace "${ORG1_NAMESPACE}" \
    --mspid "${ORG1_ORD_MSP}" \
    --ca-name tlsca \
    --output admin-tls-ordservice.yaml

echo "=== Step 2 Finish ==="
