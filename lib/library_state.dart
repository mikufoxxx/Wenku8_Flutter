import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'catalog.dart';
import 'book_identity.dart';
import 'reader_preferences.dart';
import 'library_backup.dart';
import 'performance_preferences.dart';
import 'app_typography.dart';
import 'app_language.dart';
import 'local_library_preferences.dart';
import 'user_fonts.dart';
import 'illustration_placement.dart';
import 'app_background.dart';
import 'reader_background.dart';

class ReadingPosition {
  const ReadingPosition({
    required this.chapter,
    required this.chapterId,
    required this.offset,
    required this.fraction,
    required this.fontSize,
    required this.width,
    required this.updatedAt,
    this.lineHeight = 1.72,
    this.paragraphIndex,
    this.paragraphFraction = 0,
    this.textOffset,
    this.textScale = 1,
    this.typeface = 'system',
    this.layout = '',
  });
  final int chapter;
  final int chapterId;
  final double offset;
  final double fraction;
  final double fontSize;
  final double width;
  final int updatedAt;
  final double lineHeight;
  final int? paragraphIndex;
  final double paragraphFraction;

  /// UTF-16 position inside the original paragraph, independent of layout.
  final int? textOffset;
  final double textScale;
  final String typeface;
  final String layout;

  Map<String, Object> toJson() => {
    'chapter': chapter,
    'chapterId': chapterId,
    'offset': offset,
    'fraction': fraction,
    'fontSize': fontSize,
    'width': width,
    'updatedAt': updatedAt,
    'lineHeight': lineHeight,
    'paragraphIndex': ?paragraphIndex,
    'paragraphFraction': paragraphFraction,
    'textOffset': ?textOffset,
    'textScale': textScale,
    'typeface': typeface,
    if (layout.isNotEmpty) 'layout': layout,
  };

  factory ReadingPosition.fromJson(Map<String, dynamic> value) {
    double number(String key, double fallback) {
      final number = value[key];
      return number is num && number.isFinite ? number.toDouble() : fallback;
    }

    return ReadingPosition(
      chapter: value['chapter'] is int
          ? (value['chapter'] as int).clamp(0, 100000)
          : 0,
      chapterId: value['chapterId'] is int ? value['chapterId'] : 0,
      offset: number('offset', 0).clamp(0, double.infinity),
      fraction: number('fraction', 0).clamp(0, 1),
      fontSize: number('fontSize', 19),
      width: number('width', 0),
      updatedAt: value['updatedAt'] is int ? value['updatedAt'] : 0,
      lineHeight: number('lineHeight', 1.72).clamp(1.3, 2.2),
      paragraphIndex:
          value['paragraphIndex'] is int && value['paragraphIndex'] >= 0
          ? value['paragraphIndex']
          : null,
      paragraphFraction: number('paragraphFraction', 0).clamp(0, 1),
      textOffset: value['textOffset'] is int && value['textOffset'] >= 0
          ? value['textOffset']
          : null,
      textScale: number('textScale', 1).clamp(.5, 5),
      typeface: validFontChoice(value['typeface'])
          ? value['typeface']
          : 'system',
      layout: value['layout'] is String ? value['layout'] : '',
    );
  }
}

class ReaderBookmark {
  const ReaderBookmark({
    required this.id,
    required this.chapterTitle,
    required this.position,
    this.quote = '',
  });
  final String id;
  final String chapterTitle;
  final ReadingPosition position;
  final String quote;

  Map<String, Object> toJson() => {
    'id': id,
    'chapterTitle': chapterTitle,
    'position': position.toJson(),
    if (quote.isNotEmpty) 'quote': quote,
  };

  factory ReaderBookmark.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final title = json['chapterTitle'];
    final position = json['position'];
    final quote = json['quote'] ?? '';
    if (id is! String ||
        id.isEmpty ||
        title is! String ||
        position is! Map ||
        quote is! String ||
        quote.length > 12000) {
      throw const FormatException('Damaged bookmark');
    }
    return ReaderBookmark(
      id: id,
      chapterTitle: title,
      position: ReadingPosition.fromJson(Map<String, dynamic>.from(position)),
      quote: quote,
    );
  }
}

class LibraryState extends ChangeNotifier {
  LibraryState(
    this._prefs, {
    UserFontStore? fonts,
    ReaderBackgroundStore? backgrounds,
  }) : fonts = fonts ?? UserFontStore(),
       backgrounds = backgrounds ?? ReaderBackgroundStore() {
    _homeBackgroundColor = parseBackgroundHex(
      _prefs.get('homeBackground')?.toString() ?? '',
    );
    _homeBackgroundDarkColor = parseBackgroundHex(
      _prefs.get('homeBackgroundDark')?.toString() ?? '',
    );
    _shelf.addAll(
      ((_prefs.get('shelf') is List<String>)
              ? _prefs.getStringList('shelf')!
              : const <String>[])
          .map(int.tryParse)
          .whereType<int>()
          .where((id) => id > 0 && !isLocalBook(id)),
    );
    _hiddenHistory.addAll(
      ((_prefs.get('reading_history_hidden') is List<String>)
              ? _prefs.getStringList('reading_history_hidden')!
              : const <String>[])
          .map(int.tryParse)
          .whereType<int>()
          .where((id) => id > 0),
    );
    _hiddenLocalBooks.addAll(
      (_prefs.get('local_shelf_hidden') is List<String>
              ? _prefs.getStringList('local_shelf_hidden')!
              : const <String>[])
          .map(int.tryParse)
          .whereType<int>()
          .where(isLocalBook),
    );
    for (final key in _prefs.getKeys()) {
      if (key.startsWith('chapter_')) {
        final id = int.tryParse(key.substring('chapter_'.length));
        final value = _prefs.get(key);
        if (id != null && value is int) _chapters[id] = value.clamp(0, 100000);
      }
      if (key.startsWith('shelf_added_')) {
        final id = int.tryParse(key.substring('shelf_added_'.length));
        final value = _prefs.get(key);
        if (id != null && value is int) _added[id] = value;
      }
      if (key.startsWith('novel_meta_')) {
        try {
          final novel = Novel.fromSnapshot(
            jsonDecode(_prefs.getString(key)!) as Map<String, dynamic>,
          );
          _known[novel.id] = novel;
          _persistedNovels[novel.id] = novel;
        } catch (_) {
          // A damaged cache never removes its saved shelf ID or preferences.
        }
      }
      if (key.startsWith('reading_position_')) {
        final id = int.tryParse(key.substring('reading_position_'.length));
        if (id == null) continue;
        try {
          _positions[id] = ReadingPosition.fromJson(
            jsonDecode(_prefs.getString(key)!) as Map<String, dynamic>,
          );
        } catch (_) {
          // The legacy chapter index remains usable without a position record.
        }
      }
      if (key.startsWith('illustration_layout_')) {
        final id = int.tryParse(key.substring('illustration_layout_'.length));
        if (id == null || id <= 0) continue;
        try {
          final records = jsonDecode(_prefs.getString(key)!);
          if (records is! List) continue;
          final placements = <IllustrationPlacement>[];
          final ids = <String>{};
          for (final record in records.take(2000)) {
            try {
              final placement = IllustrationPlacement.fromJson(
                Map<String, dynamic>.from(record as Map),
              );
              if (ids.add(placement.id)) placements.add(placement);
            } catch (_) {
              /* Isolate damaged placement records. */
            }
          }
          _illustrations[id] = placements;
        } catch (_) {
          /* Original chapter text is independent of local layout. */
        }
      }
      if (key.startsWith('reader_bookmarks_')) {
        final id = int.tryParse(key.substring('reader_bookmarks_'.length));
        if (id == null || id <= 0) continue;
        try {
          final records = jsonDecode(_prefs.getString(key)!);
          if (records is! List) continue;
          final bookmarks = <ReaderBookmark>[];
          final ids = <String>{};
          for (final record in records) {
            try {
              final bookmark = ReaderBookmark.fromJson(
                Map<String, dynamic>.from(record as Map),
              );
              if (ids.add(bookmark.id)) bookmarks.add(bookmark);
            } catch (_) {
              // One damaged bookmark does not erase the remaining marks.
            }
          }
          bookmarks.sort(
            (a, b) => b.position.updatedAt.compareTo(a.position.updatedAt),
          );
          _bookmarks[id] = bookmarks;
        } catch (_) {
          // Resume records are independent of the bookmark list.
        }
      }
    }
    _theme = switch (_prefs.get('theme')) {
      'dark' => ThemeMode.dark,
      'light' => ThemeMode.light,
      _ => ThemeMode.system,
    };
    double preference(String key, double fallback, double min, double max) {
      final value = _prefs.get(key);
      return value is num && value.isFinite
          ? value.toDouble().clamp(min, max)
          : fallback;
    }

    _fontSize = preference('readerFontSize', 19, 15, 27);
    _lineHeight = preference('readerLineHeight', 1.72, 1.3, 2.2);
    _reduceMotion = _prefs.get('reduceMotion') == true;
    _appTypeface = AppTypeface.fromRecord(_prefs.get('appTypeface'));
    final custom = _prefs.get('appCustomFont');
    _appCustomFont =
        validFontChoice(custom) && (custom as String).startsWith('font_')
        ? custom
        : null;
    final reader = _prefs.get('readerTypeface');
    _readerTypeface = validFontChoice(reader, follow: true)
        ? reader as String
        : followAppFont;
    _performance = PerformancePreferences.fromRecords({
      for (final key in [
        PerformancePreferences.modeKey,
        ...PerformanceEffect.values.map((effect) => effect.preferenceKey),
      ])
        key: _prefs.get(key),
    });
    _glassBlur = preference('glassBlur', 8, 0, 24);
    _glassOpacity = preference('glassOpacity', .87, 0, 1);
    _keepScreenOn = _prefs.get('readerKeepScreenOn') == true;
    _readerPreferences = ReaderPreferences.fromRecord(
      _prefs.get('readerPreferences'),
    );
    _shelfSort = switch (_prefs.get('shelfSort')) {
      'recentAdded' => 'recentAdded',
      'title' => 'title',
      _ => 'recentRead',
    };
    _shelfFilter = switch (_prefs.get('shelfFilter')) {
      'unread' => 'unread',
      'reading' => 'reading',
      'finished' => 'finished',
      _ => 'all',
    };
    _shelfLayout = _prefs.get('shelfLayout') == 'list' ? 'list' : 'shelf';
    _shelfSourceFilter =
        ['local', 'cached', 'online'].contains(_prefs.get('shelfSourceFilter'))
        ? _prefs.get('shelfSourceFilter') as String
        : 'all';
    _adaptWhenOffline = _prefs.get('adaptWhenOffline') != false;
    _localReaderMode = _prefs.get('localReaderMode') == true;
    _directReading = _prefs.get('directReading') == true;
    _combinedShelf = _prefs.get('combinedShelf') == true;
    final recent = _prefs.get('recentSearches');
    if (recent is List<String>) {
      final seen = <String>{};
      _recentSearches = recent
          .map((query) => query.trim())
          .where(
            (query) =>
                validSearchHistory(query) && seen.add(query.toLowerCase()),
          )
          .take(12)
          .toList(growable: false);
    }
  }

  final SharedPreferences _prefs;
  final ReaderBackgroundStore backgrounds;
  Color? _homeBackgroundColor;
  Color? get homeBackgroundColor => _homeBackgroundColor;
  Color? _homeBackgroundDarkColor;
  Color? homeBackgroundFor(Brightness brightness) =>
      brightness == Brightness.dark
      ? _homeBackgroundDarkColor
      : _homeBackgroundColor;
  final UserFontStore fonts;
  String? fontError;
  LocalLibraryPreferences? _organization;
  LocalLibraryPreferences get organization =>
      _organization ??= (LocalLibraryPreferences(_prefs)..load());
  final _appearance = ChangeNotifier();
  final _application = ChangeNotifier();
  final _glassChanges = ChangeNotifier();
  final _readerSettings = ChangeNotifier();
  final _settings = ChangeNotifier();
  final _history = ChangeNotifier();
  final _bookmarkChanges = ChangeNotifier();
  final _illustrationChanges = ChangeNotifier();
  final _searchChanges = ChangeNotifier();
  final _shelfViewChanges = ChangeNotifier();
  final _readerBehaviorChanges = ChangeNotifier();
  final _navigationChanges = ChangeNotifier();
  final Set<int> _shelf = {};
  final Set<int> _hiddenHistory = {};
  final Set<int> _hiddenLocalBooks = {};
  final Map<int, Novel> _known = {};
  final Map<int, Novel> _persistedNovels = {};
  final Map<int, int> _chapters = {};
  final Map<int, ReadingPosition> _positions = {};
  final Map<int, int> _added = {};
  final Map<int, List<ReaderBookmark>> _bookmarks = {};
  final Map<int, List<IllustrationPlacement>> _illustrations = {};
  final Map<int, int> _shelfRevisions = {};
  List<String> _recentSearches = const [];
  String _shelfSort = 'recentRead';
  String _shelfFilter = 'all';
  String _shelfSourceFilter = 'all';
  String _shelfLayout = 'shelf';
  bool _keepScreenOn = false;
  bool _adaptWhenOffline = true, _localReaderMode = false;
  bool _directReading = false, _combinedShelf = false;
  ReaderPreferences _readerPreferences = const ReaderPreferences();
  int _metadataEncodes = 0;
  Future<void> _positionWrites = Future.value();
  Completer<void>? _restoreBarrier;
  ThemeMode _theme = ThemeMode.system;
  double _fontSize = 19;
  double _lineHeight = 1.72;
  bool _reduceMotion = false;
  AppTypeface _appTypeface = AppTypeface.system;
  String? _appCustomFont;
  String _readerTypeface = followAppFont;
  PerformancePreferences _performance = const PerformancePreferences();
  double _glassBlur = 8;
  double _glassOpacity = .87;
  bool _disposed = false;
  bool _historyNotificationQueued = false;

  static Future<LibraryState> load() async {
    final prefs = await SharedPreferences.getInstance();
    await recoverLibraryRestore(prefs);
    final state = LibraryState(prefs);
    final storedShelf = prefs.get('shelf');
    if (storedShelf is List<String> &&
        storedShelf.map(int.tryParse).whereType<int>().any(isLocalBook)) {
      // Migrate only membership. Originals, metadata, positions and bookmarks
      // remain available to the local library and cross-device sync.
      await state._commitLibraryRecords({
        'shelf': state._shelf.map((id) => '$id').toList(),
      });
    }
    return state;
  }

  Future<void> loadFonts() async {
    try {
      await fonts.load();
      await fonts.ensureLoaded(appFontId);
      await fonts.ensureLoaded(readerFontId);
      fontError = null;
      if (!_disposed) {
        _application.notifyListeners();
        _appearance.notifyListeners();
        _readerSettings.notifyListeners();
        _settings.notifyListeners();
      }
    } catch (_) {
      fontError = '自定义字体读取失败，暂用系统字体；可在字体设置中重试。';
    }
  }

  Set<int> get shelf => Set.unmodifiable(_shelf);
  Listenable get appearanceChanges => _appearance;
  Listenable get applicationChanges => _application;
  AppLanguage get language => AppLanguage.fromRecord(_prefs.get('appLanguage'));
  Future<void> setLanguage(AppLanguage value) async {
    if (chineseLocale(
          value.locale ?? WidgetsBinding.instance.platformDispatcher.locale,
        ).countryCode !=
        'CN') {
      await ChineseText.prepare();
    }
    await _queuePositionWrite(() async {
      await writeLibraryPreference(_prefs, 'appLanguage', value.name);
      if (!_disposed) {
        _application.notifyListeners();
        _settings.notifyListeners();
      }
    });
  }

  bool get readerChromeVisible => _prefs.get('readerChromeVisible') == true;
  bool get readerChromeHintSeen => _prefs.get('readerChromeHintSeen') == true;
  Future<void> setReaderChromeVisible(bool visible) => _queuePositionWrite(
    () => writeLibraryPreference(_prefs, 'readerChromeVisible', visible),
  );
  Future<void> markReaderChromeHintSeen() => _queuePositionWrite(
    () => writeLibraryPreference(_prefs, 'readerChromeHintSeen', true),
  );
  Listenable get glassChanges => _glassChanges;
  Listenable get readerSettingsChanges => _readerSettings;
  Listenable get settingsChanges => _settings;
  Listenable get historyChanges => _history;
  Listenable get bookmarkChanges => _bookmarkChanges;
  Listenable get illustrationChanges => _illustrationChanges;
  List<IllustrationPlacement> illustrationsFor(int id, {int? chapterId}) =>
      List.unmodifiable(
        (_illustrations[id] ?? const <IllustrationPlacement>[]).where(
          (item) => chapterId == null || item.chapterId == chapterId,
        ),
      );

  Future<void> putIllustration(int id, IllustrationPlacement placement) async {
    if (_restoreBarrier case final barrier?) {
      await barrier.future;
      return putIllustration(id, placement);
    }
    await _queuePositionWrite(() async {
      final next = [...?_illustrations[id]]
        ..removeWhere((item) => item.url == placement.url);
      if (next.length >= 2000) throw const FormatException('本书插图排版已达上限，请先整理');
      next.add(placement);
      await writeLibraryPreference(
        _prefs,
        'illustration_layout_$id',
        jsonEncode(next.map((item) => item.toJson()).toList()),
      );
      _illustrations[id] = next;
      if (!_disposed) _illustrationChanges.notifyListeners();
    });
  }

  Future<void> removeIllustration(int id, String placementId) async {
    if (_restoreBarrier case final barrier?) {
      await barrier.future;
      return removeIllustration(id, placementId);
    }
    await _queuePositionWrite(() async {
      final next = [...?_illustrations[id]]
        ..removeWhere((item) => item.id == placementId);
      await writeLibraryPreference(
        _prefs,
        'illustration_layout_$id',
        jsonEncode(next.map((item) => item.toJson()).toList()),
      );
      _illustrations[id] = next;
      if (!_disposed) _illustrationChanges.notifyListeners();
    });
  }

  Listenable get searchChanges => _searchChanges;
  Listenable get shelfViewChanges => _shelfViewChanges;
  Set<int> get hiddenLocalBooks => Set.unmodifiable(_hiddenLocalBooks);
  bool localBookVisible(int id) => !_hiddenLocalBooks.contains(id);
  Future<void> setLocalBookHidden(int id, bool hidden) =>
      setLocalBooksHidden([id], hidden);

  Future<void> setLocalBooksHidden(Iterable<int> ids, bool hidden) {
    final targets = ids.where(isLocalBook).toSet();
    if (targets.isEmpty) return Future.value();
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then((_) => setLocalBooksHidden(targets, hidden));
    }
    return _queuePositionWrite(() async {
      final next = {..._hiddenLocalBooks};
      if (hidden) {
        next.addAll(targets);
      } else {
        next.removeAll(targets);
      }
      if (setEquals(next, _hiddenLocalBooks)) return;
      await writeLibraryPreference(
        _prefs,
        'local_shelf_hidden',
        next.map((id) => '$id').toList(),
      );
      _hiddenLocalBooks
        ..clear()
        ..addAll(next);
      if (!_disposed) _shelfViewChanges.notifyListeners();
    });
  }

  Listenable get readerBehaviorChanges => _readerBehaviorChanges;
  Listenable get navigationChanges => _navigationChanges;
  bool get adaptWhenOffline => _adaptWhenOffline;
  bool get localReaderMode => _localReaderMode;
  bool get directReading => _directReading;
  bool get combinedShelf => _combinedShelf;
  List<String> get recentSearches => List.unmodifiable(_recentSearches);
  String get shelfSort => _shelfSort;
  String get shelfFilter => _shelfFilter;
  String get shelfSourceFilter => _shelfSourceFilter;
  String get shelfLayout => _shelfLayout;
  bool get keepScreenOn => _keepScreenOn;
  ReaderPreferences get readerPreferences => _readerPreferences;
  ThemeMode get theme => _theme;
  double get fontSize => _fontSize;
  double get lineHeight => _lineHeight;
  int get debugMetadataEncodeCount => _metadataEncodes;
  bool get reduceMotion => _reduceMotion;
  AppTypeface get appTypeface => _appTypeface;
  String get appFontChoice => _appCustomFont ?? _appTypeface.name;
  String get appFontId =>
      fonts.available(appFontChoice) ? appFontChoice : 'system';
  String? get appFontFamily => fonts.family(appFontId);
  String get readerTypeface => _readerTypeface;
  String get readerFontId => _readerTypeface == followAppFont
      ? appFontId
      : fonts.available(_readerTypeface)
      ? _readerTypeface
      : 'system';
  String? get readerFontFamily => fonts.family(readerFontId);
  String fontLabel(String choice) =>
      choice == followAppFont || fonts.available(choice)
      ? fonts.label(choice)
      : '字体未在本机导入';
  PerformancePreferences get performance => _performance;
  bool get effectiveReduceMotion => _reduceMotion || !_performance.motion;
  double get glassBlur => _glassBlur;
  double get glassOpacity => _glassOpacity;

  bool contains(int id) => _shelf.contains(id);
  int chapterFor(int id) => _chapters[id] ?? _positions[id]?.chapter ?? 0;
  Novel? cachedNovel(int id) => _known[id];
  ReadingPosition? positionFor(int id) => _positions[id];
  List<ReaderBookmark> bookmarksFor(int id) =>
      List.unmodifiable(_bookmarks[id] ?? const <ReaderBookmark>[]);

  List<({int novelId, ReaderBookmark bookmark})> get bookmarkEntries {
    final entries =
        [
          for (final entry in _bookmarks.entries)
            for (final mark in entry.value)
              (novelId: entry.key, bookmark: mark),
        ]..sort(
          (a, b) => b.bookmark.position.updatedAt.compareTo(
            a.bookmark.position.updatedAt,
          ),
        );
    return List.unmodifiable(entries);
  }

  int? chapterForPosition(Novel novel, ReadingPosition position) {
    if (position.chapterId > 0) {
      final index = novel.chapters.indexWhere(
        (chapter) => chapter.id == position.chapterId,
      );
      return index < 0 ? null : index;
    }
    return position.chapter >= 0 && position.chapter < novel.chapters.length
        ? position.chapter
        : null;
  }

  bool hasRead(int id) =>
      _chapters.containsKey(id) || _positions.containsKey(id);
  int addedAt(int id) => _added[id] ?? 0;
  int shelfRevision(int id) => _shelfRevisions[id] ?? 0;
  Map<int, int> get shelfRevisions => Map.unmodifiable(_shelfRevisions);
  int lastReadAt(int id) => _positions[id]?.updatedAt ?? 0;

  bool finishedReading(Novel novel) {
    final position = positionFor(novel.id);
    final count = novel.chapters.isEmpty
        ? novel.chapterCount
        : novel.chapters.length;
    if (position == null || count <= 0 || position.fraction < .995) {
      return false;
    }
    if (position.chapterId > 0 && novel.chapters.isNotEmpty) {
      return novel.chapters.last.id == position.chapterId;
    }
    return position.chapter == count - 1;
  }

  static bool validSearchHistory(String query) =>
      query.isNotEmpty &&
      query.length <= 120 &&
      !RegExp(r'[\x00-\x1f]').hasMatch(query);

  Future<void> recordSearch(String query) {
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then((_) => recordSearch(query));
    }
    final term = query.trim();
    if (!validSearchHistory(term)) return Future.value();
    return _queuePositionWrite(() async {
      if (_recentSearches.isNotEmpty && _recentSearches.first == term) return;
      final next = [
        term,
        ..._recentSearches.where(
          (old) => old.toLowerCase() != term.toLowerCase(),
        ),
      ].take(12).toList(growable: false);
      await writeLibraryPreference(_prefs, 'recentSearches', next);
      _recentSearches = next;
      if (!_disposed) _searchChanges.notifyListeners();
    });
  }

  Future<void> clearRecentSearches() {
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then((_) => clearRecentSearches());
    }
    return _queuePositionWrite(() async {
      await writeLibraryPreference(_prefs, 'recentSearches', <String>[]);
      _recentSearches = const [];
      if (!_disposed) _searchChanges.notifyListeners();
    });
  }

  Future<void> setShelfView({
    String? sort,
    String? filter,
    String? layout,
    String? source,
  }) async {
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then(
        (_) => setShelfView(
          sort: sort,
          filter: filter,
          layout: layout,
          source: source,
        ),
      );
    }
    await _queuePositionWrite(() async {
      final nextSort = ['recentRead', 'recentAdded', 'title'].contains(sort)
          ? sort!
          : _shelfSort;
      final nextFilter =
          ['all', 'unread', 'reading', 'finished'].contains(filter)
          ? filter!
          : _shelfFilter;
      final nextLayout = ['shelf', 'list'].contains(layout)
          ? layout!
          : _shelfLayout;
      final nextSource = ['all', 'local', 'cached', 'online'].contains(source)
          ? source!
          : _shelfSourceFilter;
      await _commitLibraryRecords({
        'shelfSort': nextSort,
        'shelfFilter': nextFilter,
        'shelfLayout': nextLayout,
        'shelfSourceFilter': nextSource,
      });
      if (nextSort != _shelfSort ||
          nextFilter != _shelfFilter ||
          nextLayout != _shelfLayout ||
          nextSource != _shelfSourceFilter) {
        _shelfSort = nextSort;
        _shelfFilter = nextFilter;
        _shelfLayout = nextLayout;
        _shelfSourceFilter = nextSource;
        if (!_disposed) _shelfViewChanges.notifyListeners();
      }
    });
  }

  Future<void> setKeepScreenOn(bool value) async {
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then((_) => setKeepScreenOn(value));
    }
    await _queuePositionWrite(() async {
      await writeLibraryPreference(_prefs, 'readerKeepScreenOn', value);
      if (_keepScreenOn != value) {
        _keepScreenOn = value;
        if (!_disposed) {
          _readerBehaviorChanges.notifyListeners();
          _settings.notifyListeners();
        }
      }
    });
  }

  Future<void> setNavigationMode({
    bool? adaptWhenOffline,
    bool? localReaderMode,
    bool? combinedShelf,
  }) async {
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then(
        (_) => setNavigationMode(
          adaptWhenOffline: adaptWhenOffline,
          localReaderMode: localReaderMode,
          combinedShelf: combinedShelf,
        ),
      );
    }
    await _queuePositionWrite(() async {
      final offline = adaptWhenOffline ?? _adaptWhenOffline;
      final local = localReaderMode ?? _localReaderMode;
      final combined = combinedShelf ?? _combinedShelf;
      if (offline == _adaptWhenOffline &&
          local == _localReaderMode &&
          combined == _combinedShelf) {
        return;
      }
      await _commitLibraryRecords({
        'adaptWhenOffline': offline,
        'localReaderMode': local,
        'combinedShelf': combined,
      });
      _adaptWhenOffline = offline;
      _localReaderMode = local;
      _combinedShelf = combined;
      if (!_disposed) {
        _navigationChanges.notifyListeners();
        _shelfViewChanges.notifyListeners();
        _settings.notifyListeners();
      }
    });
  }

  Future<void> setDirectReading(bool value) async {
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then((_) => setDirectReading(value));
    }
    await _queuePositionWrite(() async {
      await writeLibraryPreference(_prefs, 'directReading', value);
      _directReading = value;
      if (!_disposed) _settings.notifyListeners();
    });
  }

  Future<void> setReaderPreferences(
    ReaderPreferences value, {
    bool persist = true,
  }) async {
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then(
        (_) => setReaderPreferences(value, persist: persist),
      );
    }
    final record = jsonEncode(value.toJson());
    ReaderPreferences.fromJson(jsonDecode(record));
    if (persist) {
      await _queuePositionWrite(
        () => writeLibraryPreference(_prefs, 'readerPreferences', record),
      );
    }
    if (jsonEncode(_readerPreferences.toJson()) == record) return;
    _readerPreferences = value;
    if (!_disposed) {
      _readerSettings.notifyListeners();
      _readerBehaviorChanges.notifyListeners();
      _settings.notifyListeners();
    }
  }

  List<int> get readingHistoryIds {
    final ids =
        {
            ..._chapters.keys,
            ..._positions.keys,
          }.where((id) => id > 0 && !_hiddenHistory.contains(id)).toList()
          ..sort((a, b) {
            final time = lastReadAt(b).compareTo(lastReadAt(a));
            return time != 0 ? time : a.compareTo(b);
          });
    return List.unmodifiable(ids);
  }

  void _historyChanged() {
    if (_disposed) return;
    if (WidgetsBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_historyNotificationQueued) return;
      _historyNotificationQueued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _historyNotificationQueued = false;
        if (!_disposed) _history.notifyListeners();
      });
      return;
    }
    _history.notifyListeners();
  }

  Future<void> _queuePositionWrite(Future<void> Function() write) {
    _positionWrites = _positionWrites.catchError((Object _) {}).then((_) async {
      if (_prefs.get(restoreJournalKey) != null) {
        await recoverLibraryRestore(_prefs);
      }
      await write();
    });
    return _positionWrites;
  }

  /// Hide history without destroying resume positions, shelf or body files.
  Future<void> hideReadingHistory(int id) {
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then((_) => hideReadingHistory(id));
    }
    return _queuePositionWrite(() async {
      if (id <= 0 || !hasRead(id) || _hiddenHistory.contains(id)) return;
      final next = {..._hiddenHistory, id};
      await writeLibraryPreference(
        _prefs,
        'reading_history_hidden',
        next.map((id) => '$id').toList(),
      );
      _hiddenHistory
        ..clear()
        ..addAll(next);
      _historyChanged();
    });
  }

  Future<void> clearReadingHistory() {
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then((_) => clearReadingHistory());
    }
    return _queuePositionWrite(() async {
      final visible = readingHistoryIds;
      if (visible.isEmpty) return;
      final next = {..._hiddenHistory, ...visible};
      await writeLibraryPreference(
        _prefs,
        'reading_history_hidden',
        next.map((id) => '$id').toList(),
      );
      _hiddenHistory
        ..clear()
        ..addAll(next);
      _historyChanged();
    });
  }

  Future<void> restoreReadingHistory(int id) {
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then((_) => restoreReadingHistory(id));
    }
    return _queuePositionWrite(() async {
      if (id <= 0 || !hasRead(id) || !_hiddenHistory.contains(id)) return;
      final next = {..._hiddenHistory}..remove(id);
      await writeLibraryPreference(
        _prefs,
        'reading_history_hidden',
        next.map((id) => '$id').toList(),
      );
      _hiddenHistory
        ..clear()
        ..addAll(next);
      _historyChanged();
    });
  }

  int chapterForNovel(Novel novel) {
    final position = _positions[novel.id];
    if (position != null && position.chapterId > 0) {
      final index = novel.chapters.indexWhere(
        (chapter) => chapter.id == position.chapterId,
      );
      if (index >= 0) return index;
    }
    final count = novel.chapters.isEmpty
        ? novel.chapterCount
        : novel.chapters.length;
    return count == 0
        ? chapterFor(novel.id)
        : chapterFor(novel.id).clamp(0, count - 1);
  }

  String? _novelSnapshot(Novel novel) {
    if (identical(_persistedNovels[novel.id], novel)) return null;
    assert(() {
      _metadataEncodes++;
      return true;
    }());
    final snapshot = jsonEncode(novel.toSnapshot());
    _persistedNovels[novel.id] = novel;
    return snapshot;
  }

  Future<void> _writeNovel(Novel novel, String snapshot) async {
    try {
      await writeLibraryPreference(_prefs, 'novel_meta_${novel.id}', snapshot);
    } catch (_) {
      if (identical(_persistedNovels[novel.id], novel)) {
        _persistedNovels.remove(novel.id);
      }
      rethrow;
    }
  }

  Future<void> rememberNovel(Novel novel) {
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then((_) => rememberNovel(novel));
    }
    if (novel.id <= 0) return Future.value();
    _known[novel.id] = novel;
    final snapshot = _novelSnapshot(novel);
    return snapshot == null
        ? _positionWrites
        : _queuePositionWrite(() => _writeNovel(novel, snapshot));
  }

  Future<ReaderBookmark?> addBookmark({
    required Novel novel,
    required ReadingPosition position,
    String quote = '',
  }) async {
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then(
        (_) => addBookmark(novel: novel, position: position, quote: quote),
      );
    }
    final index = chapterForPosition(novel, position);
    final excerpt = quote.trim();
    if (excerpt.length > 12000) {
      throw const FormatException('摘录过长，请选择不超过 12000 字的内容');
    }
    if (novel.id <= 0 ||
        index == null ||
        !position.offset.isFinite ||
        position.offset < 0 ||
        !position.fraction.isFinite ||
        position.fraction < 0 ||
        position.fraction > 1 ||
        !position.width.isFinite ||
        !position.fontSize.isFinite ||
        !position.lineHeight.isFinite) {
      return null;
    }
    ReaderBookmark? result;
    await _queuePositionWrite(() async {
      final marks = _bookmarks[novel.id] ?? const <ReaderBookmark>[];
      for (final mark in marks) {
        if (mark.quote == excerpt &&
            chapterForPosition(novel, mark.position) == index &&
            (excerpt.isEmpty ||
                mark.position.paragraphIndex == position.paragraphIndex &&
                    mark.position.textOffset == position.textOffset) &&
            (mark.position.offset - position.offset).abs() < 12 &&
            (mark.position.fontSize - position.fontSize).abs() < .01 &&
            (mark.position.lineHeight - position.lineHeight).abs() < .01 &&
            (mark.position.width - position.width).abs() < 1) {
          result = mark;
          return;
        }
      }
      if (marks.length >= 1000) {
        throw const FormatException('本书书签已达 1000 个，请先整理书签');
      }
      final mark = ReaderBookmark(
        id: '${DateTime.now().microsecondsSinceEpoch}-${marks.length}',
        chapterTitle: novel.chapters[index].title,
        position: position,
        quote: excerpt,
      );
      final next = [mark, ...marks];
      final snapshot = _novelSnapshot(novel);
      if (snapshot != null) await _writeNovel(novel, snapshot);
      await _writeBookmarks(novel.id, next);
      _known[novel.id] = novel;
      _bookmarks[novel.id] = next;
      if (!_disposed) _bookmarkChanges.notifyListeners();
      result = mark;
    });
    return result;
  }

  Future<void> removeBookmark(int novelId, String id) {
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then((_) => removeBookmark(novelId, id));
    }
    return _queuePositionWrite(() async {
      final marks = _bookmarks[novelId];
      if (marks == null || !marks.any((mark) => mark.id == id)) return;
      final next = marks.where((mark) => mark.id != id).toList();
      await _writeBookmarks(novelId, next);
      _bookmarks[novelId] = next;
      if (!_disposed) _bookmarkChanges.notifyListeners();
    });
  }

  Future<void> _writeBookmarks(int novelId, List<ReaderBookmark> marks) async {
    final record = jsonEncode(marks.map((mark) => mark.toJson()).toList());
    await writeLibraryPreference(_prefs, 'reader_bookmarks_$novelId', record);
  }

  Future<void> toggleShelf(int id, {Novel? novel}) {
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then((_) => toggleShelf(id, novel: novel));
    }
    return setShelfMembership(id, !contains(id), novel: novel);
  }

  /// One transactional merge/notification rather than rebuilding the shelf
  /// once per imported cloud/legacy ID. Reading records are never overwritten.
  Future<void> addShelfIds(Iterable<int> values) async {
    final ids = values.where((id) => id > 0 && !isLocalBook(id)).toSet();
    if (_restoreBarrier case final barrier?) {
      await barrier.future;
      return addShelfIds(ids);
    }
    await _queuePositionWrite(() async {
      final additions = ids.difference(_shelf);
      if (additions.isEmpty) return;
      final shelf = {..._shelf, ...additions};
      final now = DateTime.now().millisecondsSinceEpoch;
      await _commitLibraryRecords({
        'shelf': shelf.map((id) => '$id').toList(),
        for (final id in additions) 'shelf_added_$id': now,
      });
      _shelf.addAll(additions);
      for (final id in additions) {
        _added[id] = now;
        _shelfRevisions[id] = shelfRevision(id) + 1;
      }
      if (!_disposed) notifyListeners();
    });
  }

  Future<void> applyCloudShelf({
    required Set<int> add,
    required Set<int> remove,
    required Map<int, int> expectedRevisions,
  }) {
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then(
        (_) => applyCloudShelf(
          add: add,
          remove: remove,
          expectedRevisions: expectedRevisions,
        ),
      );
    }
    return _queuePositionWrite(() async {
      final next = {..._shelf};
      final now = DateTime.now().millisecondsSinceEpoch;
      final added = <int>{};
      for (final id in {...add, ...remove}) {
        if (id <= 0 ||
            isLocalBook(id) ||
            shelfRevision(id) != (expectedRevisions[id] ?? 0)) {
          continue;
        }
        if (add.contains(id)) {
          if (next.add(id)) added.add(id);
        } else {
          next.remove(id);
        }
      }
      if (setEquals(next, _shelf)) return;
      final changed = {...next.difference(_shelf), ..._shelf.difference(next)};
      await _commitLibraryRecords({
        'shelf': next.map((id) => '$id').toList(),
        for (final id in added) 'shelf_added_$id': now,
      });
      _shelf
        ..clear()
        ..addAll(next);
      for (final id in added) {
        _added[id] = now;
      }
      for (final id in changed) {
        _shelfRevisions[id] = shelfRevision(id) + 1;
      }
      if (!_disposed) notifyListeners();
    });
  }

  Future<void> setShelfMembership(
    int id,
    bool present, {
    Novel? novel,
    int? restoredAddedAt,
  }) async {
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then(
        (_) => setShelfMembership(
          id,
          present,
          novel: novel,
          restoredAddedAt: restoredAddedAt,
        ),
      );
    }
    if (id <= 0) return;
    present = present && !isLocalBook(id);
    await _queuePositionWrite(() async {
      final changedMembership = contains(id) != present;
      final shelf = {..._shelf};
      if (present) {
        shelf.add(id);
      } else {
        shelf.remove(id);
      }
      final timestamp = changedMembership && present
          ? restoredAddedAt != null && restoredAddedAt >= 0
                ? restoredAddedAt
                : DateTime.now().millisecondsSinceEpoch
          : _added[id];
      final snapshot = novel == null ? null : _novelSnapshot(novel);
      try {
        await _commitLibraryRecords({
          if (changedMembership) 'shelf': shelf.map((id) => '$id').toList(),
          if (present && timestamp != null) 'shelf_added_$id': timestamp,
          'novel_meta_$id': ?snapshot,
        });
      } catch (_) {
        if (novel != null && identical(_persistedNovels[id], novel)) {
          _persistedNovels.remove(id);
        }
        rethrow;
      }
      _shelf
        ..clear()
        ..addAll(shelf);
      if (present && timestamp != null) _added[id] = timestamp;
      if (novel != null) _known[id] = novel;
      if (changedMembership) _shelfRevisions[id] = shelfRevision(id) + 1;
      if (!_disposed && (changedMembership || novel != null)) notifyListeners();
    });
  }

  /// Copy records through explicit chapter identities without deleting the
  /// source records. Receipts make repeated reconciliation safe after a restart
  /// and prevent removed series bookmarks from being copied back again.
  Future<void> combineBookRecords({
    required Novel target,
    required Map<Novel, Map<int, int>> sources,
    bool? onShelf,
    bool revealTarget = true,
  }) async {
    if (_restoreBarrier case final barrier?) {
      await barrier.future;
      return combineBookRecords(
        target: target,
        sources: sources,
        onShelf: onShelf,
        revealTarget: revealTarget,
      );
    }
    await _queuePositionWrite(() async {
      final receiptKey = 'book_merge_${target.id}';
      final receipts = {...?_prefs.getStringList(receiptKey)};
      final indices = {for (final (i, c) in target.chapters.indexed) c.id: i};
      ReadingPosition? move(
        ReadingPosition value,
        Map<int, int> mapping,
        Novel source,
      ) {
        final index = chapterForPosition(source, value);
        if (index == null) return null;
        final chapterId = mapping[source.chapters[index].id];
        final next = indices[chapterId];
        return next == null
            ? null
            : ReadingPosition.fromJson({
                ...value.toJson(),
                'chapter': next,
                'chapterId': chapterId,
              });
      }

      final identity = {for (final c in target.chapters) c.id: c.id};
      var position = _positions[target.id];
      if (position != null) {
        position = move(position, identity, target) ?? position;
      }
      int? legacyChapter = _chapters[target.id];
      final bookmarks = <ReaderBookmark>[
        for (final mark in _bookmarks[target.id] ?? const <ReaderBookmark>[])
          ReaderBookmark(
            id: mark.id,
            chapterTitle: mark.chapterTitle,
            position: move(mark.position, identity, target) ?? mark.position,
            quote: mark.quote,
          ),
      ];
      final markIds = bookmarks.map((m) => m.id).toSet();
      final fingerprints = bookmarks.map(_bookmarkFingerprint).toSet();
      for (final entry in sources.entries) {
        final source = entry.key;
        if (source.id == target.id) continue;
        receipts.add('${source.id}');
        final old = _positions[source.id];
        final moved = old == null ? null : move(old, entry.value, source);
        if (moved != null &&
            (position == null || moved.updatedAt > position.updatedAt)) {
          position = moved;
        }
        if (legacyChapter == null &&
            hasRead(source.id) &&
            source.chapters.isNotEmpty) {
          final oldIndex = chapterForNovel(source);
          legacyChapter = indices[entry.value[source.chapters[oldIndex].id]];
        }
        for (final mark in _bookmarks[source.id] ?? const <ReaderBookmark>[]) {
          final mapped = move(mark.position, entry.value, source);
          if (mapped == null) continue;
          if (!receipts.add('m/${source.id}/${mark.id}')) continue;
          final id = '${source.id}/${mark.id}';
          final copied = ReaderBookmark(
            id: id,
            chapterTitle: target.chapters[mapped.chapter].title,
            position: mapped,
            quote: mark.quote,
          );
          if (fingerprints.add(_bookmarkFingerprint(copied)) &&
              markIds.add(id)) {
            bookmarks.add(copied);
          }
        }
      }
      if (bookmarks.length > 1000) {
        throw const FormatException('合并后超过 1000 个书签，请先整理书签；原阅读记录仍保留');
      }
      bookmarks.sort(
        (a, b) => b.position.updatedAt.compareTo(a.position.updatedAt),
      );
      final memberIds = sources.keys
          .map((b) => b.id)
          .where((id) => id != target.id)
          .toSet();
      final present =
          !isLocalBook(target.id) &&
          (onShelf ?? (contains(target.id) || memberIds.any(contains)));
      final shelf = {..._shelf}..removeAll(memberIds);
      if (present) {
        shelf.add(target.id);
      } else {
        shelf.remove(target.id);
      }
      final hidden = {..._hiddenHistory, ...memberIds.where(hasRead)};
      if (revealTarget && (position != null || legacyChapter != null)) {
        hidden.remove(target.id);
      }
      final chapter = position?.chapter ?? legacyChapter;
      final sourceAdded =
          memberIds.map((id) => _added[id]).whereType<int>().toList()..sort();
      final added =
          _added[target.id] ??
          (sourceAdded.isEmpty
              ? DateTime.now().millisecondsSinceEpoch
              : sourceAdded.first);
      final snapshot = jsonEncode(target.toSnapshot());
      final records = <String, Object>{
        receiptKey: receipts.toList()..sort(),
        'shelf': shelf.map((id) => '$id').toList(),
        'reading_history_hidden': hidden.map((id) => '$id').toList(),
        'novel_meta_${target.id}': snapshot,
        if (present) 'shelf_added_${target.id}': added,
        'chapter_${target.id}': ?chapter,
        if (position != null)
          'reading_position_${target.id}': jsonEncode(position.toJson()),
        if (bookmarks.isNotEmpty || _bookmarks.containsKey(target.id))
          'reader_bookmarks_${target.id}': jsonEncode(
            bookmarks.map((m) => m.toJson()).toList(),
          ),
      };
      records.removeWhere((key, value) {
        final old = _prefs.get(key);
        return old == value ||
            value is List<String> &&
                old is List<String> &&
                listEquals(value, old);
      });
      if (records.isNotEmpty) await _commitLibraryRecords(records);
      final oldShelf = {..._shelf};
      _shelf
        ..clear()
        ..addAll(shelf);
      for (final id in {...oldShelf, ...shelf}) {
        if (oldShelf.contains(id) != shelf.contains(id)) {
          _shelfRevisions[id] = shelfRevision(id) + 1;
        }
      }
      _hiddenHistory
        ..clear()
        ..addAll(hidden);
      _known[target.id] = target;
      _persistedNovels[target.id] = target;
      if (present) _added[target.id] = added;
      if (position != null) _positions[target.id] = position;
      if (chapter != null) _chapters[target.id] = chapter;
      if (bookmarks.isNotEmpty || _bookmarks.containsKey(target.id)) {
        _bookmarks[target.id] = bookmarks;
      }
      if (!_disposed && records.isNotEmpty) {
        _historyChanged();
        _bookmarkChanges.notifyListeners();
        notifyListeners();
      }
    });
  }

  Future<void> setChapter(int id, int chapter) async {
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then((_) => setChapter(id, chapter));
    }
    if (id <= 0 || chapter < 0) return;
    _chapters[id] = chapter;
    final reveal = _hiddenHistory.remove(id);
    final hidden = reveal ? _hiddenHistory.map((id) => '$id').toList() : null;
    notifyListeners();
    _historyChanged();
    await _queuePositionWrite(() async {
      await writeLibraryPreference(_prefs, 'chapter_$id', chapter);
      if (hidden != null) {
        await writeLibraryPreference(_prefs, 'reading_history_hidden', hidden);
      }
    });
  }

  Future<void> savePosition({
    required Novel novel,
    required int chapter,
    required double offset,
    required double maximum,
    required double width,
    bool notify = true,
    int? paragraphIndex,
    double paragraphFraction = 0,
    int? textOffset,
    double textScale = 1,
    String? typeface,
  }) {
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then(
        (_) => savePosition(
          novel: novel,
          chapter: chapter,
          offset: offset,
          maximum: maximum,
          width: width,
          notify: notify,
          paragraphIndex: paragraphIndex,
          paragraphFraction: paragraphFraction,
          textOffset: textOffset,
          textScale: textScale,
          typeface: typeface,
        ),
      );
    }
    if (novel.id <= 0 ||
        !offset.isFinite ||
        !maximum.isFinite ||
        !width.isFinite ||
        !paragraphFraction.isFinite ||
        !textScale.isFinite ||
        chapter < 0 ||
        chapter >= novel.chapters.length) {
      return Future.value();
    }
    final position = ReadingPosition(
      chapter: chapter,
      chapterId: novel.chapters[chapter].id,
      offset: offset.clamp(0, double.infinity),
      fraction: maximum > 0 ? (offset / maximum).clamp(0, 1) : 0,
      fontSize: fontSize,
      width: width,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      lineHeight: lineHeight,
      paragraphIndex: paragraphIndex != null && paragraphIndex >= 0
          ? paragraphIndex
          : null,
      paragraphFraction: paragraphFraction.clamp(0, 1),
      textOffset: textOffset != null && textOffset >= 0 ? textOffset : null,
      textScale: textScale.clamp(.5, 5),
      typeface: validFontChoice(typeface) ? typeface! : readerFontId,
      layout: _readerPreferences.layoutKey,
    );
    _positions[novel.id] = position;
    final chapterChanged = _chapters[novel.id] != chapter;
    _chapters[novel.id] = chapter;
    _known[novel.id] = novel;
    final reveal = _hiddenHistory.remove(novel.id);
    final hidden = reveal ? _hiddenHistory.map((id) => '$id').toList() : null;
    if (notify) notifyListeners();
    _historyChanged();
    final snapshot = _novelSnapshot(novel);
    final record = jsonEncode(position.toJson());
    return _queuePositionWrite(() async {
      if (chapterChanged) {
        await writeLibraryPreference(_prefs, 'chapter_${novel.id}', chapter);
      }
      await writeLibraryPreference(
        _prefs,
        'reading_position_${novel.id}',
        record,
      );
      if (snapshot != null) await _writeNovel(novel, snapshot);
      if (hidden != null) {
        await writeLibraryPreference(_prefs, 'reading_history_hidden', hidden);
      }
    });
  }

  Future<void> setTheme(ThemeMode mode) async {
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then((_) => setTheme(mode));
    }
    if (_theme == mode) {
      if (_prefs.get('theme') != null && _prefs.get('theme') != mode.name) {
        await writeLibraryPreference(_prefs, 'theme', mode.name);
      }
      return;
    }
    _theme = mode;
    _application.notifyListeners();
    _appearance.notifyListeners();
    _settings.notifyListeners();
    notifyListeners();
    await writeLibraryPreference(_prefs, 'theme', mode.name);
  }

  Future<void> setHomeBackgroundColor(
    Color? color, {
    Brightness brightness = Brightness.light,
  }) async {
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then(
        (_) => setHomeBackgroundColor(color, brightness: brightness),
      );
    }
    final normalized = color == null
        ? null
        : Color(0xff000000 | (color.toARGB32() & 0xffffff));
    await _queuePositionWrite(() async {
      await writeLibraryPreference(
        _prefs,
        brightness == Brightness.dark ? 'homeBackgroundDark' : 'homeBackground',
        normalized == null ? '' : backgroundHex(normalized),
      );
      if (brightness == Brightness.dark) {
        _homeBackgroundDarkColor = normalized;
      } else {
        _homeBackgroundColor = normalized;
      }
      if (!_disposed) {
        _application.notifyListeners();
        _appearance.notifyListeners();
        _settings.notifyListeners();
        notifyListeners();
      }
    });
  }

  Future<void> setAppTypeface(AppTypeface value) => setAppFont(value.name);

  Future<void> setAppFont(String choice) => _setFont(choice, reader: false);
  Future<void> setReaderTypeface(String choice) =>
      _setFont(choice, reader: true);
  Future<void> _setFont(String choice, {required bool reader}) async {
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then((_) => _setFont(choice, reader: reader));
    }
    if (!(reader && choice == followAppFont) && !fonts.available(choice)) {
      throw const FormatException('请先导入这款字体');
    }
    await fonts.ensureLoaded(choice);
    await _queuePositionWrite(() async {
      if ((reader ? _readerTypeface : appFontChoice) == choice) return;
      final oldReader = readerFontId;
      if (reader) {
        await _commitLibraryRecords({'readerTypeface': choice});
        _readerTypeface = choice;
      } else {
        final builtin = AppTypeface.fromRecord(choice);
        final custom = choice.startsWith('font_') ? choice : '';
        await _commitLibraryRecords({
          'appTypeface': builtin.name,
          'appCustomFont': custom,
        });
        _appTypeface = builtin;
        _appCustomFont = custom.isEmpty ? null : custom;
      }
      if (!_disposed) {
        if (!reader) {
          _application.notifyListeners();
          _appearance.notifyListeners();
        }
        if (oldReader != readerFontId) _readerSettings.notifyListeners();
        _settings.notifyListeners();
        notifyListeners();
      }
    });
  }

  Future<void> removeUserFont(String id) async {
    if (appFontChoice == id) await setAppFont('system');
    if (_readerTypeface == id) await setReaderTypeface(followAppFont);
    await fonts.remove(id);
    if (!_disposed) _settings.notifyListeners();
  }

  Future<void> setFontSize(double size, {bool persist = true}) =>
      setTypography(fontSize: size, persist: persist);

  Future<void> setLineHeight(double value, {bool persist = true}) =>
      setTypography(lineHeight: value, persist: persist);

  Future<void> setTypography({
    double? fontSize,
    double? lineHeight,
    bool persist = true,
  }) async {
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then(
        (_) => setTypography(
          fontSize: fontSize,
          lineHeight: lineHeight,
          persist: persist,
        ),
      );
    }
    final font = fontSize?.isFinite == true
        ? fontSize!.clamp(15.0, 27.0)
        : _fontSize;
    final spacing = lineHeight?.isFinite == true
        ? lineHeight!.clamp(1.3, 2.2)
        : _lineHeight;
    if (font != _fontSize || spacing != _lineHeight) {
      _fontSize = font;
      _lineHeight = spacing;
      _readerSettings.notifyListeners();
      _settings.notifyListeners();
    }
    if (persist) {
      if (fontSize?.isFinite == true) {
        await writeLibraryPreference(_prefs, 'readerFontSize', font);
      }
      if (lineHeight?.isFinite == true) {
        await writeLibraryPreference(_prefs, 'readerLineHeight', spacing);
      }
    }
  }

  Future<void> setPerformance(PerformancePreferences value) async {
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then((_) => setPerformance(value));
    }
    await _queuePositionWrite(() async {
      if (_performance == value) return;
      // Commit all switches together. A failed disk write must not leave the
      // visible mode different from the one restored on the next launch.
      await _commitLibraryRecords(value.toRecords());
      _performance = value;
      if (!_disposed) {
        _application.notifyListeners();
        _appearance.notifyListeners();
        _settings.notifyListeners();
      }
    });
  }

  Future<void> setReduceMotion(bool value) async {
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then((_) => setReduceMotion(value));
    }
    if (_reduceMotion == value) {
      if (_prefs.get('reduceMotion') != null &&
          _prefs.get('reduceMotion') != value) {
        await writeLibraryPreference(_prefs, 'reduceMotion', value);
      }
      return;
    }
    _reduceMotion = value;
    _application.notifyListeners();
    _appearance.notifyListeners();
    _settings.notifyListeners();
    notifyListeners();
    await writeLibraryPreference(_prefs, 'reduceMotion', value);
  }

  Future<void> setGlassBlur(double value, {bool persist = true}) async {
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then((_) => setGlassBlur(value, persist: persist));
    }
    if (!value.isFinite) return;
    final next = value.clamp(0.0, 24.0);
    if (_glassBlur != next) {
      _glassBlur = next;
      _glassChanges.notifyListeners();
      _appearance.notifyListeners();
      _settings.notifyListeners();
      notifyListeners();
    }
    if (persist) {
      await writeLibraryPreference(_prefs, 'glassBlur', next);
    }
  }

  Future<void> setGlassOpacity(double value, {bool persist = true}) async {
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then(
        (_) => setGlassOpacity(value, persist: persist),
      );
    }
    if (!value.isFinite) return;
    final next = value.clamp(0.0, 1.0);
    if (_glassOpacity != next) {
      _glassOpacity = next;
      _glassChanges.notifyListeners();
      _appearance.notifyListeners();
      _settings.notifyListeners();
      notifyListeners();
    }
    if (persist) {
      await writeLibraryPreference(_prefs, 'glassOpacity', next);
    }
  }

  Map<String, Object> _backupRecords() => {
    for (final entry in _illustrations.entries)
      'illustration_layout_${entry.key}': jsonEncode(
        entry.value.map((item) => item.toJson()).toList(),
      ),
    for (final key in _prefs.getKeys().where(
      (k) => k.startsWith('book_merge_'),
    ))
      key: _prefs.getStringList(key) ?? <String>[],
    'shelf': _shelf.map((id) => '$id').toList(),
    'reading_history_hidden': _hiddenHistory.map((id) => '$id').toList(),
    'local_shelf_hidden': _hiddenLocalBooks.map((id) => '$id').toList(),
    'recentSearches': _recentSearches,
    'theme': _theme.name,
    'homeBackground': _homeBackgroundColor == null
        ? ''
        : backgroundHex(_homeBackgroundColor!),
    'homeBackgroundDark': _homeBackgroundDarkColor == null
        ? ''
        : backgroundHex(_homeBackgroundDarkColor!),
    'readerFontSize': _fontSize,
    'appLanguage': language.name,
    'readerLineHeight': _lineHeight,
    'reduceMotion': _reduceMotion,
    'appTypeface': _appTypeface.name,
    'appCustomFont': _appCustomFont ?? '',
    'readerTypeface': _readerTypeface,
    ..._performance.toRecords(),
    'glassBlur': _glassBlur,
    'glassOpacity': _glassOpacity,
    'readerKeepScreenOn': _keepScreenOn,
    'readerPreferences': jsonEncode(_readerPreferences.toJson()),
    'shelfSort': _shelfSort,
    'shelfFilter': _shelfFilter,
    'shelfSourceFilter': _shelfSourceFilter,
    'shelfLayout': _shelfLayout,
    'adaptWhenOffline': _adaptWhenOffline,
    'localReaderMode': _localReaderMode,
    'directReading': _directReading,
    'combinedShelf': _combinedShelf,
    for (final entry in _added.entries) 'shelf_added_${entry.key}': entry.value,
    for (final entry in _known.entries)
      'novel_meta_${entry.key}': jsonEncode(entry.value.toSnapshot()),
    for (final entry in _chapters.entries) 'chapter_${entry.key}': entry.value,
    for (final entry in _positions.entries)
      'reading_position_${entry.key}': jsonEncode(entry.value.toJson()),
    for (final entry in _bookmarks.entries)
      'reader_bookmarks_${entry.key}': jsonEncode(
        entry.value.map((mark) => mark.toJson()).toList(),
      ),
  };

  Future<LibraryBackup> createBackup() async {
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then((_) => createBackup());
    }
    late LibraryBackup backup;
    await _queuePositionWrite(() async {
      backup = await LibraryBackup.fromRecords(_backupRecords());
    });
    return backup;
  }

  /// Merge, do not replace: current newer positions and metadata win. Memory is
  /// published only after all keys commit, with a rollback journal across kills.
  Future<void> restoreBackup(
    LibraryBackup backup, {
    bool importPreferences = false,
  }) async {
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then(
        (_) => restoreBackup(backup, importPreferences: importPreferences),
      );
    }
    final barrier = Completer<void>();
    _restoreBarrier = barrier;
    try {
      if (importPreferences && backup.records.containsKey('appLanguage')) {
        final restoredLanguage = AppLanguage.fromRecord(
          backup.records['appLanguage'],
        );
        if (chineseLocale(
              restoredLanguage.locale ??
                  WidgetsBinding.instance.platformDispatcher.locale,
            ).countryCode !=
            'CN') {
          await ChineseText.prepare();
        }
      }
      await _queuePositionWrite(() async {
        final records = backup.records;
        final shelf = {
          ..._shelf,
          ...(records['shelf'] as List<String>? ?? const [])
              .map(int.parse)
              .where((id) => !isLocalBook(id)),
        };
        final added = {..._added};
        final known = {..._known};
        final chapters = {..._chapters};
        final positions = {..._positions};
        final marks = <int, List<ReaderBookmark>>{
          for (final entry in _bookmarks.entries) entry.key: [...entry.value],
        };
        final hidden = {..._hiddenHistory};
        final hiddenLocal = {
          ..._hiddenLocalBooks,
          ...(records['local_shelf_hidden'] as List<String>? ??
                  const <String>[])
              .map(int.parse)
              .where(isLocalBook),
        };
        final changed = <String, Object>{};
        final oldRead = {..._chapters.keys, ..._positions.keys};
        for (final entry in records.entries) {
          final key = entry.key;
          if (key.startsWith('book_merge_')) {
            changed[key] = {
              ...?_prefs.getStringList(key),
              ...(entry.value as List<String>),
            }.toList()..sort();
          } else if (key.startsWith('novel_meta_')) {
            final id = int.parse(key.substring('novel_meta_'.length));
            if (!known.containsKey(id)) {
              known[id] = Novel.fromSnapshot(jsonDecode(entry.value as String));
              changed[key] = entry.value;
            }
          } else if (key.startsWith('shelf_added_')) {
            final id = int.parse(key.substring('shelf_added_'.length));
            if (!added.containsKey(id)) {
              added[id] = entry.value as int;
              changed[key] = entry.value;
            }
          } else if (key.startsWith('chapter_')) {
            final id = int.parse(key.substring('chapter_'.length));
            if (!chapters.containsKey(id) && !positions.containsKey(id)) {
              chapters[id] = entry.value as int;
              changed[key] = entry.value;
            }
          } else if (key.startsWith('reading_position_')) {
            final id = int.parse(key.substring('reading_position_'.length));
            final incoming = ReadingPosition.fromJson(
              jsonDecode(entry.value as String),
            );
            if (positions[id] == null ||
                positions[id]!.updatedAt < incoming.updatedAt) {
              positions[id] = incoming;
              chapters[id] = incoming.chapter;
              changed[key] = jsonEncode(incoming.toJson());
              changed['chapter_$id'] = incoming.chapter;
            }
          } else if (key.startsWith('illustration_layout_')) {
            final id = int.parse(key.substring('illustration_layout_'.length));
            final values = {
              for (final item in illustrationsFor(id)) item.url: item,
            };
            for (final raw in jsonDecode(entry.value as String) as List) {
              final incoming = IllustrationPlacement.fromJson(
                Map<String, dynamic>.from(raw),
              );
              if (values[incoming.url] == null ||
                  values[incoming.url]!.updatedAt < incoming.updatedAt) {
                values[incoming.url] = incoming;
              }
            }
            if (values.length > 2000) {
              throw const FormatException('合并后的插图排版超过上限');
            }
            changed[key] = jsonEncode(
              values.values.map((item) => item.toJson()).toList(),
            );
          } else if (key.startsWith('reader_bookmarks_')) {
            final id = int.parse(key.substring('reader_bookmarks_'.length));
            final current = marks.putIfAbsent(id, () => []);
            final fingerprints = current.map(_bookmarkFingerprint).toSet();
            final ids = current.map((mark) => mark.id).toSet();
            for (final raw in jsonDecode(entry.value as String) as List) {
              var mark = ReaderBookmark.fromJson(
                Map<String, dynamic>.from(raw),
              );
              if (!fingerprints.add(_bookmarkFingerprint(mark))) continue;
              var candidate = mark.id;
              for (var suffix = 1; ids.contains(candidate); suffix++) {
                candidate = 'import-${mark.position.updatedAt}-$suffix';
              }
              ids.add(candidate);
              if (candidate != mark.id) {
                mark = ReaderBookmark(
                  id: candidate,
                  chapterTitle: mark.chapterTitle,
                  position: mark.position,
                  quote: mark.quote,
                );
              }
              current.add(mark);
            }
            if (current.length > 1000) {
              throw const FormatException('合并后单本书超过 1000 个书签，请先整理书签');
            }
            current.sort(
              (a, b) => b.position.updatedAt.compareTo(a.position.updatedAt),
            );
            changed[key] = jsonEncode(
              current.map((mark) => mark.toJson()).toList(),
            );
          }
        }
        for (final id in shelf) {
          added.putIfAbsent(id, () => backup.createdAt);
          if (!_added.containsKey(id)) changed['shelf_added_$id'] = added[id]!;
        }
        for (final id
            in (records['reading_history_hidden'] as List<String>? ?? const [])
                .map(int.parse)) {
          if (!oldRead.contains(id) &&
              (positions.containsKey(id) || chapters.containsKey(id))) {
            hidden.add(id);
          }
        }
        final seen = <String>{};
        final searches = <String>[
          ..._recentSearches,
          ...(records['recentSearches'] as List<String>? ?? const []),
        ].where((term) => seen.add(term.toLowerCase())).take(12).toList();
        changed['shelf'] = shelf.map((id) => '$id').toList();
        changed['reading_history_hidden'] = hidden.map((id) => '$id').toList();
        changed['local_shelf_hidden'] = hiddenLocal.map((id) => '$id').toList();
        changed['recentSearches'] = searches;
        if (importPreferences) {
          if (records['homeBackground'] case final String value) {
            _homeBackgroundColor = parseBackgroundHex(value);
          }
          if (records['homeBackgroundDark'] case final String value) {
            _homeBackgroundDarkColor = parseBackgroundHex(value);
          }
          for (final key in backupPreferenceKeys) {
            if (records[key] case final value?) changed[key] = value;
          }
          if (records.containsKey('appTypeface') &&
              !records.containsKey('appCustomFont')) {
            changed['appCustomFont'] = '';
          }
        }
        if (importPreferences) {
          for (final choice in [
            records['appCustomFont'],
            records['readerTypeface'],
          ].whereType<String>()) {
            await fonts.ensureLoaded(choice);
          }
        }
        await _commitLibraryRecords(changed);
        for (final entry in changed.entries.where(
          (entry) => entry.key.startsWith('illustration_layout_'),
        )) {
          _illustrations[int.parse(
            entry.key.substring('illustration_layout_'.length),
          )] = [
            for (final raw in jsonDecode(entry.value as String) as List)
              IllustrationPlacement.fromJson(Map<String, dynamic>.from(raw)),
          ];
        }
        final oldShelf = {..._shelf};
        _shelf
          ..clear()
          ..addAll(shelf);
        for (final id in {...oldShelf, ...shelf}) {
          if (oldShelf.contains(id) != shelf.contains(id)) {
            _shelfRevisions[id] = shelfRevision(id) + 1;
          }
        }
        _added
          ..clear()
          ..addAll(added);
        _known
          ..clear()
          ..addAll(known);
        _persistedNovels
          ..clear()
          ..addAll(known);
        _chapters
          ..clear()
          ..addAll(chapters);
        _positions
          ..clear()
          ..addAll(positions);
        _bookmarks
          ..clear()
          ..addAll(marks);
        _hiddenHistory
          ..clear()
          ..addAll(hidden);
        _hiddenLocalBooks
          ..clear()
          ..addAll(hiddenLocal);
        _recentSearches = searches;
        if (importPreferences) {
          if (records['theme'] case final String value) {
            _theme = ThemeMode.values.firstWhere((mode) => mode.name == value);
          }
          if (records['readerFontSize'] case final num value) {
            _fontSize = value.toDouble();
          }
          if (records['readerLineHeight'] case final num value) {
            _lineHeight = value.toDouble();
          }
          if (records['glassBlur'] case final num value) {
            _glassBlur = value.toDouble();
          }
          if (records['glassOpacity'] case final num value) {
            _glassOpacity = value.toDouble();
          }
          if (records['reduceMotion'] case final bool value) {
            _reduceMotion = value;
          }
          if (records['appTypeface'] case final String value) {
            _appTypeface = AppTypeface.fromRecord(value);
            if (!records.containsKey('appCustomFont')) _appCustomFont = null;
          }
          if (records['appCustomFont'] case final String value) {
            _appCustomFont = value.isEmpty ? null : value;
          }
          if (records['readerTypeface'] case final String value) {
            _readerTypeface = value;
          }
          _performance = PerformancePreferences.fromRecords({
            ..._performance.toRecords(),
            for (final key in _performance.toRecords().keys)
              if (records.containsKey(key)) key: records[key],
          });
          if (records['readerKeepScreenOn'] case final bool value) {
            _keepScreenOn = value;
          }
          if (records['readerPreferences'] case final String value) {
            _readerPreferences = ReaderPreferences.fromRecord(value);
          }
          if (records['shelfSort'] case final String value) _shelfSort = value;
          if (records['shelfFilter'] case final String value) {
            _shelfFilter = value;
          }
          if (records['shelfSourceFilter'] case final String value) {
            _shelfSourceFilter = value;
          }
          if (records['shelfLayout'] case final String value) {
            _shelfLayout = value;
          }
          if (records['adaptWhenOffline'] case final bool value) {
            _adaptWhenOffline = value;
          }
          if (records['localReaderMode'] case final bool value) {
            _localReaderMode = value;
          }
          if (records['directReading'] case final bool value) {
            _directReading = value;
          }
          if (records['combinedShelf'] case final bool value) {
            _combinedShelf = value;
          }
        }
        if (!_disposed) {
          _historyChanged();
          _bookmarkChanges.notifyListeners();
          _illustrationChanges.notifyListeners();
          _searchChanges.notifyListeners();
          _shelfViewChanges.notifyListeners();
          if (importPreferences) {
            _application.notifyListeners();
            _appearance.notifyListeners();
            _glassChanges.notifyListeners();
            _readerSettings.notifyListeners();
            _readerBehaviorChanges.notifyListeners();
            _settings.notifyListeners();
            _navigationChanges.notifyListeners();
          }
          notifyListeners();
        }
      });
    } finally {
      _restoreBarrier = null;
      barrier.complete();
    }
  }

  static String _bookmarkFingerprint(ReaderBookmark bookmark) {
    final position = {...bookmark.position.toJson()}..remove('updatedAt');
    if (bookmark.quote.isNotEmpty) position['quote'] = bookmark.quote;
    return jsonEncode(position);
  }

  Future<void> _commitLibraryRecords(Map<String, Object> changes) async {
    changes.removeWhere(
      (key, value) => jsonEncode(_prefs.get(key)) == jsonEncode(value),
    );
    if (changes.isEmpty) return;
    final journal = jsonEncode({
      for (final key in changes.keys) key: _prefs.get(key),
    });
    if (utf8.encode(journal).length > LibraryBackup.maxBytes * 2) {
      throw const FormatException('本地恢复日志过大');
    }
    try {
      await writeLibraryPreference(_prefs, restoreJournalKey, journal);
      for (final entry in changes.entries) {
        await writeLibraryPreference(_prefs, entry.key, entry.value);
      }
      await writeLibraryPreference(_prefs, restoreJournalKey, null);
    } catch (_) {
      if (_prefs.get(restoreJournalKey) != null) {
        await recoverLibraryRestore(_prefs);
      }
      rethrow;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _appearance.dispose();
    _application.dispose();
    _glassChanges.dispose();
    _readerSettings.dispose();
    _settings.dispose();
    _history.dispose();
    _bookmarkChanges.dispose();
    _illustrationChanges.dispose();
    _searchChanges.dispose();
    _shelfViewChanges.dispose();
    _readerBehaviorChanges.dispose();
    _navigationChanges.dispose();
    _organization?.dispose();
    fonts.dispose();
    super.dispose();
  }
}
