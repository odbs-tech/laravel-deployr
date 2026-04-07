# Laravel Deployr

![CI](https://github.com/odbs/laravel-deployr/actions/workflows/ci.yml/badge.svg)

> Zero-downtime Laravel server provisioner and deployer for Ubuntu / Debian.  
> Supports multiple applications on the same server.

One command transforms a fresh VPS into a fully configured Laravel production stack — **Nginx, PHP-FPM with Opcache, PostgreSQL or MySQL, Redis, optional Node.js/npm build, Supervisor queue workers, Let's Encrypt SSL** — and deploys with **atomic release switching** so there is never a moment of downtime.

---

## Quick Start

### 1. Clone and install globally (recommended)

```bash
git clone git@github.com:odbs/laravel-deployr.git
cd laravel-deployr
sudo deployr install          # copies to /opt/deployr, links to /usr/local/bin
```

After `install`, use `deployr` from any directory without the git repo.

### 2. Run directly from the repo

```bash
sudo ./deployr deploy --app myapp
```

---

## Commands

```
sudo deployr <command> [--app <name>] [options]

Commands:
  deploy     Provision server (once) and deploy the application
  rollback   Roll back to the previous release
  upgrade    Upgrade system packages, Composer, PHP-FPM, and Nginx
  status     Show service health and release list
  install    Install deployr to /usr/local/bin (run once)

Options:
  --app <name>         Target app (required when multiple apps are deployed)
  --non-interactive    Read all values from environment variables (CI/CD)
  --dry-run            List steps without executing
  --help, -h           Show this help
```

---

## Multi-site Support

Multiple Laravel applications can run on the same server. Each app has its own domain, database, releases, and queue workers. Server infrastructure (Nginx, PHP, Redis) is shared and provisioned only once.

```bash
# Deploy two apps on one server
sudo deployr deploy --app api
sudo deployr deploy --app blog

# Target a specific app
sudo deployr rollback --app api
sudo deployr status --app blog

# Overview of all apps
sudo deployr status
```

App configs are stored separately:
```
/root/.laravel-deployr/
├── .server.conf    ← server-level (PHP version, Redis, Node.js state)
├── api.conf        ← app-specific (domain, DB, git, deploy state)
└── blog.conf
```

---

## Commands Detail

### `deploy`

Provisions the server infrastructure on the **first run** (system packages, Nginx, PHP+Opcache, DB, Redis, optional Node.js, firewall), then deploys the application as a new release.

Subsequent calls skip provisioning and only create a new release.

```bash
sudo deployr deploy --app myapp
```

### `rollback`

Switches the `current` symlink back to the previous release in seconds.

```bash
sudo deployr rollback --app myapp
```

Optionally runs `artisan migrate:rollback` and deletes the bad release.

### `upgrade`

Upgrades system packages, Composer, PHP-FPM, Nginx, Redis, and Supervisor.

```bash
sudo deployr upgrade
```

### `status`

No `--app`: prints an overview table of all deployed apps plus service health.  
With `--app`: shows detailed release list, workers, and deployment info for one app.

```bash
sudo deployr status
sudo deployr status --app myapp
```

### `install`

Copies deployr to `/opt/deployr/` and creates a `/usr/local/bin/deployr` symlink so you can run `deployr` from anywhere without the source repo.

```bash
sudo deployr install
```

---

## Configuration Prompts

On first `deploy` the following questions are asked interactively:

| Prompt | Example | Notes |
|--------|---------|-------|
| Application name | `MyApp` | Used in `.env` and as app slug |
| Domain name | `api.example.com` | DNS must point to this server |
| Setup SSL? | `y` | Let's Encrypt via Certbot |
| SSL email | `you@example.com` | Required for SSL |
| Database | `1` (PostgreSQL) / `2` (MySQL) | |
| Database name / user / password | | |
| Remote DB access? | `n` | Opens port 3306 / 5432 via UFW |
| PHP version | `8.4` | Ondrej PPA (Ubuntu) / sury.org (Debian) |
| Base directory | `/var/www/api.example.com` | Holds `releases/`, `shared/`, `current` |
| Git SSH repo URL | `git@github.com:org/repo.git` | |
| Git branch | `main` | |
| Worker count | `8` | Supervisor processes |
| Install Redis? | `y` | *(asked once per server)* |
| Install Node.js? | `n` | *(asked once per server)* |
| Node.js version | `20` | *(if Node.js selected)* |
| Run npm build? | `n` | Per-app npm build step |
| npm build command | `npm run build` | *(if npm build selected)* |

---

## Non-Interactive Mode (CI/CD)

```bash
sudo \
  APP_NAME="MyApp" \
  DOMAIN="api.example.com" \
  SETUP_SSL="true" \
  SSL_EMAIL="ops@example.com" \
  DB_TYPE="postgresql" \
  DB_NAME="mydb" \
  DB_USER="myuser" \
  DB_PASS="supersecret" \
  DB_REMOTE_ACCESS="false" \
  PHP_VERSION="8.4" \
  BASE_PATH="/var/www/api.example.com" \
  GIT_REPO="git@github.com:org/repo.git" \
  GIT_BRANCH="main" \
  WORKER_COUNT="8" \
  SETUP_REDIS="true" \
  SETUP_NODEJS="true" \
  NODE_VERSION="20" \
  NPM_BUILD_CMD="npm run build" \
  deployr deploy --app myapp --non-interactive
```

---

## Releases Structure

Every deploy creates a **timestamped directory**. Nginx always serves from the `current` symlink — switching is atomic with zero downtime.

```
/var/www/api.example.com/
├── releases/
│   ├── 20260401_090000/    ← previous (kept for rollback)
│   └── 20260407_153022/    ← current release
├── shared/
│   ├── .env                ← shared across all releases
│   └── storage/            ← logs, cache, uploads
└── current -> releases/20260407_153022
```

The last **3 releases** are kept; older ones are deleted automatically.

---

## PHP Opcache

Production-optimised Opcache settings are written to:
```
/etc/php/<version>/fpm/conf.d/99-laravel-opcache.ini
```

Key settings: `validate_timestamps=0` (max performance — PHP-FPM restart not needed between deploys since each release gets a new FPM reload via the deploy step).

---

## Node.js / npm Build

When `SETUP_NODEJS=true`, Node.js is installed via NodeSource during provisioning. If `NPM_BUILD_CMD` is set for an app, the release deploy runs:

```bash
npm ci            # install exact lockfile dependencies
npm run build     # (or your custom command)
```

before Laravel caching and migrations.

---

## Requirements

- Ubuntu 22.04+ or Debian 11+
- Root / sudo access
- DNS A record pointing to the server (required for SSL)
- A GitHub SSH deploy key added to the repository

---

## After Deployment

```bash
# Edit shared configuration
nano /var/www/<domain>/shared/.env

# Tail application logs
tail -f /var/www/<domain>/shared/storage/logs/laravel.log

# Check all queue workers
supervisorctl status

# Roll back if something went wrong
sudo deployr rollback --app <name>

# Full status overview
sudo deployr status
```

---

## Project Structure

```
laravel-deployr/
├── deployr                     # CLI entrypoint
├── lib/
│   ├── core.sh                 # Colors, logging, ask*, config helpers
│   ├── validate.sh             # OS detection, disk/DNS checks
│   ├── steps/
│   │   ├── 01_system.sh        # System update + essential packages
│   │   ├── 02_nginx.sh         # Nginx install
│   │   ├── 03_firewall.sh      # UFW rules
│   │   ├── 04_ssh_key.sh       # SSH deploy key generation
│   │   ├── 05_php.sh           # PHP-FPM + Opcache
│   │   ├── 06_composer.sh      # Composer
│   │   ├── 07_database.sh      # MySQL or PostgreSQL
│   │   ├── 08_redis.sh         # Redis (optional)
│   │   ├── 09_vhost.sh         # Nginx vhost + SSL
│   │   ├── 10_workers.sh       # Supervisor + scheduler cron
│   │   └── 11_nodejs.sh        # Node.js via NodeSource (optional)
│   └── commands/
│       ├── deploy.sh           # Full provision + release deploy
│       ├── rollback.sh         # Atomic rollback
│       ├── upgrade.sh          # Stack upgrade
│       ├── status.sh           # Health dashboard (single app or all)
│       └── install.sh          # Self-install to /usr/local/bin
├── tests/
│   └── unit/
│       ├── test_core.bats
│       └── test_validate.bats
└── .github/
    └── workflows/
        └── ci.yml              # ShellCheck + BATS on push / PR
```

---

## Development

### Local Testing with Docker

You can test the full deploy flow locally on your machine without a real server using Docker. No VPS needed — if something breaks, just delete the container and start fresh.

**Prerequisites:** Docker Desktop running.

```bash
# Start an Ubuntu 22.04 container with the repo mounted
docker run -it --rm \
  --privileged \
  --name deployr-test \
  -v "$(pwd):/opt/deployr" \
  ubuntu:22.04 bash
```

Inside the container:

```bash
# Install systemd and basic tools
apt-get update -qq && apt-get install -y systemctl curl git

# Go to the mounted repo
cd /opt/deployr

# Run a deploy (non-interactive example)
APP_NAME="TestApp" \
DOMAIN="test.local" \
SETUP_SSL="false" \
DB_TYPE="postgresql" \
DB_NAME="testdb" \
DB_USER="testuser" \
DB_PASS="secret" \
DB_REMOTE_ACCESS="false" \
PHP_VERSION="8.4" \
BASE_PATH="/var/www/test" \
GIT_REPO="git@github.com:yourorg/yourrepo.git" \
GIT_BRANCH="main" \
WORKER_COUNT="2" \
SETUP_REDIS="false" \
SETUP_NODEJS="false" \
bash deployr deploy --app testapp --non-interactive
```

> **Note:** `systemctl` commands may behave differently inside Docker since there is no full init system. Steps that install packages and write config files will work correctly; service start/enable calls may emit warnings that can be safely ignored during local testing.

To test a specific step in isolation, source the relevant file directly:

```bash
# Example: test the PHP installation step only
source lib/core.sh
source lib/steps/05_php.sh
PHP_VERSION=8.4 DB_TYPE=postgresql OS_ID=ubuntu
step_php
```

### Running Tests Locally

```bash
git clone --depth 1 https://github.com/bats-core/bats-core.git /tmp/bats-core
sudo /tmp/bats-core/install.sh /usr/local
bats tests/unit/
```

### Linting

```bash
sudo apt-get install -y shellcheck
shellcheck -S warning deployr
find lib/ -name "*.sh" -print0 | xargs -0 shellcheck -S warning
```

---

## License

MIT — © 2026 ODBS Tech
