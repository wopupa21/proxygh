# ProxyGH

在自己的 Debian 服务器上，用 Nginx 为少量可信用户提供 GitHub 公共资源加速。适合服务器位于日本、香港、新加坡等地，而客户端位于中国大陆的场景。

本项目不使用 Cloudflare，不改写 GitHub 网页，也不是任意 URL 代理。所有请求只能去往配置中写死的 GitHub 官方上游。

## Demo

公共 Demo 地址：<https://ghp.825915.xyz>

这个地址只用于展示站点入口和 TLS 是否可达，不公开任何 ProxyGH 用户名或密码；代理资源请求仍需要认证。部署自己的实例时，请把下面命令中的 `YOUR_PROXY_USER` 替换成你在服务器上通过 `scripts/add-user.sh` 自己创建的用户名。`YOUR_PROXY_USER` 不是本项目固定账号，也不是 GitHub 用户名。

## 支持范围

| 地址前缀 | 用途 | 固定上游 |
| --- | --- | --- |
| `/git/` | 公共仓库 `clone`、`fetch`、`pull` | `github.com` |
| `/raw/` | Raw 文件 | `raw.githubusercontent.com` |
| `/archive/` | ZIP、tar.gz 源码包 | `codeload.github.com` |
| `/release/` | Release 附件 | `github.com`、`release-assets.githubusercontent.com` |

不支持 GitHub 网页、登录、私有仓库、`git push`、Git LFS、GitHub API、Packages 和 GHCR。

## 工作方式

假设你的代理域名是 `gh.example.com`：

```text
https://gh.example.com/git/OWNER/REPOSITORY.git
https://gh.example.com/raw/OWNER/REPOSITORY/REF/path/to/file
https://gh.example.com/archive/OWNER/REPOSITORY/zip/REF
https://gh.example.com/release/OWNER/REPOSITORY/releases/download/TAG/FILE
```

四类入口共用一个域名和一套 Basic Auth。Release 的 GitHub 302 跳转只允许改写到官方 `release-assets.githubusercontent.com`，然后回到同一代理域名继续下载。客户端不能通过参数指定目标主机。

响应不缓存，Nginx 关闭代理缓冲和代理临时文件，大文件会直接流式转发。每次请求仍会消耗服务器流量。

## 安全设计

- 所有代理路径均要求 Basic Auth，建议每个人单独一个账号。
- 代理认证使用的 `Authorization`、`Proxy-Authorization` 和 Cookie 不会发送给 GitHub。
- Git 路径只允许 `GET`、`HEAD`、`POST`，并明确拒绝 `git-receive-pack`；其他下载路径只允许 `GET`、`HEAD`。
- 每个客户端 IP 最多 4 个并发连接，请求速率默认为每秒 10 个，允许短时突发 30 个。
- 上游 TLS 证书会使用 Debian CA 证书包验证，并发送正确的 Host 和 SNI。
- 访问日志不记录查询字符串，避免 Release 签名参数进入日志。
- 没有通用 URL 参数、动态上游、HTML 替换、CORS 放宽或 CSP 删除。

Basic Auth 只能控制谁可以使用你的代理，并不等同于 GitHub 账号授权。当前项目只代理公开资源。

## 准备工作

### 1. 检查 Debian 和 Nginx

项目面向 Debian 11/12，其他 Debian 系版本通常也能运行，但应自行验证。

```bash
cat /etc/os-release
nginx -v
sudo nginx -t
```

### 2. 配置 DNS

给代理域名添加一条直连服务器的 `A` 记录。如果服务器正确配置了 IPv6，再添加 `AAAA`。

```text
gh.example.com  A  你的日本服务器 IPv4
```

不要开启 Cloudflare 橙色云代理。等待解析后检查：

```bash
getent ahosts gh.example.com
```

### 3. 开放端口

云服务商安全组和服务器防火墙都需要允许 TCP 80、443。80 用于 HTTP 跳转和 Let's Encrypt HTTP-01 验证，443 用于实际代理。

如果使用 UFW：

```bash
sudo ufw allow 'Nginx Full'
sudo ufw status
```

### 4. 检查服务器到 GitHub 的连接

```bash
curl -I --connect-timeout 10 https://github.com/
curl -I --connect-timeout 10 https://raw.githubusercontent.com/octocat/Hello-World/master/README
curl -I --connect-timeout 10 https://codeload.github.com/octocat/Hello-World/zip/master
curl -I --connect-timeout 10 https://release-assets.githubusercontent.com/
```

最后一条返回 404 或 403 并不代表网络失败；关键是 DNS、TLS 和 HTTP 连接能够建立。

## 获取项目

```bash
sudo apt-get update
sudo apt-get install -y git
git clone https://github.com/wopupa21/proxygh.git
cd proxygh
```

## HTTPS 证书

选择下面其中一种方式。

### 方式一：使用已有通配符证书

假设证书覆盖 `*.example.com`，把证书与私钥放在只有 root 可修改的位置，例如：

```text
/etc/ssl/proxygh/fullchain.pem
/etc/ssl/proxygh/privkey.pem
```

推荐权限：

```bash
sudo chown -R root:root /etc/ssl/proxygh
sudo chmod 700 /etc/ssl/proxygh
sudo chmod 600 /etc/ssl/proxygh/privkey.pem
sudo chmod 644 /etc/ssl/proxygh/fullchain.pem
```

如果证书由其他程序自动更新，让该程序续签成功后执行：

```bash
sudo nginx -t && sudo systemctl reload nginx
```

### 方式二：申请单域名 Let's Encrypt 证书

确认域名已经直连服务器、80 端口可从公网访问，并且没有其他 Nginx 配置占用相同 `server_name`。然后运行：

```bash
sudo ./scripts/request-certificate.sh \
  --domain gh.example.com \
  --email admin@example.com
```

脚本使用 HTTP-01 Webroot 验证，证书路径为：

```text
/etc/letsencrypt/live/gh.example.com/fullchain.pem
/etc/letsencrypt/live/gh.example.com/privkey.pem
```

它还会安装一个续签成功后的 Nginx 检查与 reload hook。确认系统定时器并执行演练：

```bash
systemctl status certbot.timer --no-pager
sudo certbot renew --dry-run
```

### 关于 Let's Encrypt 通配符证书

通配符证书只能通过 DNS-01 申请。要自动续签，必须安装与你的 DNS 服务商匹配的 Certbot DNS 插件，并使用权限最小化的 DNS API 凭据。具体插件命令因 DNS 服务商不同，本项目不会让你把 DNS Token 写入仓库。

手动添加 DNS TXT 记录签发的证书，默认不能无人值守续签。

## 安装 ProxyGH

使用现有通配符证书：

```bash
sudo ./scripts/install.sh \
  --domain gh.example.com \
  --certificate /etc/ssl/proxygh/fullchain.pem \
  --certificate-key /etc/ssl/proxygh/privkey.pem
```

使用前面申请的 Let's Encrypt 单域名证书：

```bash
sudo ./scripts/install.sh \
  --domain gh.example.com \
  --certificate /etc/letsencrypt/live/gh.example.com/fullchain.pem \
  --certificate-key /etc/letsencrypt/live/gh.example.com/privkey.pem
```

安装器会：

1. 安装 `apache2-utils`、CA 证书、curl 和 Git。
2. 写入 Nginx 限流、公共代理参数和站点配置。
3. 保留已有的 `/etc/nginx/proxygh.htpasswd`。
4. 对被替换的同名配置创建带 UTC 时间戳的备份。
5. 先运行 `nginx -t`，成功后才 reload；失败时恢复本次写入前的配置。

安装后先创建账号，否则所有代理请求都会返回 401：

```bash
sudo ./scripts/add-user.sh your_proxy_user
sudo ./scripts/add-user.sh friend-a
```

脚本会交互式要求输入密码，密码不会出现在命令行参数中。账号文件使用 bcrypt 哈希并保存为 `/etc/nginx/proxygh.htpasswd`。再次使用同一用户名会更新密码。

删除账号：

```bash
sudo htpasswd -D /etc/nginx/proxygh.htpasswd friend-a
```

## 使用方法

以下示例仍假设代理域名为 `gh.example.com`。首次请求时输入 ProxyGH 用户名和密码，不是 GitHub 密码或 Token。

> 说明：本文中的 `YOUR_PROXY_USER` 是占位符，必须替换成你自己运行 `sudo ./scripts/add-user.sh 用户名` 创建的 ProxyGH 用户名。请不要照抄这个占位符，也不要把服务器 Linux 用户名或 GitHub 用户名当成 ProxyGH 用户名；密码不会在仓库中公布。

### Git clone、fetch、pull

```bash
git clone https://gh.example.com/git/OWNER/REPOSITORY.git
```

现有仓库切换到代理：

```bash
git remote set-url origin https://gh.example.com/git/OWNER/REPOSITORY.git
git fetch origin
```

恢复 GitHub 原地址：

```bash
git remote set-url origin https://github.com/OWNER/REPOSITORY.git
```

可以使用 Git 自己的 credential helper 保存代理凭据。Linux 上不要在多人共用机器使用明文 `store`；优先使用系统密钥环支持的 helper。查看当前配置：

```bash
git config --global --get credential.helper
```

如果希望所有 GitHub HTTPS clone 自动改走代理：

```bash
git config --global url."https://gh.example.com/git/".insteadOf "https://github.com/"
```

撤销：

```bash
git config --global --unset-all url."https://gh.example.com/git/".insteadOf
```

该全局改写可能影响依赖工具和子模块，建议先在少量设备测试。

### Raw 文件

原地址：

```text
https://raw.githubusercontent.com/OWNER/REPOSITORY/REF/path/to/file
```

代理地址：

```bash
curl --user 'YOUR_PROXY_USER' \
  'https://gh.example.com/raw/OWNER/REPOSITORY/REF/path/to/file'
```

不建议写成 `https://用户名:密码@域名/...`，这种 URL 容易进入 Shell 历史、日志和 Git 配置。

### curl / wget 认证

`curl` 可以只提供用户名，让它交互式询问密码。`-L` 用于跟随 Release 的重定向：

```bash
curl -L -u YOUR_PROXY_USER \
  -o file.zip \
  'https://gh.example.com/release/OWNER/REPOSITORY/releases/download/TAG/FILE'
```

Raw 文件示例：

```bash
curl -u YOUR_PROXY_USER \
  'https://gh.example.com/raw/OWNER/REPOSITORY/BRANCH/path/file' \
  -o file
```

`wget` 可以使用一次性命令，但密码会出现在命令行参数中，不适合共享服务器：

```bash
wget --user=YOUR_PROXY_USER --password='明文密码' \
  -O file.zip \
  'https://gh.example.com/release/OWNER/REPOSITORY/releases/download/TAG/FILE'
```

更适合长期使用的是权限为 600 的 `.netrc`：

```bash
cat > ~/.netrc <<'EOF'
machine gh.example.com
login YOUR_PROXY_USER
password 你的ProxyGH密码
EOF

chmod 600 ~/.netrc
wget -O file.zip \
  'https://gh.example.com/release/OWNER/REPOSITORY/releases/download/TAG/FILE'
```

`.netrc` 以明文保存密码，只允许当前用户读取；不再使用时删除：

```bash
rm -f ~/.netrc
```

PowerShell 中使用 `curl.exe`，不要使用 PowerShell 的 `curl` 别名：

```powershell
curl.exe -L -u YOUR_PROXY_USER -o file.zip "https://gh.example.com/release/OWNER/REPOSITORY/releases/download/TAG/FILE"
```

不要使用 `curl -u YOUR_PROXY_USER:密码` 或 `https://用户名:密码@域名/...`，否则密码可能进入 Shell 历史、进程列表、日志或 Git 配置。

### 源码包

```bash
curl --fail --location --user 'YOUR_PROXY_USER' \
  --output source.zip \
  'https://gh.example.com/archive/OWNER/REPOSITORY/zip/REF'

curl --fail --location --user 'YOUR_PROXY_USER' \
  --output source.tar.gz \
  'https://gh.example.com/archive/OWNER/REPOSITORY/tar.gz/REF'
```

### Release 附件

把原始 GitHub 地址中的域名替换为代理域名，并在路径前增加 `/release`：

```text
原始：https://github.com/OWNER/REPOSITORY/releases/download/TAG/FILE
代理：https://gh.example.com/release/OWNER/REPOSITORY/releases/download/TAG/FILE
```

下载示例：

```bash
curl --fail --location --user 'YOUR_PROXY_USER' \
  --continue-at - \
  --output FILE \
  'https://gh.example.com/release/OWNER/REPOSITORY/releases/download/TAG/FILE'
```

`--continue-at -` 会在服务器支持 Range 时尝试断点续传。

## 部署后验证

先检查 Nginx：

```bash
sudo nginx -t
sudo systemctl status nginx --no-pager
```

执行项目自带的交互式冒烟测试：

```bash
./scripts/smoke-test.sh --domain gh.example.com --user YOUR_PROXY_USER
```

它会验证：

- 未认证请求返回 401。
- Raw 文件可用。
- 源码包可用。
- Release 及其同域重定向可用。
- 单字节 Range 请求返回 206。
- `git ls-remote` 可以读取公开仓库。

脚本只会把密码放在当前进程环境和临时 `GIT_ASKPASS` 中，退出时删除临时文件。

## 日志和排错

```bash
sudo tail -f /var/log/nginx/proxygh-access.log
sudo tail -f /var/log/nginx/proxygh-error.log
journalctl -u nginx --since '30 minutes ago' --no-pager
```

常见问题：

### 返回 401

确认已经创建账号，客户端使用的是 ProxyGH 账号：

```bash
sudo htpasswd -v /etc/nginx/proxygh.htpasswd USERNAME
```

### 返回 403

`git push` 和 `git-receive-pack` 是设计上明确禁止的。下载路径使用了非 GET/HEAD 方法也会被拒绝。

### 返回 429

同一公网 IP 的请求过快或并发下载超过 4 个。家庭或办公室多人共用一个出口时，可按服务器带宽谨慎调整 `nginx/proxygh-zones.conf` 和模板中的 `limit_conn`，然后重新安装并验证。

### 502、504 或 TLS 错误

从服务器直接测试对应上游，检查 DNS、系统时间和 CA 包：

```bash
timedatectl status
sudo update-ca-certificates
curl -Iv https://github.com/
curl -Iv https://raw.githubusercontent.com/
curl -Iv https://codeload.github.com/
```

### Release 下载突然失效

GitHub 可能调整资源分发域名。本项目不会自动接受新重定向域名。先查看响应头和 Nginx 错误日志，确认新域名确属 GitHub 官方文档列出的固定域名，再通过代码审查更新白名单。不要把重定向目标直接做成动态 `proxy_pass`。

### Git 子模块没有走代理

子模块保存自己的 URL。使用前面的全局 `insteadOf`，或者逐个修改 `.gitmodules`，并执行：

```bash
git submodule sync --recursive
```

## 更新

在仓库目录中：

```bash
git pull --ff-only
python3 -m unittest discover -s tests -v
sudo ./scripts/install.sh \
  --domain gh.example.com \
  --certificate /你的/fullchain.pem \
  --certificate-key /你的/privkey.pem
./scripts/smoke-test.sh --domain gh.example.com --user YOUR_PROXY_USER
```

安装器不会覆盖 htpasswd 用户文件。

## 回滚和卸载

安装器替换同名 Nginx 文件时，会把备份放在不被 Nginx 自动加载的目录，类似下面：

```text
/etc/nginx/proxygh-backups/proxygh.conf.proxygh-backup-20260731T120000Z
```

手工恢复前，先列出并确认准确文件名。恢复后必须执行 `sudo nginx -t`，成功后再 reload。

完全停用站点：

```bash
sudo rm /etc/nginx/sites-enabled/proxygh.conf
sudo nginx -t
sudo systemctl reload nginx
```

确认不再需要后，可以删除项目管理的配置：

```bash
sudo rm /etc/nginx/sites-available/proxygh.conf
sudo rm /etc/nginx/snippets/proxygh-common.conf
sudo rm /etc/nginx/conf.d/proxygh-zones.conf
sudo rm /etc/nginx/proxygh.htpasswd
sudo nginx -t
sudo systemctl reload nginx
```

上述操作不可恢复账号文件，执行前可先备份。不要删除共享证书；同一证书可能还被其他站点使用。

## 本地测试

策略和脚本契约测试：

```bash
python3 -m unittest discover -s tests -v
bash -n scripts/*.sh
shellcheck scripts/*.sh
```

CI 还会安装真实 Nginx、渲染临时证书路径并运行 `nginx -t`。

## 局限与提醒

- 速度取决于中国大陆到日本、日本到 GitHub 两段网络以及服务器带宽。
- 本项目不缓存，每次访问都会产生服务器出口流量。
- Basic Auth 账号应只发给可信的人，并定期查看日志和流量账单。
- Release 附件最大可能很大；GitHub 当前允许单个 Release asset 小于 2 GiB，服务器应有足够带宽配额。
- 项目不帮助规避 GitHub 的权限控制，也不提供私有资源访问。
- 使用前应确认服务器提供商、域名注册商和所在地法律政策允许此用途。

## 参考资料

- [Nginx proxy module](https://nginx.org/en/docs/http/ngx_http_proxy_module.html)
- [GitHub: Cloning a repository](https://docs.github.com/en/repositories/creating-and-managing-repositories/cloning-a-repository)
- [GitHub: Downloading source code archives](https://docs.github.com/en/repositories/working-with-files/using-files/downloading-source-code-archives)
- [GitHub: Linking to releases](https://docs.github.com/en/repositories/releasing-projects-on-github/linking-to-releases)
- [GitHub: Self-hosted runners reference](https://docs.github.com/en/actions/reference/runners/self-hosted-runners)
- [Certbot user guide](https://eff-certbot.readthedocs.io/en/stable/using.html)

## License

[MIT](LICENSE)
