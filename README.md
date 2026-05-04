# slack-integration

Kubernetes and Tekton manifests for testing pull request webhook events in the `slack-integration-dev` namespace.

The current Tekton flow is:

```text
HTTP PR webhook request
-> Tekton EventListener
-> TriggerBinding extracts fields from JSON
-> TriggerTemplate creates PipelineRun
-> Pipeline prints PR information
```

Important: the current `.tekton/pr-pipeline.yaml` only prints PR details. It does not send a Slack notification yet. Slack notification requires adding a Slack step/task or calling the Go notifier service.

## Repository Layout

- `k8s/namespace.yaml`: creates `slack-integration-dev`
- `k8s/serviceaccount.yaml`: creates `slack-notifier-sa`
- `k8s/eventlistener-rbac.yaml`: grants Tekton EventListener permissions to `slack-notifier-sa`
- `k8s/configmap.yaml`: non-secret app config
- `k8s/secret.yaml`: Slack webhook secret placeholders
- `k8s/deployment.yaml`: test deployment for the Slack notifier app wiring
- `.tekton/pr-pipeline.yaml`: PR validation Pipeline
- `.tekton/pr-binding.yaml`: maps webhook JSON fields to Trigger params
- `.tekton/pr-trigger-template.yaml`: creates a PipelineRun
- `.tekton/pr-listener.yaml`: exposes the EventListener

## Prerequisites

- A working Kubernetes cluster.
- `kubectl` configured for the target cluster.
- Cluster-admin access, or equivalent permission to install CRDs and cluster RBAC.
- Kubernetes `1.28+` when using the latest Tekton release.

Check cluster access:

```bash
kubectl version
kubectl get nodes
```

## Install Tekton

Install Tekton Pipelines:

```bash
kubectl apply --filename https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml
```

Expected output includes CRDs such as:

```text
customresourcedefinition.apiextensions.k8s.io/pipelines.tekton.dev created
customresourcedefinition.apiextensions.k8s.io/pipelineruns.tekton.dev created
customresourcedefinition.apiextensions.k8s.io/tasks.tekton.dev created
customresourcedefinition.apiextensions.k8s.io/taskruns.tekton.dev created
deployment.apps/tekton-pipelines-controller created
deployment.apps/tekton-pipelines-webhook created
```

Warnings like these are usually not fatal:

```text
Warning: unrecognized format "int64"
Warning: unrecognized format "int32"
```

Verify Tekton Pipelines:

```bash
kubectl get pods --namespace tekton-pipelines --watch
kubectl api-resources --api-group=tekton.dev
```

Use the exact namespace `tekton-pipelines`. `tekton-pipeline` is wrong.

Install Tekton Triggers:

```bash
kubectl apply --filename https://storage.googleapis.com/tekton-releases/triggers/latest/release.yaml
kubectl apply --filename https://storage.googleapis.com/tekton-releases/triggers/latest/interceptors.yaml
```

Expected output includes:

```text
customresourcedefinition.apiextensions.k8s.io/eventlisteners.triggers.tekton.dev created
customresourcedefinition.apiextensions.k8s.io/triggerbindings.triggers.tekton.dev created
customresourcedefinition.apiextensions.k8s.io/triggertemplates.triggers.tekton.dev created
deployment.apps/tekton-triggers-controller created
deployment.apps/tekton-triggers-webhook created
clusterinterceptor.triggers.tekton.dev/github created
clusterinterceptor.triggers.tekton.dev/cel created
```

Verify Tekton Triggers:

```bash
kubectl get pods --namespace tekton-pipelines --watch
kubectl api-resources --api-group=triggers.tekton.dev
```

## Apply This Project

Apply the namespace and service account first:

```bash
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/serviceaccount.yaml
```

Apply EventListener RBAC:

```bash
kubectl apply -f k8s/eventlistener-rbac.yaml
```

This binds Tekton's built-in EventListener roles to `slack-notifier-sa`:

- `tekton-triggers-eventlistener-roles`: namespace-scoped access to EventListener, TriggerBinding, TriggerTemplate, Trigger, Interceptor, ConfigMap, Event, and PipelineRun creation.
- `tekton-triggers-eventlistener-clusterroles`: cluster-scoped access to ClusterTriggerBinding and ClusterInterceptor.

Apply the Tekton PR flow:

```bash
kubectl apply -f .tekton/pr-pipeline.yaml
kubectl apply -f .tekton/pr-binding.yaml
kubectl apply -f .tekton/pr-trigger-template.yaml
kubectl apply -f .tekton/pr-listener.yaml
```

Verify resources:

```bash
kubectl get pipeline -n slack-integration-dev
kubectl get triggerbinding -n slack-integration-dev
kubectl get triggertemplate -n slack-integration-dev
kubectl get eventlistener -n slack-integration-dev
kubectl get all -n slack-integration-dev
```

Healthy EventListener output:

```text
NAME          ADDRESS                                                              AVAILABLE   REASON                     READY
pr-listener   http://el-pr-listener.slack-integration-dev.svc.cluster.local:8080   True        MinimumReplicasAvailable   True
```

Healthy generated pod output:

```text
pod/el-pr-listener-...   1/1   Running   0
deployment.apps/el-pr-listener   1/1   1   1
```

## Test The Webhook Flow

Port-forward the EventListener service:

```bash
kubectl port-forward svc/el-pr-listener 8080:8080 -n slack-integration-dev
```

Expected output:

```text
Forwarding from 127.0.0.1:8080 -> 8080
Forwarding from [::1]:8080 -> 8080
```

If local port `8080` is already in use, use another local port:

```bash
kubectl port-forward svc/el-pr-listener 18080:8080 -n slack-integration-dev
```

Send a PR-style test payload:

```bash
curl -i -X POST http://127.0.0.1:18080/ \
  -H 'Content-Type: application/json' \
  -H 'X-GitHub-Event: pull_request' \
  -d '{
    "action": "opened",
    "repository": {
      "clone_url": "https://github.com/example/slack-integration.git",
      "full_name": "example/slack-integration"
    },
    "pull_request": {
      "number": 42,
      "head": {
        "sha": "abc123def456",
        "ref": "feature/test-pr"
      },
      "base": {
        "ref": "main"
      }
    },
    "sender": {
      "login": "rdh-tiwari"
    }
  }'
```

Postman should use:

- Method: `POST`
- URL: `http://127.0.0.1:8080/` or `http://127.0.0.1:18080/`
- Header: `Content-Type: application/json`
- Header: `X-GitHub-Event: pull_request`
- Body: raw JSON using the same shape as above

Successful EventListener response:

```json
{
  "eventListener": "pr-listener",
  "namespace": "slack-integration-dev",
  "eventListenerUID": "8fc19209-c9db-4aaa-98f9-cdaac1059be4",
  "eventID": "58ac45b1-c58c-47ee-bce3-2e3b4beda6f1"
}
```

This response only means the EventListener accepted the request. Always verify the PipelineRun.

## Verify Pipeline Execution

Check PipelineRuns and TaskRuns:

```bash
kubectl get pipelinerun -n slack-integration-dev --sort-by=.metadata.creationTimestamp
kubectl get taskrun -n slack-integration-dev --sort-by=.metadata.creationTimestamp
```

Successful output should include:

```text
NAME                      SUCCEEDED   REASON
pr-validation-run-dcqrx   True        Succeeded

NAME                                    SUCCEEDED   REASON
pr-validation-run-dcqrx-print-pr-info   True        Succeeded
```

Inspect task logs:

```bash
kubectl logs -n slack-integration-dev <taskrun-pod-name> --all-containers=true
```

Example:

```bash
kubectl logs -n slack-integration-dev pr-validation-run-dcqrx-print-pr-info-pod --all-containers=true
```

Expected log output:

```text
PR Event Received
Repo URL: https://github.com/example/slack-integration.git
PR Number: 42
Commit ID: abc123def456
Source Branch: feature/test-pr
Target Branch: main
Sender: rdh-tiwari
Action: opened
```

## Current End-To-End Test Result

The current implemented flow was tested successfully:

```text
HTTP/1.1 202 Accepted
eventID: 58ac45b1-c58c-47ee-bce3-2e3b4beda6f1

PipelineRun: pr-validation-run-dcqrx
PipelineRun status: True / Succeeded
TaskRun: pr-validation-run-dcqrx-print-pr-info
TaskRun status: True / Succeeded
```

Task logs showed all mapped PR fields, including `source-branch`.

## Slack Notification Status

If Postman returns success but Slack receives no message, check what the Pipeline actually does.

Current `.tekton/pr-pipeline.yaml` only prints PR fields. It does not:

- read `SLACK_WEBHOOK_URL_PR`
- call Slack with `curl`
- call the Go notifier service
- run the `slack-notifier` application

So no Slack message is expected from the current Tekton pipeline. To send Slack notifications, add a Slack notification step/task or call the deployed notifier service from the Pipeline.

Also replace placeholder webhook values in `k8s/secret.yaml` before testing real Slack delivery:

```yaml
SLACK_WEBHOOK_URL_PR: "https://hooks.slack.com/services/REPLACE/PRME"
SLACK_WEBHOOK_URL_CD: "https://hooks.slack.com/services/REPLACE/CDME"
```

## Troubleshooting

### Pipeline Kind Not Recognized

Error:

```text
no matches for kind "Pipeline" in version "tekton.dev/v1"
ensure CRDs are installed first
```

Cause: Tekton Pipelines CRDs are missing or incompatible.

Check:

```bash
kubectl api-resources --api-group=tekton.dev
```

Fix: install Tekton Pipelines.

### EventListener Kind Not Recognized

Error:

```text
no matches for kind "EventListener" in version "trigger.tekton.dev/v1beta1"
```

Cause: wrong API group. It must be `triggers.tekton.dev`, not `trigger.tekton.dev`.

Correct:

```yaml
apiVersion: triggers.tekton.dev/v1beta1
kind: EventListener
```

### EventListener Template Decode Error

Error:

```text
json: cannot unmarshal array into Go struct field EventListenerTrigger.spec.triggers.template
```

Cause: `template` was written as a list.

Wrong:

```yaml
template:
  - ref: pr-trigger-template
```

Correct:

```yaml
template:
  ref: pr-trigger-template
```

### Port-Forward Connection Refused

Error:

```text
socat ... connect(5, AF=2 127.0.0.1:8080, 16): Connection refused
error: lost connection to pod
```

Cause: the EventListener pod is not listening on port `8080`, usually because it is unhealthy or crashing.

Check:

```bash
kubectl get all -n slack-integration-dev
kubectl describe pod -n slack-integration-dev <el-pr-listener-pod-name>
kubectl logs -n slack-integration-dev <el-pr-listener-pod-name> --previous
kubectl get events -n slack-integration-dev --sort-by=.lastTimestamp
```

If logs show RBAC errors like this:

```text
User "system:serviceaccount:slack-integration-dev:slack-notifier-sa" cannot list resource "triggerbindings"
failed to start informers:failed to wait for cache at index 0 to sync
```

Fix:

```bash
kubectl apply -f k8s/serviceaccount.yaml
kubectl apply -f k8s/eventlistener-rbac.yaml
kubectl apply -f .tekton/pr-listener.yaml
kubectl rollout restart deployment/el-pr-listener -n slack-integration-dev
kubectl rollout status deployment/el-pr-listener -n slack-integration-dev
```

### ServiceAccount Not Found

Error in EventListener status:

```text
serviceaccount "slack-notifier-sa" not found
```

Cause: `.tekton/pr-listener.yaml` references `slack-notifier-sa`, but `k8s/serviceaccount.yaml` was not applied.

Fix:

```bash
kubectl apply -f k8s/serviceaccount.yaml
```

### PipelineRun ParameterMissing

Error:

```text
pipelineRun missing parameters: [source-branch]
```

Cause: the Pipeline requires a param that the TriggerTemplate did not pass into the generated PipelineRun.

Check:

```bash
kubectl describe pipelinerun <pipelinerun-name> -n slack-integration-dev
```

Fix: make sure `.tekton/pr-trigger-template.yaml` passes every required Pipeline param, including:

```yaml
- name: source-branch
  value: $(tt.params.source-branch)
```

### Empty Or Invalid Request Body

Error:

```text
Invalid event body format : unexpected end of JSON input
```

Cause: EventListener received an empty or invalid JSON body.

Fix: send valid JSON with `Content-Type: application/json`.

## Useful Commands

```bash
kubectl get all -n slack-integration-dev
kubectl get eventlistener -n slack-integration-dev
kubectl get pipeline -n slack-integration-dev
kubectl get pipelinerun -n slack-integration-dev
kubectl get taskrun -n slack-integration-dev
kubectl get events -n slack-integration-dev --sort-by=.lastTimestamp
```

Describe resources:

```bash
kubectl describe eventlistener pr-listener -n slack-integration-dev
kubectl describe deployment el-pr-listener -n slack-integration-dev
kubectl describe pipelinerun <pipelinerun-name> -n slack-integration-dev
kubectl describe taskrun <taskrun-name> -n slack-integration-dev
```

Logs:

```bash
kubectl logs -n slack-integration-dev <pod-name>
kubectl logs -n slack-integration-dev <pod-name> --previous
kubectl logs -n slack-integration-dev <taskrun-pod-name> --all-containers=true
```

## App Deployment

The current `k8s/deployment.yaml` is configured for cluster wiring tests, not the real app image:

- Image: `busybox:1.36`
- Command: `sh -c "env && sleep 3600"`
- Service account: `slack-notifier-sa`

Apply app support manifests:

```bash
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/secret.yaml
kubectl apply -f k8s/deployment.yaml
```

Inspect:

```bash
kubectl rollout status deployment/slack-notifier -n slack-integration-dev
kubectl logs -n slack-integration-dev deploy/slack-notifier
```

## Cleanup

Delete app support resources:

```bash
kubectl delete -f k8s/deployment.yaml
kubectl delete -f k8s/configmap.yaml
kubectl delete -f k8s/secret.yaml
```

Delete Tekton project resources:

```bash
kubectl delete -f .tekton/pr-listener.yaml
kubectl delete -f .tekton/pr-trigger-template.yaml
kubectl delete -f .tekton/pr-binding.yaml
kubectl delete -f .tekton/pr-pipeline.yaml
kubectl delete -f k8s/eventlistener-rbac.yaml
```
