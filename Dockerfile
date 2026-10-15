# ==============================================================================
# STAGE 1: Build Stage (Heavy & Tool-Rich)
# ==============================================================================
FROM python:3.13 AS builder

WORKDIR /app

COPY requirements.txt .

# Installs modules and binary wrappers into a public installation prefix
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt


# ==============================================================================
# STAGE 2: Runtime Stage (Lean, Production-Ready & Secure)
# ==============================================================================
FROM python:3.13-slim AS final

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends curl && \
    rm -rf /var/lib/apt/lists/*

# Create a non-root system user early
RUN useradd --system --create-home appuser

# Copy artifacts into /usr/local and assign permissions to appuser instantly
COPY --from=builder --chown=appuser:appuser /install /usr/local

# Copy application source files
COPY --chown=appuser:appuser . .

# Drop privileges safely
USER appuser

EXPOSE 5000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:5000/health || exit 1

CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "app:app"]