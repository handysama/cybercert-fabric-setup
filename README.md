# cybercert-fabric-setup

Hyperledger Fabric setup guide for running CyberCert e-certificate chaincode. The recipe rely on [hlf-operator](https://github.com/hyperledger-labs/hlf-operator) that allow us to setup Fabric quickly.

## How to setup on Debian/Ubuntu

Windows platform is not supported, due to not supported by some open source libraries.

Prerequisite software:

- [go 1.18](https://go.dev/doc/install)
- [snapd](https://snapcraft.io/docs/installing-snapd)
- [Docker](https://docs.docker.com/engine/install/ubuntu/#install-using-the-repository)
- [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/#install-using-native-package-management)
- [microk8s 1.23](https://microk8s.io/docs/getting-started)
- [krew](https://krew.sigs.k8s.io/docs/user-guide/setup/install/)
- [helm](https://helm.sh/docs/intro/install/#from-snap)

Additional software required for channel configuration:

- [jq](https://stedolan.github.io/jq/download/)
- [yq](https://github.com/kislyuk/yq#installation)
- [fabric-binaries](https://github.com/hyperledger/fabric/releases/tag/v2.4.3)

  ```bash
  wget https://github.com/hyperledger/fabric/releases/download/v2.4.3/hyperledger-fabric-linux-amd64-2.4.3.tar.gz
  sudo mkdir /usr/local/fabric-binaries
  sudo tar -C /usr/local/fabric-binaries -xzf hyperledger-fabric-linux-amd64-2.4.3.tar.gz
  ```

Following are commands to install from command line.

```bash
# Setup Docker (please refer to official guide)

# Add user group
sudo usermod -a -G docker $USER

# Install microk8s with last working version
sudo snap install microk8s --classic --channel=1.23/stable

# Add user group. Restart terminal session to take effect
sudo usermod -a -G microk8s $USER
sudo chown -f -R $USER ~/.kube

# Assert microk8s is up
microk8s status --wait-ready

# Enable necessary plugin
microk8s enable dashboard dns istio storage

sudo snap install kubectl --classic
sudo snap install helm --classic

# Setup Krew installation (please refer to official guide)
```

Add these lines to PATH environment variable (~/.bashrc)

```bash
export KUBECONFIG=/var/snap/microk8s/current/credentials/client.config # Change to your local path
export PATH="${KREW_ROOT:-$HOME/.krew}/bin:/usr/local/fabric-binaries/bin:$PATH"
```

Add an alias for microk8s kubectl (append to ~/.bash_aliases):

```bash
alias kubectl='microk8s kubectl'
```

Deployment setup:

- Clone `hlf-operator`

  ```bash
  git clone https://github.com/hyperledger-labs/hlf-operator.git && cd hlf-operator
  git checkout v1.5.1
  ```

- Install istio. See: <https://github.com/hyperledger-labs/hlf-operator/tree/2ab0262e1776621eed19beedf9bf5fa5f397b5b2#install-istio>

  ```bash
  kubectl apply -f ./hack/istio-operator/crds/*
  helm template ./hack/istio-operator/ \
    --set hub=docker.io/istio \
    --set tag=1.8.0 \
    --set operatorNamespace=istio-operator \
    --set watchedNamespaces=istio-system | kubectl apply -f -

  kubectl create ns istio-system
  kubectl apply -n istio-system -f ./hack/istio-operator.yaml
  ```

- Install operator

  ```bash
  helm install hlf-operator ./chart/hlf-operator
  ```

- Install plugin

  ```bash
  kubectl krew install hlf
  ```

- Patch kubectl-hlf command tools (plugin) to increase block size.
  - Goto line of code like example in [here](https://github.com/hyperledger-labs/hlf-operator/blob/94c333140de92a1125d9fba8192396a01afbed4b/controllers/testutils/channel.go#L183) then update `AbsoluteMaxBytes` to `10 * 10124 * 1024`.

    ```go
    // Before
    BatchSize: orderer.BatchSize{
      MaxMessageCount:   100,
      AbsoluteMaxBytes:  1024 * 1024,
      PreferredMaxBytes: 512 * 1024,
    }
    // After
    BatchSize: orderer.BatchSize{
      MaxMessageCount:   100,
      AbsoluteMaxBytes:  10 * 1024 * 1024, // increase limit
      PreferredMaxBytes: 512 * 1024,
    }
    ```

  - Build patched `kubectl-hlf`

    ```bash
    cd kubectl-hlf
    go build -o kubectl-hlf main.go
    ```

  - Find your local path of `kubectl-hlf` and change directory to there

    Example local path `/home/$USER/.krew/store/hlf/v1.8.4/kubectl-hlf`

    Example change dir to `/home/$USER/.krew/store/hlf/`

    ```bash
    cd ~/.krew/store/hlf
    ```

  - Download official kubectl-hlf v1.5.1 and extract the zip file

    ```bash
    wget https://github.com/hyperledger-labs/hlf-operator/releases/download/v1.5.1/hlf-operator_1.5.1_linux_amd64.zip
    unzip -d v1.5.1 hlf-operator_1.5.1_linux_amd64.zip
    ```

  - Move previous build of `kubectl-hlf` to `v1.5.1` directory

    ```bash
    cp ~/hlf-operator/kubectl-hlf/kubectl-hlf ~/.krew/store/hlf/v1.5.1/kubectl-hlf
    ```

  - Update symlink of `kubectl-hlf` point to `v1.5.1`

    ```bash
    ln -sf ~/.krew/store/hlf/v1.5.1/kubectl-hlf ~/.krew/bin/kubectl-hlf

    # Assert symlink updated
    ls -al ~/.krew/bin/
    ```

- Copy all fies in `chaincodes` directory to `fixtures/chaincodes`
  - Example: `/home/ubuntu/github/hlf-operator/fixtures/chaincodes`
- Create directory `scripts` and copy all files from `scripts` into there
  - Example `/home/ubuntu/github/hlf-operator/scripts`
- From `scripts/deploy-fabric.sh`, change `KUBE_CONFIG_PATH` and `KUBECONFIG` to your local path then run the script
- After running `deploy-fabric.sh`, there will be network config file `org1.yaml`. This config will be use in `blockchain-api`, please note the path to the file.

## Dashboard

Dashboard is important feature to allow us monitor and managing kubernetes cluster.

Use this command to run dashboard on separate terminal. Open url in web browser and use the token to access dashboard.

```bash
microk8s dashboard-proxy
```

## How to clean up resource

```bash
export KUBECONFIG=/var/snap/microk8s/current/credentials/client.config # Change to your local path
export KUBE_CONFIG_PATH=/var/snap/microk8s/current/credentials/client.config # Change to your local path

kubectl delete fabricorderernodes.hlf.kungfusoftware.es --all-namespaces --all
kubectl delete fabricpeers.hlf.kungfusoftware.es --all-namespaces --all
kubectl delete fabriccas.hlf.kungfusoftware.es --all-namespaces --all
```

## How to redeploy setup

### Steps for redeploy

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
