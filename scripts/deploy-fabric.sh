#!/bin/bash

set -o errexit

shopt -s expand_aliases
alias kubectl='microk8s kubectl'

export PEER_IMAGE=hyperledger/fabric-peer
export PEER_VERSION=2.5.0

export ORDERER_IMAGE=hyperledger/fabric-orderer
export ORDERER_VERSION=2.5.0

export CA_IMAGE=hyperledger/fabric-ca
export CA_VERSION=1.5.6

export HLF_STORAGE_CLASS=microk8s-hostpath # default: standard
export CHANNEL_ID=ecertplatform

export ORG1_CA_HOST=org1-ca.localho.st
export ORG1_PEER0_HOST=peer0-org1.localho.st
export ORG1_PEER1_HOST=peer1-org1.localho.st
export ORD_CA_HOST=ord-ca.localho.st
export ORD_NODE_HOST=orderer0-ord.localho.st

###############################################################################
# Deploy a Certificate Authority (CA)
###############################################################################

echo "=== Create Org1 CA ==="

kubectl hlf ca create \
  --image=$CA_IMAGE \
  --version=$CA_VERSION \
  --storage-class=${HLF_STORAGE_CLASSS} \
  --capacity=1Gi \
  --name=org1-ca \
  --enroll-id=enroll \
  --enroll-pw=enrollpw \
  --hosts=${ORG1_CA_HOST} \
  --istio-port=443

kubectl wait --timeout=180s --for=condition=Running fabriccas.hlf.kungfusoftware.es --all

echo "=== Register user in CA for peers ==="

kubectl hlf ca register \
  --name=org1-ca \
  --user=peer \
  --secret=peerpw \
  --type=peer \
  --enroll-id enroll \
  --enroll-secret=enrollpw \
  --mspid Org1MSP

###############################################################################
# Deploy Peer
###############################################################################

echo "=== Create Peer0 ==="

# Peer 0
kubectl hlf peer create \
  --statedb=couchdb \
  --image=${PEER_IMAGE} \
  --version=${PEER_VERSION} \
  --storage-class=${HLF_STORAGE_CLASSS} \
  --enroll-id=peer \
  --mspid=Org1MSP \
  --enroll-pw=peerpw \
  --capacity=5Gi \
  --name=org1-peer0 \
  --ca-name=org1-ca.default \
  --hosts=${ORG1_PEER0_HOST} \
  --istio-port=443

# Peer 1
# kubectl hlf peer create \
#   --statedb=couchdb \
#   --image=$PEER_IMAGE \
#   --version=$PEER_VERSION \
#   --storage-class=${HLF_STORAGE_CLASSS} \
#   --enroll-id=peer \
#   --mspid=Org1MSP \
#   --enroll-pw=peerpw \
#   --capacity=5Gi \
#   --name=org1-peer1 \
#   --ca-name=org1-ca.default \
#   --hosts=${ORG1_PEER1_HOST} \
#   --istio-port=443

kubectl wait --timeout=180s --for=condition=Running fabricpeers.hlf.kungfusoftware.es --all


###############################################################################
# Deploy Orderer
###############################################################################

echo "=== Create Orderer CA ==="

kubectl hlf ca create \
  --image=$CA_IMAGE \
  --version=$CA_VERSION \
  --storage-class=${HLF_STORAGE_CLASSS} \
  --capacity=1Gi \
  --name=ord-ca \
  --enroll-id=enroll \
  --enroll-pw=enrollpw \
  --hosts=${ORD_CA_HOST} \
  --istio-port=443

kubectl wait --timeout=180s --for=condition=Running fabriccas.hlf.kungfusoftware.es --all

echo "=== Register user orderer ==="

kubectl hlf ca register \
  --name=ord-ca \
  --user=orderer \
  --secret=ordererpw \
  --type=orderer \
  --enroll-id enroll \
  --enroll-secret=enrollpw \
  --mspid=OrdererMSP \
  --ca-url="https://${ORD_CA_HOST}:443"

echo "=== Deploy orderer ==="

kubectl hlf ordnode create \
  --image=$ORDERER_IMAGE \
  --version=$ORDERER_VERSION \
  --storage-class=${HLF_STORAGE_CLASSS} \
  --enroll-id=orderer \
  --mspid=OrdererMSP \
  --enroll-pw=ordererpw \
  --capacity=2Gi \
  --name=ord-node1 \
  --ca-name=ord-ca.default \
  --hosts=${ORD_NODE_HOST} \
  --istio-port=443

kubectl wait --timeout=180s --for=condition=Running fabricorderernodes.hlf.kungfusoftware.es --all

###############################################################################
# Create Channel
###############################################################################

echo "=== Register and enrolling OrdererMSP identity ==="

# register
kubectl hlf ca register \
  --name=ord-ca \
  --namespace=default \
  --user=admin \
  --secret=adminpw \
  --type=admin \
  --enroll-id enroll \
  --enroll-secret=enrollpw \
  --mspid=OrdererMSP

# enroll
kubectl hlf ca enroll \
  --name=ord-ca \
  --namespace=default \
  --user=admin \
  --secret=adminpw \
  --mspid OrdererMSP \
  --ca-name tlsca \
  --output orderermsp.yaml

echo "=== Register and enrolling Org1MSP identity ==="

# register
kubectl hlf ca register \
  --name=org1-ca \
  --namespace=default \
  --user=admin \
  --secret=adminpw \
  --type=admin \
  --enroll-id enroll \
  --enroll-secret=enrollpw \
  --mspid=Org1MSP

# enroll
kubectl hlf ca enroll \
  --name=org1-ca \
  --namespace=default \
  --user=admin \
  --secret=adminpw \
  --mspid Org1MSP \
  --ca-name ca \
  --output org1msp.yaml

echo "=== Create the secret ==="

kubectl create secret generic \
  wallet \
  --namespace=default \
  --from-file=org1msp.yaml=$PWD/org1msp.yaml \
  --from-file=orderermsp.yaml=$PWD/orderermsp.yaml

echo "=== Create main channel ==="

export PEER_ORG_SIGN_CERT=$(kubectl get fabriccas org1-ca -o=jsonpath='{.status.ca_cert}')
export PEER_ORG_TLS_CERT=$(kubectl get fabriccas org1-ca -o=jsonpath='{.status.tlsca_cert}')
export IDENT_8=$(printf "%8s" "")
export ORDERER_TLS_CERT=$(kubectl get fabriccas ord-ca -o=jsonpath='{.status.tlsca_cert}' | sed -e "s/^/${IDENT_8}/" )
export ORDERER0_TLS_CERT=$(kubectl get fabricorderernodes ord-node1 -o=jsonpath='{.status.tlsCert}' | sed -e "s/^/${IDENT_8}/" )
export ABSOLUTE_MAX_BYTES=10485760

kubectl apply -f - <<EOF
apiVersion: hlf.kungfusoftware.es/v1alpha1
kind: FabricMainChannel
metadata:
  name: ${CHANNEL_ID}
spec:
  name: ${CHANNEL_ID}
  adminOrdererOrganizations:
    - mspID: OrdererMSP
  adminPeerOrganizations:
    - mspID: Org1MSP
  channelConfig:
    application:
      acls: null
      capabilities:
        - V2_0
      policies: null
    capabilities:
      - V2_0
    orderer:
      batchSize:
        absoluteMaxBytes: ${ABSOLUTE_MAX_BYTES}
        maxMessageCount: 10
        preferredMaxBytes: 524288
      batchTimeout: 2s
      capabilities:
        - V2_0
      etcdRaft:
        options:
          electionTick: 10
          heartbeatTick: 1
          maxInflightBlocks: 5
          snapshotIntervalSize: 16777216
          tickInterval: 500ms
      ordererType: etcdraft
      policies: null
      state: STATE_NORMAL
    policies: null
  externalOrdererOrganizations: []
  peerOrganizations:
    - mspID: Org1MSP
      caName: "org1-ca"
      caNamespace: "default"
  identities:
    OrdererMSP:
      secretKey: orderermsp.yaml
      secretName: wallet
      secretNamespace: default
    Org1MSP:
      secretKey: org1msp.yaml
      secretName: wallet
      secretNamespace: default
  externalPeerOrganizations: []
  ordererOrganizations:
    - caName: "ord-ca"
      caNamespace: "default"
      externalOrderersToJoin:
        - host: ord-node1
          port: 7053
      mspID: OrdererMSP
      ordererEndpoints:
        - ord-node1:7050
      orderersToJoin: []
  orderers:
    - host: ord-node1
      port: 7050
      tlsCert: |-
${ORDERER0_TLS_CERT}

EOF

sleep 10

echo "=== Join peer to the channel ==="

export IDENT_8=$(printf "%8s" "")
export ORDERER0_TLS_CERT=$(kubectl get fabricorderernodes ord-node1 -o=jsonpath='{.status.tlsCert}' | sed -e "s/^/${IDENT_8}/" )

kubectl apply -f - <<EOF
apiVersion: hlf.kungfusoftware.es/v1alpha1
kind: FabricFollowerChannel
metadata:
  name: ${CHANNEL_ID}-org1msp
spec:
  anchorPeers:
    - host: org1-peer0.default
      port: 7051
  hlfIdentity:
    secretKey: org1msp.yaml
    secretName: wallet
    secretNamespace: default
  mspId: Org1MSP
  name: ${CHANNEL_ID}
  externalPeersToJoin: []
  orderers:
    - certificate: |
${ORDERER0_TLS_CERT}
      url: grpcs://ord-node1.default:7050
  peersToJoin:
    - name: org1-peer0
      namespace: default
    # - name: org1-peer1
    #   namespace: default
EOF

sleep 10

kubectl hlf inspect --output org1.yaml -o Org1MSP -o OrdererMSP

kubectl hlf ca enroll \
  --name=org1-ca \
  --user=admin \
  --secret=adminpw \
  --mspid Org1MSP \
  --ca-name ca \
  --output peer-org1.yaml

kubectl hlf utils adduser \
  --userPath=peer-org1.yaml \
  --config=org1.yaml \
  --username=admin \
  --mspid=Org1MSP

sleep 10
