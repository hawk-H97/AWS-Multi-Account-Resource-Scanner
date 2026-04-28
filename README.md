# 🔍 AWS Multi-Account Resource Scanner

> **Automatically scan every AWS resource across every region and every account — no setup required. Just run the tool and get a fully formatted Excel report.**

---

## 📌 What Is This Tool?

The **AWS Multi-Account Resource Scanner** is a zero-configuration audit tool that discovers, inventories, and reports every AWS resource in one or more accounts — simultaneously. It is built for Cloud Engineers, Security Teams, DevOps, and FinOps practitioners who need complete visibility into AWS environments without writing any code or manually navigating the AWS Console.

You provide AWS credentials. The tool handles everything else — installing dependencies, scanning all services, querying CloudTrail for creator history, and producing a colour-coded Excel workbook per account.

---

## ✅ Key Capabilities

- **No manual setup** — Docker installs Python, boto3, openpyxl, and the AWS CLI automatically inside a container. You do not need Python, pip, or any AWS tools installed on your machine.
- **Multi-account parallel scanning** — scan 1 to N accounts at the same time. Each account gets its own isolated container.
- **All regions, automatically** — every AWS opt-in region is scanned without any configuration.
- **30+ AWS services** — EC2, RDS, S3, Lambda, IAM, EKS, ECS, CloudFormation, and more (full list below).
- **CloudTrail creator lookup** — enriches every resource with the IAM identity that created it (searches last 90 days).
- **Interrupt-safe** — press Ctrl+C at any time. Containers are stopped cleanly and any partial Excel files already saved are preserved.
- **Structured Excel output** — one workbook per account with a Summary sheet + one sheet per AWS service, colour-coded by resource status.

---

## 📋 The Only Real Requirement: Docker

You only need **Docker** installed and running. The tool builds a container image that includes everything else automatically:

| What's needed | Where it comes from |
|---|---|
| Python 3.11 | Installed inside the Docker container |
| boto3 (AWS SDK) | Installed inside the Docker container via pip |
| openpyxl (Excel writer) | Installed inside the Docker container via pip |
| AWS CLI v2 | Installed inside the Docker container |
| Your AWS credentials | You enter them interactively when the tool runs |

### Install Docker

**Linux (Ubuntu / Debian / Amazon Linux):**
```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
newgrp docker
```

**macOS:**
Download and install [Docker Desktop for Mac](https://www.docker.com/products/docker-desktop)

**Windows:**
Download and install [Docker Desktop for Windows](https://www.docker.com/products/docker-desktop)
> Enable WSL 2 backend when prompted during installation.

**Verify Docker is running:**
```bash
docker info
```
You should see engine information — no errors.

---

## 📁 Files in This Repository

```
aws-scanner-pkg/
├── aws_scan.py       — Core scanner script (runs inside Docker)
├── Dockerfile        — Container definition (auto-installs all dependencies)
├── tool.sh           — Interactive launcher for Linux / macOS
├── tool.bat          — Interactive launcher for Windows
└── README.md         — This file
```

---

## 🚀 How to Run

### Linux / macOS

```bash
# 1. Clone or download this repository
git clone https://github.com/your-org/aws-scanner-tool.git
cd aws-scanner-tool/aws-scanner-pkg

# 2. Make the script executable (one-time)
chmod +x tool.sh

# 3. Run the tool
bash tool.sh
```

### Windows

```
1. Open File Explorer and navigate to the aws-scanner-pkg folder
2. Double-click  tool.bat
   OR
   Open Command Prompt and run:  tool.bat
```

> **No pip install. No Python install. No AWS CLI install.** The Dockerfile handles all of that automatically when you run the tool for the first time.

---

## 🔄 What Happens Step by Step

```
1.  Tool starts and checks that Docker is installed and running

2.  Tool builds the Docker image  (first run only — takes ~2 minutes)
    └── Downloads Python 3.11-slim base image
    └── Installs boto3 and openpyxl via pip inside the container
    └── Installs AWS CLI v2 inside the container
    └── Copies aws_scan.py into the container
    ✓   Image is cached after first build — subsequent runs are instant

3.  Tool asks: How many AWS accounts do you want to scan?

4.  Tool collects AWS credentials for each account interactively:
    ├── AWS Access Key ID
    ├── AWS Secret Access Key
    ├── AWS Session Token       (optional — for SSO / temporary credentials)
    └── Default Region          (default: us-east-1)

5.  Tool launches one Docker container per account — all in parallel
    └── Credentials are passed securely as environment variables
    └── Each container mounts a dedicated output folder on your machine

6.  Inside each container, aws_scan.py runs automatically:
    ├── [1/4] Resolves the account ID via STS
    ├── [2/4] Discovers all active AWS regions
    ├── [3/4] Scans every service across every region
    │         (progress is printed to scan.log in real time)
    └── [4/4] Queries CloudTrail for creator info → writes Excel

7.  Containers auto-delete when done (Docker --rm flag)

8.  Tool shows a summary of all saved Excel files

9.  Tool asks: Scan more accounts? [Y/N]
```

---

## 📂 Output Folder Structure

All results are saved automatically in a folder called **`aws-scan-results`** created in the same directory where you run the tool. You do not need to create this folder — it is created automatically.

```
aws-scan-results/
├── scan1_20250428/
│   ├── aws_inventory_123456789012_20250428_1045.xlsx   ← Excel report
│   └── scan.log                                        ← Full scan log
├── scan2_20250428/
│   ├── aws_inventory_987654321098_20250428_1045.xlsx
│   └── scan.log
└── .running_20250428_104500                            ← Temp session file (auto-deleted)
```

### Excel Workbook Structure

Each account produces one `.xlsx` file named:
```
aws_inventory_<ACCOUNT_ID>_<YYYYMMDD>_<HHMM>.xlsx
```

Inside the workbook:

| Sheet | Contents |
|---|---|
| **Summary** | Count of all resources by service and type, with Active vs Inactive breakdown |
| **All Resources** | Every resource from every service in one combined sheet |
| **ec2** | EC2 resources only (instances, volumes, snapshots, etc.) |
| **rds** | RDS DB instances and clusters |
| **s3** | S3 buckets |
| **lambda** | Lambda functions |
| **iam** | IAM users, roles, policies, groups |
| **…** | One sheet per AWS service found in the account |

---

## 📊 Output Columns

Every sheet contains the following columns:

| Column | Description | Source |
|---|---|---|
| **Account ID** | 12-digit AWS account number | STS |
| **Resource Name** | Human-readable name or resource ID | Service API |
| **Resource Type** | e.g. `ec2:instance`, `rds:db`, `s3:bucket` | Service API |
| **Service** | e.g. `ec2`, `rds`, `s3`, `lambda` | Service API |
| **ARN** | Full Amazon Resource Name | Service API |
| **Region** | AWS region, or `global` for IAM / Route53 | Service API |
| **Owning Account** | Account that owns the resource | STS |
| **Tags** | All key=value tag pairs | Service API |
| **Created Date** | Date the resource was created | Service API |
| **Created By** | IAM user or role that created the resource | CloudTrail |
| **Status** | e.g. running / stopped / available / active | Service API |
| **Unassigned** | `Yes` = floating / unattached resource | Service API |
| **Last Reported At** | Timestamp when the scan ran | Scanner |

### RDS-Specific Columns (blank for all other services)

| Column | Description |
|---|---|
| **Engine** | Database engine (mysql, postgres, aurora, etc.) |
| **Engine Version** | Version string |
| **Instance Class** | e.g. db.t3.medium |
| **Multi-AZ** | True / False |
| **Storage (GB)** | Allocated storage in gigabytes |
| **Endpoint** | Connection endpoint hostname |
| **Last Restored** | Latest restorable point-in-time |

### Status Colour Coding

| Colour | Meaning | Example statuses |
|---|---|---|
| 🟢 Green | Active / healthy | running, available, active, in-use, enabled |
| 🔴 Red | Inactive / failed | stopped, terminated, failed, deleted, error |
| 🟠 Orange | Unknown / transitional | unassigned EIPs, unused security groups |

---

## 🌐 AWS Services Scanned

| Service | Resources Discovered |
|---|---|
| **EC2** | Instances, EBS Volumes, Snapshots, Security Groups, VPCs, Subnets, Elastic IPs, NAT Gateways, Internet Gateways, Route Tables, Network Interfaces, Key Pairs, AMIs (owned), Launch Templates, Transit Gateways |
| **RDS** | DB Instances, DB Clusters (Aurora) |
| **S3** | Buckets (all regions, with tags) |
| **Lambda** | Functions |
| **IAM** | Users, Roles, Customer-managed Policies, Groups |
| **DynamoDB** | Tables |
| **ELB** | Application, Network, and Gateway Load Balancers (v2) |
| **CloudFormation** | Stacks |
| **Secrets Manager** | Secrets |
| **SNS** | Topics |
| **SQS** | Queues |
| **KMS** | Customer-managed Keys (AWS-managed keys excluded) |
| **EKS** | Clusters |
| **ECS** | Clusters |
| **ElastiCache** | Cache Clusters |
| **CloudWatch** | Metric Alarms |
| **CloudWatch Logs** | Log Groups |
| **Step Functions** | State Machines |
| **ECR** | Repositories |
| **ACM** | Certificates |
| **Redshift** | Clusters |
| **Kinesis** | Data Streams |
| **SSM** | Parameter Store entries |
| **Glue** | Jobs |
| **CodePipeline** | Pipelines |
| **CodeBuild** | Projects |
| **SageMaker** | Endpoints |
| **WAFv2** | Web ACLs (regional) |
| **Route53** | Hosted Zones (global) |
| **CloudFront** | Distributions (global) |
| **MQ** | Brokers |

---

## 🔑 AWS Credentials & Permissions

### Credentials You Need

| Field | Description |
|---|---|
| **AWS Access Key ID** | Found in IAM Console → Users → Security credentials |
| **AWS Secret Access Key** | Shown once when the access key is created |
| **AWS Session Token** | Only required for temporary credentials (SSO / AssumeRole / STS) |
| **Default Region** | Any region (e.g. `us-east-1`) — the tool scans all regions automatically |

### Minimum IAM Permissions Required

The scanning account needs at minimum:

```
ReadOnlyAccess   (AWS managed policy)
+
cloudtrail:LookupEvents
```

Attaching the AWS-managed `ReadOnlyAccess` policy covers all service scanners. The `cloudtrail:LookupEvents` permission is needed for the "Created By" column.

### Credential Security

Credentials are passed to Docker containers as environment variables at runtime using the `-e` flag. They are:
- **Never written to disk** on your machine
- **Never logged** to `scan.log`
- **Destroyed when the container exits** (containers auto-delete with `--rm`)

---

## ⏱ Estimated Scan Time

| Account size | Resources | Estimated time |
|---|---|---|
| Small | ~100 resources | 5–10 minutes |
| Medium | ~500 resources | 15–20 minutes |
| Large | ~2,000+ resources | 30–45 minutes |

CloudTrail lookup adds approximately 5–10 minutes per account (searches the last 90 days across all regions).

**Multiple accounts run in parallel** — scanning 10 accounts takes the same wall-clock time as scanning 1 account.

---

## ⏹ Interrupting a Scan (Ctrl+C)

Pressing **Ctrl+C** at any time triggers a clean shutdown:

1. All running Docker containers are stopped immediately
2. All containers are deleted (no leftover containers or processes)
3. Any partial Excel files already written to your results folder are preserved
4. The tool asks: **"Do you want to run more scans? [Y/N]"**

Inside the container, if the Python scanner is mid-run when interrupted, it saves a `_PARTIAL` Excel file with whatever data was collected up to that point.

---

## 🛠 Troubleshooting

**"Docker is not installed or not in PATH"**
→ Install Docker from https://docs.docker.com/get-docker/ and ensure it is in your system PATH.

**"Docker daemon is not running"**
→ Open Docker Desktop and wait for the whale icon to stop animating (fully started). On Linux, run `sudo systemctl start docker`.

**"permission denied" on tool.sh**
→ Run `chmod +x tool.sh` then try again.

**"AccessDenied" errors in scan.log**
→ The credentials provided do not have sufficient permissions. Attach `ReadOnlyAccess` + `cloudtrail:LookupEvents` to the IAM user or role.

**"No resources found" / Empty Excel**
→ Open `scan.log` in the results folder. Look for authentication errors or region access errors at the top of the file.

**Container exits immediately**
→ Check `scan.log` — almost always caused by invalid or expired credentials. If using SSO/AssumeRole, make sure the Session Token is included and hasn't expired.

**Image build fails**
→ Check your internet connection. The first build downloads the Python base image (~150 MB) and installs packages. Retry once.

**Partial Excel was saved but scan didn't finish**
→ The file is named `aws_inventory_<ACCOUNT>_<TIMESTAMP>_PARTIAL.xlsx`. You can open and use it — the Summary sheet will indicate it is partial data. Re-run the tool with the same credentials to get a complete scan.

---

## 🏗 Architecture Overview

```
Your Machine
│
├── tool.sh / tool.bat              ← You run this
│   ├── Checks Docker is running
│   ├── Builds Docker image (first time)
│   ├── Collects credentials interactively
│   └── Launches one container per account
│
├── aws-scan-results/               ← Created automatically
│   ├── scan1_YYYYMMDD/
│   │   ├── aws_inventory_*.xlsx
│   │   └── scan.log
│   └── scan2_YYYYMMDD/
│       ├── aws_inventory_*.xlsx
│       └── scan.log
│
└── Docker (running locally)
    └── aws-scanner container(s)    ← One per account, run in parallel
        ├── Python 3.11
        ├── boto3 + openpyxl        ← Auto-installed by Dockerfile
        ├── AWS CLI v2              ← Auto-installed by Dockerfile
        └── aws_scan.py             ← The scanner script
            ├── STS  → account ID
            ├── EC2  → all regions
            ├── 30+  → services scanned per region
            ├── CloudTrail → creator lookup
            └── openpyxl → Excel output → /scanner (mounted to host)
```

---

## 💡 Tips

- **First run takes longer** — Docker builds the image (~2 min). All subsequent runs skip the build (image is cached).
- **Run on the same network as your AWS environment** for best API throughput. Running from a VPN or corporate network may add latency.
- **For large accounts**, check `scan.log` in real time: `tail -f aws-scan-results/scan1_*/scan.log`
- **For SSO credentials**, copy the temporary credentials (Access Key, Secret Key, Session Token) from the AWS SSO portal's "Command line or programmatic access" section.
- **The results folder persists** between runs. Each scan creates a new timestamped subfolder so previous results are never overwritten.

---

---

## 🤝 Contributing

Pull requests are welcome. For significant changes, please open an issue first to discuss what you'd like to change.

---

*Built for AWS Engineers who need complete infrastructure visibility without the complexity.*
