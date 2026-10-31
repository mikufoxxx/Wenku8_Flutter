import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../legacy_transport.dart';

export 'current_release_content.dart'
    show currentReleaseNotes, publicReleaseNotes;

const officialUpdateRepository = 'mikufoxxx/Wenku8_Flutter';
const updateMirrorOrigin = 'https://git.3952039.xyz';
const updateRepository = String.fromEnvironment(
  'UPDATE_REPOSITORY',
  defaultValue: officialUpdateRepository,
);
const currentAppVersion = '0.5.4';
const currentAppBuild = 2274;

class ReleaseVersion implements Comparable<ReleaseVersion> {
  const ReleaseVersion(this.major, this.minor, this.patch, [this.build = 0]);
  final int major, minor, patch, build;
  static ReleaseVersion? parse(String value) {
    final match = RegExp(
      r'^v?(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?$',
    ).firstMatch(value);
    if (match == null) return null;
    final parts = [for (var i = 1; i <= 4; i++) int.tryParse(match[i] ?? '0')];
    if (parts.any((n) => n == null || n > 2100000000)) return null;
    return ReleaseVersion(parts[0]!, parts[1]!, parts[2]!, parts[3]!);
  }

  String get name => '$major.$minor.$patch';
  @override
  int compareTo(ReleaseVersion other) {
    for (final pair in [
      (major, other.major),
      (minor, other.minor),
      (patch, other.patch),
      (build, other.build),
    ]) {
      final result = pair.$1.compareTo(pair.$2);
      if (result != 0) return result;
    }
    return 0;
  }
}

class InstalledApp {
  const InstalledApp({
    required this.version,
    required this.build,
    required this.abis,
  });
  final String version;
  final int build;
  final List<String> abis;
  ReleaseVersion? get releaseVersion {
    final parsed = ReleaseVersion.parse(version);
    return parsed == null
        ? null
        : ReleaseVersion(parsed.major, parsed.minor, parsed.patch, build);
  }
}

class UpdateAsset {
  const UpdateAsset({
    required this.name,
    required this.url,
    required this.size,
    this.id,
    this.digest,
  });
  final String name;
  final Uri url;
  final int size;
  final int? id;
  final String? digest;

  bool samePackage(UpdateAsset other) =>
      id == other.id &&
      name == other.name &&
      url == other.url &&
      size == other.size &&
      digest == other.digest;
}

class AppRelease {
  const AppRelease({
    required this.tag,
    required this.version,
    required this.notes,
    required this.page,
    required this.assets,
  });
  final String tag, notes;
  final ReleaseVersion version;
  final Uri page;
  final List<UpdateAsset> assets;
  static AppRelease? fromGithub(Map<String, dynamic> json, String repository) {
    if (!RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$').hasMatch(repository)) {
      throw const FormatException('更新仓库格式错误');
    }
    if (json['draft'] == true || json['prerelease'] == true) return null;
    final tag = json['tag_name'];
    final version = tag is String ? ReleaseVersion.parse(tag) : null;
    if (version == null) return null;
    final assets = <UpdateAsset>[];
    for (final raw in (json['assets'] as List? ?? const [])) {
      if (raw is! Map) continue;
      final name = raw['name'];
      final url = Uri.tryParse(raw['browser_download_url']?.toString() ?? '');
      final size = raw['size'];
      if (name is! String ||
          !name.startsWith('wenku8-${version.name}-') ||
          !const ['.apk', '.ipa', '.hap'].any(name.endsWith) ||
          url == null ||
          url.scheme != 'https' ||
          url.host != 'github.com' ||
          url.userInfo.isNotEmpty ||
          url.port != 443 ||
          !listEquals(url.pathSegments, [
            ...repository.split('/'),
            'releases',
            'download',
            tag,
            name,
          ]) ||
          size is! int ||
          size <= 0 ||
          size > 300 * 1024 * 1024) {
        continue;
      }
      final digest = raw['digest']?.toString();
      assets.add(
        UpdateAsset(
          name: name,
          url: url,
          size: size,
          id: raw['id'] is int ? raw['id'] as int : null,
          digest:
              digest != null &&
                  RegExp(r'^sha256:[a-fA-F0-9]{64}$').hasMatch(digest)
              ? digest.substring(7).toLowerCase()
              : null,
        ),
      );
    }
    return AppRelease(
      tag: tag as String,
      version: version,
      notes: json['body'] is String ? json['body'] as String : '',
      page: Uri.https('github.com', '/$repository/releases/tag/$tag'),
      assets: assets,
    );
  }

  bool isNewerThan(InstalledApp app) {
    final installed = app.releaseVersion;
    if (installed == null) return false;
    final semantic = ReleaseVersion(version.major, version.minor, version.patch)
        .compareTo(
          ReleaseVersion(installed.major, installed.minor, installed.patch),
        );
    return semantic > 0 || (semantic == 0 && version.build > installed.build);
  }

  UpdateAsset? assetFor(List<String> abis) {
    for (final abi in abis) {
      for (final asset in assets) {
        if (asset.name.endsWith('-$abi.apk')) return asset;
      }
    }
    for (final asset in assets) {
      if (asset.name.endsWith('-universal.apk')) return asset;
    }
    return null;
  }
}

class UpdatePackageInfo {
  const UpdatePackageInfo({required this.version, required this.build});
  final String version;
  final int build;
}

abstract interface class UpdatePlatform {
  Future<InstalledApp> installedApp();
  Future<UpdatePackageInfo> inspect(File apk, String version, {int? build});
  Future<String> install(File apk, String version, {int? build});
  Future<void> allowInstalls();
  Future<void> openRelease(Uri page);
}

class AndroidUpdatePlatform implements UpdatePlatform {
  static const channel = MethodChannel('org.mewx.wenku8/app_updates');
  @override
  Future<InstalledApp> installedApp() async {
    final info = await channel.invokeMapMethod<String, dynamic>('info');
    if (info == null) throw const FormatException('无法读取当前版本');
    return InstalledApp(
      version: info['version'] as String,
      build: info['build'] as int,
      abis: (info['abis'] as List).cast<String>(),
    );
  }

  @override
  Future<UpdatePackageInfo> inspect(
    File apk,
    String version, {
    int? build,
  }) async {
    final info = await channel.invokeMapMethod<String, dynamic>('inspect', {
      'path': apk.path,
      'version': version,
      'build': build,
    });
    if (info == null) throw const FormatException('无法验证安装包，请重新下载');
    return UpdatePackageInfo(
      version: info['version'] as String,
      build: (info['build'] as num).toInt(),
    );
  }

  @override
  Future<String> install(File apk, String version, {int? build}) async =>
      await channel.invokeMethod<String>('install', {
        'path': apk.path,
        'version': version,
        'build': build,
      }) ??
      'opened';
  @override
  Future<void> allowInstalls() => channel.invokeMethod<void>('allowInstalls');
  @override
  Future<void> openRelease(Uri page) =>
      channel.invokeMethod<void>('openRelease', page.toString());
}

class UpdateCancelled implements Exception {}

/// Transport failures may use the original host. Identity/integrity failures may not.
class UpdateServiceUnavailable extends HttpException {
  const UpdateServiceUnavailable(super.message);
}

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

class UpdateDownload {
  bool cancelled = false;
  HttpClient? _client;
  void cancel() {
    cancelled = true;
    _client?.close(force: true);
  }

  void check() {
    if (cancelled) throw UpdateCancelled();
  }
}

abstract interface class UpdateSource {
  Future<AppRelease?> latest();
  Future<void> download(
    UpdateAsset asset,
    File file,
    UpdateDownload task,
    void Function(int bytes) progress,
  );
}

class GithubUpdateSource implements UpdateSource {
  GithubUpdateSource({
    this.repository = updateRepository,
    this.gateway,
    this.assetExtension,
    HttpClient Function()? clientFactory,
  }) : _clientFactory = clientFactory ?? HttpClient.new;
  final String repository;
  final String? assetExtension;

  /// Canonical release identity stays on GitHub; only transport is mirrored.
  final Uri? gateway;
  final HttpClient Function() _clientFactory;
  Uri _gateway() {
    final uri = gateway!;
    if (uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.port != 443 ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        uri.path.isNotEmpty && uri.path != '/') {
      throw const FormatException('更新镜像地址无效');
    }
    return uri;
  }

  Uri _assetTransport(UpdateAsset asset) {
    if (gateway == null) return asset.url;
    final url = asset.url;
    final parts = url.pathSegments;
    if (url.scheme != 'https' ||
        url.host != 'github.com' ||
        url.userInfo.isNotEmpty ||
        url.port != 443 ||
        url.hasQuery ||
        url.hasFragment ||
        parts.length != 6 ||
        !listEquals(parts.take(2).toList(), repository.split('/')) ||
        parts[2] != 'releases' ||
        parts[3] != 'download' ||
        parts[5] != asset.name) {
      throw const FormatException('安装包下载地址无效');
    }
    return _gateway().replace(
      pathSegments: parts,
      queryParameters: asset.id == null ? null : {'asset': '${asset.id}'},
    );
  }

  @override
  Future<AppRelease?> latest() => _release('latest');

  Future<AppRelease?> _release(String suffix, {UpdateDownload? task}) async {
    if (!RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$').hasMatch(repository)) {
      throw const FormatException('更新仓库格式错误');
    }
    final client = _clientFactory()
      ..connectionTimeout = Duration(seconds: gateway == null ? 12 : 4);
    if (task != null) {
      task.check();
      task._client = client;
    }
    try {
      final request = await client
          .getUrl(
            gateway == null
                ? Uri.https(
                    'api.github.com',
                    assetExtension != null && suffix == 'latest'
                        ? '/repos/$repository/releases'
                        : '/repos/$repository/releases/$suffix',
                    assetExtension != null && suffix == 'latest'
                        ? {'per_page': '100'}
                        : null,
                  )
                : _gateway().resolve(
                    assetExtension == null
                        ? '/api/releases/latest'
                        : '/api/releases/${assetExtension == '.ipa' ? 'ios' : 'harmony'}',
                  ),
          )
          .timeout(Duration(seconds: gateway == null ? 12 : 4));
      if (gateway != null) request.followRedirects = false;
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.github+json',
      );
      request.headers.set(HttpHeaders.userAgentHeader, 'Wenku8-Flutter');
      request.headers.set('X-GitHub-Api-Version', '2022-11-28');
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      final response = await request.close().timeout(
        Duration(seconds: gateway == null ? 20 : 8),
      );
      if (response.statusCode == 404) return null;
      if (response.statusCode != 200) {
        throw UpdateServiceUnavailable('更新服务 ${response.statusCode}');
      }
      final data = <int>[];
      await for (final chunk in response.timeout(
        Duration(seconds: gateway == null ? 20 : 6),
      )) {
        data.addAll(chunk);
        if (data.length > (assetExtension == null ? 1 : 4) * 1024 * 1024) {
          throw const FormatException('版本说明过大');
        }
      }
      Map<String, dynamic> metadata;
      try {
        final value = jsonDecode(utf8.decode(data));
        if (assetExtension != null && gateway == null && suffix == 'latest') {
          if (value is! List) throw const FormatException('版本列表格式错误');
          final candidates =
              value
                  .whereType<Map<String, dynamic>>()
                  .map((item) => AppRelease.fromGithub(item, repository))
                  .whereType<AppRelease>()
                  .where(
                    (item) => item.assets.any(
                      (asset) => asset.name.endsWith(assetExtension!),
                    ),
                  )
                  .toList()
                ..sort((a, b) => b.version.compareTo(a.version));
          return candidates.isEmpty ? null : candidates.first;
        }
        if (value is! Map<String, dynamic>) {
          throw const FormatException('版本说明格式错误');
        }
        metadata = value;
      } on FormatException {
        if (gateway != null) {
          throw const UpdateServiceUnavailable('更新镜像返回无效响应');
        }
        rethrow;
      }
      return AppRelease.fromGithub(metadata, repository);
    } finally {
      client.close(force: true);
      if (task != null) task._client = null;
    }
  }

  @override
  Future<void> download(
    UpdateAsset asset,
    File file,
    UpdateDownload task,
    void Function(int bytes) progress,
  ) async {
    task.check();
    if (gateway == null && asset.id != null) {
      final parts = asset.url.pathSegments;
      if (parts.length != 6 ||
          !listEquals(parts.take(2).toList(), repository.split('/')) ||
          parts[2] != 'releases' ||
          parts[3] != 'download' ||
          parts[5] != asset.name) {
        throw const FormatException('安装包下载地址无效');
      }
      final current = await _release('tags/${parts[4]}', task: task);
      task.check();
      if (current == null || !current.assets.any(asset.samePackage)) {
        throw const FormatException('更新文件已变化，请重新检查版本后下载');
      }
    }
    final client = _clientFactory()
      ..connectionTimeout = Duration(seconds: gateway == null ? 15 : 4);
    task._client = client;
    IOSink? sink;
    try {
      var url = _assetTransport(asset);
      HttpClientResponse? response;
      for (var hop = 0; hop < 6; hop++) {
        task.check();
        if (url.scheme != 'https' ||
            url.userInfo.isNotEmpty ||
            url.port != 443 ||
            !(gateway != null
                    ? {gateway!.host}
                    : const {
                        'github.com',
                        'release-assets.githubusercontent.com',
                        'objects.githubusercontent.com',
                      })
                .contains(url.host)) {
          throw const FormatException('安装包下载地址无效');
        }
        final request = await client
            .getUrl(url)
            .timeout(Duration(seconds: gateway == null ? 15 : 4));
        request.followRedirects = false;
        request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
        final candidate = await request.close().timeout(
          Duration(seconds: gateway == null ? 30 : 8),
        );
        if (const [301, 302, 303, 307, 308].contains(candidate.statusCode)) {
          if (gateway != null) {
            throw const UpdateServiceUnavailable('更新镜像暂不可用');
          }
          final location = candidate.headers.value(HttpHeaders.locationHeader);
          if (location == null) throw const FormatException('下载重定向无效');
          url = url.resolve(location);
          await candidate.drain<void>();
          continue;
        }
        response = candidate;
        break;
      }
      if (response?.statusCode == 409) {
        throw const FormatException('更新文件已变化，请重新检查版本后下载');
      }
      if (response == null || response.statusCode != 200) {
        throw UpdateServiceUnavailable('安装包下载服务 ${response?.statusCode ?? 0}');
      }
      sink = file.openWrite();
      var count = 0;
      final digest = _DigestSink();
      final hashing = asset.digest == null
          ? null
          : sha256.startChunkedConversion(digest);
      await for (final chunk in response.timeout(
        Duration(seconds: gateway == null ? 30 : 10),
      )) {
        task.check();
        count += chunk.length;
        if (count > asset.size) throw const FormatException('安装包大小不匹配');
        hashing?.add(chunk);
        sink.add(chunk);
        progress(count);
      }
      hashing?.close();
      await sink.flush();
      task.check();
      if (count < asset.size) {
        throw const UpdateServiceUnavailable('安装包传输未完成');
      }
      if (asset.digest != null && digest.value.toString() != asset.digest) {
        throw const FormatException('安装包校验失败，请重新下载');
      }
    } finally {
      await sink?.close();
      client.close(force: true);
      task._client = null;
    }
  }
}

class MirrorFirstUpdateSource implements UpdateSource {
  MirrorFirstUpdateSource({
    required this.mirror,
    required this.original,
    this.onRoute,
  });
  final UpdateSource mirror, original;
  final void Function(bool original)? onRoute;

  static bool _canRetry(Object failure) =>
      failure is SocketException ||
      failure is TimeoutException ||
      failure is TlsException ||
      failure is HttpException;

  @override
  Future<AppRelease?> latest() async {
    onRoute?.call(false);
    try {
      return await mirror.latest();
    } catch (failure) {
      if (!_canRetry(failure)) rethrow;
      onRoute?.call(true);
      return original.latest();
    }
  }

  @override
  Future<void> download(
    UpdateAsset asset,
    File file,
    UpdateDownload task,
    void Function(int bytes) progress,
  ) async {
    onRoute?.call(false);
    try {
      await mirror.download(asset, file, task, progress);
    } catch (failure) {
      task.check();
      if (!_canRetry(failure)) rethrow;
      // Never append original-host bytes to a partially downloaded mirror APK.
      if (await file.exists()) await file.delete();
      task.check();
      progress(0);
      onRoute?.call(true);
      await original.download(asset, file, task, progress);
    }
  }
}

class _ReadyUpdate {
  const _ReadyUpdate(this.file, this.tag, this.asset, this.info);
  final File file;
  final String tag;
  final UpdateAsset asset;
  final UpdatePackageInfo info;

  bool matches(AppRelease? release, UpdateAsset? selected) =>
      release?.tag == tag && selected != null && asset.samePackage(selected);
}

class AppUpdates extends ChangeNotifier {
  AppUpdates({
    required this.preferences,
    this.packageUpdates = true,
    this.notificationAssetExtension,
    UpdateSource? source,
    UpdatePlatform? platform,
    Future<Directory> Function()? directory,
    DateTime Function()? clock,
    Future<void> Function(bool)? networkPriority,
  }) : _source = source,
       platform = platform ?? AndroidUpdatePlatform(),
       _directory = directory ?? getTemporaryDirectory,
       _clock = clock ?? DateTime.now,
       _networkPriority =
           networkPriority ??
           (Platform.isAndroid
               ? LegacyTransport.setUpdatePriority
               : (_) async {});
  final SharedPreferences preferences;
  final bool packageUpdates;

  /// Non-Android releases announce a matching artifact but never download/install it.
  final String? notificationAssetExtension;
  bool get checksEnabled =>
      packageUpdates || notificationAssetExtension != null;
  final UpdateSource? _source;
  late final _githubSource = GithubUpdateSource(
    assetExtension: notificationAssetExtension,
  );
  late final _mirrorSource = GithubUpdateSource(
    gateway: Uri.parse(updateMirrorOrigin),
    assetExtension: notificationAssetExtension,
  );
  late final _mirrorFirstSource = MirrorFirstUpdateSource(
    mirror: _mirrorSource,
    original: _githubSource,
  );
  bool get _usesMirror => updateRepository == officialUpdateRepository;
  Uri get projectPage => _usesMirror
      ? Uri.parse(updateMirrorOrigin)
      : Uri.https('github.com', '/$updateRepository');
  Uri get releasePage => _usesMirror
      ? Uri.parse('$updateMirrorOrigin/#releases')
      : release?.page ??
            Uri.https('github.com', '/$updateRepository/releases/');
  UpdateSource get source =>
      _source ?? (_usesMirror ? _mirrorFirstSource : _githubSource);

  Future<void> openProjectPage({bool showRelease = false}) async {
    var page = showRelease ? releasePage : projectPage;
    if (_usesMirror) {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 2);
      try {
        await (() async {
          final request = await client.headUrl(Uri.parse(updateMirrorOrigin));
          request.followRedirects = false;
          final response = await request.close();
          if (response.statusCode != 200) throw const HttpException('项目入口暂不可用');
        })().timeout(const Duration(seconds: 2));
      } catch (_) {
        page = showRelease
            ? release?.page ??
                  Uri.https('github.com', '/$updateRepository/releases/')
            : Uri.https('github.com', '/$updateRepository');
      } finally {
        client.close(force: true);
      }
    }
    await platform.openRelease(page);
  }

  final UpdatePlatform platform;
  final Future<Directory> Function() _directory;
  final DateTime Function() _clock;
  final Future<void> Function(bool) _networkPriority;
  InstalledApp? installed;
  AppRelease? release;
  String? error;
  _ReadyUpdate? _ready;
  File? get downloaded => _ready?.file;
  UpdatePackageInfo? get downloadedInfo => _ready?.info;
  bool checking = false,
      downloading = false,
      checked = false,
      installing = false,
      needsPermission = false;
  int bytes = 0;
  bool _disposed = false;
  UpdateDownload? _download;
  Future<InstalledApp>? _loadingInfo;
  bool get busy => checking || downloading || installing;
  bool get autoCheck => preferences.getBool('checkAppUpdates') ?? true;
  String? get installedReleaseKey =>
      installed == null ? null : '${installed!.version}+${installed!.build}';
  bool get shouldShowReleaseNotes =>
      installedReleaseKey != null &&
      preferences.getString('completedReleaseNotes') != installedReleaseKey;

  Future<void> rememberReleaseNotes(InstalledApp shown) async {
    if (!await preferences.setString(
      'completedReleaseNotes',
      '${shown.version}+${shown.build}',
    )) {
      throw const FileSystemException('更新说明阅读状态保存失败');
    }
    _notify();
  }

  bool get available =>
      checksEnabled &&
      release != null &&
      installed != null &&
      (packageUpdates ||
          release!.assets.any(
            (asset) => asset.name.endsWith(notificationAssetExtension!),
          )) &&
      release!.isNewerThan(installed!);
  UpdateAsset? get asset => !packageUpdates || installed == null
      ? null
      : release?.assetFor(installed!.abis);

  /// Snooze only this release, including across process restarts. A different
  /// release can still be announced immediately; manual updating stays usable.
  bool get shouldPrompt {
    if (!available) return false;
    final previous = preferences.getString('lastAppUpdatePrompt')?.split('|');
    if (previous == null ||
        previous.length != 2 ||
        previous.first != release!.tag) {
      return true;
    }
    final timestamp = int.tryParse(previous.last);
    return timestamp == null ||
        _clock().millisecondsSinceEpoch - timestamp >=
            const Duration(hours: 24).inMilliseconds;
  }

  Future<void> rememberPrompt(AppRelease prompted) async {
    if (!await preferences.setString(
      'lastAppUpdatePrompt',
      '${prompted.tag}|${_clock().millisecondsSinceEpoch}',
    )) {
      throw const FileSystemException('更新提醒保存失败');
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> setAutoCheck(bool value) async {
    if (!await preferences.setBool('checkAppUpdates', value)) {
      throw const FileSystemException('设置保存失败');
    }
    _notify();
  }

  Future<void> loadInstalled({bool refresh = false}) async {
    if (_disposed || (!refresh && installed != null)) return;
    try {
      final value = await (_loadingInfo ??= platform.installedApp());
      if (!_disposed) {
        installed = value;
        if (release != null && !available) {
          _ready = null;
          needsPermission = false;
        }
        _notify();
      }
    } finally {
      _loadingInfo = null;
    }
  }

  Future<void> check({bool automatic = false}) async {
    if (_disposed || busy) return;
    if (!checksEnabled) {
      await loadInstalled();
      return;
    }
    final now = _clock();
    if (automatic && !autoCheck) return;
    checking = true;
    error = null;
    _notify();
    try {
      await _networkPriority(true);
      await loadInstalled(refresh: true);
      final candidate = await source.latest();
      if (_disposed) return;
      if (_ready != null &&
          !_ready!.matches(candidate, candidate?.assetFor(installed!.abis))) {
        _ready = null;
        needsPermission = false;
      }
      release = candidate;
      checked = true;
      await preferences.setInt(
        'lastAppUpdateCheck',
        now.millisecondsSinceEpoch,
      );
    } catch (failure) {
      if (!_disposed) {
        error = '无法检查更新，请检查网络后重试';
      }
    } finally {
      await _networkPriority(false);
      checking = false;
      _notify();
    }
  }

  Future<void> download() async {
    final selected = asset;
    final target = release;
    if (_disposed || busy || !available || selected == null || target == null) {
      return;
    }
    final task = UpdateDownload();
    _download = task;
    downloading = true;
    _ready = null;
    needsPermission = false;
    error = null;
    bytes = 0;
    _notify();
    Directory? attempt;
    var retained = false;
    try {
      await _networkPriority(true);
      final root = Directory('${(await _directory()).path}/updates');
      await root.create(recursive: true);
      // Android stages a content URI asynchronously. Never replace a file that
      // has already been handed to its installer, even for a retry of one tag.
      await _pruneOldDownloads(root);
      task.check();
      attempt = await root.createTemp('package-');
      final part = File('${attempt.path}/pending.apk.part');
      final notificationClock = Stopwatch()..start();
      await source.download(selected, part, task, (count) {
        bytes = count;
        if (notificationClock.elapsedMilliseconds >= 100 ||
            count == selected.size) {
          notificationClock.reset();
          _notify();
        }
      });
      task.check();
      final ready = await part.rename('${attempt.path}/update.apk');
      final info = await platform.inspect(
        ready,
        target.version.name,
        build: target.version.build > 0 ? target.version.build : null,
      );
      task.check();
      if (info.version != target.version.name ||
          info.build <= installed!.build ||
          (target.version.build > 0 && info.build != target.version.build)) {
        throw const FormatException('下载的安装包版本不符，请重新下载');
      }
      final candidate = _ReadyUpdate(ready, target.tag, selected, info);
      if (!candidate.matches(release, asset)) {
        throw const FormatException('更新版本已变化，请重新检查并下载');
      }
      _ready = candidate;
      retained = true;
    } catch (failure) {
      if (!task.cancelled && !_disposed) {
        error = switch (failure) {
          FormatException() => failure.message,
          PlatformException() => failure.message ?? '安装包无法验证，请重新下载',
          _ => '下载失败，请检查网络后重试',
        };
      }
    } finally {
      try {
        if (!retained && attempt != null && await attempt.exists()) {
          await attempt.delete(recursive: true);
        }
      } finally {
        await _networkPriority(false);
        _download = null;
        downloading = false;
        _notify();
      }
    }
  }

  Future<void> _pruneOldDownloads(Directory root) async {
    final expiry = _clock().subtract(const Duration(days: 7));
    await for (final entry in root.list(followLinks: false)) {
      if (entry is! Directory ||
          !entry.path
              .split(Platform.pathSeparator)
              .last
              .startsWith('package-')) {
        continue;
      }
      if ((await entry.stat()).modified.isBefore(expiry)) {
        await entry.delete(recursive: true);
      }
    }
  }

  void cancelDownload() => _download?.cancel();
  Future<void> install() async {
    final ready = _ready;
    if (ready == null || _disposed || busy) return;
    if (!ready.matches(release, asset)) {
      _ready = null;
      needsPermission = false;
      error = '更新版本已变化，请重新检查并下载';
      _notify();
      return;
    }
    installing = true;
    _notify();
    try {
      await loadInstalled(refresh: true);
      if (_disposed) return;
      if (!available) {
        error = '本机已安装 ${installed!.version}（${installed!.build}），无需重复安装';
        return;
      }
      final result = await platform.install(
        ready.file,
        ready.info.version,
        build: ready.info.build,
      );
      needsPermission = result == 'permission';
      error = null;
    } on PlatformException catch (failure) {
      if (failure.code == 'APK_REJECTED') {
        _ready = null;
        needsPermission = false;
      }
      error = failure.message ?? '无法打开安装程序，请重试';
    } catch (_) {
      error = '无法打开安装程序，请重试';
    } finally {
      installing = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _download?.cancel();
    super.dispose();
  }
}
