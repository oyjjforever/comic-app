/// 历史记录模型 - 对应 Electron 端 browse_history / download_history 表
class HistoryInfo {
  final int? id;
  final String fullPath;
  final String module;
  final String? createdAt;

  HistoryInfo({
    this.id,
    required this.fullPath,
    required this.module,
    this.createdAt,
  });

  factory HistoryInfo.fromJson(Map<String, dynamic> json) {
    return HistoryInfo(
      id: json['id'] as int?,
      fullPath: json['fullPath'] as String? ?? '',
      module: json['module'] as String? ?? '',
      createdAt: json['created_at'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {'fullPath': fullPath, 'module': module};
  }
}
