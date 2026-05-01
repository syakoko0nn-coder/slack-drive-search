// app.js
const { App } = require("@slack/bolt");
const { searchDrive } = require("./driveSearch");
const { summarizeWithClaude } = require("./claudeSummarize");

const app = new App({
  token: process.env.SLACK_BOT_TOKEN,
  signingSecret: process.env.SLACK_SIGNING_SECRET,
  socketMode: true, // スマホからも安定して動作
  appToken: process.env.SLACK_APP_TOKEN,
});

// ─── Global Shortcut → モーダル表示 ───────────────────────────────────────────
app.shortcut("search_drive", async ({ shortcut, ack, client }) => {
  await ack(); // 3秒以内に必ずACK

  await client.views.open({
    trigger_id: shortcut.trigger_id,
    view: {
      type: "modal",
      callback_id: "drive_search_modal",
      title: { type: "plain_text", text: "📁 Drive 検索" },
      submit: { type: "plain_text", text: "検索する" },
      close: { type: "plain_text", text: "閉じる" },
      blocks: [
        {
          type: "input",
          block_id: "keyword_block",
          label: { type: "plain_text", text: "キーワード" },
          element: {
            type: "plain_text_input",
            action_id: "keyword_input",
            placeholder: { type: "plain_text", text: "例：Q1レポート、採用方針..." },
          },
        },
        {
          type: "input",
          block_id: "filetype_block",
          label: { type: "plain_text", text: "ファイルタイプ（任意）" },
          optional: true,
          element: {
            type: "static_select",
            action_id: "filetype_input",
            placeholder: { type: "plain_text", text: "すべて" },
            options: [
              { text: { type: "plain_text", text: "すべて" }, value: "all" },
              { text: { type: "plain_text", text: "Google Docs" }, value: "document" },
              { text: { type: "plain_text", text: "Google Sheets" }, value: "spreadsheet" },
              { text: { type: "plain_text", text: "PDF" }, value: "pdf" },
            ],
          },
        },
        {
          type: "input",
          block_id: "maxresults_block",
          label: { type: "plain_text", text: "最大件数" },
          optional: true,
          element: {
            type: "static_select",
            action_id: "maxresults_input",
            placeholder: { type: "plain_text", text: "3件" },
            options: [
              { text: { type: "plain_text", text: "3件" }, value: "3" },
              { text: { type: "plain_text", text: "5件" }, value: "5" },
              { text: { type: "plain_text", text: "10件" }, value: "10" },
            ],
          },
        },
      ],
    },
  });
});

// ─── モーダル送信 → 即座にDM通知 → 非同期で処理 ────────────────────────────────
app.view("drive_search_modal", async ({ ack, body, view, client }) => {
  await ack(); // モーダルを即閉じる（3秒ルール対応）

  const userId = body.user.id;
  const values = view.state.values;
  const keyword = values.keyword_block.keyword_input.value;
  const filetype = values.filetype_block.filetype_input?.selected_option?.value ?? "all";
  const maxResults = parseInt(values.maxresults_block.maxresults_input?.selected_option?.value ?? "3");

  // 「検索中」をすぐDMで通知
  await client.chat.postMessage({
    channel: userId,
    text: `🔍 *「${keyword}」* を検索中です。少々お待ちください...`,
  });

  // 非同期で重い処理を実行（Slackタイムアウトを回避）
  processSearchAsync({ client, userId, keyword, filetype, maxResults });
});

// ─── 非同期検索処理本体 ────────────────────────────────────────────────────────
async function processSearchAsync({ client, userId, keyword, filetype, maxResults }) {
  try {
    // 1. Google Drive APIで検索
    const files = await searchDrive({ keyword, filetype, maxResults });

    if (files.length === 0) {
      await client.chat.postMessage({
        channel: userId,
        text: `😔 *「${keyword}」* に一致するファイルは見つかりませんでした。`,
      });
      return;
    }

    // 2. 各ファイルをClaude APIで要約 → Block Kit形式で送信
    const blocks = await buildResultBlocks({ keyword, files });

    await client.chat.postMessage({
      channel: userId,
      text: `📁 「${keyword}」の検索結果 ${files.length}件`, // 通知テキスト（モバイル通知用）
      blocks,
    });
  } catch (err) {
    console.error("Search error:", err);
    await client.chat.postMessage({
      channel: userId,
      text: `⚠️ 検索中にエラーが発生しました: ${err.message}`,
    });
  }
}

// ─── Block Kit リッチメッセージ生成 ───────────────────────────────────────────
async function buildResultBlocks({ keyword, files }) {
  const blocks = [
    {
      type: "header",
      text: { type: "plain_text", text: `📁 「${keyword}」の検索結果 ${files.length}件` },
    },
    { type: "divider" },
  ];

  for (const file of files) {
    // Claude APIで要約
    const summary = await summarizeWithClaude({ keyword, file });

    const fileTypeEmoji = {
      "application/vnd.google-apps.document": "📝",
      "application/vnd.google-apps.spreadsheet": "📊",
      "application/pdf": "📄",
    }[file.mimeType] ?? "📁";

    blocks.push(
      {
        type: "section",
        text: {
          type: "mrkdwn",
          text: `${fileTypeEmoji} *<${file.webViewLink}|${file.name}>*\n${summary}`,
        },
        accessory: {
          type: "button",
          text: { type: "plain_text", text: "開く" },
          url: file.webViewLink,
          action_id: `open_file_${file.id}`,
        },
      },
      {
        type: "context",
        elements: [
          {
            type: "mrkdwn",
            text: `最終更新: ${new Date(file.modifiedTime).toLocaleDateString("ja-JP")} ｜ ${file.owners?.[0]?.displayName ?? "不明"}`,
          },
        ],
      },
      { type: "divider" }
    );
  }

  return blocks;
}

// ─── 起動 ─────────────────────────────────────────────────────────────────────
(async () => {
  await app.start();
  console.log("⚡ Slack Drive Search Bot 起動完了");
})();
