## INSTALL CERTS ##

openssl req -x509 \
  -nodes \
  -days 365 \
  -newkey rsa:2048 \
  -keyout certs/local.key \
  -out certs/local.crt \
  -subj "/CN=*.local" \
  -addext "subjectAltName=DNS:*.local"


kubectl create secret tls local-selfsigned-tls \
  --cert=certs/local.crt \
  --key=certs/local.key \
  -n traefik \
  --dry-run=client -o yaml | kubectl apply -f -
