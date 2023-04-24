---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: egress-test
  namespace: {{ .HelmDeployNamespace }}
  labels:
    app: egress-test
spec:
  selector:
    matchLabels:
      app: egress-test
  template:
    metadata:
      labels:
        app: egress-test
    spec:
      containers:
      - name: egress-block-test
        image: "ubuntu"
        command: 
        - /bin/bash
        - -c
        - |
          apt-get update && apt-get install -y iputils-ping; /script/network-egress-test.sh
        securityContext:
          privileged: true
        volumeMounts:
        - name: networking-test
          mountPath: /script
        - name: dmesg-volume
          mountPath: /var/log/dmesg

      volumes:
      - name: networking-test
        configMap:
          defaultMode: 511
          name: network-test
      - name: dmesg-volume
        hostPath:
          path: /dev/kmsg

---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: ingress-test
  namespace: {{ .HelmDeployNamespace }}
  labels:
    app: ingress-test
spec:
  selector:
    matchLabels:
      app: ingress-test
  template:
    metadata:
      labels:
        app: ingress-test
    spec:
      containers:
      - name: ingress-block-test
        image: "ubuntu"
        command: 
        - /bin/bash
        - -c
        - |
          apt-get update && apt-get install -y iputils-ping python3 python3-pip; pip3 install scapy; /script/network-ingress-test.sh
        securityContext:
          privileged: true
        volumeMounts:
        - name: networking-test
          mountPath: /script
        - name: dmesg-volume
          mountPath: /var/log/dmesg
        env:
        - name: MY_POD_IP
          valueFrom:
            fieldRef:
              fieldPath: status.podIP

      volumes:
      - name: networking-test
        configMap:
          defaultMode: 511
          name: network-test
      - name: dmesg-volume
        hostPath:
          path: /dev/kmsg

---
apiVersion: v1
kind: ConfigMap
metadata:
  name: network-test
  namespace: {{ .HelmDeployNamespace }}
data:
  network-egress-test.sh: |
    BLOCKED_IP="93.184.216.34"
    while true
    do 
        sleep 15
        old_msg=$(dmesg | grep Policy-Filter-Dropped | grep $BLOCKED_IP | tail -1)
        ping -c 1 $BLOCKED_IP
        if [ $? -eq 0 ]; then
          echo "ERROR: ping $BLOCKED_IP should be blocked"
          exit 1
        fi
        new_msg=$(dmesg | grep Policy-Filter-Dropped | grep $BLOCKED_IP | tail -1)

        if [ "$old_msg" == "$new_msg" ]; then
          echo "ERROR: Blocked access should be logged"
          exit 1
        fi
    done
  network-ingress-test.sh: |
    BLOCKED_IP="130.214.229.163"
    while true
    do 
        sleep 15
        old_msg=$(dmesg | grep Policy-Filter-Dropped | grep $BLOCKED_IP | tail -1)
        python3 /script/send_spoofed_packet.py $BLOCKED_IP $MY_POD_IP

        new_msg=$(dmesg | grep Policy-Filter-Dropped | grep $BLOCKED_IP | tail -1)

        if [ "$old_msg" == "$new_msg" ]; then
          echo "ERROR: Blocked access should be logged"
          exit 1
        fi
    done
  send_spoofed_packet.py: |
    from scapy.all import *
    import sys
    
    src_ip = sys.argv[1]
    dst_ip = sys.argv[2]

    ip = IP(src=src_ip, dst=dst_ip)

    icmp = ICMP()

    send(ip/icmp)
