#!/bin/bash

PATCH_FILE="cert-rotation.patch"

for i in $(seq 1 $CP_NODES); do
    node_ip_var="P$(printf "%02d" $i)_IP"
    node_ip=${!node_ip_var}

    if [[ -n "$node_ip" ]]; then
        talosctl --nodes "$node_ip" patch machineconfig --patch @"$PATCH_FILE"
    fi
done

for i in $(seq 4 $((WORKER_NODES+3))); do
    node_ip_var="P$(printf "%02d" $i)_IP"
    node_ip=${!node_ip_var}

    if [[ -n "$node_ip" ]]; then
        talosctl --nodes "$node_ip" patch machineconfig --patch @"$PATCH_FILE"
    fi
done

kubectl apply -f https://raw.githubusercontent.com/alex1989hu/kubelet-serving-cert-approver/main/deploy/standalone-install.yaml
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

