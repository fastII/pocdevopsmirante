	## INSTALL SONARQUBE ##

1 STEP

CRIAR OS APPLICATION, PROJECT E VALUES PARA O SONARQUBE

vim gitops/projects/platform-quality.yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: platform-quality
  namespace: argocd
spec:
  description: SonarQube Code Quality

  sourceRepos:
    - https://SonarSource.github.io/helm-chart-sonarqube
    - https://github.com/fastII/pocdevopsmirante.git

  destinations:
    - namespace: sonarqube
      server: https://kubernetes.default.svc

  clusterResourceWhitelist:
    - group: rbac.authorization.k8s.io
      kind: ClusterRole
    - group: rbac.authorization.k8s.io
      kind: ClusterRoleBinding

  namespaceResourceWhitelist:
    - group: "*"
      kind: "*"
######################################

vim gitops/helm-values/sonarqube.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: sonarqube
  namespace: argocd
spec:
  project: platform-quality

  sources:
    - repoURL: https://SonarSource.github.io/helm-chart-sonarqube
      chart: sonarqube
      targetRevision: "2025.5.0"
      helm:
        releaseName: sonarqube
        valueFiles:
          - $values/infra/gitops/helm-values/sonarqube.yaml

    - repoURL: https://github.com/fastII/pocdevopsmirante.git
      targetRevision: main
      ref: values

  destination:
    server: https://kubernetes.default.svc
    namespace: sonarqube

  syncPolicy:
    syncOptions:
      - CreateNamespace=true

########################################

vim gitops/helm-values/sonarqube.yaml
# SonarQube Community Edition
community:
  enabled: true

# PostgreSQL integrado ao Helm Chart
postgresql:
  enabled: true

  auth:
    username: sonar
    database: sonarqube
    existingSecret: sonarqube-postgresql
    secretKeys:
      adminPasswordKey: postgres-password
      userPasswordKey: password

  primary:
    persistence:
      enabled: true
      storageClass: standard
      accessModes:
        - ReadWriteOnce
      size: 10Gi

# Persistência do SonarQube
persistence:
  enabled: true
  storageClass: standard
  accessMode: ReadWriteOnce
  size: 10Gi

# Service
service:
  type: ClusterIP

# Acesso local 
ingress:
  enabled: true

# Recursos para ambiente de POC
resources:
  requests:
    cpu: 500m
    memory: 2Gi
  limits:
    cpu: "2"
    memory: 4Gi

2) VALIDAR O HELM COM A VERSAO

helm repo add sonarqube https://SonarSource.github.io/helm-chart-sonarqube
helm repo update
helm search repo sonarqube/sonarqube --versions

3) CRIACAO NAMESPACE
 
k create namespace sonarqube \
  --dry-run=client -o yaml | kubectl apply -f -

4) CRIACAO SECRETS

k create secret generic sonarqube-monitoring \
  -n sonarqube \
  --from-literal=monitoringPasscode=admin

k create secret generic sonarqube-postgresql \
  -n sonarqube \
  --from-literal=password=admin \
  --from-literal=postgres-password=admin \
  --dry-run=client -o yaml | kubectl apply -f -

5) VALIDACAO SONARQUBE

helm template sonarqube sonarqube/sonarqube \
  --version 2025.5.0 \
  -n sonarqube \
  -f gitops/helm-values/sonarqube.yaml \
  | yq -r 'select(.kind == "StatefulSet") | .metadata.name'

 helm template sonarqube sonarqube/sonarqube \
  --version 2025.5.0 \
  -n sonarqube \
  -f gitops/helm-values/sonarqube.yaml \
  | grep -E 'kind: (StatefulSet|Deployment)'
