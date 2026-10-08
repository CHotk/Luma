import 'package:flutter/material.dart' show Color;

/// 負債種類（2026-10-08 負債管理）。使用者實際有的：信貸、手機貸、筆電貸、
/// 信用卡（2026-10-08 拿掉房貸、車貸、學貸、親友借款，加手機貸、筆電貸）。
///
/// 信用卡是**每月帳單**，不是攤還：使用者說「信用卡分期很難算，只能看當期
/// 帳單大概多少」，所以信用卡只記每月大概要繳多少（[Debt.flexPay] 當本期
/// 帳單金額），不算本金、利息、剩餘、還清日，見 [Debt.isBill]。
/// 其他種類照本息平均攤還算。舊資料裡已經拿掉的種類讀進來當「其他」。
enum DebtType {
  loan('信貸', '💳', Color(0xFF7EA6FF)),
  phone('手機貸', '📱', Color(0xFF5FD3C6)),
  laptop('筆電貸', '💻', Color(0xFFB79CFF)),
  card('信用卡', '🧾', Color(0xFFFF9F7A)),
  other('其他', '📌', Color(0xFFA3A2B2));

  const DebtType(this.label, this.emoji, this.color);

  final String label;
  final String emoji;
  final Color color;

  static DebtType parse(String? name) =>
      DebtType.values.firstWhere((t) => t.name == name, orElse: () => other);
}

/// 一筆負債。
///
/// 兩種還款方式：
/// - 固定期數（[flexible] false）：銀行貸款、信用卡分期那種「本息平均攤還」，
///   每期金額固定，前期利息多、後期本金多；
/// - 自由還款（[flexible] true）：跟親友借的，沒有利息、沒有固定期數，
///   照 [flexPay] 推算，有還就記。
///
/// 已繳的每一期存在 [DebtPayment]，不存在這裡；刪除用墓碑標記，跟其他
/// 功能同一套多裝置同步規矩。
class Debt {
  const Debt({
    required this.id,
    required this.name,
    required this.lender,
    required this.type,
    required this.principal,
    required this.rate,
    required this.term,
    required this.firstYear,
    required this.firstMonth,
    required this.dueDay,
    required this.flexible,
    required this.flexPay,
    this.fee = 0,
    this.payoffAt,
    this.payoffAmount,
    this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String name;

  /// 銀行或借錢的對象。
  final String lender;
  final DebtType type;

  /// 借款本金。
  final double principal;

  /// 年利率（%），自由還款是 0。
  final double rate;

  /// 期數，自由還款是 0。
  final int term;

  /// 第一期的年、月（月是 1–12）。
  final int firstYear;
  final int firstMonth;

  /// 每月扣款日（1–31，那個月沒有那天就用月底）。
  final int dueDay;

  final bool flexible;

  /// 自由還款預計每月還多少。
  final double flexPay;

  /// 提前清償（一次還清剩下的）的時間跟金額；沒有就是 null。
  final DateTime? payoffAt;
  final double? payoffAmount;

  final DateTime? updatedAt;
  final DateTime? deletedAt;

  DateTime get syncedAt => updatedAt ?? DateTime(2000);

  /// 開辦費（一次性，例如信貸的手續費），算總成本用，不影響每月要繳。
  final double fee;

  /// 畫面上接在名稱後面的「銀行・」。2026-10-08 起新增債務只填一個名稱
  /// （使用者：名稱跟銀行不用分兩欄），舊資料有填銀行的才會顯示。
  String get lenderPrefix => lender.isEmpty ? '' : '$lender・';

  /// 每月帳單型（信用卡）：每個月繳一次大概 [flexPay] 元，沒有本金、期數。
  bool get isBill => type == DebtType.card;

  Debt copyWith({
    String? name,
    String? lender,
    DebtType? type,
    double? principal,
    double? rate,
    int? term,
    int? firstYear,
    int? firstMonth,
    int? dueDay,
    bool? flexible,
    double? flexPay,
    double? fee,
    DateTime? Function()? payoffAt,
    double? Function()? payoffAmount,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) => Debt(
    id: id,
    name: name ?? this.name,
    lender: lender ?? this.lender,
    type: type ?? this.type,
    principal: principal ?? this.principal,
    rate: rate ?? this.rate,
    term: term ?? this.term,
    firstYear: firstYear ?? this.firstYear,
    firstMonth: firstMonth ?? this.firstMonth,
    dueDay: dueDay ?? this.dueDay,
    flexible: flexible ?? this.flexible,
    flexPay: flexPay ?? this.flexPay,
    fee: fee ?? this.fee,
    payoffAt: payoffAt == null ? this.payoffAt : payoffAt(),
    payoffAmount: payoffAmount == null ? this.payoffAmount : payoffAmount(),
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt ?? this.deletedAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'lender': lender,
    'type': type.name,
    'principal': principal,
    'rate': rate,
    'term': term,
    'firstYear': firstYear,
    'firstMonth': firstMonth,
    'dueDay': dueDay,
    'flexible': flexible,
    'flexPay': flexPay,
    'fee': fee,
    'payoffAt': payoffAt?.toIso8601String(),
    'payoffAmount': payoffAmount,
    'updatedAt': updatedAt?.toIso8601String(),
    'deletedAt': deletedAt?.toIso8601String(),
  };

  factory Debt.fromJson(Map<String, dynamic> j) => Debt(
    id: j['id'] as String,
    name: j['name'] as String,
    lender: j['lender'] as String? ?? '',
    type: DebtType.parse(j['type'] as String?),
    principal: (j['principal'] as num).toDouble(),
    rate: (j['rate'] as num?)?.toDouble() ?? 0,
    term: (j['term'] as num?)?.toInt() ?? 0,
    firstYear: (j['firstYear'] as num).toInt(),
    firstMonth: (j['firstMonth'] as num).toInt(),
    dueDay: (j['dueDay'] as num).toInt(),
    flexible: j['flexible'] as bool? ?? false,
    flexPay: (j['flexPay'] as num?)?.toDouble() ?? 0,
    fee: (j['fee'] as num?)?.toDouble() ?? 0,
    payoffAt: _date(j['payoffAt']),
    payoffAmount: (j['payoffAmount'] as num?)?.toDouble(),
    updatedAt: _date(j['updatedAt']),
    deletedAt: _date(j['deletedAt']),
  );
}

/// 繳了一期（或自由還款的一筆）。紀錄一筆都不刪（使用者的規矩：log 類
/// 資料存檔不裁），按錯取消也只是蓋墓碑。
class DebtPayment {
  const DebtPayment({
    required this.id,
    required this.debtId,
    required this.date,
    required this.amount,
    this.period,
    this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String debtId;

  /// 第幾期（固定期數才有）。
  final int? period;
  final DateTime date;
  final double amount;
  final DateTime? updatedAt;
  final DateTime? deletedAt;

  DateTime get syncedAt => updatedAt ?? date;

  DebtPayment deleted() => DebtPayment(
    id: id,
    debtId: debtId,
    period: period,
    date: date,
    amount: amount,
    updatedAt: DateTime.now(),
    deletedAt: DateTime.now(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'debtId': debtId,
    'period': period,
    'date': date.toIso8601String(),
    'amount': amount,
    'updatedAt': updatedAt?.toIso8601String(),
    'deletedAt': deletedAt?.toIso8601String(),
  };

  factory DebtPayment.fromJson(Map<String, dynamic> j) => DebtPayment(
    id: j['id'] as String,
    debtId: j['debtId'] as String,
    period: (j['period'] as num?)?.toInt(),
    date: DateTime.parse(j['date'] as String),
    amount: (j['amount'] as num).toDouble(),
    updatedAt: _date(j['updatedAt']),
    deletedAt: _date(j['deletedAt']),
  );
}

/// 負債功能的設定值（目前只有月收入，算「還款佔收入幾 %」）。一個 id
/// 一筆，跟著同步。
class DebtSetting {
  const DebtSetting({required this.id, required this.value, this.updatedAt});

  final String id;
  final double value;
  final DateTime? updatedAt;

  DateTime get syncedAt => updatedAt ?? DateTime(2000);

  Map<String, dynamic> toJson() => {
    'id': id,
    'value': value,
    'updatedAt': updatedAt?.toIso8601String(),
  };

  factory DebtSetting.fromJson(Map<String, dynamic> j) => DebtSetting(
    id: j['id'] as String,
    value: (j['value'] as num).toDouble(),
    updatedAt: _date(j['updatedAt']),
  );
}

DateTime? _date(Object? v) => v == null ? null : DateTime.parse(v as String);
