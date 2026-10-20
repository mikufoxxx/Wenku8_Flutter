import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_background.dart';
import 'app_interactions.dart';
import 'app_ui.dart';
import 'book_documents.dart';
import 'background_color_palette.dart';
import 'library_state.dart';
import 'reader_background.dart';
import 'reader_preferences.dart';

class HomeBackgroundPage extends StatefulWidget {
  const HomeBackgroundPage({super.key, required this.state});
  final LibraryState state;
  @override
  State<HomeBackgroundPage> createState() => _HomeBackgroundPageState();
}

class _HomeBackgroundPageState extends State<HomeBackgroundPage> {
  Color _color = ArchiveDesign.background;
  late HSVColor _hsv = HSVColor.fromColor(_color);
  final _hex = TextEditingController();
  Brightness? _editingBrightness;
  final _drafts = <Brightness, String>{};

  Color _defaultColor(Brightness brightness) => brightness == Brightness.dark
      ? ArchiveDesign.darkBackground
      : ArchiveDesign.background;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_editingBrightness != null) return;
    final brightness = appOriginalBrightness(Theme.of(context));
    _editingBrightness = brightness;
    _color =
        widget.state.homeBackgroundFor(brightness) ?? _defaultColor(brightness);
    _hsv = HSVColor.fromColor(_color);
    _hex.text = backgroundHex(_color);
  }

  void _edit(Brightness brightness) {
    if (_editingBrightness == brightness) return;
    _drafts[_editingBrightness!] = _hex.text;
    setState(() {
      _editingBrightness = brightness;
      _hex.text =
          _drafts[brightness] ??
          backgroundHex(
            widget.state.homeBackgroundFor(brightness) ??
                _defaultColor(brightness),
          );
      _color = parseBackgroundHex(_hex.text) ?? _defaultColor(brightness);
      _hsv = HSVColor.fromColor(_color);
      _error = null;
    });
  }

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _select(Color color) => setState(() {
    _color = color;
    _hsv = HSVColor.fromColor(color);
    _hex.text = backgroundHex(color);
    _error = null;
  });

  Future<void> _save({bool reset = false}) async {
    final color = parseBackgroundHex(_hex.text);
    if (!reset && color == null) {
      setState(() => _error = '请输入六位 HEX 色值，例如 #E4EBDD');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.state.setHomeBackgroundColor(
        reset ? null : color,
        brightness: _editingBrightness!,
      );
      if (!mounted) return;
      if (reset) {
        _select(_defaultColor(_editingBrightness!));
      }
      final mode = _editingBrightness == Brightness.dark ? '深色模式' : '浅色模式';
      showNovelFeedback(context, reset ? '已恢复$mode默认背景' : '$mode背景已保存');
    } catch (_) {
      if (mounted) setState(() => _error = '背景颜色未保存，请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hsv = _hsv;
    final ink = ThemeData.estimateBrightnessForColor(_color) == Brightness.dark
        ? Colors.white
        : const Color(0xff20251f);
    return _BackgroundPage(
      title: '主页背景颜色',
      children: [
        const AppText(
          '浅色、深色模式分别保存背景颜色，切换外观时自动使用对应颜色。未设置的模式使用默认背景，阅读器配色独立。',
          style: TextStyle(height: 1.7),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          children: [
            for (final brightness in [Brightness.light, Brightness.dark])
              ChoiceChip(
                key: ValueKey('home-background-${brightness.name}'),
                label: AppText(brightness == Brightness.dark ? '深色模式' : '浅色模式'),
                selected: _editingBrightness == brightness,
                onSelected: _busy ? null : (_) => _edit(brightness),
              ),
          ],
        ),
        const SizedBox(height: 20),
        Container(
          key: const ValueKey('home-background-preview'),
          height: 140,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: _color,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppText(
                '我的阅读空间',
                style: TextStyle(
                  color: ink,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 14),
              AppText(
                '文字颜色会随背景明暗调整',
                style: TextStyle(color: ink, height: 1.6),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        BackgroundColorPalette(
          value: hsv,
          onChanged: _busy
              ? null
              : (value) {
                  _select(value.toColor());
                  _hsv = value;
                },
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final color in const [
              Color(0xfff4f3ef),
              Color(0xffede2ca),
              Color(0xffe4ebdd),
              Color(0xffdde8ef),
              Color(0xffe9e0ee),
              Color(0xffefdfdf),
              Color(0xff354b45),
              Color(0xff263442),
              Color(0xff191919),
            ])
              Semantics(
                label: '背景色 ${backgroundHex(color)}',
                selected: color == _color,
                button: true,
                child: InkWell(
                  onTap: _busy ? null : () => _select(color),
                  borderRadius: BorderRadius.circular(24),
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    child: color == _color
                        ? Icon(
                            Icons.check,
                            color:
                                ThemeData.estimateBrightnessForColor(color) ==
                                    Brightness.dark
                                ? Colors.white
                                : Colors.black,
                          )
                        : null,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 24),
        TextField(
          key: const ValueKey('home-background-hex'),
          controller: _hex,
          enabled: !_busy,
          maxLength: 7,
          autocorrect: false,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'HEX 色值',
            hintText: '#E4EBDD',
            counterText: '',
          ),
          onChanged: (text) {
            final color = parseBackgroundHex(text);
            if (color != null) {
              setState(() {
                _color = color;
                _hsv = HSVColor.fromColor(color);
                _error = null;
              });
            }
          },
        ),
        const SizedBox(height: 16),
        if (_error != null) _BackgroundError(_error!),
        const SizedBox(height: 16),
        GlassPillButton(
          key: const ValueKey('save-home-background'),
          label: '保存颜色',
          icon: CupertinoIcons.check_mark,
          onPressed: _busy ? null : () => _save(),
        ),
        const SizedBox(height: 12),
        GlassTextButton(
          key: const ValueKey('reset-home-background'),
          onPressed: _busy ? null : () => _save(reset: true),
          child: const AppText('恢复此模式默认背景'),
        ),
      ],
    );
  }
}

class ReaderBackgroundPage extends StatefulWidget {
  const ReaderBackgroundPage({super.key, required this.state, this.documents});
  final LibraryState state;
  final BookDocuments? documents;
  @override
  State<ReaderBackgroundPage> createState() => _ReaderBackgroundPageState();
}

class _ReaderBackgroundPageState extends State<ReaderBackgroundPage> {
  late final _documents = widget.documents ?? BookDocuments();
  late String? _image = widget.state.readerPreferences.backgroundImage;
  late ReaderBackgroundFit _fit = widget.state.readerPreferences.backgroundFit;
  late double _overlay = widget.state.readerPreferences.backgroundOverlay;
  final _drafts = <String>{};
  bool _busy = false;
  bool _saving = false;
  String? _error;

  void _removeQuietly(String? id) {
    if (id != null && id != widget.state.readerPreferences.backgroundImage) {
      unawaited(widget.state.backgrounds.remove(id).catchError((Object _) {}));
    }
  }

  @override
  void dispose() {
    if (!_saving) _cleanDrafts();
    super.dispose();
  }

  void _cleanDrafts() {
    for (final id in _drafts) {
      _removeQuietly(id);
    }
  }

  Future<void> _choose() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    BookDocumentSelection? selected;
    try {
      selected = await _documents.pickBackgroundImage();
      if (selected == null || !mounted) return;
      final id = await widget.state.backgrounds.importFile(selected.path!);
      if (!mounted) {
        _removeQuietly(id);
        return;
      }
      if (id != widget.state.readerPreferences.backgroundImage) _drafts.add(id);
      setState(() => _image = id);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is FormatException
              ? error.message
              : '无法导入图片，请重新选择',
        );
      }
    } finally {
      if (selected != null) {
        try {
          await _documents.releaseBooks([selected]);
        } catch (_) {}
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save({bool reset = false}) async {
    _saving = true;
    setState(() {
      _busy = true;
      _error = null;
    });
    final previous = widget.state.readerPreferences.backgroundImage;
    try {
      await widget.state.setReaderPreferences(
        widget.state.readerPreferences.copyWith(
          backgroundImage: _image,
          clearBackgroundImage: reset || _image == null,
          backgroundFit: reset ? ReaderBackgroundFit.cover : _fit,
          backgroundOverlay: reset ? .7 : _overlay,
        ),
      );
      _drafts.remove(widget.state.readerPreferences.backgroundImage);
      _removeQuietly(previous);
      if (!mounted) return;
      if (reset) {
        setState(() {
          _image = null;
          _fit = ReaderBackgroundFit.cover;
          _overlay = .7;
        });
      }
      showNovelFeedback(context, reset ? '已恢复纯色阅读背景' : '阅读背景已保存');
    } catch (_) {
      if (mounted) setState(() => _error = '阅读背景未保存，请重试');
    } finally {
      _saving = false;
      if (!mounted) _cleanDrafts();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preferences = widget.state.readerPreferences.copyWith(
      backgroundImage: _image,
      clearBackgroundImage: _image == null,
      backgroundFit: _fit,
      backgroundOverlay: _overlay,
    );
    final dark = appOriginalBrightness(Theme.of(context)) == Brightness.dark;
    return _BackgroundPage(
      title: '阅读背景图片',
      children: [
        const AppText(
          '选择 JPG、PNG 或 WebP 图片，调整后保存。图片保存在本机，移动原图不影响阅读；跨设备恢复备份后需重新选择图片。',
          style: TextStyle(height: 1.7),
        ),
        const SizedBox(height: 20),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 220,
            child: ReaderBackgroundSurface(
              key: const ValueKey('reader-background-preview'),
              store: widget.state.backgrounds,
              preferences: preferences,
              paper: preferences.background(dark),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: AppText(
                  '阅读背景预览\n\n风翻过书页，故事在此刻继续。\n\n调高遮罩强度，可以让正文更清晰。',
                  style: TextStyle(
                    fontFamily: widget.state.readerFontFamily,
                    fontSize: 18,
                    height: 1.8,
                    color: preferences.foreground(dark),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        GlassPillButton(
          key: const ValueKey('choose-reader-background'),
          label: _busy
              ? '正在处理'
              : _image == null
              ? '选择背景图片'
              : '更换背景图片',
          icon: CupertinoIcons.photo,
          onPressed: _busy ? null : _choose,
        ),
        const SizedBox(height: 12),
        const AppText(
          '单张不超过 32 MiB。图片会适度缩小，以减少阅读时的内存占用。',
          style: TextStyle(fontSize: 12, height: 1.7),
        ),
        const SizedBox(height: 24),
        const AppText('显示方式'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final fit in ReaderBackgroundFit.values)
              ChoiceChip(
                key: ValueKey('background-fit-${fit.name}'),
                label: AppText(fit.label),
                selected: fit == _fit,
                onSelected: _busy ? null : (_) => setState(() => _fit = fit),
              ),
          ],
        ),
        const SizedBox(height: 20),
        AppText('遮罩强度 ${(_overlay * 100).round()}%'),
        Slider(
          key: const ValueKey('reader-background-overlay'),
          value: _overlay,
          divisions: 100,
          label: '${(_overlay * 100).round()}%',
          onChanged: _busy ? null : (v) => setState(() => _overlay = v),
        ),
        if (_error != null) _BackgroundError(_error!),
        const SizedBox(height: 16),
        GlassPillButton(
          key: const ValueKey('save-reader-background'),
          label: '保存阅读背景',
          icon: CupertinoIcons.check_mark,
          onPressed: _busy ? null : () => _save(),
        ),
        const SizedBox(height: 12),
        GlassTextButton(
          key: const ValueKey('reset-reader-background'),
          onPressed: _busy ? null : () => _save(reset: true),
          child: const AppText('恢复默认背景'),
        ),
      ],
    );
  }
}

class _BackgroundError extends StatelessWidget {
  const _BackgroundError(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: AppText(
      message,
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    ),
  );
}

class _BackgroundPage extends StatelessWidget {
  const _BackgroundPage({required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Atmosphere(
      child: GlassHeaderLayout(
        header: ArchiveHeaderBar(
          leading: GlassIconButton(
            icon: CupertinoIcons.back,
            label: '返回',
            onPressed: () => Navigator.pop(context),
          ),
          title: ArchiveRouteTitle(title: title, code: 'APPEARANCE'),
        ),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                24,
                MediaQuery.paddingOf(context).top +
                    FrostedHeader.toolbarHeight +
                    20,
                24,
                MediaQuery.paddingOf(context).bottom + 36,
              ),
              children: children,
            ),
          ),
        ),
      ),
    ),
  );
}
