# Observabilidade GitOps no Minikube — Argo CD + Traefik Gateway API

[Voltar ao runbook](../../../RUNBOOK.md)

## Objetivo

Provisionar **kube-prometheus-stack** (Prometheus, Alertmanager, Grafana, kube-state-metrics e node-exporter), **Loki** e **Grafana Alloy** pelo Argo CD. **Somente Grafana** terá HTTPRoute. Todos os demais Services permanecem `ClusterIP`.

```text
Git repo -> Argo CD -> Helm charts -> namespace observability
                              |-> Prometheus -> métricas do Kubernetes
                              |-> Alertmanager (interno)
                              |-> Grafana (ClusterIP) <- HTTPRoute grafana.localhost
                              |-> Loki (interno) <- Alloy DaemonSet <- logs de pods
Traefik Gateway (namespace traefik) -> HTTPRoute -> Grafana
```

## Pré-requisitos

- Minikube e Argo CD operacionais
- Traefik Gateway `traefik/traefik-gateway` com listener HTTPS `websecure` e `allowedRoutes` aceitando o namespace `observability`
- CRDs Gateway API instaladas; `kubectl get gateway -n traefik`
- StorageClass padrão para o PVC do Loki; `kubectl get storageclass`
- Memória disponível no cluster; conferir `kubectl top nodes` e `kubectl describe node minikube`
- Repositório Git **seu**, acessível pelo Argo CD, contendo estes arquivos

## 1. Versionar arquivos no Git

As Applications usam a branch `main` deste repositório. Confirme a versão publicada e execute os comandos desta página a partir de `infra/gitops/observability-minikube/`.

> O Argo CD usa `sources` com `$values`: o primeiro source instala o chart Helm e o segundo lê os values do seu Git. Não é necessário `helm install`.

## 2. Criar namespace e credencial do Grafana

Execute este bloco no Bash.

```bash
kubectl create namespace observability --dry-run=client -o yaml | kubectl apply -f -
read -rs -p 'Senha do Grafana: ' GRAFANA_PASSWORD

kubectl create secret generic grafana-admin \
  --namespace observability \
  --from-literal=admin-user=admin \
  --from-literal=admin-password="$GRAFANA_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

unset GRAFANA_PASSWORD
```

Guarde a senha no gerenciador de credenciais. Mantenha Secrets com senhas fora do Git.

## 3. Criar AppProject e Applications

```bash
kubectl apply -f argocd/project.yaml
kubectl apply -f argocd/prometheus.yaml
kubectl apply -f argocd/loki.yaml
kubectl apply -f argocd/alloy.yaml
```

Aguarde o Prometheus/Grafana e Loki ficarem saudáveis antes de validar Alloy. As Applications são gerenciadas pelo Argo CD e se reconciliam com o Git.

## 4. Publicar somente o Grafana

Depois que o Service `kube-prometheus-stack-grafana` existir:

```bash
kubectl -n observability get svc
kubectl apply -f argocd/grafana-route.yaml
kubectl -n observability get httproute grafana -o yaml
```

O `HTTPRoute` está em `manifests/grafana-httproute.yaml` e referencia o Gateway existente `traefik/traefik-gateway`, listener `websecure`, hostname `grafana.localhost`, Service `kube-prometheus-stack-grafana:80`.

**Importante:** `HTTPRoute` cross-namespace -> Gateway requer que o listener permita rotas do namespace `observability`. Se `Accepted=False`, verifique `kubectl describe httproute grafana -n observability` e a política `allowedRoutes` do Gateway.

## 5. Acesso no Mac corporativo sem sudo

Como o driver é Docker no macOS e não há acesso sudo, utilize o mecanismo já validado na POC:

```bash
minikube service traefik -n traefik --url
```

Mantenha o terminal aberto. Identifique a **segunda porta** correspondente ao HTTPS (confirme por teste; muda a cada execução):

```bash
curl -kI --noproxy '*' https://grafana.localhost:PORTA_HTTPS
```

Acesse `https://grafana.localhost:PORTA_HTTPS` no navegador. O certificado self-signed pode gerar aviso. **Não há HTTPRoute para Prometheus, Loki ou Alertmanager.**

## 6. Validação operacional

```bash
kubectl get applications -n argocd | grep obs-
kubectl get pods,pvc,svc -n observability
kubectl get servicemonitors,prometheusrules -n observability
kubectl describe httproute grafana -n observability
kubectl logs -n observability -l app.kubernetes.io/name=alloy --tail=50
```

No Grafana, confira datasources **Prometheus** e **Loki**. Execute PromQL `up` e uma consulta LogQL `{namespace="argocd"}`. Se a consulta de logs não retornar resultados, verifique se o Alloy lê `/var/log/pods` e alcança `loki-gateway`.

## 7. Dimensionamento e limitações

O values do kube-prometheus-stack foi consolidado para eliminar chaves duplicadas. Prometheus reserva 200m / 640Mi e tem limite de 500m / 1200Mi. Grafana, sidecars, Operator, Alertmanager e exporters também têm resources. Loki e Alloy definem orçamentos para os serviços principais e auxiliares. [Prometheus e Grafana](values/kube-prometheus-stack.yaml) · [Loki](values/loki.yaml) · [Alloy](values/alloy.yaml) · [Evidência da auditoria](../../../evidence/Dificuldades.md)

- Configuração para **POC**, não produção; Prometheus com retenção de 2 dias, Loki 48 horas, Loki PVC de 5 GiB, Grafana sem persistência.
- No Minikube de nó único, métricas do control plane como etcd/scheduler/controller-manager foram desabilitadas para evitar targets não acessíveis.
- O Alloy monta logs do host e roda como DaemonSet; revise políticas corporativas antes de usar.
- O chart do Loki pode exigir ajustes conforme a versão; se `obs-loki` falhar, valide o chart efetivo e seus valores com `helm show values`.
- `AppProject` usa whitelist ampla para permitir CRDs/ClusterRoles do Prometheus Operator: **restrinja antes de produção**.
- O acesso ao Grafana é via TLS self-signed existente no Gateway. Configure autenticação/SSO antes de compartilhar.

## 8. Troubleshooting

```bash
kubectl -n argocd describe application obs-prometheus
kubectl -n argocd describe application obs-loki
kubectl -n argocd describe application obs-alloy
kubectl -n observability get events --sort-by=.lastTimestamp | tail -30
kubectl -n observability get httproute grafana -o jsonpath='{.status.parents}'
```

Se o Argo CD exibir `ComparisonError`, confirme a URL do seu repositório Git, acesso do Argo CD, revisão `main`, chart OCI/Helm e caminho de `$values`. Se o HTTPRoute estiver `Accepted=True` e `ResolvedRefs=True` mas houver `404`, valide o hostname enviado pelo navegador. Se houver `502/503`, confira o Service e os endpoints do Grafana.
