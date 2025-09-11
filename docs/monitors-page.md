# Monitors Page

## Overview

The Monitors page is the central dashboard for monitoring uptime status across all configured services. It provides real-time monitoring data and management capabilities for tracking service availability.

## URL

`/monitors` - Main monitors dashboard

## Page Components

### Header
- **Title**: "Monitors."
- **New Button**: Purple "New" button with dropdown for creating new monitors
- **Search Bar**: "Search by name or url" functionality
- **Filter Button**: Access to filtering options
- **Sort Option**: "Down first" sorting control

### Monitor List
Displays all configured monitors with the following information:
- **Status Indicator**: Green circle for operational, other colors for different states
- **Monitor Name**: Display name (e.g., "Uploader server(prod)")
- **Type & URL**: Shows protocol and endpoint (e.g., "HTTP - Up 2mo, 29 day")
- **Uptime Percentage**: Visual bar showing current uptime (e.g., 100%)
- **Actions**: Three-dot menu for monitor-specific actions

### Sidebar Navigation
- **Monitoring** (current page)
- **Incidents**
- **Status pages**
- **Maintenance**
- **Team members**
- **Integrations & API**

### Current Status Panel (Right Side)
- **Status Overview**: 0 Down, 1 Up, 0 Paused
- **Monitor Usage**: "Using 1 of 50 monitors"
- **Last 24 Hours Stats**:
  - Overall uptime: 100%
  - Incidents: 0
  - Without incident: 1d
  - Affected monitors: 0

### User Account
- **Profile**: Shows "LH. Le Gia Hoang" with account controls
- **Upgrade Button**: Green "Upgrade now" call-to-action

## Features

### Monitor Management
- Create new monitors via the "New" button
- Search and filter existing monitors
- Sort monitors by status (down first, etc.)
- View detailed monitor information
- Access monitor-specific actions

### Status Monitoring
- Real-time status indicators
- Uptime percentage tracking
- Historical uptime data
- Incident tracking
- Performance metrics

### Account Management
- Monitor quota tracking (1 of 50 used)
- Upgrade options for additional features
- User profile management

## Technical Notes

This page appears to be part of an UptimeRobot-style monitoring application built with:
- Dark theme UI
- Responsive design
- Real-time status updates
- Interactive filtering and sorting
- Dashboard-style layout with sidebar navigation

## Usage

1. **Adding Monitors**: Click the "New" button to create new monitoring targets
2. **Viewing Status**: Monitor status is immediately visible via color-coded indicators
3. **Searching**: Use the search bar to find specific monitors by name or URL
4. **Filtering**: Apply filters to view subsets of monitors
5. **Managing**: Use the three-dot menu on each monitor for management options