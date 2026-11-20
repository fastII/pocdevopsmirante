
## INSTALL ARGOCD ##

https://github.com/argoproj/argo-helm/blob/main/charts/argo-cd/values.yaml


helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  --set server.ingress.enabled=true \
  --set server.ingress.ingressClassName=traefik \
  --set server.ingress.hostname=argocd.local \
  --set server.ingress.path=/ \
  --set server.ingress.pathType=Prefix \
  --set configs.params."server\.insecure"=true \
  --wait


kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
