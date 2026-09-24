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

/// 「看過但不喜歡」分類的固定 ID（見 `yt_tracker_categories.json`），列表裡
/// 固定排最後一個。
const ytDislikedCategoryId = 'seed-disliked';

/// 使用者自訂的頻道分類。一個頻道只屬於一個分類（單選，資料夾邏輯），
/// 不是可複選的標籤——跟設計稿 06 版定案的做法一致。
class YtCategory {
  const YtCategory({
    required this.id,
    required this.name,
    required this.colorValue,
    this.imageUrl = '',
    this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String name;

  /// 多裝置同步用（2026-09-24），跟 [DiaryEntry.deletedAt]／`updatedAt`
  /// 同一套：刪除是墓碑標記不是物理刪除，合併時刪除永遠贏、其餘比
  /// [updatedAt] 新舊。舊資料沒有這兩欄，null 當作最舊。
  final DateTime? updatedAt;
  final DateTime? deletedAt;

  DateTime get syncedAt => updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  /// 存 ARGB int 而不是 [Color]，因為要進 JSON；顯示時用 [color] 轉回來。
  final int colorValue;

  /// 分類卡片的底圖，選填——沒填就照舊用 [color] 那個純色調子當底
  /// （2026-09-22 使用者要求：想要卡片好看一點，可以貼圖當底圖）。
  final String imageUrl;

  Color get color => Color(colorValue);

  /// 內容有變（新增／編輯／刪除）時蓋上現在的時間，見 [YtTrackerRepository]。
  YtCategory stamped({bool deleted = false}) {
    final now = DateTime.now();
    return YtCategory(
      id: id,
      name: name,
      colorValue: colorValue,
      imageUrl: imageUrl,
      updatedAt: now,
      deletedAt: deleted ? now : deletedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'color': colorValue,
    'imageUrl': imageUrl,
    'updatedAt': updatedAt?.toIso8601String(),
    'deletedAt': deletedAt?.toIso8601String(),
  };

  factory YtCategory.fromJson(Map<String, dynamic> json) => YtCategory(
    id: json['id'] as String,
    name: json['name'] as String,
    colorValue: json['color'] as int,
    imageUrl: json['imageUrl'] as String? ?? '',
    updatedAt: _parseTime(json['updatedAt']),
    deletedAt: _parseTime(json['deletedAt']),
  );
}

/// 追蹤的頻道。[categoryId] 是 null 代表「未分類」（分類被刪掉、或新增
/// 頻道時還沒選分類）。
///
/// [url] 選填，貼頻道網址（例如 `https://www.youtube.com/@shasha77`）
/// 就能解析出 @handle，「依影片顯示」拿它去問 YouTube Data API 抓最新
/// 影片（見 `youtube_api_service.dart`）。
class YtChannel {
  const YtChannel({
    required this.id,
    required this.name,
    required this.categoryId,
    this.avatarEmoji = '📺',
    this.avatarImageUrl = '',
    this.url = '',
    this.description = '',
    this.youtubeChannelId = '',
    this.uploadsPlaylistId = '',
    required this.addedAt,
    this.updatedAt,
    this.deletedAt,
    this.subscriberCount,
    this.subscribersHidden = false,
    this.statsUpdatedAt,
  });

  final String id;
  final String name;
  final String? categoryId;

  /// 多裝置同步用，同 [YtCategory.updatedAt]。沒有的話退回 [addedAt]。
  final DateTime? updatedAt;
  final DateTime? deletedAt;

  DateTime get syncedAt => updatedAt ?? addedAt;

  /// 訂閱人數（2026-09-24 加）。YouTube API 回的是「無條件捨去到三位有效
  /// 數字」的概略值，不是精確人數；頻道可以選擇隱藏，隱藏時
  /// [subscribersHidden] 是 true、[subscriberCount] 是 null。[statsUpdatedAt]
  /// 是上次問 API 的時間，拿來決定要不要重新更新。頻道詳情頁只讀這裡存的
  /// 值，不會另外打 API。
  final int? subscriberCount;
  final bool subscribersHidden;
  final DateTime? statsUpdatedAt;

  /// 顯示用的訂閱人數文字，沒有資料就是 null（畫面就不顯示這一行）。
  String? get subscriberLabel {
    if (subscribersHidden) return '訂閱數未公開';
    final n = subscriberCount;
    if (n == null) return null;
    String trim(double v) {
      final t = v.toStringAsFixed(1);
      return t.endsWith('.0') ? t.substring(0, t.length - 2) : t;
    }

    if (n >= 100000000) return '約 ${trim(n / 100000000)} 億位訂閱';
    if (n >= 10000) return '約 ${trim(n / 10000)} 萬位訂閱';
    return '$n 位訂閱';
  }

  /// 只改指定欄位的複製（不動 [updatedAt]／[deletedAt]，要蓋時間請用
  /// [stamped]）。[categoryId] 用 [_keep] 當「不改」的標記，因為 null 本身
  /// 是有意義的值（未分類）。
  YtChannel copyWith({
    String? name,
    Object? categoryId = _keep,
    String? avatarImageUrl,
    String? url,
    String? description,
    String? youtubeChannelId,
    String? uploadsPlaylistId,
    int? subscriberCount,
    bool? subscribersHidden,
    DateTime? statsUpdatedAt,
  }) => YtChannel(
    id: id,
    name: name ?? this.name,
    categoryId: identical(categoryId, _keep)
        ? this.categoryId
        : categoryId as String?,
    avatarEmoji: avatarEmoji,
    avatarImageUrl: avatarImageUrl ?? this.avatarImageUrl,
    url: url ?? this.url,
    description: description ?? this.description,
    youtubeChannelId: youtubeChannelId ?? this.youtubeChannelId,
    uploadsPlaylistId: uploadsPlaylistId ?? this.uploadsPlaylistId,
    addedAt: addedAt,
    updatedAt: updatedAt,
    deletedAt: deletedAt,
    subscriberCount: subscriberCount ?? this.subscriberCount,
    subscribersHidden: subscribersHidden ?? this.subscribersHidden,
    statsUpdatedAt: statsUpdatedAt ?? this.statsUpdatedAt,
  );

  YtChannel _copy({
    required String? categoryId,
    required DateTime updatedAt,
    required DateTime? deletedAt,
  }) => YtChannel(
    id: id,
    name: name,
    categoryId: categoryId,
    avatarEmoji: avatarEmoji,
    avatarImageUrl: avatarImageUrl,
    url: url,
    description: description,
    youtubeChannelId: youtubeChannelId,
    uploadsPlaylistId: uploadsPlaylistId,
    addedAt: addedAt,
    updatedAt: updatedAt,
    deletedAt: deletedAt,
    subscriberCount: subscriberCount,
    subscribersHidden: subscribersHidden,
    statsUpdatedAt: statsUpdatedAt,
  );

  /// 內容有變時蓋上現在的時間，見 [YtTrackerRepository]。
  YtChannel stamped({bool deleted = false}) {
    final now = DateTime.now();
    return _copy(
      categoryId: categoryId,
      updatedAt: now,
      deletedAt: deleted ? now : deletedAt,
    );
  }

  /// 所屬分類被刪掉時，頻道改成「未分類」。
  YtChannel withoutCategory() =>
      _copy(categoryId: null, updatedAt: DateTime.now(), deletedAt: deletedAt);

  /// [avatarImageUrl] 沒填、或圖片載入失敗時的退回佔位。
  final String avatarEmoji;

  /// 頻道大頭貼的圖片網址。手動貼上來的（去頻道頁面複製大頭貼圖片
  /// 網址），或是之後「依影片顯示」解析頻道時從 API 抓到的
  /// [YoutubeChannelInfo.avatarUrl] 覆蓋過去，都是同一個欄位。
  final String avatarImageUrl;

  final String url;

  /// 頻道簡介，選填——使用者自己寫幾句話介紹這個頻道在做什麼
  /// （2026-09-22 使用者要求）。API 目前不會自動填這欄，YouTube 官方
  /// 頻道說明文字跟這個用途不完全一樣，不強行覆蓋使用者自己寫的。
  final String description;

  /// 這兩個是呼叫 YouTube Data API 第一次成功解析 [url] 裡的 @handle
  /// 之後快取下來的結果（頻道真正的 ID、上傳影片播放清單 ID）——不快取
  /// 的話「依影片顯示」每次都要多打一次 `channels.list` 才能拿到
  /// `uploadsPlaylistId`，白白多花配額，這兩個字串空著就是「還沒解析
  /// 過」（2026-09-22 使用者要求：接真的 YouTube API）。
  final String youtubeChannelId;
  final String uploadsPlaylistId;

  final DateTime addedAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'categoryId': categoryId,
    'avatarEmoji': avatarEmoji,
    'avatarImageUrl': avatarImageUrl,
    'url': url,
    'description': description,
    'youtubeChannelId': youtubeChannelId,
    'uploadsPlaylistId': uploadsPlaylistId,
    'addedAt': addedAt.toIso8601String(),
    'updatedAt': updatedAt?.toIso8601String(),
    'deletedAt': deletedAt?.toIso8601String(),
    'subscriberCount': subscriberCount,
    'subscribersHidden': subscribersHidden,
    'statsUpdatedAt': statsUpdatedAt?.toIso8601String(),
  };

  factory YtChannel.fromJson(Map<String, dynamic> json) => YtChannel(
    id: json['id'] as String,
    name: json['name'] as String,
    categoryId: json['categoryId'] as String?,
    avatarEmoji: json['avatarEmoji'] as String? ?? '📺',
    avatarImageUrl: json['avatarImageUrl'] as String? ?? '',
    url: json['url'] as String? ?? '',
    description: json['description'] as String? ?? '',
    youtubeChannelId: json['youtubeChannelId'] as String? ?? '',
    uploadsPlaylistId: json['uploadsPlaylistId'] as String? ?? '',
    addedAt: DateTime.parse(json['addedAt'] as String),
    updatedAt: _parseTime(json['updatedAt']),
    deletedAt: _parseTime(json['deletedAt']),
    subscriberCount: json['subscriberCount'] as int?,
    subscribersHidden: json['subscribersHidden'] as bool? ?? false,
    statsUpdatedAt: _parseTime(json['statsUpdatedAt']),
  );
}

/// [YtChannel.copyWith] 的「不改這個欄位」標記。
const Object _keep = Object();

DateTime? _parseTime(Object? raw) =>
    raw == null ? null : DateTime.parse(raw as String);
