#!/bin/bash

workers=$(kubectl get nodes --no-headers | awk '!/control-plane/ {print $1}')

for node in $workers; do
    kubectl label node "$node" node-role.kubernetes.io/worker= --overwrite
done

controlplanes=($(kubectl get nodes --no-headers | awk '/control-plane/ {print $1}'))

if [[ -n "${controlplanes[0]}" ]]; then
    kubectl label node "${controlplanes[0]}" bgp-policy-node=enabled
    talosctl reboot --nodes "${controlplanes[0]}"
fi

if [[ -n "${controlplanes[1]}" ]]; then
    kubectl label node "${controlplanes[1]}" bgp-policy-node=enabled
    talosctl reboot --nodes "${controlplanes[1]}"
fi
