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

| Variável ou Secret | Quando configurar |
| --- | --- |
| `SONAR_TOKEN` | Secret de análise do SonarQube |
| `SONAR_HOST_URL` | Opcional. Deixe sem valor quando o runner estiver na máquina do Minikube. O job abre o próprio port-forward via `kubectl` |
| `HARBOR_REGISTRY`, `HARBOR_PROJECT` | Modo `harbor`. Use `hostname[:porta]`, sem `https://`, e o nome do projeto |
| `HARBOR_USERNAME`, `HARBOR_PASSWORD` | Secrets para publicação no modo `harbor` |
| `POCAPP_IMAGE_PLATFORM` | Opcional. Padrão `linux/arm64`. Use `linux/amd64` se o nó for Intel/AMD |
| `POCAPP_IMAGE_DELIVERY` | Opcional. Define o modo de entrega nos pushes automáticos. Padrão `harbor` |

O build e o Trivy rodam no runner hospedado pelo GitHub. O runner `self-hosted` executa a análise Sonar e entrega o artefato. Para o acesso local automático, o usuário do runner precisa ter `kubectl`, `jq` e acesso ao contexto `minikube`. A URL criada pelo job vale durante a análise e o Quality Gate. Remova a variável `SONAR_HOST_URL` se ela apontar para uma porta antiga do Traefik.

Para o primeiro deploy com pouca memória, abra **Actions → POCAPP - CI & CD → Run workflow** em `main`, selecione `deploy_target: stable` e `image_delivery: minikube-local`. O runner baixa a imagem pronta, carrega-a no Minikube e só então o job GitOps publica a tag. Esse modo funciona com `IfNotPresent` e depende do cache do perfil. Guarde o artefato se quiser reconstruir o mesmo deploy depois de excluir o cluster. Para usar o Harbor, selecione `image_delivery: harbor` e valide o endereço do registry tanto no runner quanto no runtime do nó. [Workflow da POCAPP](../.github/workflows/pocapp-ci-cd.yaml) · [Acesso ao Harbor](../infra/harbor/01-install-harbor.md#3-preparar-o-registry-para-a-aplicação)

Use `deploy_target: canary` após o primeiro deploy saudável. Durante um canary, o job GitOps e o workflow de rollback preservam as duas imagens até o encerramento pelo Git. Um commit que mexe apenas no `helm/pocapp/values.yaml` é reconciliado pelo Argo CD sem disparar esse workflow.

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

## 5. Canary com Traefik

Faça o primeiro deploy com `canary.enabled: false`. Se o pod estiver em `ImagePullBackOff`, confira a imagem e os eventos com `kubectl -n apps describe pod -l app.kubernetes.io/instance=pocapp`. Com os values locais, disponibilize a imagem conforme a seção 2. Antes de ativar o canary, confirme a versão estável `1/1` e `/healthz` com HTTP 200. Confira a folga do nó com `kubectl top nodes` e do Docker com `docker stats --no-stream minikube`.

O canary usa o mesmo `HTTPRoute` em `healthz.localhost` com dois Services `ClusterIP` e pesos configurados no Git. Com os values padrão, o total das duas réplicas é 50m de CPU e 64Mi de memória em requests e 200m de CPU e 256Mi de memória em limites. [Divisão de tráfego na Gateway API](https://gateway-api.sigs.k8s.io/guides/user-guides/traffic-splitting/)

1. Disponibilize a candidata com uma tag própria. Use o workflow manual ou preencha `canary.image.repository` e `canary.image.tag` nos values, com a imagem já acessível pelo Minikube. Comece com `canary.enabled: true` e `canary.weight: 0`. O Argo CD mantém todo o tráfego na versão estável.
2. Após o sync, aguarde `kubectl -n apps rollout status deployment/pocapp-canary`. Abra `kubectl -n apps port-forward svc/pocapp-canary 3001:80` e consulte `curl -fsS http://127.0.0.1:3001/healthz` para conferir a tag no campo `version`. As imagens devem incluir o código atualizado da API para expor esse campo.
3. Publique `canary.weight: 10` em `main` e confira `Accepted=True` e `ResolvedRefs=True` em `kubectl -n apps describe httproute pocapp`. Com o túnel do Traefik aberto, substitua `PORTA_HTTPS` pela porta local e conte as respostas de cada versão. Confira os erros HTTP antes de aumentar o peso.

   ~~~bash
   PORTA_HTTPS=8443 # Use 8443 com --servir ou a porta anunciada pelo túnel.
   for i in $(seq 1 40); do
     curl -fkSs --noproxy '*' --resolve "healthz.localhost:$PORTA_HTTPS:127.0.0.1" \
       "https://healthz.localhost:$PORTA_HTTPS/healthz" | jq -er '.version'
   done | sort | uniq -c
   ~~~

4. **Promover.** Publique `canary.weight: 100` e confirme que a rota serve a candidata. Em seguida, copie o repositório, a tag e a política de pull efetiva da candidata para `image`, mantendo o peso em 100 até `deployment/pocapp` ficar saudável com essa imagem. Publique `canary.weight: 0` e confirme que o Service estável atende com a tag promovida. Depois publique `canary.enabled: false` para o Argo CD remover os recursos do canary.
5. **Abortar antes de atualizar a imagem estável.** Publique `canary.weight: 0` e confirme que a rota voltou à versão estável. Depois desabilite o canary. Se a imagem estável já tiver sido atualizada durante a promoção, restaure a imagem anterior nela e espere que fique saudável antes de devolver o tráfego. Mantenha a imagem anterior disponível para essa recuperação.
