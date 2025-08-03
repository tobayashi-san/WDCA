# Windows Deployment & Configuration Assistant (WDCA)

A comprehensive PowerShell-based utility with modern WPF interface for streamlining Windows system deployment, configuration, troubleshooting, and cloning.

## 🚀 Quick Start

### Prerequisites

- Windows 10/11 or Windows Server 2016+
- PowerShell 5.1 or higher
- Administrator privileges
- WinGet (for application management)
- .NET Framework 4.7+ (for WPF interface)

### Running WDCA

1. **Development Mode** (for testing):
   ```powershell
   # Clone or download the repository
   cd C:\Path\To\WDCA
   .\Compile.ps1 -Run
   ```

2. **Compiled Version**:
   ```powershell
   # Compile first
   .\Compile.ps1
   
   # Then run the compiled version
   .\wdca.ps1
   ```

## 🏗️ Project Structure

```
WDCA/
├── config/                  # Configuration files (JSON)
│   ├── applications.json    # Application definitions
│   ├── roles.json          # Server roles
│   ├── sysprep.json        # Sysprep configurations
│   ├── troubleshooting.json # Diagnostic tools
│   └── tweaks.json         # System tweaks
├── functions/              # PowerShell functions
│   ├── private/           # Internal helper functions
│   │   ├── Invoke-Helper.ps1
│   │   ├── Test-Prerequisites.ps1
│   │   └── Write-Logger.ps1
│   └── public/            # Main feature functions
│       ├── Invoke-WPFApplications.ps1
│       ├── Invoke-WPFCloning.ps1
│       ├── Invoke-WPFSystemSetup.ps1
│       ├── Invoke-WPFTroubleshooting.ps1
│       └── Invoke-WPFUpdates.ps1
├── scripts/               # Core scripts
│   ├── main.ps1          # Main execution logic
│   └── start.ps1         # Initialization script
├── tools/                 # Build tools
│   └── Invoke-Preprocessing.ps1
├── xaml/                  # UI definitions
│   ├── inputXML.xaml     # Main interface
│   └── templates/        # XAML templates
├── Compile.ps1           # Build script
├── wdca.ps1             # Compiled output (generated)
└── README.md
```

## ✨ Features

### 📦 Application Management
- **Mass Installation**: Install multiple applications simultaneously using WinGet
- **Category Organization**: Applications grouped by category (Browsers, Utilities, Pro Tools, etc.)
- **Profile Support**: Create and manage standardized application deployment profiles
- **Progress Tracking**: Real-time installation progress and logging

### ⚙️ System Setup
- **Network Configuration**: Set IP address, subnet mask, gateway, and DNS
- **Remote Desktop**: Enable and configure RDP with authentication options
- **Server Roles**: Install and configure Windows Server roles:
  - Domain Controller (AD-DS)
  - File Server with DFS
  - Web Server (IIS)
  - Terminal Server (RDS)
  - DHCP Server
  - DNS Server

### 🔧 Troubleshooting Tools
- **System Diagnostics**: Run DISM, SFC, and CHKDSK scans
- **Network Diagnostics**: Connectivity tests, DNS resolution, routing information
- **Real-Time Results**: Live diagnostic output in integrated console
- **Comprehensive Logging**: Detailed logs for all operations

### 🔄 Update Management
- **Windows Updates**: Check and install Windows Updates
- **Application Updates**: Update all installed applications via WinGet
- **Update Preparation**: Prepare systems for major upgrades
- **Reboot Detection**: Automatic detection of pending reboots

### 💿 Cloning & Imaging
- **Sysprep Automation**: Automated Sysprep execution with customizable options
- **Pre-Clone Cleanup**: Remove temporary files, logs, and unnecessary data
- **Image Preparation**: Complete system preparation for imaging workflows
- **Flexible Options**: Generalize, OOBE, shutdown/restart options

## 🛠️ Development

### Building WDCA

The build process combines all source files into a single executable PowerShell script:

```powershell
# Basic compilation
.\Compile.ps1

# Compile and run immediately
.\Compile.ps1 -Run

# Debug build (keeps temporary files)
.\Compile.ps1 -Debug

# Run with arguments
.\Compile.ps1 -Run -Arguments "-LogLevel DEBUG"
```

### Adding New Features

1. **Create JSON Configuration** (if needed):
   ```json
   // config/newfeature.json
   {
     "feature1": {
       "name": "Feature Name",
       "description": "Feature description",
       "category": "Category",
       "enabled": true
     }
   }
   ```

2. **Create Function File**:
   ```powershell
   # functions/public/Invoke-WPFNewFeature.ps1
   function Invoke-WPFNewFeature {
       param([string]$Action)
       Write-Logger "Executing new feature: $Action" "INFO"
       # Implementation here
   }
   ```

3. **Update XAML Interface** (if needed):
   Add UI elements to `xaml/inputXML.xaml`

4. **Register Event Handlers** in `scripts/main.ps1`:
   ```powershell
   if ($sync.WPFNewFeatureButton) {
       $sync.WPFNewFeatureButton.Add_Click({
           Invoke-WPFNewFeature -Action "Execute"
       })
   }
   ```

### Configuration-Driven Architecture

All features are defined in JSON configuration files:

- **applications.json**: Software packages available for installation
- **roles.json**: Server role configurations and requirements
- **tweaks.json**: System optimization and configuration tweaks
- **troubleshooting.json**: Diagnostic tools and their parameters

This approach allows adding new features without modifying PowerShell code.

## 📋 Usage Examples

### Installing Applications
1. Launch WDCA as Administrator
2. Go to **Applications** tab
3. Select desired applications by category
4. Click **Install Selected Applications**
5. Monitor progress in status bar and log

### Configuring Network Settings
1. Go to **System Setup** tab
2. Enter IP configuration in **Network Configuration** section
3. Click **Configure Network**
4. Verify settings in network adapter properties

### Running System Diagnostics
1. Go to **Troubleshooting** tab
2. Click **Run All Diagnostics** for comprehensive scan
3. Or use individual tools (DISM, SFC, CHKDSK)
4. View results in the diagnostic output panel

### Preparing for Sysprep
1. Go to **Cloning** tab
2. Click **Run Cleanup** to remove unnecessary files
3. Configure Sysprep options (Generalize, OOBE, Shutdown)
4. Click **Run Sysprep** when ready for imaging

## 🔐 Security & Permissions

- **Administrator Required**: WDCA requires administrator privileges for most operations
- **Automatic Elevation**: Attempts to restart as admin if not running elevated
- **Safe Operations**: Confirmation dialogs for destructive operations
- **Audit Trail**: Complete logging of all operations for compliance

## 📊 Logging & Monitoring

- **Centralized Logging**: All operations logged to `%TEMP%\WDCA_YYYYMMDD_HHMMSS.log`
- **Multiple Log Levels**: INFO, WARNING, ERROR, DEBUG
- **Real-Time Status**: Live status updates in application status bar
- **Progress Tracking**: Visual progress bars for long-running operations

## 🔧 Troubleshooting

### Common Issues

1. **"WinGet not found"**
   - Install WinGet from Microsoft Store or GitHub releases
   - Ensure WinGet is in system PATH

2. **"WPF Framework not available"**
   - Install .NET Framework 4.7 or higher
   - Ensure Windows is updated

3. **"Access Denied" errors**
   - Run PowerShell as Administrator
   - Check execution policy: `Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process`

4. **Network configuration fails**
   - Verify network adapter is active
   - Check for conflicting IP configurations
   - Ensure sufficient permissions for network changes

### Debug Mode

Enable debug logging for troubleshooting:

```powershell
# Set debug level in the UI or via sync variable
$sync.logLevel = "DEBUG"
```

## 🤝 Contributing

1. Fork the repository
2. Create feature branch: `git checkout -b feature/new-feature`
3. Make changes following the configuration-driven approach
4. Test thoroughly with `.\Compile.ps1 -Debug -Run`
5. Submit pull request with detailed description

## 📄 License

MIT License - see [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Inspired by [WinUtil](https://github.com/ChrisTitusTech/winutil) architecture
- Built for IT professionals managing Windows environments
- Community-driven development and feature requests welcome

---

**Note**: WDCA is designed for professional IT environments. Always test in non-production systems before deploying to critical infrastructure.