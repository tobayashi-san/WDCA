# Windows Deployment & Configuration Assistant (WDCA)

A modern PowerShell-based utility with WPF interface for streamlining Windows system deployment, configuration, troubleshooting, and imaging operations. Inspired by [WinUtil](https://github.com/ChrisTitusTech/winutil) architecture with enhanced enterprise features.

## 🚀 Quick Start

```powershell
# Clone or download the repository
cd C:\Path\To\WDCA

# Compile and run
.\Compile.ps1 -Run
```

**Requirements**: Windows 10/11, PowerShell 5.1+, Administrator privileges, WinGet

## ✨ Key Features

- **📦 Application Management**: Mass install applications via WinGet with real-time terminal output
- **⚙️ System Configuration**: Network setup (Static IP/DHCP), Remote Desktop, IPv6 management
- **🔧 System Diagnostics**: DISM, SFC, CHKDSK scans in dedicated terminal windows
- **🔄 Update Management**: Application updates, Domain Controller upgrade preparation
- **💿 System Imaging**: Pre-clone cleanup, automated Sysprep with configurable options

## 🏗️ Architecture

### Project Structure
```
WDCA/
├── config/           # JSON configuration files
├── functions/        # PowerShell functions (private/public)
├── scripts/          # Core execution scripts
├── xaml/            # WPF interface definitions
├── Compile.ps1      # Build script
└── wdca.ps1        # Compiled output
```

### Configuration-Driven Design
All features are defined in JSON files, allowing easy extension without code changes:
- `applications.json` - Software packages and WinGet IDs
- `roles.json` - Server role configurations
- `troubleshooting.json` - Diagnostic tool parameters

## 💡 Terminal-Based Operations

WDCA executes long-running operations in dedicated terminal windows for:
- **Real-time Progress**: Live output and detailed results
- **Responsive UI**: Main interface remains interactive
- **Complete Logging**: All operations logged to temp files
- **Independent Execution**: Each operation runs in its own context

## 🔧 Usage Examples

**Install Applications**:
1. Navigate to Applications tab → Select apps → Install Selected Applications
2. Monitor progress in dedicated terminal window

**Network Configuration**:
1. System Setup tab → Configure Static IP/DHCP → Apply Network Configuration

**System Diagnostics**:
1. Troubleshooting tab → Run All Diagnostics (DISM → SFC → CHKDSK sequence)

**System Imaging**:
1. Cloning tab → Run System Cleanup → Configure Sysprep → Run Sysprep

## 🛠️ Development

### Building
```powershell
.\Compile.ps1              # Standard build
.\Compile.ps1 -Debug       # Debug build with extra logging
.\Compile.ps1 -Run         # Build and run immediately
```

### Adding Features
1. Create JSON configuration (if needed)
2. Add PowerShell function in `functions/public/`
3. Update XAML interface (if needed)
4. Register event handlers in `scripts/main.ps1`

### Code Quality
- Automated preprocessing and validation during build
- PowerShell AST parsing for syntax checking
- Consistent formatting and cleanup

## 🔐 Security & Features

- **Auto-elevation**: Requests admin privileges when needed
- **Safe operations**: Confirmation dialogs for destructive actions
- **Comprehensive logging**: Multi-level logging (INFO, WARNING, ERROR, DEBUG)
- **Error handling**: Graceful degradation and detailed error reporting
- **Async operations**: Thread-safe UI updates and resource cleanup

## 📄 License

MIT License - see [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Inspired by [WinUtil](https://github.com/ChrisTitusTech/winutil) architecture
- Built for IT professionals managing Windows environments
- Community-driven development welcome

---

**Note**: WDCA is designed for professional IT environments. Always test in non-production systems before deploying to critical infrastructure.
