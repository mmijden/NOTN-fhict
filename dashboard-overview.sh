#!/bin/bash

NTOPNG_HOST="192.168.1.148"
NTOPNG_PORT="3000"
USERNAME="admin"
PASSWORD="<placeholder>"
IFID="1"

TMP_HOSTS=$(mktemp)
TMP_JSON=$(mktemp)

HOSTS_QUERY=$(curl -s -k -u "$USERNAME:$PASSWORD" \
    "http://$NTOPNG_HOST:$NTOPNG_PORT/lua/rest/v2/get/host/active.lua?ifid=$IFID")

echo "$HOSTS_QUERY" | jq -r '.rsp.data[].ip' > "$TMP_HOSTS"

declare -A app_users

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
            for APP in $APPS; do
                # Maak een unieke sleutel op basis van IP en MAC
                UNIQUE_KEY="$HOST_IP|$MAC_ADDRESS"
                if [[ -z "${app_users[$APP]}" ]]; then
                    app_users["$APP"]="$UNIQUE_KEY"
                else
                    app_users["$APP"]+=", $UNIQUE_KEY"
                fi
            done
        fi
    fi
done < "$TMP_HOSTS"

# Tellen van unieke IP/MAC combinaties per applicatie
echo "{"
first=1
for APP in "${!app_users[@]}"; do
    UNIQUE_COUNT=$(echo "${app_users[$APP]}" | tr ', ' '\n' | sort -u | wc -l)
    if [[ $first -eq 0 ]]; then
        echo ","
    fi
    printf "  \"%s\": %d" "$APP" "$UNIQUE_COUNT"
    first=0
done
echo
echo "}"

rm -f "$TMP_HOSTS" "$TMP_JSON"
