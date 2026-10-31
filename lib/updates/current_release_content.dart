import 'release_notices.dart';

class ReleaseSection {
  const ReleaseSection(this.title, this.items);
  final String title;
  final List<String> items;
}

const releaseFreeNotice = '**本项目完全免费，无任何赞助、打赏或付费渠道。**';
const releaseReadingNotice = '**在线内容以轻小说文库开放状态为准，不提供因版权限制而停止开放的在线书籍阅读。**';
const _connection = '优化官网连接、登录和验证，减小 Android 安装包。';
const _access = '完善访问受限提示及后台缓存的暂停、恢复。';
const _tags = '修复切换线路、标签页及部分书籍加载问题。';
const _theme = '修复阅读主题“恢复默认”不生效。';
const _reader = '修复 iPad 竖屏阅读显示异常。';
const _keepsake = '修复阅读纪念保存、分享和预览布局。';
const _changes = [_connection, _access, _tags, _theme, _reader, _keepsake];
const _installation =
    'Android 可直接更新。iOS 与 HarmonyOS 提供未签名包，需自行签名；iOS 主应用和小组件均需签名。iOS／HarmonyOS 0.5.0 用户请先手动更新一次。升级前请备份重要数据。';
const publicReleaseNotes =
    '''
### 免费使用，请勿付费

$releaseFreeNotice

$releaseReadingNotice

**$currentReleaseSourcePolicy**

### 本次更新
- $_connection
- $_access
- $_tags
- $_theme
- $_reader
- $_keepsake

### 安装说明
$_installation
''';
const currentReleaseNotes = publicReleaseNotes;
const currentReleaseSummary = [
  releaseFreeNotice,
  releaseReadingNotice,
  currentReleaseSourcePolicy,
  ..._changes,
];
const currentReleaseSections = [
  ReleaseSection('重要说明 · 请务必阅读', [
    releaseFreeNotice,
    releaseReadingNotice,
    currentReleaseSourcePolicy,
  ]),
  ReleaseSection('本次更新', [..._changes, _installation]),
];
