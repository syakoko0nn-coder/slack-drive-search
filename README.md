# Slack × Google Drive 検索ボット セットアップ手順

## 必要な環境変数

```env
SLACK_BOT_TOKEN=xoxb-...
SLACK_SIGNING_SECRET=...
SLACK_APP_TOKEN=xapp-...          # Socket Mode用
ANTHROPIC_API_KEY=sk-ant-...
GOOGLE_SERVICE_ACCOUNT_JSON={"type":"service_account",...}  # JSONを1行に圧縮
```

## 必要なパッケージ

```bash
npm init -y
npm install @slack/bolt @anthropic-ai/sdk googleapis
```

## Slack App 設定（api.slack.com）

1. **Global Shortcuts** を追加
   - Callback ID: `search_drive`
   - 名前: 「Drive を検索」

2. **Socket Mode** を有効化（App-Level Token が必要）

3. **Bot Token Scopes** に以下を追加
   - `chat:write`
   - `im:write`（DMで結果を返すため）

## Google サービスアカウント設定

1. Google Cloud Console でサービスアカウントを作成
2. Drive API を有効化
3. JSONキーをダウンロード → `GOOGLE_SERVICE_ACCOUNT_JSON` に設定
4. 検索対象のGoogle DriveフォルダをサービスアカウントのメールアドレスにShare

> **Shared Drive（組織全体）を横断する場合**
> `driveSearch.js` の `files.list` に以下を追加し、
> Google Workspace 管理コンソールで Domain-wide Delegation を設定する必要があります：
> ```js
> includeItemsFromAllDrives: true,
> supportsAllDrives: true,
> corpora: "allDrives",
> ```

## 起動

```bash
node app.js
```

## 使い方（スマホのSlackから）

1. Slack のグローバルショートカット（⚡アイコン）を開く
2. 「Drive を検索」を選択
3. キーワードとファイルタイプを入力して送信
4. DMに結果が届く

## コスト目安

| 項目 | 単価 | 月1,000件想定 |
|------|------|---------------|
| Claude API (Sonnet) | 入力$3/MTok, 出力$15/MTok | ¥400〜700 |
| Google Drive API | 無償枠内 | ¥0 |
| Slack API | 無償 | ¥0 |
