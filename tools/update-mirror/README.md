# 轻小说文库更新镜像

<https://git.3952039.xyz> 提供项目介绍、版本说明和下载入口。App 使用 `/api/releases/latest` 检查更新；连接失败或限流时，仍可回退到 GitHub 的同一附件，无需用户选择来源。

首页的爱发电赞助卡片在 `worker.mjs` 的 `HOME` 模板中维护，链接固定为 <https://afdian.com/a/mikufoxxx>。赞助完全自愿，应用所有功能仍免费使用。

## 发布清单

当前发行已下架（2026-11-02）：白名单为空，旧版本下载路径也不可用；保留域名与恢复配置。

`distribution.mjs` 的 `APPROVED_RELEASES` 记录经过确认的版本标签和附件 ID。只有同时匹配的内容才会展示或下载；空清单时显示「暂无正式版本供下载」，不读取上游版本或附件缓存。

- 发布前核对实际安装包、版本、签名、对应源码和第三方许可，再更新清单。
- 替换附件后，其 ID 会改变，必须重新确认；文件名相同不代表身份相同。
- 访问控制在缓存读取前执行，GET、HEAD、Range 和带附件 ID 的请求使用相同规则。
- 页面回退到 GitHub 时，也只展示和下载清单中的附件。
- 不提供任意网址代理，不转发访问者的 Cookie 或 Authorization。

## 免费部署

沿用 Workers Free 和现有资源，不启用付费套餐、R2、付费加速或自动扩容。介绍页作为 Static Asset 提供；动态请求受免费额度和限流约束。最新额度以 [Cloudflare 官方说明](https://developers.cloudflare.com/workers/platform/limits/) 为准。

Worker 为 `wenku8-update`，自定义域名为 `git.3952039.xyz`。维护现有程序时只更新版本，保留域名与触发器配置：

```sh
npx wrangler versions upload
npx wrangler versions deploy VERSION_ID@100% --yes
```

使用上传命令实际返回的版本 ID。仅在明确调整域名或触发器时才修改路由配置。不要提交 Wrangler 本机状态、密钥或构建目录。

## 下载与缓存

`ReleaseRegistry` 共享公开版本清单并合并并发请求。边缘清单缓存为 120／300 秒，附件按 ID 缓存 1 小时，支持 HEAD 和 Range，不将部分响应存为完整文件。程序上线后可使用 `/health` 检查服务；它不返回访问者 IP。

可选的 GitHub 只读令牌只保存在 Cloudflare 加密 Secret `GITHUB_TOKEN`，不放在源码、普通 vars 或前端。客户端仍需核对附件大小、摘要（如提供）、包名、版本、构建号和签名。

公开查询按 IP 每分钟最多 120 次，下载每分钟最多 30 次；超限返回 429 和 `Retry-After: 60`。限流不是身份验证，不能阻止所有分布式滥用。保留现有 WAF 规则，关闭 `workers.dev` 和版本预览入口。

域名使用 Cloudflare 官方 Anycast 调度，不写死地理位置不明的 IP。本机测速不能代表中国大陆所有运营商。

参考：[版本部署](https://developers.cloudflare.com/workers/versions-and-deployments/)、[自定义域名](https://developers.cloudflare.com/workers/configuration/routing/custom-domains/)、[Cache API](https://developers.cloudflare.com/workers/runtime-apis/cache/)。
