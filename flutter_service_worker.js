'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"assets/AssetManifest.bin": "9459b091925e0582f98295d032d1e4bf",
"assets/AssetManifest.bin.json": "95bb3f30f15e62bd7f7951c376805471",
"assets/AssetManifest.json": "1ad22af21548811d8264af74045de9b3",
"assets/assets/config/app_defaults.yaml": "f52eccc6d8df9e48f90e659277eea80d",
"assets/assets/data/diary.json": "58e0494c51d30eb3494f7c9198986bb9",
"assets/assets/data/fitness_entries.json": "58e0494c51d30eb3494f7c9198986bb9",
"assets/assets/data/history.txt": "3df901a2c5fdc8066ca8f3a7d2eb22fb",
"assets/assets/data/kana_exam.json": "58e0494c51d30eb3494f7c9198986bb9",
"assets/assets/data/kana_practice.json": "0d54fd1b38cd49b30ec0e9337c300210",
"assets/assets/data/seed-phrases.txt": "0757ed9fc8167f38686c7de5460146c5",
"assets/assets/data/seed-sentences.txt": "c69bb1528175679e2ba119e99434be92",
"assets/assets/data/seed-words.txt": "457dcc0836d4a4fed4eb959f33fe5463",
"assets/assets/data/sense-notes.md": "19851a6f8f37d57316bca15ffdcb4767",
"assets/assets/data/sentences.txt": "afa71540db5b9fe2ae149fd2e478e0d7",
"assets/assets/data/usage-notes.md": "5cf3b5efbe5423c055f00bd5d1bfd83c",
"assets/assets/data/word-choices.md": "bee2e0e2120c6019cbad559df309d207",
"assets/assets/data/words.txt": "b460052af98615849c71f44a59bb2ab4",
"assets/assets/data/yt_tracker_categories.json": "0a563a8e4d3373def3fbcfd84127ea71",
"assets/assets/data/yt_tracker_channels.json": "11381135c61dc69af911477114785c0e",
"assets/assets/images/app_logo/logo.png": "bf62f559c24560e6490d5930fbc2962e",
"assets/assets/images/fitness/setting_icon.png": "190732e8bb1fa35ea038dbe8d021ceb6",
"assets/assets/images/fitness/stats_icon.png": "9e567479ad47d1d203a9776c3c08e5ac",
"assets/assets/images/nav_icons/debug.png": "45ae419e8ccae79c1d18eb26241f4cdc",
"assets/assets/images/nav_icons/diary.png": "f71988feb22a02c8e866fded4e4ae88b",
"assets/assets/images/nav_icons/fitness.png": "66e9c409fd3cb1d0009d2c994f8bf30b",
"assets/assets/images/nav_icons/language.png": "56901a12b24c7c673293368c9da03775",
"assets/assets/images/nav_icons/yt_tracker.png": "58c94f9073ffc9e9329acb680a1a44df",
"assets/assets/images/nav_icons/yt_tracker002.png": "b8a9d31736d4547bfad566f79df21a57",
"assets/assets/images/user_profile/user_profile.png": "617cc1b9a125a10347285fb7dfb9d39c",
"assets/assets/images/yt_tracker/all.png": "7ade7f0f5f1c32d7c32b99630a84f2b5",
"assets/assets/images/yt_tracker/car.png": "a3f05a0846132a322cec6371b0cde8cf",
"assets/assets/images/yt_tracker/crypto.png": "a07520a245aeacd1a289a0a14b5cc61f",
"assets/assets/images/yt_tracker/current_affairs.png": "3eb4af02c9c57c34ca2f17bdac6d9ac9",
"assets/assets/images/yt_tracker/disliked.png": "f58e3d15145210f52277c41f86abc891",
"assets/assets/images/yt_tracker/entertainment.png": "fca37dff40891701af408433e91e3231",
"assets/assets/images/yt_tracker/film_and_television.png": "3081fd9ac95569531fcb8f9469c7ac44",
"assets/assets/images/yt_tracker/food.png": "f9ba5374fe7eabffa59c1d2a609781ee",
"assets/assets/images/yt_tracker/games.png": "f14071bb0d712a0d91051021d00c8e33",
"assets/assets/images/yt_tracker/knowledge.png": "f9880ef016609295f864adf05fdb4c0d",
"assets/assets/images/yt_tracker/life.png": "9d687275999ca0c950b80e15ff8c6e5d",
"assets/assets/images/yt_tracker/music.png": "77b9070437c06d7e4d627187313ae389",
"assets/assets/images/yt_tracker/news.png": "b83c931bf121b614218be2f7a6c5839b",
"assets/assets/images/yt_tracker/study.png": "da8a82a2ab1d412e085976e71571cb9e",
"assets/assets/images/yt_tracker/travel.png": "37f84956b699a2b7e0fb1b3c465c2ebb",
"assets/assets/images/yt_tracker/unboxing.png": "5dd781a51f619becc75844b5be544e6a",
"assets/FontManifest.json": "7b2a36307916a9721811788013e65289",
"assets/fonts/MaterialIcons-Regular.otf": "3285a4a1e637afa54a6bc5151b3cf9a3",
"assets/NOTICES": "036031c694acb19253daa6f693cd37c0",
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
"favicon.png": "aa61c0b19e621cecf4646c189cfab221",
"favicon.svg": "f389abc7848afd594ce4b368cfdb516e",
"flutter.js": "888483df48293866f9f41d3d9274a779",
"flutter_bootstrap.js": "44bd95de0b548619bc93df591e4c00d5",
"icons/Icon-192.png": "240c35e6f89a1a62556d56a6aaa38999",
"icons/Icon-512.png": "52f5fe4099f4338efb1289d24a7cdfe0",
"icons/Icon-maskable-192.png": "d5731d79d8a5c02c0fa1774eb475cefc",
"icons/Icon-maskable-512.png": "eba28d91bd6967c56d4a4cc80cfe0642",
"index.html": "0625f78d3b277c991bc1c28ed82e8f5c",
"/": "0625f78d3b277c991bc1c28ed82e8f5c",
"main.dart.js": "add194383dbbe61b11a44d9790b74a3f",
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
