# Instalar Traefik e Gateway API

[Voltar ao README](../../README.md)

## 1. Preparar Gateway API e TLS

Instale os CRDs da Gateway API v1.6.3 do canal Standard. Esse pacote fornece `TLSRoute` na API `v1`, que o Traefik consulta mesmo com `experimentalChannel: false`. As rotas HTTPS da POC usam `HTTPRoute`. [Gateway API do Traefik](https://doc.traefik.io/traefik/v3.7/reference/install-configuration/providers/kubernetes/kubernetes-gateway/)

~~~bash
kubectl apply --server-side \
  -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.3/standard-install.yaml
kubectl wait --for=condition=Established --timeout=120s \
  crd/gatewayclasses.gateway.networking.k8s.io \
  crd/gateways.gateway.networking.k8s.io \
  crd/httproutes.gateway.networking.k8s.io \
  crd/tlsroutes.gateway.networking.k8s.io
~~~

Crie o Secret TLS no namespace `traefik` seguindo o [guia de certificados](../certs/01-install-certs.md).

## 2. Sincronizar pelo Argo CD

O `platform-root` cria a Application `traefik`. Aguarde o sync automático e verifique o Deployment e o Gateway. [App-of-Apps](../../README.md#4-aplicar-app-of-apps-e-aguardar-a-plataforma)

~~~bash
argocd app wait traefik --sync --timeout 480
kubectl -n traefik rollout status deployment/traefik --timeout=300s
kubectl wait --for=condition=Accepted gatewayclass/traefik --timeout=180s
kubectl -n traefik wait --for=condition=Programmed gateway/traefik-gateway --timeout=180s
kubectl -n traefik get gateway,svc,pods
kubectl -n traefik describe gateway traefik-gateway
~~~

Os values configuram listeners nas portas HTTP `80` e HTTPS `443`, rotas entre namespaces e resources de `100m / 128Mi` de request e `300m / 256Mi` de limite. O listener HTTP recebe a rota do SonarQube local sem redirecionamento global para HTTPS. [Values do Traefik](../gitops/helm-values/traefik.yaml) · [Rota HTTP do SonarQube](../gitops/routes/sonarqube-http.yaml)

## 3. Acessar pelo macOS

~~~bash
minikube service traefik -n traefik --url
~~~

Mantenha o comando em execução e identifique o encaminhamento do listener HTTPS. As portas locais variam. Após sincronizar as rotas, use `https://argocd.localhost:<porta-https>`, `https://harbor.localhost:<porta-https>` ou `https://sonarqube.localhost:<porta-https>`. Para HTTP local, use `http://sonarqube.localhost:8080` com `--servir`. O `minikube tunnel` tentou abrir as portas privilegiadas 80 e 443 no Mac da POC e pediu sudo. [Acesso a serviços no Minikube](https://minikube.sigs.k8s.io/docs/handbook/accessing/)

Em caso de erro, confira `Programmed` no Gateway, `Accepted` e `ResolvedRefs` no HTTPRoute e os endpoints do serviço de destino.

~~~bash
kubectl get httproute -A
kubectl -n argocd describe httproute argocd
kubectl -n argocd get endpointslices
~~~
