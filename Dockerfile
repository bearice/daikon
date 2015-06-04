FROM docker.jimubox.com/nodejs
MAINTAINER bearice@icybear.net

ENV ETCD_DNS_NAME _etcd._tcp.zhaowei.jimubox.com
WORKDIR /opt/daikon
CMD ["coffee","main.coffee"]
ADD etcd-client.crt etcd-client.key ca.crt /opt/daikon/
ADD node_modules /opt/daikon/node_modules
ADD *.js *.coffee /opt/daikon/
