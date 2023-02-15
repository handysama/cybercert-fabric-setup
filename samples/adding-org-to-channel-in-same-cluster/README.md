# Adding organization to channel in same cluster

**This guide serve for educational purpose and not intended for production setup**.

This tutorial will guide you deploying new organization to exisitng channel in same machine. When adding new org in same machine, the environment can share network config file and crypto material, this way we can streamline process into scripts.

For complete example please see [deploy-org2.sh](/samples/adding-org-to-channel-in-same-cluster/deploy-org2.sh).

## Prerequisites

Before start tutorial please complete deploying first organization (Org1) cluster from initial guide then install required application: [jq](https://stedolan.github.io/jq/download/), [yq](https://github.com/kislyuk/yq#installation), and `configtxlator` from [fabric-binaries](https://github.com/hyperledger/fabric/releases/tag/v2.4.3).

```bash
cd ~

wget https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64
chmod +x jq-linux64
sudo mv jq-linux64 /usr/local/bin/jq

# alternatively can use: pip3 install yq
pip install yq 

wget https://github.com/hyperledger/fabric/releases/download/v2.4.3/hyperledger-fabric-linux-amd64-2.4.3.tar.gz
sudo mkdir /usr/local/fabric-binaries
sudo tar -C /usr/local/fabric-binaries -xzf hyperledger-fabric-linux-amd64-2.4.3.tar.gz
```

## Exports Template

Below are export value that use in this tutorial examples.

```bash
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
```

## Step 1: Create Certificate Authority (CA) and Peer for Org2

The first step is to create `CA` and one `peer` for Org2.

```bash
# Create CA
kubectl hlf ca create \
    --storage-class "${HLF_STORAGE_CLASSS}" \
    --capacity 2Gi \
    --namespace "${ORG2_NAMESPACE}" \
    --name "${ORG2_CA}" \
    --enroll-id enroll \
    --enroll-pw enrollpw

kubectl wait --timeout=180s --for=condition=Running fabriccas.hlf.kungfusoftware.es --all

# Register user for the peer
kubectl hlf ca register \
    --name "${ORG2_CA}" \
    --user peer \
    --secret peerpw \
    --type peer \
    --enroll-id enroll \
    --enroll-secret enrollpw \
    --mspid "${ORG2_MSP}" \
    --namespace "${ORG2_NAMESPACE}"

# Create Peer
kubectl hlf peer create \
    --statedb couchdb \
    --image "${PEER_IMAGE}" \
    --version "${PEER_VERSION}" \
    --storage-class "${HLF_STORAGE_CLASS}" \
    --capacity 5Gi \
    --enroll-id peer \
    --enroll-pw peerpw \
    --mspid "${ORG2_MSP}" \
    --namespace "${ORG2_NAMESPACE}" \
    --name "${ORG2_NAME}-peer0" \
    --ca-name "${ORG2_CA}.${ORG2_NAMESPACE}"

kubectl wait --timeout=180s --for=condition=Running fabricpeers.hlf.kungfusoftware.es --all
```

## Step 2: Create Admin Org2 in Org1 Orderer CA

In this step, create Org2 admin user in orderer CA. `sleep` command is execute to give enough time for previous commands to finish.

```bash
kubectl hlf ca register \
    --name "${ORG1_ORD_CA}" \
    --user "${ORG2_ADMIN_USER}" \
    --secret "${ORG2_ADMIN_SECRET}" \
    --type admin \
    --enroll-id enroll \
    --enroll-secret enrollpw \
    --namespace "${ORG1_NAMESPACE}" \
    --mspid "${ORG1_ORD_MSP}"

kubectl hlf ca enroll \
    --name "${ORG1_ORD_CA}" \
    --user "${ORG2_ADMIN_USER}" \
    --secret "${ORG2_ADMIN_SECRET}" \
    --namespace "${ORG1_NAMESPACE}" \
    --mspid "${ORG1_ORD_MSP}" \
    --ca-name ca \
    --output admin-ordservice.yaml

kubectl hlf utils adduser \
    --userPath admin-ordservice.yaml \
    --config ordservice.yaml \
    --username "${ORG2_ADMIN_USER}" \
    --mspid "${ORG1_ORD_MSP}"

sleep 10

kubectl hlf ca enroll \
    --name "${ORG1_ORD_CA}" \
    --user "${ORG2_ADMIN_USER}" \
    --secret "${ORG2_ADMIN_SECRET}" \
    --namespace "${ORG1_NAMESPACE}" \
    --mspid "${ORG1_ORD_MSP}" \
    --ca-name tlsca \
    --output admin-tls-ordservice.yaml
```

## Step 3: Create Admin Org2 in Org2 CA

```bash
kubectl hlf ca register \
    --name "${ORG2_CA}" \
    --user "${ORG2_ADMIN_USER}" \
    --secret "${ORG2_ADMIN_SECRET}" \
    --type admin \
    --enroll-id enroll \
    --enroll-secret enrollpw \
    --namespace "${ORG2_NAMESPACE}" \
    --mspid "${ORG2_MSP}"

kubectl hlf ca enroll \
    --ca-name ca \
    --name "${ORG2_CA}" \
    --user "${ORG2_ADMIN_USER}" \
    --secret "${ORG2_ADMIN_SECRET}" \
    --namespace "${ORG2_NAMESPACE}" \
    --mspid "${ORG2_MSP}" \
    --output "peer-${ORG2_NAME}.yaml"

# Output Org2 network config file with Org1MSP
kubectl hlf inspect --output "${ORG2_NAME}.yaml" -o "${ORG2_MSP}" -o "${ORG1_ORD_MSP}"

kubectl hlf utils adduser \
    --userPath "peer-${ORG2_NAME}.yaml" \
    --config "${ORG2_NAME}.yaml" \
    --username "${ORG2_ADMIN_USER}" \
    --mspid "${ORG2_MSP}"

sleep 10
```

## Step 4: Update channel configuration

In this step, we will modify channel configuration and envelope config in protobuf format. After that, `Org1` and `Org2` need to sign the update then org1 can commit channel update.

### Step 4.1: Prepare crypto material of Org2

```bash
# Output Org2 crypto material and configtx.yaml
kubectl-hlf org inspect --output-path crypto-config -o "${ORG2_MSP}"

# Output (shared) network configuration of Org1 and Org2
kubectl hlf inspect --output networkConfig.yaml -o "${ORG2_MSP}" -o "${ORG1_MSP}" -o "${ORG1_ORD_MSP}"

# Backup original config
cp networkConfig.yaml networkConfig.bak.yaml
```

### Step 4.2: Append Org1 user to Org2 network config

```bash
yq --yaml-output -s '.[0] * {"organizations":{"'${ORG1_ORD_MSP}'":{"users": .[1].organizations.'${ORG1_ORD_MSP}'.users }}}' \
    networkConfig.yaml ordservice.yaml > networkConfig-out1.yaml

yq --yaml-output -s '.[0] * {"organizations":{"'${ORG1_MSP}'":{"users": .[1].organizations.'${ORG1_MSP}'.users }}}' \
    networkConfig-out1.yaml org1.yaml > networkConfig-out2.yaml

yq --yaml-output -s '.[0] * {"organizations":{"'${ORG2_MSP}'":{"users": .[1].organizations.'${ORG2_MSP}'.users }}}' \
    networkConfig-out2.yaml org2.yaml > networkConfig-out3.yaml

# Override network config
mv networkConfig-out3.yaml networkConfig.yaml
```

### Step 4.3: Output channel add org configuration

```bash
# Output channel update config
kubectl hlf channel addorg \
    --name "${CHANNEL_ID}" \
    --config networkConfig.yaml \
    --user "${ORG1_ADMIN_USER}" \
    --peer "${ORG1_PEER0}" \
    --msp-id "${ORG2_MSP}" \
    --org-config configtx.yaml \
    --dry-run > "${ORG2_NAME}.json"
```

### Step 4.4: Add Org2 crypto material

```bash
echo '{"payload":{"header":{"channel_header":{"channel_id":"'${CHANNEL_ID}'","type":2}},"data":{"config_update":'$(cat ${ORG2_NAME}.json)'}}}' | jq . > "${ORG2_NAME}_update_in_envelope.json"

configtxlator proto_encode --type common.Envelope --input "${ORG2_NAME}_update_in_envelope.json" --output "${ORG2_NAME}_update_in_envelope.pb"
```

### Step 4.5: Sign and submit channel config update

The last step in channel config is to sign update in exisitng Org then gather signed files in Org1 enviroment.

```bash
# Channel sign update: org1 
kubectl hlf channel signupdate \
    --channel "${CHANNEL_ID}" \
    -f "${ORG2_NAME}_update_in_envelope.pb" \
    --user "${ORG1_ADMIN_USER}" \
    --config networkConfig.yaml \
    --mspid "${ORG1_MSP}" \
    --output "${ORG1_NAME}-${CHANNEL_ID}-sign.pb"

sleep 10

# Channel sign update: org2
kubectl hlf channel signupdate \
    --channel "${CHANNEL_ID}" \
    -f "${ORG2_NAME}_update_in_envelope.pb" \
    --user "${ORG2_ADMIN_USER}"  \
    --config networkConfig.yaml \
    --mspid "${ORG2_MSP}" \
    --output "${ORG2_NAME}-${CHANNEL_ID}-sign.pb"

sleep 10

# Channel update
kubectl hlf channel update \
    --channel "${CHANNEL_ID}" \
    -f "${ORG2_NAME}_update_in_envelope.pb" \
    --config networkConfig.yaml \
    --user "${ORG1_ADMIN_USER}" \
    --mspid "${ORG1_MSP}" \
    -s "${ORG1_NAME}-${CHANNEL_ID}-sign.pb" \
    -s "${ORG2_NAME}-${CHANNEL_ID}-sign.pb"
```

## Step 5: Join channel

After channel updated, Org2 can join the channel and fetch channel configuration.

```bash
kubectl hlf channel join \
    --name "${CHANNEL_ID}" \
    --config "${ORG2_NAME}.yaml" \
    --user "${ORG2_ADMIN_USER}" \
    --peer "${ORG2_PEER0}"

kubectl hlf channel inspect \
    --channel "${CHANNEL_ID}" \
    --config "${ORG2_NAME}.yaml" \
    --user "${ORG2_ADMIN_USER}" \
    --peer "${ORG2_PEER0}" > "${CHANNEL_ID}.json"

sleep 10

kubectl hlf channel addanchorpeer \
    --channel "${CHANNEL_ID}" \
    --config "${ORG2_NAME}.yaml" \
    --user "${ORG2_ADMIN_USER}" \
    --peer "${ORG2_PEER0}"

sleep 10
```

## Step 6: Install Chaincodes

To reduce redundant command, we create function `deploy_chaincode` and set export values to deploy multiple chaincodes. One thing to note is to **increment sequence number by 1** from the last sequence.

```bash
export CC_SEQUENCE=2
export CC_VERSION="1.0"
export CC_NAME=certificate_info
deploy_chaincode

export CC_NAME=certificate_template
deploy_chaincode

export CC_NAME=token_registry
deploy_chaincode
```

Executing deploy chaincode can takes several minutes depend on machine specs. Same as channel update, when deploying chaincode to new org, it require approval from existing org. See below scripts for example.

```bash
deploy_chaincode() {
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

    kubectl hlf chaincode commit \
        --config "${ORG1_NAME}.yaml" \
        --user "${ORG1_ADMIN_USER}" \
        --mspid "${ORG1_MSP}" \
        --name "${CC_NAME}" \
        --version "${CC_VERSION}" \
        --sequence "${CC_SEQUENCE}" \
        --policy "OR('${ORG1_MSP}.member')" \
        --channel "${CHANNEL_ID}"

    kubectl hlf chaincode querycommitted \
        --peer "${ORG2_PEER0}" \
        --user "${ORG2_ADMIN_USER}" \
        --config "${ORG2_NAME}.yaml" \
        --channel "${CHANNEL_ID}" \
        --chaincode "${CC_NAME}"
}
```

## Adding Org3

Adding third organization (Org3) steps are similar to the Org2. When adding Org3, we need to get approval from both Org1 and Org2. Please be aware, running multiple organization in the same cluster will takes a lots of memory.

Please see [deploy-org3.sh](/samples/adding-org-to-channel-in-same-cluster/deploy-org3.sh) for complete steps.

## References

- Fabric Channel Update Tutorial (<https://hyperledger-fabric.readthedocs.io/en/release-2.4/channel_update_tutorial.html>)
- AWS Samples, Part 5: Adding a new member to a Fabric network on Amazon Managed Blockchain (<https://github.com/aws-samples/non-profit-blockchain/blob/master/new-member/README.md>)
- Adding a new Org in MultiCluster Env - Part 16 | Hyperledger Fabric On Kubernetes (<https://www.youtube.com/watch?v=0VUx9CYn4z8&ab_channel=AdityaJoshi>)
