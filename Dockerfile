# syntax=docker/dockerfile:1-labs
FROM centos:7
MAINTAINER cbpeckles
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
VOLUME [ "/sys/fs/cgroup" ]

# get stuff from the interwebs
RUN yum -y install wget tar; yum clean all

RUN echo "SystemCTL: "; ls -l `which systemctl`;
ADD scripts/systemctl /bin/systemctl
RUN chmod 755 /bin/systemctl
RUN echo "JournalCTL: "; ls -l `which journalctl`;
ADD scripts/journalctl /bin/journalctl
RUN chmod 755 /bin/journalctl

RUN mkdir /tmp/nagiosxi \
    && wget -qO- https://assets.nagios.com/downloads/nagiosxi/5/xi-5.9.3.tar.gz \
    | tar xz -C /tmp
WORKDIR /tmp/nagiosxi

# overwrite custom config file
ADD config.cfg xi-sys.cfg

# start building
RUN ./init.sh \
    && . ./xi-sys.cfg \
	&& umask 0022 \
	&& . ./functions.sh \
	&& log="install.log"
RUN export INTERACTIVE="False" \
    && export INSTALL_PATH=`pwd`
RUN . ./functions.sh \
    && run_sub ./0-repos noupdate
RUN . ./functions.sh \
    && run_sub ./1-prereqs
RUN . ./functions.sh \
    && run_sub ./2-usersgroups
RUN --security=insecure . ./functions.sh \
    && run_sub ./3-dbservers
RUN --security=insecure . ./functions.sh \
    && run_sub ./4-services
RUN --security=insecure . ./functions.sh \
    && run_sub ./5-sudoers
RUN sed -i.bak s/selinux/sudoers/g 9-dbbackups
RUN --security=insecure . ./functions.sh \
    && run_sub ./9-dbbackups
RUN . ./functions.sh \
    && run_sub ./11-sourceguardian
RUN . ./functions.sh \
    && run_sub ./13-phpini

ADD scripts/NDOUTILS-POST subcomponents/ndoutils/post-install
ADD scripts/install subcomponents/ndoutils/install
RUN chmod 755 subcomponents/ndoutils/post-install \
    && chmod 755 subcomponents/ndoutils/install \
	&& . ./functions.sh \
	&& run_sub ./A-subcomponents \
	&& run_sub ./A0-mrtg

RUN --security=insecure service mysqld start \
    && . ./functions.sh \
	&& run_sub ./B-installxi
RUN . ./functions.sh \
    && run_sub ./C-cronjobs
RUN . ./functions.sh \
    && run_sub ./D-chkconfigalldaemons
RUN --security=insecure service mysqld start \
    && . ./functions.sh \
	&& run_sub ./E-importnagiosql
RUN --security=insecure . ./functions.sh \
    && run_sub ./F-startdaemons
RUN . ./functions.sh \
    && run_sub ./Z-webroot

RUN yum clean all

# set startup script
ADD start.sh /start.sh
RUN chmod 755 /start.sh
EXPOSE 80 5666 5667

CMD ["/start.sh"]
