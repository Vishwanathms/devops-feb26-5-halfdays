Below is an **end-to-end Capstone Lab Manual** that extends your “GitHub Actions + Docker build & push” setup with:

* **Feature branch workflow + PRs**
* **CI on PR + push** (build + tests, fail on error)
* **Terraform infra via GitHub Actions** (plan on PR, apply on merge optional)
* **Release strategy** (versioned images)
* **Environment-specific variables (dev/test)** and **run container on the VM**

I’m using **AWS EC2** as the VM example (since Terraform needs a target). If you’re on Azure/GCP, the flow stays the same—only the Terraform module changes.

---

## 0) Capstone outcome

By the end of this lab, you will have:

1. A repo with a sample app (Python example) + Dockerfile
2. A **feature branch PR workflow**
3. **CI pipeline** triggered on PR and push:

   * build Docker image
   * run tests
   * fail fast on any error
4. **Terraform pipeline**:

   * `plan` on PR
   * `apply` on merge (optional, controlled)
   * creates an EC2 VM with Docker installed
5. **Release pipeline**:

   * version Docker images using Git tags + commit SHA
   * deploy to **dev** or **test** by running the container on the VM

---

## 1) Repo structure

Create this structure:

```
capstone/
├─ app/
│  ├─ src/
│  │  └─ main.py
│  ├─ tests/
│  │  └─ test_basic.py
│  ├─ requirements.txt
│  └─ Dockerfile
├─ infra/
│  ├─ main.tf
│  ├─ variables.tf
│  ├─ outputs.tf
│  └─ env/
│     ├─ dev.tfvars
│     └─ test.tfvars
└─ .github/
   └─ workflows/
      ├─ ci.yml
      ├─ terraform.yml
      └─ deploy.yml
```

---

## 2) App code (example)

### `app/src/main.py`

```python
from flask import Flask

app = Flask(__name__)

@app.get("/")
def hello():
    return {"message": "Hello from Capstone!"}

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
```

### `app/tests/test_basic.py`

```python
def test_truth():
    assert 1 + 1 == 2
```

### `app/requirements.txt`

```
flask==3.0.0
pytest==8.0.0
```

### `app/Dockerfile`

```dockerfile
FROM python:3.12-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY src/ src/
EXPOSE 8080

CMD ["python", "src/main.py"]
```

---

## 3) Feature branch workflow with PRs

### Branching rules (lab steps)

1. `main` is protected
2. All work happens on `feature/*`
3. Developers raise **PR → main**
4. PR requires:

   * CI workflow success
   * at least 1 approval
   * (optional) Terraform plan success

**GitHub settings (recommended):**

* Settings → Branches → Add branch protection rule → `main`

  * ✅ Require pull request reviews
  * ✅ Require status checks to pass: `CI`
  * ✅ Require branches to be up to date (optional)

---

## 4) CI Pipeline (GitHub Actions) — PR + push, build & tests, fail on errors

Create: `.github/workflows/ci.yml`

```yaml
name: CI

on:
  pull_request:
    branches: [ "main" ]
  push:
    branches: [ "main" ]

jobs:
  build-test:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: "3.12"

      - name: Install dependencies
        working-directory: app
        run: |
          python -m pip install --upgrade pip
          pip install -r requirements.txt

      - name: Run tests (fail pipeline if any test fails)
        working-directory: app
        run: |
          pytest -q

      - name: Docker build (fail pipeline if build fails)
        run: |
          docker build -t capstone-app:ci ./app
```

### What makes it “fail on errors”?

* GitHub Actions fails a step automatically if the command exits non-zero (tests failing, docker build failing, etc.)

---

## 5) Docker build & push with version strategy

### Versioning strategy (recommended)

* If the commit is tagged `v1.2.0`, publish:

  * `dockerhubuser/capstone-app:v1.2.0`
  * `dockerhubuser/capstone-app:sha-<shortsha>`
* For main branch builds without tags:

  * `dockerhubuser/capstone-app:sha-<shortsha>`

We’ll implement this in the **deploy** pipeline (section 8).

---

## 6) Infrastructure Provisioning with Terraform (VM with Docker installed)

### 6.1 Terraform files (AWS EC2 example)

#### `infra/main.tf`

```hcl
terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# --- Networking (simple default VPC usage for lab) ---
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# --- Security group: allow SSH + App port ---
resource "aws_security_group" "capstone_sg" {
  name        = "capstone-sg-${var.env}"
  description = "SSH + App access"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  ingress {
    description = "App"
    from_port   = var.app_port
    to_port     = var.app_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- Find latest Ubuntu 22.04 AMI ---
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

# --- EC2 with Docker installed via user_data ---
resource "aws_instance" "capstone_vm" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.capstone_sg.id]
  associate_public_ip_address = true
  key_name                    = var.ssh_key_name

  user_data = <<-EOF
    #!/bin/bash
    set -eux
    apt-get update -y
    apt-get install -y ca-certificates curl gnupg
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
      > /etc/apt/sources.list.d/docker.list
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    usermod -aG docker ubuntu
    systemctl enable docker
    systemctl start docker
  EOF

  tags = {
    Name = "capstone-vm-${var.env}"
    Env  = var.env
  }
}
```

#### `infra/variables.tf`

```hcl
variable "env" {
  description = "Environment name (dev/test)"
  type        = string
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "app_port" {
  type    = number
  default = 8080
}

variable "allowed_ssh_cidr" {
  description = "Your public IP/32 for SSH (recommended)."
  type        = string
}

variable "ssh_key_name" {
  description = "Existing EC2 keypair name"
  type        = string
}
```

#### `infra/outputs.tf`

```hcl
output "vm_public_ip" {
  value = aws_instance.capstone_vm.public_ip
}
```

#### Environment tfvars

`infra/env/dev.tfvars`

```hcl
env              = "dev"
allowed_ssh_cidr = "YOUR_PUBLIC_IP/32"
ssh_key_name     = "your-keypair-name"
```

`infra/env/test.tfvars`

```hcl
env              = "test"
allowed_ssh_cidr = "YOUR_PUBLIC_IP/32"
ssh_key_name     = "your-keypair-name"
```

---

## 7) Terraform runs via GitHub Actions (Plan on PR, Apply on merge optional)

Create: `.github/workflows/terraform.yml`

```yaml
name: Terraform

on:
  pull_request:
    branches: ["main"]
    paths:
      - "infra/**"
  push:
    branches: ["main"]
    paths:
      - "infra/**"

permissions:
  contents: read
  pull-requests: write

jobs:
  plan:
    if: github.event_name == 'pull_request'
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: infra

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: "1.6.6"

      - name: Terraform Init
        run: terraform init

      - name: Terraform Validate
        run: terraform validate

      - name: Terraform Plan (dev)
        run: terraform plan -var-file=env/dev.tfvars -no-color
        env:
          AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}

  apply:
    # OPTIONAL APPLY ON MERGE:
    # runs only when PR is merged to main (push event)
    if: github.event_name == 'push'
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: infra

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: "1.6.6"

      - name: Terraform Init
        run: terraform init
        env:
          AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}

      - name: Terraform Apply (dev)
        run: terraform apply -auto-approve -var-file=env/dev.tfvars
        env:
          AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
```

### Notes (important)

* This example uses **AWS access keys as GitHub Secrets**.
* For production-grade, prefer **OIDC role assumption** (better security), but for lab this is OK.

**Required GitHub Secrets:**

* `AWS_ACCESS_KEY_ID`
* `AWS_SECRET_ACCESS_KEY`

---

## 8) Release Strategy: versioned Docker images + env variables + run container on VM

### 8.1 Git tags

When you’re ready to release:

```bash
git tag v1.0.0
git push origin v1.0.0
```

### 8.2 Deploy workflow (build, push, then run on VM)

Create: `.github/workflows/deploy.yml`

```yaml
name: Build-Push-Deploy

on:
  push:
    branches: ["main"]
    tags:
      - "v*"

jobs:
  build_push:
    runs-on: ubuntu-latest
    outputs:
      image_tag: ${{ steps.meta.outputs.image_tag }}

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set image tag
        id: meta
        run: |
          SHORT_SHA="${GITHUB_SHA::7}"

          # If it's a git tag like v1.2.0, use that; otherwise sha tag
          if [[ "${GITHUB_REF}" == refs/tags/* ]]; then
            TAG_NAME="${GITHUB_REF#refs/tags/}"
            echo "image_tag=${TAG_NAME}" >> "$GITHUB_OUTPUT"
          else
            echo "image_tag=sha-${SHORT_SHA}" >> "$GITHUB_OUTPUT"
          fi

      - name: Login to Docker Hub
        run: |
          echo "${{ secrets.DOCKERHUB_TOKEN }}" | docker login -u "${{ secrets.DOCKERHUB_USERNAME }}" --password-stdin

      - name: Build image
        run: |
          docker build -t "${{ secrets.DOCKERHUB_USERNAME }}/capstone-app:${{ steps.meta.outputs.image_tag }}" ./app

      - name: Push image
        run: |
          docker push "${{ secrets.DOCKERHUB_USERNAME }}/capstone-app:${{ steps.meta.outputs.image_tag }}"

  deploy_dev:
    needs: build_push
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      # --- Fetch VM public IP from Terraform output ---
      # (Simplest approach: run terraform output in infra folder)
      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: "1.6.6"

      - name: Terraform Init
        working-directory: infra
        run: terraform init
        env:
          AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}

      - name: Read VM IP
        id: vm
        working-directory: infra
        run: |
          IP=$(terraform output -raw vm_public_ip)
          echo "vm_ip=$IP" >> "$GITHUB_OUTPUT"
        env:
          AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}

      # --- Deploy by SSH-ing into VM and running docker container ---
      - name: Deploy container on VM (dev)
        uses: appleboy/ssh-action@v1.0.3
        with:
          host: ${{ steps.vm.outputs.vm_ip }}
          username: ubuntu
          key: ${{ secrets.EC2_SSH_PRIVATE_KEY }}
          script: |
            set -eux
            docker ps -a || true

            # pull the new version
            docker pull ${{ secrets.DOCKERHUB_USERNAME }}/capstone-app:${{ needs.build_push.outputs.image_tag }}

            # stop old container if exists
            docker rm -f capstone-dev || true

            # environment-specific variables (dev)
            docker run -d --name capstone-dev \
              -p 8080:8080 \
              -e APP_ENV=dev \
              -e LOG_LEVEL=debug \
              --restart unless-stopped \
              ${{ secrets.DOCKERHUB_USERNAME }}/capstone-app:${{ needs.build_push.outputs.image_tag }}

            docker ps
```

### What this does (in simple terms)

* On every push to `main` (and on version tags), it:

  1. builds the docker image
  2. pushes it to Docker Hub with a **versioned tag**
  3. reads Terraform output to get the VM IP
  4. SSH into VM and runs the container with **dev env variables**

**Required GitHub Secrets:**

* `DOCKERHUB_USERNAME`
* `DOCKERHUB_TOKEN` (or password, token is recommended)
* `EC2_SSH_PRIVATE_KEY` (private key for the EC2 keypair)
* `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`

---

## 9) Add “test” environment deployment (optional but recommended)

### Approach

* Use **GitHub Environments**: `dev`, `test`
* Each environment can have its own secrets (VM IP, SSH key, etc.)
* Trigger deploy to test manually or via tag like `v*` only.

Example idea:

* `deploy_dev` runs on merge to main
* `deploy_test` runs on tag `v*` or manual dispatch approval

Add to `deploy.yml`:

```yaml
on:
  workflow_dispatch:
    inputs:
      environment:
        type: choice
        options: [dev, test]
        required: true
```

And then use:

* `-e APP_ENV=${{ inputs.environment }}`
* Use different container name `capstone-test`
* Use different port mapping if needed (or different VM)

---

## 10) Student tasks checklist (what they must do)

### Task A — Feature branch & PR

* Create `feature/add-endpoint`
* Make a change in app
* Raise PR to `main`
* Confirm CI runs and blocks merge if tests fail

### Task B — Terraform plan on PR

* Change infra (e.g., security group port)
* Raise PR
* Confirm Terraform plan runs (PR event)

### Task C — Apply on merge

* Merge PR
* Confirm Terraform apply runs (push event)

### Task D — Release and deploy

* Create tag `v1.0.0`
* Push tag
* Confirm docker image is pushed with `v1.0.0`
* Confirm VM runs container and app is reachable:

  * `http://<vm_ip>:8080/`

---

## 11) Troubleshooting guide (common failures)

* **CI tests failing**

  * Check `pytest` output in Actions logs
* **Docker push denied**

  * Verify Docker Hub creds (token), repo name
* **Terraform auth errors**

  * Confirm AWS secrets are correct
* **SSH deploy fails**

  * Make sure Security Group allows SSH from your IP (`allowed_ssh_cidr`)
  * Confirm `EC2_SSH_PRIVATE_KEY` matches the keypair used in Terraform
* **Container not reachable**

  * Confirm SG allows port `8080`
  * On VM: `docker logs capstone-dev`
