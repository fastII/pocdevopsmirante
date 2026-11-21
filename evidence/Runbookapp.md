POC DevOps Mirante — Aplicação Node.js com Helm
Guia de criação, validação, empacotamento, instalação e testes do chart pocapp no Minikube. O código Node.js fica em app/ e o chart em helm/pocapp/.
Importante: no repositório existente, helm/pocapp já foi criado. Não execute helm create novamente sobre essa pasta: o comando aparece abaixo para documentar a criação do projeto do zero. Para o ambiente atual, comece na seção 3. Validar o chart existente.

1. Pré-requisitos e estrutura
helm version
kubectl version --client
minikube status
docker version
node --version
Estrutura esperada:
pocdevopsmirante/
├── app/
│   ├── Dockerfile
│   ├── .dockerignore
│   ├── package.json
│   └── src/server.js
└── helm/
    └── pocapp/
        ├── Chart.yaml
        ├── values.yaml
        ├── .helmignore
        └── templates/
            ├── _helpers.tpl
            ├── deployment.yaml
            ├── service.yaml
            ├── serviceaccount.yaml
            ├── httproute.yaml
            ├── ingress.yaml
            ├── hpa.yaml
            └── tests/test-connection.yaml
2. Criar um chart do zero (somente referência)
Na raiz do repositório, apenas se helm/pocapp ainda não existir:
mkdir -p helm
helm create helm/pocapp
helm show chart ./helm/pocapp
helm show values ./helm/pocapp
find helm/pocapp -maxdepth 3 -type f | sort
O helm create gera os templates iniciais e as chaves padrão do values.yaml, incluindo serviceAccount e autoscaling. Preserve essas chaves ao adaptar o chart; removê-las pode causar erros nil pointer no helm lint.

Comandos relacionados a build:
# Baixa/prepara dependências declaradas em Chart.yaml, caso existam.
helm dependency build ./helm/pocapp

# Gera o arquivo .tgz do chart.
mkdir -p dist
helm package ./helm/pocapp --destination ./dist

# Examina o conteúdo do pacote.
tar -tzf ./dist/pocapp-*.tgz | head -40
Não existe helm build no Helm CLI padrão. Para construir a imagem da aplicação, use Docker ou minikube image build. Para empacotar o chart, use helm package.

3. Validar o chart existente
Na raiz de pocdevopsmirante:
helm lint ./helm/pocapp
helm lint ./helm/pocapp --strict

# Renderiza tudo localmente, sem instalar no cluster.
helm template pocapp ./helm/pocapp --namespace apps --debug

# Salva os manifests renderizados para inspeção.
mkdir -p dist
helm template pocapp ./helm/pocapp --namespace apps > dist/pocapp-rendered.yaml

# Verifica recursos individuais.
helm template pocapp ./helm/pocapp -n apps --show-only templates/deployment.yaml
helm template pocapp ./helm/pocapp -n apps --show-only templates/service.yaml
helm template pocapp ./helm/pocapp -n apps --show-only templates/httproute.yaml
--show-only templates/httproute.yaml requer httpRoute.enabled: true no values.yaml. O aviso Chart.yaml: icon is recommended não impede o deploy.

Verifique no YAML renderizado:
- Imagem healthz-api:1.0.0 para o teste local.
- Container escutando na porta 3000.
- Service expondo a porta 80 e encaminhando à porta nomeada http (container 3000).
- readinessProbe e livenessProbe em /healthz.
- HTTPRoute com hostname healthz.localhost e parentRefs para traefik-gateway, namespace traefik, listener websecure.
Valores essenciais para a aplicação
Não substitua o values.yaml inteiro: mantenha as seções originais do helm create. Ajuste as chaves abaixo, compatíveis com os templates padrão, e acrescente service.targetPort se o Deployment foi adaptado para usá-la:
replicaCount: 1

image:
  repository: healthz-api
  pullPolicy: IfNotPresent
  tag: "1.0.0"

service:
  type: ClusterIP
  port: 80
  targetPort: 3000

serviceAccount:
  create: true
  automount: true
  annotations: {}
  name: ""

autoscaling:
  enabled: false
  minReplicas: 1
  maxReplicas: 3
  targetCPUUtilizationPercentage: 80

resources:
  requests:
    cpu: 25m
    memory: 32Mi
  limits:
    cpu: 100m
    memory: 128Mi

livenessProbe:
  httpGet:
    path: /healthz
    port: http
  initialDelaySeconds: 5
  periodSeconds: 10

readinessProbe:
  httpGet:
    path: /healthz
    port: http
  initialDelaySeconds: 2
  periodSeconds: 5

ingress:
  enabled: false

httpRoute:
  enabled: true
  annotations: {}
  parentRefs:
    - name: traefik-gateway
      namespace: traefik
      sectionName: websecure
  hostnames:
    - healthz.localhost
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
No templates/deployment.yaml, confirme que a porta do container usa containerPort: {{ .Values.service.targetPort }} e name: http. O templates/service.yaml padrão usa targetPort: http, o que é compatível.
4. Testar a API Node.js localmente
O app/src/server.js existente expõe GET /healthz na porta 3000.
cd app
npm start
Em outro terminal:
curl -i http://127.0.0.1:3000/healthz
Resultado esperado: HTTP/1.1 200 OK e JSON com status: healthy. Um caminho inexistente deve retornar 404:
curl -i http://127.0.0.1:3000/nao-existe
5. Build da imagem Docker no Minikube
Na raiz do repositório:
minikube status
minikube image build -t healthz-api:1.0.0 ./app
minikube image ls | grep healthz-api
Para esse teste local, image.repository: healthz-api, image.tag: "1.0.0" e image.pullPolicy: IfNotPresent devem corresponder à imagem construída.

Observação: a imagem construída dentro do Minikube não é automaticamente publicada no Harbor. O fluxo de CI/CD publicará uma imagem com endereço completo do registry e o values.yaml deverá apontar para ela.
6. Simular a instalação sem alterar o cluster
helm install pocapp ./helm/pocapp \
  --namespace apps \
  --create-namespace \
  --dry-run=client \
  --debug
7. Instalar ou atualizar com Helm (teste manual isolado)
Atenção ao GitOps: use esta etapa apenas enquanto o Argo CD não estiver gerenciando os mesmos recursos. Quando a Application pocapp estiver sob Argo CD, faça deploy exclusivamente pelo GitOps para evitar conflitos de ownership e reconciliação.

helm upgrade --install pocapp ./helm/pocapp \
  --namespace apps \
  --create-namespace \
  --wait \
  --timeout 180s
Consultar o release e os objetos:
helm list -n apps
helm status pocapp -n apps
helm get values pocapp -n apps
helm get manifest pocapp -n apps
kubectl get deployments,pods,services -n apps
kubectl get httproute -n apps
kubectl rollout status deployment/pocapp -n apps
O nome real do Deployment pode ser diferente se houver fullnameOverride ou ajustes no _helpers.tpl. Consulte kubectl get deployment -n apps antes de usar o nome no rollout.

8. Testar o endpoint no Kubernetes
Via Service / port-forward
kubectl get svc -n apps
kubectl port-forward -n apps svc/pocapp 3000:80
Em outro terminal:
curl -i http://127.0.0.1:3000/healthz
Via Traefik e Gateway API
kubectl get gateway -n traefik
kubectl get httproute -n apps
kubectl describe httproute -n apps
minikube service traefik -n traefik --url

## CRIAR FLUXO PARA O ARGOCD DA APP ##

GitOps com Argo CD — AppProject e Application
Esta POC utiliza o repositório https://github.com/fastII/pocdevopsmirante.git, branch main, com o chart em helm/pocapp. Os manifestos abaixo seguem a organização já utilizada no repositório:
infra/gitops/
├── projects/
│   └── pocapp.yaml                 # conteúdo de project.yaml
└── applications/
    └── pocapp.yaml                 # conteúdo de application.yaml
Arquivos entregues junto deste README: project.yaml (AppProject) e application.yaml (Application). Copie-os para os caminhos acima; os nomes dos arquivos não interferem no nome dos recursos. O AppProject permite recursos somente no namespace apps e somente a partir do repositório informado.

12.1 Criar namespace da aplicação
kubectl create namespace apps --dry-run=client -o yaml | kubectl apply -f -
O namespace é criado separadamente para não exigir permissão de criação de recursos cluster-scoped no AppProject. Confirme que o Argo CD possui RBAC para gerenciar recursos em apps.
12.2 Criar o AppProject
Arquivo infra/gitops/projects/pocapp.yaml:
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: pocapp
  namespace: argocd
spec:
  description: Aplicacao Node.js pocapp - POC DevOps Mirante
  sourceRepos:
    - https://github.com/fastII/pocdevopsmirante.git
  destinations:
    - server: https://kubernetes.default.svc
      namespace: apps
  namespaceResourceWhitelist:
    - group: '*'
      kind: '*'
Aplicar e verificar:
k apply -f infra/gitops/projects/pocapp.yaml
k get appproject pocapp -n argocd
12.3 Criar a Application
Arquivo infra/gitops/applications/pocapp.yaml:
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: pocapp
  namespace: argocd
spec:
  project: pocapp
  source:
    repoURL: https://github.com/fastII/pocdevopsmirante.git
    targetRevision: main
    path: helm/pocapp
    helm:
      releaseName: pocapp
  destination:
    server: https://kubernetes.default.svc
    namespace: apps
  syncPolicy:
    syncOptions:
      - CreateNamespace=false
Aplicar e verificar:
k apply -f infra/gitops/applications/pocapp.yaml
k  get applications.argoproj.io pocapp -n argocd
k describe applications.argoproj.io pocapp -n argocd
A Application não tem automated inicialmente: o primeiro sync é manual para permitir conferir os recursos antes do deploy.
12.4 Publicar o chart no Git
O Argo CD renderiza o chart a partir do Git, não do diretório local. Antes do sync, faça commit/push dos arquivos necessários:
git status --short
helm lint ./helm/pocapp
helm template pocapp ./helm/pocapp -n apps > /tmp/pocapp-rendered.yaml
git add helm/pocapp infra/gitops/projects/pocapp.yaml infra/gitops/applications/pocapp.yaml
git commit -m "feat: add pocapp Helm chart and Argo CD GitOps"
git push origin main
Se a branch main for protegida, faça o commit em uma branch de feature e abra PR, seguindo as regras do repositório.