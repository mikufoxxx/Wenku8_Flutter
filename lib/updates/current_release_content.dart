import 'release_notices.dart';

class ReleaseSection {
  const ReleaseSection(this.title, this.items);
  final String title;
  final List<String> items;
}

const releaseFreeNotice = '**本项目完全免费，请勿购买所谓付费版、激活码或解锁服务。**';
const releaseSponsorLink = '☕ [请我喝杯咖啡 · 爱发电](https://afdian.com/a/mikufoxxx)';
const releaseProjectNotice =
    '本项目为第三方客户端，并非轻小说文库（Wenku8）官方应用，也不运营该站点。在线书目与内容来自轻小说文库，本地书籍由用户自行导入，安装包不附带小说文件。';
const releaseRightsNotice =
    '小说、封面和插图归各自权利人所有。请仅使用有权访问的内容，遵守来源网站规则，不得绕过访问限制、破解 DRM，或未经许可传播、出售内容。';
const releaseReadingNotice = '**在线内容以轻小说文库开放状态为准，不提供因版权限制而停止开放的在线书籍阅读。**';
const releaseMaintenanceNotice = '项目以稳定维护为主，后续非必要不再发版。';
const _interruption = '修复听书被通知等短暂打断后，可能无法恢复播放的问题。';
const _cache = '修复本地书籍在线听书时，临时缓存被清理后可能出现“缓存失败”的问题。';
const _retry = '优化在线语音的断线重试；加载失败时保留当前段落，避免跳过正文。';
const _resources = '修复连续听书时音频资源累积的问题，改善长时间使用的内存占用与流畅度。';
const _changes = [_interruption, _cache, _retry, _resources];
const _androidInstall = '**Android**：直接覆盖更新，不要先卸载旧版。';
const _iosInstall = '**iOS**：提供未签名包，主应用与小组件均需自行签名。';
const _harmonyInstall = '**HarmonyOS**：提供未签名包，需自行签名后安装。';
const _legacyInstall = '**iOS／HarmonyOS 0.5.0 用户**：请先手动更新一次。';
const _backup = '升级、整理存储或同步前，请先备份重要书籍和阅读记录。';
const publicReleaseNotes =
    '''
### 免费使用，请勿付费

$releaseFreeNotice

$releaseSponsorLink

$releaseProjectNotice

$releaseRightsNotice

$releaseReadingNotice

**$currentReleaseSourcePolicy**

### 本次更新

- $_interruption
- $_cache
- $_retry
- $_resources

### 后续维护

$releaseMaintenanceNotice

### 安装说明

- $_androidInstall
- $_iosInstall
- $_harmonyInstall
- $_legacyInstall

$_backup
''';
const currentReleaseNotes = publicReleaseNotes;
const currentReleaseSummary = [
  releaseFreeNotice,
  releaseSponsorLink,
  releaseReadingNotice,
  currentReleaseSourcePolicy,
  ..._changes,
  releaseMaintenanceNotice,
];
const currentReleaseSections = [
  ReleaseSection('重要说明 · 请务必阅读', [
    releaseFreeNotice,
    releaseSponsorLink,
    releaseProjectNotice,
    releaseRightsNotice,
    releaseReadingNotice,
    currentReleaseSourcePolicy,
  ]),
  ReleaseSection('本次更新与后续维护', [
    ..._changes,
    releaseMaintenanceNotice,
    _androidInstall,
    _iosInstall,
    _harmonyInstall,
    _legacyInstall,
    _backup,
  ]),
];
