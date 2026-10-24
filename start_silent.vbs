Set WshShell = CreateObject("WScript.Shell")
Set FSO = CreateObject("Scripting.FileSystemObject")
strDir = FSO.GetParentFolderName(WScript.ScriptFullName)
strScript = strDir & "\proxy_monitor.ps1"
strCommand = "powershell.exe -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File " & Chr(34) & strScript & Chr(34)
WshShell.Run strCommand, 0, False
Set WshShell = Nothing
Set FSO = Nothing
