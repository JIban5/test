; NSIS 安装脚本 - 远程助手客户端（安装版）
; 编译命令: makensis installer.nsi
; 特性: 无桌面快捷方式 / 开机自启 / 完成后后台静默启动 / 协议勾选强制

!define PRODUCT_NAME "888"
!define PRODUCT_VERSION "1.4.9.4"
!define PRODUCT_PUBLISHER "YourCompany"
!define PRODUCT_EXE "888.exe"
!define PRODUCT_UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}"
; 客户端 autostart.rs 写入的 Run 值名为 "RustDesk"，卸载时需一并清理
!define RUN_KEY "Software\Microsoft\Windows\CurrentVersion\Run"

!include "MUI2.nsh"
!include "FileFunc.nsh"
!include "LogicLib.nsh"

Name "${PRODUCT_NAME}"
OutFile "888.exe"
InstallDir "$PROGRAMFILES\${PRODUCT_NAME}"
InstallDirRegKey HKLM "${PRODUCT_UNINST_KEY}" "InstallLocation"
RequestExecutionLevel admin

; MUI 设置
!define MUI_ABORTWARNING
!define MUI_ICON "${NSISDIR}\Contrib\Graphics\Icons\orange-install.ico"
!define MUI_UNICON "${NSISDIR}\Contrib\Graphics\Icons\orange-uninstall.ico"

; 欢迎页面
!insertmacro MUI_PAGE_WELCOME
; 许可协议页面（必须勾选同意才能继续，不勾选无法进入安装）
!define MUI_LICENSEPAGE_CHECKBOX
!insertmacro MUI_PAGE_LICENSE "LICENCE"
; 安装目录选择页面
!insertmacro MUI_PAGE_DIRECTORY
; 安装过程页面
!insertmacro MUI_PAGE_INSTFILES
; 完成页面：点击【完成】后启动程序并打开主界面
!define MUI_FINISHPAGE_RUN "$INSTDIR\${PRODUCT_EXE}"
!insertmacro MUI_PAGE_FINISH

; 卸载页面
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

; 语言文件
!insertmacro MUI_LANGUAGE "SimpChinese"

Section "MainSection" SEC01
  SetOutPath "$INSTDIR"
  SetOverwrite on

  ; ===== 升级安装：先停止本产品的 Windows 服务 =====
  ; 服务进程(SYSTEM)持有 888.exe 文件句柄，不停服务则主程序无法被替换，
  ; 表现为"安装了新版本但运行的还是旧版"
  nsExec::ExecToStack 'sc stop "${PRODUCT_NAME}"'
  Pop $0
  Sleep 1500

  ; ===== 结束正在运行的程序（升级安装时文件被占用会导致写入失败）=====
  ; 只按进程完整路径过滤：安装目录(888)或旧版目录(远程助手)下的进程。
  ; 注意：不能用 Get-Process 888 —— 纯数字参数会被 PowerShell 当作 PID 解析，
  ; 结果查不到名为 888 的进程，旧程序杀不掉、主程序替换失败。
  nsExec::ExecToStack "powershell -NoProfile -Command $\"Get-Process -ErrorAction SilentlyContinue | Where-Object { $$_.Path -and (($$_.Path -like '*\888\*') -or ($$_.Path -like '*远程助手*')) } | Stop-Process -Force$\""
  Sleep 2000

  ; ===== 旧版本升级清理（远程助手/svchost.exe 时代 → 888/rdassistant.exe）=====
  ; 旧版目录、程序名、自启动项与新版本完全不同，安装时需彻底清理，
  ; 否则旧版会继续自启运行（连旧端口，表现为"没有自动更新"）
  StrCpy $R8 "C:\Program Files\远程助手"
  IfFileExists "$R8\svchost.exe" 0 upgrade_cleanup_done
    DetailPrint "检测到旧版本，正在升级清理..."
    ; 结束旧版进程（按完整路径过滤，绝不误杀系统同名进程）
    nsExec::ExecToStack "powershell -NoProfile -Command $\"Get-Process svchost -ErrorAction SilentlyContinue | Where-Object { $$_.Path -eq '$R8\svchost.exe' } | Stop-Process -Force$\""
    Sleep 1000
    ; 清除旧版自启动项
    DeleteRegValue HKCU "${RUN_KEY}" "远程助手"
    DeleteRegValue HKCU "${RUN_KEY}" "RustDesk"
    DeleteRegValue HKLM "${RUN_KEY}" "远程助手"
    DeleteRegValue HKLM "${RUN_KEY}" "RustDesk"
    ; 删除旧版卸载注册表键
    DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\远程助手"
    ; 删除旧版目录（连同旧 uninst.exe、旧 svchost.exe 一起移除）
    RMDir /r "$R8"
    ; 删除旧版快捷方式
    Delete "$DESKTOP\远程助手.lnk"
    Delete "$PUBLIC\Desktop\远程助手.lnk"
    RMDir /r "$SMPROGRAMS\远程助手"
    RMDir /r "$APPDATA\Microsoft\Windows\Start Menu\Programs\远程助手"
    DetailPrint "旧版本清理完成"
  upgrade_cleanup_done:

  ; ===== 兜底：把仍被占用的旧主程序改名移开 =====
  ; Windows 允许重命名正在运行的可执行文件（不允许删除），改名后
  ; 新文件即可写入，旧文件安排重启后删除，彻底避免"升级但没换掉"
  IfFileExists "$INSTDIR\${PRODUCT_EXE}" 0 move_old_done
    DetailPrint "正在移开仍被占用的旧主程序..."
    Rename "$INSTDIR\${PRODUCT_EXE}" "$INSTDIR\${PRODUCT_EXE}.old"
    Delete /REBOOTOK "$INSTDIR\${PRODUCT_EXE}.old"
  move_old_done:

  ; 复制主程序与运行库（sciter 版客户端）；并清理改名前的旧文件
  File /oname=${PRODUCT_EXE} "target\release\888.exe"
  File /oname=sciter.dll "target\release\sciter.dll"
  Delete "$INSTDIR\rdassistant.exe"

  ; 不创建桌面快捷方式（需求：安装后桌面无图标）
  ; 同时清理旧版本可能遗留的桌面快捷方式
  Delete "$DESKTOP\${PRODUCT_NAME}.lnk"

  ; 创建开始菜单快捷方式（便于管理员找到程序）
  CreateDirectory "$SMPROGRAMS\${PRODUCT_NAME}"
  CreateShortCut "$SMPROGRAMS\${PRODUCT_NAME}\${PRODUCT_NAME}.lnk" "$INSTDIR\${PRODUCT_EXE}"
  CreateShortCut "$SMPROGRAMS\${PRODUCT_NAME}\卸载${PRODUCT_NAME}.lnk" "$INSTDIR\uninst.exe"

  ; 开机自启动（后台托盘模式）
  WriteRegStr HKCU "${RUN_KEY}" "${PRODUCT_NAME}" '"$INSTDIR\${PRODUCT_EXE}" --tray'

  ; 写入注册表（供"添加/删除程序"识别）
  WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "DisplayName" "${PRODUCT_NAME}"
  WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "UninstallString" "$INSTDIR\uninst.exe"
  WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "DisplayIcon" "$INSTDIR\${PRODUCT_EXE}"
  WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "DisplayVersion" "${PRODUCT_VERSION}"
  WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "Publisher" "${PRODUCT_PUBLISHER}"
  WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "InstallLocation" "$INSTDIR"

  ; 计算安装大小
  ${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2
  IntFmt $0 "0x%08X" $0
  WriteRegDWORD HKLM "${PRODUCT_UNINST_KEY}" "EstimatedSize" "$0"

  ; 创建卸载程序
  WriteUninstaller "$INSTDIR\uninst.exe"

  ; 注册并启动 Windows 系统服务（SYSTEM 后台常驻，独立于界面窗口；
  ; 关闭主界面/进程退出都不影响远程连接）
  ExecWait '"$INSTDIR\${PRODUCT_EXE}" --install-service'
  Sleep 500
  ExecWait 'net start "${PRODUCT_NAME}"'

  ; 启动用户会话的后台常驻进程（全局热键持有者）。
  ; 开机自启的 --tray 要到下次登录才生效，这里立即拉起，
  ; 保证安装完成后马上就能用 Ctrl+Alt+J 唤出主窗口。
  Exec '"$INSTDIR\${PRODUCT_EXE}" --tray'

  ; ===== 异步启动安装包自删除 =====
  ; 安装包 exe 运行中无法删除自身，由本程序 --delete-installer 模式
  ; 在后台轮询等待安装程序退出后删除安装包文件
  Exec '"$INSTDIR\${PRODUCT_EXE}" --delete-installer "$EXEPATH"'
SectionEnd

Section "Uninstall"
  ; 停止运行的程序
  ; 注意：绝不能用 taskkill /IM "svchost.exe" —— 会误杀 Windows 系统服务宿主导致蓝屏重启。
  ; 此处仅结束可执行路径位于本安装目录下的进程。
  nsExec::ExecToStack "powershell -NoProfile -Command $\"Get-Process rdassistant,888,svchost -ErrorAction SilentlyContinue | Where-Object { $$_.Path -like '*\888\*' -or $$_.Path -like '*远程助手*' } | Stop-Process -Force$\""
  Sleep 2000

  ; 停止并删除系统服务
  nsExec::ExecToStack 'sc stop "${PRODUCT_NAME}"'
  nsExec::ExecToStack 'sc delete "${PRODUCT_NAME}"'
  Sleep 1000

  ; 删除文件
  Delete "$INSTDIR\${PRODUCT_EXE}"
  Delete "$INSTDIR\rdassistant.exe"
  Delete "$INSTDIR\sciter.dll"
  Delete "$INSTDIR\uninst.exe"

  ; 删除快捷方式（含旧版本遗留）
  Delete "$DESKTOP\${PRODUCT_NAME}.lnk"
  Delete "$SMPROGRAMS\${PRODUCT_NAME}\${PRODUCT_NAME}.lnk"
  Delete "$SMPROGRAMS\${PRODUCT_NAME}\卸载${PRODUCT_NAME}.lnk"
  RMDir "$SMPROGRAMS\${PRODUCT_NAME}"

  ; 删除注册表
  DeleteRegKey HKLM "${PRODUCT_UNINST_KEY}"

  ; 删除开机自启动（兼容两种值名）
  DeleteRegValue HKCU "${RUN_KEY}" "${PRODUCT_NAME}"
  DeleteRegValue HKCU "${RUN_KEY}" "RustDesk"

  ; 删除安装目录
  RMDir "$INSTDIR"

  MessageBox MB_OK "卸载完成！"
SectionEnd

Function .onInit
  ; 检查是否已安装
  ReadRegStr $R0 HKLM "${PRODUCT_UNINST_KEY}" "UninstallString"
  StrCmp $R0 "" done

  ; 旧版卸载程序存在缺陷（taskkill 按映像名误杀系统进程导致蓝屏），
  ; 因此不再自动执行旧卸载程序，直接覆盖安装即可
  MessageBox MB_OK|MB_ICONINFORMATION \
  "检测到已安装旧版本，将直接覆盖升级。$\n$\n若此前安装过旧测试版（svchost.exe），建议安装完成后重启一次电脑。" \
  IDOK done
  Abort

done:
FunctionEnd
