# MIAOW 遥控（iPhone / iPad）

在 iPhone、iPad 上遥控家里的 MIAOW 播放器（Windows 电脑上的 MIAOW播放器.exe）：浏览专辑墙、点歌、控制播放、看卡带库，也能改专辑资料、换封面、对照识别候选。
只在家里 Wi-Fi 上用，不配对。接口说明见播放器源码旁的 `遥控接口.md`。

## 播放器那边

设置 → 手机 / 平板遥控 → 勾上。那一行会写出地址（例如 `http://192.168.1.124:47880/`），在 App 里填一次。第一次打开时 Windows 防火墙会问，要点“允许”。

## 编译（没有 Mac）

这台 Windows 电脑编不了 iPhone App。代码推到 GitHub 后，`.github/workflows/ios.yml` 在 GitHub 的 Mac 机器上：

1. 用 XcodeGen 按 `project.yml` 生成工程，编译给模拟器；
2. 起一个假播放器（`mock/mock_server.py`，数据都是编的），在 iPhone、iPad 模拟器上打开 App 截图；
3. 编一个**没签名**的 `MIAOW-unsigned.ipa`。

截图和 ipa 在那次运行页面下面的 Artifacts 里。

## 装到手机

- **不花钱**：Windows 上装 Sideloadly（或 AltStore），用你自己的 Apple ID 给 `MIAOW-unsigned.ipa` 签名、通过数据线装上。iPhone 上要打开“开发者模式”，并在 设置 → 通用 → VPN 与设备管理 里信任。免费签名 7 天过期，过期要重签一次。
- **花 99 美元 / 年**（苹果开发者账号）：可以走 TestFlight，装一次能用 90 天、自动更新。要你自己注册账号，再把证书放进 GitHub 的仓库密钥，流程另加。

## 文件

| 路径 | 内容 |
|---|---|
| `MIAOWRemote/*.swift` | App（SwiftUI，iOS 16 起，iPhone + iPad） |
| `project.yml` | XcodeGen 工程描述 |
| `mock/mock_server.py` | 假播放器，云端截图用 |
| `tools/screenshots.sh` | 模拟器截图 |
| `tools/make_icon.ps1` | 画 App 图标（Windows 上跑） |
