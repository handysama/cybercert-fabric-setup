# cybercert-fabric-setup

Hyperledger Fabric setup guide for running CyberCert e-certificate chaincode service. We use [Hyperledger Fabric Operator](https://github.com/hyperledger/bevel-operator-fabric/) to deploy Fabric cluster conveniently.

## Docker hub account

Account on [Docker hub](https://hub.docker.com/) is required to publish chaincode image that use to deploy chaincode as external service. For setup example, we already prepared default public repository.

Alternatively, you can publish your own image by sign up for docker hub account. After succeed publishing docker image, you must change `CHAINCODE_IMAGE` env in deploy chaincode script to your repository path.

## How to setup on Debian/Ubuntu

Windows platform is not supported due to some libraries is not natively available on the platform.

Prerequisite software:

- [go 1.18](https://go.dev/doc/install)
- [snapd](https://snapcraft.io/docs/installing-snapd)
- [Docker](https://docs.docker.com/engine/install/ubuntu/#install-using-the-repository)
- [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/#install-using-native-package-management)
- [microk8s](https://microk8s.io/docs/getting-started)
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
sudo snap install microk8s --classic --channel=1.27/stable

# Add user group. Restart terminal session to take effect
sudo usermod -a -G microk8s $USER
sudo chown -f -R $USER ~/.kube

# Assert microk8s is up
microk8s status --wait-ready

# Enable necessary plugin
microk8s enable dashboard dns istio hostpath-storage

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
  git clone https://github.com/hyperledger/bevel-operator-fabric.git && cd bevel-operator-fabric
  git checkout v1.9.2
  ```

- Install helm hlf-operator

  ```bash
  helm repo add kfs https://kfsoftware.github.io/hlf-helm-charts --force-update
  helm install hlf-operator --version=1.9.0 -- kfs/hlf-operator
  ```

- Install plugin

  ```bash
  kubectl krew install hlf
  ```

- Install istio. See: <https://github.com/hyperledger/bevel-operator-fabric/tree/25c0a86b8aa2c710ee76287e0ce31f359ab6874b#install-istio>

  ```bash
  curl -L https://istio.io/downloadIstio | sh -

  kubectl create namespace istio-system

  istioctl operator init

  kubectl apply -f - <<EOF
  apiVersion: install.istio.io/v1alpha1
  kind: IstioOperator
  metadata:
    name: istio-gateway
    namespace: istio-system
  spec:
    addonComponents:
      grafana:
        enabled: false
      kiali:
        enabled: false
      prometheus:
        enabled: false
      tracing:
        enabled: false
    components:
      ingressGateways:
        - enabled: true
          k8s:
            hpaSpec:
              minReplicas: 1
            resources:
              limits:
                cpu: 500m
                memory: 512Mi
              requests:
                cpu: 100m
                memory: 128Mi
            service:
              ports:
                - name: http
                  port: 80
                  targetPort: 8080
                  nodePort: 30949
                - name: https
                  port: 443
                  targetPort: 8443
                  nodePort: 30950
              type: NodePort
          name: istio-ingressgateway
      pilot:
        enabled: true
        k8s:
          hpaSpec:
            minReplicas: 1
          resources:
            limits:
              cpu: 300m
              memory: 512Mi
            requests:
              cpu: 100m
              memory: 128Mi
    meshConfig:
      accessLogFile: /dev/stdout
      enableTracing: false
      outboundTrafficPolicy:
        mode: ALLOW_ANY
    profile: default

  EOF
  ```

- Configure internal DNS. See: <https://github.com/hyperledger/bevel-operator-fabric/tree/25c0a86b8aa2c710ee76287e0ce31f359ab6874b#configure-internal-dns>

  ```bash
  CLUSTER_IP=$(kubectl -n istio-system get svc istio-ingressgateway -o json | jq -r .spec.clusterIP)
  kubectl apply -f - <<EOF
  kind: ConfigMap
  apiVersion: v1
  metadata:
    name: coredns
    namespace: kube-system
  data:
    Corefile: |
      .:53 {
          errors
          health {
            lameduck 5s
          }
          rewrite name regex (.*)\.localho\.st host.ingress.internal
          hosts {
            ${CLUSTER_IP} host.ingress.internal
            fallthrough
          }
          ready
          kubernetes cluster.local in-addr.arpa ip6.arpa {
            pods insecure
            fallthrough in-addr.arpa ip6.arpa
            ttl 30
          }
          prometheus :9153
          forward . /etc/resolv.conf {
            max_concurrent 1000
          }
          cache 30
          loop
          reload
          loadbalance
      }
  EOF
  ```

- Add cluster ip to `etc/hosts`

  ```bash
  # Output cluster ip to be added into `etc/hosts`
  kubectl -n istio-system get svc istio-ingressgateway -o json | jq -r .spec.clusterIP

  # Edit `etc/hosts` and append CLUSTER_IP to the list
  sudo nano etc/hosts
  ```

  Example edited content, replace CLUSTER_IP from previous output:

  ```text
  127.0.0.1   localhost
  CLUSTER_IP  org1-ca.localho.st
  CLUSTER_IP  peer0-org1.localho.st
  CLUSTER_IP  ord-ca.localho.st
  CLUSTER_IP  orderer0-ord.localho.st
  ```

- From this repository, copy all files in `scripts` to cloned `hlf-operator` repository with path `scripts`
- From `scripts/deploy-fabric.sh`, change `KUBE_CONFIG_PATH` and `KUBECONFIG` to your local path then run the script
- `cd` to cloned `hlf-operator` repository
- Run `./scripts/deploy-fabric.sh`
- Run `./scripts/deploy-cc-certinfo.sh` to deploy `certificate-info` chaincode
- Run `./scripts/deploy-cc-certtemplate.sh` to deploy `certificate-template` chaincode
- Run `./scripts/deploy-cc-tokenregistry.sh` to deploy `token-registry` chaincode
- There will be exported network config file `org1.yaml`. This config will be use in `blockchain-api`, please note the path to the file to set `ORG1_HLF_CONFIG` env.

## Dashboard

Dashboard is important feature to allow us monitor and managing kubernetes cluster.

Use this command to run dashboard on separate terminal. Open url in web browser and use the token to access dashboard.

```bash
microk8s dashboard-proxy
```

## How to clean up resource

```bash
#!/bin/bash

shopt -s expand_aliases
alias kubectl='microk8s kubectl'
export CHANNEL_ID=ecertplatform

kubectl delete fabricorderernodes.hlf.kungfusoftware.es --all-namespaces --all
kubectl delete fabricpeers.hlf.kungfusoftware.es --all-namespaces --all
kubectl delete fabriccas.hlf.kungfusoftware.es --all-namespaces --all
kubectl delete fabricchaincode.hlf.kungfusoftware.es --all-namespaces --all
kubectl delete fabricmainchannels --all-namespaces --all
kubectl delete fabricfollowerchannels --all-namespaces --all
kubectl delete secret wallet

# delete channel config
kubectl delete configmap ${CHANNEL_ID}-config -n default
kubectl delete configmap ${CHANNEL_ID}-org1msp-follower-config -n default
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
export CHANNEL_ID="ecertplatform"
export CHAINCODE_NAME="certificate-info"
export CERT_KEY=d230d22e-b420-4e54-af8d-868d8d748374
export CERT_SIGN=NONE
export TEMPLATE_KEY=cbe91541-4b62-4847-adc1-c25259162a5c
export ISSUER_ID=40c73a35-36c9-47c3-a89e-987781860b7f
export ISSUER_NAME=CyberCert

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
    -a "${ISSUER_NAME}" \
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

# Query records with index selector
kubectl hlf chaincode query \
  --config=org1.yaml \
  --user=admin \
  --peer=org1-peer0.default \
  --chaincode="${CHAINCODE_NAME}" \
  --channel=${CHANNEL_ID} \
  --fcn=QueryRecords -a "{\"selector\":{\"issuer_name\":\"${ISSUER_NAME}\"},\"use_index\":[\"_design/indexIssuerNameDoc\",\"indexIssuerName\"]}"
```
