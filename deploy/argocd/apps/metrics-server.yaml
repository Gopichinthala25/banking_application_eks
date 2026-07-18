# metrics-server — provides the Kubernetes resource-metrics API (CPU/memory),
# which HPAs and `kubectl top` require. EKS does NOT ship it, so we add it here.
# --kubelet-insecure-tls is needed on EKS (kubelet serving certs aren't verifiable
# by metrics-server by default).
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: metrics-server
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: banking
  source:
    repoURL: https://kubernetes-sigs.github.io/metrics-server/
    chart: metrics-server
    targetRevision: 3.13.1
    helm:
      values: |
        args:
          - --kubelet-insecure-tls
        resources:
          requests: { cpu: 25m, memory: 64Mi }
          limits: { cpu: 200m, memory: 128Mi }
  destination:
    server: https://kubernetes.default.svc
    namespace: kube-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
