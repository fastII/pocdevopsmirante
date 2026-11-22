# Rollback da POCAPP

[Voltar ao runbook](../RUNBOOK.md)

O workflow manual Rollback POCAPP troca apenas a chave image.tag de helm/pocapp/values.yaml e publica um commit em main. O Git armazena o estado desejado e o Argo CD renderiza e aplica o chart. [Workflow de rollback](../.github/workflows/rollback-pocapp.yaml)

| Cenário | Procedimento |
| --- | --- |
| Restaurar uma imagem do mesmo repositório Harbor | Executar o workflow manual com a tag anterior |
| Restaurar outros values, templates ou o repositório da imagem | Reverter a mudança em Git, por PR, e acompanhar o sync |
| Recuperar temporariamente pelo histórico do Argo CD | Desabilitar auto-sync de forma coordenada, selecionar a revisão e registrar no Git o estado que deve permanecer |

A reversão pelo histórico do Argo CD exige auto-sync desabilitado. O selfHeal e o platform-root podem reaplicar a configuração versionada. O Helm atua como renderizador neste fluxo GitOps. [Política de sincronização do Argo CD](https://argo-cd.readthedocs.io/en/release-3.2/user-guide/auto_sync/)

## Executar pelo GitHub Actions

1. Confirme no Harbor a tag da última versão saudável, no repositório configurado em image.repository. Registre a tag atual para poder restaurá-la.
2. Confirme a disponibilidade de um runner `self-hosted` e a permissão do bot para publicar em main. Se a proteção da branch impedir o push direto, faça a troca de tag por PR.
3. Abra **Actions → Rollback POCAPP → Run workflow**, informe a tag em **image_tag** e acompanhe o job. O workflow ainda baixa o yq para Linux amd64. O runner do macOS ARM64 precisa de um ajuste no workflow para usar o binário correspondente, ou um yq v4 já instalado no PATH.
4. Confira o commit em main e aguarde o Argo CD. O commit do workflow usa o token automático do GitHub Actions, que normalmente não dispara outro workflow de push. Se a troca for feita por PR ou com outra credencial, confira se o CI/CD publica uma nova tag e sobrescreve a seleção. [Comportamento do GITHUB_TOKEN](https://docs.github.com/en/actions/concepts/security/github_token)
5. Confira a imagem efetiva e valide o endpoint. Mudanças de configuração e dados exigem recuperação própria.

~~~bash
argocd app get pocapp --refresh
argocd app wait pocapp --sync --health --timeout 300
kubectl -n apps rollout status deployment/pocapp --timeout=180s
kubectl -n apps get deployment pocapp \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
kubectl -n apps port-forward svc/pocapp 3000:80
~~~

Em outro terminal, valide com `curl -fsS http://127.0.0.1:3000/healthz`.
