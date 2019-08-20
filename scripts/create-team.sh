#!/usr/bin/env bash

set -o errexit

: ${1?"Usage: $0 <TEAM NAME>"}

TEAM_NAME=$1
TEMPLATE="team1"
REPO_ROOT=$(git rev-parse --show-toplevel)
TEAM_DIR="${REPO_ROOT}/cluster/${TEAM_NAME}/"

mkdir -p ${TEAM_DIR}

cp -r "${REPO_ROOT}/cluster/${TEMPLATE}/." ${TEAM_DIR}

for f in "${TEAM_DIR}*.yaml"
do
 # This sed command seems to work with OSX 10.9+ and GNU Linux
 sed -i'' -e "s/$TEMPLATE/$TEAM_NAME/g" ${f}
done

echo "${TEAM_NAME} created at ${TEAM_DIR}"
echo -e "\n  - ./${TEAM_NAME}/" >> "${REPO_ROOT}/cluster/kustomization.yaml"
echo "${TEAM_NAME} added to ${REPO_ROOT}/cluster/kustomization.yaml"
