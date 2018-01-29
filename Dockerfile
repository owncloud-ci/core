FROM owncloudci/php:latest

LABEL maintainer="ownCloud DevOps <devops@owncloud.com>" \
  org.label-schema.name="ownCloud CI core" \
  org.label-schema.vendor="ownCloud GmbH" \
  org.label-schema.schema-version="1.0"


ADD /rootfs/plugin.sh /usr/sbin/plugin.sh
ENTRYPOINT ["/usr/sbin/plugin.sh"]