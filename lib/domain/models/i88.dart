import 'dart:math';

/// i88（2026-11-03）：單純記某個網站今天輸多少、贏多少（新台幣整數），目的是
/// 看每個月有沒有達標。跟交易&自律、記帳都分開，不共用任何東西。
///
/// [amount] 贏是正的、輸是負的（只有這個功能這樣存，方便直接加總）。刪除用
/// 墓碑標記，跟其他功能同一套多裝置同步規矩。
class I88Entry {
  const I88Entry({
    required this.id,
    required this.at,
    required this.amount,
    this.note = '',
    this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final DateTime at;
  final int amount;
  final String note;
  final DateTime? updatedAt;
  final DateTime? deletedAt;

  bool get isWin => amount > 0;
  DateTime get syncedAt => updatedAt ?? at;

  I88Entry copyWith({
    DateTime? at,
    int? amount,
    String? note,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) => I88Entry(
    id: id,
    at: at ?? this.at,
    amount: amount ?? this.amount,
    note: note ?? this.note,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt ?? this.deletedAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'at': at.toIso8601String(),
    'amount': amount,
    'note': note,
    'updatedAt': updatedAt?.toIso8601String(),
    'deletedAt': deletedAt?.toIso8601String(),
  };

  factory I88Entry.fromJson(Map<String, dynamic> j) => I88Entry(
    id: j['id'] as String,
    at: DateTime.parse(j['at'] as String),
    amount: (j['amount'] as num).toInt(),
    note: j['note'] as String? ?? '',
    updatedAt: _d(j['updatedAt']),
    deletedAt: _d(j['deletedAt']),
  );
}

/// 設定值（目前只有「每月目標」）。一個 id 一筆，跟著同步（後改的贏）。
class I88Setting {
  const I88Setting({required this.id, required this.value, this.updatedAt});

  final String id;
  final int value;
  final DateTime? updatedAt;

  DateTime get syncedAt => updatedAt ?? DateTime(2000);

  Map<String, dynamic> toJson() => {
    'id': id,
    'value': value,
    'updatedAt': updatedAt?.toIso8601String(),
  };

  factory I88Setting.fromJson(Map<String, dynamic> j) => I88Setting(
    id: j['id'] as String,
    value: (j['value'] as num).toInt(),
    updatedAt: _d(j['updatedAt']),
  );
}

final _rand = Random.secure();

/// 32 個十六進位字元的隨機 id（兩台裝置同時新增也不會撞號）。
String i88Id() =>
    List.generate(32, (_) => '0123456789abcdef'[_rand.nextInt(16)]).join();

DateTime? _d(Object? v) => v == null ? null : DateTime.parse(v as String);
