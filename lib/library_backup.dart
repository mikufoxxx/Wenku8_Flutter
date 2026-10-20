import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'catalog.dart';
import 'book_identity.dart';
import 'performance_preferences.dart';
import 'local_book_media.dart';
import 'reader_preferences.dart';
import 'user_fonts.dart';
import 'illustration_placement.dart';
import 'app_background.dart';

final backupPreferenceKeys = <String>{
  'theme',
  'homeBackground',
  'homeBackgroundDark',
  'appLanguage',
  'readerFontSize',
  'readerLineHeight',
  'reduceMotion',
  'glassBlur',
  'glassOpacity',
  'readerKeepScreenOn',
  'readerPreferences',
  'checkAppUpdates',
  'appTypeface',
  'appCustomFont',
  'readerTypeface',
  'shelfSort',
  'shelfFilter',
  'shelfSourceFilter',
  'shelfLayout',
  'adaptWhenOffline',
  'localReaderMode',
  'directReading',
  'combinedShelf',
  PerformancePreferences.modeKey,
  ...PerformanceEffect.values.map((effect) => effect.preferenceKey),
};
const _listKeys = {
  'shelf',
  'reading_history_hidden',
  'recentSearches',
  'local_shelf_hidden',
};
const restoreJournalKey = 'library_restore_journal';
final _recordKey = RegExp(
  r'^(chapter|shelf_added|novel_meta|reading_position|reader_bookmarks|book_merge|illustration_layout)_([1-9][0-9]{0,9})$',
);

bool isLibraryRecordKey(String key) =>
    backupPreferenceKeys.contains(key) ||
    _listKeys.contains(key) ||
    (_recordKey.hasMatch(key) &&
        int.parse(_recordKey.firstMatch(key)![2]!) <= 0x7fffffff);

class LibraryBackup {
  LibraryBackup._(this.createdAt, Map<String, Object> records)
    : records = Map.unmodifiable(records);
  static const maxBytes = 4 * 1024 * 1024;
  final int createdAt;
  final Map<String, Object> records;
  int get shelfCount => (records['shelf'] as List<String>? ?? const [])
      .where((id) => !isLocalBook(int.parse(id)))
      .length;
  int get positionCount =>
      records.keys.where((key) => key.startsWith('reading_position_')).length;
  int get bookmarkCount => records.entries
      .where((entry) => entry.key.startsWith('reader_bookmarks_'))
      .fold<int>(
        0,
        (sum, entry) =>
            sum + (jsonDecode(entry.value as String) as List).length,
      );
  int get historyCount => records.keys
      .where(
        (key) =>
            key.startsWith('chapter_') || key.startsWith('reading_position_'),
      )
      .map((key) => key.substring(key.lastIndexOf('_') + 1))
      .toSet()
      .length;

  static Future<LibraryBackup> parse(String text) =>
      compute(_decodeBackup, text);
  static Future<LibraryBackup> fromRecords(Map<String, Object> records) =>
      compute(_createBackup, records);
  Future<String> encode() =>
      compute(_encodeBackup, (createdAt: createdAt, records: records));
}

String _encodeBackup(({int createdAt, Map<String, Object> records}) backup) {
  final text = jsonEncode({
    'format': 'wenku8-local-backup',
    'version': 1,
    'createdAt': backup.createdAt,
    'records': backup.records,
  });
  if (utf8.encode(text).length > LibraryBackup.maxBytes) {
    throw const FormatException('备份超过 4 MiB，请减少本地记录后重试');
  }
  return text;
}

LibraryBackup _createBackup(Map<String, Object> records) {
  final backup = LibraryBackup._(
    DateTime.now().millisecondsSinceEpoch,
    _validateRecords(records),
  );
  _encodeBackup((createdAt: backup.createdAt, records: backup.records));
  return backup;
}

LibraryBackup _decodeBackup(String text) {
  if (text.length > LibraryBackup.maxBytes ||
      utf8.encode(text).length > LibraryBackup.maxBytes) {
    throw const FormatException('备份文件超过 4 MiB');
  }
  final raw = jsonDecode(text);
  if (raw is! Map ||
      raw['format'] != 'wenku8-local-backup' ||
      raw['version'] != 1 ||
      raw['createdAt'] is! int ||
      raw['createdAt'] < 0 ||
      raw['records'] is! Map) {
    throw const FormatException('不是受支持的文库备份文件');
  }
  return LibraryBackup._(
    raw['createdAt'],
    _validateRecords(Map<String, dynamic>.from(raw['records'])),
  );
}

Map<String, Object> _validateRecords(Map<String, dynamic> input) {
  if (input.length > 50000) throw const FormatException('备份记录数量过多');
  final output = <String, Object>{};
  for (final entry in input.entries) {
    final key = entry.key;
    final value = entry.value;
    if (!isLibraryRecordKey(key)) throw const FormatException('备份包含未识别的记录');
    if (key.startsWith('book_merge_')) {
      if (value is! List ||
          value.length > 20000 ||
          value.any((v) => v is! String || v.length > 512)) {
        throw const FormatException('分卷阅读记录格式有误');
      }
      final receipts = <String>{};
      for (final receipt in value.cast<String>()) {
        final parts = receipt.split('/');
        final id = int.tryParse(
          parts.first == 'm' && parts.length >= 3 ? parts[1] : receipt,
        );
        if (id == null ||
            id <= 0 ||
            id > 0x7fffffff ||
            RegExp(r'[\x00-\x1f]').hasMatch(receipt)) {
          throw const FormatException('分卷阅读记录格式有误');
        }
        receipts.add(receipt);
      }
      output[key] = receipts.toList()..sort();
    } else if (_listKeys.contains(key)) {
      if (value is! List ||
          value.length > (key == 'recentSearches' ? 12 : 10000) ||
          value.any((item) => item is! String)) {
        throw const FormatException('备份列表格式有误');
      }
      final list = <String>[];
      final seen = <String>{};
      for (final item in value.cast<String>()) {
        if (key == 'recentSearches') {
          if (item.trim().isEmpty ||
              item.length > 120 ||
              RegExp(r'[\x00-\x1f]').hasMatch(item)) {
            throw const FormatException('搜索记录格式有误');
          }
          if (seen.add(item.trim().toLowerCase())) list.add(item.trim());
        } else {
          final id = int.tryParse(item);
          if (id == null || id <= 0 || id > 0x7fffffff) {
            throw const FormatException('书籍标识格式有误');
          }
          if (seen.add('$id')) list.add('$id');
        }
      }
      output[key] = List<String>.unmodifiable(list);
    } else if (backupPreferenceKeys.contains(key)) {
      final valid = switch (key) {
        'theme' => ['system', 'light', 'dark'].contains(value),
        'shelfSort' => ['recentRead', 'recentAdded', 'title'].contains(value),
        'shelfLayout' => ['shelf', 'list'].contains(value),
        'shelfSourceFilter' => [
          'all',
          'local',
          'cached',
          'online',
        ].contains(value),
        'shelfFilter' => [
          'all',
          'unread',
          'reading',
          'finished',
        ].contains(value),
        'reduceMotion' ||
        'readerKeepScreenOn' ||
        'adaptWhenOffline' ||
        'localReaderMode' ||
        'directReading' ||
        'combinedShelf' ||
        'checkAppUpdates' => value is bool,
        'appLanguage' => [
          'system',
          'simplified',
          'hongKong',
          'taiwan',
        ].contains(value),
        'appTypeface' => value == 'system' || value == 'sourceHanSerif',
        'appCustomFont' =>
          value == '' ||
              (validFontChoice(value) && (value as String).startsWith('font_')),
        'homeBackground' || 'homeBackgroundDark' =>
          value is String &&
              (value.isEmpty || parseBackgroundHex(value) != null),
        'readerTypeface' => validFontChoice(value, follow: true),
        'readerFontSize' => _number(value, 15, 27),
        'readerLineHeight' => _number(value, 1.3, 2.2),
        'readerPreferences' => _validReaderPreferences(value),
        'glassBlur' => _number(value, 0, 24),
        'glassOpacity' => _number(value, 0, 1),
        _ =>
          (key == PerformancePreferences.modeKey ||
                  PerformanceEffect.values.any(
                    (e) => e.preferenceKey == key,
                  )) &&
              value is bool,
      };
      if (!valid) throw const FormatException('偏好设置格式有误');
      output[key] = value is num ? value.toDouble() : value as Object;
    } else if (key.startsWith('chapter_') || key.startsWith('shelf_added_')) {
      if (value is! int ||
          value < 0 ||
          value > (key.startsWith('chapter_') ? 100000 : 1000000000000000)) {
        throw const FormatException('阅读记录格式有误');
      }
      output[key] = value;
    } else {
      if (value is! String || value.length > 256 * 1024) {
        throw const FormatException('书籍记录格式有误');
      }
      final record = jsonDecode(value);
      if (key.startsWith('novel_meta_')) {
        if (record is! Map<String, dynamic>) {
          throw const FormatException('书籍信息格式有误');
        }
        for (final field in [
          'title',
          'author',
          'genre',
          'summary',
          'coverUrl',
          'lastUpdate',
        ]) {
          final text = record[field];
          if (text != null &&
              (text is! String ||
                  text.length > (field == 'summary' ? 100000 : 2048))) {
            throw const FormatException('书籍信息过长或格式有误');
          }
        }
        final novel = Novel.fromSnapshot(record);
        if (novel.id != int.parse(key.substring('novel_meta_'.length))) {
          throw const FormatException('书籍标识不一致');
        }
        final url = novel.coverUrl == null
            ? null
            : Uri.tryParse(novel.coverUrl!);
        if (url != null &&
            !['http', 'https'].contains(url.scheme) &&
            !(LocalBookMedia.valid(url) && url.host == '${novel.id}')) {
          throw const FormatException('封面地址格式有误');
        }
        final colors = record['colors'];
        if (colors != null &&
            (colors is! List ||
                colors.length > 8 ||
                colors.any(
                  (color) => color is! int || color < 0 || color > 0xffffffff,
                ))) {
          throw const FormatException('封面颜色格式有误');
        }
        output[key] = jsonEncode(novel.toSnapshot());
      } else if (key.startsWith('reading_position_')) {
        _validatePosition(record);
        output[key] = jsonEncode(record);
      } else if (key.startsWith('illustration_layout_')) {
        if (record is! List || record.length > 2000) {
          throw const FormatException('插图排版数量过多或格式有误');
        }
        final ids = <String>{};
        for (final raw in record) {
          if (raw is! Map) throw const FormatException('插图排版格式有误');
          final placement = IllustrationPlacement.fromJson(
            Map<String, dynamic>.from(raw),
          );
          if (!ids.add(placement.id)) throw const FormatException('插图排版记录重复');
        }
        output[key] = jsonEncode(record);
      } else {
        if (record is! List || record.length > 1000) {
          throw const FormatException('书签数量过多或格式有误');
        }
        final seen = <String>{};
        for (final mark in record) {
          if (mark is! Map ||
              mark['id'] is! String ||
              (mark['id'] as String).isEmpty ||
              (mark['id'] as String).length > 256 ||
              !seen.add(mark['id']) ||
              mark['chapterTitle'] is! String ||
              (mark['chapterTitle'] as String).length > 2048 ||
              (mark['quote'] != null &&
                  (mark['quote'] is! String ||
                      (mark['quote'] as String).length > 12000))) {
            throw const FormatException('书签格式有误');
          }
          _validatePosition(mark['position']);
        }
        output[key] = jsonEncode(record);
      }
    }
  }
  return output;
}

bool _number(Object? value, double min, double max) =>
    value is num && value.isFinite && value >= min && value <= max;
bool _validReaderPreferences(Object? value) {
  if (value is! String || value.length > 4096) return false;
  try {
    ReaderPreferences.fromJson(jsonDecode(value));
    return true;
  } catch (_) {
    return false;
  }
}

void _validatePosition(Object? record) {
  if (record is! Map ||
      record['chapter'] is! int ||
      !_number(record['chapter'], 0, 100000) ||
      record['chapterId'] is! int ||
      !_number(record['chapterId'], 0, 0x7fffffff) ||
      !_number(record['offset'], 0, 1e12) ||
      !_number(record['fraction'], 0, 1) ||
      !_number(record['fontSize'], 1, 200) ||
      !_number(record['width'], 0, 1e6) ||
      record['updatedAt'] is! int ||
      !_number(record['updatedAt'], 0, 1e15) ||
      (record['lineHeight'] != null &&
          !_number(record['lineHeight'], 1.3, 2.2)) ||
      (record['textScale'] != null && !_number(record['textScale'], .5, 5)) ||
      (record['typeface'] != null && !validFontChoice(record['typeface'])) ||
      (record['layout'] != null &&
          (record['layout'] is! String ||
              (record['layout'] as String).length > 128)) ||
      (record['paragraphIndex'] != null &&
          (record['paragraphIndex'] is! int ||
              !_number(record['paragraphIndex'], 0, 1000000))) ||
      (record['paragraphFraction'] != null &&
          !_number(record['paragraphFraction'], 0, 1)) ||
      (record['textOffset'] != null &&
          (record['textOffset'] is! int ||
              !_number(record['textOffset'], 0, 100000000)))) {
    throw const FormatException('阅读位置格式有误');
  }
}

Future<void> writeLibraryPreference(
  SharedPreferences prefs,
  String key,
  Object? value,
) async {
  try {
    final success = switch (value) {
      null => await prefs.remove(key),
      bool v => await prefs.setBool(key, v),
      int v => await prefs.setInt(key, v),
      double v => await prefs.setDouble(key, v),
      String v => await prefs.setString(key, v),
      List<String> v => await prefs.setStringList(key, v),
      _ => throw const FormatException('Unsupported preference value'),
    };
    if (!success) throw StateError('Local preference did not commit');
  } catch (_) {
    // The legacy plugin updates its in-memory cache before returning a failed
    // platform write. Reload prevents a failed hide/favorite from surviving a
    // new LibraryState instance in the same process.
    await prefs.reload();
    rethrow;
  }
}

/// An interrupted multi-key merge is rolled back before LibraryState is loaded.
/// The journal contains only allowlisted library keys, never session/API data.
Future<void> recoverLibraryRestore(SharedPreferences prefs) async {
  final raw = prefs.get(restoreJournalKey);
  if (raw == null) return;
  if (raw is! String || raw.length > LibraryBackup.maxBytes * 2) {
    throw const FormatException('本地恢复日志格式有误');
  }
  final journal = jsonDecode(raw);
  if (journal is! Map || journal.length > 50000) {
    throw const FormatException('本地恢复日志格式有误');
  }
  for (final entry in journal.entries) {
    if (entry.key is! String || !isLibraryRecordKey(entry.key)) {
      throw const FormatException('本地恢复日志包含未知记录');
    }
    final value = entry.value;
    if (value != null &&
        value is! String &&
        value is! bool &&
        value is! int &&
        value is! double &&
        !(value is List && value.every((item) => item is String))) {
      throw const FormatException('本地恢复日志格式有误');
    }
  }
  for (final entry in journal.entries) {
    await writeLibraryPreference(
      prefs,
      entry.key,
      entry.value is List ? List<String>.from(entry.value) : entry.value,
    );
  }
  await writeLibraryPreference(prefs, restoreJournalKey, null);
}
