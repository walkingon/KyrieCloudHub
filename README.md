# KyrieCloudHub

<div align="center">

<img src="assets/images/ic_launcher.png" alt="KyrieCloudHub Icon" width="128" />

[![Flutter](https://img.shields.io/badge/Flutter-3.10+-02569B?style=flat-square&logo=flutter)](https://flutter.dev)
[![License](https://img.shields.io/badge/License-Apache%202.0-green?style=flat-square)](LICENSE)
[![GitHub Stars](https://img.shields.io/github/stars/walkingon/KyrieCloudHub?style=flat-square)](https://github.com/walkingon/KyrieCloudHub/stargazers)

一款使用 Flutter 开发的跨平台云盘管理客户端，支持腾讯云 COS 和阿里云 OSS 对象存储服务。

</div>

## 📋 目录

- [简介](#简介)
- [功能特性](#功能特性)
- [技术栈](#技术栈)
- [安装指南](#安装指南)
- [使用说明](#使用说明)
- [项目结构](#项目结构)
- [贡献指南](#贡献指南)
- [开源协议](#开源协议)

## 简介

KyrieCloudHub 是一款跨平台云盘管理客户端，致力于为用户提供统一管理腾讯云 COS 和阿里云 OSS 对象存储服务的便捷体验。通过简洁直观的界面，您可以轻松管理云端文件，享受安全高效的云存储服务。

## 功能特性

### 🔐 账号管理
- 支持腾讯云、阿里云两大平台
- 使用访问密钥（SecretID + SecretKey）认证
- 自动保存/加载登录凭证
- 安全的登出功能

### 📁 存储桶管理
- 列出所有存储桶
- 支持列表/网格视图切换
- 存储桶浏览与导航

### 📄 文件管理
- 查看对象文件列表（支持分页）
- 文件夹导航（路径导航面包屑）
- 文件排序（名称、时间）
- 创建文件夹
- 上传文件（支持批量选择）
- 下载文件（支持分块下载）
- 打开本地文件
- 删除文件/文件夹
- 重命名文件/文件夹
- 复制/移动文件

### ⚡ 批量操作
- 批量下载
- 批量删除

### ⚙️ 设置功能
- 自定义下载目录
- 目录写入权限检查
- 重置为默认目录

## 技术栈

| 技术 | 说明 |
|------|------|
| **Flutter** | 跨平台 UI 框架 |
| **Dio** | HTTP 客户端 |
| **Provider** | 状态管理 |
| **Shared Preferences** | 本地数据持久化 |
| **file_picker** | 文件选择器 |
| **open_filex** | 文件打开 |

## 安装指南

### 环境要求

- Flutter SDK 3.10+
- Dart SDK ^3.10.1
- Android / Windows / Linux

### 安装步骤

1. 克隆项目：
   ```bash
   git clone https://github.com/walkingon/KyrieCloudHub.git
   cd KyrieCloudHub
   ```

2. 安装依赖：
   ```bash
   flutter pub get
   ```

3. 运行应用：
   ```bash
   flutter run
   ```

4. 构建发布版：
   ```bash
   # Windows
   flutter build windows

   # Android
   flutter build apk

   # Linux
   flutter build linux
   ```

## 使用说明

### 获取云平台凭证

#### 腾讯云 COS
1. 登录 [腾讯云控制台](https://console.cloud.tencent.com/)
2. 进入「访问管理」→「访问密钥」→「API 密钥管理」
3. 创建密钥，获取 SecretID 和 SecretKey

#### 阿里云 OSS
1. 登录 [阿里云控制台](https://home.console.aliyun.com/)
2. 进入「RAM 访问控制」→「用户管理」
3. 创建用户或使用已有用户，获取 AccessKey

### 快速开始

1. 启动应用后，选择登录平台（腾讯云/阿里云）
2. 输入 SecretID 和 SecretKey 进行登录
3. 登录成功后即可查看和管理存储桶
4. 在设置中配置下载目录

## 项目结构

```
kyrie_cloud_hub/
├── lib/
│   ├── main.dart              # 应用入口
│   ├── models/                # 数据模型层
│   │   ├── bucket.dart        # 存储桶模型
│   │   ├── object_file.dart   # 对象/文件模型
│   │   ├── platform_type.dart # 平台类型枚举
│   │   └── platform_credential.dart # 平台凭证模型
│   ├── screens/               # 界面层
│   │   ├── main_screen.dart           # 主界面
│   │   ├── bucket_objects_screen.dart # 对象文件列表
│   │   ├── platform_selection_screen.dart # 平台选择
│   │   ├── login_dialog.dart          # 登录对话框
│   │   ├── settings_screen.dart       # 设置界面
│   │   ├── about_screen.dart          # 关于界面
│   │   └── widgets/                   # 共享组件
│   ├── services/              # 服务层
│   │   ├── storage_service.dart        # 本地存储服务
│   │   ├── cloud_platform_factory.dart # 平台工厂
│   │   └── api/                        # API 实现
│   │       ├── cloud_platform_api.dart  # API 抽象接口
│   │       ├── tencent_cos_api.dart     # 腾讯云 COS 实现
│   │       ├── ali_yun_oss_api.dart     # 阿里云 OSS 实现
│   │       └── aliyun/                  # 阿里云签名/分块
│   │           └── tencent/             # 腾讯云签名/分块
│   └── utils/                 # 工具类
│       ├── logger.dart        # 日志系统
│       ├── file_path_helper.dart     # 文件路径辅助
│       ├── file_type_helper.dart     # 文件类型辅助
│       ├── file_chunk_reader.dart    # 文件分块读取
│       └── progress_dialog.dart      # 进度对话框
├── pubspec.yaml
├── analysis_options.yaml
└── README.md
```

## 贡献指南

欢迎提交 Issue 和 Pull Request！

1. Fork 本项目
2. 创建分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 开启 Pull Request

## 开源协议

本项目基于 Apache License 2.0 开源协议，详见 [LICENSE](LICENSE) 文件。

## 致谢

感谢所有为这个项目做出贡献的人！

---

<div align="center">

如果本项目对您有帮助，欢迎点亮 Star ⭐

</div>
