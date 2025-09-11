# Telegram Integration Setup

## Overview

The Telegram integration enables you to receive real-time monitor alerts directly on your mobile device or desktop through Telegram messages. This provides instant notifications about service downtime and recovery, ensuring you're always informed about your infrastructure status.

## Prerequisites

- Solo, Team, or Enterprise UptimeRobot plan
- Telegram account (mobile app or desktop client)
- Basic familiarity with Telegram bots

## Setup Process

### Step 1: Upgrade Your Plan (If Needed)

1. Navigate to the Integrations page (`/integrations`)
2. Locate the Telegram integration card
3. If you see "Available only in Solo, Team and Enterprise. Upgrade now", click the "Upgrade now" link
4. Select an appropriate plan that includes Telegram integration

### Step 2: Create Telegram Bot

1. Open Telegram and search for `@BotFather`
2. Start a conversation with BotFather
3. Send `/newbot` command
4. Follow the prompts to create a new bot:
   - Choose a name for your bot (e.g., "UptimeRobot Alerts")
   - Choose a username ending in "bot" (e.g., "mycompany_uptime_bot")
5. BotFather will provide a bot token - save this securely

### Step 3: Configure UptimeRobot Integration

1. Return to the UptimeRobot Integrations page
2. Click on the Telegram integration card
3. Enter the bot token provided by BotFather
4. Configure notification settings

### Step 4: Get Chat ID

#### For Personal Notifications:
1. Start a conversation with your bot
2. Send any message to the bot
3. Visit: `https://api.telegram.org/bot[BOT_TOKEN]/getUpdates`
4. Look for the "chat" object and note the "id" value
5. Enter this Chat ID in UptimeRobot

#### For Group Notifications:
1. Add your bot to a Telegram group
2. Send a message in the group mentioning the bot
3. Use the getUpdates API method as above
4. Look for the group chat ID (usually negative number)

### Step 5: Monitor Assignment

1. Select which monitors should send Telegram notifications
2. Choose notification preferences:
   - **All events**: Down, up, and maintenance alerts
   - **Down only**: Only when monitors go down
   - **Critical only**: Only for high-priority monitors

## Notification Types

Telegram messages will include:

- **🔴 Down Alerts**: When a monitor detects service failure
- **🟢 Up Alerts**: When a monitor detects service recovery  
- **🟡 Maintenance Alerts**: Scheduled maintenance notifications
- **📊 Status Summaries**: Periodic status reports (if enabled)

## Message Format

Telegram notifications typically appear as:

```
🔴 MONITOR DOWN
Monitor: Production API
URL: https://api.example.com
Status: DOWN
Duration: 3 minutes
Time: 15:30 UTC
Response: Connection timeout
```

## Advanced Configuration

### Custom Message Templates

Customize notification messages with variables:
- `{MONITOR_NAME}` - Name of the monitor
- `{MONITOR_URL}` - Monitor URL
- `{STATUS}` - Current status (UP/DOWN)
- `{DURATION}` - Downtime duration
- `{TIMESTAMP}` - Alert timestamp
- `{RESPONSE_TIME}` - Last response time

### Silent Notifications

Configure silent notifications for:
- Non-critical monitors
- Maintenance windows
- Recovery alerts

### Chat Targeting

Set up different chat destinations:
- **Personal chat**: Direct messages to yourself
- **Team group**: Notifications to team group chat
- **Alert channel**: Dedicated alerts channel

## Testing the Integration

1. Use the "Send Test Message" feature in UptimeRobot
2. Verify the test message appears in Telegram
3. Check message formatting and content
4. Test with a temporary monitor pause/unpause

## Troubleshooting

### Common Issues

1. **No messages received**:
   - Verify bot token is correct
   - Check chat ID is properly configured
   - Ensure bot hasn't been blocked
   - Confirm monitors are assigned to Telegram integration

2. **Bot not responding**:
   - Restart conversation with bot
   - Check bot permissions in group chats
   - Verify bot is still active with BotFather

3. **Wrong chat receiving messages**:
   - Double-check chat ID configuration
   - Verify you're using the correct positive/negative chat ID format

4. **Messages not formatted correctly**:
   - Review message template configuration
   - Check for unsupported characters or formatting

### Re-setup Process

If integration fails:

1. Revoke current bot token with BotFather
2. Create new bot and obtain new token
3. Reconfigure integration in UptimeRobot
4. Update chat ID if needed
5. Test thoroughly

## Security Best Practices

- **Token Security**: Never share your bot token publicly
- **Access Control**: Limit bot access to necessary chats only
- **Regular Review**: Periodically review active integrations
- **Token Rotation**: Consider rotating bot tokens periodically

## Mobile vs Desktop

### Mobile Advantages:
- Instant push notifications
- Always accessible
- Location-independent alerts

### Desktop Advantages:
- Better for team environments
- Easier message management
- Integration with desktop workflows

## Group Chat Best Practices

- **Dedicated Channel**: Create specific uptime alerts group
- **Member Management**: Limit group to relevant team members
- **Notification Settings**: Configure appropriate notification levels
- **Bot Permissions**: Give bot only necessary permissions
- **Message Retention**: Configure message history settings appropriately

## Integration Limits

- Maximum message rate: Telegram API limits apply
- Message length: Up to 4096 characters per message
- File attachments: Limited support for images/documents
- Bot limitations: Subject to Telegram's bot API restrictions