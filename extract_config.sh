#!/bin/bash

echo "=== NPM Proxy Host Configuration Extractor ==="
echo "This will extract your existing proxy host details for easy recreation"
echo ""

CONTAINER_NAME="NPMplus-Official"

for conf_file in /data/nginx/proxy_host/*.conf; do
    if docker exec $CONTAINER_NAME [ -f "$conf_file" ]; then
        filename=$(basename "$conf_file")
        host_id=${filename%.conf}
        
        echo "===================================="
        echo "PROXY HOST $host_id"
        echo "===================================="
        
        # Extract domain name
        domain=$(docker exec $CONTAINER_NAME grep -o 'server_name[[:space:]]*[^;]*' "$conf_file" | head -1 | sed 's/server_name[[:space:]]*//')
        echo "🌐 Domain Name: $domain"
        
        # Extract backend URL
        backend=$(docker exec $CONTAINER_NAME grep -o 'proxy_pass[[:space:]]*[^;]*' "$conf_file" | head -1 | sed 's/proxy_pass[[:space:]]*//')
        echo "🔗 Forward to: $backend"
        
        # Check for SSL
        if docker exec $CONTAINER_NAME grep -q "ssl_certificate" "$conf_file"; then
            ssl_cert=$(docker exec $CONTAINER_NAME grep -o 'ssl_certificate[[:space:]]*[^;]*' "$conf_file" | head -1 | sed 's/ssl_certificate[[:space:]]*//')
            if [[ "$ssl_cert" == *"custom"* ]]; then
                echo "🔒 SSL: Custom Certificate"
            elif [[ "$ssl_cert" == *"certbot"* ]] || [[ "$ssl_cert" == *"letsencrypt"* ]]; then
                echo "🔒 SSL: Let's Encrypt"
            else
                echo "🔒 SSL: Yes (unknown type)"
            fi
        else
            echo "❌ SSL: No"
        fi
        
        # Check for websockets
        if docker exec $CONTAINER_NAME grep -q -i "upgrade.*websocket\|connection.*upgrade" "$conf_file"; then
            echo "🔄 WebSockets: Enabled"
        else
            echo "🔄 WebSockets: Disabled"
        fi
        
        # Check for custom config
        if docker exec $CONTAINER_NAME grep -q "# Custom" "$conf_file"; then
            echo "⚙️  Custom Config: Yes"
        else
            echo "⚙️  Custom Config: No"
        fi
        
        echo ""
        echo "TO RECREATE IN NPMplus:"
        echo "1. Add Proxy Host"
        echo "2. Domain: $domain"
        echo "3. Forward to: $backend"
        echo "4. Configure SSL if needed"
        echo "5. Enable WebSockets if noted above"
        echo ""
    fi
done

echo "===================================="
echo "RECREATION SUMMARY"
echo "===================================="
echo "1. Login to NPMplus: https://localhost:8091"
echo "2. Use the information above to recreate each proxy host"
echo "3. SSL certificates will be auto-detected if they exist"
echo "4. Your websites should continue working during recreation"
echo ""
