# Instalar Kyverno via Argo CD

[Voltar ao runbook](../../RUNBOOK.md)

## 1. Instalar os controladores

O `platform-root` cria `kyverno` e `kyverno-policies`. O chart 3.10.0 usa uma réplica por controlador, auto-sync e Server-Side Apply.

~~~bash
argocd app wait kyverno --sync --health --timeout 300
kubectl -n kyverno get pods,deployments
kubectl get crds -o name | grep kyverno
kubectl get validatingwebhookconfigurations
~~~

Os resources ficam em helm.valuesObject. O admission controller usa 100m / 160Mi de request e 500m / 384Mi de limite. Background e cleanup usam 100m / 128Mi e 300m / 256Mi. Reports usa 100m / 96Mi e 300m / 192Mi. [Application Kyverno](../gitops/applications/kyverno.yaml)

## 2. Sincronizar a política em Audit

Confirme que ValidatingPolicy está disponível após a instalação dos controladores. A política audita imagens sem tag explícita ou com :latest em pods de apps, incluindo init e ephemeral containers. [Política versionada](../security/kyverno/disallow-latest.yaml)

~~~bash
kubectl api-resources --api-group=policies.kyverno.io
argocd app diff kyverno-policies
argocd app sync kyverno-policies
argocd app wait kyverno-policies --sync --health --timeout 180
kubectl get validatingpolicies.policies.kyverno.io
~~~

Confira os relatórios e teste a admissão em apps antes de propor mudança de Audit para Deny. A verificação de assinaturas Cosign requer uma política específica, identidade de assinatura e confiança no Harbor.

## 3. Diagnosticar

~~~bash
kubectl -n argocd describe application kyverno
kubectl -n kyverno get events --sort-by=.lastTimestamp
kubectl -n kyverno top pods
~~~

Se o sync indicar API ausente, confira os CRDs e a saúde do admission controller. Se indicar pasta inexistente, confira a branch remota e o caminho infra/security/kyverno configurado na Application. [Application de políticas](../gitops/applications/kyverno-policies.yaml)
