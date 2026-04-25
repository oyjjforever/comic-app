/// 服务器信息模型
class ServerInfo {
  final String name;
  final String hostname;
  final String ip;
  final int port;
  final String version;
  final String resourcePath;
  final String videoResourcePath;

  ServerInfo({
    required this.name,
    required this.hostname,
    required this.ip,
    required this.port,
    this.version = '1.0.0',
    this.resourcePath = '',
    this.videoResourcePath = '',
  });

  /// 服务器基础 URL
  String get baseUrl => 'http://$ip:$port';

  /// 从 mDNS 发现结果创建
  factory ServerInfo.fromDiscovery({
    required String name,
    required String ip,
    required int port,
  }) {
    return ServerInfo(
      name: name,
      hostname: name.replaceAll('Comic Reader on ', ''),
      ip: ip,
      port: port,
    );
  }

  /// 从 /api/server/info 响应创建
  factory ServerInfo.fromJson(Map<String, dynamic> json, String ip) {
    return ServerInfo(
      name: json['name'] as String? ?? '',
      hostname: json['hostname'] as String? ?? '',
      ip: ip,
      port: json['port'] as int? ?? 9527,
      version: json['version'] as String? ?? '1.0.0',
      resourcePath: json['resourcePath'] as String? ?? '',
      videoResourcePath: json['videoResourcePath'] as String? ?? '',
    );
  }

  @override
  String toString() => 'ServerInfo(name: $name, ip: $ip, port: $port)';
}
