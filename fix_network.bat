@echo off
netsh advfirewall firewall add rule name="Fekka Server 3000" dir=in action=allow protocol=TCP localport=3000
powershell -Command "Get-NetConnectionProfile | Set-NetConnectionProfile -NetworkCategory Private"
echo Done. Your network is now Private. Try from your phone now.
pause
