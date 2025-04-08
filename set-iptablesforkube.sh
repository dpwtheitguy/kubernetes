#!/usr/bin/env bash
# Title: Kubernetes Network Setup
# Description: Configure iptables and sysctl for Kubernetes
# Author: You
# Logging: CIM-friendly, PEP-compliant True/False booleans

set -euo pipefail

# Constants
readonly SYSCTL_CONF="/etc/sysctl.d/k8s.conf"
readonly IPTABLES_CONF="/etc/iptables/rules.v4"
readonly IPTABLES_DIR="$(dirname "$IPTABLES_CONF")"

readonly TCP_PORTS=(22 6443 10250 10257 10259)
readonly ETCD_PORT_RANGE="2379:2380"
readonly NODEPORT_RANGE="30000:32767"
readonly UDP_PORTS=(4789 8472)
readonly BGP_PORT=179
readonly CIDRS=("10.244.0.0/16" "192.168.0.0/16")

function check-root() {
  if [[ "$EUID" -ne 0 ]]; then
    echo "event=script-exit app=kubernetes reason=not-root success=False" >&2
    exit 1
  fi
}

function drop-firewall() {
  if command -v ufw &>/dev/null; then
    echo "event=remove-ufw app=iptables action=disabling success=True"
    ufw disable || true
    apt-get remove -y ufw || true
  fi

  if systemctl list-unit-files | grep -q firewalld; then
    echo "event=remove-firewalld app=iptables action=disabling success=True"
    systemctl stop firewalld || true
    systemctl disable firewalld || true
    yum remove -y firewalld || true
  fi
}

function install-iptables() {
  if ! command -v iptables &>/dev/null; then
    echo "event=install app=iptables status=missing success=True"
    if [ -f /etc/os-release ]; then
      source /etc/os-release
      if [[ "$ID" == "amzn" ]]; then
        yum install -y iptables iptables-services
        systemctl enable iptables
        systemctl start iptables
      else
        echo "event=install-failed app=iptables reason=unsupported-distro distro=$ID success=False" >&2
        exit 1
      fi
    fi
  fi
}

function set-sysctl() {
  echo "event=sysctl-config app=kubernetes start=True"
  cat <<EOF > "$SYSCTL_CONF"
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
  sysctl --system
  echo "event=sysctl-config app=kubernetes complete=True"
}

function set-rules() {
  echo "event=iptables-config app=iptables start=True"

  iptables -F
  iptables -X

  iptables -A INPUT -i lo -j ACCEPT
  iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
  iptables -A FORWARD -m physdev --physdev-is-bridged -j ACCEPT

  for cidr in "${CIDRS[@]}"; do
    iptables -A INPUT -s "$cidr" -j ACCEPT
  done

  for port in "${TCP_PORTS[@]}"; do
    iptables -A INPUT -p tcp --dport "$port" -j ACCEPT
  done

  iptables -A INPUT -p tcp --dport "$ETCD_PORT_RANGE" -j ACCEPT

  for port in "${UDP_PORTS[@]}"; do
    iptables -A INPUT -p udp --dport "$port" -j ACCEPT
  done

  iptables -A INPUT -p tcp --dport "$BGP_PORT" -j ACCEPT
  iptables -A INPUT -p tcp --dport "$NODEPORT_RANGE" -j ACCEPT
  iptables -A INPUT -p icmp -j ACCEPT

  iptables -A INPUT -j DROP

  mkdir -p "$IPTABLES_DIR"
  iptables-save > "$IPTABLES_CONF"

  if systemctl list-unit-files | grep -q iptables.service; then
    systemctl enable iptables
    systemctl restart iptables
  fi

  echo "event=iptables-config app=iptables complete=True"
}

function run-setup() {
  check-root
  drop-firewall
  install-iptables
  set-sysctl
  set-rules
  echo "event=network-setup app=kubernetes status=completed success=True"
}

run-setup
