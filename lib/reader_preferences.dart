import 'dart:convert';
import 'package:flutter/material.dart';
import 'archive_design.dart';

bool validReaderBackground(Object? value) =>
    value is String && RegExp(r'^background_[a-f0-9]{64}$').hasMatch(value);

enum ReaderBackgroundFit {
  cover('铺满裁切', BoxFit.cover),
  contain('完整显示', BoxFit.contain),
  fill('拉伸铺满', BoxFit.fill);

  const ReaderBackgroundFit(this.label, this.fit);
  final String label;
  final BoxFit fit;
}

enum ReaderPaper {
  system('跟随外观'),
  milk('奶白'),
  parchment('羊皮纸'),
  sage('浅苔'),
  night('夜读');

  const ReaderPaper(this.label);
  final String label;
}

enum ReaderMode {
  scroll('上下滚动'),
  paged('横排翻页'),
  vertical('竖排翻页');

  const ReaderMode(this.label);
  final String label;
  bool get paginated => this != scroll;
}

enum ReaderTapLayout {
  standard('常规'),
  rightHand('右手'),
  leftHand('左手');

  const ReaderTapLayout(this.label);
  final String label;
}

enum ReaderPageEffect {
  staggered('段落接续'),
  none('无动画'),
  slide('平移'),
  cover('覆盖'),
  paper('纸页翻动');

  const ReaderPageEffect(this.label);
  final String label;
  Duration get duration => switch (this) {
    staggered => const Duration(milliseconds: 620),
    none => Duration.zero,
    slide => const Duration(milliseconds: 300),
    cover => const Duration(milliseconds: 340),
    paper => const Duration(milliseconds: 440),
  };
}

/// Reader-only settings: changing paper never changes the rest of the app.
class ReaderPreferences {
  const ReaderPreferences({
    this.paper = ReaderPaper.system,
    this.margin = 26,
    this.marginLeft,
    this.marginRight,
    this.marginTop = 8,
    this.marginBottom = 8,
    this.paragraphGap = 12,
    this.indent = false,
    this.justify = false,
    this.tapPaging = false,
    this.volumePaging = false,
    this.brightness,
    this.autoScrollSpeed = 24,
    this.mode = ReaderMode.scroll,
    this.tapLayout = ReaderTapLayout.standard,
    this.edgeBrightness = false,
    this.pageEffect = ReaderPageEffect.staggered,
    this.hideSystemStatus = false,
    this.backgroundImage,
    this.backgroundFit = ReaderBackgroundFit.cover,
    this.backgroundOverlay = .7,
  });
  final String? backgroundImage;
  final ReaderBackgroundFit backgroundFit;
  final double backgroundOverlay;
  final ReaderPaper paper;
  final double margin, paragraphGap, autoScrollSpeed;
  // Null horizontal edges preserve old records and existing margin callers.
  final double? marginLeft, marginRight;
  final double marginTop, marginBottom;
  double get leftMargin => marginLeft ?? margin;
  double get rightMargin => marginRight ?? margin;
  double get bindingMargin => (leftMargin + rightMargin) / 2;
  final bool indent, justify, tapPaging, volumePaging;
  final double? brightness;
  final ReaderMode mode;
  final ReaderTapLayout tapLayout;
  final bool edgeBrightness;
  final ReaderPageEffect pageEffect;
  final bool hideSystemStatus;
  String get layoutKey =>
      leftMargin == 26 &&
          rightMargin == 26 &&
          marginTop == 8 &&
          marginBottom == 8 &&
          paragraphGap == 12 &&
          !indent &&
          !justify &&
          mode == ReaderMode.scroll
      ? ''
      : '${leftMargin == rightMargin && marginTop == 8 && marginBottom == 8 ? '$leftMargin' : '$leftMargin,$marginTop,$rightMargin,$marginBottom'}:$paragraphGap:$indent:$justify${mode == ReaderMode.scroll ? '' : ':${mode.name}'}';
  Color background(bool dark) => switch (paper) {
    ReaderPaper.system =>
      dark ? ArchiveDesign.darkBackground : const Color(0xFFF7F7F2),
    ReaderPaper.milk => const Color(0xFFF6F5EF),
    ReaderPaper.parchment => const Color(0xFFEDE2CA),
    ReaderPaper.sage => const Color(0xFFE4EBDD),
    ReaderPaper.night => ArchiveDesign.darkBackground,
  };
  Color foreground(bool dark) =>
      paper == ReaderPaper.night || paper == ReaderPaper.system && dark
      ? ArchiveDesign.darkInk
      : const Color(0xFF30352F);
  Map<String, Object?> toJson() => {
    'paper': paper.name,
    'margin': margin,
    if (marginLeft != null) 'marginLeft': marginLeft,
    if (marginRight != null) 'marginRight': marginRight,
    'marginTop': marginTop,
    'marginBottom': marginBottom,
    'paragraphGap': paragraphGap,
    'indent': indent,
    'justify': justify,
    'tapPaging': tapPaging,
    'volumePaging': volumePaging,
    'brightness': brightness,
    'autoScrollSpeed': autoScrollSpeed,
    'mode': mode.name,
    'tapLayout': tapLayout.name,
    'edgeBrightness': edgeBrightness,
    'pageEffect': pageEffect.name,
    'hideSystemStatus': hideSystemStatus,
    if (backgroundImage != null) 'backgroundImage': backgroundImage,
    'backgroundFit': backgroundFit.name,
    'backgroundOverlay': backgroundOverlay,
  };
  factory ReaderPreferences.fromJson(Map<String, dynamic> json) {
    double number(String key, double min, double max, double fallback) {
      final value = json[key];
      if (value == null) return fallback;
      if (value is! num || !value.isFinite || value < min || value > max) {
        throw const FormatException('阅读偏好数值超出范围');
      }
      return value.toDouble();
    }

    for (final key in [
      'indent',
      'justify',
      'tapPaging',
      'volumePaging',
      'edgeBrightness',
      'hideSystemStatus',
    ]) {
      if (json[key] != null && json[key] is! bool) {
        throw const FormatException('阅读偏好格式有误');
      }
    }
    if (json['backgroundImage'] != null &&
        !validReaderBackground(json['backgroundImage'])) {
      throw const FormatException('阅读背景图片记录无效');
    }
    return ReaderPreferences(
      backgroundImage: json['backgroundImage'] as String?,
      backgroundFit: ReaderBackgroundFit.values.byName(
        json['backgroundFit'] ?? 'cover',
      ),
      backgroundOverlay: number('backgroundOverlay', 0, 1, .7),
      paper: ReaderPaper.values.firstWhere(
        (p) => p.name == (json['paper'] ?? 'system'),
      ),
      margin: number('margin', 0, 80, 26),
      marginLeft: json['marginLeft'] == null
          ? null
          : number('marginLeft', 0, 80, 26),
      marginRight: json['marginRight'] == null
          ? null
          : number('marginRight', 0, 80, 26),
      marginTop: number('marginTop', 0, 80, 8),
      marginBottom: number('marginBottom', 0, 80, 8),
      paragraphGap: number('paragraphGap', 0, 32, 12),
      indent: json['indent'] == true,
      justify: json['justify'] == true,
      tapPaging: json['tapPaging'] == true,
      volumePaging: json['volumePaging'] == true,
      brightness: json['brightness'] == null
          ? null
          : number('brightness', .03, 1, 1),
      autoScrollSpeed: number('autoScrollSpeed', 8, 80, 24),
      mode: ReaderMode.values.byName(json['mode'] ?? 'scroll'),
      tapLayout: ReaderTapLayout.values.byName(json['tapLayout'] ?? 'standard'),
      edgeBrightness: json['edgeBrightness'] == true,
      hideSystemStatus: json['hideSystemStatus'] == true,
      pageEffect: ReaderPageEffect.values.byName(
        json['pageEffect'] ?? 'staggered',
      ),
    );
  }
  static ReaderPreferences fromRecord(Object? record) {
    try {
      return ReaderPreferences.fromJson(jsonDecode(record as String));
    } catch (_) {
      return const ReaderPreferences();
    }
  }

  ReaderPreferences copyWith({
    ReaderPaper? paper,
    double? margin,
    double? marginLeft,
    double? marginRight,
    double? marginTop,
    double? marginBottom,
    double? paragraphGap,
    bool? indent,
    bool? justify,
    bool? tapPaging,
    bool? volumePaging,
    double? brightness,
    bool systemBrightness = false,
    double? autoScrollSpeed,
    ReaderMode? mode,
    ReaderTapLayout? tapLayout,
    bool? edgeBrightness,
    ReaderPageEffect? pageEffect,
    bool? hideSystemStatus,
    String? backgroundImage,
    bool clearBackgroundImage = false,
    ReaderBackgroundFit? backgroundFit,
    double? backgroundOverlay,
  }) => ReaderPreferences(
    backgroundImage: clearBackgroundImage
        ? null
        : backgroundImage ?? this.backgroundImage,
    backgroundFit: backgroundFit ?? this.backgroundFit,
    backgroundOverlay: backgroundOverlay ?? this.backgroundOverlay,
    paper: paper ?? this.paper,
    margin: margin ?? this.margin,
    marginLeft: marginLeft ?? (margin ?? this.marginLeft),
    marginRight: marginRight ?? (margin ?? this.marginRight),
    marginTop: marginTop ?? this.marginTop,
    marginBottom: marginBottom ?? this.marginBottom,
    paragraphGap: paragraphGap ?? this.paragraphGap,
    indent: indent ?? this.indent,
    justify: justify ?? this.justify,
    tapPaging: tapPaging ?? this.tapPaging,
    volumePaging: volumePaging ?? this.volumePaging,
    brightness: systemBrightness ? null : brightness ?? this.brightness,
    autoScrollSpeed: autoScrollSpeed ?? this.autoScrollSpeed,
    mode: mode ?? this.mode,
    tapLayout: tapLayout ?? this.tapLayout,
    edgeBrightness: edgeBrightness ?? this.edgeBrightness,
    pageEffect: pageEffect ?? this.pageEffect,
    hideSystemStatus: hideSystemStatus ?? this.hideSystemStatus,
  );
}
