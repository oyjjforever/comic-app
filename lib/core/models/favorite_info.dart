/// 收藏信息模型 - 对应 Electron 端 favorites 表
class FavoriteInfo {
  final int? id;
  final String fullPath;
  final String module;
  final String? tags;
  final String? createdAt;

  FavoriteInfo({
    this.id,
    required this.fullPath,
    required this.module,
    this.tags,
    this.createdAt,
  });

  factory FavoriteInfo.fromJson(Map<String, dynamic> json) {
    return FavoriteInfo(
      id: json['id'] as int?,
      fullPath: json['fullPath'] as String? ?? '',
      module: json['module'] as String? ?? '',
      tags: json['tags'] as String?,
      createdAt: json['created_at'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {'fullPath': fullPath, 'module': module, 'tags': tags};
  }
}
