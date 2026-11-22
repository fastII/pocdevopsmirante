# Instalar SonarQube Community

[Voltar ao README](../../README.md)

## 1. Preparar o Secret de monitoramento

Execute no shell Bash.

~~~bash
kubectl create namespace sonarqube --dry-run=client -o yaml | kubectl apply -f -
read -rs -p 'Passcode de monitoramento do SonarQube: ' SONAR_MONITORING_PASSCODE
kubectl -n sonarqube create secret generic sonarqube-monitoring \
  --from-literal=monitoringPasscode="$SONAR_MONITORING_PASSCODE" \
  --dry-run=client -o yaml | kubectl apply -f -
unset SONAR_MONITORING_PASSCODE
~~~

## 2. Sincronizar e validar

Após o `platform-root` criar a Application `sonarqube`, aguarde o sync automático.

~~~bash
argocd app wait sonarqube --sync --health --timeout 600
kubectl -n sonarqube get pods,pvc,svc
~~~

O chart `2026.5.1005` usa banco embutido nesta configuração da POC. Para usar PostgreSQL, provisione o banco separadamente e configure `jdbcOverwrite` com um Secret. O bloco antigo `postgresql` era ignorado pelo chart. O contêiner principal usa request de `400m / 1536Mi` e limite de `1500m / 2Gi`. Os init containers também têm resources definidos. [Values do SonarQube](../gitops/helm-values/sonarqube.yaml)

## 3. Conectar ao pipeline

Após sincronizar `platform-routes`, acesse `http://sonarqube.localhost:8080` com o provisionador em `--servir`, configure o projeto `pocapp` e gere o token de análise para `SONAR_TOKEN`. Com o runner na máquina do Minikube, deixe `SONAR_HOST_URL` vazia para o scanner e o Quality Gate usarem um túnel HTTP próprio em loopback. O workflow também usa esse túnel quando recebe a URL antiga `https://sonarqube.localhost:8443`. Para um SonarQube remoto, configure uma URL acessível ao runner com DNS e TLS válidos. [Workflow de CI/CD](../../.github/workflows/pocapp-ci-cd.yaml)
