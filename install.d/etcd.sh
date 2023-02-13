if [[ "${INSTALL_TYPE}" == systemd ]]; then
cat <<EOF > /etc/systemd/system/etcd.service
[Unit]
Description=etcd
Wants=network-online.target
After=network-online.target

[Service]
ExecStart=/home/arch/workspace/common_utils/k8s-hard-way/downloads/etcd-v3.5.7-linux-amd64/etcd \\
    --advertise-client-urls=https://${LAN_IP}:2379 \\
    --cert-file=/etc/kubernetes/pki/etcd/all.crt \\
    --client-cert-auth=true \\
    --data-dir=/var/lib/etcd \\
    --experimental-initial-corrupt-check=true \\
    --experimental-watch-progress-notify-interval=5s \\
    --initial-advertise-peer-urls=https://${LAN_IP}:2380 \\
    --initial-cluster=$(hostname)=https://${LAN_IP}:2380 \\
    --key-file=/etc/kubernetes/pki/etcd/all.key \\
    --listen-client-urls=https://127.0.0.1:2379,https://${LAN_IP}:2379 \\
    --listen-metrics-urls=http://127.0.0.1:2381 \\
    --listen-peer-urls=https://${LAN_IP}:2380 \\
    --name=$(hostname) \\
    --peer-cert-file=/etc/kubernetes/pki/etcd/all.crt \\
    --peer-client-cert-auth=true \\
    --peer-key-file=/etc/kubernetes/pki/etcd/all.key \\
    --peer-trusted-ca-file=/etc/kubernetes/pki/etcd/ca.crt \\
    --snapshot-count=10000 \\
    --trusted-ca-file=/etc/kubernetes/pki/etcd/ca.crt
Restart=always
StartLimitInterval=0
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
else
cat <<EOF > "${cur}/etc/kubernetes/manifests/etcd.yaml"
apiVersion: v1
kind: Pod
metadata:
  annotations:
    kubeadm.kubernetes.io/etcd.advertise-client-urls: https://${LAN_IP}:2379
  creationTimestamp: null
  labels:
    component: etcd
    tier: control-plane
  name: etcd
  namespace: kube-system
spec:
  containers:
  - command:
    - etcd
    - --advertise-client-urls=https://${LAN_IP}:2379
    - --cert-file=/etc/kubernetes/pki/etcd/all.crt
    - --client-cert-auth=true
    - --data-dir=/var/lib/etcd
    - --experimental-initial-corrupt-check=true
    - --experimental-watch-progress-notify-interval=5s
    - --initial-advertise-peer-urls=https://${LAN_IP}:2380
    - --initial-cluster=$(hostname)=https://${LAN_IP}:2380
    - --key-file=/etc/kubernetes/pki/etcd/all.key
    - --listen-client-urls=https://127.0.0.1:2379,https://${LAN_IP}:2379
    - --listen-metrics-urls=http://0.0.0.0:2381
    - --listen-peer-urls=https://${LAN_IP}:2380
    - --name=$(hostname)
    - --peer-cert-file=/etc/kubernetes/pki/etcd/all.crt
    - --peer-client-cert-auth=true
    - --peer-key-file=/etc/kubernetes/pki/etcd/all.key
    - --peer-trusted-ca-file=/etc/kubernetes/pki/etcd/ca.crt
    - --snapshot-count=10000
    - --trusted-ca-file=/etc/kubernetes/pki/etcd/ca.crt
    image: registry.k8s.io/etcd:3.5.6-0
    imagePullPolicy: IfNotPresent
    resources:
        requests:
            memory: "16Mi"
        limits:
            memory: "2048Mi"
    readinessProbe:
      failureThreshold: 3
      httpGet:
        host: 127.0.0.1
        path: /health?exclude=NOSPACE&serializable=true
        port: 2381
        scheme: HTTP
      periodSeconds: 1
      timeoutSeconds: 15
    livenessProbe:
      failureThreshold: 8
      httpGet:
        host: 127.0.0.1
        path: /health?exclude=NOSPACE&serializable=true
        port: 2381
        scheme: HTTP
      initialDelaySeconds: 10
      periodSeconds: 10
      timeoutSeconds: 15
    name: etcd
    startupProbe:
      failureThreshold: 24
      httpGet:
        host: 127.0.0.1
        path: /health?serializable=false
        port: 2381
        scheme: HTTP
      initialDelaySeconds: 10
      periodSeconds: 10
      timeoutSeconds: 15
    volumeMounts:
    - mountPath: /var/lib/etcd
      name: etcd-data
    - mountPath: /etc/kubernetes/pki/etcd
      name: etcd-certs
  hostNetwork: true
  priorityClassName: system-node-critical
  securityContext:
    seccompProfile:
      type: RuntimeDefault
  volumes:
  - hostPath:
      path: /etc/kubernetes/pki/etcd
      type: DirectoryOrCreate
    name: etcd-certs
  - hostPath:
      path: /var/lib/etcd
      type: DirectoryOrCreate
    name: etcd-data
status: {}
EOF
fi
