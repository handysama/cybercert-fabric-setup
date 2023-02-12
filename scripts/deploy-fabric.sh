#!/bin/bash

set -o errexit

# TODO: change this path to your local
export KUBE_CONFIG_PATH=/var/snap/microk8s/current/credentials/client.config
export KUBECONFIG=/var/snap/microk8s/current/credentials/client.config

export PEER_IMAGE=quay.io/kfsoftware/fabric-peer
export PEER_VERSION=2.4.1-v0.0.3

export ORDERER_IMAGE=hyperledger/fabric-orderer
export ORDERER_VERSION=2.4.1

export HLF_STORAGE_CLASS=microk8s-hostpath # default: standard

export CHANNEL_ID=ecertplatform
export ORG1_NAME=org1
export ORG1_MSP=Org1MSP

###############################################################################
# Create Certificate Authority (CA) and Peer for Organization
###############################################################################

echo "=== Create Certificate Authority ==="

kubectl hlf ca create \
    --storage-class "${HLF_STORAGE_CLASSS}" \
    --capacity 2Gi \
    --name org1-ca \
    --enroll-id enroll \
    --enroll-pw enrollpw

kubectl wait --timeout=180s --for=condition=Running fabriccas.hlf.kungfusoftware.es --all

kubectl hlf ca register \
    --name org1-ca \
    --user peer \
    --secret peerpw \
    --type peer \
    --enroll-id enroll \
    --enroll-secret enrollpw \
    --mspid Org1MSP

echo "=== Create Peer ==="

# Peer 0
kubectl hlf peer create \
    --statedb couchdb \
    --image "${PEER_IMAGE}" \
    --version "${PEER_VERSION}" \
    --storage-class "${HLF_STORAGE_CLASS}" \
    --enroll-id peer \
    --mspid Org1MSP \
    --enroll-pw peerpw \
    --capacity 10Gi \
    --name org1-peer0 \
    --ca-name org1-ca.default

kubectl wait --timeout=180s --for=condition=Running fabricpeers.hlf.kungfusoftware.es --all

# Peer 1
# kubectl hlf peer create \
#     --statedb couchdb \
#     --image "${PEER_IMAGE}" \
#     --version "${PEER_VERSION}" \
#     --storage-class "${HLF_STORAGE_CLASS}" \
#     --enroll-id peer \
#     --mspid Org1MSP \
#     --enroll-pw peerpw \
#     --capacity 5Gi \
#     --name org1-peer1 \
#     --ca-name org1-ca.default

# kubectl wait --timeout=180s --for=condition=Running fabricpeers.hlf.kungfusoftware.es --all

###############################################################################
# Deploying Ordering Service
###############################################################################

echo "=== Create Ord CA ==="

kubectl hlf ca create \
    --storage-class "${HLF_STORAGE_CLASS}" \
    --capacity 2Gi \
    --name ord-ca \
    --enroll-id enroll \
    --enroll-pw enrollpw

kubectl wait --timeout=180s --for=condition=Running fabriccas.hlf.kungfusoftware.es --all

kubectl hlf ca register \
    --name ord-ca \
    --user orderer \
    --secret ordererpw \
    --type orderer \
    --enroll-id enroll \
    --enroll-secret enrollpw \
    --mspid OrdererMSP

echo "=== Create Orderer node ==="

kubectl hlf ordnode create \
    --image "${ORDERER_IMAGE}" \
    --version "${ORDERER_VERSION}" \
    --storage-class "${HLF_STORAGE_CLASS}" \
    --enroll-id orderer \
    --mspid OrdererMSP \
    --enroll-pw ordererpw \
    --capacity 2Gi \
    --name ord-node1 \
    --ca-name ord-ca.default

kubectl wait --timeout=180s --for=condition=Running fabricorderernodes.hlf.kungfusoftware.es --all

# Output orderer service config
kubectl hlf inspect --output ordservice.yaml -o OrdererMSP

kubectl hlf ca register \
    --name ord-ca \
    --user admin \
    --secret adminpw \
    --type admin \
    --enroll-id enroll \
    --enroll-secret enrollpw \
    --mspid OrdererMSP

kubectl hlf ca enroll \
    --name ord-ca \
    --user admin \
    --secret adminpw \
    --mspid OrdererMSP \
    --ca-name ca \
    --output admin-ordservice.yaml

## add user from admin-ordservice.yaml to ordservice.yaml
kubectl hlf utils adduser --userPath=admin-ordservice.yaml --config=ordservice.yaml --username=admin --mspid=OrdererMSP

sleep 10

###############################################################################
# Create Channel
###############################################################################

echo "=== Create Channel ==="

kubectl hlf channel generate \
    --output "${CHANNEL_ID}.block" \
    --name "${CHANNEL_ID}" \
    --organizations Org1MSP \
    --ordererOrganizations OrdererMSP

kubectl hlf ca enroll \
    --name ord-ca \
    --namespace default \
    --user admin \
    --secret adminpw \
    --mspid OrdererMSP \
    --ca-name tlsca \
    --output admin-tls-ordservice.yaml 

kubectl hlf ordnode join \
    --block "${CHANNEL_ID}.block" \
    --name ord-node1 \
    --namespace default \
    --identity admin-tls-ordservice.yaml

kubectl hlf ca register \
    --name org1-ca \
    --user admin \
    --secret adminpw \
    --type admin \
    --enroll-id enroll \
    --enroll-secret enrollpw \
    --mspid Org1MSP  

kubectl hlf ca enroll \
    --name org1-ca \
    --user admin \
    --secret adminpw \
    --mspid Org1MSP \
    --ca-name ca \
    --output peer-org1.yaml

kubectl hlf inspect --output org1.yaml -o Org1MSP -o OrdererMSP

kubectl hlf utils adduser \
    --userPath peer-org1.yaml \
    --config org1.yaml \
    --username admin \
    --mspid Org1MSP

sleep 10

###############################################################################
# Join channel
###############################################################################

echo "=== Join channel ==="

# Join Peer0
kubectl hlf channel join \
    --name "${CHANNEL_ID}" \
    --config org1.yaml \
    --user admin \
    --peer org1-peer0.default

# Join Peer1
# kubectl hlf channel join \
#     --name "${CHANNEL_ID}" \
#     --config org1.yaml \
#     --user admin \
#     --peer org1-peer1.default

# Output channel config
kubectl hlf channel inspect \
    --channel "${CHANNEL_ID}" \
    --config org1.yaml \
    --user admin \
    --peer org1-peer0.default > "${CHANNEL_ID}.json"

echo "=== Add anchor peer ==="
kubectl hlf channel addanchorpeer \
    --channel "${CHANNEL_ID}" \
    --config org1.yaml \
    --user admin \
    --peer org1-peer0.default 

sleep 10

###############################################################################
# Install Chaincodes
###############################################################################

deploy_chaincode() {
    echo "=== Install chaincode ${CC_NAME} / this can take 3-4 minutes ==="

    kubectl hlf chaincode install \
        --path "./fixtures/chaincodes/${CC_NAME}" \
        --config org1.yaml \
        --language golang \
        --label "${CC_NAME}" \
        --user admin \
        --peer org1-peer0.default

    echo "=== Query chaincodes ${CC_NAME} installed ==="

    kubectl hlf chaincode queryinstalled \
        --config org1.yaml \
        --user admin \
        --peer org1-peer0.default

    PACKAGE_ID=`kubectl hlf chaincode queryinstalled --config=org1.yaml --user=admin --peer=org1-peer0.default | awk -v cc_name="${CC_NAME}" '{ if ($2 == cc_name) print $1 }'`
    echo "${PACKAGE_ID}"

    echo "=== Approve Chaincode ${CC_NAME} ==="

    kubectl hlf chaincode approveformyorg \
        --config org1.yaml \
        --user admin \
        --peer org1-peer0.default \
        --package-id "${PACKAGE_ID}" \
        --version "${CC_VERSION}" \
        --sequence "${CC_SEQUENCE}" \
        --name "${CC_NAME}" \
        --policy "OR('Org1MSP.member')" \
        --channel "${CHANNEL_ID}"

    echo "=== Commit Chaincode ${CC_NAME} ==="
    kubectl hlf chaincode commit \
        --config org1.yaml \
        --user admin \
        --mspid Org1MSP \
        --version "${CC_VERSION}" \
        --sequence "${CC_SEQUENCE}" \
        --name "${CC_NAME}" \
        --policy "OR('Org1MSP.member')" \
        --channel "${CHANNEL_ID}"
}

export CC_SEQUENCE=1
export CC_VERSION="1.0"
export CC_NAME=certificate_info
deploy_chaincode

export CC_NAME=certificate_template
deploy_chaincode

export CC_NAME=token_registry
deploy_chaincode
