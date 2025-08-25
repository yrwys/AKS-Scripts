#!/bin/bash

echo "------------------------------------------------------------------------------------------------------------------------------------------------------------------"

start=$((CP_NODES + 1))
end=$((CP_NODES + WORKER_NODES))

declare -A node_disks

for ((i=start; i<=end; i++)); do
  idx=$(printf "%02d" "$i")
  node_ip_var="P${idx}_IP"
  node_name_var="P${idx}_NAME"
  node_ip="${!node_ip_var:-}"
  node_name="${!node_name_var:-}"

  echo "Disk Directory of ${node_name} (${node_ip}):"

#   talosctl wipe disk sdb --nodes "$node_ip"
#   talosctl wipe disk sdc --nodes "$node_ip"
#   talosctl wipe disk sdd --nodes "$node_ip"
#   talosctl wipe disk sde --nodes "$node_ip"
#   talosctl wipe disk sdf --nodes "$node_ip"
#   talosctl wipe disk sdg --nodes "$node_ip"

  talosctl ls /dev/disk/by-id -l --nodes "$node_ip"

  echo
  read -p "No. of disks to mount into ${node_name}: " disk_count

  disks=()
  for ((d=1; d<=disk_count; d++)); do
    read -p "Disk ${d} name (scsi-xxxxxxxxxxxxxxxxxxxx): " disk_name
    disks+=("$disk_name")
  done

  node_disks["$node_name"]="${disks[*]}"

  echo "------------------------------------------------------------------------------------------------------------------------------------------------------------------"
done

for node_name in "${!node_disks[@]}"; do
  disks_str="${node_disks[$node_name]}"
  IFS=' ' read -r -a disks <<< "$disks_str"
  disk_count=${#disks[@]}
  filename="${node_name}-DISKS.patch"

  cat > "$filename" <<EOF
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

  for ((j=0; j<disk_count; j++)); do
    disknum=$((j+1))
    cat >> "$filename" <<EOF
      - destination: /var/lib/longhorn/disk${disknum}
        type: bind
        source: /var/lib/longhorn/disk${disknum}
        options:
          - bind
          - rshared
          - rw
EOF
  done

  cat >> "$filename" <<'EOF'
  disks:
EOF

  for ((j=0; j<disk_count; j++)); do
    disknum=$((j+1))
    cat >> "$filename" <<EOF
      - device: /dev/disk/by-id/${disks[$j]}
        partitions:
          - mountpoint: /var/lib/longhorn/disk${disknum}
EOF
  done

  echo "$filename has been created."
done

echo "------------------------------------------------------------------------------------------------------------------------------------------------------------------"