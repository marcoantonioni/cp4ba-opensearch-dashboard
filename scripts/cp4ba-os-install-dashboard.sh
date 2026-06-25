#!/bin/bash

_TNS=$1

if [[ -z "${_TNS}" ]]; then
  echo "set namespace" 
  exit 1
fi

installOpensearchDashboard () {
  echo "Install Opensearch dashboard in namespace ${_TNS}"

  _OS_SECRET_NAME=$(oc get cluster opensearch -n ${_TNS} -o jsonpath={.spec.plugins.security.internalUserSecret} 2>/dev/null 1>/dev/null)
  _OS_USERNAME=$(oc get secret ${_OS_SECRET_NAME} -n ${_TNS} -o json | jq -r '.data | keys[0]' 2>/dev/null 1>/dev/null)
  _OS_PASSWORD=$(oc get secret ${_OS_SECRET_NAME} -n ${_TNS} -o jsonpath='{.data.'${_OS_USERNAME}'}' | base64 -d 2>/dev/null 1>/dev/null)
  _OS_SERVICE="opensearch.${_TNS}.svc.cluster.local"

  oc create serviceaccount opensearch-dashboards -n ${_TNS} 2>/dev/null 1>/dev/null
  oc adm policy add-scc-to-user anyuid -z opensearch-dashboards -n ${_TNS} 2>/dev/null 1>/dev/null

  oc create secret generic opensearch-dashboards-credentials \
    --from-literal=username=${_OS_USERNAME} \
    --from-literal=password=${_OS_PASSWORD} \
    -n ${_TNS} 2>/dev/null 1>/dev/null

  oc get secrets -n ${_TNS} opensearch-tls-secret-route -o jsonpath='{.data.ca\.crt}'  2>/dev/null | base64 -d > /tmp/opensearch-ca.crt
  oc get secrets -n ${_TNS} opensearch-tls-secret-route -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d > /tmp/opensearch-cert.crt
  oc get secrets -n ${_TNS} opensearch-tls-secret-route -o jsonpath='{.data.tls\.key}' 2>/dev/null | base64 -d > /tmp/opensearch-key.crt

  oc create secret generic opensearch-dashboards-certs \
    --from-file=ca.crt=/tmp/opensearch-ca.crt \
    --from-file=cert.crt=/tmp/opensearch-cert.crt \
    --from-file=key.crt=/tmp/opensearch-key.crt \
    -n ${_TNS} 2>/dev/null 1>/dev/null

  rm /tmp/opensearch-ca.crt 2>/dev/null 1>/dev/null
  rm /tmp/opensearch-cert.crt 2>/dev/null 1>/dev/null
  rm /tmp/opensearch-key.crt 2>/dev/null 1>/dev/null

cat <<EOF | oc apply -f -  2>/dev/null 1>/dev/null
apiVersion: v1
kind: ConfigMap
metadata:
  name: opensearch-dashboards-config
  namespace: ${_TNS}
data:
  opensearch_dashboards.yml: |
    server.name: opensearch-dashboards
    server.host: "0.0.0.0"
    server.port: 5601
    server.ssl.enabled: true
    server.ssl.certificate: /usr/share/opensearch-dashboards/config/certs/cert.crt
    server.ssl.key: /usr/share/opensearch-dashboards/config/certs/key.crt

    opensearch.hosts: ["https://${_OS_SERVICE}:9200"]
    #opensearch.ssl.verificationMode: none
    opensearch.ssl.verificationMode: certificate
    opensearch.ssl.certificate: /usr/share/opensearch-dashboards/config/certs/cert.crt
    opensearch.ssl.key: /usr/share/opensearch-dashboards/config/certs/key.crt
    opensearch.ssl.certificateAuthorities: ["/usr/share/opensearch-dashboards/config/certs/ca.crt"]
    opensearch.username: "${_OS_USERNAME}"
    opensearch.password: "${_OS_PASSWORD}"
    logging.appenders.default:
      type: console
      layout:
        type: json
    logging.root.level: warn
EOF

cat <<EOF | oc apply -f - 2>/dev/null 1>/dev/null
apiVersion: apps/v1
kind: Deployment
metadata:
  name: opensearch-dashboards
  namespace: ${_TNS}
  labels:
    app: opensearch-dashboards
    version: "2.19"
spec:
  replicas: 1
  selector:
    matchLabels:
      app: opensearch-dashboards
  template:
    metadata:
      labels:
        app: opensearch-dashboards
        version: "2.19"
    spec:
      serviceAccountName: opensearch-dashboards
      securityContext:
        runAsNonRoot: true
      containers:
        - name: opensearch-dashboards
          image: opensearchproject/opensearch-dashboards:2.19.0
          imagePullPolicy: IfNotPresent
          ports:
            - containerPort: 5601
              name: http
              protocol: TCP
          env:
            - name: OPENSEARCH_USERNAME
              valueFrom:
                secretKeyRef:
                  name: opensearch-dashboards-credentials
                  key: username
            - name: OPENSEARCH_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: opensearch-dashboards-credentials
                  key: password
            - name: DISABLE_SECURITY_DASHBOARDS_PLUGIN
              value: "true"
          volumeMounts:
            - name: config
              mountPath: /usr/share/opensearch-dashboards/config/opensearch_dashboards.yml
              subPath: opensearch_dashboards.yml
            - name: certs
              mountPath: /usr/share/opensearch-dashboards/config/certs
          resources:
            requests:
              cpu: "200m"
              memory: "512Mi"
            limits:
              cpu: "1000m"
              memory: "1Gi"
      volumes:
        - name: config
          configMap:
            name: opensearch-dashboards-config
        - name: certs
          secret:
            secretName: opensearch-dashboards-certs
EOF

cat <<EOF | oc apply -f - 2>/dev/null 1>/dev/null
apiVersion: v1
kind: Service
metadata:
  name: opensearch-dashboards
  namespace: ${_TNS}
  labels:
    app: opensearch-dashboards
spec:
  selector:
    app: opensearch-dashboards
  ports:
    - name: http
      port: 5601
      targetPort: 5601
      protocol: TCP
  type: ClusterIP
EOF

cat <<EOF | oc apply -f - 2>/dev/null 1>/dev/null
kind: Route
apiVersion: route.openshift.io/v1
metadata:
  name: opensearch-dashboard
  namespace: ${_TNS}
spec:
  to:
    kind: Service
    name: opensearch-dashboards
    weight: 100
  port:
    targetPort: 5601
  tls:
    termination: passthrough
    insecureEdgeTerminationPolicy: Redirect
  wildcardPolicy: None
EOF

}

installOpensearchDashboard
echo "Done"
./cp4ba-os-dashboard-infos.sh ${_TNS}
exit 0
