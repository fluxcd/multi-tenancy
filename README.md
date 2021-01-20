# fluxcd-multi-tenancy

## We are moving to Flux v2

> ⚠️ Please note: In preparation of [Flux v2](https://toolkit.fluxcd.io/) GA this repository with Flux v1 examples has been archived. The Flux v2 equivalent of what is shown here can be found at [flux2-multi-tenancy](https://github.com/fluxcd/flux2-multi-tenancy).
>
> Thanks a lot for your interest.

## For posterity

This repository serves as a starting point for a multi-tenant cluster managed with Git, Flux and Kustomize.

I'm assuming that a multi-tenant cluster is shared by multiple teams. The cluster wide operations are performed by 
the cluster administrators while the namespace scoped operations are performed by various teams each with its own Git repository.
That means a team member, that's not a cluster admin, can't create namespaces, 
custom resources definitions or change something in another team namespace.

![Flux multi-tenancy](https://github.com/fluxcd/helm-operator-get-started/blob/master/diagrams/flux-multi-tenancy.png)

### Repositories

First you'll have to create two git repositories:

* a clone of [fluxcd-multi-tenancy](https://github.com/fluxcd/multi-tenancy) repository for the cluster admins, I will refer to it as `org/dev-cluster`
* a clone of [fluxcd-multi-tenancy-team1](https://github.com/fluxcd/multi-tenancy-team1) repository for the dev team1, I will refer to it as `org/dev-team1`

| Team      | Namespace   | Git Repository        | Flux RBAC
| --------- | ----------- | --------------------- | ---------------
| ADMIN     | all         | org/dev-cluster       | Cluster wide e.g. namespaces, CRDs, Flux controllers
| DEV-TEAM1 | team1       | org/dev-team1         | Namespace scoped e.g. deployments, custom resources
| DEV-TEAM2 | team2       | org/dev-team2         | Namespace scoped e.g. ingress, services, network policies

Cluster admin repository structure:

```
├── .flux.yaml 
├── base
│   ├── flux
│   └── memcached
├── cluster
│   ├── common
│   │   ├── crds.yaml
│   │   └── kustomization.yaml
│   └── team1
│       ├── flux-patch.yaml
│       ├── kubeconfig.yaml
│       ├── kustomization.yaml
│       ├── namespace.yaml
│       ├── psp.yaml
│       └── rbac.yaml
├── install
└── scripts
```

The `base` folder holds the deployment spec used for installing Flux in the `flux-system` namespace 
and in the teams namespaces. All Flux instances share the same Memcached server deployed at 
install time in `flux-system` namespace. 

With `.flux.yaml` we configure Flux to run Kustomize build on the cluster dir and deploy the generated manifests:

```yaml
version: 1
commandUpdated:
  generators:
    - command: kustomize build .
```

Development team1 repository structure:

```
├── .flux.yaml 
├── flux-patch.yaml
├── kustomization.yaml
└── workloads
    ├── frontend
    │   ├── deployment.yaml
    │   ├── kustomization.yaml
    │   └── service.yaml
    └── backend
        ├── deployment.yaml
        ├── kustomization.yaml
        └── service.yaml
```

The `workloads` folder contains the desired state of the `team1` namespace and the `flux-patch.yaml` contains the 
Flux annotations that define how the container images should be updated.

With `.flux.yaml` we configure Flux to run Kustomize build, apply the container update policies and deploy the generated manifests:

```yaml
version: 1
patchUpdated:
  generators:
    - command: kustomize build .
  patchFile: flux-patch.yaml
```

### Install the cluster admin Flux

In the dev-cluster repo, change the git URL to point to your fork:

```bash
vim ./install/flux-patch.yaml

--git-url=git@github.com:org/dev-cluster
```

Install the cluster wide Flux with kubectl kustomize:

```bash
kubectl apply -k ./install/
```

Get the public SSH key with:

```bash
fluxctl --k8s-fwd-ns=flux-system identity
```

Add the public key to the `github.com:org/dev-cluster` repository deploy keys with write access.

The cluster wide Flux will do the following:
* creates the cluster objects from `cluster/common` directory (CRDs, cluster roles, etc)
* creates the `team1` namespace and deploys a Flux instance with restricted access to that namespace

### Install a Flux per team

Change the dev team1 git URL:

```bash
vim ./cluster/team1/flux-patch.yaml

--git-url=git@github.com:org/dev-team1
```

When you commit your changes, the system Flux will configure the team1's Flux to sync with `org/dev-team1` repository.

Get the public SSH key for team1 with:

```bash
fluxctl --k8s-fwd-ns=team1 identity
```

Add the public key to the `github.com:org/dev-team1` deploy keys with write access. The team1's Flux
will apply the manifests from `org/dev-team1` repository only in the `team1` namespace, this is enforced with RBAC and role bindings.

If team1 needs to deploy a controller that depends on a CRD or a cluster role, they'll 
have to open a PR in the `org/dev-cluster`repository and add those cluster wide objects in the `cluster/common` directory.

The team1's Flux instance can be customised with different options than the system Flux using the `cluster/team1/flux-patch.yaml`. 

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: flux
spec:
  template:
    spec:
      containers:
        - name: flux
          args:
            - --manifest-generation=true
            - --memcached-hostname=flux-memcached.flux-system
            - --memcached-service=
            - --git-poll-interval=5m
            - --sync-interval=5m
            - --ssh-keygen-dir=/var/fluxd/keygen
            - --k8s-allow-namespace=team1
            - --git-url=git@github.com:org/dev-team1
            - --git-branch=master
``` 

The `k8s-allow-namespace` restricts Flux discovery mechanism to a single namespace.

### Install Flagger

[Flagger](https://docs.flagger.app) is a progressive delivery Kubernetes operator that can be used to automate Canary, A/B testing and Blue/Green deployments.

![Flux Flagger](https://github.com/fluxcd/helm-operator-get-started/blob/master/diagrams/flux-flagger.png)

You can deploy Flagger by including its manifests in the `cluster/kustomization.yaml` file:

```yaml
bases:
  - ./flagger/
  - ./common/
  - ./team1/
```

Commit the changes to git and wait for system Flux to install Flagger and Prometheus:

```bash
fluxctl --k8s-fwd-ns=flux-system sync

kubectl -n flagger-system get po
NAME                                  READY   STATUS
flagger-64c6945d5b-4zgvh              1/1     Running
flagger-prometheus-6f6b558b7c-22kw5   1/1     Running
```

A team member can now push canary objects to `org/dev-team1` repository and Flagger will automate the deployment process. 

Flagger can notify your teams when a canary deployment has been initialised, 
when a new revision has been detected and if the canary analysis failed or succeeded.

You can enable Slack notifications by editing the `cluster/flagger/flagger-patch.yaml` file:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: flagger
spec:
  template:
    spec:
      containers:
        - name: flagger
          args:
            - -mesh-provider=kubernetes
            - -metrics-server=http://flagger-prometheus:9090
            - -slack-user=flagger
            - -slack-channel=alerts
            - -slack-url=https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK
```

### Enforce pod security policies per team

With [pod security policies](https://kubernetes.io/docs/concepts/policy/pod-security-policy/)
a cluster admin can define a set of conditions that a pod must run with in order to be accepted into the system.

For example you can forbid a team from creating privileged containers or use the host network.

Edit the team1 pod security policy `cluster/team1/psp.yaml`:

```yaml
apiVersion: policy/v1beta1
kind: PodSecurityPolicy
metadata:
  name: default-psp-team1
  annotations:
    seccomp.security.alpha.kubernetes.io/allowedProfileNames: '*'
spec:
  privileged: false
  hostIPC: false
  hostNetwork: false
  hostPID: false
  allowPrivilegeEscalation: false
  allowedCapabilities:
    - '*'
  fsGroup:
    rule: RunAsAny
  runAsUser:
    rule: RunAsAny
  seLinux:
    rule: RunAsAny
  supplementalGroups:
    rule: RunAsAny
  volumes:
    - '*'
```

Set privileged, hostIPC, hostNetwork and hostPID to false and commit the change to git. From this moment on, team1 will 
not be able to run containers with an elevated security context under the default service account.

If a team member adds a privileged container definition in the `org/dev-team1` repository, Kubernetes will deny it:

```bash
kubectl -n team1 describe replicasets podinfo-5d7d9fc9d5

Error creating: pods "podinfo-5d7d9fc9d5-" is forbidden: unable to validate against any pod security policy:
[spec.containers[0].securityContext.privileged: Invalid value: true: Privileged containers are not allowed]
```

### Enforce custom policies per team

[Gatekeeper](https://github.com/open-policy-agent/gatekeeper)
is a validating webhook that enforces CRD-based policies executed by Open Policy Agent.

![Flux Gatekeeper](https://github.com/fluxcd/helm-operator-get-started/blob/master/diagrams/flux-open-policy-agent-gatekeeper.png)

You can deploy Gatekeeper by including its manifests in the `cluster/kustomization.yaml` file:

```yaml
bases:
  - ./gatekeeper/
  - ./flagger/
  - ./common/
  - ./team1/
```

Inside the gatekeeper dir there is a constraint template that instructs OPA to reject Kubernetes deployments if no 
container resources are specified.

Enable the constraint for team1 by editing the `cluster/gatekeeper/constraints.yaml` file:

```yaml
apiVersion: constraints.gatekeeper.sh/v1alpha1
kind: ContainerResources
metadata:
  name: containerresources
spec:
  match:
    namespaces:
      - team1
    kinds:
      - apiGroups: ["apps"]
        kinds: ["Deployment"]
```

Commit the changes to git and wait for system Flux to install Gatekeeper and apply the constraints:

```bash
fluxctl --k8s-fwd-ns=flux-system sync

watch kubectl -n gatekeeper-system get po
```

If a team member adds a deployment without CPU or memory resources in the `org/dev-team1` repository, Gatekeeper will deny it:

```bash
kubectl -n team1 logs deploy/flux

admission webhook "validation.gatekeeper.sh" denied the request: 
[denied by containerresources] container <podinfo> has no memory requests
[denied by containerresources] container <sidecar> has no memory limits
```

### Add a new team/namespace/repository

If you want to add another team to the cluster, first create a git repository as `github.com:org/dev-team2`.

Run the create team script:

```bash
./scripts/create-team.sh team2

team2 created at cluster/team2/
team2 added to cluster/kustomization.yaml
```

Change the git URL in `cluster/team2` dir:

```bash
vim ./cluster/team2/flux-patch.yaml

--git-url=git@github.com:org/dev-team2
```

Push the changes to the master branch of `org/dev-cluster` and sync with the cluster:

```bash
fluxctl --k8s-fwd-ns=flux-system sync
```

Get the team2 public SSH key with:
                                       
```bash
fluxctl --k8s-fwd-ns=team2 identity
```

Add the public key to the `github.com:org/dev-team2` repository deploy keys with write access. The team2's Flux
will apply the manifests from `org/dev-team2` repository only in the `team2` namespace.

### Isolate tenants

With this setup, Flux will prevent a team member from altering cluster level objects or other team's workloads. 

In order to harden the tenant isolation, a cluster admin should consider using:
* resource quotas (limit the compute resources that can be requested by a team)
* network policies (restrict cross namespace traffic)
* pod security policies (prevent running privileged containers or host network and filesystem usage)
* Open Policy Agent admission controller (enforce custom policies on Kubernetes objects)

### Getting Help

If you have any questions about Flux and GitOps:


- Invite yourself to the <a href="https://slack.cncf.io" target="_blank">CNCF community</a>
  slack and ask a question on the [#flux](https://cloud-native.slack.com/messages/flux/)
  channel.
- To be part of the conversation about Flux's development, join the
  [flux-dev mailing list](https://lists.cncf.io/g/cncf-flux-dev).
- Join the [Weave User Group](https://www.meetup.com/pro/Weave/) and get invited to online talks,
  hands-on training and meetups in your area.
