# 已停用的轻小说文库更新镜像

项目展示页迁至 GitHub Pages：<https://mikufoxxx.github.io/Wenku8_Flutter/>。页面仅展示项目、赞助与反馈入口，不提供下载、不自动查询发行版，也不使用 Worker。

旧客户端仍会访问 `git.3952039.xyz` 的更新接口。2026-11-03 已收紧该主机的 Cloudflare WAF 白名单：只允许 GET／HEAD 访问 `/` 与 `/index.html`，这两个入口由边缘规则 301 跳转至 GitHub Pages；其他路径在 Worker 执行前阻断。旧镜像不再执行更新、下载或健康检查请求。仅将 Worker 内的响应改成 404 或 429 不能节省调用额度。其他主机和原有速率限制规则不变。

首页的爱发电赞助卡片在 `worker.mjs` 的 `HOME` 模板中维护，链接固定为 <https://afdian.com/a/mikufoxxx>。赞助完全自愿，应用所有功能仍免费使用。

## 发布清单

当前发行已下架（2026-11-02）：白名单为空，旧版本下载路径也不可用。以下内容是保留的恢复配置，不作为重新开放镜像的授权。

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

恢复配置中的 `ReleaseRegistry` 共享公开版本清单并合并并发请求。边缘清单缓存为 120／300 秒，附件按 ID 缓存 1 小时，支持 HEAD 和 Range，不将部分响应存为完整文件。`/health` 目前同样被边缘阻断；重新开放动态服务需要单独授权。

可选的 GitHub 只读令牌只保存在 Cloudflare 加密 Secret `GITHUB_TOKEN`，不放在源码、普通 vars 或前端。客户端仍需核对附件大小、摘要（如提供）、包名、版本、构建号和签名。

公开查询按 IP 每分钟最多 120 次，下载每分钟最多 30 次；超限返回 429 和 `Retry-After: 60`。限流不是身份验证，不能阻止所有分布式滥用。保留现有 WAF 规则，关闭 `workers.dev` 和版本预览入口。

域名使用 Cloudflare 官方 Anycast 调度，不写死地理位置不明的 IP。本机测速不能代表中国大陆所有运营商。

参考：[版本部署](https://developers.cloudflare.com/workers/versions-and-deployments/)、[自定义域名](https://developers.cloudflare.com/workers/configuration/routing/custom-domains/)、[Cache API](https://developers.cloudflare.com/workers/runtime-apis/cache/)。

## 维护静态项目页

文案在 `site/content.json`，结构和样式在同目录的 `template.html` 与 `site.css`。运行 `python3 tools/build_project_site.py`，输出至 `build/project-site`，仅包含两个语言页面、样式和明确列出的公开图片。

`.github/workflows/project-pages.yml` 将这一目录发布到 GitHub Pages，不上传整个源码仓库。默认英文，中文入口为 `zh.html`；页面无运行脚本、发行版查询或统计上报。修改静态页不会重新开放镜像或发行版。
