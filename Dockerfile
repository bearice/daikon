FROM docker.jimubox.com/iojs
MAINTAINER bearice@icybear.net

ENV ETCD_DNS_NAME _etcd._tcp.zhaowei.jimubox.com
WORKDIR /opt/daikon
CMD ["node","lib/main"]

ADD node_modules /opt/daikon/node_modules
ADD certs /opt/daikon/certs
ADD src /opt/daikon/src
ADD lib /opt/daikon/lib
