# Runs engine/tests/lua_tests.lua with the game's own Lua51.dll (32-bit), no game needed.
#
#   powershell -ExecutionPolicy Bypass -File engine\tests\run_lua_tests.ps1 [-Dll <path to Lua51.dll>]
#
# Default DLL: $env:PALADINS_LUA51, else the usual Steam path. The DLL is 32-bit, so the script
# restarts itself in the 32-bit PowerShell when started from a 64-bit one. Exit code 0 = all passed.
param([string]$Dll = $env:PALADINS_LUA51)
$ErrorActionPreference = 'Stop'

if (-not $Dll) { $Dll = 'D:\SteamLibrary\steamapps\common\Paladins\Binaries\Win32\Lua51.dll' }
if (-not (Test-Path $Dll)) { Write-Error "Lua51.dll not found: $Dll (pass -Dll or set PALADINS_LUA51)" }

if ([IntPtr]::Size -ne 4) {
    $ps32 = Join-Path $env:WINDIR 'SysWOW64\WindowsPowerShell\v1.0\powershell.exe'
    & $ps32 -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -Dll $Dll
    exit $LASTEXITCODE
}

$modRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$script = Join-Path $PSScriptRoot 'lua_tests.lua'
$report = Join-Path $env:TEMP 'smartcounter_lua_tests.txt'
if (Test-Path $report) { Remove-Item $report }

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class SmartCounterLuaHost {
    [DllImport("kernel32", SetLastError=true, CharSet=CharSet.Unicode)] static extern IntPtr LoadLibrary(string p);
    [DllImport("lua51", CallingConvention=CallingConvention.Cdecl)] static extern IntPtr luaL_newstate();
    [DllImport("lua51", CallingConvention=CallingConvention.Cdecl)] static extern void luaL_openlibs(IntPtr L);
    [DllImport("lua51", CallingConvention=CallingConvention.Cdecl)] static extern int luaL_loadbuffer(IntPtr L, byte[] buf, IntPtr sz, string name);
    [DllImport("lua51", CallingConvention=CallingConvention.Cdecl)] static extern int lua_pcall(IntPtr L, int nargs, int nres, int errfunc);
    [DllImport("lua51", CallingConvention=CallingConvention.Cdecl)] static extern IntPtr lua_tolstring(IntPtr L, int idx, out IntPtr len);
    [DllImport("lua51", CallingConvention=CallingConvention.Cdecl)] static extern void lua_close(IntPtr L);
    public static string Run(string dll, string code, string name) {
        if (LoadLibrary(dll) == IntPtr.Zero) return "LoadLibrary failed (" + Marshal.GetLastWin32Error() + ")";
        IntPtr L = luaL_newstate();
        luaL_openlibs(L);
        byte[] b = Encoding.UTF8.GetBytes(code);
        int r = luaL_loadbuffer(L, b, (IntPtr)b.Length, name);
        if (r == 0) r = lua_pcall(L, 0, 0, 0);
        string res = "OK";
        if (r != 0) {
            IntPtr n; IntPtr p = lua_tolstring(L, -1, out n);
            byte[] o = new byte[(int)n]; Marshal.Copy(p, o, 0, (int)n);
            res = "ERROR: " + Encoding.UTF8.GetString(o);
        }
        lua_close(L);
        return res;
    }
}
"@

[Environment]::CurrentDirectory = $modRoot
Set-Location $modRoot
$code = [IO.File]::ReadAllText($script, [Text.Encoding]::UTF8)
$res = [SmartCounterLuaHost]::Run($Dll, $code, '@lua_tests.lua')

if (Test-Path $report) { Get-Content $report -Encoding UTF8 | Where-Object { $_ -match '^(==|FAIL|\d+ passed)' } }
if ($res -ne 'OK') {
    Write-Output $res
    exit 1
}
Write-Output 'Lua tests: OK'
