// Inline sciter UI resources into the binary.
// When the `inline` feature is enabled, pages are loaded via `frame.load_html()`
// instead of `frame.load_file()`, so external css/tis references must be
// embedded into the HTML text itself.

use std::collections::HashMap;

fn resources() -> HashMap<&'static str, &'static str> {
    HashMap::from([
        // css
        ("common.css", include_str!("common.css")),
        ("cm.css", include_str!("cm.css")),
        ("index.css", include_str!("index.css")),
        ("remote.css", include_str!("remote.css")),
        ("file_transfer.css", include_str!("file_transfer.css")),
        ("header.css", include_str!("header.css")),
        // tiscript
        ("common.tis", include_str!("common.tis")),
        ("cm.tis", include_str!("cm.tis")),
        ("msgbox.tis", include_str!("msgbox.tis")),
        ("ab.tis", include_str!("ab.tis")),
        ("index.tis", include_str!("index.tis")),
        ("install.tis", include_str!("install.tis")),
        ("remote.tis", include_str!("remote.tis")),
        ("file_transfer.tis", include_str!("file_transfer.tis")),
        ("port_forward.tis", include_str!("port_forward.tis")),
        ("grid.tis", include_str!("grid.tis")),
        ("header.tis", include_str!("header.tis")),
        ("printer.tis", include_str!("printer.tis")),
    ])
}

fn inline_page(html: &str) -> String {
    let resources = resources();
    let mut result = html.to_owned();
    // Multiple passes: a tis file may `include` another tis file.
    for _ in 0..3 {
        let mut changed = false;
        for (name, content) in resources.iter() {
            let import_pattern = format!("@import url({});", name);
            if result.contains(&import_pattern) {
                result = result.replace(&import_pattern, content);
                changed = true;
            }
            let include_pattern = format!("include \"{}\";", name);
            if result.contains(&include_pattern) {
                result = result.replace(&include_pattern, content);
                changed = true;
            }
        }
        if !changed {
            break;
        }
    }
    result
}

pub fn get_index() -> String {
    inline_page(include_str!("index.html"))
}

pub fn get_cm() -> String {
    inline_page(include_str!("cm.html"))
}

pub fn get_install() -> String {
    inline_page(include_str!("install.html"))
}

pub fn get_remote() -> String {
    inline_page(include_str!("remote.html"))
}

pub fn get_chatbox() -> String {
    inline_page(include_str!("chatbox.html"))
}
