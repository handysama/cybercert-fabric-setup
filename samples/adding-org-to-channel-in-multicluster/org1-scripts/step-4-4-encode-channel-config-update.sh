#!/bin/bash

set -o errexit

# Output org2_update_in_envelope.pb
echo '{"payload":{"header":{"channel_header":{"channel_id":"'${CHANNEL_ID}'","type":2}},"data":{"config_update":'$(cat ${ORG2_NAME}.json)'}}}' | jq . > "${ORG2_NAME}_update_in_envelope.json"

configtxlator proto_encode --type common.Envelope --input "${ORG2_NAME}_update_in_envelope.json" --output "${ORG2_NAME}_update_in_envelope.pb"

# Update org2.yaml with orderer
yq --yaml-output -s '.[0] * {"orderers":.[1].orderers}' \
    "${ORG2_NAME}.yaml" ordservice.yaml > "${ORG2_NAME}-out1.yaml"

yq --yaml-output -s '.[0] * {"channels":{"_default":{"orderers": .[1].channels._default.orderers }}}' \
    "${ORG2_NAME}-out1.yaml" ordservice.yaml > "${ORG2_NAME}-out2.yaml"

# Backup original org2 config
mv "${ORG2_NAME}.yaml" "${ORG2_NAME}.yaml.backup"

# Rename output to org2.yaml
mv "${ORG2_NAME}-out2.yaml" "${ORG2_NAME}.yaml"

echo "=== Process finished. Please send 'org2.yaml' and 'org2_update_in_envelope.pb' to Org2 ==="
