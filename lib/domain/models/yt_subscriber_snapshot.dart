/// 一次「問到某頻道訂閱人數是多少」的快照（2026-09-29 使用者要求：想要
/// 自己記錄每個頻道訂閱數隨時間的變化，YouTube API 本身沒有歷史資料可
/// 查，只能從現在開始自己累積，見對話紀錄的說明）。
///
/// 不管頻道有沒有被刪除都要記——使用者原話「不管有沒有刪除的頻道 也都
/// 記錄一份」，垃圾桶裡的頻道一樣繼續累積歷史，不會因為丟進垃圾桶就
/// 斷掉。
class YtSubscriberSnapshot {
  const YtSubscriberSnapshot({required this.at, required this.count});

  final DateTime at;

  /// YouTube API 回的是無條件捨去到三位有效數字的概略值，隱藏訂閱數的
  /// 頻道不會有這筆快照（沒有數字可記）。
  final int count;

  Map<String, dynamic> toJson() => {
    'at': at.toIso8601String(),
    'count': count,
  };

  factory YtSubscriberSnapshot.fromJson(Map<String, dynamic> json) =>
      YtSubscriberSnapshot(
        at: DateTime.parse(json['at'] as String),
        count: json['count'] as int,
      );
}
