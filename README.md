### 🪟 `Init-Windows`

> **PowerShell** script to (re)configure my Windows PC.

```powershell
./Init-Windows.ps1
```

_**Note:** Run the following to unblock files (if needed)_
```powershell
Get-ChildItem -Recurse -File | Where-Object { $_.Name -match '.ps(d|m)?1$' } | Unblock-File
```
