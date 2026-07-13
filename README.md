# Banking Platform on Amazon EKS

A production-grade, enterprise-style **banking platform** built as ~30 Go
microservices and deployed on **Amazon EKS** with modern DevOps, GitOps,
observability, security and scalability practices.

> This is a learning / portfolio reference project. It intentionally self-hosts
> its data stores (PostgreSQL, Redis, Kafka) in-cluster rather than using managed
> AWS services, and uses Traefik for ingress.

## Tech stack

| Layer            | Choice                                             |
|------------------|----------------------------------------------------|
| Backend          | Go 1.25, Gin (REST), gRPC (internal)               |
| Frontend         | React                                              |
| Database         | PostgreSQL (single shared DB, per-service prefixes)|
| Cache            | Redis                                              |
| Messaging        | Apache Kafka                                        |
| Object storage   | Amazon S3                                           |
| Orchestration    | Amazon EKS (Kubernetes)                            |
| Packaging        | Helm (one umbrella chart)                          |
| Ingress / TLS    | Traefik + cert-manager + Let's Encrypt             |
| GitOps           | Argo CD                                             |
| CI/CD            | GitHub Actions + Trivy + Amazon ECR                |
| IaC              | Terraform (modular)                                |
| Observability    | Prometheus, Grafana, Loki, Promtail, Tempo, OTel   |
| Progressive del. | Argo Rollouts                                       |
| Backup/DR        | Velero                                             |

## Repository layout

```
banking-platform/
├── pkg/                      # shared platform kit (config, logging, otel, http, grpc, kafka, db...)
├── templates/service-template/  # golden-path service every microservice is scaffolded from
├── services/                 # the ~30 microservices (added phase by phase)
├── frontend/                 # React SPA
├── deploy/                   # helm chart, argocd, rollouts, observability
├── terraform/                # modular IaC (vpc, iam, eks, ecr, s3...)
├── docs/                     # architecture & diagrams
├── .github/workflows/        # CI/CD
├── docker-compose.yaml       # local dependencies
├── go.work                   # Go workspace
└── Makefile
```

See [PROJECT_PROGRESS.md](PROJECT_PROGRESS.md) for the phased roadmap and status.

## Quick start (local)

Prerequisites: Docker (Go is optional — the Makefile runs Go in a container).

```bash
# 1. Start local dependencies (Postgres, Redis, Kafka, Kafka UI)
make compose-up

# 2. Build & test everything
make build
make test

# 3. Run the service template (in-memory, no dependencies needed)
make run-template
# then:
curl -s localhost:8080/healthz
curl -s -X POST localhost:8080/api/v1/resources -d '{"name":"demo"}'
curl -s localhost:8080/api/v1/resources
```

Handy local endpoints: Kafka UI → http://localhost:8090

## Module path

Go modules use the `banking-platform/...` prefix (a neutral, non-published path
resolved locally via `go.work` + `replace`). To publish under your own GitHub
org, find-and-replace `banking-platform` with `github.com/<your-org>/<repo>`.

## Status

**Phase 1 complete** — foundation & platform kit. See `PROJECT_PROGRESS.md`.
