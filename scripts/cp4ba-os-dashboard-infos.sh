#!/bin/bash

echo "Opensearch dashboard infos"

infoOpensearchDashboard () {

  _OS_SECRET_NAME=$(oc get cluster opensearch -n ${_TNS} -o jsonpath={.spec.plugins.security.internalUserSecret} 2>/dev/null)
  _OS_USERNAME=$(oc get secret ${_OS_SECRET_NAME} -n ${_TNS} -o json | jq -r '.data | keys[0]' 2>/dev/null)
  _OS_PASSWORD=$(oc get secret ${_OS_SECRET_NAME} -n ${_TNS} -o jsonpath='{.data.'${_OS_USERNAME}'}' | base64 -d 2>/dev/null)
  _OS_SERVICE="opensearch.${_TNS}.svc.cluster.local"
  _OS_DASHBOARD_URL="https://$(oc get route opensearch-dashboard -n $_TNS -o jsonpath='{.spec.host}' 2>/dev/null)"

  echo "Dashboard ${_OS_DASHBOARD_URL}"
  echo "Credentials ${_OS_USERNAME} / ${_OS_PASSWORD}"

}

_TNS=$1

if [[ -z "${_TNS}" ]]; then
  echo "set namespace" 
  exit 1
fi
infoOpensearchDashboard
echo "Done"
exit 0
