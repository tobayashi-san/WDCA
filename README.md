# Windows Deployment & Configuration Assistant (WDCA)

A modern PowerShell-based utility with WPF interface for streamlining Windows system deployment, configuration, troubleshooting, and imaging operations. Inspired by [WinUtil](https://github.com/ChrisTitusTech/winutil) architecture with enhanced enterprise features.

## 🚀 Quick Start

### One-Line Install & Run
```powershell
irm "tobayashi-san.github.io/WDCA/start" | iex
```

This command will:
- ✅ Automatically request administrator privileges
- ✅ Download the latest WDCA directly from GitHub
- ✅ Run without requiring ExecutionPolicy changes
- ✅ Work in Windows Terminal or PowerShell

### Alternative Installation Methods

#### Local Development
```powershell
# Clone or download the repository
git clone https://github.com/Tobayashi-san/WDCA.git
cd WDCA

# Compile and run
.\Compile.ps1 -Run
```

#### Direct Download
```powershell
# Download and run compiled version
Invoke-WebRequest -Uri "https://tobayashi-san.github.io/WDCA/wdca.ps1" -OutFile "wdca.ps1"
.\wdca.ps1
```


## Architecture

### Configuration-Driven Design
All features are defined in JSON configuration files, enabling easy extension without code changes:

```
WDCA/
├── config/           # JSON configuration files
│   ├── applications.json    # Software packages and WinGet IDs
│   └── roles.json          # Server role configurations
├── functions/        # PowerShell functions
│   ├── private/            # Internal helper functions
│   └── public/             # Main feature functions
├── scripts/          # Core execution scripts
├── xaml/            # WPF interface definitions
├── tools/           # Build and development tools
├── Compile.ps1      # Build script
└── wdca.ps1        # Compiled output
```

## 🛠️ Development

### Building from Source
```powershell
# Standard build
.\Compile.ps1

# Debug build with extra logging
.\Compile.ps1 -Debug

# Build and run immediately
.\Compile.ps1 -Run
```

### Adding New Features
1. **Add Configuration**: Create or update JSON files in `config/`
2. **Create Functions**: Add PowerShell functions in `functions/public/`
3. **Update Interface**: Modify XAML in `xaml/inputXML.xaml` if needed
4. **Register Events**: Add event handlers in `scripts/main.ps1`
5. **Build & Test**: Use `Compile.ps1` to build and test

## 📋 System Requirements

### Minimum Requirements
- **Operating System**: Windows 10 (1903+) or Windows 11
- **PowerShell**: Version 5.1 or higher (PowerShell 7+ recommended)
- **Privileges**: Administrator rights required for system modifications
- **Framework**: .NET Framework 4.5+ (for WPF interface)

### Optional Components
- **WinGet**: Required for application installation features
- **Windows Terminal**: Enhanced terminal experience (automatically detected)
- **Git**: For development and contributing

## 🌐 Network Requirements

### Internet Connectivity
- **GitHub Access**: For downloading latest version and updates
- **WinGet Repositories**: For application installations
- **Microsoft Services**: For Windows updates and tools

### Offline Usage
- Compiled `wdca.ps1` can run offline (limited functionality)
- Application installations require internet for WinGet operations
- System diagnostics and configuration work offline

## 🤝 Contributing

### How to Contribute
1. **Fork the Repository**: Create your own copy on GitHub
2. **Create Feature Branch**: `git checkout -b feature/amazing-feature`
3. **Make Changes**: Add your improvements or fixes
4. **Test Thoroughly**: Ensure all functionality works as expected
5. **Submit Pull Request**: Describe your changes and benefits

### Development Guidelines
- Follow PowerShell best practices and style guidelines
- Add comprehensive error handling and logging
- Update documentation for new features
- Test on multiple Windows versions when possible
- Consider enterprise environments in design decisions

## 📄 License

**MIT License** - see [LICENSE](LICENSE) file for details.

This project is open source and free to use, modify, and distribute.

## 🙏 Acknowledgments

- **Inspiration**: [WinUtil](https://github.com/ChrisTitusTech/winutil) by Chris Titus Tech
- **Community**: Built for IT professionals managing Windows environments
- **Contributors**: Thanks to all who contribute to making WDCA better

---

**Ready to streamline your Windows deployments?**

```powershell
irm "tobayashi-san.github.io/WDCA/start" | iex
```

