apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: argocd
resources:
  # change to specific release once release 2.3 is merged
  #- https://raw.githubusercontent.com/codefresh-io/argo-cd/c143423592f517911b6e626d12022a5742992f39/manifests/ha/install.yaml
  - https://raw.githubusercontent.com/codefresh-io/argo-cd/release-2.3/manifests/ha/install.yaml
  - default-rbac.yaml
  - pdb.yaml
images:
  - name: quay.io/codefresh/argocd
    newTag: v2.3.4-cap-CR-12256-fix-res-cache-key
  - name: quay.io/codefresh/applicationset
    newTag: v0.4.2

configMapGenerator:
  - behavior: merge
    name: argocd-cm
    literals:
      - timeout.reconciliation=20s
      - accounts.admin=apiKey,login
  - behavior: merge
    name: argocd-cmd-params-cm
    literals:
      - server.insecure=true

# reset the crbs to `subject.namespace: default`, so that argo-cd will later change them to the actual ns
patches:

  - target:
      group: rbac.authorization.k8s.io
      kind: ClusterRoleBinding
      version: v1
    patch: |-
      - op: replace
        path: /subjects/0/namespace
        value: default
  - target:
      version: v1
      kind: Service
      name: argocd-server
    patch: |
      - op: add
        path: /spec/ports/0/appProtocol
        value: grpc
      - op: add
        path: /spec/ports/1/appProtocol
        value: grpc
# Set high availability for application controller
  - target:
      group: apps
      version:  v1
      kind: StatefulSet
      name: argocd-application-controller
    patch: |-
      - op: replace
        path: /spec/replicas
        value: 2
      - op: add
        path: /spec/template/spec/containers/0/env/-
        value:
          name: ARGOCD_CONTROLLER_REPLICAS
          value: "2"