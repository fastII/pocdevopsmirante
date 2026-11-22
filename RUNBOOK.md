# Runbook de provisionamento da POC DevOps Mirante

Execute os comandos a partir da raiz do repositório, salvo quando o guia indicar outro diretório. A referência da POC é um cluster Minikube de nó único no macOS, com Docker Desktop, runtime containerd e Kubernetes v1.37.0.

Na instalação original, as Applications foram provisionadas individualmente pelo Argo CD. O script abaixo usa `platform-root` para reproduzir o ambiente. [Evidências da instalação original](evidence/Provisionamento.md)

## Provisionamento pelo script

### Primeira instalação em outra máquina

1. Instale Bash, Git, Minikube, kubectl, Helm, OpenSSL, jq e o yq v4 de mikefarah. Inicie o Docker.
2. Com seu próprio acesso ao GitHub, clone o repositório da POC e entre na pasta.
3. Execute o Bash abaixo. Como o repositório é privado, o script solicita usuário e token HTTPS de leitura para o Argo CD, além das senhas locais de Harbor e Grafana e do passcode de monitoramento do SonarQube. A pessoa pode usar credenciais próprias. TLS é gerado localmente.

~~~bash
git clone https://github.com/fastII/pocdevopsmirante.git
cd pocdevopsmirante
bash scripts/provision-minikube.sh --repositorio-privado --acesso-corporativo
~~~

O token do Argo CD precisa de leitura no repositório. O Git da máquina já deve estar autenticado para clonar e conferir a revisão. A instalação nova da infraestrutura funciona com os prompts, sem arquivos SOPS, chave age ou backups de outra máquina. Para automatizar o preenchimento, forneça as variáveis listadas em `--help`. Por exemplo, `SONAR_MONITORING_PASSCODE` fornece o passcode do SonarQube.

O runner `self-hosted` é configurado à parte quando houver necessidade de rodar CI/CD. Para instalar o ARC, acrescente `--com-arc` e tenha a GitHub App, seus IDs e o PEM guardado fora do Git. Os jobs precisam selecionar o runner pretendido pelo `runs-on`. [Preparar a GitHub App](infra/gitops/arc-minikube/01-install-arc-github.md)

O [script](scripts/provision-minikube.sh) prepara o Minikube, pede as credenciais em falta e executa o provisionamento na ordem abaixo. Em ambiente corporativo sem permissão para editar `/etc/hosts`, `--acesso-corporativo` executa `minikube service traefik -n traefik --url`. Use o hostname da rota e a porta encaminhada para HTTPS. As portas podem mudar a cada execução. Se houver túnel, mantenha o terminal aberto. `--servir` é a alternativa de porta fixa `8443`. [Acesso a serviços no Minikube](https://minikube.sigs.k8s.io/docs/handbook/accessing/)

| Grupo | Quem cria as Applications |
| --- | --- |
| Traefik, Harbor, SonarQube, Kyverno, políticas, rotas da plataforma e POCAPP | `platform-root` lê `infra/gitops/applications/` |
| ARC | Com `--com-arc`, o script aplica o projeto, o controller e o scale set |
| Observabilidade | O script aplica o projeto e as Applications de Prometheus/Grafana, Loki, Alloy e rota do Grafana |

Dentro da observabilidade, apenas o Grafana é publicado por HTTPRoute. As rotas do Argo CD, Harbor, SonarQube e POCAPP fazem parte da plataforma.

O `platform-root` cria a Application `pocapp`. A própria filha usa auto-sync para renderizar `helm/pocapp` e implantar no namespace `apps`. Os AppProjects continuam separados. Eles autorizam os repositórios, destinos e recursos usados pelas Applications. [Application POCAPP](infra/gitops/applications/pocapp.yaml)

- Rode `bash scripts/provision-minikube.sh --help` para ver as variáveis de automação. Use `--sem-observabilidade` para omitir essa etapa quando houver pouca folga de memória.
- Com os values padrão da POCAPP, o script constrói a imagem no nó. Se `main` já aponta para um registry, a tag precisa estar disponível e acessível no Minikube. Para reconstruir o cluster com uma imagem preservada, passe `POCAPP_IMAGE_ARCHIVE` com um archive da referência esperada e use política de pull `IfNotPresent` ou `Never`. Para registry privado, passe `POCAPP_DOCKER_CONFIG` e declare o nome do Secret em `imagePullSecrets`. [Imagem e CI/CD da POCAPP](app/Runbookapp.md)
- GitHub Actions ainda exige as variáveis e os Secrets do workflow. O runner `self-hosted` precisa alcançar o SonarQube e o Harbor. O encaminhamento local atende processos na mesma máquina. [Configuração do CI/CD](app/Runbookapp.md#3-configurar-o-cicd)

Depois do provisionamento, acesse `https://argocd.localhost:PORTA_HTTPS` com a porta anunciada, ou `8443` com `--servir`. O Argo CD atende HTTP interno no Service `argocd-server:80`. O Traefik termina TLS no listener `websecure`, e a Application `platform-routes` publica o HTTPRoute. [Values do Argo CD](infra/gitops/helm-values/argocd-resources.yaml) · [HTTPRoute do Argo CD](infra/gitops/routes/argocd-httproute.yaml) · [Values do Traefik](infra/gitops/helm-values/traefik.yaml)

### Reexecutar ou reconstruir

- **Perfil existente.** Reexecute o script para reconciliar a instalação. Ele reutiliza Secrets encontrados e solicita apenas os ausentes. As sincronizações manuais usam `prune: false`; as Applications automáticas mantêm suas próprias políticas. Confira os PVCs e suas políticas antes de mudanças que removam volumes do estado desejado.
- **Perfil excluído.** Forneça as credenciais por prompt, variáveis ou backups SOPS. Para reativar um repositório Git privado, configure o acesso do Git local. O Argo CD usa o PAT do backup SOPS ou as credenciais HTTPS informadas com `--repositorio-privado`. TLS e credenciais de pull têm suas próprias etapas.

| Arquivo SOPS | Secret esperado | Chaves |
| --- | --- | --- |
| `harbor.enc.yaml` | `harbor/harbor-admin` | `HARBOR_ADMIN_PASSWORD` |
| `sonarqube.enc.yaml` | `sonarqube/sonarqube-monitoring` | `monitoringPasscode` |
| `grafana.enc.yaml` | `observability/grafana-admin` | `admin-user`, `admin-password` |
| `gitops-repo.enc.yaml` | `argocd/provision-gitops-repo` | `type` (`git`), `url` (igual à do `platform-root`), `username`, `password` (PAT) |
| `arc.enc.yaml` | `arc-runners/arc-github-app` | `github_app_id`, `github_app_installation_id`, `github_app_private_key` |

Com `--restaurar-secrets`, o script procura os arquivos da tabela dentro de `SECRETS_DIR`, que tem `infra/secrets` como padrão. Aponte essa variável para a sua pasta de backups e `SOPS_AGE_KEY_FILE` para a chave privada age que abre os arquivos. Guarde a chave fora do Git e do Minikube. Cada arquivo deve conter um único Secret. O script preserva Secrets existentes e solicita credenciais ausentes quando o arquivo correspondente também estiver ausente. [SOPS e age](https://getsops.io/docs/)

~~~bash
export SOPS_AGE_KEY_FILE="/caminho/seguro/keys.txt"
export SECRETS_DIR="/caminho/seguro/backups-sops"
bash scripts/provision-minikube.sh --restaurar-secrets --repositorio-privado --acesso-corporativo
~~~

Acrescente `--com-arc` para instalar o ARC e restaurar a credencial da GitHub App, quando disponível. O PAT do backup configura o acesso do Argo CD ao repositório. O Git local precisa ter acesso à revisão antes de iniciar o bootstrap.

Antes de excluir o perfil, confirme que os backups podem ser abertos com a chave armazenada fora do cluster. Imagens e metadados do Harbor, histórico do SonarQube e dashboards criados manualmente exigem exportação ou backup próprio. Restaurar um Secret recupera credenciais do bootstrap, sem recuperar os dados dos volumes.

## Melhorias da POC

- **Recuperação opcional de credenciais com SOPS e age.** Use o modo de restauração quando precisar recuperar as credenciais de um perfil anterior. Para uma instalação nova em outra máquina, o script já solicita credenciais próprias. Mantenha a chave age fora do Git e valide a descriptografia antes de excluir um perfil. [Reexecutar ou reconstruir](#reexecutar-ou-reconstruir)
- **Provisionamento com poucos recursos.** Use o driver Docker com o runtime `containerd` no nó Kubernetes. Essa é a configuração já usada pelo script para um perfil novo. O Docker continua executando o nó, e o containerd executa os pods dentro dele. Se a memória continuar apertada, comece com `--sem-observabilidade`, mantenha o ARC desativado se já usa um runner externo e acompanhe `docker stats` antes de adicionar os demais componentes. [Driver Docker do Minikube](https://minikube.sigs.k8s.io/docs/drivers/docker/) · [Evidências de capacidade](evidence/Dificuldades.md)

### Aprovar mudanças antes de entrar em main

1. Abra PR de uma branch de trabalho para `main`. Configure validações no evento `pull_request`, como os checks do Node.js e o `helm lint`.
2. Proteja `main` com uma regra de branch ou ruleset. Exija PR, pelo menos uma aprovação e os checks obrigatórios aprovados antes do merge. [Regras de proteção no GitHub](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets)
3. Antes de ativar o bloqueio de push direto, adapte os workflows de deploy e rollback para publicar a mudança de tag em uma branch e abrir um PR. Mantenha a validação obrigatória nos PRs de GitOps e evite disparar um novo build de imagem só porque o PR atualizou a tag no Helm values. Após o merge, o Argo CD reconcilia o estado publicado em `main`. [Workflow de CI/CD](.github/workflows/pocapp-ci-cd.yaml) · [Workflow de rollback](.github/workflows/rollback-pocapp.yaml)

Essa proteção é uma melhoria proposta. Hoje os dois workflows ainda fazem push direto para `main`.

<details>
<summary>Arquitetura e provisionamento manual</summary>

Use as etapas abaixo para entender a ordem do bootstrap ou instalar por etapas. Se rodou o script com sucesso, vá direto a [Operar e recuperar](#4-operar-e-recuperar).

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

Antes de aplicar o pai, execute as etapas indicadas abaixo para que as filhas encontrem os CRDs, Secrets e a imagem esperada.

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

O primeiro deploy usa uma réplica estável. Com a versão estável saudável e folga no nó, ative o canary pelo Git ou pelo workflow manual e ajuste o peso na rota do Traefik. [Canary da POCAPP](app/Runbookapp.md#5-canary-com-traefik)

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

</details>

## 4. Operar e recuperar

- Para acessar os hosts locais no macOS, mantenha `minikube service traefik -n traefik --url` aberto e use a porta encaminhada ao listener HTTPS. [Acesso pelo Traefik](infra/traefik/01-install-traefik.md)
- Para incidentes de provisionamento, confira contêiner, nó, API Server, pods e eventos. [Dificuldades e evidências](evidence/Dificuldades.md)
- Para restaurar uma imagem da POCAPP, selecione uma tag disponível no Harbor e execute o workflow. Git registra o estado desejado e Argo CD aplica a mudança. [Procedimento de rollback](evidence/Processorollback.md)
