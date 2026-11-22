# Evidências do provisionamento original

[Voltar ao README](../README.md)

As capturas registram o provisionamento original entre 19 e 21 de novembro de 2026. As etapas iniciais foram feitas por componente, com Helm e Applications individuais. O `platform-root` aparece no inventário posterior, e o script do runbook descreve o fluxo de reprodução da POC.

As imagens estão agrupadas pela ordem do provisionamento, com data e hora do Mac. As etapas mostram o que foi observado naquele momento, incluindo tentativas e correções. Capturas de credenciais e configuração de acesso foram mantidas fora do repositório.

## 1. Minikube

<details>
<summary>Ver 4 capturas</summary>

**19/11/2026 18:11:41** — Inicialização do perfil e ativação dos add-ons. O Minikube informa que alterar CPU e disco de um perfil existente exige recriação.

![Inicialização do perfil e ativação dos add-ons. O Minikube informa que alterar CPU e disco de um perfil existente exige recriação.](capturas/01-minikube-01-inicializacao.png)

**19/11/2026 18:11:53** — Nó de controle em `Ready` após a ativação do Metrics Server.

![Nó de controle em Ready após a ativação do Metrics Server.](capturas/01-minikube-02-no-ready.png)

**19/11/2026 18:12:18** — IngressClass Nginx presente no perfil original, antes da consolidação do acesso com Traefik.

![IngressClass Nginx presente no perfil original, antes da consolidação do acesso com Traefik.](capturas/01-minikube-03-ingress-nginx.png)

**19/11/2026 18:12:57** — Coleta inicial de CPU e memória com `kubectl top node`.

![Coleta inicial de CPU e memória com kubectl top node.](capturas/01-minikube-04-metricas.png)

</details>

## 2. Argo CD e projetos

<details>
<summary>Ver 6 capturas</summary>

**19/11/2026 18:47:46** — Configuração inicial do repositório Helm do Argo CD.

![Configuração inicial do repositório Helm do Argo CD.](capturas/02-argocd-01-repositorio-helm.png)

**19/11/2026 18:54:10** — Criação das pastas `projects` e `bootstrap` durante a organização do GitOps.

![Criação das pastas projects e bootstrap durante a organização do GitOps.](capturas/02-argocd-02-estrutura-gitops.png)

**19/11/2026 19:17:58** — Definição do AppProject `platform-registry` para o Harbor.

![Definição do AppProject platform-registry para o Harbor.](capturas/02-argocd-03-appproject-registry.png)

**20/11/2026 15:47:30** — Repositório Git com status de conexão bem-sucedida na interface do Argo CD.

![Repositório Git com status de conexão bem-sucedida na interface do Argo CD.](capturas/02-argocd-04-repositorio-conectado.png)

**20/11/2026 15:54:04** — Inventário de AppProjects e Applications. O `platform-root` já aparecia nesse momento, após as primeiras etapas da instalação.

![Inventário de AppProjects e Applications. O platform-root já aparecia nesse momento, após as primeiras etapas da instalação.](capturas/02-argocd-05-projetos-e-applications.png)

**20/11/2026 18:09:33** — Upgrade do release Helm do Argo CD.

![Upgrade do release Helm do Argo CD.](capturas/02-argocd-06-upgrade-helm.png)

</details>

## 3. Gateway API, TLS e Traefik

<details>
<summary>Ver 11 capturas</summary>

**19/11/2026 18:27:23** — Aplicação dos CRDs Standard da Gateway API.

![Aplicação dos CRDs Standard da Gateway API.](capturas/03-traefik-01-crds-standard.png)

**19/11/2026 18:27:51** — Instalação inicial do Traefik por Helm.

![Instalação inicial do Traefik por Helm.](capturas/03-traefik-02-instalacao-helm.png)

**19/11/2026 18:28:05** — Pods do sistema e do Traefik após a instalação.

![Pods do sistema e do Traefik após a instalação.](capturas/03-traefik-03-pods.png)

**20/11/2026 14:49:18** — Inventário do Secret TLS no namespace `traefik`.

![Inventário do Secret TLS no namespace traefik.](capturas/03-traefik-04-secret-tls.png)

**20/11/2026 14:58:10** — Geração do certificado autoassinado e inspeção do certificado público e do SAN.

![Geração do certificado autoassinado e inspeção do certificado público e do SAN.](capturas/03-traefik-05-certificado.png)

**20/11/2026 18:25:44** — Aplicação individual dos HTTPRoutes de Argo CD, Harbor e SonarQube.

![Aplicação individual dos HTTPRoutes de Argo CD, Harbor e SonarQube.](capturas/03-traefik-06-httproutes.png)

**20/11/2026 18:25:56** — Registro da Application `platform-routes`.

![Registro da Application platform-routes.](capturas/03-traefik-07-application-rotas.png)

**20/11/2026 18:47:35** — Logs de inicialização do Traefik durante o diagnóstico da Gateway API.

![Logs de inicialização do Traefik durante o diagnóstico da Gateway API.](capturas/03-traefik-08-erros-provider.png)

**20/11/2026 18:48:28** — Inventário das APIs e das versões da Gateway API.

![Inventário das APIs e das versões da Gateway API.](capturas/03-traefik-09-inventario-crds.png)

**20/11/2026 19:07:31** — Backup dos CRDs e aplicação do bundle Experimental 1.4.1 durante a recuperação original.

![Backup dos CRDs e aplicação do bundle Experimental 1.4.1 durante a recuperação original.](capturas/03-traefik-10-recuperacao-crds.png)

**20/11/2026 19:58:16** — Resposta HTTP 404 no acesso local durante o diagnóstico de rota.

![Resposta HTTP 404 no acesso local durante o diagnóstico de rota.](capturas/03-traefik-11-resposta-404.png)

</details>

## 4. Harbor e SonarQube

<details>
<summary>Ver 6 capturas</summary>

**19/11/2026 18:34:20** — Preparação da pasta e dos values iniciais do Harbor.

![Preparação da pasta e dos values iniciais do Harbor.](capturas/04-harbor-01-estrutura.png)

**19/11/2026 18:35:35** — Consulta de versões do chart Harbor.

![Consulta de versões do chart Harbor.](capturas/04-harbor-02-versoes-chart.png)

**19/11/2026 18:39:02** — Pods, Services e Deployments do Harbor. O Trivy constava na instalação original.

![Pods, Services e Deployments do Harbor. O Trivy constava na instalação original.](capturas/04-harbor-03-recursos.png)

**19/11/2026 18:39:17** — PVCs do Harbor em `Bound`.

![PVCs do Harbor em Bound.](capturas/04-harbor-04-pvcs.png)

**20/11/2026 14:20:31** — Consulta de versões do chart SonarQube.

![Consulta de versões do chart SonarQube.](capturas/04-sonarqube-01-versoes-chart.png)

**20/11/2026 14:31:44** — Renderização de StatefulSets em uma versão anterior do chart. A captura não descreve a configuração de banco atual.

![Renderização de StatefulSets em uma versão anterior do chart. A captura não descreve a configuração de banco atual.](capturas/04-sonarqube-02-renderizacao.png)

</details>

## 5. Kyverno e políticas

<details>
<summary>Ver 3 capturas</summary>

**21/11/2026 10:58:59** — Consulta do chart Kyverno e da versão selecionada.

![Consulta do chart Kyverno e da versão selecionada.](capturas/05-kyverno-01-versoes-chart.png)

**21/11/2026 11:01:30** — Dry-run dos manifests e criação individual do AppProject e da Application.

![Dry-run dos manifests e criação individual do AppProject e da Application.](capturas/05-kyverno-02-dry-run-e-application.png)

**21/11/2026 11:01:53** — O job `kyverno-check-legacy-policies` terminou em `Completed`. O `kubectl get pods -w` ainda estava ativo, então a imagem não mostra as verificações seguintes de Deployments, CRDs e webhooks.

![O job kyverno-check-legacy-policies terminou em Completed. O kubectl get pods -w ainda estava ativo, então a imagem não mostra as verificações seguintes de Deployments, CRDs e webhooks.](kyverno-01-pre-sync.png)

</details>

## 6. ARC e GitHub Actions

<details>
<summary>Ver 3 capturas</summary>

**21/11/2026 11:17:57** — O workflow pediu o runner `arc-minikube` e estava na fila. Esta captura registra a espera, sem confirmar a execução do job.

![O workflow pediu o runner arc-minikube e estava na fila. Esta captura registra a espera, sem confirmar a execução do job.](capturas/06-arc-01-job-aguardando-runner.png)

**21/11/2026 22:17:38** — Registro de um runner self-hosted no macOS ARM64 que chegou a `Listening for Jobs`. Esse runner local é distinto do scale set ARC no Kubernetes.

![Registro de um runner self-hosted no macOS ARM64 que chegou a Listening for Jobs. Esse runner local é distinto do scale set ARC no Kubernetes.](capturas/06-runner-02-self-hosted-macos.png)

**21/11/2026 22:18:16** — Tela do GitHub com a configuração de um runner self-hosted para macOS ARM64. A captura foi recortada e complementa o registro do terminal acima.

![Tela de configuração do runner self-hosted para macOS ARM64 no GitHub Actions](capturas/06-runner-03-github-configuracao-macos.png)

</details>

## 7. POCAPP

<details>
<summary>Ver 6 capturas</summary>

**19/11/2026 18:17:39** — Criação e estrutura inicial do chart `helm/pocapp`.

![Criação e estrutura inicial do chart helm/pocapp.](capturas/07-pocapp-01-chart.png)

**21/11/2026 09:54:29** — API Node.js iniciada localmente na porta 3000.

![API Node.js iniciada localmente na porta 3000.](capturas/07-pocapp-02-api-local.png)

**21/11/2026 09:55:00** — Endpoint `/healthz` da API local com HTTP 200 e `status: healthy`.

![Endpoint /healthz da API local com HTTP 200 e status: healthy.](capturas/07-pocapp-03-healthz-local.png)

**21/11/2026 21:30:43** — Aplicação individual do AppProject `pocapp`. A captura registra uma configuração histórica; use o manifesto do repositório como referência.

![Aplicação individual do AppProject pocapp. A captura registra uma configuração histórica; use o manifesto do repositório como referência.](capturas/07-pocapp-04-appproject-original.png)

**22/11/2026 17:28:39** — Execução nº 49 concluída com sucesso da validação Node.js e Helm à atualização GitOps. [Execução no GitHub Actions](https://github.com/fastII/pocdevopsmirante/actions/runs/45063520671)

![Execução nº 49 do pipeline com os cinco jobs em verde](capturas/07-pocapp-05-pipeline-sucesso.png)

**22/11/2026 17:36:57** — A aba **Summary** mostra os seis jobs em verde, a imagem entregue ao Harbor para a versão estável e a revisão GitOps `4e6054b43b59`.

![Resumo do pipeline com os seis jobs concluídos com sucesso, a imagem entregue e a revisão GitOps](capturas/07-pocapp-06-pipeline-summary.png)

</details>

## 8. Observabilidade

<details>
<summary>Ver 5 capturas</summary>

**20/11/2026 21:23:16** — Criação do namespace `observability` e do Secret do Grafana com entrada oculta da senha.

![Criação do namespace observability e do Secret do Grafana com entrada oculta da senha.](capturas/08-observabilidade-01-namespace-e-secret.png)

**20/11/2026 21:23:29** — Criação do AppProject e das Applications de Prometheus, Loki e Alloy.

![Criação do AppProject e das Applications de Prometheus, Loki e Alloy.](capturas/08-observabilidade-02-applications.png)

**20/11/2026 21:23:53** — Criação da Application da rota do Grafana após registrar os componentes.

![Criação da Application da rota do Grafana após registrar os componentes.](capturas/08-observabilidade-03-rota-grafana.png)

**22/11/2026 16:38:41** — Grafana com as métricas de CPU e memória do namespace `observability`, coletadas pelo Prometheus.

![Painel do Grafana com utilização de CPU e memória por pod](capturas/08-observabilidade-04-grafana-metricas.png)

**22/11/2026 16:40:39** — Grafana consultando no Loki os logs do namespace `traefik`.

![Painel do Grafana com a linha do tempo e os logs do Traefik no Loki](capturas/08-observabilidade-05-grafana-logs.png)

</details>

## 9. Incidentes de provisionamento

<details>
<summary>Ver 3 capturas</summary>

**20/11/2026 17:32:53** — Tentativa de acessar a API e retomada do perfil Minikube existente.

![Tentativa de acessar a API e retomada do perfil Minikube existente.](capturas/09-incidente-01-retomada-minikube.png)

**21/11/2026 08:05:25** — Falha do check de prontidão do API Server durante o incidente.

![Falha do check de prontidão do API Server durante o incidente.](capturas/09-incidente-02-readyz-falhando.png)

**21/11/2026 09:21:15** — Aumento do limite de CPU e checagem de prontidão do API Server durante o contorno.

![Aumento do limite de CPU e checagem de prontidão do API Server durante o contorno.](capturas/09-incidente-03-contorno-cpu.png)

</details>

[Diagnóstico e contornos](Dificuldades.md) · [Procedimento de rollback](Processorollback.md)
