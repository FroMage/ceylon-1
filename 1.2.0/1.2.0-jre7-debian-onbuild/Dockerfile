#
# Base image for compiling and running Ceylon applications
#
FROM ceylon/ceylon:1.2.0-jre7-debian

USER 1000

VOLUME ${HOME}

ONBUILD ADD . ${HOME}

