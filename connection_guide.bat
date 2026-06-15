@echo off
echo ============================================
echo  FAKKA SERVER - Connection Fix
echo ============================================
echo.
echo Option 1: USB Tethering (Recommended)
echo   1. Connect your Oppo phone to PC via USB cable
echo   2. On your phone: Settings - Network - Tethering - USB Tethering - ON
echo   3. On PC, check new network IP with: ipconfig
echo   4. Look for "Ethernet" or "Remote NDIS" adapter IP
echo   5. Open http://THAT_IP:3000 on phone browser
echo.
echo Option 2: Mobile Hotspot from PC
echo   1. Windows Settings - Network - Mobile Hotspot - ON
echo   2. Connect your phone to this hotspot
echo   3. On phone, open http://192.168.137.1:3000
echo.
pause
