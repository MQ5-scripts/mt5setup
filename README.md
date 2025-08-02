# 🐧 Run MetaTrader 5 on Linux

This project helps you install and run MetaTrader 5 on Linux using Wine.

## ✅ Prerequisites

- Linux (Ubuntu, Debian, Arch, etc.)
- `wget`, `unzip`, and `wine` installed
- Internet access

## 📦 Installation

To install MetaTrader 5:

```bash
./mt5setup.sh
```

This script will:

1. Set up a Wine prefix for MetaTrader 5 in `$HOME/.mt5wine`.
2. Download MetaTrader 5 terminal installer.
3. Run the installer under Wine.
4. Launch MetaTrader 5 upon completion.

You only need to run this once.

## 🏃 Running MetaTrader 5 Later

Once MetaTrader 5 is installed, you can launch it again any time using:

```bash
./mt5run.sh
```

This script starts MetaTrader 5 using the correct Wine prefix.

## 📁 Files

- `mt5setup.sh` — one-time installer and launcher script.
- `mt5run.sh` — script to launch MetaTrader 5 after it's installed.
- `README.md` — this file.

## 💬 Notes

- You can change the default Wine prefix path by editing the `WINEPREFIX` variable in both scripts.
- MetaTrader will be installed in:  
  `$HOME/.mt5wine/drive_c/Program Files/MetaTrader 5`

## Kill background Wine processes (optional)

If needed, stop Wine processes that remain running:

```bash
wineserver -k
```

## Troubleshooting

- If MT5 fails to launch, check that Wine is properly installed:  
  `wine --version`

- If UI doesn't load, make sure WebView2 was installed correctly.

- Clean up Wine prefix (this will delete MT5 configuration):  
  `rm -rf ~/.mt5`

---

## License

MIT License. Use at your own risk.
