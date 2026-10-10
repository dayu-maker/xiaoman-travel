/* ============================================================================
   小满出行 · Service Worker
   ----------------------------------------------------------------------------
   作用：缓存核心文件，让页面在断网时也能打开（离线可用）。

   重要限制：Service Worker 只在 https:// 或 http://localhost 下才能注册成功。
   用 file:// 直接双击打开 HTML 时，浏览器会拒绝注册（安全策略），
   这时页面本身照常工作，只是没有离线能力。

   缓存策略：
     · 主页面（HTML）  → 网络优先，失败回落缓存
                         这样你在电脑上改完代码，手机刷新就能拿到新版，
                         不会出现「装了 PWA 后页面永远卡在旧版本」的问题
     · 其他静态资源   → 缓存优先，后台静默更新
     · 高德接口请求   → 完全不拦截，直接走网络（跨域 JSONP）
   ============================================================================ */

var VERSION = 'v1.0.0';
var CACHE_NAME = 'xiaoman-' + VERSION;

/* 需要预先缓存的核心文件（相对路径，按 sw.js 所在位置解析） */
var CORE_ASSETS = [
  './',
  './小满出行.html',
  './manifest.json',
  './assets/icon.svg',
  './assets/intro.mp4'
];

/* ---------- 安装：预缓存核心文件 ---------- */
self.addEventListener('install', function (event) {
  event.waitUntil(
    caches.open(CACHE_NAME).then(function (cache) {
      /* 逐个 add，单个文件失败（比如还没有 intro.mp4）不会让整个安装失败 */
      return Promise.all(CORE_ASSETS.map(function (url) {
        return cache.add(url).catch(function (err) {
          console.info('[小满出行 SW] 跳过预缓存：' + url + '（' + err.message + '）');
        });
      }));
    }).then(function () {
      return self.skipWaiting();   // 新版本立即接管，不用等所有标签页关闭
    })
  );
});

/* ---------- 激活：清理旧版本缓存 ---------- */
self.addEventListener('activate', function (event) {
  event.waitUntil(
    caches.keys().then(function (keys) {
      return Promise.all(keys.map(function (key) {
        if (key !== CACHE_NAME && key.indexOf('xiaoman-') === 0) {
          console.info('[小满出行 SW] 删除旧缓存：' + key);
          return caches.delete(key);
        }
      }));
    }).then(function () {
      return self.clients.claim();  // 立刻控制已打开的页面
    })
  );
});

/* ---------- 拦截请求 ---------- */
self.addEventListener('fetch', function (event) {
  var req = event.request;

  /* 只处理 GET */
  if (req.method !== 'GET') return;

  var url = new URL(req.url);

  /* 跨域请求（高德接口等）一律不拦截，交给浏览器 */
  if (url.origin !== self.location.origin) return;

  /* 主页面：网络优先 —— 保证能拿到最新版本，离线时才用缓存 */
  var isDocument = req.mode === 'navigate' ||
                   (req.headers.get('accept') || '').indexOf('text/html') >= 0;
  if (isDocument) {
    event.respondWith(
      fetch(req).then(function (res) {
        var copy = res.clone();
        caches.open(CACHE_NAME).then(function (c) { c.put(req, copy); });
        return res;
      }).catch(function () {
        return caches.match(req).then(function (hit) {
          return hit || caches.match('./小满出行.html');
        });
      })
    );
    return;
  }

  /* 其他静态资源：缓存优先 + 后台更新 */
  event.respondWith(
    caches.match(req).then(function (hit) {
      if (hit) {
        /* 后台顺手更新一份，下次打开就是新的 */
        fetch(req).then(function (res) {
          if (res && res.status === 200 && res.type === 'basic') {
            caches.open(CACHE_NAME).then(function (c) { c.put(req, res.clone()); });
          }
        }).catch(function () {});
        return hit;
      }
      return fetch(req).then(function (res) {
        if (res && res.status === 200 && res.type === 'basic') {
          var copy = res.clone();
          caches.open(CACHE_NAME).then(function (c) { c.put(req, copy); });
        }
        return res;
      });
    })
  );
});

/* ---------- 支持页面主动触发「立即更新」 ---------- */
self.addEventListener('message', function (event) {
  if (event.data === 'skipWaiting') self.skipWaiting();
});
