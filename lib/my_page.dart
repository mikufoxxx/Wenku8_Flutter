import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_interactions.dart';
import 'app_ui.dart';
import 'bookmark_library_page.dart';
import 'catalog.dart';
import 'feature_pages.dart';
import 'library_state.dart';
import 'offline_repository.dart';
import 'pages.dart' show SettingsPage;
import 'ui_notifiers.dart';
import 'updates/app_updates.dart';
import 'updates/update_page.dart';
import 'wenku_features.dart';

class MyPage extends StatelessWidget {
  const MyPage({
    super.key,
    required this.state,
    required this.repository,
    this.showHeader = true,
  });
  final LibraryState state;
  final NovelRepository repository;
  final bool showHeader;

  Widget buildHeader(BuildContext context) => const Align(
    alignment: Alignment.centerLeft,
    child: ArchiveMasthead(title: '我的', code: '04 / PERSONAL ARCHIVE'),
  );

  @override
  Widget build(BuildContext context) {
    final features = WenkuFeaturesScope.maybeOf(context);
    final updates = AppUpdatesScope.maybeOf(context);
    return GlassHeaderLayout(
      showHeader: showHeader,
      header: buildHeader(context),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            key: const PageStorageKey('my-page'),
            padding: featurePadding(
              context,
            ).copyWith(bottom: MediaQuery.paddingOf(context).bottom + 120),
            children: [
              AnimatedBuilder(
                animation: Listenable.merge([
                  features?.account ?? state.bookmarkChanges,
                  ?features?.shelfSync,
                ]),
                builder: (context, _) {
                  final account = features?.account;
                  final profile = account?.profile;
                  return ContentPanel(
                    key: const ValueKey('my-account'),
                    onTap: account == null
                        ? null
                        : () => pushNovelPage<void>(
                            context,
                            WenkuAccountPage(
                              account: account,
                              state: state,
                              repository: repository,
                            ),
                            reduceMotion: state.reduceMotion,
                          ),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: account?.authenticated == true
                              ? SizedBox(
                                  width: 56,
                                  height: 56,
                                  child: account?.avatar == null
                                      ? const ArchiveIcon(
                                          CupertinoIcons.person_crop_circle,
                                          size: 40,
                                        )
                                      : Image.memory(
                                          account!.avatar!,
                                          fit: BoxFit.cover,
                                          cacheWidth:
                                              (56 *
                                                      MediaQuery.devicePixelRatioOf(
                                                        context,
                                                      ))
                                                  .ceil(),
                                          errorBuilder: (_, _, _) =>
                                              const ArchiveIcon(
                                                CupertinoIcons
                                                    .person_crop_circle,
                                                size: 40,
                                              ),
                                        ),
                                )
                              : Image.asset(
                                  'assets/branding/app-icon.png',
                                  width: 56,
                                  height: 56,
                                  cacheWidth:
                                      (56 *
                                              MediaQuery.devicePixelRatioOf(
                                                context,
                                              ))
                                          .ceil(),
                                  cacheHeight:
                                      (56 *
                                              MediaQuery.devicePixelRatioOf(
                                                context,
                                              ))
                                          .ceil(),
                                ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              AppText(
                                account?.authenticated == true
                                    ? profile?.displayName ?? '文库账号'
                                    : '登录文库账号',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 7),
                              AppText(
                                account?.authenticated == true
                                    ? profile == null
                                          ? '账号已连接'
                                          : '${profile.score} 积分 · ${profile.rank}${features?.shelfSync == null
                                                ? ''
                                                : features!.shelfSync!.syncing
                                                ? '\n书架正在同步'
                                                : features.shelfSync!.error != null
                                                ? '\n书架待同步 · ${features.shelfSync!.error}'
                                                : features.shelfSync!.syncedAt != null
                                                ? '\n书架已与文库同步'
                                                : ''}'
                                    : '轻小说文库账号 · 云书架与每日签到',
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.6,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        const ArchiveIcon(
                          CupertinoIcons.chevron_right,
                          size: 14,
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),
              ActiveListenableBuilder(
                listenable: state.bookmarkChanges,
                builder: (context) {
                  final count = libraryBookmarks(
                    state,
                    books: repository is OfflineNovelRepository
                        ? (repository as OfflineNovelRepository).local
                        : null,
                  ).length;
                  return FeatureEntry(
                    key: const ValueKey('my-bookmarks'),
                    title: '书签',
                    subtitle: count == 0 ? '收藏喜欢的句子与阅读位置' : '$count 条书签与摘录',
                    icon: CupertinoIcons.bookmark,
                    onTap: () => pushNovelPage<void>(
                      context,
                      BookmarkLibraryPage(state: state, repository: repository),
                      reduceMotion: state.reduceMotion,
                    ),
                  );
                },
              ),
              const SizedBox(height: 14),
              FeatureEntry(
                key: const ValueKey('my-settings'),
                title: '设置',
                subtitle: '阅读、外观、性能与本地数据',
                icon: CupertinoIcons.settings,
                onTap: () => pushNovelPage<void>(
                  context,
                  ArchiveFeaturePage(
                    title: '设置',
                    code: '04·1 / PREFERENCES',
                    child: SettingsPage(
                      state: state,
                      repository: repository,
                      showHeader: false,
                    ),
                  ),
                  reduceMotion: state.reduceMotion,
                ),
              ),
              const SizedBox(height: 14),
              FeatureEntry(
                key: const ValueKey('my-about'),
                title: '关于',
                subtitle:
                    '版本 ${updates?.installed?.version ?? currentAppVersion}${updates?.available == true ? ' · 有新版本' : ''}',
                icon: CupertinoIcons.info_circle,
                onTap: () => pushNovelPage<void>(
                  context,
                  AppUpdatePage(updates: updates),
                  reduceMotion: state.reduceMotion,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
