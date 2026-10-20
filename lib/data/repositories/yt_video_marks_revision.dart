import 'package:flutter/foundation.dart';

/// 「看過／隱藏」紀錄有人寫了就 +1（2026-10-20 使用者回報：在頻道裡看完影片，
/// 再點下面「影片」那格，看過的還在——那一頁是疊著一直留著的，只在打開時
/// 讀過一次）。開著的頻道詳情頁、分類頁聽這個，畫面先照舊，背景重讀完再把
/// 看過的過濾掉。
final ytVideoMarksRevision = ValueNotifier<int>(0);
