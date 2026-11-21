# Configurar a GitHub App do ARC

[Voltar ao runbook](../../../RUNBOOK.md)

O ARC Controller gerencia os runners. O listener recebe jobs por uma conexão de saída com o GitHub e cria runners sob demanda com Docker-in-Docker (DinD).

1. Em **Settings → Developer settings → GitHub Apps**, crie a app com um nome disponível e a URL do projeto como homepage.
2. Desative o webhook. Deixe os campos opcionais de callback e setup em branco para este fluxo.
3. Para o scale set vinculado ao repositório, configure **Repository permissions → Administration: Read and write** e **Metadata: Read-only**. Instale a app no repositório da POC. [Autenticação do ARC](https://docs.github.com/en/actions/how-tos/manage-runners/use-actions-runner-controller/authenticate-to-the-api)
4. Registre App ID e Installation ID. Gere a chave privada e guarde o PEM fora do Git. Se uma chave já tiver sido versionada, revogue-a no GitHub e atualize o Secret com uma chave nova.
5. Crie o Secret arc-github-app e instale o controller e o scale set pelo [procedimento de instalação](README.md).

O scale set arc-minikube mantém zero runners ociosos e permite um runner simultâneo. O pod reserva 500m de CPU e 768Mi de memória e tem limite conjunto de 1500m e 2Gi para runner e DinD. [Application do scale set](argo/scaleset.yaml)
