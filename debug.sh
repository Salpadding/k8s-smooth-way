#!/bin/sh


cur=`dirname $0`
cur=`cd $cur; pwd`
pushd "${cur}/../learn"

LAN_IP=`go run . lanIP`
popd

if [[ "${1}" == "certs" ]]; then
    pushd "${cur}/../learn"
    # 生成证书/kubeconfig
    go run . certs
    popd
    rsync -av "${cur}/etc/kubernetes/" /etc/kubernetes/
    rm -rf /etc/kubernetes/manifests/
    rm -rf /var/lib/kubelet/pki
fi

if [[ "${1}" == "etcd" ]]; then
    rm -rf /var/lib/etcd
    mkdir -p /var/lib/etcd
    /home/arch/workspace/common_utils/k8s-hard-way/downloads/etcd-v3.5.7-linux-amd64/etcd \
    --advertise-client-urls=https://${LAN_IP}:2379 \
    --cert-file=/etc/kubernetes/pki/etcd/all.crt \
    --client-cert-auth=true \
    --data-dir=/var/lib/etcd \
    --experimental-initial-corrupt-check=true \
    --experimental-watch-progress-notify-interval=5s \
    --initial-advertise-peer-urls=https://${LAN_IP}:2380 \
    --initial-cluster=localhost=https://${LAN_IP}:2380 \
    --key-file=/etc/kubernetes/pki/etcd/all.key \
    --listen-client-urls=https://127.0.0.1:2379,https://${LAN_IP}:2379 \
    --listen-metrics-urls=http://127.0.0.1:2381 \
    --listen-peer-urls=https://${LAN_IP}:2380 \
    --name=localhost \
    --peer-cert-file=/etc/kubernetes/pki/etcd/all.crt \
    --peer-client-cert-auth=true \
    --peer-key-file=/etc/kubernetes/pki/etcd/all.key \
    --peer-trusted-ca-file=/etc/kubernetes/pki/etcd/ca.crt \
    --snapshot-count=10000 \
    --trusted-ca-file=/etc/kubernetes/pki/etcd/ca.crt
fi


if [[ "${1}" == "etcd-conn" ]]; then
    ETCDCTL_API=3 /home/arch/workspace/common_utils/k8s-hard-way/downloads/etcd-v3.5.7-linux-amd64/etcdctl \
        member list --endpoints=https://${LAN_IP}:2379 \
        --cacert=/etc/kubernetes/pki/etcd/ca.crt \
	    --cert=/etc/kubernetes/pki/etcd/all.crt \
	    --key=/etc/kubernetes/pki/etcd/all.key
fi



if [[ "${1}" == "kube-apiserver" ]]; then
    kube-apiserver \
    --advertise-address=${LAN_IP} \
    --allow-privileged=true \
    --authorization-mode=Node,RBAC \
    --client-ca-file=/etc/kubernetes/pki/ca.crt \
    --enable-admission-plugins=NodeRestriction \
    --enable-bootstrap-token-auth=true \
    --etcd-cafile=/etc/kubernetes/pki/etcd/ca.crt \
    --etcd-certfile=/etc/kubernetes/pki/etcd/all.crt \
    --etcd-keyfile=/etc/kubernetes/pki/etcd/all.key \
    --etcd-servers=https://${LAN_IP}:2379 \
    --kubelet-client-certificate=/etc/kubernetes/pki/apiserver-kubelet-client.crt \
    --kubelet-client-key=/etc/kubernetes/pki/apiserver-kubelet-client.key \
    --kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname \
    --secure-port=6443 \
    --service-account-issuer=https://kubernetes.default.svc.cluster.local \
    --service-account-key-file=/etc/kubernetes/pki/sa.pub \
    --service-account-signing-key-file=/etc/kubernetes/pki/sa.key \
    --service-cluster-ip-range=10.96.0.0/12 \
    --tls-cert-file=/etc/kubernetes/pki/apiserver.crt \
    --tls-private-key-file=/etc/kubernetes/pki/apiserver.key \
    --proxy-client-cert-file=/etc/kubernetes/pki/front-proxy-client.crt \
    --proxy-client-key-file=/etc/kubernetes/pki/front-proxy-client.key \
    --requestheader-allowed-names=front-proxy-client \
    --requestheader-client-ca-file=/etc/kubernetes/pki/front-proxy-ca.crt \
    --requestheader-extra-headers-prefix=X-Remote-Extra- \
    --requestheader-group-headers=X-Remote-Group \
    --requestheader-username-headers=X-Remote-User
fi


if [[ "${1}" == "kubelet" ]]; then
    rm -rf /etc/kubernetes/manifests/*
    pushd /var/lib/kubelet
    ls | grep -v 'config.yaml' | grep -v '.env' | xargs rm -rf
    popd
    if [[ -n `crictl pods | sed 1d` ]]; then
        crictl pods | sed 1d | awk '{print $1}' | xargs crictl stopp
        crictl pods | sed 1d | awk '{print $1}' | xargs crictl rmp
    fi
    crictl pods
    kubelet --kubeconfig=/etc/kubernetes/kubelet.conf \
        --config=/var/lib/kubelet/config.yaml \
        --container-runtime-endpoint=unix:///var/run/containerd/containerd.sock
fi


if [[ "${1}" == "kube-scheduler" ]]; then
    kube-scheduler \
    --authentication-kubeconfig=/etc/kubernetes/scheduler.conf \
    --authorization-kubeconfig=/etc/kubernetes/scheduler.conf \
    --bind-address=0.0.0.0 \
    --kubeconfig=/etc/kubernetes/scheduler.conf \
    --leader-elect=false 
fi

if [[ "${1}" == "kube-controller-manager" ]]; then
    kube-controller-manager \
    --authentication-kubeconfig=/etc/kubernetes/controller-manager.conf \
    --authorization-kubeconfig=/etc/kubernetes/controller-manager.conf \
    --bind-address=0.0.0.0 \
    --client-ca-file=/etc/kubernetes/pki/ca.crt \
    --cluster-name=kubernetes \
    --cluster-signing-cert-file=/etc/kubernetes/pki/ca.crt \
    --cluster-signing-key-file=/etc/kubernetes/pki/ca.key \
    --controllers=*,bootstrapsigner,tokencleaner \
    --kubeconfig=/etc/kubernetes/controller-manager.conf \
    --leader-elect=false \
    --requestheader-client-ca-file=/etc/kubernetes/pki/front-proxy-ca.crt \
    --root-ca-file=/etc/kubernetes/pki/ca.crt \
    --service-account-private-key-file=/etc/kubernetes/pki/sa.key \
    --use-service-account-credentials=true
fi


if [[ "${1}" == "kube-proxy" ]]; then
    rm -rf /var/lib/kube-proxy 
    mkdir -p /var/lib/kube-proxy

cat <<EOF > /var/lib/kube-proxy/config.conf
apiVersion: kubeproxy.config.k8s.io/v1alpha1
bindAddress: 0.0.0.0
bindAddressHardFail: false
clientConnection:
  acceptContentTypes: ""
  burst: 0
  contentType: ""
  kubeconfig: /etc/kubernetes/kube-proxy.conf
  qps: 0
clusterCIDR: ""
configSyncPeriod: 0s
conntrack:
  maxPerCore: null
  min: null
  tcpCloseWaitTimeout: null
  tcpEstablishedTimeout: null
detectLocal:
  bridgeInterface: ""
  interfaceNamePrefix: ""
detectLocalMode: ""
enableProfiling: false
healthzBindAddress: ""
hostnameOverride: ""
iptables:
  localhostNodePorts: null
  masqueradeAll: false
  masqueradeBit: null
  minSyncPeriod: 0s
  syncPeriod: 0s
ipvs:
  excludeCIDRs: null
  minSyncPeriod: 0s
  scheduler: ""
  strictARP: false
  syncPeriod: 0s
  tcpFinTimeout: 0s
  tcpTimeout: 0s
  udpTimeout: 0s
kind: KubeProxyConfiguration
metricsBindAddress: ""
mode: ""
nodePortAddresses: null
oomScoreAdj: null
portRange: ""
showHiddenMetricsForVersion: ""
winkernel:
  enableDSR: false
  forwardHealthCheckVip: false
  networkName: ""
  rootHnsEndpointName: ""
  sourceVip: ""
EOF

kube-proxy --config=/var/lib/kube-proxy/config.conf --hostname-override=arch.rs
fi
