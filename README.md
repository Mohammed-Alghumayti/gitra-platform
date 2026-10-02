<p align="center">
  <img src="docs/images/gitra-logo.png" alt="Gitra logo" width="420">
</p>

# Gitra Platform — Internal Git & CI/CD Platform on Azure

An internal GitLab CE platform deployed on Microsoft Azure, built as a 3-person bootcamp project. The platform gives the team a single place for source control, code review, and CI/CD pipelines.

**Live environment:** `http://20.55.88.3` "for Now" (Azure VM, Ubuntu 22.04 LTS)

> **v2.0 update:** fixed `external_url` pointing at `localhost` instead of the public IP, tightened storage folder permissions from `777` to `700`, added a backup script, and added `.gitignore` so GitLab's secrets/data folder is never committed. See [Update Log](#update-log--v20) below.

## Team & Workstreams

| Member | Workstream | Status |
|---|---|---|
| **Member 1** — Nasser | Azure Infrastructure & Terraform | 🔲 _To be added_ |
| **Member 2** — Faisal | GitLab & CI/CD Configuration | 🔲 _To be added_ |
| **Member 3** — Mohammed | Docker, Bash Automation & Operations | ✅ Complete (this section) |

> This README is a shared document. Each member should fill in their own section below rather than create a separate file, so the whole team's work reads as one coherent project.

---

## Architecture Overview

```
             INFRASTRUCTURE
                  │
            Terraform   (Member 1)
                  │
                  ▼
              Azure VM
                  │
                  ▼
      Docker + Bash Automation   (Member 3 — this section)
                  │
                  ▼
               GitLab
                  │
          SOFTWARE DELIVERY
                  │
       GitLab + CI/CD Pipeline   (Member 2)
```

---

## Member 3 — Docker, Bash Automation & Operations

### What this covers
Deploying GitLab CE as a Docker container on the Azure VM, with persistent storage so no data is lost on restart, and the scripts needed to install, deploy, health-check, and back up the platform.

### Repository layout
```
gitra-platform/
├── docker-compose.yaml       # Container orchestration file
├── .gitignore                 # Keeps gitlab/ (secrets, data) out of version control
├── scripts/
│   ├── setup.sh                # Installs Docker and prepares the environment
│   ├── deploy.sh                # Creates storage folders and launches the container
│   ├── health_check.sh          # Waits for GitLab to become reachable
│   └── backup.sh                # Creates and exports a GitLab backup
└── gitlab/                    # Persistent storage (bind-mounted into the container)
    ├── config/                 # GitLab configuration and certificates (/etc/gitlab)
    ├── logs/                    # Operational logs (/var/log/gitlab)
    └── data/                    # Databases and project data (/var/opt/gitlab)
```

### Network Security Group (NSG) rules

| Rule | Port | Protocol | Purpose |
|---|---|---|---|
| Allow-SSH-Admin | 22 | TCP | Remote server administration |
| Allow-HTTP | 80 | TCP | GitLab web interface |
| Allow-HTTPS | 443 | TCP | Future encrypted connection (SSL/TLS) |
| Allow-GitLab-SSH | 2224 | TCP | Git clone / push / pull over SSH |

The internal Git SSH port is mapped to **2224** instead of 22, to avoid conflicting with the VM's own administrative SSH port.

### Security

**In place**
- **Network:** only ports 22, 80, 443 and 2224 are open, each through its own NSG rule.
- **SSH separation:** Git uses 2224 and admin SSH uses 22, so each can be restricted on its own.
- **Permissions:** `./gitlab` is `root`-owned with mode `700`, so other VM users can't read GitLab's secrets.
- **Secrets out of Git:** `.gitignore` excludes `gitlab/` and `gitlab-backups/`.
- **Backups:** `backup.sh` also exports `gitlab-secrets.json` and `gitlab.rb`; treat the backup folder as sensitive.
- **Root password:** the generated one expires after 24h. Change it on first login.

**To do before real use**
- [ ] Enable HTTPS: set `external_url 'https://<domain>'` and `letsencrypt['enable'] = true`. Port 80 is plaintext today.
- [ ] Restrict NSG source IPs to the team, at least for ports 22 and 2224.
- [ ] Disable public sign-up and enforce 2FA (Admin → Settings → General).
- [ ] Pin the GitLab image version instead of `latest`.
- [ ] Allow only SSH keys for admin SSH (no passwords).
- [ ] Keep encrypted backups off the VM (e.g. Azure Blob Storage).

### Quick start

```bash
# 1. Clone the repository
git clone -b Mohamemd-docker-automation \
  https://github.com/Mohammed-Alghumayti/gitra-platform.git
cd gitra-platform

# 2. Make the scripts executable
chmod +x scripts/*.sh

# 3. Install Docker and enable permissions
./scripts/setup.sh
newgrp docker

# 4. Launch GitLab
./scripts/deploy.sh

# 5. Wait until it's actually ready (polls every 10s, 5 min default timeout)
./scripts/health_check.sh

# 6. (recommended, periodically) Back up GitLab
./scripts/backup.sh
```

Once `health_check.sh` reports success, open `http://20.55.88.3` in a browser. Retrieve the initial `root` password (valid for the first 24 hours only) with:

```bash
docker exec -it gitlab_server cat /etc/gitlab/initial_root_password | grep "Password:"
```

### Update Log — v2.0

| # | Issue | Fix |
|---|---|---|
| 1 | `external_url` was `http://localhost` while the VM is reached at `20.55.88.3` — produced broken clone URLs and UI links. | Updated to `http://20.55.88.3`. Requires `docker compose down && docker compose up -d` (a restart alone does not re-read this value). |
| 2 | `deploy.sh` set storage folders to `chmod -R 777` — world-writable, including GitLab's secrets. | Changed to `chown root:root` + `chmod -R 700`, matching GitLab's own recommendation for bind-mounted volumes. |

Also added: `scripts/backup.sh` (no backup/restore path previously existed), `.gitignore` (the `gitlab/` folder was not excluded from version control), and removed the obsolete `version: '3.8'` key from `docker-compose.yaml`.

### Still worth checking
- [ ] Confirm the Azure VM has at least 4 GB RAM (8 GB recommended) — GitLab CE is memory-hungry on first boot, and an undersized VM is the most common cause of slow startups or 502 errors.

---

## Member 1 — Azure Infrastructure & Terraform

> _To be completed by Member 1._ Should cover: Terraform modules used to provision the Resource Group, Virtual Network, Subnet, NSG, and VM; how to run `terraform plan` / `terraform apply`; variables and outputs; any design decisions worth noting.

```
terraform/
├── main.tf
├── variables.tf
├── outputs.tf
├── providers.tf
├── network.tf
├── vm.tf
├── security.tf
└── terraform.tfvars.example
```

---

## Member 2 — GitLab & CI/CD

> _To be completed by Member 2._ Should cover: GitLab project and runner configuration, the sample application repository, `.gitlab-ci.yml` pipeline stages, and a walkthrough of a successful (and a failed) pipeline run through to staging deployment.

```
sample-app/
├── src/
├── tests/
├── Dockerfile
└── .gitlab-ci.yml
```

---

## Full Project Structure (target)

```
gitra-platform/
├── terraform/        # Member 1
├── docker-compose.yaml
├── .gitignore
├── scripts/           # Member 3
├── sample-app/        # Member 2
├── docs/
│   ├── images/         # Logo and diagrams
│   ├── architecture.md
│   ├── deployment.md
│   └── troubleshooting.md
└── README.md
```

## Acceptance Criteria

- [x] GitLab is installed and reachable through Docker automation
- [x] Docker Compose brings the platform up reliably with persistent storage
- [x] Secrets and runtime data are excluded from version control
- [ ] Azure infrastructure is provisioned with Terraform (Member 1)
- [ ] A sample CI/CD pipeline is demonstrated (Member 2)
- [ ] The full end-to-end workflow is documented
- [ ] The design reflects enterprise practice (access, secrets, hardening, recovery)
- [ ] Items under **Security → To do** are closed
