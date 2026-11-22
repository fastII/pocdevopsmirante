# Instalar Harbor

[Voltar ao README](../../README.md)

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

Após o `platform-root` criar a Application `harbor`, aguarde o sync automático.

~~~bash
argocd app wait harbor --sync --health --timeout 600
kubectl -n harbor get pods,pvc,svc
~~~

O chart 1.19.4 usa banco e Redis internos e PVCs. O Trivy do Harbor está desabilitado. O scan da imagem da POCAPP roda no GitHub Actions. Os values incluem requests e limits para Nginx, banco e init containers, Core, Jobservice e os dois containers do Registry. [Values do Harbor](../gitops/helm-values/harbor.yaml)

## 3. Preparar o registry para a aplicação

1. Aguarde `platform-routes` e valide a rota do Harbor. [Instalação manual](../../README.md#4-aplicar-app-of-apps-e-aguardar-a-plataforma)
2. Crie o projeto de imagens e uma credencial de publicação. Verifique que `externalURL` corresponde ao endpoint canônico usado pelos clientes, inclusive no fluxo de autenticação.
3. Confirme DNS, acesso HTTPS e confiança no certificado a partir do runner que publica e do runtime do Minikube que puxa a imagem. Para projeto privado, configure uma credencial de pull no namespace `apps` e referencie-a nos values da POCAPP.
4. Para diagnosticar `ImagePullBackOff`, confira os eventos do pod, a referência da imagem e as credenciais do registry.

Para a interface no navegador, abra `kubectl --context minikube -n traefik port-forward svc/traefik 8443:443` e use `https://harbor.localhost:8443`. O push em modo `harbor` roda no runner `self-hosted`. Use `HARBOR_REGISTRY` com o endereço canônico do registry. O Docker do runner e o containerd do nó precisam resolver esse endereço e confiar no certificado. O endpoint de token anunciado pelo Harbor usa `externalURL`, atualmente `https://harbor.local`. Enquanto o endereço canônico estiver indisponível, use `minikube-local` para carregar o artefato diretamente no perfil. [CI/CD da POCAPP](../../README.md#configurar-o-cicd)
