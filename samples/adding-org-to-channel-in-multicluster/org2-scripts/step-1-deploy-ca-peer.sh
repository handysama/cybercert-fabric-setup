#!/bin/bash

set -o errexit

echo "=== Step 1 Start ==="

# Create CA
kubectl hlf ca create \
    --storage-class "${HLF_STORAGE_CLASSS}" \
    --capacity 2Gi \
    --namespace "${ORG2_NAMESPACE}" \
    --name "${ORG2_CA}" \
    --enroll-id enroll \
    --enroll-pw enrollpw

kubectl wait --timeout=180s --for=condition=Running fabriccas.hlf.kungfusoftware.es --all

# Register user for the peer
kubectl hlf ca register \
    --name "${ORG2_CA}" \
    --user peer \
    --secret peerpw \
    --type peer \
    --enroll-id enroll \
    --enroll-secret enrollpw \
    --mspid "${ORG2_MSP}" \
    --namespace "${ORG2_NAMESPACE}"

# Create Peer
kubectl hlf peer create \
    --statedb couchdb \
    --image "${PEER_IMAGE}" \
    --version "${PEER_VERSION}" \
    --storage-class "${HLF_STORAGE_CLASS}" \
    --capacity 5Gi \
    --enroll-id peer \
    --enroll-pw peerpw \
    --mspid "${ORG2_MSP}" \
    --namespace "${ORG2_NAMESPACE}" \
    --name "${ORG2_NAME}-peer0" \
    --ca-name "${ORG2_CA}.${ORG2_NAMESPACE}"

kubectl wait --timeout=180s --for=condition=Running fabricpeers.hlf.kungfusoftware.es --all

echo "=== Step 1 Finish ==="
