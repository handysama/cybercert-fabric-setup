# Renew Certificate

The platform will have annual refresh certificate for standard security. Suggested the renew certificate done 2 weeks before expiry date and perform manually. Admin platform need to keep track the expiry date and schedule for renew certificate. The process will takes some time (~10 minutes) and kubernetes cluster will need to go down around for moment. Prepare 1 hour time slot for renew certificate process.

## Microk8s

Use `refresh-cert` command to check and refresh certificate.

```bash
# Check cert expiry
sudo microk8s refresh-certs -c

# Example response:
# The CA certificate will expire in 3629 days.
# The server certificate will expire in 347 days.
# The front proxy client certificate will expire in 347 days.

# refresh server and front proxy client certificate
sudo microk8s refresh-certs -e server.crt
sudo microk8s refresh-certs -e front-proxy-client.crt
```

## Hyperledger Fabric

- Open `org1.yaml` (exported hyperledger network config).
- Go to path `organizations.Org1MSP.users.admin.cert.pem` and copy value to new file `cert.pem`

  ```yaml
  # Example org1.yaml content (edited for brevity)
  organizations:
    Org1MSP:
      cryptoPath: /tmp/cryptopath
      mspid: Org1MSP
      orderers: []
      peers:
      - org1-peer0.default
      users:
        admin:
          cert:
          # Copy pem value below to new file `cert.pem`
            pem: |
              -----BEGIN CERTIFICATE-----
              XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
              XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
              XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
              XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
              XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
              XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
              XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
              XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
              XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
              XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
              XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
              XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
              XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
              -----END CERTIFICATE-----
          key:
            pem: |
              -----BEGIN PRIVATE KEY-----
              XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
              XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
              XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
              -----END PRIVATE KEY-----
  ```

- Run `openssl` to check expiry dates:

  ```bash
  # check x509 cert from org1.yaml -> organizations.Org1MSP.users.admin.cert.pem
  # export to some text file and use openssl to decode it

  openssl x509 -in cert.pem -text -noout
  ```

- If certificate near expiry date. Stop `blockchain-api` service then run hlf renew command:

  ```bash
  # renew peer
  PEER_NAME=org1-peer0
  PEER_NS=default
  kubectl hlf peer renew --name=$PEER_NAME --namespace=$PEER_NS

  # renew orderer
  ORDERER_NAME=ord-node1
  ORDERER_NS=default
  kubectl hlf ordnode renew --name=$ORDERER_NAME --namespace=$ORDERER_NS
  ```

- After renew finished, export network configuration `org1.yaml`. Copy config file to `blockchain-api` and start blockchain api services.

  ```bash
  kubectl hlf inspect --output org1.yaml -o Org1MSP -o OrdererMSP
  ```

## References

- <https://microk8s.io/docs/command-reference#heading--microk8s-refresh-certs>
- <https://hyperledger.github.io/bevel-operator-fabric/docs/operator-guide/renew-certificates>
