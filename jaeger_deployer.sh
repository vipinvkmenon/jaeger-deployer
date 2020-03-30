#!/bin/bash

es_password=$(kubectl get secret passwords-store -o jsonpath='{$.data.admin}' | base64 --decode)

until $(curl --output /dev/null --silent --head --fail -u "admi:$es_password" http://elastic-client:9200); do es_password=$(kubectl get secret passwords-store -o jsonpath='{$.data.admin}' | base64 --decode); echo $es_password; sleep 5;  done; echo \"Complete\";


depl="{\"apiVersion\":\"jaegertracing.io/v1\",\"kind\":\"Jaeger\",\"metadata\":{\"name\":\"jaeger\"},\"spec\":{\"strategy\":\"production\",\"storage\":{\"type\":\"elasticsearch\",\"options\":{\"es\":{\"server-urls\":\"http://elastic-client:9200\",\"username\":\"admin\",\"password\":\"$es_password\"}}}}}"
depl=$(echo $depl)

cat << EOF | kubectl apply -f -
$depl
EOF

