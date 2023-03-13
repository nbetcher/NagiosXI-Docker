# syntax=docker/dockerfile:1-labs
FROM centos:7
MAINTAINER nbetcher
ENV container docker

RUN (cd /lib/systemd/system/sysinit.target.wants/; for i in *; do [ $i == \
    systemd-tmpfiles-setup.service ] || rm -f $i; done); \
    rm -f /lib/systemd/system/multi-user.target.wants/*; \
    rm -f /etc/systemd/system/*.wants/*; \
    rm -f /lib/systemd/system/local-fs.target.wants/*; \
    rm -f /lib/systemd/system/sockets.target.wants/*udev*; \
    rm -f /lib/systemd/system/sockets.target.wants/*initctl*; \
    rm -f /lib/systemd/system/basic.target.wants/*; \
    rm -f /lib/systemd/system/anaconda.target.wants/*;

# get stuff from the interwebs
RUN yum -y install wget python3 which patch; yum clean all

RUN mkdir /tmp/nagiosxi \
    && wget -qO- https://assets.nagios.com/downloads/nagiosxi/5/xi-5.9.3.tar.gz \
    | tar xz -C /tmp

# Patch nrpe install to specify system init type as SystemD

ADD scripts/nrpe-install-systemd.patch /tmp/nagiosxi/subcomponents/nrpe/nrpe-install-systemd.patch
WORKDIR /tmp/nagiosxi/subcomponents/nrpe
RUN patch < nrpe-install-systemd.patch
RUN install; exit 1

WORKDIR /tmp/nagiosxi

RUN ls -l /tmp/nagiosxi/

# overwrite custom config file
ADD config.cfg xi-sys.cfg

# start building
RUN pwd && ls -l /tmp/nagiosxi/ && ./init.sh \
    && . ./xi-sys.cfg \
	&& umask 0022 \
	&& . ./functions.sh \
	&& log="install.log"
RUN export INTERACTIVE="False" \
    && export INSTALL_PATH=`pwd`;
RUN . ./functions.sh \
    && run_sub ./0-repos noupdate
RUN . ./functions.sh \
    && run_sub ./1-prereqs
    
    
# Replace systemd stuff with Docker-friendly 'fake' python3 derivitive from:
#   https://github.com/gdraheim/docker-systemctl-replacement
RUN echo "Replacing systemctl with slimmed-down Docker-friendly derivitive."
ADD scripts/systemctl /usr/bin/systemctl
RUN chmod 755 /usr/bin/systemctl
RUN echo "Replacing journalctl with slimmed-down Docker-friendly derivitive."
ADD scripts/journalctl /usr/bin/journalctl
RUN chmod 755 /usr/bin/journalctl


RUN . ./functions.sh \
    && run_sub ./2-usersgroups
RUN . ./functions.sh \
    && run_sub ./3-dbservers
RUN . ./functions.sh \
    && run_sub ./4-services
RUN . ./functions.sh \
    && run_sub ./5-sudoers
RUN sed -i.bak s/selinux/sudoers/g 9-dbbackups
RUN . ./functions.sh \
    && run_sub ./9-dbbackups
RUN . ./functions.sh \
    && run_sub ./11-sourceguardian
RUN . ./functions.sh \
    && run_sub ./13-phpini

ADD scripts/NDOUTILS-POST subcomponents/ndoutils/post-install
ADD scripts/install subcomponents/ndoutils/install

# Install fake ps so system is identified as system
#
# Backup existing 'ps' first for later.
# RUN mv /bin/ps /bin/ps.orig

# Install fake ps:
# ADD scripts/ps /bin/ps
# RUN chmod 755 /bin/ps

RUN service start mariadb.service \
    && chmod 755 subcomponents/ndoutils/post-install \
    && chmod 755 subcomponents/ndoutils/install \
    && . ./functions.sh \
    && run_sub ./A-subcomponents \
    && run_sub ./A0-mrtg
	
# Restore existing ps:
# RUN mv /bin/ps.orig /bin/ps

RUN service start mariadb.service \
    && . ./functions.sh \
	&& run_sub ./B-installxi
RUN . ./functions.sh \
    && run_sub ./C-cronjobs
RUN . ./functions.sh \
    && run_sub ./D-chkconfigalldaemons
RUN service start mariadb.service \
    && . ./functions.sh \
	&& run_sub ./E-importnagiosql
RUN . ./functions.sh \
    && run_sub ./F-startdaemons
RUN . ./functions.sh \
    && run_sub ./Z-webroot

RUN yum clean all

# set startup script
ADD start.sh /start.sh
RUN chmod 755 /start.sh
EXPOSE 80 5666 5667

CMD ["/start.sh"]
