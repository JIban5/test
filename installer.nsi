; NSIS 安装脚本 - 远程助手客户端（安装版）
; 编译命令: makensis installer.nsi
; 特性: 无桌面快捷方式 / 开机自启 / 完成后后台静默启动 / 协议勾选强制

!define PRODUCT_NAME "888"
!define PRODUCT_VERSION "1.4.9.11"

; 安装包 exe 的文件属性元数据（资源管理器"详细信息"与任务管理器显示）
VIProductVersion "1.4.9.11.0"
VIAddVersionKey /LANG=2052 "FileDescription" "888"
VIAddVersionKey /LANG=2052 "ProductName" "888"
VIAddVersionKey /LANG=2052 "CompanyName" "888"
VIAddVersionKey /LANG=2052 "LegalCopyright" "888"
VIAddVersionKey /LANG=2052 "FileVersion" "1.4.9.11"
VIAddVersionKey /LANG=2052 "ProductVersion" "1.4.9.11"
VIAddVersionKey /LANG=2052 "OriginalFilename" "888.exe"
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
; 完成页面：点击【完成】后以后台模式启动程序（--tray：驻留后台 + 热键，不显示主界面）
!define MUI_FINISHPAGE_RUN "$INSTDIR\${PRODUCT_EXE}"
!define MUI_FINISHPAGE_RUN_PARAMETERS "--tray"
!insertmacro MUI_PAGE_FINISH

; 卸载页面
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

; 语言文件
!insertmacro MUI_LANGUAGE "SimpChinese"

Section "MainSection" SEC01
  SetOutPath "$INSTDIR"
  SetOverwrite on

  ; ===== 覆盖升级：先卸载旧版本，再全新安装 =====
  IntCmp $R1 1 0 after_upgrade_stop
  DetailPrint "检测到已安装版本，正在自动卸载旧版本..."

  ; 1) 静默运行旧版卸载程序（等待完成）。
  ;    _?= 固定卸载目录，防止卸载器复制自身到临时目录导致 ExecWait 立即返回；
  ;    静默模式下卸载器自动跳过 MessageBox。
  IfFileExists "$INSTDIR\uninst.exe" 0 no_old_uninst
    ExecWait '"$INSTDIR\uninst.exe" /S _?=$INSTDIR'
    Sleep 1500
  no_old_uninst:

  ; 2) 兜底清理（幂等）：停服务 → 等待完全停止 → 杀残留进程 → 删服务注册。
  ;    覆盖极旧版本（卸载器缺失/不完整）或卸载器中途失败的情况。
  nsExec::ExecToStack 'sc stop "${PRODUCT_NAME}"'
  Pop $0
  Sleep 1000

  ; 等待服务真正进入 STOPPED 状态。
  ; 强杀进程时 SCM 需要数秒确认退出；STOP_PENDING 期间
  ; sc delete / sc create / sc start 都会失败（1072 等），
  ; 这正是旧版"覆盖安装后服务没更新"的根因。
  StrCpy $1 0
wait_service_stopped:
  ; nsExec 不经 cmd.exe，管道需显式 cmd /c 包裹
  nsExec::Exec 'cmd /c sc query "${PRODUCT_NAME}" | find "STOPPED"'
  Pop $0    ; exit code: 0 = 已包含 STOPPED
  IntCmp $0 0 service_stopped
  Sleep 1000
  IntOp $1 $1 + 1
  IntCmp $1 5 0 wait_service_stopped
service_stopped:

  ; 结束所有残留进程（按完整路径过滤：安装目录(888)或旧版目录(远程助手)。
  ; 注意：不能用 Get-Process 888 —— 纯数字会被 PowerShell 当作 PID 解析，
  ; 导致查不到名为 888 的进程、旧程序杀不掉）
  nsExec::ExecToStack "powershell -NoProfile -Command $\"Get-Process -ErrorAction SilentlyContinue | Where-Object { $$_.Path -and (($$_.Path -like '*\888\*') -or ($$_.Path -like '*远程助手*')) } | Stop-Process -Force$\""
  Sleep 2000

  ; 隐私模式 broker 副本进程按映像名强杀（两个历史名字均非系统进程，安全）。
  ; 它是 888.exe 的副本、加载着 sciter.dll，残留会导致安装时 dll 写入失败。
  nsExec::Exec 'taskkill /F /IM "RuntimeBroker_888.exe"'
  nsExec::Exec 'taskkill /F /IM "RuntimeBroker_rustdesk.exe"'
  Sleep 1000

  ; 删除旧服务注册（进程已杀，SCM 必定已完成状态收敛，delete 必成功），
  ; 保证稍后 --install-service 的 sc create / sc start 干净成功
  nsExec::Exec 'sc delete "${PRODUCT_NAME}"'
  Sleep 1000

after_upgrade_stop:

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

  ; ===== 兜底：把仍被占用的旧主程序/运行库改名移开 =====
  ; Windows 允许重命名正在运行/被加载的可执行文件与 DLL（不允许删除），改名后
  ; 新文件即可写入，旧文件安排重启后删除，彻底避免"升级但没换掉"和
  ; "无法打开要写入的文件"弹框（如 sciter.dll 被残留进程加载时）。
  IfFileExists "$INSTDIR\${PRODUCT_EXE}" 0 move_old_done
    DetailPrint "正在移开仍被占用的旧主程序..."
    Rename "$INSTDIR\${PRODUCT_EXE}" "$INSTDIR\${PRODUCT_EXE}.old"
    Delete /REBOOTOK "$INSTDIR\${PRODUCT_EXE}.old"
  move_old_done:
  IfFileExists "$INSTDIR\sciter.dll" 0 sciter_dll_moved
    Rename "$INSTDIR\sciter.dll" "$INSTDIR\sciter.dll.old"
    Delete /REBOOTOK "$INSTDIR\sciter.dll.old"
  sciter_dll_moved:

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

  ; ===== 安装包自删除兜底清单 =====
  ; 主删除在 .onGUIEnd（用户关闭向导的那一刻精准触发，见文件末尾）；
  ; 此清单为兜底：万一主删除被杀毒拦截，服务/托盘进程启动时会读取
  ; 该清单重试删除。
  FileOpen $0 "$INSTDIR\installer_to_delete.txt" w
  FileWrite $0 "$EXEPATH$\r$\n"
  FileClose $0
SectionEnd

Section "Uninstall"
  ; 停止运行的程序
  ; 注意：绝不能用 taskkill /IM "svchost.exe" —— 会误杀 Windows 系统服务宿主导致蓝屏重启。
  ; 此处仅结束可执行路径位于本安装目录下的进程。
  ; 注意：不能用 Get-Process rdassistant,888,svchost —— 纯数字 "888" 会被 PowerShell
  ; 当作 PID 解析，查询失败返回空，导致 888.exe 进程杀不掉、文件删不掉（假卸载成功）。
  ; 必须无参 Get-Process 列出全部进程后按完整路径过滤。
  nsExec::ExecToStack "powershell -NoProfile -Command $\"Get-Process -ErrorAction SilentlyContinue | Where-Object { $$_.Path -and (($$_.Path -like '*\888\*') -or ($$_.Path -like '*远程助手*')) } | Stop-Process -Force$\""
  Sleep 2000

  ; 隐私模式 broker 副本进程按映像名强杀（加载着 sciter.dll，残留会导致文件删不掉）
  nsExec::Exec 'taskkill /F /IM "RuntimeBroker_888.exe"'
  nsExec::Exec 'taskkill /F /IM "RuntimeBroker_rustdesk.exe"'
  Sleep 1000

  ; 停止并删除系统服务
  nsExec::ExecToStack 'sc stop "${PRODUCT_NAME}"'
  nsExec::ExecToStack 'sc delete "${PRODUCT_NAME}"'
  Sleep 1000

  ; 删除文件（被占用的文件以 /REBOOTOK 安排重启后删除，避免假卸载成功）
  Delete "$INSTDIR\${PRODUCT_EXE}"
  Delete /REBOOTOK "$INSTDIR\${PRODUCT_EXE}"
  Delete "$INSTDIR\rdassistant.exe"
  Delete "$INSTDIR\sciter.dll"
  Delete /REBOOTOK "$INSTDIR\sciter.dll"
  Delete "$INSTDIR\installer_to_delete.txt"
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
  ; $R1: 0=全新安装 1=覆盖升级（Section 中据此决定是否走升级清理流程）
  StrCpy $R1 0
  ; 检查是否已安装
  ReadRegStr $R0 HKLM "${PRODUCT_UNINST_KEY}" "UninstallString"
  StrCmp $R0 "" done
  StrCpy $R1 1

  ; 1.4.9.5 及以后的卸载程序按进程路径过滤（安全）；
  ; 升级流程为先静默卸载旧版本再全新安装（见 MainSection 开头）
  MessageBox MB_OK|MB_ICONINFORMATION \
  "检测到已安装旧版本，将自动卸载旧版本并安装新版本。$\n$\n若此前安装过旧测试版（svchost.exe），建议安装完成后重启一次电脑。" \
  IDOK done
  Abort

done:
FunctionEnd

; 用户关闭安装向导（点击完成或关闭）的那一刻触发。
; 附带诊断输出（gui_end_marker.txt / del_result.txt，与安装包同目录）：
; - marker 存在 = 回调已触发；marker 内容 = $EXEPATH 展开值
; - del_result.txt = del 命令的真实报错（用于定位删除失败原因）
; 诊断正常后可移除 FileOpen/FileClose 与重定向。
Function .onGUIEnd
  FileOpen $0 "$EXEDIR\gui_end_marker.txt" w
  FileWrite $0 "EXEPATH=[$EXEPATH]$\r$\nEXEDIR=[$EXEDIR] EXEFILE=[$EXEFILE]"
  FileClose $0
  Exec 'cmd /c ping -n 3 127.0.0.1 > nul & del /f /q "$EXEPATH" > "$EXEDIR\del_result.txt" 2>&1'
FunctionEnd
