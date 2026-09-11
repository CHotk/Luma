import '../../domain/models/word.dart';

/// 題庫的來源。
///
/// 抽成介面有兩個理由：
///   1. repository 不必知道題庫是從 assets、網路還是別的地方來的。
///   2. 測試時可以塞一份假題庫，不用開 Flutter binding 讀 assets。
abstract interface class SeedSource {
  /// 題庫版本。題庫加了新字就要往上加一號。
  /// repository 靠這個判斷要不要把新字補進既有的資料。
  Future<int> version();

  /// 題庫本身，不含任何成績。
  Future<List<Word>> seedWords();

  /// 第一次開啟時用的完整匯入：題庫加上使用者既有的成績。
  Future<List<Word>> initialImport();
}
