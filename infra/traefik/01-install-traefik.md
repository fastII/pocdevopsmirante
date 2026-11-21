# Instalar Traefik e Gateway API

[Voltar ao runbook](../../RUNBOOK.md)

## 1. Preparar Gateway API e TLS

No cluster novo, instale os CRDs do canal Standard. A versão 1.4.1 segue o registro da POC, cujo diagnóstico anterior usou o bundle Experimental. O provider atual usa `experimentalChannel: false`. Em um cluster existente, confira a versão e o canal antes de substituir CRDs. [Gateway API](https://gateway-api.sigs.k8s.io/guides/getting-started/)

~~~bash
kubectl apply --server-side \
  -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.1/standard-install.yaml
kubectl wait --for=condition=Established --timeout=120s \
  crd/gateways.gateway.networking.k8s.io \
  crd/httproutes.gateway.networking.k8s.io
~~~

Crie o Secret TLS no namespace `traefik` seguindo o [guia de certificados](../certs/01-install-certs.md).

## 2. Sincronizar pelo Argo CD

O `platform-root` cria a Application `traefik`. Se estiver fazendo o bootstrap manual, sincronize a filha e aguarde o Gateway. [App of Apps](../../RUNBOOK.md#3-provisionar-as-aplicações-com-app-of-apps)

~~~bash
argocd app sync traefik
argocd app wait traefik --sync --health --timeout 300
kubectl -n traefik get gateway,svc,pods
kubectl -n traefik describe gateway traefik-gateway
~~~

O values configura listeners HTTP e HTTPS, redirecionamento para HTTPS, rotas entre namespaces e resources de `100m / 128Mi` de request e `300m / 256Mi` de limite. [Values do Traefik](../gitops/helm-values/traefik.yaml)

## 3. Acessar pelo macOS

~~~bash
minikube service traefik -n traefik --url
~~~

Mantenha o comando em execução e identifique o encaminhamento do listener HTTPS. As portas locais variam. Após sincronizar as rotas, use `https://argocd.localhost:<porta-https>`, `https://harbor.localhost:<porta-https>` ou `https://sonarqube.localhost:<porta-https>`. O `minikube tunnel` tentou abrir as portas privilegiadas 80 e 443 no Mac da POC e pediu sudo. [Acesso a serviços no Minikube](https://minikube.sigs.k8s.io/docs/handbook/accessing/)

Em caso de erro, confira `Programmed` no Gateway, `Accepted` e `ResolvedRefs` no HTTPRoute e os endpoints do serviço de destino.

~~~bash
kubectl get httproute -A
kubectl -n argocd describe httproute argocd
kubectl -n argocd get endpointslices
~~~
