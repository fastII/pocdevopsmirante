# Criar o certificado TLS local

[Voltar ao runbook](../../RUNBOOK.md)

Use um diretório fora do repositório para guardar o certificado e a chave. O SAN cobre os hosts `.localhost` e `.local` usados nas rotas.

~~~bash
kubectl create namespace traefik --dry-run=client -o yaml | kubectl apply -f -
TLS_DIR=$(mktemp -d)
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout "$TLS_DIR/local.key" -out "$TLS_DIR/local.crt" \
  -subj '/CN=*.localhost' \
  -addext 'subjectAltName=DNS:*.localhost,DNS:*.local'
kubectl -n traefik create secret tls local-selfsigned-tls \
  --cert="$TLS_DIR/local.crt" --key="$TLS_DIR/local.key" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n traefik get secret local-selfsigned-tls
~~~

O listener `websecure` usa esse Secret. Para renovar, gere outro certificado e atualize o mesmo Secret. O navegador pode pedir confiança explícita por ser autoassinado. [Values do Traefik](../gitops/helm-values/traefik.yaml)
