# Rollback da POCAPP

[Voltar ao README](../README.md)

O workflow manual **Rollback POCAPP** restaura a referência da imagem estável em `helm/pocapp/values.yaml` e publica um commit em `main`. A tag é obrigatória. O repositório e a política de pull são opcionais e preservam os valores atuais quando omitidos. O Argo CD reconcilia a referência publicada. [Workflow de rollback](../.github/workflows/rollback-pocapp.yaml)

| Cenário | Procedimento |
| --- | --- |
| Restaurar uma imagem do mesmo repositório | Executar o workflow com `image_tag` e manter os demais valores |
| Interromper um canary ativo | Restaurar o tráfego para a versão estável pelo Git e desabilitar o canary depois da validação. [Canary com Traefik](../README.md#canary-com-traefik) |
| Restaurar uma imagem de outro repositório ou modo de entrega | Informar `image_repository`, `image_tag` e, se necessário, `image_pull_policy` |
| Restaurar outros values ou templates | Reverter a mudança em Git, por PR, e acompanhar o sync |
| Recuperar temporariamente pelo histórico do Argo CD | Desabilitar auto-sync de forma coordenada, selecionar a revisão e registrar no Git o estado que deve permanecer |

A reversão pelo histórico do Argo CD exige auto-sync desabilitado. O selfHeal e o platform-root podem reaplicar a configuração versionada. O Helm atua como renderizador neste fluxo GitOps. [Política de sincronização do Argo CD](https://argo-cd.readthedocs.io/en/release-3.2/user-guide/auto_sync/)

## Executar pelo GitHub Actions

1. Confirme a referência completa da última versão saudável no Harbor ou no cache do Minikube, conforme a entrega original. Registre a referência atual para poder recuperá-la.
2. Confirme que `canary.enabled` está desabilitado e que o bot pode publicar em `main`. Se a proteção da branch impedir o push direto, faça a troca de tag por PR.
3. Abra **Actions → Rollback POCAPP → Run workflow** em `main`, informe `image_tag` e preencha os campos opcionais se a referência anterior exigir. Para voltar do Harbor a uma imagem carregada localmente, use o repositório anterior, por exemplo `healthz-api`, e a política `IfNotPresent` ou `Never`, de acordo com o deploy original. O job atualiza o Git em `ubuntu-latest`.
4. Confira o commit em `main` e aguarde o Argo CD. Para uma troca por PR, limite o diff ao `helm/pocapp/values.yaml` para o CI/CD não publicar outra imagem durante o rollback.
5. Confira a imagem efetiva e valide o endpoint pelo Traefik. Após o rollout, aguarde a atualização dos endpoints. Considere o rollback concluído quando requisições consecutivas retornarem a tag esperada. Mudanças de configuração e dados exigem recuperação própria.

~~~bash
argocd app get pocapp --refresh
argocd app wait pocapp --sync --health --timeout 300
kubectl -n apps rollout status deployment/pocapp --timeout=180s
kubectl -n apps get deployment pocapp \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
kubectl -n apps port-forward svc/pocapp 3000:80
~~~

Em outro terminal, valide a tag pelo Service com `curl -fsS http://127.0.0.1:3000/healthz | jq -er '.version'`. Com o Traefik acessível, confira a mesma tag em várias requisições pelo endereço público da POC. [Amostragem de tráfego](../README.md#canary-com-traefik)
