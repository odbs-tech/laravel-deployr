# Laravel Deployr

![CI](https://github.com/odbs/laravel-deployr/actions/workflows/ci.yml/badge.svg)

> Zero-downtime Laravel server provisioner and deployer for Ubuntu / Debian.

One command transforms a fresh VPS into a fully configured Laravel production stack — with **Nginx, PHP-FPM, PostgreSQL or MySQL, Redis, Supervisor queue workers, Let's Encrypt SSL** — and deploys your application with **atomic release switching** so there is never a moment of downtime.

---

## Installation

Clone the repository to your server or workstation:

```bash
git clone git@github.com:odbs/laravel-deployr.git
cd laravel-deployr
sudo chmod +x deployr
```

Or run directly with curl:

```bash
curl -fsSL https://raw.githubusercontent.com/odbs/laravel-deployr/main/deployr | sudo bash -s deploy
```

---

## Commands

```
sudo deployr <command> [options]

Commands:
  deploy     Provision the server (once) and deploy the application
  rollback   Roll back to the previous release in seconds
  upgrade    Upgrade system packages, Composer, PHP-FPM, and Nginx
  status     Show service health, release list, and deployment info

Options:
  --non-interactive    Read all values from environment variables (CI/CD)
  --dry-run            List steps without executing
  --help, -h           Show help
```

### `deploy`

Provisions the server infrastructure on the **first run** (system packages, Nginx, PHP, database, Redis, firewall), then deploys the application into a timestamped release directory and switches Nginx to it atomically.

```bash
sudo deployr deploy
```

On every subsequent call the infrastructure is skipped; only a new release is created and the `current` symlink is switched.

### `rollback`

Switches the `current` symlink back to the previous release. Asks whether to also run `artisan migrate:rollback` and delete the bad release.

```bash
sudo deployr rollback
```

### `upgrade`

Runs `apt-get upgrade`, updates Composer, and gracefully restarts PHP-FPM, Nginx, Redis, and Supervisor.

```bash
sudo deployr upgrade
```

### `status`

Displays service health, the list of available releases (with the current one highlighted), disk usage, and deployment details.

```bash
sudo deployr status
```

---

## Configuration Prompts

On first run `deployr deploy` asks the following questions interactively:

| Prompt | Example | Notes |
|--------|---------|-------|
| Application name | `MyApp` | Used in `.env` |
| Domain name | `api.example.com` | DNS must point to this server |
| Setup SSL? | `y` | Let's Encrypt via Certbot |
| SSL email | `you@example.com` | Required for SSL |
| Database | `1` (PostgreSQL) / `2` (MySQL) | |
| Database name | `mydb` | |
| Database username | `myuser` | |
| Database password | _(hidden)_ | |
| Remote DB access? | `n` | Opens port 3306 / 5432 via UFW |
| PHP version | `8.4` | Uses sury.org on Debian, ondrej/php on Ubuntu |
| Base directory | `/var/www/api.example.com` | Holds `releases/`, `shared/`, `current` |
| Git SSH repo URL | `git@github.com:org/repo.git` | |
| Git branch | `main` | |
| Worker count | `8` | Supervisor processes |
| Install Redis? | `y` | |

---

## Non-Interactive Mode (CI/CD)

Pass all values as environment variables and add `--non-interactive`:

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
  deployr deploy --non-interactive
```

---

## Releases Structure

Every deploy creates a **timestamped directory** inside `releases/`. Nginx always serves from the `current` symlink. Switching between releases is atomic — there is no window where a partial deploy is visible.

```
/var/www/api.example.com/
├── releases/
│   ├── 20260401_090000/    ← previous (kept for rollback)
│   └── 20260407_153022/    ← current release
├── shared/
│   ├── .env                ← shared across all releases
│   └── storage/            ← logs, cache, uploads
└── current -> releases/20260407_153022   (Nginx serves from here)
```

The last **3 releases** are kept automatically; older ones are deleted.

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

# Check queue workers
supervisorctl status

# Roll back if something went wrong
sudo deployr rollback

# Check overall health
sudo deployr status
```

---

## Project Structure

```
laravel-deployr/
├── deployr                     # CLI entrypoint
├── lib/
│   ├── core.sh                 # Colors, logging, ask*, save_config
│   ├── validate.sh             # OS detection, disk/DNS checks
│   ├── steps/
│   │   ├── 01_system.sh        # System update + essential packages
│   │   ├── 02_nginx.sh         # Nginx install
│   │   ├── 03_firewall.sh      # UFW rules
│   │   ├── 04_ssh_key.sh       # SSH deploy key generation
│   │   ├── 05_php.sh           # PHP-FPM (Ubuntu PPA / Debian sury.org)
│   │   ├── 06_composer.sh      # Composer
│   │   ├── 07_database.sh      # MySQL or PostgreSQL
│   │   ├── 08_redis.sh         # Redis (optional)
│   │   ├── 09_vhost.sh         # Nginx vhost + SSL
│   │   └── 10_workers.sh       # Supervisor + scheduler cron
│   └── commands/
│       ├── deploy.sh           # Full provision + release deploy
│       ├── rollback.sh         # Atomic rollback
│       ├── upgrade.sh          # Stack upgrade
│       └── status.sh           # Health dashboard
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

### Running Tests Locally

```bash
# Install BATS
git clone --depth 1 https://github.com/bats-core/bats-core.git /tmp/bats-core
sudo /tmp/bats-core/install.sh /usr/local

# Run tests
bats tests/unit/
```

### Linting

```bash
# Install ShellCheck
sudo apt-get install -y shellcheck

# Lint all scripts
shellcheck -S warning deployr setup.sh
find lib/ -name "*.sh" -print0 | xargs -0 shellcheck -S warning
```

### CI

GitHub Actions runs ShellCheck and BATS on every push and pull request to `main`. See [`.github/workflows/ci.yml`](.github/workflows/ci.yml).

---

## License

MIT — © 2026 ODBS Tech
