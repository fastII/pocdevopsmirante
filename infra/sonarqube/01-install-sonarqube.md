# Instalar SonarQube Community

[Voltar ao runbook](../../RUNBOOK.md)

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

Após o `platform-root` criar a Application `sonarqube`, faça o sync manual da filha se o provisionamento foi iniciado sem o script.

~~~bash
argocd app sync sonarqube
argocd app wait sonarqube --sync --health --timeout 600
kubectl -n sonarqube get pods,pvc,svc
~~~

O chart `2026.5.1005` usa banco embutido nesta configuração da POC. Para usar PostgreSQL, provisione o banco separadamente e configure `jdbcOverwrite` com um Secret. O bloco antigo `postgresql` era ignorado pelo chart. O contêiner principal usa request de `400m / 1536Mi` e limite de `1500m / 2Gi`. Os init containers também têm resources definidos. [Values do SonarQube](../gitops/helm-values/sonarqube.yaml)

## 3. Conectar ao pipeline

Após sincronizar `platform-routes`, acesse a interface, configure o projeto `pocapp` e gere um token de análise para `SONAR_TOKEN`. Configure `SONAR_HOST_URL` com uma URL acessível a partir do pod runner. Valide DNS, conectividade e confiança TLS desse ambiente. [Workflow de CI/CD](../../.github/workflows/pocapp-ci-cd.yaml)
