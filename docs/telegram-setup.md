# Telegram bot setup for server-pulse alerts

A complete walk-through for getting Telegram notifications working with server-pulse.

## 1. Create a bot

1. Open Telegram and start a chat with [`@BotFather`](https://t.me/BotFather).
2. Send `/newbot`.
3. Pick a display name (e.g. `My Server Pulse`).
4. Pick a username ending in `bot` (e.g. `my_server_pulse_bot`).
5. BotFather replies with an HTTP token like `1234567890:AAH...`. **This is your `TELEGRAM_BOT_TOKEN`.**

Treat the token like a password — anyone with it can post messages as your bot.

## 2. Find the chat ID

The `chat_id` is where alerts will be sent. It can be a personal chat, a group, or a channel.

### For a personal chat (alerts in your DMs)

1. Open a chat with your new bot and send any message (e.g. `/start`).
2. Run on your laptop:
   ```bash
   curl -s "https://api.telegram.org/bot<YOUR_TOKEN>/getUpdates" | jq
   ```
3. Look for `"chat": { "id": <number>, ... }`. That number is your `TELEGRAM_CHAT_ID`.

### For a group

1. Add the bot to the group.
2. Send any message in the group.
3. Run the same `getUpdates` curl. The group's `chat.id` is **negative** (e.g. `-1001234567890`).

### For a channel

1. Add the bot as an **administrator** of the channel (the "post messages" permission must be enabled — channels reject non-admin posts).
2. Forward any message from the channel to [`@userinfobot`](https://t.me/userinfobot) — it will reply with the channel's ID.
3. Channel IDs look like `-1001234567890`.

## 3. Configure server-pulse

Edit `/etc/server-pulse/config.env`:

```bash
TELEGRAM_BOT_TOKEN="1234567890:AAH..."
TELEGRAM_CHAT_ID="-1001234567890"
```

Make sure the file is owned by root and locked down — the installer does this automatically:

```bash
sudo chown root:root /etc/server-pulse/config.env
sudo chmod 600 /etc/server-pulse/config.env
```

server-pulse refuses to start if the config is world-readable.

## 4. Verify

```bash
sudo server-pulse test
```

You should see the test message in your chat within a few seconds. If not, see [Troubleshooting](#troubleshooting).

## Behind a firewall

If your server can't reach `api.telegram.org` (RKN blocks, restrictive corporate networks, etc.), add an outbound HTTP/HTTPS proxy:

```bash
OUTBOUND_PROXY_URI="http://proxy.example.com:9999"
OUTBOUND_PROXY_AUTH="username:password"   # omit if proxy is open
```

curl uses `-x` and `-U` flags internally — only Telegram requests go through the proxy, nothing else.

## Troubleshooting

### `Telegram API HTTP 401`
Your `TELEGRAM_BOT_TOKEN` is wrong or revoked. Generate a new one in BotFather.

### `Telegram API HTTP 400: chat not found`
The bot has never seen this chat. Send a message in the chat (or, for channels, make sure the bot is an admin).

### `Telegram API HTTP 403: bot was blocked by the user`
You blocked the bot in Telegram. Unblock it and try again.

### `Telegram curl failed: ... timed out`
- Firewall is blocking `api.telegram.org` (port 443). Use `OUTBOUND_PROXY_URI`.
- DNS issue. Test with `curl -v https://api.telegram.org/`.

### Wrong chat
The `getUpdates` endpoint only returns recent updates (last 24 h). If the chat doesn't show up, send a fresh message and retry.
