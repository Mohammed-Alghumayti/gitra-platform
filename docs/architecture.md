# Gitra Platform — Architecture

> Part of the project documentation: **Architecture** · [Deployment & Operations](deployment.md) · [Troubleshooting & Change Log](troubleshooting.md)

## What this covers

Gitra is an internal Git and CI/CD platform built on **GitLab CE**, running on **Microsoft Azure**. It gives the team one place for source control, code review (merge requests) and CI/CD pipelines. It is publicly reachable so supervisors and other students can use it, with security at every layer, and it is deployed **fully automatically** by GitHub Actions.

| Member | Workstream | Main folders |
|---|---|---|
| **Member 1** — Nasser | Azure Infrastructure & Terraform | `terraform/` |
| **Member 2** — Faisal | GitLab & CI/CD Configuration | `sample-app/`, runner |
| **Member 3** — Mohammed | Docker, Bash Automation & Operations | `docker-compose*.yaml`, `scripts/`, `.github/` |

---

## System overview

```
                     GitHub — push to Testing
                                │
                     GitHub Actions (deploy.yml)
           ┌────────────────────┼────────────────────────┐
           ▼                    ▼                        ▼
   Azure: GitLab VM       Terraform (Member 1)      GitLab API
   start, static IP,      runner VM + network       demo project
   DNS name, NSG,         (state in Azure Storage)  + pipeline
   deploy user
           │                    │
           ▼                    ▼
  GitLab VM (gitra-gitlab-vm)                   Runner VM (gitra-runner-vm)
  East US · Standard_D4s_v4 · 16 GB             West US 2 · Standard_B2s_v2
  NSG: 22, 80, 443, 2224                        NSG: 22, 5000
  ┌──────────────────────────────┐              ┌──────────────────────────────┐
  │ GitLab CE (Docker)           │ ◄── HTTPS ── │ GitLab Runner (Docker)       │
  │ HTTPS · Let's Encrypt        │  jobs, clone │ docker executor              │
  │ data + secrets live here     │              │ staging app on :5000         │
  └──────────────────────────────┘              └──────────────────────────────┘
       Docker & automation (Member 3)               CI/CD pipeline (Member 2)
```

### Key design decisions

| Decision | Why |
|---|---|
| **GitLab and the runner on separate VMs** | The runner mounts the Docker socket so jobs can build images, which gives jobs root-level control of their VM. Keeping it away from GitLab means a malicious `.gitlab-ci.yml` can't reach GitLab's data or secrets. |
| **Runner VM in another region** | The subscription allows 4 vCPUs **per region**; the GitLab VM uses all 4 in East US. The runner talks to GitLab only over HTTPS, so distance doesn't matter. |
| **Public, but hardened** | Supervisors and students need access, so IP allow-lists aren't an option. Instead: HTTPS, admin-approved sign-up, mandatory 2FA, private code. |
| **Everything in Docker** | Isolated from the host OS, easy to upgrade (change the image), identical everywhere. |
| **Infrastructure as Code** | Terraform defines the runner VM; the workflow can rebuild it at any time and changes are reviewed in Git. |
| **Idempotent automation** | Every deployment step is safe to re-run, so a failed run can simply be run again. |

---

## Member 1 — Azure Infrastructure & Terraform

### What this covers
Terraform provisions everything the CI runner needs on Azure. The GitLab VM already existed; the deploy workflow prepares it with the Azure CLI (see [Deployment](deployment.md)).

### Repository layout
```
terraform/
├── providers.tf                 # azurerm provider + remote state backend (Azure Storage)
├── variables.tf                 # Inputs: region, VM size, SSH key, GitLab URL, allowed CIDRs…
├── main.tf                      # Resource group (gitra-runner-rg)
├── network.tf                   # VNet, subnet, static public IP, NIC
├── security.tf                  # Runner NSG (22, 5000) + NIC association
├── vm.tf                        # Ubuntu 22.04 runner VM, SSH keys only
├── cloud-init-runner.yaml.tftpl # First boot: Docker, fail2ban, clone repo, start runner
├── outputs.tf                   # Runner IP, SSH command, staging URL
├── terraform.tfvars.example     # Only needed for manual runs
└── tests/plan.tftest.hcl        # terraform test with a mocked Azure provider
```

### Resources
| Resource | Name | Notes |
|---|---|---|
| Resource group | `gitra-runner-rg` | Runner only — kept apart from `gitra-rg` (GitLab VM) |
| Virtual network / subnet | `gitra-runner-vnet` / `gitra-runner-subnet` | `10.20.0.0/16` / `10.20.1.0/24` |
| Public IP | `gitra-runner-pip` | Static, Standard SKU |
| NSG | `gitra-runner-nsg` | 22, 5000 |
| VM | `gitra-runner-vm` | First 2-vCPU size with capacity (currently `Standard_B2s_v2`), 32 GB Premium SSD |
| State storage | `gitra-tfstate-rg` / `gitratf…` | Created by the workflow; keeps Terraform state between runs |

### Notable implementation details
- **Remote state** in Azure Storage, so every GitHub Actions run sees the same infrastructure.
- **`replace_triggered_by`** rebuilds the subnet with its VNet and the NIC–NSG link with the NIC — a subnet has no region of its own, so Terraform wouldn't notice it was gone after a region move.
- **`prevent_deletion_if_contains_resources = false`** lets `gitra-runner-rg` be replaced on a region move even if a failed attempt left a disk behind (safe: that group only holds the runner).
- **Tests without Azure:** `terraform test` with a mock provider checks the runner config, SSH-key-only login, exact NSG ports, the staging URL, and that names never reuse the existing `gitra-rg` / `gitra-gitlab-vm`.

---

## Member 2 — GitLab & CI/CD

### What this covers
The GitLab runner that executes pipelines, a demo application, and its CI/CD pipeline.

### Repository layout
```
docker-compose.runner.yaml   # GitLab Runner container (runner VM)
sample-app/
├── app.py                   # Flask app: / and /health
├── test_app.py              # pytest tests
├── requirements.txt
├── Dockerfile               # python:3.12-slim, runs as a non-root user
├── .gitlab-ci.yml           # test → build → deploy_staging
└── README.md
```

### Runner
- `gitlab-runner` container on the runner VM, **Docker executor** (every job runs in a fresh container).
- Registered automatically by the workflow; talks to GitLab over HTTPS.

### Pipeline
| Stage | Job | What it does |
|---|---|---|
| test | `test` | `pip install` + `pytest` (image `python:3.12`) |
| build | `build` | `docker build`, tagged with the commit SHA and `latest` |
| deploy | `deploy_staging` | Replaces the `internal-demo-app-staging` container on port 5000 and checks `/health` (default branch only) |

If a stage fails, the next ones don't run — broken code never reaches staging.

---

## Member 3 — Docker, Bash Automation & Operations

### What this covers
Running GitLab in Docker with persistent storage, the scripts to deploy, health-check, harden and back it up, and the GitHub Actions workflow that automates everything.

### Repository layout
```
docker-compose.yaml              # GitLab CE (GitLab VM)
.env.example                     # GITLAB_EXTERNAL_URL (the workflow writes .env)
scripts/
├── deploy.sh                    # Storage folders + launch GitLab
├── health_check.sh              # Waits until GitLab is really ready (/-/readiness + HTTP)
├── harden_gitlab.sh             # Sign-up approval, 2FA, password policy, no public projects
├── deploy_runner.sh             # Launch the runner (runner VM)
├── register_runner.sh           # Register the runner with GitLab
├── backup.sh                    # Backup + gitlab-secrets.json + gitlab.rb
├── setup.sh                     # Installs Docker (manual path)
└── ci/                          # Used by the workflow
    ├── azure_prepare_gitlab_vm.sh   # Start VM, static IP, DNS name, NSG, deploy user
    ├── remote_deploy_gitlab.sh      # Deploy GitLab, keep data, repair permissions
    ├── gitlab_bootstrap.rb          # Root password, runner token, temporary token
    ├── run_gitlab_bootstrap.sh      # Runs it over SSH (secrets via stdin, retries)
    └── push_demo_app.sh             # Push sample-app/ and wait for its pipeline
.github/workflows/deploy.yml     # The automatic deployment
```

### Persistent storage
| VM | Host path | Container path | Contents |
|---|---|---|---|
| GitLab | `/opt/gitra-platform/gitlab/config` | `/etc/gitlab` | Configuration, secrets, certificates |
| GitLab | `/opt/gitra-platform/gitlab/logs` | `/var/log/gitlab` | Logs |
| GitLab | `/opt/gitra-platform/gitlab/data` | `/var/opt/gitlab` | Database, repositories, uploads |
| Runner | `~/gitra-platform/runner` | `/etc/gitlab-runner` | Runner config + token |

The parent `./gitlab` folder is `root:700`. The mounted subfolders are managed by GitLab itself — its internal users (`git`, `gitlab-www`, `gitlab-psql`…) need their own permissions there.

---

## Network

| VM | Rule | Port | Purpose |
|---|---|---|---|
| GitLab | Allow-SSH-Admin | 22 | Server administration (keys only + fail2ban) |
| GitLab | Allow-HTTP | 80 | Redirect to HTTPS + Let's Encrypt validation |
| GitLab | Allow-HTTPS | 443 | GitLab web interface |
| GitLab | Allow-GitLab-SSH | 2224 | Git clone / push / pull over SSH |
| Runner | Allow-SSH-Admin | 22 | Server administration (keys only + fail2ban) |
| Runner | Allow-Staging-App | 5000 | Demo app deployed by the pipeline |

Git SSH uses **2224** so it never conflicts with the VM's own admin SSH on 22, and each can be restricted separately.

---

## Security model

| Layer | Protection | Where |
|---|---|---|
| Encryption | HTTPS with a free Let's Encrypt certificate on a free Azure DNS name; HTTP redirects to HTTPS | `azure_prepare_gitlab_vm.sh`, `docker-compose.yaml` |
| Accounts | Anyone can register, but an admin must approve each account | `harden_gitlab.sh` |
| Login | 2FA mandatory (48h grace period); passwords ≥ 12 characters | `harden_gitlab.sh` |
| Code | Projects can't be public — visible to signed-in users only | `harden_gitlab.sh` |
| Brute force | GitLab's login rate limiting; fail2ban on SSH | GitLab, deploy scripts |
| Servers | SSH keys only, no passwords; deploy user added through Azure | `azure_prepare_gitlab_vm.sh`, `vm.tf` |
| Network | Each VM opens only the ports it needs | NSGs |
| Isolation | CI jobs run on a separate VM from GitLab's data | Architecture |
| Files | Parent data folder `root:700`; GitLab manages the rest | `deploy.sh` |
| Git | `.gitignore` excludes `gitlab/`, `runner/`, `.env`, backups, Terraform state, `*.tfvars` | `.gitignore` |
| Automation secrets | GitHub Secrets; masked in logs; passed via stdin / root-only env files, never on a command line; temporary GitLab token revoked every run | `deploy.yml`, `run_gitlab_bootstrap.sh` |
| Automation identity | Service principal with Contributor on the subscription (can't grant permissions) | Azure |
| Containers | The demo app runs as a non-root user | `sample-app/Dockerfile` |
