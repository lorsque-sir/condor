import 'dart:convert';
import 'dart:io';

import 'package:condor_cli/src/command.dart';
import 'package:condor_cli/src/common.dart';
import 'package:condor_cli/src/utils/log.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:path/path.dart' as p;
import 'package:http/http.dart' as http;

/// API源配置
class ApiSource {
  /// 名称
  final String name;
  
  /// API端点
  final String endpoint;
  
  /// API密钥
  final String key;
  
  /// 构造函数
  ApiSource({
    required this.name,
    required this.endpoint,
    required this.key,
  });
  
  /// 从JSON创建
  factory ApiSource.fromJson(Map<String, dynamic> json) {
    return ApiSource(
      name: json['name'] as String,
      endpoint: json['endpoint'] as String,
      key: json['key'] as String,
    );
  }
  
  /// 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'endpoint': endpoint,
      'key': key,
    };
  }
}

/// AI配置命令 - 管理API密钥和模型设置
class AiConfigCommand extends CondorCommand {
  /// 构造函数
  AiConfigCommand() {
    argParser
      ..addOption(
        'model',
        abbr: 'm',
        help: '设置默认AI模型 (openai, claude, grok)',
        allowed: ['openai', 'claude', 'grok'],
      )
      ..addOption(
        'source',
        help: '为指定模型添加/选择API源 (格式: [model]:[source_name])',
      )
      ..addOption(
        'use-source',
        help: '设置模型使用的API源 (格式: [model]:[source_name])',
      )
      ..addOption(
        'endpoint',
        help: '设置API源端点URL (与--source一起使用)',
      )
      ..addOption(
        'key',
        help: '设置API源密钥 (与--source一起使用)',
      )
      ..addOption(
        'openai-model',
        help: '设置OpenAI模型 (默认: gpt-4o)',
        defaultsTo: 'gpt-4o',
      )
      ..addOption(
        'claude-model',
        help: '设置Claude模型 (默认: claude-3-opus-20240229)',
        defaultsTo: 'claude-3-opus-20240229',
      )
      ..addOption(
        'grok-model',
        help: '设置Grok模型 (默认: grok-1)',
        defaultsTo: 'grok-1',
      )
      ..addFlag(
        'list',
        abbr: 'l',
        help: '列出当前配置',
        negatable: false,
      )
      ..addFlag(
        'list-sources',
        help: '列出指定模型的所有API源',
        negatable: false,
      )
      ..addFlag(
        'delete-source',
        help: '删除指定的API源 (需与--source一起使用)',
        negatable: false,
      )
      ..addFlag(
        'reset',
        abbr: 'r',
        help: '重置所有配置',
        negatable: false,
      )
      ..addFlag(
        'scan-models',
        help: '扫描API源支持的模型（需要先使用--source配置源）',
        negatable: false,
      )
      ..addOption(
        'scan-models-source',
        help: '指定要扫描模型的API源 (格式: [model]:[source_name])',
      )
      ..addFlag(
        'add-all-models',
        help: '添加扫描到的所有模型到配置中 (与--scan-models一起使用)',
        negatable: false,
      );
  }

  @override
  String get description => '配置AI设置 - 管理API密钥和默认模型';

  @override
  String get name => 'config';
  
  @override
  String get usageFooter => '''
示例:
  # 添加API源
  condor-ai config --source=openai:default --key="您的API密钥"
  
  # 添加自定义源
  condor-ai config --source=openai:custom --key="您的API密钥" --endpoint="https://api.自定义域名.com/v1"
  
  # 扫描源支持的模型
  condor-ai config --scan-models-source=openai:default
  
  # 一步完成源配置并扫描模型
  condor-ai config --source=openai:default --key="您的API密钥" --scan-models
  
  # 扫描当前活跃源支持的模型
  condor-ai config --scan-models
  
  # 设置默认模型
  condor-ai config --model=openai
  condor-ai config --openai-model="gpt-4"
  
  # 列出配置信息
  condor-ai config --list
  condor-ai config --list-sources --source=openai:default
''';
  
  /// 配置文件路径
  String get _configPath {
    final home = Platform.environment['HOME'] ?? '';
    return p.join(home, '.condor', 'ai_config.json');
  }
  
  /// 加密密钥
  final _encryptKey = encrypt.Key.fromUtf8('ConDorAiKeY12345ConDorAiKeY12345');
  
  @override
  Future<int> run() async {
    try {
      final bool showList = boolOption('list');
      final bool showSources = boolOption('list-sources');
      final bool deleteSource = boolOption('delete-source');
      final bool resetConfig = boolOption('reset');
      final bool addAllModels = boolOption('add-all-models');
      final bool shouldScanModels = boolOption('scan-models');
      final String scanModelsSource = stringOption('scan-models-source');
      final String sourceOption = stringOption('source');
      final String keyOption = stringOption('key');
      final String endpointOption = stringOption('endpoint');
      
      // 创建配置目录
      final configDir = Directory(p.dirname(_configPath));
      if (!await configDir.exists()) {
        await configDir.create(recursive: true);
      }
      
      // 重置配置
      if (resetConfig) {
        return await _resetConfig();
      }
      
      // 读取现有配置
      final config = await readConfig();

      // 处理源配置 - 移到扫描模型处理之前，确保可以在同一命令中添加源并扫描模型
      bool updated = false;
      String modelTypeForScan = '';
      String sourceNameForScan = '';
      
      if (results.wasParsed('source')) {
        final parts = sourceOption.split(':');
        if (parts.length != 2) {
          Log.error('源格式错误，应为 "model:source_name"');
          return ExitCode.usage.code;
        }
        
        final modelType = parts[0];
        final sourceName = parts[1];
        
        if (!['openai', 'claude', 'grok'].contains(modelType)) {
          Log.error('不支持的模型类型: $modelType');
          return ExitCode.usage.code;
        }
        
        // 记录当前正在操作的源，以便后续可能的扫描模型操作
        modelTypeForScan = modelType;
        sourceNameForScan = sourceName;
        
        // 删除源
        if (deleteSource) {
          updated = _deleteSource(config, modelType, sourceName);
        } 
        // 添加/更新源
        else if (results.wasParsed('key') || results.wasParsed('endpoint')) {
          if (!results.wasParsed('endpoint')) {
            // 使用默认端点
            updated = _addOrUpdateSource(config, modelType, sourceName, 
                _getDefaultEndpoint(modelType), keyOption);
          } else {
            updated = _addOrUpdateSource(config, modelType, sourceName, 
                endpointOption, keyOption);
          }
          
          // 如果源刚刚添加或更新成功，并且同时指定了扫描模型，准备稍后扫描
          if (updated && shouldScanModels) {
            Log.success('已成功配置源信息，即将扫描可用模型...');
            
            // 保存配置，确保扫描模型时可以读取到最新的配置
            await _saveConfig(config);
          }
        }
      }
      
      // 处理扫描模型选项
      if (scanModelsSource.isNotEmpty || (shouldScanModels && modelTypeForScan.isNotEmpty)) {
        String modelType, sourceName;
        
        // 使用scan-models-source指定的源，或者使用刚才通过--source配置的源
        if (scanModelsSource.isNotEmpty) {
          final parts = scanModelsSource.split(':');
          if (parts.length != 2) {
            Log.error('模型源格式错误，应为 "model:source_name"');
            Log.info('正确格式示例: --scan-models-source=openai:default');
            return ExitCode.usage.code;
          }
          modelType = parts[0];
          sourceName = parts[1];
        } else if (modelTypeForScan.isNotEmpty && sourceNameForScan.isNotEmpty) {
          // 使用刚才添加/更新的源信息
          modelType = modelTypeForScan;
          sourceName = sourceNameForScan;
          Log.info('使用刚才配置的源: $modelType:$sourceName 扫描模型');
        } else {
          // 没有指定源，尝试使用默认活跃源
          final defaultModel = config['default_model'] ?? 'openai';
          final activeSource = config['${defaultModel}_active_source'] as String?;
          
          if (activeSource == null || activeSource.isEmpty) {
            Log.error('未指定要扫描的源，且没有默认活跃源');
            Log.info('请指定源: --source=model:name 或 --scan-models-source=model:name');
            return ExitCode.usage.code;
          }
          
          modelType = defaultModel;
          sourceName = activeSource;
          Log.info('未指定源，使用默认活跃源: $modelType:$sourceName');
        }
        
        if (!['openai', 'claude', 'grok'].contains(modelType)) {
          Log.error('不支持的模型类型: $modelType');
          return ExitCode.usage.code;
        }
        
        // 验证源是否存在
        if (!_sourceExists(config, modelType, sourceName)) {
          Log.error('源 "$sourceName" 在模型 "$modelType" 中不存在');
          Log.info('请先使用以下命令添加源:\ncondor-ai config --source=$modelType:$sourceName --key="您的密钥" [--endpoint="API端点"]');
          return ExitCode.usage.code;
        }

        // 验证源是否有密钥
        final sourceData = _getSourceData(config, modelType, sourceName);
        if (sourceData == null) {
          Log.error('无法获取源 "$sourceName" 的数据');
          return ExitCode.software.code;
        }
        
        final apiKey = decryptValue(sourceData['key'] ?? '');
        if (apiKey.isEmpty) {
          Log.error('源 "$sourceName" 没有设置API密钥');
          Log.info('请使用以下命令设置密钥:\ncondor-ai config --source=$modelType:$sourceName --key="您的密钥"');
          return ExitCode.usage.code;
        }
        
        // 扫描模型
        final models = await scanModels(modelType, sourceName, config);
        
        if (models.isEmpty) {
          Log.warning('未检测到任何可用模型');
          return ExitCode.success.code;
        }
        
        // 显示模型列表
        Log.success('检测到的可用模型:');
        for (int i = 0; i < models.length; i++) {
          stdout.writeln('${i + 1}. ${models[i]}');
        }
        
        // 如果指定了添加所有模型选项
        if (addAllModels) {
          Log.info('将所有模型添加到配置中...');
          
          // 将模型列表添加到配置中
          config['${modelType}_available_models'] = models;
          
          // 更新默认模型（如果尚未设置）
          if ((config['${modelType}_model'] ?? '').isEmpty && models.isNotEmpty) {
            config['${modelType}_model'] = models[0];
            Log.info('已将默认${_getModelName(modelType)}模型设置为: ${models[0]}');
          }
          
          // 保存配置
          await _saveConfig(config);
          Log.success('已将所有模型添加到配置中');
        } else {
          // 交互式选择模型
          stdout.write('请选择要设置的默认模型 (1-${models.length}，输入0使用第一个): ');
          final choice = stdin.readLineSync();
          int selectedIndex;
          
          try {
            selectedIndex = int.parse(choice ?? '0');
            if (selectedIndex < 0 || selectedIndex > models.length) {
              throw FormatException('选择超出范围');
            }
          } catch (e) {
            selectedIndex = 0; // 默认使用第一个
          }
          
          final selectedModel = selectedIndex == 0 ? models[0] : models[selectedIndex - 1];
          
          // 将所有模型添加到配置中
          config['${modelType}_available_models'] = models;
          
          // 设置选择的模型
          config['${modelType}_model'] = selectedModel;
          
          // 保存配置
          await _saveConfig(config);
          Log.success('已将${_getModelName(modelType)}模型设置为: $selectedModel');
        }
        
        return ExitCode.success.code;
      }
      
      // 更新配置（源配置处理已移到前面）
      
      // 设置使用的源
      if (results.wasParsed('use-source')) {
        final sourceSpec = stringOption('use-source');
        final parts = sourceSpec.split(':');
        if (parts.length != 2) {
          Log.error('源格式错误，应为 "model:source_name"');
          return ExitCode.usage.code;
        }
        
        final modelType = parts[0];
        final sourceName = parts[1];
        
        if (!['openai', 'claude', 'grok'].contains(modelType)) {
          Log.error('不支持的模型类型: $modelType');
          return ExitCode.usage.code;
        }
        
        // 验证源是否存在
        if (!_sourceExists(config, modelType, sourceName)) {
          Log.error('源 "$sourceName" 在模型 "$modelType" 中不存在');
          return ExitCode.usage.code;
        }
        
        config['${modelType}_active_source'] = sourceName;
        updated = true;
      }
      
      if (results.wasParsed('model')) {
        config['default_model'] = stringOption('model');
        updated = true;
      }
      
      // 兼容旧版配置的特殊处理
      _handleLegacyConfig(config);
      
      if (results.wasParsed('openai-model')) {
        config['openai_model'] = stringOption('openai-model');
        updated = true;
      }
      
      if (results.wasParsed('claude-model')) {
        config['claude_model'] = stringOption('claude-model');
        updated = true;
      }
      
      if (results.wasParsed('grok-model')) {
        config['grok_model'] = stringOption('grok-model');
        updated = true;
      }
      
      // 保存配置
      if (updated) {
        await _saveConfig(config);
        Log.success('AI配置已更新');
      }
      
      // 显示源列表
      if (showSources) {
        if (results.wasParsed('source')) {
          final modelType = stringOption('source').split(':')[0];
          if (['openai', 'claude', 'grok'].contains(modelType)) {
            await _showSources(config, modelType);
          } else {
            Log.error('不支持的模型类型: $modelType');
            return ExitCode.usage.code;
          }
        } else {
          Log.error('请指定模型类型，例如 --source=openai:default --list-sources');
          return ExitCode.usage.code;
        }
      }
      
      // 显示配置列表
      if (showList || (!updated && !showSources)) {
        await _showConfig(config);
      }
      
      return ExitCode.success.code;
    } catch (e) {
      Log.error('配置AI设置时出错: $e');
      return ExitCode.software.code;
    }
  }
  
  /// 处理旧版配置
  void _handleLegacyConfig(Map<String, dynamic> config) {
    // 检查是否有旧版密钥，如果有则迁移到新的源结构
    final openaiKey = config['openai_key'];
    final claudeKey = config['claude_key'];
    final grokKey = config['grok_key'];
    
    if (openaiKey is String && openaiKey.isNotEmpty) {
      // 检查是否已经有default源
      if (!_sourceExists(config, 'openai', 'default')) {
        _initModelSourcesIfNeeded(config, 'openai');
        config['openai_sources'].add({
          'name': 'default',
          'endpoint': 'https://api.openai.com/v1',
          'key': openaiKey,
        });
        config['openai_active_source'] = 'default';
      }
      // 删除旧密钥
      config.remove('openai_key');
    }
    
    if (claudeKey is String && claudeKey.isNotEmpty) {
      if (!_sourceExists(config, 'claude', 'default')) {
        _initModelSourcesIfNeeded(config, 'claude');
        config['claude_sources'].add({
          'name': 'default',
          'endpoint': 'https://api.anthropic.com/v1',
          'key': claudeKey,
        });
        config['claude_active_source'] = 'default';
      }
      config.remove('claude_key');
    }
    
    if (grokKey is String && grokKey.isNotEmpty) {
      if (!_sourceExists(config, 'grok', 'default')) {
        _initModelSourcesIfNeeded(config, 'grok');
        config['grok_sources'].add({
          'name': 'default',
          'endpoint': 'https://api.xai.com/v1',
          'key': grokKey,
        });
        config['grok_active_source'] = 'default';
      }
      config.remove('grok_key');
    }
  }
  
  /// 获取默认端点
  String _getDefaultEndpoint(String modelType) {
    switch (modelType) {
      case 'openai':
        return 'https://api.openai.com/v1';
      case 'claude':
        return 'https://api.anthropic.com/v1';
      case 'grok':
        return 'https://api.xai.com/v1';
      default:
        return '';
    }
  }
  
  /// 初始化模型源列表
  void _initModelSourcesIfNeeded(Map<String, dynamic> config, String modelType) {
    if (!config.containsKey('${modelType}_sources') || 
        !(config['${modelType}_sources'] is List)) {
      config['${modelType}_sources'] = [];
    }
  }
  
  /// 检查源是否存在
  bool _sourceExists(Map<String, dynamic> config, String modelType, String sourceName) {
    _initModelSourcesIfNeeded(config, modelType);
    
    final sources = config['${modelType}_sources'] as List;
    return sources.any((s) => s is Map && s['name'] == sourceName);
  }
  
  /// 添加或更新源
  bool _addOrUpdateSource(Map<String, dynamic> config, String modelType, 
      String sourceName, String endpoint, String key) {
    _initModelSourcesIfNeeded(config, modelType);
    
    final sources = config['${modelType}_sources'] as List;
    final existingIndex = sources.indexWhere((s) => s is Map && s['name'] == sourceName);
    
    final sourceData = {
      'name': sourceName,
      'endpoint': endpoint,
      'key': _encryptValue(key),
    };
    
    if (existingIndex >= 0) {
      sources[existingIndex] = sourceData;
    } else {
      sources.add(sourceData);
      
      // 如果是第一个源，设为活跃源
      if (sources.length == 1) {
        config['${modelType}_active_source'] = sourceName;
      }
    }
    
    return true;
  }
  
  /// 删除源
  bool _deleteSource(Map<String, dynamic> config, String modelType, String sourceName) {
    _initModelSourcesIfNeeded(config, modelType);
    
    final sources = config['${modelType}_sources'] as List;
    final initialLength = sources.length;
    
    final newSources = sources.where((s) => !(s is Map && s['name'] == sourceName)).toList();
    config['${modelType}_sources'] = newSources;
    
    // 如果删除的是活跃源，重置活跃源
    if (config['${modelType}_active_source'] == sourceName) {
      if (newSources.isNotEmpty) {
        config['${modelType}_active_source'] = (newSources.first as Map)['name'];
      } else {
        config['${modelType}_active_source'] = '';
      }
    }
    
    return initialLength != newSources.length;
  }
  
  /// 读取配置
  Future<Map<String, dynamic>> readConfig() async {
    final file = File(_configPath);
    
    if (!await file.exists()) {
      return _getDefaultConfig();
    }
    
    try {
      final content = await file.readAsString();
      final config = jsonDecode(content) as Map<String, dynamic>;
      
      // 迁移旧的密钥格式
      _migrateKeysIfNeeded(config);
      
      return config;
    } catch (e) {
      Log.error('读取配置文件失败: $e');
      // 如果读取失败，返回默认配置
      return _getDefaultConfig();
    }
  }
  
  /// 获取默认配置
  Map<String, dynamic> _getDefaultConfig() {
    return {
      'default_model': 'openai',
      'openai_model': 'gpt-4o',
      'claude_model': 'claude-3-opus-20240229',
      'grok_model': 'grok-1',
      'openai_sources': [],
      'claude_sources': [],
      'grok_sources': [],
      'openai_active_source': '',
      'claude_active_source': '',
      'grok_active_source': '',
    };
  }
  
  /// 迁移旧的密钥格式
  void _migrateKeysIfNeeded(Map<String, dynamic> config) {
    // 迁移模型源中的密钥
    _migrateSourcesKeysIfNeeded(config, 'openai');
    _migrateSourcesKeysIfNeeded(config, 'claude');
    _migrateSourcesKeysIfNeeded(config, 'grok');
    
    // 兼容旧版配置
    _handleLegacyConfig(config);
  }
  
  /// 迁移源中的密钥
  void _migrateSourcesKeysIfNeeded(Map<String, dynamic> config, String modelType) {
    if (config.containsKey('${modelType}_sources') && config['${modelType}_sources'] is List) {
      final sources = config['${modelType}_sources'] as List;
      for (int i = 0; i < sources.length; i++) {
        if (sources[i] is Map && sources[i].containsKey('key')) {
          final value = sources[i]['key'];
          if (value is String && value.isNotEmpty) {
            try {
              // 尝试解析为JSON，如果成功则已经是新格式
              json.decode(value);
            } catch (e) {
              // 如果无法解析为JSON，则可能是旧格式
              // 将其重新加密为新格式
              final decrypted = decryptValue(value);
              if (decrypted.isNotEmpty) {
                sources[i]['key'] = _encryptValue(decrypted);
              }
            }
          }
        }
      }
    }
  }
  
  /// 保存配置
  Future<void> _saveConfig(Map<String, dynamic> config) async {
    final file = File(_configPath);
    await file.writeAsString(jsonEncode(config));
  }
  
  /// 显示配置
  Future<void> _showConfig(Map<String, dynamic> config) async {
    Log.info('当前AI配置:');
    
    final defaultModel = config['default_model'] ?? 'openai';
    final openaiModel = config['openai_model'] ?? 'gpt-4o';
    final claudeModel = config['claude_model'] ?? 'claude-3-opus-20240229';
    final grokModel = config['grok_model'] ?? 'grok-1';
    
    stdout.writeln('默认模型: $defaultModel');
    stdout.writeln('OpenAI模型: $openaiModel');
    stdout.writeln('Claude模型: $claudeModel');
    stdout.writeln('Grok模型: $grokModel');
    
    // 显示活跃源
    _showActiveSource(config, 'openai');
    _showActiveSource(config, 'claude');
    _showActiveSource(config, 'grok');
    
    stdout.writeln('\n使用 "--list-sources --source=模型:任意源名" 查看所有源');
    stdout.writeln('例如: condor-ai config --list-sources --source=openai:default');
  }
  
  /// 显示活跃源
  void _showActiveSource(Map<String, dynamic> config, String modelType) {
    final activeSource = config['${modelType}_active_source'] ?? '';
    
    if (activeSource.isNotEmpty) {
      _initModelSourcesIfNeeded(config, modelType);
      final sources = config['${modelType}_sources'] as List;
      final source = sources.firstWhere(
        (s) => s is Map && s['name'] == activeSource, 
        orElse: () => null
      );
      
      if (source != null) {
        stdout.writeln('${_getModelName(modelType)}活跃源: ${source['name']} (${source['endpoint']})');
      } else {
        stdout.writeln('${_getModelName(modelType)}活跃源: $activeSource (未找到)');
      }
    } else {
      stdout.writeln('${_getModelName(modelType)}活跃源: 未设置');
    }
  }
  
  /// 显示源列表
  Future<void> _showSources(Map<String, dynamic> config, String modelType) async {
    _initModelSourcesIfNeeded(config, modelType);
    
    final sources = config['${modelType}_sources'] as List;
    final activeSource = config['${modelType}_active_source'] ?? '';
    
    Log.info('${_getModelName(modelType)}可用API源:');
    
    if (sources.isEmpty) {
      stdout.writeln('没有配置源');
      return;
    }
    
    for (final source in sources) {
      if (source is Map) {
        final name = source['name'] ?? '';
        final endpoint = source['endpoint'] ?? '';
        final hasKey = source['key'] != null && source['key'].isNotEmpty;
        
        final isActive = name == activeSource ? ' [活跃]' : '';
        stdout.writeln('$name$isActive: $endpoint');
        stdout.writeln('  API密钥: ${hasKey ? '已设置' : '未设置'}');
      }
    }
  }
  
  /// 获取模型名称
  String _getModelName(String modelType) {
    switch (modelType) {
      case 'openai':
        return 'OpenAI ';
      case 'claude':
        return 'Claude ';
      case 'grok':
        return 'Grok ';
      default:
        return '';
    }
  }
  
  /// 重置配置
  Future<int> _resetConfig() async {
    final file = File(_configPath);
    
    if (await file.exists()) {
      await file.delete();
      Log.success('AI配置已重置');
    } else {
      Log.info('没有找到现有配置文件');
    }
    
    return ExitCode.success.code;
  }
  
  /// 加密值
  String _encryptValue(String value) {
    if (value.isEmpty) return '';
    
    final iv = encrypt.IV.fromLength(16);
    final encrypter = encrypt.Encrypter(encrypt.AES(_encryptKey));
    
    final encrypted = encrypter.encrypt(value, iv: iv);
    return json.encode({'iv': iv.base64, 'content': encrypted.base64});
  }
  
  /// 解密值
  String decryptValue(String value) {
    if (value.isEmpty) return '';
    
    try {
      // 尝试新格式解密
      try {
        final data = json.decode(value) as Map<String, dynamic>;
        
        // 验证数据格式
        if (!data.containsKey('iv') || !data.containsKey('content')) {
          throw FormatException('无效的加密数据格式');
        }
        
        final iv = encrypt.IV.fromBase64(data['iv']);
        final encrypter = encrypt.Encrypter(encrypt.AES(_encryptKey));
        
        return encrypter.decrypt(
          encrypt.Encrypted.fromBase64(data['content']), 
          iv: iv
        );
      } catch (formatError) {
        Log.debug('尝试使用旧格式解密: $formatError');
        // 尝试旧格式解密
        try {
          final iv = encrypt.IV.fromLength(16);
          final encrypter = encrypt.Encrypter(encrypt.AES(_encryptKey));
          
          return encrypter.decrypt(encrypt.Encrypted.fromBase64(value), iv: iv);
        } catch (oldFormatError) {
          Log.debug('旧格式解密失败: $oldFormatError');
          // 如果使用默认IV解密失败，尝试纯文本返回
          if (value.startsWith('{') && value.endsWith('}')) {
            try {
              // 检查是否为已解密的JSON数据
              final data = json.decode(value) as Map<String, dynamic>;
              if (data.containsKey('iv') && data.containsKey('content')) {
                // 已经是加密格式但解析失败，返回空以避免使用无效的密钥
                Log.error('无法解密数据，密钥格式正确但解密失败');
                return '';
              }
            } catch (jsonError) {
              // 不是有效的JSON
            }
          }
          
          // 如果不是有效的密文，返回原始值
          return value;
        }
      }
    } catch (e) {
      Log.error('解密失败: $e');
      return ''; // 解密失败时返回空字符串，而不是原始值，以避免使用无效密钥
    }
  }
  
  /// 获取活跃源
  ApiSource? getActiveSource(Map<String, dynamic> config, String modelType) {
    final activeSourceName = config['${modelType}_active_source'] ?? '';
    if (activeSourceName.isEmpty) return null;
    
    _initModelSourcesIfNeeded(config, modelType);
    final sources = config['${modelType}_sources'] as List;
    
    final sourceMap = sources.firstWhere(
      (s) => s is Map && s['name'] == activeSourceName,
      orElse: () => null
    );
    
    if (sourceMap == null) return null;
    
    return ApiSource(
      name: sourceMap['name'],
      endpoint: sourceMap['endpoint'],
      key: decryptValue(sourceMap['key'] ?? ''),
    );
  }
  
  /// 扫描API源支持的模型
  Future<List<String>> scanModels(String modelType, String sourceName, Map<String, dynamic> config) async {
    final List<String> detectedModels = [];
    
    try {
      // 获取API源
      _initModelSourcesIfNeeded(config, modelType);
      final sources = config['${modelType}_sources'] as List;
      final sourceData = sources.firstWhere(
        (s) => s is Map && s['name'] == sourceName,
        orElse: () => null
      );
      
      if (sourceData == null) {
        Log.error('源 "$sourceName" 在模型 "$modelType" 中不存在');
        return detectedModels;
      }
      
      final endpoint = sourceData['endpoint'] as String;
      final apiKey = decryptValue(sourceData['key'] ?? '');
      
      if (endpoint.isEmpty || apiKey.isEmpty) {
        Log.error('端点URL或API密钥不能为空');
        return detectedModels;
      }
      
      Log.info('正在扫描 $endpoint 支持的模型...');
      
      // 构建模型列表API端点
      String modelsEndpoint;
      if (endpoint.endsWith('/')) {
        modelsEndpoint = '${endpoint}v1/models';
      } else if (endpoint.endsWith('/v1')) {
        modelsEndpoint = '$endpoint/models';
      } else if (endpoint.contains('/v1/')) {
        // 如果包含/v1/但不是结尾，则从/v1/之前的部分重新构建
        final baseUrl = endpoint.substring(0, endpoint.indexOf('/v1/') + 3);
        modelsEndpoint = '${baseUrl}models';
      } else {
        modelsEndpoint = '$endpoint/v1/models';
      }
      
      // 特殊处理etak.cn域名
      if (endpoint.contains('etak.cn')) {
        // etak可能需要不同的端点格式
        modelsEndpoint = endpoint;
        if (endpoint.endsWith('/')) {
          modelsEndpoint += 'v1/models';
        } else {
          modelsEndpoint += '/v1/models';
        }
      }
      
      // 特殊处理unlimit.chat域名
      if (endpoint.contains('unlimit.chat')) {
        // unlimit.chat可能有自定义端点
        if (!endpoint.contains('/models')) {
          if (endpoint.endsWith('/')) {
            modelsEndpoint = '${endpoint}models';
          } else {
            modelsEndpoint = '$endpoint/models';
          }
        } else {
          modelsEndpoint = endpoint;
        }
      }
      
      // 特殊处理xai.com域名
      if (endpoint.contains('xai.com')) {
        // 确保使用正确的v1路径
        if (!endpoint.contains('/v1/models')) {
          if (endpoint.endsWith('/')) {
            modelsEndpoint = '${endpoint}v1/models';
          } else if (endpoint.endsWith('/v1')) {
            modelsEndpoint = '$endpoint/models';
          } else {
            modelsEndpoint = '$endpoint/v1/models';
          }
        }
      }
      
      Log.info('请求端点: $modelsEndpoint');
      
      // 发送HTTP请求获取模型列表
      final client = http.Client();
      try {
        // 准备请求头
        Map<String, String> headers = {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        };
        
        // 添加特定域名的请求头
        if (endpoint.contains('unlimit.chat')) {
          headers['User-Agent'] = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
          headers['Accept'] = 'application/json';
          headers['Origin'] = 'https://platform.unlimit.chat';
          headers['Referer'] = 'https://platform.unlimit.chat/';
        } else if (endpoint.contains('etak.cn')) {
          headers['User-Agent'] = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36';
          headers['Accept'] = 'application/json, text/plain, */*';
          headers['Origin'] = 'https://api.etak.cn';
          headers['Referer'] = 'https://api.etak.cn/';
        }
        
        final response = await client.get(
          Uri.parse(modelsEndpoint),
          headers: headers,
        ).timeout(Duration(seconds: 30), onTimeout: () {
          throw Exception('请求超时，请检查网络连接或API服务状态');
        });
        
        if (response.statusCode != 200) {
          Log.error('API请求失败: ${response.statusCode}');
          
          // 尝试解析错误详情
          try {
            final errorData = jsonDecode(utf8.decode(response.bodyBytes));
            if (errorData != null && errorData.containsKey('error')) {
              final error = errorData['error'];
              if (error is Map && error.containsKey('message')) {
                Log.error('错误详情: ${error['message']}');
              }
            }
          } catch (e) {
            // 如果解析失败，提供原始响应
            Log.error('原始响应: ${response.body}');
          }
          
          return detectedModels;
        }
        
        // 解析响应
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        
        // 处理不同的响应格式
        if (data != null && data.containsKey('data') && data['data'] is List) {
          // 标准OpenAI格式
          final models = data['data'] as List;
          for (var model in models) {
            if (model is Map && model.containsKey('id')) {
              final modelId = model['id'];
              detectedModels.add(modelId.toString());
            }
          }
        } else if (data != null && data.containsKey('models') && data['models'] is List) {
          // 某些API使用不同格式
          final models = data['models'] as List;
          for (var model in models) {
            if (model is Map && model.containsKey('id')) {
              final modelId = model['id'];
              detectedModels.add(modelId.toString());
            } else if (model is String) {
              detectedModels.add(model);
            }
          }
        } else if (data != null && data is List) {
          // 直接返回模型列表的格式
          for (var model in data) {
            if (model is Map && model.containsKey('id')) {
              final modelId = model['id'];
              detectedModels.add(modelId.toString());
            } else if (model is String) {
              detectedModels.add(model);
            }
          }
        } else if (data != null && data.containsKey('available_models') && data['available_models'] is List) {
          // 有些API使用available_models字段
          final models = data['available_models'] as List;
          for (var model in models) {
            if (model is Map && model.containsKey('id')) {
              final modelId = model['id'];
              detectedModels.add(modelId.toString());
            } else if (model is String) {
              detectedModels.add(model);
            }
          }
        }
        
        if (detectedModels.isEmpty) {
          Log.warning('未检测到任何模型，API响应格式可能不标准');
          Log.info('API响应内容: ${response.body.length > 500 ? response.body.substring(0, 500) + "..." : response.body}');
          
          // 对于已知域名，提供预定义模型列表
          if (endpoint.contains('etak.cn')) {
            Log.info('为etak.cn提供默认模型列表');
            detectedModels.addAll([
              'gpt-3.5-turbo', 
              'gpt-3.5-turbo-16k', 
              'gpt-4', 
              'gpt-4-turbo',
              'gpt-4o'
            ]);
          } else if (endpoint.contains('xai.com')) {
            Log.info('为xai.com提供默认模型列表');
            detectedModels.add('grok-1');
          }
        } else {
          Log.success('已检测到 ${detectedModels.length} 个可用模型');
        }
      } finally {
        client.close();
      }
    } catch (e) {
      Log.error('扫描模型时出错: $e');
      
      // 提供通用建议
      Log.info('如果扫描失败，您可以手动设置模型: condor-ai config --${modelType}-model="模型名称"');
    }
    
    return detectedModels;
  }

  /// 获取源数据
  Map<String, dynamic>? _getSourceData(Map<String, dynamic> config, String modelType, String sourceName) {
    _initModelSourcesIfNeeded(config, modelType);
    
    final sources = config['${modelType}_sources'] as List;
    try {
      return sources.firstWhere(
        (s) => s is Map && s['name'] == sourceName,
        orElse: () => null
      );
    } catch (e) {
      return null;
    }
  }
} 