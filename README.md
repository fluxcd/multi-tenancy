# fluxcd-multi-tenancy

This repository serves as a starting point for a multi-tenant cluster managed with Git, Flux and Kustomize.

I'm assuming that a multi-tenant cluster is shared by multiple teams. The cluster wide operations are performed by 
the cluster administrators while the namespace scoped operations are performed by various teams each with its own Git repository.
That means a team member, that's not a cluster admin, can't create namespaces, 
custom resources definitions or change something in another team namespace.

![Flux multi-tenancy](https://github.com/fluxcd/helm-operator-get-started/blob/master/diagrams/flux-multi-tenancy.png)

| Team      | Namespace   | Git Repository        | Flux RBAC
| --------- | ----------- | --------------------- | ---------------
| ADMIN     | all         | org/dev-cluster       | Cluster wide e.g. namespaces, cluster roles, CRDs, controllers
| DEV-TEAM1 | team1       | org/dev-team1         | Namespace scoped e.g. deployments, custom resources
| DEV-TEAM2 | team2       | org/dev-team2         | Namespace scoped e.g. ingress, services, network policies

First you'll have to create two git repositories:
* a clone of [fluxcd-multi-tenancy](https://github.com/stefanprodan/fluxcd-multi-tenancy) repository for the cluster admins, I will refer to it as `org/dev-cluster`
* a clone of [fluxcd-multi-tenancy-team1](https://github.com/stefanprodan/fluxcd-multi-tenancy-team1) repository for the dev team1, I will refer to it as `org/dev-team1`

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

### Install a Flux per namespace

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

**Note** that all Flux instances share the same Memcached server deployed at install time in `flux-system` namespace.

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

### Getting Help

If you have any questions about Flux and GitOps:


* Invite yourself to the [Weave community slack](https://slack.weave.works/)
  and join the [#flux](https://weave-community.slack.com/messages/flux/) channel.
* Join the [Weave User Group](https://www.meetup.com/pro/Weave/) and get invited to online talks,
  hands-on training and meetups in your area.
