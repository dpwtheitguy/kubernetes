#!/usr/bin/env bash
# Purpose: Configure sysctl and iptables rules for Kubernetes labs on EC2
# Standards: Google Shell Style, PEP20, SPLUNK CIM, PowerShell Verb-Noun
# Author: world-class scripter™

set -euo pipefail

readonly SYSCTL_CONFIG="/etc/sysctl.d/k8s.conf"
readonly IPTABLES_CONFIG="/etc/iptables/rules.v4"
readonly SYSTEMD_UNIT="/etc/systemd/system/iptables-restore.service"
readonly NODEPORT_RANGE_START="30000"
readonly NODEPORT_RANGE_END="32767"
readonly CIDR_RANGES=("10.244.0.0/16" "192.168.0.0/16")
readonly CNI_PORTS_UDP=(4789 8472)
readonly CNI_PORTS_TCP=(179)
readonly SERVICE_PORTS_TCP=(6443 10250)

IPTABLES_DIR="$(dirname "$IPTABLES_CONFIG")"
readonly IPTABLES_DIR

require-Root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "event=permission_check result=failure reason=root_required" >&2
    exit 1
  fi
  echo "event=permission_check result=success"
}

setup-Iptables() {
  if ! command -v iptables &> /dev/null; then
    echo "event=iptables_check result=missing action=install status=started"
    if command -v yum &> /dev/null; then
      yum install -y iptables
    elif command -v dnf &> /dev/null; then
      dnf install -y iptables
    elif command -v apt-get &> /dev/null; then
      apt-get update && apt-get install -y iptables
    else
      echo "event=iptables_install result=failure reason=unsupported_package_manager" >&2
      exit 1
    fi
    echo "event=iptables_check result=installed"
  else
    echo "event=iptables_check result=present"
  fi
}

set-SysctlSettings() {
  echo "event=sysctl_config action=set target=$SYSCTL_CONFIG status=started"
  cat <<EOF > "$SYSCTL_CONFIG"
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
  sysctl --system
  echo "event=sysctl_config action=set target=$SYSCTL_CONFIG status=completed"
}

initialize-Iptables() {
  echo "event=iptables_init action=flush status=started"
  iptables -F
  iptables -X
  echo "event=iptables_init action=flush status=completed"
}

set-FirewallRules() {
  echo "event=iptables_rules action=set status=started"

  iptables -A INPUT -i lo -j ACCEPT
  iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
  iptables -A FORWARD -m physdev --physdev-is-bridged -j ACCEPT

  for cidr in "${CIDR_RANGES[@]}"; do
    iptables -A INPUT -s "$cidr" -j ACCEPT
  done

  for port in "${SERVICE_PORTS_TCP[@]}"; do
    iptables -A INPUT -p tcp --dport "$port" -j ACCEPT
  done

  for port in "${CNI_PORTS_UDP[@]}"; do
    iptables -A INPUT -p udp --dport "$port" -j ACCEPT
  done

  for port in "${CNI_PORTS_TCP[@]}"; do
    iptables -A INPUT -p tcp --dport "$port" -j ACCEPT
  done

  iptables -A INPUT -p tcp --dport "${NODEPORT_RANGE_START}:${NODEPORT_RANGE_END}" -j ACCEPT
  iptables -A INPUT -p icmp -j ACCEPT
  iptables -A INPUT -j DROP

  echo "event=iptables_rules action=set status=completed"
}

save-Iptables() {
  echo "event=iptables_save action=write target=$IPTABLES_CONFIG status=started"
  mkdir -p "$IPTABLES_DIR"
  iptables-save > "$IPTABLES_CONFIG"
  echo "event=iptables_save action=write target=$IPTABLES_CONFIG status=completed"
}

enable-IptablesBootRestore() {
  echo "event=iptables_boot_restore action=configure target=$SYSTEMD_UNIT status=started"
  cat <<EOF > "$SYSTEMD_UNIT"
[Unit]
Description=Restore iptables rules
DefaultDependencies=no
Before=network-pre.target
Wants=network-pre.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/iptables-restore < $IPTABLES_CONFIG
ExecReload=/usr/sbin/iptables-restore < $IPTABLES_CONFIG
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

  chmod 644 "$SYSTEMD_UNIT"
  systemctl daemon-reexec
  systemctl daemon-reload
  systemctl enable iptables-restore.service
  echo "event=iptables_boot_restore action=configure status=completed"
}

main() {
  require-Root
  setup-Iptables
  set-SysctlSettings
  initialize-Iptables
  set-FirewallRules
  save-Iptables
  enable-IptablesBootRestore
  echo "event=script_complete message='Kubernetes iptables and sysctl configuration applied successfully.'"
}

main
