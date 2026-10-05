<p align="center">
  <img src="docs/images/gitra-logo.png" alt="Gitra logo" width="420">
</p>

# Gitra Platform — Internal Git & CI/CD Platform on Azure

An internal GitLab CE platform deployed on Microsoft Azure, built as a 3-person bootcamp project. The platform gives the team a single place for source control, code review, and CI/CD pipelines — publicly reachable, so supervisors and other students can use it, with security built in.

**Live environment:** `http://20.55.88.3` "for Now" (Azure VM, Ubuntu 22.04 LTS). After `terraform apply`: `https://<dns_label>.<location>.cloudapp.azure.com`.

## Team & Workstreams

| Member | Workstream | Folder | Status |
|---|---|---|---|
| **Member 1** — Nasser | Azure Infrastructure & Terraform | `terraform/` | ✅ Complete |
| **Member 2** — Faisal | GitLab & CI/CD Configuration | `sample-app/`, runner | ✅ Complete |
| **Member 3** — Mohammed | Docker, Bash Automation & Operations | `docker-compose*.yaml`, `scripts/` | ✅ Complete |

---

## Architecture Overview

```
                         INFRASTRUCTURE — Terraform (Member 1)
                Resource Group · VNet · 2 NSGs · 2 Static IPs · 2 VMs
                                       │
             ┌─────────────────────────┴─────────────────────────┐
             ▼                                                   ▼
   GitLab VM  (Standard_D2s_v3)                        Runner VM  (Standard_B2s)
   NSG: 22, 80, 443, 2224                              NSG: 22, 5000
   ┌───────────────────────────┐                       ┌───────────────────────────┐
   │ GitLab CE (Docker)        │ ◄──── HTTPS ───────── │ GitLab Runner (Docker)    │
   │ HTTPS · Let's Encrypt     │   jobs + clone        │ CI jobs: test → build     │
   │ data + secrets live here  │                       │ staging app :5000         │
   └───────────────────────────┘                       └───────────────────────────┘
        Docker + Bash Automation (Member 3)               CI/CD Pipeline (Member 2)
```

## Repository layout

```
gitra-platform/
├── terraform/                     # Member 1 — Azure infrastructure
│   ├── providers.tf, variables.tf, main.tf
│   ├── network.tf                  # VNet, subnet, 2 static public IPs (+ DNS name), 2 NICs
│   ├── security.tf                 # One NSG per VM, minimal ports
│   ├── vm.tf                       # GitLab VM + runner VM (SSH keys only)
│   ├── cloud-init-gitlab.yaml.tftpl  # Docker, fail2ban, deploy, health check, hardening
│   ├── cloud-init-runner.yaml.tftpl  # Docker, fail2ban, start runner
│   ├── outputs.tf                  # URLs, IPs, SSH commands
│   ├── terraform.tfvars.example
│   └── tests/plan.tftest.hcl       # `terraform test` with a mocked Azure provider
├── docker-compose.yaml            # Member 3 — GitLab CE (GitLab VM)
├── docker-compose.runner.yaml     # GitLab Runner (runner VM)
├── .env.example                   # GITLAB_EXTERNAL_URL (cloud-init writes .env)
├── scripts/                       # Member 3
│   ├── setup.sh                    # Installs Docker (manual install path)
│   ├── deploy.sh                   # GitLab VM: storage folders + launch GitLab
│   ├── health_check.sh             # Waits for GitLab to become reachable
│   ├── harden_gitlab.sh            # Sign-up approval, mandatory 2FA, password policy
│   ├── deploy_runner.sh            # Runner VM: launch the runner
│   ├── register_runner.sh          # Runner VM: register with GitLab (once)
│   └── backup.sh                   # Creates and exports a GitLab backup
├── sample-app/                    # Member 2 — demo Flask app + pipeline
└── docs/images/                   # Logo
```

---

## Quick start

### 1. Provision Azure (Terraform)

Requires [Terraform](https://developer.hashicorp.com/terraform/install) ≥ 1.7, the Azure CLI (`az login`) and an SSH key pair.

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # set subscription_id and a unique dns_label
terraform init
terraform test                                 # optional: checks the config without Azure
terraform plan
terraform apply
```

On first boot (~10 minutes), cloud-init does everything on both VMs: installs Docker and fail2ban, clones this repo, starts GitLab with HTTPS (Let's Encrypt), applies the security settings, and starts the runner.

### 2. Log in to GitLab

Open the `gitlab_url` output. Get the initial `root` password (expires after 24h — change it and set up 2FA right away):

```bash
ssh azureuser@<gitlab_public_ip>
sudo docker exec gitlab_server grep 'Password:' /etc/gitlab/initial_root_password
```

### 3. Register the runner (once)

In GitLab: **Admin → CI/CD → Runners → New instance runner** (tick *Run untagged jobs*), copy the `glrt-…` token, then on the **runner VM**:

```bash
ssh azureuser@<runner_public_ip>
cd ~/gitra-platform && ./scripts/register_runner.sh <glrt-token>
```

### 4. Run the pipeline

Create a project in GitLab and push the contents of `sample-app/` to it. The pipeline runs **test → build → deploy_staging**, and the app is served at the `staging_app_url` output. See [`sample-app/README.md`](sample-app/README.md).

### 5. Invite people

Supervisors and students open the GitLab URL and click **Register**. Their account stays pending until an admin approves it (**Admin → Users → Pending approval**). On first login they must set up 2FA.

### Backups

```bash
./scripts/backup.sh [destination_dir]    # on the GitLab VM, default: ~/gitlab-backups
```

---

## Security decisions

Two risks came up while designing the platform. This is how each one is solved.

### Problem 1 — CI jobs could take over the GitLab server

**Risk:** the runner needs the Docker socket (`/var/run/docker.sock`) so jobs can `docker build` and run the staging app. Whoever controls Docker controls the machine, so any `.gitlab-ci.yml` could read GitLab's secrets or delete its data if the runner shared GitLab's VM.

**Solution: the runner has its own VM.**
- Terraform creates a separate `gitra-runner-vm`; GitLab and the runner are split into `docker-compose.yaml` and `docker-compose.runner.yaml`.
- The runner talks to GitLab only over HTTPS, like any user. GitLab's data and secrets are not on the runner VM.
- Worst case, a malicious job compromises the runner VM — it can be rebuilt with `terraform apply` while GitLab is unaffected.

### Problem 2 — The site must be public, but safely

**Risk:** supervisors and other students need to reach GitLab, so we can't restrict it to the team's IPs. But a public site on plain HTTP exposes passwords, and open sign-up lets anyone create accounts and run CI jobs.

**Solution: public, with protection at every layer.**

| Layer | Protection | Where |
|---|---|---|
| Encryption | HTTPS with a free Let's Encrypt certificate on a free Azure DNS name; HTTP redirects to HTTPS | `network.tf` (`dns_label`), `docker-compose.yaml` |
| Accounts | Anyone can register, but an admin must approve each account | `harden_gitlab.sh` |
| Login | 2FA mandatory for every user (48h grace period); minimum 12-character passwords | `harden_gitlab.sh` |
| Code visibility | Projects can't be made public — code is visible to signed-in users only | `harden_gitlab.sh` |
| Brute force | GitLab's built-in rate limiting on logins; fail2ban on admin SSH | GitLab default, cloud-init |
| Server access | SSH keys only, no passwords, on both VMs | `vm.tf` |
| Network | Each VM opens only the ports it needs | `security.tf` |

### Network Security Group (NSG) rules

| VM | Rule | Port | Purpose |
|---|---|---|---|
| GitLab | Allow-SSH-Admin | 22 | Server administration (keys only + fail2ban) |
| GitLab | Allow-HTTP | 80 | Redirect to HTTPS + Let's Encrypt validation |
| GitLab | Allow-HTTPS | 443 | GitLab web interface |
| GitLab | Allow-GitLab-SSH | 2224 | Git clone / push / pull over SSH |
| Runner | Allow-SSH-Admin | 22 | Server administration (keys only + fail2ban) |
| Runner | Allow-Staging-App | 5000 | Sample app deployed by the pipeline |

Git SSH is on **2224** so it never conflicts with the VM's admin SSH on 22. Sources are public by default (`user_source_cidrs`); admin SSH can optionally be narrowed with `admin_source_cidrs`.

### Other measures
- **Permissions:** `./gitlab` and `./runner` are `root`-owned with mode `700`.
- **Secrets out of Git:** `.gitignore` excludes `gitlab/`, `runner/`, `.env`, backups, Terraform state and `terraform.tfvars`.
- **Containers:** the sample app runs as a non-root user.
- **Backups:** `backup.sh` also exports `gitlab-secrets.json` and `gitlab.rb`; treat the backup folder as sensitive.

### Still to do
- [ ] Pin the GitLab and runner image versions instead of `latest`.
- [ ] Keep encrypted backups off the VM (e.g. Azure Blob Storage), and store Terraform state remotely.
- [ ] Serve the staging app over HTTPS too (it's a demo app on plain HTTP today).

---

## Member 1 — Azure Infrastructure & Terraform

| Resource | Name | Notes |
|---|---|---|
| Resource group | `gitra-rg` | `terraform destroy` removes everything |
| Virtual network / subnet | `gitra-vnet` / `gitra-subnet` | `10.10.0.0/16` / `10.10.1.0/24` |
| Public IPs | `gitra-gitlab-pip`, `gitra-runner-pip` | Static; GitLab's has the DNS name used for HTTPS |
| NSGs | `gitra-gitlab-nsg`, `gitra-runner-nsg` | One per VM, attached to its NIC |
| GitLab VM | `gitra-gitlab-vm` | `Standard_D2s_v3` (2 vCPU, 8 GB), 64 GB Premium SSD |
| Runner VM | `gitra-runner-vm` | `Standard_B2s` (2 vCPU, 4 GB), 32 GB Premium SSD |

Both VMs run Ubuntu 22.04. Names use the `project_name` prefix (default `gitra`). Key variables: `location`, `dns_label`, `vm_size`, `runner_vm_size`, `repo_branch`.

## Member 2 — GitLab & CI/CD

- **Runner:** `gitlab-runner` container on the runner VM, Docker executor, registered with `register_runner.sh`.
- **Sample app:** a Flask app with `/` and `/health`, unit-tested with pytest, packaged with a non-root Dockerfile.
- **Pipeline (`sample-app/.gitlab-ci.yml`):**

| Stage | Job | What it does |
|---|---|---|
| test | `test` | `pip install` + `pytest` |
| build | `build` | `docker build`, tagged with the commit SHA |
| deploy | `deploy_staging` | Replaces the `internal-demo-app-staging` container on port 5000 of the runner VM and checks `/health` (default branch only) |

## Member 3 — Docker, Bash Automation & Operations

| VM | Volume (host) | Container path | Contents |
|---|---|---|---|
| GitLab | `./gitlab/config` | `/etc/gitlab` | Configuration, secrets, certificates |
| GitLab | `./gitlab/logs` | `/var/log/gitlab` | Logs |
| GitLab | `./gitlab/data` | `/var/opt/gitlab` | Databases and repositories |
| Runner | `./runner` | `/etc/gitlab-runner` | Runner config + token |

Changing `GITLAB_EXTERNAL_URL` needs `docker compose down && docker compose up -d` — a restart does not re-read it.

---

## Testing

| Check | Result |
|---|---|
| `terraform fmt -check`, `init`, `validate` | ✅ Pass |
| `terraform test` (mocked Azure: separate VMs, HTTPS URL, hardening in cloud-init, SSH keys only, exact NSG ports) | ✅ 3 passed |
| Both cloud-init templates render to valid YAML | ✅ Pass |
| `shellcheck scripts/*.sh`, `yamllint`, `docker compose config` (both files) | ✅ Pass |
| `pytest` (sample app) + Docker build/run (`/`, `/health`, non-root user) | ✅ Pass |
| `deploy.sh` → `health_check.sh` → `harden_gitlab.sh` on a real GitLab container | ✅ Pass |
| `deploy_runner.sh` → `register_runner.sh` → `gitlab-runner verify` | ✅ Pass |
| `.gitlab-ci.yml` via GitLab CI Lint, pipeline picked up by the runner | ✅ Pass |
| `terraform apply`, Let's Encrypt certificate, full pipeline run | ⏳ To run on Azure |

## Acceptance Criteria

- [x] GitLab is installed and reachable through Docker automation
- [x] Docker Compose brings the platform up reliably with persistent storage
- [x] Secrets and runtime data are excluded from version control
- [x] Azure infrastructure is defined with Terraform (Member 1)
- [x] A sample CI/CD pipeline is defined and the runner is wired to GitLab (Member 2)
- [x] The full end-to-end workflow is documented
- [x] The design reflects enterprise practice (isolated runner, HTTPS, approval + 2FA, least-privilege network)
- [ ] Infrastructure applied on Azure and a pipeline run demonstrated end to end
