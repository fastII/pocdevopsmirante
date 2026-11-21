# POCAPP com Node.js, Helm e Argo CD

[Voltar ao runbook](../RUNBOOK.md)

A API está em app/ e o chart em helm/pocapp/. O Deployment usa requests de 25m de CPU e 32Mi de memória, com limites de 100m e 128Mi. As probes verificam /healthz. [Values da POCAPP](../helm/pocapp/values.yaml)

## 1. Validar a aplicação e o chart

Execute na raiz do repositório com Node.js 20 ou superior.

~~~bash
helm lint helm/pocapp
helm template pocapp helm/pocapp -n apps
npm --prefix app start
~~~

Em outro terminal, consulte `curl -i http://127.0.0.1:3000/healthz`. Espere HTTP 200 e status healthy. Uma rota inexistente deve retornar 404. Para criar um pacote local, use `helm package helm/pocapp`.

## 2. Disponibilizar a imagem

Para o primeiro sync com os values locais padrão, construa a imagem dentro do nó. O nome e a tag precisam corresponder à versão em main.

~~~bash
minikube -p minikube image build -t healthz-api:1.0.0 ./app
minikube -p minikube image ls
~~~

Para deploy via Harbor, confirme o projeto, a tag e o acesso do runtime ao registry. Se o projeto for privado, crie a credencial de pull em apps e referencie-a em imagePullSecrets. [Instalação do Harbor](../infra/harbor/01-install-harbor.md)

## 3. Configurar o CI/CD

| Tipo no GitHub Actions | Campos |
| --- | --- |
| Variables | SONAR_HOST_URL, HARBOR_REGISTRY, HARBOR_PROJECT |
| Secrets | SONAR_TOKEN, HARBOR_USERNAME, HARBOR_PASSWORD |

Os jobs de validação e análise Sonar executam no runner arc-minikube. O build e o Trivy usam ubuntu-latest. Em main, esse runner recebe a tarefa de publicar no Harbor, e o job GitOps atualiza image.repository e image.tag em main. A URL do SonarQube deve estar acessível no pod ARC. O endpoint do Harbor precisa estar acessível no runner hospedado pelo GitHub. [Workflow da POCAPP](../.github/workflows/pocapp-ci-cd.yaml)

## 4. Implantar e conferir

O `platform-root` cria a Application `pocapp`, que usa auto-sync.

~~~bash
argocd app wait pocapp --sync --health --timeout 300
kubectl -n apps rollout status deployment/pocapp
kubectl -n apps describe httproute pocapp
kubectl -n apps port-forward svc/pocapp 3000:80
~~~

O manifesto habilita auto-sync e criação do namespace apps. O Argo CD lê os values publicados em main. Para testar o deploy fora do GitOps, use um ambiente isolado para o release de Helm. [Application da POCAPP](../infra/gitops/applications/pocapp.yaml)

Verifique /healthz pelo port-forward ou use healthz.localhost com a porta HTTPS descrita no [guia do Traefik](../infra/traefik/01-install-traefik.md). Para recuperar uma imagem anterior, siga o [procedimento de rollback](../evidence/Processorollback.md).
