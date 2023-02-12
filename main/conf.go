package main

import (
	"crypto"
	"crypto/x509"
	"fmt"
	"os"
	"path"

	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/client-go/tools/clientcmd/api"
	clientcmdlatest "k8s.io/client-go/tools/clientcmd/api/latest"
)

type KubeConfigSpec struct {
	ClientName    string
	Organizations []string
	FileName      string
}

func getKubeConfigSpecs() []KubeConfigSpec {
	return []KubeConfigSpec{
		{
			ClientName:    "kubernetes-admin",
			Organizations: []string{"system:masters"},
			FileName:      "admin.conf",
		},
		{
			ClientName:    fmt.Sprintf("system:node:%s", HostName),
			Organizations: []string{"system:nodes"},
			FileName:      "kubelet.conf",
		},
		{
			ClientName: "system:kube-controller-manager",
			Organizations: []string{"system:kube-controller-manager"},
			FileName:   "controller-manager.conf",
		},
		{
			ClientName: "system:kube-scheduler",
			Organizations: []string{"system:kube-scheduler"},
			FileName:   "scheduler.conf",
		},
		{
            ClientName: "system:kube-proxy",
            Organizations: []string{"system:node-proxier"},
			FileName:   "kube-proxy.conf",
		},
	}
}

// 生成 kubeconfig
func genKubeconfig(spec KubeConfigSpec) (kubeConfig *api.Config, err error) {
	var (
		clientCert *x509.Certificate
		clientKey  crypto.Signer
	)
	caCert, caKey, err := LoadCA("ca")
	if err != nil {
		return nil, err
	}

	certConfig := CertConfig{
		CommonName:   spec.ClientName,
		Organization: spec.Organizations,
		Usages:       []x509.ExtKeyUsage{x509.ExtKeyUsageClientAuth},
	}

	certSpec := CertSpec{
		CAName: "ca",
		Config: certConfig,
	}

	if clientCert, clientKey, err = certSpec.CreateFromCa(caCert, caKey); err != nil {
		return nil, err
	}

	contextName := fmt.Sprintf("%s@%s", spec.ClientName, ClusterName)
	clientKeyEncoded, _ := MarshalPrivateKeyToPEM(clientKey)

	kubeConfig = &api.Config{
		Clusters: map[string]*api.Cluster{
			ClusterName: {
				Server:                   ApiServer,
				CertificateAuthorityData: EncodeCertPEM(caCert),
			},
		}, // 集群
		Contexts: map[string]*api.Context{
			contextName: {
				Cluster:  ClusterName,
				AuthInfo: spec.ClientName,
			},
		}, // 用户名-集群
		CurrentContext: contextName,
		AuthInfos: map[string]*api.AuthInfo{
			spec.ClientName: {
				ClientKeyData:         clientKeyEncoded,
				ClientCertificateData: EncodeCertPEM(clientCert),
			},
		}, // 客户端密钥/证书
	}
	return
}

func GenKubeConfig() error {
	for _, spec := range getKubeConfigSpecs() {
		cfg, err := genKubeconfig(spec)
		if err != nil {
			return err
		}

		content, err := runtime.Encode(clientcmdlatest.Codec, cfg)
		if err != nil {
			return err
		}
		if err = os.WriteFile(path.Join(kubeConfigPath, spec.FileName), content, 0600); err != nil {
			return err
		}
	}
	return nil
}
