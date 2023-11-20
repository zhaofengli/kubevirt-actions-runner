# kubevirt-actions-runner

`kubevirt-actions-runner` is a runner image for [Actions Runner Controller (ARC)](https://github.com/actions/actions-runner-controller) that spawns ephemeral virtual machines for jobs using [KubeVirt](https://kubevirt.io).

## Use cases

- Windows and macOS jobs
- Jobs that require configuring system services
- Jobs that require stronger isolation

## Usage

You need a Kubernetes cluster with [Actions Runner Controller](https://github.com/actions/actions-runner-controller/blob/master/docs/quickstart.md) and [KubeVirt](https://kubevirt.io/quickstart_cloud) installed.

### 1. Create VirtualMachine template

First, we need to create a VirtualMachine to act as a template for the runner VMs.
`kubevirt-actions-runner` will create VirtualMachineInstances from it, and the VirtualMachine itself will never be started.

Create a namespace and apply the sample template:

```bash
kubectl create ns vm-runner-test
kubectl apply -f ./nixos-vm/vm-template.yaml
```

Let's take a deeper look at this sample VirtualMachine.
Inside we mount the `runner-info` volume:

```yaml
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: vm-template
  namespace: vm-runner-test
spec:
  runStrategy: Manual
  template:
    metadata:
      name: runner
    spec:
      domain:
        # Config abbreviated - See the following documentations:
        # - https://kubevirt.io/user-guide/virtual_machines/creating_vms
        # - https://github.com/kubevirt/kubevirt/blob/main/examples/vm-cirros.yaml

        devices:
          # You can also use `disk` as an alternative
          filesystems:
            - name: runner-info
              virtiofs: {}
```

This `runner-info` volume will be injected by `kubevirt-actions-runner`, containing `runner-info.json` that looks like the following:

```json
{
    "name":"runner-abcde-abcde",
    "token":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
    "url":"https://github.com/org/repo",
    "ephemeral":true,
    "groups":"",
    "labels":""
}
```

When making your own VM image, you need to mount the volume and configure the runner with it.
Once the runner exits, the VM must attempt to deregister the runner and automatically shut down.
You can see how the sample NixOS VM image implements this in `nixos-vm/arc-runner.nix`.

For manual testing, you can configure a `runner-info` volume that points to a ConfigMap and start the VirtualMachine manually.
`kubevirt-actions-runner` will replace the existing `runner-info` volume in the template if it exists.

### 2. Set up RBAC

The service account of the runner pod needs to be able to create `VirtualMachineInstance`s.
An example is as follows:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: kubevirt-actions-runner
  namespace: vm-runner-test
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: kubevirt-actions-runner
  namespace: vm-runner-test
rules:
  - apiGroups: ["kubevirt.io"]
    resources: ["virtualmachines"]
    verbs: ["get", "watch", "list"]
  - apiGroups: ["kubevirt.io"]
    resources: ["virtualmachineinstances"]
    verbs: ["get", "watch", "list", "create", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: kubevirt-actions-runner
  namespace: vm-runner-test
subjects:
  - kind: ServiceAccount
    name: kubevirt-actions-runner
    namespace: vm-runner-test
roleRef:
  kind: Role
  name: kubevirt-actions-runner
  apiGroup: rbac.authorization.k8s.io
```

### 3. Create runner scale set

You can configure the runner scale set using Helm.
Use the following `values.yaml`:

```yaml
githubConfigUrl: https://github.com/<your_enterprise/org/repo>
githubConfigSecret: ...
template:
  spec:
    serviceAccountName: kubevirt-actions-runner
    containers:
      - name: runner
        image: ghcr.io/zhaofengli/kubevirt-actions-runner:latest
        command: []
        env:
          - name: KUBEVIRT_VM_TEMPLATE
            value: vm-template
```

```bash
INSTALLATION_NAME="arc-runner-set"
NAMESPACE="vm-runner-test"
helm install "${INSTALLATION_NAME}" \
    --namespace "${NAMESPACE}" \
    --create-namespace \
    --values ./values.yaml \
    oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set
```

The lifecycle of the spawned VMI is bound to the runner pod.
If one of them exits, the other will be terminated as well.
