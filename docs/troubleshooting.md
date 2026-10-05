# Gitra Platform — Troubleshooting & Change Log

> Part of the project documentation: [Architecture](architecture.md) · [Deployment & Operations](deployment.md) · **Troubleshooting & Change Log**

## What this covers

Every problem found while building and deploying the platform — what caused it and how it was fixed — plus a quick guide for problems you may hit later, and what's still worth improving.

---

## Change log

### v1.0 — Docker automation (Member 3)
GitLab CE in Docker Compose with persistent storage, plus `setup.sh`, `deploy.sh` and `health_check.sh`.

### v2.0 — First fixes
| # | Issue | Fix |
|---|---|---|
| 1 | `external_url` was `http://localhost` while the VM is reached at `20.55.88.3` — broken clone URLs and UI links | Set to the VM's address (later: its HTTPS DNS name) |
| 2 | `deploy.sh` set storage folders to `chmod 777` — anyone on the VM could read GitLab's secrets | Locked down (final form: problem 9 below) |
| 3 | No backup/restore path | Added `backup.sh` (backup + `gitlab-secrets.json` + `gitlab.rb`) |
| 4 | `gitlab/` (secrets, data) wasn't excluded from Git | Added `.gitignore` |
| 5 | Scripts contained leftover `cat << EOF` wrappers and didn't run | Cleaned up |
| 6 | `health_check.sh` checked only once, while GitLab takes minutes to boot | Polls until ready or timeout |

### v3.0 — Integration of the three workstreams (`Testing` branch)
| # | Change |
|---|---|
| 1 | Merged Member 3's Docker work and Member 2's GitLab/CI work; one compose file instead of two |
| 2 | Member 2's demo app moved to `sample-app/`, with real pytest tests, a `/health` route, a non-root Dockerfile and a `deploy_staging` stage |
| 3 | Member 1's Azure infrastructure written in Terraform, with tests using a mocked Azure provider |
| 4 | Git SSH standardised on port **2224** (Member 2's file used 2222) to match the NSG |

### v3.1 — Security design
| # | Risk | Solution |
|---|---|---|
| 1 | The runner mounts the Docker socket, so CI jobs could take over the GitLab server | Runner moved to **its own VM** |
| 2 | The site must be public for supervisors and students | HTTPS (Let's Encrypt), admin-approved sign-up, mandatory 2FA, 12-char passwords, no public projects, fail2ban, minimal NSG rules |

### v4.0 — Fully automatic deployment
GitHub Actions deploys everything on each push to `Testing`, using the team's existing GitLab VM and a Terraform-built runner VM. Secrets are stored in GitHub Secrets.

### v4.1 → v4.8 — Problems found on the first real Azure deployments

#### Azure
| # | Problem | Cause | Fix |
|---|---|---|---|
| 1 | `exceeding approved Total Regional Cores quota` | The subscription allows 4 vCPUs per region; the GitLab VM (`Standard_D4s_v4`) uses all 4 in East US | Runner VM placed in another region — quotas are per region |
| 2 | Terraform would have clashed with the existing VM | The GitLab VM lives in `gitra-rg`, the name Terraform also used | Runner resources renamed `gitra-runner-*`; a test guards against reuse |
| 3 | `Cannot modify extensions in the VM when the VM is not running` | The VM was stopped (auto-shutdown) | The workflow starts the VM if it isn't running |
| 4 | `Connection ... closed by remote host` mid-deploy | The VM was shut down during the run | Dropped SSH connections are retried (all steps are idempotent) |
| 5 | `SkuNotAvailable` / `Allocation failed` | No capacity for the requested size in the region — common on student subscriptions | Try 7 small 2-vCPU sizes across 5 regions; first one Azure accepts wins |
| 6 | Every later size failed with `already exists` | A failed allocation left a half-created VM outside Terraform's state | Delete leftover VMs and unattached disks before each attempt |

#### GitLab
| # | Problem | Cause | Fix |
|---|---|---|---|
| 7 | Security settings failed with `database.yml is a symlink that does not point to a valid file` | `health_check.sh` accepted nginx's `301` redirect, which is returned before Rails has started | Check GitLab's own readiness endpoint (`/-/readiness`) inside the container |
| 8 | Container stayed `unhealthy` although GitLab served pages | Docker's built-in health check doesn't cope with the HTTPS setup | Same readiness endpoint, independent of HTTP vs HTTPS |
| 9 | GitLab didn't come back after a VM restart: `Permission denied - puma.rb`, sidekiq down, container restart loop | An earlier `chmod -R 700` / `chown -R root` on the data folders locked GitLab's internal users (`git`, `gitlab-www`, …) out of their own files. It only showed after a restart, when GitLab re-read its files | `deploy.sh` now locks only the parent `./gitlab` folder. The deploy detects when `git` can't read its files, reopens the folders (PostgreSQL's stays `700`), runs `update-permissions` and restarts GitLab so it resets exact permissions |

#### Terraform
| # | Problem | Cause | Fix |
|---|---|---|---|
| 10 | `subnet ... was not found` after moving the runner to another region | Replacing the resource group deleted the subnet, but a subnet has no region attribute, so Terraform assumed it still existed | `replace_triggered_by` rebuilds the subnet with its VNet, and the NIC–NSG link with the NIC |

#### Result
The full run passed end to end: GitLab over HTTPS with all security settings, root password set, runner VM created (`Standard_B2s_v2`, West US 2) and registered, and the demo pipeline **test → build → deploy_staging** passed.

### Lessons learned
- **Reproduce before fixing.** The permission bug was recreated on a local GitLab (same error, same restart loop) and the repair was proven there before it touched the real VM.
- **Don't trust a single signal.** An HTTP answer or Docker's health status isn't proof the application is ready.
- **Make every step idempotent**, so a failed deployment can simply be re-run.
- **Least privilege must fit the software.** Locking everything down broke GitLab; lock the outer folder and let the application manage its own permissions.
- **Cloud capacity isn't guaranteed**, especially on student subscriptions — design for fallbacks.

---

## Troubleshooting guide

### Where to look first
- **GitHub → Actions →** the failed run → the red step. Its log ends with the actual error.
- **GitLab logs** (Azure portal → `gitra-gitlab-vm` → **Operations → Run command → RunShellScript**, no SSH needed):
  ```bash
  docker logs gitlab_server --tail 100
  docker exec gitlab_server gitlab-ctl status
  ```

### Common problems
| Symptom | Likely cause | What to do |
|---|---|---|
| Site shows **502** | GitLab is still starting | Wait 3–5 minutes |
| Site doesn't open at all | GitLab VM is stopped | Start it in the portal, or re-run the workflow |
| Browser says the certificate isn't secure | Let's Encrypt not issued yet | Check port 80 is open; `docker logs gitlab_server \| grep -i letsencrypt` |
| Workflow: `Deployment skipped — missing secrets` | Secrets not added | Add the 3 secrets ([Deployment](deployment.md)) |
| Workflow: `No public IP ... in this subscription` | Wrong `GITLAB_VM_IP` | Set the `GITLAB_VM_IP` variable |
| Workflow: `No runner VM size had capacity` | Azure has no capacity in the tried regions | Set `RUNNER_LOCATION` to another region your subscription allows |
| Workflow fails at step 3c (waiting for runner VM) | Runner VM is stopped | Start `gitra-runner-vm` in the portal, then re-run |
| Runner shows **offline** in GitLab | Runner VM stopped, or token lost | Start the VM; if still offline, re-run the workflow (it re-registers when needed) |
| Pipeline stuck in **pending** | No online runner | See the previous row |
| `Permission denied - puma.rb` in GitLab logs | File permissions broken | Re-run the workflow — it repairs them. Manually: `docker exec gitlab_server update-permissions && docker restart gitlab_server` |
| `git push` rejects the password | 2FA is on | Use a personal access token (**Edit profile → Access tokens**, scope `write_repository`) as the password |
| New user can't log in | Account pending | **Admin → Users → Pending approval → Approve** |

---

## Still worth improving
- [ ] Pin the GitLab and runner image versions instead of `latest`, so upgrades are deliberate.
- [ ] Copy encrypted backups off the VM (e.g. Azure Blob Storage) on a schedule.
- [ ] Serve the staging app over HTTPS.
- [ ] Have the workflow start a stopped runner VM automatically, like the GitLab VM.
- [ ] Copy the workflow to `main` so the **Run workflow** button is available.
