# 把 MIAOW 遥控装到 iPhone / iPad（不用 Mac、不花钱）

安装包：`MIAOW-unsigned.ipa`（没签名）。苹果不让没签名的 App 直接装，要用你自己的 Apple ID 签一下。Windows 上用 Sideloadly 最省事。

## 一次性准备

1. 电脑上装 **Sideloadly**（sideloadly.io，免费）。它会提示装苹果的设备驱动（“Apple 设备”或 iTunes），照着装。
2. iPhone 用数据线连电脑，iPhone 上点“信任这台电脑”。

## 装

1. 打开 Sideloadly，把 `MIAOW-unsigned.ipa` 拖进去。
2. “Apple account” 填你的 Apple ID，点 Start，按提示输入密码（和两步验证码）。这一步是 Sideloadly 拿你的账号签名，密码只在你电脑上输入。
3. 装好后，iPhone 上：
   - **设置 → 隐私与安全性 → 开发者模式** 打开（iOS 16 起要），手机会重启一次；
   - **设置 → 通用 → VPN 与设备管理**，点你的 Apple ID，点“信任”。
4. 打开 MIAOW，填电脑上 设置 → 手机 / 平板遥控 那一行写的地址。

## 要知道的

- 免费的 Apple ID 签的 App **7 天后打不开**，再用 Sideloadly 装一遍就好（资料不丢）。Sideloadly 可以设成自动续签（电脑和手机在同一个 Wi-Fi、电脑开着时）。
- 免费账号同时最多装 3 个这样的 App。
- 想不折腾：注册苹果开发者账号（每年 99 美元），之后走 TestFlight，装一次 90 天、有新版自动提示。要的话告诉 Claude，云端编译那边再加签名这一步。

## 第一次连上时

- iPhone 会问“查找并连接本地网络上的设备”，点 **好**。点错了：设置 → 隐私与安全性 → 本地网络 → 打开 MIAOW。
- 电脑上 Windows 防火墙会弹窗，点 **允许**。
- 连不上先看：电脑上遥控勾上了没有、手机和电脑是不是同一个 Wi-Fi（不是访客网络）。
