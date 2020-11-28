# core

[![Build Status](https://drone.owncloud.com/api/badges/owncloud-ci/core/status.svg)](https://drone.owncloud.com/owncloud-ci/core)

ownCloud Core for CI pipelines. The plugin will fetch ownCloud core either from a prebuilt tarball or from a branch/tag from GitHub and aims to ease the setup process for testing owncloud applications.

## Plugin Variables

The plugin requires either `VERSION`, `GIT_REFERENCE` or `DOWNLOAD_URL` to be defined. All other variables are optional

- `VERSION`
  The owncloud tarball version to fetch from https://download.owncloud.org/community/ or the daily or testing sub-directory

- `GIT_REFERENCE`
  The branch to fetch from https://github.com/owncloud/core

- `DOWNLOAD_URL`
  Provide a tarball from a different location

- `EXCLUDE`
  Exclude files/folders from being copied to the workspace. This is useful when testing apps that are included in the nightly tarballs. The exclude pattern uses rsync `--exclude` logic

If `CORE_PATH` is not defined - the plugin assumes the workspace directory is nested two directories deeper in relation to the owncloud folder

With the following definition of the workspace in the `drone.yml`

```yaml
workspace:
  base: /owncloud
  path: apps/app_to_test
```

The directory layout would be like this:

```console
owncloud              ( PATH )
  └── apps
     └── app_to_test  ( workspace )
```

### Full list of variables

```console
VERSION
GIT_REFERENCE
DOWNLOAD_URL
CORE_DOWNLOAD_URL
EXTRACT_PARAMS     (xj)
DOWNLOAD_FILENAME  (owncloud-${PLUGIN_VERSION}.tar.bz2)
DOWNLOAD_URL       (https://download.owncloud.org/community/${PLUGIN_DOWNLOAD_FILENAME})
GIT_REPOSITORY     (https://github.com/owncloud/core.git)
INSTALL            (true)
ADMIN_LOGIN        (admin)
ADMIN_PASSWORD     (admin)
DATA_DIRECTORY     ($PATH/data)
DB_TYPE            (sqlite)
DB_NAME            (owncloud)
DB_USERNAME        (owncloud)
DB_PASSWORD        (owncloud)
DB_HOST            (localhost:3306)
DB_PREFIX          (oc_)
DB_TIMEOUT         (600)
EXCLUDE
```

## Examples

**Basic Example**

Download `owncloud-daily-master-qa.tar.bz2` and put contents into `/var/www/owncloud`, install owncloud with sqlite

```yaml
workspace:
  base: /var/www/owncloud
  path: apps/my_app

pipeline:
  install-server:
    image: owncloudci/core
    pull: true
    version: daily-master-qa
```

**Git core branch and mysql as database**

Fetch stable10 branch into `/drone`, install owncloud with mysql

```yaml
workspace:
  base: /drone
  path: apps/my_app

pipeline:
  install-server:
    image: owncloudci/core
    pull: true
    git_reference: stable10
    db_type: mysql
    db_name: oc_db
    db_host: service_name:3306
    db_username: admin
    db_password: secret

services:
  service_name:
    image: mysql:5.5
    environment:
      - MYSQL_USER=admin
      - MYSQL_PASSWORD=secret
      - MYSQL_DATABASE=oc_db
      - MYSQL_ROOT_PASSWORD=secret
```

**Exclude folders/files from core**

```yaml
workspace:
  base: /var/www/owncloud
  path: apps/my_app

pipeline:
  install-server:
    image: owncloudci/core
    pull: true
    exclude:
      - apps/notifications
    version: daily-master-qa
```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
