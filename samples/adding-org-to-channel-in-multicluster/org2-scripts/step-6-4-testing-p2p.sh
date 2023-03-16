#!/bin/bash

ISSUER_NAME=$1

kubectl hlf chaincode query \
    --config "${ORG2_NAME}.yaml" \
    --user "${ORG2_ADMIN_USER}" \
    --peer "${ORG2_PEER0}" \
    --channel "${CHANNEL_ID}" \
    --chaincode "${CC_NAME}" \
    --fcn=QueryRecords -a "{\"selector\":{\"issuer_name\":\"${ISSUER_NAME}\"},\"use_index\":[\"_design/indexIssuerNameDoc\",\"indexIssuerName\"]}"
