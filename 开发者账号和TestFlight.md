# 用付费开发者账号 + TestFlight 装 MIAOW 遥控

有了付费开发者账号（Apple Developer Program，99 美元 / 年，国区标价以付款页为准），云端编译完会自动签名、传到 TestFlight，手机上点"安装"就行：一次装好用 90 天，有新版 TestFlight 会提示。不用 Sideloadly、不用 7 天重签。

账号、付款、实名、密钥都是你自己操作；Claude 不碰。

## 一、注册（在 iPhone 上）

1. App Store 装 **Apple Developer**（苹果官方，蓝色图标）。
2. 打开 → 账户 → 用**你现有的 Apple ID** 登录（不用新开号；要开着双重认证）。
3. **立即注册（Enroll Now）** → 选**个人** → 填姓名、地址，拍证件实名。名字要和证件一致，以后 TestFlight 上显示的开发者名就是它。
4. 在 App 里付年费。
5. 等苹果审核，通过会发邮件（一般一两天）。

## 二、审核通过后，一次性设置（在电脑上，大约 15 分钟）

页面要你同意新协议时，自己看过再点同意。

### 1. 记下团队 ID

developer.apple.com/account → **会员资格详细信息**（Membership details）→ **团队 ID**，10 位字母数字。

### 2. 登记 App 的套装 ID（Bundle ID）

developer.apple.com/account/resources/identifiers → **+** → App IDs → App →

- 描述：`MIAOW Remote`
- Bundle ID：选 **Explicit**，填 `com.miaow.remote`
- 下面的功能都不用勾 → 注册

套装 ID 全苹果唯一，先到先得。提示已被占用就换一个，例如 `com.你的拼音.miaow`，并且第 5 步要多加一个变量 `BUNDLE_ID`。

### 3. 在 App Store Connect 里建 App

appstoreconnect.apple.com → **App** → **+** → 新建 App：

- 平台：iOS
- 名称：`MIAOW 遥控`（全 App Store 唯一，被占了就换个写法；只用 TestFlight 不上架也要有名字）
- 主要语言：简体中文
- 套装 ID：选第 2 步登记的那个
- SKU：`miaow-remote`（自己看的编号，随便填）
- 用户访问权限：完全访问

### 4. 生成 API 密钥（给云端编译签名、上传用）

App Store Connect → **用户和访问** → **集成** → **App Store Connect API** → 团队密钥 → **生成 API 密钥**（第一次可能要先点"请求访问"）：

- 名称：`GitHub`
- 访问：**管理**（Admin；云端要自动建发布证书，低一级的权限不够）

生成后：

- **下载 .p8 文件 —— 只能下载一次。** 备份到 Drive `我的云端硬盘\密钥备份\`（不共享），**不要放进项目文件夹、不要发给任何人、不要传到 GitHub 仓库里**。
- 记下这把密钥的 **密钥 ID**，和页面上方的 **Issuer ID（签发者 ID）**。

### 5. 把密钥放进 GitHub（只放 Secrets，仓库是公开的，代码里不能有）

github.com/lixueling-bot/miaow-remote-ios → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**，建 4 个：

| 名字 | 填什么 |
|---|---|
| `ASC_KEY_ID` | 第 4 步的密钥 ID |
| `ASC_ISSUER_ID` | 第 4 步的 Issuer ID |
| `ASC_KEY_P8` | 用记事本打开 .p8，**全部**复制粘贴（含 `-----BEGIN PRIVATE KEY-----` 和 `-----END PRIVATE KEY-----` 两行） |
| `APPLE_TEAM_ID` | 第 1 步的团队 ID |

第 2 步换了套装 ID 的：同一页切到 **Variables** 标签 → New repository variable，名字 `BUNDLE_ID`，值填你登记的那个。

Secrets 放进去以后谁都看不到内容（包括你自己），编译日志里也会被遮住。

### 6. 告诉 Claude

Claude 重跑一次云端编译，最后一步会签名并上传。苹果处理 5~30 分钟。

### 7. 把自己加进内部测试

App Store Connect → 这个 App → **TestFlight** → 内部测试 旁边 **+** → 建一个组（例如"自己"）→ 把你自己的账号加进去。内部测试不用等苹果的测试审核。

## 三、手机上装

1. App Store 装 **TestFlight**（苹果官方）。
2. 用同一个 Apple ID 登录，里面会出现 **MIAOW** → 安装。
3. 第一次打开时问"查找本地网络上的设备"，点 **好**。
4. 电脑上 MIAOW 播放器：设置 → 手机 / 平板遥控 → 勾上，把那一行写的地址填进 App。Windows 防火墙弹窗，点 **允许**。

以后每次推新代码，云端自动传一版，TestFlight 会提示更新。

## 出问题时看哪里

GitHub 仓库 → Actions → 那次运行 → **testflight** → 失败的那一步。日志也在那次运行最下面的 `testflight-logs` 里。常见的：

- `No profiles` / `No signing certificate`：API 密钥权限不是"管理"，或者没同意新协议。
- `No suitable application records`：第 3 步没建 App，或者套装 ID 对不上。
- `bundle version must be higher`：编号重复了，再跑一次就好（编号用的是运行次数）。
