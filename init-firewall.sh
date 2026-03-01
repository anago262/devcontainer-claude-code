#!/bin/bash
set -euo pipefail  # Exit on error, undefined vars, and pipeline failures
IFS=$'\n\t'       # Stricter word splitting

# =============================================================================
# 3-Tier Domain Firewall for Claude Code Dev Containers
#
# Tier 1 - Core (hardcoded): Essential domains for Claude Code, npm, GitHub, etc.
# Tier 2 - Project (file):   Per-project domains from /workspace/.devcontainer/allowed-domains.txt
# Tier 3 - Extra (env var):  Ad-hoc domains from EXTRA_ALLOWED_DOMAINS environment variable
# =============================================================================

# --- Tier 1: Core domains (always allowed) ---
CORE_DOMAINS=(
    "registry.npmjs.org"
    "api.anthropic.com"
    "sentry.io"
    "statsig.anthropic.com"
    "statsig.com"
    "marketplace.visualstudio.com"
    "vscode.blob.core.windows.net"
    "update.code.visualstudio.com"
)

# --- Tier 2: Project domains (from file) ---
# Auto-detect workspace directory (supports /workspace and /workspaces/<name>)
WORKSPACE_DIR=$(find /workspaces -maxdepth 1 -mindepth 1 -type d 2>/dev/null | head -1)
WORKSPACE_DIR="${WORKSPACE_DIR:-/workspace}"
PROJECT_DOMAINS_FILE="${WORKSPACE_DIR}/.devcontainer/allowed-domains.txt"
PROJECT_DOMAINS=()
if [ -f "$PROJECT_DOMAINS_FILE" ]; then
    echo "Loading project domains from $PROJECT_DOMAINS_FILE..."
    while IFS= read -r line; do
        # Skip empty lines and comments
        line=$(echo "$line" | sed 's/#.*//; s/^[[:space:]]*//; s/[[:space:]]*$//')
        if [ -n "$line" ]; then
            PROJECT_DOMAINS+=("$line")
        fi
    done < "$PROJECT_DOMAINS_FILE"
    echo "Loaded ${#PROJECT_DOMAINS[@]} project domain(s)"
else
    echo "No project domains file found at $PROJECT_DOMAINS_FILE (skipping Tier 2)"
fi

# --- Tier 3: Extra domains (from environment variable) ---
EXTRA_DOMAINS=()
if [ -n "${EXTRA_ALLOWED_DOMAINS:-}" ]; then
    echo "Loading extra domains from EXTRA_ALLOWED_DOMAINS..."
    IFS=',' read -ra EXTRA_DOMAINS <<< "$EXTRA_ALLOWED_DOMAINS"
    # Trim whitespace from each entry
    for i in "${!EXTRA_DOMAINS[@]}"; do
        EXTRA_DOMAINS[$i]=$(echo "${EXTRA_DOMAINS[$i]}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    done
    echo "Loaded ${#EXTRA_DOMAINS[@]} extra domain(s)"
else
    echo "No EXTRA_ALLOWED_DOMAINS set (skipping Tier 3)"
fi

# Merge all domains
ALL_DOMAINS=("${CORE_DOMAINS[@]}" "${PROJECT_DOMAINS[@]}" "${EXTRA_DOMAINS[@]}")
echo "Total domains to allow: ${#ALL_DOMAINS[@]}"

# 1. Extract Docker DNS info BEFORE any flushing
DOCKER_DNS_RULES=$(iptables-save -t nat | grep "127\.0\.0\.11" || true)

# Flush existing rules and delete existing ipsets
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
ipset destroy allowed-domains 2>/dev/null || true

# 2. Selectively restore ONLY internal Docker DNS resolution
if [ -n "$DOCKER_DNS_RULES" ]; then
    echo "Restoring Docker DNS rules..."
    iptables -t nat -N DOCKER_OUTPUT 2>/dev/null || true
    iptables -t nat -N DOCKER_POSTROUTING 2>/dev/null || true
    echo "$DOCKER_DNS_RULES" | xargs -L 1 iptables -t nat
else
    echo "No Docker DNS rules to restore"
fi

# First allow DNS and localhost before any restrictions
# Allow outbound DNS
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
# Allow inbound DNS responses
iptables -A INPUT -p udp --sport 53 -j ACCEPT
# Allow outbound SSH
iptables -A OUTPUT -p tcp --dport 22 -j ACCEPT
# Allow inbound SSH responses
iptables -A INPUT -p tcp --sport 22 -m state --state ESTABLISHED -j ACCEPT
# Allow localhost
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# Create ipset with CIDR support
ipset create allowed-domains hash:net

# Fetch GitHub meta information and aggregate + add their IP ranges
echo "Fetching GitHub IP ranges..."
gh_ranges=$(curl -s https://api.github.com/meta)
if [ -z "$gh_ranges" ]; then
    echo "ERROR: Failed to fetch GitHub IP ranges"
    exit 1
fi

if ! echo "$gh_ranges" | jq -e '.web and .api and .git' >/dev/null; then
    echo "ERROR: GitHub API response missing required fields"
    exit 1
fi

echo "Processing GitHub IPs..."
while read -r cidr; do
    if [[ ! "$cidr" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        echo "ERROR: Invalid CIDR range from GitHub meta: $cidr"
        exit 1
    fi
    echo "Adding GitHub range $cidr"
    ipset add allowed-domains "$cidr"
done < <(echo "$gh_ranges" | jq -r '(.web + .api + .git)[]' | aggregate -q)

# Resolve and add all allowed domains
for domain in "${ALL_DOMAINS[@]}"; do
    echo "Resolving $domain..."
    ips=$(dig +short A "$domain" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || true)
    if [ -z "$ips" ]; then
        echo "WARNING: Failed to resolve $domain, skipping"
        continue
    fi

    while read -r ip; do
        echo "Adding $ip for $domain"
        ipset add allowed-domains "$ip" -exist
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

# Set default policies to DROP first
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

# First allow established connections for already approved traffic
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Then allow only specific outbound traffic to allowed domains
iptables -A OUTPUT -m set --match-set allowed-domains dst -j ACCEPT

# Explicitly REJECT all other outbound traffic for immediate feedback
iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited

echo "Firewall configuration complete"
echo "Verifying firewall rules..."
if curl --connect-timeout 5 https://example.com >/dev/null 2>&1; then
    echo "ERROR: Firewall verification failed - was able to reach https://example.com"
    exit 1
else
    echo "Firewall verification passed - unable to reach https://example.com as expected"
fi

# Verify GitHub API access
if ! curl --connect-timeout 5 https://api.github.com/zen >/dev/null 2>&1; then
    echo "ERROR: Firewall verification failed - unable to reach https://api.github.com"
    exit 1
else
    echo "Firewall verification passed - able to reach https://api.github.com as expected"
fi
