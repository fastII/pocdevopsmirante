#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

profile=minikube
arc=true
observability=true
serve=false

usage() {
  cat <<'HELP'
Uso: bash scripts/provision-minikube.sh [--sem-arc] [--sem-observabilidade] [--servir]

Instala a plataforma no perfil minikube. Reutiliza os Secrets existentes.
Variáveis opcionais para provisionamento sem prompts:
  HARBOR_ADMIN_PASSWORD, SONAR_MONITORING_PASSCODE, GRAFANA_PASSWORD
  ARC_APP_ID, ARC_INSTALLATION_ID, ARC_PRIVATE_KEY_FILE
  GITOPS_USERNAME e GITOPS_TOKEN (repositório Git privado por HTTPS)
  POCAPP_IMAGE_ARCHIVE (arquivo de imagem para carregar no Minikube)
  POCAPP_DOCKER_CONFIG (config.json de pull para o registry privado)
HELP
}

while (( $# )); do
  case "$1" in
    --sem-arc) arc=false ;;
    --sem-observabilidade) observability=false ;;
    --servir) serve=true ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'Opção desconhecida: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

cd "$(dirname "${BASH_SOURCE[0]}")/.."
log() { printf '\n==> %s\n' "$*"; }
die() { printf 'Erro: %s\n' "$*" >&2; exit 1; }
trap 'printf "Falha na linha %s. Corrija o erro acima e rode o script novamente.\n" "$LINENO" >&2' ERR

for cmd in docker minikube kubectl helm git jq yq openssl; do
  command -v "$cmd" >/dev/null || die "Instale $cmd antes de executar."
done
yq --version | grep -Eq 'mikefarah/yq.*v4\.' || die 'Use o yq v4 de mikefarah.'
docker info >/dev/null || die 'Inicie o Docker Desktop.'

repo=$(yq -r '.spec.source.repoURL' infra/gitops/bootstrap/root-app.yaml)
branch=$(yq -r '.spec.source.targetRevision' infra/gitops/bootstrap/root-app.yaml)
log "Conferindo a revisão que o Argo CD vai ler ($branch)"
git fetch --no-tags "$repo" "$branch"
revision=$(git rev-parse FETCH_HEAD)
git diff --quiet "$revision" -- infra/gitops infra/security helm/pocapp app ||
  die "Publique os manifests e o código da aplicação em $branch e alinhe o clone com essa revisão. SHA remoto: $revision."
untracked=$(git ls-files --others --exclude-standard -- infra/gitops infra/security helm/pocapp app)
[[ -z "$untracked" ]] || die 'Há arquivos não versionados nas pastas do provisionamento. Confira git status.'
printf 'SHA GitOps: %s\n' "$revision"

scratch=$(mktemp -d)
cleanup() {
  rm -f -- "$scratch"/tls.crt "$scratch"/tls.key "$scratch"/username "$scratch"/password
  rmdir -- "$scratch"
}
trap cleanup EXIT

k() { kubectl --context "$profile" "$@"; }
a() { k -n argocd "$@"; }
m() { minikube -p "$profile" "$@"; }
app() { a --request-timeout=10s get applications.argoproj.io "$@"; }

poll() {
  local timeout=$1 description=$2 deadline
  shift 2
  deadline=$((SECONDS + timeout))
  until "$@"; do
    (( SECONDS < deadline )) || { printf 'Tempo esgotado: %s\n' "$description" >&2; return 1; }
    sleep 4
  done
}

namespace() {
  k create namespace "$1" --dry-run=client -o yaml | k apply -f -
}

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

app_ready() {
  app "$1" -o json 2>/dev/null | jq -e --arg mode "$2" --arg sha "${3:-}" '
    .status.sync.status == "Synced"
    and (.operation == null)
    and ($mode == "sync" or .status.health.status == "Healthy")
    and ($sha == "" or .status.sync.revision == $sha)
  ' >/dev/null
}

wait_app() {
  local name=$1 timeout=$2 mode=${3:-health} sha=${4:-}
  if ! poll "$timeout" "Application $name ($mode)" app_ready "$name" "$mode" "$sha"; then
    app "$name" -o json | jq '{sync: .status.sync, health: .status.health, conditions: .status.conditions, operation: .status.operationState.message}'
    die "Confira os eventos e o estado da Application $name no Argo CD."
  fi
}

sync_finished() {
  local name=$1 operation_id=$2 phase
  phase=$(app "$name" -o json 2>/dev/null | jq -r --arg id "$operation_id" '
    select(.operation == null and any(.status.operationState.operation.info[]?; .name == "provision" and .value == $id))
    | .status.operationState.phase
  ') || return 1
  case "$phase" in
    Succeeded) return 0 ;;
    Failed|Error) die "Sync de $name falhou: $(app "$name" -o jsonpath='{.status.operationState.message}')" ;;
    *) return 1 ;;
  esac
}

sync_app() {
  local name=$1 timeout=$2 mode=${3:-health} operation_id operation
  operation_id="$(date +%s)-$$-$name"
  operation=$(app "$name" -o json | jq -ce --arg id "$operation_id" '
    if .operation != null then error("já existe um sync em execução")
    else {operation: {info: [{name: "provision", value: $id}],
          sync: {prune: false, syncOptions: (.spec.syncPolicy.syncOptions // [])}}}
    end
  ')
  a patch applications.argoproj.io "$name" --type merge --patch "$operation"
  poll "$timeout" "operação de sync de $name" sync_finished "$name" "$operation_id" ||
    die "Confira a operação de $name no Argo CD."
  wait_app "$name" "$timeout" "$mode"
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

log 'Instalando Argo CD e AppProjects'
helm repo add argo https://argoproj.github.io/argo-helm --force-update
helm --kube-context "$profile" upgrade --install argocd argo/argo-cd --version 10.18.2 \
  -n argocd --create-namespace -f infra/gitops/helm-values/argocd-resources.yaml \
  --wait --timeout 10m
k wait --for=condition=Established crd/applications.argoproj.io --timeout=120s
k apply -f infra/gitops/projects/
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

log 'Preparando Gateway API, TLS e credenciais'
k apply --server-side \
  -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.1/standard-install.yaml
k wait --for=condition=Established --timeout=120s \
  crd/gateways.gateway.networking.k8s.io crd/httproutes.gateway.networking.k8s.io
for ns in traefik harbor sonarqube apps; do namespace "$ns"; done
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
  k apply -f infra/gitops/arc-minikube/manifests/namespaces.yaml
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
  namespace observability
  password_secret observability grafana-admin admin-password GRAFANA_PASSWORD 'Senha inicial do Grafana' \
    --from-literal=admin-user=admin
fi

log 'Preparando a imagem da POCAPP'
image_repo=$(yq -r '.image.repository' helm/pocapp/values.yaml)
image_tag=$(yq -r '.image.tag' helm/pocapp/values.yaml)
pull_policy=$(yq -r '.image.pullPolicy' helm/pocapp/values.yaml)
if [[ -n "${POCAPP_DOCKER_CONFIG:-}" ]]; then
  pull_secret=$(yq -r '.imagePullSecrets[0].name // ""' helm/pocapp/values.yaml)
  [[ -n "$pull_secret" ]] || die 'Defina imagePullSecrets no values da POCAPP em Git.'
  if ! secret_exists apps "$pull_secret"; then
    k -n apps create secret generic "$pull_secret" --type=kubernetes.io/dockerconfigjson \
      --from-file=".dockerconfigjson=$POCAPP_DOCKER_CONFIG"
  fi
fi
if [[ -n "${POCAPP_IMAGE_ARCHIVE:-}" ]]; then
  [[ "$pull_policy" != Always ]] || die 'A imagem local exige pullPolicy IfNotPresent ou Never.'
  m image load "$POCAPP_IMAGE_ARCHIVE"
  m image ls | awk -v image="$image_repo:$image_tag" '
    $0 == image || $0 == "docker.io/" image || $0 == "docker.io/library/" image { found = 1 }
    END { exit !found }
  ' || die "O archive não disponibilizou a imagem esperada: $image_repo:$image_tag."
elif [[ "$image_repo" == healthz-api && "$pull_policy" != Always ]]; then
  m image build -t "$image_repo:$image_tag" ./app
else
  printf 'POCAPP usará %s:%s. O registry e a tag precisam estar disponíveis para o Minikube.\n' "$image_repo" "$image_tag"
fi

log 'Criando Applications filhas pelo platform-root'
k apply -f infra/gitops/bootstrap/root-app.yaml
wait_app platform-root 240 sync "$revision"

log 'Sincronizando Traefik, Harbor, SonarQube e rotas'
sync_app traefik 480
k -n traefik wait --for=condition=Programmed gateway/traefik-gateway --timeout=180s
sync_app harbor 600
poll 120 'API de saúde do Harbor' service_healthy '/api/v1/namespaces/harbor/services/http:harbor:80/proxy/api/v2.0/health'
sync_app sonarqube 600
sync_app platform-routes 300 sync
check_route argocd argocd
check_route harbor harbor
check_route sonarqube sonarqube

log 'Validando Kyverno e sincronizando a política'
wait_app kyverno 480
k wait --for=condition=Established crd/validatingpolicies.policies.kyverno.io --timeout=120s
sync_app kyverno-policies 300 sync

log 'Validando a POCAPP'
wait_app pocapp 480 health "$revision"
check_route apps pocapp
poll 120 'endpoint /healthz da POCAPP' service_healthy '/api/v1/namespaces/apps/services/http:pocapp:80/proxy/healthz'

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
printf 'Abra https://argocd.localhost:8443 com o encaminhamento abaixo. O TLS local é autoassinado.\n'
if "$serve"; then
  k -n traefik port-forward svc/traefik 8443:443
else
  printf 'kubectl --context minikube -n traefik port-forward svc/traefik 8443:443\n'
fi
