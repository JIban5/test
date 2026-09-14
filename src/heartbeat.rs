// 客户端心跳：每 60 秒向管理后台上报设备在线状态
// 管理后台据此判定设备是否真实在线（客户端退出后停止心跳 → 面板标记离线）
use hbb_common::config::Config;
use std::thread;
use std::time::Duration;

const HEARTBEAT_INTERVAL_SECS: u64 = 60;

pub fn start() {
    thread::spawn(|| loop {
        if let Err(e) = send_heartbeat() {
            // 生产构建不落盘日志，仅调试模式可见
            hbb_common::log::info!("Heartbeat: {}", e);
        }
        thread::sleep(Duration::from_secs(HEARTBEAT_INTERVAL_SECS));
    });
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
    // 只上报 device_id，不覆盖管理后台/同步脚本设置的设备名称
    let body = serde_json::json!({ "device_id": Config::get_id() });
    let client = crate::hbbs_http::create_http_client_with_url(&url);
    let resp = client
        .post(&url)
        .json(&body)
        .timeout(Duration::from_secs(10))
        .send()?;
    if !resp.status().is_success() {
        hbb_common::bail!("HTTP {}", resp.status());
    }
    Ok(())
}
