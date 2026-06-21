# GCP Infrastructure: Automated Predictive Pipeline

## 1. Architecture Overview

**Pattern:** Trigger-Action-Archive Cloud Scheduler invokes a Cloud Run job (Drive extraction) or a Workflows-based GitHub Actions dispatcher (Dataform pipeline). Extracted CSV data lands in GCS, is externalized to BigQuery, and flows through a medallion pipeline (source → contract → ml_data → ml_model → published). All infrastructure is managed via Terraform with a GCS backend for state locking.

**Event Flow (Daily):**
1. Cloud Scheduler (`midnight-trigger`) fires at 00:00 Asia/Manila.
2. Scheduler POSTs to Cloud Run Jobs API, executing `google-drive-extractor` as the `extractor-orchestration-sa` service account.
3. Extractor reads CSVs from Google Drive, uploads them to `marketing-archival-{env}` GCS bucket.
4. BigQuery external tables in `marketing_dataset` auto-detect new CSV partitions.

**Event Flow (Weekly, Monday 03:00 PHT):**
1. Cloud Scheduler (`weekly-prediction-trigger`) POSTs to Workflows API.
2. `github-actions-dispatcher` workflow calls GitHub Actions API using a PAT from Secret Manager.
3. GitHub Actions runs Dataform with `ml:predict` tag group, producing `predictions_nextweek`.

**Event Flow (Monthly, First Monday 02:00 PHT):**
1. Cloud Scheduler (`monthly-retrain-trigger`) POSTs to Workflows API.
2. `github-actions-dispatcher` workflow triggers `monthly-retrain` GitHub Actions run.
3. Dataform executes `ml:train` and `ml:evaluate` tag groups, retraining the BQML model.

---

## 2. Infrastructure Components (Inventory)

### Compute

| Resource | Type | Specs | Purpose |
| :--- | :--- | :--- | :--- |
| `google-drive-extractor-{env}` | Cloud Run Job | 1 vCPU, 1 GiB RAM, 900s timeout, max 2 retries | Executes the Python GDrive extractor; deploys via GitHub Actions CI/CD |
| `github-actions-dispatcher-{env}` | Cloud Workflows | N/A | Orchestrates GitHub Actions API calls for Dataform pipeline execution |

### Storage

| Resource | Type | Specs | Purpose |
| :--- | :--- | :--- | :--- |
| `marketing-archival-{env}` | GCS Bucket | `STANDARD` → `COLDLINE` after 400d, delete after 1095d (3y), uniform bucket-level access | Stores extracted CSVs, status markers, and run metadata |
| `marketing-terraform-state-vault-2026` | GCS Bucket (pre-provisioned) | Terraform backend | Stores Terraform state files at `terraform/state` prefix |
| `marketing-predictive-pipeline-{env}` | Artifact Registry | DOCKER format | Stores the extractor container image built by GitHub Actions |

### BigQuery

| Resource | Type | Location | Purpose |
| :--- | :--- | :--- | :--- |
| `marketing_dataset` | BQ Dataset | US | Houses external tables (`ext_campaign_registry`, `ext_marketing_spend_daily`) federated to GCS CSVs |
| `core_ecom_dataset` | BQ Dataset | US | Core e-commerce data (orders, products, users, order_items) managed externally |
| `source_dataset` | BQ Dataset | US | Pass-through views into `core_ecom_dataset` |
| `contracted_dataset` | BQ Dataset | US | Cleaned and joined contract tables (`marketing_data`, `ml_core_dataset`) |
| `published_dataset` | BQ Dataset | US | Terminal tables for predictions, evaluation, feature weights, and health monitoring |

### Orchestration

| Resource | Type | Schedule | Purpose |
| :--- | :--- | :--- | :--- |
| `midnight-trigger-{env}` | Cloud Scheduler | `every day 00:00` (Asia/Manila) | Invokes the GDrive extractor Cloud Run job daily |
| `weekly-prediction-trigger-{env}` | Cloud Scheduler | `every mon 03:00` (Asia/Manila) | Invokes `github-actions-dispatcher` with `event_type: "weekly-predict"` |
| `monthly-retrain-trigger-{env}` | Cloud Scheduler | `first monday of month 02:00` (Asia/Manila) | Invokes `github-actions-dispatcher` with `event_type: "monthly-retrain"` |

### Monitoring

| Resource | Type | Severity | Purpose |
| :--- | :--- | :--- | :--- |
| `scheduler_midnight_failure` | Alert Policy | CRITICAL | Alerts on Cloud Scheduler job failure for daily extraction |
| `extractor_failure` | Alert Policy | CRITICAL | Alerts on Cloud Run job ERROR logs from the extractor |
| `scheduler_weekly_failure` | Alert Policy | CRITICAL | Alerts on weekly prediction scheduler failure |
| `scheduler_monthly_failure` | Alert Policy | CRITICAL | Alerts on monthly retrain scheduler failure |
| `github_actions_dispatcher_failure` | Alert Policy | CRITICAL | Alerts on Workflows execution ERROR for the dispatcher |
| `weekly_prediction_failure` | Alert Policy | CRITICAL | Alerts on GitHub Actions workflow failure for weekly predictions |
| `monthly_retrain_failure` | Alert Policy | CRITICAL | Alerts on GitHub Actions workflow failure for monthly retrain |

All alert policies notify the three email channels (`engineer`, `manager`, `admin`) and auto-close after 6 hours with 30-minute re-notification intervals.

---

## 3. Identity & Security Matrix

### 3.1 Identity Registry

| Identity Name | Role / Primary Responsibility |
| :--- | :--- |
| `drive-extractor-sa` | Runtime: Reads Google Drive files, writes CSVs to GCS archival bucket |
| `dataform-pipeline-sa` | Runtime: Manages BigQuery datasets/tables/views and reads GCS objects during Dataform execution |
| `github-actions-deployer-sa` | CI/CD: Deploys all Terraform-managed resources via GitHub Actions with WIF |
| `extractor-orchestration-sa` | Orchestration: Invokes the Cloud Run extractor job from Cloud Scheduler |
| `dataform-orchestration-sa` | Orchestration: Invokes Cloud Workflows and writes logs; accesses `github-token` secret for GitHub API calls |

### 3.2 Permission Bindings

| Identity | Target | Roles | Rationale |
| :--- | :--- | :--- | :--- |
| `github-actions-deployer-sa` | Project | `run.developer`, `workflows.editor`, `cloudscheduler.admin`, `artifactregistry.admin`, `eventarc.admin`, `storage.admin`, `resourcemanager.projectIamAdmin`, `iam.workloadIdentityPoolAdmin`, `monitoring.admin`, `iam.serviceAccountAdmin`, `iam.serviceAccountUser`, `iam.admin`, `logging.configWriter`, `logging.logWriter`, `bigquery.admin`, `serviceusage.serviceUsageAdmin`, `secretmanager.admin` | Full infrastructure lifecycle management: compute, storage, IAM, monitoring, APIs, and secrets |
| | Self (SA) | `iam.workloadIdentityUser` | Allow GitHub OIDC token to impersonate this SA |
| `drive-extractor-sa` | GCS Bucket `marketing-archival-{env}` | `storage.objectAdmin` | Full CRUD for data landing and archival |
| `dataform-pipeline-sa` | Project | `bigquery.admin`, `storage.objectViewer` | Execute Dataform SQL and read GCS CSVs federated to BigQuery external tables |
| `extractor-orchestration-sa` | Project | `run.invoker` | Invoke the extractor Cloud Run job |
| `dataform-orchestration-sa` | Project | `workflows.invoker`, `logging.logWriter` | Trigger Workflows executions and write logs |
| | Secret `github-token` | `secretmanager.secretAccessor` | Read GitHub PAT for API authentication in the dispatcher workflow |

### 3.3 Trust Policy (Workload Identity Federation)

| GitHub Secret | Source / Origin | Condition |
| :--- | :--- | :--- |
| `WIF_PROVIDER` | `google_iam_workload_identity_pool_provider.github_provider` | `attribute.repository == "{github_repo}"` |
| `DEPLOYER_SA_EMAIL` | `google_service_account.github-actions-deployer-sa.email` | N/A |

The WIF provider maps GitHub OIDC token claims to GCP principal attributes:
- `google.subject` ← `assertion.sub`
- `attribute.actor` ← `assertion.actor`
- `attribute.repository` ← `assertion.repository`

Only the configured `github_repo` (`BLMgithub/automated-predictive-pipeline`) is permitted to authenticate.

---

## 4. Operational Decisions & Constraints (ADRs)

### 4.1 Cloud Run Job Image Managed Externally
- **Decision:** The Cloud Run job's container image is excluded from Terraform lifecycle management via `ignore_changes` on `template[0].template[0].containers[0].image`.
- **Rationale:** The image is built and pushed by GitHub Actions CI/CD, not by Terraform. Allowing Terraform to manage the image tag would cause drift on every deployment and prevent roll-forward updates.
- **Mitigation:** GitHub Actions uses the deployer SA to update the Cloud Run job with the new image tag after `terraform apply`.

### 4.2 State Bucket Pre-Provisioned
- **Decision:** The Terraform backend GCS bucket (`marketing-terraform-state-vault-2026`) must exist before `terraform init`.
- **Rationale:** Terraform cannot create its own backend bucket during initialization. A bootstrap step (manual or via a separate root module) creates the bucket first.
- **Mitigation:** Documented in the `main.tf` comment. The bucket is not managed by this Terraform root module.

### 4.3 Broad Deployer SA Permissions
- **Decision:** The `github-actions-deployer-sa` holds 16 project-level roles including `roles/resourcemanager.projectIamAdmin` and `roles/iam.admin`.
- **Rationale:** The deployer manages the full infrastructure lifecycle compute, storage, IAM, monitoring, APIs in a single root module. Granular SA-per-resource would require significant refactoring without reducing blast radius, since all resources are in one project.
- **Mitigation:** The WIF provider restricts authentication to a single GitHub repository. The `github-actions-deployer-sa` is never used for runtime execution purpose-specific SAs handle each workload.

### 4.4 Cloud Scheduler Uses OAuth Token, Not OIDC
- **Decision:** Scheduler jobs use `oauth_token` with a service account email directly, rather than OIDC.
- **Rationale:** Cloud Scheduler natively supports OAuth token authentication to Cloud Run and Workflows. OIDC adds complexity without benefit for intra-GCP service-to-service calls.
- **Mitigation:** Each scheduler job uses a dedicated orchestration SA with the minimal `roles/run.invoker` or `roles/workflows.invoker` role.

### 4.5 No Staging/Production Environment Separation in Terraform Workspaces
- **Decision:** Environment is parameterized via `var.environment` suffixed on resource names, not via Terraform workspaces or separate root modules.
- **Rationale:** Single-environment deployment (dev). Resource naming convention (`{name}-{env}`) prevents collisions and allows future multi-environment extension with a simple variable change.
- **Consequence:** Adding a production environment requires either a second `terraform.tfvars` file or a wrapper script that sets `-var="environment=prod"`.

---

## 5. Post-Provisioning (Handshake)

### Required Outputs for CI/CD

| Output / Value | Destination | Purpose |
| :--- | :--- | :--- |
| `GITHUB_WIF_PROVIDER_NAME` (from `wif.tf` output) | GitHub Actions Secret: `WIF_PROVIDER` | WIF authentication from GitHub Actions to GCP |
| `github-actions-deployer-sa` email | GitHub Actions Secret: `DEPLOYER_SA_EMAIL` | SA impersonation target for `google-github-actions/auth` |
| `extractor-orchestration-sa` email | Cloud Scheduler `oauth_token` | Invoke extractor job (embedded in Terraform, not a post-provisioning step) |
| `dataform-orchestration-sa` email | Cloud Scheduler `oauth_token` + Workflows SA | Invoke dispatcher workflow (embedded in Terraform) |
| `github-token` (Secret Manager) | Manual population required | GitHub PAT with `actions:write` scope for the dispatcher workflow |

### Manual Provisioning Steps
1. Create the Terraform state bucket: `gsutil mb gs://marketing-terraform-state-vault-2026`
2. Run `terraform init` with the GCS backend.
3. Run `terraform apply` to provision all resources.
4. Populate the `github-token` secret in Secret Manager with a GitHub PAT.
5. Set GitHub Actions secrets: `WIF_PROVIDER` (from `terraform output`) and `DEPLOYER_SA_EMAIL`.
6. Share the Google Drive `marketing_upload-folder` with the `drive-extractor-sa` email.
