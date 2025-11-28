/* local_rules.vala
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
using GLib;
using Adw;
using FiveCh;

[GtkTemplate (ui = "/jp/lv34/Semboola/local_rules.ui")]
public class local_rules : Adw.NavigationPage {

    Semboola.Window win;

    private string url;

    [GtkChild]
    private unowned WebKit.WebView webview;

    public local_rules (string url) {
        // Object(
        //     title:name
        // );
        this.url = url;

        // NavigationView に push されて画面に出る直前〜直後に呼ばれる
        this.shown.connect (() => {
            win = this.get_root() as Semboola.Window;
        });

        WebKit.NetworkSession session = webview.network_session;
        WebKit.CookieManager cookie_manager = session.get_cookie_manager ();

        cookie_manager.set_persistent_storage (
            FiveCh.cookie,
            WebKit.CookiePersistentStorage.TEXT
        );

        load.begin ();
    }

    static construct {
    }

    private async void load () {

        var client = new FiveCh.Client ();
        string text;
        try {
            text = yield client.fetch_head_async (new FiveCh.Board(Board.guess_site_base_from_url (url), Board.guess_board_key_from_url (url)));
        } catch (Error e) {
            win.show_error_toast (e.message);
            return;
        }
        text = "<html>"+text+"</html>";
        // テンプレート(=webview)が生えた後で呼ばれる
        webview.load_html (text, url) ;
    }

}
