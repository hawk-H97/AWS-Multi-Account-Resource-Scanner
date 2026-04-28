FROM python:3.11-slim

LABEL maintainer="aws-scanner-tool"
LABEL description="AWS All-Resource Inventory Scanner"

# System deps
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl unzip groff less \
    && rm -rf /var/lib/apt/lists/*

# AWS CLI v2
RUN curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip \
    && unzip -q /tmp/awscliv2.zip -d /tmp \
    && /tmp/aws/install \
    && rm -rf /tmp/awscliv2.zip /tmp/aws

# Python deps
RUN pip install --no-cache-dir boto3 openpyxl

# ── FIX: store the script in /app (NOT /scanner) ──────────────────────────────
# /scanner is the volume mount point for OUTPUT files (Excel reports, logs).
# If we put aws_scan.py in /scanner, the host volume mount OVERWRITES it
# when the container starts → "No such file or directory" error.
# Solution: script lives in /app, output goes to /scanner.
WORKDIR /app
COPY aws_scan.py .

# Create output dir — host volume will be mounted here at runtime
RUN mkdir -p /scanner

# Run script — output dir passed as env var so script knows where to write Excel
ENV OUTPUT_DIR=/scanner

ENTRYPOINT ["python3", "/app/aws_scan.py"]
