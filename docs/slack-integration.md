# Slack Integration Setup

## Overview

The Slack integration allows you to receive real-time notifications about monitor status changes directly in your Slack workspace. This ensures your team is immediately informed when services go down or come back online.

## Prerequisites

- Solo, Team, or Enterprise UptimeRobot plan
- Admin access to your Slack workspace
- Appropriate permissions to add apps to Slack channels

## Setup Process

### Step 1: Upgrade Your Plan (If Needed)

1. Navigate to the Integrations page (`/integrations`)
2. Locate the Slack integration card
3. If you see "Available only in Solo, Team and Enterprise. Upgrade now", click the "Upgrade now" link
4. Select an appropriate plan that includes Slack integration

### Step 2: Configure Slack Integration

1. Once your plan supports Slack integration, return to the Integrations page
2. Click on the Slack integration card
3. You'll be redirected to the Slack configuration page

### Step 3: Slack App Installation

1. Click "Add to Slack" or "Install App" button
2. You'll be redirected to Slack's authorization page
3. Select the Slack workspace where you want to install the UptimeRobot app
4. Review the permissions requested by the app
5. Click "Allow" to authorize the integration

### Step 4: Channel Configuration

1. Choose which Slack channel(s) should receive notifications
2. You can configure different channels for different types of alerts:
   - **General alerts**: All monitor status changes
   - **Critical alerts**: Only for critical monitors
   - **Recovery notifications**: When monitors come back online

### Step 5: Monitor Assignment

1. Select which monitors should send notifications to Slack
2. You can choose:
   - **All monitors**: Every monitor sends notifications
   - **Specific monitors**: Only selected monitors send alerts
   - **Monitor groups**: Assign based on monitor categories

## Notification Types

Slack notifications will include:

- **Down alerts**: When a monitor detects a service is down
- **Up alerts**: When a monitor detects a service has recovered
- **Maintenance alerts**: Scheduled maintenance notifications
- **Status summaries**: Periodic status reports (if configured)

## Message Format

Slack messages typically include:

```
🔴 Monitor Alert: [Monitor Name]
Status: DOWN
URL: https://example.com
Duration: 2 minutes
Time: 2024-01-15 14:30:00 UTC
```

## Customization Options

- **Alert frequency**: Configure how often to send alerts
- **Message format**: Customize the notification message template
- **Channel routing**: Route different alert types to different channels
- **Mention settings**: Configure @channel or specific user mentions for critical alerts

## Testing the Integration

1. After setup, use the "Test Integration" feature (if available)
2. Alternatively, temporarily pause and unpause a monitor to trigger a test notification
3. Verify notifications appear in the correct Slack channel

## Troubleshooting

### Common Issues

1. **No notifications received**:
   - Check that the Slack app has proper permissions
   - Verify the channel configuration
   - Ensure monitors are assigned to the Slack integration

2. **Notifications going to wrong channel**:
   - Review channel routing settings
   - Check monitor-to-channel assignments

3. **App not found in Slack**:
   - Re-install the UptimeRobot Slack app
   - Check workspace app permissions

### Re-authorization

If the integration stops working:

1. Go to Integrations page
2. Remove the existing Slack integration
3. Re-add and reconfigure the integration
4. Test to ensure notifications work

## Best Practices

- **Dedicated channel**: Create a dedicated #uptime-alerts channel
- **Channel notifications**: Configure appropriate notification levels to avoid spam
- **Team training**: Ensure team members know how to interpret alerts
- **Regular testing**: Test the integration periodically to ensure it's working
- **Escalation rules**: Set up escalation procedures for critical alerts

## Security Considerations

- The Slack integration only sends outbound notifications
- No sensitive monitor data is stored in Slack
- Revoke integration access if team members leave
- Regularly review app permissions in your Slack workspace