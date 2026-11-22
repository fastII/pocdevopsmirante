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

Com `--servir` ativo, use `http://harbor.localhost:8080` ou `https://harbor.localhost:8443` no navegador.

No Docker Desktop, use `host.docker.internal:8081` para o push e o pull da POC. Inclua esse endereço em `insecure-registries` no Docker Engine e use `HARBOR_REGISTRY=host.docker.internal:8081` e `HARBOR_PROJECT=poc` no GitHub. O provisionador mantém o encaminhamento direto ao Service `harbor` em loopback enquanto o Argo CD sincroniza. O containerd usa HTTP somente nesse endereço. Para diagnosticar o registry, o `401` abaixo deve vir acompanhado do endereço de token em `http://host.docker.internal:8081/service/token`.

~~~bash
curl --noproxy '*' -i -H 'Host: host.docker.internal:8081' http://127.0.0.1:8081/v2/
~~~

O projeto público libera pull anônimo. Configure `HARBOR_USERNAME` e `HARBOR_PASSWORD` para publicar com uma conta autorizada a escrever em `poc`. O workflow verifica o pull pelo Minikube após publicar em um projeto público local. [CI/CD da POCAPP](../../README.md#configurar-o-cicd)
