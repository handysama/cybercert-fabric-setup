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
