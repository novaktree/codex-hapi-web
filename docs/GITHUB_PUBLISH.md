# GitHub 发布说明

这份仓库已经按“可公开发布”整理过，但在真正推送前，仍建议按下面流程再检查一遍。

## 发布目录

建议只发布当前项目目录本身，不要把外层工作区一起推上去。

进入仓库目录后执行下面命令：

```powershell
cd <repo-root>
```

其中 `<repo-root>` 就是本项目根目录，也就是包含 `backend/`、`frontend/`、`scripts/`、`README.md` 的那个目录。

## 推荐流程

### 1. 配置 Git 身份

如果这台电脑还没配过 Git 身份：

```powershell
git config --global user.name "your-github-name"
git config --global user.email "your-email@example.com"
```

### 2. 在 GitHub 创建空仓库

建议：

- 仓库名：`codex-hapi-web`
- 可见性：按需选择 `Public` 或 `Private`
- 不要勾选自动生成 `README`、`.gitignore`、`LICENSE`

### 3. 初始化独立仓库

在项目根目录运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\init-standalone-git.ps1
```

如果你想顺手把 Git 身份也写进当前仓库：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\init-standalone-git.ps1 `
  -GitUserName "your-github-name" `
  -GitUserEmail "your-email@example.com"
```

### 4. 绑定远端

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\init-standalone-git.ps1 `
  -RemoteUrl https://github.com/<your-name>/codex-hapi-web.git
```

### 5. 推送到 GitHub

```powershell
git push -u origin main
```

## 一步完成

如果 GitHub 空仓库已经建好，也可以直接执行：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\init-standalone-git.ps1 `
  -GitUserName "your-github-name" `
  -GitUserEmail "your-email@example.com" `
  -RemoteUrl https://github.com/<your-name>/codex-hapi-web.git `
  -Push
```

## 手动命令版

如果你不想用脚本，也可以手动执行：

```powershell
git init -b main
git add .
git commit -m "Initial public release"
git remote add origin https://github.com/<your-name>/codex-hapi-web.git
git push -u origin main
```

## 默认不会进入公开仓库的内容

这些内容已经在 `.gitignore` 中忽略：

- `.runtime/`
- `logs/`
- `uploads/`
- `.env`
- `frontend/node_modules/`
- `frontend/dist/`
- Python 缓存目录

## 发布前自检

建议在推送前确认：

1. `README.md` 没有写死你的本机用户名、绝对路径、局域网地址或隧道地址。
2. `.env.example` 只保留配置项模板，不包含真实密钥。
3. `.runtime/`、日志、上传文件、测试产物没有被提交。
4. 桌面刷新脚本没有依赖你个人电脑专属的硬编码线程标题或固定窗口顺序。
5. 文档中的示例地址都使用占位符，而不是你真实的部署地址。
