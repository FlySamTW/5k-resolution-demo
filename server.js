const http = require("node:http");
const fs = require("node:fs");
const path = require("node:path");
const Busboy = require("busboy");
const { ZipArchive } = require("archiver");

const root = __dirname;
const bundledImagesDir = path.join(root, "images");
const mediaDir = path.resolve(process.env.MEDIA_DIR || bundledImagesDir);
const requestedPort = Number(process.env.PORT || 18765);
const fallbackPorts = process.env.PORT ? [requestedPort] : [18765, 18766, 18767, 18768, 18769];
const allowedMediaExt = new Set([".png", ".jpg", ".jpeg", ".webp", ".mp4", ".webm", ".mkv"]);
const adminPassword = process.env.ADMIN_PASSWORD || "";
const googleDriveFolderId = process.env.GOOGLE_DRIVE_FOLDER_ID || "1k705zXDNpHdknPeSPnANBdYDG2wIP_OD";
const googleDriveApiKey = process.env.GOOGLE_DRIVE_API_KEY || "";
const googleDriveFolderUrl = `https://drive.google.com/drive/folders/${googleDriveFolderId}?usp=sharing`;
const localPackageFiles = [
  "index.html",
  "啟動展示.bat",
  "launch-demo.ps1",
  "start-demo.ps1",
  "LOCAL_APP_README.txt"
];

function contentType(filePath) {
  switch (path.extname(filePath).toLowerCase()) {
    case ".html":
      return "text/html; charset=utf-8";
    case ".js":
      return "application/javascript; charset=utf-8";
    case ".css":
      return "text/css; charset=utf-8";
    case ".json":
      return "application/json; charset=utf-8";
    case ".png":
      return "image/png";
    case ".jpg":
    case ".jpeg":
      return "image/jpeg";
    case ".webp":
      return "image/webp";
    case ".mp4":
      return "video/mp4";
    case ".webm":
      return "video/webm";
    case ".mkv":
      return "video/x-matroska";
    default:
      return "application/octet-stream";
  }
}

function sendJson(res, payload) {
  const body = Buffer.from(JSON.stringify(payload));
  res.writeHead(200, {
    "Content-Type": "application/json; charset=utf-8",
    "Content-Length": body.length,
    "Cache-Control": "no-store"
  });
  res.end(body);
}

function sendFile(req, res, filePath) {
  fs.stat(filePath, (err, stat) => {
    if (err || !stat.isFile()) {
      res.writeHead(404);
      res.end("Not found");
      return;
    }

    const headers = {
      "Content-Type": contentType(filePath),
      "Cache-Control": filePath.endsWith("index.html") ? "no-store" : "public, max-age=3600"
    };

    const range = req.headers.range;
    if (range) {
      const match = range.match(/bytes=(\d*)-(\d*)/);
      if (match) {
        const start = match[1] ? Number(match[1]) : 0;
        const end = match[2] ? Number(match[2]) : stat.size - 1;
        if (start <= end && end < stat.size) {
          res.writeHead(206, {
            ...headers,
            "Accept-Ranges": "bytes",
            "Content-Range": `bytes ${start}-${end}/${stat.size}`,
            "Content-Length": end - start + 1
          });
          fs.createReadStream(filePath, { start, end }).pipe(res);
          return;
        }
      }
    }

    res.writeHead(200, { ...headers, "Content-Length": stat.size });
    fs.createReadStream(filePath).pipe(res);
  });
}

function sendLocalAppZip(res) {
  const archive = new ZipArchive({ zlib: { level: 9 } });

  archive.on("warning", (err) => {
    if (err.code !== "ENOENT") {
      console.warn(err);
    }
  });

  archive.on("error", (err) => {
    console.error(err);
    if (!res.headersSent) {
      res.writeHead(500);
    }
    res.end();
  });

  res.writeHead(200, {
    "Content-Type": "application/zip",
    "Content-Disposition": "attachment; filename=\"5k-resolution-demo-local.zip\"",
    "Cache-Control": "no-store"
  });

  archive.pipe(res);

  localPackageFiles.forEach((name) => {
    const filePath = path.join(root, name);
    if (fs.existsSync(filePath)) {
      archive.file(filePath, { name });
    }
  });
  archive.append("", { name: "images/.keep" });
  archive.finalize();
}

function safeName(name) {
  return path.basename(name).replace(/[^\w\u4e00-\u9fff ().\-[\]]+/g, "_");
}

function filesInDir(dir, prefix) {
  if (!fs.existsSync(dir)) return [];
  return fs.readdirSync(dir)
    .filter((name) => allowedMediaExt.has(path.extname(name).toLowerCase()))
    .map((name) => {
      const filePath = path.join(dir, name);
      const stat = fs.statSync(filePath);
      return { name, src: `${prefix}/${encodeURIComponent(name)}`, modifiedAt: stat.mtimeMs };
    });
}

function isAllowedDriveFile(file) {
  const ext = path.extname(file.name || "").toLowerCase();
  return allowedMediaExt.has(ext);
}

function driveMediaSrc(fileId, name) {
  return `/drive-media/${encodeURIComponent(fileId)}/${encodeURIComponent(name)}`;
}

async function driveFiles() {
  if (!googleDriveFolderId || !googleDriveApiKey) {
    return [];
  }

  const files = [];
  let pageToken = "";
  do {
    const params = new URLSearchParams({
      key: googleDriveApiKey,
      q: `'${googleDriveFolderId}' in parents and trashed=false`,
      fields: "nextPageToken,files(id,name,mimeType,modifiedTime,size,thumbnailLink)",
      pageSize: "1000",
      orderBy: "name"
    });
    if (pageToken) params.set("pageToken", pageToken);

    const response = await fetch(`https://www.googleapis.com/drive/v3/files?${params.toString()}`);
    if (!response.ok) {
      throw new Error(`Google Drive API failed: ${response.status}`);
    }
    const data = await response.json();
    (data.files || []).filter(isAllowedDriveFile).forEach((file) => {
      files.push({
        name: file.name,
        src: driveMediaSrc(file.id, file.name),
        modifiedAt: file.modifiedTime ? Date.parse(file.modifiedTime) : 0,
        thumbnailSrc: file.thumbnailLink || "",
        source: "google-drive"
      });
    });
    pageToken = data.nextPageToken || "";
  } while (pageToken);

  return files;
}

async function mediaFiles() {
  const files = [
    ...filesInDir(bundledImagesDir, "images"),
    ...(mediaDir === bundledImagesDir ? [] : filesInDir(mediaDir, "media")),
    ...await driveFiles()
  ];
  const seen = new Set();
  return files
    .filter((file) => {
      const key = file.src;
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    })
    .sort((a, b) => a.name.localeCompare(b.name, "zh-Hant"));
}

function isAuthorized(req, url) {
  if (!adminPassword) return false;
  const header = req.headers.authorization || "";
  const bearer = header.startsWith("Bearer ") ? header.slice(7) : "";
  return bearer === adminPassword || url.searchParams.get("key") === adminPassword;
}

function adminPage() {
  const enabled = Boolean(adminPassword);
  return `<!doctype html>
<html lang="zh-Hant">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>展示素材上傳</title>
<style>
  body{margin:0;background:#121212;color:#f6efe5;font-family:"Microsoft JhengHei",system-ui,sans-serif}
  main{max-width:720px;margin:0 auto;padding:32px 18px}
  h1{font-size:28px;margin:0 0 12px}
  p{color:#d7c8b8;line-height:1.7}
  form{display:grid;gap:14px;padding:18px;border:1px solid #4a3926;border-radius:12px;background:#1b1a18}
  input,button{font:inherit}
  input{padding:12px;border-radius:8px;border:1px solid #6a5844;background:#0d0d0d;color:#fff}
  button{padding:12px 14px;border:1px solid #b57b3c;border-radius:8px;background:#4a3019;color:#ffe3bf;cursor:pointer}
  .note{font-size:14px;color:#baa996}
</style>
<main>
  <h1>展示素材上傳</h1>
  <p>可上傳 PNG、JPG、WEBP、MP4、WEBM、MKV。若部署在 Zeabur，請把 <code>MEDIA_DIR</code> 指到已掛載 Volume 的資料夾，才會在重啟後保留。</p>
  ${enabled ? `<form method="post" action="/api/upload?key=" enctype="multipart/form-data" onsubmit="this.action='/api/upload?key='+encodeURIComponent(document.querySelector('#key').value)">
    <input id="key" type="password" placeholder="管理密碼" required>
    <input type="file" name="media" accept=".png,.jpg,.jpeg,.webp,.mp4,.webm,.mkv" multiple required>
    <button type="submit">上傳素材</button>
    <div class="note">上傳完成後回到首頁重新整理即可看到素材。</div>
  </form>` : `<p class="note">尚未設定 <code>ADMIN_PASSWORD</code>，上傳功能目前關閉。</p>`}
</main>`;
}

function handleUpload(req, res, url) {
  if (!isAuthorized(req, url)) {
    res.writeHead(401, { "Content-Type": "text/plain; charset=utf-8" });
    res.end("未授權，請確認管理密碼。");
    return;
  }

  fs.mkdirSync(mediaDir, { recursive: true });
  const busboy = Busboy({ headers: req.headers, limits: { fileSize: 1024 * 1024 * 1024 } });
  const saved = [];
  let rejected = false;

  busboy.on("file", (_field, file, info) => {
    const filename = safeName(info.filename || "upload");
    const ext = path.extname(filename).toLowerCase();
    if (!allowedMediaExt.has(ext)) {
      rejected = true;
      file.resume();
      return;
    }

    const target = path.join(mediaDir, `${Date.now()}-${filename}`);
    saved.push(path.basename(target));
    file.pipe(fs.createWriteStream(target));
  });

  busboy.on("finish", () => {
    if (rejected) {
      res.writeHead(400, { "Content-Type": "text/plain; charset=utf-8" });
      res.end("有檔案格式不支援，已略過。");
      return;
    }
    res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
    res.end(`<meta charset="utf-8"><p>已上傳 ${saved.length} 個檔案。</p><p><a href="/">回首頁</a>　<a href="/admin">繼續上傳</a></p>`);
  });

  req.pipe(busboy);
}

async function handleRequest(req, res) {
  try {
    const url = new URL(req.url, `http://${req.headers.host || "localhost"}`);
    if (url.pathname === "/api/media") {
      let files = [];
      let driveError = "";
      try {
        files = await mediaFiles();
      } catch (err) {
        driveError = err.message || "Google Drive 讀取失敗";
        files = [
          ...filesInDir(bundledImagesDir, "images"),
          ...(mediaDir === bundledImagesDir ? [] : filesInDir(mediaDir, "media"))
        ];
      }
      sendJson(res, {
        files,
        drive: {
          enabled: Boolean(googleDriveFolderId),
          configured: Boolean(googleDriveApiKey),
          folderUrl: googleDriveFolderUrl,
          error: driveError
        }
      });
      return;
    }

    if (url.pathname === "/api/drive-config") {
      sendJson(res, {
        enabled: Boolean(googleDriveFolderId),
        configured: Boolean(googleDriveApiKey),
        folderUrl: googleDriveFolderUrl
      });
      return;
    }

    if (url.pathname === "/api/app-root") {
      sendJson(res, { root });
      return;
    }

    if (url.pathname === "/download-local-app") {
      sendLocalAppZip(res);
      return;
    }

    if (url.pathname === "/admin") {
      res.writeHead(200, { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store" });
      res.end(adminPage());
      return;
    }

    if (url.pathname === "/api/upload" && req.method === "POST") {
      handleUpload(req, res, url);
      return;
    }

    if (url.pathname.startsWith("/media/")) {
      const name = decodeURIComponent(url.pathname.slice("/media/".length));
      const filePath = path.resolve(mediaDir, name);
      if (!filePath.startsWith(mediaDir + path.sep)) {
        res.writeHead(403);
        res.end("Forbidden");
        return;
      }
      sendFile(req, res, filePath);
      return;
    }

    if (url.pathname.startsWith("/drive-media/")) {
      const parts = url.pathname.slice("/drive-media/".length).split("/");
      const fileId = decodeURIComponent(parts[0] || "");
      if (!/^[a-zA-Z0-9_-]+$/.test(fileId)) {
        res.writeHead(403);
        res.end("Forbidden");
        return;
      }
      res.writeHead(302, {
        Location: `https://drive.google.com/uc?export=download&id=${encodeURIComponent(fileId)}`,
        "Cache-Control": "public, max-age=300"
      });
      res.end();
      return;
    }

    const relative = url.pathname === "/" ? "index.html" : decodeURIComponent(url.pathname.slice(1));
    const filePath = path.resolve(root, relative);
    if (!filePath.startsWith(root + path.sep) && filePath !== root) {
      res.writeHead(403);
      res.end("Forbidden");
      return;
    }

    sendFile(req, res, filePath);
  } catch (err) {
    console.error(err);
    res.writeHead(500);
    res.end("Server error");
  }
}

function listenWithFallback(index = 0) {
  const port = fallbackPorts[index];
  const server = http.createServer(handleRequest);
  server.once("error", (err) => {
    if ((err.code === "EADDRINUSE" || err.code === "EACCES") && index < fallbackPorts.length - 1) {
      console.warn(`Port ${port} is unavailable, trying ${fallbackPorts[index + 1]}...`);
      listenWithFallback(index + 1);
      return;
    }
    throw err;
  });
  server.listen(port, () => {
    console.log(`5K resolution demo is running on http://localhost:${port}`);
  });
}

listenWithFallback();
