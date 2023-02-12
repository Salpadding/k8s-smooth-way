#!/bin/sh

cur=`dirname $0`
cur=`cd $cur; pwd`
LAN_IP=10.240.0.16

systemctl stop kubelet

pushd /var/lib/kubelet
ls | grep -v 'config.yaml' | grep -v '.env' | xargs rm -rf
popd
if [[ -n `crictl pods | sed 1d` ]]; then
    crictl pods | sed 1d | awk '{print $1}' | xargs crictl stopp
    crictl pods | sed 1d | awk '{print $1}' | xargs crictl rmp
fi
crictl pods

systemctl stop containerd
rm -rf /var/lib/cni/*
rm -rf /default.etcd /var/lib/etcd /var/lib/kube-proxy
mkdir /var/lib/etcd /var/lib/kube-proxy


systemctl start containerd
systemctl start kubelet


export KUBECONFIG="${cur}/etc/kubernetes/admin.conf"


# 等待 api server 启动 创建 node-proxiers 组
while ! curl -k https://localhost:6443/healthz >/dev/null 2>&1; do
    sleep 1
done

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
