# Runbook de provisionamento da POC DevOps Mirante

Execute os comandos a partir da raiz do repositório, salvo quando o guia indicar outro diretório. A referência da POC é um cluster Minikube de nó único no macOS, com Docker Desktop, runtime containerd e Kubernetes v1.37.0.

## Arquitetura

~~~mermaid
flowchart LR
    Dev[GitHub Actions] --> ARC[ARC no Minikube]
    ARC --> Sonar[SonarQube]
    Dev --> Harbor[Harbor]
    Dev --> Git[Git main e Helm values]
    Git --> Argo[Argo CD]
    Argo --> Apps[Workloads no Minikube]
    Harbor --> Apps
    Kyverno[Kyverno] --> Apps
    Cliente[Cliente HTTPS] --> Traefik[Traefik Gateway]
    Traefik --> Apps
    Apps --> Obs[Prometheus e Alloy]
    Obs --> Grafana[Grafana e Loki]
~~~

## 1. Preparar o host e iniciar o cluster

1. Instale Git, Minikube, Docker Desktop, kubectl, Helm e OpenSSL. A CLI do Argo CD facilita os syncs abaixo.
2. Inicie o Docker Desktop. Confira a memória e as CPUs que a VM realmente disponibiliza. Em um Mac de 16 GiB, comece com 8 GiB no Docker Desktop e valide a pressão no macOS. A auditoria encontrou 9,67 GiB na VM e um teto separado de 8 GiB no contêiner do Minikube. Se a stack completa precisar rodar com builds, avalie cerca de 10 GiB na VM conforme o uso do Mac. [Configurações do Docker Desktop](https://docs.docker.com/desktop/settings-and-maintenance/settings/)
3. Para um perfil novo dedicado à POC, deixe o Docker Desktop definir o teto compartilhado. As opções `no-limit` evitam adicionar outro teto ao contêiner. Em um perfil existente, confira os limites efetivos após qualquer alteração e preserve os volumes antes de considerar recriação. [Opções do Minikube](https://minikube.sigs.k8s.io/docs/commands/start/)

~~~bash
docker info --format 'CPUs={{.NCPU}} RAM={{.MemTotal}}'
minikube start -p minikube --driver=docker --container-runtime=containerd \
  --kubernetes-version=v1.37.0 --cpus=no-limit --memory=no-limit
kubectl config use-context minikube
kubectl wait --for=condition=Ready node/minikube --timeout=180s
minikube -p minikube addons enable metrics-server
kubectl get storageclass
kubectl get --raw='/readyz?verbose'
~~~

Confirme a StorageClass `standard` e o provisionador de volumes do perfil antes das aplicações com PVC. Para um ambiente com teto efetivo de 4 CPUs e 8 GiB, estabilize a stack sem jobs ARC primeiro. [Evidência de pressão de CPU e memória](evidence/Dificuldades.md)

## 2. Instalar Argo CD e criar os projetos

~~~bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update argo
helm upgrade --install argocd argo/argo-cd --version 10.18.2 \
  --namespace argocd --create-namespace \
  -f infra/gitops/helm-values/argocd-resources.yaml --wait --timeout 10m
kubectl apply -f infra/gitops/projects/
kubectl -n argocd get pods,appprojects
kubectl -n argocd port-forward svc/argocd-server 8080:80
~~~

Em outro terminal, obtenha a senha inicial com `argocd admin initial-password -n argocd`, autentique a CLI no endereço encaminhado com `argocd login localhost:8080 --plaintext` e troque a senha inicial. O values ativa HTTP no serviço interno para o Traefik terminar TLS. O mesmo arquivo define os resources do controller, repo-server, Dex e demais componentes. [Values do Argo CD](infra/gitops/helm-values/argocd-resources.yaml)

Os manifests GitOps leem a branch `main` remota. Publique os arquivos pelo fluxo de revisão antes do sync e configure o acesso ao Git no Argo CD se o repositório for privado.

## 3. Provisionar as aplicações com App of Apps

Com o Minikube e o Argo CD prontos, use `platform-root` como entrada da plataforma. Essa Application pai lê a pasta `infra/gitops/applications` na branch `main` e cria as sete Applications filhas. O pai sincroniza automaticamente suas definições. Cada filha mantém sua própria política de sync para os workloads. [Application raiz](infra/gitops/bootstrap/root-app.yaml) · [Padrão App of Apps no Argo CD](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/#app-of-apps-pattern-alternative)

### 3.1 Preparar as dependências

Antes de aplicar o pai, execute as etapas indicadas abaixo para que as filhas encontrem os CRDs, Secrets e a imagem esperada. Os comandos de criação individual de Applications nos guias servem para instalações isoladas.

| Dependência | Procedimento |
| --- | --- |
| AppProjects | Confirme a aplicação de `infra/gitops/projects/` na seção 2 |
| TLS e Gateway API | Crie `traefik/local-selfsigned-tls` e instale os CRDs antes de aplicar as rotas. [Certificados](infra/certs/01-install-certs.md) · [Gateway API](infra/traefik/01-install-traefik.md#1-preparar-gateway-api-e-tls) |
| Harbor | Crie o namespace `harbor` e o Secret `harbor-admin`. [Guia do Harbor](infra/harbor/01-install-harbor.md#1-preparar-o-namespace-e-a-senha) |
| SonarQube | Crie o namespace `sonarqube` e o Secret `sonarqube-monitoring`. [Guia do SonarQube](infra/sonarqube/01-install-sonarqube.md#1-preparar-o-secret-de-monitoramento) |
| Imagem da POCAPP | Confira `image.repository`, `image.tag` e `image.pullPolicy` no values publicado em `main`. Com o padrão `healthz-api:1.0.0` e `IfNotPresent`, carregue o build local no Minikube. Com imagem no Harbor, siga o procedimento de recuperação abaixo se ela ainda estiver indisponível. [Guia da POCAPP](app/Runbookapp.md#2-disponibilizar-a-imagem) |

Registre o SHA usado como referência do provisionamento. O clone local e a revisão Git lida pelo Argo CD devem conter os mesmos manifests. Em uma reconstrução, recupere as credenciais do gerenciador e restaure volumes ou imagens de backup quando quiser preservar os dados do ambiente anterior.

~~~bash
kubectl config current-context
git fetch origin main
git rev-parse HEAD origin/main
kubectl -n argocd get appprojects
kubectl -n traefik get secret local-selfsigned-tls
kubectl -n harbor get secret harbor-admin
kubectl -n sonarqube get secret sonarqube-monitoring
kubectl get crd gateways.gateway.networking.k8s.io httproutes.gateway.networking.k8s.io
~~~

### 3.2 Criar e conferir as Applications filhas

~~~bash
kubectl apply -f infra/gitops/bootstrap/root-app.yaml
argocd app wait platform-root --sync --timeout 180
kubectl -n argocd get applications
~~~

Espere encontrar `traefik`, `harbor`, `sonarqube`, `platform-routes`, `kyverno`, `kyverno-policies` e `pocapp`. O status `Synced` do pai confirma que os manifests das filhas foram aplicados. Confira a saúde e o sync de cada filha nas etapas seguintes.

### 3.3 Sincronizar a plataforma e as políticas

Execute cada bloco após o anterior completar. As Applications de Traefik, Harbor, SonarQube, rotas e políticas usam sync manual.

~~~bash
argocd app sync traefik
argocd app wait traefik --sync --health --timeout 300
kubectl -n traefik wait --for=condition=Programmed gateway/traefik-gateway --timeout=180s

argocd app sync harbor
argocd app wait harbor --sync --health --timeout 600
kubectl -n harbor get pods,pvc,svc
kubectl get --raw='/api/v1/namespaces/harbor/services/http:harbor:80/proxy/api/v2.0/health'

argocd app sync sonarqube
argocd app wait sonarqube --sync --health --timeout 600
kubectl -n sonarqube get pods,pvc,svc

argocd app sync platform-routes
argocd app wait platform-routes --sync --timeout 180
kubectl get httproute -A
~~~

Avance com o Harbor reportando `healthy`, os PVCs em `Bound` e as rotas de plataforma com `Accepted=True` e `ResolvedRefs=True`. Consulte os guias para configurar o acesso ao [Harbor](infra/harbor/01-install-harbor.md#3-preparar-o-registry-para-a-aplicação) e ao [SonarQube](infra/sonarqube/01-install-sonarqube.md#3-conectar-ao-pipeline).

O Kyverno sincroniza automaticamente. Aguarde os controladores, confirme a API da política e sincronize a filha de políticas. [Guia do Kyverno](infra/kyverno/01-install-kyverno.md)

~~~bash
argocd app wait kyverno --sync --health --timeout 300
kubectl -n kyverno get deployments,pods
kubectl api-resources --api-group=policies.kyverno.io
argocd app diff kyverno-policies
argocd app sync kyverno-policies
argocd app wait kyverno-policies --sync --health --timeout 180
~~~

### 3.4 Validar a POCAPP

A POCAPP também usa auto-sync. Se a primeira tentativa falhar porque a imagem ainda está indisponível, ajuste a dependência e dispare um sync da filha. Com um Harbor novo, restaure ou publique a imagem esperada e confirme que o runtime do Minikube alcança o registry. Em projeto privado, configure o Secret de pull em `apps` e referencie-o nos values. Se a tag original não estiver disponível, publique no Git uma referência válida antes de sincronizar. [Imagem e CI/CD da POCAPP](app/Runbookapp.md)

~~~bash
argocd app wait pocapp --sync --health --timeout 300
kubectl -n apps rollout status deployment/pocapp --timeout=180s
kubectl -n apps describe httproute pocapp
kubectl -n apps port-forward svc/pocapp 3000:80
~~~

Em outro terminal, execute `curl -fsS http://127.0.0.1:3000/healthz` e confira `status: healthy`.

### 3.5 Adicionar ARC e observabilidade

ARC e observabilidade têm bootstrap separado porque seus manifests ficam fora da pasta lida por `platform-root`. Execute os guias na ordem abaixo e confira a capacidade do nó antes de iniciar um runner ou habilitar toda a observabilidade.

1. Configure a GitHub App e instale o controller e o scale set com os respectivos AppProject e Secret. Confirme o listener e faça o teste do runner sob demanda. [GitHub App](infra/gitops/arc-minikube/01-install-arc-github.md) · [Instalação do ARC](infra/gitops/arc-minikube/README.md)
2. Crie o Secret do Grafana e o AppProject de observabilidade. Instale Prometheus/Grafana e Loki, aguarde os serviços e siga com Alloy e a rota do Grafana. [Observabilidade](infra/gitops/observability-minikube/README.md)
3. Configure o CI/CD e confirme que o runner chega ao SonarQube, que o runner de publicação chega ao Harbor e que o Minikube consegue puxar a imagem. [CI/CD da POCAPP](app/Runbookapp.md#3-configurar-o-cicd)

### 3.6 Conferir o ambiente ao final

~~~bash
kubectl -n argocd get applications
kubectl get pods,pvc -A
kubectl get gateway,httproute -A
kubectl top node
docker stats --no-stream minikube
~~~

Registre o SHA reconciliado e confirme as Applications provisionadas como `Synced/Healthy`, os PVCs em `Bound`, as rotas aceitas e o endpoint da POCAPP respondendo. O ARC pode ficar sem pods de runner quando estiver ocioso.

## 4. Operar e recuperar

- Para acessar os hosts locais no macOS, mantenha `minikube service traefik -n traefik --url` aberto e use a porta encaminhada ao listener HTTPS. [Acesso pelo Traefik](infra/traefik/01-install-traefik.md)
- Para incidentes de provisionamento, confira contêiner, nó, API Server, pods e eventos. [Dificuldades e evidências](evidence/Dificuldades.md)
- Para restaurar uma imagem da POCAPP, selecione uma tag disponível no Harbor e execute o workflow. Git registra o estado desejado e Argo CD aplica a mudança. [Procedimento de rollback](evidence/Processorollback.md)
