#!/bin/bash

NTOPNG_HOST="192.168.1.148"
NTOPNG_PORT="3000"
USERNAME="admin"
PASSWORD="<placeholder>"
IFID="1"

TMP_HOSTS=$(mktemp)

curl -s -k -u "$USERNAME:$PASSWORD" "http://$NTOPNG_HOST:$NTOPNG_PORT/lua/rest/v2/get/host/active.lua?ifid=$IFID" | jq -r '.rsp.data[].ip' > "$TMP_HOSTS"

declare -A app_users

while read -r HOST_IP; do
    if [[ "$HOST_IP" =~ ^192\.168\..* ]]; then
        HOST_QUERY=$(curl -s -k -u "$USERNAME:$PASSWORD" "http://$NTOPNG_HOST:$NTOPNG_PORT/lua/rest/v2/get/host/l7/stats.lua?ifid=$IFID&host=$HOST_IP")

        if echo "$HOST_QUERY" | jq -e '.rsp != null and (.rsp | length > 0)' > /dev/null; then
            for APP in $(echo "$HOST_QUERY" | jq -r '.rsp[].label'); do
                [[ -z "$APP" ]] && continue
                app_users["$APP"]+="$HOST_IP "
            done
        fi
    fi
done < "$TMP_HOSTS"

echo "{"
first=1
for APP in "${!app_users[@]}"; do
    UNIQUE_COUNT=$(echo "${app_users[$APP]}" | tr ' ' '\n' | sort -u | wc -l)
    if [[ $first -eq 0 ]]; then
        echo ","
    fi
    printf "  \"%s\": %d" "$APP" "$UNIQUE_COUNT"
    first=0
done
echo
echo "}"

rm -f "$TMP_HOSTS"
