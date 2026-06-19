# AIVA ERP — Deployment Guide

Complete reference for developing, building, and deploying AIVA ERP (ERPNext v16 / Frappe v16).
Follow this document for **every** change. Do not improvise custom scripts or one-off fixes.

---

## 1. Repositories & What They Contain

| Repo | Visibility | Purpose | Produces app folder |
|------|-----------|---------|---------------------|
| `frappe/frappe` | public | Frappe framework (the web framework) | `apps/frappe` |
| `frappe/erpnext` | public | ERPNext app | `apps/erpnext` |
| `gp-enshrine/logicsky_docker` | private (our fork of `frappe/frappe_docker`) | Docker infra: compose files, Containerfile, apps.json, this doc | — |
| `gp-enshrine/logicsky_theme` | private | UI theme (CSS/JS, colors, login) | `apps/logicsky_theme` |
| `gp-enshrine/logicsky_core` | private | Core customizations | `apps/logicsky_core` |
| `gp-enshrine/logicsky_erpcontrol` | private | Control app — **repo name differs from app name** | `apps/logicsky_op` |

> **Note:** The repo `logicsky_erpcontrol` contains a Frappe app named `logicsky_op`.
> After build, the image shows `apps/logicsky_op`, not `apps/logicsky_erpcontrol`.

**Docker Hub image:** `gopinathanps/logicsky_erp_eval:latest`
Contains all 5 apps: `erpnext frappe logicsky_core logicsky_op logicsky_theme`

---

## 2. Directory Structure

### Local (development machine)
```
/Users/gopinathan/opt/erpnext/
├── frappe_docker/              ← git: gp-enshrine/logicsky_docker (this repo)
│   ├── docker-compose.logicsky.yml   ← main services (image-based, no bind mounts)
│   ├── docker-compose.caddy.yml      ← Caddy reverse proxy (SSL/HTTPS)
│   ├── apps.json                     ← apps to bake into image (uses ${GITHUB_TOKEN})
│   ├── images/custom/Containerfile   ← image build definition
│   ├── resources/core/main-entrypoint.sh  ← rebuilds sites/assets symlink at startup
│   └── DEPLOYMENT.md                 ← this file
└── apps/                       ← local clones of app repos (for theme development only)
    ├── logicsky_theme/
    ├── logicsky_core/
    └── logicsky_erpcontrol/    (app folder inside is logicsky_op)
```

### Production server (`ubuntu@ip-172-31-2-219`)
```
/opt/frappe/logicsky-dev/
└── frappe_docker/              ← git pull of gp-enshrine/logicsky_docker
    ├── docker-compose.logicsky.yml
    ├── docker-compose.caddy.yml
    ├── caddy/Caddyfile
    └── (apps.json present but NOT used — server never builds)
```

> The server only **runs** the pre-built image. It never builds.
> App code lives **inside the Docker image**, not in folders on the server.

---

## 3. How Assets Work (read this — it explains the recurring CSS/JS bug)

- App assets (CSS/JS bundles) are **baked into the image** at `/home/frappe/frappe-bench/assets/`.
- `sites/assets` is a **symlink** to that baked path, recreated by `main-entrypoint.sh` on container start.
- Each new image build produces **new bundle hashes** (e.g. `login.bundle.LMJLRDRX.css`).
- The database stores an **asset manifest** mapping logical names → hashed filenames.
- After deploying a new image, the DB manifest is **stale** → browser requests old hashes → **404 / MIME errors**.

### The fix: `bench migrate` after every deploy
`bench migrate` rebuilds the asset manifest in the DB so frappe serves the correct new hashes.
`clear-cache` alone does **NOT** fix this. **Always run migrate after force-recreate.**

---

## 4. Development Workflow (making changes)

### Theme / UI changes (CSS, JS, colors)
1. Edit files in `apps/logicsky_theme/` locally.
2. Commit & push to `gp-enshrine/logicsky_theme`:
   ```bash
   cd /Users/gopinathan/opt/erpnext/apps/logicsky_theme
   git add -A
   git commit -m "Describe the UI change"
   git push origin main
   ```
3. Deploy → **Workflow B** (full image build). The image picks up the latest push from the repo.

### App logic changes (logicsky_core, logicsky_op, erpnext customizations)
Same as above — edit, commit, push to the respective repo, then **Workflow B**.

### Docker / infra changes (compose, Containerfile, apps.json)
1. Edit in `frappe_docker/` locally.
2. Commit & push to `gp-enshrine/logicsky_docker`:
   ```bash
   cd /Users/gopinathan/opt/erpnext/frappe_docker
   git add -A
   git commit -m "Describe the infra change"
   git push origin main
   ```
3. On server: `git pull origin main` (see Workflow B step 5).

---

## 5. Workflow B — Full Build & Deploy (standard procedure)

This is the **only** correct way to deploy app/framework code to production.
Total time: ~30–45 min build + ~5 min deploy.

### Step 1 — Push all changed app repos
Make sure every changed app (theme, core, erpcontrol) is committed and pushed to its GitHub repo (see Section 4). The build pulls the **latest** from each repo listed in `apps.json`.

### Step 2 — Build the image (LOCAL machine)
```bash
cd /Users/gopinathan/opt/erpnext/frappe_docker

# Enter GitHub token securely (hidden, not saved to shell history)
read -s -p "GitHub Token: " GITHUB_TOKEN && echo

# Inject the token into a temp apps file (real token never committed)
envsubst < apps.json > /tmp/apps_build.json

# Build AND push to Docker Hub in one step
docker buildx build \
  --no-cache \
  --build-arg FRAPPE_BRANCH=version-16 \
  --secret id=apps_json,src=/tmp/apps_build.json \
  --tag gopinathanps/logicsky_erp_eval:latest \
  --file images/custom/Containerfile \
  --push \
  .

# Clean up
rm /tmp/apps_build.json
unset GITHUB_TOKEN
```

### Step 3 — VERIFY the image (LOCAL) — do not skip
```bash
docker run --rm gopinathanps/logicsky_erp_eval:latest \
  ls /home/frappe/frappe-bench/apps/
```
Must print exactly:
```
erpnext
frappe
logicsky_core
logicsky_op
logicsky_theme
```
If any app is missing → the build failed → **do not deploy**. Re-check `apps.json` and the token.

### Step 4 — Push infra changes (LOCAL, if compose/Containerfile changed)
```bash
cd /Users/gopinathan/opt/erpnext/frappe_docker
git add -A
git commit -m "Describe infra change"
git push origin main
```

### Step 5 — Deploy (PRODUCTION SERVER)
```bash
cd /opt/frappe/logicsky-dev/frappe_docker

# 1. Get latest compose files
git pull origin main

# 2. Pull the new image from Docker Hub
docker compose -f docker-compose.logicsky.yml -f docker-compose.caddy.yml pull

# 3. Recreate containers with the new image (data volumes untouched)
docker compose -f docker-compose.logicsky.yml -f docker-compose.caddy.yml up -d --force-recreate --remove-orphans

# 4. Rebuild asset manifest + apply DB schema changes (FIXES CSS/JS 404)
docker exec frappe_docker-backend-1 bench --site aivaerp.com migrate
```

### Step 6 — Confirm
- Open https://aivaerp.com and hard-refresh (`Cmd+Shift+R`).
- Console should have **no** CSS/JS MIME or 404 errors.

> Multi-site? Run migrate for each site, or `bench --site all migrate`.
> Sites on this server: `aivaerp.com`, `LogicSkyERP`, `fides.aivaerp.com`, `test-company.aivaerp.com`.

---

## 6. GitHub Token Setup

Private repos in `apps.json` use a `${GITHUB_TOKEN}` placeholder. `envsubst` injects the real
token into a temp file at build time so it is **never committed** to git and **never baked** into
the final image (passed via `--secret`).

**Create a token:** GitHub → Settings → Developer settings → Personal access tokens →
Tokens (classic) → Generate → scope `repo` → copy (`ghp_...`).

The server does **not** need the token — it only pulls the pre-built image.

---

## 7. Rules — Never Do These on Production

- ❌ `bench build --app frappe` or `bench build --app erpnext` — breaks asset hashes.
- ❌ `docker system prune` — can delete the only good image.
- ❌ Bind-mounting app folders in compose — overrides the image's baked apps (causes `ModuleNotFoundError`).
- ❌ Building the image on the server — server only runs pre-built images.
- ❌ Pushing an unverified image — always run Step 3 verify first.
- ❌ Committing a real token to `apps.json`.

---

## 8. Quick Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| CSS/JS 404 or MIME errors after deploy | Stale asset manifest in DB | `bench --site aivaerp.com migrate` |
| `ModuleNotFoundError: No module named 'logicsky_op'` | App missing from image / bad bind mount | Rebuild image (Step 2), verify (Step 3), ensure no app bind mounts in compose |
| `sites/assets` symlink broken | Entrypoint didn't run | `docker exec frappe_docker-backend-1 bash -c "rm -rf sites/assets && ln -s /home/frappe/frappe-bench/assets sites/assets"` |
| Build fails cloning private repo | Token missing/expired | Re-enter token in Step 2; check repo access |
| Site internal error after recreate | Migration pending | `bench --site aivaerp.com migrate` |

### Diagnostics
```bash
# What's running and which image
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"

# Apps inside the running image
docker exec frappe_docker-backend-1 ls /home/frappe/frappe-bench/apps/

# Assets symlink + bundles
docker exec frappe_docker-frontend-1 ls -la /home/frappe/frappe-bench/sites/assets
docker exec frappe_docker-frontend-1 ls /home/frappe/frappe-bench/assets/frappe/dist/css/ | head

# Logs
docker logs frappe_docker-backend-1 --tail 50
```

---

## 9. Summary (the loop you repeat for every change)

```
LOCAL:   edit app code → push app repos → build image (token via envsubst) → VERIFY → push infra repo
SERVER:  git pull → compose pull → up -d --force-recreate → bench migrate → check site
```

**The single most important rule:** every deploy ends with `bench migrate`.
