#!/bin/bash
#
# Script to add a new VPN client
# Sample usage: ./new_vpn_client.sh client_name

if [[ "$EUID" -ne 0 ]]; then
    echo "This installer needs to be run with superuser privileges."
    exit
fi

script_dir=$(cd "$(dirname "$0")" && pwd)
unsanitized_client=$1
client=$(sed 's/[^0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_-]/_/g' <<< "$unsanitized_client")
if [[ -z "$client" || -e /etc/openvpn/server/easy-rsa/pki/issued/"$client".crt ]]; then 
    echo "$client: invalid name."
    exit 1
fi
cd /etc/openvpn/server/easy-rsa/
./easyrsa --batch --days=3650 build-client-full "$client" nopass
# Build the $client.ovpn file, stripping comments from easy-rsa in the process
grep -vh '^#' /etc/openvpn/server/client-common.txt /etc/openvpn/server/easy-rsa/pki/inline/private/"$client".inline > "$script_dir"/"$client".ovpn
echo "$client added. Configuration available in:" "$script_dir"/"$client.ovpn"
exit
