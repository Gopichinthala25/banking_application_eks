# Project Progress — Banking Platform on Amazon EKS

This file is the single source of truth for the phased build. It is updated at
the end of **every** phase.

- **Project:** Production-grade enterprise banking platform (~30 Go microservices) on Amazon EKS
- **Module path prefix:** `banking-platform/...`
- **Go baseline:** 1.25
- **Last updated:** 2026-07-13 (Phase 13 complete)

---

## Approved design decisions

| Decision | Choice |
|----------|--------|
| Service depth | Shared platform kit + template → ~10 core services deep, ~20 scaffolded |
| Repository model | Monorepo with Go workspaces (`go.work`) |
| Database | Single PostgreSQL **in-cluster** (StatefulSet), one shared DB, per-service table prefixes. **No RDS.** |
| Cache / Messaging | Redis + Kafka, **in-cluster** (no managed AWS data services) |
| Object storage | Amazon S3 (accessed via K8s Secret credentials) |
| Ingress | **Traefik only** (no ALB / AWS LB Controller) |
| Runtime during build | **kind locally first**, EKS later for recording |
| Secrets | Kubernetes Secrets (primary); External Secrets Operator documented as upgrade path |
| Ledger | Included — double-entry Ledger service as banking core |

---

## Roadmap & status

| Phase | Title | Status |
|-------|-------|--------|
| 0 | Architecture & Design | ✅ Complete |
| 1 | Foundation & Platform Kit | ✅ Complete |
| 2 | Identity & Customer core (Auth, AuthZ, Customer, Profile, KYC, Document) | ✅ Complete |
| 3 | Core Banking + Ledger (Account, Ledger, Transaction, Payment, Beneficiary, Wallet) | ✅ Complete |
| 4 | Products & remaining services (Card, Loan, EMI, FD, RD, Investment, FX + scaffolds) | ✅ Complete |
| 5 | Async, Risk & Insight (Notification, Email, SMS, Fraud, Audit, Reports, Statement, Analytics, Search) | ✅ Complete |
| 6 | API Gateway + React frontend | ✅ Complete |
| 7 | Containerization & local E2E (kind) + Helm chart | ✅ Complete |
| 8 | Terraform: Networking & IAM | ✅ Complete |
| 9 | Terraform: EKS, ECR, S3 (no RDS) | ✅ Complete |
| 10 | Helm umbrella chart | ✅ Complete (delivered early in Phase 7) |
| 11 | Ingress & TLS (Traefik, cert-manager, Let's Encrypt, GoDaddy) | ⏳ Pending approval |
| 12 | GitOps (Argo CD) | ✅ Manifests authored (app-of-apps) |
| 13 | CI/CD (GitHub Actions → Trivy → ECR → bump values) | ✅ Complete |
| 14 | Observability (Prometheus, Grafana, Loki, Promtail, Tempo, OTel Collector, dashboards) | ✅ Complete (verified on kind) |
| 15 | Scaling (HPA, VPA, Cluster Autoscaler) | ⬜ Not started |
| 16 | Deployment strategies (Argo Rollouts: rolling, blue/green, canary) | ⬜ Not started |
| 17 | Backup & DR (Velero) | ⬜ Not started |
| 18 | Security hardening (RBAC, NetworkPolicies, Pod Security) | ⬜ Not started |
| 19 | Documentation & diagrams | ⬜ Not started |

Legend: ✅ complete · ⏳ pending approval / in progress · ⬜ not started

---

## Phase 1 — Foundation & Platform Kit ✅

**Goal:** establish the monorepo, a reusable Go platform kit, and a golden-path
service template that every microservice will be built from.

### Delivered

**Shared platform kit (`pkg/`)** — one module, `banking-platform/pkg`:

| Package | Responsibility |
|---------|----------------|
| `config` | Env-driven config with a shared `Base` (HTTP, gRPC, Postgres, Redis, Kafka, telemetry, log) |
| `logger` | zap structured logging with OTel trace correlation |
| `telemetry` | OpenTelemetry traces + metrics via OTLP/gRPC; W3C context + baggage propagators |
| `httpserver` | Gin server: request-ID, logging, recovery, Prometheus, OTel middleware, graceful shutdown |
| `grpcserver` | gRPC server: OTel stats handler, health service, reflection, graceful shutdown |
| `kafka` | Producer/consumer wrappers with trace-context propagation via message headers |
| `postgres` | pgx pool with OTel query tracing + goose migration runner |
| `redis` | go-redis client with OTel tracing |
| `health` | Liveness / readiness / startup endpoints with pluggable checks |
| `apierror` | Typed API errors mapped to HTTP statuses |
| `money` | Exact decimal money type (never float) — with unit tests |
| `metrics` | Prometheus `/metrics` endpoint |

**Service template (`templates/service-template/`)** — golden path:
- Layered architecture: `cmd` → `handler` → `service` → `repository` → `domain`
- In-memory + Postgres repositories (fallback when DB disabled)
- Embedded goose migrations (`tmpl_` table prefix)
- Multi-stage Dockerfile → distroless **non-root** image
- README with "create a new service" instructions

**Root tooling:**
- `go.work` workspace, `Makefile` (Go-in-Docker, no host Go required)
- `docker-compose.yaml` — Postgres, Redis, Kafka (KRaft), Kafka UI
- `.env.example`, `.gitignore`, `README.md`

### Verification
- `go build ./...` — passes (pkg + template)
- `go vet ./...` — clean
- `go test ./...` — money package tests pass
- Multi-stage Docker image builds; service smoke-tested (health + CRUD)

### Notes / follow-ups
- `proto/` (buf) will be introduced in Phase 3 when the first gRPC contracts appear.
- Outbox pattern helper will be added to `pkg/` in Phase 3 alongside the Ledger.

---

## Phase 2 — Identity & Customer core ✅

**Goal:** the first *deep* services — authentication, authorization and customer
onboarding — plus the first gRPC contracts.

### Delivered

**Shared kit additions (`pkg/`)**
- `pkg/auth` — JWT Manager (HS256 access + refresh tokens) and Gin middleware
  (`Middleware`, `RequireRole`, `Subject/Email/Roles`). Stateless validation
  usable by every service.
- `pkg/password` — bcrypt hashing/verification.
- `pkg/s3` — AWS SDK v2 S3 client with presigned GET/PUT (MinIO-compatible).
- `pkg/config` — added `Auth` (JWT) and `S3` sections to `Base`.

**gRPC contracts (`proto/`, buf)**
- `auth.v1.AuthService.ValidateToken`
- `authz.v1.AuthzService.Check` + `GetRoles`
- Generated Go under `proto/gen/...` (protoc-gen-go + protoc-gen-go-grpc via buf).

**Services (`services/`)** — all with REST, health/metrics/tracing, in-memory +
Postgres repos (single shared DB, per-service table prefixes), embedded goose
migrations:

| Service | Highlights | Tables |
|---------|-----------|--------|
| auth-service | register/login/refresh/logout, bcrypt, JWT, Redis (or in-mem) refresh-token store with rotation + revocation, **gRPC ValidateToken** | `auth_users` |
| authz-service | RBAC (roles/permissions/assignments), default-model seeding, wildcard admin, **gRPC Check/GetRoles** | `authz_roles`, `authz_permissions`, `authz_role_permissions`, `authz_user_roles` |
| customer-service | customer master, JWT-protected, self + staff (teller/admin) endpoints | `customer_customers` |
| profile-service | extended profile + address, upsert by user | `profile_profiles` |
| kyc-service | KYC submit + staff review workflow (PENDING/VERIFIED/REJECTED) | `kyc_verifications` |
| document-service | presigned S3 upload/download, owner-scoped, metadata store | `document_documents` |

**Build tooling**
- `build/service.Dockerfile` — one parameterized multi-stage, distroless
  non-root Dockerfile for all services (`--build-arg SERVICE=<name>`).
- `go.work` updated with proto + all 6 services.

### Verification
- `go build ./...` + `go vet ./...` — pass for pkg, proto, and all 6 services.
- **auth-service** run end-to-end: register→tokens, /me (200 with token, 401
  without), duplicate register→409, login→200, wrong password→401, refresh→new
  tokens, logout then refresh-reuse→401 (rotation + revocation verified).
- **authz-service** run: default RBAC seeded (admin/customer/teller with correct
  permissions), Check returns false for unassigned subject.

### Design decisions / notes
- **Stateless JWT** is the primary auth mechanism; gRPC `ValidateToken` exists
  for services that prefer central introspection. Shared `JWT_SECRET`.
- **One shared Dockerfile** instead of 30 per-service files (DRY monorepo best
  practice); the template retains its own as a reference.
- gRPC servers are **opt-in per service** via `GRPC_ENABLED` (auth + authz
  register their services when enabled).
- Follow-up: API Gateway (Phase 6) will call authz `Check` over gRPC; the outbox
  + Ledger land in Phase 3.

---

## Phase 3 — Core Banking + Ledger ✅

**Goal:** the money core — a real double-entry ledger, accounts, transactions,
payments, beneficiaries and wallets — with the outbox pattern and idempotency.

### Delivered

**Shared kit additions (`pkg/`)**
- `pkg/grpcclient` — OTel-instrumented gRPC dialing for service-to-service calls.
- `pkg/outbox` — transactional outbox (`Insert` within a tx + background `Relay`
  that publishes to Kafka). Single shared `outbox_events` table, per-`source`.
- `pkg/httpserver/idempotency` — `Idempotency-Key` header helper for money endpoints.

**gRPC contracts (`proto/`)**
- `ledger.v1.LedgerService` — OpenAccount / PostTransaction / GetBalance
- `account.v1.AccountService` — GetAccount

**Services (`services/`)**

| Service | Highlights | Tables |
|---------|-----------|--------|
| **ledger-service** | Double-entry engine, source of truth for money. Balanced-posting validation (ΣDEBIT==ΣCREDIT), idempotency on posting key, running balances. REST + gRPC. | `ledger_accounts`, `ledger_transactions`, `ledger_entries` |
| account-service | Bank accounts; opens a ledger account on creation (gRPC); balance queried from ledger. REST + gRPC (GetAccount). | `account_accounts` |
| transaction-service | Deposit / withdraw / transfer → balanced ledger postings; overdraft check; idempotent replay; **transactional outbox** events. | `transaction_transactions`, `outbox_events` |
| beneficiary-service | Saved payee CRUD, owner-scoped. | `beneficiary_beneficiaries` |
| payment-service | Outbound payment to a beneficiary (DEBIT payer, CREDIT clearing) via ledger; idempotent; outbox events. | `payment_payments`, `outbox_events` |
| wallet-service | Stored-value wallet (top-up/spend), overdraft-safe atomic balance update, idempotent, outbox events. | `wallet_wallets`, `wallet_transactions`, `outbox_events` |

All money amounts use exact `NUMERIC(38,2)` / shopspring `decimal` — never floats.

### Verification
- `go build ./...` + `go vet ./...` — pass for pkg, proto, and all 6 new services.
- **ledger-service** run live: open accounts, deposit, transfer, balances correct
  (A=700, B=300, sys=−1000), idempotent replay returned `duplicate:true` with
  unchanged balances, unbalanced posting rejected (400).
- **Cross-service integration** (auth + ledger + transaction on a Docker network,
  transaction→ledger over gRPC): register→JWT, deposit/transfer/withdraw posted
  correctly (A=700, B=200), overdraft→422, idempotent deposit replay returned the
  same transaction id with no double-credit, unauthenticated→401.

### Design decisions / notes
- **Ledger is authoritative for balances**; account-service does not store balances.
- **System accounts** (cash per currency, clearing per currency) are opened lazily
  with deterministic UUIDs so deposits/withdrawals/payments stay balanced.
- **Outbox events** are written only when Postgres is enabled; the relay runs only
  when Kafka is enabled (so local in-memory mode stays dependency-free).
- Beneficiary validation across services is deferred (payment takes an opaque
  `beneficiary_id`) to limit coupling; can be tightened later.

---

## Phase 4 — Products & remaining services ✅

**Goal:** the banking product catalog — loans, deposits, cards, investments, FX.

### Delivered (`services/`)

| Service | Highlights | Tables |
|---------|-----------|--------|
| **loan-service** | Apply → approve → **disburse (credits borrower account via ledger gRPC)**; reducing-balance EMI calc. | `loan_loans` |
| emi-service | Generates & stores a full amortization schedule; pay-next-installment. | `emi_installments` |
| fixed-deposit-service | FD create with compound-annual maturity calc; list/get/close. | `fd_deposits` |
| recurring-deposit-service | RD create with monthly-compounding maturity; installment deposits. | `rd_deposits` |
| card-service | Issue card (crypto/rand PAN, **stores only masked number**), block/unblock. | `card_cards` |
| investment-service | Buy/sell holdings with weighted-average cost, portfolio view. | `inv_holdings` |
| currency-exchange-service | Seeded USD-based FX rates (public), authenticated convert. | `fx_rates` |

### Also delivered
- **`docker-compose.services.yaml`** — one-command local run of the whole platform
  (all 19 services + shared Postgres/Redis/Kafka), ports 81xx:
  `docker compose -f docker-compose.yaml -f docker-compose.services.yaml up -d --build`

### Verification
- `go build ./...` + `go vet ./...` — pass for all 7 new services.
- Live: FX `100 USD→EUR = 92.00`; FD `10000 @10%/12mo → 11000.00`;
  Loan `12000 @12%/12mo → EMI 1066.19` (standard formula); loan disbursement path
  reuses the Phase-3-verified ledger gRPC integration.

### Notes
- 5 of the 7 (fixed-deposit, recurring-deposit, card, investment, currency-exchange)
  were generated in parallel from the golden-path pattern, then centrally
  compiled/vetted — demonstrating the "service template" approach paying off.
- **Service count: 19 real microservices** built and compiling. Remaining ~11
  (Notification, Email, SMS, Fraud, Audit, Reports, Statement, Analytics, Search,
  Support, Admin) + API Gateway arrive in Phases 5–6.

---

## Phase 5 — Async, Risk & Insight ✅

**Goal:** the event-driven layer — services that CONSUME the Kafka events the
outbox emits (`banking.transactions`, `banking.payments`, `banking.wallet`).

### Shared kit addition
- `pkg/kafka` — added a transport-agnostic `Message` + `Consumer.Run(ctx, handler)`
  so consuming services never import the raw Kafka library.

### Delivered (`services/`)

| Service | Role | Consumes | Tables |
|---------|------|----------|--------|
| **audit-service** | immutable audit log (reference consumer) | all 3 topics | `audit_events` (JSONB) |
| **fraud-service** | rule-based fraud scoring → alerts | txns, payments | `fraud_alerts` |
| notification-service | in-app notifications | all 3 topics | `notification_notifications` |
| statement-service | per-account statement entries | transactions | `statement_entries` |
| reports-service | daily volume aggregates | transactions | `reports_daily` |
| analytics-service | per-type metrics | transactions | `analytics_metrics` |
| search-service | indexes events, ILIKE query | transactions | `search_index` |
| email-service / sms-service | mock channel senders (REST) | — | `email_messages` / `sms_messages` |

### 🐛 Real bug found & fixed by the live test
The shared database + goose's single `goose_db_version` table meant only the
**first** service's `0001` migration ran; every other service's `0001` was
treated as already-applied and skipped (so `auth_users` etc. were never
created). **Fix:** `pkg/postgres.Migrate` now takes the service name and uses a
**per-service version table** (`<service>_goose_version`). All 20 call sites
updated. This is a genuine consequence of the single-shared-DB decision — now
handled correctly.

### Verification — full pipeline exercised live
Ran Postgres + Kafka + ledger + transaction (outbox relay) + audit/fraud/statement,
then posted a 15000 deposit:
- outbox row published to Kafka (`sent_at` set) ✓
- audit-service recorded `banking.transactions` ✓
- fraud-service fired `large amount` (score 90) ✓
- statement-service wrote `CREDIT 15000.00 DEPOSIT` ✓

All 9 services also `go build` + `go vet` clean.

### Service count: **28 microservices** (+ template). Remaining for a full ~30:
Support & Admin (ops) — can fold into Phase 6 or a later pass. API Gateway +
React frontend is Phase 6.

---

## Phase 6 — API Gateway + React Frontend + Ops ✅

**Goal:** unify all services behind one door and give the platform a real UI.

### Delivered
- **api-gateway** (`services/api-gateway/`) — the single entry point:
  - Reverse-proxy routing table (`/api/v1/<resource>` → owning service) covering all 30 services.
  - Central **JWT validation** for protected resources; propagates `X-User-Id` /
    `X-User-Roles` to upstreams (services still enforce their own authz — defense in depth).
  - **CORS** for the SPA, global **rate limiting** (token bucket), request-ID +
    tracing + metrics from the shared kit.
- **support-service** (`support_tickets`) — customer tickets + staff triage.
- **admin-service** (`admin_settings`) — platform feature flags / settings (seeded).
- **React SPA** (`frontend/`, Vite): auth (login/register), dashboard, accounts
  (open + balance), transfer (with idempotency key), cards (issue/block), loans
  (apply). Talks to the gateway via `/api/v1`. Multi-stage Docker → nginx that
  serves the build and proxies `/api` to the gateway.

### Compose
`docker-compose.services.yaml` now includes **all 30 services + gateway + frontend**.
Full stack up with:
```
docker compose -f docker-compose.yaml -f docker-compose.services.yaml up -d --build
# SPA: http://localhost:3000   Gateway: http://localhost:8080
```

### Verification
- `go build` + `go vet` clean for api-gateway, support, admin.
- Frontend `npm run build` succeeds (44 modules → dist).
- **Gateway live test**: register through gateway (public→auth) ✓; protected
  route 401 without token ✓; proxied to account-service with token ✓; unknown
  route 404 ✓; CORS preflight 204 ✓.

### 🎉 Milestone: the APPLICATION is complete
**30 microservices + API gateway + React frontend**, all building and
spot-verified. Service inventory:
- Identity (6): auth, authz, customer, profile, kyc, document
- Core banking (6): ledger, account, transaction, beneficiary, payment, wallet
- Products (7): loan, emi, fixed-deposit, recurring-deposit, card, investment, currency-exchange
- Async/risk/insight (9): audit, fraud, notification, statement, reports, analytics, search, email, sms
- Ops/edge (3): support, admin, api-gateway

From here the work is **infrastructure & delivery**, not application code.

---

## Phase 7 — Containerization & local E2E on kind (+ Helm chart) ✅

**Goal:** prove the whole platform runs on real Kubernetes before touching AWS.
Ran on a GCP VM (`e2e-standard-8`, Ubuntu, kind) driven over SSH from the dev box.

### Delivered
- **Helm umbrella chart** (`deploy/helm/banking-platform/`) — pulled forward from
  Phase 10 so kind and EKS share one source of truth:
  - Generic `templates/services.yaml` renders Deployment + Service + optional HPA
    for **all 33 workloads** from the `services` map.
  - `templates/infra.yaml`: in-cluster Postgres + Kafka (StatefulSets) and Redis.
  - Shared ConfigMap + Secret; per-service env, gRPC ports, NodePort for
    gateway/frontend; hardened pod securityContext (non-root, read-only rootfs,
    drop ALL caps).
  - `values.yaml` + `values-dev.yaml` + `values-prod.yaml` (prod turns on HPA,
    higher replicas, ECR registry).
- **`build/service.Dockerfile`** upgraded with BuildKit cache mounts → 33 images
  build fast on repeat.
- kind cluster (extraPortMappings 30080/30081), all 33 images built + loaded,
  `helm install` → **35/35 pods Ready**.

### 🐛 Bugs found & fixed by running it for real (not just templating)
1. **runAsNonRoot vs distroless USER name** — distroless `USER nonroot` is a
   name; the kubelet needs a numeric UID to verify non-root. Added
   `runAsUser: 65532` to the security context.
2. **Helm YAML separator swallowed** — template whitespace trimming glued each
   `---` onto the previous Service's last line (`targetPort: 9090---`), so every
   Service merged into the next Deployment doc and only the last survived (4
   Services instead of 35). Rewrote `services.yaml` whitespace handling; verified
   the parser now sees 33 Deployments / 35 Services / 2 StatefulSets.
3. **nginx resolves upstream at startup** — frontend crashed if `api-gateway`
   wasn't resolvable yet. Switched to a `resolver` + variable `proxy_pass` so the
   gateway is resolved at request time.

### Verification (live, on kind)
Full flow through the gateway NodePort:
register → open account (**account→ledger gRPC**, acct# generated) → deposit
15000 (**transaction→ledger + outbox→Kafka**) → balance 15000.00 → statement
entry created by the **Kafka consumer** → `audit_events=1`, `fraud_alert "large
amount" (90)`, `outbox published=1`. Frontend serves the SPA and proxies `/api`.
All 35 pods 1/1 Ready.

### Test environment (reusable)
- GCP VM external IP `35.244.38.31`, user `claudecode-banking`, key
  `~/.ssh/gcp_banking_ed25519` (on the dev box).
- Repo synced to `~/banking_application_eks`; cluster `kind-banking`, namespace `banking`.
- Rebuild/redeploy: `helm upgrade banking deploy/helm/banking-platform -n banking -f .../values-dev.yaml`.
- **Stop the VM when idle** to save cost.

---

## Phase 8 — Terraform: Networking & IAM ✅

**Goal:** the modular AWS foundation for EKS. Author + validate only (no creds,
nothing provisioned). Add-ons stay out of Terraform (Helm/GitOps).

### Delivered (`terraform/`)
- **modules/vpc** — VPC, public+private subnets across 3 AZs, IGW, NAT
  gateway(s) (single for dev/qa, one-per-AZ for prod), public/private route
  tables + associations, and the EKS discovery tags
  (`kubernetes.io/role/elb`, `internal-elb`, `cluster/<name>=shared`).
- **modules/iam** — EKS cluster role (+`AmazonEKSClusterPolicy`), worker node
  role (+worker/CNI/ECR-readonly), and an ECR push policy for CI.
- **environments/dev, qa, prod** — each a root module wiring vpc+iam with its own
  CIDR (10.10/10.20/10.30), S3+DynamoDB backend stanza, and default_tags.
- `terraform/README.md` documents layout, usage, and state bootstrap.

### Decisions (per your choices)
- Terraform provisions **AWS only**; cluster add-ons via Helm/GitOps.
- Validation = `init -backend=false` + `validate` + `fmt` (no AWS spend).

### Verification
- `terraform validate` → **Success** for dev, qa, and prod.
- `terraform fmt -recursive -check` → clean across the whole tree.
- (Provider: `hashicorp/aws ~> 5.60`, Terraform `>= 1.5`.)

---

## Phase 9 — Terraform: EKS, ECR, S3 ✅

**Goal:** the compute + registry + storage layer, consuming Phase 8's VPC/IAM.
Author + validate only (no apply).

### Delivered (`terraform/`)
- **modules/eks** — EKS via `terraform-aws-modules/eks ~> 20.24`: managed node
  group in the private subnets, **IRSA/OIDC enabled**, cluster addons (CoreDNS,
  kube-proxy, VPC-CNI), reusing the Phase 8 cluster + node IAM roles
  (`create_iam_role = false`). API auth mode + creator admin permissions on.
- **modules/ecr** — a **single** repository (`banking-platform`) holding every
  service's images, separated by **tag prefix** (`<service>-<gitsha>`), with
  scan-on-push, AES256 encryption, and a keep-last-40 lifecycle policy.
  (ECR is a flat namespace — this is the native way to keep many services' images
  in one repo; CI pushes `…/banking-platform:auth-service-<sha>` etc.)
- **modules/s3** — private, encrypted, versioned bucket for documents/statements
  with full public-access block.
- **modules/route53** — apex hosted zone for `vijaygiduthuri.in` (outputs the 4
  nameservers to delegate at GoDaddy). Two-stage: `create_apex_record=false`
  (default) makes the zone only; `create_apex_record=true` (Phase 11/DNS) adds
  the apex **ALIAS A → Traefik NLB**, discovering the NLB by its
  `kubernetes.io/service-name=traefik/traefik` tag. Wired into `environments/dev`.
- dev/qa/prod wire all modules; prod uses larger nodes (t3.xlarge, 3–8) and
  per-AZ NAT.

### Verification
- `terraform validate` → **Success** for dev, qa, prod (EKS module resolved).
- `terraform fmt -check` → clean.
- Nothing applied; no AWS credentials used.

### Note on Phase 10
The **Helm umbrella chart was already delivered in Phase 7** and proven on kind,
so Phase 10 is complete. The prod overlay's image registry points at the ECR
repo; the CI in Phase 13 will push `banking-platform:<service>-<sha>` and bump
the Helm tag.

---

## Phase 14 — Observability ✅ (verified on kind)

**Goal:** metrics, logs and traces from every service, unified in Grafana with
metrics↔logs↔traces correlation. Deployed and verified on the kind cluster.

### Delivered (`deploy/observability/`)
- **OTel Collector** (contrib) — OTLP in from all services → **Tempo** (traces)
  and a Prometheus exporter (metrics). Stable name `otel-collector`.
- **kube-prometheus-stack** — Prometheus + Alertmanager + Grafana +
  node-exporter + kube-state-metrics; Grafana wired with Loki + Tempo
  datasources and log↔trace correlation (Loki derived field → Tempo;
  Tempo `tracesToLogsV2` → Loki).
- **Tempo** (traces), **Loki + Promtail** (pod stdout → Loki).
- `ServiceMonitor` scraping all `part-of=banking-platform` services' `/metrics`.
- Custom Grafana dashboard **Banking Platform — Services** (req rate, p95, 5xx).
- `install.sh` one-shot installer; `docs/observability.md` architecture doc.
- Platform `values-dev.yaml` now sets `OTEL_ENABLED=true` →
  `otel-collector.observability:4317`.

### Verified live (on kind, after generating traffic)
- **Metrics:** Prometheus scraping **31 banking targets**; `http_requests_total`
  climbing (1600+).
- **Traces:** Tempo returns real spans (services → collector → Tempo).
- **Logs:** Loki has `namespace="banking"` logs; **49 lines carrying `trace_id`**
  (log↔trace correlation data present).
- **Grafana:** healthy, datasources loaded. Exposed on the VM at
  **`<vm-ip>:30090`** (admin/admin) via a durable systemd port-forward unit.

### Notes
- Metrics come from direct `/metrics` scrape (richest data: http + Go runtime);
  the collector also has a metrics pipeline per the required architecture.
- Collector self-metrics (`otelcol_*`) aren't scraped (only the app-metrics
  exporter port is) — cosmetic; trace flow is proven directly via Tempo.

---

## How to resume

## Phase 13 — CI/CD (GitHub Actions) ✅

**Goal:** build → test → scan → push → bump Helm tag (GitOps handoff).

### Delivered
- **`.github/workflows/ci.yaml`**:
  1. **changes** — detect changed services (shared change → build all; manual
     `build_all` input).
  2. **build** (matrix per service) — `go test` + `vet` → `docker build`
     (build/service.Dockerfile) → **Trivy** scan (CRITICAL/HIGH, fail on fixable)
     → push to the single ECR repo as `<repo>:<service>-<sha>`.
  3. **frontend** — React → docker → Trivy → push `:frontend-<sha>`.
  4. **bump-and-commit** — `yq` bumps `global.image.tag=<sha>` in
     `values-prod.yaml`, commits `[skip ci]` (Argo CD picks it up in Phase 12).
- **`.github/workflows/terraform.yaml`** — fmt/init/validate for dev/qa/prod.
- AWS auth via **OIDC** (no static keys); PRs test+scan but don't push.
- Helm chart updated: `global.image.singleRepo` toggles
  `<registry>:<service>-<tag>` (ECR) vs `<registry>/<service>:<tag>` (local).
- `docs/cicd.md` documents the flow + required repo secrets/vars.

### Verification
- `actionlint` passes on both workflows (exit 0).
- Helm renders correctly in both image modes (dev per-service repos; prod single
  ECR repo with tag-prefix).
- Note: the pipeline runs on GitHub against AWS — not executed here; it's
  authored + statically validated. Requires repo vars `AWS_REGION`,
  `ECR_REPOSITORY` and secret `AWS_ROLE_ARN` (OIDC role with ECR push).

---

## Phase 12 — GitOps (Argo CD) ✅ (manifests authored)

**Goal:** declare the whole cluster in git and let Argo CD reconcile it
(automated sync + prune + selfHeal), via the **app-of-apps** pattern.

### Delivered (`deploy/argocd/`)
- **`bootstrap/project.yaml`** — AppProject `banking`: allowed `sourceRepos`
  (git + prometheus/grafana/otel/jetstack Helm repos) and destination namespaces
  (banking, observability, cert-manager, argocd).
- **`bootstrap/root-app.yaml`** — the app-of-apps root (`platform-root`); watches
  `deploy/argocd/apps/` recursively and creates every child Application.
- **`apps/banking-platform.yaml`** — the umbrella Helm chart → ns `banking`
  (keeps the StatefulSet `volumeClaimTemplates` `ignoreDifferences`).
- **`apps/cert-manager.yaml`** — jetstack cert-manager `v1.15.3` → ns
  `cert-manager` (Phase 11/TLS).
- **`apps/observability/*`** — `kube-prometheus-stack`, `loki-stack`, `tempo`,
  `otel-collector` (multi-source: chart from Helm repo + values from
  `deploy/observability/values/*.yaml` via a `$values` ref) + `extras.yaml`
  (directory source → `deploy/observability/manifests/` ServiceMonitor +
  dashboards ConfigMap).
- **`README.md`** — the one-time repoURL edit + two-command bootstrap.
- Moved `deploy/observability/{servicemonitor,dashboards-configmap}.yaml` into
  `deploy/observability/manifests/`; updated `install.sh` accordingly.

### Verification
- All 9 manifests YAML-parse clean (Application/AppProject).
- `docs/aws/04-argocd.md` (bootstrap), `06-observability.md` (GitOps option),
  `07-https-tls.md` (cert-manager) reconciled to reference the committed files.
- Note: bootstrap is authored, not applied here — needs the repo on GitHub +
  the repoURL placeholder (`YOUR_GH_USER`) replaced. Observability chart
  `targetRevision` is `"*"` (latest); pin for production.

---

## Helm chart restructure (per user request) ✅

Refactored the umbrella chart from one generic loop into **explicit per-service
files** with a **flat `values.yaml`** (one block per service):
- `templates/<service>.yaml` — each contains Deployment + Service + ConfigMap +
  Secret + HPA (32 files: 30 services + api-gateway + frontend).
- `templates/{postgres,redis,kafka}.yaml` (infra) and `templates/ingress.yaml`
  (Traefik, for Phase 11; disabled by default).
- `values.yaml` is flat: per-service `deploymentname/servicename/image/replicas/
  port/grpcPort/hpa/min/maxReplicas` + shared `db/redis/kafka/otel/s3/secrets`.
- Removed the old generic `services.yaml`/`config.yaml`/`infra.yaml` and the
  `values-dev/prod` overlays (single flat values now; CI patches per-service
  `image:`).
- **Bug found & fixed by redeploying on kind:** a Service named `postgres`
  made Kubernetes auto-inject `POSTGRES_PORT=tcp://…:5432`, colliding with our
  typed `POSTGRES_PORT` int (api-gateway panicked). Fixed with
  `enableServiceLinks: false` on every pod.
- CI `bump-and-commit` updated to patch each rebuilt service's `image:` in
  `values.yaml` (needs repo var `ECR_REGISTRY`).
- **Verified on kind:** helm upgrade → 35/35 pods Running; E2E through the
  gateway (deposit POSTED, balance 500.00); HPAs show live metrics
  (metrics-server installed).

---

## How to resume

Remaining: **12 GitOps (Argo CD)**, **11 Ingress/TLS**, **15–19** (HPA/VPA/
Cluster-Autoscaler, Argo Rollouts, Velero, security hardening, docs & diagrams).
Suggested next: **Phase 12 — GitOps (Argo CD)** — installable/testable on kind.
Awaiting approval.
