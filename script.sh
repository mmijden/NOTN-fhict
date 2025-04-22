#!/bin/bash

# Configuratie
NTOPNG_HOST="192.168.2.113"
NTOPNG_PORT="3000"
USERNAME="admin"
PASSWORD="<placeholder>"
IFID="1"

# Tijdelijk bestand voor IP's
TMP_HOSTS=$(mktemp)

# Stap 1: Haal alle actieve hosts op
curl -s -k -u $USERNAME:$PASSWORD \
    "http://$NTOPNG_HOST:$NTOPNG_PORT/lua/rest/v2/get/host/active.lua?ifid=$IFID" \
    | jq -r '.rsp.data[].ip' > "$TMP_HOSTS"

# Stap 2: Filter IP-adressen die beginnen met 192.168
declare -A app_users

# Verwerk elke host
while read -r HOST_IP; do
    # Alleen IP's binnen het bereik 192.168.x.x verwerken
    if [[ "$HOST_IP" =~ ^192\.168\..* ]]; then
        # Haal Layer 7 stats op voor de host
        HOST_QUERY=$(curl -s -k -u $USERNAME:$PASSWORD \
            "http://$NTOPNG_HOST:$NTOPNG_PORT/lua/rest/v2/get/host/l7/stats.lua?ifid=$IFID&host=$HOST_IP")

        # Debug: toon de ruwe JSON-output van de host-query
        echo "Verwerking van host: $HOST_IP"
        echo "$HOST_QUERY"  # Debug: toon de volledige JSON-output

        # Controleer of er 'rsp' data is en die data bevat labels
        if echo "$HOST_QUERY" | jq -e '.rsp != null' > /dev/null; then
            # Haal applicatienamen uit de JSON en tel ze per host
            echo "$HOST_QUERY" | jq -r '.rsp[].label' | while read -r APP; do
                [[ -z "$APP" ]] && continue
                # Voeg de applicatie toe aan de lijst van gebruikers voor deze host
                app_users["$APP"]+="$HOST_IP "
            done
        else
            echo "Geen applicatiegegevens voor host: $HOST_IP"
        fi
    fi
done < "$TMP_HOSTS"

# Stap 3: Toon een overzicht van de applicaties en het aantal gebruikers
echo
echo "Aantal unieke gebruikers per applicatie:"

# Controleer of er applicaties zijn gevonden
if [ ${#app_users[@]} -eq 0 ]; then
    echo "Geen applicaties gevonden."
else
    # Toon het totaal aantal unieke gebruikers per applicatie
    for APP in "${!app_users[@]}"; do
        # Tel het aantal unieke gebruikers voor deze applicatie
        UNIQUE_COUNT=$(echo "${app_users[$APP]}" | tr ' ' '\n' | sort -u | wc -l)
        printf "%-25s : %s gebruikers\n" "$APP" "$UNIQUE_COUNT"
    done
fi

# Opruimen
rm -f "$TMP_HOSTS"
