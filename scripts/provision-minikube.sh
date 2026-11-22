#!/usr/bin/env bash
# Reexecutar reconcilia o ambiente e reutiliza os Secrets existentes.
# Após minikube delete, credenciais e dados precisam de fontes externas.
# Este script não faz backup nem restaura os dados dos PVCs.
set -Eeuo pipefail
umask 077

profile=minikube
# Os workflows atuais usam o runner self-hosted externo ao cluster.
arc=false
observability=true
serve=false
corporate_access=false
restore_secrets=false
private_repo=false
secrets_dir="${SECRETS_DIR:-infra/secrets}"

usage() {
  cat <<'HELP'
Uso: bash scripts/provision-minikube.sh [--com-arc] [--sem-observabilidade]
       [--repositorio-privado] [--restaurar-secrets] [--servir | --acesso-corporativo]

Instala a plataforma no perfil minikube. Reutiliza os Secrets existentes.
  --com-arc              Instala o ARC no cluster. Por padrão usa-se o runner externo.
  --sem-arc              Mantém o ARC fora deste provisionamento (padrão).
  --repositorio-privado Solicita usuário e token HTTPS para o Argo CD.
  --restaurar-secrets    Lê backups SOPS de Harbor, SonarQube, Grafana, Git e ARC.
                        O backup do ARC é usado somente com --com-arc.
                        Configure SECRETS_DIR e SOPS_AGE_KEY_FILE.
  --servir              Mantém o port-forward HTTPS na porta local 8443.
  --acesso-corporativo  Abre o Traefik com minikube service, sem editar /etc/hosts.

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
    --com-arc) arc=true ;;
    --sem-arc) arc=false ;;
    --repositorio-privado) private_repo=true ;;
    --sem-observabilidade) observability=false ;;
    --restaurar-secrets) restore_secrets=true ;;
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

if "$serve" && "$corporate_access"; then
  die 'Escolha --servir ou --acesso-corporativo.'
fi

for cmd in docker minikube kubectl helm git jq yq openssl; do
  command -v "$cmd" >/dev/null || die "Instale $cmd antes de executar."
done
if "$restore_secrets"; then
  command -v sops >/dev/null || die 'Instale sops para restaurar Secrets.'
  [[ -r "${SOPS_AGE_KEY_FILE:-}" && -f "${SOPS_AGE_KEY_FILE:-}" ]] ||
    die 'Configure SOPS_AGE_KEY_FILE com a chave age guardada fora do cluster.'
  [[ -d "$secrets_dir" ]] || die "Diretório de backups SOPS inexistente: $secrets_dir."
  if [[ ! -f "$secrets_dir/harbor.enc.yaml" && ! -f "$secrets_dir/sonarqube.enc.yaml" &&
        ! -f "$secrets_dir/gitops-repo.enc.yaml" ]] &&
    ! { "$observability" && [[ -f "$secrets_dir/grafana.enc.yaml" ]]; } &&
    ! { "$arc" && [[ -f "$secrets_dir/arc.enc.yaml" ]]; }; then
    die 'Nenhum backup SOPS para os componentes selecionados.'
  fi
fi
yq --version | grep -Eq 'mikefarah/yq.*v4\.' || die 'Use o yq v4 de mikefarah.'
docker info >/dev/null || die 'Inicie o Docker Desktop.'

repo=$(yq -r '.spec.source.repoURL' infra/gitops/bootstrap/root-app.yaml)
branch=$(yq -r '.spec.source.targetRevision' infra/gitops/bootstrap/root-app.yaml)
log "Conferindo a revisão que o Argo CD vai ler ($branch)"
git fetch --no-tags "$repo" "$branch" ||
  die "Confirme o acesso do Git desta máquina a $repo ($branch). A opção --repositorio-privado configura o acesso separado do Argo CD."
revision=$(git rev-parse FETCH_HEAD)
# Documentação local em edição não muda os manifests nem o build.
gitops_paths=(infra/gitops infra/security helm/pocapp app ':(exclude,glob)**/*.md')
git diff --quiet "$revision" -- "${gitops_paths[@]}" ||
  die "Publique os manifests e o código da aplicação em $branch e alinhe o clone com essa revisão. SHA remoto: $revision."
untracked=$(git ls-files --others --exclude-standard -- "${gitops_paths[@]}")
[[ -z "$untracked" ]] || die 'Há arquivos não versionados nas pastas do provisionamento. Confira git status.'
printf 'SHA GitOps: %s\n' "$revision"

# Arquivos temporários com permissão restrita para a emissão do TLS e os prompts.
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

# O Argo CD também pode ter cadastrado esse repositório com um nome gerado.
gitops_repo_configured() {
  local matches
  if secret_exists argocd provision-gitops-repo; then
    return 0
  fi
  matches=$(a --request-timeout=10s get secrets -l argocd.argoproj.io/secret-type=repository -o json |
    jq -r --arg repo "$repo" '
      def normalize: sub("/+$"; "") | sub("\\.git$"; "");
      any(.items[]; ((.data.url // "") | @base64d | normalize) == ($repo | normalize))
    ') || die 'Não foi possível consultar o cadastro Git no Argo CD.'
  [[ "$matches" == true ]]
}

# Restaura somente o Secret esperado. kubectl create preserva um Secret que
# surgir entre a consulta e a criação. O YAML claro passa apenas pelo pipe.
restore_secret() {
  local file=$1 ns=$2 name=$3
  shift 3
  [[ -f "$file" ]] || return 0
  if secret_exists "$ns" "$name"; then
    log "Preservando Secret existente $ns/$name"
    return 0
  fi
  log "Restaurando Secret $ns/$name do backup SOPS"
  if ! sops decrypt --output-type json "$file" |
    jq -cse --arg ns "$ns" --arg name "$name" --arg repo "$repo" '
      def repository_secret: $ns == "argocd" and $name == "provision-gitops-repo";
      def value($key): .stringData[$key] // ((.data[$key] // "") | @base64d);
      if length == 1 and (.[0] |
        .apiVersion == "v1" and .kind == "Secret"
        and .metadata.namespace == $ns and .metadata.name == $name
        and ((.type // "Opaque") == "Opaque")
        and ((.data // {}) | type == "object")
        and ((.stringData // {}) | type == "object")
        and ((.data // {}) + (.stringData // {}) |
          . as $values | all($ARGS.positional[];
            ($values[.] | type == "string" and length > 0)))
        and ((repository_secret | not) or (value("type") == "git" and value("url") == $repo)))
      then .[0] | {
        apiVersion, kind, metadata: {name: $name, namespace: $ns},
        type: "Opaque", data: (.data // {}), stringData: (.stringData // {})
      }
      | if repository_secret then .metadata.labels["argocd.argoproj.io/secret-type"] = "repository" else . end
      else error("O backup precisa conter somente o Secret esperado e seus dados obrigatórios.")
      end
    ' --args "$@" | k create -f -; then
    die "Falha ao restaurar $ns/$name de $file."
  fi
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

# As operações manuais usam prune=false. Cada Application mantém sua própria
# política de auto-sync. A retenção de dados depende também de PVC/PV e chart.
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

pocapp_image_cached() {
  m image ls | awk -v image="$1" '
    $0 == image || $0 == "docker.io/" image || $0 == "docker.io/library/" image { found = 1 }
    END { exit !found }
  '
}

# 1. Bootstrap. Preserva o perfil e prepara o Argo CD e as APIs usadas pelas apps.
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
if "$restore_secrets" && [[ -f "$secrets_dir/gitops-repo.enc.yaml" ]]; then
  if gitops_repo_configured; then
    log 'Preservando o cadastro Git existente no Argo CD'
  else
    restore_secret "$secrets_dir/gitops-repo.enc.yaml" argocd provision-gitops-repo type url username password
  fi
fi
if { "$private_repo" || [[ -n "${GITOPS_USERNAME:-}${GITOPS_TOKEN:-}" ]]; } &&
  ! gitops_repo_configured; then
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
if "$observability"; then namespace observability; fi

# 2. Credenciais. Restaura os backups disponíveis antes dos prompts.
if "$restore_secrets"; then
  restore_secret "$secrets_dir/harbor.enc.yaml" harbor harbor-admin HARBOR_ADMIN_PASSWORD
  restore_secret "$secrets_dir/sonarqube.enc.yaml" sonarqube sonarqube-monitoring monitoringPasscode
  if "$observability"; then
    restore_secret "$secrets_dir/grafana.enc.yaml" observability grafana-admin admin-user admin-password
  fi
fi

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
  if "$restore_secrets"; then
    restore_secret "$secrets_dir/arc.enc.yaml" arc-runners arc-github-app \
      github_app_id github_app_installation_id github_app_private_key
  fi
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
  pocapp_image_cached "$image_repo:$image_tag" || die "O archive não disponibilizou a imagem esperada: $image_repo:$image_tag."
elif [[ "$image_repo" == healthz-api && "$pull_policy" != Always ]]; then
  if pocapp_image_cached "$image_repo:$image_tag"; then
    printf 'Reutilizando a imagem local %s:%s.\n' "$image_repo" "$image_tag"
  elif [[ "$image_tag" == 1.0.0 ]]; then
    m image build -t "$image_repo:$image_tag" ./app
  else
    die "A imagem local $image_repo:$image_tag está ausente. Forneça o artefato exato em POCAPP_IMAGE_ARCHIVE."
  fi
else
  printf 'POCAPP usará %s:%s. O registry e a tag precisam estar disponíveis para o Minikube.\n' "$image_repo" "$image_tag"
fi

# 3. GitOps. Cria o pai depois que os Secrets e a imagem estiverem disponíveis.
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
if ! "$arc"; then printf 'ARC fora deste provisionamento. Use --com-arc para instalá-lo.\n'; fi
if ! "$observability"; then printf 'Observabilidade omitida por opção.\n'; fi
if a get secret argocd-initial-admin-secret >/dev/null 2>&1; then
  printf "Para obter a senha inicial do Argo CD, consulte argocd-initial-admin-secret no namespace argocd.\n"
fi
# As HTTPRoutes usam o hostname e o TLS termina no listener websecure.
if "$corporate_access"; then
  log 'Acesso corporativo pelo Traefik'
  printf 'Use a porta encaminhada para websecure. Se houver túnel, mantenha este terminal aberto.\n'
  printf 'Abra https://argocd.localhost:PORTA_HTTPS; substitua PORTA_HTTPS pela porta anunciada.\n'
  printf '%s\n' "Teste local para o túnel: curl -k --noproxy '*' --resolve 'sonarqube.localhost:PORTA_HTTPS:127.0.0.1' 'https://sonarqube.localhost:PORTA_HTTPS/api/server/version'"
  m service traefik -n traefik --url
elif "$serve"; then
  printf 'Abra https://argocd.localhost:8443. O TLS local é autoassinado.\n'
  k -n traefik port-forward svc/traefik 8443:443
else
  printf 'Acesso local com porta fixa ou pelo encaminhamento do Minikube:\n'
  printf 'kubectl --context minikube -n traefik port-forward svc/traefik 8443:443\n'
  printf 'minikube -p minikube service traefik -n traefik --url\n'
fi
