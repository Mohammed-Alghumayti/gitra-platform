<p align="center">
  <img src="docs/images/gitra-logo.png" alt="Gitra logo" width="420">
</p>

# Gitra Platform — Internal Git & CI/CD Platform on Azure

An internal GitLab CE platform deployed on Microsoft Azure, built as a 3-person bootcamp project. The platform gives the team a single place for source control, code review, and CI/CD pipelines — publicly reachable, so supervisors and other students can use it, with security built in.

**Fully automatic:** after a one-time setup, every push to `Testing` deploys everything with GitHub Actions — nobody needs to log in to a server.

**Live environment:** [https://gitra-25ee91e6.eastus.cloudapp.azure.com](https://gitra-25ee91e6.eastus.cloudapp.azure.com) — the team's Azure VM (`20.55.88.3`, East US), over HTTPS. The staging app URL is shown in each workflow run's summary.

## Documentation

| Document | Contents |
|---|---|
| [Architecture](docs/architecture.md) | System design, each member's part, network and security model |
| [Deployment & Operations](docs/deployment.md) | One-time setup, what each deployment does, starting/stopping servers, backups, what's safe to delete |
| [Troubleshooting & Change Log](docs/troubleshooting.md) | Every problem we hit and how we fixed it, common issues, what's left to improve |

## Team & Workstreams

| Member | Workstream | Folder | Status |
|---|---|---|---|
| **Member 1** — Nasser | Azure Infrastructure & Terraform | `terraform/gitlab`, `terraform/runner` | ✅ Complete |
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
   GitLab VM  (gitra-gitlab-vm, East US)          Runner VM  (gitra-runner-vm, West US 2)
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
├── terraform/                     # Member 1 — Azure infrastructure (two configs, two state files)
│   ├── gitlab/                     # GitLab platform: RG, VNet, subnet, NSG, public IP, NIC, VM
│   │   ├── main.tf, network.tf, security.tf, vm.tf, variables.tf, outputs.tf
│   │   ├── import_existing.sh      # Adopts the existing platform into Terraform (no recreate)
│   │   └── tests/platform.tftest.hcl
│   └── runner/                     # CI runner: RG, VNet, subnet, NSG, public IP, NIC, VM
│       ├── main.tf, network.tf, security.tf, vm.tf, variables.tf, outputs.tf
│       ├── cloud-init-runner.yaml.tftpl  # Docker, fail2ban, start runner
│       └── tests/plan.tftest.hcl
├── docker-compose.yaml            # Member 3 — GitLab CE (GitLab VM)
├── docker-compose.runner.yaml     # GitLab Runner (runner VM)
├── scripts/                       # Member 3
│   ├── deploy.sh                   # Storage folders + launch GitLab
│   ├── health_check.sh             # Waits until GitLab is really ready (/-/readiness + HTTP)
│   ├── harden_gitlab.sh            # Sign-up approval, mandatory 2FA, password policy
│   ├── harden_ssh.sh               # Admin SSH: keys only, no password login
│   ├── deploy_runner.sh            # Launch the runner (runner VM)
│   ├── register_runner.sh          # Register the runner with GitLab
│   ├── backup.sh                   # Creates and exports a GitLab backup
│   ├── restore.sh                  # Restores GitLab from a backup.sh folder
│   ├── setup.sh                    # Installs Docker (manual install path)
│   └── ci/                         # Used by the GitHub Actions workflow
│       ├── azure_prepare_gitlab_vm.sh  # Static IP, DNS name, NSG, deploy user
│       ├── remote_deploy_gitlab.sh     # Deploys GitLab on the VM (keeps data, repairs permissions)
│       ├── gitlab_bootstrap.rb         # Root password, runner token, temp token
│       ├── run_gitlab_bootstrap.sh     # Runs it over SSH (secrets via stdin, retries)
│       └── push_demo_app.sh            # Pushes sample-app/ and waits for its pipeline
├── sample-app/                    # Member 2 — demo Flask app + pipeline
└── docs/                        # architecture.md, deployment.md, troubleshooting.md, images/
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

Optional, under the **Variables** tab: `GITLAB_VM_IP` (default `20.55.88.3`), `DNS_LABEL` (default `gitra-<8 chars>`), `RUNNER_LOCATION` and `RUNNER_VM_SIZE` (by default the workflow tries several small 2-vCPU sizes in `westus2`, `centralus`, `eastus2`, `westus3`, `northeurope` and uses the first one Azure has capacity for).

**3. Run it** — **Actions → Deploy Gitra Platform → Run workflow** (or just push to `Testing`).

### What every run does

| Step | What happens |
|---|---|
| 0. GitLab platform | Terraform imports the existing platform (first run only) and plans; applies only if nothing would be deleted, replaced or modified |
| 1. Prepare GitLab VM | Finds the VM by its IP, starts it if stopped, makes the IP static, adds a free DNS name, opens ports 22/80/443/2224 in its NSG if needed, adds the `gitra-deploy` user with the SSH key |
| 2. Deploy GitLab | Pulls this branch to `/opt/gitra-platform`, moves any existing GitLab data there (nothing is lost), starts GitLab with HTTPS, repairs file permissions if GitLab can't read its own files, waits until it's ready, applies the security settings, turns off password login for admin SSH (keys only), sets `root`'s password from the secret |
| 3. Runner VM | Terraform creates/updates `gitra-runner-vm` in `gitra-runner-rg` (state kept in Azure Storage, so runs don't duplicate anything). An existing runner VM keeps its size and region (no resize); a new one tries several sizes and regions until Azure has capacity, cleaning up after each failed attempt. Starts the runner VM if it's stopped |
| 4. Runner registration | Registers the runner with GitLab (only when needed) |
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

### Backup and restore

```bash
# On the GitLab VM
sudo /opt/gitra-platform/scripts/backup.sh /root/gitlab-backups     # backup + gitlab-secrets.json + gitlab.rb
sudo /opt/gitra-platform/scripts/restore.sh /root/gitlab-backups    # restores the newest backup
```

`restore.sh` checks that the backup's GitLab version matches the running one, restores the secrets first (without them CI variables, runner tokens and 2FA can't be decrypted), stops the services that write to the database, restores, restarts and runs GitLab's own checks. Full steps: [Deployment & Operations](docs/deployment.md#backup-and-restore).

### Server access (admin SSH)

Admin SSH on the GitLab VM accepts **keys only** — password login is turned off by every deployment (`harden_ssh.sh`). To add your own key, see [Deployment & Operations](docs/deployment.md#server-access-admin-ssh). Without SSH, use **Azure portal → VM → Run command**.

---

## Design decision — two VMs instead of single-node

The project spec proposes a **single-node** deployment (GitLab and runner on one VM) for simplicity. We deliberately use **two VMs** instead:

| | Single-node (spec) | Two VMs (what we built) |
|---|---|---|
| Security | CI jobs control Docker on the same machine as GitLab — any `.gitlab-ci.yml` could read GitLab's secrets or delete its data | CI jobs can only reach the runner VM; GitLab's data and secrets are not there |
| Performance | Builds compete with GitLab for CPU and memory | GitLab keeps its whole VM |
| Azure quota | Needs a bigger VM in East US, where the 4-vCPU quota is already used | Runner fits in another region's quota |
| Recovery | A broken runner can take GitLab down with it | The runner VM is disposable — the next run rebuilds it |
| Cost | One VM | One extra small VM (~$30–40/month; stop it when not needed) |

Everything else in the spec is kept: one GitLab instance in Docker, Terraform for the infrastructure, persistent storage, a working CI runner. The runner is the spec's *optional CI runner configuration*, placed where it can't hurt the platform. Details: [Architecture](docs/architecture.md#why-two-vms-instead-of-single-node).

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
| Server access | Admin SSH accepts keys only (password login off, root login off); the deploy user's key is added through Azure | `harden_ssh.sh`, `azure_prepare_gitlab_vm.sh`, `terraform/runner/vm.tf` |
| Network | Each VM opens only the ports it needs | NSGs |
| Pipeline secrets | Passwords and tokens are masked in logs, passed via stdin/env files (never on a command line), and the temporary GitLab token is revoked at the end of every run | `deploy.yml` |

### Network Security Group (NSG) rules

| VM | Rule | Port | Purpose |
|---|---|---|---|
| GitLab | default-allow-ssh | 22 | Server administration (keys only + fail2ban) |
| GitLab | Allow-HTTP | 80 | Redirect to HTTPS + Let's Encrypt validation |
| GitLab | Allow-HTTPS | 443 | GitLab web interface |
| GitLab | Allow-GitLab-SSH | 2224 | Git clone / push / pull over SSH |
| Runner | Allow-SSH-Admin | 22 | Server administration (keys only + fail2ban) |
| Runner | Allow-Staging-App | 5000 | Sample app deployed by the pipeline |

Git SSH is on **2224** so it never conflicts with the VM's admin SSH on 22.

### Other measures
- **Permissions:** the parent `./gitlab` folder and `./runner` are `root`-owned with mode `700`. GitLab's mounted subfolders are left to GitLab (see *Problems we hit* below).
- **Secrets out of Git:** `.gitignore` excludes `gitlab/`, `runner/`, `.env`, backups, Terraform state and `terraform.tfvars`.
- **Containers:** the sample app runs as a non-root user.
- **Least privilege for automation:** the Azure service principal has Contributor on the subscription only (it can't grant permissions to anyone).

### Still to do
- [ ] Pin the GitLab and runner image versions instead of `latest`.
- [ ] Keep encrypted backups off the VM (e.g. Azure Blob Storage).
- [ ] Serve the staging app over HTTPS too (it's a demo app on plain HTTP today).

## Problems we hit — and how we solved them

The first real deployments on Azure surfaced problems that local tests couldn't. Each was reproduced or diagnosed from the logs, fixed, and verified before pushing.

### Setup

| Problem | Cause | Fix |
|---|---|---|
| Clone links and redirects pointed to the wrong address | `external_url` was `http://localhost` | Set automatically to the VM's HTTPS DNS name |
| GitLab's secrets were readable by every VM user | Storage folders were `chmod 777` | Lock the parent `./gitlab` folder to `root:700` |
| Name clash with the existing VM | The GitLab VM lives in `gitra-rg`, the name Terraform also used | Runner resources renamed `gitra-runner-*`; a Terraform test guards it |

### Azure

| Problem | Cause | Fix |
|---|---|---|
| `exceeding approved Total Regional Cores quota` | The subscription allows 4 vCPUs per region and the GitLab VM uses all 4 in East US | Runner VM in another region (quotas are per region) |
| `SkuNotAvailable` / `Allocation failed` | No capacity for the requested size in the region (common on student subscriptions) | Try several 2-vCPU sizes across 5 regions, first one Azure accepts wins |
| `already exists` on every later attempt | A failed allocation left a half-created VM outside Terraform's state | Delete leftover VMs and disks before each attempt |
| The VM was off mid-deployment | Azure auto-shutdown / VM stopped | The workflow starts the VM if needed and retries dropped SSH connections |

### GitLab

| Problem | Cause | Fix |
|---|---|---|
| GitLab didn't come back after a VM restart (`Permission denied - puma.rb`, container restart loop) | An earlier `chmod -R 700` / `chown -R root` locked GitLab's internal users (`git`, `gitlab-www`, …) out of their own files | Never lock the mounted subfolders; the deploy detects the problem, reopens the folders (PostgreSQL's stays private), runs `update-permissions` and restarts GitLab |
| Security settings ran on a half-started GitLab | The health check accepted nginx's `301` redirect, which comes before Rails is up | Check GitLab's own readiness endpoint (`/-/readiness`) inside the container |
| Container stuck at `unhealthy` even when GitLab worked | Docker's built-in health check doesn't cope with the HTTPS setup | Same readiness endpoint, independent of HTTP vs HTTPS |

### Terraform

| Problem | Cause | Fix |
|---|---|---|
| `subnet ... was not found` after moving region | Replacing the resource group deleted the subnet, but a subnet has no region attribute, so Terraform assumed it still existed | `replace_triggered_by` rebuilds the subnet with its VNet (and the NIC/NSG link with the NIC) |

### What we learned
- **Reproduce before fixing.** The permission bug was recreated on a local GitLab (same `Permission denied`, same restart loop); the repair was verified there before it touched the real VM.
- **Never trust a single signal.** An HTTP answer, or Docker's health status, isn't proof that the application is ready.
- **Make every step idempotent.** Re-running the deployment after a failure must be safe — that's what let us fix one problem at a time.
- **Least privilege has to fit the software.** Locking files down blindly broke GitLab; lock the outer door and let the application manage its own permissions.

---

## Member 1 — Azure Infrastructure & Terraform

Terraform is split in two configurations, each with its own state file, so a change to one can never touch the other:

| Config | Builds | State |
|---|---|---|
| `terraform/gitlab` | The GitLab platform: resource group `gitra-rg`, VNet `vnet-eastus-1`, subnet, NSG (22, 80, 443, 2224), static public IP with DNS name, NIC, VM `gitra-gitlab-vm` | `gitra-gitlab.tfstate` |
| `terraform/runner` | The CI runner: resource group `gitra-runner-rg`, VNet, subnet, NSG (22, 5000), public IP, NIC, VM `gitra-runner-vm` | `gitra-runner.tfstate` |

**Adopting the existing GitLab VM:** the platform was created before Terraform managed it, so `import_existing.sh` imports each resource into the state — importing changes nothing in Azure. `prevent_destroy` guards the resource group, public IP and VM, and the workflow refuses to apply any plan that would delete or replace something; if a plan would modify an existing resource it isn't applied automatically.

**Why two regions:** the subscription allows 4 vCPUs per region, and the GitLab VM (`Standard_D4s_v4`) uses all 4 in East US. Quotas are per region, so the runner VM goes to another region — the first of West US 2, Central US, East US 2, West US 3 or North Europe with capacity (`RUNNER_LOCATION` pins one). The runner only talks to GitLab over HTTPS, so the distance doesn't matter.

| Resource | Name | Notes |
|---|---|---|
| Resource group | `gitra-runner-rg` | Everything for the runner; kept apart from the existing `gitra-rg` (GitLab VM) |
| Virtual network / subnet | `gitra-runner-vnet` / `gitra-runner-subnet` | `10.20.0.0/16` / `10.20.1.0/24` |
| Public IP | `gitra-runner-pip` | Static |
| NSG | `gitra-runner-nsg` | 22, 5000 |
| Runner VM | `gitra-runner-vm` | First 2-vCPU size with capacity (currently `Standard_B2s_v2` in West US 2), 32 GB Premium SSD, Ubuntu 22.04 |
| State storage | `gitra-tfstate-rg` / `gitratf…` | Created by the workflow; keeps Terraform state between runs |

Local checks without Azure (in `terraform/gitlab` and `terraform/runner`): `terraform init -backend=false && terraform validate && terraform test`.

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
| Permission repair: reproduced the VM's `chmod -R 700` damage locally (restart loop), repair brings GitLab back (readiness 200, no services down, PostgreSQL data still `700`) | ✅ Pass |
| `health_check.sh`: waits through a restart, passes only once GitLab is ready | ✅ Pass |
| `backup.sh` → delete a project → `restore.sh`: project and its repository back, `gitlab:doctor:secrets` 0 failures | ✅ Pass |
| `harden_ssh.sh` on Ubuntu 22.04: overrides the image's `PasswordAuthentication yes`, refuses to run when no user has an SSH key | ✅ Pass |
| `gitlab_bootstrap.rb`: root password, runner token, temporary token | ✅ Pass |
| Runner deploy + registration + `gitlab-runner verify` | ✅ Pass |
| `push_demo_app.sh`: project created, app pushed, pipeline started | ✅ Pass |
| **Full run on Azure:** VM prepared, GitLab over HTTPS, security settings, runner VM created and registered, demo pipeline **test → build → deploy_staging passed** | ✅ Pass |

## Acceptance Criteria

- [x] GitLab is installed and reachable through Docker automation
- [x] Docker Compose brings the platform up reliably with persistent storage
- [x] Secrets and runtime data are excluded from version control
- [x] Azure infrastructure is defined with Terraform (Member 1)
- [x] A sample CI/CD pipeline is defined and the runner is wired to GitLab (Member 2)
- [x] The full end-to-end workflow is automated and documented
- [x] The design reflects enterprise practice (isolated runner, HTTPS, approval + 2FA, least-privilege network)
- [x] First automatic deployment run on Azure — end to end, pipeline passed
