# Building and Pushing Progress Reconciler

## Automated Builds (CI/CD)

Images are built and pushed automatically via GitHub Actions on every push to `main` that changes files under `progress-reconciler/`.

- **Registry:** `ghcr.io/castai/k8s-ai-workshop/progress-reconciler`
- **Tags:** `latest` + `sha-<short-commit-hash>`
- **Workflow:** `.github/workflows/progress-reconciler.yml`

No manual steps are needed for normal development — just merge to main.

---

## Manual Build and Push (emergency / local testing)

### Prerequisites

1. **GitHub Personal Access Token (PAT)**
   - Go to GitHub Settings > Developer settings > Personal access tokens > Tokens (classic)
   - Generate new token with `write:packages` and `read:packages` scopes

2. **Docker Login to GitHub Container Registry**
   ```bash
   echo "YOUR_GITHUB_TOKEN" | docker login ghcr.io -u YOUR_GITHUB_USERNAME --password-stdin
   ```

### Build and Push

```bash
cd progress-reconciler

# Build and push
docker buildx build --platform linux/amd64 \
    -t ghcr.io/castai/k8s-ai-workshop/progress-reconciler:latest \
    -t ghcr.io/castai/k8s-ai-workshop/progress-reconciler:v$(date +%Y%m%d-%H%M%S) \
    --push .
```

### Update Kubernetes Deployment

```bash
kubectl set image deployment/progress-reconciler \
    reconciler=ghcr.io/castai/k8s-ai-workshop/progress-reconciler:latest \
    -n progress-reconciler
```

## Troubleshooting

### Authentication Issues
```bash
docker logout ghcr.io
echo "YOUR_TOKEN" | docker login ghcr.io -u YOUR_USERNAME --password-stdin
```

### Builder Issues
```bash
docker buildx rm multiarch
docker buildx create --name multiarch --use
```
