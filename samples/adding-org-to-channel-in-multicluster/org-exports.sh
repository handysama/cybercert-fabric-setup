#!/bin/bash

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

# CHAINCODE
export CC_NAME=certificate_info
export CC_VERSION="1.0"
export CC_SEQUENCE=2
