# 🚀 Incus Backup Script
A simple tool to automatically export your Incus instances. While Incus provides basic backup capabilities, they lack automation and integration features needed for a robust backup strategy. This script bridges that gap by automating instance exports, making it easy to integrate with external backup tools like Restic, Rclone or any other tool.

The script handles the Incus export process, retention management, and logging, letting you focus on where and how to store your backups securely.

## ✨ Key Features
- 📦 Automatic Incus instances export
- 🎯 Per-instance configuration via profile
- 📝 JSON logs
- 🔄 Automatic log rotation
- 🧹 Export retention management

## Installation
```bash
git clone https://github.com/M3t4Data/incus-backup.git
cd incus-backup
chmod +x incus-export.sh
```

## ⚙️ Configuration Options
### Global Configuration
| Variable | Description | Default |
|----------|-------------|---------|
| LOG_MODE | Logging mode (per-instance/global) | per-instance |
| LOG_FORMAT | Log format (json/text) | json |
| LOG_MAX_SIZE | Max log file size | 10MB |
| DEFAULT_RETENTION | Default retention | 7 |

### Instance Configuration
| Option | Description |
|--------|-------------|
| user.incus-export.enabled | Enable export |
| user.incus-export.dest | Destination folder |
| user.incus-export.compression | Compression type |
| user.incus-export.retention | Number of exports to keep |
| user.incus-export.prefix | Filename prefix |
| user.incus-export.suffix | Filename suffix |

## 💡 Usage
### Basic Command
```bash
./incus-export.sh [PROJECT]
```

### Manual Instance Configuration
```bash
# Enable export for an instance
incus config set myinstance user.incus-export.enabled true
# Configure export directory
incus config set myinstance user.incus-export.dest /backups
# Set retention (number of exports to keep)
incus config set myinstance user.incus-export.retention 7
```

### Configuration via Dedicated Profile
```bash
# Create a new backup profile
incus profile create export-daily
# Configure backup options
incus profile set export-daily user.incus-export.enabled=true
incus profile set export-daily user.incus-export.dest=/backups/daily
incus profile set export-daily user.incus-export.retention=7
incus profile set export-daily user.incus-export.compression=gzip
incus profile set export-daily user.incus-export.instance-only=true
# Advanced options (optional)
incus profile set export-daily user.incus-export.prefix="daily-"
incus profile set export-daily user.incus-export.optimized-storage=true
```

#### Profile Application
##### On a New Instance
```bash
# Create instance with export profile
incus launch ubuntu:22.04 my-instance --profile default --profile export-daily
```

##### On an Existing Instance
```bash
# Add profile to an existing instance
incus profile add my-instance export-daily
```

## 📋 TODO
- [ ] Notification support (Telegram, Discord, etc.)
- [ ] Export metrics via prometheus
- [ ] Locking system to prevent simultaneous executions
- [ ] Pre/post backup hooks support
- [ ] Enhanced retention with time-based policies (daily, monthly, etc.)

## 🔄 Future Development

While this script serves its purpose well, the project could benefit from being rewritten in a more robust programming language like Go or Python. This would offer several advantages:

### Benefits
- Better concurrency handling
- Stronger type safety
- Single binary distribution
- Better performance
- Rich ecosystem for notifications (Slack, Discord libraries)
- Easy integration with monitoring tools
- More maintainable codebase
- Better error handling
- Extensive testing frameworks

If you're interested in contributing to such a rewrite, feel free to open an issue to discuss the best approach!
