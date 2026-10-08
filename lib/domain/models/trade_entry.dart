/// 一筆交易（2026-10-08 使用者要求：看盤記錄改成「交易&自律」，除了看盤
/// 次數，也要記每一單賺賠多少、當時槓桿幾倍、本金多少、賺賠幾 %）。
///
/// 只記**已實現損益**：開倉時先存一筆 [closedAt] 為 null 的「持倉中」，
/// 平倉那天補上 [pnl]，賺賠算在平倉那天，不追浮盈浮虧（要一直盯價格才
/// 算得出來，跟少看盤的目的相反）。
///
/// 刪除用墓碑標記（[deletedAt]），跟看盤／日記同一套多裝置同步規矩。
class TradeEntry {
  const TradeEntry({
    required this.id,
    required this.symbol,
    required this.isLong,
    required this.leverage,
    required this.margin,
    required this.openedAt,
    this.closedAt,
    this.pnl,
    this.note,
    this.updatedAt,
    this.deletedAt,
  });

  /// 用微秒時間戳字串當 id，不會重複。
  final String id;

  /// 幣種代號，例如 BTC。
  final String symbol;

  /// true＝做多，false＝做空。
  final bool isLong;

  /// 槓桿倍數。
  final double leverage;

  /// 本金（保證金），USDT。
  final double margin;

  final DateTime openedAt;

  /// 平倉時間，null＝持倉中。
  final DateTime? closedAt;

  /// 已實現損益（USDT，賠是負數），持倉中是 null。手續費直接扣在裡面。
  final double? pnl;

  final String? note;

  final DateTime? updatedAt;
  final DateTime? deletedAt;

  bool get isOpen => closedAt == null;

  /// 倉位大小＝本金 × 槓桿。
  double get positionSize => margin * leverage;

  /// 本金報酬率（%）：損益 ÷ 本金。持倉中是 null。
  double? get pnlPercent =>
      pnl == null || margin == 0 ? null : pnl! / margin * 100;

  /// 合併時比新舊用；舊資料沒有 [updatedAt] 就退回開倉時間。
  DateTime get syncedAt => updatedAt ?? openedAt;

  TradeEntry stamped({bool deleted = false}) => _copy(
    updatedAt: DateTime.now(),
    deletedAt: deleted ? DateTime.now() : deletedAt,
  );

  /// 平倉結算。
  TradeEntry closed({required double pnl, required DateTime at}) =>
      _copy(closedAt: at, pnl: pnl, updatedAt: DateTime.now());

  TradeEntry _copy({
    DateTime? closedAt,
    double? pnl,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) => TradeEntry(
    id: id,
    symbol: symbol,
    isLong: isLong,
    leverage: leverage,
    margin: margin,
    openedAt: openedAt,
    closedAt: closedAt ?? this.closedAt,
    pnl: pnl ?? this.pnl,
    note: note,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt ?? this.deletedAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'symbol': symbol,
    'isLong': isLong,
    'leverage': leverage,
    'margin': margin,
    'openedAt': openedAt.toIso8601String(),
    'closedAt': closedAt?.toIso8601String(),
    'pnl': pnl,
    'note': note,
    'updatedAt': updatedAt?.toIso8601String(),
    'deletedAt': deletedAt?.toIso8601String(),
  };

  factory TradeEntry.fromJson(Map<String, dynamic> json) => TradeEntry(
    id: json['id'] as String,
    symbol: json['symbol'] as String,
    isLong: json['isLong'] as bool,
    leverage: (json['leverage'] as num).toDouble(),
    margin: (json['margin'] as num).toDouble(),
    openedAt: DateTime.parse(json['openedAt'] as String),
    closedAt: _date(json['closedAt']),
    pnl: (json['pnl'] as num?)?.toDouble(),
    note: json['note'] as String?,
    updatedAt: _date(json['updatedAt']),
    deletedAt: _date(json['deletedAt']),
  );
}

/// 某個月的月初資金，算「月報酬 %＝本月損益 ÷ 月初資金」用。每個月使用者
/// 自己填一次，[id] 是 `yyyy-MM`，同一個月只有一筆，改了就蓋掉。
class TradeMonthCapital {
  const TradeMonthCapital({
    required this.id,
    required this.amount,
    this.updatedAt,
  });

  final String id;
  final double amount;
  final DateTime? updatedAt;

  static String idOf(DateTime month) =>
      '${month.year}-${month.month.toString().padLeft(2, '0')}';

  /// 沒有 [updatedAt] 的舊資料當成最舊，雲端有新的就讓它蓋過去。
  DateTime get syncedAt => updatedAt ?? DateTime(2000);

  Map<String, dynamic> toJson() => {
    'id': id,
    'amount': amount,
    'updatedAt': updatedAt?.toIso8601String(),
  };

  factory TradeMonthCapital.fromJson(Map<String, dynamic> json) =>
      TradeMonthCapital(
        id: json['id'] as String,
        amount: (json['amount'] as num).toDouble(),
        updatedAt: _date(json['updatedAt']),
      );
}

DateTime? _date(Object? v) => v == null ? null : DateTime.parse(v as String);
