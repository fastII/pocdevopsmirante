# Instalar Harbor

[Voltar ao runbook](../../RUNBOOK.md)

## 1. Preparar o namespace e a senha

Escolha a senha de administrador e informe-a no prompt. Execute no shell Bash.

~~~bash
kubectl create namespace harbor --dry-run=client -o yaml | kubectl apply -f -
read -rs -p 'Senha do Harbor: ' HARBOR_ADMIN_PASSWORD
kubectl -n harbor create secret generic harbor-admin \
  --from-literal=HARBOR_ADMIN_PASSWORD="$HARBOR_ADMIN_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -
unset HARBOR_ADMIN_PASSWORD
~~~

## 2. Instalar pelo Argo CD

~~~bash
kubectl apply -f infra/gitops/projects/platform-registry.yaml
kubectl apply -f infra/gitops/applications/harbor.yaml
argocd app sync harbor
argocd app wait harbor --sync --health --timeout 600
kubectl -n harbor get pods,pvc,svc
~~~

O chart 1.19.4 usa banco e Redis internos, PVCs e Trivy. Os values incluem requests e limits para Nginx, banco e init containers, Trivy, Core, Jobservice e os dois containers do Registry. As chaves corretas do chart são `registry.registry.resources` e `registry.controller.resources`. [Values do Harbor](../gitops/helm-values/harbor.yaml)

## 3. Preparar o registry para a aplicação

1. Sincronize `platform-routes` pelo runbook e valide a rota do Harbor.
2. Crie o projeto de imagens e uma credencial de publicação. Verifique que `externalURL` corresponde ao endpoint canônico usado pelos clientes, inclusive no fluxo de autenticação.
3. Confirme DNS, acesso HTTPS e confiança no certificado a partir do runner que publica e do runtime do Minikube que puxa a imagem. Para projeto privado, configure uma credencial de pull no namespace `apps` e referencie-a nos values da POCAPP.
4. Para diagnosticar `ImagePullBackOff`, confira os eventos do pod, a referência da imagem e as credenciais do registry.

O túnel local de navegador do Traefik atende o Mac. O job de push atual usa `ubuntu-latest` e precisa de um endpoint do Harbor alcançável a partir do GitHub. [Workflow de CI/CD](../../.github/workflows/pocapp-ci-cd.yaml)
