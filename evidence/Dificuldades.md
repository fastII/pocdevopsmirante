
## PROBLEMA OOMKilled - MINIKUBE ##

Dificuldade em provisionar o ambiente devido recursos de hardware no Mac

Ao subir a stack de observability o minikube apresentou falhas devido escassez de memoria (pressão controlplane), onde o container do Minikube está em execução, mas o API Server não está saudável porque a verificação do etcd falhou.

Como você está utilizando Minikube com driver Docker no macOS, e acabou de provisionar uma stack de observabilidade com Prometheus, Grafana, Loki e Alloy, precisamos investigar principalmente pressão de memória, disco e falhas do etcd.

No primeiro momento não realizei o minikube delete

Não execute minikube delete, minikube delete --all ou minikube start --delete-on-failure. Isso poderia destruir os recursos locais da sua POC.

## DEBUG AMBIENTE ##

docker stats --no-stream minikube
CONTAINER ID   NAME       CPU %     MEM USAGE / LIMIT   MEM %     NET I/O         BLOCK I/O      PIDS
3f5a8b6c7409   minikube   201.08%   5.394GiB / 8GiB     67.42%    669MB / 317MB   996GB / 20GB   914

 docker inspect minikube \
  --format 'Memory={{.HostConfig.Memory}} CPUs={{.HostConfig.NanoCpus}} OOMKilled={{.State.OOMKilled}}'
Memory=8589934592 CPUs=2000000000 OOMKilled=false

docker exec minikube crictl ps -a --name etcd

docker exec minikube crictl logs --tail=100 "$ETCD_ID"

docker stats --no-stream minikube
CONTAINER ID   NAME       CPU %     MEM USAGE / LIMIT   MEM %     NET I/O         BLOCK I/O      PIDS
3f5a8b6c7409   minikube   201.08%   5.394GiB / 8GiB     67.42%    669MB / 317MB   996GB / 20GB   914
(.venv) anderson.oliveira@CACTUS-IS-0035 argocd % docker inspect minikube \
  --format 'Memory={{.HostConfig.Memory}} CPUs={{.HostConfig.NanoCpus}} OOMKilled={{.State.OOMKilled}}'
Memory=8589934592 CPUs=2000000000 OOMKilled=false
(.venv) anderson.oliveira@CACTUS-IS-0035 argocd % docker exec minikube df -h
docker exec minikube free -h
Filesystem      Size  Used Avail Use% Mounted on
overlay         224G   39G  174G  19% /
tmpfs            64M     0   64M   0% /dev
shm              64M  100K   64M   1% /dev/shm
tmpfs           4.9G   21M  4.9G   1% /run
tmpfs           4.9G  8.0K  4.9G   1% /tmp
/dev/vda1       224G   39G  174G  19% /var
overlay         990M  364K  990M   1% /usr/lib/modules
tmpfs           5.0M     0  5.0M   0% /run/lock
shm              64M     0   64M   0% /run/containerd/io.containerd.grpc.v1.cri/sandboxes/3b867477edabd3d0d97d3d96a8090356d15856e14b8a9041d0ceb8c888a2c1b2/shm
shm              64M     0   64M   0% /run/containerd/io.containerd.grpc.v1.cri/sandboxes/a74db10463019053ed801f378a2f56c3c073c8541ae65155b99b9bea27305c7e/shm
shm              64M     0   64M   0% /run/containerd/io.containerd.grpc.v1.cri/sandboxes/d58ea7e17f67b173fa0a349752dd8b6eb9364cc854800f1cbe04155f91ca65f9/shm
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/a74db10463019053ed801f378a2f56c3c073c8541ae65155b99b9bea27305c7e/rootfs
shm              64M     0   64M   0% /run/containerd/io.containerd.grpc.v1.cri/sandboxes/f314587a1cf4e9870fec1fbb8f54dc442a5b8cffa21200b72557bfb8cbeb1d6e/shm
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/3b867477edabd3d0d97d3d96a8090356d15856e14b8a9041d0ceb8c888a2c1b2/rootfs
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/d58ea7e17f67b173fa0a349752dd8b6eb9364cc854800f1cbe04155f91ca65f9/rootfs
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/f314587a1cf4e9870fec1fbb8f54dc442a5b8cffa21200b72557bfb8cbeb1d6e/rootfs
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/2d284cedc430d4915a59afc71d6cf4b746a82a54e4ba05fcbae0a28d0459055a/rootfs
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/4319de9bc5191c9b710678525de33bc74b18775c484de40c2448ff2192f984ee/rootfs
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/a830b65d36669b94c568005fdfbdace9dc007e3dd45919827e2e36a8de7c6fdb/rootfs
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/cad350b0b8fc4e43f0946930a2c1fe57dfa3a231dd9e70cdb97b05a007abf654/rootfs
tmpfs           9.7G   12K  9.7G   1% /var/lib/kubelet/pods/9e8f293d-ed94-4a2f-92a3-cbacf84a12ab/volumes/kubernetes.io~projected/kube-api-access-5hbhn
tmpfs            50M   12K   50M   1% /var/lib/kubelet/pods/9ce2d9d9-a3cb-4b7b-815c-16a5fc97b47e/volumes/kubernetes.io~projected/kube-api-access-pb5qh
shm              64M     0   64M   0% /run/containerd/io.containerd.grpc.v1.cri/sandboxes/369c52724fc204fcce88b530df1121a26eb13bf6882fade1b9cc2c1f305faab9/shm
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/369c52724fc204fcce88b530df1121a26eb13bf6882fade1b9cc2c1f305faab9/rootfs
shm              64M     0   64M   0% /run/containerd/io.containerd.grpc.v1.cri/sandboxes/a0735e48f9aebf8a392337e4e004c96c1a8d40060b3689873676926fc2a222cd/shm
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/a0735e48f9aebf8a392337e4e004c96c1a8d40060b3689873676926fc2a222cd/rootfs
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/fe7945c9f47a47bb362a62ea8ccefb21a96ec3401db5ab943ec045d45aae82dc/rootfs
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/01fa2c731805805443d8f34bd885703c2c962ab4061e45541c6c117fd7410263/rootfs
tmpfs           9.7G   12K  9.7G   1% /var/lib/kubelet/pods/5854f63f-c286-47b4-9dff-9a1516bec275/volumes/kubernetes.io~projected/kube-api-access-mwmc5
shm              64M     0   64M   0% /run/containerd/io.containerd.grpc.v1.cri/sandboxes/a7258c1183f260356a2f398538fa09f07d530b0106bdcb0796f8f8714093142e/shm
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/a7258c1183f260356a2f398538fa09f07d530b0106bdcb0796f8f8714093142e/rootfs
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/d1795c12f18ca192e5951d8c8fb50d3b00bb6f81add7973307a2398fd2d547c1/rootfs
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/e6036fbd75c75a452d6d23f6dd0e9d8ac023466bd2570310e77cd05dcc3bb4a2/rootfs
shm              64M     0   64M   0% /run/containerd/io.containerd.grpc.v1.cri/sandboxes/6792714ab5b5097e114b1986bdd0fb70874de588018db510e836b365c7b7c725/shm
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/6792714ab5b5097e114b1986bdd0fb70874de588018db510e836b365c7b7c725/rootfs
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/f599217378489c9be52a469c975885b2458302e2efabdf36813b18ce07863111/rootfs
tmpfs           9.7G   12K  9.7G   1% /var/lib/kubelet/pods/dc6b9ce2-704d-4e4f-ac0a-0199234bb4e4/volumes/kubernetes.io~secret/tls-secret
tmpfs           9.7G   12K  9.7G   1% /var/lib/kubelet/pods/dc6b9ce2-704d-4e4f-ac0a-0199234bb4e4/volumes/kubernetes.io~projected/kube-api-access-mtcdz
tmpfs           9.7G   12K  9.7G   1% /var/lib/kubelet/pods/ace18664-0b72-47e4-8908-ee2b9e21c556/volumes/kubernetes.io~projected/kube-api-access-z9szl
tmpfs           9.7G   12K  9.7G   1% /var/lib/kubelet/pods/625174ae-b5a6-4548-9c3b-0774ce3999f0/volumes/kubernetes.io~projected/kube-api-access-fvcr6
tmpfs           512M   12K  512M   1% /var/lib/kubelet/pods/8aacdf6e-3c3c-4e42-8712-524e028f163f/volumes/kubernetes.io~projected/kube-api-access-4cxqv
tmpfs           170M   12K  170M   1% /var/lib/kubelet/pods/fbb4ad86-c473-4b16-96e2-0c8efbce5cd0/volumes/kubernetes.io~projected/kube-api-access-st62x
tmpfs           170M   12K  170M   1% /var/lib/kubelet/pods/8f4787e3-b1b7-4eb3-a6e1-cde8e6e4b858/volumes/kubernetes.io~projected/kube-api-access-wbldx
tmpfs           1.0G     0  1.0G   0% /var/lib/kubelet/pods/c8f6dae7-2c8e-4649-9495-f6d8b038c0e5/volumes/kubernetes.io~secret/argocd-repo-server-tls
tmpfs           512M     0  512M   0% /var/lib/kubelet/pods/eeae561b-e770-4e18-afbd-32a24586d1cd/volumes/kubernetes.io~secret/argocd-repo-server-tls
tmpfs           9.7G     0  9.7G   0% /var/lib/kubelet/pods/3ee4fab7-ac33-4f31-8cc5-a9234f78729a/volumes/kubernetes.io~secret/argocd-dex-server-tls
tmpfs           1.0G   12K  1.0G   1% /var/lib/kubelet/pods/c8f6dae7-2c8e-4649-9495-f6d8b038c0e5/volumes/kubernetes.io~projected/kube-api-access-dhmsr
tmpfs           512M   12K  512M   1% /var/lib/kubelet/pods/eeae561b-e770-4e18-afbd-32a24586d1cd/volumes/kubernetes.io~projected/kube-api-access-26zlj
tmpfs           768M  4.0K  768M   1% /var/lib/kubelet/pods/c22c58a6-427c-4a71-b7c8-b54283832d9a/volumes/kubernetes.io~secret/secret-key
tmpfs           768M   32K  768M   1% /var/lib/kubelet/pods/c22c58a6-427c-4a71-b7c8-b54283832d9a/volumes/kubernetes.io~secret/token-service-private-key
tmpfs           9.7G   12K  9.7G   1% /var/lib/kubelet/pods/3ee4fab7-ac33-4f31-8cc5-a9234f78729a/volumes/kubernetes.io~projected/kube-api-access-lhsc6
tmpfs           256M   12K  256M   1% /var/lib/kubelet/pods/fc794ddf-371d-4c85-b9c4-53208ed83140/volumes/kubernetes.io~projected/kube-api-access-t57xr
tmpfs           512M     0  512M   0% /var/lib/kubelet/pods/90442f94-02b2-40a3-b8f3-d186f14c5d35/volumes/kubernetes.io~secret/argocd-dex-server-tls
tmpfs           512M     0  512M   0% /var/lib/kubelet/pods/90442f94-02b2-40a3-b8f3-d186f14c5d35/volumes/kubernetes.io~secret/argocd-repo-server-tls
tmpfs           256M     0  256M   0% /var/lib/kubelet/pods/96eea593-e0b4-4a2c-b083-3c625f5c8e01/volumes/kubernetes.io~secret/argocd-repo-server-tls
tmpfs           9.7G  4.0K  9.7G   1% /var/lib/kubelet/pods/7d9c35b0-fe0d-478d-b748-7e08f5a9aaa7/volumes/kubernetes.io~secret/registry-htpasswd
tmpfs           512M   12K  512M   1% /var/lib/kubelet/pods/90442f94-02b2-40a3-b8f3-d186f14c5d35/volumes/kubernetes.io~projected/kube-api-access-mspf6
tmpfs           9.7G   12K  9.7G   1% /var/lib/kubelet/pods/b20037e8-0e37-49e4-99b9-151ef9ae7d2e/volumes/kubernetes.io~projected/kube-api-access-xzm8t
tmpfs           256M   12K  256M   1% /var/lib/kubelet/pods/96eea593-e0b4-4a2c-b083-3c625f5c8e01/volumes/kubernetes.io~projected/kube-api-access-2jqbs
tmpfs           9.7G   12K  9.7G   1% /var/lib/kubelet/pods/7f5a59b3-7474-4db7-b260-f8572afa2341/volumes/kubernetes.io~projected/kube-api-access-gsf7m
shm              64M     0   64M   0% /run/containerd/io.containerd.grpc.v1.cri/sandboxes/d0b19474884957cb779c626733dcb22df77c7a5dffa616eaf665a7d559dd2b71/shm
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/d0b19474884957cb779c626733dcb22df77c7a5dffa616eaf665a7d559dd2b71/rootfs
shm              64M     0   64M   0% /run/containerd/io.containerd.grpc.v1.cri/sandboxes/f7006a77aa6c4cffaee76faf731d8284cdd2314fb155196ef539c393268362f4/shm
shm              64M     0   64M   0% /run/containerd/io.containerd.grpc.v1.cri/sandboxes/ef68611243a45c46566eeccc16e8ada251be8d884e5780c759a401ead65208d9/shm
shm              64M     0   64M   0% /run/containerd/io.containerd.grpc.v1.cri/sandboxes/6ccc2610739255a08159e61bdfbc80ff4d471c5db540ab5b139074454500c0cd/shm
shm              64M     0   64M   0% /run/containerd/io.containerd.grpc.v1.cri/sandboxes/016fab111d231354db895526396481fc26c803405e9a7b9141d043be41f0a95d/shm
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/f7006a77aa6c4cffaee76faf731d8284cdd2314fb155196ef539c393268362f4/rootfs
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/ef68611243a45c46566eeccc16e8ada251be8d884e5780c759a401ead65208d9/rootfs
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/6ccc2610739255a08159e61bdfbc80ff4d471c5db540ab5b139074454500c0cd/rootfs
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/016fab111d231354db895526396481fc26c803405e9a7b9141d043be41f0a95d/rootfs
shm              64M     0   64M   0% /run/containerd/io.containerd.grpc.v1.cri/sandboxes/3437237f2744d0bd93b446cd414b0e2f10c6735f5eee1076e109839eaf8c21f5/shm
shm              64M     0   64M   0% /run/containerd/io.containerd.grpc.v1.cri/sandboxes/64488a23d630bda1971c7a969d1c5603b4122451366858c8c1b37f444484c861/shm
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/3437237f2744d0bd93b446cd414b0e2f10c6735f5eee1076e109839eaf8c21f5/rootfs
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/64488a23d630bda1971c7a969d1c5603b4122451366858c8c1b37f444484c861/rootfs
shm              64M     0   64M   0% /run/containerd/io.containerd.grpc.v1.cri/sandboxes/94d8295a65d93d6f26035cf762939deda4f49dd338d7391a9eba718f3017202a/shm
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/94d8295a65d93d6f26035cf762939deda4f49dd338d7391a9eba718f3017202a/rootfs
shm              64M     0   64M   0% /run/containerd/io.containerd.grpc.v1.cri/sandboxes/610b50a684dec65fb4bc274bf3fd95de2c4f7dc2f83a31e796d60450fff41e2c/shm
shm              64M     0   64M   0% /run/containerd/io.containerd.grpc.v1.cri/sandboxes/24e503a4905c6be0441b26980de79baa446bd0a3e0e5e4c3180287fb6a3e41ff/shm
shm              64M     0   64M   0% /run/containerd/io.containerd.grpc.v1.cri/sandboxes/c677a4a0cb6e5e4ca1adffe25470e5ebb10392aa103fb7ef08a82b0f98208fb1/shm
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/610b50a684dec65fb4bc274bf3fd95de2c4f7dc2f83a31e796d60450fff41e2c/rootfs
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/24e503a4905c6be0441b26980de79baa446bd0a3e0e5e4c3180287fb6a3e41ff/rootfs
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/c677a4a0cb6e5e4ca1adffe25470e5ebb10392aa103fb7ef08a82b0f98208fb1/rootfs
shm              64M     0   64M   0% /run/containerd/io.containerd.grpc.v1.cri/sandboxes/292a032e694d211b56f5a55554c9ddd3e8e9419fa4fee6972cd15c0df49beecf/shm
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/292a032e694d211b56f5a55554c9ddd3e8e9419fa4fee6972cd15c0df49beecf/rootfs
shm              64M     0   64M   0% /run/containerd/io.containerd.grpc.v1.cri/sandboxes/6df9e787371fdeac1f162f64ec9d7626fa42274ecef1423f7934211711a3474d/shm
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/6df9e787371fdeac1f162f64ec9d7626fa42274ecef1423f7934211711a3474d/rootfs
shm              64M     0   64M   0% /run/containerd/io.containerd.grpc.v1.cri/sandboxes/737368608b6fd31839fd32510ef72b31ed44fd2408e39ccbe1388caef6e297a7/shm
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/737368608b6fd31839fd32510ef72b31ed44fd2408e39ccbe1388caef6e297a7/rootfs
shm              64M     0   64M   0% /run/containerd/io.containerd.grpc.v1.cri/sandboxes/47199f7e23f9c0a3bcc8a4461feb7f8b57e704d4ef3145118ad2b52b69463cf0/shm
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/47199f7e23f9c0a3bcc8a4461feb7f8b57e704d4ef3145118ad2b52b69463cf0/rootfs
shm              64M     0   64M   0% /run/containerd/io.containerd.grpc.v1.cri/sandboxes/de1d0ac55542f62e1a265675f13c54a68036def544fedb1722681feaaa3e1792/shm
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/de1d0ac55542f62e1a265675f13c54a68036def544fedb1722681feaaa3e1792/rootfs
shm              64M     0   64M   0% /run/containerd/io.containerd.grpc.v1.cri/sandboxes/c67795cf6b60581797be5d6052fd9e2190de4f2a315fe5e7bb9af220469e69e9/shm
shm              64M     0   64M   0% /run/containerd/io.containerd.grpc.v1.cri/sandboxes/a6350b4a4c14b1114c7af66a81159838375e6819a71e8558852fca633d7af719/shm
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/c67795cf6b60581797be5d6052fd9e2190de4f2a315fe5e7bb9af220469e69e9/rootfs
shm              64M     0   64M   0% /run/containerd/io.containerd.grpc.v1.cri/sandboxes/60c135527b6e9fce24bf45aeeba690859e8aa353b45ecab9ce3ec48e23d0b28e/shm
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/a6350b4a4c14b1114c7af66a81159838375e6819a71e8558852fca633d7af719/rootfs
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/60c135527b6e9fce24bf45aeeba690859e8aa353b45ecab9ce3ec48e23d0b28e/rootfs
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/75bb8fd4fe1ea88633692865e624b2d41584bda21e87639ef7b0ae43e678db02/rootfs
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/fd6261ccecfcf8e4c5ba9af480c5d4b80622e387d28aa538cd6af30313de6b7c/rootfs
tmpfs           9.7G   12K  9.7G   1% /var/lib/kubelet/pods/8f489665-c806-49e7-ace2-efaf99d17bd2/volumes/kubernetes.io~projected/kube-api-access-dfbjq
tmpfs           9.7G  4.0K  9.7G   1% /var/lib/kubelet/pods/8f489665-c806-49e7-ace2-efaf99d17bd2/volumes/kubernetes.io~secret/config-volume
tmpfs           9.7G  4.0K  9.7G   1% /var/lib/kubelet/pods/8f489665-c806-49e7-ace2-efaf99d17bd2/volumes/kubernetes.io~empty-dir/config-out
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/4e562f242c2ae2852bffd5deeb95f47f595691a6f8bdc7f04c1984bf4ef59ded/rootfs
tmpfs           9.7G     0  9.7G   0% /var/lib/kubelet/pods/8f489665-c806-49e7-ace2-efaf99d17bd2/volumes/kubernetes.io~secret/web-config
tmpfs           9.7G     0  9.7G   0% /var/lib/kubelet/pods/8f489665-c806-49e7-ace2-efaf99d17bd2/volumes/kubernetes.io~projected/tls-assets
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/c49da97eabd8e4c4eab20a0d0a3459cb679b3849c0ab523f0d0c80bf4261572c/rootfs
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/6537989d7bd8d580e1a28a48e82a27c6f740e26960f73a8fa0d6850607fcef3d/rootfs
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/2883d08a20d925c0f6042a9d2d18e7bfcc3c4b0ea950511e6d6be20dad65daa3/rootfs
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/cee66cd59cb181800763053c57cebdddc147ebd8656d3a53973e113d682ba1b0/rootfs
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/a1043c6dd09a86dd5ea42b08568b2ee013d80e6757211a969b40266c5815dbb5/rootfs
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/176a1f9ad8bab638651518479d67b321bc709bb44cececb3ef96c4702635cc87/rootfs
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/9ef3977b828d414ba2ab2bed30bb3069070a16b05ac91abaa703ed51afdeb29a/rootfs
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/8b607245c90b58c5512214cb5c3b9e2780b9ef1d7d9292c2afbc214f8ee0a015/rootfs
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/7df66ad6129cdc47bbae5a454733086bb5723a5c4b123efadc9dfe48014f5524/rootfs
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/dc0ddba18167fda9ef19a8bc33e8c4e10e6db66f7ad04976141d354ec77fbeef/rootfs
shm              64M     0   64M   0% /run/containerd/io.containerd.grpc.v1.cri/sandboxes/887ea11ee7bf4690984e922400d2024fd26b5a95818f058786eeff444facefa1/shm
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/887ea11ee7bf4690984e922400d2024fd26b5a95818f058786eeff444facefa1/rootfs
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/df1e48d71b2573aafe3466e6e04143cb07e9cbdced2f2d2ceb9093970a4ce400/rootfs
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/372a2c5c555c3670986de1e57e5aa53fb085a90e300451e51d8b47e07c43f238/rootfs
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/ae696384877473ee3de39a7a50e34fb003ae4679ba866a387892aa89546ca7a0/rootfs
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/abfc934993edf6edd4795a23730255b57226f0d56afc8b60a7fc7d58e2b8c129/rootfs
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/cf774593618baf1fbd1ec61ebf5d4c253b6319532f8d2a5f39545a116332c7b2/rootfs
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/f9ff90cad32edc2c9ffe5285e986a58759b18ea3ec94e3844f3907c8016774f5/rootfs
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/b4df99ea182206cc1b42ba1a39a979b2f235e515584a8a95b94e1c05c00bf994/rootfs
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/0db01d4a1854a825d52a58ee0fb2103e4c03c54ac16198876cb6910d34f70b55/rootfs
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/47ff16c030fbd30c156a289d2f25146521186cf0a2d06df8aa3c0c1c0d7fadce/rootfs
tmpfs           9.7G   12K  9.7G   1% /var/lib/kubelet/pods/d11764e1-7662-48e3-8013-f32a1a8ba878/volumes/kubernetes.io~projected/kube-api-access-rpb7q
shm              64M     0   64M   0% /run/containerd/io.containerd.grpc.v1.cri/sandboxes/0c9517a1743c455ed9ab2c2e3d6003ac089f46e13695f8f9d6e39169200818ab/shm
shm              64M     0   64M   0% /run/containerd/io.containerd.grpc.v1.cri/sandboxes/7183c2010aa44f149269329db533edfc5a52ff8fbb4cfc4657c72c29c2c40e53/shm
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/0c9517a1743c455ed9ab2c2e3d6003ac089f46e13695f8f9d6e39169200818ab/rootfs
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/7183c2010aa44f149269329db533edfc5a52ff8fbb4cfc4657c72c29c2c40e53/rootfs
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/e8ca6e8da8fb62ce0527712e82a805211ef7d8bd9b17067bee29c00972bd51cd/rootfs
tmpfs           9.7G   12K  9.7G   1% /var/lib/kubelet/pods/4c915c2c-6e9e-49a6-b634-3530e28da167/volumes/kubernetes.io~projected/kube-api-access-k82pm
shm              64M     0   64M   0% /run/containerd/io.containerd.grpc.v1.cri/sandboxes/5ddde75beef408a61a0f05e060225e85eb185102595a6f16c9a1325aaa81d143/shm
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/5ddde75beef408a61a0f05e060225e85eb185102595a6f16c9a1325aaa81d143/rootfs
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/16247b883292911018c0fcb7aaba716f392cdcffe8067a02f473cfa0bb7f15ad/rootfs
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/519ad13621c2fdca04af6859451616b8b7ab40ce5d0fb5496c8488b7161f2000/rootfs
shm              64M     0   64M   0% /run/containerd/io.containerd.grpc.v1.cri/sandboxes/2981a97d225da29e6f238a7172e577eda7fa024fb8f4587a7241138562df8745/shm
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/2981a97d225da29e6f238a7172e577eda7fa024fb8f4587a7241138562df8745/rootfs
shm              64M     0   64M   0% /run/containerd/io.containerd.grpc.v1.cri/sandboxes/46f980529bfe96049d2180739332f2e4262be0dcf0836fb2523c5b605c885445/shm
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/46f980529bfe96049d2180739332f2e4262be0dcf0836fb2523c5b605c885445/rootfs
tmpfs           1.0G     0  1.0G   0% /var/lib/kubelet/pods/80835f40-8cfd-4a74-a3e0-19abfe66b89b/volumes/kubernetes.io~secret/argocd-repo-server-tls
tmpfs           1.0G   12K  1.0G   1% /var/lib/kubelet/pods/80835f40-8cfd-4a74-a3e0-19abfe66b89b/volumes/kubernetes.io~projected/kube-api-access-qnx9c
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/da4067785aa660b4af74768d1787a98a66c1afc90678ab3df8a8b79f5af987cf/rootfs
shm              64M     0   64M   0% /run/containerd/io.containerd.grpc.v1.cri/sandboxes/3f89702339a1b166a66ac0668f8b6e81abf0fdc1cc5a1ffe2244745adc69c575/shm
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/3f89702339a1b166a66ac0668f8b6e81abf0fdc1cc5a1ffe2244745adc69c575/rootfs
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/cf2605c028591d3a1ef1dd3f8764e0025a0cc209d4a4bd4430cea4f8be6648dc/rootfs
tmpfs           9.7G     0  9.7G   0% /var/lib/kubelet/pods/9dab2ff2-fba1-4197-b4d2-e84b19880122/volumes/kubernetes.io~secret/web-config
tmpfs           9.7G  4.0K  9.7G   1% /var/lib/kubelet/pods/9dab2ff2-fba1-4197-b4d2-e84b19880122/volumes/kubernetes.io~secret/config
tmpfs           9.7G  4.0K  9.7G   1% /var/lib/kubelet/pods/9dab2ff2-fba1-4197-b4d2-e84b19880122/volumes/kubernetes.io~projected/tls-assets
tmpfs           9.7G   28K  9.7G   1% /var/lib/kubelet/pods/9dab2ff2-fba1-4197-b4d2-e84b19880122/volumes/kubernetes.io~empty-dir/config-out
tmpfs           9.7G   12K  9.7G   1% /var/lib/kubelet/pods/9dab2ff2-fba1-4197-b4d2-e84b19880122/volumes/kubernetes.io~projected/kube-api-access-gcdxd
tmpfs           512M  1.3M  511M   1% /var/lib/kubelet/pods/7e540eae-7399-4abf-bf58-ad5b52c995e5/volumes/kubernetes.io~empty-dir/shm-volume
shm              64M     0   64M   0% /run/containerd/io.containerd.grpc.v1.cri/sandboxes/8d4737a62ae7315dcbb04ad8bb184559e724408edbe9a22351f34a97c60874c2/shm
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/8d4737a62ae7315dcbb04ad8bb184559e724408edbe9a22351f34a97c60874c2/rootfs
shm              64M     0   64M   0% /run/containerd/io.containerd.grpc.v1.cri/sandboxes/674b1a6707aac3cf192d002edcb11b8ff355de594b3d3685a7634db36bcf19d8/shm
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/674b1a6707aac3cf192d002edcb11b8ff355de594b3d3685a7634db36bcf19d8/rootfs
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/ea4bae589cd60ff3449135f6b0081a63856696db939838e63328dfed2faf0347/rootfs
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/f532caa2fee1bbf63ba70f238dbb897d0024dbefd2d3b7c0d18c6d40efce0b52/rootfs
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/57260f704767bd0e721288d7f25b47db2910ebe727e8785807caab7b356fc66c/rootfs
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/b542796b8163e9497b0a3ac7aa3f7ed2000e999bc81015b58a67cf835dca5311/rootfs
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/09f2a63ee900e6bad26cd5a91e7f7ed8e963cbb5b625a62c4f1b31a1d881090a/rootfs
overlay         224G   39G  174G  19% /run/containerd/io.containerd.runtime.v2.task/k8s.io/dff5b854b2ff0896260e20b55dd95fea7034f9322760d5d1ebb7bb872d8f961e/rootfs
               total        used        free      shared  buff/cache   available
Mem:           9.7Gi       5.6Gi       766Mi        63Mi       3.6Gi       4.1Gi
Swap:          1.0Gi       189Mi       834Mi

docker exec minikube crictl ps -a --name etcd
2d284cedc430d       c2e426bbd1cd6       15 hours ago         Running             etcd                        7                   a74db10463019       etcd-minikube                                               kube-system
7fc0d43e34451       c2e426bbd1cd6       15 hours ago         Exited              etcd                        6                   f72f2e54a5f81       etcd-minikube                                               kube-system

docker exec minikube crictl ps -a --name etcd
CONTAINER           IMAGE               CREATED             STATE               NAME                ATTEMPT             POD ID              POD                 NAMESPACE
2d284cedc430d       c2e426bbd1cd6       15 hours ago        Running             etcd                7                   a74db10463019       etcd-minikube       kube-system

ETCD_ID=$(docker exec minikube crictl ps -a --name etcd -q | head -1)

echo "$ETCD_ID"
2d284cedc430d4915a59afc71d6cf4b746a82a54e4ba05fcbae0a28d0459055a
(.venv) anderson.oliveira@CACTUS-IS-0035 argocd % docker exec minikube crictl logs --tail=100 "$ETCD_ID"
{"level":"warn","ts":"2026-11-21T11:08:24.944535Z","caller":"txn/util.go:93","msg":"apply request took too long","took":"300.933334ms","expected-duration":"100ms","prefix":"read-only range ","request":"key:\"/registry/actions.github.com/ephemeralrunnersets\" limit:1","response":"range_response_count:0 size:6"}
{"level":"info","ts":"2026-11-21T11:08:24.944709Z","caller":"traceutil/trace.go:195","msg":"trace","trace_id":1433445059,"operation":"range","detail":"{range_begin:/registry/actions.github.com/ephemeralrunnersets; range_end:; response_count:0; response_revision:49716; }","duration":"301.138375ms","start":"2026-11-21T11:08:24.643531Z","end":"2026-11-21T11:08:24.944670Z","steps":["'range keys from in-memory index tree'  (duration: 300.783916ms)"],"step_count":1}
{"level":"warn","ts":"2026-11-21T11:08:24.944763Z","caller":"v3rpc/interceptor.go:203","msg":"request stats","start time":"2026-11-21T11:08:24.643513Z","time spent":"301.235375ms","remote":"127.0.0.1:39782","response type":"/etcdserverpb.KV/Range","request count":0,"request size":52,"response count":0,"response size":30,"request content":"key:\"/registry/actions.github.com/ephemeralrunnersets\" limit:1"}
{"level":"warn","ts":"2026-11-21T11:08:24.945910Z","caller":"txn/util.go:93","msg":"apply request took too long","took":"302.581417ms","expected-duration":"100ms","prefix":"read-only range ","request":"key:\"/registry/resourceslices\" limit:1","response":"range_response_count:0 size:6"}
{"level":"info","ts":"2026-11-21T11:08:24.945994Z","caller":"traceutil/trace.go:195","msg":"trace","trace_id":2018757332,"operation":"range","detail":"{range_begin:/registry/resourceslices; range_end:; response_count:0; response_revision:49716; }","duration":"302.658792ms","start":"2026-11-21T11:08:24.643316Z","end":"2026-11-21T11:08:24.945975Z","steps":["'range keys from in-memory index tree'  (duration: 302.490792ms)"],"step_count":1}
{"level":"warn","ts":"2026-11-21T11:08:24.946019Z","caller":"v3rpc/inte


Diagnóstico dos resultados
Indicador	Resultado	Análise
CPU do Minikube	201,08%	Utilizando aproximadamente 2 CPUs
CPU configurada	2 vCPUs	Muito pouco para toda a sua POC
Memória	5,39 GiB / 8 GiB	67,42% utilizada
Disco	39 GB / 224 GB	Sem evidência de falta de espaço
OOMKilled	false	Container Minikube não foi encerrado por OOM
etcd	Running, tentativa 7	Histórico de reinicializações
Processos	914 PIDs	Carga considerável para o ambiente



docker exec minikube sh -c \
  'cat /sys/fs/cgroup/cpu.stat'
usage_usec 16219583744
user_usec 9991530642
system_usec 6228053102
nice_usec 0
nr_periods 187789
nr_throttled 45910
throttled_usec 21959668469
nr_bursts 0
burst_usec 0


docker exec minikube crictl stats
E1121 11:11:33.654741  131333 log.go:32] "ListContainerStats with filter from runtime service failed" err="rpc error: code = DeadlineExceeded desc = stream terminated by RST_STREAM with error code: CANCEL" filter=""
time="2026-11-21T11:11:33Z" level=fatal msg="get container stats: rpc error: code = DeadlineExceeded desc = stream terminated by RST_STREAM with error code: CANCEL

## SOLUÇÃO DE CONTORNO ##

Recuperação sem apagar o cluster, foi aumentar a capacidade do Minikube para pelo menos 4 vCPUs, preferencialmente 6, desde que o Mac tenha recursos disponíveis.

OBS.: detalhe importante: com o driver Docker, alterar minikube config set cpus 6 não aumenta automaticamente os recursos do container existente.

Não recomendo modificar diretamente os limites do container com docker update sem antes verificar a configuração e o procedimento de recuperação.

minikube config view
argocd % docker exec minikube crictl stats
E1121 11:11:33.654741  131333 log.go:32] "ListContainerStats with filter from runtime service failed" err="rpc error: code = DeadlineExceeded desc = stream terminated by RST_STREAM with error code: CANCEL" filter=""
time="2026-11-21T11:11:33Z" level=fatal msg="get container stats: rpc error: code = DeadlineExceeded desc = stream terminated by RST_STREAM with error code: CANCEL"
(.venv) anderson.oliveira@CACTUS-IS-0035 argocd % minikube config view

docker info --format \
  'CPUs={{.NCPU}} Memory={{.MemTotal}}'
CPUs=8 Memory=10379169792

kubectl --request-timeout=10s get --raw='/readyz?verbose'
[+]ping ok
[+]log ok
[+]etcd ok
[+]etcd-readiness ok
[+]informer-sync ok
[+]poststarthook/start-apiserver-admission-initializer ok
[+]poststarthook/generic-apiserver-start-informers ok
[+]poststarthook/priority-and-fairness-config-consumer ok
[+]poststarthook/priority-and-fairness-filter ok
[+]poststarthook/storage-object-count-tracker-hook ok
[+]poststarthook/start-apiextensions-informers ok
[+]poststarthook/start-apiextensions-controllers ok
[+]poststarthook/crd-informer-synced ok
[+]poststarthook/start-system-namespaces-controller ok
[+]poststarthook/peer-endpoint-reconciler-controller ok
[+]poststarthook/start-cluster-authentication-info-controller ok
[+]poststarthook/start-kube-apiserver-identity-lease-controller ok
[+]poststarthook/start-kube-apiserver-identity-lease-garbage-collector ok
[+]poststarthook/storage-readiness ok
[+]poststarthook/start-legacy-token-tracking-controller ok
[+]poststarthook/start-service-ip-repair-controllers ok
[+]poststarthook/rbac/bootstrap-roles ok
[+]poststarthook/scheduling/bootstrap-system-priority-classes ok
[+]poststarthook/priority-and-fairness-config-producer ok
[+]poststarthook/bootstrap-controller ok
[+]poststarthook/start-kubernetes-service-cidr-controller ok
[+]poststarthook/aggregator-reload-proxy-client-cert ok
[+]poststarthook/start-kube-aggregator-informers ok
[+]poststarthook/apiservice-status-local-available-controller ok
[+]poststarthook/apiservice-status-remote-available-controller ok
[+]poststarthook/apiservice-registration-controller ok
[+]poststarthook/apiservice-discovery-controller ok
[+]poststarthook/kube-apiserver-autoregistration ok
[+]autoregister-completion ok
[+]poststarthook/apiservice-openapi-controller ok
[+]poststarthook/apiservice-openapiv3-controller ok
[+]shutdown ok
readyz check passed

minikube status
minikube
type: Control Plane
host: Running
kubelet: Running
apiserver: Running
kubeconfig: Configured

## PÓS SOLUÇÃO DE CONTORNO

 k get po -A
NAMESPACE       NAME                                                        READY   STATUS             RESTARTS        AGE
arc-systems     arc-gha-rs-controller-674cf6b948-5p7l8                      1/1     Running            0               8m16s
argocd          argocd-application-controller-0                             1/1     Running            0               6m32s
argocd          argocd-applicationset-controller-6d4f9855b7-k85hs           1/1     Running            0               8m14s
argocd          argocd-dex-server-6688b6d8c7-gdf6s                          1/1     Running            0               8m14s
argocd          argocd-notifications-controller-64ccb979bb-q428z            1/1     Running            0               8m14s
argocd          argocd-redis-7659897594-qv4z5                               1/1     Running            0               8m14s
argocd          argocd-repo-server-56d9b77b87-2h5qn                         1/1     Running            0               8m14s
argocd          argocd-server-7c8d96f688-mwvdr                              1/1     Running            0               8m13s
harbor          harbor-core-7bb9f7dc66-mgfwf                                1/1     Running            1 (5m16s ago)   8m14s
harbor          harbor-database-0                                           1/1     Running            0               6m28s
harbor          harbor-jobservice-7756c6ff4c-p9x9k                          0/1     CrashLoopBackOff   5 (2m37s ago)   8m16s
harbor          harbor-nginx-5b8545bc6f-67t5n                               1/1     Running            2 (6m36s ago)   8m15s
harbor          harbor-portal-789f958455-n5qcl                              1/1     Running            0               8m14s
harbor          harbor-redis-0                                              1/1     Running            0               6m38s
harbor          harbor-registry-66c45f8bdd-4f6pz                            2/2     Running            0               8m14s
harbor          harbor-trivy-0                                              1/1     Running            0               6m34s
kube-system     coredns-559f6c778d-dhhdc                                    1/1     Running            0               8m16s
kube-system     coredns-559f6c778d-sfr8v                                    1/1     Running            0               8m13s
kube-system     etcd-minikube                                               1/1     Running            7 (14h ago)     38h
kube-system     kindnet-272xc                                               1/1     Running            3 (14h ago)     38h
kube-system     kube-apiserver-minikube                                     1/1     Running            14 (14h ago)    38h
kube-system     kube-controller-manager-minikube                            1/1     Running            14 (14h ago)    38h
kube-system     kube-proxy-v9rml                                            1/1     Running            3 (14h ago)     38h
kube-system     kube-scheduler-minikube                                     1/1     Running            10 (14h ago)    38h
kube-system     metrics-server-768f9f6999-hgl7s                             1/1     Running            0               8m15s
observability   alertmanager-kube-prometheus-stack-alertmanager-0           2/2     Running            0               7m6s
observability   alloy-sl2gp                                                 2/2     Running            0               10h
observability   kube-prometheus-stack-grafana-f4c67b-chprl                  3/3     Running            0               8m14s
observability   kube-prometheus-stack-kube-state-metrics-68565d6658-cbssw   1/1     Running            0               8m16s
observability   kube-prometheus-stack-operator-558f47f4cd-27fkg             1/1     Running            0               8m15s
observability   kube-prometheus-stack-prometheus-node-exporter-8zsk8        1/1     Running            4 (7m54s ago)   9h
observability   loki-0                                                      2/2     Running            0               6m36s
observability   loki-gateway-6dbdd865d5-tp26w                               1/1     Running            2 (6m24s ago)   8m16s
observability   prometheus-kube-prometheus-stack-prometheus-0               2/2     Running            0               6m29s
sonarqube       sonarqube-sonarqube-0                                       1/1     Running            0               6m35s
traefik         traefik-77cbc65fd9-ndfm9                                    1/1     Running            0               8m14s


## SOLUÇÃO DEFINITIVA - MELHORAR OS RECURSOS DO PROMETHEUS INCLUINDO RESOURCESLIMITS ##|



grafana:
  enabled: true
  admin:
    existingSecret: grafana-admin
    userKey: admin-user
    passwordKey: admin-password
  service:
    type: ClusterIP
  ingress:
    enabled: false
  persistence:
    enabled: false

  # ADICIONADO: requests e limits do Grafana
  resources:
    requests:
      cpu: 50m
      memory: 128Mi
    limits:
      cpu: 200m
      memory: 384Mi

  additionalDataSources:
    - name: Loki
      type: loki
      access: proxy
      url: http://loki-gateway.observability.svc.cluster.local
      isDefault: false

prometheus:
  prometheusSpec:
    retention: 2d
    resources:
      requests:
        cpu: 150m
        memory: 500Mi
      limits:
        # ADICIONADO: limite de CPU
        cpu: 500m
        memory: 1200Mi
    storageSpec: {}

alertmanager:
  alertmanagerSpec:
    resources:
      requests:
        cpu: 25m
        memory: 64Mi
      limits:
        # ADICIONADO: limite de CPU
        cpu: 100m
        memory: 256Mi

# ADICIONADO: requests e limits do Prometheus Operator
prometheusOperator:
  resources:
    requests:
      cpu: 50m
      memory: 128Mi
    limits:
      cpu: 200m
      memory: 256Mi

kubeControllerManager:
  enabled: false

kubeScheduler:
  enabled: false

kubeEtcd:
  enabled: false

# ADICIONADO ANTERIORMENTE:
# Não criar Services de descoberta em kube-system.
kubeDns:
  enabled: false

coreDns:
  enabled: false

kubeProxy:
  enabled: false


