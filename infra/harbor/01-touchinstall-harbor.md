## INSTALL HARBOR ##

helm repo add harbor https://helm.goharbor.io
helm repo update
helm search repo harbor/harbor --versions | head


kubectl create namespace harbor

k -n harbor create secret generic harbor-admin \
  --from-literal=HARBOR_ADMIN_PASSWORD='admin' \
  --dry-run=client -o yaml | k apply -f -
