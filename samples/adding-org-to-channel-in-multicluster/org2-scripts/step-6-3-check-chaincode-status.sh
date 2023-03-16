#!/bin/bash

kubectl hlf chaincode querycommitted \
    --config "${ORG2_NAME}.yaml" \
    --user "${ORG2_ADMIN_USER}" \
    --peer "${ORG2_PEER0}" \
    --channel "${CHANNEL_ID}" \
    --chaincode "${CC_NAME}"
