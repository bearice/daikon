FROM docker.jimubox.com/iojs
MAINTAINER bearice@icybear.net

ENV ETCD_DNS_NAME _etcd._tcp.zhaowei.jimubox.com
WORKDIR /opt/daikon
CMD ["node","lib/main"]

ADD node_modules certs /opt/daikon/
ADD lib src /opt/daikon/
