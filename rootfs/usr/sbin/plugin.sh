#!/usr/bin/env bash
set -eo pipefail; [[ "${PLUGIN_DEBUG}" == "true" ]] && set -x

declare -x PLUGIN_VERSION
declare -x PLUGIN_GIT_REFERENCE
declare -x PLUGIN_DOWNLOAD_URL
declare -x CORE_DOWNLOAD_URL

if [[ -z "${PLUGIN_VERSION}" && -z "${PLUGIN_GIT_REFERENCE}" && -z "${PLUGIN_DOWNLOAD_URL}" && -z "${CORE_DOWNLOAD_URL}" ]]; then
  echo "Missing VERSION, GIT_REFERENCE, DOWNLOAD_URL or CORE_DOWNLOAD_URL";
  exit 1;
fi

# If no core path is set, we will assume that core should be put two folders above the
# dore workspace
#
# We assume that drones workspace is layout similar to:
#   core
#   └── apps
#       └── app_to_test
#
# workspace:
#    base: /core
#    path: apps/app_to_test

declare -x PLUGIN_CORE_PATH
[[ -z "${PLUGIN_CORE_PATH}" ]] && PLUGIN_CORE_PATH="$(dirname "$(dirname "${DRONE_WORKSPACE}")")"

declare -x PLUGIN_GIT_REPOSITORY
[[ -z "${PLUGIN_GIT_REPOSITORY}" ]] && PLUGIN_GIT_REPOSITORY="https://github.com/owncloud/core.git"

declare -x PLUGIN_DOWNLOAD_FILENAME
[[ -z "${PLUGIN_DOWNLOAD_FILENAME}" ]] && PLUGIN_DOWNLOAD_FILENAME="owncloud-${PLUGIN_VERSION}.tar.bz2"

# CORE_DOWNLOAD_URL should always override PLUGIN variable
[[ ! -z "${CORE_DOWNLOAD_URL}" ]] && PLUGIN_DOWNLOAD_URL="${CORE_DOWNLOAD_URL}"
[[ -z "${PLUGIN_DOWNLOAD_URL}" ]] && PLUGIN_DOWNLOAD_URL="https://download.owncloud.org/community/${PLUGIN_DOWNLOAD_FILENAME}"

declare -x PLUGIN_EXTRACT_PARAMS
[[ -z "${PLUGIN_EXTRACT_PARAMS}" ]] && PLUGIN_EXTRACT_PARAMS="xj"


# Installation related variables
declare -x PLUGIN_INSTALL
[[ -z "${PLUGIN_INSTALL}" ]] && PLUGIN_INSTALL="true"

declare -x PLUGIN_ADMIN_LOGIN
[[ -z "${PLUGIN_ADMIN_LOGIN}" ]] && PLUGIN_ADMIN_LOGIN="admin"

declare -x PLUGIN_ADMIN_PASSWORD
[[ -z "${PLUGIN_ADMIN_PASSWORD}" ]] && PLUGIN_ADMIN_PASSWORD="admin"

declare -x PLUGIN_DATA_DIRECTORY
[[ -z "${PLUGIN_DATA_DIRECTORY}" ]] && PLUGIN_DATA_DIRECTORY="${PLUGIN_CORE_PATH}/data"

declare -x PLUGIN_DB_TYPE
[[ -z "${PLUGIN_DB_TYPE}" ]] && PLUGIN_DB_TYPE="sqlite"

declare -x PLUGIN_DB_NAME
[[ -z "${PLUGIN_DB_NAME}" ]] && PLUGIN_DB_NAME="owncloud"

declare -x PLUGIN_DB_USERNAME
[[ -z "${PLUGIN_DB_USERNAME}" ]] && PLUGIN_DB_USERNAME="owncloud"

declare -x PLUGIN_DB_PASSWORD
[[ -z "${PLUGIN_DB_PASSWORD}" ]] && PLUGIN_DB_PASSWORD="owncloud"

declare -x PLUGIN_DB_HOST
[[ -z "${PLUGIN_DB_HOST}" ]] && PLUGIN_DB_HOST="localhost:3306"

declare -x PLUGIN_DB_PREFIX
[[ -z "${PLUGIN_DB_PREFIX}" ]] && PLUGIN_DB_PREFIX="oc_"


plugin_oc_from_tarball() {
  echo "\$ wget -qO- ${PLUGIN_DOWNLOAD_URL} | tar -${PLUGIN_EXTRACT_PARAMS} -C ${PLUGIN_CORE_PATH} --strip 1"
  wget -qO- "${PLUGIN_DOWNLOAD_URL}" | tar -"${PLUGIN_EXTRACT_PARAMS}" -C "${PLUGIN_CORE_PATH}" --strip 1
}

plugin_oc_from_git() {

  pushd "${PLUGIN_CORE_PATH}"
    echo "\$ git init"
    git init

    echo "\$ git remote add origin ${PLUGIN_GIT_REPOSITORY}"
    git remote add origin "${PLUGIN_GIT_REPOSITORY}"

    echo "\$ git fetch --depth 1 --no-tags origin ${PLUGIN_GIT_REFERENCE}"
    git fetch --depth 1 --no-tags origin "${PLUGIN_GIT_REFERENCE}"

    echo "\$ git checkout ${PLUGIN_GIT_REFERENCE}"
    git checkout "${PLUGIN_GIT_REFERENCE}"

    echo "\$ git submodule update --init"
    git submodule update --init
  popd
}


plugin_execute_build() {
  pushd "${PLUGIN_CORE_PATH}"
    echo "\$ make"
    make
  popd
}

plugin_check_database() {
  case "${PLUGIN_DB_TYPE}" in
    sqlite)
      ;;
    mysql|pgsql|oci)
      echo "wait-for-it ${PLUGIN_DB_HOST}"
      wait-for-it "${PLUGIN_DB_HOST}"
      ;;
    *)
      echo "\"${PLUGIN_DB_TYPE}\" is a unsupported database type !"
      exit 1
      ;;
  esac
}

plugin_install_owncloud() {
  echo "installing owncloud"
  plugin_check_database

  _occ_command="./occ maintenance:install -vvv \
        --database=${PLUGIN_DB_TYPE} \
        --database-name=${PLUGIN_DB_NAME} \
        --database-table-prefix=${PLUGIN_DB_PREFIX} \
        --admin-user=${PLUGIN_ADMIN_LOGIN} \
        --admin-pass=${PLUGIN_ADMIN_PASSWORD} \
        --data-dir=${PLUGIN_DATA_DIRECTORY} "

  if [[ "${PLUGIN_DB_TYPE}" != "sqlite" ]]; then
    _occ_command+="--database-host=${PLUGIN_DB_HOST} \
                   --database-user=${PLUGIN_DB_USERNAME} \
                   --database-pass=${PLUGIN_DB_PASSWORD}"
  fi


  pushd "${PLUGIN_CORE_PATH}"
    echo "\$ php ${_occ_command}"
    php ${_occ_command}
  popd

}

plugin_main() {

  if [[ ! -d "${PLUGIN_CORE_PATH}" ]]; then
    mkdir -p "${PLUGIN_CORE_PATH}"
  fi

  if [[ ! -z "${PLUGIN_GIT_REFERENCE}" ]]; then
    plugin_oc_from_git
    plugin_execute_build
  else
    plugin_oc_from_tarball
  fi

  if [[ "${PLUGIN_INSTALL}" == "true" ]]; then
    plugin_install_owncloud
  else
    echo "skipping installation"
  fi

}

plugin_main