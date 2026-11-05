# Security Policy / セキュリティ

## 対象のバージョン

| バージョン | 修正の対象 |
|---|---|
| 1.0.x | 対象 |
| 1.0 より前 | 対象外 |

## 脆弱性の報告

脆弱性は公開の Issue に書かず、GitHub の非公開の報告機能で知らせてほしい。

1. このリポジトリの **Security** タブを開く。
2. **Report a vulnerability** を押す。
3. 内容・再現手順・影響を書いて送る。

行動規範（[CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)）に関する報告も、同じ方法で受け付ける。

届いた報告は、できるだけ早く確認して返事をする。個人で開発しているので、返事に数日かかることがある。

> **English**: Please do not open a public issue for security vulnerabilities. Use GitHub's private vulnerability reporting instead (**Security** tab → **Report a vulnerability**).

## 注意

Atlas は、Modbus TCP と OPC-UA で PLC などの機器とつながる。v1.0 では、どちらも通信の暗号化と認証の設定に対応していない。

- Modbus TCP は、規格そのものに暗号化と認証が無い。
- OPC-UA は、暗号化なし・匿名の接続を優先して使う。証明書やユーザー名の設定はまだ無い。

信頼できるネットワークの中だけで使ってほしい。
