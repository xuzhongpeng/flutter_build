执行环境

> flutter 版本：v1.12.13+hotfix.9

> macOS 系统： 10.15.4

1. 修改 configs/build_android.dart

```
String mavenUrl = 'maven仓库地址';
String username = 'maven仓库名';
String password = 'maven仓库密码';
String debugUrl = ''; //推送企业微信debug机器人 没有不传就行了
String releaseUrl = ''; //推送企业微信release机器人
```

2. 修改 build.pom 中的上传 maven 的`groupId`及`artifactId`

3. 执行 `dart ./configs/build_android.dart` 开始打包并根据提示输入打包信息
