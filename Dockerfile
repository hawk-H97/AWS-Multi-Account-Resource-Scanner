FROM python:3.11-slim

LABEL maintainer="aws-scanner-tool"
LABEL description="AWS All-Resource Inventory Scanner"

# System deps
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    unzip \
    groff \
    less \
    && rm -rf /var/lib/apt/lists/*

# AWS CLI v2
RUN curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip \
    && unzip -q /tmp/awscliv2.zip -d /tmp \
    && /tmp/aws/install \
    && rm -rf /tmp/awscliv2.zip /tmp/aws

# Python deps
RUN pip install --no-cache-dir boto3 openpyxl

# Working dir
WORKDIR /scanner

# Copy scan script
COPY aws_scan.py .

# Output dir (mounted from host)
RUN mkdir -p /output

# Default: run the scan script
# Credentials injected via -e at runtime
ENTRYPOINT ["python3", "aws_scan.py"]
