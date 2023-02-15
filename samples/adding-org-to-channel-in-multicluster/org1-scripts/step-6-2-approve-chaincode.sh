#!/bin/bash

echo "=== Step 6.2 Start ==="

kubectl hlf chaincode approveformyorg \
    --config "${ORG1_NAME}.yaml" \
    --user "${ORG1_ADMIN_USER}" \
    --peer "${ORG1_PEER0}" \
    --package-id "${PACKAGE_ID}" \
    --name "${CC_NAME}" \
    --version "${CC_VERSION}" \
    --sequence "${CC_SEQUENCE}" \
    --policy "OR('${ORG1_MSP}.member')" \
    --channel "${CHANNEL_ID}"

# Wait few seconds here before commit
sleep 10

kubectl hlf chaincode commit \
    --config "${ORG1_NAME}.yaml" \
    --user "${ORG1_ADMIN_USER}" \
    --mspid "${ORG1_MSP}" \
    --name "${CC_NAME}" \
    --version "${CC_VERSION}" \
    --sequence "${CC_SEQUENCE}" \
    --policy "OR('${ORG1_MSP}.member')" \
    --channel "${CHANNEL_ID}"

echo "=== Step 6.2 Finish ==="
