import 'models/ledger.dart';

/// 記帳操作紀錄的文字（2026-11-03）：一筆交易的簡述、改了哪些欄位。
/// 純函式，不碰儲存；帳戶名稱由呼叫端給（[acct]）。

String _money(int v) => '\$$v';

String _day(DateTime t) => '${t.year}/${t.month}/${t.day}（時間不確定）';

String _time(DateTime t) =>
    '${t.year}/${t.month}/${t.day} '
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// 「支出 便當 $120（現金）」。
String logTx(LedgerTx t, String Function(String?) acct) {
  final name = t.merchant.isEmpty ? '' : ' ${t.merchant}';
  final where = t.type == LedgerTxType.transfer
      ? '${acct(t.accountId)} → ${acct(t.toAccountId)}'
      : acct(t.accountId);
  return '${t.type.label}$name ${_money(t.amount)}（$where）';
}

String _splits(List<LedgerSplit> s) => s.isEmpty
    ? '沒拆分'
    : s.map((x) => '${x.category}${_money(x.amount)}').join('＋');

String _pf(PaidFor? p) => p == null
    ? '沒有'
    : '${p.people} 要給 ${_money(p.amount)}${p.settled ? '（已給）' : ''}';

/// 改了哪些欄位（舊→新），沒變就是空清單。
List<String> logDiffTx(LedgerTx a, LedgerTx b, String Function(String?) acct) {
  final out = <String>[];
  void d(String label, Object? x, Object? y) {
    if (x != y) out.add('$label：$x → $y');
  }

  d('類型', a.type.label, b.type.label);
  d(
    '時間',
    a.timeUnknown ? _day(a.occurredAt) : _time(a.occurredAt),
    b.timeUnknown ? _day(b.occurredAt) : _time(b.occurredAt),
  );
  d('時間不確定', a.timeUnknown ? '是' : '否', b.timeUnknown ? '是' : '否');
  if (a.timeUnknown || b.timeUnknown) d('同天排序', a.timeOrder, b.timeOrder);
  d('金額', _money(a.amount), _money(b.amount));
  d('帳戶', acct(a.accountId), acct(b.accountId));
  if (a.toAccountId != b.toAccountId) {
    out.add('轉入：${acct(a.toAccountId)} → ${acct(b.toAccountId)}');
  }
  d('分類', a.category ?? '無', b.category ?? '無');
  d('拆分', _splits(a.splits), _splits(b.splits));
  d('商家', a.merchant, b.merchant);
  d('品項', a.item, b.item);
  d('備註', a.note, b.note);
  d('標記旗幟', a.flagged ? '是' : '否', b.flagged ? '是' : '否');
  d('跟別人一起', _pf(a.paidFor), _pf(b.paidFor));
  d('連到', a.linkedId ?? '無', b.linkedId ?? '無');
  return out;
}
