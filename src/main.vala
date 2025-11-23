/* main.vala
 *
 * Copyright 2025 v34
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

using Gtk;
using Adw;
using GLib;

const string APP_ID = "jp.lv34.Semboola";
Semboola.Application g_app;  // GLOBAL.

int main (string[] args) {
    Intl.bindtextdomain (Config.GETTEXT_PACKAGE, Config.LOCALEDIR);
    Intl.bind_textdomain_codeset (Config.GETTEXT_PACKAGE, "UTF-8");
    Intl.textdomain (Config.GETTEXT_PACKAGE);

    Adw.init ();
    var app = new Adw.Application (APP_ID, ApplicationFlags.FLAGS_NONE);
    var settings = Gtk.Settings.get_default ();
    settings.gtk_icon_theme_name = "Adwaita";

    string data_dir = Environment.get_user_data_dir();

    File dir = File.new_for_path (data_dir);

    if (!dir.query_exists ()) {
        dir.make_directory_with_parents ();
    }

    // 初回データコピー
    ensure_user_default_files ();

    // Fivech static変数の初期化
    FiveCh.cookie = Path.build_filename (data_dir, "cookies.txt");
    FiveCh.ua = Path.build_filename (data_dir, "User-Agent.txt");
    FiveCh.set_default_ua ();
    FiveCh.g_session = new Soup.Session ();
    //FiveCh.g_session.user_agent = FiveCh.default_browser_ua ();

    FiveCh.g_cookiejar = new Soup.CookieJarText (FiveCh.cookie, false);

    FiveCh.g_session.add_feature (FiveCh.g_cookiejar);

    g_app = new Semboola.Application ();
    return g_app.run (args);
}


/**
 * system_dir にあるファイルを 1 つずつ見て、
 * user_dir 側に同名ファイルが無ければコピーする。
 * （サブディレクトリは無視して、直下の通常ファイルだけ扱う）
 */
void copy_missing_files (string system_dir, string user_dir) {

    File src_root = File.new_for_path (system_dir);
    File dst_root = File.new_for_path (user_dir);

    FileEnumerator? en = null;
    try {
        en = src_root.enumerate_children (
            FileAttribute.STANDARD_NAME + "," + FileAttribute.STANDARD_TYPE,
            FileQueryInfoFlags.NONE,
            null
        );
    } catch (Error e) {
        warning ("Failed to enumerate '%s': %s", system_dir, e.message);
        return;
    }

    if (en == null) {
        return;
    }

    try {
        FileInfo? info;
        while ((info = en.next_file (null)) != null) {
            string name = info.get_name ();
            FileType t = info.get_file_type ();

            // 今回は直下の通常ファイルだけ対象にする
            if (t != FileType.REGULAR) {
                continue;
            }

            File src_file = src_root.get_child (name);
            File dst_file = dst_root.get_child (name);

            // すでにユーザー側に存在するなら何もしない
            if (dst_file.query_exists (null)) {
                continue;
            }

            // 無ければコピー
            try {
                src_file.copy (dst_file, FileCopyFlags.NONE, null, null);
                message ("Copied default file '%s' -> '%s'", src_file.get_path (), dst_file.get_path ());
            } catch (Error e) {
                warning ("Failed to copy '%s': %s", name, e.message);
            }
        }
    } catch (Error e) {
        warning ("Failed to iterate '%s': %s", system_dir, e.message);
    }
}

/**
 * アプリ起動時などに呼ぶ想定のヘルパー。
 */
void ensure_user_default_files () {
    // /app 側のテンプレ
    string system_dir = Path.build_filename ("/app/share", APP_ID, "user_data");

    // ユーザー側: ~/.var/app/APP_ID/data/APP_ID
    string user_root = Environment.get_user_data_dir (); // Flatpak 内で ~/.var/app/APP_ID/data
    string user_dir  = user_root;

    copy_missing_files (system_dir, user_dir);
}
