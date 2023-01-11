# cybercert-fabric-setup

Hyperledger Fabric setup guide for running CyberCert e-certificate chaincode. The recipe rely on [hlf-operator](https://github.com/hyperledger-labs/hlf-operator) that allow us to setup Fabric quickly.

## How to setup on Debian/Ubuntu

Windows platform is not supported, due to not supported by some open source libraries.

Prerequisite software:

- [snapd](https://snapcraft.io/docs/installing-snapd)
- [Docker](https://docs.docker.com/engine/install/ubuntu/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/#install-using-native-package-management)
- [microk8s](https://microk8s.io/)
- [krew](https://krew.sigs.k8s.io/docs/user-guide/setup/install/)
- [helm](https://helm.sh/docs/intro/install/#from-snap)

Following are commands to install from command line.

```bash
snap install kubectl --classic
sudo snap install microk8s --classic
sudo snap install helm --classic

# for Docker and Krew installation please refer to official guide

# Add user group. Replace USER with your local username
sudo usermod -a -G microk8s USER

# Enable necessary plugin
microk8s enable dashboard istio storage

# To monitor kubenertes resource use this command. Open url and use default token to access dashboard.
microk8s dashboard-proxy
```

Add an alias to simplify invoke namespaced microk8s (append to ~/.bash_aliases):

```text
alias kubectl='microk8s kubectl'
```

Deployment setup:

- Run `git clone https://github.com/hyperledger-labs/hlf-operator.git` and checkout to `v1.5.1`
- Change directory to `hlf-operator` repository. This will serve as working directory.
- Install [istio](https://github.com/hyperledger-labs/hlf-operator/tree/2ab0262e1776621eed19beedf9bf5fa5f397b5b2#install-istio)
- Install operator: `helm install hlf-operator ./chart/hlf-operator`
- Install plugin: `kubectl krew install hlf`
- Before proceed, we need to patch hlf command tools (plugin) to increase block size.
  - Goto line of code like example in [here](https://github.com/hyperledger-labs/hlf-operator/blob/94c333140de92a1125d9fba8192396a01afbed4b/controllers/testutils/channel.go#L183) then update `AbsoluteMaxBytes` to `10 * 10124 * 1024`.
  - Goto `kubectl-hlf` directory and run `go build -o kubectl-hlf main.go`
  - Find your local path of `kubectl-hlf` then replace (or rename original for backup) with previous patched build
- Copy all fies in `chaincodes` directory to `fixtures/chaincodes`. Example: `/home/ubuntu/github/hlf-operator/fixtures/chaincodes`
- Create directory `scripts` and copy all files from `scripts` into there. Example `/home/ubuntu/github/hlf-operator/scripts`
- From `scripts/deploy-fabric.sh`, change `KUBE_CONFIG_PATH` and `KUBECONFIG` to your local path then run the script
- After running `deploy-fabric.sh`, there will be network config file `org1.yaml`. This config will be use in `blockchain-api`, please note the path to the file.

## How to clean up resource

```bash
export KUBECONFIG=/var/snap/microk8s/current/credentials/client.config # Change to your local path
export KUBE_CONFIG_PATH=/var/snap/microk8s/current/credentials/client.config # Change to your local path

kubectl delete fabricorderernodes.hlf.kungfusoftware.es --all-namespaces --all
kubectl delete fabricpeers.hlf.kungfusoftware.es --all-namespaces --all
kubectl delete fabriccas.hlf.kungfusoftware.es --all-namespaces --all
```

## How to redeploy setup

Steps needed to redeploy:

- Update Persistent Volumes reclaim policy from `Delete` to `Retain` for:
  - `default/org1-peer0--couchdb`
  - `default/org1-peer0--chaincode`

- Clean up existing resources

- Re-enable PVC resource by remove reference of old uid by running:

  `kubectl patch pv YOUR_PV_NAME --type json -p '[{"op": "remove", "path": "/spec/claimRef/uid"}]'`

- Bump `SEQUENCE` number of chaincode in `scripts/deploy-fabric.sh` and re-run the setup script

### Changing reclaim policy of a PersistentVolume

See: <https://kubernetes.io/docs/tasks/administer-cluster/change-pv-reclaim-policy/#changing-the-reclaim-policy-of-a-persistentvolume>

```bash
# list current pv
kubectl get pv

# patch pv claim policy to Retain (this will keep data after resource got deleted)
kubectl patch pv YOUR_PV_NAME -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'

# after resource deleted, pv status become `released`, we need to reactive with this script to become `available`
kubectl patch pv YOUR_PV_NAME --type json -p '[{"op": "remove", "path": "/spec/claimRef/uid"}]'
```

## How to invoke chaincode from command line

Following is example how to invoke chaincode through command line. Change parameters as necessary.

```bash
#!/bin/bash
export KUBECONFIG=/var/snap/microk8s/current/credentials/client.config # Change to your local path
export CHANNEL_ID="ecertplatform"
export CHAINCODE_NAME="certificate_info"
export CERT_KEY=d230d22e-b420-4e54-af8d-868d8d748374
export CERT_SIGN=NONE
export TEMPLATE_KEY=cbe91541-4b62-4847-adc1-c25259162a5c
export ISSUER_ID=40c73a35-36c9-47c3-a89e-987781860b7f

# Issue Certificate
kubectl hlf chaincode invoke \
    --config=org1.yaml \
    --user=admin \
    --peer=org1-peer0.default \
    --chaincode="${CHAINCODE_NAME}" \
    --channel=${CHANNEL_ID} \
    --fcn=IssueCertificate \
    -a "${CERT_KEY}" \
    -a "${CERT_SIGN}" \
    -a "${TEMPLATE_KEY}" \
    -a "Fintech Training" \
    -a "How is DeFi Transforming Finance?" \
    -a "Aashman Anand Vyas" \
    -a "Aashman@academy.hk" \
    -a "${ISSUER_ID}" \
    -a 'My Academy' \
    -a '2022-02-02 17:00:00' \
    -a '{"attrib001":"Custom Attribute Value 001"}'

# Query Certificate
kubectl hlf chaincode query \
    --config=org1.yaml \
    --user=admin \
    --peer=org1-peer0.default \
    --chaincode="${CHAINCODE_NAME}" \
    --channel=${CHANNEL_ID} \
    --fcn=QueryCertificate \
    -a "${CERT_KEY}"

# Revoke Certificate
kubectl hlf chaincode invoke \
    --config=org1.yaml \
    --user=admin \
    --peer=org1-peer0.default \
    --chaincode="${CHAINCODE_NAME}" \
    --channel=${CHANNEL_ID} \
    --fcn=RevokeCertificate \
    -a "${CERT_KEY}"

# Get History of Certificate
kubectl hlf chaincode query \
    --config=org1.yaml \
    --user=admin \
    --peer=org1-peer0.default \
    --chaincode="${CHAINCODE_NAME}" \
    --channel=${CHANNEL_ID} \
    --fcn=GetHistoryForKey \
    -a "${CERT_KEY}"
```
