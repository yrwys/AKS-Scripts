#!/bin/bash

declare -a controlplane_mgmt_ips
declare -a controlplane_hostnames
declare -a controlplane_talos_ips
declare -a controlplane_interfaces1
declare -a controlplane_interfaces2
declare -a controlplane_disks
declare -a worker_mgmt_ips
declare -a worker_hostnames
declare -a worker_talos_ips
declare -a worker_interfaces1
declare -a worker_interfaces2
declare -a worker_disks

talosctl gen secrets -o secrets.yaml

echo "------------------------------------------------------------------------------------------------------------------------------------------------------------------"

read -p "Cluster name: " cluster_name

echo "------------------------------------------------------------------------------------------------------------------------------------------------------------------"

read -p "Virtual IP (VIP): " vip

echo "------------------------------------------------------------------------------------------------------------------------------------------------------------------"

talosctl gen config --with-secrets secrets.yaml --kubernetes-version 1.32.5 $cluster_name https://$vip:6443

echo "------------------------------------------------------------------------------------------------------------------------------------------------------------------"

read -p "No. of control plane nodes: " cp_nodes

for ((i=1; i<=cp_nodes; i++)); do
    suffix=$(printf "%d%s" "$i" "$(if [[ $i -eq 1 ]]; then echo "st"; elif [[ $i -eq 2 ]]; then echo "nd"; elif [[ $i -eq 3 ]]; then echo "rd"; else echo "th"; fi)")
    read -p "$suffix control plane node management IP: " ip
    controlplane_mgmt_ips+=("$ip")
done

for ((i=1; i<=cp_nodes; i++)); do
    suffix=$(printf "%d%s" "$i" "$(if [[ $i -eq 1 ]]; then echo "st"; elif [[ $i -eq 2 ]]; then echo "nd"; elif [[ $i -eq 3 ]]; then echo "rd"; else echo "th"; fi)")
    read -p "$suffix control plane node hostname: " hostname
    controlplane_hostnames+=("$hostname")
done

for ((i=0; i<cp_nodes; i++)); do
    read -p "${controlplane_hostnames[$i]} Talos IP: " ip
    controlplane_talos_ips+=("$ip")
done

echo "------------------------------------------------------------------------------------------------------------------------------------------------------------------"

read -p "No. of worker nodes: " worker_nodes

for ((i=1; i<=worker_nodes; i++)); do
    suffix=$(printf "%d%s" "$i" "$(if [[ $i -eq 1 ]]; then echo "st"; elif [[ $i -eq 2 ]]; then echo "nd"; elif [[ $i -eq 3 ]]; then echo "rd"; else echo "th"; fi)")
    read -p "$suffix worker node management IP: " ip
    worker_mgmt_ips+=("$ip")
done

for ((i=1; i<=worker_nodes; i++)); do
    suffix=$(printf "%d%s" "$i" "$(if [[ $i -eq 1 ]]; then echo "st"; elif [[ $i -eq 2 ]]; then echo "nd"; elif [[ $i -eq 3 ]]; then echo "rd"; else echo "th"; fi)")
    read -p "$suffix worker node hostname: " hostname
    worker_hostnames+=("$hostname")
done

for ((i=0; i<worker_nodes; i++)); do
    read -p "${worker_hostnames[$i]} Talos IP: " ip
    worker_talos_ips+=("$ip")
done

echo "------------------------------------------------------------------------------------------------------------------------------------------------------------------"

read -p "Gateway IP: " gateway

echo "------------------------------------------------------------------------------------------------------------------------------------------------------------------"

process_controlplane_nodes() {
    local hostname="$1"
    local mgmt_ip="$2"
    local index="$3"

    echo -e "$hostname Available Interfaces ($mgmt_ip):"
    talosctl get links --nodes "$mgmt_ip"

    echo -e "\n$hostname Available Disks ($mgmt_ip):"
    talosctl get disks --nodes "$mgmt_ip"

    echo ""
    read -p "$hostname 1st interface: " int1
    read -p "$hostname 2nd interface: " int2
    read -p "$hostname disk: " disk

    controlplane_interfaces1[$index]="$int1"
    controlplane_interfaces2[$index]="$int2"
    controlplane_disks[$index]="$disk"

    echo "------------------------------------------------------------------------------------------------------------------------------------------------------------------"
}

process_worker_nodes() {
    local hostname="$1"
    local mgmt_ip="$2"
    local index="$3"

    echo -e "$hostname Available Interfaces ($mgmt_ip):"
    talosctl get links --nodes "$mgmt_ip"

    echo -e "\n$hostname Available Disks ($mgmt_ip):"
    talosctl get disks --nodes "$mgmt_ip"

    echo ""
    read -p "$hostname 1st interface: " int1
    read -p "$hostname 2nd interface: " int2
    read -p "$hostname disk: " disk

    worker_interfaces1[$index]="$int1"
    worker_interfaces2[$index]="$int2"
    worker_disks[$index]="$disk"

    echo "------------------------------------------------------------------------------------------------------------------------------------------------------------------"
}

for ((i=0; i<cp_nodes; i++)); do
    process_controlplane_nodes "${controlplane_hostnames[$i]}" "${controlplane_mgmt_ips[$i]}" "$i"
done

for ((i=0; i<worker_nodes; i++)); do
    process_worker_nodes "${worker_hostnames[$i]}" "${worker_mgmt_ips[$i]}" "$i"
done

generate_controlplane_yaml() {
    local hostname="$1"
    local address="$2"
    local gateway="$3"
    local interface1="$4"
    local interface2="$5"
    local vip="$6"
    local disk="$7"
    local filename="$8"

    cat > controlplane.patch <<EOF
machine:
  network:
    hostname: $hostname
    interfaces:
      - interface: bond0
        addresses:
          - $address/24
        routes:
          - network: 0.0.0.0/0
            gateway: $gateway
        bond:
          interfaces:
            - $interface1
            - $interface2
        dhcp: false
        vip:
          ip: $vip
    nameservers:
      - 1.1.1.1
      - 8.8.8.8
  install:
    disk: /dev/$disk
    image: factory.talos.dev/installer/613e1592b2da41ae5e265e8789429f22e121aab91cb4deb6bc3c0b6262961245:v1.10.5
  nodeLabels:
    node-role.kubernetes.io/controlplane: ""
cluster:
  network:
    cni:
      name: none
  proxy:
    disabled: true
EOF

    talosctl machineconfig patch controlplane.yaml --patch @controlplane.patch --output "$filename"
    rm -f controlplane.patch
}

generate_worker_yaml() {
    local hostname="$1"
    local address="$2"
    local gateway="$3"
    local interface1="$4"
    local interface2="$5"
    local disk="$6"
    local filename="$7"

    cat > worker.patch <<EOF 
machine:
  network:
    hostname: $hostname
    interfaces:
      - interface: bond0
        addresses:
          - $address/24
        routes:
          - network: 0.0.0.0/0
            gateway: $gateway
        bond:
          interfaces:
            - $interface1
            - $interface2
        dhcp: false
    nameservers:
      - 1.1.1.1
      - 8.8.8.8
  install:
    disk: /dev/$disk
    image: factory.talos.dev/installer/613e1592b2da41ae5e265e8789429f22e121aab91cb4deb6bc3c0b6262961245:v1.10.5
cluster:
  network:
    cni:
      name: none
EOF

    talosctl machineconfig patch worker.yaml --patch @worker.patch --output "$filename"
    rm -f worker.patch
}

for ((i=0; i<cp_nodes; i++)); do
    filename="${controlplane_hostnames[$i]}.yaml"
    generate_controlplane_yaml \
        "${controlplane_hostnames[$i]}" \
        "${controlplane_talos_ips[$i]}" \
        "$gateway" \
        "${controlplane_interfaces1[$i]}" \
        "${controlplane_interfaces2[$i]}" \
        "$vip" \
        "${controlplane_disks[$i]}" \
        "$filename"
    echo "$filename has been created."
done

for ((i=0; i<worker_nodes; i++)); do
    filename="${worker_hostnames[$i]}.yaml"
    generate_worker_yaml \
        "${worker_hostnames[$i]}" \
        "${worker_talos_ips[$i]}" \
        "$gateway" \
        "${worker_interfaces1[$i]}" \
        "${worker_interfaces2[$i]}" \
        "${worker_disks[$i]}" \
        "$filename"
    echo "$filename has been created."
done

if [[ $cp_nodes -ge 1 ]]; then
    talosctl config endpoint \
        "${controlplane_talos_ips[@]:0:$cp_nodes}" \
        --talosconfig=./talosconfig
    # talosctl config merge ./talosconfig
    echo "talosctl endpoints configured successfully."
else
    echo "No control plane nodes defined!"
fi

env_file="${cluster_name}-ENV.sh"

echo "export VIP=$vip" >> "${env_file}"

node_index=1

echo "export CP_NODES=$cp_nodes" >> "${env_file}"

for ((i=0; i<cp_nodes; i++)); do
    padded=$(printf "P%02d" "$node_index")
    echo "export ${padded}_IP=${controlplane_talos_ips[$i]}" >> "${env_file}"
    echo "export ${padded}_NAME=${controlplane_hostnames[$i]}" >> "${env_file}"
    ((node_index++))
done

echo "export WORKER_NODES=$worker_nodes" >> "${env_file}"

for ((i=0; i<worker_nodes; i++)); do
    padded=$(printf "P%02d" "$node_index")
    echo "export ${padded}_IP=${worker_talos_ips[$i]}" >> "${env_file}"
    echo "export ${padded}_NAME=${worker_hostnames[$i]}" >> "${env_file}"
    ((node_index++))
done

echo -e "\nEnvironment variables saved to: ${env_file}"
echo "Run this command: source ${env_file}"