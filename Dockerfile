FROM openshift/origin-base

RUN yum install -y nginx && echo "Hello World" > /usr/share/nginx/html/index.html

EXPOSE 80
EXPOSE 443

ADD conf/ /etc/nginx/
ADD certs/example_chain.pem /etc/nginx/
ADD certs/example.key /etc/nginx/

CMD ["/usr/sbin/nginx"]
