#!/bin/bash

_TNS=$1

if [[ -z "${_TNS}" ]]; then
  echo "set namespace" 
  exit 1
fi

removeOpensearchDashboard () {
  echo "Remove Opensearch dashboard from namespace ${_TNS}"
  
  oc delete serviceaccount opensearch-dashboards -n ${_TNS} 2>/dev/null 1>/dev/null
  oc delete configmap opensearch-dashboards-config -n ${_TNS} 2>/dev/null 1>/dev/null
  oc delete secret opensearch-dashboards-credentials -n ${_TNS} 2>/dev/null 1>/dev/null
  oc delete secret opensearch-dashboards-certs -n ${_TNS} 2>/dev/null 1>/dev/null
  oc delete deployment opensearch-dashboards -n ${_TNS} 2>/dev/null 1>/dev/null
  oc delete service opensearch-dashboards -n ${_TNS} 2>/dev/null 1>/dev/null
  oc delete route opensearch-dashboard -n ${_TNS} 2>/dev/null 1>/dev/null
}

removeOpensearchDashboard
echo "Done"
exit 0
