package main

import (
	"fmt"
	"net"
	"os"
	"strings"
    "path"
)

func init() {
    HostName, _ = os.Hostname()
    ifaces, _ := net.Interfaces()
    pkiPath = path.Join(os.Getenv("ROOT_DIR"), "etc/kubernetes/pki")
    kubeConfigPath = path.Join(os.Getenv("ROOT_DIR"), "etc/kubernetes")
    ServiceIP = net.ParseIP(os.Getenv("SERVICE_IP"))

    if ServiceIP == nil {
        panic(fmt.Sprintf("无效的 Service IP %s", os.Getenv("SERVICE_IP")))
    }

    for _, iface := range ifaces {
       if !strings.HasPrefix( iface.Name, "e") {
            continue
        }
        addrs, _ := iface.Addrs()  
        for _, addr := range addrs {
            ip, _, _ := net.ParseCIDR(addr.String())
            ip = ip.To4()
            if ip == nil {
                return
            }
            LanIP = ip
            ApiServer = fmt.Sprintf("https://%s:6443", LanIP)
        }
    }
}
