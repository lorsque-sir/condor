import 'dart:async';
import 'dart:io';

import 'package:condor_cli/src/command.dart';
import 'package:condor_cli/src/common.dart';
import 'package:condor_cli/src/utils/log.dart';
import 'package:dart_console/dart_console.dart';
import 'package:path/path.dart' as p;

/// 智能文件整理命令 - 分析并整理文件夹中的文件
class FileOrgCommand extends CondorCommand {
  /// 构造函数
  FileOrgCommand() {
    argParser
      ..addOption(
        'source',
        abbr: 's',
        help: '要整理的源文件夹路径',
        defaultsTo: '${Platform.environment['HOME']}/Downloads',
      )
      ..addOption(
        'target',
        abbr: 't',
        help: '整理后的目标文件夹路径',
      )
      ..addFlag(
        'dryrun',
        abbr: 'd',
        help: '预览模式，不实际移动文件',
        negatable: false,
      )
      ..addFlag(
        'recursive',
        abbr: 'r',
        help: '递归处理子文件夹',
        negatable: false,
      )
      ..addFlag(
        'byType',
        help: '按文件类型分类（默认开启）',
        defaultsTo: true,
      )
      ..addFlag(
        'byDate',
        help: '按文件修改日期分类（年/月）',
        defaultsTo: true,
      )
      ..addOption(
        'exclude',
        abbr: 'e',
        help: '排除的文件或文件夹名称，用逗号分隔',
      )
      ..addFlag(
        'interactive',
        abbr: 'i',
        help: '交互模式，处理每个文件前询问',
        negatable: false,
      );
  }

  @override
  String get description => '智能文件整理器 - 自动分析并整理文件夹';

  @override
  String get name => 'fileorg';

  /// 控制台对象
  final _console = Console();

  /// 文件类型映射
  final Map<String, List<String>> _fileTypeMap = {
    '图片': ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'svg', 'webp', 'heic', 'heif', 'raw', 'tiff'],
    '文档': ['pdf', 'docx', 'doc', 'xlsx', 'xls', 'pptx', 'ppt', 'txt', 'rtf', 'md'],
    '视频': ['mp4', 'mov', 'avi', 'mkv', 'wmv', 'flv', 'webm', 'm4v', 'mpeg', 'mpg'],
    '音频': ['mp3', 'wav', 'flac', 'aac', 'm4a', 'ogg', 'wma'],
    '压缩包': ['zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz', 'tgz'],
    '安装包': ['dmg', 'pkg', 'exe', 'msi', 'deb', 'rpm'],
    '代码': ['js', 'py', 'java', 'c', 'cpp', 'h', 'html', 'css', 'dart', 'swift', 'kt', 'go', 'rs'],
  };

  /// 移动的文件计数
  int _movedCount = 0;
  
  /// 总文件数
  int _totalFiles = 0;
  
  /// 被排除的文件数
  int _excludedCount = 0;
  
  /// 错误文件数
  int _errorCount = 0;

  @override
  Future<int> run() async {
    try {
      final String sourcePath = stringOption('source');
      final String targetPath = stringOption('target') ?? '$sourcePath/已整理';
      final bool dryRun = boolOption('dryrun');
      final bool recursive = boolOption('recursive');
      final bool byType = boolOption('byType');
      final bool byDate = boolOption('byDate');
      final String excludeList = stringOption('exclude');
      final bool interactive = boolOption('interactive');
      
      // 解析排除列表
      final List<String> excludes = excludeList.isNotEmpty 
          ? excludeList.split(',').map((e) => e.trim()).toList() 
          : [];
      
      // 验证源文件夹
      final sourceDir = Directory(sourcePath);
      if (!await sourceDir.exists()) {
        Log.error('源文件夹 "$sourcePath" 不存在！');
        return ExitCode.unavailable.code;
      }
      
      // 确保目标文件夹存在
      final targetDir = Directory(targetPath);
      if (!dryRun && !await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }
      
      Log.info('正在分析文件夹: $sourcePath');
      
      if (dryRun) {
        Log.info('预览模式: 只显示将要执行的操作，不实际移动文件');
      }
      
      // 扫描源文件夹
      final List<FileSystemEntity> entities = await _scanDirectory(sourceDir, recursive, excludes);
      
      _totalFiles = entities.length;
      
      if (_totalFiles == 0) {
        Log.info('没有找到需要整理的文件');
        return ExitCode.success.code;
      }
      
      Log.info('找到 $_totalFiles 个文件需要整理');
      
      // 开始整理文件
      for (var entity in entities) {
        if (entity is File) {
          await _organizeFile(entity, targetPath, byType, byDate, dryRun, interactive);
        }
      }
      
      // 输出统计信息
      _printSummary(dryRun);
      
      return ExitCode.success.code;
    } catch (e) {
      Log.error('整理文件时出错: $e');
      return ExitCode.software.code;
    }
  }
  
  /// 扫描目录并返回所有需要处理的文件
  Future<List<FileSystemEntity>> _scanDirectory(
    Directory directory, 
    bool recursive, 
    List<String> excludes
  ) async {
    final List<FileSystemEntity> result = [];
    
    try {
      final List<FileSystemEntity> entities = await directory.list().toList();
      
      for (var entity in entities) {
        final basename = p.basename(entity.path);
        
        // 检查是否应该排除
        if (excludes.contains(basename)) {
          _excludedCount++;
          continue;
        }
        
        if (entity is File) {
          result.add(entity);
        } else if (entity is Directory && recursive) {
          // 排除已整理目录和隐藏目录
          if (!basename.startsWith('.') && basename != '已整理') {
            final subEntities = await _scanDirectory(entity, recursive, excludes);
            result.addAll(subEntities);
          }
        }
      }
    } catch (e) {
      Log.error('扫描目录时出错: $e');
    }
    
    return result;
  }
  
  /// 整理单个文件
  Future<void> _organizeFile(
    File file, 
    String targetBasePath, 
    bool byType, 
    bool byDate, 
    bool dryRun,
    bool interactive
  ) async {
    try {
      final String extension = p.extension(file.path).toLowerCase().replaceFirst('.', '');
      final String fileName = p.basename(file.path);
      
      // 确定文件类型目录
      String typeDir = '其他';
      if (byType) {
        for (var entry in _fileTypeMap.entries) {
          if (entry.value.contains(extension)) {
            typeDir = entry.key;
            break;
          }
        }
      }
      
      // 确定日期目录
      String dateDir = '';
      if (byDate) {
        final fileStat = await file.stat();
        final lastModified = fileStat.modified;
        dateDir = '${lastModified.year}/${lastModified.month.toString().padLeft(2, '0')}';
      }
      
      // 构建目标路径
      final List<String> pathSegments = [];
      if (byType) pathSegments.add(typeDir);
      if (byDate) pathSegments.add(dateDir);
      
      final String relativePath = p.joinAll(pathSegments);
      final String targetDirPath = p.join(targetBasePath, relativePath);
      final String targetFilePath = p.join(targetDirPath, fileName);
      
      // 如果是交互模式，询问用户是否移动此文件
      if (interactive && !dryRun) {
        _console.clearScreen();
        _console.resetCursorPosition();
        
        _console.setForegroundColor(ConsoleColor.brightCyan);
        _console.writeLine('文件整理 - 交互模式');
        _console.writeLine('─────────────────────────────────────────────────');
        _console.resetColorAttributes();
        
        _console.writeLine('正在处理: $fileName');
        _console.writeLine('');
        _console.writeLine('类型: $typeDir');
        if (byDate) _console.writeLine('日期: $dateDir');
        _console.writeLine('');
        _console.writeLine('将移动到: $targetFilePath');
        _console.writeLine('');
        
        _console.setForegroundColor(ConsoleColor.brightYellow);
        _console.write('是否移动此文件? (y/n/q): ');
        _console.resetColorAttributes();
        
        // 读取用户输入
        final input = stdin.readLineSync()?.toLowerCase() ?? '';
        
        if (input == 'q') {
          Log.info('用户取消操作，退出程序');
          exit(0);
        } else if (input != 'y') {
          Log.info('跳过文件: $fileName');
          _excludedCount++;
          return;
        }
      }
      
      if (dryRun) {
        Log.info('将移动: $fileName -> $targetFilePath');
        _movedCount++;
      } else {
        // 确保目标目录存在
        final targetDir = Directory(targetDirPath);
        if (!await targetDir.exists()) {
          await targetDir.create(recursive: true);
        }
        
        // 检查目标文件是否已存在
        final targetFile = File(targetFilePath);
        if (await targetFile.exists()) {
          // 生成唯一文件名
          final String newFileName = _generateUniqueFileName(fileName);
          final String newTargetPath = p.join(targetDirPath, newFileName);
          
          Log.info('文件已存在，重命名为: $newFileName');
          await file.copy(newTargetPath);
        } else {
          // 移动文件
          await file.copy(targetFilePath);
        }
        
        // 删除原文件
        await file.delete();
        
        Log.info('已移动: $fileName -> $targetFilePath');
        _movedCount++;
      }
    } catch (e) {
      Log.error('处理文件 ${p.basename(file.path)} 时出错: $e');
      _errorCount++;
    }
  }
  
  /// 生成唯一的文件名
  String _generateUniqueFileName(String originalName) {
    final extension = p.extension(originalName);
    final nameWithoutExtension = p.basenameWithoutExtension(originalName);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    
    return '$nameWithoutExtension($timestamp)$extension';
  }
  
  /// 打印汇总信息
  void _printSummary(bool dryRun) {
    final action = dryRun ? '将要移动' : '已移动';
    
    _console.setForegroundColor(ConsoleColor.brightGreen);
    _console.writeLine('');
    _console.writeLine('整理完成!');
    _console.writeLine('─────────────────────────────────────────────────');
    _console.resetColorAttributes();
    
    _console.writeLine('总文件数: $_totalFiles');
    _console.writeLine('$action: $_movedCount');
    
    if (_excludedCount > 0) {
      _console.writeLine('已排除: $_excludedCount');
    }
    
    if (_errorCount > 0) {
      _console.setForegroundColor(ConsoleColor.brightRed);
      _console.writeLine('处理失败: $_errorCount');
      _console.resetColorAttributes();
    }
  }
} 