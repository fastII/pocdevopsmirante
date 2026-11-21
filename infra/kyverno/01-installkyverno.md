Instalação do Kyverno via Argo CD — POC pocdevopsmirante
Este guia instala Kyverno por GitOps, usando o Helm Chart oficial gerenciado pelo Argo CD. O cluster Minikube, o Argo CD, o Harbor e o Traefik existentes não são recriados.
1. Arquitetura
- Application kyverno: instala o chart oficial, CRDs, controladores e webhooks no namespace kyverno.
- Application kyverno-policies: lê políticas versionadas em infra/gitops/security/kyverno/ na branch main.
- AppProject kyverno: autoriza os repositórios e recursos necessários. Como o Kyverno instala recursos de escopo global, esse projeto tem permissões elevadas; restrinja quem pode alterá-lo.
- Namespace apps: será o alvo das políticas da aplicação pocapp, mas a instalação dos controladores acontece em kyverno.
2. Estrutura de arquivos
pocdevopsmirante/
└── infra/gitops/
    ├── projects/kyverno.yaml
    ├── applications/kyverno.yaml
    ├── applications/kyverno-policies.yaml
    └── security/kyverno/
        └── README.md                 # Substituir/adicionar políticas validadas depois
Os três manifestos YAML acompanham este README. Copie-os para os caminhos correspondentes no repositório.
3. Pré-requisitos e verificações (somente leitura)
Execute na raiz do repositório:
minikube status
kubectl config current-context
kubectl version
kubectl get nodes
kubectl get pods -n argocd
kubectl get applications.argoproj.io -n argocd
helm version
Confira a versão do chart e a compatibilidade com a versão do Kubernetes antes de sincronizar. O manifesto fornecido usa targetRevision: 3.10.0 como versão fixa de referência; altere-a caso não seja adequada ao seu cluster.
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo update
helm search repo kyverno/kyverno --versions
helm show chart kyverno/kyverno --version 3.10.0
Atenção ao Minikube: Kyverno adiciona controladores e webhooks de admissão. Monitore CPU e memória e não habilite políticas Enforce antes de confirmar a saúde do admission controller.

4. Conferir os manifestos antes da instalação
cat infra/gitops/projects/kyverno.yaml
cat infra/gitops/applications/kyverno.yaml
cat infra/gitops/applications/kyverno-policies.yaml

kubectl apply --dry-run=client -f infra/gitops/projects/kyverno.yaml
kubectl apply --dry-run=client -f infra/gitops/applications/kyverno.yaml
kubectl apply --dry-run=client -f infra/gitops/applications/kyverno-policies.yaml
4.1 AppProject
infra/gitops/projects/kyverno.yaml permite o chart oficial e o repositório GitHub, além de recursos cluster-scoped necessários para CRDs, RBAC e webhooks. Não reutilize esse AppProject para aplicações comuns.
4.2 Application dos controladores
infra/gitops/applications/kyverno.yaml usa:
source:
  repoURL: https://kyverno.github.io/kyverno/
  chart: kyverno
  targetRevision: 3.10.0
  helm:
    releaseName: kyverno
A sincronização automática está habilitada, com prune: false para reduzir risco de remoções acidentais. ServerSideApply=true ajuda com CRDs grandes. As quatro classes de controladores foram configuradas com uma réplica para a POC, não para alta disponibilidade.
5. Instalar pelo Argo CD
Primeiro crie o projeto e depois a Application:
kubectl apply -f infra/gitops/projects/kyverno.yaml
kubectl apply -f infra/gitops/applications/kyverno.yaml
A Application está em auto-sync. Acompanhe a instalação:
kubectl get application kyverno -n argocd -w
Em outro terminal:
kubectl get pods -n kyverno -w
kubectl get deployments -n kyverno
kubectl get crds | grep -i kyverno
kubectl get validatingwebhookconfigurations | grep -i kyverno
Se a CLI Argo CD estiver autenticada:
argocd app get kyverno
argocd app wait kyverno --sync --health --timeout 300
Critério de avanço: Application Synced/Healthy, controladores disponíveis e webhooks registrados. Caso falhe, inspecione antes de prosseguir:
kubectl describe application kyverno -n argocd
kubectl get events -n kyverno --sort-by=.lastTimestamp
kubectl get pods -n kyverno
kubectl describe pods -n kyverno
6. Preparar a Application das políticas
A pasta infra/gitops/security/kyverno/ deve conter ao menos uma política YAML válida antes da sincronização. O README.md sozinho não cria políticas.

Após adicionar e enviar ao GitHub a política validada (comece com Audit), crie a Application:
kubectl apply -f infra/gitops/applications/kyverno-policies.yaml
argocd app get kyverno-policies
argocd app diff kyverno-policies
Como o auto-sync das políticas está desabilitado, sincronize somente após revisar o diff:
argocd app sync kyverno-policies
argocd app wait kyverno-policies --sync --health --timeout 180
Dependência: crie/sincronize kyverno-policies somente depois de instalar os CRDs e validar os controladores do Kyverno. A configuração não automatiza a ordem entre Applications.

7. Política mínima: proibir latest
A próxima etapa é adicionar uma política compatível com a versão do Kyverno instalada, com escopo apenas no namespace apps, contemplando containers, initContainers e imagens sem tag. Prefira uma política oficial de referência adaptada e testada, em vez de ativar imediatamente uma regra experimental.

Processo recomendado:
1. Adicionar política em modo Audit à pasta infra/gitops/security/kyverno/.
2. Fazer commit/push para main e executar argocd app diff kyverno-policies.
3. Sincronizar e consultar os relatórios de violação.
4. Testar com kubectl ... --dry-run=server usando imagem :latest.
5. Somente depois mudar para Enforce, sincronizar e repetir o teste (a admissão deve negar a imagem proibida).
Não aplique uma política Enforce indiscriminadamente a todos os namespaces, pois Argo CD, Harbor, SonarQube, Traefik e os demais serviços já estão instalados.
8. Cosign e verificação de assinaturas (etapa posterior)
A instalação do Kyverno não ativa automaticamente a verificação de assinaturas. Para isso, configure uma política verifyImages/ImageValidatingPolicy compatível com a versão instalada, com identidade OIDC do workflow GitHub Actions, acesso ao Harbor e confiança Sigstore. Comece em auditoria, teste a verificação por digest e só depois ative bloqueio.

Fluxo esperado: build → Trivy → push Harbor → assinatura Cosign → verificação Cosign → atualização GitOps na main → Argo CD → admissão Kyverno.
9. Comandos rápidos
# Aplicações Argo CD
kubectl get applications.argoproj.io -n argocd | grep kyverno

# Estado dos controladores
kubectl get pods,deployments -n kyverno

# Recursos instalados
kubectl get crds | grep -i kyverno
kubectl get validatingwebhookconfigurations | grep -i kyverno

# Diagnóstico de consumo (se Metrics Server estiver disponível)
kubectl top pods -n kyverno
kubectl top nodes

# Políticas instaladas (a API exata depende da versão)
kubectl api-resources | grep -i policy
10. Boas práticas
- Mantenha a versão do chart fixa, atualizando por PR revisado.
- Mantenha Kyverno e políticas em Applications separadas.
- Faça a instalação dos controladores antes das políticas.
- Restrinja acesso de escrita ao AppProject com permissões globais.
- Teste políticas primeiro em Audit, depois em Enforce.
- Não use helm install paralelamente para gerenciar o mesmo Kyverno já instalado pelo Argo CD.
- Não remova CRDs, webhooks ou Applications existentes como tentativa de troubleshooting sem avaliar impacto.

# Add política de proibir image latest
Criar uma pasta infra/kyverno
Criar arquivo disallow-latest.yaml
conteudo

apiVersion: policies.kyverno.io/v1
kind: ValidatingPolicy
metadata:
  name: pocapp-disallow-latest
spec:
  # Inicialmente apenas audita violações.
  # Após os testes, alterar para Deny.
  validationActions:
    - Audit

  # Aplicar somente aos Pods do namespace apps.
  matchConstraints:
    resourceRules:
      - apiGroups:
          - ""
        apiVersions:
          - v1
        operations:
          - CREATE
          - UPDATE
        resources:
          - pods

  # Restringe a política ao namespace apps.
  matchConditions:
    - name: namespace-apps
      expression: "request.namespace == 'apps'"

  validations:
    - message: >-
        Imagens devem possuir uma tag explicita diferente
        de latest ou utilizar digest SHA-256.
      expression: >-
        object.spec.containers.all(c,
          c.image.matches('^.+(:[^/:@]+|@sha256:[a-fA-F0-9]{64})$')
          && !c.image.matches('^.+:latest$')
        )
        &&
        (!has(object.spec.initContainers) ||
          object.spec.initContainers.all(c,
            c.image.matches('^.+(:[^/:@]+|@sha256:[a-fA-F0-9]{64})$')
            && !c.image.matches('^.+:latest$')
          )
        )
        &&
        (!has(object.spec.ephemeralContainers) ||
          object.spec.ephemeralContainers.all(c,
            c.image.matches('^.+(:[^/:@]+|@sha256:[a-fA-F0-9]{64})$')
            && !c.image.matches('^.+:latest$')
          )
        )