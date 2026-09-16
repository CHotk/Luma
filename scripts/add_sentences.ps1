<#
.SYNOPSIS
    把 staging_sentences.txt 裡暫存的句子安全併進 assets/data/sentences.txt。

.DESCRIPTION
    比照 En 資料夾那邊 add_words.ps1 + staging_words.txt 的模式，用來預防
    「同一句被加兩次」這種手動加句子時容易犯的錯（2026-09-16 使用者決定）：
    句子已存在（整句英文小寫比對）就只合併 tags／relatedWords，不動其他
    欄位；不存在才新增一行，編號自動接續。

    這支腳本管的是 lume（App）這邊的 assets/data/sentences.txt，跟 En 資料夾
    那支各管各的資料，邏輯一樣但是兩個獨立的腳本、兩個獨立的專案，不要
    合併成一支共用的。

    每一句都保證會有「句型」這個標籤（sentenceTag），就算 staging 裡沒填，
    腳本也會自動補上——這個標籤是出題規則拿來判斷「這是句子不是單字」的
    依據，漏了會讓句子安靜地從句型池消失，比忘記加標籤本身更難發現。

    跑完之後：
      - 有新增句子，`# seed-version:` 會自動 +1（跟現有慣例一致：加新內容
        才要動版本號，只合併標籤不算）。
      - staging_sentences.txt 會被清空成只剩說明文字。
      - `lib/data/seed/word_seed_loader.dart` 的 `bundleVersion` 不會自動
        改，腳本結尾會提醒，因為那是 Dart 原始碼，交給人手動確認比較安全。
#>

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$sentencesPath = Join-Path $root 'assets\data\sentences.txt'
$stagingPath = Join-Path $PSScriptRoot 'staging_sentences.txt'

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Get-DisplayWidth {
    param([string]$Text)
    $w = 0
    foreach ($ch in $Text.ToCharArray()) {
        if ([int]$ch -gt 0x2E80) { $w += 2 } else { $w += 1 }
    }
    return $w
}

function Pad-Field {
    param([string]$Text, [int]$Target)
    $spaces = $Target - (Get-DisplayWidth $Text) + 2
    if ($spaces -lt 2) { $spaces = 2 }
    return $Text + (' ' * $spaces)
}

function Parse-DelimList {
    param([string]$Raw)
    if ([string]::IsNullOrWhiteSpace($Raw) -or $Raw.Trim() -eq '-') { return @() }
    return @($Raw -split '、' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
}

function Merge-Unique {
    param([string[]]$Existing, [string[]]$Incoming)
    $result = New-Object System.Collections.Generic.List[string]
    foreach ($item in @($Existing) + @($Incoming)) {
        if ($null -eq $item) { continue }
        $t = $item.Trim()
        if ($t -ne '' -and $t -ne '-' -and -not $result.Contains($t)) {
            [void]$result.Add($t)
        }
    }
    return $result
}

if (-not (Test-Path $sentencesPath)) {
    throw "找不到 $sentencesPath，確認腳本是不是放在 lume 專案的 scripts 資料夾底下。"
}

if (-not (Test-Path $stagingPath)) {
    throw "找不到 $stagingPath，先建立這個檔案並填幾行要加的句子再跑。"
}

# ---- 讀 sentences.txt，拆成「開頭的註解/表頭」跟「資料列」兩段 ----

$raw = [IO.File]::ReadAllText($sentencesPath, [Text.Encoding]::UTF8)
$rawLines = $raw -replace "`r`n", "`n" -split "`n"

$headerLines = New-Object System.Collections.Generic.List[string]
$rawDataLines = New-Object System.Collections.Generic.List[string]
$seenData = $false
foreach ($line in $rawLines) {
    if (-not $seenData -and ($line.StartsWith('#') -or $line.Trim() -eq '')) {
        [void]$headerLines.Add($line)
        continue
    }
    if ($line.Trim() -eq '') { continue }  # 結尾的空行，稍後重加
    $seenData = $true
    [void]$rawDataLines.Add($line)
}

$sep = ' {2,}'

# 資料列存成有序清單（保留原始順序），同時用小寫句子當鍵建索引，
# 方便待會 O(1) 查有沒有重複。
$entries = New-Object System.Collections.Generic.List[System.Collections.Hashtable]
$indexByKey = @{}
$maxId = 0

foreach ($line in $rawDataLines) {
    $cols = [regex]::Split($line, $sep)
    if ($cols.Length -lt 8) {
        Write-Warning "sentences.txt 有一列欄位數不對，原樣保留但不會被比對到：$line"
        continue
    }
    $no = [int]$cols[0]
    if ($no -gt $maxId) { $maxId = $no }
    $entry = @{
        no           = $no
        sentence     = $cols[1]
        pos          = $cols[2]
        zh           = $cols[3]
        grade        = $cols[4]
        sense        = $cols[5]
        tags         = Parse-DelimList $cols[6]
        relatedWords = Parse-DelimList $cols[7]
    }
    [void]$entries.Add($entry)
    $indexByKey[$cols[1].Trim().ToLower()] = $entries.Count - 1
}

# ---- 讀 staging，逐行套用 ----

$stagingRaw = [IO.File]::ReadAllText($stagingPath, [Text.Encoding]::UTF8)
$stagingLines = $stagingRaw -replace "`r`n", "`n" -split "`n"

$added = New-Object System.Collections.Generic.List[string]
$merged = New-Object System.Collections.Generic.List[string]
$skipped = New-Object System.Collections.Generic.List[string]

foreach ($line in $stagingLines) {
    $trimmed = $line.Trim()
    if ($trimmed -eq '' -or $trimmed.StartsWith('#')) { continue }

    $fields = $line -split '\|'
    $get = { param($i) if ($i -lt $fields.Length) { $fields[$i].Trim() } else { '' } }

    $sentence = (& $get 0)
    if ($sentence -eq '') {
        Write-Warning "staging 有一行沒填句子，已略過：$line"
        continue
    }

    $pos = (& $get 1); if ($pos -eq '') { $pos = 'sent.' }
    $zh = (& $get 2)
    $grade = (& $get 3); if ($grade -eq '') { $grade = '國小' }
    $sense = (& $get 4); if ($sense -eq '') { $sense = '-' }
    $stagedTags = Parse-DelimList (& $get 5)
    $stagedRelated = Parse-DelimList (& $get 6)

    $key = $sentence.ToLower()

    if ($indexByKey.ContainsKey($key)) {
        $idx = $indexByKey[$key]
        $entry = $entries[$idx]

        if ($zh -ne '' -and $zh -ne $entry.zh) {
            Write-Warning "「$sentence」已經存在，但 staging 的中文（$zh）跟現有的（$($entry.zh)）不一樣——中文不會被覆蓋，確認是不是打錯字。"
        }

        $entry.tags = Merge-Unique -Existing $entry.tags -Incoming (@('句型') + $stagedTags)
        $entry.relatedWords = Merge-Unique -Existing $entry.relatedWords -Incoming $stagedRelated
        $entries[$idx] = $entry
        [void]$merged.Add($sentence)
    } else {
        if ($zh -eq '') {
            Write-Warning "「$sentence」是新句子但沒填中文，已略過：$line"
            [void]$skipped.Add($sentence)
            continue
        }
        $maxId += 1
        $entry = @{
            no           = $maxId
            sentence     = $sentence
            pos          = $pos
            zh           = $zh
            grade        = $grade
            sense        = $sense
            tags         = Merge-Unique -Existing @() -Incoming (@('句型') + $stagedTags)
            relatedWords = Merge-Unique -Existing @() -Incoming $stagedRelated
        }
        [void]$entries.Add($entry)
        $indexByKey[$key] = $entries.Count - 1
        [void]$added.Add($sentence)
    }
}

if ($added.Count -eq 0 -and $merged.Count -eq 0) {
    Write-Host '沒有任何有效的新句子或標籤要處理，staging 也不會被清空。'
    exit 0
}

# ---- 重新計算欄寬，寫回 sentences.txt ----

# 不能寫成 `$rows = foreach (...) { @(...) }`：PowerShell 會把每次迭代
# 產生的陣列攤平接進外層的輸出流，$rows 最後會變成一長串散開的欄位字串，
# 不是一列一個陣列。用 List 明確 .Add() 才不會被攤平。
$rows = New-Object System.Collections.Generic.List[string[]]
foreach ($entry in $entries) {
    $row = @(
        [string]$entry.no,
        $entry.sentence,
        $entry.pos,
        $entry.zh,
        $entry.grade,
        $entry.sense,
        $(if ($entry.tags.Count -gt 0) { $entry.tags -join '、' } else { '-' }),
        $(if ($entry.relatedWords.Count -gt 0) { $entry.relatedWords -join '、' } else { '-' })
    )
    [void]$rows.Add($row)
}

$headerLabels = @('no', 'sentence', 'pos', 'zh', 'grade', 'sense', 'tags', 'words')
$colCount = $headerLabels.Length
$widths = New-Object int[] $colCount
for ($i = 0; $i -lt $colCount; $i++) {
    $widths[$i] = Get-DisplayWidth $headerLabels[$i]
}
foreach ($row in $rows) {
    for ($i = 0; $i -lt $colCount; $i++) {
        $w = Get-DisplayWidth $row[$i]
        if ($w -gt $widths[$i]) { $widths[$i] = $w }
    }
}

function Build-Line {
    param([string[]]$Fields, [int[]]$Widths)
    $sb = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt $Fields.Length; $i++) {
        if ($i -eq $Fields.Length - 1) {
            [void]$sb.Append($Fields[$i])
        } else {
            [void]$sb.Append((Pad-Field $Fields[$i] $Widths[$i]))
        }
    }
    return $sb.ToString()
}

$newHeaderColumnLine = '# ' + (Build-Line -Fields $headerLabels -Widths $widths)

$outLines = New-Object System.Collections.Generic.List[string]
foreach ($line in $headerLines) {
    if ($line -match '^#\s*seed-version:\s*(\d+)') {
        if ($added.Count -gt 0) {
            $next = [int]$Matches[1] + 1
            [void]$outLines.Add("# seed-version: $next")
        } else {
            [void]$outLines.Add($line)
        }
    } elseif ($line -match '^#\s*no\b') {
        [void]$outLines.Add($newHeaderColumnLine)
    } else {
        [void]$outLines.Add($line)
    }
}
foreach ($row in $rows) {
    [void]$outLines.Add((Build-Line -Fields $row -Widths $widths))
}
[void]$outLines.Add('')

[IO.File]::WriteAllText($sentencesPath, ($outLines -join "`n"), $Utf8NoBom)

# ---- 清空 staging ----

$stagingTemplate = @'
# staging_sentences.txt — 句型暫存區。
#
# 要加新句子就在下面新增一行，欄位用「|」分隔：
#   sentence | pos | zh | grade | sense | tags | relatedWords
#
# 只有 sentence 是必填（新句子還要填 zh，不然腳本會跳過那一行並警告）。
# 其餘留空會套用預設值：
#   pos           留空預設 sent.
#   grade         留空預設 國小
#   sense         留空預設 -
#   tags          不用手動加「句型」，腳本一定會自動補上這個標籤
#   relatedWords  這句用到哪些學過的單字，留空就是沒有，多個用「、」分隔
#
# 例：
#   I need a hand.|sent.|我需要幫忙。|國小||need、hand
#
# 比對已存在的句子是看整句英文（小寫、去頭尾空白）是否相同，
# 已存在就只合併 tags／relatedWords，不會動 pos/zh/grade/sense；
# 不存在才新增一行，編號自動接續。
#
# 跑完 add_sentences.ps1 這個檔案會自動清空成只剩這段說明。
'@
[IO.File]::WriteAllText($stagingPath, $stagingTemplate, $Utf8NoBom)

# ---- 報告 ----

Write-Host ''
Write-Host "新增 $($added.Count) 句："
foreach ($s in $added) { Write-Host "  + $s" }
Write-Host "合併標籤 $($merged.Count) 句："
foreach ($s in $merged) { Write-Host "  ~ $s" }
if ($skipped.Count -gt 0) {
    Write-Host "略過 $($skipped.Count) 句（缺中文）："
    foreach ($s in $skipped) { Write-Host "  ! $s" }
}
Write-Host ''
Write-Host '記得手動把 lib/data/seed/word_seed_loader.dart 的 bundleVersion +1，資料內容真的變了。'
