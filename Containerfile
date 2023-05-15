# RHEL container version
FROM registry.access.redhat.com/ubi8/ubi

COPY fleetkick.sh /usr/local/bin/
#COPY kickstart-stage.ks .

# Fetch dependencies.
USER root
RUN dnf install -y pykickstart mtools xorriso genisoimage syslinux isomd5sum file ostree
ENV MTOOLS_SKIP_CHECK=1

USER 1001

CMD ["/usr/local/bin/fleetkick.sh"]
