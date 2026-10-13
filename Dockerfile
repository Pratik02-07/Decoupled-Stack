#base - lightweight python image
FROM python:3.13-slim

# Set the working directory in the container
WORKDIR /app

# Replace "RUN useradd --system --no-create-home appuser" with:
RUN useradd --system --create-home appuser

# 1. Copy only the requirements first
# Dependencies are pure Python (PyMySQL), so no compiler or system packages are needed
COPY requirements.txt .

# 2. Install dependencies (Docker will cache this layer!)
RUN pip install --no-cache-dir -r requirements.txt

# 3. Copy the rest of the application code AND transfer ownership to appuser
COPY --chown=appuser:appuser . .

# Switch to the non-root user for security
USER appuser

# expose port 5000
EXPOSE 5000

# No curl in slim images, so use Python for the container health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:5000/health')"

# Specify the command to run your application
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "--timeout", "90", "app:app"]
