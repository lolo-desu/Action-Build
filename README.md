# ERP Stable

针对 https://erp.sex/ 的 WKWebView iOS 容器，最低 iOS 15，arm64 真机。

## 构建未签名 IPA

在安装完整 Xcode 的 Mac 上运行：

```sh
bash scripts/build-unsigned.sh
```

产物：`build/ERPStable-unsigned.ipa`。无需开发者账号或签名证书来构建。
普通 iPhone 安装时仍须通过自己的侧载工具签名；未签名 IPA 不能直接安装。

## 交互处理

- 禁用 WKWebView 双指缩放，并在页面及子框架注入固定 viewport，抑制双击和聚焦缩放。
- 编辑控件字号至少 16px，减少 iOS 输入时自动放大。
- 非输入区域禁用长按文本选择和系统弹出菜单；输入区保留选字、复制和粘贴。
- 清除 HTML autofocus 属性；不拦截网站 JavaScript 主动调用 focus()，避免破坏聊天和登录。
- DOM 更新后重新应用规则，保留普通点击、网页自身双击处理、滚动和滑动返回。
- 使用持久化网站存储保存登录状态，无自定义服务器、统计或登录信息转发。

## 验证状态与限制

交付环境是 Linux，没有 Xcode/iOS SDK，未执行 iOS 编译或真机验证，当前交付的是源码，不是 IPA。
网站内部的 CSS transform 缩放、JavaScript 焦点逻辑、Shadow DOM 或特殊编辑器可能需要针对实际页面继续适配。
未实现系统下载管理、上传权限配置及多窗口浏览器功能。

真机检查：登录；双击聊天区域；双指缩放；输入框弹出/收起键盘；长按普通文字；输入框选字与粘贴；刷新后登录保持；横竖屏；滑动返回。
