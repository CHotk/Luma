# 給 Claude 的專案規則

完整規則跟「為什麼」寫在 `docs/規則.md`，那份先看。這份只放
「每次一定要做、容易漏掉」的行動清單。

## master 跟 gh-pages 要一起 push

只要有改到 `lib/`（app 本身的程式）並且 push 了 master，**同一次
一定要把 GitHub Pages（gh-pages 分支）也一起部署**，不要只 push
master 就結束——使用者是透過 GitHub Pages 在用這個 App，master
落後 gh-pages 太多次會忘記補，變成 App 一直是舊版（2026-09-22
踩過：gh-pages 落後 master 兩個部署都沒發現）。

只有純文件/記憶/design-history 這種不影響 `build/web` 產出的改動，
可以只 push master、不用部署。

### 部署步驟

1. 建 gh-pages 專用的 build（跟本地測試用的 `build/web` **分開輸出**，
   原因見 `docs/規則.md`「本地測試跟部署不要共用同一個 build 資料夾」）：

   ```
   flutter build web --base-href /Luma/ -o build/web-ghpages
   ```
   （Git Bash 底下 `/Luma/` 會被路徑轉譯吃掉，要加
   `MSYS_NO_PATHCONV=1` 前綴。）

2. 建一個指向 `gh-pages` 分支的暫時 worktree（部署完就移除，不要
   留著常駐）：

   ```
   git worktree add ../lume-ghpages gh-pages
   ```

3. 把新 build 鏡射進 worktree。**`/XD ".git"` 沒用**——worktree 根目錄
   的 `.git` 是一個檔案（指回主 repo 的 `.git/worktrees/...`），不是
   資料夾，`/XD` 只排除資料夾，會被 `/MIR` 當成多餘檔案砍掉，
   worktree 直接壞掉。`.nojekyll`（GitHub Pages 用來關掉 Jekyll 處理，
   不然開頭底線的資料夾會被忽略，Flutter 的 asset 路徑會壞）同理，
   它不是 Flutter build 的產物，也不能被鏡射邏輯清掉。兩個都要用
   `/XF`（排除檔案）：

   ```
   robocopy build\web-ghpages ..\lume-ghpages /MIR /XF ".git" ".nojekyll"
   ```

   （萬一手滑用 `/XD` 把 worktree 的 `.git` 檔案砍了：主 repo的
   `.git/worktrees/<name>/gitdir` 檔案還在，內容是
   `<worktree路徑>/.git`；照這個內容重建那個檔案就救得回來，
   不用整個 worktree 重建。）

4. 進 worktree 內 commit＋push：

   ```
   cd ../lume-ghpages
   git add -A
   git commit -m "Deploy: <跟 master 那次 commit 同一句話或摘要>"
   git push origin gh-pages
   ```

5. 部署完移除 worktree，不要留著：

   ```
   cd ../lume
   git worktree remove ../lume-ghpages
   ```
