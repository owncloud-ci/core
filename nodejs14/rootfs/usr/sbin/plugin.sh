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

declare -x PLUGIN_TESTING_APP_GIT
[[ -z "${PLUGIN_TESTING_APP_GIT}" ]] && PLUGIN_TESTING_APP_GIT="https://github.com/owncloud/testing.git"

declare -x PLUGIN_EXTRACT_PARAMS
[[ -z "${PLUGIN_EXTRACT_PARAMS}" ]] && PLUGIN_EXTRACT_PARAMS="xj"

declare -x PLUGIN_EXCLUDE
[[ -z "${PLUGIN_EXCLUDE}" ]] && PLUGIN_EXCLUDE=""

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

declare -x PLUGIN_DB_TIMEOUT
[[ -z "${PLUGIN_DB_TIMEOUT}" ]] && PLUGIN_DB_TIMEOUT="600"


readonly PLUGIN_TMP_DIR="/tmp/owncloud/"

#
plugin_validate_url() {
  if [[ `wget -S --spider $1  2>&1 | grep 'HTTP/1.1 200 OK'` ]]; then
    return 0
  else
    return 1
  fi
}

plugin_oc_from_tarball() {
  local dest_dir=${1}
  if  [[ -z "${PLUGIN_DOWNLOAD_URL}" ]]; then
    PLUGIN_DOWNLOAD_URL="https://download.owncloud.com/server/daily/${PLUGIN_DOWNLOAD_FILENAME}"
    if ! plugin_validate_url ${PLUGIN_DOWNLOAD_URL} ; then
      PLUGIN_DOWNLOAD_URL="https://download.owncloud.com/server/testing/${PLUGIN_DOWNLOAD_FILENAME}"
      if ! plugin_validate_url ${PLUGIN_DOWNLOAD_URL} ; then
        PLUGIN_DOWNLOAD_URL="https://download.owncloud.com/server/stable/${PLUGIN_DOWNLOAD_FILENAME}"
      fi
    fi
  fi
  echo "\$ wget -qO- ${PLUGIN_DOWNLOAD_URL} | tar -${PLUGIN_EXTRACT_PARAMS} -C ${dest_dir} --strip 1"
  wget -qO- "${PLUGIN_DOWNLOAD_URL}" | tar -"${PLUGIN_EXTRACT_PARAMS}" -C "${dest_dir}" --strip 1
  build_sha=$(grep OC_Build "${dest_dir}/version.php" | cut -d "'" -f2 | cut -d " " -f2)
  build_date=$(grep OC_Build "${dest_dir}/version.php" | cut -d "'" -f2 | cut -d " " -f1)
  build_version=$(grep OC_VersionString "${dest_dir}/version.php" | cut -d "'" -f2)
  build_channel=$(grep OC_Channel "${dest_dir}/version.php" | cut -d "'" -f2)
  echo "Fetched ${build_version} - channel: ${build_channel} - build at ${build_date} - SHA: ${build_sha}"
}

plugin_oc_from_git() {
  local dest_dir=${1}
  pushd "${dest_dir}"
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

    echo "\$ git log --format=oneline -n 1"
    git log --format=oneline -n 1
  popd
}

plugin_oc_move() {
  local excluded=""
  local verbose=""
  local src_path=${1}
  local dest_path=${2}
  if [[ "${PLUGIN_DEBUG}" == "true" ]]; then
    verbose="-v"
  fi
  for excluded_pattern in $(echo ${PLUGIN_EXCLUDE} | tr "," " "); do
    excluded="${excluded} --exclude ${excluded_pattern}"
  done
  cmd="rsync -aIX ${verbose} ${excluded} ${src_path} ${dest_path}"
  echo "${cmd}"
  ${cmd}
}


plugin_execute_build() {
  local core_path=${1}
  pushd "${core_path}"
    echo "\$ make"
    make
  popd
}

plugin_wait_for_database() {
    local host_name="${1}"
    local default_port="${2}"
    if ! grep -q ":" <<< "${host_name}"
    then
        host_name="${host_name}:${default_port}"
    fi
    echo "$ wait-for-it -t ${PLUGIN_DB_TIMEOUT} ${host_name}"
    wait-for-it -t "${PLUGIN_DB_TIMEOUT}" "${host_name}"
}

plugin_wait_for_oracle() {
    local sqlplus=/usr/lib/oracle/12.2/client64/bin/sqlplus
    local result
    local host_name="${PLUGIN_DB_HOST}"
    if ! grep -q ":" <<< "${host_name}"
    then
        host_name="${host_name}:1521"
    fi


    echo "wait-for-oracle: waiting ${PLUGIN_DB_TIMEOUT} seconds for ${host_name}"
    for i in $(seq "${PLUGIN_DB_TIMEOUT}"); do
        # disabled to not abort testing the connection
        set +eo pipefail

        echo "QUIT" | $sqlplus -L "${PLUGIN_DB_USERNAME}/${PLUGIN_DB_PASSWORD}@${host_name}/${PLUGIN_DB_NAME}" | grep "Connected to:" > /dev/null 2>&1
        result=$?

        # reenable pipefail
        set -eo pipefail

        if [ ${result} -eq 0 ] ; then
            echo "wait-for-oracle: ${host_name} available after ${i} seconds"
            break
        fi
        sleep 1
    done
    if [ ! ${result} -eq 0 ] ; then
        echo "wait-for-oracle: timeout - ${host_name} still not available after ${PLUGIN_DB_TIMEOUT} seconds"
        exit 1
    fi

}

plugin_check_database() {
  local db_type="${1}"
  local host_to_wait="${2}"
  case "${db_type}" in
    sqlite)
      ;;
    mysql)
        plugin_wait_for_database "$host_to_wait" 3306
      ;;
    pgsql)
        plugin_wait_for_database "$host_to_wait" 5432
      ;;
    oci)
        plugin_wait_for_oracle
      ;;
    *)
      echo "\"${db_type}\" is a unsupported database type !"
      exit 1
      ;;
  esac


}

plugin_install_owncloud() {
  echo "installing owncloud"
  plugin_check_database "${PLUGIN_DB_TYPE}" "${PLUGIN_DB_HOST}"

  _occ_command="./occ maintenance:install -vvv \
        --database=${PLUGIN_DB_TYPE} \
        --database-name=${PLUGIN_DB_NAME} \
        --database-table-prefix=${PLUGIN_DB_PREFIX} \
        --admin-user=${PLUGIN_ADMIN_LOGIN} \
        --admin-pass=${PLUGIN_ADMIN_PASSWORD} \
        --data-dir=${PLUGIN_DATA_DIRECTORY} "

  if [[ "${PLUGIN_DB_TYPE}" != "sqlite" ]]; then
    if [[ "${PLUGIN_DB_TYPE}" != "oci" ]]; then
      _occ_command+="--database-host=${PLUGIN_DB_HOST} \
                     --database-user=${PLUGIN_DB_USERNAME} \
                     --database-pass=${PLUGIN_DB_PASSWORD}"
    else
      _occ_command+=" --database-connection-string=(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=${PLUGIN_DB_HOST})(PORT=1521))(CONNECT_DATA=(SERVICE_NAME=XE))) \
                     --database-user=${PLUGIN_DB_USERNAME} \
                     --database-pass=${PLUGIN_DB_PASSWORD}"
    fi
  fi


  pushd "${PLUGIN_CORE_PATH}"
    echo "\$ php ${_occ_command}"
    php ${_occ_command}
  popd

}

plugin_install_testing_app() {
  local core_path=${1}
  pushd "${core_path}/apps"
  if [[ ! -d "testing" ]]; then
    echo "installing testing app"
    git clone "${PLUGIN_TESTING_APP_GIT}"
  else
    echo "testing app already available"
  fi
  popd
}

plugin_main() {

  if [[ ! -d "${PLUGIN_TMP_DIR}" ]]; then
    mkdir -p "${PLUGIN_TMP_DIR}"
  fi

  if [[ ! -d "${PLUGIN_CORE_PATH}" ]]; then
    mkdir -p "${PLUGIN_CORE_PATH}"
  fi

  if [[ ! -z "${PLUGIN_GIT_REFERENCE}" ]]; then
    plugin_oc_from_git "${PLUGIN_TMP_DIR}"
    plugin_oc_move "${PLUGIN_TMP_DIR}" "${PLUGIN_CORE_PATH}"
    plugin_execute_build "${PLUGIN_CORE_PATH}"
    plugin_install_testing_app "${PLUGIN_CORE_PATH}"
  else
    plugin_oc_from_tarball "${PLUGIN_TMP_DIR}"
    plugin_oc_move "${PLUGIN_TMP_DIR}" "${PLUGIN_CORE_PATH}"
    plugin_install_testing_app "${PLUGIN_CORE_PATH}"
  fi



  if [[ "${PLUGIN_INSTALL}" == "true" ]]; then
    plugin_install_owncloud
  else
    echo "skipping installation"
  fi

}

plugin_main
