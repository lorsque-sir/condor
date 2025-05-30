import 'dart:io';

/// Log messages to the console with colors
class Log {
  Log._();

  /// Print a message in blue
  static void info(String msg) {
    _log('\x1B[34m$msg\x1B[0m');
  }

  /// Print a message in green
  static void success(String msg) {
    _log('\x1B[32m$msg\x1B[0m');
  }

  /// Print a message in yellow
  static void warning(String msg) {
    _log('\x1B[33m$msg\x1B[0m');
  }

  /// Print a message in red
  static void error(String msg) {
    _log('\x1B[31m$msg\x1B[0m');
  }

  /// Print a debug message in gray (only in debug mode)
  static void debug(String msg) {
    // 可以在此添加条件判断是否在调试模式
    if (false) { // 设置为false关闭调试日志
      _log('\x1B[90m[DEBUG] $msg\x1B[0m');
    }
  }

  /// Print a message
  static void _log(String message) {
    // ignore: avoid_print
    print(message);
  }
}
