# Deploying OpenClaw Containers to the Cloud

This guide covers deploying your OpenClaw agent(s) to AWS and other cloud providers. The core idea: push your Docker images to a registry, then run them on a cloud VM or container service.

## Approach A: EC2 Instance (Simplest)

The closest to what you're doing locally. One VM, Docker Compose, SSH in to manage.

### 1. Launch an EC2 instance

- **AMI**: Amazon Linux 2023 or Ubuntu 24.04
- **Instance type**: `t3.small` (2 vCPU, 2GB RAM) is fine for one agent. `t3.medium` for multiple.
- **Storage**: 30GB gp3
- **Security group**: Open ports 22 (SSH), 18789 (gateway), 18791 (if QA agent)

### 2. Install Docker

```bash
# Amazon Linux 2023
sudo dnf install -y docker git
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
# Log out and back in

# Install Docker Compose plugin
sudo mkdir -p /usr/local/lib/docker/cli-plugins
sudo curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-$(uname -m) \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
```

### 3. Clone the repo and copy your data

```bash
# On the EC2 instance
git clone https://github.com/openclaw/openclaw.git ~/openclaw

# From your Mac — copy your config
scp -r ~/openclaw-docker ec2-user@<your-ec2-ip>:~/openclaw-docker
```

### 4. Copy your local scripts

Your `launch.sh` and `Dockerfile.tools` work as-is. Adjust paths if your home directory differs:

```bash
# On EC2, edit ~/openclaw-docker/launch.sh
# Change REPO_DIR="$HOME/openclaw" (no Dev/ subdirectory)
```

### 5. Build and run

```bash
~/openclaw-docker/launch.sh
```

### 6. Access

- **Dashboard**: `http://<ec2-ip>:18789/chat?session=main&token=<your-token>`
- **Telegram**: Works automatically (bot polls Telegram servers, no inbound ports needed)
- **SSH shell**: `ssh ec2-user@<ec2-ip>` then `docker compose exec ...`

### Security considerations

- **Don't expose port 18789 to 0.0.0.0** unless you have token auth. Use SSH tunneling instead:
  ```bash
  ssh -L 18789:localhost:18789 ec2-user@<ec2-ip>
  # Then open http://localhost:18789 on your Mac
  ```
- Use AWS Security Groups to restrict access to your IP only
- Consider putting it behind a reverse proxy (Caddy/nginx) with HTTPS

---

## Approach B: ECS Fargate (Serverless Containers)

No VM to manage. AWS runs your container for you.

### 1. Push image to ECR

```bash
# Create ECR repository
aws ecr create-repository --repository-name openclaw-tools

# Login to ECR
aws ecr get-login-password | docker login --username AWS --password-stdin <account-id>.dkr.ecr.<region>.amazonaws.com

# Tag and push
docker tag openclaw:tools <account-id>.dkr.ecr.<region>.amazonaws.com/openclaw-tools:latest
docker push <account-id>.dkr.ecr.<region>.amazonaws.com/openclaw-tools:latest
```

### 2. Create ECS task definition

Key settings:
- **Image**: your ECR image URL
- **CPU**: 512 (0.5 vCPU)
- **Memory**: 1024 MB
- **Port mappings**: 18789
- **Environment variables**: `OPENCLAW_GATEWAY_TOKEN`, etc.
- **EFS volume**: Mount for persistent config data (replaces bind mounts)

### 3. Storage with EFS

Since Fargate containers are ephemeral, you need EFS for persistent data:

```bash
# Create an EFS filesystem
aws efs create-file-system --creation-token openclaw-data

# Mount it in your task definition at /home/node/.openclaw
```

### 4. Trade-offs

| | EC2 | ECS Fargate |
|---|---|---|
| Complexity | Low | Medium |
| Cost (1 agent) | ~$8/mo (t3.small) | ~$15/mo |
| Shell access | SSH anytime | `aws ecs execute-command` |
| Scaling | Manual | Auto |
| Maintenance | You patch the OS | AWS handles it |

---

## Approach C: Other Cloud Providers

### DigitalOcean Droplet

Essentially the same as EC2. $6/mo for 1GB RAM.

```bash
# Create a droplet, SSH in, then same steps as EC2
doctl compute droplet create openclaw \
  --image ubuntu-24-04-x64 \
  --size s-1vcpu-2gb \
  --region nyc1
```

### Hetzner (cheapest)

Great value for compute. ~$4/mo for 2 vCPU, 4GB RAM.

```bash
hcloud server create --name openclaw --type cx22 --image ubuntu-24.04
```

### Railway / Render / Fly.io

These platforms run Docker containers directly from a repo or image:

- **Railway**: Connect your GitHub repo, set env vars in dashboard, deploy
- **Fly.io**: `fly launch` with a `fly.toml` config, supports volumes for persistence
- **Render**: Docker deploy from registry, persistent disks available

---

## Persistent Data Strategy

The main challenge in cloud deployment is persisting your data across container restarts.

| Platform | Persistence method |
|---|---|
| EC2 / Droplet / Hetzner | Bind mounts to host disk (same as local) |
| ECS Fargate | EFS (Elastic File System) |
| Fly.io | Fly Volumes |
| Railway | Railway Volumes |
| Render | Persistent Disks |

Your config directory (`~/openclaw-docker/`) needs to survive container rebuilds. On a VM this is trivial (it's on the host). On serverless platforms you need a mounted volume.

---

## Multi-Agent Cloud Setup

To run both Coder and QA agents on the same VM, just copy both data directories and run both update scripts:

```bash
~/openclaw-docker/launch.sh        # Coder on :18789
~/openclaw-docker-qa/launch.sh     # QA on :18791
```

For separate VMs per agent, each VM gets one data directory and one update script.

---

## Estimated Costs

| Setup | Monthly cost |
|---|---|
| 1 agent on Hetzner CX22 | ~$4 |
| 1 agent on DigitalOcean | ~$6 |
| 1 agent on EC2 t3.small | ~$8 |
| 2 agents on EC2 t3.medium | ~$15 |
| 1 agent on ECS Fargate | ~$15 |

Note: These are compute costs only. Outbound data transfer and EFS/EBS storage are extra but typically negligible for this workload.

---

## Quick Start Recommendation

If you just want to get an agent running in the cloud quickly:

1. Spin up a **Hetzner CX22** or **DigitalOcean Droplet** ($4-6/mo)
2. SSH in, install Docker, clone the repo
3. `scp` your `~/openclaw-docker/` directory to the server
4. Run `~/openclaw-docker/launch.sh`
5. Use SSH tunneling for dashboard access

That's it. Same workflow as your Mac, just on a server.
