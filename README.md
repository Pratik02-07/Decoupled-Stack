# DecoupledStack — Containerized Two-Tier Web Architecture

A production-ready, decoupled two-tier web application engineered with **Flask**, **Gunicorn**, and **MySQL 8.4** running on an isolated Docker bridge network (`decoupled-net`).

This repository showcases containerization best practices, least-privilege security, layer caching optimization, external volume & network decoupling, and resilient health monitoring.

---

## 🏗️ Architecture Overview

The application establishes a strict separation of concerns between a stateless web presentation tier and a stateful relational database tier:

![DecoupledStack Architecture](docs/DecoupledStack_Architecture.png)

- **Stateless Web Tier (`flask-app-two-tier-backend`)**: Built on `python:3.13-slim` running Gunicorn with 2 worker forks. Handles incoming HTTP requests and automatically auto-provisions idempotent database schemas (`CREATE TABLE IF NOT EXISTS messages`) on first request.
- **Stateful Database Tier (`mysql`)**: Official MySQL 8.4 container with custom healthcheck monitoring and persistent data storage. Host port mapped to `3307:3306` to avoid conflicts with local MySQL services while preserving internal port `3306` within the Docker network.
- **Service Discovery & Network Isolation**: Containers communicate securely across a custom external bridge network (`decoupled-net`) via Docker's embedded DNS engine using service aliases (`mysql:3306`), eliminating the security vulnerability of hardcoded IP addresses.
- **Data Persistence**: Backed by a dedicated external Docker volume (`decoupled_mysql_data`) or host bind mounts (`volumes/mysql`), ensuring data survives container restarts and teardowns.

---

## 🌟 Production-Ready Dockerfile & Architecture Highlights

The `Dockerfile` and infrastructure setup incorporate key production engineering patterns:

1. **Lightweight Base Image (`python:3.13-slim`) with Clean `curl`**:
   - Uses `python:3.13-slim` to minimize the attack surface and keep image size lean (~150MB instead of ~1GB full Python).
   - Installs `curl` explicitly with `--no-install-recommends` and purges the apt cache (`rm -rf /var/lib/apt/lists/*`) in a single layer. This enables standard, readable HTTP health check syntax (`curl -f`) without image bloat.

2. **Leveraging Layer Caching**:
   - `requirements.txt` is copied and installed *before* copying the application source code (`COPY . .`). Changes to Python application code will not invalidate dependency build layers, speeding up CI/CD pipelines and local rebuilds.

3. **`--no-cache-dir` Optimization**:
   - Running `pip install --no-cache-dir` prevents pip from storing transient installation packages and wheels inside the image layers.

4. **Least Privilege Principle (Non-Root Security)**:
   - A dedicated system user `appuser` is created via `useradd --system --create-home appuser`.
   - Application code is chowned on transfer via `COPY --chown=appuser:appuser . .`, and runtime execution switches to `USER appuser`. In the event of an application vulnerability exploit, attackers are trapped in an unprivileged container environment.

5. **Clean Healthchecks with Warning Suppression**:
   - **Flask App**: Evaluated with `curl -f http://localhost:5000/health || exit 1` (interval 30s, timeout 5s, start-period 10s, retries 3).
   - **MySQL**: Evaluated with `MYSQL_PWD=$$MYSQL_ROOT_PASSWORD mysqladmin ping -h 127.0.0.1 -u root`. Passing the password via `MYSQL_PWD` inside the subshell suppresses the insecure command-line password warning (`mysqladmin: [Warning] Using a password on the command line interface can be insecure.`).

6. **Production-Ready Server (Gunicorn)**:
   - Replaces the single-threaded Flask development server with Gunicorn worker forks (`gunicorn --bind 0.0.0.0:5000 --workers 2 app:app`) to handle concurrency, worker timeouts, and request cycling.

7. **External Network & Volume Decoupling**:
   - `decoupled-net` and `decoupled_mysql_data` are declared with `external: true` in `docker-compose.yml`. This decouples persistent storage and network infrastructure from Compose lifecycles (`docker compose down` will never inadvertently destroy persistent database data).

### 🔎 Code Quality Check Summary

| Metric | Status | Implementation Details |
|---|:---:|---|
| **Base Image Size** | ✅ Passed | `python:3.13-slim` base with minimal `--no-install-recommends` curl utility. |
| **Layer Caching** | ✅ Passed | `requirements.txt` installed prior to application code copy. |
| **Storage Footprint** | ✅ Passed | `--no-cache-dir` flag prevents pip cache retention. |
| **Least Privilege (Security)** | ✅ Passed | Dedicated `appuser` system account drops root execution. |
| **Resiliency & Healthchecks** | ✅ Passed | Standardized `curl -f` probe for Flask and sanitized `mysqladmin ping` for MySQL. |
| **Startup Synchronization** | ✅ Passed | Compose `depends_on: mysql: condition: service_healthy` eliminates connection race conditions. |
| **Concurrency Handling** | ✅ Passed | Gunicorn multi-worker WSGI server configured for web traffic. |

---

## 📁 Repository Structure & Git Tracking Policy

In accordance with `.gitignore`, version-controlled code is strictly separated from local secrets, runtime volumes, and development artifacts:

```text
DecoupledStack - two-tier-flask-app/
├── docs/
│   └── DecoupledStack_Architecture.png # Architectural diagram
├── templates/
│   └── index.html          # Frontend UI (Jinja2 template with async fetch)
├── .dockerignore           # Excludes .git, cache, and env files from image builds
├── .env.example            # Environment template for credentials
├── .gitignore              # Ignores local secrets, data volumes, and dev artifacts
├── app.py                  # Two-tier Flask backend application & PyMySQL connection logic
├── docker-compose.yml      # Multi-container orchestration (external volume & network)
├── Dockerfile              # Multi-tier, secure non-root Dockerfile with curl healthcheck
├── message.sql             # SQL bootstrap script for initial database table creation
├── README.md               # Technical documentation & operational guide
└── requirements.txt        # Pinned Python dependencies (Flask, Gunicorn, PyMySQL, cryptography)
```

---

## 🔌 API Endpoints & Routes

| Method | Endpoint | Description |
|---|---|---|
| `GET` | `/` | Renders the web interface, lists all saved messages, and identifies the serving container hostname. |
| `POST` | `/submit` | Accepts form data (`new_message`), persists the entry in MySQL, and returns `{ "message": "<content>" }`. |
| `GET` | `/health` | Lightweight liveness probe returning `{ "status": "ok" }`. Deliberately decoupled from DB queries so intermittent DB latency does not trigger false negative pod/container restarts. |

---

## ⚙️ Environment Configuration

The application reads database parameters dynamically from environment variables:

| Variable | Default Fallback | Purpose |
|---|---|---|
| `MYSQL_HOST` | `localhost` (`mysql` in Docker network) | Hostname or container alias of the database server. |
| `MYSQL_PORT` | `3306` | Internal port exposed by the MySQL database instance. |
| `MYSQL_USER` | `admin` (fallback: `default_user`) | Application database username. |
| `MYSQL_PASSWORD` | `root` (fallback: `default_password`) | Application database user password. |
| `MYSQL_DB` | `default_db` | Target database schema name inside MySQL. |
| `FLASK_DEBUG` | off (`0`) | Enables interactive debug mode when launched via `python app.py`. |
---

## 🚀 Deployment Guide

### Prerequisites

Create the shared external bridge network and named volume before launching the stack:

```bash
docker network create decoupled-net
docker volume create decoupled_mysql_data
```

---

### Option 1: Docker Compose Deployment (Recommended)

1. **Configure Environment Variables**:
   ```bash
   cp .env.example .env
   ```

2. **Launch the Stack**:
   ```bash
   docker compose up -d --build
   ```

   **Key Compose Design Features**:
   - **Startup Synchronization**:
     ```yaml
     depends_on:
       mysql:
         condition: service_healthy
     ```
     Ensures the Flask application will not launch or attempt connections until MySQL passes its health checks.
   - **Host Port Conflict Prevention**:
     MySQL exposes `"3307:3306"` on the host machine. If you run a local MySQL server on port 3306, it will not collide with the container.

3. **Tear down the stack**:
   ```bash
   docker compose down
   ```
   *(Because `decoupled_mysql_data` is an external volume, your database data remains intact).*

---

### Option 2: Manual Docker CLI Deployment

#### Step 1: Run the MySQL Container
Using the external named volume:
```bash
docker run -d \
  --name mysql \
  --network decoupled-net \
  -v decoupled_mysql_data:/var/lib/mysql \
  -e MYSQL_ROOT_PASSWORD=root_secure_password \
  -e MYSQL_DATABASE=default_db \
  -e MYSQL_USER=admin \
  -e MYSQL_PASSWORD=root \
  -p 3307:3306 \
  mysql:8.4
```

#### Step 2: Build and Run the Flask Application Container
```bash
# Build the image
docker build -t two-tier-backend:latest .

# Run the backend
docker run -d \
  --name Decoupled-Stack \
  --network decoupled-net \
  -p 5000:5000 \
  -e MYSQL_HOST=mysql \
  -e MYSQL_USER=admin \
  -e MYSQL_PASSWORD=root \
  -e MYSQL_DB=default_db \
  two-tier-backend:latest
```
---

## 🧪 Verification & Runtime Inspection

1. **Verify Health Endpoint**:
   ```bash
   curl -i http://localhost:5000/health
   # Expected: HTTP/200 OK {"status":"ok"}
   ```

2. **Stream Application Logs**:
   ```bash
   docker logs -f Decoupled-Stack
   # Or for compose:
   docker compose logs -f flask-app
   ```

3. **Verify Non-Root User Execution**:
   ```bash
   docker exec -it Decoupled-Stack whoami
   # Expected output: appuser
   ```

4. **Inspect Container Health Status**:
   ```bash
   docker inspect --format='{{json .State.Health.Status}}' Decoupled-Stack
   # Expected output: "healthy"
   ```

5. **Access Application UI**:
   Open [http://localhost:5000](http://localhost:5000) in your web browser. Post a message to test end-to-end database persistence.
