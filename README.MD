# k8s smooth way

模仿 kubeadm 的思路创建一个单节点 k8s 集群, kube-proxy 使用的是 ipvs 模式,cni 插件使用 bridge

## 先决条件

1. 安装好 containerd, 设置好一些基础的 cni plugins
2. 内核开启 ip_vs 相关模块
3. sysctl 开启以下配置

net.bridge.bridge-nf-call-iptables=1

net.ipv4.vs.conntrack=1

net.ipv4.ip_forward = 1



## 安装细节

具体安装步骤见 install.sh

1. 使用 go 编写的程序生成证书和 kubeconfig 文件
2. 生成 bridge 的 cni 配置文件
3. 生成静态 pod 清单，包含 etcd kube-apiserver kube-controller-manager kube-scheduler 
4. 把证书、kubeconfig配置文件、静态pod清单、kubelet unit file 和 kubelet 配置文件同步到 /etc 和 /var/lib 下
5. 启动 kubelet 等待 kubelet 成功拉起 kube-apiserver 这个静态 pod
6.  使用 daemon set 部署 kube-proxy
7. 使用 deployment 的方式部署 coredns

## 参考
1. [kubeadm实现细节](https://kubernetes.io/zh-cn/docs/reference/setup-tools/kubeadm/implementation-details/)
2. [彻底搞懂 kube-proxy IPVS 模式的工作](https://cloud.tencent.com/developer/article/1832918)
3. [bridge cni](https://www.cni.dev/plugins/current/main/bridge/)
4. [重学容器01: Docker、Containerd、Kubernetes之间的渊源](https://blog.frognew.com/2021/04/relearning-container-01.html)
5. [重学容器03: 使用CNI为Containerd容器添加网络能力](https://blog.frognew.com/2021/04/relearning-container-03.html)

