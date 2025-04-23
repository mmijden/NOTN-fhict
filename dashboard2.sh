#!/bin/bash

NTOPNG_HOST="192.168.2.113"
NTOPNG_PORT="3000"
USERNAME="admin"
PASSWORD="<placeholder>"
IFID="1"

TMP_HOSTS=$(mktemp)
TMP_JSON=$(mktemp)

HOSTS_QUERY=$(curl -s -k -u "$USERNAME:$PASSWORD" \
    "http://$NTOPNG_HOST:$NTOPNG_PORT/lua/rest/v2/get/host/active.lua?ifid=$IFID")

# Vul tijdelijke hostlijst
echo "$HOSTS_QUERY" | jq -r '.rsp.data[].ip' > "$TMP_HOSTS"

while read -r HOST_IP; do
    if [[ "$HOST_IP" =~ ^192\.168\..* ]]; then
        HOST_INFO=$(echo "$HOSTS_QUERY" | jq -r ".rsp.data[] | select(.ip == \"$HOST_IP\")")
        MAC_ADDRESS=$(echo "$HOST_INFO" | jq -r '.mac')
        START_TIME=$(echo "$HOST_INFO" | jq -r '.first_seen')
        END_TIME=$(echo "$HOST_INFO" | jq -r '.last_seen')

        HOST_QUERY=$(curl -s -k -u "$USERNAME:$PASSWORD" \
            "http://$NTOPNG_HOST:$NTOPNG_PORT/lua/rest/v2/get/host/l7/stats.lua?ifid=$IFID&host=$HOST_IP")

        if echo "$HOST_QUERY" | jq -e '.rsp != null and (.rsp | length > 0)' > /dev/null; then
            APPS=$(echo "$HOST_QUERY" | jq -r '.rsp[].label' | grep -vE '^(Unknown|Other)$' | tr '\n' ' ')
        else
            APPS=""
        fi

        if [[ -n "$APPS" ]]; then
            jq -n \
                --arg ip "$HOST_IP" \
                --arg mac "$MAC_ADDRESS" \
                --arg start "$(date -d @$START_TIME '+%Y-%m-%d %H:%M:%S')" \
                --arg end "$(date -d @$END_TIME '+%Y-%m-%d %H:%M:%S')" \
                --arg apps "$APPS" \
                '{ip_address: $ip, mac_address: $mac, start_time: $start, end_time: $end, applications: ($apps | split(" ") | map(select(. != "")))}' >> "$TMP_JSON"
            echo "," >> "$TMP_JSON"
        fi
    fi
done < "$TMP_HOSTS"

# Bouw JSON array en verwijder laatste komma
JSON_OUTPUT=$(cat "$TMP_JSON" | sed '$ s/,$//' | awk 'BEGIN{print "["} {print} END{print "]"}')

# Toon resultaat
echo "$JSON_OUTPUT" | jq

# Opschonen
rm -f "$TMP_HOSTS" "$TMP_JSON"
