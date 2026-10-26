# Infrastructure as Code Lab on AWS

> This README was generated with [Claude](https://claude.ai) by Anthropic.

A small, end-to-end DevOps lab:

- **Terraform** creates an EC2 server, a security group and a private S3 bucket on AWS.
- **Ansible** installs Docker on the new server and deploys the app container.
- **Jenkins** runs everything in one pipeline: tests, Docker build, **Trivy** security scan, push to Docker Hub, Terraform, Ansible and a smoke test.
- **Kubernetes (minikube)** runs the same container locally with a Deployment and a Service.

```
 git push ──► Jenkins (on your laptop)
                │
                ├─ pytest
                ├─ docker build
                ├─ Trivy scan ── CRITICAL found? ──► pipeline stops
                ├─ docker push ──► Docker Hub
                ├─ terraform apply ──► AWS: EC2 + security group + S3
                ├─ ansible: install Docker on EC2
                ├─ ansible: run container (port 80)
                └─ curl /health ──► ✅ http://<EC2-IP>
```

## Folder structure

| Folder / file | What it does |
|---|---|
| `app/` | Tiny Python Flask web app with a `/health` endpoint, unit tests and a `Dockerfile` |
| `terraform/` | AWS infrastructure: EC2, security group, SSH key, S3 bucket. Also writes the Ansible inventory |
| `ansible/` | `install-docker.yml` prepares the server, `deploy-app.yml` runs the container |
| `Jenkinsfile` | The CI/CD pipeline (with the Trivy scan stage) |
| `jenkins/` | `Dockerfile` + `docker-compose.yml` that start a Jenkins with Terraform, Ansible and Docker already installed |
| `k8s/` | Kubernetes Deployment and Service for minikube |

---

## 0. What you need

| Tool | Why | Install |
|---|---|---|
| Docker Desktop (or Docker Engine on Linux) | Runs Jenkins, builds images | https://docs.docker.com/get-docker/ |
| An AWS account | Where the server runs | https://aws.amazon.com/free/ |
| A Docker Hub account (free) | Stores the image so the server can pull it | https://hub.docker.com/ |
| A GitHub account | Jenkins pulls the code from your repo | https://github.com/ |
| Terraform, Ansible (optional) | Only for Part A (manual run). Jenkins already has them | https://developer.hashicorp.com/terraform/install, `pip install ansible` |
| minikube + kubectl | Part C, local Kubernetes | https://minikube.sigs.k8s.io/docs/start/ |

> **Windows:** run the commands in WSL2 (Ubuntu). Ansible does not run natively on Windows.

---

## 1. One-time setup

### 1.1 Create an AWS user for the lab (don't use the root account)

1. AWS Console → **IAM → Users → Create user**, name it `iac-lab`.
2. Attach the policies **AmazonEC2FullAccess** and **AmazonS3FullAccess** (fine for a lab; in a real job you would scope them tighter).
3. Open the user → **Security credentials → Create access key → Command Line Interface**. Save the *Access key ID* and *Secret access key*.

### 1.2 Set a budget alarm (2 minutes, highly recommended)

AWS Console → **Billing → Budgets → Create budget → Zero spend budget** (or a $1 monthly budget). AWS emails you as soon as anything costs money.

### 1.3 Create an SSH key for the server

```bash
ssh-keygen -t ed25519 -f ~/.ssh/iac-lab -N ""
# creates ~/.ssh/iac-lab (private, keep secret) and ~/.ssh/iac-lab.pub (public)
```

### 1.4 Create a Docker Hub access token

Docker Hub → **Account settings → Personal access tokens → Generate** (Read & Write). Save the token.

### 1.5 Push this project to your GitHub

Create an **empty** repo on GitHub named `iac-lab` (no README, no .gitignore), then:

```bash
cd iac-lab
git init
git add .
git commit -m "Infrastructure as Code Lab: Terraform, Ansible, Jenkins, Trivy, Kubernetes"
git branch -M main
git remote add origin https://github.com/<YOUR_GITHUB_USER>/iac-lab.git
git push -u origin main
```

Before every commit, check that `git status` shows **no** `terraform.tfvars`, `*.tfstate` or key files. The `.gitignore` already excludes them.

---

## Part A: run it by hand first (recommended, to understand each step)

### A1. Build and test the app locally

```bash
cd app
docker build -t iac-lab-app:local .
docker run --rm -p 8080:8080 iac-lab-app:local
# open http://localhost:8080 and http://localhost:8080/health, then Ctrl+C
```

Scan it with Trivy, the same way the pipeline does:

```bash
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy:0.65.0 image --severity HIGH,CRITICAL iac-lab-app:local
```

### A2. Create the AWS infrastructure with Terraform

```bash
export AWS_ACCESS_KEY_ID=...        # from step 1.1
export AWS_SECRET_ACCESS_KEY=...

cd terraform
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars:
#   allowed_ssh_cidr = "<output of: curl -s https://checkip.amazonaws.com>/32"
#   ssh_public_key   = "<contents of ~/.ssh/iac-lab.pub>"

terraform init      # downloads the AWS provider
terraform plan      # shows what will be created (5-8 resources), changes nothing
terraform apply     # type "yes"
```

At the end Terraform prints `server_public_ip`, `app_url`, `ssh_command` and the bucket name. It also writes `ansible/inventory.ini` with the server's IP.

### A3. Configure the server and deploy with Ansible

Push your image to Docker Hub first so the server can pull it:

```bash
docker login
# --platform linux/amd64 because the EC2 server is x86 (matters on Apple Silicon Macs)
docker build --platform linux/amd64 -t <DOCKERHUB_USER>/iac-lab-app:latest ../app
docker push <DOCKERHUB_USER>/iac-lab-app:latest
```

Then:

```bash
cd ../ansible
ansible-galaxy collection install -r requirements.yml
ansible web -m ping                           # should answer "pong"
ansible-playbook install-docker.yml
ansible-playbook deploy-app.yml -e app_image=<DOCKERHUB_USER>/iac-lab-app:latest
```

Open the `app_url` from Terraform in your browser. 🎉

### A4. Tear it down

```bash
cd ../terraform
terraform destroy   # type "yes"
```

---

## Part B: the full Jenkins pipeline

### B1. Start Jenkins

```bash
cd jenkins
docker compose up -d --build        # first build takes a few minutes
docker exec iac-lab-jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

Open http://localhost:8080, paste the password, choose **Install suggested plugins**, create your admin user.

### B2. Add three credentials

**Manage Jenkins → Credentials → System → Global credentials → Add credentials**

| ID (type exactly) | Kind | Values |
|---|---|---|
| `aws-creds` | Username with password | Username = AWS access key ID, Password = secret access key |
| `dockerhub-creds` | Username with password | Username = Docker Hub user, Password = access token |
| `ec2-ssh-key` | SSH Username with private key | Username = `ubuntu`, Private key → Enter directly → paste the contents of `~/.ssh/iac-lab` |

### B3. Create the pipeline job

1. **New Item** → name `iac-lab` → **Pipeline** → OK.
2. Under **Pipeline**: Definition = *Pipeline script from SCM*, SCM = *Git*, Repository URL = `https://github.com/<YOUR_GITHUB_USER>/iac-lab.git`, Branch = `*/main`, Script Path = `Jenkinsfile`.
3. Save → **Build Now** once (this first run only loads the parameters and may fail, that's normal).
4. **Build with Parameters** → ACTION = `deploy`, DOCKERHUB_USER = your Docker Hub user → **Build**.

Watch the stages in the Stage View. The last stage prints the URL of your app.

**Try the security gate:** change the first line of `app/Dockerfile` to an old image, e.g. `FROM python:3.8-slim-buster`, push, and build again. Trivy should find CRITICAL vulnerabilities and stop the pipeline before anything is deployed. Change it back afterwards.

**Try a change:** edit the `<h1>` text in `app/app.py`, push, build again. The new version (build number) appears on the page without any manual step.

### B4. Destroy from Jenkins

**Build with Parameters** → ACTION = `destroy`. This deletes the EC2 server, security group, key pair and S3 bucket.

> Terraform keeps its state file in the Jenkins workspace (inside the `jenkins_home` Docker volume). Don't delete that volume or the job before you've run `destroy`, otherwise Terraform no longer knows what it created (you would then delete the resources by hand in the AWS Console; they all have the tag `Project = iac-lab`).

---

## Part C: Kubernetes on minikube (local, free)

```bash
minikube start

# build the image directly inside minikube, so no registry is needed
minikube image build -t iac-lab-app:local app

kubectl apply -f k8s/
kubectl get pods -w              # wait until both pods are Running and READY 1/1 (Ctrl+C)
minikube service iac-lab-app     # opens the app in your browser
```

Things to try:

```bash
kubectl scale deployment iac-lab-app --replicas=4
kubectl get pods -o wide
kubectl delete pod <one-pod-name>      # Kubernetes starts a new one automatically
kubectl logs deployment/iac-lab-app
```

Refresh the page a few times: "Served by" changes because the Service balances across pods.

Clean up: `kubectl delete -f k8s/` and `minikube stop` (or `minikube delete`).

---

## Costs and cleanup

| Resource | Free tier | Without free tier (approx.) |
|---|---|---|
| EC2 `t3.micro` | Included in the AWS free tier* | ~$0.01 / hour |
| Public IPv4 address | Included while attached to a free-tier instance* | ~$0.005 / hour |
| EBS disk 8 GB gp3 | 30 GB included | ~$0.70 / month |
| S3 bucket | 5 GB included | almost nothing (it stays empty) |
| Data transfer | 100 GB/month out included | – |

\* AWS changed its free tier in July 2025: new accounts get credits (up to $200) on a free plan instead of the old 12-month model. Either way, running this lab for a few hours costs cents at most. Check your plan under **Billing → Free tier**.

**Rules to stay at $0:**

1. Always run `terraform destroy` (or the Jenkins `destroy` build) when you're done for the day.
2. Set the budget alarm from step 1.2.
3. Afterwards check the AWS Console in your region (default **eu-central-1 / Frankfurt**): EC2 → Instances should show none running, and no leftover Elastic IPs or volumes.
4. Don't change `instance_type` to something bigger.

---

## Troubleshooting

| Problem | Fix |
|---|---|
| `ansible ... UNREACHABLE` / SSH timeout | Your IP changed. Update `allowed_ssh_cidr` and run `terraform apply` again (Jenkins does this automatically). |
| `Permission denied (publickey)` | The key in `terraform.tfvars` / Jenkins doesn't match `~/.ssh/iac-lab`. Check `chmod 600 ~/.ssh/iac-lab`. |
| `InvalidAMIID` or `Unsupported instance type` | Some regions use `t2.micro` for the free tier. Set `instance_type = "t2.micro"`. |
| Trivy stage fails | It works as intended: read the CVE list, update the base image or the package version in `requirements.txt`. |
| `exec format error` on the server | The image was built for ARM (Apple Silicon). The pipeline builds with `--platform linux/amd64`; do the same when building by hand. |
| `permission denied ... docker.sock` in Jenkins | Make sure you started Jenkins with the provided `docker-compose.yml`. |
| minikube pod `ErrImageNeverPull` | Run `minikube image build -t iac-lab-app:local app` again. |

---

## What I'd add next

- Store the Terraform state in an S3 backend with locking instead of the Jenkins workspace.
- Push images to Amazon ECR instead of Docker Hub.
- Use a GitHub webhook so every push starts the pipeline automatically.
- Deploy to a managed Kubernetes cluster (EKS) with the same manifests.
