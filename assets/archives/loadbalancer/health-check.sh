#!/bin/bash
# Health check and monitoring script for load balancer

LOG_FILE="/var/log/loadbalancer-health.log"

log_health() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
}

check_service() {
    if systemctl is-active --quiet "$1"; then
        log_health "✓ $1 is running"
        return 0
    else
        log_health "✗ $1 is not running"
        systemctl restart "$1"
        return 1
    fi
}

log_health "=== Load Balancer Health Check ==="

# Check NGINX service
check_service nginx

# Check upstream servers
log_health "=== Backend Health Check ==="

# Check webapp services
if curl -s -o /dev/null -w "%{http_code}" "http://${WEBAPP1_IP:-localhost}:3000" 2>/dev/null | grep -q "200"; then
    log_health "✓ Webapp 1 (${WEBAPP1_IP:-localhost}:3000) is responding"
else
    log_health "✗ Webapp 1 (${WEBAPP1_IP:-localhost}:3000) is DOWN"
fi

if curl -s -o /dev/null -w "%{http_code}" "http://${WEBAPP2_IP:-localhost}:3000" 2>/dev/null | grep -q "200"; then
    log_health "✓ Webapp 2 (${WEBAPP2_IP:-localhost}:3000) is responding"
else
    log_health "✗ Webapp 2 (${WEBAPP2_IP:-localhost}:3000) is DOWN"
fi

# Check API health endpoints  
if curl -s -o /dev/null -w "%{http_code}" "http://${WEBAPP1_IP:-localhost}:3000/api/health" 2>/dev/null | grep -q "200"; then
    log_health "✓ Webapp 1 API (${WEBAPP1_IP:-localhost}:3000/api/health) is responding"
else
    log_health "✗ Webapp 1 API (${WEBAPP1_IP:-localhost}:3000/api/health) is DOWN"
fi

if curl -s -o /dev/null -w "%{http_code}" "http://${WEBAPP2_IP:-localhost}:3000/api/health" 2>/dev/null | grep -q "200"; then
    log_health "✓ Webapp 2 API (${WEBAPP2_IP:-localhost}:3000/api/health) is responding"
else
    log_health "✗ Webapp 2 API (${WEBAPP2_IP:-localhost}:3000/api/health) is DOWN"
fi

# Check backend API servers
if curl -s -o /dev/null -w "%{http_code}" "http://${BACKEND_API1_IP:-localhost}:5000/health" 2>/dev/null | grep -q "200"; then
    log_health "✓ Backend API 1 (${BACKEND_API1_IP:-localhost}:5000) is responding"
else
    log_health "✗ Backend API 1 (${BACKEND_API1_IP:-localhost}:5000) is DOWN"
fi

if curl -s -o /dev/null -w "%{http_code}" "http://${BACKEND_API2_IP:-localhost}:5000/health" 2>/dev/null | grep -q "200"; then
    log_health "✓ Backend API 2 (${BACKEND_API2_IP:-localhost}:5000) is responding"
else
    log_health "✗ Backend API 2 (${BACKEND_API2_IP:-localhost}:5000) is DOWN"
fi

# Check load balancer health endpoint
if curl -s -o /dev/null -w "%{http_code}" "http://localhost/health" 2>/dev/null | grep -q "200"; then
    log_health "✓ Load balancer health endpoint is responding"
else
    log_health "✗ Load balancer health endpoint is DOWN"
fi

# Get NGINX status if available
if curl -s "http://localhost/nginx_status" 2>/dev/null > /tmp/nginx_status; then
    connections=$(grep "Active connections" /tmp/nginx_status | awk '{print $3}')
    log_health "✓ NGINX status: $connections active connections"
    rm -f /tmp/nginx_status
else
    log_health "! NGINX status page unavailable"
fi

log_health "Health check completed"