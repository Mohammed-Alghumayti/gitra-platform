# Gitra Platform — Deployment & Operations

> Part of the project documentation: [Architecture](architecture.md) · **Deployment & Operations** · [Troubleshooting & Change Log](troubleshooting.md)

## What this covers

How the platform is deployed (automatically, with GitHub Actions), the one-time setup it needs, and day-to-day operations: logging in, inviting people, admin SSH access, starting and stopping the servers, backup and restore, and which Azure resources are safe to delete.

**Live environment:** [https://gitra-25ee91e6.eastus.cloudapp.azure.com](https://gitra-25ee91e6.eastus.cloudapp.azure.com)

---

## One-time setup (~10 minutes, all in the browser)

### 1. Azure credentials and SSH key
Open [Azure Cloud Shell](https://shell.azure.com) (Bash) and run:

```bash
SUB=$(az account show --query id -o tsv)
az ad sp create-for-rbac --name gitra-github-actions --role Contributor \
  --scopes /subscriptions/$SUB --json-auth
ssh-keygen -t rsa -b 4096 -N "" -C gitra-deploy -f ~/gitra_deploy
cat ~/gitra_deploy
```

The first command prints a JSON block (the service principal GitHub Actions uses). The last prints a private SSH key. Keep both for step 2.

> If `create-for-rbac` fails with an authorization error, your account isn't Owner on the subscription — ask the subscription owner to run it.

### 2. GitHub secrets
Repository **Settings → Secrets and variables → Actions → New repository secret**:

| Secret | Value |
|---|---|
| `AZURE_CREDENTIALS` | The whole JSON block from step 1 |
| `SSH_PRIVATE_KEY` | The whole private key (`-----BEGIN …` to `-----END …`) |
| `GITLAB_ROOT_PASSWORD` | A strong password for GitLab's `root` (12+ characters, not a common word) |

### 3. Optional variables
Same page, **Variables** tab:

| Variable | Default | Use |
|---|---|---|
| `GITLAB_VM_IP` | `20.55.88.3` | Public IP of the GitLab VM |
| `DNS_LABEL` | `gitra-<8 chars>` | Azure DNS name → `https://<label>.<region>.cloudapp.azure.com` |
| `RUNNER_LOCATION` | tries `westus2`, `centralus`, `eastus2`, `westus3`, `northeurope` | Pin the runner VM's region |
| `RUNNER_VM_SIZE` | tries 7 small 2-vCPU sizes | Pin the runner VM's size |

### 4. Run
Push to `Testing`, or open the latest run under **Actions** and click **Re-run all jobs**.

> The **Run workflow** button only appears once the workflow file exists on the default branch (`main`). Until then, use a push or **Re-run**.

---

## What every deployment does

`.github/workflows/deploy.yml` runs on every push to `Testing` (docs-only changes are skipped). Each step is idempotent — safe to re-run after a failure.

| Step | What happens |
|---|---|
| **0. GitLab platform** | Terraform imports the existing platform into its state (first run only), then plans. It applies only if nothing would be deleted, replaced or modified; otherwise it stops with an error or a warning listing what differs |
| **1. Prepare GitLab VM** | Finds the VM by its IP, **starts it if it's stopped**, makes the IP static, adds the free DNS name, opens ports 22/80/443/2224 in its NSG if missing, adds the `gitra-deploy` user with the SSH key (through the Azure VM agent — no password needed) |
| **2. Deploy GitLab** | Installs Docker, git and fail2ban if needed, pulls the branch to `/opt/gitra-platform`, moves any older GitLab data there (nothing is lost), starts GitLab with HTTPS, **repairs file permissions** if GitLab can't read its own files, waits until GitLab is really ready, applies the security settings, and turns off password login for admin SSH (keys only) |
| **2b. Root password** | Sets `root`'s password from the `GITLAB_ROOT_PASSWORD` secret |
| **3. Runner VM** | Creates the Terraform state storage if needed, then Terraform creates/updates the runner VM. An existing VM keeps its size and region (it's never resized); a new one tries sizes and regions until Azure has capacity, cleaning up after each failed attempt. **Starts the runner VM if it's stopped** — if Azure has no capacity to start it, another size or region is used |
| **4. Register runner** | Creates a runner token in GitLab and registers the runner (only if it isn't registered yet) |
| **5. Demo app** | Creates `root/internal-demo-app` in GitLab, pushes `sample-app/`, and waits for its pipeline: **test → build → deploy_staging** |
| **Clean-up** | Revokes the temporary GitLab token used in step 5 |

The run's **Summary** page shows the GitLab URL, the demo project and the staging app URL.

A full first run takes about **20–30 minutes**; later runs are faster.

---

## After the first deployment

1. Open the GitLab URL and log in as **`root`** with the `GITLAB_ROOT_PASSWORD` secret.
2. Set up **2FA** when asked (Google Authenticator or Microsoft Authenticator).
3. Check the runner: **Admin → CI/CD → Runners** → `gitra-runner` with a green dot.
4. Check the pipeline: `root/internal-demo-app` → **Build → Pipelines**.

### Inviting the supervisor and students
1. Send them the GitLab URL — they click **Register**.
2. Approve them: **Admin → Users → Pending approval → Approve**.
3. On first login they must set up 2FA.

### Changing root's password
Change the `GITLAB_ROOT_PASSWORD` secret; the next run applies it.

---

## Starting and stopping the servers

| VM | Resource group | Purpose |
|---|---|---|
| `gitra-gitlab-vm` | `gitra-rg` | GitLab (East US) |
| `gitra-runner-vm` | `gitra-runner-rg` | Runner + staging app (West US 2) |

### Stop (to save money)
Azure portal → **Virtual machines** → select the VM → **Stop** → wait for **Stopped (deallocated)**.

> Always stop from the portal. Shutting down from inside the VM leaves it **Stopped** but still billed.

While stopped, data is kept and only disk and IP costs remain.

### Start
- **Portal:** select the VM → **Start**. GitLab and the runner start on their own (`restart: always`); GitLab needs 3–5 minutes.
- **GitHub Actions:** **Re-run all jobs** — this starts **both VMs** automatically.

### Auto-shutdown
If **Auto-shutdown** is enabled on a VM (VM → **Operations → Auto-shutdown**), it stops every day at the set time. The next deployment starts the GitLab VM again.

---

## Azure resource groups — what's safe to delete

| Resource group | Contains | Delete? |
|---|---|---|
| `gitra-rg` | GitLab VM and **all its data** (projects, users, code) | ❌ **Never** — this can't be undone |
| `gitra-tfstate-rg` | Terraform's state file | ❌ No — costs almost nothing; without it Terraform forgets what it built |
| `gitra-runner-rg` | Runner VM only | ⚠️ Safe — pipelines stop until the next deployment recreates it |

To save money, **stop** VMs instead of deleting anything.

---

## Backup and restore

### Backup
On the GitLab VM:

```bash
sudo /opt/gitra-platform/scripts/backup.sh /root/gitlab-backups
```

It creates a GitLab backup (`<id>_gitlab_backup.tar` — projects, users, issues, CI history) and copies it to the folder together with `gitlab-secrets.json` and `gitlab.rb` — **both are required to restore**. Treat the folder as sensitive and keep a copy off the VM. Backups older than 7 days are removed from the container.

### Restore

> ⚠️ A restore **replaces all current GitLab data** with the backup.

```bash
sudo /opt/gitra-platform/scripts/restore.sh /root/gitlab-backups            # newest backup in the folder
sudo /opt/gitra-platform/scripts/restore.sh /root/gitlab-backups <backup_id> # a specific one
```

It asks you to type `yes`, then:

| # | Step | Why |
|---|---|---|
| 1 | Checks the backup's GitLab version (the end of `<backup_id>`) matches the running GitLab | GitLab can only restore a backup made by the same version |
| 2 | Restores `gitlab-secrets.json` and `gitlab.rb` (current ones are kept as `*.before-restore.<time>`), restarts GitLab | Without the matching secrets, CI variables, runner tokens and 2FA can't be decrypted |
| 3 | Copies the backup into the container | `gitlab-backup` reads from `/var/opt/gitlab/backups` |
| 4 | Stops `puma` and `sidekiq` | Nothing may write to the database during the restore |
| 5 | `gitlab-backup restore` | Restores the database, repositories and uploads |
| 6 | Restarts, waits until ready, runs `gitlab:check` and `gitlab:doctor:secrets` | Confirms GitLab works and every secret can be decrypted |

**If the versions differ**, start the backup's version first: in `docker-compose.yaml` set `image: 'gitlab/gitlab-ce:<version>-ce.0'` (e.g. `17.4.0-ce.0`), run `docker compose up -d`, then restore.

**Restoring onto a new VM** (e.g. the old one was lost):
1. Deploy GitLab on the new VM (point `GITLAB_VM_IP` at it and re-run the workflow, or follow *Manual install* below).
2. Copy the backup folder to the new VM: `scp -r gitlab-backups <user>@<new-vm>:/tmp/`
3. `sudo /opt/gitra-platform/scripts/restore.sh /tmp/gitlab-backups`
4. Re-run the workflow so the runner re-registers if needed.

---

## Server access (admin SSH)

Admin SSH (port 22) on the GitLab VM accepts **SSH keys only** — every deployment turns password login off (`scripts/harden_ssh.sh`). Root login over SSH is off too. GitHub Actions is unaffected: it uses its own key (`gitra-deploy`).

### Add your own key (once, in [Azure Cloud Shell](https://shell.azure.com), Bash)

```bash
# 1. Create a key pair (skip if you already have one)
ssh-keygen -t ed25519 -N "" -C "gitra-admin" -f ~/.ssh/gitra_admin

# 2. Add the public key to the "gitra" user on the GitLab VM (through the Azure VM agent)
az vm user update -g gitra-rg -n gitra-gitlab-vm \
  -u gitra --ssh-key-value "$(cat ~/.ssh/gitra_admin.pub)"

# 3. Log in
ssh -i ~/.ssh/gitra_admin gitra@gitra-25ee91e6.eastus.cloudapp.azure.com
```

> Cloud Shell is **Bash**: paths use `/` (`~/.ssh/...`). The Windows form `$HOME\.ssh\...` fails there with `Permission denied`.

### Or from your own Windows computer (PowerShell)

```powershell
# 1. Create a key pair (press Enter twice for no passphrase)
mkdir "$HOME\.ssh" -Force
ssh-keygen -t ed25519 -C "gitra-admin" -f "$HOME\.ssh\gitra_admin"

# 2. Show the public key and copy the whole line (starts with ssh-ed25519)
Get-Content "$HOME\.ssh\gitra_admin.pub"
```

**Step 3.** Add it to the VM — either in Cloud Shell: `az vm user update -g gitra-rg -n gitra-gitlab-vm -u gitra --ssh-key-value "<the copied line>"`, or in the portal: `gitra-gitlab-vm` → **Help → Reset password** → **Add SSH public key**, username `gitra`, paste the key → **Update**.

**Step 4.** Log in from PowerShell:

```powershell
ssh -i "$HOME\.ssh\gitra_admin" gitra@gitra-25ee91e6.eastus.cloudapp.azure.com
```

**Never share the private key** (the file without `.pub`).

### Without SSH
**Azure portal → `gitra-gitlab-vm` → Operations → Run command → RunShellScript** runs commands as root, no SSH needed.

### Turning password login back on (not recommended)
Delete `/etc/ssh/sshd_config.d/00-gitra-hardening.conf` (via Run command) and run `systemctl reload ssh`. The next deployment turns it off again unless `harden_ssh.sh` is removed from `remote_deploy_gitlab.sh`.

---

## Manual install (without GitHub Actions)

On a fresh Ubuntu VM:

```bash
git clone -b Testing https://github.com/Mohammed-Alghumayti/gitra-platform.git
cd gitra-platform && chmod +x scripts/*.sh
./scripts/setup.sh && newgrp docker
cp .env.example .env                   # set GITLAB_EXTERNAL_URL
./scripts/deploy.sh
./scripts/health_check.sh 900
./scripts/harden_gitlab.sh
```

For a runner on another VM: `./scripts/deploy_runner.sh`, then `./scripts/register_runner.sh <glrt-token> <gitlab_url>` (token from **Admin → CI/CD → Runners → New instance runner**).

> Changing `GITLAB_EXTERNAL_URL` needs `docker compose down && docker compose up -d` — a restart does not re-read it.

---

## Local checks (no Azure needed)

```bash
# Terraform
for d in terraform/gitlab terraform/runner; do (cd $d && terraform init -backend=false && terraform validate && terraform test); done

# Scripts and workflow
shellcheck scripts/*.sh scripts/ci/*.sh
actionlint .github/workflows/deploy.yml
docker compose config -q && docker compose -f docker-compose.runner.yaml config -q

# Demo app
cd sample-app && pip install -r requirements.txt && pytest -v
```
