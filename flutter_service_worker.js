'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"assets/AssetManifest.bin": "b31b761378e0ddceccba00e7353f222b",
"assets/AssetManifest.bin.json": "9a362d2f00ace26a028ff5851c60959a",
"assets/AssetManifest.json": "0d42a68d5ba629f3865b1183fbc922e6",
"assets/assets/config/app_defaults.yaml": "c42b8f35ef71677ab8cc21dfe4c33008",
"assets/assets/data/diary.json": "58e0494c51d30eb3494f7c9198986bb9",
"assets/assets/data/fitness_entries.json": "58e0494c51d30eb3494f7c9198986bb9",
"assets/assets/data/history.txt": "f8473da7db7f9cbb66af59d0c356dd8d",
"assets/assets/data/kana_exam.json": "58e0494c51d30eb3494f7c9198986bb9",
"assets/assets/data/kana_practice.json": "0d54fd1b38cd49b30ec0e9337c300210",
"assets/assets/data/seed-phrases.txt": "0757ed9fc8167f38686c7de5460146c5",
"assets/assets/data/seed-sentences.txt": "c69bb1528175679e2ba119e99434be92",
"assets/assets/data/seed-words.txt": "457dcc0836d4a4fed4eb959f33fe5463",
"assets/assets/data/sense-notes.md": "19851a6f8f37d57316bca15ffdcb4767",
"assets/assets/data/sentences.txt": "afa71540db5b9fe2ae149fd2e478e0d7",
"assets/assets/data/usage-notes.md": "5cf3b5efbe5423c055f00bd5d1bfd83c",
"assets/assets/data/word-choices.md": "bee2e0e2120c6019cbad559df309d207",
"assets/assets/data/words.txt": "bc7e42092bc81b5750bdcb835919bf9d",
"assets/assets/data/yt_tracker_categories.json": "9a828454dfac84a3dba1a3a40de18ddc",
"assets/assets/data/yt_tracker_channels.json": "c08f1a90573d660d08efa1037899d60a",
"assets/assets/images/app_logo/logo.png": "23ed3e8e7c321fbfc58c053ac7966d78",
"assets/assets/images/fitness/setting_icon.png": "190732e8bb1fa35ea038dbe8d021ceb6",
"assets/assets/images/fitness/stats_icon.png": "9e567479ad47d1d203a9776c3c08e5ac",
"assets/assets/images/nav_icons/debug.png": "45ae419e8ccae79c1d18eb26241f4cdc",
"assets/assets/images/nav_icons/diary.png": "f71988feb22a02c8e866fded4e4ae88b",
"assets/assets/images/nav_icons/fitness.png": "66e9c409fd3cb1d0009d2c994f8bf30b",
"assets/assets/images/nav_icons/language.png": "56901a12b24c7c673293368c9da03775",
"assets/assets/images/nav_icons/yt_tracker.png": "58c94f9073ffc9e9329acb680a1a44df",
"assets/assets/images/nav_icons/yt_tracker002.png": "b8a9d31736d4547bfad566f79df21a57",
"assets/assets/images/user_profile/user_profile.png": "617cc1b9a125a10347285fb7dfb9d39c",
"assets/assets/images/yt_tracker/all.png": "ddf3f07d7837197721e8571a864893df",
"assets/assets/images/yt_tracker/crypto.png": "7928d04dd40b2654cb1d9f971fc29fcf",
"assets/assets/images/yt_tracker/current_affairs.png": "3eb4af02c9c57c34ca2f17bdac6d9ac9",
"assets/assets/images/yt_tracker/disliked.png": "f58e3d15145210f52277c41f86abc891",
"assets/assets/images/yt_tracker/entertainment.png": "fca37dff40891701af408433e91e3231",
"assets/assets/images/yt_tracker/food.png": "f9ba5374fe7eabffa59c1d2a609781ee",
"assets/assets/images/yt_tracker/games.png": "f14071bb0d712a0d91051021d00c8e33",
"assets/assets/images/yt_tracker/music.png": "0025704ee793936e15aec0f17a339eb6",
"assets/assets/images/yt_tracker/travel.png": "37f84956b699a2b7e0fb1b3c465c2ebb",
"assets/FontManifest.json": "7b2a36307916a9721811788013e65289",
"assets/fonts/MaterialIcons-Regular.otf": "5d37ccda376f980601e4785068174e55",
"assets/NOTICES": "3ec0ed9a2fad402f40c60dfcff726028",
"assets/shaders/ink_sparkle.frag": "ecc85a2e95f5e9f53123dcaf8cb9b6ce",
"canvaskit/canvaskit.js": "140ccb7d34d0a55065fbd422b843add6",
"canvaskit/canvaskit.js.symbols": "58832fbed59e00d2190aa295c4d70360",
"canvaskit/canvaskit.wasm": "07b9f5853202304d3b0749d9306573cc",
"canvaskit/chromium/canvaskit.js": "5e27aae346eee469027c80af0751d53d",
"canvaskit/chromium/canvaskit.js.symbols": "193deaca1a1424049326d4a91ad1d88d",
"canvaskit/chromium/canvaskit.wasm": "24c77e750a7fa6d474198905249ff506",
"canvaskit/skwasm.js": "1ef3ea3a0fec4569e5d531da25f34095",
"canvaskit/skwasm.js.symbols": "0088242d10d7e7d6d2649d1fe1bda7c1",
"canvaskit/skwasm.wasm": "264db41426307cfc7fa44b95a7772109",
"canvaskit/skwasm_heavy.js": "413f5b2b2d9345f37de148e2544f584f",
"canvaskit/skwasm_heavy.js.symbols": "3c01ec03b5de6d62c34e17014d1decd3",
"canvaskit/skwasm_heavy.wasm": "8034ad26ba2485dab2fd49bdd786837b",
"favicon.png": "a9c92d663e361ada70f34d1d871f42a4",
"favicon.svg": "027d7430d051456c4b9fe44220e44466",
"flutter.js": "888483df48293866f9f41d3d9274a779",
"flutter_bootstrap.js": "a375c6c1b22eb5dc4f3973414fc52ea0",
"icons/Icon-192.png": "1fe7a5a9ddd2f70b4f6757412e10798e",
"icons/Icon-512.png": "7ce93eb952bc3ba66ac88e63cb9a3b62",
"icons/Icon-maskable-192.png": "cfca6ab9f6d02cb416b83165d0b81c22",
"icons/Icon-maskable-512.png": "8cb94c2ffab5cedeb3b59141871022ee",
"index.html": "0625f78d3b277c991bc1c28ed82e8f5c",
"/": "0625f78d3b277c991bc1c28ed82e8f5c",
"main.dart.js": "373f11cc4016036a3fac3d25eb696cbc",
"manifest.json": "f96ea3fa7f2311b731f99b5f8a07dec5",
"version.json": "1c0e216e937d0bcb2aea9e7bc937d959"};
// The application shell files that are downloaded before a service worker can
// start.
const CORE = ["main.dart.js",
"index.html",
"flutter_bootstrap.js",
"assets/AssetManifest.bin.json",
"assets/FontManifest.json"];

// During install, the TEMP cache is populated with the application shell files.
self.addEventListener("install", (event) => {
  self.skipWaiting();
  return event.waitUntil(
    caches.open(TEMP).then((cache) => {
      return cache.addAll(
        CORE.map((value) => new Request(value, {'cache': 'reload'})));
    })
  );
});
// During activate, the cache is populated with the temp files downloaded in
// install. If this service worker is upgrading from one with a saved
// MANIFEST, then use this to retain unchanged resource files.
self.addEventListener("activate", function(event) {
  return event.waitUntil(async function() {
    try {
      var contentCache = await caches.open(CACHE_NAME);
      var tempCache = await caches.open(TEMP);
      var manifestCache = await caches.open(MANIFEST);
      var manifest = await manifestCache.match('manifest');
      // When there is no prior manifest, clear the entire cache.
      if (!manifest) {
        await caches.delete(CACHE_NAME);
        contentCache = await caches.open(CACHE_NAME);
        for (var request of await tempCache.keys()) {
          var response = await tempCache.match(request);
          await contentCache.put(request, response);
        }
        await caches.delete(TEMP);
        // Save the manifest to make future upgrades efficient.
        await manifestCache.put('manifest', new Response(JSON.stringify(RESOURCES)));
        // Claim client to enable caching on first launch
        self.clients.claim();
        return;
      }
      var oldManifest = await manifest.json();
      var origin = self.location.origin;
      for (var request of await contentCache.keys()) {
        var key = request.url.substring(origin.length + 1);
        if (key == "") {
          key = "/";
        }
        // If a resource from the old manifest is not in the new cache, or if
        // the MD5 sum has changed, delete it. Otherwise the resource is left
        // in the cache and can be reused by the new service worker.
        if (!RESOURCES[key] || RESOURCES[key] != oldManifest[key]) {
          await contentCache.delete(request);
        }
      }
      // Populate the cache with the app shell TEMP files, potentially overwriting
      // cache files preserved above.
      for (var request of await tempCache.keys()) {
        var response = await tempCache.match(request);
        await contentCache.put(request, response);
      }
      await caches.delete(TEMP);
      // Save the manifest to make future upgrades efficient.
      await manifestCache.put('manifest', new Response(JSON.stringify(RESOURCES)));
      // Claim client to enable caching on first launch
      self.clients.claim();
      return;
    } catch (err) {
      // On an unhandled exception the state of the cache cannot be guaranteed.
      console.error('Failed to upgrade service worker: ' + err);
      await caches.delete(CACHE_NAME);
      await caches.delete(TEMP);
      await caches.delete(MANIFEST);
    }
  }());
});
// The fetch handler redirects requests for RESOURCE files to the service
// worker cache.
self.addEventListener("fetch", (event) => {
  if (event.request.method !== 'GET') {
    return;
  }
  var origin = self.location.origin;
  var key = event.request.url.substring(origin.length + 1);
  // Redirect URLs to the index.html
  if (key.indexOf('?v=') != -1) {
    key = key.split('?v=')[0];
  }
  if (event.request.url == origin || event.request.url.startsWith(origin + '/#') || key == '') {
    key = '/';
  }
  // If the URL is not the RESOURCE list then return to signal that the
  // browser should take over.
  if (!RESOURCES[key]) {
    return;
  }
  // If the URL is the index.html, perform an online-first request.
  if (key == '/') {
    return onlineFirst(event);
  }
  event.respondWith(caches.open(CACHE_NAME)
    .then((cache) =>  {
      return cache.match(event.request).then((response) => {
        // Either respond with the cached resource, or perform a fetch and
        // lazily populate the cache only if the resource was successfully fetched.
        return response || fetch(event.request).then((response) => {
          if (response && Boolean(response.ok)) {
            cache.put(event.request, response.clone());
          }
          return response;
        });
      })
    })
  );
});
self.addEventListener('message', (event) => {
  // SkipWaiting can be used to immediately activate a waiting service worker.
  // This will also require a page refresh triggered by the main worker.
  if (event.data === 'skipWaiting') {
    self.skipWaiting();
    return;
  }
  if (event.data === 'downloadOffline') {
    downloadOffline();
    return;
  }
});
// Download offline will check the RESOURCES for all files not in the cache
// and populate them.
async function downloadOffline() {
  var resources = [];
  var contentCache = await caches.open(CACHE_NAME);
  var currentContent = {};
  for (var request of await contentCache.keys()) {
    var key = request.url.substring(origin.length + 1);
    if (key == "") {
      key = "/";
    }
    currentContent[key] = true;
  }
  for (var resourceKey of Object.keys(RESOURCES)) {
    if (!currentContent[resourceKey]) {
      resources.push(resourceKey);
    }
  }
  return contentCache.addAll(resources);
}
// Attempt to download the resource online before falling back to
// the offline cache.
function onlineFirst(event) {
  return event.respondWith(
    fetch(event.request).then((response) => {
      return caches.open(CACHE_NAME).then((cache) => {
        cache.put(event.request, response.clone());
        return response;
      });
    }).catch((error) => {
      return caches.open(CACHE_NAME).then((cache) => {
        return cache.match(event.request).then((response) => {
          if (response != null) {
            return response;
          }
          throw error;
        });
      });
    })
  );
}
