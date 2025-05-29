import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:condor_cli/src/command.dart';
import 'package:condor_cli/src/common.dart';
import 'package:condor_cli/src/utils/log.dart';
import 'package:dart_console/dart_console.dart';
import 'package:http/http.dart' as http;

/// IP质量检测命令 - 检测当前IP或指定IP的质量
class IpTestCommand extends CondorCommand {
  /// 构造函数
  IpTestCommand() {
    argParser
      ..addOption(
        'ip',
        abbr: 'i',
        help: '要检测的IP地址，不提供则检测本机IP',
      )
      ..addFlag(
        'debug',
        abbr: 'd',
        help: '显示调试信息，包括请求和响应详情',
        negatable: false,
      )
      ..addFlag(
        'raw',
        abbr: 'r',
        help: '显示原始JSON响应',
        negatable: false,
      )
      ..addOption(
        'proxy',
        abbr: 'p',
        help: '使用指定的HTTP代理 (例如: 127.0.0.1:7890)',
      )
      ..addFlag(
        'browser',
        abbr: 'b',
        help: '使用浏览器User-Agent',
        negatable: false,
      );
  }

  @override
  String get description => '检测IP质量';

  @override
  String get name => 'iptest';

  /// 控制台对象
  final _console = Console();

  /// 清理JSON字符串，移除可能导致解析问题的字符
  String _sanitizeJsonString(String input) {
    // 移除任何非ASCII和控制字符
    return input.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F-\x9F]'), '');
  }

  /// 尝试解析JSON，如果失败则清理并重试
  dynamic _tryParseJson(String input, bool isDebugMode) {
    try {
      return jsonDecode(input);
    } catch (e) {
      if (isDebugMode) {
        Log.info('JSON解析错误: $e');
        Log.info('尝试清理JSON数据后重新解析...');
      }
      
      // 尝试清理数据后解析
      final sanitizedInput = _sanitizeJsonString(input);
      
      try {
        return jsonDecode(sanitizedInput);
      } catch (e) {
        if (isDebugMode) {
          Log.info('清理后解析仍然失败: $e');
        }
        throw FormatException('无法解析响应数据为JSON: $e');
      }
    }
  }

  @override
  Future<int> run() async {
    Log.info('正在检测IP质量...');

    // 解析参数
    final ipToTest = stringOption('ip');
    final isDebugMode = boolOption('debug');
    final showRawJson = boolOption('raw');
    final proxyUrl = stringOption('proxy');
    final useBrowserUserAgent = boolOption('browser');
    
    // 构建API URL
    final apiUrl = 'https://full-starling-79.deno.dev/${ipToTest ?? ''}';
    
    try {
      // 准备请求头
      final headers = <String, String>{};
      if (useBrowserUserAgent) {
        headers['User-Agent'] = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36';
        headers['Accept'] = 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8';
        headers['Accept-Language'] = 'en-US,en;q=0.9,zh-CN;q=0.8,zh;q=0.7';
        headers['Accept-Encoding'] = 'gzip, deflate, br';
        headers['Cache-Control'] = 'no-cache';
        headers['DNT'] = '1';
        headers['Sec-GPC'] = '1';
        headers['Pragma'] = 'no-cache';
      }
      
      final uri = Uri.parse(apiUrl);
      String responseBody = '';
      int statusCode = 0;
      Map<String, String> responseHeaders = {};
      
      if (isDebugMode) {
        Log.info('请求URL: $apiUrl');
        Log.info('请求头: $headers');
      }
      
      // 如果指定了代理，使用自定义客户端
      if (proxyUrl != null && proxyUrl.isNotEmpty) {
        if (isDebugMode) {
          Log.info('使用代理: $proxyUrl');
        }
        
        final client = HttpClient();
        try {
          // 设置代理
          final parts = proxyUrl.split(':');
          if (parts.length == 2) {
            final host = parts[0];
            final port = int.tryParse(parts[1]) ?? 0;
            if (port > 0) {
              client.findProxy = (uri) => 'PROXY $host:$port';
            }
          }
          
          final request = await client.getUrl(uri);
          
          // 添加请求头
          headers.forEach((key, value) {
            request.headers.add(key, value);
          });
          
          final httpResponse = await request.close();
          statusCode = httpResponse.statusCode;
          
          // 收集响应头信息
          httpResponse.headers.forEach((name, values) {
            responseHeaders[name] = values.join(', ');
          });
          
          // 读取响应体
          try {
            responseBody = await httpResponse.transform(utf8.decoder).join();
          } catch (e) {
            if (isDebugMode) {
              Log.error('utf8解码错误: $e，尝试使用latin1解码...');
            }
            // 如果utf8解码失败，尝试latin1解码
            final bytes = await httpResponse.toList().then((chunks) => 
              chunks.expand((chunk) => chunk).toList());
            responseBody = latin1.decode(bytes);
          }
        } finally {
          client.close();
        }
      } else {
        // 标准http请求
        final response = await http.get(uri, headers: headers);
        responseBody = response.body;
        statusCode = response.statusCode;
        responseHeaders = response.headers;
      }
      
      if (isDebugMode) {
        Log.info('响应状态码: $statusCode');
        Log.info('响应头: $responseHeaders');
        
        // 在调试模式下打印前100个字符的响应体，避免日志过长
        final previewLength = math.min(100, responseBody.length);
        final hasMore = responseBody.length > previewLength;
        Log.info('响应体预览: ${responseBody.substring(0, previewLength)}${hasMore ? '...' : ''}');
      }
      
      if (statusCode == 200) {
        // 使用增强的JSON解析功能
        dynamic data;
        try {
          data = _tryParseJson(responseBody, isDebugMode);
        } catch (e) {
          // 如果解析失败，尝试一些替代方法
          if (isDebugMode) {
            Log.error('JSON解析错误: $e');
            Log.error('尝试直接显示响应内容...');
          }
          
          if (showRawJson) {
            // 无法解析时直接显示原始响应
            _console.clearScreen();
            _console.writeLine('原始响应（JSON解析失败）', TextAlignment.center);
            _console.writeLine('=' * 50, TextAlignment.center);
            _console.writeLine('');
            _console.writeLine(responseBody);
            return ExitCode.success.code;
          } else {
            throw FormatException('无法解析响应数据为JSON: $e');
          }
        }
        
        if (showRawJson) {
          // 显示原始JSON
          _console.clearScreen();
          _console.writeLine('原始JSON响应', TextAlignment.center);
          _console.writeLine('=' * 50, TextAlignment.center);
          _console.writeLine('');
          try {
            _console.writeLine(const JsonEncoder.withIndent('  ').convert(data));
          } catch (e) {
            // 如果美化JSON失败，则直接显示原始JSON字符串
            _console.writeLine(responseBody);
          }
          return ExitCode.success.code;
        }
        
        _console.clearScreen();
        _console.writeLine('IP质量报告', TextAlignment.center);
        _console.writeLine('=' * 50, TextAlignment.center);
        _console.writeLine('');
        
        // 基本IP信息
        _console.writeLine('📍 基本信息');
        
        // 安全地访问字段，确保它们存在
        if (data.containsKey('ip')) {
          _console.writeLine('IP地址: ${data['ip']}');
        }
        
        // 构建完整地区字符串
        final List<String> locationParts = [];
        if (data.containsKey('city') && data['city'] != null) {
          locationParts.add(data['city']);
        }
        if (data.containsKey('region') && data['region'] != null) {
          locationParts.add(data['region']);
        }
        if (data.containsKey('country_name') && data['country_name'] != null) {
          locationParts.add(data['country_name']);
        }
        final locationString = locationParts.isEmpty ? 'N/A' : locationParts.join(' ');
        _console.writeLine('地区: $locationString');
        
        // 经纬度信息
        if (data.containsKey('latitude') && data.containsKey('longitude')) {
          _console.writeLine('地理位置: 纬度 ${data['latitude']}, 经度 ${data['longitude']}');
        }
        
        // 国家/地区代码
        if (data.containsKey('country_code')) {
          _console.writeLine('国家/地区代码: ${data['country_code']}');
        }
        
        // 大洲信息
        if (data.containsKey('continent_name') && data.containsKey('continent_code')) {
          _console.writeLine('大洲: ${data['continent_name']} (${data['continent_code']})');
        } else if (data.containsKey('continent_name')) {
          _console.writeLine('大洲: ${data['continent_name']}');
        }
        
        // 国旗信息
        if (data.containsKey('emoji_flag')) {
          _console.writeLine('国家/地区旗帜: ${data['emoji_flag']}');
        } else if (data.containsKey('flag')) {
          _console.writeLine('国旗链接: ${data['flag']}');
        }
        
        _console.writeLine('');
        
        // ISP/公司信息
        if (data.containsKey('company') && data['company'] is Map) {
          final company = data['company'] as Map;
          if (company.isNotEmpty) {
            _console.writeLine('🏢 网络提供商');
            
            if (company.containsKey('name')) {
              _console.writeLine('名称: ${company['name']}');
            }
            if (company.containsKey('domain')) {
              _console.writeLine('域名: ${company['domain'] ?? 'N/A'}');
            }
            if (company.containsKey('network')) {
              _console.writeLine('网络: ${company['network']}');
            }
            if (company.containsKey('type')) {
              _console.writeLine('类型: ${company['type']}');
            }
            
            _console.writeLine('');
          }
        }
        
        // ASN信息 (有些API可能返回asn而不是company)
        if (data.containsKey('asn') && data['asn'] is Map && !data.containsKey('company')) {
          final asn = data['asn'] as Map;
          if (asn.isNotEmpty) {
            _console.writeLine('🌐 ASN信息');
            
            if (asn.containsKey('asn')) {
              _console.writeLine('ASN: ${asn['asn']}');
            }
            if (asn.containsKey('name')) {
              _console.writeLine('名称: ${asn['name']}');
            }
            if (asn.containsKey('domain')) {
              _console.writeLine('域名: ${asn['domain'] ?? 'N/A'}');
            }
            if (asn.containsKey('route')) {
              _console.writeLine('路由: ${asn['route']}');
            }
            if (asn.containsKey('type')) {
              _console.writeLine('类型: ${asn['type']}');
            }
            
            _console.writeLine('');
          }
        }
        
        // 威胁评估
        if (data.containsKey('threat') && data['threat'] is Map) {
          final threat = data['threat'] as Map;
          if (threat.isNotEmpty) {
            _console.writeLine('🛡️ 威胁评估');
            
            // 各种威胁标志
            final threatFlags = [
              {'key': 'is_vpn', 'label': 'VPN'},
              {'key': 'is_proxy', 'label': '代理'},
              {'key': 'is_datacenter', 'label': '数据中心'},
              {'key': 'is_anonymous', 'label': '匿名'},
              {'key': 'is_known_attacker', 'label': '已知攻击者'},
              {'key': 'is_known_abuser', 'label': '已知滥用者'},
              {'key': 'is_threat', 'label': '威胁'},
              {'key': 'is_tor', 'label': 'Tor出口节点'},
              {'key': 'is_icloud_relay', 'label': 'iCloud私有中继'},
              {'key': 'is_bogon', 'label': 'Bogon地址'},
            ];
            
            // 输出存在的威胁标志
            for (final flag in threatFlags) {
              if (threat.containsKey(flag['key'])) {
                _console.writeLine('${flag['label']}: ${threat[flag['key']] ? '是' : '否'}');
              }
            }
            
            // 评分信息
            if (threat.containsKey('scores') && threat['scores'] is Map) {
              final scores = threat['scores'] as Map;
              if (scores.isNotEmpty) {
                _console.writeLine('');
                _console.writeLine('📊 评分');
                
                final scoreTypes = [
                  {'key': 'vpn_score', 'label': 'VPN评分'},
                  {'key': 'proxy_score', 'label': '代理评分'},
                  {'key': 'threat_score', 'label': '威胁评分'},
                  {'key': 'trust_score', 'label': '信任评分'},
                ];
                
                for (final score in scoreTypes) {
                  if (scores.containsKey(score['key'])) {
                    _console.writeLine('${score['label']}: ${scores[score['key']]}');
                  }
                }
              }
            }
            
            _console.writeLine('');
          }
        }
        
        // 时区信息
        if (data.containsKey('time_zone') && data['time_zone'] is Map) {
          final timeZone = data['time_zone'] as Map;
          if (timeZone.isNotEmpty) {
            _console.writeLine('🕒 时区信息');
            
            String tzName = timeZone.containsKey('name') ? timeZone['name'] : 'N/A';
            String tzAbbr = timeZone.containsKey('abbr') ? timeZone['abbr'] : '';
            
            if (tzName != 'N/A' && tzAbbr.isNotEmpty) {
              _console.writeLine('时区: $tzName ($tzAbbr)');
            } else if (tzName != 'N/A') {
              _console.writeLine('时区: $tzName');
            }
            
            if (timeZone.containsKey('offset')) {
              _console.writeLine('偏移: ${timeZone['offset']}');
            }
            
            if (timeZone.containsKey('current_time')) {
              _console.writeLine('当前时间: ${timeZone['current_time']}');
            }
            
            _console.writeLine('');
          }
        }
        
        // 语言信息
        if (data.containsKey('languages') && data['languages'] is List && (data['languages'] as List).isNotEmpty) {
          final languages = data['languages'] as List;
          _console.writeLine('🗣️ 语言');
          
          for (final lang in languages) {
            if (lang is Map) {
              final name = lang.containsKey('name') ? lang['name'] : 'Unknown';
              final native = lang.containsKey('native') ? lang['native'] : '';
              final code = lang.containsKey('code') ? lang['code'] : '';
              
              if (native.isNotEmpty && code.isNotEmpty) {
                _console.writeLine('$name ($native, $code)');
              } else if (code.isNotEmpty) {
                _console.writeLine('$name ($code)');
              } else {
                _console.writeLine(name);
              }
            }
          }
          
          _console.writeLine('');
        }
        
        // 货币信息
        if (data.containsKey('currency') && data['currency'] is Map) {
          final currency = data['currency'] as Map;
          if (currency.isNotEmpty) {
            _console.writeLine('💰 货币');
            
            final name = currency.containsKey('name') ? currency['name'] : 'Unknown';
            final code = currency.containsKey('code') ? currency['code'] : '';
            final symbol = currency.containsKey('symbol') ? currency['symbol'] : '';
            
            if (code.isNotEmpty && symbol.isNotEmpty) {
              _console.writeLine('$name ($code, $symbol)');
            } else if (code.isNotEmpty) {
              _console.writeLine('$name ($code)');
            } else {
              _console.writeLine(name);
            }
            
            _console.writeLine('');
          }
        }
        
        return ExitCode.success.code;
      } else {
        Log.error('请求失败: HTTP $statusCode');
        if (isDebugMode) {
          Log.error('响应: $responseBody');
        } else {
          Log.error('使用 --debug 参数查看详细错误信息');
        }
        return ExitCode.unavailable.code;
      }
    } catch (e) {
      Log.error('检测IP质量时出错: $e');
      if (isDebugMode && e is Error) {
        Log.error('错误堆栈: ${e.stackTrace}');
      }
      return ExitCode.software.code;
    }
  }
}
