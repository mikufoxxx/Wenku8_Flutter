import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_ui.dart';
import 'app_background.dart';
import 'app_licenses.dart';
import 'catalog.dart';
import 'legacy_wenku_repository.dart';
import 'library_state.dart';
import 'local_books.dart';
import 'local_series_actions.dart';
import 'listening/audio_output.dart';
import 'listening/cache.dart';
import 'listening/controller.dart';
import 'listening/store.dart';
import 'listening/custom_tts.dart';
import 'listening/widgets.dart';
import 'native_effects.dart';
import 'network_status.dart';
import 'offline_cache.dart';
import 'offline_repository.dart';
import 'pages.dart';
import 'performance_preferences.dart';
import 'touch_sampling.dart';
import 'updates/app_updates.dart';
import 'updates/update_page.dart';
import 'wenku_account.dart';
import 'wenku_features.dart';
import 'wenku_shelf_sync.dart';

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  registerAppLicenses();
  TouchSamplingPolicy(binding);
  // Do not hold the first frame while Android is applying window insets.
  unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
  final state = await LibraryState.load();
  if (chineseLocale(
        state.language.locale ?? binding.platformDispatcher.locale,
      ).countryCode !=
      'CN') {
    await ChineseText.prepare();
  }
  await state.loadFonts();
  final network = NetworkStatus();
  await network.start();
  if (state.performance.needsRuntimeEffects) await NativeEffects.prepare();
  final brightness = switch (state.theme) {
    ThemeMode.light => Brightness.light,
    ThemeMode.dark => Brightness.dark,
    ThemeMode.system =>
      WidgetsBinding.instance.platformDispatcher.platformBrightness,
  };
  SystemChrome.setSystemUIOverlayStyle(novelSystemUiStyle(brightness));
  final account = defaultTargetPlatform == TargetPlatform.android
      ? WenkuAccount()
      : null;
  final remote = LegacyWenkuRepository(
    publicationRequest: account?.readPublication,
    publicationSessionKey: account == null
        ? null
        : () => (
            account.sessionRevision,
            account.publicationRevision,
            account.authenticated,
          ),
  );
  final repository = defaultTargetPlatform == TargetPlatform.android
      ? OfflineNovelRepository(
          remote: remote,
          cache: await OfflineCacheStore.forApp(),
          local: await LocalBookStore.forApp(),
          network: network,
        )
      : const DemoNovelRepository();
  if (repository is OfflineNovelRepository && repository.local != null) {
    await reconcileLocalSeries(repository.local!, state);
  }
  final features = account != null
      ? WenkuFeatures(
          account: account,
          // The authenticated novellist response already contains book metadata.
          // Reuse its adapter, pagination and the existing account session.
          publications: remote,
          shelfSync: WenkuShelfSync(
            account: account,
            library: state,
            preferences: await SharedPreferences.getInstance(),
            network: network,
          )..start(),
        )
      : null;
  final customSpeech = defaultTargetPlatform == TargetPlatform.android
      ? CustomSpeechSettings()
      : null;
  await customSpeech?.load();
  final listening = defaultTargetPlatform == TargetPlatform.android
      ? ListeningController(
          repository: repository,
          audio: await SpeechAudioCache.forApp(
            customSpeech: customSpeech,
            network: network,
          ),
          customSpeech: customSpeech,
          store: ListeningStore(await SharedPreferences.getInstance()),
          outputFactory: createListeningOutput,
        )
      : null;
  runApp(
    NovelApp(
      state: state,
      repository: repository,
      features: features,
      listening: listening,
      network: network,
      updates: defaultTargetPlatform == TargetPlatform.android
          ? AppUpdates(preferences: await SharedPreferences.getInstance())
          : null,
    ),
  );
  if (listening != null) {
    // Register media commands without allocating a player or blocking the first
    // frame. A service-created engine also gets a handler, with no auto-play.
    unawaited(prepareListeningService(listening).catchError((Object _) {}));
  }
  if (features != null) unawaited(features.account.initialize());
}

class NovelApp extends StatefulWidget {
  const NovelApp({
    super.key,
    required this.state,
    required this.repository,
    this.features,
    this.listening,
    this.updates,
    this.network,
  });

  final LibraryState state;
  final NovelRepository repository;
  final WenkuFeatures? features;
  final ListeningController? listening;
  final AppUpdates? updates;
  final NetworkStatus? network;
  @override
  State<NovelApp> createState() => _NovelAppState();
}

class _NovelAppState extends State<NovelApp> with WidgetsBindingObserver {
  LibraryState get state => widget.state;
  NovelRepository get repository => widget.repository;
  WenkuFeatures? get features => widget.features;
  ListeningController? get listening => widget.listening;
  AppUpdates? get updates => widget.updates;
  final _updateNavigation = AppUpdateNavigation();
  late String _lastTypeface = state.appFontId;
  Locale _systemLocale = chineseLocale(
    WidgetsBinding.instance.platformDispatcher.locale,
  );
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  Future<void> didChangeLocales(List<Locale>? locales) async {
    final ticket = ++_localeRequest;
    final next = chineseLocale(locales?.firstOrNull);
    if (state.language == AppLanguage.system && next.countryCode != 'CN') {
      await ChineseText.prepare();
    }
    if (mounted && ticket == _localeRequest) {
      setState(() => _systemLocale = next);
    }
  }

  int _localeRequest = 0;

  static final _themes = <(TargetPlatform, Brightness, String), ThemeData>{};

  ThemeData _theme(Brightness brightness) => withAppBackground(
    _themes.putIfAbsent((
      defaultTargetPlatform,
      brightness,
      state.appFontId,
    ), () => novelTheme(brightness, fontFamily: state.appFontFamily)),
    state.homeBackgroundFor(brightness),
  );

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    features?.shelfSync?.dispose();
    _updateNavigation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state.applicationChanges,
      builder: (context, child) {
        final typefaceChanged = _lastTypeface != state.appFontId;
        _lastTypeface = state.appFontId;
        return MaterialApp(
          title: '轻小说文库',
          locale: state.language.locale ?? _systemLocale,
          supportedLocales: const [
            Locale('zh', 'CN'),
            Locale('zh', 'HK'),
            Locale('zh', 'TW'),
          ],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          localeResolutionCallback: (locale, _) =>
              chineseLocale(state.language.locale ?? locale),
          navigatorObservers: [_updateNavigation],
          debugShowCheckedModeBanner: false,
          scrollBehavior: const NovelScrollBehavior(),
          theme: _theme(Brightness.light),
          darkTheme: _theme(Brightness.dark),
          themeMode: state.theme,
          themeAnimationDuration:
              typefaceChanged ||
                  state.effectiveReduceMotion ||
                  (MediaQuery.maybeOf(context)?.disableAnimations ?? false)
              ? Duration.zero
              : NovelMotion.enter,
          themeAnimationCurve: NovelMotion.ease,
          builder: (context, child) {
            final media = MediaQuery.of(context);
            final content = PerformanceScope(
              preferences: state.performance,
              child: MediaQuery(
                data: media.copyWith(
                  disableAnimations:
                      media.disableAnimations || state.effectiveReduceMotion,
                ),
                child: AnnotatedRegion<SystemUiOverlayStyle>(
                  value: novelSystemUiStyle(Theme.of(context).brightness),
                  child: AnimatedBuilder(
                    animation: state.glassChanges,
                    child: child,
                    builder: (context, child) => GlassAppearance(
                      blur: state.glassBlur,
                      opacity: state.glassOpacity,
                      child: ListeningScope(
                        controller: listening,
                        child: WenkuFeaturesScope(
                          features: features,
                          child: child!,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            return updates == null
                ? content
                : AppUpdateMonitor(
                    updates: updates!,
                    navigation: _updateNavigation,
                    child: content,
                  );
          },
          home: Builder(
            builder: (context) {
              // A newly attached Android surface can report a zero-sized view.
              // Do not create a glass geometry texture until metrics are ready.
              if (MediaQuery.sizeOf(context).isEmpty) {
                return const SizedBox.shrink();
              }
              return RepaintBoundary(
                child: HomeShell(
                  state: state,
                  repository: repository,
                  network: widget.network,
                ),
              );
            },
          ),
        );
      },
    );
  }
}
