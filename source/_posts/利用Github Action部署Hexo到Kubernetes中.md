---
title: 利用Github Actions部署Hexo到Kubernetes中
date: 2020-01-23
updated: 2020-01-23
categories:
- 操作记录
tags:
- Github
- Kubernetes
- Workflow
- Docker
---

最近看上了一个`Hexo`博客的主题，就打算自己也开一个博客。惊奇的发现 github 上居然已经有了 CI 功能（是我火星了）。于是乎，一个通过 GitHub Actions 持续部署博客到 Kubernetes 中的想法就出现了。通过这种方式，我们可以实现 0 停机时间更新 Hexo、弹性扩缩、健康检查和故障转移等等。。。不过其实都没啥意义，一个博客而已，跑在 1c1g 的机器上，没必要引入这种重型工具。

但这架不住我闲得慌，也就有了现在这一篇记录。本文基本是纯记录，对于很多事情不会有太多介绍和解释。

## 事前准备
- 一个 Github 账号
- 一个已经配置好的 hexo 博客。这方面教程太多了，不赘述了
- 一个云主机，配置无所谓
- 一定的 Linux 操作知识
- 经得住折腾

## 部署Kubernetes？还是K3s吧
最后我还是没有使用 Kubernetes，而是转为使用了`K3s`。原因很简单，Kubernetes 他实在是太大了，光是一个 Etcd 就够我这个可怜的 1c1g 主机喝一壶了。虽然 K8s（Kubernetes）可能是不能用了，但我们还有 K3s 啊。

### 啥是K3s
[K3s](https://k3s.io/)是 Rancher Lab 在 18 年 7 月发行的一个基于 K8s 的容器编排工具。虽然在使用上和 K8s 几乎一模一样，但是为了减少资源的使用，k3s 删除了很多云服务相关的插件（ Cloud Provider）和存储插件。同时，k3s 使用 sqlite 作为默认的数据库，这可以进一步减少 k3s 的资源使用率，对于单机部署来说自然是极好的。当然，k3s 也支持配置 etcd 以及其他数据库，如 mysql、postgresql。

就在这几天（2020 年 1 月 13 号），k3s 正式 release 了 1.0 版本。这意味着 K3S 已经可以正常的使用了。所以我也是第一时间的在自己的云主机上部署了一套来玩。不过值得一提的是，k3s 中的容器并非是使用 docker 来运行的，而是使用了`containderd`，这个工具通过`crictl`交互，子命令和 docker 都差不多。如果想要使用 docker 作为 container runtime，需要在启动参数中指定。

### 在服务器中安装K3s
#### 脚本安装
通常情况下，我们只需要运行一行`curl -sfL https://get.k3s.io | sh -`就可以完成 K3s 的安装了。

#### 手动安装K3S
假如我们不幸遇到了一些网络问题，无法顺利的下载 k3s 二进制文件的话。那么我们可以现在 k3s 的[release](https://github.com/rancher/k3s/releases/latest)页面中找到自己需要的版本，并想办法把它下载下来。

下载下来以后，我们进入到文件所在的目录，并通过 scp 命令，将这个文件上传到我们的机器中。
```sh
# windows中可能需要先开启openssh功能，如果不能开启openssh的话，我们可以安装git bash来运行这个命令
scp k3s root@xxx.xxx.xxx
```
上传完后，登录到我们的主机中，我们需要为其赋予启动权限，并将 K3S 移动到`/usr/local/bin`

```sh
# 为k3s赋予可执行权限
chmod +x k3s
# 移动文件到/usr/local/bin中
mv k3s /usr/local/bin
# 后台运行k3s，这样启动k3s会使用默认的配置，更多配置请看https://rancher.com/docs/k3s/latest/en/installation/install-options/
(k3s server &)
```

安装完成后，我们可以通过一下命令来判断安装是否成功。
```sh
# 脚本安装的可以用这个指令
kubectl get all
# 或
k3s kubectl get all
```

在安装完后，可能还是无法从外网访问这个 K3s，这时候要看一下 iptables 或者其他防火墙设置。对于阿里云、腾讯云之类的云主机，我们还需要更改安全组设置，允许 6443 端口的入向流量进入。

## Action 你的博客
在 K3s 安装完成后，我们就可以开始准备将 Hexo 博客的 github 项目布置上 Github Actions 了。Github Actions 是由 Github 官方提供的一套 CI 方案，对于 CI 不太了解的，可以看看[阮一峰的介绍](http://www.ruanyifeng.com/blog/2015/09/continuous-integration.html)。总之，通过 Actions，我们可以在每次提交代码的时候，让 GitHub 自动帮我们完成`编译->打包->测试->部署`的整个过程。Actions 能做的操作非常的多，详细的说明也可以参考[阮一峰的博客](http://www.ruanyifeng.com/blog/2019/09/getting-started-with-github-actions.html)。

以下是本博客的 Actions 配置，这个配置只会在 master 收到 push 时触发。随后会使用`hexo-cli`将博客编译成静态文件；再将这些静态文件打包到一个 docker 镜像中，并 push 到我的镜像仓库；最后通过 kubectl 将我的应用配置部署到 k3s 服务上。只需要将这个 yaml 文件放在项目根目录下的`.github/workflows`文件夹中，再 push 到 GitHub 上，我们的配置就会生效了。
```yaml
name: master
on:
  push:
      branches:
      - master
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v1
    # node 编译
    - name: build
      uses: actions/setup-node@v1
    - run: |
        npm i -g hexo-cli
        npm i
        hexo clean
        hexo g
    # docker build，并push
    - name: Docker push
      uses: azure/docker-login@v1
      with:
        login-server: reg.qiniu.com
        username: ${{ secrets.REGISTRY_USERNAME }}
        password: ${{ secrets.REGISTRY_PASSWORD }}
    - run: |
        docker build -t reg.qiniu.com/holo-blog/blog:${{ github.sha }} -t reg.qiniu.com/holo-blog/blog .
        docker push reg.qiniu.com/holo-blog/blog:${{ github.sha }}
        docker push reg.qiniu.com/holo-blog/blog
    # 让K8s应用deployment
    - run: |
        sed -i 's/{TAG}/${{ github.sha }}/g' deployment.yaml
    - name: deploy to cluster
      uses: steebchen/kubectl@master
      env:
        KUBE_CONFIG_DATA: ${{ secrets.KUBE_CONFIG_DATA }}
        KUBECTL_VERSION: "1.15"
      with:
        args: apply -f deployment.yaml
    - name: verify deployment
      uses: steebchen/kubectl@master
      env:
        KUBE_CONFIG_DATA: ${{ secrets.KUBE_CONFIG_DATA }}
        KUBECTL_VERSION: "1.15"
      with:
        args: '"rollout status -n blog deployment/blog"'
```
在这个配置中我们使用到了三个 secrets，分别是镜像仓账号密码和 kubeconfig，通过 secrets 调用敏感信息可以避免在 actions 日志或者代码仓库中将这部分信息暴露出来。我们可以在 GitHub 项目`settings-secrets`页面中设置 secrets。`KUBE_CONFIG_DATA`这个密钥是 kubeconfig 文件的 base64 版，我们可以通过以下命令来得到这个 secrets。
```sh
kubectl config view | base64
# 或
k3s kubectl config view | base64
```

通过这种方式得到的 kubeconfig 中的 apiserver 的地址可能不正确（是 127.0.0.1），我们可以先将 kubeconfig 保存成文件，在修改完成后在通过`cat kubeconfig | base64`得到正确的 config 信息。

### Docker打包与推送
在`Docker push`这一步中，会用到根目录的一个 dockerfile 文件。通过 dockerfile，我们可以将应用部署到任意同架构同系统的机器中。关于[docker](https://docs.docker.com/)和[dockerfile](https://docs.docker.com/engine/reference/builder/)的更多信息可以查看官方文档。

对于 hexo 博客而言，通过`hexo g`编译成静态文件后我们就可以直接通过访问`public`文件夹中的 index.html 文件来预览我们的博客了。所以在这里我们可以通过将静态文件打包到一个 nginx 镜像中，并暴露 80 端口来为提供 http 请求提供服务。
```dockerfile
FROM nginx:1.17.7-alpine
EXPOSE 80
EXPOSE 443
COPY public /usr/share/nginx/html
```

打包好镜像后，我们需要将其 push 到某一个镜像仓库中，我用的是七牛云，因为不要钱。

### Apply你的升级！
最后，我们需要通知 k3s 部署服务或者升级服务。通过在设置好 kubeconfig 文件，我们便能使用 kubectl 远程访问 apiserver。在通过`kubectl apply -f deployment.yaml`部署上最新的配置文件即可。

在这里我又偷了点懒，应用的文件名虽然叫做`deployment.yaml`，但是其实`service`和`ingress`的配置我也一并写入其中了，其完整配置如下：
```yaml
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: blog
  namespace: blog
spec:
  rules:
  - host: dalaocarryme.com
    http:
      paths:
      - backend:
          serviceName: blog
          servicePort: 80
  - host: www.dalaocarryme.com
    http:
      paths:
      - backend:
          serviceName: blog
          servicePort: 80
  - host: blog.dalaocarryme.com
    http:
      paths:
      - backend:
          serviceName: blog
          servicePort: 80
  backend:
    serviceName: blog
    servicePort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: blog
  namespace: blog
spec:
  ports:
  - name: http
    port: 80
    protocol: TCP
    targetPort: 80
  selector:
    app: blog
  sessionAffinity: ClientIP
  type: ClusterIP
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: blog
  namespace: blog
spec:
  progressDeadlineSeconds: 600
  replicas: 2
  revisionHistoryLimit: 10
  selector:
    matchLabels:
      app: blog
  strategy:
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 1
    type: RollingUpdate
  template:
    metadata:
      labels:
        app: blog
    spec:
      containers:
      - image: reg.qiniu.com/holo-blog/blog:{TAG}
        imagePullPolicy: IfNotPresent
        livenessProbe:
          failureThreshold: 3
          httpGet:
            path: /
            port: 80
            scheme: HTTP
          initialDelaySeconds: 10
          periodSeconds: 2
          successThreshold: 1
          timeoutSeconds: 2
        name: blog
        ports:
        - containerPort: 80
          name: 80tcp02
          protocol: TCP
        readinessProbe:
          failureThreshold: 3
          httpGet:
            path: /
            port: 80
            scheme: HTTP
          initialDelaySeconds: 10
          periodSeconds: 2
          successThreshold: 2
          timeoutSeconds: 2
        resources: {}
        securityContext:
          allowPrivilegeEscalation: false
          capabilities: {}
          privileged: false
          readOnlyRootFilesystem: false
          runAsNonRoot: false
        stdin: true
        terminationMessagePath: /dev/termination-log
        terminationMessagePolicy: File
        tty: true
        volumeMounts:
        - mountPath: /usr/share/nginx/html/db.json
          name: db
        - mountPath: /usr/share/nginx/html/Thumbs.json
          name: thumbs
      dnsConfig: {}
      dnsPolicy: ClusterFirst
      restartPolicy: Always
      schedulerName: default-scheduler
      securityContext: {}
      terminationGracePeriodSeconds: 30
      volumes:
      - hostPath:
          path: /data/db.json
          type: ""
        name: db
      - hostPath:
          path: /data/Thumbs.json
          type: ""
        name: thumbs
```
需要注意的是，在 docker build 时，我是用的 gitsha 来给镜像打的 tag，所以在 deployment 对象中，我的镜像 tag 那个留的是一个`{TAG}`占位符。然后我们再用 sed 命令将这个占位符替换为 gitsha 即可。在 actions 中配置如下：
```yaml
    - run: |
        sed -i 's/{TAG}/${{ github.sha }}/g' deployment.yaml
```

对于 hexo 中的点击数据点赞数据，我们可以通过挂载一个本地卷来将其持久化。这样我们的镜像更新就不会将我们的数据带走了。

如果希望能够 0 中断更新，我们可以部署两个 pod，或者部署 1 个 pod，但是将更新策略设置为 0 个`maxUnavailable`，这样就可以始终保证有一个 pod 在提供服务了。

其他还有很多细节需要注意，但在这里就不多做展开了。未来可能会做一系列关于 kubernetes 和 git 的文章，感兴趣可以关注以下。

本文中所用到的设置与代码都在 https://github.com/Okabe-Kurisu/blog 中。