import 'package:condor_cli/src/command.dart';
import 'package:condor_cli/src/commands/ai/chat.dart';
import 'package:condor_cli/src/commands/ai/config.dart';

/// AI命令 - 配置AI设置并进行对话
class AiCommand extends CondorCommand {
  /// AI命令构造函数
  AiCommand() {
    addSubcommand(AiConfigCommand());
    addSubcommand(AiChatCommand());
  }

  @override
  final String description = 'AI对话与配置 - 支持多种大型语言模型';

  @override
  final String name = 'ai';
} 