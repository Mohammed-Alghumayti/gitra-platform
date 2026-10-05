<p align="center">
  <img src="docs/images/gitra-logo.png" alt="Gitra logo" width="420">
</p>

# Gitra Platform — Internal Git & CI/CD Platform on Azure

An internal GitLab CE platform deployed on Microsoft Azure, built as a 3-person bootcamp project. The platform gives the team a single place for source control, code review, and CI/CD pipelines — publicly reachable, so supervisors and other students can use it, with security built in.

**Fully automatic:** after a one-time setup, every push to `Testing` deploys everything with GitHub Actions — nobody needs to log in to a server.

**Live environment:** the team's Azure VM (`20.55.88.3`), served over HTTPS at `https://<dns-label>.<region>.cloudapp.azure.com` (shown in each workflow run's summary).

## Team & Workstreams

| Member | Workstream | Folder | Status |
|---|---|---|---|
| **Member 1** — Nasser | Azure Infrastructure & Terraform | `terraform/` | ✅ Complete |
| **Member 2** — Faisal | GitLab & CI/CD Configuration | `sample-app/`, runner | ✅ Complete |
| **Member 3** — Mohammed | Docker, Bash Automation & Operations | `docker-compose*.yaml`, `scripts/`, `.github/` | ✅ Complete |

---

## Architecture Overview

```
                    GitHub — push to Testing
                               │
                    GitHub Actions (deploy.yml)
          ┌────────────────────┼────────────────────────┐
          ▼                    ▼                        ▼
   Azure: existing VM     Terraform (Member 1)     GitLab API
   static IP, DNS name,   creates the runner VM    demo project + pipeline
   NSG, deploy user       (state in Azure Storage)
          │                    │
          ▼                    ▼
   GitLab VM  (existing, 20.55.88.3)              Runner VM  (gitra-runner-vm)
   NSG: 22, 80, 443, 2224                          NSG: 22, 5000
   ┌───────────────────────────┐                   ┌───────────────────────────┐
   │ GitLab CE (Docker)        │ ◄──── HTTPS ───── │ GitLab Runner (Docker)    │
   │ HTTPS · Let's Encrypt     │  jobs + clone     │ CI jobs: test → build     │
   │ data + secrets live here  │                   │ staging app :5000         │
   └───────────────────────────┘                   └───────────────────────────┘
     Docker + Bash Automation (Member 3)             CI/CD Pipeline (Member 2)
```

## Repository layout

```
gitra-platform/
├── .github/workflows/deploy.yml   # Fully automatic deployment (every push to Testing)
├── terraform/                     # Member 1 — runner VM on Azure
│   ├── providers.tf                # azurerm + remote state in Azure Storage
│   ├── variables.tf, main.tf
│   ├── network.tf                  # VNet, subnet, static public IP, NIC
│   ├── security.tf                 # Runner NSG (22, 5000)
│   ├── vm.tf                       # Runner VM (SSH keys only)
│   ├── cloud-init-runner.yaml.tftpl  # Docker, fail2ban, start runner
│   ├── outputs.tf
│   └── tests/plan.tftest.hcl       # `terraform test` with a mocked Azure provider
├── docker-compose.yaml            # Member 3 — GitLab CE (GitLab VM)
├── docker-compose.runner.yaml     # GitLab Runner (runner VM)
├── scripts/                       # Member 3
│   ├── deploy.sh                   # Storage folders + launch GitLab
│   ├── health_check.sh             # Waits for GitLab to become reachable
│   ├── harden_gitlab.sh            # Sign-up approval, mandatory 2FA, password policy
│   ├── deploy_runner.sh            # Launch the runner (runner VM)
│   ├── register_runner.sh          # Register the runner with GitLab
│   ├── backup.sh                   # Creates and exports a GitLab backup
│   ├── setup.sh                    # Installs Docker (manual install path)
│   └── ci/                         # Used by the GitHub Actions workflow
│       ├── azure_prepare_gitlab_vm.sh  # Static IP, DNS name, NSG, deploy user
│       ├── remote_deploy_gitlab.sh     # Deploys GitLab on the VM (keeps existing data)
│       ├── gitlab_bootstrap.rb         # Root password, runner token, temp token
│       └── push_demo_app.sh            # Pushes sample-app/ and waits for its pipeline
├── sample-app/                    # Member 2 — demo Flask app + pipeline
└── docs/images/                   # Logo
```

---

## Automatic deployment

### One-time setup (~10 minutes, from the browser)

**1. Create the Azure credentials and SSH key** — open [Azure Cloud Shell](https://shell.azure.com) (Bash) and run:

```bash
SUB=$(az account show --query id -o tsv)
az ad sp create-for-rbac --name gitra-github-actions --role Contributor \
  --scopes /subscriptions/$SUB --json-auth
ssh-keygen -t rsa -b 4096 -N "" -C gitra-deploy -f ~/gitra_deploy
cat ~/gitra_deploy
```

The first command prints a JSON block; the last one prints a private key. Keep both for the next step.

**2. Add three secrets on GitHub** — repository **Settings → Secrets and variables → Actions → New repository secret**:

| Secret | Value |
|---|---|
| `AZURE_CREDENTIALS` | The whole JSON block from step 1 |
| `SSH_PRIVATE_KEY` | The whole private key from step 1 (`-----BEGIN … END …-----`) |
| `GITLAB_ROOT_PASSWORD` | A strong password for GitLab's `root` (12+ characters, not a common word) |

Optional, under the **Variables** tab: `GITLAB_VM_IP` (default `20.55.88.3`) and `DNS_LABEL` (default `gitra-<8 chars>`).

**3. Run it** — **Actions → Deploy Gitra Platform → Run workflow** (or just push to `Testing`).

### What every run does

| Step | What happens |
|---|---|
| 1. Prepare GitLab VM | Finds the VM by its IP, starts it if stopped, makes the IP static, adds a free DNS name, opens ports 22/80/443/2224 in its NSG if needed, adds the `gitra-deploy` user with the SSH key |
| 2. Deploy GitLab | Pulls this branch to `/opt/gitra-platform`, moves any existing GitLab data there (nothing is lost), starts GitLab with HTTPS, applies the security settings |
| 3. Runner VM | Terraform creates/updates `gitra-runner-vm` in `gitra-runner-rg` (state kept in Azure Storage, so runs don't duplicate anything) |
| 4. Bootstrap | Sets `root`'s password from the secret and registers the runner (only when needed) |
| 5. Demo app | Pushes `sample-app/` to GitLab and waits for its pipeline: **test → build → deploy_staging** |

The run's **Summary** page shows the GitLab URL, the demo project and the staging app URL. Re-running is safe: every step is idempotent.

### After the first run

- Log in at the GitLab URL as `root` with `GITLAB_ROOT_PASSWORD`, and set up 2FA when asked.
- Supervisors and students click **Register**; approve them under **Admin → Users → Pending approval**. They set up 2FA on first login.
- To change `root`'s password, change the secret — the next run applies it.

### Manual install (without GitHub Actions)

```bash
git clone -b Testing https://github.com/Mohammed-Alghumayti/gitra-platform.git
cd gitra-platform && chmod +x scripts/*.sh
./scripts/setup.sh && newgrp docker
cp .env.example .env               # set GITLAB_EXTERNAL_URL
./scripts/deploy.sh && ./scripts/health_check.sh && ./scripts/harden_gitlab.sh
```

> Changing `GITLAB_EXTERNAL_URL` needs `docker compose down && docker compose up -d` — a restart does not re-read it. The workflow handles this automatically.

### Backups

```bash
sudo /opt/gitra-platform/scripts/backup.sh [destination_dir]    # on the GitLab VM
```

---

## Security decisions

Two risks came up while designing the platform. This is how each one is solved.

### Problem 1 — CI jobs could take over the GitLab server

**Risk:** the runner needs the Docker socket (`/var/run/docker.sock`) so jobs can `docker build` and run the staging app. Whoever controls Docker controls the machine, so any `.gitlab-ci.yml` could read GitLab's secrets or delete its data if the runner shared GitLab's VM.

**Solution: the runner has its own VM.**
- GitLab stays on the team's existing VM; Terraform creates a separate `gitra-runner-vm` for the runner. They use separate compose files (`docker-compose.yaml`, `docker-compose.runner.yaml`).
- The runner talks to GitLab only over HTTPS, like any user. GitLab's data and secrets are not on the runner VM.
- Worst case, a malicious job compromises the runner VM — the next workflow run rebuilds it while GitLab is unaffected.

### Problem 2 — The site must be public, but safely

**Risk:** supervisors and other students need to reach GitLab, so we can't restrict it to the team's IPs. But a public site on plain HTTP exposes passwords, and open sign-up lets anyone create accounts and run CI jobs.

**Solution: public, with protection at every layer.**

| Layer | Protection | Where |
|---|---|---|
| Encryption | HTTPS with a free Let's Encrypt certificate on a free Azure DNS name; HTTP redirects to HTTPS | `azure_prepare_gitlab_vm.sh`, `docker-compose.yaml` |
| Accounts | Anyone can register, but an admin must approve each account | `harden_gitlab.sh` |
| Login | 2FA mandatory for every user (48h grace period); minimum 12-character passwords | `harden_gitlab.sh` |
| Code visibility | Projects can't be made public — code is visible to signed-in users only | `harden_gitlab.sh` |
| Brute force | GitLab's built-in rate limiting on logins; fail2ban on admin SSH | GitLab default, deploy scripts |
| Server access | SSH keys only; the deploy user is added through Azure, no passwords | `azure_prepare_gitlab_vm.sh`, `vm.tf` |
| Network | Each VM opens only the ports it needs | NSGs |
| Pipeline secrets | Passwords and tokens are masked in logs, passed via stdin/env files (never on a command line), and the temporary GitLab token is revoked at the end of every run | `deploy.yml` |

### Network Security Group (NSG) rules

| VM | Rule | Port | Purpose |
|---|---|---|---|
| GitLab | Allow-SSH-Admin | 22 | Server administration (keys only + fail2ban) |
| GitLab | Allow-HTTP | 80 | Redirect to HTTPS + Let's Encrypt validation |
| GitLab | Allow-HTTPS | 443 | GitLab web interface |
| GitLab | Allow-GitLab-SSH | 2224 | Git clone / push / pull over SSH |
| Runner | Allow-SSH-Admin | 22 | Server administration (keys only + fail2ban) |
| Runner | Allow-Staging-App | 5000 | Sample app deployed by the pipeline |

Git SSH is on **2224** so it never conflicts with the VM's admin SSH on 22.

### Other measures
- **Permissions:** `./gitlab` and `./runner` are `root`-owned with mode `700`.
- **Secrets out of Git:** `.gitignore` excludes `gitlab/`, `runner/`, `.env`, backups, Terraform state and `terraform.tfvars`.
- **Containers:** the sample app runs as a non-root user.
- **Least privilege for automation:** the Azure service principal has Contributor on the subscription only (it can't grant permissions to anyone).

### Still to do
- [ ] Pin the GitLab and runner image versions instead of `latest`.
- [ ] Keep encrypted backups off the VM (e.g. Azure Blob Storage).
- [ ] Serve the staging app over HTTPS too (it's a demo app on plain HTTP today).

---

## Member 1 — Azure Infrastructure & Terraform

Terraform manages the runner VM; the GitLab VM already existed and is prepared by the workflow.

| Resource | Name | Notes |
|---|---|---|
| Resource group | `gitra-runner-rg` | Everything for the runner; kept apart from the existing `gitra-rg` (GitLab VM) |
| Virtual network / subnet | `gitra-runner-vnet` / `gitra-runner-subnet` | `10.20.0.0/16` / `10.20.1.0/24` |
| Public IP | `gitra-runner-pip` | Static |
| NSG | `gitra-runner-nsg` | 22, 5000 |
| Runner VM | `gitra-runner-vm` | `Standard_B2s` (2 vCPU, 4 GB), 32 GB Premium SSD, Ubuntu 22.04 |
| State storage | `gitra-tfstate-rg` / `gitratf…` | Created by the workflow; keeps Terraform state between runs |

Local checks without Azure: `terraform init -backend=false && terraform validate && terraform test`.

## Member 2 — GitLab & CI/CD

- **Runner:** `gitlab-runner` container on the runner VM, Docker executor, registered automatically by the workflow.
- **Sample app:** a Flask app with `/` and `/health`, unit-tested with pytest, packaged with a non-root Dockerfile. Pushed to GitLab as `root/internal-demo-app` by the workflow.
- **Pipeline (`sample-app/.gitlab-ci.yml`):**

| Stage | Job | What it does |
|---|---|---|
| test | `test` | `pip install` + `pytest` |
| build | `build` | `docker build`, tagged with the commit SHA |
| deploy | `deploy_staging` | Replaces the `internal-demo-app-staging` container on port 5000 of the runner VM and checks `/health` (default branch only) |

## Member 3 — Docker, Bash Automation & Operations

| VM | Volume (host) | Container path | Contents |
|---|---|---|---|
| GitLab | `/opt/gitra-platform/gitlab/config` | `/etc/gitlab` | Configuration, secrets, certificates |
| GitLab | `/opt/gitra-platform/gitlab/logs` | `/var/log/gitlab` | Logs |
| GitLab | `/opt/gitra-platform/gitlab/data` | `/var/opt/gitlab` | Databases and repositories |
| Runner | `~/gitra-platform/runner` | `/etc/gitlab-runner` | Runner config + token |

---

## Testing

| Check | Result |
|---|---|
| `terraform fmt -check`, `validate`, `test` (mocked Azure: runner config, SSH keys only, exact NSG ports, staging URL) | ✅ Pass |
| `actionlint` on the workflow (incl. shellcheck of every step) | ✅ Pass |
| `shellcheck` on all scripts, `yamllint`, `docker compose config` | ✅ Pass |
| `pytest` (sample app) + Docker build/run (`/`, `/health`, non-root user) | ✅ Pass |
| `remote_deploy_gitlab.sh` against a simulated existing GitLab: data moved to `/opt`, nothing lost, security settings applied | ✅ Pass |
| `gitlab_bootstrap.rb`: root password, runner token, temporary token | ✅ Pass |
| Runner deploy + registration + `gitlab-runner verify` | ✅ Pass |
| `push_demo_app.sh`: project created, app pushed, pipeline started | ✅ Pass |
| First real run on Azure (Azure CLI steps, Let's Encrypt, full pipeline) | ⏳ Needs the one-time setup |

## Acceptance Criteria

- [x] GitLab is installed and reachable through Docker automation
- [x] Docker Compose brings the platform up reliably with persistent storage
- [x] Secrets and runtime data are excluded from version control
- [x] Azure infrastructure is defined with Terraform (Member 1)
- [x] A sample CI/CD pipeline is defined and the runner is wired to GitLab (Member 2)
- [x] The full end-to-end workflow is automated and documented
- [x] The design reflects enterprise practice (isolated runner, HTTPS, approval + 2FA, least-privilege network)
- [ ] First automatic deployment run on Azure
