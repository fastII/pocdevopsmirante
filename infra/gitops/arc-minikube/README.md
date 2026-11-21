# ARC via Argo CD — Minikube sem External Secrets

[Voltar ao runbook](../../../RUNBOOK.md) · [Configurar a GitHub App](01-install-arc-github.md)

O script de provisionamento já instala o ARC após a plataforma. Use os passos abaixo para instalar o ARC separadamente, por exemplo após provisionar com `--sem-arc`. [Provisionamento pelo script](../../../RUNBOOK.md#provisionamento-pelo-script)

## 1. Preparar o repositório OCI

O chart 0.14.2 usa a URL e o ServiceAccount definidos nas Applications. Execute os comandos desta página a partir de `infra/gitops/arc-minikube/`.

Registre o repositório de charts no Argo CD como Helm OCI. [Repositórios Helm OCI no Argo CD](https://argo-cd.readthedocs.io/en/stable/user-guide/private-repositories/#helm)

```bash
argocd repo add ghcr.io/actions/actions-runner-controller-charts \
  --type helm --enable-oci
```

## 2. Bootstrap (somente namespaces e Secret fora do Argo)

```bash
kubectl apply -f manifests/namespaces.yaml
kubectl -n arc-runners create secret generic arc-github-app \
  --from-literal=github_app_id='APP_ID' \
  --from-literal=github_app_installation_id='INSTALLATION_ID' \
  --from-file=github_app_private_key='/caminho/seguro/app.pem' \
  --dry-run=client -o yaml | kubectl apply -f -
```

## 3. Instalar por Argo CD (sem helm install)

```bash
kubectl apply -f argo/project.yaml
kubectl apply -f argo/controller.yaml
argocd app wait arc-controller --sync --health --timeout 300
kubectl -n arc-systems get pods
kubectl apply -f argo/scaleset.yaml
argocd app wait arc-runner-minikube --sync --health --timeout 300
kubectl -n arc-runners get autoscalingrunnersets,pods
kubectl -n arc-systems get autoscalinglisteners,pods
```

O bootstrap raiz cobre `infra/gitops/applications/`. Aplique as Applications desta pasta quando seus manifests mudarem. Os `valuesObject` das Applications são os valores efetivos. Os arquivos em `helm/` são exemplos para instalações Helm separadas.

## 4. Validar

Copie `examples/test-runner.yaml` para `.github/workflows/arc-smoke.yaml` no repositorio alvo e execute `workflow_dispatch`. Como `minRunners: 0`, nenhum pod runner ocioso e esperado antes de um job.

## 5. Cuidados

- DinD usa containers privilegiados; executar apenas workflows confiaveis.
- Nao versionar o PEM, tokens, nem manifests com credenciais literais.
- `containerMode: dind` depende do suporte do chart e de recursos livres no Minikube.
- Em um Docker Desktop limitado a 8 GiB, mantenha `maxRunners: 1`; o orçamento
  do pod limita runner + DinD a 1,5 CPU e 2 GiB.
- Em caso de falha de autenticação, confira o escopo de instalação da GitHub App, os IDs e o Secret.
- O controller usa requests de 50m / 64Mi e limits de 250m / 256Mi. O listener usa 25m / 64Mi e 200m / 256Mi. [Controller](argo/controller.yaml) · [Scale set](argo/scaleset.yaml)
