import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:condor_cli/src/command.dart';
import 'package:condor_cli/src/common.dart';
import 'package:condor_cli/src/utils/log.dart';
import 'package:path/path.dart' as p;
import 'package:http/http.dart' as http;

/// 查询Mac系统中安装的应用程序
class AppsCommand extends CondorCommand {
  /// 构造函数
  AppsCommand() {
    argParser
      ..addFlag(
        'count',
        abbr: 'c',
        help: '只显示应用数量',
        negatable: false,
      )
      ..addFlag(
        'all',
        abbr: 'a',
        help: '包含系统应用',
        negatable: false,
      )
      ..addOption(
        'search',
        abbr: 's',
        help: '搜索特定应用',
      )
      ..addFlag(
        'homebrew',
        help: '显示通过Homebrew安装的应用',
        negatable: false,
      )
      ..addFlag(
        'mas',
        help: '显示通过Mac App Store安装的应用',
        negatable: false,
      )
      ..addFlag(
        'detailed',
        abbr: 'd',
        help: '显示应用详细信息',
        negatable: false,
      )
      ..addOption(
        'app',
        help: '查看指定应用的详细信息',
      )
      ..addFlag(
        'outdated',
        abbr: 'o',
        help: '检查哪些应用有可用更新',
        negatable: false,
      );
  }

  @override
  String get description => '查询Mac系统中已安装的应用程序';

  @override
  String get name => 'apps';

  @override
  Future<int> run() async {
    if (!Platform.isMacOS) {
      Log.error('该命令仅支持Mac系统');
      return ExitCode.unavailable.code;
    }
    
    final bool onlyCount = boolOption('count');
    final bool includeSystem = boolOption('all');
    final String? searchTerm = results.wasParsed('search') ? results['search'] as String : null;
    final bool showHomebrew = boolOption('homebrew');
    final bool showMas = boolOption('mas');
    final bool showDetailed = boolOption('detailed');
    final String? specificApp = results.wasParsed('app') ? results['app'] as String : null;
    final bool checkUpdates = boolOption('outdated');
    
    // 检查更新
    if (checkUpdates) {
      return await _checkForUpdates(searchTerm);
    }
    
    // 如果指定了查询具体应用详情
    if (specificApp != null) {
      return await _showAppDetailedInfo(specificApp);
    }
    
    // 如果指定了查询Homebrew或MAS，则优先处理这些
    if (showHomebrew) {
      return await _listHomebrewApps(searchTerm, onlyCount, showDetailed);
    } else if (showMas) {
      return await _listMacAppStoreApps(searchTerm, onlyCount, showDetailed);
    }
    
    Log.info('正在查询已安装的应用程序...');
    
    try {
      // 查询应用程序目录
      final List<FileSystemEntity> mainApps = await _getApplications('/Applications');
      final List<FileSystemEntity> userApps = await _getApplications('${Platform.environment['HOME']}/Applications');
      
      // 合并结果
      final List<FileSystemEntity> allApps = [...mainApps, ...userApps];
      
      // 应用信息列表
      final List<Map<String, dynamic>> appInfoList = [];
      
      // 处理应用数据
      for (final app in allApps) {
        final String basename = p.basename(app.path);
        if (basename.endsWith('.app')) {
          final String appName = basename.substring(0, basename.length - 4);
          
          // 是否跳过系统应用
          if (!includeSystem && _isSystemApp(appName)) {
            continue;
          }
          
          // 是否符合搜索词
          if (searchTerm != null && searchTerm.isNotEmpty && 
              !appName.toLowerCase().contains(searchTerm.toLowerCase())) {
            continue;
          }
          
          // 添加应用信息
          final Map<String, dynamic> appInfo = {
            'name': appName,
            'path': app.path,
          };
          
          // 如果需要详细信息
          if (showDetailed) {
            await _addDetailedAppInfo(appInfo);
          }
          
          appInfoList.add(appInfo);
        }
      }
      
      // 排序
      appInfoList.sort((a, b) => a['name'].toLowerCase().compareTo(b['name'].toLowerCase()));
      
      // 输出结果
      if (onlyCount) {
        Log.success('已安装应用数量: ${appInfoList.length}');
      } else {
        if (appInfoList.isEmpty) {
          Log.info('未找到符合条件的应用');
        } else {
          Log.success('已安装应用列表 (共${appInfoList.length}个):');
          for (final appInfo in appInfoList) {
            if (showDetailed) {
              _printDetailedAppInfo(appInfo);
            } else {
              stdout.writeln('- ${appInfo['name']}');
            }
          }
        }
      }
      
      return ExitCode.success.code;
    } catch (e) {
      Log.error('查询应用程序时出错: $e');
      return ExitCode.software.code;
    }
  }

  /// 获取指定目录中的应用
  Future<List<FileSystemEntity>> _getApplications(String directory) async {
    final dir = Directory(directory);
    if (!await dir.exists()) {
      return [];
    }
    
    return await dir
        .list()
        .where((entity) => 
            entity is Directory && p.basename(entity.path).endsWith('.app'))
        .toList();
  }
  
  /// 判断是否为系统应用
  bool _isSystemApp(String appName) {
    final systemApps = [
      'App Store', 'Books', 'Calculator', 'Calendar', 'Chess',
      'Contacts', 'Dictionary', 'FaceTime', 'Font Book', 'Home',
      'Image Capture', 'Launchpad', 'Mail', 'Maps', 'Messages',
      'Mission Control', 'News', 'Notes', 'Photo Booth', 'Photos',
      'Preview', 'QuickTime Player', 'Reminders', 'Safari',
      'Siri', 'Stickies', 'Stocks', 'System Preferences', 'System Settings',
      'TextEdit', 'Time Machine', 'TV', 'Utilities', 'Voice Memos',
    ];
    
    return systemApps.contains(appName);
  }
  
  /// 添加应用的详细信息
  Future<void> _addDetailedAppInfo(Map<String, dynamic> appInfo) async {
    try {
      final String appPath = appInfo['path'];
      
      // 获取应用大小
      final result = await Process.run('du', ['-sh', appPath]);
      if (result.exitCode == 0) {
        final String output = result.stdout as String;
        final sizeMatch = RegExp(r'^(\S+)').firstMatch(output);
        if (sizeMatch != null) {
          appInfo['size'] = sizeMatch.group(1);
        }
      }
      
      // 获取应用元数据
      final mdlsResult = await Process.run('mdls', [appPath]);
      if (mdlsResult.exitCode == 0) {
        final String mdlsOutput = mdlsResult.stdout as String;
        
        // 解析上次使用时间
        final lastUsedMatch = RegExp(r'kMDItemLastUsedDate\s+=\s+(.+)').firstMatch(mdlsOutput);
        if (lastUsedMatch != null) {
          appInfo['lastUsed'] = lastUsedMatch.group(1)?.trim();
        }
        
        // 解析版本信息
        final versionMatch = RegExp(r'kMDItemVersion\s+=\s+"(.+)"').firstMatch(mdlsOutput);
        if (versionMatch != null) {
          appInfo['version'] = versionMatch.group(1);
        }
        
        // 应用创建时间（安装时间）
        final createdMatch = RegExp(r'kMDItemContentCreationDate\s+=\s+(.+)').firstMatch(mdlsOutput);
        if (createdMatch != null) {
          appInfo['created'] = createdMatch.group(1)?.trim();
        }
      }
      
      // 获取应用包信息
      final plistPath = '$appPath/Contents/Info.plist';
      if (await File(plistPath).exists()) {
        final plistResult = await Process.run('plutil', ['-convert', 'json', '-o', '-', plistPath]);
        if (plistResult.exitCode == 0) {
          try {
            final Map<String, dynamic> plistInfo = jsonDecode(plistResult.stdout as String);
            appInfo['bundleId'] = plistInfo['CFBundleIdentifier'];
            appInfo['displayName'] = plistInfo['CFBundleDisplayName'] ?? plistInfo['CFBundleName'];
            
            // 获取最小系统版本要求
            if (plistInfo.containsKey('LSMinimumSystemVersion')) {
              appInfo['minOSVersion'] = plistInfo['LSMinimumSystemVersion'];
            }
          } catch (e) {
            // 解析错误，忽略
          }
        }
      }
    } catch (e) {
      // 获取详细信息出错，忽略
    }
  }

  /// 打印应用的详细信息
  void _printDetailedAppInfo(Map<String, dynamic> appInfo) {
    stdout.writeln('- ${appInfo['name']}');
    
    if (appInfo.containsKey('displayName') && appInfo['displayName'] != null && 
        appInfo['displayName'] != appInfo['name']) {
      stdout.writeln('  显示名称: ${appInfo['displayName']}');
    }
    
    if (appInfo.containsKey('version')) {
      stdout.writeln('  版本: ${appInfo['version']}');
    }
    
    if (appInfo.containsKey('bundleId')) {
      stdout.writeln('  包ID: ${appInfo['bundleId']}');
    }
    
    if (appInfo.containsKey('size')) {
      stdout.writeln('  占用空间: ${appInfo['size']}');
    }
    
    if (appInfo.containsKey('lastUsed')) {
      stdout.writeln('  上次使用: ${appInfo['lastUsed']}');
    }
    
    if (appInfo.containsKey('created')) {
      stdout.writeln('  安装时间: ${appInfo['created']}');
    }
    
    if (appInfo.containsKey('minOSVersion')) {
      stdout.writeln('  最低系统要求: ${appInfo['minOSVersion']}');
    }
    
    stdout.writeln('  安装位置: ${appInfo['path']}');
    stdout.writeln('');
  }
  
  /// 显示特定应用的详细信息
  Future<int> _showAppDetailedInfo(String appName) async {
    Log.info('正在查询应用 "$appName" 的详细信息...');
    
    try {
      // 查询应用程序目录
      final List<FileSystemEntity> mainApps = await _getApplications('/Applications');
      final List<FileSystemEntity> userApps = await _getApplications('${Platform.environment['HOME']}/Applications');
      
      // 合并结果
      final List<FileSystemEntity> allApps = [...mainApps, ...userApps];
      
      // 查找匹配的应用
      FileSystemEntity? matchedApp;
      for (final app in allApps) {
        final String basename = p.basename(app.path);
        if (basename.endsWith('.app')) {
          final String currentAppName = basename.substring(0, basename.length - 4);
          if (currentAppName.toLowerCase() == appName.toLowerCase() || 
              currentAppName.toLowerCase().contains(appName.toLowerCase())) {
            matchedApp = app;
            break;
          }
        }
      }
      
      if (matchedApp == null) {
        Log.error('未找到应用 "$appName"');
        return ExitCode.noInput.code;
      }
      
      // 获取应用信息
      final String fullAppName = p.basename(matchedApp.path).substring(
          0, p.basename(matchedApp.path).length - 4);
      
      final Map<String, dynamic> appInfo = {
        'name': fullAppName,
        'path': matchedApp.path,
      };
      
      // 添加详细信息
      await _addDetailedAppInfo(appInfo);
      
      // 获取额外的应用信息
      await _addExtraAppInfo(appInfo);
      
      // 显示应用信息
      Log.success('应用详细信息:');
      _printFullAppInfo(appInfo);
      
      return ExitCode.success.code;
    } catch (e) {
      Log.error('查询应用详细信息时出错: $e');
      return ExitCode.software.code;
    }
  }
  
  /// 添加额外的应用信息
  Future<void> _addExtraAppInfo(Map<String, dynamic> appInfo) async {
    try {
      final String appPath = appInfo['path'];
      
      // 获取应用签名信息
      final codesignResult = await Process.run('codesign', ['-dvv', appPath]);
      if (codesignResult.exitCode == 0 || codesignResult.exitCode == 1) {
        // codesign输出到stderr
        final String output = codesignResult.stderr as String;
        
        // 解析签名者身份
        final authorityMatch = RegExp(r'Authority=(.+)').firstMatch(output);
        if (authorityMatch != null) {
          appInfo['signedBy'] = authorityMatch.group(1);
        }
        
        // 解析团队ID
        final teamIdMatch = RegExp(r'TeamIdentifier=(.+)').firstMatch(output);
        if (teamIdMatch != null) {
          appInfo['teamId'] = teamIdMatch.group(1);
        }
      }
      
      // 获取应用权限信息
      final entitlementsResult = await Process.run('codesign', ['--display', '--entitlements', ':-', appPath]);
      if (entitlementsResult.exitCode == 0) {
        final String output = entitlementsResult.stderr as String;
        if (output.contains('entitlements')) {
          appInfo['hasEntitlements'] = true;
        }
      }
      
      // 获取应用类型（Intel/ARM/Universal）
      final fileResult = await Process.run('file', [appPath]);
      if (fileResult.exitCode == 0) {
        final String output = fileResult.stdout as String;
        if (output.contains('Mach-O')) {
          if (output.contains('arm64')) {
            appInfo['architecture'] = output.contains('x86_64') ? '通用二进制 (Intel + Apple Silicon)' : 'Apple Silicon (ARM)';
          } else if (output.contains('x86_64')) {
            appInfo['architecture'] = 'Intel (x86_64)';
          }
        }
      }
      
      // 使用系统剖析器获取更多信息
      final spctlResult = await Process.run('spctl', ['--assess', '--verbose', appPath]);
      if (spctlResult.exitCode == 0) {
        final String output = spctlResult.stderr as String;
        if (output.contains('accepted')) {
          appInfo['gatekeeperStatus'] = '已通过公证';
        } else {
          appInfo['gatekeeperStatus'] = '未通过公证';
        }
      }
      
      // 获取应用启动次数
      try {
        final String bundleId = appInfo['bundleId'] ?? '';
        if (bundleId.isNotEmpty) {
          final cfprefsResult = await Process.run('bash', ['-c', 
              "defaults read com.apple.appstore.commerce | grep -A5 '$bundleId' | grep 'numberOfLaunches' | awk '{print \$3}'"]);
          if (cfprefsResult.exitCode == 0 && (cfprefsResult.stdout as String).trim().isNotEmpty) {
            appInfo['launchCount'] = (cfprefsResult.stdout as String).trim();
          }
        }
      } catch (e) {
        // 无法获取启动次数，忽略
      }
      
      // 获取应用依赖库信息
      final dependenciesResult = await Process.run('otool', ['-L', '$appPath/Contents/MacOS/${appInfo['name']}']);
      if (dependenciesResult.exitCode == 0) {
        final String output = dependenciesResult.stdout as String;
        final List<String> dependencies = LineSplitter.split(output)
            .where((line) => !line.contains(':') && line.trim().isNotEmpty)
            .map((line) => line.trim())
            .toList();
        
        if (dependencies.isNotEmpty) {
          appInfo['dependencies'] = dependencies;
        }
      }
    } catch (e) {
      // 获取额外信息出错，忽略
    }
  }
  
  /// 打印完整的应用信息
  void _printFullAppInfo(Map<String, dynamic> appInfo) {
    stdout.writeln('📱 ${appInfo['name']}');
    stdout.writeln('──────────────────────────────────────────────');
    
    if (appInfo.containsKey('displayName') && appInfo['displayName'] != null && 
        appInfo['displayName'] != appInfo['name']) {
      stdout.writeln('📋 显示名称: ${appInfo['displayName']}');
    }
    
    if (appInfo.containsKey('bundleId')) {
      stdout.writeln('🆔 包ID: ${appInfo['bundleId']}');
    }
    
    if (appInfo.containsKey('version')) {
      stdout.writeln('🔢 版本: ${appInfo['version']}');
    }
    
    if (appInfo.containsKey('size')) {
      stdout.writeln('💾 占用空间: ${appInfo['size']}');
    }
    
    stdout.writeln('📂 安装位置: ${appInfo['path']}');
    
    if (appInfo.containsKey('lastUsed')) {
      stdout.writeln('🕒 上次使用: ${appInfo['lastUsed']}');
    }
    
    if (appInfo.containsKey('created')) {
      stdout.writeln('📅 安装时间: ${appInfo['created']}');
    }
    
    if (appInfo.containsKey('architecture')) {
      stdout.writeln('🏗️ 架构: ${appInfo['architecture']}');
    }
    
    if (appInfo.containsKey('minOSVersion')) {
      stdout.writeln('🔒 最低系统要求: ${appInfo['minOSVersion']}');
    }
    
    if (appInfo.containsKey('signedBy')) {
      stdout.writeln('✅ 签名者: ${appInfo['signedBy']}');
    }
    
    if (appInfo.containsKey('teamId')) {
      stdout.writeln('👥 开发团队ID: ${appInfo['teamId']}');
    }
    
    if (appInfo.containsKey('gatekeeperStatus')) {
      stdout.writeln('🛡️ 公证状态: ${appInfo['gatekeeperStatus']}');
    }
    
    if (appInfo.containsKey('launchCount')) {
      stdout.writeln('🚀 启动次数: ${appInfo['launchCount']}');
    }
    
    if (appInfo.containsKey('hasEntitlements') && appInfo['hasEntitlements'] == true) {
      stdout.writeln('🔑 权限: 应用有特殊权限和授权');
    }
    
    if (appInfo.containsKey('dependencies')) {
      stdout.writeln('\n📚 依赖库 (前5个):');
      int count = 0;
      for (final dep in appInfo['dependencies'] as List<String>) {
        if (count >= 5) break;
        stdout.writeln('  - $dep');
        count++;
      }
      
      if ((appInfo['dependencies'] as List<String>).length > 5) {
        stdout.writeln('  ... 共${(appInfo['dependencies'] as List<String>).length}个依赖库');
      }
    }
    
    stdout.writeln('──────────────────────────────────────────────');
  }
  
  /// 列出Homebrew安装的应用程序
  Future<int> _listHomebrewApps(String? searchTerm, bool onlyCount, bool detailed) async {
    try {
      Log.info('正在查询通过Homebrew安装的应用程序...');
      
      // 检查是否安装了Homebrew
      final brewResult = await Process.run('which', ['brew']);
      if (brewResult.exitCode != 0) {
        Log.error('未安装Homebrew，请先安装Homebrew');
        return ExitCode.unavailable.code;
      }
      
      // 获取所有已安装的formula和casks
      final formulaResult = await Process.run('brew', ['list', '--formula']);
      final caskResult = await Process.run('brew', ['list', '--cask']);
      
      final List<String> formulas = LineSplitter.split(formulaResult.stdout as String)
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      
      final List<String> casks = LineSplitter.split(caskResult.stdout as String)
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      
      // 过滤搜索结果
      if (searchTerm != null && searchTerm.isNotEmpty) {
        formulas.removeWhere(
            (formula) => !formula.toLowerCase().contains(searchTerm.toLowerCase()));
        casks.removeWhere(
            (cask) => !cask.toLowerCase().contains(searchTerm.toLowerCase()));
      }
      
      if (onlyCount) {
        final int totalCount = formulas.length + casks.length;
        Log.success('Homebrew已安装应用总数: $totalCount (公式: ${formulas.length}, 软件包: ${casks.length})');
        return ExitCode.success.code;
      }
      
      // 输出结果
      if (formulas.isEmpty && casks.isEmpty) {
        Log.info('未找到符合条件的Homebrew应用');
      } else {
        if (formulas.isNotEmpty) {
          Log.success('Homebrew Formulas (共${formulas.length}个):');
          for (final formula in formulas) {
            if (detailed) {
              // 获取详细信息
              final infoResult = await Process.run('brew', ['info', '--json=v2', formula]);
              if (infoResult.exitCode == 0) {
                try {
                  final infoJson = jsonDecode(infoResult.stdout as String);
                  final formulaInfo = infoJson['formulae'][0];
                  final version = formulaInfo['versions']['stable'];
                  final desc = formulaInfo['desc'] ?? '无描述';
                  final installedSize = formulaInfo['installed'][0]['installed_as_dependency'] ? 
                      '作为依赖安装' : '${(formulaInfo['installed'][0]['installed_on_request'] as bool) ? '手动安装' : '自动安装'}';
                  final installedPath = formulaInfo['installed'][0]['path'] ?? '未知';
                  
                  stdout.writeln('- $formula (版本: $version)');
                  stdout.writeln('  描述: $desc');
                  stdout.writeln('  安装方式: $installedSize');
                  stdout.writeln('  安装路径: $installedPath');
                  
                  // 获取磁盘占用
                  final diskResult = await Process.run('du', ['-sh', installedPath]);
                  if (diskResult.exitCode == 0) {
                    final size = (diskResult.stdout as String).split('\t').first;
                    stdout.writeln('  占用空间: $size');
                  }
                  
                  // 获取依赖
                  if (formulaInfo['dependencies'] != null && (formulaInfo['dependencies'] as List).isNotEmpty) {
                    stdout.writeln('  依赖项: ${(formulaInfo['dependencies'] as List).join(', ')}');
                  }
                  
                  stdout.writeln('');
                } catch (e) {
                  stdout.writeln('- $formula (无法获取详细信息)');
                }
              } else {
                stdout.writeln('- $formula');
              }
            } else {
              stdout.writeln('- $formula');
            }
          }
        }
        
        if (casks.isNotEmpty) {
          Log.success('Homebrew Casks (共${casks.length}个):');
          for (final cask in casks) {
            if (detailed) {
              // 获取详细信息
              final infoResult = await Process.run('brew', ['info', '--json=v2', '--cask', cask]);
              if (infoResult.exitCode == 0) {
                try {
                  final infoJson = jsonDecode(infoResult.stdout as String);
                  final caskInfo = infoJson['casks'][0];
                  final version = caskInfo['version'];
                  final desc = caskInfo['desc'] ?? '无描述';
                  final homepage = caskInfo['homepage'] ?? '无主页';
                  
                  stdout.writeln('- $cask (版本: $version)');
                  stdout.writeln('  描述: $desc');
                  stdout.writeln('  主页: $homepage');
                  
                  // 获取安装应用路径
                  if (caskInfo['artifacts'] != null) {
                    for (final artifact in caskInfo['artifacts']) {
                      if (artifact is List && artifact.isNotEmpty && artifact[0].toString().endsWith('.app')) {
                        final String appPath = '/Applications/${artifact[0]}';
                        stdout.writeln('  应用路径: $appPath');
                        
                        // 获取磁盘占用
                        if (await Directory(appPath).exists()) {
                          final diskResult = await Process.run('du', ['-sh', appPath]);
                          if (diskResult.exitCode == 0) {
                            final size = (diskResult.stdout as String).split('\t').first;
                            stdout.writeln('  占用空间: $size');
                          }
                        }
                        break;
                      }
                    }
                  }
                  
                  stdout.writeln('');
                } catch (e) {
                  stdout.writeln('- $cask (无法获取详细信息)');
                }
              } else {
                stdout.writeln('- $cask');
              }
            } else {
              stdout.writeln('- $cask');
            }
          }
        }
      }
      
      return ExitCode.success.code;
    } catch (e) {
      Log.error('查询Homebrew应用时出错: $e');
      return ExitCode.software.code;
    }
  }
  
  /// 列出Mac App Store安装的应用程序
  Future<int> _listMacAppStoreApps(String? searchTerm, bool onlyCount, bool detailed) async {
    try {
      Log.info('正在查询通过Mac App Store安装的应用程序...');
      
      // 检查是否安装了 -cli
      final masResult = await Process.run('which', ['mas']);
      if (masResult.exitCode != 0) {
        Log.error('未安装mas-cli工具，请先执行: brew install mas');
        return ExitCode.unavailable.code;
      }
      
      // 获取所有已安装的Mac App Store应用
      final listResult = await Process.run('mas', ['list']);
      if (listResult.exitCode != 0) {
        Log.error('获取Mac App Store应用列表失败');
        return ExitCode.software.code;
      }
      
      final List<String> lines = LineSplitter.split(listResult.stdout as String)
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      
      final List<Map<String, String>> masApps = [];
      
      // 解析应用信息
      for (final line in lines) {
        // 格式: 应用ID 应用名 (版本号)
        final match = RegExp(r'(\d+)\s+(.+)\s+\((.+)\)').firstMatch(line);
        if (match != null) {
          masApps.add({
            'id': match.group(1)!,
            'name': match.group(2)!,
            'version': match.group(3)!,
          });
        }
      }
      
      // 过滤搜索结果
      if (searchTerm != null && searchTerm.isNotEmpty) {
        masApps.removeWhere((app) => 
            !app['name']!.toLowerCase().contains(searchTerm.toLowerCase()));
      }
      
      // 按名称排序
      masApps.sort((a, b) => a['name']!.compareTo(b['name']!));
      
      if (onlyCount) {
        Log.success('Mac App Store已安装应用总数: ${masApps.length}');
        return ExitCode.success.code;
      }
      
      // 输出结果
      if (masApps.isEmpty) {
        Log.info('未找到符合条件的Mac App Store应用');
      } else {
        Log.success('Mac App Store应用列表 (共${masApps.length}个):');
        for (final app in masApps) {
          if (detailed) {
            // 尝试查找应用的路径
            String? appPath;
            final findResult = await Process.run('find', ['/Applications', '-name', '*.app', '-maxdepth', '1']);
            if (findResult.exitCode == 0) {
              final appPaths = LineSplitter.split(findResult.stdout as String)
                  .map((line) => line.trim())
                  .where((line) => line.isNotEmpty)
                  .toList();
              
              for (final path in appPaths) {
                // 读取Info.plist来确认应用ID
                final plistPath = '$path/Contents/Info.plist';
                if (await File(plistPath).exists()) {
                  final plistResult = await Process.run('plutil', ['-convert', 'json', '-o', '-', plistPath]);
                  if (plistResult.exitCode == 0) {
                    try {
                      final Map<String, dynamic> plistInfo = jsonDecode(plistResult.stdout as String);
                      if (plistInfo.containsKey('CFBundleIdentifier')) {
                        final String bundleId = plistInfo['CFBundleIdentifier'];
                        // 通过mas info查询应用ID对应的bundleID
                        final masInfoResult = await Process.run('mas', ['info', app['id']!]);
                        if (masInfoResult.exitCode == 0 && (masInfoResult.stdout as String).contains(bundleId)) {
                          appPath = path;
                          break;
                        }
                      }
                    } catch (e) {
                      // 解析错误，忽略
                    }
                  }
                }
              }
            }
            
            stdout.writeln('- ${app['name']} (版本: ${app['version']}, ID: ${app['id']})');
            
            if (appPath != null) {
              stdout.writeln('  应用路径: $appPath');
              
              // 获取磁盘占用
              final diskResult = await Process.run('du', ['-sh', appPath]);
              if (diskResult.exitCode == 0) {
                final size = (diskResult.stdout as String).split('\t').first;
                stdout.writeln('  占用空间: $size');
              }
              
              // 获取上次使用时间
              final mdlsResult = await Process.run('mdls', ['-name', 'kMDItemLastUsedDate', appPath]);
              if (mdlsResult.exitCode == 0) {
                final String output = mdlsResult.stdout as String;
                final lastUsedMatch = RegExp(r'kMDItemLastUsedDate\s+=\s+(.+)').firstMatch(output);
                if (lastUsedMatch != null) {
                  stdout.writeln('  上次使用: ${lastUsedMatch.group(1)?.trim()}');
                }
              }
            }
            
            // 获取应用更多信息
            final masInfoResult = await Process.run('mas', ['info', app['id']!]);
            if (masInfoResult.exitCode == 0) {
              final String output = masInfoResult.stdout as String;
              final categoryMatch = RegExp(r'Category:\s+(.+)').firstMatch(output);
              if (categoryMatch != null) {
                stdout.writeln('  分类: ${categoryMatch.group(1)}');
              }
              
              final developerMatch = RegExp(r'Developer:\s+(.+)').firstMatch(output);
              if (developerMatch != null) {
                stdout.writeln('  开发者: ${developerMatch.group(1)}');
              }
            }
            
            stdout.writeln('');
          } else {
            stdout.writeln('- ${app['name']}');
          }
        }
      }
      
      return ExitCode.success.code;
    } catch (e) {
      Log.error('查询Mac App Store应用时出错: $e');
      return ExitCode.software.code;
    }
  }

  /// 检查应用更新
  Future<int> _checkForUpdates(String? searchTerm) async {
    Log.info('正在检查应用更新...');
    
    bool foundUpdates = false;
    
    // 1. 检查Homebrew应用更新
    try {
      final brewResult = await Process.run('which', ['brew']);
      if (brewResult.exitCode == 0) {
        Log.info('检查Homebrew应用更新...');
        
        // 检查formula更新
        final outdatedResult = await Process.run('brew', ['outdated', '--formula']);
        if (outdatedResult.exitCode == 0) {
          final List<String> outdatedFormulas = LineSplitter.split(outdatedResult.stdout as String)
              .map((line) => line.trim())
              .where((line) => line.isNotEmpty)
              .toList();
          
          // 过滤搜索结果
          if (searchTerm != null && searchTerm.isNotEmpty) {
            outdatedFormulas.removeWhere(
                (formula) => !formula.toLowerCase().contains(searchTerm.toLowerCase()));
          }
          
          if (outdatedFormulas.isNotEmpty) {
            foundUpdates = true;
            Log.success('可更新的Homebrew Formula (共${outdatedFormulas.length}个):');
            for (final formula in outdatedFormulas) {
              // 获取当前版本和最新版本
              final infoResult = await Process.run('brew', ['info', '--json=v2', formula]);
              if (infoResult.exitCode == 0) {
                try {
                  final infoJson = jsonDecode(infoResult.stdout as String);
                  final formulaInfo = infoJson['formulae'][0];
                  final currentVersion = formulaInfo['installed'][0]['version'];
                  final latestVersion = formulaInfo['versions']['stable'];
                  stdout.writeln('- $formula (当前: $currentVersion → 最新: $latestVersion)');
                } catch (e) {
                  stdout.writeln('- $formula');
                }
              } else {
                stdout.writeln('- $formula');
              }
            }
            stdout.writeln('');
            stdout.writeln('更新命令: brew upgrade [formula名称]');
            stdout.writeln('');
          } else {
            Log.info('所有Homebrew Formula均为最新版本');
          }
        }
        
        // 检查cask更新
        final outdatedCasksResult = await Process.run('brew', ['outdated', '--cask']);
        if (outdatedCasksResult.exitCode == 0) {
          final List<String> outdatedCasks = LineSplitter.split(outdatedCasksResult.stdout as String)
              .map((line) => line.trim())
              .where((line) => line.isNotEmpty)
              .toList();
          
          // 过滤搜索结果
          if (searchTerm != null && searchTerm.isNotEmpty) {
            outdatedCasks.removeWhere(
                (cask) => !cask.toLowerCase().contains(searchTerm.toLowerCase()));
          }
          
          if (outdatedCasks.isNotEmpty) {
            foundUpdates = true;
            Log.success('可更新的Homebrew Cask (共${outdatedCasks.length}个):');
            for (final cask in outdatedCasks) {
              // 获取当前版本和最新版本
              final infoResult = await Process.run('brew', ['info', '--json=v2', '--cask', cask]);
              if (infoResult.exitCode == 0) {
                try {
                  final infoJson = jsonDecode(infoResult.stdout as String);
                  final caskInfo = infoJson['casks'][0];
                  final currentVersion = caskInfo['installed'];
                  final latestVersion = caskInfo['version'];
                  stdout.writeln('- $cask (当前: $currentVersion → 最新: $latestVersion)');
                } catch (e) {
                  stdout.writeln('- $cask');
                }
              } else {
                stdout.writeln('- $cask');
              }
            }
            stdout.writeln('');
            stdout.writeln('更新命令: brew upgrade --cask [cask名称]');
            stdout.writeln('');
          } else {
            Log.info('所有Homebrew Cask均为最新版本');
          }
        }
      }
    } catch (e) {
      Log.error('检查Homebrew更新时出错: $e');
    }
    
    // 2. 检查Mac App Store应用更新
    try {
      final masResult = await Process.run('which', ['mas']);
      if (masResult.exitCode == 0) {
        Log.info('检查Mac App Store应用更新...');
        
        final outdatedResult = await Process.run('mas', ['outdated']);
        if (outdatedResult.exitCode == 0) {
          final List<String> lines = LineSplitter.split(outdatedResult.stdout as String)
              .map((line) => line.trim())
              .where((line) => line.isNotEmpty)
              .toList();
          
          final List<Map<String, String>> outdatedApps = [];
          
          // 解析更新信息
          for (final line in lines) {
            // 格式: 应用ID 应用名 (当前版本 -> 最新版本)
            final match = RegExp(r'(\d+)\s+(.+)\s+\((.+)\s+->\s+(.+)\)').firstMatch(line);
            if (match != null) {
              outdatedApps.add({
                'id': match.group(1)!,
                'name': match.group(2)!,
                'currentVersion': match.group(3)!,
                'latestVersion': match.group(4)!,
              });
            }
          }
          
          // 过滤搜索结果
          if (searchTerm != null && searchTerm.isNotEmpty) {
            outdatedApps.removeWhere((app) => 
                !app['name']!.toLowerCase().contains(searchTerm.toLowerCase()));
          }
          
          if (outdatedApps.isNotEmpty) {
            foundUpdates = true;
            Log.success('可更新的Mac App Store应用 (共${outdatedApps.length}个):');
            for (final app in outdatedApps) {
              stdout.writeln('- ${app['name']} (当前: ${app['currentVersion']} → 最新: ${app['latestVersion']})');
            }
            stdout.writeln('');
            stdout.writeln('更新命令: mas upgrade [应用ID] 或在App Store中更新');
            stdout.writeln('');
          } else {
            Log.info('所有Mac App Store应用均为最新版本');
          }
        }
      }
    } catch (e) {
      Log.error('检查Mac App Store更新时出错: $e');
    }
    
    // 3. 检查其他常见应用更新
    try {
      Log.info('检查其他常见应用更新...');
      
      // 获取安装的应用列表
      final List<FileSystemEntity> mainApps = await _getApplications('/Applications');
      final List<FileSystemEntity> userApps = await _getApplications('${Platform.environment['HOME']}/Applications');
      final List<FileSystemEntity> allApps = [...mainApps, ...userApps];
      
      // 检查主要应用的更新
      List<Map<String, dynamic>> updatableApps = [];
      
      // 应用及其检查更新的方法
      final appsToCheck = [
        {'name': 'Google Chrome', 'bundleId': 'com.google.Chrome', 'checkMethod': 'api'},
        {'name': 'Visual Studio Code', 'bundleId': 'com.microsoft.VSCode', 'checkMethod': 'api'},
        {'name': 'Firefox', 'bundleId': 'org.mozilla.firefox', 'checkMethod': 'api'},
      ];
      
      for (final appToCheck in appsToCheck) {
        // 尝试找到这个应用
        FileSystemEntity? appEntity;
        for (final app in allApps) {
          final String basename = p.basename(app.path);
          if (basename.endsWith('.app')) {
            final String appName = basename.substring(0, basename.length - 4);
            if (appName == appToCheck['name'] || 
                appName.toLowerCase().contains((appToCheck['name'] as String).toLowerCase())) {
              appEntity = app;
              break;
            }
          }
        }
        
        // 如果找到应用，检查更新
        if (appEntity != null) {
          // 如果有搜索词，检查是否匹配
          if (searchTerm != null && searchTerm.isNotEmpty && 
              !appToCheck['name'].toString().toLowerCase().contains(searchTerm.toLowerCase())) {
            continue;
          }
          
          final appPath = appEntity.path;
          String? currentVersion;
          
          // 获取当前版本
          final plistPath = '$appPath/Contents/Info.plist';
          if (await File(plistPath).exists()) {
            final plistResult = await Process.run('plutil', ['-convert', 'json', '-o', '-', plistPath]);
            if (plistResult.exitCode == 0) {
              try {
                final Map<String, dynamic> plistInfo = jsonDecode(plistResult.stdout as String);
                currentVersion = plistInfo['CFBundleShortVersionString'] ?? plistInfo['CFBundleVersion'];
              } catch (e) {
                // 解析错误，忽略
              }
            }
          }
          
          if (currentVersion != null) {
            String? latestVersion;
            
            // 根据不同的应用使用不同的方法获取最新版本
            if (appToCheck['name'] == 'Google Chrome') {
              latestVersion = await _getLatestChromeVersion();
            } else if (appToCheck['name'] == 'Visual Studio Code') {
              latestVersion = await _getLatestVSCodeVersion();
            } else if (appToCheck['name'] == 'Firefox') {
              latestVersion = await _getLatestFirefoxVersion();
            }
            
            if (latestVersion != null && latestVersion != currentVersion) {
              updatableApps.add({
                'name': appToCheck['name'],
                'currentVersion': currentVersion,
                'latestVersion': latestVersion,
              });
            }
          }
        }
      }
      
      if (updatableApps.isNotEmpty) {
        foundUpdates = true;
        Log.success('可更新的其他应用 (共${updatableApps.length}个):');
        for (final app in updatableApps) {
          stdout.writeln('- ${app['name']} (当前: ${app['currentVersion']} → 最新: ${app['latestVersion']})');
        }
        stdout.writeln('');
        stdout.writeln('请访问应用官网或使用应用内更新功能进行更新');
      } else {
        Log.info('检查的常见应用均为最新版本');
      }
    } catch (e) {
      Log.error('检查其他应用更新时出错: $e');
    }
    
    if (!foundUpdates) {
      Log.success('所有检查的应用均为最新版本');
    }
    
    return ExitCode.success.code;
  }
  
  /// 获取Google Chrome最新版本
  Future<String?> _getLatestChromeVersion() async {
    try {
      final response = await http.get(Uri.parse('https://chromedriver.storage.googleapis.com/LATEST_RELEASE'));
      if (response.statusCode == 200) {
        return response.body.trim();
      }
    } catch (e) {
      // 请求错误，忽略
    }
    return null;
  }
  
  /// 获取VS Code最新版本
  Future<String?> _getLatestVSCodeVersion() async {
    try {
      final response = await http.get(Uri.parse('https://update.code.visualstudio.com/api/update/darwin/stable/latest'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['productVersion'];
      }
    } catch (e) {
      // 请求错误，忽略
    }
    return null;
  }
  
  /// 获取Firefox最新版本
  Future<String?> _getLatestFirefoxVersion() async {
    try {
      final response = await http.get(Uri.parse('https://product-details.mozilla.org/1.0/firefox_versions.json'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['LATEST_FIREFOX_VERSION'];
      }
    } catch (e) {
      // 请求错误，忽略
    }
    return null;
  }
} 