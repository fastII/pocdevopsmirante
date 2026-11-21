Os conceitos principais do projeto original:
- ARC Controller: gerencia os runners no Kubernetes.
- Runner Scale Set: registra os runners no GitHub e cria pods conforme a demanda.
- GitHub App: autentica o ARC usando um Kubernetes Secret nativo.
- DinD: permite executar workflows com docker build e docker push.
- Escalabilidade: começa com zero runners ociosos e cria pods quando chegam jobs.


Preenchimento da GitHub App
Campo	Valor recomendado
GitHub App name	arc-minikube-runner (se disponível)
Description	GitHub App for Kubernetes self-hosted runners managed by ARC
Homepage URL	https://github.com/fastII
Redirect URI	Deixar vazio
Allow wildcard matching	Desmarcado
Expire user authorization tokens	Pode manter o padrão
Request user authorization during installation	Desmarcado
Enable Device Flow	Desmarcado
Setup URL	Deixar vazio
Redirect on update	Desmarcado

2. Webhook
Desmarque Active.

O ARC não precisa de um webhook público configurado nessa GitHub App para receber jobs. O listener do ARC se comunica com o GitHub por conexões de saída.

Assim, você não precisa configurar Webhook URL nem Webhook Secret.
3. Permissions
Essa é a parte mais importante.

Para runners vinculados a um único repositório, configure:

Repository permissions
Permissão	Acesso
Administration	Read and write
Metadata	Read-only (padrão)

As demais permissões podem permanecer em No access, salvo alguma necessidade específica.

Organization permissions: nenhuma permissão adicional para esse cenário.

Account permissions: nenhuma.

Subscribe to events: não é necessário selecionar eventos para a autenticação do ARC.

Se futuramente você quiser compartilhar runners entre vários repositórios de uma organização, será necessário utilizar as permissões de runners no nível da organização.


### PROCEDIMENTO DE INSTALACAO ##

Owned by: @fastII

App ID: 5855867

Using your App ID to get installation tokens? You can now use your Client ID instead.

Client ID: Iv23liLQdi8ncuLWMp6k

k apply -f arc-minikube/manifests/namespaces.yaml 

k -n arc-runners create secret generic arc-github-app \
  --from-literal=github_app_id="" \
  --from-literal=github_app_installation_id="" \
  --from-file=github_app_private_key="$HOME/Documents/GitHub/pocdevopsmirante/infra/gitops/arc-minikube/arc-minikube-runne.2026-11-20.private-key.pem"

k apply -f project.yaml 
appproject.argoproj.io/arc created

 k apply -f controller.yaml 
application.argoproj.io/arc-controller created

k get applications -n argocd && k get pods -n arc-systems 

NAME              SYNC STATUS   HEALTH STATUS
arc-controller    Synced        Healthy
harbor            OutOfSync     Healthy
platform-root     Synced        Healthy
platform-routes   OutOfSync     Healthy
sonarqube         Synced        Healthy
traefik           OutOfSync     Healthy
NAME                                     READY   STATUS    RESTARTS   AGE
arc-gha-rs-controller-674cf6b948-2pgzs   1/1     Running   0          41s

k apply -f scaleset.yaml 
application.argoproj.io/arc-runner-minikube created