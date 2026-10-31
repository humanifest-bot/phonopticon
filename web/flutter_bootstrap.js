{{flutter_js}}
{{flutter_build_config}}
// Local experiment builds must not reuse a simulator-only main.dart.js from a
// prior preview. A new URL bypasses both HTTP and legacy Flutter resource caches.
for (const build of _flutter.buildConfig.builds) {
  if (build.mainJsPath) build.mainJsPath += '?localPreview=' + Date.now();
}
_flutter.loader.load();
