ARG PHP_VERSION=7.1

FROM owncloudci/php:${PHP_VERSION}

LABEL maintainer="ownCloud DevOps <devops@owncloud.com>" \
  org.label-schema.name="ownCloud CI core" \
  org.label-schema.vendor="ownCloud GmbH" \
  org.label-schema.schema-version="1.0"


ADD rootfs /
ENTRYPOINT ["/usr/sbin/plugin.sh"]