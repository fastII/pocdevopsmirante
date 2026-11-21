#!/usr/bin/env bash
set -Eeuo pipefail

# POC: Minikube + Codex CLI + Kubernetes MCP (somente leitura).
# Requer macOS, Docker Desktop/Colima com daemon Docker acessível, kubectl,
# minikube, Node.js/npm e Codex CLI. Não instala dependências automaticamente.

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
fail() { printf 'ERRO: %s\n' "$*" >&2; exit 1; }
for cmd in docker minikube kubectl node npm npx codex; do
  command -v "$cmd" >/dev/null 2>&1 || fail "Comando ausente: $cmd. Instale-o antes de continuar."
done

docker info >/dev/null 2>&1 || fail 'Docker daemon indisponível. Inicie Docker Desktop ou Colima.'

log 'Iniciando Minikube (Docker, 4 CPUs, 8192 MB)'
minikube start --driver=docker --cpus=4 --memory=8192

log 'Validando cluster Minikube'
kubectl --context=minikube get nodes
kubectl --context=minikube get pods -A

CONFIG_DIR="${HOME}/.config/codex-minikube-mcp"
mkdir -p "$CONFIG_DIR"
chmod 700 "$CONFIG_DIR"

# Copia apenas o contexto Minikube, sem alterar o contexto padrão do usuário.
# ATENÇÃO: inicialmente contém credenciais do contexto minikube, que podem
# ser privilegiadas. O modo read-only do servidor MCP é uma defesa adicional,
# não um substituto para RBAC.
KUBECONFIG_FILE="$CONFIG_DIR/minikube.kubeconfig"
log 'Exportando kubeconfig dedicado ao Minikube'
kubectl config view --context=minikube --minify --flatten --raw > "$KUBECONFIG_FILE"
chmod 600 "$KUBECONFIG_FILE"

# O servidor MCP será iniciado via npx e terá acesso ao kubeconfig dedicado.
# Evita configurações não verificadas em TOML; usa a flag --read-only.
log 'Registrando servidor Kubernetes MCP no Codex'
if codex mcp get kubernetes-minikube >/dev/null 2>&1; then
  log 'Removendo registro antigo kubernetes-minikube para atualizar configuração'
  codex mcp remove kubernetes-minikube
fi
codex mcp add kubernetes-minikube \
  --env "KUBECONFIG=$KUBECONFIG_FILE" \
  -- npx -y kubernetes-mcp-server@latest --read-only

PROMPT_FILE="$CONFIG_DIR/prompt-sre.txt"
cat > "$PROMPT_FILE" <<'PROMPT'
Atue como Senior SRE. Use o servidor MCP kubernetes-minikube para inspecionar SOMENTE o cluster Minikube. Não altere nenhum recurso, não execute comandos de escrita e não consulte Secrets. Verifique nodes, pods, deployments, events, restarts, CrashLoopBackOff, OOMKilled, Pending, probes, requests/limits e HPA. Informe namespace, recurso, evidências, causa provável, severidade e recomendações. Antes de qualquer remediação, apresente um plano e solicite aprovação explícita. Não faça mudanças automaticamente.
PROMPT
chmod 600 "$PROMPT_FILE"

log 'Concluído'
printf 'Kubeconfig: %s\nPrompt: %s\n' "$KUBECONFIG_FILE" "$PROMPT_FILE"
printf '\nPróximos comandos:\n  codex login\n  codex mcp list\n  codex\n\nCole o conteúdo de %s no Codex.\n' "$PROMPT_FILE"
printf '\nAVISO: kubeconfig ainda pode ter privilégios elevados. Use RBAC mínimo antes de produção.\n'
