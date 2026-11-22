# Rollback da POCAPP

[Voltar ao README](../README.md)

O workflow manual Rollback POCAPP troca apenas a chave image.tag de helm/pocapp/values.yaml e publica um commit em main. O Git armazena o estado desejado e o Argo CD renderiza e aplica o chart. [Workflow de rollback](../.github/workflows/rollback-pocapp.yaml)

| Cenário | Procedimento |
| --- | --- |
| Restaurar uma imagem do mesmo repositório Harbor | Executar o workflow manual com a tag anterior |
| Interromper um canary ativo | Restaurar o tráfego para a versão estável pelo Git e desabilitar o canary depois da validação. [Canary com Traefik](../README.md#canary-com-traefik) |
| Restaurar outros values, templates ou o repositório da imagem | Reverter a mudança em Git, por PR, e acompanhar o sync |
| Recuperar temporariamente pelo histórico do Argo CD | Desabilitar auto-sync de forma coordenada, selecionar a revisão e registrar no Git o estado que deve permanecer |

A reversão pelo histórico do Argo CD exige auto-sync desabilitado. O selfHeal e o platform-root podem reaplicar a configuração versionada. O Helm atua como renderizador neste fluxo GitOps. [Política de sincronização do Argo CD](https://argo-cd.readthedocs.io/en/release-3.2/user-guide/auto_sync/)

## Executar pelo GitHub Actions

1. Confirme no Harbor a tag da última versão saudável, no repositório configurado em image.repository. Registre a tag atual para poder restaurá-la.
2. Confirme que `canary.enabled` está desabilitado e que o bot pode publicar em `main`. Se a proteção da branch impedir o push direto, faça a troca de tag por PR.
3. Abra **Actions → Rollback POCAPP → Run workflow**, informe a tag em **image_tag** e acompanhe o job no runner hospedado `ubuntu-latest`.
4. Confira o commit em `main` e aguarde o Argo CD. Para uma troca por PR, limite o diff ao `helm/pocapp/values.yaml` para o CI/CD não publicar outra imagem durante o rollback.
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
