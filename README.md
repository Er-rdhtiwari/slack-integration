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

## Tekton pipeline

The `.tekton/` manifests define a Tekton pipeline for preparing sample Go source, validating event params, running tests, building the binary, and simulating a Slack notification.

### Tekton command reference

Use these commands from the repository root. If you are already inside `.tekton/`, remove the `.tekton/` prefix from manifest paths.

Install Tekton Pipelines CRDs and controllers:

```bash
kubectl apply -f https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml
```

Purpose: installs the `Task`, `TaskRun`, `Pipeline`, and `PipelineRun` resource types. Without this, Kubernetes returns `no matches for kind "Task" in version "tekton.dev/v1"`.

Check Tekton controller pods:

```bash
kubectl get pods -n tekton-pipelines
kubectl get pods -n tekton-pipelines -w
```

Purpose: confirms the Tekton controllers and webhook are running. Wait until all pods show `1/1 Running` before applying Tekton resources.

Verify Tekton API resources:

```bash
kubectl api-resources | grep tekton
```

Purpose: confirms the Tekton CRDs are registered with the cluster. You should see resources such as `tasks`, `taskruns`, `pipelines`, and `pipelineruns`.

Apply the Tekton namespace:

```bash
kubectl apply -f .tekton/namespace.yaml
```

Purpose: creates or updates the `slack-integration-dev` namespace used by the Tekton resources.

Apply all Tasks and the Pipeline:

```bash
kubectl apply -f .tekton/task-prepare-source.yaml
kubectl apply -f .tekton/task-validate-event.yaml
kubectl apply -f .tekton/task-go-test.yaml
kubectl apply -f .tekton/task-go-build.yaml
kubectl apply -f .tekton/task-slack-notify.yaml
kubectl apply -f .tekton/pipeline-slack-integration.yaml
```

Purpose: creates the reusable Tekton Tasks and the Pipeline that connects them.

Create a new PipelineRun:

```bash
kubectl create -f .tekton/pipelinerun-slack-integration.yaml
```

Purpose: starts a new pipeline execution. Use `kubectl create` for this file because it uses `metadata.generateName`, so each run gets a unique generated name.

List PipelineRuns:

```bash
kubectl get pipelinerun -n slack-integration-dev
```

Purpose: checks whether each pipeline is `Running`, `Succeeded`, or `Failed`.

List TaskRuns:

```bash
kubectl get taskrun -n slack-integration-dev
```

Purpose: shows which individual pipeline task is pending, running, succeeded, or failed.

List Tekton pods:

```bash
kubectl get pods -n slack-integration-dev
```

Purpose: checks the actual pods created by Tekton for each TaskRun. Useful statuses include `PodInitializing`, `Running`, `Completed`, `Error`, and `ImagePullBackOff`.

Stream PipelineRun logs with the Tekton CLI:

```bash
tkn pipelinerun logs -f -n slack-integration-dev
```

Purpose: interactively selects a PipelineRun and streams logs from its Tasks.

Stream logs for a specific PipelineRun with `kubectl`:

```bash
kubectl logs -n slack-integration-dev -l tekton.dev/pipelineRun=<pipelinerun-name> --all-containers=true
```

Purpose: prints logs from all pods for one PipelineRun. Replace `<pipelinerun-name>` with the actual run name, for example `slack-integration-run-pk5xm`. Do not include angle brackets in the real command.

Describe a failed PipelineRun:

```bash
kubectl describe pipelinerun -n slack-integration-dev <pipelinerun-name>
```

Purpose: shows failure reason, conditions, task status, and events for one PipelineRun.

Describe a failed TaskRun:

```bash
kubectl describe taskrun -n slack-integration-dev <taskrun-name>
```

Purpose: shows lower-level failure details for a specific Task, such as `run-tests`.

Describe a stuck or failed pod:

```bash
kubectl describe pod -n slack-integration-dev <pod-name>
```

Purpose: shows scheduling, image pull, volume mount, PVC, and container startup events.

Check PVCs created for PipelineRun workspaces:

```bash
kubectl get pvc -n slack-integration-dev
kubectl describe pvc -n slack-integration-dev <pvc-name>
```

Purpose: verifies workspace storage. The PipelineRun uses `volumeClaimTemplate` so files from `prepare-source`, such as `go.mod`, persist for later Tasks like `go-test` and `go-build`.

Delete old PipelineRuns:

```bash
kubectl delete pipelinerun -n slack-integration-dev <pipelinerun-name>
```

Purpose: cleans up old runs and their generated TaskRuns/pods.

Delete all PipelineRuns in the namespace:

```bash
kubectl delete pipelinerun -n slack-integration-dev --all
```

Purpose: resets the Tekton run history in the namespace before a fresh test.

If applying a Task fails with `no matches for kind "Task" in version "tekton.dev/v1"`, Tekton Pipelines is not installed or the CRDs are not ready yet. Install Tekton first, then wait for the `tekton-pipelines` pods before applying the Task manifests.

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
