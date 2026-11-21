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

## 3. Provisionar as aplicações em ordem

| Ordem | Procedimento | Critério de avanço |
| --- | --- | --- |
| 1 | [Certificado local](infra/certs/01-install-certs.md) e [Traefik / Gateway API](infra/traefik/01-install-traefik.md) | Secret TLS criado, CRDs presentes e Gateway programado |
| 2 | [Harbor](infra/harbor/01-install-harbor.md) e [SonarQube](infra/sonarqube/01-install-sonarqube.md) | Serviços disponíveis e PVCs `Bound` |
| 3 | Sincronize [platform-routes](infra/gitops/applications/platform-routes.yaml) | Rotas do Argo CD, Harbor e SonarQube aceitas |
| 4 | [Kyverno](infra/kyverno/01-install-kyverno.md) | Controladores disponíveis antes do sync das políticas |
| 5 | [GitHub App para ARC](infra/gitops/arc-minikube/01-install-arc-github.md) e [instalação do ARC](infra/gitops/arc-minikube/README.md) | Controller e listener prontos, runner criado sob demanda |
| 6 | [POCAPP e CI/CD](app/Runbookapp.md) | Imagem disponível para o nó, Deployment pronto e `/healthz` retorna 200 |
| 7 | [Prometheus, Grafana, Loki e Alloy](infra/gitops/observability-minikube/README.md) | Dashboards disponíveis, métricas e logs consultáveis, pressão acompanhada |

Para instalar as rotas no passo 3, use `kubectl apply -f infra/gitops/applications/platform-routes.yaml` e `argocd app sync platform-routes`. Os guias instalam as Applications individualmente para respeitar dependências no primeiro provisionamento. Depois que elas estiverem prontas, registre a Application raiz para reconciliar os manifests em `infra/gitops/applications`. ARC e observabilidade ficam fora desse caminho e têm bootstrap próprio.

~~~bash
kubectl apply -f infra/gitops/bootstrap/root-app.yaml
kubectl -n argocd get applications
kubectl get pods,pvc -A
kubectl get gateway,httproute -A
kubectl top node
docker stats --no-stream minikube
~~~

## 4. Operar e recuperar

- Para acessar os hosts locais no macOS, mantenha `minikube service traefik -n traefik --url` aberto e use a porta encaminhada ao listener HTTPS. [Acesso pelo Traefik](infra/traefik/01-install-traefik.md)
- Para incidentes de provisionamento, confira contêiner, nó, API Server, pods e eventos. [Dificuldades e evidências](evidence/Dificuldades.md)
- Para restaurar uma imagem da POCAPP, selecione uma tag disponível no Harbor e execute o workflow. Git registra o estado desejado e Argo CD aplica a mudança. [Procedimento de rollback](evidence/Processorollback.md)
