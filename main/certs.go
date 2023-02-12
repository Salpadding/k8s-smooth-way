package main

import (
	"crypto"
	"crypto/ecdsa"
	"crypto/elliptic"
	cryptorand "crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"fmt"
	//"math"
	"math/big"
	"net"
	"os"
	"path/filepath"
	"time"
)

// 生成 CA 过程
// 1. 生成密钥对
// 2. 用私钥给自己作签名

const (
	rsaKeySize     = 2048
	duration365d   = time.Hour * 24 * 365

	// ECPrivateKeyBlockType is a possible value for pem.Block.Type.
	ECPrivateKeyBlockType = "EC PRIVATE KEY"
	// RSAPrivateKeyBlockType is a possible value for pem.Block.Type.
	RSAPrivateKeyBlockType = "RSA PRIVATE KEY"
	// PrivateKeyBlockType is a possible value for pem.Block.Type.
	PrivateKeyBlockType = "PRIVATE KEY"
	// PublicKeyBlockType is a possible value for pem.Block.Type.
	PublicKeyBlockType = "PUBLIC KEY"
	// CertificateBlockType is a possible value for pem.Block.Type.
	CertificateBlockType = "CERTIFICATE"
	CertificateValidity  = time.Hour * 24 * 365
    SerialNumber = 202202101000 // 固定序列号便于调试认证
)

var (
	LanIP       net.IP
	LoopIP      = net.IPv4(127, 0, 0, 1)
	ServiceIP   = net.IPv4(10, 96, 0, 1)
	ApiServer   string
	ClusterName = "kubernetes"
    HostName string
	pkiPath      string
	kubeConfigPath string
)

// ParsePrivateKeyPEM returns a private key parsed from a PEM block in the supplied data.
// Recognizes PEM blocks for "EC PRIVATE KEY", "RSA PRIVATE KEY", or "PRIVATE KEY"
func ParsePrivateKeyPEM(keyData []byte) (interface{}, error) {
	var privateKeyPemBlock *pem.Block
	for {
		privateKeyPemBlock, keyData = pem.Decode(keyData)
		if privateKeyPemBlock == nil {
			break
		}

		switch privateKeyPemBlock.Type {
		case ECPrivateKeyBlockType:
			// ECDSA Private Key in ASN.1 format
			if key, err := x509.ParseECPrivateKey(privateKeyPemBlock.Bytes); err == nil {
				return key, nil
			}
		case RSAPrivateKeyBlockType:
			// RSA Private Key in PKCS#1 format
			if key, err := x509.ParsePKCS1PrivateKey(privateKeyPemBlock.Bytes); err == nil {
				return key, nil
			}
		case PrivateKeyBlockType:
			// RSA or ECDSA Private Key in unencrypted PKCS#8 format
			if key, err := x509.ParsePKCS8PrivateKey(privateKeyPemBlock.Bytes); err == nil {
				return key, nil
			}
		}

		// tolerate non-key PEM blocks for compatibility with things like "EC PARAMETERS" blocks
		// originally, only the first PEM block was parsed and expected to be a key block
	}

	// we read all the PEM blocks and didn't recognize one
	return nil, fmt.Errorf("data does not contain a valid RSA or ECDSA private key")
}

// LoadCA tries to load a CA in the given directory with the given name.
func LoadCA(caName string) (cert *x509.Certificate, key crypto.Signer, err error) {
	// 1. 加载根证书
	// 2. 加载私钥
	// etcd-ca -> etcd/ca
	// front-proxy-ca
	var baseName string
	if caName == "etcd-ca" {
		baseName = "etcd/ca"
	} else {
		baseName = caName
	}
	pemCerts, err := os.ReadFile(fmt.Sprintf("%s/%s.crt", pkiPath, baseName))
	if err != nil {
		return nil, nil, err
	}
	certs := []*x509.Certificate{}
	for len(pemCerts) > 0 {
		var block *pem.Block
		block, pemCerts = pem.Decode(pemCerts)
		if block == nil {
			break
		}
		// Only use PEM "CERTIFICATE" blocks without extra headers
		if block.Type != CertificateBlockType || len(block.Headers) != 0 {
			continue
		}

		cert, err := x509.ParseCertificate(block.Bytes)
		if err != nil {
			return nil, nil, err
		}

		certs = append(certs, cert)
	}
	cert = certs[0]

	data, err := os.ReadFile(fmt.Sprintf("%s/%s.key", pkiPath, baseName))
	if err != nil {
		return nil, nil, err
	}
	privKey, err := ParsePrivateKeyPEM(data)
	if err != nil {
		return nil, nil, fmt.Errorf("error reading private key file %s: %v", caName, err)
	}

	switch k := privKey.(type) {
	case *rsa.PrivateKey:
		key = k
	case *ecdsa.PrivateKey:
		key = k
	default:
		return nil, nil, fmt.Errorf("the private key file %s is neither in RSA nor ECDSA format", caName)
	}

	return
}

// MarshalPrivateKeyToPEM converts a known private key type of RSA or ECDSA to
// a PEM encoded block or returns an error.
func MarshalPrivateKeyToPEM(privateKey crypto.PrivateKey) ([]byte, error) {
	switch t := privateKey.(type) {
	case *ecdsa.PrivateKey:
		derBytes, err := x509.MarshalECPrivateKey(t)
		if err != nil {
			return nil, err
		}
		block := &pem.Block{
			Type:  ECPrivateKeyBlockType,
			Bytes: derBytes,
		}
		return pem.EncodeToMemory(block), nil
	case *rsa.PrivateKey:
		block := &pem.Block{
			Type:  RSAPrivateKeyBlockType,
			Bytes: x509.MarshalPKCS1PrivateKey(t),
		}
		return pem.EncodeToMemory(block), nil
	default:
		return nil, fmt.Errorf("private key is not a recognized type: %T", privateKey)
	}
}

// EncodeCertPEM returns PEM-endcoded certificate data
func EncodeCertPEM(cert *x509.Certificate) []byte {
	block := pem.Block{
		Type:  CertificateBlockType,
		Bytes: cert.Raw,
	}
	return pem.EncodeToMemory(&block)
}

// EncodePublicKeyPEM returns PEM-encoded public data
func EncodePublicKeyPEM(key crypto.PublicKey) ([]byte, error) {
	der, err := x509.MarshalPKIXPublicKey(key)
	if err != nil {
		return []byte{}, err
	}
	block := pem.Block{
		Type:  PublicKeyBlockType,
		Bytes: der,
	}
	return pem.EncodeToMemory(&block), nil
}

// AltNames contains the domain names and IP addresses that will be added
// to the API Server's x509 certificate SubAltNames field. The values will
// be passed directly to the x509.Certificate object.
type AltNames struct {
	DNSNames []string
	IPs      []net.IP
}

// Config contains the basic fields required for creating a certificate
type CertConfig struct {
	CommonName         string
	Organization       []string
	AltNames           AltNames
	Usages             []x509.ExtKeyUsage
	NotAfter           *time.Time
	PublicKeyAlgorithm x509.PublicKeyAlgorithm

	BaseName string // key/证书 保存的路径
}

type CertSpec struct {
	CAName string     // 签名用的根证书
	Config CertConfig // 私钥 签名配置项
}

// CreateFromCa
// 主要用到的配置项是
// spec.Config.Usages spec.Config.PublicKeyAlgorithm
// spec.Config.CommonName spec.Config.AltNames
// spec.Config.NotAfter spec.Config.Organization
func (spec *CertSpec) CreateFromCa(caCert *x509.Certificate, caKey crypto.Signer) (*x509.Certificate, crypto.Signer, error) {
	// 1. 生成私钥
	key, err := GeneratePrivateKey(spec.Config.PublicKeyAlgorithm)
	if err != nil {
		return nil, nil, err
	}
	// 2. 签名
	serial := new(big.Int).SetInt64(SerialNumber)
	if err != nil {
		return nil, nil, err
	}
	keyUsage := x509.KeyUsageKeyEncipherment | x509.KeyUsageDigitalSignature
	notAfter := time.Now().Add(CertificateValidity).UTC()
	if spec.Config.NotAfter != nil {
		notAfter = *spec.Config.NotAfter
	}
    var dnsNames []string 
    func(){
        dnsMap := make(map[string]bool)

        for _, name := range spec.Config.AltNames.DNSNames {
            if _, ok := dnsMap[name]; ok {
                continue
            }
            dnsNames =append(dnsNames, name)
            dnsMap[name] = true
        }
    }()
	certTmpl := x509.Certificate{
		Subject: pkix.Name{
			CommonName:   spec.Config.CommonName,
			Organization: spec.Config.Organization,
		},
		DNSNames:              spec.Config.AltNames.DNSNames,
		IPAddresses:           spec.Config.AltNames.IPs,
		SerialNumber:          serial,
		NotBefore:             caCert.NotBefore,
		NotAfter:              notAfter,
		KeyUsage:              keyUsage,
		ExtKeyUsage:           spec.Config.Usages,
		BasicConstraintsValid: true,
		IsCA:                  false,
	}
	certDERBytes, err := x509.CreateCertificate(cryptorand.Reader, &certTmpl, caCert, key.Public(), caKey)
	if err != nil {
		return nil, nil, err
	}
	cert, err := x509.ParseCertificate(certDERBytes)
	if err != nil {
		return nil, nil, err
	}
	return cert, key, nil
}

// NewSelfSignedCACert creates a CA certificate
// 生成自签名证书
// 只用到了 CommonName, Organization
func NewSelfSignedCACert(cfg CertConfig, key crypto.Signer) (*x509.Certificate, error) {
	now := time.Now()
	tmpl := x509.Certificate{
		SerialNumber: new(big.Int).SetInt64(0),
		Subject: pkix.Name{
			CommonName:   cfg.CommonName,
			Organization: cfg.Organization,
		},
		DNSNames:              []string{cfg.CommonName},
		NotBefore:             now.UTC(),
		NotAfter:              now.Add(duration365d * 10).UTC(),
		KeyUsage:              x509.KeyUsageKeyEncipherment | x509.KeyUsageDigitalSignature | x509.KeyUsageCertSign,
		BasicConstraintsValid: true,
		IsCA:                  true,
	}

	certDERBytes, err := x509.CreateCertificate(cryptorand.Reader, &tmpl, &tmpl, key.Public(), key)
	if err != nil {
		return nil, err
	}
	return x509.ParseCertificate(certDERBytes)
}

// GeneratePrivateKey 生成密钥对
func GeneratePrivateKey(keyType x509.PublicKeyAlgorithm) (crypto.Signer, error) {
	if keyType == x509.ECDSA {
		return ecdsa.GenerateKey(elliptic.P256(), cryptorand.Reader)
	}

	return rsa.GenerateKey(cryptorand.Reader, rsaKeySize)
}

func writeCertAndKey(baseName string, cert *x509.Certificate, key crypto.Signer) error {
	// write *.key
	pem, err := MarshalPrivateKeyToPEM(key)
	if err != nil {
		return err
	}
	if err = os.WriteFile(filepath.Join(pkiPath, fmt.Sprintf("%s.key", baseName)), pem, os.FileMode(0600)); err != nil {
		return err
	}
	// write *.crt
	if err = os.WriteFile(filepath.Join(pkiPath, fmt.Sprintf("%s.crt", baseName)), EncodeCertPEM(cert), os.FileMode(0644)); err != nil {
		return err
	}
	return nil
}

// 生成根证书
func GenCa() error {

	configs := []CertConfig{
		{
			CommonName:         "kubernetes",
			PublicKeyAlgorithm: x509.RSA,
			BaseName:           "ca",
		}, // 生成  ca.key ca.crt k8s 集群根证书
		{
			CommonName:         "etcd-ca",
			PublicKeyAlgorithm: x509.RSA,
			BaseName:           "etcd/ca",
		}, // 生成  etcd/ca.key etcd/ca.crt etcd根证书
		{
			CommonName:         "front-proxy-ca",
			PublicKeyAlgorithm: x509.RSA,
			BaseName:           "front-proxy-ca",
		}, // 生成  front-proxy-ca
	}

	for _, cfg := range configs {
		privateKey, err := GeneratePrivateKey(cfg.PublicKeyAlgorithm)
		if err != nil {
			return err
		}
		cert, err := NewSelfSignedCACert(cfg, privateKey)
		if err != nil {
			return err
		}
		if err = writeCertAndKey(cfg.BaseName, cert, privateKey); err != nil {
			return err
		}
	}
	return nil
}

// 生成根证书签名过的 密钥对和证书
func GenCerts() error {
	configs := []CertSpec{
		{
			CAName: "etcd-ca",
			Config: CertConfig{
				CommonName: HostName,
				AltNames: AltNames{
					DNSNames: []string{"localhost", HostName},
					IPs: []net.IP{
						LoopIP,
						LanIP,
					},
				},
				Usages: []x509.ExtKeyUsage{
					x509.ExtKeyUsageServerAuth,
					x509.ExtKeyUsageClientAuth,
				},
				PublicKeyAlgorithm: x509.RSA,
				BaseName:           "etcd/all", // 用于所有和 etcd 相关的认证
			},
		},
		{
			CAName: "ca",
			Config: CertConfig{
				CommonName: "kube-apiserver",
				AltNames: AltNames{
					DNSNames: []string{HostName, "localhost", "kubernetes", "kubernetes.default", "kubernetes.default.svc", "kubernetes.default.svc.cluster.local"},
					IPs: []net.IP{
						LoopIP,
						LanIP,
						ServiceIP,
					},
				},
				Usages: []x509.ExtKeyUsage{
					x509.ExtKeyUsageServerAuth,
				},
				PublicKeyAlgorithm: x509.RSA,
				BaseName:           "apiserver", // api server 的 tls
			},
		},
		{
			CAName: "ca",
			Config: CertConfig{
				CommonName:   "kube-apiserver-kubelet-client",
				Organization: []string{"system:masters"},
				Usages: []x509.ExtKeyUsage{
					x509.ExtKeyUsageClientAuth,
				},
				PublicKeyAlgorithm: x509.RSA,
				BaseName:           "apiserver-kubelet-client", // api server 跟 kubelet 认证时的身份
			},
		},
		{
			CAName: "front-proxy-ca",
			Config: CertConfig{
				CommonName:   "front-proxy-client",
				Organization: []string{"system:masters"},
				Usages: []x509.ExtKeyUsage{
					x509.ExtKeyUsageClientAuth,
				},
				PublicKeyAlgorithm: x509.RSA,
				BaseName:           "front-proxy-client", // 尚未用到
			},
		},
		{
			CAName: "etcd-ca",
			Config: CertConfig{
				CommonName:   HostName,
				Organization: []string{"system:masters"},
				Usages: []x509.ExtKeyUsage{
					x509.ExtKeyUsageServerAuth,
					x509.ExtKeyUsageClientAuth,
				},
				PublicKeyAlgorithm: x509.RSA,
				BaseName:           "etcd/peer", // etcd peer 之间认证 尚未用到 可以用 etcd/all
				AltNames: AltNames{
					DNSNames: []string{"localhost", HostName},
					IPs: []net.IP{
						LoopIP,
						LanIP,
						net.IPv6loopback,
					},
				},
			},
		},
	}

	for _, cfg := range configs {
		cert, key, err := LoadCA(cfg.CAName)
		if err != nil {
			return err
		}
		if cert, key, err = cfg.CreateFromCa(cert, key); err != nil {
			return err
		}
		if err = writeCertAndKey(cfg.Config.BaseName, cert, key); err != nil {
			return err
		}
	}

	// 生成 sa.key sa.pub service account 密钥对
	saKey, err := GeneratePrivateKey(x509.RSA)
	if err != nil {
		return err
	}
	pem, err := MarshalPrivateKeyToPEM(saKey)
	if err != nil {
		return err
	}
	if err = os.WriteFile(filepath.Join(pkiPath, "sa.key"), pem, os.FileMode(0600)); err != nil {
		return err
	}
	pub, err := EncodePublicKeyPEM(saKey.Public())
	if err != nil {
		return err
	}
	if err = os.WriteFile(filepath.Join(pkiPath, "sa.pub"), pub, os.FileMode(0600)); err != nil {
		return err
	}
	return nil
}

func main() {
    var err error
	if len(os.Args) < 2 {
		return
	}
	// 生成或者覆盖证书
	if os.Args[1] == "certs" {
		err := GenCa()
		if err != nil {
			panic(err)
		}
		err = GenCerts()
		if err != nil {
			panic(err)
		}
		if err = GenKubeConfig(); err != nil {
			panic(err)
		}
		return
	}

    if os.Args[1] == "config" {
		if err = GenKubeConfig(); err != nil {
			panic(err)
		}
        return
    }

	// 生成 etcd 配置 /etc/kubernetes/manifests
	if os.Args[1] == "etcd" {
		return
	}

	if os.Args[1] == "lanIP" {
		fmt.Printf("%s\n", LanIP)
		return
	}
}
