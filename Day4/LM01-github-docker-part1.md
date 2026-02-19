## Lab Manual: GitHub Actions + Docker (Python App)

**Repo files in root:** `app.py`, `requirements.txt`, `Dockerfile`

---

## 1) Lab Objective

Build a **Python Docker image** in GitHub Actions and **push it to your personal Docker Hub**.

### Stages

* **Stage 1:** Docker info
* **Stage 2:** Docker build
* **Stage 3:** Push to Docker Hub (secure login using GitHub Secrets)

---

## 2) Prerequisites

* GitHub repo created
* Docker Hub account + **access token**
* Git installed locally (or use GitHub web editor)

---

## 3) Create the Python App (Root Path)

### 3.1 `app.py`

```python
from flask import Flask, jsonify
import os

app = Flask(__name__)

@app.get("/")
def home():
    return jsonify(
        message="Hello from GitHub Actions Docker Lab (Python)!",
        env=os.getenv("APP_ENV", "dev")
    )

@app.get("/health")
def health():
    return jsonify(status="ok")

if __name__ == "__main__":
    # Flask will listen on 0.0.0.0 for container access
    app.run(host="0.0.0.0", port=8080)
```

### 3.2 `requirements.txt`

```txt
flask==3.0.2
```

---

## 4) Create Dockerfile (Root Path)

### `Dockerfile`

```dockerfile
FROM python:3.12-slim

WORKDIR /app

# Faster, cleaner logs
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application
COPY app.py .

EXPOSE 8080

CMD ["python", "app.py"]
```

---

## 5) Test Locally (Optional but Recommended)

From repo root:

```bash
docker build -t python-gha-lab:local .
docker run -p 8080:8080 python-gha-lab:local
```

Test:

* [http://localhost:8080/](http://localhost:8080/)
* [http://localhost:8080/health](http://localhost:8080/health)

---

## 6) Docker Hub Token + GitHub Secrets

### 6.1 Create Docker Hub Access Token

Docker Hub → **Account Settings → Security → New Access Token**

### 6.2 Add GitHub Secrets

GitHub Repo → **Settings → Secrets and variables → Actions → New repository secret**

Add:

* `DOCKERHUB_USERNAME` = your Docker Hub username
* `DOCKERHUB_TOKEN` = Docker Hub access token

---

## 7) Create GitHub Actions Workflow (3 Stages)

Create file: `.github/workflows/docker-ci.yml`

```yaml
name: Python Docker CI - Build & Push

on:
  push:
    branches: ["main"]

jobs:
  docker:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      # -------------------------
      # Stage 1 — Docker info
      # -------------------------
      - name: Stage 1 - Docker info
        run: |
          echo "Docker version:"
          docker --version
          echo "Docker info:"
          docker info

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      # -------------------------
      # Stage 2 — BUild with commit ID as TAG
      # -------------------------

      - name: Set image tag
        run: echo "IMAGE_TAG=${GITHUB_SHA::7}" >> $GITHUB_ENV

      - name: Build image
        run: |
          docker build -t ${{ secrets.DOCKERHUB_USERNAME }}/python-gha-lab:${{ env.IMAGE_TAG }} .
          docker images

      # -------------------------
      # Stage 3 — Push to Docker Hub
      # -------------------------
      - name: Login to Docker Hub
        run: echo "${{ secrets.DOCKERHUB_TOKEN }}" | docker login -u "${{ secrets.DOCKERHUB_USERNAME }}" --password-stdin

      - name: Stage 3 - Push Docker image
        run: |
          docker push ${{ secrets.DOCKERHUB_USERNAME }}/python-gha-lab:${{ env.IMAGE_TAG }}
```

Commit + push:

```bash
git add .
git commit -m "Add Python app, Dockerfile, and GitHub Actions workflow"
git push origin main
```

---

## 8) Verification

### In GitHub

Repo → **Actions** → open latest run
Confirm:

* Stage 1 prints Docker version/info
* Stage 2 builds image successfully
* Stage 3 logs in and pushes image

### In Docker Hub

Docker Hub → **Repositories**
You should see:

* `python-gha-lab`
* tag: `latest`

---

## 9) Troubleshooting

### `denied: requested access to the resource is denied`

* Ensure image name starts with your Docker Hub username:
  `${{ secrets.DOCKERHUB_USERNAME }}/python-gha-lab:latest`

### `unauthorized: incorrect username or password`

* Token incorrect/expired → regenerate token and update `DOCKERHUB_TOKEN`

### Build fails: dependency install

* Check `requirements.txt` spelling/version
* Ensure files are in **repo root**

---

## 10) Optional Upgrade: Tag with Git SHA

Replace Stage 2 & 3 with:

```yaml
      - name: Set image tag
        run: echo "IMAGE_TAG=${GITHUB_SHA::7}" >> $GITHUB_ENV

      - name: Build Docker image (SHA tag)
        run: docker build -t ${{ secrets.DOCKERHUB_USERNAME }}/python-gha-lab:${{ env.IMAGE_TAG }} .

      - name: Push Docker image (SHA tag)
        run: docker push ${{ secrets.DOCKERHUB_USERNAME }}/python-gha-lab:${{ env.IMAGE_TAG }}
```

---

If you want, I can also provide the **production-grade workflow** using:

* `docker/login-action`
* `docker/build-push-action`
* caching (`cache-from/cache-to`) to speed builds.
