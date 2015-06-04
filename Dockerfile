FROM docker.jimubox.com/nodejs
MAINTAINER bearice@icybear.net

ENV ETCD_DNS_NAME _etcd._tcp.zhaowei.jimubox.com
WORKDIR /opt/daikon
CMD ["coffee","main.coffee"]
ADD etcd-client.crt etcd-client.key ca.crt node_modules /opt/daikon/
ADD *.js *.coffee /opt/daikon/
