if [[ "${INSTALL_TYPE}" == systemd ]]; then
cat <<EOF > /etc/systemd/system/kube-apiserver.service
[Unit]
Description=kube-apiserver

[Service]
ExecStart=/home/arch/bin/kube-apiserver \\
    --advertise-address=${LAN_IP} \\
    --allow-privileged=true \\
    --authorization-mode=Node,RBAC \\
    --client-ca-file=/etc/kubernetes/pki/ca.crt \\
    --enable-admission-plugins=NodeRestriction \\
    --enable-bootstrap-token-auth=true \\
    --etcd-cafile=/etc/kubernetes/pki/etcd/ca.crt \\
    --etcd-certfile=/etc/kubernetes/pki/etcd/all.crt \\
    --etcd-keyfile=/etc/kubernetes/pki/etcd/all.key \\
    --etcd-servers=https://${LAN_IP}:2379 \\
    --kubelet-client-certificate=/etc/kubernetes/pki/apiserver-kubelet-client.crt \\
    --kubelet-client-key=/etc/kubernetes/pki/apiserver-kubelet-client.key \\
    --kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname \\
    --secure-port=6443 \\
    --service-account-issuer=https://kubernetes.default.svc.cluster.local \\
    --service-account-key-file=/etc/kubernetes/pki/sa.pub \\
    --service-account-signing-key-file=/etc/kubernetes/pki/sa.key \\
    --service-cluster-ip-range=${SERVICE_CIDR} \\
    --tls-cert-file=/etc/kubernetes/pki/apiserver.crt \\
    --tls-private-key-file=/etc/kubernetes/pki/apiserver.key \\
    --proxy-client-cert-file=/etc/kubernetes/pki/front-proxy-client.crt \\
    --proxy-client-key-file=/etc/kubernetes/pki/front-proxy-client.key \\
    --requestheader-allowed-names=front-proxy-client \\
    --requestheader-client-ca-file=/etc/kubernetes/pki/front-proxy-ca.crt \\
    --requestheader-extra-headers-prefix=X-Remote-Extra- \\
    --requestheader-group-headers=X-Remote-Group \\
    --requestheader-username-headers=X-Remote-User
Restart=always
StartLimitInterval=0
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
else
cat <<EOF >  "${cur}/etc/kubernetes/manifests/kube-apiserver.yaml"
apiVersion: v1
kind: Pod
metadata:
  annotations:
    kubeadm.kubernetes.io/kube-apiserver.advertise-address.endpoint: ${LAN_IP}:6443
  creationTimestamp: null
  labels:
    component: kube-apiserver
    tier: control-plane
  name: kube-apiserver
  namespace: kube-system
spec:
  containers:
  - command:
    - kube-apiserver
    - --bind-address=0.0.0.0
    - --advertise-address=${LAN_IP}
    - --allow-privileged=true
    - --authorization-mode=Node,RBAC
    - --client-ca-file=/etc/kubernetes/pki/ca.crt
    - --enable-admission-plugins=NodeRestriction
    - --enable-bootstrap-token-auth=true
    - --etcd-cafile=/etc/kubernetes/pki/etcd/ca.crt
    - --etcd-certfile=/etc/kubernetes/pki/etcd/all.crt
    - --etcd-keyfile=/etc/kubernetes/pki/etcd/all.key
    - --etcd-servers=https://${LAN_IP}:2379
    - --kubelet-client-certificate=/etc/kubernetes/pki/apiserver-kubelet-client.crt
    - --kubelet-client-key=/etc/kubernetes/pki/apiserver-kubelet-client.key
    - --kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname
    - --proxy-client-cert-file=/etc/kubernetes/pki/front-proxy-client.crt
    - --proxy-client-key-file=/etc/kubernetes/pki/front-proxy-client.key
    - --requestheader-allowed-names=front-proxy-client
    - --requestheader-client-ca-file=/etc/kubernetes/pki/front-proxy-ca.crt
    - --requestheader-extra-headers-prefix=X-Remote-Extra-
    - --requestheader-group-headers=X-Remote-Group
    - --requestheader-username-headers=X-Remote-User
    - --secure-port=6443
    - --service-account-issuer=https://kubernetes.default.svc.cluster.local
    - --service-account-key-file=/etc/kubernetes/pki/sa.pub
    - --service-account-signing-key-file=/etc/kubernetes/pki/sa.key
    - --service-cluster-ip-range=${SERVICE_CIDR}
    - --tls-cert-file=/etc/kubernetes/pki/apiserver.crt
    - --tls-private-key-file=/etc/kubernetes/pki/apiserver.key
    image: registry.k8s.io/kube-apiserver:v1.26.1
    imagePullPolicy: IfNotPresent
    resources:
        requests:
            memory: "16Mi"
        limits:
            memory: "2048Mi"
    livenessProbe:
      failureThreshold: 8
      httpGet:
        host: 127.0.0.1
        path: /livez
        port: 6443
        scheme: HTTPS
      initialDelaySeconds: 10
      periodSeconds: 10
      timeoutSeconds: 15
    name: kube-apiserver
    readinessProbe:
      failureThreshold: 3
      httpGet:
        host: 127.0.0.1
        path: /readyz
        port: 6443
        scheme: HTTPS
      periodSeconds: 1
      timeoutSeconds: 15
    startupProbe:
      failureThreshold: 24
      httpGet:
        host: 127.0.0.1
        path: /livez
        port: 6443
        scheme: HTTPS
      initialDelaySeconds: 10
      periodSeconds: 10
      timeoutSeconds: 15
    volumeMounts:
    - mountPath: /etc/ssl/certs
      name: ca-certs
      readOnly: true
    - mountPath: /etc/ca-certificates
      name: etc-ca-certificates
      readOnly: true
    - mountPath: /etc/kubernetes/pki
      name: k8s-certs
      readOnly: true
    - mountPath: /usr/share/ca-certificates
      name: usr-share-ca-certificates
      readOnly: true
  hostNetwork: true
  priorityClassName: system-node-critical
  securityContext:
    seccompProfile:
      type: RuntimeDefault
  volumes:
  - hostPath:
      path: /etc/ssl/certs
      type: DirectoryOrCreate
    name: ca-certs
  - hostPath:
      path: /etc/ca-certificates
      type: DirectoryOrCreate
    name: etc-ca-certificates
  - hostPath:
      path: /etc/kubernetes/pki
      type: DirectoryOrCreate
    name: k8s-certs
  - hostPath:
      path: /usr/share/ca-certificates
      type: DirectoryOrCreate
    name: usr-share-ca-certificates
status: {}
EOF
fi
