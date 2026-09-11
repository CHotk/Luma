import '../../domain/models/history.dart';
import '../../domain/models/word.dart';

/// 打包在 App 裡的資料來源。
///
/// 抽成介面有兩個理由：
///   1. repository 不必知道資料是從 assets、網路還是別的地方來的。
///   2. 測試時可以塞一份假資料，不用開 Flutter binding 讀 assets。
abstract interface class SeedSource {
  /// 打包資料的版本。
  ///
  /// 只要把 En 資料夾的 words.txt、history.txt 或 seed-words.txt
  /// 重新複製進 assets，這個數字就要加一，App 才知道要同步。
  int get bundleVersion;

  /// 題庫加上既有成績，合併好的一整份。
  /// 版本變新時，這份是權威，會覆蓋 App 裡同名字的對錯次數。
  Future<List<Word>> bundle();

  /// 既有的測驗紀錄，一行一題。只在 App 第一次啟用時匯入一次。
  Future<List<HistoryEntry>> bundleHistory();
}
