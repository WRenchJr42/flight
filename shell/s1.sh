#!/bin/bash
# This script executes the curl command, saves the response,
# then extracts the external IP address and writes it to ip_address.txt.

# Run the curl command and save the output in response.txt
curl --path-as-is -i -s -k -X $'POST' \
    -H $'Host: 192.168.0.1' \
    -H $'Content-Length: 43' \
    -H $'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36' \
    -H $'TokenID: a9baeffbaa2f8dffd26888a46de28b' \
    -H $'Content-Type: text/plain' \
    -H $'Accept: */*' \
    -H $'Origin: http://192.168.0.1' \
    -H $'Referer: http://192.168.0.1/' \
    -H $'Accept-Encoding: gzip, deflate, br' \
    -H $'Accept-Language: en-US,en;q=0.9,hi;q=0.8' \
    -H $'Connection: keep-alive' \
    -b $'JSESSIONID=8c2e53244d3e662315ab21a5300e66' \
    --data-binary $'[WAN_PPP_CONN#1,1,1,0,0,0#0,0,0,0,0,0]0,0\x0d\x0a' \
    $'http://192.168.0.1/cgi?1' > response.txt


# Extract the external IP address from the response.
# This regex matches an IPv4 address following 'externalIPAddress='.
external_ip=$(grep -oP 'externalIPAddress=\K[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' response.txt)

if [ -n "$external_ip" ]; then
    # Write the extracted IP address to ip_address.txt
    echo "$external_ip" > ip_address.txt
    
else
    echo "No external IP Address found in the response."
fi

