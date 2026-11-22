#!/usr/bin/env bash
# Provisionamento Minikube + Argo CD + Harbor + SonarQube + Traefik.
# Reexecutar preserva Secrets existentes; destruir Minikube remove dados locais.
# Para reconstrução, use credenciais externas e backups separados dos PVCs.
# Falha imediatamente em erros, variáveis ausentes e falhas em pipes.
set -Eeuo pipefail
umask 077

# Configurações: ARC desativado por padrão (runner self-hosted externo ao cluster).
profile=minikube
arc=false
observability=true
serve=false
corporate_access=false
restore_secrets=false
secrets_dir="${SECRETS_DIR:-infra/secrets}"

# Ajuda de uso e opções disponíveis.
usage() {
  cat <<'HELP'
Uso: bash scripts/provision-minikube.sh [--com-arc] [--sem-observabilidade] [--restaurar-secrets] [--servir] [--acesso-corporativo]

Instala a plataforma no perfil minikube. Preserva Secrets existentes.
--restaurar-secrets: restaura arquivos *.enc.yaml criptografados com SOPS antes do GitOps.
--acesso-corporativo: abre túnel do Traefik com `minikube service traefik -n traefik --url`.
  Útil em ambientes corporativos sem sudo ou acesso ao /etc/hosts; portas dinâmicas.
  NÃO salva Secrets fora do cluster. O túnel termina com Ctrl+C.
--servir: abre túnel HTTPS com porta fixa 8443 via kubectl port-forward.
  Exemplo: https://argocd.localhost:8443 (sem editar /etc/hosts, se *.localhost
  resolver para loopback e a HTTPRoute/Gateway aceitar o hostname).
  O túnel permanece ativo até Ctrl+C. Certificado autoassinado pode gerar aviso.
  Não use --servir e --acesso-corporativo juntos: o script prioriza o segundo.
--com-arc: instala o Actions Runner Controller dentro do cluster (opcional).
  Não é necessário para runner self-hosted instalado fora do Kubernetes.
Configure SOPS_AGE_KEY_FILE com a chave privada age armazenada fora do cluster.
Variáveis opcionais para provisionamento sem prompts:
  HARBOR_ADMIN_PASSWORD, SONAR_MONITORING_PASSCODE, GRAFANA_PASSWORD
  ARC_APP_ID, ARC_INSTALLATION_ID, ARC_PRIVATE_KEY_FILE
  GITOPS_USERNAME e GITOPS_TOKEN (repositório Git privado por HTTPS)
  POCAPP_IMAGE_ARCHIVE (arquivo de imagem para carregar no Minikube)
  POCAPP_DOCKER_CONFIG (config.json de pull para o registry privado)
HELP
}

# Processa as opções informadas na linha de comando.
while (( $# )); do
  case "$1" in
    --com-arc) arc=true ;;
    --sem-arc) arc=false ;;
    --restaurar-secrets) restore_secrets=true ;;
    --sem-observabilidade) observability=false ;;
    --servir) serve=true ;;
    --acesso-corporativo) corporate_access=true ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'Opção desconhecida: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

# Trabalha sempre a partir da raiz do repositório.
cd "$(dirname "${BASH_SOURCE[0]}")/.."
log() { printf '\n==> %s\n' "$*"; }
die() { printf 'Erro: %s\n' "$*" >&2; exit 1; }
trap 'printf "Falha na linha %s. Corrija o erro acima e rode o script novamente.\n" "$LINENO" >&2' ERR

# Confere dependências locais antes de modificar o cluster.
for cmd in docker minikube kubectl helm git jq yq openssl; do
  command -v "$cmd" >/dev/null || die "Instale $cmd antes de executar."
done
yq --version | grep -Eq 'mikefarah/yq.*v4\.' || die 'Use o yq v4 de mikefarah.'
docker info >/dev/null || die 'Inicie o Docker Desktop.'

# Valida se o checkout local está alinhado com o Git remoto usado pelo Argo CD.
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

# Cria área temporária para credenciais e certificado, removida ao sair.
scratch=$(mktemp -d)
cleanup() {
  rm -f -- "$scratch"/tls.crt "$scratch"/tls.key "$scratch"/username "$scratch"/password
  rmdir -- "$scratch"
}
trap cleanup EXIT

# Atalhos para kubectl/minikube e Applications do Argo CD.
k() { kubectl --context "$profile" "$@"; }
a() { k -n argocd "$@"; }
m() { minikube -p "$profile" "$@"; }
app() { a --request-timeout=10s get applications.argoproj.io "$@"; }

# Aguarda uma condição com tentativas a cada quatro segundos.
poll() {
  local timeout=$1 description=$2 deadline
  shift 2
  deadline=$((SECONDS + timeout))
  until "$@"; do
    (( SECONDS < deadline )) || { printf 'Tempo esgotado: %s\n' "$description" >&2; return 1; }
    sleep 4
  done
}

# Garante a existência do namespace sem excluí-lo.
namespace() {
  k create namespace "$1" --dry-run=client -o yaml | k apply -f -
}

# Consulta Secret no cluster ATUAL: não é backup nem restauração.
secret_exists() {
  local found
  found=$(k --request-timeout=10s -n "$1" get secret "$2" --ignore-not-found -o name) ||
    die "Não foi possível consultar o Secret $1/$2."
  [[ -n "$found" ]]
}

# Solicita uma credencial ausente; senhas são digitadas sem eco.
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

# Reutiliza o Secret se existir; caso contrário solicita/cria um novo.
# Depois de `minikube delete`, o Secret anterior não estará disponível.
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

# Confere sincronização, saúde e opcionalmente SHA da Application.
app_ready() {
  app "$1" -o json 2>/dev/null | jq -e --arg mode "$2" --arg sha "${3:-}" '
    .status.sync.status == "Synced"
    and (.operation == null)
    and ($mode == "sync" or .status.health.status == "Healthy")
    and ($sha == "" or .status.sync.revision == $sha)
  ' >/dev/null
}

# Aguarda a Application atingir o estado esperado.
wait_app() {
  local name=$1 timeout=$2 mode=${3:-health} sha=${4:-}
  if ! poll "$timeout" "Application $name ($mode)" app_ready "$name" "$mode" "$sha"; then
    app "$name" -o json | jq '{sync: .status.sync, health: .status.health, conditions: .status.conditions, operation: .status.operationState.message}'
    die "Confira os eventos e o estado da Application $name no Argo CD."
  fi
}

# Confere o resultado da sincronização solicitada por este script.
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

# Sincroniza via Argo CD, com prune:false nesta operação.
# Políticas automáticas de sync/prune devem ser verificadas separadamente.
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

# Verifica se HTTPRoute foi aceita pelo Traefik e resolveu referências.
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

# Aguarda a rota e mostra diagnóstico se não estiver pronta.
check_route() {
  if ! poll 180 "rota $1/$2" route_ready "$1" "$2"; then
    k -n "$1" describe httproute "$2"
    die "A rota $1/$2 não foi aceita pelo Traefik."
  fi
}

# Consulta a saúde de um serviço pela API do Kubernetes.
service_healthy() {
  k --request-timeout=10s get --raw="$1" 2>/dev/null | jq -e '.status == "healthy"' >/dev/null
}

# ETAPA 1: BOOTSTRAP — inicia Minikube, sem apagá-lo, e habilita métricas.
# PVCs existentes só sobrevivem enquanto os dados do cluster forem mantidos.
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

# ETAPA 1: instala Argo CD e aplica os projetos de acesso do GitOps.
log 'Instalando Argo CD e AppProjects'
helm repo add argo https://argoproj.github.io/argo-helm --force-update
helm --kube-context "$profile" upgrade --install argocd argo/argo-cd --version 10.18.2 \
  -n argocd --create-namespace -f infra/gitops/helm-values/argocd-resources.yaml \
  --wait --timeout 10m
k wait --for=condition=Established crd/applications.argoproj.io --timeout=120s
k apply -f infra/gitops/projects/
# Para repositório Git privado, registra credenciais HTTPS no Argo CD.
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

# ETAPA 2: prepara CRDs Gateway API, namespaces, TLS e Secrets.
# Os Secrets precisam existir antes de sincronizar as aplicações dependentes.
log 'Preparando Gateway API, TLS e credenciais'
k apply --server-side \
  -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.1/standard-install.yaml
k wait --for=condition=Established --timeout=120s \
  crd/gateways.gateway.networking.k8s.io crd/httproutes.gateway.networking.k8s.io
for ns in traefik harbor sonarqube apps; do namespace "$ns"; done
# Em cluster novo, restaure os Secrets ANTES das aplicações GitOps.
# Esta opção não sobrescreve Secrets já existentes: é voltada a reconstrução.
# Opcional: restaura arquivos SOPS criptografados usando chave age externa.
# Usa kubectl create: falha se o mesmo Secret já existir.
# NÃO restaura dados de PVCs, imagens do Harbor ou bancos de dados.
if "$restore_secrets"; then
  command -v sops >/dev/null || die 'Instale sops para restaurar Secrets.'
  [[ -n "${SOPS_AGE_KEY_FILE:-}" && -r "${SOPS_AGE_KEY_FILE:-}" ]] ||
    die 'Configure SOPS_AGE_KEY_FILE com um arquivo de chave age legível.'
  [[ -d "$secrets_dir" ]] || die "Diretório de Secrets inexistente: $secrets_dir"
  shopt -s nullglob
  encrypted_files=("$secrets_dir"/*.enc.yaml)
  (( ${#encrypted_files[@]} > 0 )) || die "Nenhum arquivo *.enc.yaml em $secrets_dir"
  for encrypted_file in "${encrypted_files[@]}"; do
    log "Restaurando Secrets de $encrypted_file"
    # A restauração deve ocorrer em cluster novo; create impede sobrescrever recursos.
    sops --decrypt "$encrypted_file" | k create -f -
  done
  shopt -u nullglob
fi
# Cria certificado local autoassinado apenas se o Secret estiver ausente.
if ! secret_exists traefik local-selfsigned-tls; then
  openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout "$scratch/tls.key" -out "$scratch/tls.crt" -subj '/CN=*.localhost' \
    -addext 'subjectAltName=DNS:*.localhost,DNS:*.local'
  k -n traefik create secret tls local-selfsigned-tls \
    --key="$scratch/tls.key" --cert="$scratch/tls.crt"
fi
# Credenciais do Harbor e SonarQube: não sobrescreve valores existentes.
password_secret harbor harbor-admin HARBOR_ADMIN_PASSWORD HARBOR_ADMIN_PASSWORD 'Senha inicial do Harbor'
password_secret sonarqube sonarqube-monitoring monitoringPasscode SONAR_MONITORING_PASSCODE 'Passcode de monitoramento do SonarQube'

# ARC é opcional; não é necessário para o runner self-hosted instalado fora do cluster.
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
# Configura a senha do Grafana quando observabilidade está habilitada.
if "$observability"; then
  namespace observability
  password_secret observability grafana-admin admin-password GRAFANA_PASSWORD 'Senha inicial do Grafana' \
    --from-literal=admin-user=admin
fi

# Prepara a imagem da aplicação (registry, arquivo local ou build local).
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

# ETAPA 3: GITOPS — aplica App of Apps; Argo CD gerencia as aplicações.
log 'Criando Applications filhas pelo platform-root'
k apply -f infra/gitops/bootstrap/root-app.yaml
wait_app platform-root 240 sync "$revision"

# Sincroniza Traefik, Harbor, SonarQube e suas rotas em ordem.
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

# Verifica Kyverno e suas políticas de segurança.
log 'Validando Kyverno e sincronizando a política'
wait_app kyverno 480
k wait --for=condition=Established crd/validatingpolicies.policies.kyverno.io --timeout=120s
sync_app kyverno-policies 300 sync

# Verifica a aplicação de exemplo e endpoint de saúde.
log 'Validando a POCAPP'
wait_app pocapp 480 health "$revision"
check_route apps pocapp
poll 120 'endpoint /healthz da POCAPP' service_healthy '/api/v1/namespaces/apps/services/http:pocapp:80/proxy/healthz'

if "$arc"; then
# Só instala ARC quando solicitado com --com-arc.
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
# Instala Prometheus, Loki, Alloy e rota do Grafana se habilitado.
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

# Mostra estado das aplicações, PVCs, rotas e recursos do Minikube.
# Listar PVCs não significa salvar seus dados em backup.
log 'Verificação final'
a get applications.argoproj.io
k get pvc -A
k get gateway,httproute -A
docker stats --no-stream "$profile"
printf '\nProvisionamento concluído para a revisão %s.\n' "$revision"
if ! "$arc"; then printf 'ARC omitido por padrão.\n'; fi
if ! "$observability"; then printf 'Observabilidade omitida por opção.\n'; fi
if a get secret argocd-initial-admin-secret >/dev/null 2>&1; then
  printf "Para obter a senha inicial do Argo CD, consulte argocd-initial-admin-secret no namespace argocd.\n"
fi
# ACESSO LOCAL AO TRAEFIK (INCLUSIVE AMBIENTE CORPORATIVO SEM SUDO)
# ---------------------------------------------------------------
# Não é obrigatório editar /etc/hosts para acessar https://argocd.localhost:8443:
# domínios *.localhost normalmente resolvem para o loopback 127.0.0.1.
# Condições: resolução local funcionando, túnel ativo, listener HTTPS no Traefik,
# HTTPRoute com hostname argocd.localhost e TLS configurado corretamente.
# Teste DNS/resolução: curl -k -I --resolve argocd.localhost:8443:127.0.0.1 \
#   https://argocd.localhost:8443
# O parâmetro --resolve força o endereço apenas para o curl; não altera /etc/hosts.
# Certificados autoassinados podem gerar alerta no navegador; -k é só para teste.
#
# OPÇÃO --servir (porta fixa):
#   kubectl --context minikube -n traefik port-forward svc/traefik 8443:443
#   https://argocd.localhost:8443
#   https://sonarqube.localhost:8443
#   https://harbor.localhost:8443
#   https://grafana.localhost:8443
# Os exemplos dependem dos hostnames reais das HTTPRoutes.
# Esta opção é preferível para configurar endpoints estáveis no runner self-hosted.
#
# OPÇÃO --acesso-corporativo (portas dinâmicas):
#   minikube service traefik -n traefik --url
# O Minikube com driver Docker pode criar um túnel local com portas dinâmicas.
# As URLs 127.0.0.1:PORTA são entradas do Traefik, não URLs específicas dos apps.
# Para testar uma HTTPRoute com host sonarqube.localhost pela porta HTTP:
#   curl -i -H 'Host: sonarqube.localhost' \
#     http://127.0.0.1:PORTA_HTTP/api/server/version
# HTTP 404 pode significar hostname, rota ou entrypoint incorreto.
# Em ambos os modos, mantenha o terminal aberto; Ctrl+C encerra o túnel.
# Nenhum dos dois modos restaura ou exporta Kubernetes Secrets/PVCs.
if "$corporate_access"; then
  log 'Acesso corporativo: expondo Traefik sem modificar /etc/hosts'
  printf 'O Minikube mostrará as URLs locais do Traefik. Mantenha este processo aberto.\n'
  printf 'Exemplo de teste (substitua PORTA_HTTP):\n'
  printf "curl -i -H 'Host: sonarqube.localhost' http://127.0.0.1:PORTA_HTTP/api/server/version\n"
  printf 'Confira os hostnames reais: kubectl --context minikube get httproute -A\n'
  m service traefik -n traefik --url
elif "$serve"; then
  # Porta fixa HTTPS; requer que a rota e o certificado TLS estejam configurados.
  printf 'Traefik HTTPS em https://127.0.0.1:8443 (use o hostname da HTTPRoute).\n'
  k -n traefik port-forward svc/traefik 8443:443
else
  printf 'Acesso HTTPS via porta fixa: kubectl --context minikube -n traefik port-forward svc/traefik 8443:443\n'
  printf 'Sem acesso a /etc/hosts, *.localhost normalmente funciona com --servir; alternativa: --acesso-corporativo\n'
  printf 'Ou rode diretamente: minikube service traefik -n traefik --url\n'
fi
