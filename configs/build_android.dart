import 'dart:convert';
import 'dart:io';
import 'package:xml/xml.dart' as xml;

String projectDir = Directory('').absolute.path;

String mavenUrl = 'http://47.111.7.46:8080/repository/maven-releases';
String username = 'android';
String password = 'gunmaduoke';
String debugUrl = ''; //推送企业微信debug机器人
String releaseUrl = ''; //推送企业微信release机器人
void main() async {
  List<String> arguments = [];
  print("输入打包方式：debug & release & both(两种同时打包):");
  arguments.add(stdin.readLineSync());
  print("输入打包版本号:");
  arguments.add(stdin.readLineSync());
  if (await buildAndroid(arguments)) {
    exit(0);
  } else {
    exit(-1);
  }
}

Future<bool> buildAndroid(List<String> arguments) async {
  // Directory('$projectDir/.android/config').deleteSync(recursive: true);
  // Directory('$projectDir/.android/Flutter/build').deleteSync(recursive: true);
  if (arguments.length != 2) {
    print('参数错误，请确认');
    return false;
  }
  String buildMode = arguments[0]; //debug release both
  String buildVersion = arguments[1]; //版本号
  print('android开始打包,打包方式是$buildMode,打包版本是$buildVersion');

  print('package get');
  await start('flutter', ['pub', 'upgrade']);

  print('复制打包aar相关文件');
  {
    File copyFile =
        File(projectDir + '.android/config/dependencies_gradle_plugin.gradle');
    copyFile.createSync(recursive: true);
    copyFile.writeAsStringSync(gradlePlugin);
  }
  print('插入fat-aar相关的包');
  {
    print('插入文件到.andriod/build.gradle');
    File file = File(projectDir + '/.android/build.gradle');
    String buildGradle = file.readAsStringSync();
    if (!buildGradle.contains('com.kezong:fat-aar')) {
      buildGradle = buildGradle.replaceAllMapped(
          RegExp(r"'com.android.tools.build:gradle\S+"), (group) {
        return group.groups([0])[0] + '\nclasspath "com.kezong:fat-aar:1.2.12"';
      });
      file.writeAsStringSync(buildGradle);
    }

    print('插入文件到.andorid/Flutter/build.gradle');
    File flutterGradleFile =
        File(projectDir + '/.android/Flutter/build.gradle');
    String flutterGradleStr = flutterGradleFile.readAsStringSync();
    if (!flutterGradleStr.contains('com.kezong.fat-aar')) {
      flutterGradleStr +=
          '\napply plugin: "com.kezong.fat-aar"\napply from: "../config/dependencies_gradle_plugin.gradle"';
      flutterGradleFile.writeAsStringSync(flutterGradleStr);
    }
  }
  print('开始打包');
  {
    int exitCode;
    print('正在打包...');
    if (buildMode == 'debug') {
      exitCode = await start('bash', ['./gradlew', 'assembleProfile'],
          workingDirectory: '$projectDir/.android', isPrint: false);
    } else if (buildMode == 'release') {
      exitCode = await start('bash', ['./gradlew', 'assembleRelease'],
          workingDirectory: '$projectDir/.android', isPrint: false);
    } else {
      exitCode = await start('bash', ['./gradlew', 'assemble'],
          workingDirectory: '$projectDir/.android', isPrint: false);
    }
    if (exitCode != 0) {
      print('打包出错');
      return false;
    } else {
      print('打包成功');
    }
  }

  print('开始上传maven');
  {
    bool result;
    if (buildMode == 'debug' || buildMode == 'release') {
      result = await uploadMaven(buildVersion, buildMode);
      await uploadToWX(buildVersion, buildMode, exitCode == 0);
      if (!result) {
        print('上传aar失败');
        return false;
      }
    } else {
      result = await uploadMaven(buildVersion, 'debug');
      await uploadToWX(buildVersion, 'debug', exitCode == 0);
      if (exitCode != 0) {
        print('上传aar失败');
        return false;
      }
      result = await uploadMaven(buildVersion, 'release');
      await uploadToWX(buildVersion, 'release', exitCode == 0);
      if (exitCode != 0) {
        print('上传aar失败');
        return false;
      }
    }
  }
  return true;
}

//通知到企业微信
Future<int> uploadToWX(
    String buildVersion, String buildMode, bool result) async {
  if (debugUrl == '' || releaseUrl == '') {
    print('没设置通知url');
    return -1;
  }
  String info = '修复缺陷'; // releaseInfo.readAsStringSync();
  if (result)
    info = "<font color=\\\"info\\\">打包成功</font> ($info)";
  else {
    info = "<font color=\\\"red\\\">打包失败</font>";
  }
  String debugWXUrl = debugUrl; //放企业微信debug机器人url
  if (buildMode == 'release') {
    debugWXUrl = releaseUrl; //放企业微信release机器人url
  }
  return await start('curl', [
    debugWXUrl,
    '-H',
    'Content-Type: application/json',
    '-d'
        '''{
            \"msgtype\": \"markdown\",
            \"markdown\": {
            \"content\": \"android-$buildMode-$buildVersion $info\"
            }
        }''',
    '-k'
  ]);
}

//执行sh脚本
Future<int> start(String executable, List<String> arguments,
    {String workingDirectory,
    Map<String, String> environment,
    bool includeParentEnvironment = true,
    bool runInShell = true,
    ProcessStartMode mode = ProcessStartMode.normal,
    bool isPrint = true}) async {
  Process result = await Process.start(executable, arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      includeParentEnvironment: includeParentEnvironment,
      runInShell: runInShell,
      mode: mode);
  result.stdout.listen((out) {
    if (isPrint) print(utf8.decode(out));
  });
  result.stderr.listen((err) {
    print(utf8.decode(err));
  });
  return result.exitCode;
}

class DeployObject {
  File pomFile;
  File aarFile;
}

///上传到maven
Future<bool> uploadMaven(String version, String buildMode) async {
  if (mavenUrl == 'xxx') {
    print('你什么都没改，别传maven了');
    return false;
  }
  String pomName; //pom名
  String build; //arr对应文件名
  // final dir = Directory("build/host/outputs/repo");
  if (buildMode == 'debug') {
    pomName = 'debug';
    build = 'profile';
  } else {
    pomName = 'release';
    build = 'release';
  }
  final aar =
      File("$projectDir/.android/Flutter/build/outputs/aar/flutter-$build.aar");
  final pom1 = File("$projectDir/configs/build.pom");
  final tempPath = File("${Directory.systemTemp.path}/temp.pom");
  tempPath.createSync(recursive: true);
  final temp = pom1.copySync(tempPath.path);
  print('修改pom内容');
  {
    final doc = xml.parse(temp.readAsStringSync());
    {
      // 修改自身的版本号
      final xml.XmlText versionNode =
          doc.findAllElements("version").first.firstChild;
      versionNode.text = version;
      final xml.XmlText name =
          doc.findAllElements("artifactId").first.firstChild;
      name.text = pomName;
    }
    final elements = doc.findAllElements("dependency");
    // 修改flutter相关依赖名
    for (final element in elements) {
      xml.XmlText artifactId =
          element.findElements("artifactId").first.firstChild;
      if (artifactId.text.contains('release')) {
        artifactId.text =
            artifactId.text.replaceAll('release', build); // 修改依赖的版本号
        print(artifactId);
      }
    }
    final buffer = StringBuffer();
    doc.writePrettyTo(buffer, 0, "  ");
    temp.writeAsStringSync(buffer.toString());
  }
  DeployObject deploy = DeployObject()
    ..aarFile = aar
    ..pomFile = temp;

  //把用户名密码写入mvn-setting.xml
  {
    File setting = File('$projectDir/configs/mvn-settings.xml');
    final doc = xml.parse(setting.readAsStringSync());
    final xml.XmlText user = doc.findAllElements("username").first.firstChild;
    user.text = username;
    final xml.XmlText pwd = doc.findAllElements('password').first.firstChild;
    pwd.text = password;
    final buffer = StringBuffer();
    doc.writePrettyTo(buffer, 0, "  ");
    setting.writeAsStringSync(buffer.toString());
  }
  print('开始上传');
  {
    final configPath =
        File('$projectDir/configs/mvn-settings.xml').absolute.path;
    List<String> args = [
      'deploy:deploy-file',
      '-DpomFile="${deploy.pomFile.absolute.path}"',
      '-Dmaven.metadata.legacy=true',
      '-DgeneratePom=false',
      '-Dfile="${deploy.aarFile.absolute.path}"',
      '-Durl="${mavenUrl}"',
      '-DrepositoryId="nexus"',
      '-Dpackaging=aar',
      '-s="$configPath"',
    ];
    final shell = "mvn ${args.join(' \\\n    ')}";
    final f = File(
        "${Directory.systemTemp.path}/${DateTime.now().millisecondsSinceEpoch}.sh");
    f.writeAsStringSync(shell);
    final exitCode = await start('bash', [f.path]);
    f.deleteSync();
    if (exitCode != 0) {
      print(deploy.aarFile.path.split('/').last + '上传失败');
      return false;
    } else {
      print(deploy.aarFile.path.split('/').last + '上传成功');
    }
  }
  temp.deleteSync();
  return true;
}

//加载aar的gradle
String gradlePlugin = """
  dependencies {
    def flutterProjectRoot = rootProject.projectDir.parentFile.toPath()
    def plugins = new Properties()
    def pluginsFile = new File(flutterProjectRoot.toFile(), '.flutter-plugins')
    if (pluginsFile.exists()) {
        pluginsFile.withReader('UTF-8') { reader -> plugins.load(reader) }
    }
    plugins.each { name, path->
        File editableAndroidProject = new File(path, 'android' + File.separator + 'build.gradle')
        println name
        if (editableAndroidProject.exists()) {
            embed project(path: ":\$name", configuration: 'default')
        }
    }
}
""";
