import 'package:condor_cli/src/commands/ai/ai.dart';
import 'package:condor_cli/src/commands/apps.dart';
import 'package:condor_cli/src/commands/copilot/copilot.dart';
import 'package:condor_cli/src/commands/doctor.dart';
import 'package:condor_cli/src/commands/fileorg.dart';
import 'package:condor_cli/src/commands/flutter/flutter.dart';
import 'package:condor_cli/src/commands/init.dart';
import 'package:condor_cli/src/commands/iptest.dart';
import 'package:condor_cli/src/commands/optimize_build/optimize_build.dart';
import 'package:condor_cli/src/commands/sysmon.dart';
import 'package:condor_cli/src/commands/upload.dart';
import 'package:condor_cli/src/common.dart';
import 'package:condor_cli/src/utils/utils.dart';

/// 包名
const packageName = 'condor_cli';

/// 可执行程序名
const executableName = 'condor';

/// 该CLI的描述
const description = 'LinXunFeng的脚本工具集';

/// condor命令行运行器
class CondorCommandRunner extends CompletionCommandRunner<int> {
  /// condor命令行运行器构造函数
  /// 添加所有命令
  CondorCommandRunner() : super(executableName, description) {
    Log.info('初始化命令运行器...');
    addCommand(InitCommand());
    addCommand(DoctorCommand());
    addCommand(UploadCommand());
    addCommand(FlutterCommand());
    addCommand(OptimizeBuildCommand());
    addCommand(CopilotCommand());
    
    // 确保这些命令被添加
    Log.info('添加Apps命令...');
    addCommand(AppsCommand());
    Log.info('添加SysMon命令...');
    addCommand(SysMonCommand());
    Log.info('添加FileOrg命令...');
    addCommand(FileOrgCommand());
    Log.info('添加AI命令...');
    addCommand(AiCommand());
    Log.info('添加IPTest命令...');
    addCommand(IpTestCommand());
  }

  @override
  Future<int> run(Iterable<String> args) async {
    try {
      Log.info('运行命令: $args');
      return await runCommand(parse(args)) ?? ExitCode.success.code;
    } on UsageException catch (e) {
      Log.error(e.message);
      Log.info(e.usage);
      return ExitCode.usage.code;
    } catch (e) {
      Log.error('运行出错: ${e.toString()}');
      return ExitCode.software.code;
    }
  }

  @override
  Future<int?> runCommand(ArgResults topLevelResults) {
    Log.info('处理参数: $topLevelResults');
    return super.runCommand(topLevelResults);
  }
}
