# Webhook Integration Setup

## Overview

Webhooks provide the most flexible integration option, allowing you to send monitor alerts to any HTTP endpoint. This enables custom notification workflows, integration with internal systems, third-party services, or custom applications that can process UptimeRobot alert data.

## Prerequisites

- Team or Enterprise UptimeRobot plan
- HTTP endpoint capable of receiving POST requests
- Basic understanding of HTTP requests and JSON data
- SSL certificate for HTTPS endpoints (recommended)

## Setup Process

### Step 1: Upgrade Your Plan (If Needed)

1. Navigate to the Integrations page (`/integrations`)
2. Locate the Webhook integration card  
3. If you see "Available only in Team and Enterprise. Upgrade now", click the "Upgrade now" link
4. Select Team or Enterprise plan to access webhook functionality

### Step 2: Prepare Your Endpoint

Create an HTTP endpoint that can:
- Accept POST requests
- Process JSON payloads
- Return appropriate HTTP status codes (200-299 for success)
- Handle UptimeRobot's expected data format

### Step 3: Configure Webhook Integration

1. Return to the UptimeRobot Integrations page
2. Click on the Webhook integration card
3. Click "Add" or "Configure" to set up a new webhook
4. Fill in the webhook configuration form

## Configuration Options

### Basic Settings

- **Webhook URL**: Your endpoint URL (https://your-domain.com/webhook)
- **HTTP Method**: Usually POST (GET also supported)
- **Content Type**: application/json or application/x-www-form-urlencoded

### Security Settings

- **Authentication**: HTTP Basic Auth, Bearer Token, or API Key
- **Custom Headers**: Add custom HTTP headers
- **IP Restriction**: Limit to UptimeRobot's IP addresses
- **SSL Verification**: Enable/disable SSL certificate verification

### Alert Configuration

- **Trigger Events**: Choose which events trigger webhooks
  - Monitor goes down
  - Monitor comes back up
  - Maintenance mode starts/ends
  - SSL certificate expiration warnings

- **Data Format**: Configure payload structure and included fields

## Webhook Payload Structure

### Default JSON Payload

```json
{
  "alert": {
    "monitorID": "123456789",
    "monitorName": "Production API",
    "monitorURL": "https://api.example.com",
    "monitorType": "1",
    "status": "down",
    "datetime": "2024-01-15 14:30:00",
    "timezone": "UTC",
    "alertType": "down",
    "alertDuration": "180",
    "alertDetails": "Connection timeout after 30 seconds",
    "sslExpiryDate": "2024-12-31",
    "sslExpiryDaysLeft": "350"
  },
  "account": {
    "email": "user@example.com",
    "plan": "enterprise"
  }
}
```

### Custom Payload Variables

Available variables for custom payloads:
- `*monitorID*` - Unique monitor identifier
- `*monitorName*` - Monitor display name
- `*monitorURL*` - Monitored URL
- `*status*` - Current status (up/down/paused)
- `*datetime*` - Alert timestamp
- `*alertType*` - Type of alert (down/up/maintenance)
- `*alertDuration*` - Duration of downtime (in seconds)
- `*alertDetails*` - Detailed alert information
- `*responsetime*` - Last response time in milliseconds

## Testing Your Webhook

### Test Endpoint Setup

Create a simple test endpoint to verify webhook delivery:

```python
# Example Flask endpoint
from flask import Flask, request, jsonify

app = Flask(__name__)

@app.route('/webhook', methods=['POST'])
def handle_webhook():
    data = request.get_json()
    print(f"Received webhook: {data}")
    
    # Process the alert data
    monitor_name = data['alert']['monitorName']
    status = data['alert']['status']
    
    print(f"Monitor {monitor_name} is {status}")
    
    return jsonify({"status": "received"}), 200
```

### Testing Process

1. Set up your test endpoint
2. Configure webhook in UptimeRobot
3. Use "Send Test Webhook" feature
4. Verify webhook is received and processed correctly
5. Check logs for any errors or issues

## Advanced Use Cases

### Custom Alerting Systems

```python
# Example: Forward to PagerDuty
import requests

def handle_webhook():
    data = request.get_json()
    
    if data['alert']['status'] == 'down':
        # Create PagerDuty incident
        pagerduty_payload = {
            "incident_key": data['alert']['monitorID'],
            "event_type": "trigger",
            "description": f"Monitor {data['alert']['monitorName']} is down"
        }
        
        requests.post(
            "https://events.pagerduty.com/v2/enqueue",
            json=pagerduty_payload,
            headers={"Authorization": "Token YOUR_PD_TOKEN"}
        )
```

### Database Logging

```python
# Example: Log alerts to database
def handle_webhook():
    data = request.get_json()
    
    # Store alert in database
    alert_record = {
        'monitor_id': data['alert']['monitorID'],
        'monitor_name': data['alert']['monitorName'],
        'status': data['alert']['status'],
        'timestamp': data['alert']['datetime'],
        'duration': data['alert']['alertDuration']
    }
    
    database.alerts.insert(alert_record)
```

### Multi-Channel Routing

```python
# Example: Route to different channels based on monitor
def handle_webhook():
    data = request.get_json()
    monitor_name = data['alert']['monitorName']
    
    if 'production' in monitor_name.lower():
        # Send to critical alerts channel
        send_to_slack('#critical-alerts', data)
    else:
        # Send to general alerts channel
        send_to_slack('#general-alerts', data)
```

## Error Handling

### Common HTTP Response Codes

- **200-299**: Success - webhook processed correctly
- **400**: Bad Request - invalid payload format
- **401**: Unauthorized - authentication failed
- **404**: Not Found - endpoint doesn't exist
- **500**: Internal Server Error - processing failed

### Retry Behavior

UptimeRobot will retry failed webhooks:
- Initial retry after 1 minute
- Second retry after 5 minutes  
- Third retry after 15 minutes
- Maximum of 3 retry attempts

### Debugging Failed Webhooks

1. Check webhook logs in UptimeRobot dashboard
2. Verify endpoint is accessible from internet
3. Check SSL certificate validity
4. Review server logs for error details
5. Test with webhook testing tools

## Security Best Practices

### Authentication
- Use HTTPS endpoints only
- Implement webhook signature verification
- Use strong API keys or tokens
- Rotate credentials regularly

### Validation
- Validate incoming payload structure
- Verify webhook source IP
- Implement rate limiting
- Log all webhook attempts

### Data Protection
- Don't log sensitive information
- Encrypt stored webhook data
- Use secure communication channels
- Implement proper access controls

## Monitoring Your Webhooks

### Health Checks
- Monitor webhook endpoint uptime
- Track response times
- Alert on failed webhook deliveries
- Monitor error rates

### Logging
- Log all webhook receptions
- Track processing times
- Monitor for duplicate deliveries
- Log authentication attempts

## Troubleshooting

### Webhook Not Received
1. Check endpoint URL is correct and accessible
2. Verify HTTP method configuration
3. Check firewall and security group settings
4. Test endpoint with curl or webhook testing tools

### Authentication Failures
1. Verify authentication credentials
2. Check custom headers configuration
3. Ensure proper authorization header format
4. Test authentication separately

### Payload Issues
1. Check content-type header
2. Verify JSON payload structure
3. Test with minimal payload
4. Check character encoding

### Performance Issues
1. Optimize endpoint response time
2. Implement asynchronous processing
3. Check for resource constraints
4. Monitor database performance

## Webhook URLs Best Practices

- Use dedicated subdomain (webhooks.yourdomain.com)
- Implement versioning (/v1/webhook)
- Use meaningful paths (/uptime-alerts)
- Include environment indicators (/prod/webhook)
- Consider load balancing for high volume