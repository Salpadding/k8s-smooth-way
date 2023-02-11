#!/bin/sh

SERVICE_CIDR=10.96.0.0/12
POD_CIDR=10.64.0.0/16
rm -rf /var/lib/cni/networks
mkdir -p /var/lib/cni/networks

cur=`dirname $0`
cur=`cd $cur; pwd`

export ROOT_DIR="${cur}"
pushd "${cur}/main"

# 生成证书/kubeconfig
mkdir -p "${ROOT_DIR}/etc/kubernetes/pki" "${ROOT_DIR}/etc/kubernetes/manifests"
go run . certs
LAN_IP=`go run . lanIP`
popd

# 停止 kubelet
systemctl stop kubelet
systemctl disable kubelet

if [[ -n `crictl pods | sed 1d` ]]; then
    crictl pods | sed 1d | awk '{print $1}' | xargs crictl stopp
    crictl pods | sed 1d | awk '{print $1}' | xargs crictl rmp
fi

# kubelet 会从 /var/lib/kubelet/pki 读旧的证书
rm -rf /var/lib/etcd /var/lib/kubelet /etc/kubernetes/manifests "${cur}/etc/kubernetes/manifests/" /var/lib/cni
mkdir -p /etc/kubernetes/ /var/lib/kubelet/ /etc/kubernetes/manifests /var/lib/etcd etc/kubernetes/manifests /var/lib/cni



### 配置 CNI
rm -rf /etc/cni/net.d
mkdir -p /etc/cni/net.d
cat <<EOF > /etc/cni/net.d/10-bridge.conf
{
    "cniVersion": "0.3.1",
    "name": "bridge",
    "type": "bridge",
    "bridge": "cni0",
    "isDefaultGateway": true,
    "forceAddress": false,
    "ipMasq": true,
    "hairpinMode": true,
    "ipam": {
        "type": "host-local",
        "subnet": "10.64.0.0/16"
    }
}
EOF

# etcd 静态 pod 配置
# 静态 pod 配置建议把 resources.limit.memory 设置大一些
# 默认的 limit 很小, 很容易导致 pod oom 被 kubelet 杀掉
source "${cur}/install.d/etcd.sh"


### 配置 kube-apiserver
source "${cur}/install.d/kube-apiserver.sh"

### 配置 kube-controller-manager
source "${cur}/install.d/kube-controller-manager.sh"

### 配置 kube-scheduler
source "${cur}/install.d/kube-scheduler.sh"

### 配置 kube-proxy


### 把配置都 rsync 过去
rsync -azv "${cur}/etc/kubernetes/" /etc/kubernetes/
rsync -azv "${cur}/etc/systemd/system/" /etc/systemd/system/
rsync -azv "${cur}/var/lib/kubelet/" /var/lib/kubelet/



# 启动 kubelet
systemctl daemon-reload
systemctl start kubelet


# 等待 api server 启动 创建 node-proxiers 组
while ! curl -k https://localhost:6443/healthz >/dev/null 2>&1; do
    sleep 1
done

export KUBECONFIG="${cur}/etc/kubernetes/admin.conf"

# 部署前需要加载ipvs 模块
# 方法是编辑 /etc/mkinitcpio.conf
# 添加 MODULES=(ip_vs ip_vs_rr ip_vs_wrr ip_vs_sh)
# 部署 kube-proxy
cat "${cur}/install.d/kube-proxy.yaml" | sed "s|server: https://127.0.0.1:6443|server: https://${LAN_IP}:6443|" | kubectl apply -f -


# 验证 kube-proxy 成功代理 cluster ip
while ! curl -k https://10.96.0.1/healthz; do
    sleep 1
done


# 安装 coredns
kubectl apply -f "${cur}/install.d/coredns.yaml"
