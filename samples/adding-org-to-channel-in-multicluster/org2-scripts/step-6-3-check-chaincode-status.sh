#!/bin/bash

kubectl hlf chaincode querycommitted \
    --peer "${ORG2_PEER0}" \
    --user "${ORG2_ADMIN_USER}" \
    --config "${ORG2_NAME}.yaml" \
    --channel "${CHANNEL_ID}" \
    --chaincode "${CC_NAME}"
