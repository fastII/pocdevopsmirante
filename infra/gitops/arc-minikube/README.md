# ARC via Argo CD — Minikube sem External Secrets

Adaptado do arc.zip original: `argo/project.yaml`, `argo/controller.yaml`, `argo/scaleset.yaml` e namespaces. Removidos ExternalSecret, SecretStore, IRSA, endpoints EKS e dependencias AWS. **Nao coloque a chave privada do GitHub App no Git.**

## 1. Ajustes obrigatorios

- Em `argo/scaleset.yaml`, trocar `https://github.com/fastII/SEU_REPOSITORIO` pela URL real do repositorio no qual instalou o GitHub App. Para runners de organizacao, usar URL da organizacao e permissoes correspondentes.
- Versao 0.14.2 foi preservada do original, sem verificacao online de disponibilidade.
- O chart pode exigir adequacoes de versao e do nome do ServiceAccount; verifique antes do sync.

## 2. Bootstrap (somente namespaces e Secret fora do Argo)

```bash
kubectl apply -f manifests/namespaces.yaml
kubectl -n arc-runners create secret generic arc-github-app \
  --from-literal=github_app_id='APP_ID' \
  --from-literal=github_app_installation_id='INSTALLATION_ID' \
  --from-file=github_app_private_key='/caminho/seguro/app.pem'
```

## 3. Instalar por Argo CD (sem helm install)

```bash
kubectl apply -f argo/project.yaml
kubectl apply -f argo/controller.yaml
kubectl -n argocd get applications arc-controller -w
kubectl -n arc-systems get pods
# Somente apos o controller estar saudavel:
kubectl apply -f argo/scaleset.yaml
kubectl -n argocd get applications arc-runner-minikube -w
kubectl -n arc-runners get autoscalingrunnersets,autoscalinglisteners,pods
```

**GitOps permanente:** commitar `argo/*.yaml` e `manifests/namespaces.yaml` no repositorio GitOps e incluí-los no bootstrap/ApplicationSet raiz ja existente. `kubectl apply` acima e somente o bootstrap inicial. Nao incluir o Secret no Git.

## 4. Validar

Copie `examples/test-runner.yaml` para `.github/workflows/arc-smoke.yaml` no repositorio alvo e execute `workflow_dispatch`. Como `minRunners: 0`, nenhum pod runner ocioso e esperado antes de um job.

## 5. Cuidados

- DinD usa containers privilegiados; executar apenas workflows confiaveis.
- Nao versionar o PEM, tokens, nem manifests com credenciais literais.
- `containerMode: dind` depende do suporte do chart e de recursos livres no Minikube.
- Em caso de falha de autenticacao, confira escopo de instalacao da GitHub App e permissoes.
