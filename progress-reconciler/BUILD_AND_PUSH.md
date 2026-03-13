# Building and Pushing Progress Reconciler to GitHub Container Registry

## Prerequisites

1. **GitHub Personal Access Token (PAT)**
   - Go to GitHub Settings → Developer settings → Personal access tokens → Tokens (classic)
   - Generate new token with `write:packages` and `read:packages` scopes
   - Save the token securely

2. **Docker Login to GitHub Container Registry**
   ```bash
   echo "YOUR_GITHUB_TOKEN" | docker login ghcr.io -u YOUR_GITHUB_USERNAME --password-stdin
   ```

## Build and Push Commands

### Option 1: Single Platform Build (faster)
```bash
# Navigate to the progress-reconciler directory
cd /path-to-the-repo/banaglore-workshop/progress-reconciler

# Build for linux/amd64 and push
docker buildx build --platform linux/amd64 \
    -t ghcr.io/YOUR_GITHUB_USERNAME/progress-reconciler:latest \
    -t ghcr.io/YOUR_GITHUB_USERNAME/progress-reconciler:v$(date +%Y%m%d-%H%M%S) \
    --push .
```

### Option 2: Multi-Platform Build (supports multiple architectures)
```bash
# Create a builder instance (one-time setup)
docker buildx create --name multiarch --use

# Build for multiple platforms and push
docker buildx build --platform linux/amd64,linux/arm64 \
    -t ghcr.io/YOUR_GITHUB_USERNAME/progress-reconciler:latest \
    -t ghcr.io/YOUR_GITHUB_USERNAME/progress-reconciler:v$(date +%Y%m%d-%H%M%S) \
    --push .
```

### Option 3: Build with Specific Version Tag
```bash
# Set your version
VERSION="v1.0.0"

docker buildx build --platform linux/amd64 \
    -t ghcr.io/YOUR_GITHUB_USERNAME/progress-reconciler:latest \
    -t ghcr.io/YOUR_GITHUB_USERNAME/progress-reconciler:${VERSION} \
    --push .
```

## Example with Actual Username

Replace `YOUR_GITHUB_USERNAME` with your actual GitHub username (e.g., if your username is `narunas`):

```bash
# Login
echo "ghp_your_token_here" | docker login ghcr.io -u narunas --password-stdin

# Build and push
docker buildx build --platform linux/amd64 \
    -t ghcr.io/narunas-k/progress-reconciler:latest \
    -t ghcr.io/narunas-k/progress-reconciler:v$(date +%Y%m%d-%H%M%S) \
    --push .
```

## Update Kubernetes Deployment

After pushing to GitHub Container Registry, update the deployment:

```bash
# Update the image in the deployment
kubectl set image deployment/progress-reconciler \
    progress-reconciler=ghcr.io/YOUR_GITHUB_USERNAME/progress-reconciler:latest \
    -n progress-reconciler

# Or edit the manifest and apply
kubectl apply -f manifests/deployment.yaml
```

## Make Image Public (Optional)

By default, packages are private. To make it public:
1. Go to https://github.com/users/YOUR_GITHUB_USERNAME/packages/container/progress-reconciler/settings
2. Scroll to "Danger Zone"
3. Click "Change visibility" → "Public"

## Troubleshooting

### Authentication Issues
```bash
# Verify login
docker logout ghcr.io
echo "YOUR_TOKEN" | docker login ghcr.io -u YOUR_USERNAME --password-stdin
```

### Builder Issues
```bash
# Remove and recreate builder
docker buildx rm multiarch
docker buildx create --name multiarch --use
```

### View Built Images
```bash
# List images
docker images | grep progress-reconciler

# Inspect remote image
docker buildx imagetools inspect ghcr.io/YOUR_GITHUB_USERNAME/progress-reconciler:latest
```