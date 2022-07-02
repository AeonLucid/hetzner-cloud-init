#!/bin/bash

while [[ $# -gt 0 ]]
do
key="$1"

case $key in
  --hcloud-token)
    TOKEN="$2"
    shift
    shift
  ;;
  --whitelisted-ips)
    WHITELIST_S="$2"
    shift
    shift
  ;;
  --floating-ips)
    FLOATING_IPS="1"
    shift
  ;;
  *)
    shift
  ;;
esac
done

# Self update
curl -s -S -f -o /usr/local/bin/update-config.sh https://raw.githubusercontent.com/AeonLucid/hetzner-cloud-init/master/update-config.sh

NEW_NODE_IPS=( $(curl -H 'Accept: application/json' -H "Authorization: Bearer ${TOKEN}" 'https://api.hetzner.cloud/v1/servers' | jq -r '.servers[].public_net.ipv4.ip') )

touch /etc/current_node_ips
cp /etc/current_node_ips /etc/old_node_ips
echo "" > /etc/current_node_ips

for IP in "${NEW_NODE_IPS[@]}"; do
  ufw allow from "$IP"
  echo "$IP" >> /etc/current_node_ips
done

IFS=$'\r\n' GLOBIGNORE='*' command eval 'OLD_NODE_IPS=($(cat /etc/old_node_ips))'

REMOVED=()
for i in "${OLD_NODE_IPS[@]}"; do
  skip=
  for j in "${NEW_NODE_IPS[@]}"; do
    [[ $i == $j ]] && { skip=1; break; }
  done
  [[ -n $skip ]] || REMOVED+=("$i")
done
declare -p REMOVED

for IP in "${REMOVED[@]}"; do
  ufw deny from "$IP"
done

FLOATING_IPS=${FLOATING_IPS:-"0"}

if [ "$FLOATING_IPS" == "1" ]; then
  FLOATING_IPS=( $(curl -H 'Accept: application/json' -H "Authorization: Bearer ${TOKEN}" 'https://api.hetzner.cloud/v1/floating_ips' | jq -r '.floating_ips[].ip') )    

  for IP in "${FLOATING_IPS[@]}"; do
    ip addr add $IP/32 dev eth0
  done  
fi

# Cloudflare
curl -s https://www.cloudflare.com/ips-v4 -o /tmp/cf_ips
curl -s https://www.cloudflare.com/ips-v6 >> /tmp/cf_ips

for cfip in `cat /tmp/cf_ips`; do /usr/sbin/ufw allow proto tcp from $cfip to any port 80 comment 'Cloudflare IP'; done
for cfip in `cat /tmp/cf_ips`; do /usr/sbin/ufw allow proto tcp from $cfip to any port 443 comment 'Cloudflare IP'; done
