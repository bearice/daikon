FROM docker.jimubox.com/iojs
MAINTAINER bearice@icybear.net

ENV ETCD_DNS_NAME _etcd._tcp.zhaowei.jimubox.com
WORKDIR /opt/daikon
CMD ["node","lib/main"]
ADD etcd-client.crt etcd-client.key ca.crt /opt/daikon/certs
ADD node_modules /opt/daikon/node_modules
ADD lib src /opt/daikon/
