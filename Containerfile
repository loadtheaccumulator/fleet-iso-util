############################
# STEP 1 build executable binary
############################
#FROM registry.redhat.io/rhel8/go-toolset:1.15 AS builder
FROM registry.redhat.io/ubi8

COPY fleetkick.sh .
#COPY kickstart-stage.ks .

# Fetch dependencies.
USER root
RUN dnf install -y pykickstart mtools xorriso genisoimage syslinux isomd5sum file ostree
ENV MTOOLS_SKIP_CHECK=1

USER 1001

#CMD ["edge-api"]
