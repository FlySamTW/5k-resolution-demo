# 5K / 4K / 2K / 1K 同面積解析度展示

這是一個純網頁展示程式，用同一個取樣位置比較 5K、4K、2K、1K / Full HD 在同面積畫面下的細節與點距差異。

## 本機執行

```bash
npm start
```

開啟：

```text
http://localhost:18765/
```

沉浸展示模式：

```text
http://localhost:18765/?mode=immersive
```

## 新增圖片或影片

把素材放進 `images/` 資料夾即可。支援：

- `.png`
- `.jpg`
- `.jpeg`
- `.webp`
- `.mp4`
- `.webm`
- `.mkv`

注意：MKV 會列入素材清單，但實際能不能播放仍取決於瀏覽器與影片內部編碼；展示現場最穩定的格式仍建議使用 MP4 / H.264。

影片縮圖若要最穩定，請在影片旁放同名 poster 圖，例如 `demo.mp4` 搭配 `demo.poster.jpg`。沒有 poster 時，網頁會嘗試從影片中段自動擷取代表幀，但不同瀏覽器和影片格式不一定都能成功。

部署在 Zeabur 時，小型素材可以一起放進 Git repo 的 `images/`，推送後讓 Zeabur 重新部署。

大型影片不建議放進 Git；若影片已壓到 100MB 以下，可以先放進 `images/` 隨 Git 部署。若希望上線後直接從網頁後台上傳素材，請在 Zeabur 掛載 Volume，並設定：

```text
MEDIA_DIR=/data/media
ADMIN_PASSWORD=自訂一組管理密碼
```

然後打開：

```text
https://你的網域/admin
```

用管理密碼上傳素材。請確認 Zeabur Volume 掛載到 `/data/media` 或你設定的 `MEDIA_DIR`，否則服務重啟後，上傳的檔案可能會消失。

## Zeabur 部署

Zeabur 可部署 Node.js 專案。此專案的啟動指令是：

```bash
npm start
```

Zeabur 會使用平台提供的 `PORT` 環境變數；本機沒有 `PORT` 時預設使用 `18765`，若被占用會改用下一個可用連接埠。

建議環境變數：

```text
MEDIA_DIR=/data/media
ADMIN_PASSWORD=自訂一組管理密碼
```
