#!/bin/bash
set -euo pipefail  # Exit on error, undefined vars, and pipeline failures
IFS=$'\n\t'       # Stricter word splitting

#!/bin/bash
#
# init_firewall.sh - set up restrictive iptables firewall inside container
#
# Dangerous flag to allow outbound traffic without restrictions
ALLOW_OUTBOUND=false
# Flag to relax forwarding when running Docker-in-Docker
ALLOW_DIND=false
for arg in "$@"; do
    case "$arg" in
        --dangerously-allow-network-outbound)
            ALLOW_OUTBOUND=true
            ;;
        --allow-docker-in-docker)
            ALLOW_DIND=true
            ;;
        *)
            echo "Unknown option: $arg"
            ;;
    esac
done

# Flush existing rules and delete existing ipsets
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
ipset destroy allowed-domains 2>/dev/null || true

# First allow DNS and localhost before any restrictions
# Allow outbound DNS
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
# Allow inbound DNS responses
iptables -A INPUT -p udp --sport 53 -j ACCEPT
# Allow localhost
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# Create ipset with CIDR support
ipset create allowed-domains hash:net

# Resolve and add other allowed domains
for domain in \
    "api.openai.com"; do
    echo "Resolving $domain..."
    ips=$(dig +short A "$domain")
    if [ -z "$ips" ]; then
        echo "ERROR: Failed to resolve $domain"
        exit 1
    fi

    while read -r ip; do
        if [[ ! "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            echo "ERROR: Invalid IP from DNS for $domain: $ip"
            exit 1
        fi
        echo "Adding $ip for $domain"
        ipset add allowed-domains "$ip"
    done < <(echo "$ips")
done

# Get host IP from default route
HOST_IP=$(ip route | grep default | cut -d" " -f3)
if [ -z "$HOST_IP" ]; then
    echo "ERROR: Failed to detect host IP"
    exit 1
fi

HOST_NETWORK=$(echo "$HOST_IP" | sed "s/\.[0-9]*$/.0\/24/")
echo "Host network detected as: $HOST_NETWORK"

# Set up remaining iptables rules
iptables -A INPUT -s "$HOST_NETWORK" -j ACCEPT
iptables -A OUTPUT -d "$HOST_NETWORK" -j ACCEPT

# Set default policies
iptables -P INPUT DROP
# Allow or drop forwarding based on Docker-in-Docker mode
if [ "$ALLOW_DIND" = true ]; then
  echo "DIND mode: allowing container-to-container forwarding"
  iptables -P FORWARD ACCEPT
else
  iptables -P FORWARD DROP
fi
# Allow or drop outbound based on flag
if [ "$ALLOW_OUTBOUND" = true ]; then
  iptables -P OUTPUT ACCEPT
else
  iptables -P OUTPUT DROP
fi

# First allow established connections for already approved traffic
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Then allow only specific outbound traffic to allowed domains
# Then allow only specific outbound traffic to allowed domains, if restrictions are enabled
if [ "$ALLOW_OUTBOUND" != true ]; then
  iptables -A OUTPUT -m set --match-set allowed-domains dst -j ACCEPT
fi

# Append final REJECT rules for immediate error responses
# For TCP traffic, send a TCP reset; for UDP, send ICMP port unreachable.
iptables -A INPUT -p tcp -j REJECT --reject-with tcp-reset
iptables -A INPUT -p udp -j REJECT --reject-with icmp-port-unreachable
if [ "$ALLOW_OUTBOUND" != true ]; then
  iptables -A OUTPUT -p tcp -j REJECT --reject-with tcp-reset
  iptables -A OUTPUT -p udp -j REJECT --reject-with icmp-port-unreachable
fi
## Conditionally reject forwarded packets when not in DIND mode
if [ "$ALLOW_DIND" != true ]; then
  iptables -A FORWARD -p tcp -j REJECT --reject-with tcp-reset
  iptables -A FORWARD -p udp -j REJECT --reject-with icmp-port-unreachable
fi

echo "Firewall configuration complete"
# Skip verification if outbound is allowed
if [ "$ALLOW_OUTBOUND" = true ]; then
  echo "DANGEROUS Allow-outbound flag set; skipping firewall verification"
  exit 0
fi
echo "Verifying firewall rules..."
if curl --connect-timeout 5 https://example.com >/dev/null 2>&1; then
    echo "ERROR: Firewall verification failed - was able to reach https://example.com"
    exit 1
else
    echo "Firewall verification passed - unable to reach https://example.com as expected"
fi

# Verify OpenAI API access
if ! curl --connect-timeout 5 https://api.openai.com >/dev/null 2>&1; then
    echo "ERROR: Firewall verification failed - unable to reach https://api.openai.com"
    exit 1
else
    echo "Firewall verification passed - able to reach https://api.openai.com as expected"
fi
