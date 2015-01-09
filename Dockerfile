FROM openshift/origin-base

RUN yum install -y nginx

EXPOSE 80
EXPOSE 443

ADD conf/ /etc/nginx/

CMD ["/usr/sbin/nginx"]
