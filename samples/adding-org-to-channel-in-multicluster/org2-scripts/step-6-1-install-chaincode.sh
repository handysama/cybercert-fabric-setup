#!/bin/bash

set -o errexit

echo "=== Installing chaincode: ${CC_NAME}. This will takes few minutes. ==="

kubectl hlf chaincode install \
    --path "./fixtures/chaincodes/${CC_NAME}" \
    --config "${ORG2_NAME}.yaml" \
    --language golang \
    --label "${CC_NAME}" \
    --user "${ORG2_ADMIN_USER}" \
    --peer "${ORG2_PEER0}"

kubectl hlf chaincode queryinstalled \
    --config "${ORG2_NAME}.yaml" \
    --user "${ORG2_ADMIN_USER}" \
    --peer "${ORG2_PEER0}"

PACKAGE_ID=`kubectl hlf chaincode queryinstalled --config=${ORG2_NAME}.yaml --user=${ORG2_ADMIN_USER} --peer=${ORG2_PEER0} | awk -v cc_name="${CC_NAME}" '{ if ($2 == cc_name) print $1 }'`
echo "${PACKAGE_ID}"

kubectl hlf chaincode approveformyorg \
    --config "${ORG2_NAME}.yaml" \
    --user "${ORG2_ADMIN_USER}" \
    --peer "${ORG2_PEER0}" \
    --package-id "${PACKAGE_ID}" \
    --name "${CC_NAME}" \
    --version "${CC_VERSION}" \
    --sequence "${CC_SEQUENCE}" \
    --policy "OR('${ORG1_MSP}.member')" \
    --channel "${CHANNEL_ID}"

echo "=== Please notify Admin Org1 of CC_NAME and PACKAGE_ID ==="
