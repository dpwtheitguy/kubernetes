#!/bin/bash
# This script configures sysctl and iptables for Kubernetes labs on EC2 instances.
# It ensures necessary networking settings and firewall rules are in place.

set -euo pipefail

# Constants
SYSCTL_CONFIG="/etc/sysctl.d/k8s.conf"
IPTABLES_CONFIG="/etc/iptables/rules.v4"

# Function to configure sysctl for bridged network traffic
configure_sysctl() {
    echo "Configuring sysctl for Kubernetes networking..."
    cat <<EOF | sudo tee "$SYSCTL_CONFIG"
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
    sudo sysctl --system
}

# Function to configure iptables rules
configure_iptables() {
    echo "Configuring iptables rules for Kubernetes..."
    
    # Flush existing rules
    sudo iptables -F
    sudo iptables -X

    # Allow loopback traffic
    sudo iptables -A INPUT -i lo -j ACCEPT
    
    # Allow established and related connections
    sudo iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
    
    # Allow bridged network traffic
    sudo iptables -A FORWARD -m physdev --physdev-is-bridged -j ACCEPT
    
    # Allow intra-cluster communication (adjust CIDR as needed)
    sudo iptables -A INPUT -s 10.244.0.0/16 -j ACCEPT
    sudo iptables -A INPUT -s 192.168.0.0/16 -j ACCEPT
    
    # Allow kube-apiserver access (for control plane nodes)
    sudo iptables -A INPUT -p tcp --dport 6443 -j ACCEPT
    
    # Allow kubelet API
    sudo iptables -A INPUT -p tcp --dport 10250 -j ACCEPT
    
    # Allow CNI traffic (Flannel, Calico, etc.)
    sudo iptables -A INPUT -p udp --dport 4789 -j ACCEPT  # VXLAN (Flannel)
    sudo iptables -A INPUT -p udp --dport 8472 -j ACCEPT  # GRE (Flannel)
    sudo iptables -A INPUT -p tcp --dport 179 -j ACCEPT   # BGP (Calico)
    
    # Allow NodePort services (default range 30000-32767)
    sudo iptables -A INPUT -p tcp --dport 30000:32767 -j ACCEPT
    
    # Allow ICMP (ping)
    sudo iptables -A INPUT -p icmp -j ACCEPT
    
    # Drop all other traffic (optional)
    sudo iptables -A INPUT -j DROP
    
    # Save rules for persistence
    sudo mkdir -p "$(dirname "$IPTABLES_CONFIG")"
    sudo iptables-save | sudo tee "$IPTABLES_CONFIG"
}

# Main execution
main() {
    configure_sysctl
    configure_iptables
    echo "Kubernetes networking setup complete."
}

main
