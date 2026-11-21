# Observabilidade no Minikube

O script de provisionamento instala Grafana, Prometheus, Alertmanager, Loki e Alloy. As Applications `obs-*` têm bootstrap próprio e usam os values da branch `main`. [Runbook de provisionamento](../../../RUNBOOK.md#provisionamento-pelo-script)

Apenas o Grafana recebe HTTPRoute **dentro da observabilidade**. Prometheus, Alertmanager e Loki são acessados internamente. O Alloy coleta logs dos pods e envia ao Loki.

## Acessar e validar

Com o script rodando com `--servir`, abra **https://grafana.localhost:8443**. Para abrir o encaminhamento depois, rode o comando abaixo em um terminal separado. O certificado local é autoassinado.

~~~bash
kubectl --context minikube -n traefik port-forward svc/traefik 8443:443
~~~

No Grafana, consulte `up` no Prometheus e `{namespace="argocd"}` no Loki. Para diagnosticar falhas, confira as Applications, os pods e os PVCs. Na rota do Grafana, procure `Accepted=True` e `ResolvedRefs=True`.

~~~bash
kubectl --context minikube -n argocd get applications obs-prometheus obs-loki obs-alloy obs-grafana-route
kubectl --context minikube -n observability get pods,pvc,svc
kubectl --context minikube -n observability describe httproute grafana
kubectl --context minikube -n observability logs -l app.kubernetes.io/name=alloy --tail=50
~~~

O Prometheus usa intervalos padrão de 60s e retenção de 2 dias. O Loki está configurado com retenção de 48h e PVC de 5 GiB. Os orçamentos de CPU e memória estão nos values. [Prometheus e Grafana](values/kube-prometheus-stack.yaml) · [Loki](values/loki.yaml) · [Alloy](values/alloy.yaml) · [Pressão de memória](../../../evidence/Dificuldades.md)

<details>
<summary>Instalar somente a observabilidade manualmente</summary>

Use este fluxo se pulou a observabilidade no primeiro provisionamento. Confirme o Gateway `traefik/traefik-gateway` com listener `websecure` e uma StorageClass padrão. Execute na raiz do repositório em Bash, com a CLI do Argo CD autenticada.

~~~bash
kubectl create namespace observability --dry-run=client -o yaml | kubectl apply -f -
read -rs -p 'Senha do Grafana: ' GRAFANA_PASSWORD
kubectl -n observability create secret generic grafana-admin \
  --from-literal=admin-user=admin --from-literal=admin-password="$GRAFANA_PASSWORD"
unset GRAFANA_PASSWORD

OBS=infra/gitops/observability-minikube/argocd
kubectl apply -f "$OBS/project.yaml" -f "$OBS/prometheus.yaml" -f "$OBS/loki.yaml"
argocd app wait obs-prometheus obs-loki --sync --health --timeout 600
kubectl apply -f "$OBS/alloy.yaml" -f "$OBS/grafana-route.yaml"
argocd app wait obs-alloy --sync --health --timeout 300
~~~

Se o Secret `grafana-admin` já existir, reutilize a credencial. A Application `obs-grafana-route` lê o [HTTPRoute do Grafana](manifests/grafana-httproute.yaml), que aponta para `kube-prometheus-stack-grafana:80`.

</details>
