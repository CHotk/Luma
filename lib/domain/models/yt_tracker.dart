import 'package:flutter/material.dart';

/// 新增分類時可以選的顏色，卡片小色點跟篩選 chip 都用這組——不開放
/// 自由選色，選項太多反而增加決策負擔，這套顏色也跟設計稿的分類色系
/// 一致（見 `design-history/Yt頻道訂閱管理/`）。
const ytCategoryColors = <int>[
  0xFF6AA9E0, // 藍
  0xFF7FBF8F, // 綠
  0xFFE0A94E, // 金
  0xFFC98FE0, // 紫
  0xFFE07A7A, // 珊瑚
  0xFF5FB8C9, // 青
  0xFFE069A0, // 桃
  0xFF8592E0, // 靛
];

/// 「未分類」不是一筆真的存在 [YtCategory] 記錄，是 [YtChannel.categoryId]
/// 為 null 的頻道的統稱——首頁資料夾格子、篩選 chip 都要能代表這群
/// 頻道，但它們沒有真的分類 id 可以用，所以另外訂一個固定字串當 key
/// （2026-09-22 使用者要求：未分類頻道首頁也要看得到）。
const ytUncategorizedId = '__uncategorized__';

/// 使用者自訂的頻道分類。一個頻道只屬於一個分類（單選，資料夾邏輯），
/// 不是可複選的標籤——跟設計稿 06 版定案的做法一致。
class YtCategory {
  const YtCategory({
    required this.id,
    required this.name,
    required this.colorValue,
  });

  final String id;
  final String name;

  /// 存 ARGB int 而不是 [Color]，因為要進 JSON；顯示時用 [color] 轉回來。
  final int colorValue;

  Color get color => Color(colorValue);

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'color': colorValue};

  factory YtCategory.fromJson(Map<String, dynamic> json) => YtCategory(
    id: json['id'] as String,
    name: json['name'] as String,
    colorValue: json['color'] as int,
  );
}

/// 追蹤的頻道。[categoryId] 是 null 代表「未分類」（分類被刪掉、或新增
/// 頻道時還沒選分類）。
///
/// [url] 選填——現在還沒接 YouTube API（2026-09-22 使用者決定：先只做
/// 分類／頻道管理，影片資料之後再接，避免 API 金鑰直接曝光在這個純前端
/// 靜態網站的疑慮），先讓使用者把網址存起來，以後真的要抓資料時就不用
/// 每個頻道再補一次。
class YtChannel {
  const YtChannel({
    required this.id,
    required this.name,
    required this.categoryId,
    this.avatarEmoji = '📺',
    this.avatarImageUrl = '',
    this.url = '',
    this.description = '',
    required this.addedAt,
  });

  final String id;
  final String name;
  final String? categoryId;

  /// [avatarImageUrl] 沒填、或圖片載入失敗時的退回佔位。
  final String avatarEmoji;

  /// 頻道大頭貼的圖片網址，選填——YouTube 官方大頭貼要透過 Data API
  /// 才拿得到，但這是純前端網站，金鑰會曝光（2026-09-22 使用者決定：
  /// 先不接 API），所以先讓使用者自己去頻道頁面複製大頭貼圖片網址貼
  /// 上來，之後真的接了 API，一樣是覆蓋這個欄位，不用另外改資料結構。
  final String avatarImageUrl;

  final String url;

  /// 頻道簡介，選填——使用者自己寫幾句話介紹這個頻道在做什麼
  /// （2026-09-22 使用者要求），不是自動抓來的，因為還沒接 API。
  final String description;

  final DateTime addedAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'categoryId': categoryId,
    'avatarEmoji': avatarEmoji,
    'avatarImageUrl': avatarImageUrl,
    'url': url,
    'description': description,
    'addedAt': addedAt.toIso8601String(),
  };

  factory YtChannel.fromJson(Map<String, dynamic> json) => YtChannel(
    id: json['id'] as String,
    name: json['name'] as String,
    categoryId: json['categoryId'] as String?,
    avatarEmoji: json['avatarEmoji'] as String? ?? '📺',
    avatarImageUrl: json['avatarImageUrl'] as String? ?? '',
    url: json['url'] as String? ?? '',
    description: json['description'] as String? ?? '',
    addedAt: DateTime.parse(json['addedAt'] as String),
  );
}
