#!/bin/bash

es_password=$(kubectl get secret passwords-store -o jsonpath='{$.data.admin}' | base64 --decode)
ns=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
instance=$(echo "$ns" | cut -c 4-)
ingress_val=$(kubectl get eckf "eckf-$instance" -o jsonpath='{$.spec.ingress}')

until $(curl --output /dev/null --silent --head --fail -u "admi:$es_password" http://elastic-client:9200); do es_password=$(kubectl get secret passwords-store -o jsonpath='{$.data.admin}' | base64 --decode); echo $es_password; sleep 5;  done; echo \"Complete\";


depl="{\"apiVersion\":\"jaegertracing.io/v1\",\"kind\":\"Jaeger\",\"metadata\":{\"name\":\"jaeger\"},\"spec\":{\"strategy\":\"production\",\"storage\":{\"type\":\"elasticsearch\",\"options\":{\"es\":{\"server-urls\":\"http://elastic-client:9200\",\"username\":\"admin\",\"password\":\"$es_password\"}}}}}"
depl=$(echo $depl)

cat << EOF | kubectl apply -f -
$depl
EOF

##
collector_url="collector-$instance.$ingress_val"
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
DNS.1 = $collectorURL
EOF

openssl req -new -x509 -sha256 -newkey rsa:2048 -nodes -keyout CA.key -days 365 -out CA.crt -config csr.txt &> /dev/null

openssl req -nodes -newkey rsa:2048 -keyout server.key -out server.csr -config csr.txt &> /dev/null



