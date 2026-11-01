import 'release_notices.dart';

class ReleaseSection {
  const ReleaseSection(this.title, this.items);
  final String title;
  final List<String> items;
}

const releaseFreeNotice = '**本项目完全免费，无任何赞助、打赏或付费渠道。**';
const releaseReadingNotice = '**在线内容以轻小说文库开放状态为准，不提供因版权限制而停止开放的在线书籍阅读。**';
const releaseMaintenanceNotice = '项目已趋于稳定，0.5.5 预计是最后一次常规更新。后续非必要不再发版。';
const _search = '修复搜索结果跳转被误判、搜索无法继续的问题。';
const _access = '完善读取受限时的提示及后台缓存暂停、重试。';
const _import = '改进 iOS 文件夹选择和目录授权交接，保留原文件关联。';
const _storage = '修复鸿蒙官网会话密钥恢复问题，新增“修复官网连接”入口。';
const _changes = [_search, _access, _import, _storage];
const _installation =
    'Android 可直接更新。iOS 与 HarmonyOS 提供未签名包，需自行签名；iOS 主应用和小组件均需签名。iOS／HarmonyOS 0.5.0 用户请先手动更新一次。升级前请备份重要数据。';
const publicReleaseNotes =
    '''
### 免费使用，请勿付费

$releaseFreeNotice

$releaseReadingNotice

**$currentReleaseSourcePolicy**

### 后续维护
$releaseMaintenanceNotice

### 本次更新
- $_search
- $_access
- $_import
- $_storage

### 安装说明
$_installation
''';
const currentReleaseNotes = publicReleaseNotes;
const currentReleaseSummary = [
  releaseFreeNotice,
  releaseReadingNotice,
  currentReleaseSourcePolicy,
  releaseMaintenanceNotice,
  ..._changes,
];
const currentReleaseSections = [
  ReleaseSection('重要说明 · 请务必阅读', [
    releaseFreeNotice,
    releaseReadingNotice,
    currentReleaseSourcePolicy,
  ]),
  ReleaseSection('本次更新与后续维护', [
    releaseMaintenanceNotice,
    ..._changes,
    _installation,
  ]),
];
