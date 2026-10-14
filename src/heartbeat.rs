// 客户端心跳：每 60 秒向管理后台上报设备在线状态
// 管理后台据此判定设备是否真实在线（客户端退出后停止心跳 → 面板标记离线）
// 同时接收设备授权状态：管理后台可将设备设置到期时间（expires_at），
// 到期设备心跳响应 authorized=false → 停止被控服务（stop-service=Y），
// RendezvousMediator 检测到该选项后停止向服务器注册并断开现有连接，
// 设备将无法被远程连接；管理员改回永久/延长后自动恢复。
use hbb_common::config::{Config, LocalConfig};
use std::sync::atomic::{AtomicBool, Ordering};
use std::thread;
use std::time::Duration;

/// 学员编号导入（下载页定制流程）：下载页按编号命名安装包
/// （888-<编号>-setup.exe），安装器安装时把编号写入注册表；
/// 客户端启动时导入到配置（全局+本地双写）并删除注册表值——
/// 一次性导入：此后用户在客户端内的手动修改不会被安装覆盖。
#[cfg(windows)]
pub fn import_student_no_from_registry() {
    use winreg::enums::*;
    use winreg::RegKey;
    // 配置里已有编号（用户手动输入，或此前已导入）则不再导入——
    // HKLM\Software\888\StudentNo 由管理员安装器写入，普通用户删不掉，
    // 若无条件导入会每次启动覆盖用户的手动修改
    let existing = Config::get_option("student-no");
    if !existing.is_empty() {
        return;
    }
    let hklm = RegKey::predef(HKEY_LOCAL_MACHINE);
    let Ok(key) = hklm.open_subkey(r"Software\888") else {
        return;
    };
    let Ok(no) = key.get_value::<String, _>("StudentNo") else {
        return;
    };
    let no = no.trim().to_string();
    if no.is_empty() {
        return;
    }
    // 双写全局+本地配置（与心跳读取配对），并立即触发一次上报
    Config::set_option("student-no".into(), no.clone());
    LocalConfig::set_option("student-no".into(), no.clone());
    hbb_common::log::info!("已从安装包导入学员编号: {}", no);
    // 删除注册表值（一次性导入）；普通用户无写权限删不掉也无妨——
    // 上面的"配置已有编号则跳过"保证不会被重复导入覆盖
    if let Ok(wkey) = hklm.open_subkey_with_flags(r"Software\888", KEY_WRITE) {
        let _ = wkey.delete_value("StudentNo");
    }
    thread::spawn(|| {
        thread::sleep(Duration::from_secs(3));
        let _ = send_heartbeat();
    });
}

const HEARTBEAT_INTERVAL_SECS: u64 = 60;

// 保存学员编号等场景需要立即上报（不等下一轮 60 秒心跳）
static TRIGGER_NOW: AtomicBool = AtomicBool::new(false);

pub fn start() {
    thread::spawn(|| loop {
        if let Err(e) = send_heartbeat() {
            // 生产构建不落盘日志，仅调试模式可见
            hbb_common::log::info!("Heartbeat: {}", e);
        }
        // 正常等 60 秒；期间被 trigger_now() 置位则立即进入下一轮上报
        for _ in 0..HEARTBEAT_INTERVAL_SECS {
            if TRIGGER_NOW.swap(false, Ordering::SeqCst) {
                break;
            }
            thread::sleep(Duration::from_secs(1));
        }
    });
}

/// 主界面保存学员编号后调用：立即触发一次上报，后台马上可见
pub fn trigger_now() {
    TRIGGER_NOW.store(true, Ordering::SeqCst);
}

fn send_heartbeat() -> hbb_common::ResultType<()> {
    let api = crate::common::get_api_server(
        Config::get_option("api-server"),
        Config::get_option("custom-rendezvous-server")
    );
    if api.is_empty() {
        return Ok(());
    }
    let url = format!("{}/api/devices/register", api.trim_end_matches('/'));
    // 只上报 device_id + 学员编号（用户在客户端自行输入），
    // 不覆盖管理后台/同步脚本设置的设备名称。
    // 学员编号双读：全局 option 与本地配置（LocalConfig）两套存储都试
    // （写入方为主界面进程双写：set_option + LocalConfig::set_option）
    let student_no = {
        let global = Config::get_option("student-no");
        if global.is_empty() {
            LocalConfig::get_option("student-no")
        } else {
            global
        }
    };
    let body = serde_json::json!({
        "device_id": Config::get_id(),
        "student_no": student_no,
        // 是否注册到 hbbs（RendezvousMediator 收到注册响应）：
        // 管理后台据此判定"可正常远程"——心跳在线但未注册 hbbs 的设备不可被连接
        "registered": crate::rendezvous_mediator::REGISTER_PEER_OK
            .load(std::sync::atomic::Ordering::SeqCst),
    });
    let client = crate::hbbs_http::create_http_client_with_url(&url);
    let resp = client
        .post(&url)
        .json(&body)
        .timeout(Duration::from_secs(10))
        .send()?;
    if !resp.status().is_success() {
        hbb_common::bail!("HTTP {}", resp.status());
    }
    // 设备授权检查：服务器未返回该字段时保持现状（兼容旧版管理后台）
    let authorized = resp
        .json::<serde_json::Value>()
        .ok()
        .and_then(|v| v.get("authorized").and_then(|a| a.as_bool()))
        .unwrap_or(true);
    apply_device_authorization(authorized);
    Ok(())
}

/// 根据授权状态启停被控服务。
/// 被控服务进程（--service）内生效：更新 stop-service 选项并重启 RendezvousMediator，
/// 到期 → 停止注册 + 断开现有连接（无法被远程连接），恢复授权 → 重新注册。
/// 其他进程（主窗口/托盘）中调用安全：仅更新本地配置（落盘），标志位操作无副作用，
/// 被控服务进程自身的心跳线程也会做同样处理。
fn apply_device_authorization(authorized: bool) {
    let stopped = Config::get_option("stop-service") == "Y";
    if !authorized && !stopped {
        hbb_common::log::info!("Device expired, stopping controlled service");
        Config::set_option("stop-service".into(), "Y".into());
        crate::rendezvous_mediator::RendezvousMediator::restart();
    } else if authorized && stopped {
        hbb_common::log::info!("Device re-authorized, restarting controlled service");
        Config::set_option("stop-service".into(), "".into());
        crate::rendezvous_mediator::RendezvousMediator::restart();
    }
}
