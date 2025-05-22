#!/bin/bash
set -euxo pipefail

# Log everything for debugging
exec > >(tee /var/log/user-data-monitor.log)
exec 2>&1

echo "=== Starting Monitoring Instance User Data Script ==="
echo "Web instance IP: ${web_instance_ip}"

# Update system
dnf update -y
dnf install -y docker git curl

# Start Docker
systemctl enable --now docker

# Install Docker Compose
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Create monitoring stack directory
mkdir -p /opt/monitoring-stack/{config,data,dashboards}
cd /opt/monitoring-stack

# Create Prometheus configuration
cat > config/prometheus.yml << PROM_EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - "alert_rules.yml"

scrape_configs:
  # Node Exporter from web instance
  - job_name: 'node-exporter-web'
    static_configs:
      - targets: ['${web_instance_ip}:9100']
    scrape_interval: 15s
    metrics_path: /metrics

  # Flask application metrics (if available)
  - job_name: 'flask-app'
    static_configs:
      - targets: ['${web_instance_ip}:5000']
    scrape_interval: 30s
    metrics_path: /metrics
    scrape_timeout: 10s

  # Self-monitoring
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  # Monitor the monitoring instance itself
  - job_name: 'monitoring-node'
    static_configs:
      - targets: ['localhost:9100']
PROM_EOF

# Create alert rules
cat > config/alert_rules.yml << ALERT_EOF
groups:
- name: web_application_alerts
  rules:
  - alert: WebInstanceDown
    expr: up{job="node-exporter-web"} == 0
    for: 1m
    labels:
      severity: critical
    annotations:
      summary: "Web instance is down"
      description: "The web application instance has been down for more than 1 minute."

  - alert: HighCPUUsage
    expr: 100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[2m])) * 100) > 80
    for: 2m
    labels:
      severity: warning
    annotations:
      summary: "High CPU usage detected"
      description: "CPU usage is above 80% for more than 2 minutes on {{ \$labels.instance }}"

  - alert: HighMemoryUsage
    expr: (node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100 > 85
    for: 2m
    labels:
      severity: warning
    annotations:
      summary: "High memory usage detected"
      description: "Memory usage is above 85% for more than 2 minutes on {{ \$labels.instance }}"

  - alert: FlaskAppDown
    expr: up{job="flask-app"} == 0
    for: 1m
    labels:
      severity: critical
    annotations:
      summary: "Flask application is not responding"
      description: "The Flask application metrics endpoint has been unreachable for more than 1 minute."
ALERT_EOF

# Create Grafana provisioning for datasources
mkdir -p config/grafana/provisioning/{datasources,dashboards}

cat > config/grafana/provisioning/datasources/prometheus.yml << DS_EOF
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    jsonData:
      timeInterval: 5s
DS_EOF

# Create dashboard provisioning
cat > config/grafana/provisioning/dashboards/default.yml << DB_EOF
apiVersion: 1
providers:
  - name: 'default'
    type: file
    updateIntervalSeconds: 30
    options:
      path: /var/lib/grafana/dashboards
DS_EOF

# Download Node Exporter dashboard
curl -sL https://grafana.com/api/dashboards/1860/revisions/32/download -o dashboards/node-exporter-full.json

# Create custom Flask application dashboard
cat > dashboards/flask-application.json << FLASK_DASHBOARD_EOF
{
  "dashboard": {
    "id": null,
    "title": "Student Registration System - Application Metrics",
    "tags": ["flask", "student-registration"],
    "timezone": "browser",
    "panels": [
      {
        "id": 1,
        "title": "Application Status",
        "type": "stat",
        "targets": [
          {
            "expr": "up{job=\"flask-app\"}",
            "legendFormat": "Application Status"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "mappings": [
              {"options": {"0": {"text": "DOWN"}}, "type": "value"},
              {"options": {"1": {"text": "UP"}}, "type": "value"}
            ]
          }
        },
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0}
      },
      {
        "id": 2,
        "title": "HTTP Requests per Second",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(flask_http_request_total[5m])",
            "legendFormat": "Requests/sec"
          }
        ],
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0}
      }
    ],
    "time": {"from": "now-6h", "to": "now"},
    "refresh": "5s"
  }
}
FLASK_DASHBOARD_EOF

# Create Docker Compose for monitoring stack
cat > docker-compose.yml << COMPOSE_EOF
version: '3.8'

services:
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    ports:
      - "9090:9090"
    volumes:
      - ./config/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - ./config/alert_rules.yml:/etc/prometheus/alert_rules.yml:ro
      - prometheus-data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/etc/prometheus/console_libraries'
      - '--web.console.templates=/etc/prometheus/consoles'
      - '--storage.tsdb.retention.time=200h'
      - '--web.enable-lifecycle'
    restart: unless-stopped

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
      - GF_USERS_ALLOW_SIGN_UP=false
      - GF_SECURITY_ADMIN_USER=admin
    volumes:
      - grafana-data:/var/lib/grafana
      - ./config/grafana/provisioning:/etc/grafana/provisioning
      - ./dashboards:/var/lib/grafana/dashboards
    restart: unless-stopped

  node-exporter:
    image: quay.io/prometheus/node-exporter:latest
    container_name: node-exporter-monitoring
    ports:
      - "9100:9100"
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.rootfs=/rootfs'
      - '--path.sysfs=/host/sys'
      - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)'
    restart: unless-stopped

volumes:
  prometheus-data:
  grafana-data:
COMPOSE_EOF

# Set proper permissions
chown -R ec2-user:ec2-user /opt/monitoring-stack

# Start the monitoring stack
echo "Starting Prometheus and Grafana..."
docker-compose up -d

# Wait for services to start
echo "Waiting for services to start..."
sleep 30

# Verify services are running
echo "Verifying monitoring services..."
docker-compose ps

# Test Prometheus
if curl -f http://localhost:9090 > /dev/null 2>&1; then
    echo "✅ Prometheus is running and accessible"
else
    echo "❌ Prometheus is not responding"
fi

# Test Grafana
if curl -f http://localhost:3000 > /dev/null 2>&1; then
    echo "✅ Grafana is running and accessible"
else
    echo "❌ Grafana is not responding"
fi

# Create monitoring health check script
cat > /home/ec2-user/monitoring_health_check.sh << 'MONITOR_HEALTH_EOF'
#!/bin/bash
echo "=== Monitoring Stack Health Check ==="
echo "Timestamp: $(date)"

cd /opt/monitoring-stack

# Check container status
echo "Container status:"
docker-compose ps

# Check Prometheus targets
echo "Prometheus targets status:"
curl -s http://localhost:9090/api/v1/targets | python3 -c "
import sys, json
data = json.load(sys.stdin)
for target in data['data']['activeTargets']:
    print(f\"Target: {target['labels']['job']} - {target['scrapeUrl']} - Health: {target['health']}\")
" 2>/dev/null || echo "Could not check Prometheus targets"

# Check Grafana
echo "Grafana status:"
if curl -f -s http://localhost:3000/api/health > /dev/null; then
    echo "✅ Grafana is healthy"
else
    echo "❌ Grafana is not responding"
fi

echo "=== Monitoring Health Check Complete ==="
MONITOR_HEALTH_EOF

chmod +x /home/ec2-user/monitoring_health_check.sh
chown ec2-user:ec2-user /home/ec2-user/monitoring_health_check.sh

# Run initial health check
/home/ec2-user/monitoring_health_check.sh

echo "=== Monitoring Instance Setup Complete ==="
echo "📊 Grafana URL: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):3000"
echo "📈 Prometheus URL: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):9090"
echo "🔐 Grafana Login: admin / admin"