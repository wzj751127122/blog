---
title: 为自己的Gitlab账号设置动态头像
date: 2019-09-12
updated: 2019-09-12
categories:
- 技巧
tags:
- Gitlab
- Javascript
- 技巧
---

在使用私人的 gitlab 的时候，我发现 gitlab 可以上传自定义头像，而且支持各种类型，但是裁剪后都只变成了 png 类型。这样的话，头像就都是静态的了，显得十分枯燥。经过 20 分钟的摸索，我终于将我的头像改成了动态头像。

以下过程我是在内网 gitlab 中实现的，在公网上那个 gitlab 上能不能好使我就不知道了。

## 原理

感谢开源精神，我们可以在 gitlab 上看到关于 gitlab 的全部代码。[这里](https://gitlab.com/gitlab-org/gitlab/blob/master/app/assets/javascripts/profile/profile.js)是有关修改个人信息的前端代码。

读代码的部分就不介绍了，简而言之，在点击`更新个人资料设置`的时候，会检查是否在某个元素中通过`jquery.data()`方法存储了头像图片的 blob 对象，如果有的话，就把这个对象封装到 form 对象中，并将这个 blob 对象上传到后端。

而在前端中对于图片的上传是没有任何验证的，我们直接就可以上传任何内容，然后格式都会被标识为 png。

那么要做的就很简单了，我们只需要将我们想要用作头像的图片转换成一个 blob，赋值给页面后，再触发一次正常的更新资料就好了

## 步骤

1. 登录， 并打开你的编辑个人资料页面。
2. 按一下`F12`，打开开发者工具，并点击开发者工具顶部的 Network 按钮。这时候会开始监听页面请求。
3. 点击页面中的选择文件按钮，并且将想要用的头像上传上去。这时候再看开发者工具的 Network，会发现多出来一行`data:image`起头的请求，右键这一行，并选择`复制`-`复制链接地址`。
4. 这个时候我们已经得到了一个`base64`编码的图片。在开发者工具最底下的 Console 中输入如下代码，记得修改其中需要粘贴 base64 图片的地方

  ```javascript
  function dataURLtoBlob(dataurl) {
  var arr = dataurl.split(","),
   mime = arr[0].match(/:(.*?);/)[1],
   bstr = atob(arr[1]),
   n = bstr.length,
   u8arr = new Uint8Array(n);
  while (n--) {
   u8arr[n] = bstr.charCodeAt(n);
  }
  return new Blob([u8arr], { type: mime });
  }
  let blob = dataURLtoBlob('此处粘贴你的base64')
  let avatar = $('.js-user-avatar-input').data('glcrop')
  avatar.croppedImageBlob = blob
  ```

5. 点击个人资料页面中的`更新个人资料设置`按钮，如果不出意外就已经成功了。
