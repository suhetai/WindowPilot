# 签名与 macOS 权限

WindowPilot 需要辅助功能和屏幕录制权限。macOS 会验证应用的签名身份，因此仅保持相同的应用名或 Bundle ID，并不保证更新后能继续使用旧授权。

## 默认本地构建

```sh
bash build.sh
```

默认使用临时签名（ad-hoc）。适合一次性本地体验，但修改代码后重新构建可能需要移除旧权限项，再为新构建重新授权。

## 本地固定签名（推荐用于开发）

没有 Apple 开发者证书时，可创建一个仅存在于本机登录钥匙串的自签名身份：

```sh
bash scripts/create-local-signing-identity.sh   # 只需运行一次
bash install.sh                                  # 构建、替换 /Applications 中的应用并重新打开
```

`build.sh` 检测到 `WindowPilot Local Signing` 后会自动使用它，此后每次构建的签名要求都保持为 `identifier "dev.windowpilot.mac" and certificate leaf = H"…"`，重新编译不再需要重新授权。该身份不会被设置为系统信任，首次签名时如钥匙串询问，选择“始终允许”。切换到该身份后，需要最后一次移除旧权限项并重新授权。

## 使用固定签名身份

如果钥匙串中已有 Apple Development 或 Developer ID Application 证书，可指定身份名称或指纹：

```sh
security find-identity -v -p codesigning

WINDOWPILOT_SIGNING_IDENTITY="你的签名身份" bash build.sh
```

保持相同 Bundle ID、签名证书及安装位置。正式对外分发时，请使用适当的 Developer ID 签名并完成 Apple 公证；`build.sh` 不负责证书申请或公证。

也支持通过 `WINDOWPILOT_SIGNING_HELPER` 指定自有 Python 签名脚本。构建脚本会将生成的 `.app` 路径作为该脚本的第一个参数，并在签名后验证包完整性：

```sh
WINDOWPILOT_SIGNING_HELPER="/absolute/path/to/sign.py" bash build.sh
```

本地自签名身份可用于开发，仍需系统实际允许相应权限，不能替代 Apple 公证，也不应通过修改系统信任设置或关闭 TCC 来解决权限问题。

## 排查权限

- `AX -25211`：实际辅助功能调用被系统拒绝。
- ScreenCaptureKit `-3801`：实际屏幕捕获请求被系统拒绝。
- 系统设置中已打开开关但仍拒绝：确认授权的是当前安装版本，退出应用后移除旧项，再重新添加，并按系统提示重启应用。

不要把签名私钥、证书导出包、钥匙串、密码文件或本机签名脚本提交到仓库。仓库不包含任何开发者的签名凭据。

参考：[Apple DTS 关于临时签名与屏幕捕获权限的说明](https://developer.apple.com/forums/thread/819406)。
