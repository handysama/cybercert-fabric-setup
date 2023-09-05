#!/bin/bash

set -o errexit

shopt -s expand_aliases
alias kubectl='microk8s kubectl'

export CHANNEL_ID=ecertplatform
export ORG1_NAME=org1
export ORG1_MSP=Org1MSP

echo "=== Create metadata file ==="

export CHAINCODE_IMAGE=handysama/cc_certtemplate # path to published public chaincode docker images
export CHAINCODE_NAME=certificate-template
export CHAINCODE_LABEL=certificate-template
export SEQUENCE=1
export VERSION="1.0"

# remove the code.tar.gz chaincode.tgz if they exist
test -f code.tar.gz && rm code.tar.gz
test -f chaincode.tgz && rm chaincode.tgz
cat << METADATA-EOF > "metadata.json"
{
    "type": "ccaas",
    "label": "${CHAINCODE_LABEL}"
}
METADATA-EOF
## chaincode as a service

cat > "connection.json" <<CONN_EOF
{
  "address": "${CHAINCODE_NAME}:7052",
  "dial_timeout": "10s",
  "tls_required": false
}
CONN_EOF

tar cfz code.tar.gz connection.json
tar cfz chaincode.tgz metadata.json code.tar.gz
export PACKAGE_ID=$(kubectl hlf chaincode calculatepackageid --path=chaincode.tgz --language=node --label=$CHAINCODE_LABEL)
echo "PACKAGE_ID=$PACKAGE_ID"

# Peer 0
kubectl hlf chaincode install \
  --path=./chaincode.tgz \
  --config=org1.yaml \
  --language=golang \
  --label=${CHAINCODE_LABEL} \
  --user=admin \
  --peer=org1-peer0.default

# Peer 1
# kubectl hlf chaincode install \
#   --path=./chaincode.tgz \
#   --config=org1.yaml \
#   --language=golang \
#   --label=${CHAINCODE_LABEL} \
#   --user=admin \
#   --peer=org1-peer1.default

echo "=== Deploy chaincode container ==="

kubectl hlf externalchaincode sync \
  --image=${CHAINCODE_IMAGE} \
  --name=${CHAINCODE_NAME} \
  --namespace=default \
  --package-id=${PACKAGE_ID} \
  --tls-required=false \
  --replicas=1

kubectl hlf chaincode queryinstalled --config=org1.yaml --user=admin --peer=org1-peer0.default

echo "=== Approve chaincode ==="

kubectl hlf chaincode approveformyorg \
  --config=org1.yaml \
  --user=admin \
  --peer=org1-peer0.default \
  --package-id=${PACKAGE_ID} \
  --version "$VERSION" \
  --sequence "$SEQUENCE" \
  --name=${CHAINCODE_NAME} \
  --policy="OR('Org1MSP.member')" \
  --channel=${CHANNEL_ID}

echo "=== Commit chaincode ==="

kubectl hlf chaincode commit \
  --config=org1.yaml \
  --user=admin \
  --mspid=Org1MSP \
  --version "$VERSION" \
  --sequence "$SEQUENCE" \
  --name=${CHAINCODE_NAME} \
  --policy="OR('Org1MSP.member')" \
  --channel=${CHANNEL_ID}

sleep 30

echo "=== Chaincode deployed ==="
