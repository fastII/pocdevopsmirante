# ARC no Minikube — Kubernetes Secret nativo, sem External Secrets

Adaptado do ZIP original (ARC EKS/Argo CD) para a POC local. Helm charts `gha-runner-scale-set-controller` e `gha-runner-scale-set` na versao **0.14.2**, a mesma do material recebido. Verifique a disponibilidade da versao no registry antes da instalacao.

## 0. Pre-requisitos

- `kubectl`, `helm`, Minikube funcional e acesso de saida HTTPS ao GitHub e GHCR.
- GitHub App instalado na organizacao `bs2-bet` com **Organization permissions > Self-hosted runners: Read and write**.
- Ter `App ID`, `Installation ID` e o arquivo privado `.pem` do GitHub App.
- O runner executa workflows no seu Mac corporativo: use apenas repositorios e jobs confiaveis.
- O DinD exige `privileged`; a POC nao deve ser considerada isolada para workloads nao confiaveis.

## 1. Criar namespaces

```bash
kubectl apply -f manifests/namespaces.yaml
```

## 2. Criar o Kubernetes Secret (sem External Secrets)

Execute no terminal local; substitua os IDs e caminho pelo seu GitHub App. **Nao coloque a chave no Git nem em YAML versionado.**

```bash
read -r -p 'GitHub App ID: ' GH_APP_ID
read -r -p 'GitHub Installation ID: ' GH_INSTALLATION_ID
read -r -p 'Caminho do arquivo .pem: ' GH_APP_PEM
kubectl -n arc-runners create secret generic arc-github-app \
  --from-literal=github_app_id="$GH_APP_ID" \
  --from-literal=github_app_installation_id="$GH_INSTALLATION_ID" \
  --from-file=github_app_private_key="$GH_APP_PEM"
unset GH_APP_ID GH_INSTALLATION_ID GH_APP_PEM
```

Chaves exigidas: `github_app_id`, `github_app_installation_id`, `github_app_private_key`. Confira apenas os nomes das chaves:

```bash
kubectl -n arc-runners get secret arc-github-app -o json | jq -r '.data | keys[]'
```

## 3. Instalar controller ARC

```bash
helm install arc \
  --namespace arc-systems \
  --version 0.14.2 \
  -f helm/controller-values.yaml \
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller

kubectl -n arc-systems get deployments,serviceaccounts,pods
```

Confirme que existe o ServiceAccount `arc-gha-rs-controller`. Se o nome real for diferente, ajuste `controllerServiceAccount.name` no values do scale set.

## 4. Instalar runner scale set

```bash
helm install arc-bs2bet \
  --namespace arc-runners \
  --version 0.14.2 \
  -f helm/scaleset-values.yaml \
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set
```

## 5. Validar

```bash
kubectl -n arc-systems get pods
kubectl -n arc-runners get autoscalingrunnersets.actions.github.com
kubectl -n arc-systems get autoscalinglisteners.actions.github.com
kubectl -n arc-systems logs deploy/arc-gha-rs-controller --tail=100
kubectl -n arc-runners get pods -w
```

Em um repositorio autorizado da org, adicione `examples/test-runner.yaml` como `.github/workflows/test-arc.yaml` e execute **Actions > Test ARC Minikube > Run workflow**. O job `runs-on: arc-bs2bet` deve criar um pod efemero. `minRunners: 0` significa que nao havera pods de runner parados; o listener permanece.

## 6. NetworkPolicy opcional

```bash
kubectl apply -f manifests/networkpolicy.yaml
```

A aplicacao efetiva depende do CNI suportar NetworkPolicy. A regra original de egress foi omitida porque poderia bloquear trafego necessario no Minikube.

## 7. Operacao e troubleshooting

```bash
helm list -A | grep -E 'arc|runner'
kubectl -n arc-runners describe autoscalingrunnerset arc-bs2bet
kubectl -n arc-systems get pods
kubectl -n arc-runners get pods -w
kubectl -n arc-systems logs deploy/arc-gha-rs-controller --tail=200
```

Se o runner nao registrar: conferir permissao de org do GitHub App, IDs, instalacao do App e acesso HTTPS de saida. Se o runner ficar Pending/OOMKilled: reduzir `maxRunners` para 1 e conferir memoria livre. O `docker version` do exemplo exige DinD ativo.

## 8. Atualizar valores

```bash
helm upgrade arc-bs2bet \
  --namespace arc-runners --version 0.14.2 \
  -f helm/scaleset-values.yaml \
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set
```

## 9. Desinstalar

```bash
helm uninstall arc-bs2bet -n arc-runners
helm uninstall arc -n arc-systems
# Apenas se desejar apagar credenciais e recursos restantes:
# kubectl -n arc-runners delete secret arc-github-app
# kubectl delete namespace arc-runners arc-systems
```

## Diferencas em relacao ao ZIP original

- Retirados ExternalSecret, SecretStore, IRSA, AWS Secrets Manager e referencias ao endpoint do EKS.
- Secret do GitHub App criado diretamente no Kubernetes.
- `maxRunners: 20` reduzido para 2; DinD configurado pelo chart, sem sidecar customizado de 4–6 GiB.
- Removido digest fixo do runner do arquivo original (atualizacao deve ser controlada em ambiente de producao).
- Instalacao via Helm CLI para validacao inicial; pode ser migrada para Argo CD posteriormente.
- NetworkPolicy ingress opcional; egress restritivo do EKS nao foi transportado automaticamente.
