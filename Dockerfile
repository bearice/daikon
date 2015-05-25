FROM docker.jimubox.com/nodejs
MAINTAINER bearice@icybear.net

ADD . /opt/diakon
WORKDIR /opt/daikon

CMD ["node","main"]
