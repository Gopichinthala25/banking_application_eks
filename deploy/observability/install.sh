#!/usr/bin/env bash
# Installs the full observability stack into the `observability` namespace:
#   kube-prometheus-stack (Prometheus + Alertmanager + Grafana + exporters)
#   Tempo (traces) · Loki + Promtail (logs) · OpenTelemetry Collector (OTLP in)
set -euo pipefail
NS=observability
DIR="$(cd "$(dirname "$0")" && pwd)"

kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null
helm repo add grafana https://grafana.github.io/helm-charts >/dev/null
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts >/dev/null
helm repo update >/dev/null

echo ">>> kube-prometheus-stack (installs the Prometheus Operator CRDs)"
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n "$NS" -f "$DIR/values/kube-prometheus-stack.yaml" --wait --timeout 10m

echo ">>> tempo"
helm upgrade --install tempo grafana/tempo -n "$NS" -f "$DIR/values/tempo.yaml" --wait --timeout 5m

echo ">>> loki + promtail"
# Release name MUST be "loki-stack" so the service is loki-stack (matches the
# Grafana Loki datasource URL in kube-prometheus-stack values, and the Argo app).
helm upgrade --install loki-stack grafana/loki-stack -n "$NS" -f "$DIR/values/loki-stack.yaml" --wait --timeout 5m

echo ">>> opentelemetry-collector"
helm upgrade --install otel-collector open-telemetry/opentelemetry-collector \
  -n "$NS" -f "$DIR/values/otel-collector.yaml" --wait --timeout 5m

echo ">>> ServiceMonitors + custom dashboard"
kubectl apply -f "$DIR/manifests/servicemonitor.yaml"
kubectl apply -f "$DIR/manifests/dashboards-configmap.yaml"

echo "observability stack installed."
