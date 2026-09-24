// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

/// 從 user agent 判斷「系統・瀏覽器」，例如「Android・Chrome」。
/// 判斷順序有講究：Edge／Opera 的 UA 也含 Chrome、Chrome 的 UA 也含
/// Safari，要先比對特殊的。
String currentDeviceLabel() {
  final ua = html.window.navigator.userAgent;
  final os = ua.contains('Android')
      ? 'Android'
      : (ua.contains('iPhone') || ua.contains('iPad'))
      ? 'iOS'
      : ua.contains('Windows')
      ? 'Windows'
      : ua.contains('Mac OS')
      ? 'Mac'
      : ua.contains('Linux')
      ? 'Linux'
      : '未知系統';
  final browser = ua.contains('Edg/')
      ? 'Edge'
      : (ua.contains('OPR/') || ua.contains('Opera'))
      ? 'Opera'
      : (ua.contains('Chrome') || ua.contains('CriOS'))
      ? 'Chrome'
      : ua.contains('Firefox')
      ? 'Firefox'
      : ua.contains('Safari')
      ? 'Safari'
      : '未知瀏覽器';
  return '$os・$browser';
}
