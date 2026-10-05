<p align="center">
  <img src="docs/images/gitra-logo.png" alt="Gitra logo" width="420">
</p>

# Gitra Platform — Internal Git & CI/CD Platform on Azure

An internal GitLab CE platform deployed on Microsoft Azure, built as a 3-person bootcamp project. The platform gives the team a single place for source control, code review, and CI/CD pipelines.

**Live environment:** `http://20.55.88.3` "for Now" (Azure VM, Ubuntu 22.04 LTS)

## Team & Workstreams

| Member | Workstream | Folder | Status |
|---|---|---|---|
| **Member 1** — Nasser | Azure Infrastructure & Terraform | `terraform/` | ✅ Complete |
| **Member 2** — Faisal | GitLab & CI/CD Configuration | `sample-app/`, runner | ✅ Complete |
| **Member 3** — Mohammed | Docker, Bash Automation & Operations | `docker-compose.yaml`, `scripts/` | ✅ Complete |

---

## Architecture Overview

```
             INFRASTRUCTURE
                  │
            Terraform   (Member 1)      → Resource Group, VNet, NSG, Static IP, VM
                  │
                  ▼
              Azure VM   (Ubuntu 22.04, cloud-init runs deploy.sh on first boot)
                  │
                  ▼
      Docker + Bash Automation   (Member 3)
                  │
                  ▼
     GitLab CE  ◄── gitlab-network ──►  GitLab Runner
                  │
          SOFTWARE DELIVERY
                  │
       CI/CD Pipeline   (Member 2)      → test → build → deploy (staging :5000)
```

## Repository layout

```
gitra-platform/
├── terraform/                  # Member 1 — Azure infrastructure
│   ├── providers.tf             # azurerm provider
│   ├── variables.tf             # Inputs (region, VM size, allowed IPs, repo branch…)
│   ├── main.tf                  # Resource group
│   ├── network.tf               # VNet, subnet, static public IP, NIC
│   ├── security.tf              # NSG + rules
│   ├── vm.tf                    # Ubuntu 22.04 VM (SSH keys only)
│   ├── cloud-init.yaml.tftpl    # First boot: Docker → clone repo → deploy.sh
│   ├── outputs.tf               # IP, GitLab URL, SSH command
│   └── terraform.tfvars.example
├── docker-compose.yaml         # Member 3 — GitLab CE + GitLab Runner
├── .env.example                # GITLAB_EXTERNAL_URL (cloud-init writes .env)
├── scripts/                    # Member 3
│   ├── setup.sh                 # Installs Docker (manual install path)
│   ├── deploy.sh                # Creates storage folders and launches the stack
│   ├── health_check.sh          # Waits for GitLab to become reachable
│   ├── register_runner.sh       # Registers the runner with GitLab (once)
│   └── backup.sh                # Creates and exports a GitLab backup
├── sample-app/                 # Member 2 — demo Flask app + pipeline
│   ├── app.py, test_app.py, requirements.txt, Dockerfile
│   └── .gitlab-ci.yml           # test → build → deploy_staging
├── docs/images/                # Logo
└── gitlab/, runner/            # Runtime data on the VM (git-ignored)
```

---

## Quick start

### 1. Provision Azure (Terraform)

Requires [Terraform](https://developer.hashicorp.com/terraform/install) ≥ 1.5, the Azure CLI (`az login`) and an SSH key pair.

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # set subscription_id and your IPs
terraform init
terraform plan
terraform apply
```

Outputs give you `gitlab_url`, `ssh_command` and `public_ip`. On first boot, cloud-init installs Docker, clones this repo (`repo_branch`, default `Testing`), writes `.env` with the VM's IP, and runs `deploy.sh`. The repo must be public for the clone to work (or change `repo_url`).

### 2. Wait for GitLab

```bash
ssh azureuser@<public_ip>
cd ~/gitra-platform
./scripts/health_check.sh          # polls every 10s, 5 min default timeout
sudo docker exec -it gitlab_server grep 'Password:' /etc/gitlab/initial_root_password
```

Open `http://<public_ip>` and log in as `root` (the generated password expires after 24h).

### 3. Register the runner (once)

In GitLab: **Admin → CI/CD → Runners → New instance runner** (tick *Run untagged jobs*), copy the `glrt-…` token, then:

```bash
./scripts/register_runner.sh <glrt-token>
```

### 4. Run the pipeline

Create a project in GitLab and push the contents of `sample-app/` to it. The pipeline runs **test → build → deploy_staging**, and the app is served at `http://<public_ip>:5000`. See [`sample-app/README.md`](sample-app/README.md).

### Manual install (existing VM, no Terraform)

```bash
git clone -b Testing https://github.com/Mohammed-Alghumayti/gitra-platform.git
cd gitra-platform
chmod +x scripts/*.sh
./scripts/setup.sh && newgrp docker
cp .env.example .env               # set GITLAB_EXTERNAL_URL to the VM's address
./scripts/deploy.sh
./scripts/health_check.sh
```

> Changing `GITLAB_EXTERNAL_URL` needs `docker compose down && docker compose up -d` — a restart does not re-read it.

### Backups

```bash
./scripts/backup.sh [destination_dir]    # default: ~/gitlab-backups
```

---

## Member 1 — Azure Infrastructure & Terraform

| Resource | Name | Notes |
|---|---|---|
| Resource group | `gitra-rg` | Everything lives here; `terraform destroy` removes it all |
| Virtual network / subnet | `gitra-vnet` / `gitra-subnet` | `10.10.0.0/16` / `10.10.1.0/24` |
| Public IP | `gitra-pip` | **Static**, so `external_url` and clone links never change |
| NSG | `gitra-nsg` | Attached to the subnet, rules below |
| VM | `gitra-vm` | `Standard_D2s_v3` (2 vCPU, 8 GB), 64 GB Premium SSD, Ubuntu 22.04 |

All names use the `project_name` prefix (default `gitra`). Key variables: `location`, `vm_size`, `admin_source_cidrs`, `user_source_cidrs`, `repo_branch`.

### Network Security Group (NSG) rules

| Rule | Port | Allowed from | Purpose |
|---|---|---|---|
| Allow-SSH-Admin | 22 | `admin_source_cidrs` | Remote server administration |
| Allow-HTTP | 80 | `user_source_cidrs` | GitLab web interface |
| Allow-HTTPS | 443 | `user_source_cidrs` | Future encrypted connection (SSL/TLS) |
| Allow-GitLab-SSH | 2224 | `user_source_cidrs` | Git clone / push / pull over SSH |
| Allow-Staging-App | 5000 | `user_source_cidrs` | Sample app deployed by the pipeline |

The internal Git SSH port is mapped to **2224** instead of 22, to avoid conflicting with the VM's own administrative SSH port.

---

## Member 2 — GitLab & CI/CD

- **Runner:** `gitlab-runner` container in `docker-compose.yaml`, Docker executor, on the same `gitlab-network` as GitLab. Jobs clone from `http://gitlab_server` internally, so they don't depend on the public IP.
- **Sample app:** a Flask app with `/` and `/health`, unit-tested with pytest, packaged with a non-root Dockerfile.
- **Pipeline (`sample-app/.gitlab-ci.yml`):**

| Stage | Job | What it does |
|---|---|---|
| test | `test` | `pip install` + `pytest` |
| build | `build` | `docker build`, tagged with the commit SHA |
| deploy | `deploy_staging` | Replaces the `internal-demo-app-staging` container on port 5000 and checks `/health` (default branch only) |

---

## Member 3 — Docker, Bash Automation & Operations

Deploys GitLab CE and the runner as Docker containers with persistent bind-mounted storage, plus the scripts to install, deploy, health-check, register the runner and back up.

| Volume (host) | Container path | Contents |
|---|---|---|
| `./gitlab/config` | `/etc/gitlab` | Configuration, secrets, certificates |
| `./gitlab/logs` | `/var/log/gitlab` | Logs |
| `./gitlab/data` | `/var/opt/gitlab` | Databases and repositories |
| `./runner` | `/etc/gitlab-runner` | Runner config + token |

---

## Security

**In place**
- **Network:** only ports 22, 80, 443, 2224 and 5000 are open, each through its own NSG rule, with configurable source IPs.
- **SSH separation:** Git uses 2224 and admin SSH uses 22, so each can be restricted on its own.
- **VM login:** SSH keys only; password authentication is disabled by Terraform.
- **Permissions:** `./gitlab` and `./runner` are `root`-owned with mode `700`, so other VM users can't read GitLab's secrets.
- **Secrets out of Git:** `.gitignore` excludes `gitlab/`, `runner/`, `.env`, backups, Terraform state and `terraform.tfvars`.
- **Containers:** the sample app runs as a non-root user.
- **Backups:** `backup.sh` also exports `gitlab-secrets.json` and `gitlab.rb`; treat the backup folder as sensitive.
- **Root password:** the generated one expires after 24h. Change it on first login.

**To do before real use**
- [ ] Enable HTTPS: set `GITLAB_EXTERNAL_URL=https://<domain>` and `letsencrypt['enable'] = true`. Port 80 is plaintext today.
- [ ] Set `admin_source_cidrs` / `user_source_cidrs` to the team's IPs (defaults allow everyone).
- [ ] Disable public sign-up and enforce 2FA (Admin → Settings → General).
- [ ] Pin the GitLab and runner image versions instead of `latest`.
- [ ] The runner mounts the Docker socket, which gives CI jobs root-level access to the VM — only run trusted projects on it.
- [ ] Keep encrypted backups off the VM (e.g. Azure Blob Storage), and store Terraform state remotely.

---

## Testing

What was verified for this branch:

| Check | Result |
|---|---|
| `terraform fmt -check`, `terraform init`, `terraform validate` | ✅ Pass |
| cloud-init template renders to valid YAML | ✅ Pass |
| `shellcheck scripts/*.sh` | ✅ Pass |
| `yamllint` + `docker compose config` | ✅ Pass |
| `pytest` (sample app) | ✅ 2 passed |
| Docker build + run of the sample app (`/`, `/health`, non-root user) | ✅ Pass |
| `deploy.sh` → `health_check.sh` (GitLab up in ~3 min, folders `700 root`) | ✅ Pass |
| `register_runner.sh` + `gitlab-runner verify` | ✅ Pass |
| `.gitlab-ci.yml` via GitLab CI Lint, pipeline picked up by the runner | ✅ Pass |
| `terraform apply` on Azure and a full pipeline run | ⏳ To run on Azure (needs Azure credentials and internet for job images) |

## Acceptance Criteria

- [x] GitLab is installed and reachable through Docker automation
- [x] Docker Compose brings the platform up reliably with persistent storage
- [x] Secrets and runtime data are excluded from version control
- [x] Azure infrastructure is defined with Terraform (Member 1)
- [x] A sample CI/CD pipeline is defined and the runner is wired to GitLab (Member 2)
- [x] The full end-to-end workflow is documented
- [ ] Infrastructure applied on Azure and a pipeline run demonstrated end to end
- [ ] Items under **Security → To do** are closed
