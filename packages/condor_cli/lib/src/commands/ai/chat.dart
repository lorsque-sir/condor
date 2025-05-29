import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:condor_cli/src/command.dart';
import 'package:condor_cli/src/commands/ai/config.dart';
import 'package:condor_cli/src/common.dart';
import 'package:condor_cli/src/utils/log.dart';
import 'package:dart_console/dart_console.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// AI聊天命令 - 在终端中与AI模型进行对话
class AiChatCommand extends CondorCommand {
  /// 构造函数
  AiChatCommand() {
    argParser
      ..addOption(
        'model',
        abbr: 'm',
        help: '使用的AI模型 (openai, claude, grok)',
        allowed: ['openai', 'claude', 'grok'],
      )
      ..addOption(
        'system',
        abbr: 's',
        help: '设置系统提示',
      )
      ..addFlag(
        'stream',
        help: '使用流式响应',
        defaultsTo: true,
      )
      ..addFlag(
        'new',
        abbr: 'n',
        help: '开始新对话',
        negatable: false,
      )
      ..addFlag(
        'list',
        abbr: 'l',
        help: '列出历史对话',
        negatable: false,
      )
      ..addOption(
        'load',
        help: '加载指定的历史对话',
      );
  }

  @override
  String get description => '与AI模型进行对话';

  @override
  String get name => 'chat';
  
  /// 控制台
  final _console = Console();
  
  /// 会话历史记录
  List<Map<String, dynamic>> _messages = [];
  
  /// 当前会话ID
  String _sessionId = DateTime.now().millisecondsSinceEpoch.toString();
  
  /// 会话历史文件目录
  String get _historyDir {
    final home = Platform.environment['HOME'] ?? '';
    return p.join(home, '.condor', 'ai_history');
  }
  
  /// 获取会话历史文件路径
  String _getHistoryPath(String sessionId) {
    return p.join(_historyDir, '$sessionId.json');
  }
  
  @override
  Future<int> run() async {
    try {
      // 创建历史目录
      final historyDir = Directory(_historyDir);
      if (!await historyDir.exists()) {
        await historyDir.create(recursive: true);
      }
      
      // 列出历史对话
      if (boolOption('list')) {
        return await _listHistory();
      }
      
      // 加载历史对话
      if (results.wasParsed('load')) {
        final sessionId = stringOption('load');
        if (sessionId.isEmpty) {
          Log.error('请指定要加载的会话ID');
          return ExitCode.usage.code;
        }
        
        if (!await _loadHistory(sessionId)) {
          Log.error('无法加载会话: $sessionId');
          return ExitCode.noInput.code;
        }
        
        _sessionId = sessionId;
      } else if (boolOption('new')) {
        // 开始新对话
        _messages = [];
        _sessionId = DateTime.now().millisecondsSinceEpoch.toString();
      }
      
      // 读取配置
      final configCommand = AiConfigCommand();
      final config = await configCommand.readConfig();
      
      String modelType = stringOption('model');
      if (modelType.isEmpty) {
        modelType = config['default_model'] ?? 'openai';
      }
      
      // 获取活跃API源
      final openaiSource = configCommand.getActiveSource(config, 'openai');
      final claudeSource = configCommand.getActiveSource(config, 'claude');
      final grokSource = configCommand.getActiveSource(config, 'grok');
      
      final String openaiModel = config['openai_model'] ?? 'gpt-4o';
      final String claudeModel = config['claude_model'] ?? 'claude-3-opus-20240229';
      final String grokModel = config['grok_model'] ?? 'grok-1';
      
      // 设置系统提示
      final String systemPrompt = stringOption('system');
      if (systemPrompt.isNotEmpty && _messages.isEmpty) {
        _messages.add({
          'role': 'system',
          'content': systemPrompt,
        });
      }
      
      // 验证API源
      if (modelType == 'openai' && openaiSource == null) {
        Log.error('未配置OpenAI API源，请先运行: condor ai config --source=openai:default --key="您的密钥"');
        return ExitCode.usage.code;
      } else if (modelType == 'claude' && claudeSource == null) {
        Log.error('未配置Claude API源，请先运行: condor ai config --source=claude:default --key="您的密钥"');
        return ExitCode.usage.code;
      } else if (modelType == 'grok' && grokSource == null) {
        Log.error('未配置Grok API源，请先运行: condor ai config --source=grok:default --key="您的密钥"');
        return ExitCode.usage.code;
      }
      
      // 打印会话信息
      if (_messages.isNotEmpty) {
        final systemMessage = _messages.firstWhere(
          (message) => message['role'] == 'system',
          orElse: () => {'content': ''},
        );
        
        if (systemMessage['content'].isNotEmpty) {
          Log.info('系统提示: ${systemMessage['content']}');
        }
        
        int userMessages = _messages.where((m) => m['role'] == 'user').length;
        int assistantMessages = _messages.where((m) => m['role'] == 'assistant').length;
        
        if (userMessages > 0 || assistantMessages > 0) {
          Log.info('已加载会话历史: $userMessages 条用户消息, $assistantMessages 条助手回复');
        }
      }
      
      // 获取模型显示名称
      String modelDisplayName = modelType;
      String apiSourceName = '';
      
      if (modelType == 'openai' && openaiSource != null) {
        modelDisplayName = 'OpenAI ($openaiModel)';
        apiSourceName = openaiSource.name;
      } else if (modelType == 'claude' && claudeSource != null) {
        modelDisplayName = 'Claude ($claudeModel)';
        apiSourceName = claudeSource.name;
      } else if (modelType == 'grok' && grokSource != null) {
        modelDisplayName = 'Grok ($grokModel)';
        apiSourceName = grokSource.name;
      }
      
      // 启动聊天循环
      Log.success('开始与$modelDisplayName对话');
      if (apiSourceName.isNotEmpty && apiSourceName != 'default') {
        Log.info('使用API源: $apiSourceName');
      }
      Log.info('输入 "exit" 或 "quit" 退出对话，输入 "clear" 清除历史记录');
      
      while (true) {
        // 获取用户输入
        stdout.write('\n\x1B[1;36m你:\x1B[0m ');
        final userInput = stdin.readLineSync();
        
        if (userInput == null || userInput.trim().isEmpty) {
          continue;
        }
        
        if (userInput.trim().toLowerCase() == 'exit' || userInput.trim().toLowerCase() == 'quit') {
          // 保存对话历史
          await _saveHistory();
          break;
        }
        
        if (userInput.trim().toLowerCase() == 'clear') {
          _messages = _messages.where((message) => message['role'] == 'system').toList();
          Log.info('聊天历史已清除，系统提示保留');
          continue;
        }
        
        // 添加用户消息
        _messages.add({
          'role': 'user',
          'content': userInput,
        });
        
        try {
          // 发送请求并获取回复
          final bool useStream = boolOption('stream');
          
          if (modelType == 'openai') {
            await _sendOpenAIRequest(
              openaiModel, 
              useStream, 
              openaiSource!.key,
              openaiSource.endpoint
            );
          } else if (modelType == 'claude') {
            await _sendClaudeRequest(
              claudeModel, 
              useStream, 
              claudeSource!.key,
              claudeSource.endpoint
            );
          } else if (modelType == 'grok') {
            await _sendGrokRequest(
              grokModel, 
              false, // 强制使用非流式响应
              grokSource!.key,
              grokSource.endpoint
            );
          }
          
          // 保存对话历史
          await _saveHistory();
        } catch (e) {
          String errorMessage;
          // 处理特定异常类型
          if (e is FormatException) {
            if (e.toString().contains('<!doctype html>') || 
                e.toString().contains('<html') || 
                e.toString().contains('<!DOCTYPE')) {
              
              errorMessage = '服务器返回了HTML内容而不是预期的JSON响应。\n';
              errorMessage += '这通常表示API端点配置有误或认证失败。\n\n';
              
              if (modelType == 'openai' && openaiSource != null && 
                  openaiSource.endpoint.contains('etak.cn')) {
                errorMessage += '对于etak.cn源，请尝试：\n';
                errorMessage += '1. 确认API密钥格式正确（应以sk-开头）\n';
                errorMessage += '2. 尝试不同的模型名称，例如"gpt-3.5-turbo"或"gpt-4"\n';
                errorMessage += '3. 检查etak.cn服务是否正常\n';
                errorMessage += '4. 考虑切换到其他API源: \n';
                errorMessage += '   dart run bin/condor.dart ai config --use-source=openai:default\n';
              }
            } else {
              errorMessage = '解析API响应时出错: ${e.message}';
            }
          } else {
            errorMessage = '获取AI回复时出错: $e';
          }
          
          Log.error(errorMessage);
          
          // 向对话历史添加错误消息
          _messages.add({
            'role': 'assistant',
            'content': '[错误] $errorMessage',
          });
          
          // 保存历史，包括错误信息
          await _saveHistory();
        }
      }
      
      return ExitCode.success.code;
    } catch (e) {
      Log.error('聊天过程中出错: $e');
      return ExitCode.software.code;
    }
  }
  
  /// 发送OpenAI请求
  Future<void> _sendOpenAIRequest(
      String model, bool useStream, String apiKey, String endpoint) async {
    final client = http.Client();
    
    try {
      final openaiMessages = _messages.map((m) {
        return {
          'role': m['role'],
          'content': m['content'],
        };
      }).toList();
      
      if (useStream) {
        // 为避免潜在的兼容性问题，对于非标准端点，强制使用非流式响应
        if (endpoint != 'https://api.openai.com/v1' || endpoint.contains('etak.cn')) {
          stdout.write('\n\x1B[1;32mAI:\x1B[0m 思考中...');
          
          // 生成正确的API端点URL
          String chatEndpoint;
          
          // 检查endpoint是否已经包含完整路径
          if (endpoint.endsWith('/chat/completions')) {
            chatEndpoint = endpoint;
          } else if (endpoint.endsWith('/v1')) {
            chatEndpoint = '$endpoint/chat/completions';
          } else if (endpoint.endsWith('/v1/')) {
            chatEndpoint = '${endpoint}chat/completions';
          } else if (endpoint.contains('/v1/')) {
            // 如果已经包含/v1/但不是结尾，可能已经是完整路径
            if (!endpoint.contains('/chat/completions')) {
              chatEndpoint = '$endpoint/chat/completions';
            } else {
              chatEndpoint = endpoint;
            }
          } else {
            // 没有包含/v1/，添加完整路径
            if (endpoint.endsWith('/')) {
              chatEndpoint = '${endpoint}v1/chat/completions';
            } else {
              chatEndpoint = '$endpoint/v1/chat/completions';
            }
          }
          
          // 特殊处理etak.cn
          if (endpoint.contains('etak.cn')) {
            // 确保etak.cn使用正确的URL格式
            if (!endpoint.contains('/v1/')) {
              chatEndpoint = endpoint;
              if (endpoint.endsWith('/')) {
                chatEndpoint = '${endpoint}v1/chat/completions';
              } else {
                chatEndpoint = '$endpoint/v1/chat/completions';
              }
            }
          }
          
          Log.debug('发送请求到: $chatEndpoint');
          Log.debug('使用模型: $model');
          Log.debug('消息数量: ${openaiMessages.length}');
          
          final requestBody = {
            'model': model,
            'messages': openaiMessages,
          };
          
          if (endpoint.contains('etak.cn')) {
            // etak源可能需要一些特殊处理
            requestBody['temperature'] = 0.7;
            requestBody['max_tokens'] = 2000;
            Log.debug('添加etak源特定参数');
          }
          
          Log.debug('请求体: ${jsonEncode(requestBody)}');
          
          try {
            // 准备请求头
            Map<String, String> headers = {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $apiKey',
            };
            
            // 为etak源添加特殊请求头
            if (endpoint.contains('etak.cn')) {
              headers['User-Agent'] = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36';
              headers['Accept'] = 'application/json, text/plain, */*';
              headers['Origin'] = 'https://api.etak.cn';
              headers['Referer'] = 'https://api.etak.cn/';
              Log.debug('添加etak源特定请求头');
            }
            
            // 为unlimit.chat源添加特殊请求头
            if (endpoint.contains('unlimit.chat')) {
              headers['User-Agent'] = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
              headers['Accept'] = 'application/json';
              headers['Origin'] = 'https://platform.unlimit.chat';
              headers['Referer'] = 'https://platform.unlimit.chat/';
              
              // 修改requestBody，添加特定字段
              if (!requestBody.containsKey('temperature')) {
                requestBody['temperature'] = 0.7;
              }
              if (!requestBody.containsKey('max_tokens')) {
                requestBody['max_tokens'] = 4000;
              }
              if (!requestBody.containsKey('stream')) {
                requestBody['stream'] = useStream;
              }
              
              Log.debug('添加unlimit.chat源特定参数和请求头');
            }
            
            // 打印详细的请求信息
            Log.debug('====== 请求详情 ======');
            Log.debug('请求URL: $chatEndpoint');
            Log.debug('请求方法: POST');
            Log.debug('请求头:');
            headers.forEach((key, value) {
              if (key == 'Authorization') {
                Log.debug('  $key: Bearer sk-***');
              } else {
                Log.debug('  $key: $value');
              }
            });
            Log.debug('模型: ${requestBody['model']}');
            Log.debug('消息数量: ${(requestBody['messages'] as List).length}');
            Log.debug('=====================');
            
            final response = await client.post(
              Uri.parse(chatEndpoint),
              headers: headers,
              body: jsonEncode(requestBody),
            ).timeout(Duration(seconds: 30), onTimeout: () {
              Log.debug('请求超时');
              throw Exception('请求超时，请检查网络连接或API服务状态');
            });
            
            Log.debug('收到响应状态码: ${response.statusCode}');
            Log.debug('响应内容类型: ${response.headers['content-type'] ?? '未知'}');
            if (response.contentLength != null) {
              Log.debug('响应长度: ${response.contentLength}');
            }
            
            final bodyContent = response.body.trim();
            Log.debug('响应前100字符: ${bodyContent.substring(0, math.min(100, bodyContent.length))}');
            
            // 检查是否为HTML响应
            final contentType = response.headers['content-type'] ?? '';
            if (contentType.contains('text/html') || 
                bodyContent.startsWith('<!doctype html>') ||
                bodyContent.startsWith('<html') ||
                bodyContent.startsWith('<!DOCTYPE')) {
              
              Log.debug('检测到HTML响应，不尝试解析为JSON');
              String errorMessage = '服务器返回了HTML内容而不是预期的JSON响应。\n';
              errorMessage += '这通常表示API端点配置有误或认证失败。\n\n';
              
              if (endpoint.contains('etak.cn')) {
                errorMessage += '对于etak.cn源，请尝试：\n';
                errorMessage += '1. 确认API密钥格式正确（应以sk-开头）\n';
                errorMessage += '2. 尝试不同的模型名称，例如"gpt-3.5-turbo"或"gpt-4"\n';
                errorMessage += '3. 检查etak.cn服务是否正常\n';
                errorMessage += '4. 考虑切换到其他API源: \n';
                errorMessage += '   dart run bin/condor.dart ai config --use-source=openai:default\n';
              }
              
              // 直接显示友好错误信息，不抛出异常
              stdout.write('\r\x1B[K\x1B[1;32mAI:\x1B[0m ');
              stdout.writeln(errorMessage);
              
              // 添加错误响应到历史记录
              _messages.add({
                'role': 'assistant',
                'content': '[API错误] ' + errorMessage,
              });
              
              return;
            }
            
            if (response.statusCode != 200) {
              _handleErrorResponse(response, 'OpenAI');
            }
            
            _handleNonStreamResponse(response, model);
          } catch (e) {
            Log.debug('请求错误: $e');
            throw e;
          }
          return;
        }
        
        // 标准OpenAI API的流式响应处理
        final chatEndpoint = '$endpoint/chat/completions';
        final request = http.Request('POST', Uri.parse(chatEndpoint));
        request.headers.addAll({
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        });
        
        request.body = jsonEncode({
          'model': model,
          'messages': openaiMessages,
          'stream': true,
        });
        
        final streamedResponse = await client.send(request);
        
        if (streamedResponse.statusCode != 200) {
          final response = await http.Response.fromStream(streamedResponse);
          throw Exception('API请求失败: ${response.statusCode} ${response.body}');
        }
        
        stdout.write('\n\x1B[1;32mAI:\x1B[0m ');
        String fullResponse = '';
        
        final stream = streamedResponse.stream.transform(utf8.decoder).transform(const LineSplitter());
        
        await for (var line in stream) {
          if (line.startsWith('data: ')) {
            // 跳过[DONE]消息
            if (line.contains('data: [DONE]')) {
              continue;
            }
            
            String data = line.substring(6).trim(); // 移除 'data: ' 前缀
            if (data.isEmpty) {
              continue;
            }
            
            try {
              final json = jsonDecode(data);
              // 尝试标准OpenAI格式
              if (json != null && 
                  json.containsKey('choices') && 
                  json['choices'] is List && 
                  json['choices'].isNotEmpty && 
                  json['choices'][0] is Map) {
                
                if (json['choices'][0].containsKey('delta') && 
                    json['choices'][0]['delta'] is Map && 
                    json['choices'][0]['delta'].containsKey('content')) {
                  final delta = json['choices'][0]['delta']['content'];
                  if (delta != null) {
                    stdout.write(delta);
                    fullResponse += delta;
                  }
                } else if (json['choices'][0].containsKey('message') && 
                           json['choices'][0]['message'] is Map && 
                           json['choices'][0]['message'].containsKey('content')) {
                  // 处理非流式返回格式
                  final content = json['choices'][0]['message']['content'];
                  if (content != null) {
                    stdout.write(content);
                    fullResponse += content;
                  }
                }
              } 
              // 尝试Claude格式
              else if (json != null && 
                        json.containsKey('type') && 
                        json['type'] == 'content_block_delta' && 
                        json.containsKey('delta') && 
                        json['delta'] is Map && 
                        json['delta'].containsKey('text')) {
                final delta = json['delta']['text'];
                if (delta != null) {
                  stdout.write(delta);
                  fullResponse += delta;
                }
              }
              // 尝试自定义格式 - 直接content字段
              else if (json != null && json.containsKey('content')) {
                final content = json['content'].toString();
                stdout.write(content);
                fullResponse += content;
              }
              // 尝试自定义格式 - 文本字段
              else if (json != null && json.containsKey('text')) {
                final text = json['text'].toString();
                stdout.write(text);
                fullResponse += text;
              }
            } catch (e) {
              Log.debug('流式数据解析错误: $e, 数据: $data');
              // 尝试直接输出原始数据（如果不是JSON格式）
              if (!data.startsWith('{') && !data.startsWith('[')) {
                stdout.write(data);
                fullResponse += data;
              }
            }
          } else if (line.isNotEmpty && line != '[DONE]') {
            // 处理不带前缀的行，可能是原始文本
            stdout.write(line);
            fullResponse += line;
          }
        }
        
        // 保存响应
        _messages.add({
          'role': 'assistant',
          'content': fullResponse,
        });
        
        stdout.writeln();
      } else {
        stdout.write('\n\x1B[1;32mAI:\x1B[0m 思考中...');
        
        final chatEndpoint = '$endpoint/chat/completions';
        final response = await client.post(
          Uri.parse(chatEndpoint),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $apiKey',
          },
          body: jsonEncode({
            'model': model,
            'messages': openaiMessages,
          }),
        );
        
        if (response.statusCode != 200) {
          throw Exception('API请求失败: ${response.statusCode} ${response.body}');
        }
        
        final data = jsonDecode(response.body);
        final content = data['choices'][0]['message']['content'] as String;
        
        stdout.write('\r\x1B[K\x1B[1;32mAI:\x1B[0m ');
        stdout.writeln(content);
        
        // 保存响应
        _messages.add({
          'role': 'assistant',
          'content': content,
        });
      }
    } catch (e) {
      // 捕获所有异常，包括FormatException
      Log.debug('OpenAI请求过程中出错: $e');
      
      String errorMessage;
      
      if (e is FormatException) {
        // 处理JSON解析错误，很可能是HTML响应
        if (e.toString().contains('<!doctype html>') || 
            e.toString().contains('<html') || 
            e.toString().contains('<!DOCTYPE')) {
          
          errorMessage = '服务器返回了HTML内容而不是预期的JSON响应。\n';
          errorMessage += '这通常表示API端点配置有误或认证失败。\n\n';
          
          if (endpoint.contains('etak.cn')) {
            errorMessage += '对于etak.cn源，请尝试：\n';
            errorMessage += '1. 确认API密钥格式正确（应以sk-开头）\n';
            errorMessage += '2. 尝试不同的模型名称，例如"gpt-3.5-turbo"或"gpt-4"\n';
            errorMessage += '3. 检查etak.cn服务是否正常\n';
            errorMessage += '4. 考虑切换到其他API源: \n';
            errorMessage += '   dart run bin/condor.dart ai config --use-source=openai:default\n';
          }
        } else {
          // 其他格式错误
          errorMessage = '解析API响应时出错: ${e.message}\n';
          errorMessage += '这可能表示API返回了非预期格式的数据。';
        }
      } else if (e.toString().contains('timeout') || e.toString().contains('timed out')) {
        // 处理超时错误
        errorMessage = '请求超时。\n';
        errorMessage += '请检查您的网络连接以及API服务状态。';
      } else {
        // 其他错误
        errorMessage = '获取AI回复时出错: $e';
      }
      
      Log.error(errorMessage);
    } finally {
      client.close();
    }
  }
  
  /// 处理非流式响应
  void _handleNonStreamResponse(http.Response response, String model) {
    try {
      String content = '';
      
      // 检查响应内容类型
      final contentType = response.headers['content-type'] ?? '';
      
      // 如果是HTML内容
      if (contentType.contains('text/html') || 
          (response.body.trim().isNotEmpty && (
            response.body.trim().startsWith('<!DOCTYPE') || 
            response.body.trim().startsWith('<html')
          ))) {
        // 尝试从HTML中提取内容（简单处理）
        content = '服务器返回了HTML内容，可能是API不支持或出现故障。\n请检查API配置是否正确。\n响应状态码: ${response.statusCode}';
        
        // 对于etak.cn源，提供额外信息
        final requestUrl = response.request?.url.toString() ?? '';
        if (requestUrl.contains('etak.cn')) {
          content += '\n\n对于etak.cn源，您可能需要：\n1. 检查API密钥是否正确\n2. 该源可能需要特定的模型名称，尝试更改模型配置\n3. 考虑切换到其他API源';
        }
        
        // 保存响应并显示
        _saveAndDisplayResponse(content);
        return;
      }
      
      // 尝试解析为JSON
      try {
        if (response.body.trim().isEmpty) {
          content = '服务器返回了空响应。';
          _saveAndDisplayResponse(content);
          return;
        }
        
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        
        // 尝试各种可能的格式提取内容
        if (data != null) {
          // OpenAI标准格式
          if (data.containsKey('choices') && 
              data['choices'] is List && 
              data['choices'].isNotEmpty) {
            var choice = data['choices'][0];
            if (choice is Map) {
              if (choice.containsKey('message') && 
                  choice['message'] is Map && 
                  choice['message'].containsKey('content') &&
                  choice['message']['content'] != null) {
                content = choice['message']['content'].toString();
              } else if (choice.containsKey('text') && choice['text'] != null) {
                content = choice['text'].toString();
              }
            }
          } 
          // 其他可能的格式
          else if (data.containsKey('content') && data['content'] != null) {
            content = data['content'].toString();
          } else if (data.containsKey('response') && data['response'] != null) {
            content = data['response'].toString();
          } else if (data.containsKey('text') && data['text'] != null) {
            content = data['text'].toString();
          } else if (data.containsKey('message') && 
                    data['message'] is Map && 
                    data['message'].containsKey('content') &&
                    data['message']['content'] != null) {
            content = data['message']['content'].toString();
          }
        }
        
        // 如果无法提取到内容
        if (content.isEmpty) {
          // 直接使用完整响应
          content = '无法从API响应中提取内容。原始响应：\n${response.body}';
          Log.debug('无法解析响应内容，使用原始响应');
        }
      } catch (e) {
        // JSON解析失败，直接使用原始响应
        Log.debug('JSON解析失败: $e');
        content = '响应格式不是标准JSON。原始响应：\n${response.body}';
      }
      
      _saveAndDisplayResponse(content);
    } catch (e) {
      Log.error('处理响应时出错: $e');
      stdout.write('\r\x1B[K\x1B[1;32mAI:\x1B[0m 处理响应时出错，请重试。');
      stdout.writeln();
    }
  }
  
  /// 保存并显示响应
  void _saveAndDisplayResponse(String content) {
    stdout.write('\r\x1B[K\x1B[1;32mAI:\x1B[0m ');
    stdout.writeln(content);
    
    // 保存响应
    _messages.add({
      'role': 'assistant',
      'content': content,
    });
  }
  
  /// 处理错误响应
  void _handleErrorResponse(http.Response response, String provider) {
    String errorMessage = '${provider} API请求失败: ${response.statusCode}';
    
    try {
      final contentType = response.headers['content-type'] ?? '';
      
      // 检查响应是否为空
      if (response.body.isEmpty) {
        errorMessage += '\n服务器返回了空响应。';
        throw Exception(errorMessage);
      }
      
      // 检查是否是JSON响应
      if (contentType.contains('application/json')) {
        try {
          final errorJson = jsonDecode(utf8.decode(response.bodyBytes));
          if (errorJson != null) {
            if (errorJson.containsKey('error') && errorJson['error'] is Map) {
              final error = errorJson['error'];
              if (error.containsKey('message') && error['message'] != null) {
                errorMessage += '\n错误信息: ${error['message']}';
              } else if (error.containsKey('msg') && error['msg'] != null) {
                errorMessage += '\n错误信息: ${error['msg']}';
              } else if (error.containsKey('code') && error['code'] != null) {
                errorMessage += '\n错误代码: ${error['code']}';
              }
            } else if (errorJson.containsKey('message') && errorJson['message'] != null) {
              errorMessage += '\n错误信息: ${errorJson['message']}';
            } else if (errorJson.containsKey('msg') && errorJson['msg'] != null) {
              errorMessage += '\n错误信息: ${errorJson['msg']}';
            }
          }
        } catch (jsonError) {
          Log.debug('解析错误JSON失败: $jsonError');
          errorMessage += '\n无法解析JSON错误信息: ${response.body}';
        }
      } else if (contentType.contains('text/html') || 
                response.body.trim().startsWith('<!DOCTYPE') || 
                response.body.trim().startsWith('<html')) {
        // HTML响应
        errorMessage += '\n服务器返回了HTML内容，可能是认证问题或端点URL配置错误。';
      } else {
        // 非JSON响应
        errorMessage += '\n服务器返回非JSON错误: ${response.body}';
      }
      
      // 提供特定错误的友好提示
      if (response.statusCode == 401 || response.statusCode == 403) {
        errorMessage += '\n请检查您的API密钥是否正确或者已过期，请尝试重新设置密钥。';
        // 检查端点是否包含特定域名
        final requestUrl = response.request?.url.toString() ?? '';
        if (requestUrl.contains('etak.cn')) {
          errorMessage += '\n对于etak.cn源，请确认密钥格式是否以sk-开头。';
        } else if (requestUrl.contains('xai.com')) {
          errorMessage += '\n对于Grok API，请确认您的密钥格式是否正确。';
        }
      } else if (response.statusCode == 404) {
        errorMessage += '\n请检查API端点URL是否正确，或者所请求的资源是否存在。';
        errorMessage += '\n可能的原因：模型名称错误、API路径格式错误。';
      } else if (response.statusCode == 429) {
        errorMessage += '\n请求过于频繁，API限制了请求速率。请稍后重试。';
      } else if (response.statusCode >= 500) {
        errorMessage += '\n服务器错误，请稍后重试。';
      }
    } catch (e) {
      if (e is Exception && e.toString().contains(errorMessage)) {
        // 已经包含了错误信息，直接抛出
        throw e;
      }
      errorMessage += '\n响应解析错误: $e';
    }
    
    throw Exception(errorMessage);
  }
  
  /// 发送Claude请求
  Future<void> _sendClaudeRequest(
      String model, bool useStream, String apiKey, String endpoint) async {
    final client = http.Client();
    
    try {
      final claudeMessages = _messages.map((m) {
        if (m['role'] == 'system') {
          return {
            'role': 'system',
            'content': m['content'],
          };
        } else if (m['role'] == 'user') {
          return {
            'role': 'user',
            'content': m['content'],
          };
        } else {
          return {
            'role': 'assistant',
            'content': m['content'],
          };
        }
      }).toList();
      
      if (useStream) {
        // 生成正确的API端点URL
        String messagesEndpoint;
        
        // 检查endpoint是否已经包含完整路径
        if (endpoint.endsWith('/messages')) {
          messagesEndpoint = endpoint;
        } else if (endpoint.endsWith('/v1')) {
          messagesEndpoint = '$endpoint/messages';
        } else if (endpoint.endsWith('/v1/')) {
          messagesEndpoint = '${endpoint}messages';
        } else if (endpoint.contains('/v1/')) {
          // 如果已经包含/v1/但不是结尾，可能已经是完整路径
          if (!endpoint.contains('/messages')) {
            messagesEndpoint = '$endpoint/messages';
          } else {
            messagesEndpoint = endpoint;
          }
        } else {
          // 没有包含/v1/，添加完整路径
          if (endpoint.endsWith('/')) {
            messagesEndpoint = '${endpoint}v1/messages';
          } else {
            messagesEndpoint = '$endpoint/v1/messages';
          }
        }
        
        Log.debug('发送请求到: $messagesEndpoint');
        
        final request = http.Request('POST', Uri.parse(messagesEndpoint));
        request.headers.addAll({
          'Content-Type': 'application/json',
          'x-api-key': apiKey,
          'anthropic-version': '2023-06-01',
        });
        
        request.body = jsonEncode({
          'model': model,
          'messages': claudeMessages,
          'max_tokens': 4000,
          'stream': true,
        });
        
        final streamedResponse = await client.send(request);
        
        if (streamedResponse.statusCode != 200) {
          final response = await http.Response.fromStream(streamedResponse);
          throw Exception('API请求失败: ${response.statusCode} ${response.body}');
        }
        
        stdout.write('\n\x1B[1;32mAI:\x1B[0m ');
        String fullResponse = '';
        
        final stream = streamedResponse.stream.transform(utf8.decoder).transform(const LineSplitter());
        
        await for (var line in stream) {
          if (line.startsWith('data: ') && !line.contains('data: [DONE]')) {
            final data = line.substring(6); // Remove 'data: ' prefix
            try {
              final json = jsonDecode(data);
              if (json['type'] == 'content_block_delta' && json['delta'] != null) {
                final String? delta = json['delta']['text'];
                if (delta != null) {
                  stdout.write(delta);
                  fullResponse += delta;
                }
              }
            } catch (e) {
              // Ignore parsing errors
            }
          }
        }
        
        // 保存响应
        _messages.add({
          'role': 'assistant',
          'content': fullResponse,
        });
        
        stdout.writeln();
      } else {
        stdout.write('\n\x1B[1;32mAI:\x1B[0m 思考中...');
        
        // 生成正确的API端点URL
        String messagesEndpoint;
        
        // 检查endpoint是否已经包含完整路径
        if (endpoint.endsWith('/messages')) {
          messagesEndpoint = endpoint;
        } else if (endpoint.endsWith('/v1')) {
          messagesEndpoint = '$endpoint/messages';
        } else if (endpoint.endsWith('/v1/')) {
          messagesEndpoint = '${endpoint}messages';
        } else if (endpoint.contains('/v1/')) {
          // 如果已经包含/v1/但不是结尾，可能已经是完整路径
          if (!endpoint.contains('/messages')) {
            messagesEndpoint = '$endpoint/messages';
          } else {
            messagesEndpoint = endpoint;
          }
        } else {
          // 没有包含/v1/，添加完整路径
          if (endpoint.endsWith('/')) {
            messagesEndpoint = '${endpoint}v1/messages';
          } else {
            messagesEndpoint = '$endpoint/v1/messages';
          }
        }
        
        Log.debug('发送请求到: $messagesEndpoint');
        
        final response = await client.post(
          Uri.parse(messagesEndpoint),
          headers: {
            'Content-Type': 'application/json',
            'x-api-key': apiKey,
            'anthropic-version': '2023-06-01',
          },
          body: jsonEncode({
            'model': model,
            'messages': claudeMessages,
            'max_tokens': 4000,
          }),
        );
        
        if (response.statusCode != 200) {
          throw Exception('API请求失败: ${response.statusCode} ${response.body}');
        }
        
        final data = jsonDecode(response.body);
        final content = data['content'][0]['text'] as String;
        
        stdout.write('\r\x1B[K\x1B[1;32mAI:\x1B[0m ');
        stdout.writeln(content);
        
        // 保存响应
        _messages.add({
          'role': 'assistant',
          'content': content,
        });
      }
    } finally {
      client.close();
    }
  }
  
  /// 发送Grok请求
  Future<void> _sendGrokRequest(
      String model, bool useStream, String apiKey, String endpoint) async {
    final client = http.Client();
    
    try {
      // 将消息转换为Grok格式
      final List<Map<String, dynamic>> grokMessages = [];
      
      // 对于Grok，简化消息处理，只保留最后一条用户消息和系统提示
      final systemMessage = _messages.firstWhere(
        (m) => m['role'] == 'system',
        orElse: () => {'content': ''},
      );
      
      String prompt = '';
      if (systemMessage['content'].isNotEmpty) {
        prompt += "${systemMessage['content']}\n\n";
      }
      
      // 获取最后一条用户消息
      final userMessages = _messages.where((m) => m['role'] == 'user').toList();
      if (userMessages.isNotEmpty) {
        prompt += userMessages.last['content'].toString();
      }
      
      // 简化为单一消息
      grokMessages.add({
        'role': 'user',
        'content': prompt,
      });
      
      // 强制使用非流式响应
      useStream = false;
      
      stdout.write('\n\x1B[1;32mAI:\x1B[0m 思考中...');
      
      // 生成正确的API端点URL
      String chatEndpoint;
      
      // 检查endpoint是否已经包含完整路径
      if (endpoint.endsWith('/chat/completions')) {
        chatEndpoint = endpoint;
      } else if (endpoint.endsWith('/v1')) {
        chatEndpoint = '$endpoint/chat/completions';
      } else if (endpoint.endsWith('/v1/')) {
        chatEndpoint = '${endpoint}chat/completions';
      } else if (endpoint.contains('/v1/')) {
        // 如果已经包含/v1/但不是结尾，可能已经是完整路径
        if (!endpoint.contains('/chat/completions')) {
          chatEndpoint = '$endpoint/chat/completions';
        } else {
          chatEndpoint = endpoint;
        }
      } else {
        // 没有包含/v1/，添加完整路径
        if (endpoint.endsWith('/')) {
          chatEndpoint = '${endpoint}v1/chat/completions';
        } else {
          chatEndpoint = '$endpoint/v1/chat/completions';
        }
      }
      
      // 特殊处理特定域名
      if (endpoint.contains('xai.com')) {
        // 确保XAI域名使用正确的URL格式
        if (!endpoint.contains('/v1/chat/completions')) {
          if (endpoint.endsWith('/')) {
            chatEndpoint = '${endpoint}v1/chat/completions';
          } else if (endpoint.endsWith('/v1') || endpoint.endsWith('/v1/')) {
            chatEndpoint = endpoint.endsWith('/') 
                ? '${endpoint}chat/completions' 
                : '$endpoint/chat/completions';
          } else {
            chatEndpoint = '$endpoint/v1/chat/completions';
          }
        }
        Log.debug('处理XAI域名，最终端点: $chatEndpoint');
      }
      
      Log.debug('发送请求到: $chatEndpoint');
      
      final requestBody = {
        'model': model,
        'messages': grokMessages,
        'stream': false, // 强制非流式
      };
      
      Log.debug('请求体: ${jsonEncode(requestBody)}');
      
      final response = await client.post(
        Uri.parse(chatEndpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode(requestBody),
      );
      
      Log.debug('收到响应状态码: ${response.statusCode}');
      
      if (response.statusCode != 200) {
        Log.debug('错误响应: ${response.body}');
        String errorMessage = 'Grok API请求失败: ${response.statusCode}';
        try {
          final errorJson = jsonDecode(response.body);
          if (errorJson != null && errorJson.containsKey('msg')) {
            errorMessage += '\n错误信息: ${errorJson['msg']}';
            
            // 提供特定错误的友好提示
            if (response.statusCode == 401) {
              errorMessage += '\n请检查您的Grok API密钥是否正确或者已过期，请尝试重新设置: condor ai config --source="grok:源名称" --key="您的密钥"';
            }
          }
        } catch (e) {
          errorMessage += ' ${response.body}';
        }
        throw Exception(errorMessage);
      }
      
      try {
        Log.debug('尝试解析响应: ${response.body.substring(0, math.min(200, response.body.length))}...');
        // 尝试解析为JSON
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        String content = '';
        
        // 尝试各种可能的格式
        if (data != null) {
          if (data.containsKey('choices') && 
              data['choices'] is List && 
              data['choices'].isNotEmpty) {
            var choice = data['choices'][0];
            if (choice is Map) {
              if (choice.containsKey('message') && 
                  choice['message'] is Map && 
                  choice['message'].containsKey('content') &&
                  choice['message']['content'] != null) {
                content = choice['message']['content'].toString();
              } else if (choice.containsKey('content') && choice['content'] != null) {
                content = choice['content'].toString();
              } else if (choice.containsKey('text') && choice['text'] != null) {
                content = choice['text'].toString();
              }
            }
          } else if (data.containsKey('content') && data['content'] != null) {
            content = data['content'].toString();
          } else if (data.containsKey('text') && data['text'] != null) {
            content = data['text'].toString();
          } else if (data.containsKey('response') && data['response'] != null) {
            content = data['response'].toString();
          } else if (data.containsKey('message') && 
                   data['message'] is Map && 
                   data['message'].containsKey('content') &&
                   data['message']['content'] != null) {
            content = data['message']['content'].toString();
          }
          
          if (content.isEmpty) {
            // 尝试直接从body提取内容，跳过JSON解析
            content = utf8.decode(response.bodyBytes);
            
            // 如果内容看起来像JSON，尝试美化它
            if (content.trim().startsWith('{') || content.trim().startsWith('[')) {
              try {
                final prettyJson = const JsonEncoder.withIndent('  ').convert(jsonDecode(content));
                content = prettyJson;
              } catch (e) {
                // 如果美化失败，使用原始内容
                Log.debug('美化JSON失败: $e');
              }
            }
          }
        } else {
          // 尝试直接输出响应体
          content = utf8.decode(response.bodyBytes);
        }
        
        stdout.write('\r\x1B[K\x1B[1;32mAI:\x1B[0m ');
        stdout.writeln(content);
        
        // 保存响应
        _messages.add({
          'role': 'assistant',
          'content': content,
        });
      } catch (e) {
        // 如果解析JSON失败，尝试直接输出响应体
        Log.debug('解析响应失败: $e');
        String content = '';
        try {
          content = utf8.decode(response.bodyBytes);
        } catch (encodeError) {
          // 如果UTF-8解码失败，尝试其他编码或直接使用ASCII
          Log.debug('UTF-8解码失败: $encodeError，尝试ASCII');
          content = String.fromCharCodes(
            response.bodyBytes.where((byte) => byte >= 32 && byte < 127)
          );
        }
        
        stdout.write('\r\x1B[K\x1B[1;32mAI:\x1B[0m ');
        stdout.writeln(content);
        
        // 保存响应
        _messages.add({
          'role': 'assistant',
          'content': content,
        });
      }
    } finally {
      client.close();
    }
  }
  
  /// 保存对话历史
  Future<void> _saveHistory() async {
    try {
      final historyFile = File(_getHistoryPath(_sessionId));
      
      // 过滤掉系统消息
      final userMessages = _messages.where((m) => m['role'] != 'system').toList();
      
      if (userMessages.isEmpty) {
        return;
      }
      
      final systemMessage = _messages.firstWhere(
        (m) => m['role'] == 'system',
        orElse: () => {'content': ''},
      );
      
      final Map<String, dynamic> historyData = {
        'id': _sessionId,
        'timestamp': DateTime.now().toIso8601String(),
        'messages': _messages,
        'system': systemMessage['content'],
        'summary': userMessages.first['content'].toString().substring(0, 
            userMessages.first['content'].toString().length > 50 
            ? 50 
            : userMessages.first['content'].toString().length) + '...'
      };
      
      await historyFile.writeAsString(jsonEncode(historyData));
    } catch (e) {
      Log.error('保存历史记录失败: $e');
    }
  }
  
  /// 加载对话历史
  Future<bool> _loadHistory(String sessionId) async {
    try {
      final historyFile = File(_getHistoryPath(sessionId));
      
      if (!await historyFile.exists()) {
        return false;
      }
      
      final content = await historyFile.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;
      
      if (data.containsKey('messages')) {
        _messages = (data['messages'] as List).cast<Map<String, dynamic>>();
        return true;
      }
      
      return false;
    } catch (e) {
      Log.error('加载历史记录失败: $e');
      return false;
    }
  }
  
  /// 列出历史对话
  Future<int> _listHistory() async {
    try {
      final historyDir = Directory(_historyDir);
      
      if (!await historyDir.exists()) {
        Log.info('没有历史对话记录');
        return ExitCode.success.code;
      }
      
      final files = await historyDir
          .list()
          .where((entity) => entity.path.endsWith('.json'))
          .toList();
      
      if (files.isEmpty) {
        Log.info('没有历史对话记录');
        return ExitCode.success.code;
      }
      
      Log.success('历史对话列表:');
      
      final List<Map<String, dynamic>> histories = [];
      
      for (var file in files) {
        try {
          final content = await File(file.path).readAsString();
          final data = jsonDecode(content) as Map<String, dynamic>;
          
          histories.add({
            'id': data['id'] ?? p.basenameWithoutExtension(file.path),
            'timestamp': data['timestamp'] ?? '',
            'summary': data['summary'] ?? '(无摘要)',
          });
        } catch (e) {
          // 忽略解析错误
        }
      }
      
      // 按时间排序
      histories.sort((a, b) => (b['timestamp'] as String).compareTo(a['timestamp'] as String));
      
      for (var history in histories) {
        final timestamp = history['timestamp'] == '' 
            ? '' 
            : DateTime.parse(history['timestamp']).toString().substring(0, 19);
        
        stdout.writeln('${history['id']} - $timestamp');
        stdout.writeln('  ${history['summary']}');
      }
      
      stdout.writeln('');
      stdout.writeln('使用命令加载历史对话: condor ai chat --load=对话ID');
      
      return ExitCode.success.code;
    } catch (e) {
      Log.error('列出历史记录失败: $e');
      return ExitCode.software.code;
    }
  }
} 