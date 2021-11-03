---
title: Kubernetes 服务切换https 
date: 2021-11-03
updated: 2021-11-03
categories:
  - Record
index_img: /img/ssl.png
tags:
  - Kubernetes
  - http
  - ssl


---

之前一直使用http来访问网站，没太关注https的相关内容，今天将网站访问https的证书添加上，以后就不会提示不安全的访问了。

大致步骤分为以下几块：

1. 某服务器网站可以申请免费的ssl证书，先去申请一个ssl证书
2. ssl证书申请，添加相应的访问域名用于申请证书
3. 将证书文件创建为secret资源
4. 将nginx配置文件修改为configMap形式进行挂载
5. 修改网站访问的ingress转发规则
6. 修改服务的yaml文件来挂载secret和configmap
7. 测试

## 申请证书

登陆控制台申请免费的sll证书

![image-20211103161155462](https://tva1.sinaimg.cn/large/008i3skNly1gw213124n0j311307nq3o.jpg)

申请成功后点击下载将证书文件上传云服务器上并解压缩

```shell
[root@VM-8-8-centos Nginx]# ll
总用量 8
-rw-r--r-- 1 root root 3897 11月  3 10:44 1_i9t.top_bundle.crt
-rw-r--r-- 1 root root 1704 11月  3 10:44 2_i9t.top.key
```



## 创建证书的secret资源

*要注意secret一定要和你的服务在同一个namespace内，否则创建的secret和configmap无法被读取到*

```shell
[root@VM-8-8-centos Nginx]# kubectl create secret tls --namespace=blog nginx-secret --key /root/Nginx/2_i9t.top.key --cert /root/Nginx/1_i9t.top_bundle.crt
[root@VM-8-8-centos Nginx]# kubectl get secret -n blog
NAME                  TYPE                                  DATA   AGE
default-token-kl8nq   kubernetes.io/service-account-token   3      274d
nginx-secret          kubernetes.io/tls                     2      39m
```



创建配置有ssl证书的conf文件，以configmap的形式挂载使用

首先编写一个nginx的配置文件

```shell
[root@VM-8-8-centos Nginx]# vim nginx.conf
```

```shell
server {
    listen       80;
    listen       443 ssl;
    server_name  localhost;

    #charset koi8-r;
    #access_log  /var/log/nginx/host.access.log  main;
    ssl_certificate /etc/nginx/ssl/tls.crt; #填写您的证书文件名称，例如：1_cloud.tencent.com_bundle.crt
    ssl_certificate_key /etc/nginx/ssl/tls.key; #填写您的私钥文件名称，例如：2_cloud.tencent.com.key
    ssl_session_timeout 5m;
    ssl_protocols TLSv1 TLSv1.1 TLSv1.2;  # 可参考此 SSL 协议进行配置
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:HIGH:!aNULL:!MD5:!RC4:!DHE;   #可按照此加密套件配置，写法遵循 openssl 标准
    ssl_prefer_server_ciphers on;
    location / {
        root   /usr/share/nginx/html;
        index  index.html index.htm;
    }

    #error_page  404              /404.html;

    # redirect server error pages to the static page /50x.html
    #
    error_page   500 502 503 504  /50x.html;
    location = /50x.html {
        root   /usr/share/nginx/html;
    }
```

创建configmap(当然你也可以以yaml格式的文件来创建)

```shell
[root@VM-8-8-centos Nginx]# kubectl create configmap --namespace=blog nginx-conf --from-file=nginx.conf
[root@VM-8-8-centos ~]# kubectl get cm -n blog
NAME         DATA   AGE
nginx-conf   1      43m
```

## 修改服务的ingress规则

```shell
[root@VM-8-8-centos ~]# kubectl edit ingress -n blog blog
```

```yaml
# cat ingress.yaml
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: secret-tls-ingress
  annotations:
    ingress.kubernetes.io/ssl-redirect: "False"
spec:
  tls:
  - hosts:
    - i9t.com
    secretName: nginx-secret
  rules:
  - host: i9t.com
    http:
      paths:
      - backend:
          serviceName: blog
          servicePort: 80
        path: /
```

## 修改服务的配置yaml文件

```shell
[root@VM-8-8-centos ~]# cat blog.yaml
```

```yaml
[root@VM-8-8-centos ~]# cat nginx-app.yaml 
apiVersion: v1
kind: Service
metadata:
  name: my-nginx
  labels:
    run: my-nginx
spec:
  type: NodePort
  ports:
  - port: 8080
    targetPort: 80
    protocol: TCP
    name: http
  - port: 443         #这里service要开启443访问
    protocol: TCP
    name: https
  selector:
    run: my-nginx
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-nginx
spec:
  selector:
    matchLabels:
      run: my-nginx
  replicas: 1
  template:
    metadata:
      labels:
        run: my-nginx
    spec:
      volumes:
      - name: secret-volume
        secret:
          secretName: nginx-secret
      - name: configmap-volume
        configMap:
          name: nginx-configmap
      containers:
      - name: nginxhttps
        image: wzj751127122/nginxhttps:1.0
        ports:
        - containerPort: 443
        - containerPort: 80
        volumeMounts:
        - mountPath: /etc/nginx/ssl
          name: secret-volume
        - mountPath: /etc/nginx/conf.d
          name: configmap-volume
```



## 测试访问即可

```shel
[root@VM-8-8-centos ~]# curl https://www.i9t.top
```

