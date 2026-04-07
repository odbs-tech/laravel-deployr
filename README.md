# Laravel Deployr

```
  _                          _   ____             _
 | |    __ _ _ __ __ ___   _| | |  _ \  ___ _ __ | | ___  _   _ _ __
 | |   / _` | '__/ _` \ \ / / | | | | |/ _ \ '_ \| |/ _ \| | | | '__|
 | |__| (_| | | | (_| |\ V /| | | |_| |  __/ |_) | | (_) | |_| | |
 |_____\__,_|_|  \__,_| \_/ |_| |____/ \___| .__/|_|\___/ \__, |_|
                                             |_|            |___/
```

One-command interactive server provisioning for Laravel on Ubuntu/Debian. Answer the prompts, grab a coffee, come back to a production-ready server.

## Features

- **Auto-detects** Ubuntu/Debian version
- **Nginx** with PHP-FPM virtual host
- **PHP** with all common Laravel extensions (configurable version)
- **Composer** installed globally
- **PostgreSQL or MySQL** — creates user, database, and optional remote access
- **Redis** with systemd supervision
- **SSH key generation** — displays public key and waits for GitHub setup
- **Git clone** via SSH
- **Let's Encrypt SSL** with auto-renewal
- **Supervisor** queue workers (configurable process count)
- **Laravel scheduler** cron (`schedule:run` every minute)
- **UFW firewall** — SSH + HTTP/HTTPS + DB port (if remote)
- **.env** auto-generated with random `APP_KEY`

## Usage

```bash
curl -sO https://raw.githubusercontent.com/odbs-tech/laravel-deployr/main/setup.sh
sudo bash setup.sh
```

Or manually:

```bash
scp setup.sh root@your-server:/root/
sudo bash setup.sh
```

## Prompts

| Prompt | Default | Notes |
|--------|---------|-------|
| App Name | `Laravel` | Used in `.env` |
| Domain | — | e.g. `api.example.com` |
| SSL | Yes | Requires domain pointed to server |
| SSL Email | — | For Let's Encrypt |
| Database | PostgreSQL | PostgreSQL or MySQL |
| DB Name | — | |
| DB User | — | |
| DB Password | — | Hidden input |
| DB Remote Access | No | Opens port + binds to `0.0.0.0` |
| PHP Version | `8.4` | |
| Project Dir | `/var/www/{domain}` | |
| Git SSH URL | — | e.g. `git@github.com:user/repo.git` |
| Git Branch | `main` | |
| Worker Count | `8` | Supervisor processes |
| Redis | Yes | |

## Requirements

- Ubuntu 22.04+ or Debian 11+
- Root access
- Domain pointing to the server IP

## What Happens

1. System packages updated
2. UFW firewall configured (SSH + Nginx Full)
3. SSH key generated, you add it to GitHub
4. Nginx, PHP, Composer installed
5. Database installed and configured
6. Redis installed (if selected)
7. Project cloned via SSH
8. `.env` generated with DB credentials and random `APP_KEY`
9. `composer install`, cache, migrate
10. File permissions set (`www-data`)
11. Nginx virtual host configured
12. SSL certificate obtained (if selected)
13. Supervisor queue workers started
14. Laravel scheduler cron added

## After Setup

```bash
# Check your .env and fill in remaining values (mail, AWS, etc.)
nano /var/www/yourdomain/.env

# View logs
tail -f /var/www/yourdomain/storage/logs/laravel.log

# Monitor queue workers
supervisorctl status
```

## License

MIT
