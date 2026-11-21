O ponto principal é entender que, quando utilizamos Argo CD com Helm, o Helm normalmente atua como gerador dos manifestos Kubernetes, enquanto o Argo CD controla a implantação e a sincronização.
1. Helm rollback vs. Argo CD rollback
Operação	             Helm CLI	                     Argo CD
Instalar aplicação	   helm install	                Sincronização da Application
Atualizar aplicação	   helm upgrade	                Sincronização após alteração no Git
Consultar histórico	   helm history	                Histórico da Application
Reverter versão	       helm rollback	            Restaurar versão anterior no Git e sincronizar
Executar pela pipeline	    Sim	                    Sim
Fonte de verdade	   Estado do release Helm	    Repositório Git

Por que não usar helm rollback nesse cenário?

Quando o Argo CD utiliza um Helm Chart diretamente do Git, ele executa a renderização dos templates e aplica os recursos Kubernetes. Normalmente não existe um release Helm gerenciado pelo Helm CLI para executar helm rollback.

Além disso, se o Argo CD estiver configurado com sincronização automática, qualquer alteração manual que não corresponda ao Git poderá ser revertida na próxima reconciliação.

## SOLUÇÃO ##

01) fazer procedimento de rollback utilizando o argocd
02) criar gitflow pipeline para rollback
