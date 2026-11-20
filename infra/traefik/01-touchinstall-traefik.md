helm repo add traefik https://traefik.github.io/charts
helm repo update
kubectl create namespace traefik


1) Generate a self‑signed certificate valid for *.local
openssl req -x509 \
  -nodes \
  -days 365 \
  -newkey rsa:2048 \
  -keyout certs/local.key \
  -out certs/local.crt \
  -subj "/CN=*.local" \
  -addext "subjectAltName=DNS:*.local"

2) Create the TLS secret in the traefik namespace
kubectl create secret tls local-selfsigned-tls \
  --cert=tls.crt --key=tls.key \
  --namespace traefik

3) CRIAR OS APPLICATION, PROJECT E VALUES PARA O TRAEFIK


apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: traefik
  namespace: argocd
spec:
  project: platform-networking

  sources:
    - repoURL: https://traefik.github.io/charts
      chart: traefik
      targetRevision: "42.4.1"
      helm:
        releaseName: traefik
        valueFiles:
          - $values/infra/gitops/helm-values/traefik.yaml

    - repoURL: https://github.com/fastII/pocdevopsmirante.git
      targetRevision: main
      ref: values

  destination:
    server: https://kubernetes.default.svc
    namespace: traefik

  syncPolicy:
    syncOptions:
      - CreateNamespace=true


apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: platform-networking
  namespace: argocd
spec:
  description: Traefik Gateway API

  sourceRepos:
    - https://traefik.github.io/charts
    - https://github.com/fastII/pocdevopsmirante.git

  destinations:
    - namespace: traefik
      server: https://kubernetes.default.svc

  clusterResourceWhitelist:
    - group: gateway.networking.k8s.io
      kind: GatewayClass

  namespaceResourceWhitelist:
    - group: "*"
      kind: "*"

3) VALUES

accessLog:
  enabled: true
api:
  dashboard: true
  insecure: false
gateway:
  listeners:
    web:
      namespacePolicy:
        from: All
      port: 80
      protocol: HTTP
    websecure:
      certificateRefs:
      - group: ''
        kind: Secret
        name: local-selfsigned-tls
      mode: Terminate
      namespacePolicy:
        from: All
      port: 443
      protocol: HTTPS
  enabled: true
ingressClass:
  enabled: false
ingressRoute:
  dashboard:
    enabled: false
    entryPoints:
    - websecure
    matchRule: Host(`dashboard.docker.localhost`)
    middlewares:
    - name: dashboard-auth
log:
  level: INFO
metrics:
  prometheus:
    enabled: true
ports:
  web:
    http:
      redirections:
        entryPoint:
          permanent: true
          scheme: https
          to: websecure
    nodePort: 30000
    port: 80
  websecure:
    nodePort: 30001
    port: 443
providers:
  kubernetesGateway:
    enabled: true
    experimentalChannel: false
  kubernetesIngress:
    enabled: false
gatewayClass:
  enabled: true
  name: traefik
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 512Mi

4) ERRO TRAEFIK

K get crd | grep gateway.networking.k8s.io
backendtlspolicies.gateway.networking.k8s.io   Namespaced   v1(storage)           2026-11-19T21:27:18Z
gatewayclasses.gateway.networking.k8s.io       Cluster      v1(storage),v1beta1   2026-11-19T21:27:18Z
gateways.gateway.networking.k8s.io             Namespaced   v1(storage),v1beta1   2026-11-19T21:27:19Z
grpcroutes.gateway.networking.k8s.io           Namespaced   v1(storage)           2026-11-19T21:27:19Z
httproutes.gateway.networking.k8s.io           Namespaced   v1(storage),v1beta1   2026-11-19T21:27:19Z
referencegrants.gateway.networking.k8s.io      Namespaced   v1beta1(storage)      2026-11-19T21:27:19Z

parametro no values
experimentalChannel: false

5) ERRO NO CRD GATEWAY
CORRECAO TIVE QUE FAZER BACKUP DOS CRD'S HTTPROUTE E RODAR O YAML 

BACKUP DOS CRD'S

 helm-values % kubectl get $(kubectl get crd -o name | grep 'gateway.networking.k8s.io') \
  -o yaml > gateway-api-crds-backup.yaml

  kubectl apply --server-side \
  -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.1/experimental-install.yaml


  ## EXPOR O TRAEFIK COMO LOADBALANCE PARA ACESSO EXTERNO ##

  2. Por que não utilizar minikube tunnel?
O comando:
minikube tunnel


Tem como objetivo disponibilizar Services do tipo LoadBalancer, criando os encaminhamentos e as rotas necessárias para acessá-los a partir do host.

No seu ambiente, ele anunciou:
EXTERNAL-IP: 127.0.0.1


Entretanto, o Traefik utiliza as portas 80 e 443, que são privilegiadas no macOS.

O próprio Minikube informou:
The service/ingress traefik requires privileged ports
to be exposed: [80 443]
sudo permission will be asked for it.


Como seu usuário corporativo não pertence ao grupo autorizado para sudo, o túnel não conseguiu disponibilizar essas portas.

Consequência: o Gateway anunciava 127.0.0.1, mas as conexões para https://127.0.0.1:443 falhavam.
3. Encerrar o túnel anterior
Se o minikube tunnel estiver aberto em outro terminal, encerre-o com Ctrl+C.

Verifique:
ps aux | grep '[m]inikube tunnel'


Se não retornar processos, o túnel foi encerrado.

Não é necessário remover o Service LoadBalancer, modificar o Helm ou alterar o Gateway.
4. Expor o Traefik utilizando minikube service
Execute:
minikube service traefik -n traefik --url


Exemplo de saída do seu ambiente:
http://127.0.0.1:62902
http://127.0.0.1:62905

https://harbor.localhost:62905
https://argocd.localhost:62905
https://sonarqube.localhost:62905