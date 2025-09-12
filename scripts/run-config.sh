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
declare -a worker_extra_disks

talosctl gen secrets -o secrets.yaml

echo "------------------------------------------------------------------------------------------------------------------------------------------------------------------"

read -p "Cluster name: " cluster_name

echo "------------------------------------------------------------------------------------------------------------------------------------------------------------------"

read -p "Virtual IP (VIP): " vip

echo "------------------------------------------------------------------------------------------------------------------------------------------------------------------"

read -p "Gateway IP: " gateway

echo "------------------------------------------------------------------------------------------------------------------------------------------------------------------"

read -p "Pod Subnets: " pod_subnets

read -p "Service Subnets: " service_subnets

echo "------------------------------------------------------------------------------------------------------------------------------------------------------------------"

talosctl gen config --with-secrets secrets.yaml --kubernetes-version 1.32.5 $cluster_name https://$vip:6443

echo "------------------------------------------------------------------------------------------------------------------------------------------------------------------"

read -p "No. of control plane nodes: " cp_nodes

echo "------------------------------------------------------------------------------------------------------------------------------------------------------------------"

generate_controlplane_yaml() {
    local hostname="$1"
    local address="$2"
    local gateway="$3"
    local interface1="$4"
    local interface2="$5"
    local vip="$6"
    local disk="$7"
    local pod_subnets="$8"
    local service_subnets="$9"
    local filename="${10}"

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
          mode: 802.3ad
          lacpRate: fast
          xmitHashPolicy: layer3+4
          miimon: 100
          updelay: 200
          downdelay: 200
        dhcp: false
        vip:
          ip: $vip
    nameservers:
      - 1.1.1.1
      - 8.8.8.8
  install:
    disk: /dev/disk/by-id/wwn-0x$disk
    image: factory.talos.dev/installer/613e1592b2da41ae5e265e8789429f22e121aab91cb4deb6bc3c0b6262961245:v1.10.5
  nodeLabels:
    node-role.kubernetes.io/controlplane: ""
cluster:
  network:
    cni:
      name: none
    podSubnets:
      - $pod_subnets/16
    serviceSubnets:
      - $service_subnets/12
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
    local extra_disks="$7"
    local num_extra_disks="$8"
    local pod_subnets="$9"
    local service_subnets="${10}"
    local filename="${11}"

    IFS=',' read -ra extra_disk_array <<< "$extra_disks"

    cat > worker.patch <<EOF 
machine:
  kubelet:
    extraMounts:
      - destination: /var/lib/longhorn
        type: bind
        source: /var/lib/longhorn
        options:
          - bind
          - rshared
          - rw
EOF

    for ((k=1; k<=num_extra_disks; k++)); do
        cat >> worker.patch <<EOF
      - destination: /var/lib/longhorn/disk$k
        type: bind
        source: /var/lib/longhorn/disk$k
        options:
          - bind
          - rshared
          - rw
EOF
    done

    cat >> worker.patch <<EOF
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
          mode: 802.3ad
          lacpRate: fast
          xmitHashPolicy: layer3+4
          miimon: 100
          updelay: 200
          downdelay: 200
        dhcp: false
    nameservers:
      - 1.1.1.1
      - 8.8.8.8
  disks:
EOF

    for ((k=0; k<${#extra_disk_array[@]}; k++)); do
        disk_num=$((k+1))
        cat >> worker.patch <<EOF
    - device: /dev/disk/by-id/wwn-0x${extra_disk_array[$k]}
      partitions:
        - mountpoint: /var/lib/longhorn/disk$disk_num
EOF
    done

    cat >> worker.patch <<EOF
  install:
    disk: /dev/disk/by-id/wwn-0x$disk
    image: factory.talos.dev/installer/613e1592b2da41ae5e265e8789429f22e121aab91cb4deb6bc3c0b6262961245:v1.10.5
cluster:
  network:
    cni:
      name: none
    podSubnets:
      - $pod_subnets/16
    serviceSubnets:
      - $service_subnets/12
EOF

    talosctl machineconfig patch worker.yaml --patch @worker.patch --output "$filename"
    rm -f worker.patch
}

process_controlplane_nodes() {
    local hostname="$1"
    local mgmt_ip="$2"
    local talos_ip="$3"
    local index="$4"

    echo -e "$hostname Available Interfaces ($mgmt_ip):"
    talosctl get links --insecure --nodes "$mgmt_ip"

    echo -e "\n$hostname Available Disks ($mgmt_ip):"
    talosctl get disks --insecure --nodes "$mgmt_ip"

    echo ""
    read -p "$hostname 1st interface: " int1
    read -p "$hostname 2nd interface: " int2
    read -p "Disk for Talos installation: " disk

    controlplane_interfaces1[$index]="$int1"
    controlplane_interfaces2[$index]="$int2"
    controlplane_disks[$index]="$disk"

    filename="${hostname}.yaml"
    generate_controlplane_yaml \
        "$hostname" \
        "$talos_ip" \
        "$gateway" \
        "$int1" \
        "$int2" \
        "$vip" \
        "$disk" \
        "$pod_subnets" \
        "$service_subnets" \
        "$filename"

    echo "✅ $hostname.yaml has been created."

    echo ""
    read -p "Do you want to apply the config? (y/n): " choice
    if [[ "$choice" == "y" ]]; then
        talosctl apply-config --insecure --nodes "$mgmt_ip" --file "$filename"
        echo "✅ $hostname.yaml has been applied."
    else
        echo "⚠️  Skipped applying config for $hostname."
    fi

    echo "------------------------------------------------------------------------------------------------------------------------------------------------------------------"
}

process_worker_nodes() {
    local hostname="$1"
    local mgmt_ip="$2"
    local talos_ip="$3"
    local index="$4"

    echo -e "$hostname Available Interfaces ($mgmt_ip):"
    talosctl get links --insecure --nodes "$mgmt_ip"

    echo -e "\n$hostname Available Disks ($mgmt_ip):"
    talosctl get disks --insecure --nodes "$mgmt_ip"

    echo ""
    read -p "$hostname 1st interface: " int1
    read -p "$hostname 2nd interface: " int2
    read -p "Disk for Talos installation: " disk
    read -p "No. of extra disks to mount: " num_extra_disks

    worker_interfaces1[$index]="$int1"
    worker_interfaces2[$index]="$int2"
    worker_disks[$index]="$disk"

    local extra_disks_str=""
    for ((j=1; j<=num_extra_disks; j++)); do
        read -p "Disk $j: " extra_disk
        if [[ $j -eq 1 ]]; then
            extra_disks_str="$extra_disk"
        else
            extra_disks_str="$extra_disks_str,$extra_disk"
        fi
    done
    worker_extra_disks[$index]="$extra_disks_str"

    filename="${hostname}.yaml"
    generate_worker_yaml \
        "$hostname" \
        "$talos_ip" \
        "$gateway" \
        "$int1" \
        "$int2" \
        "$disk" \
        "$extra_disks_str" \
        "$num_extra_disks" \
        "$pod_subnets" \
        "$service_subnets" \
        "$filename"

    echo "✅ $hostname.yaml has been created."

    echo ""
    read -p "Do you want to apply the config? (y/n): " choice
    if [[ "$choice" == "y" ]]; then
        talosctl apply-config --insecure --nodes "$mgmt_ip" --file "$filename"
        echo "✅ $hostname.yaml has been applied."
    else
        echo "⚠️  Skipped applying config for $hostname"
    fi

    echo "------------------------------------------------------------------------------------------------------------------------------------------------------------------"
}

for ((i=1; i<=cp_nodes; i++)); do
    suffix=$(printf "%d%s" "$i" "$(if [[ $i -eq 1 ]]; then echo "st"; elif [[ $i -eq 2 ]]; then echo "nd"; elif [[ $i -eq 3 ]]; then echo "rd"; else echo "th"; fi)")
    read -p "$suffix control plane node management IP: " mgmt_ip
    read -p "$suffix control plane node hostname: " hostname
    read -p "$hostname Talos IP: " talos_ip
    
    controlplane_mgmt_ips+=("$mgmt_ip")
    controlplane_hostnames+=("$hostname")
    controlplane_talos_ips+=("$talos_ip")
    
    echo ""
    process_controlplane_nodes "$hostname" "$mgmt_ip" "$talos_ip" "$((i-1))"
done

read -p "No. of worker nodes: " worker_nodes

echo "------------------------------------------------------------------------------------------------------------------------------------------------------------------"

for ((i=1; i<=worker_nodes; i++)); do
    suffix=$(printf "%d%s" "$i" "$(if [[ $i -eq 1 ]]; then echo "st"; elif [[ $i -eq 2 ]]; then echo "nd"; elif [[ $i -eq 3 ]]; then echo "rd"; else echo "th"; fi)")
    read -p "$suffix worker node management IP: " mgmt_ip
    read -p "$suffix worker node hostname: " hostname
    read -p "$hostname Talos IP: " talos_ip
    
    worker_mgmt_ips+=("$mgmt_ip")
    worker_hostnames+=("$hostname")
    worker_talos_ips+=("$talos_ip")
    
    echo ""
    process_worker_nodes "$hostname" "$mgmt_ip" "$talos_ip" "$((i-1))"
done

if [[ $cp_nodes -ge 1 ]]; then
    talosctl config endpoint \
        "${controlplane_talos_ips[@]:0:$cp_nodes}" \
        --talosconfig=./talosconfig
    talosctl config merge ./talosconfig
else
    echo "No control plane nodes defined!"
fi

env_file="${cluster_name}.sh"

{
    echo "export VIP=$vip"

    for ((i=0; i<cp_nodes; i++)); do
        varname=$(echo "${controlplane_hostnames[$i]}" | tr '-' '_')
        echo "export ${varname}=${controlplane_talos_ips[$i]}"
    done

    for ((i=0; i<worker_nodes; i++)); do
        varname=$(echo "${worker_hostnames[$i]}" | tr '-' '_')
        echo "export ${varname}=${worker_talos_ips[$i]}"
    done

    echo ""
    echo "talosctl config context $cluster_name"
    echo "kubectx admin@$cluster_name"
} > "${env_file}"

echo "⚠️  Run this command: source ${env_file}"