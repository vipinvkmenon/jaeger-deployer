#!/bin/bash

es_password=$(kubectl get secret passwords-store -o jsonpath='{$.data.admin}' | base64 --decode)
ns=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
instance=$(echo "$ns" | cut -c 4-)
echo "Instance is " $instance
kubectl get cls "cls-$instance"

ingress_val=$(kubectl get cls "cls-$instance" -o jsonpath='{$.spec.ingress}')

until $(curl --output /dev/null --silent --head --fail -u "admin:$es_password" http://elastic-client:9200); do es_password=$(kubectl get secret passwords-store -o jsonpath='{$.data.admin}' | base64 --decode); echo $es_password; sleep 5;  done; echo \"Complete\";


depl="{\"apiVersion\":\"jaegertracing.io/v1\",\"kind\":\"Jaeger\",\"metadata\":{\"name\":\"jaeger\"},\"spec\":{\"strategy\":\"production\",\"storage\":{\"type\":\"elasticsearch\",\"options\":{\"es\":{\"server-urls\":\"http://elastic-client:9200\",\"username\":\"admin\",\"password\":\"$es_password\"}}}}}"
depl=$(echo $depl)

cat << EOF | kubectl apply -f -
$depl
EOF

echo "Ingres val " $(kubectl get cls "cls-$instance" -o jsonpath='{$.spec.ingress}')
ingress_val=$(kubectl get cls "cls-$instance" -o jsonpath='{$.spec.ingress}')
##
jaegercollector="jaeger-collector-$ns.$ingress_val"
jaegergrpccollector="jaeger-grpc-collector-$ns.$ingress_val"
jaegerquery="jaeger-query-$ns.$ingress_val"

cd tmp

cat > csr.txt << EOF
[req]
default_bits = 2048
prompt = no
default_md = sha256
req_extensions = req_ext
distinguished_name = dn

[ dn ]
C=NA
ST=NA
L=NA
O=NA
OU=Jaeger
emailAddress=$email
CN = $ns
[ req_ext ]
subjectAltName = @alt_names
[ alt_names ]
DNS.1 = $jaegercollector
EOF

openssl req -new -x509 -sha256 -newkey rsa:2048 -nodes -keyout CA.key -days 365 -out CA.crt -config csr.txt &> /dev/null

openssl req -nodes -newkey rsa:2048 -keyout server.key -out server.csr -config csr.txt &> /dev/null

openssl x509 -req -extfile <(printf "subjectAltName=DNS:$jaegercollector") -days 1460 -in server.csr -CA CA.crt -CAkey CA.key -set_serial 01 -out server.crt &> /dev/null

kubectl create secret generic jaeger-grpc-tls --from-file=tls.crt=server.crt --from-file=tls.key=server.key --from-file=ca.crt=CA.crt --from-file=ca.key=CA.key

jaeger_pass=`openssl rand -base64 10`
htpasswd -c -b auth jaeger $jaeger_pass

kubectl create secret generic jaeger-http-auth --from-file=auth=auth --from-literal=username=jaeger --from-literal=password="$jaeger_pass"

cat << EOF | kubectl apply -f -
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  annotations:
    kubernetes.io/ingress.class: nginx
    kubernetes.io/tls-acme: "true"
    nginx.ingress.kubernetes.io/auth-type: basic
    nginx.ingress.kubernetes.io/auth-secret: jaeger-http-auth
    nginx.ingress.kubernetes.io/auth-realm: 'Authentication Required'
  labels:
    app: jaeger
    release: jaeger
  name: jaeger-collector-ingress
spec:
  rules:
  - host: $jaegercollector
    http:
      paths:
      - path: /
        backend:
          serviceName: jaeger-collector
          servicePort: 14268
  tls:
  - hosts:
    - $jaegercollector
---
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  annotations:
    kubernetes.io/ingress.class: nginx
    kubernetes.io/tls-acme: "true"
    nginx.ingress.kubernetes.io/auth-type: basic
    nginx.ingress.kubernetes.io/auth-secret: jaeger-http-auth
    nginx.ingress.kubernetes.io/auth-realm: 'Authentication Required'
  labels:
    app: jaeger
    release: jaeger
  name: jaeger-query-ingress
spec:
  rules:
  - host: $jaegerquery
    http:
      paths:
      - path: /
        backend:
          serviceName: jaeger-query
          servicePort: 16686
  tls:
  - hosts:
    - $jaegerquery
---    
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  annotations:
    kubernetes.io/ingress.class: nginx
    nginx.ingress.kubernetes.io/backend-protocol: "GRPC"
    nginx.ingress.kubernetes.io/grpc-backend: "true"
    nginx.ingress.kubernetes.io/auth-tls-verify-client: "on"
    nginx.ingress.kubernetes.io/auth-tls-secret: "jaeger-grpc-tls"
  labels:
    app: jaeger
    release: jaeger
  name: jaeger-grpc-ingress
spec:
  rules:
  - host: $jaegergrpccollector
    http:
      paths:
      - path: / 
        backend:
          serviceName: jaeger-collector-grpc
          servicePort: 14250
  tls:
  - hosts:
    - $jaegergrpccollector 
    secretName: jaeger-grpc-tls  
EOF
