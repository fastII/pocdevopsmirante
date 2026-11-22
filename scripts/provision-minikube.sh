#!/usr/bin/env bash
# =============================================================================
# POC DEVOPS MIRANTE | Provisionamento Minikube / Argo CD / Gateway API
# =============================================================================
# OBJETIVO
#   Preparar um cluster Minikube local e sincronizar a plataforma por GitOps.
#   Componentes: Argo CD, Traefik, Harbor, SonarQube, Kyverno e POCAPP.
#   Observabilidade (Prometheus, Loki, Grafana) ativada por padrão.
#   ARC (Actions Runner Controller) DESATIVADO por padrão.
#
# REDE E GATEWAY API
#   Gateway API v1.6.3 Standard, HTTPRoute e TLS terminado no Traefik.
#   O Traefik tambem precisa da API TLSRoute v1 para iniciar o provider.
#   O Helm values do Traefik deve manter:
#     providers.kubernetesGateway.enabled: true
#     providers.kubernetesGateway.experimentalChannel: false
#   Publique as alteracoes de infra/gitops/helm-values/traefik.yaml no Git
#   antes de provisionar: o Argo CD usa a revisao remota.
#
# REEXECUCAO / DADOS
#   Nao apaga o Minikube. O script pode ser reexecutado apos uma falha.
#   --restaurar-secrets SOBRESCREVE os Secrets do cluster com os backups SOPS.
#   A POCAPP NAO e compilada aqui: o pipeline CI publica a imagem no registry.
#   O Argo CD faz o deploy da tag declarada em helm/pocapp/values.yaml.
#   Os backups de Secrets nao incluem PVCs, banco de dados ou imagens.
#   Nunca versione a chave privada age ou credenciais em texto claro.
#
# EXEMPLOS (a partir da raiz do repositorio)
#   bash scripts/provision-minikube.sh --help
#   bash scripts/provision-minikube.sh
#   bash scripts/provision-minikube.sh --servir
#   bash scripts/provision-minikube.sh --sem-observabilidade
#   bash scripts/provision-minikube.sh --restaurar-secrets --servir
#   bash scripts/provision-minikube.sh --acesso-corporativo
#   bash scripts/provision-minikube.sh --com-arc
#
# SOPS + AGE
#   export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/SEU-ARQUIVO.agekey"
#   bash scripts/provision-minikube.sh --restaurar-secrets --servir
# =============================================================================
set -Eeuo pipefail
umask 077

profile=minikube
arc=false
observability=true
serve=false
corporate_access=false
restore_secrets=false
secrets_dir="${SECRETS_DIR:-infra/secrets}"
gateway_api_version=v1.6.3
argocd_values=infra/gitops/helm-values/argocd-resources.yaml
root_app=infra/gitops/bootstrap/root-app.yaml

# Exibe a ajuda completa sem iniciar Docker, Minikube ou Argo CD.
usage() {
  cat <<'HELP'
USO
  bash scripts/provision-minikube.sh [OPCOES]

OPCOES
  -h, --help             Exibe esta ajuda e encerra.
  --restaurar-secrets    Restaura backups *.enc.yaml com SOPS + age.
                        Reaplica Secrets existentes (sobrescreve credenciais).
                        Ignora arc.enc.yaml quando ARC estiver desativado.
  --sem-observabilidade Nao provisiona Prometheus, Loki, Alloy e Grafana.
  --com-arc             Ativa o Actions Runner Controller (opcional).
  --sem-arc             Desativa ARC (comportamento padrao).
  --servir              Abre HTTP 8080 para SonarQube, Harbor e Grafana via Traefik,
                        e HTTPS 8443 para as rotas configuradas.
                        No Docker Desktop com containerd, abre o registry direto em 8081.
                        O terminal fica ocupado ate Ctrl+C.
  --acesso-corporativo  Abre o acesso pelo 'minikube service traefik --url'.
                        Usa portas locais dinamicas, sem editar /etc/hosts.
                        Tem prioridade sobre --servir quando ambos forem usados.

EXEMPLOS
  # Provisionamento padrao: observabilidade ligada, ARC desligado
  bash scripts/provision-minikube.sh

  # Provisionar e abrir HTTP 8080 e HTTPS 8443 para os servicos
  bash scripts/provision-minikube.sh --servir

  # Restaurar credenciais do backup e abrir o acesso HTTPS
  export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/SEU-ARQUIVO.agekey"
  bash scripts/provision-minikube.sh --restaurar-secrets --servir

  # Ambiente corporativo sem acesso a /etc/hosts
  bash scripts/provision-minikube.sh --acesso-corporativo

  # Sem observabilidade e sem ARC
  bash scripts/provision-minikube.sh --sem-observabilidade --sem-arc

  # ARC habilitado explicitamente
  bash scripts/provision-minikube.sh --com-arc

VARIAVEIS OPCIONAIS
  SECRETS_DIR             Diretorio dos backups SOPS. Padrao: infra/secrets.
  SOPS_AGE_KEY_FILE       Caminho da chave privada age (fora do repositorio).
  HARBOR_ADMIN_PASSWORD   Senha inicial do Harbor, se Secret ausente.
  SONAR_MONITORING_PASSCODE  Passcode de monitoramento do SonarQube.
  GRAFANA_PASSWORD        Senha inicial do Grafana, se Secret ausente.
  GITOPS_USERNAME         Usuario Git HTTPS para repositorio privado.
  GITOPS_TOKEN            Token Git HTTPS para repositorio privado.
  ARC_APP_ID, ARC_INSTALLATION_ID, ARC_PRIVATE_KEY_FILE
                          Credenciais da GitHub App quando --com-arc.
  POCAPP_IMAGE_ARCHIVE    Excecao local: carrega imagem precompilada no Minikube.
                        O script NAO executa docker build nem minikube image build.
  POCAPP_DOCKER_CONFIG    Config JSON de autenticacao do registry privado.

OBSERVACOES
  - O chart do Traefik deve estar configurado para HTTPRoute/Standard.
  - Os arquivos Helm values devem estar publicados na branch do GitOps.
  - A observabilidade inicia independentemente da disponibilidade da POCAPP.
  - O pipeline CI/CD e responsavel por build, scan, push e atualizacao da tag.
  - --restaurar-secrets restaura somente Secrets, nao dados persistentes.
  - As URLs *.localhost dependem dos hostnames configurados nas HTTPRoutes.
  - A porta 8080 e compartilhada pelo Traefik: cada hostname escolhe o backend.
  - As rotas HTTP precisam estar aceitas no listener HTTP, sem redirect HTTPS.
  - Harbor HTTP como registry Docker exige configuracao adicional no daemon.
HELP
}

while (( $# )); do
  case "$1" in
    --sem-arc) arc=false ;;
    --com-arc) arc=true ;;
    --restaurar-secrets) restore_secrets=true ;;
    --sem-observabilidade) observability=false ;;
    --servir) serve=true ;;
    --acesso-corporativo) corporate_access=true ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'Opção desconhecida: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

cd "$(dirname "${BASH_SOURCE[0]}")/.."
log() { printf '\n==> %s\n' "$*"; }
die() { printf 'Erro: %s\n' "$*" >&2; exit 1; }
trap 'printf "Falha na linha %s. Corrija o erro acima e rode o script novamente.\n" "$LINENO" >&2' ERR

# Verifica dependencias locais antes de modificar qualquer recurso.
for cmd in docker minikube kubectl helm git jq yq openssl; do
  command -v "$cmd" >/dev/null || die "Instale $cmd antes de executar."
done
yq --version | grep -Eq 'mikefarah/yq.*v4\.' || die 'Use o yq v4 de mikefarah.'
docker info >/dev/null || die 'Inicie o Docker Desktop.'
if "$restore_secrets"; then
  command -v sops >/dev/null || die 'Instale sops antes de restaurar Secrets.'
  [[ -d "$secrets_dir" ]] || die "Diretório de Secrets inexistente: $secrets_dir"
  if [[ -n "${SOPS_AGE_KEY_FILE:-}" ]]; then
    [[ -r "$SOPS_AGE_KEY_FILE" ]] || die 'SOPS_AGE_KEY_FILE não está acessível.'
  fi
fi

# Confere se a revisao GitOps que o Argo CD vai ler ja foi publicada.
repo=$(yq -r '.spec.source.repoURL' "$root_app")
branch=$(yq -r '.spec.source.targetRevision' "$root_app")
log "Conferindo a revisão que o Argo CD vai ler ($branch)"
git fetch --no-tags "$repo" "$branch"
revision=$(git rev-parse FETCH_HEAD)
# O Helm e o kubectl leem os arquivos do bootstrap diretamente do clone.
git diff --quiet "$revision" -- infra/gitops infra/security helm/pocapp app \
  ":(exclude)$argocd_values" ":(exclude)$root_app" ':(exclude,glob)**/*.md' ||
  die "Publique os manifests e o código da aplicação em $branch e alinhe o clone com essa revisão. SHA remoto: $revision."
untracked=$(git ls-files --others --exclude-standard -- infra/gitops infra/security helm/pocapp app \
  ':(exclude,glob)**/*.md')
[[ -z "$untracked" ]] || die 'Há arquivos não versionados nas pastas do provisionamento. Confira git status.'
printf 'SHA GitOps: %s\n' "$revision"

# Diretorio temporario com permissao restrita para materiais sensiveis.
scratch=$(mktemp -d)
cleanup() {
  if [[ -n "${harbor_forward_pid:-}" ]]; then
    kill "$harbor_forward_pid" 2>/dev/null || true
    wait "$harbor_forward_pid" 2>/dev/null || true
  fi
  rm -f -- "$scratch"/tls.crt "$scratch"/tls.key "$scratch"/username "$scratch"/password \
    "$scratch"/harbor-forward.log
  rmdir -- "$scratch"
}
trap cleanup EXIT

# Wrappers: todos os comandos Kubernetes apontam para o contexto minikube.
k() { kubectl --context "$profile" "$@"; }
a() { k -n argocd "$@"; }
m() { minikube -p "$profile" "$@"; }
app() { a --request-timeout=10s get applications.argoproj.io "$@"; }

# Espera com timeout; evita loops infinitos em recursos nao saudaveis.
poll() {
  local timeout=$1 description=$2 deadline next_status
  shift 2
  deadline=$((SECONDS + timeout))
  next_status=$((SECONDS + 30))
  until "$@"; do
    (( SECONDS < deadline )) || { printf 'Tempo esgotado: %s\n' "$description" >&2; return 1; }
    if (( SECONDS >= next_status )); then
      printf 'Aguardando %s (%ss restantes).\n' "$description" "$((deadline - SECONDS))"
      next_status=$((SECONDS + 30))
    fi
    sleep 4
  done
}

# Cria namespaces de forma idempotente.
namespace() {
  k create namespace "$1" --dry-run=client -o yaml | k apply -f -
}

# Consulta a existencia de Secret sem exibir seus dados.
secret_exists() {
  local found
  found=$(k --request-timeout=10s -n "$1" get secret "$2" --ignore-not-found -o name) ||
    die "Não foi possível consultar o Secret $1/$2."
  [[ -n "$found" ]]
}

prompt() {
  local variable=$1 label=$2 mode=${3:-text} answer
  [[ -z "${!variable:-}" ]] || return 0
  [[ -t 0 ]] || die "Informe $variable por variável de ambiente."
  if [[ "$mode" == secret ]]; then
    IFS= read -r -s -p "$label: " answer
    printf '\n'
  else
    IFS= read -r -p "$label: " answer
  fi
  [[ -n "$answer" ]] || die "$variable é obrigatório."
  printf -v "$variable" '%s' "$answer"
}

# So solicita senha quando o Secret ainda nao existe.
password_secret() {
  local ns=$1 name=$2 key=$3 var_name=$4 label=$5
  shift 5
  secret_exists "$ns" "$name" && return 0
  prompt "$var_name" "$label" secret
  printf '%s' "${!var_name}" > "$scratch/password"
  k -n "$ns" create secret generic "$name" --from-file="$key=$scratch/password" "$@"
  rm -f -- "$scratch/password"
  unset "$var_name"
}

repo_server_ready() {
  a --request-timeout=10s get endpointslices.discovery.k8s.io \
    -l kubernetes.io/service-name=argocd-repo-server -o json | jq -e '
    any(.items[];
      any(.ports[]?; .port == 8081)
      and any(.endpoints[]?; .conditions.ready == true))
  ' >/dev/null
}

repo_server_diagnostics() {
  a --request-timeout=10s get pods -l app.kubernetes.io/name=argocd-repo-server -o wide >&2 || true
  a --request-timeout=10s get endpointslices.discovery.k8s.io \
    -l kubernetes.io/service-name=argocd-repo-server >&2 || true
}

app_ready() {
  app "$1" -o json 2>/dev/null | jq -e --arg mode "$2" --arg sha "${3:-}" --argjson refresh "${4:-false}" '
    .status.sync.status == "Synced"
    and (.operation == null)
    and all(.status.conditions[]?; .type != "ComparisonError")
    and ($mode == "sync" or .status.health.status == "Healthy")
    and ($sha == "" or .status.sync.revision == $sha)
    and (($refresh | not) or .metadata.annotations["argocd.argoproj.io/refresh"] == null)
  ' >/dev/null
}

wait_app() {
  local name=$1 timeout=$2 mode=${3:-health} sha=${4:-} refresh=${5:-false}
  local check=${6:-app_ready}
  if ! poll "$timeout" "Application $name ($mode)" "$check" "$name" "$mode" "$sha" "$refresh"; then
    app "$name" -o json | jq '{
      sync: .status.sync, health: .status.health, conditions: .status.conditions,
      operation: (.status.operationState | {phase, message}),
      failures: [.status.operationState.syncResult.resources[]? |
        select(.status == "SyncFailed") | {kind, name, message}]
    }' >&2 || true
    if [[ "$name" == platform-root ]]; then repo_server_diagnostics; fi
    die "Confira os eventos e o estado da Application $name no Argo CD."
  fi
}

kyverno_api_ready() {
  k --request-timeout=10s get --raw /apis/policies.kyverno.io/v1 2>/dev/null |
    jq -e 'any(.resources[]?; .name == "validatingpolicies" and .kind == "ValidatingPolicy")' >/dev/null
}

kyverno_policies_ready() {
  app_ready "$@" && return 0
  "$kyverno_retry_requested" && return 1
  local name=$1 target_revision=$3 patch
  # O autosync pode esgotar as tentativas enquanto o chart registra a API.
  # A atualização condicional evita substituir outra operação concorrente.
  patch=$(app "$name" -o json 2>/dev/null | jq -c --arg revision "$target_revision" '
    select(.operation == null and .status.sync.status == "OutOfSync"
      and .status.sync.revision == $revision
      and ((.status.operationState.phase // "") | IN("Failed", "Error"))
      and any(.status.operationState.syncResult.resources[]?;
        .group == "policies.kyverno.io" and .kind == "ValidatingPolicy"
        and .status == "SyncFailed" and ((.message // "") | contains("could not find"))))
    | [{op: "test", path: "/metadata/resourceVersion", value: .metadata.resourceVersion},
       {op: "add", path: "/operation", value: {
         sync: {revision: $revision, prune: false, syncOptions: (.spec.syncPolicy.syncOptions // [])}
       }}]
  ') || return 1
  [[ -n "$patch" ]] || return 1
  if a --request-timeout=10s patch application "$name" --type=json --patch "$patch"; then
    kyverno_retry_requested=true
    log 'Solicitada uma nova sincronização das políticas após a API do Kyverno ficar disponível'
  fi
  return 1
}

route_ready() {
  k --request-timeout=10s -n "$1" get httproute "$2" -o json 2>/dev/null | jq -e '
    .metadata.generation as $generation |
    any(.status.parents[]?;
      .parentRef.name == "traefik-gateway" and .parentRef.namespace == "traefik"
      and any(.conditions[]?; .type == "Accepted" and .status == "True" and .observedGeneration == $generation)
      and any(.conditions[]?; .type == "ResolvedRefs" and .status == "True" and .observedGeneration == $generation)
    )
  ' >/dev/null
}

check_route() {
  if ! poll 180 "rota $1/$2" route_ready "$1" "$2"; then
    k -n "$1" describe httproute "$2"
    die "A rota $1/$2 não foi aceita pelo Traefik."
  fi
}

service_healthy() {
  k --request-timeout=10s get --raw="$1" 2>/dev/null | jq -e '.status == "healthy"' >/dev/null
}

harbor_forward_ready() {
  local headers
  headers=$(curl --noproxy '*' -sS --max-time 3 -D - -o /dev/null \
    -H 'Host: host.docker.internal:8081' http://127.0.0.1:8081/v2/ 2>/dev/null) || return 1
  grep -Eq '^HTTP/[0-9.]+ 401 ' <<< "$headers" &&
    grep -iFq 'realm="http://host.docker.internal:8081/service/token"' <<< "$headers" &&
    ! curl --noproxy '*' -ksS --max-time 3 -o /dev/null https://127.0.0.1:8081/v2/ 2>/dev/null
}

serve_local_harbor() {
  command -v curl >/dev/null || die 'Instale curl para verificar o túnel local do Harbor.'

  # O containerd usa hosts.toml para escolher HTTP neste endereço.
  docker exec -i "$profile" sh -s <<'NODE'
set -eu
target=/etc/containerd/certs.d/host.docker.internal:8081/hosts.toml
candidate=$(mktemp)
trap 'rm -f "$candidate"' EXIT
cat > "$candidate" <<'TOML'
server = "http://host.docker.internal:8081"

[host."http://host.docker.internal:8081"]
  capabilities = ["pull", "resolve"]
TOML
if [ -e "$target" ]; then
  if ! cmp -s "$candidate" "$target"; then
    printf 'Configuração do registry já existe em %s. Confira o endpoint HTTP.\n' "$target" >&2
    exit 1
  fi
else
  install -D -m 0644 "$candidate" "$target"
fi
NODE

  if ! harbor_forward_ready; then
    # O backend é HTTP puro, então o Docker pode fazer fallback de HTTPS.
    kubectl --context "$profile" -n harbor port-forward --address 127.0.0.1 \
      svc/harbor 8081:80 > "$scratch/harbor-forward.log" 2>&1 &
    harbor_forward_pid=$!
    if ! poll 30 'túnel HTTP direto do Harbor na porta 8081' harbor_forward_ready; then
      cat "$scratch/harbor-forward.log" >&2
      die 'Confira se a porta 8081 está livre para o encaminhamento direto ao Harbor.'
    fi
  fi
  printf 'Registry para Docker Desktop e Minikube: host.docker.internal:8081\n'
}

harbor_ready() {
  app_ready harbor health && return 0
  local migration_errors dirty_version
  migration_errors=$(k --request-timeout=10s -n harbor logs deployment/harbor-core --all-pods=true --tail=30 2>/dev/null |
    awk 'match($0, /Dirty database version [0-9]+/) { print substr($0, RSTART, RLENGTH) }' |
    sort -u) || return 1
  [[ -n "$migration_errors" ]] || return 1
  dirty_version=$(k --request-timeout=10s -n harbor exec statefulset/harbor-database -c database -- \
    psql -X -w -U postgres -d registry -Atc 'SELECT version FROM public.schema_migrations WHERE dirty;' 2>/dev/null) ||
    return 1
  if [[ "$dirty_version" =~ ^[0-9]+$ ]] &&
     grep -Fxq "Dirty database version $dirty_version" <<< "$migration_errors"; then
    die "PostgreSQL do Harbor: Dirty database version $dirty_version. Recupere a migração no banco persistente antes de reexecutar."
  fi
  return 1
}

# ETAPA 1: reutiliza o Minikube existente ou inicia um novo perfil.
log 'Preparando Minikube e Metrics Server'
if ! m status >/dev/null 2>&1; then
  if docker container inspect "$profile" >/dev/null 2>&1; then
    m start --driver=docker
  else
    m start --driver=docker --container-runtime=containerd --kubernetes-version=v1.37.0 \
      --cpus=no-limit --memory=no-limit
  fi
fi
k wait --for=condition=Ready node/"$profile" --timeout=180s
k get storageclass standard
m addons enable metrics-server

# ETAPA 2: instala/atualiza Argo CD e os AppProjects da plataforma.
log 'Instalando Argo CD e AppProjects'
helm repo add argo https://argoproj.github.io/argo-helm --force-update
if ! helm --kube-context "$profile" upgrade --install argocd argo/argo-cd --version 10.18.2 \
  -n argocd --create-namespace -f "$argocd_values" --wait --timeout 10m; then
  repo_server_diagnostics
  die 'A instalação ou atualização do Argo CD falhou.'
fi
log 'Aguardando o repo-server do Argo CD na porta 8081'
if ! a rollout status deployment/argocd-repo-server --timeout=180s ||
   ! poll 120 'endpoint do repo-server do Argo CD' repo_server_ready; then
  repo_server_diagnostics
  die 'O serviço interno argocd-repo-server:8081 ficou indisponível.'
fi
k wait --for=condition=Established crd/applications.argoproj.io --timeout=120s
k apply -f infra/gitops/projects/

# Esta POC utiliza somente HTTPRoute. O chart do Traefik e gerenciado
# pelo Argo CD a partir dos valores versionados no Git, nao por este script.
# Evita instalar CRDs experimentais para mascarar configuracao incorreta.
traefik_values=infra/gitops/helm-values/traefik.yaml
[[ -f "$traefik_values" ]] || die "Valores do Traefik nao encontrados: $traefik_values"
traefik_gateway_enabled=$(yq -r '.providers.kubernetesGateway.enabled // false' "$traefik_values")
traefik_experimental=$(yq -r '.providers.kubernetesGateway.experimentalChannel // false' "$traefik_values")
[[ "$traefik_gateway_enabled" == true ]] ||
  die 'Habilite providers.kubernetesGateway.enabled=true no arquivo de valores do Traefik.'
[[ "$traefik_experimental" == false ]] ||
  die 'Esta POC usa somente HTTPRoute: defina providers.kubernetesGateway.experimentalChannel=false e publique os valores no Git.'

# ETAPA 3: instala os CRDs Standard, incluindo TLSRoute v1, usado pelo informer do Traefik.
log 'Preparando Gateway API, TLS e credenciais'
k apply --server-side \
  -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/$gateway_api_version/standard-install.yaml"
k wait --for=condition=Established --timeout=120s \
  crd/gatewayclasses.gateway.networking.k8s.io crd/gateways.gateway.networking.k8s.io \
  crd/httproutes.gateway.networking.k8s.io crd/tlsroutes.gateway.networking.k8s.io
for ns in traefik harbor sonarqube apps; do namespace "$ns"; done
# O namespace deve existir ANTES da restauração do Secret do Grafana.
if "$observability"; then namespace observability; fi
if "$arc"; then k apply -f infra/gitops/arc-minikube/manifests/namespaces.yaml; fi

# Restauração SOPS + age: só é executada com --restaurar-secrets.
# Ignora o ARC quando não solicitado; idem para observabilidade desabilitada.
# Valida cada manifesto como Secret e verifica seu namespace antes de aplicar.
# Os dados descriptografados trafegam apenas por pipes; não são gravados em arquivos.
restore_sops_secrets() {
  local file filename ns kind count=0
  shopt -s nullglob
  local files=("$secrets_dir"/*.enc.yaml)
  shopt -u nullglob
  (( ${#files[@]} > 0 )) || die "Nenhum arquivo .enc.yaml encontrado em $secrets_dir."
  for file in "${files[@]}"; do
    filename=${file##*/}
    if [[ "$arc" == false && "$filename" == arc.enc.yaml ]]; then
      log "Ignorando $filename: ARC desabilitado"
      continue
    fi
    if [[ "$observability" == false && "$filename" == grafana.enc.yaml ]]; then
      log "Ignorando $filename: observabilidade desabilitada"
      continue
    fi
    # Verificação em pipe, sem exibir ou salvar credenciais.
    kind=$(sops -d "$file" | yq -r '.kind') || die "Falha ao descriptografar $file"
    ns=$(sops -d "$file" | yq -r '.metadata.namespace') || die "Falha ao ler namespace de $file"
    [[ "$kind" == Secret ]] || die "$file deve conter um manifesto Kubernetes kind: Secret."
    [[ -n "$ns" && "$ns" != null ]] || die "Secret sem metadata.namespace: $file"
    if [[ "$ns" == arc-runners || "$ns" == arc-systems ]]; then
      if ! "$arc"; then log "Ignorando $filename: namespace do ARC desabilitado"; continue; fi
    fi
    if [[ "$ns" == observability ]] && ! "$observability"; then
      log "Ignorando $filename: observabilidade desabilitada"
      continue
    fi
    k get namespace "$ns" >/dev/null || die "Namespace inexistente para $file: $ns"
    log "Restaurando Secret de $file no namespace $ns"
    sops -d "$file" | k apply -f - || die "Falha na restauração de $file"
    ((count+=1))
  done
  log "Secrets restaurados: $count"
}
if "$restore_secrets"; then restore_sops_secrets; fi
if [[ -n "${GITOPS_USERNAME:-}${GITOPS_TOKEN:-}" ]] && ! secret_exists argocd provision-gitops-repo; then
  prompt GITOPS_USERNAME 'Usuário Git HTTPS'
  prompt GITOPS_TOKEN 'Token Git HTTPS' secret
  printf '%s' "$GITOPS_USERNAME" > "$scratch/username"
  printf '%s' "$GITOPS_TOKEN" > "$scratch/password"
  a create secret generic provision-gitops-repo --from-literal=type=git --from-literal=url="$repo" \
    --from-file="username=$scratch/username" --from-file="password=$scratch/password" --dry-run=client -o json |
    jq '.metadata.labels["argocd.argoproj.io/secret-type"] = "repository"' | a create -f -
  rm -f -- "$scratch/username" "$scratch/password"
  unset GITOPS_TOKEN
fi
# Gera TLS local autoassinado somente se ainda nao houver Secret.
if ! secret_exists traefik local-selfsigned-tls; then
  openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout "$scratch/tls.key" -out "$scratch/tls.crt" -subj '/CN=*.localhost' \
    -addext 'subjectAltName=DNS:*.localhost,DNS:*.local'
  k -n traefik create secret tls local-selfsigned-tls \
    --key="$scratch/tls.key" --cert="$scratch/tls.crt"
fi
password_secret harbor harbor-admin HARBOR_ADMIN_PASSWORD HARBOR_ADMIN_PASSWORD 'Senha inicial do Harbor'
password_secret sonarqube sonarqube-monitoring monitoringPasscode SONAR_MONITORING_PASSCODE 'Passcode de monitoramento do SonarQube'

if "$arc"; then
  if ! secret_exists arc-runners arc-github-app; then
    prompt ARC_APP_ID 'GitHub App ID'
    prompt ARC_INSTALLATION_ID 'GitHub App Installation ID'
    prompt ARC_PRIVATE_KEY_FILE 'Caminho do PEM da GitHub App'
    [[ "$ARC_APP_ID" =~ ^[0-9]+$ && "$ARC_INSTALLATION_ID" =~ ^[0-9]+$ ]] ||
      die 'Use IDs numéricos da GitHub App e da instalação.'
    [[ -f "$ARC_PRIVATE_KEY_FILE" && -r "$ARC_PRIVATE_KEY_FILE" ]] || die 'PEM inacessível.'
    k -n arc-runners create secret generic arc-github-app \
      --from-literal="github_app_id=$ARC_APP_ID" --from-literal="github_app_installation_id=$ARC_INSTALLATION_ID" \
      --from-file="github_app_private_key=$ARC_PRIVATE_KEY_FILE"
  fi
fi
if "$observability"; then
  password_secret observability grafana-admin admin-password GRAFANA_PASSWORD 'Senha inicial do Grafana' \
    --from-literal=admin-user=admin
fi

# ETAPA 4: prepara o acesso à imagem quando solicitado.
if [[ -n "${POCAPP_DOCKER_CONFIG:-}" ]]; then
  pull_secret=$(yq -r '.imagePullSecrets[0].name // ""' helm/pocapp/values.yaml)
  [[ -n "$pull_secret" ]] || die 'Defina imagePullSecrets no values da POCAPP em Git.'
  if ! secret_exists apps "$pull_secret"; then
    k -n apps create secret generic "$pull_secret" --type=kubernetes.io/dockerconfigjson \
      --from-file=".dockerconfigjson=$POCAPP_DOCKER_CONFIG"
  fi
fi
if [[ -n "${POCAPP_IMAGE_ARCHIVE:-}" ]]; then
  pull_policy=$(yq -r '.image.pullPolicy' helm/pocapp/values.yaml)
  [[ "$pull_policy" != Always ]] || die 'A imagem local exige pullPolicy IfNotPresent ou Never.'
  [[ -r "$POCAPP_IMAGE_ARCHIVE" ]] || die 'POCAPP_IMAGE_ARCHIVE nao encontrado ou sem permissao de leitura.'
  log 'Carregando a imagem fornecida para a POCAPP'
  m image load "$POCAPP_IMAGE_ARCHIVE"
fi

# ETAPA 5: App-of-Apps cria as Applications filhas do Argo CD.
log 'Criando Applications filhas pelo platform-root'
k apply -f "$root_app"
a annotate applications.argoproj.io platform-root argocd.argoproj.io/refresh=hard --overwrite
log 'Verificando se o Argo CD lê a revisão do GitHub'
wait_app platform-root 240 sync "$revision" true

# ETAPA 6: acompanha o autosync declarado nas Applications da plataforma.
# A prontidão do Traefik é medida pelo Deployment e pelo Gateway.
log 'Aguardando o sync automático do Traefik'
wait_app traefik 480 sync
k -n traefik rollout status deployment/traefik --timeout=300s
if ! k wait --for=condition=Accepted gatewayclass/traefik --timeout=180s ||
   ! k -n traefik wait --for=condition=Programmed gateway/traefik-gateway --timeout=180s; then
  k --request-timeout=10s describe gatewayclass traefik >&2 || true
  k --request-timeout=10s -n traefik describe gateway traefik-gateway >&2 || true
  k --request-timeout=10s -n traefik logs deployment/traefik --since=5m --tail=30 >&2 || true
  die 'O controller do Traefik não programou o Gateway.'
fi
log 'Aguardando o sync automático do Harbor'
wait_app harbor 480 sync
log 'Aguardando a migração do PostgreSQL e a saúde do Harbor'
if ! poll 600 'Harbor saudável' harbor_ready ||
   ! poll 120 'API de saúde do Harbor' service_healthy '/api/v1/namespaces/harbor/services/http:harbor:80/proxy/api/v2.0/health'; then
  k --request-timeout=10s -n harbor get pods,pvc >&2 || true
  die 'A API de saúde do Harbor não ficou pronta.'
fi
log 'Aguardando o SonarQube e as rotas de plataforma'
wait_app sonarqube 600
wait_app platform-routes 300 sync
check_route argocd argocd
check_route harbor harbor
check_route sonarqube sonarqube
check_route sonarqube sonarqube-http

# ETAPA 7: verifica o Kyverno e sincroniza as politicas.
log 'Validando Kyverno e a sincronização da política'
wait_app kyverno 480
k wait --for=condition=Established crd/validatingpolicies.policies.kyverno.io --timeout=120s
poll 90 'API ValidatingPolicy v1 do Kyverno' kyverno_api_ready
kyverno_retry_requested=false
wait_app kyverno-policies 300 sync "$revision" false kyverno_policies_ready

# ETAPA OPCIONAL: ARC somente com --com-arc.
if "$arc"; then
  log 'Instalando ARC'
  arc_dir=infra/gitops/arc-minikube
  if ! secret_exists argocd arc-helm-oci; then
    arc_repo=$(yq -r '.spec.source.repoURL' "$arc_dir/argo/controller.yaml")
    a create secret generic arc-helm-oci --from-literal=type=helm \
      --from-literal=enableOCI=true --from-literal=url="$arc_repo" --dry-run=client -o json |
      jq '.metadata.labels["argocd.argoproj.io/secret-type"] = "repository"' | a create -f -
  fi
  k apply -f "$arc_dir/argo/project.yaml" -f "$arc_dir/argo/controller.yaml"
  wait_app arc-controller 480
  k apply -f "$arc_dir/argo/scaleset.yaml"
  wait_app arc-runner-minikube 480
  k -n arc-systems rollout status deployment/arc-gha-rs-controller --timeout=120s
  listener_ready() {
    k -n arc-systems --request-timeout=10s get pods -o json |
      jq -e 'any(.items[]; (.metadata.name | endswith("-listener")) and
          any(.status.conditions[]?; .type == "Ready" and .status == "True"))' >/dev/null
  }
  poll 180 'listener do ARC' listener_ready
fi

# ETAPA OPCIONAL: observabilidade ativa por padrao.
if "$observability"; then
  log 'Instalando observabilidade'
  obs=infra/gitops/observability-minikube/argocd
  k apply -f "$obs/project.yaml" -f "$obs/prometheus.yaml" -f "$obs/loki.yaml"
  wait_app obs-prometheus 600
  wait_app obs-loki 480
  k apply -f "$obs/alloy.yaml" -f "$obs/grafana-route.yaml"
  wait_app obs-alloy 300
  wait_app obs-grafana-route 300 sync
  check_route observability grafana
fi

# ETAPA FINAL: inventario resumido e orientacoes de acesso.
log 'Verificação final'
a get applications.argoproj.io
k get pvc -A
k get gateway,httproute -A
docker stats --no-stream "$profile"
printf '\nProvisionamento concluído para a revisão %s.\n' "$revision"
if ! "$arc"; then printf 'ARC omitido por opção.\n'; fi
if ! "$observability"; then printf 'Observabilidade omitida por opção.\n'; fi
if a get secret argocd-initial-admin-secret >/dev/null 2>&1; then
  printf "Para obter a senha inicial do Argo CD, consulte argocd-initial-admin-secret no namespace argocd.\n"
fi
# MODOS DE ACESSO: escolha portas fixas ou URLs dinâmicas do Minikube.
# --acesso-corporativo tem prioridade caso as duas flags sejam informadas.
if "$corporate_access"; then
  log 'Acesso corporativo: Traefik via minikube service'
  printf 'As URLs locais mostradas pelo Minikube apontam para o Traefik.\n'
  printf 'Para HTTPRoute, informe o hostname correto no cabecalho Host.\n'
  printf "Exemplo: curl -i -H 'Host: sonarqube.localhost' http://127.0.0.1:PORTA_HTTP/api/server/version\n"
  m service traefik -n traefik --url
elif "$serve"; then
  # Um unico port-forward HTTP atende todas as HTTPRoutes por hostname.
  # Nao sao necessarios forwards separados para Harbor, SonarQube e Grafana.
  # Os manifestos HTTPRoute devem permitir o listener HTTP do Gateway.
  printf '\nAcessos locais via Traefik (HTTP):\n'
  printf '  SonarQube: http://sonarqube.localhost:8080\n'
  printf '  Harbor:    http://harbor.localhost:8080\n'
  if "$observability"; then
    printf '  Grafana:   http://grafana.localhost:8080\n'
  fi
  printf '\nHTTPS (mantido): https://argocd.localhost:8443\n'
  printf '\nTestes em outro terminal:\n'
  printf '  curl -i http://sonarqube.localhost:8080/api/system/status\n'
  printf '  curl -i http://harbor.localhost:8080/v2/\n'
  if "$observability"; then
    printf '  curl -I http://grafana.localhost:8080/login\n'
  fi
  printf '\nNota: respostas 301 para HTTPS indicam redirecionamento na rota ou aplicacao.\n'
  printf 'Nota: Docker push HTTP no Harbor requer configuracao do registry no Docker.\n'
  if [[ "$(docker info --format '{{.OperatingSystem}}')" == 'Docker Desktop' &&
        "$(k get node "$profile" -o jsonpath='{.status.nodeInfo.containerRuntimeVersion}')" == containerd://* ]]; then
    serve_local_harbor
  fi
  printf 'Iniciando port-forward em loopback; encerre com Ctrl+C.\n'
  k -n traefik port-forward --address 127.0.0.1 svc/traefik 8443:443 8080:80
else
  printf 'Acesso local HTTP (8080): sonarqube.localhost, harbor.localhost'
  if "$observability"; then printf ', grafana.localhost'; fi
  printf '\nAcesso HTTPS (8443): argocd.localhost e demais rotas HTTPS.\n'
  printf 'Para abrir os acessos: bash scripts/provision-minikube.sh --servir\n'
  printf 'Ou execute: kubectl --context minikube -n traefik port-forward --address 127.0.0.1 svc/traefik 8443:443 8080:80\n'
  printf 'Alternativa: minikube -p minikube service traefik -n traefik --url\n'
fi
