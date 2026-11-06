# 版本与发布

## 唯一版本来源

`Version.json` 声明 `version`、递增整数 `build` 和 `minimumMacOS`。构建时生成 Info.plist，填入语义版本、Apple 三段产品版本、构建号、Git 修订和构建类型；不手工维护另一组版本号。工作区有已跟踪的未提交修改时，修订显示 `-dirty`；源码归档无 Git 元数据时显示 `source`。

```bash
python3 scripts/version.py show
python3 scripts/version.py bump patch
python3 scripts/version.py bump build
python3 scripts/version.py set 0.3.0-rc.1 16
```

每次只执行需要的一条变更命令。`set` 必须递增构建号；版本遵循 SemVer。应用比较语义版本与构建号，不按字符串或发布时间排序。正式通道排除 GitHub 预发布标记及语义预发布版本；预览通道同时显示二者。历史页面可以阅读旧版说明，但不自动降级。

## 开发验证

```bash
python3 scripts/version.py check
python3 -m unittest discover -s Tests/Scripts
swift test
bash build-app.sh --unsigned
```

`--unsigned` 是无开发者证书的审查构建，不能作为自动更新安装包。实际安装与更新要使用自己的同一固定签名身份。GitHub CI 不需要或保存开发者证书私钥。

## 生成安装包

先完成审查并提交源码，在对应提交上创建与产品版本相符的标签，再用本机固定证书打包：

```bash
git tag -a v0.2.0 -m 'MacAuthAssistant 0.2.0'
bash scripts/package-release.sh
```

打包器要求源码干净、标签与版本一致，产出 `MacAuthAssistant-<version>-b<build>-<architecture>.zip` 及 `SHA256SUMS`；包内只有应用，不打包源码根目录、钥匙串、`.local`、本机签名配置或 Application Support。不同架构应在对应 Mac 构建；没有对应包时界面明确提示，不误装另一架构。

向本仓库的 GitHub Release 上传 ZIP 与校验文件后，GitHub 为附件提供 `sha256:` digest，客户端据此验包。Release 必须非草稿；预览版同时标记 prerelease。发行说明来自 CHANGELOG，对应标签必须与应用版本一致。客户端只接受固定仓库的 HTTPS 下载 URL 和明确命名的包；源代码 ZIP 不作为安装包。

```bash
git push origin main
git push origin v0.2.0
gh release create v0.2.0 dist/MacAuthAssistant-0.2.0-b14-arm64.zip dist/SHA256SUMS --repo baihua666/mac-auth-assistant --title 'MacAuthAssistant 0.2.0' --notes-file release-notes.md
```

以上是维护者按实际版本执行的例子，发行说明文件须由维护者准备。创建 Release 是独立的发布动作，CI 只测试和构建，不自动公开个人签名的二进制。未做 Developer ID 公证时须在发行说明中明确标注，签名构建不冒充公证通过。

## 更新流程

从菜单或设置页打开“版本与更新…”。后台启动不弹设置或更新窗口。自动检查开启时，每天最多访问一次公开 GitHub 发行 API，不携带 GitHub token、凭据、历史、黑名单或机器标识；下载与安装都由用户点击发起。

下载可取消。检查失败、请求受限、无发行、无本机可验证安装包分别显示；网络失败不能显示“已是最新”。手动检查可重新查看跳过的版本，后台提醒尊重跳过选择。最多读取最近 30 条 GitHub Release；长期归档可从发行页查看。

安装前核对 ZIP 大小/SHA-256、目录路径与链接、展开大小、应用标识、可执行文件、语义版本/构建号、最低系统版本，并验证新版满足当前应用的签名身份要求。没有稳定签名的审查版、不同签名、磁盘映像内运行或目录不可写时停止，不申请 root 或绕过系统策略。

用户确认“安装并重启”后，等待主进程退出，以同目录 rename 整体替换应用；替换前后重新核对签名。保留旧包在应用同目录 `.MacAuthAssistant-update-…/previous.app`，失败时尝试恢复并重新打开旧版。无法退出、无法替换或无法恢复时保留本地材料，不删除用户数据。下一次启动显示安装结果。

应用包之外的钥匙串、偏好、历史和黑名单保留。当前签名的指定要求不变时可保持原授权，但证书换身份仍可能需要本人重新授权。GitHub 本身及签名身份构成更新信任来源；SHA-256 不替代签名验证。

## 验证边界

自动回归覆盖语义比较、通道/跳过、架构与 URL/digest 过滤、空发行/HTTP 错误、下载校验、取消、元数据不符、目录穿越/链接及无签名拒绝。独立的已签名临时探针验证过整体替换、旧包保留、重新启动和篡改签名拒绝，未操作系统认证 UI。完整的生产更新仍应以实际发布附件、当前安装与新版本的端到端结果核对。
