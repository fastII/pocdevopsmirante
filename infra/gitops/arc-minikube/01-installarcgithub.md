### PROCEDIMENTO DE INSTALACAO ##

Owned by: @fastII

App ID: 5855867

Using your App ID to get installation tokens? You can now use your Client ID instead.

Client ID: Iv23liLQdi8ncuLWMp6k

k apply -f arc-minikube/manifests/namespaces.yaml 

k -n arc-runners create secret generic arc-github-app \
  --from-literal=github_app_id="" \
  --from-literal=github_app_installation_id="" \
  --from-file=github_app_private_key="$HOME/Documents/GitHub/pocdevopsmirante/infra/gitops/arc-minikube/arc-minikube-runne.2026-11-20.private-key.pem"