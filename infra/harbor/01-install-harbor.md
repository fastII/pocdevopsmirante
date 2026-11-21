## INSTALL HARBOR ##

helm repo add harbor https://helm.goharbor.io
helm repo update
helm search repo harbor/harbor --versions | head


1) k create namespace harbor

2) k -n harbor create secret generic harbor-admin \
  --from-literal=HARBOR_ADMIN_PASSWORD='admin' \
  --dry-run=client -o yaml | k apply -f -


3) CRIAR OS APPLICATION, PROJECT E VALUES PARA O TRAEFIK


apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: platform-registry
  namespace: argocd
spec:
  description: Harbor Container Registry

  sourceRepos:
    - https://helm.goharbor.io
    - https://github.com/fastII/pocdevopsmirante.git

  destinations:
    - namespace: harbor
      server: https://kubernetes.default.svc

  namespaceResourceWhitelist:
    - group: "*"
      kind: "*"


apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: harbor
  namespace: argocd
spec:
  project: platform-registry

  sources:
    - repoURL: https://helm.goharbor.io
      chart: harbor
      targetRevision: "1.19.4"
      helm:
        releaseName: harbor
        valueFiles:
          - $values/infra/gitops/helm-values/harbor.yaml

    - repoURL: https://github.com/fastII/pocdevopsmirante.git
      targetRevision: main
      ref: values

  destination:
    server: https://kubernetes.default.svc
    namespace: harbor

  syncPolicy:
    syncOptions:
      - CreateNamespace=true


3) VALUES.YAML

database:
  type: internal
  internal:
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 768Mi
expose:
  type: clusterIP
  tls:
    enabled: false
  clusterIP:
    name: harbor
    ports:
      httpPort: 80
externalURL: https://harbor.local
existingSecretAdminPassword: harbor-admin
existingSecretAdminPasswordKey: HARBOR_ADMIN_PASSWORD
persistence:
  enabled: true
  persistentVolumeClaim:
    database:
      size: 2Gi
    jobservice:
      jobLog:
        size: 1Gi
    redis:
      size: 1Gi
    registry:
      size: 10Gi
    trivy:
      size: 2Gi
redis:
  type: internal
  internal:
    resources:
      requests:
        cpu: 50m
        memory: 64Mi
      limits:
        cpu: 250m
        memory: 256Mi
trivy:
  enabled: true
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 1000m
      memory: 1Gi
portal:
  resources:
    requests:
      cpu: 50m
      memory: 64Mi
    limits:
      cpu: 250m
      memory: 256Mi
core:
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 768Mi
jobservice:
  resources:
    requests:
      cpu: 50m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 512Mi
registry:
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 512Mi
exporter:
  resources:
    requests:
      cpu: 25m
      memory: 64Mi
    limits:
      cpu: 200m
      memory: 128Mi
