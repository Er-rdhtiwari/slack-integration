# slack-integration

Kubernetes manifests for deploying `slack-integration` into the `slack-integration-dev` namespace.

## What is in `k8s/`

- `namespace.yaml`: creates the `slack-integration-dev` namespace
- `configmap.yaml`: provides non-secret app configuration
- `secret.yaml`: stores Slack webhook values
- `serviceaccount.yaml`: creates the pod service account
- `deployment.yaml`: runs the workload

## Current deployment behavior

The current Deployment is configured for cluster wiring tests, not for the real app image.

- Image: `busybox:1.36`
- Command: `sh -c "env && sleep 3600"`
- Purpose: verify the Deployment, ConfigMap, Secret, and ServiceAccount are wired correctly

This means the pod will start with a public image, print environment variables once, and then stay alive for inspection.

## Configuration

### ConfigMap

[`k8s/configmap.yaml`](/Users/radheshyam/Desktop/BSS/slack-integration/k8s/configmap.yaml) defines:

- `APP_ENV=dev`
- `LOG_LEVEL=debug`
- `RETRY_COUNT=3`

### Secret

[`k8s/secret.yaml`](/Users/radheshyam/Desktop/BSS/slack-integration/k8s/secret.yaml) defines:

- `SLACK_WEBHOOK_URL_PR`
- `SLACK_WEBHOOK_URL_CD`

Replace the placeholder webhook values before applying to a real environment.

## Apply commands

Validate manifests before applying:

```bash
kubectl apply --dry-run=client -f k8s/
```

Apply all manifests:

```bash
kubectl apply -f k8s/
```

Apply a single manifest when iterating:

```bash
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/secret.yaml
kubectl apply -f k8s/configmap.yaml
```

## Important inspection commands

```bash
kubectl get all -n slack-integration-dev
kubectl get secrets -n slack-integration-dev
kubectl get configmaps -n slack-integration-dev
kubectl get serviceaccounts -n slack-integration-dev
kubectl get deployments -n slack-integration-dev
kubectl get pods -n slack-integration-dev
kubectl describe deployment slack-notifier -n slack-integration-dev
kubectl describe pod -n slack-integration-dev <pod-name>
kubectl logs -n slack-integration-dev deploy/slack-notifier
kubectl rollout status deployment/slack-notifier -n slack-integration-dev
```

## Debugging steps

### 1. Validate the manifests

Run:

```bash
kubectl apply --dry-run=client -f k8s/
```

This catches common issues such as:

- wrong `apiVersion`
- wrong `kind` capitalization
- invalid YAML structure or indentation
- invalid enum values such as `imagePullPolicy`

### 2. Check whether resources were created

Run:

```bash
kubectl get all -n slack-integration-dev
```

If expected resources are missing, re-apply:

```bash
kubectl apply -f k8s/
```

### 3. If the Deployment is not ready

Run:

```bash
kubectl get deployments -n slack-integration-dev
kubectl get pods -n slack-integration-dev
kubectl rollout status deployment/slack-notifier -n slack-integration-dev
```

Common states:

- `0/1 READY`: pod is not healthy yet
- `CrashLoopBackOff`: container starts and exits repeatedly
- `ImagePullBackOff`: image cannot be pulled
- `Pending`: scheduling or resource problem

### 4. Inspect pod events

Run:

```bash
kubectl describe pod -n slack-integration-dev <pod-name>
```

Look at the `Events` section for the actual reason. This is usually the fastest way to diagnose Kubernetes startup problems.

### 5. Inspect container logs

Run:

```bash
kubectl logs -n slack-integration-dev deploy/slack-notifier
```

For the current `busybox` test container, this should print the injected environment variables and then keep the container alive.

### 6. Verify ConfigMap and Secret injection

Run:

```bash
kubectl logs -n slack-integration-dev deploy/slack-notifier
kubectl describe pod -n slack-integration-dev <pod-name>
```

Confirm these variables are present:

- `APP_ENV`
- `LOG_LEVEL`
- `RETRY_COUNT`
- `SLACK_WEBHOOK_URL_PR`
- `SLACK_WEBHOOK_URL_CD`

### 7. If you see `ImagePullBackOff`

That means Kubernetes cannot pull the configured image.

For the real app image, typical fixes are:

- build the image inside Minikube
- load the image into Minikube
- push the image to a registry and reference that registry path in the Deployment

The current manifest avoids this during basic testing by using `busybox:1.36`.

### 8. Re-run after manifest changes

Whenever you update a manifest:

```bash
kubectl apply -f k8s/
kubectl rollout status deployment/slack-notifier -n slack-integration-dev
```

## Cleanup

Delete the full stack:

```bash
kubectl delete -f k8s/
```

Delete only the Deployment:

```bash
kubectl delete -f k8s/deployment.yaml
```
