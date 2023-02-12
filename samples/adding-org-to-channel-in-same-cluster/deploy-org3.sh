###############################################################################
#
#   Deploy Org3 in Same Cluster
#
#   Please make sure required apps (jq, yq, configtxlator) already installed.
###############################################################################

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

# ORG 1
export ORG1_MSP=Org1MSP
export ORG1_NAME=org1
export ORG1_NAMESPACE=default

export ORG1_ADMIN_USER=admin
export ORG1_ORD_MSP=OrdererMSP
export ORG1_ORD_CA=ord-ca
export ORG1_PEER0=${ORG1_NAME}-peer0.${ORG1_NAMESPACE}

# ORG 2
export ORG2_MSP=Org2MSP
export ORG2_NAME=org2
export ORG2_NAMESPACE=default
export ORG2_ADMIN_USER=admin-org2
export ORG2_ADMIN_SECRET=adminpw

export ORG2_CA=${ORG2_NAME}-ca
export ORG2_ORD_NODE1=${ORG2_NAME}-ord-node1
export ORG2_PEER0=${ORG2_NAME}-peer0.${ORG2_NAMESPACE}

# ORG 3
export ORG3_MSP=Org3MSP
export ORG3_NAME=org3
export ORG3_NAMESPACE=default
export ORG3_ADMIN_USER=admin-org3
export ORG3_ADMIN_SECRET=adminpw

export ORG3_CA=${ORG3_NAME}-ca
export ORG3_ORD_NODE1=${ORG3_NAME}-ord-node1
export ORG3_PEER0=${ORG3_NAME}-peer0.${ORG3_NAMESPACE}


###############################################################################
# Step 1: Create Certificate Authority (CA) and Peer for Org2
###############################################################################

echo "=== Create Org3 CA ==="
kubectl hlf ca create \
    --storage-class "${HLF_STORAGE_CLASSS}" \
    --capacity 2Gi \
    --name "${ORG3_CA}" \
    --enroll-id enroll \
    --enroll-pw enrollpw

kubectl wait --timeout=180s --for=condition=Running fabriccas.hlf.kungfusoftware.es --all

echo "=== Register peer user in Org3 CA ==="
kubectl hlf ca register \
    --name "${ORG3_CA}" \
    --user peer \
    --secret peerpw \
    --type peer \
    --enroll-id enroll \
    --enroll-secret enrollpw \
    --mspid "${ORG3_MSP}"

echo "=== Create Org3 Peer ==="
kubectl hlf peer create \
    --statedb couchdb \
    --image "${PEER_IMAGE}" \
    --version "${PEER_VERSION}" \
    --storage-class "${HLF_STORAGE_CLASS}" \
    --capacity 5Gi \
    --enroll-id peer \
    --enroll-pw peerpw \
    --mspid "${ORG3_MSP}" \
    --name "${ORG3_NAME}-peer0" \
    --ca-name "${ORG3_CA}.${ORG3_NAMESPACE}"

kubectl wait --timeout=180s --for=condition=Running fabricpeers.hlf.kungfusoftware.es --all

###############################################################################
# Step 2: Create Admin Org3 in Org1 Orderer CA
###############################################################################

echo "=== Register Admin Org3 to Org1 Ord CA ==="
kubectl hlf ca register \
    --name "${ORG1_ORD_CA}" \
    --user "${ORG3_ADMIN_USER}" \
    --secret "${ORG3_ADMIN_SECRET}" \
    --type admin \
    --enroll-id enroll \
    --enroll-secret enrollpw \
    --namespace "${ORG1_NAMESPACE}" \
    --mspid "${ORG1_ORD_MSP}"

echo "=== Enroll Admin Org3 in Org1 Ord CA ==="
kubectl hlf ca enroll \
    --name "${ORG1_ORD_CA}" \
    --user "${ORG3_ADMIN_USER}" \
    --secret "${ORG3_ADMIN_SECRET}" \
    --namespace "${ORG1_NAMESPACE}" \
    --mspid "${ORG1_ORD_MSP}" \
    --ca-name ca \
    --output admin-ordservice.yaml

echo "=== Add enrolled Admin Org3 to Org1 network config ==="
kubectl hlf utils adduser \
    --userPath admin-ordservice.yaml \
    --config ordservice.yaml \
    --username "${ORG3_ADMIN_USER}" \
    --mspid "${ORG1_ORD_MSP}"

sleep 10

echo "=== Enroll Admin Org3 in Org1 TLS CA ==="
kubectl hlf ca enroll \
    --name "${ORG1_ORD_CA}" \
    --namespace "${ORG1_NAMESPACE}" \
    --user "${ORG3_ADMIN_USER}" \
    --secret "${ORG3_ADMIN_SECRET}" \
    --namespace "${ORG1_NAMESPACE}" \
    --mspid "${ORG1_ORD_MSP}" \
    --ca-name tlsca \
    --output admin-tls-ordservice.yaml

###############################################################################
# Step 3: Create Admin Org3 in Org3 CA
###############################################################################

echo "=== Register Admin Org3 in Org3 CA ==="
kubectl hlf ca register \
    --name "${ORG3_CA}" \
    --user "${ORG3_ADMIN_USER}" \
    --secret "${ORG3_ADMIN_SECRET}" \
    --type admin \
    --enroll-id enroll \
    --enroll-secret enrollpw \
    --namespace "${ORG3_NAMESPACE}" \
    --mspid "${ORG3_MSP}"

kubectl hlf ca enroll \
    --ca-name ca \
    --name "${ORG3_CA}" \
    --user "${ORG3_ADMIN_USER}" \
    --secret "${ORG3_ADMIN_SECRET}" \
    --mspid "${ORG3_MSP}" \
    --output "peer-${ORG3_NAME}.yaml"

# Output Org3 network config file with Org1MSP
kubectl hlf inspect --output "${ORG3_NAME}.yaml" -o "${ORG3_MSP}" -o "${ORG1_ORD_MSP}"

echo "=== Add enrolled  Admin Org3 to Org3 network config ==="
kubectl hlf utils adduser \
    --userPath "peer-${ORG3_NAME}.yaml" \
    --config "${ORG3_NAME}.yaml" \
    --username "${ORG3_ADMIN_USER}" \
    --mspid "${ORG3_MSP}"

sleep 10

###############################################################################
# Step 4: Update channel configuration
###############################################################################

echo "=== Update channel configuration ==="

# Output Org3 crypto material and configtx.yaml
kubectl-hlf org inspect --output-path crypto-config -o "${ORG3_MSP}"

# Output (shared) network configuration of Org1, Org2, Org3
kubectl hlf inspect --output networkConfig.yaml -o "${ORG3_MSP}" -o "${ORG2_MSP}" -o "${ORG1_MSP}" -o "${ORG1_ORD_MSP}"

# Backup original config
cp networkConfig.yaml networkConfig.bak.yaml

yq --yaml-output -s '.[0] * {"organizations":{"'${ORG1_ORD_MSP}'":{"users": .[1].organizations.'${ORG1_ORD_MSP}'.users }}}' \
    networkConfig.yaml ordservice.yaml > networkConfig-out1.yaml

yq --yaml-output -s '.[0] * {"organizations":{"'${ORG1_MSP}'":{"users": .[1].organizations.'${ORG1_MSP}'.users }}}' \
    networkConfig-out1.yaml ${ORG1_NAME}.yaml > networkConfig-out2.yaml

yq --yaml-output -s '.[0] * {"organizations":{"'${ORG2_MSP}'":{"users": .[1].organizations.'${ORG2_MSP}'.users }}}' \
    networkConfig-out2.yaml ${ORG2_NAME}.yaml > networkConfig-out3.yaml

yq --yaml-output -s '.[0] * {"organizations":{"'${ORG3_MSP}'":{"users": .[1].organizations.'${ORG3_MSP}'.users }}}' \
    networkConfig-out3.yaml ${ORG3_NAME}.yaml > networkConfig-out4.yaml

# Override network config
mv networkConfig-out4.yaml networkConfig.yaml

# Output channel update config
kubectl hlf channel addorg \
    --name "${CHANNEL_ID}" \
    --config networkConfig.yaml \
    --user "${ORG1_ADMIN_USER}" \
    --peer "${ORG1_PEER0}" \
    --msp-id "${ORG3_MSP}" \
    --org-config configtx.yaml \
    --dry-run > "${ORG3_NAME}.json"


# Prepare config update material

configtxlator proto_encode --type common.ConfigUpdate --input "${ORG3_NAME}.json" --output "${ORG3_NAME}.pb"

echo '{"payload":{"header":{"channel_header":{"channel_id":"'${CHANNEL_ID}'","type":2}},"data":{"config_update":'$(cat ${ORG3_NAME}.json)'}}}' | jq . > "${ORG3_NAME}_update_in_envelope.json"

configtxlator proto_encode --type common.Envelope --input "${ORG3_NAME}_update_in_envelope.json" --output "${ORG3_NAME}_update_in_envelope.pb"

echo "=== Channel sign update: Org1 ==="

kubectl hlf channel signupdate \
    --channel "${CHANNEL_ID}" \
    -f "${ORG3_NAME}_update_in_envelope.pb" \
    --user "${ORG1_ADMIN_USER}" \
    --config networkConfig.yaml \
    --mspid ${ORG1_MSP} \
    --output "${ORG1_NAME}-${CHANNEL_ID}-sign.pb"

sleep 10

echo "=== Channel sign update: Org2 ==="

kubectl hlf channel signupdate \
    --channel "${CHANNEL_ID}" \
    -f "${ORG3_NAME}_update_in_envelope.pb" \
    --user "${ORG2_ADMIN_USER}" \
    --config networkConfig.yaml \
    --mspid "${ORG2_MSP}" \
    --output "${ORG2_NAME}-ecertplatform-sign.pb"

sleep 10

echo "=== Channel sign update: Org3 ==="

kubectl hlf channel signupdate \
    --channel "${CHANNEL_ID}" \
    -f "${ORG3_NAME}_update_in_envelope.pb" \
    --user "${ORG3_ADMIN_USER}" \
    --config networkConfig.yaml \
    --mspid "${ORG3_MSP}" \
    --output "${ORG3_NAME}-${CHANNEL_ID}-sign.pb"

sleep 10

echo "=== Channel update ==="

kubectl hlf channel update \
    --channel "${CHANNEL_ID}" \
    -f "${ORG3_NAME}_update_in_envelope.pb" \
    --config networkConfig.yaml \
    --user "${ORG1_ADMIN_USER}" \
    --mspid "${ORG1_MSP}" \
    -s "${ORG1_NAME}-${CHANNEL_ID}-sign.pb" \
    -s "${ORG2_NAME}-${CHANNEL_ID}-sign.pb" \
    -s "${ORG3_NAME}-${CHANNEL_ID}-sign.pb"

sleep 10

###############################################################################
# Step 5: Join channel
###############################################################################

echo "=== Join channel ==="

# Join Org3 Peer0
kubectl hlf channel join \
    --name "${CHANNEL_ID}" \
    --config "${ORG3_NAME}.yaml" \
    --user "${ORG3_ADMIN_USER}" \
    --peer "${ORG3_PEER0}"

# Inspect the channel
kubectl hlf channel inspect \
    --channel "${CHANNEL_ID}" \
    --config "${ORG3_NAME}.yaml" \
    --user "${ORG3_ADMIN_USER}" \
    --peer "${ORG3_PEER0}" > "${CHANNEL_ID}.json"

sleep 10

echo "=== Add anchor peer ==="

kubectl hlf channel addanchorpeer \
    --channel "${CHANNEL_ID}" \
    --config "${ORG3_NAME}.yaml" \
    --user "${ORG3_ADMIN_USER}" \
    --peer "${ORG3_PEER0}"

sleep 10

###############################################################################
# Step 6: Install Chaincodes
###############################################################################

deploy_chaincode() {
    echo "=== Install chaincode ${CC_NAME} (this can take 3-4 minutes) ==="
    kubectl hlf chaincode install \
        --path "./fixtures/chaincodes/${CC_NAME}" \
        --config "${ORG3_NAME}.yaml" \
        --language golang \
        --label "${CC_NAME}" \
        --user "${ORG3_ADMIN_USER}" \
        --peer "${ORG3_PEER0}"

    echo "=== Query chaincodes ${CC_NAME} installed ==="
    kubectl hlf chaincode queryinstalled \
        --config "${ORG3_NAME}.yaml" \
        --user "${ORG3_ADMIN_USER}" \
        --peer "${ORG3_PEER0}"

    PACKAGE_ID=`kubectl hlf chaincode queryinstalled --config=${ORG3_NAME}.yaml --user=${ORG3_ADMIN_USER} --peer=${ORG3_PEER0} | awk -v cc_name="${CC_NAME}" '{ if ($2 == cc_name) print $1 }'`
    echo "${PACKAGE_ID}"

    echo "=== Approve Chaincode ${CC_NAME} ==="

    # Approve by Org3
    kubectl hlf chaincode approveformyorg \
        --config "${ORG3_NAME}.yaml" \
        --user "${ORG3_ADMIN_USER}" \
        --peer "${ORG3_PEER0}" \
        --package-id "${PACKAGE_ID}" \
        --name "${CC_NAME}" \
        --version "${CC_VERSION}" \
        --sequence "${CC_SEQUENCE}" \
        --policy "OR('${ORG1_MSP}.member')" \
        --channel "${CHANNEL_ID}"

    # Approve by Org2
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

    # Approve by Org1
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

    sleep 10

    echo "=== Commit Chaincode ${CC_NAME} ==="
    kubectl hlf chaincode commit \
        --config "${ORG1_NAME}.yaml" \
        --user "${ORG1_ADMIN_USER}" \
        --mspid "${ORG1_MSP}" \
        --name "${CC_NAME}" \
        --version "${CC_VERSION}" \
        --sequence "${CC_SEQUENCE}" \
        --policy "OR('${ORG1_MSP}.member')" \
        --channel "${CHANNEL_ID}"

    sleep 5

    echo "== querycommitted ==="
    kubectl hlf chaincode querycommitted \
        --peer "${ORG3_PEER0}" \
        --user "${ORG3_ADMIN_USER}" \
        --config "${ORG3_NAME}.yaml" \
        --channel "${CHANNEL_ID}" \
        --chaincode "${CC_NAME}"
}

export CC_SEQUENCE=3
export CC_VERSION="1.0"
export CC_NAME=certificate_info
deploy_chaincode

export CC_NAME=certificate_template
deploy_chaincode

export CC_NAME=token_registry
deploy_chaincode
