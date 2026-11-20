
## INSTALL ARGOCD ##

https://github.com/argoproj/argo-helm/blob/main/charts/argo-cd/values.yaml


helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

PRIMEIRA EXECUÇÃO PARA CRIAR O ARGOCD

helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  --set server.ingress.enabled=true \
  --set server.ingress.ingressClassName=traefik \
  --set server.ingress.hostname=argocd.local \
  --set server.ingress.path=/ \
  --set server.ingress.pathType=Prefix \
  --set configs.params."server\.insecure"=true \
  --wait

## Pegar a senha do ARGO ##
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

OBS.: Como configuramos o gatewayclass no caso foi necessário o upgrade novamente incluindo os resourceslimites e a criação do HTTPROUTE
COMANDO PARA HELM PARA BACKUP

helm get values argocd -n argocd -o yaml > argocd-values-backup.yaml

helm upgrade argocd argo/argo-cd \
  -n argocd \
  --reuse-values \
  -f argocd-resources.yaml \
  --wait \
  --timeout 10m

### ERRO ENCONTRADO ##

Problema restrição project: default no Secret do repositório. Como Harbor e SonarQube pertencem a outros AppProjects, o Argo CD não conseguia utilizar a credencial.

Depois de remover essa restrição, as Applications passaram de Unknown para OutOfSync. Isso indica que o Argo CD voltou a conseguir comparar os manifestos do Git com os recursos do cluster.
Estado atual
Application	Sync	Health	Interpretação
platform-root	Synced	Healthy	Funcionando
harbor	OutOfSync	Healthy	Recursos saudáveis, mas diferentes do Git
sonarqube	OutOfSync	Missing	Recursos esperados ainda não encontrados
traefik	OutOfSync	Progressing	Recursos ainda não totalmente saudáveis

Próximo passo: sincronização manual
Como mantivemos o Auto Sync desabilitado nas três Applications, OutOfSync é esperado até executarmos o Sync manual.