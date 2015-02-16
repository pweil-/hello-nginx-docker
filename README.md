# hello-nginx-docker
This repository provides some helper applications and configurations for testing TLS termination in the OpenShift
enviroment.  It is meant for testing purposes only, the certificates contained within this project are not valid.

It is important to note that routing for beta 1 relies on SNI for custom certificate delivery.  In future iterations
it is planned to be able to offer custom frontend implementations which will allow applications to serve non-sni
traffic with custom certificates.

## Building the docker image
    docker build -t pweil/hello-nginx-docker .

## Verifying the docker image
    docker run pweil/hello-nginx-docker
    docker ps
    docker inspect <container id> | grep IP
    # at this point you need to put a hosts entry in /etc/hosts for the docker container that is being run
    # or you will receive an error from curl that the requested domain does not match the certificate
    curl https://www.example.com:443 --cacert certs/mypersonalca/certs/ca.pem

    Hello World

    # you may also view the certificate being served with openssl
    openssl s_client -connect 172.17.0.13:443 | grep example
    ... lines removed for clarity ...
    subject=/CN=www.example.com/ST=SC/C=US/emailAddress=example@example.com/O=Example/OU=Example
    issuer=/C=US/ST=SC/L=Default City/O=Default Company Ltd/OU=Test CA/CN=www.exampleca.com/emailAddress=example@example.com

## Testing with OpenShift V3 routing beta1

### UC 1: non ssl enabled application

    # clone openshift and start the vagrant environment
    [pweil@localhost origin]$ vagrant up
    ...
    # enter the vagrant machine
    [pweil@localhost origin]$ vagrant ssh
    Last login: Thu Oct 30 18:18:12 2014 from 10.0.2.2
    [vagrant@openshiftdev ~]$ cd /data/src/github.com/openshift/origin/

    # build the base images (not necessary if they have been pushed to the openshift repository, as of writing they
    # had not been pushed. This step may take a while to download images.
    [vagrant@openshiftdev origin]$ hack/build-base-images.sh

    # build the openshift release and build the openshift images
    [vagrant@openshiftdev origin]$ hack/build-release.sh && hack/build-images.sh

    # add the build path and start openshift.  You can start this in the background or open another window and
    # add the path to your new session as well
    [vagrant@openshiftdev origin]$ export PATH=${ORIGIN_BASE}/_output/local/bin/linux/amd64:$PATH
    [vagrant@openshiftdev origin]$ sudo /data/src/github.com/openshift/origin/_output/local/bin/linux/amd64/openshift start --loglevel=4

    # If running in https mode, ensure openshift cli can authenticate
    [vagrant@openshiftdev origin]$ sudo chmod a+r openshift.local.certificates/admin/*
    [vagrant@openshiftdev origin]$ export KUBECONFIG=/data/src/github.com/openshift/origin/openshift.local.certificates/admin/.kubeconfig
    [vagrant@openshiftdev origin]$ export OPENSHIFT_CA_DATA=$(</data/src/github.com/openshift/origin/openshift.local.certificates/master/root.crt)


    # deploy the router, non-secure pod, service, and route.  If running in non-https mode please adjust the url accordingly
    [vagrant@openshiftdev origin]$ hack/install-router.sh router https://10.0.2.15:8443
    Creating router file and starting pod...
    router
    [vagrant@openshiftdev origin]$ openshift cli get pods
    POD                 CONTAINER(S)                   IMAGE(S)                          HOST                  LABELS              STATUS
    router              origin-haproxy-router-router   openshift/origin-haproxy-router   openshiftdev.local/   <none>              Running

    [vagrant@openshiftdev ~]$ cd
    [vagrant@openshiftdev ~]$ git clone https://github.com/pweil-/hello-nginx-docker.git
    # starting the pod may take a while, it must download the container
    [vagrant@openshiftdev ~]$ openshift cli create -f hello-nginx-docker/openshift/nginx_pod.json pods
    hello-nginx-docker
    [vagrant@openshiftdev ~]$ openshift cli get pods
    POD                  CONTAINER(S)                   IMAGE(S)                          HOST                  LABELS                    STATUS
    router               origin-haproxy-router-router   openshift/origin-haproxy-router   openshiftdev.local/   <none>                    Running
    hello-nginx-docker   hello-nginx-docker-pod         pweil/hello-nginx-docker          openshiftdev.local/   name=hello-nginx-docker   Running

    [vagrant@openshiftdev ~]$ openshift cli create -f hello-nginx-docker/openshift/unsecure/service.json
    hello-nginx
    [vagrant@openshiftdev ~]$ openshift cli create -f hello-nginx-docker/openshift/unsecure/route.json
    route-unsecure
    [vagrant@openshiftdev ~]$ curl -H Host:www.example.com 10.0.2.15
    Hello World

    # the below steps are for in depth testing/demonstration purposes only and aren't necessarily required
    # to satisy the qa environment

    # find the docker container running the router and enter it
    [vagrant@openshiftdev ~]$ docker ps
    [vagrant@openshiftdev ~]$ docker inspect 71ef | grep Pid
        "Pid": 5686,
    [vagrant@openshiftdev ~]$ sudo nsenter -m -u -n -i -p -t 5686
    [root@router /]# cd /var/lib/containers/router/

    # view the created router state
    [root@router router]# cat routes.json
    {
      "hello-nginx": {
        "Name": "hello-nginx",
        "EndpointTable": {
          "172.17.0.14:80": {
            "ID": "172.17.0.14:80",
            "IP": "172.17.0.14",
            "Port": "80"
          }
        },
        "ServiceAliasConfigs": {
          "www.example.com-": {
            "Host": "www.example.com",
            "Path": "",
            "TLSTermination": "",
            "Certificates": null
          }
        }
      },

     .... removed for clarity ...

    [root@router conf]# cd /var/lib/haproxy/conf

    # view the created http backend
    [root@router conf]# cat haproxy.config
    .... removed for clarity ....
    backend be_http_hello-nginx
      mode http
      balance leastconn
      timeout check 5000ms
      server hello-nginx 172.17.0.14:80 check inter 5000ms

    [root@router conf]# exit


### UC 2: Edge terminated route with custom cert
This use case assumes that you are starting from the ending point of UC 1 and will demonstrate using both an
unsecure and secure route together.

    [vagrant@openshiftdev ~]$ openshift cli create -f hello-nginx-docker/openshift/edge/route.json
    route-edge

    # verify the certificate is being served correctly by the router
    [vagrant@openshiftdev ~]$ openssl s_client -servername www.example.com -connect 10.0.2.15:443 | grep 'subject\|issuer'
    depth=1 C = US, ST = SC, L = Default City, O = Default Company Ltd, OU = Test CA, CN = www.exampleca.com, emailAddress = example@example.com
    verify error:num=19:self signed certificate in certificate chain
    verify return:0
    subject=/CN=www.example.com/ST=SC/C=US/emailAddress=example@example.com/O=Example/OU=Example
    issuer=/C=US/ST=SC/L=Default City/O=Default Company Ltd/OU=Test CA/CN=www.exampleca.com/emailAddress=example@example.com
    ^C

    # verify hello world
    [vagrant@openshiftdev ~]$ curl --resolve www.example.com:443:10.0.2.15 https://www.example.com --cacert hello-nginx-docker/certs/mypersonalca/certs/ca.pem
    Hello World


### UC 3: Passthrough termination
This use case assumes that you are starting with an empty OpenShift environment and demonstrates a secure, pod terminated route.  Prior to running
this use case it is assumed you have built and started OpenShift.

    # install the router
    [vagrant@openshiftdev origin]$ hack/install-router.sh router https://10.0.2.15:8443
    Creating router file and starting pod...
    router

    [vagrant@openshiftdev origin]$ openshift cli get pods
    POD                 CONTAINER(S)                   IMAGE(S)                          HOST                  LABELS              STATUS
    router              origin-haproxy-router-router   openshift/origin-haproxy-router   openshiftdev.local/   <none>              Running

    # install the pod
    [vagrant@openshiftdev origin]$ cd
    [vagrant@openshiftdev ~]$ openshift cli create -f hello-nginx-docker/openshift/nginx_pod.json
    hello-nginx-docker

    [vagrant@openshiftdev ~]$ openshift cli get pods
    POD                  CONTAINER(S)                   IMAGE(S)                          HOST                  LABELS                    STATUS
    router               origin-haproxy-router-router   openshift/origin-haproxy-router   openshiftdev.local/   <none>                    Running
    hello-nginx-docker   hello-nginx-docker-pod         pweil/hello-nginx-docker          openshiftdev.local/   name=hello-nginx-docker   Running

    # install the service and route
    [vagrant@openshiftdev ~]$ openshift cli create -f hello-nginx-docker/openshift/passthrough/service.json
    hello-nginx-secure
    [vagrant@openshiftdev ~]$ openshift cli create -f hello-nginx-docker/openshift/passthrough/route.json
    route-secure

    # validate the certificate being served
    [vagrant@openshiftdev ~]$ openssl s_client -servername www.example.com -connect 10.0.2.15:443 | grep 'subject\|issuer'
    depth=1 C = US, ST = SC, L = Default City, O = Default Company Ltd, OU = Test CA, CN = www.exampleca.com, emailAddress = example@example.com
    verify error:num=19:self signed certificate in certificate chain
    verify return:0
    subject=/CN=www.example.com/ST=SC/C=US/emailAddress=example@example.com/O=Example/OU=Example
    issuer=/C=US/ST=SC/L=Default City/O=Default Company Ltd/OU=Test CA/CN=www.exampleca.com/emailAddress=example@example.com
    ^C

    # validate the response
    [vagrant@openshiftdev ~]$ curl --resolve www.example.com:443:10.0.2.15 https://www.example.com --cacert hello-nginx-docker/certs/mypersonalca/certs/ca.pem
    Hello World

    # in depth review
    [vagrant@openshiftdev ~]$ sudo nsenter -m -u -n -i -p -t <pid of your router container>
    [root@router /]# cd /var/lib/haproxy/conf

    # map indicating that translates the host name (via sni) to the backend name
    [root@router conf]# cat os_tcp_be.map
    www.example.com hello-nginx-secure

    # map indicating that this route should be treated as a passthrough (by using the os_tcp_be.map)
    [root@router conf]# cat os_sni_passthrough.map
    www.example.com 1


    # tcp backend created for the service
    [root@router conf]# vi haproxy.config
    ... removed for clarity ...
    frontend public_ssl
      bind :443
        tcp-request  inspect-delay 5s
        tcp-request content accept if { req_ssl_hello_type 1 }

        # if the connection is SNI and the route is a passthrough don't use the termination backend, just use the tcp backend
        acl sni req.ssl_sni -m found
        acl sni_passthrough req.ssl_sni,map(/var/lib/haproxy/conf/os_sni_passthrough.map) -m found
        use_backend be_tcp_%[req.ssl_sni,map(/var/lib/haproxy/conf/os_tcp_be.map)] if sni sni_passthrough

    ... removed for clarity ...
    backend be_tcp_hello-nginx-secure
      balance leastconn
      timeout check 5000ms
      server hello-nginx-secure 172.17.0.30:443 check inter 5000ms


### UC 4: Reencrypt termination 
This use case assumes that you are starting with an empty OpenShift environment.  Prior to running
this use case it is assumed you have built and started OpenShift.

    # install the router
    [vagrant@openshiftdev origin]$ hack/install-router.sh router https://10.0.2.15:8443
    Creating router file and starting pod...
    router

    # install the pod, service, and route
    [vagrant@openshiftdev origin]$ cd
    [vagrant@openshiftdev ~]$ git clone https://github.com/pweil-/hello-nginx-docker.git
    [vagrant@openshiftdev ~]$ openshift cli create -f hello-nginx-docker/openshift/nginx_pod.json
    hello-nginx-docker
    [vagrant@openshiftdev ~]$ openshift cli create -f hello-nginx-docker/openshift/reencrypt/service.json
    hello-nginx-secure
    [vagrant@openshiftdev ~]$ openshift cli create -f hello-nginx-docker/openshift/reencrypt/route.json
    route-reencrypt

    # verify the pod certificate is www.example.com
    [vagrant@openshiftdev ~]$ openshift cli get pod hello-nginx-docker -o json | grep podIP

    [vagrant@openshiftdev ~]$ openssl s_client -connect 172.17.0.22:443 | grep 'subject\|issuer'
    depth=1 C = US, ST = SC, L = Default City, O = Default Company Ltd, OU = Test CA, CN = www.exampleca.com, emailAddress = example@example.com
    verify error:num=19:self signed certificate in certificate chain
    verify return:0
    subject=/CN=www.example.com/ST=SC/C=US/emailAddress=example@example.com/O=Example/OU=Example
    issuer=/C=US/ST=SC/L=Default City/O=Default Company Ltd/OU=Test CA/CN=www.exampleca.com/emailAddress=example@example.com
    ^C

    # verify the route certificate is www.example2.com
    [vagrant@openshiftdev ~]$ openssl s_client -connect 10.0.2.15:443 -servername www.example2.com | grep 'subject\|issuer'
    depth=1 C = US, ST = SC, L = Default City, O = Default Company Ltd, OU = Test CA, CN = www.exampleca.com, emailAddress = example@example.com
    verify error:num=19:self signed certificate in certificate chain
    verify return:0
    subject=/CN=www.example2.com/ST=SC/C=SU/emailAddress=example@example.com/O=Example2/OU=Example2
    issuer=/C=US/ST=SC/L=Default City/O=Default Company Ltd/OU=Test CA/CN=www.exampleca.com/emailAddress=example@example.com

    # verify the output of the route to ensure connectivity
    # first, create a host entry for www.example2.com in /etc/hosts similar to the use cases above
    [vagrant@openshiftdev ~]$ curl --resolve www.example2.com:443:10.0.2.15 https://www.example2.com --cacert hello-nginx-docker/certs/mypersonalca/certs/ca.pem
    Hello World

    # in depth review
    [vagrant@openshiftdev ~]$ sudo nsenter -m -u -n -i -p -t <pid of your router container>
    [root@router /]# cd /var/lib/haproxy/conf

    # the haproxy.conf relevant to termination + reencryption
    [root@router conf]# cat haproxy.config
    ... removed for clarity ...
    frontend fe_sni
       # terminate ssl on edge
       bind 127.0.0.1:10444 ssl crt /var/lib/containers/router/certs accept-proxy
       mode http

       # re-ssl?
       acl reencrypt hdr(host),map(/var/lib/haproxy/conf/os_reencrypt.map) -m found
       use_backend be_secure_%[hdr(host),map(/var/lib/haproxy/conf/os_tcp_be.map)] if reencrypt

       # regular http
       use_backend be_http_%[hdr(host),map(/var/lib/haproxy/conf/os_http_be.map)] if TRUE

       default_backend openshift_default

    ... removed for clarity ...
    backend be_secure_hello-nginx-secure
      balance leastconn
      timeout check 5000ms
      server hello-nginx-secure 172.17.0.12:443 ssl check inter 5000ms verify required ca-file /var/lib/containers/router/cacerts/www.example2.com_pod.pem

    # the reencryption mapping that signals a secure tcp backend should be used
    [root@router conf]# cat os_reencrypt.map
    www.example2.com 1

    # the mapping of host -> backend
    [root@router conf]# cat os_tcp_be.map
    www.example2.com hello-nginx-secure

